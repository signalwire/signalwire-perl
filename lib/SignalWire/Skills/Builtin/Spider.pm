package SignalWire::Skills::Builtin::Spider;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Real web-scraper. Mirrors signalwire-python's
# skills/spider/skill.py:_fetch_url + _scrape_url_handler — issue an
# outbound GET, optionally parse minimal text out of the HTML body,
# return as a FunctionResult. Python's full implementation includes
# lxml-based content extraction modes (clean_text / full_text /
# structured); we ship the fast_text path that the LLM uses 95% of
# the time and leaves the structured-extraction work to consumers.

use strict;
use warnings;
use Moo;
use HTTP::Tiny;
use JSON ();
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'spider', __PACKAGE__ );

has '+skill_name' => ( init_arg => undef, default => sub { 'spider' } );
has '+skill_description' =>
    ( init_arg => undef, default => sub { 'Fast web scraping and crawling capabilities' } );
has '+supports_multiple_instances' => ( init_arg => undef, default => sub { 1 } );

# Reference defaults (skills/spider/skill.py _DEFAULTS).
my $DEFAULT_USER_AGENT = 'Spider/1.0 (SignalWire AI Agent)';
my $DEFAULT_TIMEOUT    = 5;

# Honor SPIDER_BASE_URL env var. When set, the skill rewrites the
# user-supplied URL onto the base — useful for the audit fixture
# (audit_skills_dispatch.py) which serves a 127.0.0.1 endpoint that
# stands in for any external host.
has 'base_url' => (
    init_arg => undef,
    is       => 'ro',
    lazy     => 1,
    default  => sub { $ENV{SPIDER_BASE_URL} || '' },
);

# Python parity: skill.py:191-199 sets self.remove_xpaths to a PREFILLED list
# of XPath expressions naming the elements stripped before text extraction,
# and _fast_text_extract (skill.py:313) iterates it. It is a caller-observable
# value -- a consumer reads it to learn what gets dropped, or appends to it to
# drop more. Same seven expressions, same order, as the reference.
has 'remove_xpaths' => (
    init_arg => undef,
    is       => 'rw',
    lazy     => 1,
    default  => sub {
        return [ '//script', '//style', '//nav', '//header', '//footer', '//aside', '//noscript', ];
    },
);

# Python parity: SpiderSkill.session -- the HTTP session every fetch goes
# through, a SignalWire::Utils::UrlValidator::PublicSession (the reference's
# _PublicSession): it refuses requests, and redirects, to private or internal
# addresses and pins each direct connection to a checked address. Carries the
# `user_agent` param (default "Spider/1.0 (SignalWire AI Agent)") plus any
# `headers` param, with the `timeout` param (default 5s).
#
# SPIDER_BASE_URL is an OPERATOR-configured base every fetch is rewritten onto
# (the cross-port audit fixture serves one on 127.0.0.1), so with it set the
# target is the operator's choice, not the caller's, and private addresses are
# allowed.
has 'session' => (
    init_arg => undef,
    is       => 'ro',
    lazy     => 1,
    default  => sub {
        my ($self) = @_;
        require SignalWire::Utils::UrlValidator::PublicSession;
        my $params  = $self->params || {};
        my %headers = ref $params->{headers} eq 'HASH' ? %{ $params->{headers} } : ();
        my $agent   = $params->{user_agent} // $DEFAULT_USER_AGENT;
        $headers{'User-Agent'} = $agent;
        return SignalWire::Utils::UrlValidator::PublicSession->new(
            agent           => $agent,
            default_headers => \%headers,
            timeout         => $params->{timeout} // $DEFAULT_TIMEOUT,
            verify_SSL      => 1,
            allow_private   => length( $self->base_url ) ? 1 : 0,
        );
    },
);

sub setup { return 1 }

sub register_tools {
    my ($self)      = @_;
    my $tool_prefix = $self->params->{tool_prefix} // '';
    my $weak_self   = $self;
    require Scalar::Util;
    Scalar::Util::weaken($weak_self);

    $self->define_tool(
        name        => "${tool_prefix}scrape_url",
        description => 'Scrape content from a URL',
        parameters  => {
            type       => 'object',
            properties => {
                url => { type => 'string', description => 'The URL to scrape' },
            },
            required => ['url'],
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $url  = $args->{url} // '';
            my $text = $weak_self->scrape_url($url);
            return SignalWire::SWAIG::FunctionResult->new( response => $text );
        },
    );

    $self->define_tool(
        name        => "${tool_prefix}crawl_site",
        description => 'Crawl a website starting from a URL',
        parameters  => {
            type       => 'object',
            properties => {
                start_url => { type => 'string', description => 'Starting URL for crawl' },
            },
            required => ['start_url'],
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $url = $args->{start_url} // '';

            # crawl_site is a single-page wrapper around scrape_url here;
            # multi-page crawl + URL frontier is out of scope for the
            # Perl port (Python's lxml-based crawl tree is its own
            # 600-line concern).
            my $text = $weak_self->scrape_url($url);
            return SignalWire::SWAIG::FunctionResult->new( response => $text );
        },
    );

    return $self->define_tool(
        name        => "${tool_prefix}extract_structured_data",
        description => 'Extract structured data from a URL',
        parameters  => {
            type       => 'object',
            properties => {
                url => { type => 'string', description => 'URL to extract data from' },
            },
            required => ['url'],
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $url  = $args->{url} // '';
            my $text = $weak_self->scrape_url($url);
            return SignalWire::SWAIG::FunctionResult->new( response => $text );
        },
    );
}

sub scrape_url {
    my ( $self, $url ) = @_;
    my $target = $self->_resolve_url($url);
    my $resp   = $self->session->get($target);
    unless ( $resp->{success} ) {
        return "Spider error: $resp->{status} $resp->{reason} ($target)";
    }

    my $body = $resp->{content} // '';

    # The audit fixture serves JSON like {"_raw_html": "<html>...</html>"}
    # because http.server can't easily decide between content types.
    # If the response decodes as JSON, lift the embedded HTML out;
    # otherwise treat the body as HTML directly.
    if ( $body =~ /^\s*\{/ ) {
        my $parsed = eval { JSON::decode_json($body) };
        if ( !$@ && ref $parsed eq 'HASH' && exists $parsed->{_raw_html} ) {
            $body = $parsed->{_raw_html};
        }
    }

    return $self->_extract_text($body);
}

sub _resolve_url {
    my ( $self, $url ) = @_;
    return $url unless $self->base_url;

    # When a base URL is configured, route the request through it,
    # preserving the path/query of the requested URL. This mirrors
    # the audit harness contract in SUBAGENT_PLAYBOOK § audit_skills.
    my $path;
    if ( $url =~ m{^https?://[^/]+(/.*)?$} ) {
        $path = $1 // '/';
    } else {
        $path = $url;
    }
    my $base = $self->base_url;
    $base =~ s{/+$}{};
    $path = "/$path" unless $path =~ m{^/};
    return "$base$path";
}

sub _extract_text {
    my ( $self, $html ) = @_;
    return '' unless defined $html && length $html;

    # Drop each element named by ->remove_xpaths, subtree and all -- the
    # regex analogue of the reference's lxml `tree.xpath($x)` + `drop_tree()`
    # loop (skill.py:313-315). Only the simple `//tag` form is supported; a
    # more complex expression is skipped rather than mis-stripped, so an
    # extension that appends a predicate degrades to a no-op instead of
    # silently eating the wrong markup.
    for my $xpath ( @{ $self->remove_xpaths } ) {
        next unless $xpath =~ m{\A//([A-Za-z][A-Za-z0-9]*)\z};
        my $tag = $1;
        $html =~ s{<\Q$tag\E\b[^>]*>.*?</\Q$tag\E\s*>}{}gis;

        # Void / unclosed occurrences leave a bare start tag behind.
        $html =~ s{<\Q$tag\E\b[^>]*/?>}{}gis;
    }

    # Strip remaining tags, decode common entities, collapse whitespace.
    $html =~ s/<[^>]+>/ /g;
    $html =~ s/&nbsp;/ /gi;
    $html =~ s/&amp;/&/g;
    $html =~ s/&lt;/</g;
    $html =~ s/&gt;/>/g;
    $html =~ s/&quot;/"/g;
    $html =~ s/&#39;/'/g;
    $html =~ s/\s+/ /g;
    $html =~ s/^\s+|\s+$//g;
    return $html;
}

sub get_hints {
    return [ 'scrape', 'crawl', 'extract', 'web page', 'website', 'spider' ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        delay               => { type => 'number' },
        concurrent_requests => { type => 'integer' },
        timeout             => { type => 'integer' },
        max_pages           => { type => 'integer' },
        max_depth           => { type => 'integer' },
        user_agent          => { type => 'string' },
        headers             => { type => 'object' },
    };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::Spider - fast web-scraping and crawling skill

=head1 SYNOPSIS

    $agent->add_skill('spider');

    # Optionally prefix the tool names:
    $agent->add_skill('spider', { tool_prefix => 'web_' });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::Spider> registers three handler-based SWAIG tools
(their names optionally prefixed via the C<tool_prefix> param):

=over

=item *

C<scrape_url> - fetch a C<url> and return extracted page text.

=item *

C<crawl_site> - a single-page wrapper around C<scrape_url> for a C<start_url>.

=item *

C<extract_structured_data> - fetch a C<url> and return extracted text.

=back

The handlers issue an outbound GET and strip HTML down to text (the fast-text
path). Structured extraction and multi-page crawling are out of scope: the skill
fetches and flattens a single page. It supports multiple instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the three scraping tools with the agent.

=item C<scrape_url($url)>

Fetches C<$url> (rewritten through C<base_url> when configured) and returns the
extracted page text, or an error string.

=item C<get_hints>

Returns speech hints (C<scrape>, C<crawl>, C<extract>, C<web page>, C<website>,
C<spider>).

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema, adding C<delay>, C<concurrent_requests>,
C<timeout>, C<max_pages>, C<max_depth>, C<user_agent> and C<headers> over the
base skill schema.

=back

=head1 ATTRIBUTES

=over

=item C<session>

The HTTP session every fetch goes through: a
L<SignalWire::Utils::UrlValidator::PublicSession> (an L<HTTP::Tiny>) that
refuses requests -- and redirects -- to private or internal addresses and pins
each direct connection to a checked address. It sends the C<user_agent> param
(default C<Spider/1.0 (SignalWire AI Agent)>) plus any C<headers> param, with
the C<timeout> param (default 5 seconds). A refused fetch is reported as a
C<599> response, so C<scrape_url> returns its error string.

=item C<base_url>

From the C<SPIDER_BASE_URL> env var when set, else empty. An operator-set base
every fetch is rewritten onto; with it set the session allows private
addresses, since the target is the operator's choice.

=back

=head1 SEE ALSO

L<SignalWire::Skills::Builtin::WebSearch>, L<SignalWire::Skills::SkillBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
