#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use MIME::Base64 qw(encode_base64);

use SignalWire::Agent::AgentBase;
use SignalWire::SWML::Service;

# =============================================================================
# as_router parity: the mountable "embed my routes in a host app" unit.
#
# Python parity:
#   signalwire.core.mixins.web_mixin.WebMixin.as_router
#   signalwire.core.swml_service.SWMLService.as_router
#     -> return a HostAppRouter (a FastAPI APIRouter) that a host app mounts.
#
# Perl's routable unit is a PSGI application coderef
#   (sub { my $env = shift; ...; [$status, $headers, $body] })
# mountable in any Plack app via Plack::Builder `mount`. as_router returns
# that coderef (== $self->to_psgi_app), carrying this service's routes
# (/, /swaig, /post_prompt + health/ready + auth).
# =============================================================================

sub make_env {
    my (%o) = @_;
    return {
        REQUEST_METHOD     => $o{method}  // 'GET',
        PATH_INFO          => $o{path}    // '/',
        SCRIPT_NAME        => '',
        SERVER_NAME        => 'localhost',
        SERVER_PORT        => 3000,
        QUERY_STRING       => $o{query}   // '',
        ( $o{auth} ? ( HTTP_AUTHORIZATION => "Basic $o{auth}" ) : () ),
        'psgi.input'       => do { open my $fh, '<', \( $o{body} // '' ); $fh },
    };
}

subtest 'as_router returns a PSGI coderef (mountable app)' => sub {
    my $svc = SignalWire::SWML::Service->new( name => 'router_svc' );
    my $app = $svc->as_router;
    is( ref($app), 'CODE', 'as_router returns a coderef' );

    # It is the SAME mountable unit as to_psgi_app (Perl idiom for the
    # HostAppRouter capability).
    my $direct = $svc->to_psgi_app;
    is( ref($direct), 'CODE', 'to_psgi_app is also a coderef' );

    # Health endpoint needs no auth — proves the returned coderef is a live,
    # routable PSGI app, not an empty stub.
    my $res = $app->( make_env( path => '/health' ) );
    is( ref($res), 'ARRAY', 'PSGI app returns a [status, headers, body] triple' );
    is( $res->[0], 200, '/health served with 200 through as_router coderef' );
};

subtest 'as_router coderef carries the service routes (/ and /swaig)' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'router_agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $agent->define_tool(
        name        => 'ping',
        description => 'ping tool',
        parameters  => { type => 'object', properties => {} },
        handler     => sub { {} },
    );

    my $app  = $agent->as_router;
    is( ref($app), 'CODE', 'AgentBase inherits as_router (PSGI coderef)' );

    my $auth = encode_base64( 'u:p', '' );

    # Main SWML route.
    my $swml = $app->( make_env( path => '/', auth => $auth ) );
    is( $swml->[0], 200, 'main route (/) served through as_router' );

    # SWAIG route (GET returns the SWML doc; proves the route is carried).
    my $swaig = $app->(
        make_env( method => 'GET', path => '/swaig', auth => $auth ) );
    is( $swaig->[0], 200, '/swaig route served through as_router' );

    # Auth is enforced on protected routes (proves it is the real app).
    my $noauth = $app->( make_env( path => '/' ) );
    is( $noauth->[0], 401, 'protected route requires auth through as_router' );
};

done_testing();
