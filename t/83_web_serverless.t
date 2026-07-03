#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON qw(decode_json);

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
    is( $ret, $svc, 'chainable (returns self)' );
    is( $svc->_debug_routes_enabled, 1, 'debug routes now enabled' );
};

subtest 'Service setup_graceful_shutdown installs handlers' => sub {
    my $svc = SignalWire::SWML::Service->new;

    # Preserve and restore any existing handlers.
    local $SIG{TERM} = $SIG{TERM};
    local $SIG{INT}  = $SIG{INT};

    my $ret = $svc->setup_graceful_shutdown;
    is( $ret, $svc, 'chainable (returns self)' );
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
    my $agent = SignalWire::Agent::AgentBase->new( name => 'svc', route => '/svc' );

    my $resp = $agent->handle_serverless_request(
        mode  => 'lambda',
        event => { rawPath => '/health', httpMethod => 'GET' },
    );
    is( ref $resp, 'HASH', 'lambda response is a hashref' );
    is( $resp->{statusCode}, 200, 'lambda proxy statusCode' );
    ok( defined $resp->{body}, 'lambda response carries a body' );
    is( ref $resp->{headers}, 'HASH', 'headers folded to hashref' );
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
    is( ref $decoded, 'HASH', 'cgi health body is JSON' );
    is( $decoded->{status}, 'healthy', 'health status healthy' );
};

subtest 'handle_serverless_request server mode falls through to run' => sub {
    # In 'server' mode handle_serverless_request delegates to run()/serve().
    # We stub serve to avoid actually binding a socket.
    my $agent = SignalWire::Agent::AgentBase->new( name => 'svc', route => '/svc' );

    my $served = 0;
    no warnings 'redefine';
    local *SignalWire::Agent::AgentBase::serve = sub { $served = 1; return 'served' };

    my $out = $agent->handle_serverless_request( mode => 'server' );
    is( $served, 1,        'server mode routed to serve()' );
    is( $out,    'served', 'return value propagated' );
};

done_testing;
