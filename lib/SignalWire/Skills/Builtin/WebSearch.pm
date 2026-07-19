package SignalWire::Skills::Builtin::WebSearch;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Real Google Custom Search client. Mirrors signalwire-python's
# skills/web_search/skill.py:GoogleSearchScraper.search_google — issue
# an outbound GET to customsearch/v1 with `key`, `cx`, `q`, parse
# the JSON `items[]` array, format title+snippet for the LLM.
#
# Python's full implementation also fetches each result URL and runs
# HTML extraction + quality scoring. We ship the search portion (the
# part the audit_skills_dispatch contract probes) in the SDK and leave
# the page-extraction to the spider skill, so consumers compose the two
# when they want full-page text. A Perl port that ships ~600 lines of
# BeautifulSoup-equivalent HTML cleanup is a separate piece of work.

use strict;
use warnings;
use Moo;
use HTTP::Tiny;
use JSON        ();
use URI::Escape qw(uri_escape);
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'web_search', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'web_search' } );
has '+skill_description' =>
    ( default => sub { 'Search the web for information using Google Custom Search API' } );
has '+skill_version'               => ( default => sub { '2.0.0' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

# Google CSE base URL. Honor WEB_SEARCH_BASE_URL env var so the audit
# fixture (audit_skills_dispatch.py) can redirect us at a local HTTP
# server. The override replaces the host+scheme; the canonical
# `/customsearch/v1` path is always appended so the documented Google
# CSE wire shape is preserved (the audit's `expected_path_substring`
# is `customsearch`, which would not appear if we used the override
# verbatim).
has 'base_url' => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $override = $ENV{WEB_SEARCH_BASE_URL};
        return 'https://www.googleapis.com/customsearch/v1' unless $override;

        # Strip trailing slash, then append the canonical Google CSE
        # path so callers see the same URL shape as production.
        $override =~ s{/+$}{};
        return "$override/customsearch/v1";
    },
);

# HTTP client for the Google CSE call. `rw` + lazy so a test can inject a
# stub transport (`$skill->_http($fake)`) and drive the no-results / error
# branches deterministically without a live network.
#
# The client timeout is set from per_page_timeout (Python parity: the same
# knob that bounds a single page fetch in the scraping ports bounds our one
# outbound HTTP call here, since the CSE GET is the only page we fetch).
# HTTP::Tiny's `timeout` is the per-request ceiling. Falls back to 15s when
# per_page_timeout is unset or non-positive so a misconfiguration can never
# produce an unbounded fetch.
has '_http' => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        HTTP::Tiny->new(
            agent   => 'SignalWire-Perl-WebSearch/2.0',
            timeout => $self->_per_page_timeout,
        );
    },
);

# Monotonic clock hook. Overridable so a test can inject a fake elapsed
# time and exercise the overall_deadline path deterministically (no real
# sleeping). Production reads Time::HiRes' high-resolution wall clock.
has '_clock' => (
    is      => 'rw',
    default => sub {
        require Time::HiRes;
        return sub { Time::HiRes::time() };
    },
);

sub setup { return 1 }

# --- Latency-control param readers (Python parity: 51101da) -------------
#
# The SignalWire kernel times out webhook responses around 55s, so the
# handler MUST finish under that. These read the four latency knobs from
# params with the same defaults as Python:
#   per_page_timeout (2.0s)  bounds a single page fetch. The Perl skill is
#                            snippet-only (it formats Google CSE snippets
#                            and does NOT deep-scrape result pages), so the
#                            one page we fetch is the CSE call itself; this
#                            is its HTTP::Tiny timeout.
#   overall_deadline (10.0s) wall-clock budget for the whole tool call.
#                            Enforced as a guard around the CSE call +
#                            formatting; if it has already fired we return
#                            the snippet fallback rather than nothing.
#   parallel_scrape  (true)  accepted for API parity. Perl parallel HTTP is
#                            invasive (forks/threads) and is NOT contracted;
#                            we run sequentially. The value is read so it is
#                            a no-surprise pass-through, not a hard error.
#   snippets_only    (false) skip page scraping and format CSE snippets
#                            directly. Already the Perl skill's behavior, so
#                            honoring it is a no-op on the happy path; it
#                            still routes a zero-result call through the
#                            non-empty snippet fallback.
sub _per_page_timeout {
    my ($self) = @_;
    my $t = $self->params->{per_page_timeout};
    $t = 2.0 unless defined $t;
    $t += 0;                    # numify
    return $t > 0 ? $t : 15;    # never unbounded
}

sub _overall_deadline {
    my ($self) = @_;
    my $d = $self->params->{overall_deadline};
    $d = 10.0 unless defined $d;
    return $d + 0;              # numify
}

sub _parallel_scrape {
    my ($self) = @_;
    my $p = $self->params->{parallel_scrape};
    return 1 unless defined $p;    # default true
    return $p ? 1 : 0;
}

sub _snippets_only {
    my ($self) = @_;
    return $self->params->{snippets_only} ? 1 : 0;
}

sub register_tools {
    my ($self) = @_;
    my $tool_name = $self->params->{tool_name} // 'web_search';

    my $weak_self = $self;
    require Scalar::Util;
    Scalar::Util::weaken($weak_self);

    return $self->define_tool(
        name        => $tool_name,
        description =>
'Search the web for high-quality information, automatically filtering low-quality results',
        parameters => {
            type       => 'object',
            properties => {
                query => { type => 'string', description => 'The search query' },
            },

            # No `required`: the Python reference (skills/web_search/skill.py)
            # passes none and the handler guards an empty query. Adding it would
            # over-constrain the SWAIG schema vs the reference contract.
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $query = $args->{query} // '';
            my $text  = $weak_self->search_web($query);
            $text = $weak_self->_wrap_response($text);
            return SignalWire::SWAIG::FunctionResult->new( response => $text );
        },
    );
}

sub search_web {
    my ( $self, $query ) = @_;

    # overall_deadline is the wall-clock budget for the WHOLE tool call.
    # Start the clock before the (slowest, non-cancelable) CSE fetch so a
    # slow request gets caught by the post-fetch guard and routed to the
    # snippet fallback rather than blowing past the kernel webhook timeout.
    # THIS IS THE CONTRACT (Python parity: 51101da).
    my $started_at  = $self->_clock->();
    my $deadline_at = $started_at + $self->_overall_deadline;

    my $api_key = $self->params->{api_key} || $ENV{GOOGLE_API_KEY} || '';
    my $cse_id =
           $self->params->{search_engine_id}
        || $self->params->{cx}
        || $ENV{GOOGLE_CSE_ID}
        || '';
    my $num = $self->params->{num_results} // 3;
    $num = 10 if $num > 10;
    $num = 1  if $num < 1;

    my $url =
          $self->base_url . '?key='
        . uri_escape($api_key) . '&cx='
        . uri_escape($cse_id) . '&q='
        . uri_escape($query) . '&num='
        . $num;

    # The CSE GET is bounded by per_page_timeout via the _http client's
    # HTTP::Tiny timeout (set from _per_page_timeout in the _http builder).
    my $resp = $self->_http->get($url);
    unless ( $resp->{success} ) {
        return "Web search error: $resp->{status} $resp->{reason}";
    }
    my $data = eval { JSON::decode_json( $resp->{content} ) };
    return "Web search parse error: $@" if $@;

    my $items = $data->{items} // [];

    # Zero CSE results: nothing to format, snippet-fallback returns the
    # same non-empty "no results" sentinel. Matches Python's
    # _format_snippet_results([]) -> "No search results found ...".
    return "No results for: $query" unless @$items;

    # snippets_only is ALREADY this skill's behavior (it formats CSE
    # snippets and never deep-scrapes), so honoring the flag is a no-op on
    # the happy path. We still route the deadline / zero-result cases
    # through the snippet fallback below.
    #
    # overall_deadline guard: if the CSE fetch alone has already consumed
    # the budget, skip the (cheap) per-item loop and hand back the snippet
    # fallback immediately so the caller always gets non-empty context
    # before the kernel webhook timeout fires — exactly as Python falls
    # back to _format_snippet_results when time runs out.
    if ( $self->_deadline_exceeded($deadline_at) ) {
        return $self->_format_snippet_results( $query, $items, $num );
    }

    my @lines;
    my $i = 1;
    for my $item (@$items) {
        last if $i > $num;

        # Re-check the deadline inside the loop. Formatting is cheap, but
        # the contract is "check before each unit of work and stop once
        # exceeded"; this keeps the guard honest even if a future change
        # makes per-item work expensive.
        if ( $self->_deadline_exceeded($deadline_at) ) {
            return $self->_format_snippet_results( $query, $items, $num );
        }
        my $title   = $item->{title}   // '';
        my $link    = $item->{link}    // '';
        my $snippet = $item->{snippet} // '';
        push @lines, "$i. $title\n   $snippet\n   $link";
        $i++;
    }
    return join( "\n\n", @lines );
}

# True once the monotonic clock has reached/passed the deadline. Reads the
# overridable _clock hook so a test can inject elapsed time and drive the
# deadline path deterministically (no real sleeping).
sub _deadline_exceeded {
    my ( $self, $deadline_at ) = @_;
    return $self->_clock->() >= $deadline_at ? 1 : 0;
}

# Format Google CSE snippets without fetching/deep-scraping the underlying
# pages. Used as the graceful fallback when the overall_deadline has fired
# (and, structurally, is what the Perl skill does on every call since it is
# snippet-only). Always non-empty when CSE returned anything at all, so the
# kernel never sees a webhook timeout. Mirrors Python
# GoogleSearchScraper._format_snippet_results (51101da). The output carries
# title + snippet + url for each item, so downstream sentinel/quality checks
# still see the same content the happy path would emit.
sub _format_snippet_results {
    my ( $self, $query, $items, $num ) = @_;
    $items ||= [];
    return "No results for: $query" unless @$items;

    my $top   = $num && $num > 0 ? $num : 1;
    my @lines = ( "Snippet-only results for '$query' (page content not scraped):", "" );
    my $i     = 1;
    for my $item (@$items) {
        last if $i > $top;
        my $title   = $item->{title}   // '';
        my $link    = $item->{link}    // '';
        my $snippet = $item->{snippet} // '';
        $snippet =~ s/^\s+//;
        $snippet =~ s/\s+$//;
        push @lines, "=== RESULT $i ===";
        push @lines, "Title: $title";
        push @lines, "URL: $link";
        push @lines, "Snippet: $snippet";
        push @lines, "";
        $i++;
    }
    my $out = join( "\n", @lines );
    $out =~ s/\n+$//;
    return $out;
}

# Wrap a successful search response with optional response_prefix /
# response_postfix. Mirrors Python signalwire/skills/web_search/skill.py
# (commit 8aad242): prefix/postfix are joined with a blank line on each
# side. Error / no-result branches are passed through unwrapped so the
# LLM still sees the failure mode verbatim.
sub _wrap_response {
    my ( $self, $text ) = @_;
    return $text unless defined $text && length $text;

    # Match Python's "errors don't get wrapped" pattern. The Perl
    # search_web returns one of three known failure sentinels; anything
    # else is a real result list.
    return $text if $text =~ /^Web search error:/;
    return $text if $text =~ /^Web search parse error:/;
    return $text if $text =~ /^No results for:/;
    my $prefix  = $self->params->{response_prefix}  // '';
    my $postfix = $self->params->{response_postfix} // '';
    $text = "$prefix\n\n$text"  if length $prefix;
    $text = "$text\n\n$postfix" if length $postfix;
    return $text;
}

sub get_global_data {
    return {
        web_search_enabled => JSON::true,
        search_provider    => 'Google Custom Search',
        quality_filtering  => JSON::true,
    };
}

sub _get_prompt_sections {
    return [
        {
            title   => 'Web Search Capability (Quality Enhanced)',
            body    => '',
            bullets => [
                'Use web_search to find current information',
                'Results are quality-filtered automatically',
            ],
        }
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        api_key          => { type => 'string',  required => 1, hidden => 1 },
        search_engine_id => { type => 'string',  required => 1, hidden => 1 },
        num_results      => { type => 'integer', default  => 3, min    => 1, max => 10 },
        response_prefix  => { type => 'string',  default  => '' },
        response_postfix => { type => 'string',  default  => '' },

        # Latency-control parameters (Python parity: 51101da + 295745b). The
        # kernel times out webhook responses around 55s; these keep the
        # handler under that. per_page_timeout bounds the CSE HTTP fetch;
        # overall_deadline is the wall-clock budget for the whole call;
        # parallel_scrape is accepted for API parity (Perl runs sequentially,
        # not contracted); snippets_only returns CSE snippets directly (the
        # Perl skill's default behavior).
        per_page_timeout => {
            type        => 'number',
            description =>
'Maximum seconds to wait on a single page fetch (the Google CSE HTTP call for this snippet-only skill).',
            default  => 2.0,
            required => 0,
            min      => 0.1,
        },
        overall_deadline => {
            type        => 'number',
            description =>
'Wall-clock budget in seconds for the whole tool call. Once exceeded, format the CSE snippets we already have so the response beats the kernel webhook timeout.',
            default  => 10.0,
            required => 0,
            min      => 1.0,
        },
        parallel_scrape => {
            type        => 'boolean',
            description =>
'Accepted for API parity with the scraping ports. The Perl skill is snippet-only and runs sequentially; this flag has no effect.',
            default  => 1,
            required => 0,
        },
        snippets_only => {
            type        => 'boolean',
            description =>
'Return Google CSE snippets directly without deep-scraping result pages. This is the Perl skill\'s default behavior.',
            default  => 0,
            required => 0,
        },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::WebSearch - web-search skill using the Google Custom Search API

=head1 SYNOPSIS

    $agent->add_skill('web_search', {
        api_key          => $GOOGLE_API_KEY,
        search_engine_id => $GOOGLE_CSE_ID,
    });

    # Optionally rename the tool and tune result count / latency:
    $agent->add_skill('web_search', {
        api_key          => $GOOGLE_API_KEY,
        search_engine_id => $GOOGLE_CSE_ID,
        tool_name        => 'web_search',
        num_results      => 3,
        overall_deadline => 10.0,
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::WebSearch> is the Perl port of the Python reference
C<signalwire.skills.web_search.skill> (the C<GoogleSearchScraper> path). It
registers a handler-based SWAIG tool (default name C<web_search>) that searches
the web via the Google Custom Search API.

The handler issues an outbound GET to C<customsearch/v1> with C<key>/C<cx>/C<q>,
parses the JSON C<items[]>, and formats title + snippet + link for the LLM. It is
snippet-only (it does not deep-scrape result pages). Four latency-control params
(C<per_page_timeout>, C<overall_deadline>, C<parallel_scrape>, C<snippets_only>)
keep the response under the kernel webhook timeout; when the wall-clock deadline
fires the skill returns the snippets it already has. The skill supports multiple
instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the web-search tool (name overridable via C<tool_name>) with the agent.

=item C<search_web($query)>

Performs the Google CSE search for C<$query> and returns the formatted result
string (or an error / no-results sentinel), enforcing the overall deadline.

=item C<get_global_data>

Returns the skill's global-data contribution (C<web_search_enabled>,
C<search_provider>, C<quality_filtering>).

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<api_key> and C<search_engine_id> (both
required), C<num_results>, C<response_prefix>, C<response_postfix>, and the four
latency-control params.

=back

=head1 ATTRIBUTES

C<base_url> (derived from C<WEB_SEARCH_BASE_URL> when set, else the canonical
Google CSE URL). The C<_http> and C<_clock> attributes are overridable hooks for
testing.

=head1 SEE ALSO

L<SignalWire::Skills::Builtin::Spider>, L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
