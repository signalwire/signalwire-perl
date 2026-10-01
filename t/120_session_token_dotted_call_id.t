#!/usr/bin/env perl
# SessionManager tokens for a call_id that itself contains dots -- the composed
# conversation ids ("root.2") the AI Chat handoff mints. The other four token
# fields never contain dots, so the token is split from the RIGHT (python
# parity: session_manager.validate_token's decoded_token.rsplit(".", 4)).
use strict;
use warnings;
use Test::More;

use SignalWire::Security::SessionManager;

my $sm = SignalWire::Security::SessionManager->new( secret_key => 'k' x 32 );

for my $call_id ( 'plain', 'root.2', 'a.b.c' ) {
    my $token = $sm->generate_token( 'fn', $call_id );
    ok( $sm->validate_token( $call_id, 'fn', $token ), "round trip for call_id '$call_id'" );
    ok(
        !$sm->validate_token( "$call_id.x", 'fn', $token ),
        "another call_id is refused ('$call_id')"
    );
    ok(
        !$sm->validate_token( $call_id, 'other', $token ),
        "another function is refused ('$call_id')"
    );
}

my $root = $sm->generate_token( 'fn', 'root' );
ok( !$sm->validate_token( 'root.2', 'fn', $root ),
    'a token for "root" does not validate "root.2"' );
ok( !$sm->validate_token( 'x', 'fn', 'bm90LWEtdG9rZW4' ),
    'a token with too few fields is refused' );

done_testing;
