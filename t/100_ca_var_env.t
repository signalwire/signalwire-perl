#!/usr/bin/env perl
# PERL-4 / PSDK-4b (A5) CA-var contract, BEHAVIORAL proof for the REST transport.
#
# The fleet CA-var contract (hard-cut, no aliases): a custom CA bundle for each
# transport is supplied via the EXACT env var —
#   SIGNALWIRE_REST_CA_FILE   -> the REST HTTP client's TLS trust root.
#   SIGNALWIRE_RELAY_CA_FILE  -> the RELAY WS transport's TLS trust root.
#
# Proof strategy that ISOLATES SIGNALWIRE_REST_CA_FILE as the trust path:
#   * Start the HTTPS mock with the OS-default trust store (SSL_CERT_FILE) set to
#     the harness CA so the harness's own readiness probe works.
#   * For the client GET, point SSL_CERT_FILE at a NONEXISTENT file (default
#     trust store trusts nothing) and SIGNALWIRE_REST_CA_FILE at the real CA.
#     A verified GET can now succeed ONLY if the client honors
#     SIGNALWIRE_REST_CA_FILE. If the wiring is missing, the leaf is untrusted
#     and the handshake fails.
#   * Negative: SIGNALWIRE_REST_CA_FILE also wrong -> GET fails (verification is
#     genuine, not merely disabled).

use strict;
use warnings;
use Test::More;
use FindBin    ();
use File::Spec ();
use lib "$FindBin::Bin/lib";

use TlsMockTest;
use SignalWire::REST::RestClient;
use SignalWire::Relay::Client;

# trust_ca sets SSL_CERT_FILE to the harness CA (needed so the mock's own
# readiness probe crosses a verified TLS session) and returns the CA path.
my $ca = TlsMockTest::trust_ca();
plan skip_all => 'porting-sdk/test_harness/tls not adjacent (no CA)'
    unless defined $ca;

my $base = TlsMockTest::start_https_mock();
plan skip_all => 'mock_signalwire --tls not available' unless defined $base;

my $bogus_ca =
    File::Spec->catfile( ( File::Spec->splitpath($ca) )[1], 'no-such-ca.crt' );

subtest 'SIGNALWIRE_REST_CA_FILE is the REST client trust root' => sub {

    # Default trust store trusts NOTHING (points at a nonexistent file); the ONLY
    # path to trusting the mock leaf is SIGNALWIRE_REST_CA_FILE.
    local $ENV{SSL_CERT_FILE}           = $bogus_ca;
    local $ENV{SIGNALWIRE_REST_CA_FILE} = $ca;

    my $client = SignalWire::REST::RestClient->new(
        project => $TlsMockTest::PROJECT,
        token   => $TlsMockTest::TOKEN,
        host    => $base,
    );
    my $body = eval { $client->fabric->addresses->list() };
    ok( defined $body, 'verified https GET succeeded, trusting via SIGNALWIRE_REST_CA_FILE only' )
        or diag("error: $@");
    is( ref $body, 'HASH', 'JSON object body returned over TLS' );
};

subtest 'a WRONG SIGNALWIRE_REST_CA_FILE fails (verification is genuine)' => sub {
    local $ENV{SSL_CERT_FILE}           = $bogus_ca;
    local $ENV{SIGNALWIRE_REST_CA_FILE} = $bogus_ca;

    my $client = SignalWire::REST::RestClient->new(
        project => $TlsMockTest::PROJECT,
        token   => $TlsMockTest::TOKEN,
        host    => $base,
    );
    my $body = eval { $client->fabric->addresses->list() };
    ok( !defined $body || $@, 'GET fails when neither trust source trusts the leaf' );
};

# ---------------------------------------------------------------------------
# RELAY half of the SAME contract.
#
# This file's header has always declared both halves, but only the REST one was
# ever exercised. The RELAY transport's CA wiring was covered nowhere: the wss
# test (t/60_tls_wss_relay.t) trusts the harness CA via SSL_CERT_FILE, which
# proves the DEFAULT TRUST STORE path and would still pass with the
# SIGNALWIRE_RELAY_CA_FILE branch deleted outright. The static CA-VAR gate does
# not close the hole either — it cites Client.pm:117, a COMMENT inside
# _build_scheme, not the SSL_ca_file assignment that does the work, so prose
# alone satisfies it.
#
# Same isolation as the REST subtests above: point the default trust store at a
# nonexistent file so it trusts NOTHING, leaving SIGNALWIRE_RELAY_CA_FILE as the
# only possible path to trusting the mock's leaf.
# ---------------------------------------------------------------------------

my $ws_base = TlsMockTest::start_wss_mock();

SKIP: {
    skip 'mock_relay --tls not available', 2 unless defined $ws_base;

    subtest 'SIGNALWIRE_RELAY_CA_FILE is the RELAY transport trust root' => sub {
        local $ENV{SSL_CERT_FILE}            = $bogus_ca;
        local $ENV{SIGNALWIRE_RELAY_CA_FILE} = $ca;

        my $client = SignalWire::Relay::Client->new(
            project  => $TlsMockTest::PROJECT,
            token    => $TlsMockTest::TOKEN,
            host     => "$TlsMockTest::HOST:$TlsMockTest::WSS_PORT",
            contexts => ['default'],
        );
        is( $client->scheme, 'wss', 'a configured RELAY CA selects the wss scheme' );

        my $ok = eval { $client->connect; 1 };
        ok( $ok && $client->connected,
            'wss handshake succeeded, trusting via SIGNALWIRE_RELAY_CA_FILE only' )
            or diag( "error: " . ( $@ // '' ) );

        # The mock issues a protocol string only after a completed credential
        # exchange, so a value here means the round-trip crossed a genuinely
        # verified TLS session rather than a short-circuited one.
        like( $client->relay_protocol, qr/^signalwire_/,
            'server-issued protocol string returned over the CA-var-trusted wss session' );

        $client->disconnect;
    };

    subtest 'a WRONG SIGNALWIRE_RELAY_CA_FILE fails (verification is genuine)' => sub {
        local $ENV{SSL_CERT_FILE}            = $bogus_ca;
        local $ENV{SIGNALWIRE_RELAY_CA_FILE} = $bogus_ca;

        my $client = SignalWire::Relay::Client->new(
            project  => $TlsMockTest::PROJECT,
            token    => $TlsMockTest::TOKEN,
            host     => "$TlsMockTest::HOST:$TlsMockTest::WSS_PORT",
            contexts => ['default'],
        );

        my $ok = eval { $client->connect; 1 };
        ok( !$ok || !$client->connected,
            'wss handshake fails when neither trust source trusts the leaf' );
    };
}

done_testing;
