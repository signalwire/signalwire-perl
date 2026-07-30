#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

# ================================================================
# mcp_gateway CLIENT skill. TDD-bidirectional: assert it registers the
# gateway's MCP tools as SWAIG functions (HTTP mocked, no live network),
# that verify_ssl defaults TRUE and threads to HTTP::Tiny's verify_SSL,
# and that both auth methods (bearer / HTTP Basic) build the right
# Authorization header.
# ================================================================

my $factory = SignalWire::Skills::SkillRegistry->get_factory('mcp_gateway');
ok( defined $factory, 'factory found for mcp_gateway' );

# ---- Stub HTTP transport: an HTTP::Tiny-shaped object whose `request`
# dispatches on (method, url). Records every call (method, url, headers,
# content) so tests can assert auth headers + registration wiring.
{

    package StubHTTP;

    sub new {
        my ( $class, %a ) = @_;
        return bless { calls => [], responses => $a{responses} // {} }, $class;
    }

    sub request {
        my ( $self, $method, $url, $opts ) = @_;
        push @{ $self->{calls} },
            {
            method  => $method,
            url     => $url,
            headers => $opts->{headers},
            content => $opts->{content}
            };

        # Match the longest configured (method-url-suffix) key.
        for my $key ( sort { length($b) <=> length($a) } keys %{ $self->{responses} } ) {
            my ( $m, $suffix ) = split /\s+/, $key, 2;
            if ( $m eq $method && index( $url, $suffix ) >= 0 ) {
                return $self->{responses}{$key};
            }
        }
        return { success => 1, status => 200, reason => 'OK', content => '{}' };
    }
    sub calls { my ($self) = @_; return $self->{calls} }
}

sub _ok_resp {
    my ($content) = @_;
    return { success => 1, status => 200, reason => 'OK', content => $content };
}

# A gateway advertising one service ('files') with two tools.
my %gateway_responses = (
    'GET /services'             => _ok_resp('["files"]'),
    'GET /services/files/tools' => _ok_resp(
        JSON::encode_json(
            {
                tools => [
                    {
                        name        => 'read',
                        description => 'Read a file',
                        inputSchema => {
                            type       => 'object',
                            properties =>
                                { path => { type => 'string', description => 'File path' } },
                            required => ['path'],
                        },
                    },
                    {
                        name        => 'list',
                        description => 'List a directory',
                        inputSchema => { type => 'object', properties => {} },
                    },
                ],
            }
        )
    ),
    'POST /services/files/call' => _ok_resp('{"result":"file contents here"}'),
);

subtest 'construction + skill metadata' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_ctor' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw.example.com', auth_token => 'tok' },
    );
    is( $skill->skill_name, 'mcp_gateway', 'skill_name' );
    ok( $skill->supports_multiple_instances, 'multi-instance' );
};

subtest 'verify_ssl defaults TRUE and threads to HTTP::Tiny verify_SSL' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_ssl_def' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw.example.com', auth_token => 'tok' },
    );
    is( $skill->verify_ssl, 1, 'verify_ssl config default is 1 (secure: verify ON)' );

    # The lazily-built default _http is a real HTTP::Tiny whose verify_SSL
    # is threaded from the secure-default verify_ssl config param.
    isa_ok( $skill->_http, 'HTTP::Tiny', 'default _http' );
    is( $skill->_http->verify_SSL, 1, 'HTTP::Tiny built with verify_SSL => 1 from secure default' );
};

subtest 'verify_ssl opt-out threads through to verify_SSL off' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_ssl_off' );
    my $skill = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw.example.com', auth_token => 'tok', verify_ssl => 0 },
    );
    is( $skill->verify_ssl,        0, 'verify_ssl=0 opt-out honored' );
    is( $skill->_http->verify_SSL, 0, 'HTTP::Tiny verify_SSL follows the opt-out' );
};

subtest 'schema advertises verify_ssl with a secure (true) default' => sub {
    my $schema = $factory->get_parameter_schema;
    ok( exists $schema->{gateway_url},    'schema has gateway_url' );
    ok( $schema->{gateway_url}{required}, 'gateway_url required' );
    ok( exists $schema->{verify_ssl},     'schema has verify_ssl' );
    is( $schema->{verify_ssl}{type}, 'boolean', 'verify_ssl typed boolean' );
    ok( $schema->{verify_ssl}{default},  'verify_ssl default is true (secure)' );
    ok( exists $schema->{auth_token},    'schema has auth_token' );
    ok( exists $schema->{auth_user},     'schema has auth_user' );
    ok( exists $schema->{auth_password}, 'schema has auth_password' );
    ok( exists $schema->{tool_prefix},   'schema has tool_prefix' );
};

subtest 'setup validates auth + gateway_url' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_setup' );

    # Missing gateway_url -> fail.
    my $s1 = $factory->new( agent => $agent, params => { auth_token => 'tok' } );
    ok( !$s1->setup, 'no gateway_url -> setup fails' );

    # gateway_url + no auth at all -> fail.
    my $s2 = $factory->new( agent => $agent, params => { gateway_url => 'https://gw' } );
    ok( !$s2->setup, 'no auth -> setup fails' );

    # Bearer token -> ok.
    my $s3 = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw', auth_token => 't' }
    );
    ok( $s3->setup, 'bearer token -> setup ok' );

    # Basic auth pair -> ok.
    my $s4 = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw', auth_user => 'u', auth_password => 'p' },
    );
    ok( $s4->setup, 'basic auth pair -> setup ok' );
};

subtest 'registers gateway tools as SWAIG functions (discover-all)' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_reg' );
    my $stub  = StubHTTP->new( responses => \%gateway_responses );
    my $skill = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw.example.com', auth_token => 'tok' },
        _http  => $stub,
    );
    $skill->setup;
    $skill->register_tools;

    ok( exists $agent->tools->{'mcp_files_read'}, 'mcp_files_read registered as SWAIG function' );
    ok( exists $agent->tools->{'mcp_files_list'}, 'mcp_files_list registered as SWAIG function' );
    ok( exists $agent->tools->{'_mcp_gateway_hangup'}, 'hangup hook registered' );
    ok( $agent->tools->{'_mcp_gateway_hangup'}{is_hangup_hook},
        'hangup hook flagged is_hangup_hook' );

    # The read tool forwards the MCP required-arg list.
    my $read = $agent->tools->{'mcp_files_read'};
    is_deeply( $read->{parameters}{required}, ['path'],
        'required args forwarded from inputSchema' );
    is( $read->{parameters}{properties}{path}{type}, 'string', 'param type from inputSchema' );
    like( $read->{description}, qr/\[files\]/, 'description carries the service name' );
};

subtest 'explicit service + tool filter registers only kept tools' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_filter' );
    my $stub  = StubHTTP->new( responses => \%gateway_responses );
    my $skill = $factory->new(
        agent  => $agent,
        params => {
            gateway_url => 'https://gw.example.com',
            auth_token  => 'tok',
            services    => [ { name => 'files', tools => ['read'] } ],
        },
        _http => $stub,
    );
    $skill->setup;
    $skill->register_tools;
    ok( exists $agent->tools->{'mcp_files_read'},  'kept tool registered' );
    ok( !exists $agent->tools->{'mcp_files_list'}, 'filtered-out tool NOT registered' );

    # With an explicit services list, /services is never queried.
    ok( ( !grep { $_->{url} =~ m{/services$} } @{ $stub->calls } ),
        'no discover-all when services given' );
};

subtest 'bearer auth sends Bearer Authorization header' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_bearer' );
    my $stub  = StubHTTP->new( responses => \%gateway_responses );
    my $skill = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw.example.com', auth_token => 'secrettoken' },
        _http  => $stub,
    );
    $skill->setup;
    $skill->register_tools;
    my ($call) = grep { $_->{url} =~ m{/tools$} } @{ $stub->calls };
    ok( $call, 'a tools request was made' );
    is( $call->{headers}{Authorization}, 'Bearer secrettoken', 'bearer header' );
};

subtest 'basic auth sends Basic Authorization header' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_basic' );
    my $stub  = StubHTTP->new( responses => \%gateway_responses );
    my $skill = $factory->new(
        agent  => $agent,
        params => {
            gateway_url   => 'https://gw.example.com',
            auth_user     => 'alice',
            auth_password => 'pw'
        },
        _http => $stub,
    );
    $skill->setup;
    $skill->register_tools;
    my ($call) = grep { $_->{url} =~ m{/tools$} } @{ $stub->calls };
    ok( $call, 'a tools request was made' );
    require MIME::Base64;
    my $expect = 'Basic ' . MIME::Base64::encode_base64( 'alice:pw', '' );
    is( $call->{headers}{Authorization}, $expect, 'basic auth header' );
};

subtest 'a registered tool handler calls the gateway and returns the result' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_call' );
    my $stub  = StubHTTP->new( responses => \%gateway_responses );
    my $skill = $factory->new(
        agent  => $agent,
        params => { gateway_url => 'https://gw.example.com', auth_token => 'tok' },
        _http  => $stub,
    );
    $skill->setup;
    $skill->register_tools;
    my $handler = $agent->tools->{'mcp_files_read'}{_handler};
    ok( $handler, 'handler present' );
    my $result = $handler->( { path => '/etc/hosts' }, { call_id => 'call-1' } );
    isa_ok( $result, 'SignalWire::SWAIG::FunctionResult', 'handler returns FunctionResult' );
    my $hash = $result->to_hash;
    like( JSON::encode_json($hash), qr/file contents here/, 'gateway result propagated' );

    # The call POSTed to the gateway with the bearer header.
    my ($call) = grep { $_->{url} =~ m{/call$} } @{ $stub->calls };
    ok( $call, 'call endpoint hit' );
    is( $call->{method},                 'POST',       'POST to /call' );
    is( $call->{headers}{Authorization}, 'Bearer tok', 'call carries bearer auth' );
};

subtest 'contributions: hints, global_data, prompt_sections' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'mcp_contrib' );
    my $skill = $factory->new(
        agent  => $agent,
        params => {
            gateway_url => 'https://gw.example.com/',
            auth_token  => 'tok',
            services    => [ { name => 'files', tools => ['read'] } ],
        },
    );
    my $hints = $skill->get_hints;
    ok( ( grep { $_ eq 'MCP' } @$hints ),   'hints include MCP' );
    ok( ( grep { $_ eq 'files' } @$hints ), 'hints include the service name' );

    my $gd = $skill->get_global_data;
    is( $gd->{mcp_gateway_url},
        'https://gw.example.com', 'global_data gateway_url normalised (trailing slash stripped)' );
    is_deeply( $gd->{mcp_services}, ['files'], 'global_data service names' );

    my $sections = $skill->get_prompt_sections;
    ok( @$sections, 'prompt sections present when services configured' );
    like( $sections->[0]{title}, qr/MCP Gateway/, 'prompt section title' );

    # skip_prompt suppresses the sections (base-class behavior).
    my $skill2 = $factory->new(
        agent  => $agent,
        params => {
            gateway_url => 'https://gw',
            auth_token  => 'tok',
            services    => [ { name => 'x' } ],
            skip_prompt => 1
        },
    );
    is_deeply( $skill2->get_prompt_sections, [], 'skip_prompt suppresses prompt sections' );
};

done_testing;
