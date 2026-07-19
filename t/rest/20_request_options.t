#!/usr/bin/env perl
# RequestOptions envelope -- behavioral contract over the real mock (plan 4.2).
#
# Translated from signalwire-python/tests/unit/rest/test_request_options.py.
# These drive a real RestClient through the real HTTP::Tiny transport into the
# shared mock_signalwire and assert on the recorded journal -- the same journal
# the REST-COVERAGE gate reads. Retry / timeout are wire-observable: the mock
# sees N attempts and honors the backoff ordering, so the contract is proven
# over the real mock, NOT a transport mock.
#
# Contract pinned here (the oracle):
#   - retries: a retryable failure is retried up to `retries` extra times; the
#     mock sees retries + 1 attempts; the final success is returned.
#   - idempotency asymmetry: GET/PUT/DELETE retry on the full retry_on_status
#     set; POST/PATCH retry only on 429/503 (throttles), never 500/502/504.
#   - timeout: a server-side delay exceeding the timeout raises the transport
#     error family.
#   - abort_signal: set before a request raises the transport error family.
#   - per-request options shallow-override the client default.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Scalar::Util qw(blessed);

use MockTest;
use SignalWire::REST::RequestOptions;

my $ADDRESSES_ENDPOINT = 'fabric.list_fabric_addresses';
my $ADDRESSES_PATH     = '/api/fabric/addresses';
my $CREATE_ENDPOINT    = 'relay-rest.create_address';
my $CREATE_PATH        = '/api/relay/rest/addresses';

# Arm the FULL scenario JSON (status / response / headers? / delay_ms?) --
# MockTest::scenario_set only forwards {status,response}; the timeout case needs
# delay_ms passed through, so post the control-plane frame directly (auth-scoped
# like scenario_set).
sub arm_full {
    my ( $endpoint, $scenario ) = @_;
    my $q = MockTest::_scope_query();
    my $payload = JSON::encode_json($scenario);
    my $resp = MockTest::_ua()->post(
        "$MockTest::BASE_URL/__mock__/scenarios/$endpoint$q",
        { content => $payload, headers => { 'Content-Type' => 'application/json' } },
    );
    die "arm_full failed: $resp->{status} - $resp->{content}" unless $resp->{success};
    return;
}

# Count this client's journal entries matching (method, path). The mock journal
# is scoped per-process (per auth), NOT per-subtest, and MockTest::journal_reset
# is a no-op while a project is active -- so a raw count accumulates across
# subtests. Every assertion therefore measures a DELTA: snapshot the count before
# the call under test, then assert how many NEW entries it produced.
sub count_hits {
    my ( $method, $path ) = @_;
    my $entries = MockTest::journal_all();
    return scalar grep {
        ( $_->{method} // '' ) eq $method && ( $_->{path} // '' ) eq $path
    } @$entries;
}

# ---- Retry contract: a retryable failure is retried ----------------------
subtest 'TestRetryContract' => sub {
    subtest 'test_get_retries_503_then_succeeds' => sub {
        my $client = MockTest::client();
        # Arm a single 503; the default synthesized 200 follows it. retries=1
        # retries the 503 into the 200 => 2 attempts.
        my $before = count_hits( 'GET', $ADDRESSES_PATH );
        MockTest::scenario_set( $ADDRESSES_ENDPOINT, 503, { errors => [ { code => 'X' } ] } );
        my $result = $client->_http->get( $ADDRESSES_PATH,
            request_options =>
                SignalWire::REST::RequestOptions->new( retries => 1, retry_backoff => 0 ) );
        ok( defined $result, 'retry-into-200 returned a body' );
        is( count_hits( 'GET', $ADDRESSES_PATH ) - $before, 2,
            'expected 2 attempts (503 then 200)' );
    };

    subtest 'test_no_retries_by_default_raises_on_first_failure' => sub {
        my $client = MockTest::client();
        my $before = count_hits( 'GET', $ADDRESSES_PATH );
        MockTest::scenario_set( $ADDRESSES_ENDPOINT, 503, { errors => [ { code => 'X' } ] } );
        my $err;
        my $ok = eval { $client->_http->get($ADDRESSES_PATH); 1 };
        $err = $@ unless $ok;
        ok( !$ok, 'default (retries 0) raises on the first failure' );
        isa_ok( $err, 'SignalWireRestError', 'raised typed error' );
        is( $err->status_code, 503, 'status is 503' );
        is( count_hits( 'GET', $ADDRESSES_PATH ) - $before, 1, 'default must not retry' );
    };

    subtest 'test_retries_exhausted_raises_last_error' => sub {
        my $client = MockTest::client();
        # Two 503s + retries=1 => 2 attempts, both 503 => raise the 503.
        my $before = count_hits( 'GET', $ADDRESSES_PATH );
        MockTest::scenario_set( $ADDRESSES_ENDPOINT, 503, { errors => [ { code => 'X' } ] } );
        MockTest::scenario_set( $ADDRESSES_ENDPOINT, 503, { errors => [ { code => 'X' } ] } );
        my $err;
        my $ok = eval {
            $client->_http->get( $ADDRESSES_PATH,
                request_options =>
                    SignalWire::REST::RequestOptions->new( retries => 1, retry_backoff => 0 ) );
            1;
        };
        $err = $@ unless $ok;
        ok( !$ok, 'exhausted retries raises' );
        isa_ok( $err, 'SignalWireRestError', 'raised typed error' );
        is( $err->status_code, 503, 'status is 503' );
        is( count_hits( 'GET', $ADDRESSES_PATH ) - $before, 2,
            'retries=1 => exactly 2 attempts' );
    };
};

# ---- Idempotency asymmetry: POST/PATCH don't blindly retry 500 -----------
subtest 'TestIdempotencyAsymmetry' => sub {
    subtest 'test_post_does_not_retry_500' => sub {
        my $client = MockTest::client();
        # 500 is NOT retryable for a non-idempotent method even with retries armed.
        my $before = count_hits( 'POST', $CREATE_PATH );
        MockTest::scenario_set( $CREATE_ENDPOINT, 500, { error => 'x' } );
        my $err;
        my $ok = eval {
            $client->_http->post( $CREATE_PATH,
                body => { label => 'x' },
                request_options =>
                    SignalWire::REST::RequestOptions->new( retries => 2, retry_backoff => 0 ) );
            1;
        };
        $err = $@ unless $ok;
        ok( !$ok, 'POST 500 raises' );
        isa_ok( $err, 'SignalWireRestError', 'raised typed error' );
        is( $err->status_code, 500, 'status is 500' );
        is( count_hits( 'POST', $CREATE_PATH ) - $before, 1,
            'POST must not retry a 500 (side-effect safety)' );
    };

    subtest 'test_post_does_retry_503' => sub {
        my $client = MockTest::client();
        # 503 (throttle) IS retryable even for a non-idempotent method.
        my $before = count_hits( 'POST', $CREATE_PATH );
        MockTest::scenario_set( $CREATE_ENDPOINT, 503, { error => 'x' } );
        $client->_http->post( $CREATE_PATH,
            body => { label => 'x' },
            request_options =>
                SignalWire::REST::RequestOptions->new( retries => 1, retry_backoff => 0 ) );
        is( count_hits( 'POST', $CREATE_PATH ) - $before, 2,
            'POST retries a 503 throttle (safe): 503 then 200' );
    };
};

# ---- Timeout: a slow response exceeding the timeout raises transport error --
subtest 'TestTimeout' => sub {
    subtest 'test_slow_response_times_out' => sub {
        my $client = MockTest::client();
        # Arm a 200 delayed 400ms; a 100ms timeout must fire => transport error.
        arm_full( $ADDRESSES_ENDPOINT,
            { status => 200, response => { data => [], links => {} }, delay_ms => 400 } );
        my $err;
        my $ok = eval {
            $client->_http->get( $ADDRESSES_PATH,
                request_options => SignalWire::REST::RequestOptions->new( timeout => 0.1 ) );
            1;
        };
        $err = $@ unless $ok;
        ok( !$ok, 'a timeout raises' );
        isa_ok( $err, 'SignalWireRestTransportError', 'raised transport error' );
    };
};

# ---- AbortSignal: a set signal raises before the request goes out --------
subtest 'TestAbortSignal' => sub {
    subtest 'test_preset_abort_raises_transport_error' => sub {
        my $client = MockTest::client();
        # A coderef returning true is a set signal (Perl's cooperative-cancel idiom).
        my $signal = sub { 1 };
        my $before = count_hits( 'GET', $ADDRESSES_PATH );
        my $err;
        my $ok = eval {
            $client->_http->get( $ADDRESSES_PATH,
                request_options =>
                    SignalWire::REST::RequestOptions->new( abort_signal => $signal ) );
            1;
        };
        $err = $@ unless $ok;
        ok( !$ok, 'a set abort_signal raises' );
        isa_ok( $err, 'SignalWireRestTransportError', 'raised transport error' );
        is( count_hits( 'GET', $ADDRESSES_PATH ) - $before, 0,
            'aborted request must not reach the server' );
    };
};

# ---- Per-request override shallow-overrides the client default -----------
subtest 'TestPerRequestOverride' => sub {
    subtest 'test_per_request_retries_override_client_default' => sub {
        # Client default = no retries (the built-in default when request_options is
        # unset); per-request opts in to 1 retry. Uses MockTest::client() so the
        # shared mock is ensured up the same way the other subtests do.
        my $client = MockTest::client();
        MockTest::scenario_set( $ADDRESSES_ENDPOINT, 503, { errors => [ { code => 'X' } ] } );
        my $result = $client->_http->get( $ADDRESSES_PATH,
            request_options =>
                SignalWire::REST::RequestOptions->new( retries => 1, retry_backoff => 0 ) );
        ok( defined $result, 'per-request retries override the client default (retried into 200)' );
    };

    subtest 'test_client_default_retries_applied' => sub {
        # A client-default request_options (retries=1) is applied to a plain call
        # with no per-request override. Ensure the shared mock first via client(),
        # then build a client carrying the default and point it at the same host.
        MockTest::client();    # ensure the singleton mock is up
        my $client = SignalWire::REST::RestClient->new(
            project         => $MockTest::PROJECT,
            token           => $MockTest::TOKEN,
            host            => $MockTest::BASE_URL,
            request_options =>
                SignalWire::REST::RequestOptions->new( retries => 1, retry_backoff => 0 ),
        );
        MockTest::scenario_set( $ADDRESSES_ENDPOINT, 503, { errors => [ { code => 'X' } ] } );
        my $result = $client->_http->get($ADDRESSES_PATH);
        ok( defined $result,
            'client-default retries retried the 503 into the 200 (no per-request opts)' );
    };

    subtest 'test_merge_is_shallow' => sub {
        # Unit-level: merge applies only the set fields of the override.
        my $base = SignalWire::REST::RequestOptions->new( retries => 5, timeout => 12 );
        my $merged = $base->merge(
            SignalWire::REST::RequestOptions->new( retries => 1 ) );
        is( $merged->retries, 1, 'override retries wins' );
        is( $merged->timeout, 12, 'unset override field keeps the base value' );
        is( $base->retries, 5, 'merge does not mutate the base' );
        my $noop = $base->merge(undef);
        is( $noop->retries, 5, 'merge(undef) returns self unchanged' );
    };
};

done_testing;
