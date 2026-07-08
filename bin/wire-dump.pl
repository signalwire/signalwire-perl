#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# wire-dump.pl — the Perl port's WIRE-CRYPTO dump program for the cross-port
# wire differ (porting-sdk/scripts/diff_port_wire.py).
#
# It runs the shared wire_crypto corpus against the Perl SDK's native security
# code (SessionManager tokens, webhook-signature validation, redact/filter
# helpers) and prints ONE JSON object mapping
#
#     case-id -> observable-artifact
#
# to stdout. The differ runs this program, canonicalizes both sides, and
# byte-compares each entry against the python oracle. Only stdout carries JSON;
# nothing else is printed there.
#
# The corpus sentinels (__ORACLE_FORMAT_TOKEN__, __TAMPERED_TOKEN__,
# __ORACLE_SIG__) are materialized here from the fixed per-case SECRET exactly
# as the oracle materializes them, so the interop/tamper cases are reproducible.
# Mirrors signalwire-go/cmd/wire-dump.
#
# Run from the signalwire-perl repo root:
#
#     perl -Ilib bin/wire-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();
use MIME::Base64 ();
use Digest::SHA qw(hmac_sha256_hex);

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::Security::SessionManager;
use SignalWire::Security::SecurityUtils qw(redact_url filter_sensitive_headers);
use SignalWire::Security::WebhookValidator qw(validate_webhook_signature);

# SECRET mirrors wire_crypto_corpus.SECRET ("a" * 64).
my $SECRET = 'a' x 64;

# Deterministic oracle constants (mirror diff_port_wire._oracle_token).
my $ORACLE_EXPIRY = 9999999999;
my $ORACLE_NONCE  = '0123456789abcdef';

# oracle_token builds a token in the SDK wire format
# (call_id.fn.expiry.nonce.sig, base64url) from the fixed SECRET.
sub oracle_token ( $call_id, $fn ) {
    my $msg = "$call_id:$fn:$ORACLE_EXPIRY:$ORACLE_NONCE";
    my $sig = hmac_sha256_hex( $msg, $SECRET );
    my $raw = "$call_id.$fn.$ORACLE_EXPIRY.$ORACLE_NONCE.$sig";
    return MIME::Base64::encode_base64url( $raw, '' );
}

# tampered_token flips the first byte of the signature (mirror _tampered_token).
sub tampered_token {
    my $tok = oracle_token( 'c', 'f' );
    my $raw = MIME::Base64::decode_base64url($tok);
    my $last = rindex( $raw, '.' );
    my $idx  = $last + 1;
    my $ch   = substr( $raw, $idx, 1 );
    substr( $raw, $idx, 1 ) = ( $ch eq 'f' ) ? 'e' : 'f';
    return MIME::Base64::encode_base64url( $raw, '' );
}

# oracle_sig computes the correct webhook signature: hex(HMAC-SHA1(key,url+body)).
sub oracle_sig ( $url, $body, $key ) {
    require Digest::SHA;
    return Digest::SHA::hmac_sha1_hex( $url . $body, $key );
}

# observe_token_fields decodes a token and returns its wire-format shape.
sub observe_token_fields ($token) {
    my $raw   = MIME::Base64::decode_base64url($token);
    my @parts = split /\./, $raw, -1;
    my $nonce = @parts > 3 ? $parts[3] : '';
    my $is_hex = ( @parts > 3 && $nonce =~ /\A[0-9a-f]*\z/ ) ? JSON::true : JSON::false;
    return {
        n_fields      => scalar(@parts),
        call_id       => ( @parts > 0 ? $parts[0] : undef ),
        function_name => ( @parts > 1 ? $parts[1] : undef ),
        nonce_len     => length($nonce),
        nonce_is_hex  => $is_hex,
    };
}

sub jbool ($v) { return $v ? JSON::true : JSON::false; }

sub main {
    my %out;

    # token_format: generate a token via the SDK, decode its fields.
    my $sm = SignalWire::Security::SessionManager->new(
        token_expiry_secs => $ORACLE_EXPIRY - int( time() ),
        secret_key        => $SECRET,
    );
    $out{token_format} = observe_token_fields( $sm->generate_token( 'my_func', 'call_1' ) );

    # token_nonce_distinct: two generations must differ (random nonce).
    my $n1 = $sm->generate_token( 'f', 'c' );
    my $n2 = $sm->generate_token( 'f', 'c' );
    $out{token_nonce_distinct} = { distinct => jbool( $n1 ne $n2 ) };

    # token_interop: validate an oracle-format token built from SECRET.
    $out{token_interop} = {
        valid => jbool(
            $sm->validate_token( 'oracle_call', 'oracle_fn', oracle_token( 'oracle_call', 'oracle_fn' ) )
        ),
    };

    # token_tamper_rejected: a one-byte-flipped signature must fail.
    $out{token_tamper_rejected} = { valid => jbool( $sm->validate_token( 'c', 'f', tampered_token() ) ) };

    # wire_validate_webhook_signature: correct HMAC-SHA1 -> valid.
    my $wh_url  = 'https://example.com/hook';
    my $wh_body = '{"event":"call.created"}';
    $out{wire_validate_webhook_signature} = {
        valid => jbool(
            validate_webhook_signature(
                $SECRET, oracle_sig( $wh_url, $wh_body, $SECRET ), $wh_url, $wh_body
            )
        ),
    };
    # wire_validate_webhook_signature_bad: wrong sig -> invalid.
    my $bad_sig = 'deadbeef' x 8;
    $out{wire_validate_webhook_signature_bad} = {
        valid => jbool( validate_webhook_signature( $SECRET, $bad_sig, $wh_url, $wh_body ) ),
    };

    # redact_url: credentials + token redacted, structure preserved.
    $out{wire_redact_url} =
        { redacted => redact_url('https://user:s3cr3t@api.signalwire.com/path?token=abc') };

    # filter_sensitive_headers: authorization + x-api-key dropped, content-type kept.
    $out{wire_filter_sensitive_headers} = {
        filtered => filter_sensitive_headers(
            { 'Authorization' => 'Bearer x', 'X-Api-Key' => 'y', 'Content-Type' => 'application/json' }
        ),
    };

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
