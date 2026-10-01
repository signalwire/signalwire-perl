#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

# Allow the private/loopback test URL past the SSRF guard.
local $ENV{SWML_ALLOW_PRIVATE_URLS} = '1';

my $factory = SignalWire::Skills::SkillRegistry->get_factory('native_vector_search');
ok( defined $factory, 'factory found for native_vector_search' );

# A tiny fake HTTP client capturing the last request and replaying a canned body.
{

    package FakeHttp;
    sub new { my ( $class, $resp ) = @_; return bless { calls => [], resp => $resp }, $class }

    sub post {
        my ( $self, $url, $opts ) = @_;
        push @{ $self->{calls} }, { url => $url, opts => $opts };
        return $self->{resp};
    }
}

subtest 'construction + metadata' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs' );
    my $skill = $factory->new( agent => $agent, params => {} );
    is( $skill->skill_name, 'native_vector_search', 'skill_name' );
    ok( $skill->supports_multiple_instances, 'multi-instance' );
};

subtest 'setup requires remote_url' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_nourl' );
    my $skill = $factory->new( agent => $agent, params => {} );
    ok( !$skill->setup, 'setup returns false without remote_url' );

    my $agent2 = SignalWire::Agent::AgentBase->new( name => 'nvs_url' );
    my $skill2 = $factory->new(
        agent  => $agent2,
        params => { remote_url => 'http://search.example.test:8001' },
    );
    ok( $skill2->setup, 'setup returns true with a valid remote_url' );
};

subtest 'setup rejects a non-http scheme (SSRF guard)' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_ssrf' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { remote_url => 'file:///etc/passwd' },
    );
    ok( !$skill->setup, 'setup rejects a file:// URL' );
};

subtest 'registers a search tool' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_reg' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { remote_url => 'http://search.example.test:8001' },
    );
    $skill->setup;
    $skill->register_tools;
    ok( exists $agent->tools->{search_knowledge}, 'search_knowledge tool registered' );

    my $agent2 = SignalWire::Agent::AgentBase->new( name => 'nvs_custom' );
    my $skill2 = $factory->new(
        agent  => $agent2,
        params => { remote_url => 'http://search.example.test:8001', tool_name => 'kb' },
    );
    $skill2->setup;
    $skill2->register_tools;
    ok( exists $agent2->tools->{kb}, 'custom tool_name honored' );
};

subtest 'handle_search POSTs {query,count} and formats results' => sub {
    my $body = JSON::encode_json(
        {
            results => [
                {
                    content  => 'The sky is blue.',
                    score    => 0.91,
                    metadata => { filename => 'sky.md' }
                },
                {
                    content  => 'Grass is green.',
                    score    => 0.72,
                    metadata => { filename => 'grass.md' }
                },
            ],
        }
    );
    my $fake = FakeHttp->new( { success => 1, status => 200, content => $body } );

    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_search' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { remote_url => 'http://search.example.test:8001', index_name => 'docs' },
    );
    $skill->setup;
    $skill->{_http} = $fake;    # inject the mock transport

    my $result = $skill->_handle_search( { query => 'colors', count => 2 }, {} );
    ok( defined $result, 'handle_search returned a FunctionResult' );

    # It POSTed exactly once, to <base>/search, with a JSON {query,count,index_name} body.
    is( scalar @{ $fake->{calls} }, 1, 'exactly one POST issued' );
    my $call = $fake->{calls}[0];
    like( $call->{url}, qr{/search$}, 'POST to the /search endpoint' );
    my $sent = JSON::decode_json( $call->{opts}{content} );
    is( $sent->{query},      'colors', 'query forwarded on the wire' );
    is( $sent->{count},      2,        'count forwarded on the wire' );
    is( $sent->{index_name}, 'docs',   'index_name forwarded on the wire' );

    my $text = $result->response;
    like( $text, qr/Search results for 'colors'/, 'header present' );
    like( $text, qr/The sky is blue\./,           'first result content formatted' );
    like( $text, qr/relevance: 0\.91/,            'score rendered' );
    like( $text, qr/=== RESULT 1 ===/,            'result block markers' );
};

subtest 'empty query is guarded before any HTTP call' => sub {
    my $fake  = FakeHttp->new( { success => 1, status => 200, content => '{}' } );
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_empty' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { remote_url => 'http://search.example.test:8001' },
    );
    $skill->setup;
    $skill->{_http} = $fake;

    my $result = $skill->_handle_search( { query => '   ' }, {} );
    like( $result->response, qr/provide a search query/i, 'empty-query message' );
    is( scalar @{ $fake->{calls} }, 0, 'no HTTP call for an empty query' );
};

subtest 'no results yields the no-results message' => sub {
    my $fake = FakeHttp->new(
        { success => 1, status => 200, content => JSON::encode_json( { results => [] } ) } );
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_none' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { remote_url => 'http://search.example.test:8001' },
    );
    $skill->setup;
    $skill->{_http} = $fake;

    my $result = $skill->_handle_search( { query => 'nothing' }, {} );
    like( $result->response, qr/No results found for 'nothing'/, 'no-results message with query' );
};

subtest 'service failure is handled gracefully' => sub {
    my $fake  = FakeHttp->new( { success => 0, status => 503, content => '' } );
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_fail' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { remote_url => 'http://search.example.test:8001' },
    );
    $skill->setup;
    $skill->{_http} = $fake;

    my $result = $skill->_handle_search( { query => 'x' }, {} );
    like( $result->response, qr/unavailable/i, 'graceful unavailable message' );
};

subtest 'hints, global data, prompt sections, parameter schema' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'nvs_meta' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { remote_url => 'http://search.example.test:8001', hints => ['knowledge'] },
    );
    $skill->setup;

    my $hints = $skill->get_hints;
    ok( ( grep { $_ eq 'search' } @$hints ),    'default hint present' );
    ok( ( grep { $_ eq 'knowledge' } @$hints ), 'custom hint merged' );

    is( $skill->get_global_data->{search_mode}, 'remote', 'global data reports remote mode' );

    my $sections = $skill->get_prompt_sections;
    like( $sections->[0]{title}, qr/Knowledge Search/, 'prompt section title' );

    my $schema = $factory->get_parameter_schema;
    ok( $schema->{remote_url}{required}, 'remote_url is required in the schema' );
    ok( exists $schema->{count},         'count in the schema' );

    like( $skill->get_instance_key, qr/^native_vector_search_/, 'instance key shape' );
};

done_testing;
