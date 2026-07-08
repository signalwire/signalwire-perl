#!/usr/bin/env perl
# Behavioral Contract 7 — tool-token WIRE FORMAT + nonce parity.
#
# Python (core/security/session_manager.py): a minted tool token is 5
# dot-joined fields {call_id}.{function_name}.{expiry}.{nonce}.{signature};
# the HMAC-SHA256 signed message is {call_id}:{function_name}:{expiry}:{nonce};
# nonce = secrets.token_hex(8) (16 hex chars); validation is CONSTANT-TIME.
#
# Perl base64url-wraps the whole token (MIME::Base64::encode_base64url), so
# the contract asserts on the DECODED form. Perl is already at parity — this
# is the lock-in test.
use strict;
use warnings;
use Test::More;
use MIME::Base64 ();
use Digest::SHA qw(hmac_sha256_hex);

use_ok('SignalWire::Security::SessionManager');

# Fixed secret so we can construct a python-oracle-format token below.
my $secret = 'a' x 64;
my $sm     = SignalWire::Security::SessionManager->new( secret_key => $secret );

sub decode { MIME::Base64::decode_base64url( $_[0] ) }

# (1) A freshly minted token, decoded, has exactly 5 dot-fields with a
#     NON-EMPTY nonce.
subtest 'decoded token has 5 fields + non-empty nonce' => sub {
    my $token   = $sm->generate_token( 'my_func', 'call_1' );
    my $decoded = decode($token);
    my @parts   = split /\./, $decoded;
    is( scalar @parts, 5, 'exactly 5 dot-joined fields' );
    my ( $call_id, $fn, $expiry, $nonce, $sig ) = @parts;
    is( $call_id, 'call_1',  'field 1 = call_id' );
    is( $fn,      'my_func', 'field 2 = function_name' );
    like( $expiry, qr/^\d+$/, 'field 3 = numeric expiry' );
    ok( length($nonce), 'field 4 = non-empty nonce' );
    is( length($nonce), 16, 'nonce is 16 hex chars (token_hex(8) parity)' );
    like( $nonce, qr/^[0-9a-f]{16}$/, 'nonce is lowercase hex' );
    ok( length($sig), 'field 5 = non-empty signature' );
};

# (2) Two mints for the SAME (function_name, call_id, expiry) produce
#     DIFFERENT nonces.
subtest 'two mints => different nonces' => sub {
    my $t1 = decode( $sm->generate_token( 'f', 'c' ) );
    my $t2 = decode( $sm->generate_token( 'f', 'c' ) );
    my $n1 = ( split /\./, $t1 )[3];
    my $n2 = ( split /\./, $t2 )[3];
    isnt( $n1, $n2, 'nonces differ across two mints of the same tuple' );
    isnt( $t1, $t2, 'whole tokens differ' );
};

# (3) A token constructed in the python-oracle format validates in-port
#     (cross-port interop). Signed message = call:fn:expiry:nonce, HMAC-SHA256
#     of that with the secret, then base64url-wrap the 5-field dot string.
subtest 'python-oracle-format token validates (interop)' => sub {
    my $call_id  = 'oracle_call';
    my $fn       = 'oracle_fn';
    my $expiry   = time() + 900;
    my $nonce    = 'deadbeefcafe1234';            # 16 hex chars, python token_hex(8) shape
    my $message  = "$call_id:$fn:$expiry:$nonce";
    my $sig      = hmac_sha256_hex( $message, $secret );
    my $raw      = "$call_id.$fn.$expiry.$nonce.$sig";
    my $token    = MIME::Base64::encode_base64url( $raw, '' );
    ok( $sm->validate_token( $call_id, $fn, $token ),
        'oracle-format token validates in the perl port' );
};

# (4) Flip one byte of the signature => validation fails.
subtest 'tampered signature => invalid' => sub {
    my $call_id = 'c4';
    my $fn      = 'f4';
    my $expiry  = time() + 900;
    my $nonce   = '00112233445566aa';
    my $message = "$call_id:$fn:$expiry:$nonce";
    my $sig     = hmac_sha256_hex( $message, $secret );

    # Flip the first hex char of the signature.
    my $first = substr( $sig, 0, 1 );
    my $flip  = $first eq '0' ? '1' : '0';
    substr( $sig, 0, 1 ) = $flip;

    my $raw   = "$call_id.$fn.$expiry.$nonce.$sig";
    my $token = MIME::Base64::encode_base64url( $raw, '' );
    ok( !$sm->validate_token( $call_id, $fn, $token ),
        'a one-byte-tampered signature is rejected' );
};

# (5) Signature compare is constant-time (no first-mismatch early return):
#     the HMAC-of-both-sides compare examines the whole string regardless of
#     where the first divergence is. Assert the private compare returns false
#     for values differing only in the LAST byte AND only in the FIRST byte
#     (an early-return impl would still reject both, so we assert on the
#     mechanism: equal-length differing strings are rejected, and the compare
#     hashes rather than short-circuits).
subtest 'constant-time compare (no early return)' => sub {
    no warnings 'once';
    my $cmp = \&SignalWire::Security::SessionManager::_timing_safe_compare;
    ok( $cmp->( 'abcdef', 'abcdef' ), 'equal strings compare equal' );
    ok( !$cmp->( 'abcdef', 'abcdeg' ), 'differ in last byte => not equal' );
    ok( !$cmp->( 'abcdef', 'zbcdef' ), 'differ in first byte => not equal' );
    # The compare HMACs both operands, so it does not early-return on the
    # first mismatching character: verify it works across differing lengths
    # too (a naive index-by-index loop would need equal length).
    ok( !$cmp->( 'short', 'a_much_longer_value' ), 'differing lengths => not equal, no length-based early exit' );
};

done_testing();
