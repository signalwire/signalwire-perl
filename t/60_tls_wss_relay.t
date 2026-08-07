#!/usr/bin/env perl
# TLS capability test #1 (WSS RELAY client).
#
# One of the three cross-port "every SDK does verified HTTPS + WSS" quadrants
# (template: signalwire-go commit b6b2b6d, TestTLS_RelayClient_WSS). Spawns the
# shared mock_relay in --tls mode so the WebSocket plane is wss:// backed by the
# porting-sdk self-signed test CA, points the real SignalWire::Relay::Client at
# wss://127.0.0.1:<port>, trusts the test CA via SSL_CERT_FILE, and drives the
# full connect + authenticate handshake.
#
# CA trust is wired idiomatically: SSL_CERT_FILE -> certs/ca.crt. The relay
# client's wss path uses IO::Socket::SSL with SSL_VERIFY_PEER and NO explicit
# CA, so it consults the default trust store, which honors SSL_CERT_FILE. No
# SSL_VERIFY_NONE, no transport mock: the server-issued protocol string can only
# come back over a genuinely-completed, CA-verified TLS session.
#
# A negative subtest dials the same wss:// endpoint with an EMPTY trust store
# (SSL_ca_path => a dir with no certs, SSL_verify_mode => PEER) and asserts the
# handshake is rejected, proving the cert is actually verified.

use strict;
use warnings;
use Test::More;
use FindBin ();
use lib "$FindBin::Bin/lib";

use TlsMockTest;
use SignalWire::Relay::Client;

# Trust the harness CA before any TLS handshake in this process.
my $ca = TlsMockTest::trust_ca();
plan skip_all => 'porting-sdk/test_harness/tls not adjacent (no CA)' unless defined $ca;

my $http_base = TlsMockTest::start_wss_mock();
plan skip_all => 'mock_relay --tls not available' unless defined $http_base;

# ---------------------------------------------------------------------------
# Real wss:// connect + authenticate against the --tls mock.
# ---------------------------------------------------------------------------

subtest 'relay client connects + authenticates over wss://' => sub {
    TlsMockTest::wss_journal_reset();

    my $client = SignalWire::Relay::Client->new(
        project  => $TlsMockTest::PROJECT,
        token    => $TlsMockTest::TOKEN,
        host     => "$TlsMockTest::HOST:$TlsMockTest::WSS_PORT",
        contexts => ['default'],
    );

    my $result = eval { $client->connect };
    ok( !$@,                'connect() over wss:// did not die' ) or diag $@;
    ok( $client->connected, 'client reports connected after wss handshake' );

    # Behavioral proof: the mock only issues a protocol string on a successful
    # credential exchange. A value here means the connect round-trip completed
    # end-to-end over the verified TLS session.
    like( $client->relay_protocol, qr/^signalwire_/,
        'server-issued protocol string returned over wss://' );

    # Wire proof: the mock journaled the inbound signalwire.connect frame on
    # the same (TLS) WebSocket. The journal is read over the plain-HTTP control
    # plane (mock_relay keeps the control plane HTTP even in --tls).
    ok( TlsMockTest::wss_saw_recv('signalwire.connect'),
        'mock journaled a recv signalwire.connect frame over the wss connection' );

    $client->disconnect;
};

# ---------------------------------------------------------------------------
# Negative control: a client that does NOT trust the CA must be rejected.
# ---------------------------------------------------------------------------

subtest 'untrusted client is rejected (real verification in force)' => sub {
    require IO::Socket::SSL;
    require File::Temp;

    # An empty CA directory => no trust anchors. SSL_VERIFY_PEER forces the
    # leaf to chain to a trusted root, which it cannot here.
    my $empty_dir = File::Temp->newdir();

    my $sock = IO::Socket::SSL->new(
        PeerHost        => $TlsMockTest::HOST,
        PeerPort        => $TlsMockTest::WSS_PORT,
        SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_PEER(),
        SSL_ca_path     => "$empty_dir",                         # empty -> no trusted roots
        SSL_ca_file     => undef,
        Timeout         => 5,
    );

    ok( !$sock, 'TLS handshake to wss endpoint rejected with empty trust store' )
        or do { diag "unexpectedly connected"; $sock->close if $sock };
    note( "untrusted wss handshake correctly rejected: "
            . ( $IO::Socket::SSL::SSL_ERROR // $! // 'verify failure' ) );
};

done_testing();
