#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON         qw(decode_json);
use MIME::Base64 qw(encode_base64);

# =============================================================================
# Behavioral contract #5 — Serverless per-platform DISPATCH (not detection-only,
# not Lambda-only).
#
# Python (serverless_mixin.py): handle_serverless_request dispatches by platform
# — lambda, cgi, google_cloud_function, azure_function — each producing a real
# (status/headers/body)-shaped response. php is the reference (Lambda / GCF /
# Azure / CGI).
#
# For EACH of lambda + cgi + gcf + azure we feed a synthetic platform event/env
# and assert the agent DISPATCHES it to a real response (a 200 + the health
# document), NOT a fall-through to serve() / an empty handler / unsupported.
# =============================================================================

use SignalWire::Agent::AgentBase;

sub new_agent {
    return SignalWire::Agent::AgentBase->new(
        name                => 'svc',
        route               => '/svc',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
}

subtest 'lambda: direct dispatch -> Lambda-proxy response' => sub {

    # Python parity (serverless_mixin.py, mode "lambda"): the event is
    # dispatched DIRECTLY — Basic-auth gate, then a root event renders the SWML
    # document as a {statusCode,headers,body} Lambda-proxy response. Lambda does
    # NOT proxy through the PSGI app, so /health is a framework route, not a
    # lambda one.
    my $auth = 'Basic ' . encode_base64( 'u:p', '' );
    my $resp = new_agent()->handle_serverless_request(
        mode  => 'lambda',
        event => { rawPath => '/', headers => { authorization => $auth } },
    );
    is( ref $resp,            'HASH', 'lambda response is a hashref' );
    is( $resp->{statusCode},  200,    'lambda root statusCode 200' );
    is( ref $resp->{headers}, 'HASH', 'headers folded to a hashref' );
    my $doc = eval { decode_json( $resp->{body} ) };
    is( ref $doc, 'HASH', 'root event renders the SWML document' );

    # No Authorization header -> 401 auth challenge.
    my $noauth = new_agent()->handle_serverless_request(
        mode  => 'lambda',
        event => { rawPath => '/', headers => {} },
    );
    is( $noauth->{statusCode}, 401, 'lambda without auth -> 401 challenge' );
};

subtest 'cgi: PATH_INFO env -> rendered body' => sub {
    local $ENV{PATH_INFO}      = '/health';
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = '';
    local $ENV{CONTENT_LENGTH} = 0;

    my $body = new_agent()->handle_serverless_request( mode => 'cgi' );
    ok( defined $body && !ref $body, 'cgi returns a scalar body string' );
    my $doc = eval { decode_json($body) };
    is( $doc->{status}, 'healthy', 'cgi dispatched to the health document' );
};

subtest 'gcf: google_cloud_function event -> {status,headers,body}' => sub {
    for my $mode ( 'google_cloud_function', 'gcf' ) {
        my $resp = new_agent()->handle_serverless_request(
            mode  => $mode,
            event => { path => '/health', method => 'GET' },
        );
        is( ref $resp,            'HASH', "$mode response is a hashref" );
        is( $resp->{status},      200,    "$mode status 200" );
        is( ref $resp->{headers}, 'HASH', "$mode headers hashref" );
        my $doc = eval { decode_json( $resp->{body} ) };
        is( $doc->{status}, 'healthy', "$mode dispatched to the health document" );
    }
};

subtest 'azure: azure_function event (URL) -> {status,headers,body}' => sub {
    for my $mode ( 'azure_function', 'azure' ) {
        my $resp = new_agent()->handle_serverless_request(
            mode  => $mode,
            event => {
                url    => 'https://app.azurewebsites.net/health?x=1',
                method => 'GET',
            },
        );
        is( ref $resp,            'HASH', "$mode response is a hashref" );
        is( $resp->{status},      200,    "$mode status 200" );
        is( ref $resp->{headers}, 'HASH', "$mode headers hashref" );
        my $doc = eval { decode_json( $resp->{body} ) };
        is( $doc->{status}, 'healthy', "$mode dispatched (path parsed out of the URL)" );
    }
};

done_testing;
