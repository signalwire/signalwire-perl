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

done_testing;
