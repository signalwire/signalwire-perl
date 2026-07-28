#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON qw(encode_json decode_json);
use MIME::Base64 qw(encode_base64);

# Real-behavior tests for the framework-free request-dispatch core
# handle_request(method, url, headers, body) -> (status, headers, body_string).
# Parity with Python's SWMLService.handle_request and its AgentBase override
# (the primitive dispatch surface the FastAPI/PSGI path delegates to).

use_ok('SignalWire::SWML::Service');
use_ok('SignalWire::Agent::AgentBase');

# Build a Basic-auth header value for the given service's credentials.
sub auth_for {
    my ($svc) = @_;
    my $raw = $svc->basic_auth_user . ':' . $svc->basic_auth_password;
    return 'Basic ' . encode_base64( $raw, '' );
}

# ------------------------------------------------------------------
# SWMLService.handle_request
# ------------------------------------------------------------------
subtest 'SWMLService: 200 renders the document' => sub {
    my $svc = SignalWire::SWML::Service->new(
        name             => 'svc',
        basic_auth_user  => 'u',
        basic_auth_password => 'p',
    );
    my ( $status, $headers, $body ) = $svc->handle_request(
        'GET', 'http://x/', { Authorization => auth_for($svc) }, undef,
    );
    is( $status, 200, 'status 200' );
    my $doc = eval { decode_json($body) };
    ok( ref $doc, 'body is JSON' );
};

subtest 'SWMLService: 401 on missing/bad auth' => sub {
    my $svc = SignalWire::SWML::Service->new(
        name             => 'svc',
        basic_auth_user  => 'u',
        basic_auth_password => 'p',
    );
    my ( $status, $headers, $body ) =
        $svc->handle_request( 'GET', 'http://x/', {}, undef );
    is( $status, 401, 'status 401 without credentials' );
    is( $headers->{'WWW-Authenticate'}, 'Basic', 'WWW-Authenticate header set' );
    my $err = decode_json($body);
    is( $err->{error}, 'Unauthorized', 'JSON error body' );
};

subtest 'SWMLService: 307 routing redirect, callback gets (body, headers)' => sub {
    my $svc = SignalWire::SWML::Service->new(
        name             => 'svc',
        basic_auth_user  => 'u',
        basic_auth_password => 'p',
    );
    my @seen;
    $svc->register_routing_callback(
        sub {
            my ( $body, $headers ) = @_;
            @seen = ( $body, $headers );
            return '/elsewhere';
        },
        '/route',
    );
    my ( $status, $headers, $body ) = $svc->handle_request(
        'POST', 'http://x/route',
        { Authorization => auth_for($svc), 'X-Trace' => 'abc' },
        { call_id => '123' },
    );
    is( $status, 307, 'status 307 redirect' );
    is( $headers->{Location}, '/elsewhere', 'Location header carries the route' );
    is( $body, '', 'empty body on redirect' );
    is( $seen[0]{call_id}, '123', 'callback arg 1 is the parsed body' );
    is( $seen[1]{'X-Trace'}, 'abc', 'callback arg 2 is the headers hashref' );
};

subtest 'SWMLService: callback returning undef falls through to 200' => sub {
    my $svc = SignalWire::SWML::Service->new(
        name             => 'svc',
        basic_auth_user  => 'u',
        basic_auth_password => 'p',
    );
    $svc->register_routing_callback( sub { return undef }, '/route' );
    my ( $status, undef, $body ) = $svc->handle_request(
        'POST', 'http://x/route',
        { Authorization => auth_for($svc) },
        { k => 'v' },
    );
    is( $status, 200, 'no redirect -> 200 document' );
    ok( decode_json($body), 'body is the JSON document' );
};

# ------------------------------------------------------------------
# AgentBase.handle_request (override renders SWML via render_swml)
# ------------------------------------------------------------------
subtest 'AgentBase: 200 renders SWML' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    my ( $status, $headers, $body ) = $agent->handle_request(
        'GET', 'http://x/', { Authorization => auth_for($agent) }, undef,
    );
    is( $status, 200, 'status 200' );
    my $swml = decode_json($body);
    ok( ref $swml eq 'HASH', 'SWML document is a JSON object' );
};

subtest 'AgentBase: 401 on bad auth' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    my ( $status, $headers ) =
        $agent->handle_request( 'POST', 'http://x/', { Authorization => 'Basic bogus' }, { a => 1 } );
    is( $status, 401, 'status 401' );
    is( $headers->{'WWW-Authenticate'}, 'Basic', 'WWW-Authenticate header set' );
};

subtest 'AgentBase: routing callback (body, headers) drives 307' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(
        name                => 'agent',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    my $got_headers;
    $agent->register_routing_callback(
        sub {
            my ( $body, $headers ) = @_;
            $got_headers = $headers;
            return $body->{go} ? '/target' : undef;
        },
        '/swaig',
    );
    my ( $status, $headers, $body ) = $agent->handle_request(
        'POST', 'http://x/swaig',
        { Authorization => auth_for($agent), 'X-Id' => 'z' },
        { go => 1 },
    );
    is( $status, 307, 'status 307' );
    is( $headers->{Location}, '/target', 'Location carries the route' );
    is( $got_headers->{'X-Id'}, 'z', 'callback received headers as second arg' );
};

done_testing;
