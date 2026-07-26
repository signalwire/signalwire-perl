#!/usr/bin/env perl
# A1 / PSDK-4a SECURE-DEFAULT — the secure-by-default contract and its WIRE
# manifestation.
#
# Python parity (tool_mixin.define_tool(..., secure=True); agent_base.py:1040 /
# 1096-1100):
#
#   1. define_tool WITHOUT an explicit `secure` records secure => TRUE. The SDK
#      must never silently register a tool as unauthenticated because the caller
#      omitted the flag.
#   2. `secure` is an SDK-SIDE flag, NOT a SWAIG wire key — python builds the
#      rendered function entry from an explicit field list, so `secure` never
#      reaches the wire.
#   3. The WIRE manifestation of `secure` is the per-tool `__token` appended to a
#      SECURE tool's `web_hook_url` when the SWML is rendered with an active
#      call_id. An insecure tool gets NO token. Without a call_id no token is
#      mintable (it is bound to the call), so none is emitted.
#   4. The minted token VALIDATES for (that tool, that call_id) — the token on the
#      wire is a real, checkable credential, not a placeholder.
#
# Regression lock: before this, perl's define_tool set no `secure` default, the
# render minted no token at all (`secure` was entirely inert on the wire), and a
# blanket copy of the tool definition LEAKED `"secure": 0` into the rendered SWAIG
# function as invented wire surface.

use strict;
use warnings;
use Test::More;

use SignalWire::Agent::AgentBase;

my $CALL_ID = 'call-secure-default-t100';

sub build_agent {
    my $a = SignalWire::Agent::AgentBase->new(
        name                => 'sd-agent',
        route               => '/sd',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $a->define_tool(
        name        => 'default_tool',
        description => 'no explicit secure',
        parameters  => {},
        handler     => sub { return { response => 'ok' } },
    );
    $a->define_tool(
        name        => 'insecure_tool',
        description => 'explicit secure => 0',
        parameters  => {},
        secure      => 0,
        handler     => sub { return { response => 'ok' } },
    );
    return $a;
}

# sections.main -> the `ai` verb -> SWAIG.functions, keyed by function name.
sub rendered_functions {
    my ($doc) = @_;
    my $main = eval { $doc->{sections}{main} };
    return {} unless ref $main eq 'ARRAY';
    for my $entry (@$main) {
        next unless ref $entry eq 'HASH' && ref $entry->{ai} eq 'HASH';
        my $fns = eval { $entry->{ai}{SWAIG}{functions} };
        next unless ref $fns eq 'ARRAY';
        return { map { ( $_->{function} // '' ) => $_ } grep { ref $_ eq 'HASH' } @$fns };
    }
    return {};
}

subtest 'define_tool defaults secure => TRUE; explicit secure => 0 is honored' => sub {
    my $agent = build_agent();
    ok( $agent->tools->{default_tool}{secure}, 'no explicit secure => recorded SECURE' );
    ok( !$agent->tools->{insecure_tool}{secure}, 'explicit secure => 0 => recorded INSECURE' );
};

subtest 'rendered with a call_id: __token IFF the tool is secure' => sub {
    my $agent = build_agent();
    my $fns   = rendered_functions( $agent->_render_swml_for_call( {}, $CALL_ID ) );

    ok( exists $fns->{default_tool},  'default_tool rendered' );
    ok( exists $fns->{insecure_tool}, 'insecure_tool rendered' );

    like(
        $fns->{default_tool}{web_hook_url},
        qr/[?&]__token=/,
        'SECURE tool webhook carries a per-tool __token'
    );
    unlike(
        $fns->{insecure_tool}{web_hook_url},
        qr/__token=/,
        'INSECURE tool webhook carries NO __token'
    );
};

subtest '`secure` never reaches the SWAIG wire' => sub {
    my $agent = build_agent();
    my $fns   = rendered_functions( $agent->_render_swml_for_call( {}, $CALL_ID ) );
    ok( !exists $fns->{default_tool}{secure},
        'no `secure` key on the rendered SECURE function' );
    ok( !exists $fns->{insecure_tool}{secure},
        'no `secure` key on the rendered INSECURE function' );
};

subtest 'no call_id => no token is mintable, so none is emitted' => sub {
    my $agent = build_agent();
    my $fns   = rendered_functions( $agent->render_swml( {} ) );
    unlike( $fns->{default_tool}{web_hook_url}, qr/__token=/,
        'a render without a call_id emits no __token even for a secure tool' );
};

subtest 'the __token on the wire is a token that VALIDATES' => sub {
    my $agent = build_agent();
    my $fns   = rendered_functions( $agent->_render_swml_for_call( {}, $CALL_ID ) );
    my ($token) = $fns->{default_tool}{web_hook_url} =~ /[?&]__token=([^&]+)/;
    ok( defined $token && length $token, 'extracted the __token off the wire' );
    ok(
        $agent->validate_tool_token( 'default_tool', $token, $CALL_ID ),
        'the wire token validates for (default_tool, the render call_id)'
    );
    ok(
        !$agent->validate_tool_token( 'default_tool', $token, 'some-other-call' ),
        'the wire token does NOT validate for a different call_id'
    );
};

subtest 'render_call_id is per-render state, cleared after the render' => sub {
    my $agent = build_agent();
    is( $agent->_render_call_id, undef, 'unset before any render' );
    $agent->_render_swml_for_call( {}, $CALL_ID );
    is( $agent->_render_call_id, undef, 'cleared after the render' );

    # A later plain render must NOT reuse the previous call_id's token.
    my $fns = rendered_functions( $agent->render_swml( {} ) );
    unlike( $fns->{default_tool}{web_hook_url}, qr/__token=/,
        'a stale call_id does not leak into a subsequent plain render' );
};

subtest 'the served path threads the body call_id into the render' => sub {
    my $agent = build_agent();
    my ( $status, $headers, $body ) = $agent->handle_request(
        'POST',
        'http://localhost:3000/sd',
        { Authorization => 'Basic ' . MIME::Base64::encode_base64( 'u:p', '' ) },
        { call_id => $CALL_ID },
    );
    is( $status, 200, 'served 200' );
    require JSON;
    my $fns = rendered_functions( JSON::decode_json($body) );
    like( $fns->{default_tool}{web_hook_url}, qr/[?&]__token=/,
        'the served document tokenizes the secure tool from the body call_id' );
    unlike( $fns->{insecure_tool}{web_hook_url}, qr/__token=/,
        'the served document leaves the insecure tool untokenized' );
};

subtest 'the served path accepts the nested body.call.call_id form' => sub {
    my $agent = build_agent();
    my ( $status, $headers, $body ) = $agent->handle_request(
        'POST',
        'http://localhost:3000/sd',
        { Authorization => 'Basic ' . MIME::Base64::encode_base64( 'u:p', '' ) },
        { call => { call_id => $CALL_ID } },
    );
    is( $status, 200, 'served 200' );
    require JSON;
    my $fns = rendered_functions( JSON::decode_json($body) );
    like( $fns->{default_tool}{web_hook_url}, qr/[?&]__token=/,
        'body.call.call_id is honored as the fallback (python parity)' );
};

done_testing();
