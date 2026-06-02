#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

my $factory = SignalWire::Skills::SkillRegistry->get_factory('web_search');
ok(defined $factory, 'factory found');

subtest 'construction' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws');
    my $skill = $factory->new(agent => $agent, params => {});
    is($skill->skill_name, 'web_search', 'skill_name');
    is($skill->skill_version, '2.0.0', 'version 2.0.0');
    ok($skill->supports_multiple_instances, 'supports multi-instance');
};

subtest 'registers tool' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_reg');
    my $skill = $factory->new(agent => $agent, params => {});
    $skill->setup;
    $skill->register_tools;
    ok(exists $agent->tools->{web_search}, 'web_search registered');
};

subtest 'custom tool_name' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_custom');
    my $skill = $factory->new(agent => $agent, params => { tool_name => 'search' });
    $skill->setup;
    $skill->register_tools;
    ok(exists $agent->tools->{search}, 'custom tool name');
};

subtest 'global data' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_gd');
    my $skill = $factory->new(agent => $agent, params => {});
    my $gdata = $skill->get_global_data;
    ok(exists $gdata->{web_search_enabled}, 'web_search_enabled');
    ok(exists $gdata->{quality_filtering}, 'quality_filtering');
};

subtest 'prompt sections' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_ps');
    my $skill = $factory->new(agent => $agent, params => {});
    my $sections = $skill->get_prompt_sections;
    like($sections->[0]{title}, qr/Web Search/, 'title');
};

subtest 'parameter schema' => sub {
    my $schema = $factory->get_parameter_schema;
    ok(exists $schema->{api_key}, 'has api_key');
    ok(exists $schema->{search_engine_id}, 'has search_engine_id');
    ok(exists $schema->{num_results}, 'has num_results');
    ok(exists $schema->{response_prefix},  'has response_prefix');
    ok(exists $schema->{response_postfix}, 'has response_postfix');
};

# ----------------------------------------------------------------
# Python 8aad242 parity: response_prefix / response_postfix wrap
# successful results, leave error / empty branches alone.
# ----------------------------------------------------------------
subtest 'response_prefix wraps success body' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_prefix');
    my $skill = $factory->new(agent => $agent,
                              params => { response_prefix => 'BEGIN-CITATION' });
    my $out = $skill->_wrap_response("1. Foo\n   Foo snippet\n   http://x");
    like($out, qr/\ABEGIN-CITATION\n\n1\. Foo\b/,
         'prefix prepended with blank-line separator');
};

subtest 'response_postfix wraps success body' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_postfix');
    my $skill = $factory->new(agent => $agent,
                              params => { response_postfix => 'END-CITATION' });
    my $out = $skill->_wrap_response("1. Foo\n   snippet\n   http://x");
    like($out, qr/http:\/\/x\n\nEND-CITATION\z/,
         'postfix appended with blank-line separator');
};

subtest 'both prefix and postfix wrap success body' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_both');
    my $skill = $factory->new(agent => $agent, params => {
        response_prefix  => 'P',
        response_postfix => 'Q',
    });
    my $out = $skill->_wrap_response("body");
    is($out, "P\n\nbody\n\nQ",
       'both wrappers applied in canonical order');
};

subtest 'no wrap when neither prefix nor postfix set' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_no_wrap');
    my $skill = $factory->new(agent => $agent, params => {});
    my $body = "1. Foo\n   snippet\n   http://x";
    is($skill->_wrap_response($body), $body,
       'response passed through unchanged when params absent');
};

subtest 'error responses are NOT wrapped' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_err');
    my $skill = $factory->new(agent => $agent, params => {
        response_prefix  => 'WRAP',
        response_postfix => 'WRAP',
    });
    is($skill->_wrap_response('Web search error: 503 Service Unavailable'),
       'Web search error: 503 Service Unavailable',
       'HTTP error passes through unwrapped (matches Python)');
    is($skill->_wrap_response('Web search parse error: bad json'),
       'Web search parse error: bad json',
       'parse error passes through unwrapped');
    is($skill->_wrap_response('No results for: zzz'),
       'No results for: zzz',
       'empty-result sentinel passes through unwrapped');
};

# ================================================================
# Latency-control parity (Python 51101da + 295745b).
#
# overall_deadline + per_page_timeout are the contract; parallel_scrape
# is accepted for API parity (Perl runs sequentially); snippets_only is
# honored and the no-results / deadline paths fall back to a non-empty
# CSE-snippet formatting so a slow request can't blow past the kernel
# webhook timeout.
#
# These exercise the deadline path DETERMINISTICALLY by injecting a fake
# monotonic clock (no real sleeping) and a stub HTTP transport (no live
# network), so the assertions are stable.
# ================================================================

# Stub HTTP transport: returns a canned HTTP::Tiny-shaped success
# response with a fixed CSE `items[]` body. `get` records the URL it was
# called with so tests can assert per_page_timeout wiring + call counts.
{
    package StubHTTP;
    sub new {
        my ($class, %a) = @_;
        return bless {
            body  => $a{body}  // '{"items":[]}',
            calls => [],
        }, $class;
    }
    sub get {
        my ($self, $url) = @_;
        push @{ $self->{calls} }, $url;
        return { success => 1, status => 200, reason => 'OK', content => $self->{body} };
    }
    sub call_count { scalar @{ $_[0]->{calls} } }
}

my $one_item_body = '{"items":[{"title":"Acme Title","link":"https://example.com/a","snippet":"  Acme snippet text  "}]}';

# ---- defaults read correctly from params ----
subtest 'latency params default correctly' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_def');
    my $skill = $factory->new(agent => $agent, params => {});
    is($skill->_per_page_timeout, 2.0,  'per_page_timeout default 2.0');
    is($skill->_overall_deadline, 10.0, 'overall_deadline default 10.0');
    is($skill->_parallel_scrape, 1,     'parallel_scrape default true');
    is($skill->_snippets_only, 0,       'snippets_only default false');
};

subtest 'latency params honor overrides' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_ovr');
    my $skill = $factory->new(agent => $agent, params => {
        per_page_timeout => 3.5,
        overall_deadline => 12.0,
        parallel_scrape  => 0,
        snippets_only    => 1,
    });
    is($skill->_per_page_timeout, 3.5,  'per_page_timeout overridden');
    is($skill->_overall_deadline, 12.0, 'overall_deadline overridden');
    is($skill->_parallel_scrape, 0,     'parallel_scrape overridden false');
    is($skill->_snippets_only, 1,       'snippets_only overridden true');
};

subtest 'per_page_timeout falls back to bounded value when non-positive' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_ppt0');
    my $skill = $factory->new(agent => $agent, params => { per_page_timeout => 0 });
    is($skill->_per_page_timeout, 15, 'non-positive per_page_timeout -> 15s bound (never unbounded)');
};

# ---- all 6 params advertised in the schema (drift guard) ----
subtest 'all six latency/response params advertised in schema' => sub {
    my $schema = $factory->get_parameter_schema;
    for my $key (qw(response_prefix response_postfix per_page_timeout
                    overall_deadline parallel_scrape snippets_only)) {
        ok(exists $schema->{$key}, "schema advertises $key");
    }
    is($schema->{per_page_timeout}{default}, 2.0,  'per_page_timeout default 2.0 in schema');
    is($schema->{overall_deadline}{default}, 10.0, 'overall_deadline default 10.0 in schema');
    is($schema->{per_page_timeout}{type}, 'number',  'per_page_timeout typed number');
    is($schema->{overall_deadline}{type}, 'number',  'overall_deadline typed number');
    is($schema->{parallel_scrape}{type}, 'boolean',  'parallel_scrape typed boolean');
    is($schema->{snippets_only}{type},   'boolean',  'snippets_only typed boolean');
    is($schema->{parallel_scrape}{default}, 1, 'parallel_scrape default true');
    is($schema->{snippets_only}{default},   0, 'snippets_only default false');
};

# ---- per_page_timeout wires into the HTTP client timeout ----
subtest 'per_page_timeout sets the HTTP client timeout' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_http_to');
    my $skill = $factory->new(agent => $agent, params => { per_page_timeout => 4.0 });
    # The lazily-built default _http is an HTTP::Tiny with timeout from
    # per_page_timeout. Build it and assert the timeout took.
    is($skill->_http->timeout, 4.0,
       'HTTP::Tiny timeout derives from per_page_timeout');
};

# ---- happy path: snippets formatted, HTTP called once ----
subtest 'happy path formats CSE items (snippet-only behavior)' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_happy');
    my $skill = $factory->new(agent => $agent, params => {
        api_key => 'k', search_engine_id => 'cx',
    });
    my $stub = StubHTTP->new(body => $one_item_body);
    $skill->_http($stub);
    my $out = $skill->search_web('weather');
    is($stub->call_count, 1, 'CSE fetched exactly once');
    like($out, qr/Acme Title/,        'title present in response');
    like($out, qr/Acme snippet text/, 'snippet present in response');
    unlike($out, qr/^Snippet-only results/,
           'happy path uses the normal numbered format, not the fallback');
};

# ---- snippets_only: still returns non-empty content (already the behavior) ----
subtest 'snippets_only returns non-empty CSE content' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_snip');
    my $skill = $factory->new(agent => $agent, params => {
        api_key => 'k', search_engine_id => 'cx', snippets_only => 1,
    });
    $skill->_http(StubHTTP->new(body => $one_item_body));
    my $out = $skill->search_web('weather');
    ok(length $out, 'snippets_only response is non-empty');
    like($out, qr/Acme snippet text/, 'snippets_only carries the CSE snippet text');
};

# ---- overall_deadline guard: deterministic via injected clock ----
# The fake clock returns a first value (start), then a value past the
# deadline on the NEXT read — so the post-fetch deadline guard fires and
# the call must return the non-empty snippet fallback, NOT an empty
# "no results" message. This is the contract assertion.
subtest 'overall_deadline guard returns non-empty snippet fallback' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_deadline');
    my $skill = $factory->new(agent => $agent, params => {
        api_key => 'k', search_engine_id => 'cx',
        overall_deadline => 1.0,
    });
    $skill->_http(StubHTTP->new(body => $one_item_body));

    # Clock: first call = start (t=0). Every later call = t=100s, i.e. far
    # past the 1.0s deadline. So search_web computes deadline_at = 0+1.0 = 1.0,
    # then the guard sees clock()=100 >= 1.0 and falls back.
    my $nth = 0;
    $skill->_clock(sub { $nth++ == 0 ? 0 : 100 });

    my $out = $skill->search_web('weather');
    ok(length $out, 'deadline path returns a non-empty response');
    like($out, qr/^Snippet-only results/,
         'deadline path falls back to snippet formatting');
    like($out, qr/Acme snippet text/,
         'deadline fallback carries the CSE snippet text');
    unlike($out, qr/^No results for:/,
           'deadline path must NOT return the empty no-results message');
};

# ---- deadline guard fires even before the formatting loop ----
subtest 'overall_deadline already expired short-circuits to fallback' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_dl0');
    my $skill = $factory->new(agent => $agent, params => {
        api_key => 'k', search_engine_id => 'cx',
        overall_deadline => 0,   # zero budget: expired the instant we start
    });
    $skill->_http(StubHTTP->new(body => $one_item_body));
    # Real monotonic clock; with a 0s budget the post-fetch guard is
    # already past deadline regardless of timing.
    my $out = $skill->search_web('weather');
    like($out, qr/^Snippet-only results/,
         'zero deadline budget routes straight to the snippet fallback');
    like($out, qr/Acme snippet text/, 'fallback still non-empty');
};

# ---- no-results path returns a non-empty fallback sentinel ----
subtest 'no CSE results yields a non-empty no-results sentinel' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_empty');
    my $skill = $factory->new(agent => $agent, params => {
        api_key => 'k', search_engine_id => 'cx',
    });
    $skill->_http(StubHTTP->new(body => '{"items":[]}'));
    my $out = $skill->search_web('zzz no such thing');
    ok(length $out, 'no-results response is non-empty');
    like($out, qr/No results for: zzz no such thing/,
         'returns the non-empty no-results sentinel');
};

# ---- _format_snippet_results directly: empty -> non-empty, items -> shaped ----
subtest '_format_snippet_results shapes items and never returns empty' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'ws_fmt');
    my $skill = $factory->new(agent => $agent, params => {});
    my $empty = $skill->_format_snippet_results('q', [], 3);
    ok(length $empty, 'empty items still yields a non-empty string');
    like($empty, qr/No results for: q/, 'empty items -> no-results sentinel');

    my $items = [
        { title => 'T1', link => 'https://1', snippet => '  s1  ' },
        { title => 'T2', link => 'https://2', snippet => 's2' },
    ];
    my $out = $skill->_format_snippet_results('q', $items, 1);
    like($out, qr/=== RESULT 1 ===/, 'first result block present');
    like($out, qr/Title: T1/,   'title rendered');
    like($out, qr/URL: https:\/\/1/, 'url rendered');
    like($out, qr/Snippet: s1/, 'snippet trimmed + rendered');
    unlike($out, qr/T2/, 'num cap honored (only 1 of 2 items)');
};

done_testing;
