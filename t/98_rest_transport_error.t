#!/usr/bin/env perl
# Transport-error typing for the REST client (plan 1.3b).
#
# A TRANSPORT failure (connection refused / DNS failure / connection reset / TLS
# error) must surface as the SDK's TYPED transport error --
# SignalWireRestTransportError, a member of the SignalWireRestError family with
# status_code => undef -- NOT a bare HTTP::Tiny synthetic-599 SignalWireRestError
# as if the server had answered, and NOT a bare string die. This is the SDK half
# of the cross-port ERROR-ENVELOPE transport case (envelope_transport_refused).
use strict;
use warnings;
use Test::More;

use SignalWire::REST::HttpClient;
use SignalWire::REST::RestClient;
use Scalar::Util qw(blessed);
use IO::Socket::INET ();

# --- The typed transport error class ---------------------------------------
{
    my $e = SignalWireRestTransportError->new(
        body   => 'Could not connect to 127.0.0.1:1: Connection refused',
        url    => '/api/fabric/addresses',
        method => 'GET',
    );
    isa_ok( $e, 'SignalWireRestTransportError', 'transport error' );
    isa_ok( $e, 'SignalWireRestError',
        'transport error is a member of the SignalWireRestError family' );
    ok( $e->isa('SignalWire::REST::HttpClient::Error'),
        'transport error also isa the back-compat alias' );
    is( $e->status_code, undef, 'transport error status_code is undef (no HTTP status)' );
    is( $e->method, 'GET', 'transport error carries the method' );
    is( $e->url, '/api/fabric/addresses', 'transport error carries the url/path' );
    like(
        "$e",
        qr/GET .*failed to reach the server.*Connection refused/,
        'transport error stringifies as "failed to reach the server" (no bogus status)'
    );
    unlike( "$e", qr/returned/, 'transport error does NOT say "returned <status>"' );

    # §6.6: a transport error produced no response, so headers/request_id are undef.
    is( $e->headers,    undef, 'transport error headers are undef (no response)' );
    is( $e->request_id, undef, 'transport error request_id is undef' );
}

# --- §6.6 error-observability: request_id + headers on an HTTP error ---------
{
    # request_id is derived from the response headers, case-insensitively, in the
    # SignalWire/proxy preference order. Construct the error directly to prove the
    # derivation + stringification without needing a live server header.
    my $e = SignalWireRestError->new(
        status_code => 500,
        body        => { error => 'boom' },
        url         => 'http://x/api/things',
        method      => 'POST',
        headers     => { 'X-Request-Id' => 'req-abc123', 'Content-Type' => 'application/json' },
    );
    is( $e->request_id, 'req-abc123',
        '6.6: request_id is pulled from X-Request-Id (case-insensitive)' );
    is( $e->headers->{'Content-Type'}, 'application/json',
        '6.6: the full response header map is exposed' );
    like( "$e", qr/\(request-id: req-abc123\)/,
        '6.6: the request id is appended to the stringified error' );

    # Preference order: x-request-id wins over x-amzn-requestid when both present.
    my $e2 = SignalWireRestError->new(
        status_code => 502, body => 'bad gateway', url => 'http://x/y', method => 'GET',
        headers => { 'x-amzn-requestid' => 'amzn-1', 'x-request-id' => 'sw-1' },
    );
    is( $e2->request_id, 'sw-1', '6.6: x-request-id takes precedence over x-amzn-requestid' );

    # No matching header → undef request_id, no "(request-id: ...)" suffix.
    my $e3 = SignalWireRestError->new(
        status_code => 404, body => 'nope', url => 'http://x/z', method => 'GET',
        headers => { 'Content-Type' => 'text/plain' },
    );
    is( $e3->request_id, undef, '6.6: no request-id header → request_id is undef' );
    unlike( "$e3", qr/request-id/, '6.6: no request-id suffix when none present' );
}

# --- _is_transport_failure: classifies the HTTP::Tiny synthetic 599 ---------
# HTTP::Tiny returns status 599 / reason "Internal Exception" on a transport
# failure (no real server sends a 599). A genuine >= 400 from the server must NOT
# be classified as a transport failure.
{
    ok(
        SignalWire::REST::HttpClient::_is_transport_failure(
            { status => 599, reason => 'Internal Exception', content => 'refused' }
        ),
        'synthetic 599 / Internal Exception is a transport failure'
    );
    ok(
        !SignalWire::REST::HttpClient::_is_transport_failure(
            { status => 500, reason => 'Internal Server Error', content => '{}' }
        ),
        'a real 500 from the server is NOT a transport failure'
    );
    ok(
        !SignalWire::REST::HttpClient::_is_transport_failure(
            { status => 404, reason => 'Not Found', content => '{}' }
        ),
        'a real 404 is NOT a transport failure'
    );
    ok(
        !SignalWire::REST::HttpClient::_is_transport_failure(
            { status => 599, reason => 'Weird Real 599', content => '{}' }
        ),
        'a 599 that is NOT HTTP::Tiny\'s Internal Exception reason is NOT a transport failure'
    );
}

# --- End to end: a real connection-refused raises the TYPED transport error --
# Point the client at a DEAD port (bind an ephemeral port then release it, so
# nothing is listening) and issue a GET. It must raise a typed transport error,
# not a bare error and not a raw-599 SignalWireRestError with status 599.
{
    my $sock = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'tcp',
        Listen    => 1,
    ) or die "cannot bind a probe port: $!";
    my $dead = $sock->sockport;
    $sock->close;    # release it -- now nothing is listening

    my $client = SignalWire::REST::RestClient->new(
        project => 'p',
        token   => 't',
        host    => "http://127.0.0.1:$dead",
    );

    my $err;
    my $ok = eval {
        $client->_http->get('/api/fabric/addresses');
        1;
    };
    $err = $@ unless $ok;

    ok( !$ok, 'a connection-refused GET raises (does not return)' );
    ok( blessed($err), 'the raised error is an object, not a bare string die' )
        or diag("raised: $err");
    isa_ok( $err, 'SignalWireRestTransportError', 'the raised transport error' );
    isa_ok( $err, 'SignalWireRestError',
        'the raised error is caught by "catch SignalWireRestError"' );
    is( $err->status_code, undef,
        'the raised transport error has status_code undef (NOT a raw 599)' );
    isnt( "$err", '599', 'the error is not a bare 599' );
    like( "$err", qr/failed to reach the server/,
        'the raised transport error stringifies as a transport failure' );

    # D1 (owner-approved): error.url is the FULL url (scheme+host+path), not the
    # bare path — so a caught error tells you exactly which endpoint failed.
    is( $err->url, "http://127.0.0.1:$dead/api/fabric/addresses",
        'D1: transport error url is the full absolute URL (scheme+host+path)' );
}

# --- D1: an HTTP-error (>=400) error carries the FULL url INCLUDING query -----
# Drive a real 404 through the mock; the raised SignalWireRestError.url must be the
# absolute URL with the query string preserved (not the bare path).
{
    my $sock = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 0,
        Proto     => 'tcp',
        Listen    => 1,
    ) or die "cannot bind a probe port: $!";
    my $dead = $sock->sockport;
    $sock->close;

    my $client = SignalWire::REST::RestClient->new(
        project => 'p',
        token   => 't',
        host    => "http://127.0.0.1:$dead",
    );

    # Even a transport failure goes through the same url-building path; assert the
    # query is preserved in the error url (the D1 "with query" clause).
    my $err;
    eval { $client->_http->get( '/api/things', params => { page => 2, q => 'a b' } ); 1 }
        or $err = $@;
    ok( blessed($err), 'query-bearing GET raised a typed error' );
    like( $err->url, qr{^http://127\.0\.0\.1:\Q$dead\E/api/things\?},
        'D1: error url is absolute and includes the query string' );
    like( $err->url, qr/page=2/, 'D1: error url preserves the page query param' );
    like( $err->url, qr/q=a(?:%20|\+)b/, 'D1: error url preserves + encodes the q param' );
}

done_testing;
