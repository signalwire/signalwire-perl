#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON         qw(decode_json);
use MIME::Base64 ();

use_ok('SignalWire::SWML::Service');
use_ok('SignalWire::Agent::AgentBase');

# ---------------------------------------------------------------------------
# SWML::Service WebMixin surface: get_app / enable_debug_routes /
# setup_graceful_shutdown
# ---------------------------------------------------------------------------
subtest 'Service get_app returns a PSGI coderef' => sub {
    my $svc = SignalWire::SWML::Service->new;
    my $app = $svc->get_app;
    is( ref $app, 'CODE', 'get_app is a PSGI coderef' );

    my $res = $app->( { REQUEST_METHOD => 'GET', PATH_INFO => '/health' } );
    is( $res->[0], 200, 'health endpoint 200 via get_app' );
};

subtest 'Service enable_debug_routes' => sub {
    my $svc = SignalWire::SWML::Service->new;
    is( $svc->_debug_routes_enabled, 0, 'debug routes off by default' );
    my $ret = $svc->enable_debug_routes;
    is( $ret,                        $svc, 'chainable (returns self)' );
    is( $svc->_debug_routes_enabled, 1,    'debug routes now enabled' );
};

subtest 'Service setup_graceful_shutdown installs handlers' => sub {
    my $svc = SignalWire::SWML::Service->new;

    # Preserve and restore any existing handlers.
    local $SIG{TERM} = $SIG{TERM};
    local $SIG{INT}  = $SIG{INT};

    my $ret = $svc->setup_graceful_shutdown;
    is( $ret,           $svc,   'chainable (returns self)' );
    is( ref $SIG{TERM}, 'CODE', 'SIGTERM handler installed' );
    is( ref $SIG{INT},  'CODE', 'SIGINT handler installed' );

    # Firing the handler flips _server_running off via stop().
    $svc->_server_running(1);
    $SIG{TERM}->('TERM');
    is( $svc->_server_running, 0, 'handler calls stop()' );
};

# ---------------------------------------------------------------------------
# AgentBase ServerlessMixin surface: handle_serverless_request
# ---------------------------------------------------------------------------
subtest 'handle_serverless_request lambda mode' => sub {

    # Python parity: lambda mode dispatches the event DIRECTLY (auth gate,
    # then /swaig-or-path SWAIG dispatch, else root SWML) — it does NOT proxy
    # through the PSGI app, so /health is not a lambda route and a valid Basic
    # header is required. A root event with good auth renders the SWML doc.
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'svc',
        route               => '/svc',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    my $auth = 'Basic ' . MIME::Base64::encode_base64( 'u:p', '' );

    my $resp = $agent->handle_serverless_request(
        mode  => 'lambda',
        event => { rawPath => '/', headers => { authorization => $auth } },
    );
    is( ref $resp,           'HASH', 'lambda response is a hashref' );
    is( $resp->{statusCode}, 200,    'lambda root statusCode 200' );
    ok( defined $resp->{body}, 'lambda response carries a body' );
    is( ref $resp->{headers}, 'HASH', 'headers folded to hashref' );
    my $doc = eval { decode_json( $resp->{body} ) };
    is( ref $doc, 'HASH', 'body is the rendered SWML document' );

    # No auth -> 401 challenge (Python parity: _send_lambda_auth_challenge).
    my $noauth = $agent->handle_serverless_request(
        mode  => 'lambda',
        event => { rawPath => '/', headers => {} }
    );
    is( $noauth->{statusCode}, 401, 'lambda without auth -> 401' );
};

subtest 'handle_serverless_request cgi mode' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'svc', route => '/svc' );

    local $ENV{PATH_INFO}      = '/health';
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = '';
    local $ENV{CONTENT_LENGTH} = 0;

    my $body = $agent->handle_serverless_request( mode => 'cgi' );
    ok( defined $body && !ref $body, 'cgi mode returns a scalar body string' );
    my $decoded = eval { decode_json($body) };
    is( ref $decoded,       'HASH',    'cgi health body is JSON' );
    is( $decoded->{status}, 'healthy', 'health status healthy' );
};

subtest 'handle_serverless_request server mode falls through to run' => sub {

    # In 'server' mode handle_serverless_request delegates to run()/serve().
    # We stub serve to avoid actually binding a socket.
    my $agent = SignalWire::Agent::AgentBase->new( name => 'svc', route => '/svc' );

    my $served = 0;

    # Stub serve() so the test never binds a real socket; 'redefine' is exactly
    # the warning this deliberate override raises.
    no warnings 'redefine';    ## no critic (TestingAndDebugging::ProhibitNoWarnings)
    local *SignalWire::Agent::AgentBase::serve = sub { $served = 1; return 'served' };

    my $out = $agent->handle_serverless_request( mode => 'server' );
    is( $served, 1,        'server mode routed to serve()' );
    is( $out,    'served', 'return value propagated' );
};

done_testing;
