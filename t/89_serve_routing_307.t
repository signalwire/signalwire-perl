#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);

# =============================================================================
# #61 — the SERVED path must route through handle_request.
#
# serve()/run() build the PSGI app via psgi_app -> _build_psgi_app; as_router()
# / get_app() return to_psgi_app. Before this fix those apps ran an inline SWML
# handler that re-implemented auth + render but SKIPPED the routing-callback 307
# branch, so a request that should redirect got a 200 SWML document instead.
#
# These tests hit the actual served PSGI endpoint (the same coderef serve()
# hands to Plack) and assert the routing callback drives a real 307 — plus the
# 401-on-bad-auth and 200-happy-path, all now flowing through handle_request.
# =============================================================================

use SignalWire::Agent::AgentBase;
use SignalWire::SWML::Service;

# Build a PSGI env. A POST carries a JSON body (buffered so psgi.input is
# readable by the app).
sub make_env {
    my (%o) = @_;
    my $body = $o{body} // '';
    open my $fh, '<', \$body or die "cannot open in-memory body: $!";
    return {
        REQUEST_METHOD => $o{method} // 'GET',
        PATH_INFO      => $o{path}   // '/',
        SCRIPT_NAME    => '',
        SERVER_NAME    => 'localhost',
        SERVER_PORT    => 3000,
        QUERY_STRING   => $o{query} // '',
        CONTENT_LENGTH => length($body),
        CONTENT_TYPE   => 'application/json',
        ( $o{auth} ? ( HTTP_AUTHORIZATION => "Basic $o{auth}" ) : () ),
        ( $o{extra_headers} ? %{ $o{extra_headers} } : () ),
        'psgi.input'   => $fh,
        'psgi.errors'  => \*STDERR,
        'psgi.url_scheme' => 'http',
    };
}

# Turn a PSGI [status, \@headers, \@body] triple into (status, %headers, body).
sub psgi_parts {
    my ($res) = @_;
    my %h = @{ $res->[1] };
    my $body = join '', @{ $res->[2] };
    return ( $res->[0], \%h, $body );
}

my $AUTH = encode_base64( 'u:p', '' );

# ------------------------------------------------------------------
# AgentBase served path (serve/run -> psgi_app -> _build_psgi_app)
# ------------------------------------------------------------------
subtest 'AgentBase served path: routing callback drives a real 307' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    my $seen_body;
    my $seen_headers;
    $agent->register_routing_callback(
        sub {
            my ( $body, $headers ) = @_;
            $seen_body    = $body;
            $seen_headers = $headers;
            return 'https://elsewhere.example/swml';
        },
        '/',
    );

    # This is the exact coderef serve()/run() hands to Plack.
    my $app = $agent->psgi_app;

    my ( $status, $headers, $body ) = psgi_parts(
        $app->(
            make_env(
                method => 'POST',
                path   => '/',
                auth   => $AUTH,
                body   => encode_json( { call_id => 'abc123' } ),
                extra_headers => { HTTP_X_TRACE => 'trace-99' },
            )
        )
    );

    is( $status, 307, 'served POST / returns 307 (NOT a 200 SWML doc)' );
    is( $headers->{Location}, 'https://elsewhere.example/swml',
        'Location header carries the routed URL' );
    is( $body, '', 'redirect body is empty' );
    is( $seen_body->{call_id}, 'abc123',
        'routing callback received the parsed body' );
    is( $seen_headers->{'X-Trace'}, 'trace-99',
        'routing callback received the request headers' );
};

subtest 'AgentBase served path: 401 on bad auth through the served endpoint' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $agent->register_routing_callback( sub { return '/nope' }, '/' );
    my $app = $agent->psgi_app;

    my ( $status, $headers ) = psgi_parts(
        $app->(
            make_env(
                method => 'POST',
                path   => '/',
                auth   => encode_base64( 'u:wrong', '' ),
                body   => encode_json( { call_id => 'x' } ),
            )
        )
    );
    is( $status, 401, 'bad auth -> 401 through served path' );
    is( $headers->{'WWW-Authenticate'}, 'Basic',
        'WWW-Authenticate header set on 401' );
};

subtest 'AgentBase served path: 200 SWML happy path (no redirect)' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );

    # A callback that returns undef must fall through to the rendered document.
    $agent->register_routing_callback( sub { return undef }, '/' );
    my $app = $agent->psgi_app;

    my ( $status, $headers, $body ) = psgi_parts(
        $app->(
            make_env(
                method => 'POST',
                path   => '/',
                auth   => $AUTH,
                body   => encode_json( { call_id => 'x' } ),
            )
        )
    );
    is( $status, 200, 'no redirect -> 200 SWML document' );
    my $doc = eval { decode_json($body) };
    ok( ref $doc eq 'HASH', 'body is a JSON SWML document' );

    # GET happy path (no body, no redirect) also 200.
    my ( $gstatus, undef, $gbody ) = psgi_parts(
        $app->( make_env( method => 'GET', path => '/', auth => $AUTH ) ) );
    is( $gstatus, 200, 'GET / served with 200' );
    ok( decode_json($gbody), 'GET body is JSON SWML' );
};

# ------------------------------------------------------------------
# as_router served path (as_router / get_app -> to_psgi_app)
# ------------------------------------------------------------------
subtest 'as_router served path: routing callback drives a real 307' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'router_agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $agent->register_routing_callback( sub { return '/routed' }, '/' );

    my $app = $agent->as_router;    # == to_psgi_app (inherited)

    my ( $status, $headers, $body ) = psgi_parts(
        $app->(
            make_env(
                method => 'POST',
                path   => '/',
                auth   => $AUTH,
                body   => encode_json( { call_id => 'z' } ),
            )
        )
    );
    is( $status, 307, 'as_router POST / returns 307 (NOT a 200)' );
    is( $headers->{Location}, '/routed', 'Location header carries the route' );
    is( $body, '', 'redirect body is empty' );
};

subtest 'SWMLService served path: routing callback drives a real 307' => sub {
    my $svc = SignalWire::SWML::Service->new(
        name                => 'svc',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $svc->register_routing_callback( sub { return '/svc-routed' }, '/' );

    my $app = $svc->as_router;

    my ( $status, $headers, $body ) = psgi_parts(
        $app->(
            make_env(
                method => 'POST',
                path   => '/',
                auth   => $AUTH,
                body   => encode_json( { call_id => 'q' } ),
            )
        )
    );
    is( $status, 307, 'SWMLService served POST / returns 307' );
    is( $headers->{Location}, '/svc-routed', 'Location header carries the route' );
};

done_testing();
