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
}

done_testing;
