#!/usr/bin/env perl
# TLS capability test #2 (HTTPS REST client).
#
# One of the three cross-port "every SDK does verified HTTPS + WSS" quadrants
# (template: signalwire-go commit b6b2b6d, TestTLS_RestClient_HTTPS). Spawns the
# shared mock_signalwire in --tls mode (HTTPS, whole app, backed by the
# porting-sdk self-signed test CA), points a real SignalWire::REST::RestClient
# at https://127.0.0.1:<port>, trusts the test CA via SSL_CERT_FILE, and
# performs a real GET, asserting a JSON response.
#
# CA trust is wired idiomatically: SSL_CERT_FILE -> certs/ca.crt. The REST
# client's HTTP::Tiny user-agent uses verify_SSL => 1 (matching the Python
# reference, which verifies by default), and HTTP::Tiny / IO::Socket::SSL honor
# SSL_CERT_FILE as the trust store. No SSL_VERIFY_NONE, no transport mock.
#
# A negative subtest issues the same GET with verify_SSL => 1 but an EMPTY trust
# store and asserts it fails, proving the cert is genuinely verified.

use strict;
use warnings;
use Test::More;
use FindBin ();
use lib "$FindBin::Bin/lib";

use TlsMockTest;
use SignalWire::REST::RestClient;

# Trust the harness CA before any TLS request in this process.
my $ca = TlsMockTest::trust_ca();
plan skip_all => 'porting-sdk/test_harness/tls not adjacent (no CA)' unless defined $ca;

my $base = TlsMockTest::start_https_mock();
plan skip_all => 'mock_signalwire --tls not available' unless defined $base;

# ---------------------------------------------------------------------------
# Real https:// GET through the SDK REST client.
# ---------------------------------------------------------------------------

subtest 'REST client performs a verified https:// GET' => sub {
    # RestClient accepts a fully-qualified host; the HttpClient uses it verbatim
    # when it already carries a scheme, so this drives the real client over TLS.
    my $client = SignalWire::REST::RestClient->new(
        project => $TlsMockTest::PROJECT,
        token   => $TlsMockTest::TOKEN,
        host    => $base,                  # https://127.0.0.1:<port>
    );

    # GET a spec-backed collection endpoint over HTTPS. A JSON response with a
    # 'data' array can only come back over a completed, CA-verified TLS session.
    my $body = eval { $client->fabric->addresses->list() };
    ok(!$@, 'fabric.addresses.list() over https:// did not die') or diag $@;
    is(ref $body, 'HASH', 'response is a hashref');
    ok(exists $body->{data}, "response has a 'data' key")
        or diag 'keys: ' . join(',', sort keys %{ $body || {} });

    # Wire proof: the mock journaled the GET on its (HTTPS) control plane.
    my $last = TlsMockTest::https_journal_last();
    is($last->{method}, 'GET', 'mock recorded a GET over HTTPS');
    is($last->{path}, '/api/fabric/addresses', 'recorded path matches the GET');
};

# ---------------------------------------------------------------------------
# Negative control: verify_SSL => 1 with no CA trust must be rejected.
# ---------------------------------------------------------------------------

subtest 'untrusted client is rejected (real verification in force)' => sub {
    require HTTP::Tiny;

    # Point SSL_CERT_FILE at an empty trust source so there is no anchor for the
    # leaf. verify_SSL => 1 then forces a chain that cannot be built.
    local $ENV{SSL_CERT_FILE} = '/dev/null';
    my $ua = HTTP::Tiny->new(timeout => 5, verify_SSL => 1);
    my $resp = $ua->get("$base/__mock__/health");

    ok(!$resp->{success}, 'HTTPS GET with empty trust store was rejected')
        or diag "unexpectedly succeeded: status=$resp->{status}";
    note("untrusted https GET correctly rejected: status=$resp->{status} "
         . "reason=" . ($resp->{reason} // ''));
};

done_testing();
