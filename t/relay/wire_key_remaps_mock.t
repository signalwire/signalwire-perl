#!/usr/bin/env perl
# Pin the API-name -> wire-key REMAPS at the WIRE level.
#
# The reference (signalwire-python signalwire/relay/call.py) exposes seven
# keyword parameters under one name but puts them on the RELAY wire under a
# DIFFERENT key:
#
#     :567   play()             media        -> "play"
#     :844   play_and_collect() media        -> "play"
#     :1024  pay()              input_method -> "input"
#     :1260  join_conference()  stream_obj   -> "stream"
#     :1359  bind_digit()       bind_params  -> "params"
#     :1479  ai()               ai_params    -> "params"
#     :1502  amazon_bedrock()   ai_params    -> "params"
#
# All seven are server-confirmed in mod_infrastructure/relay_apis.c
# (pay:1595 `input`; join_conference:1758 `stream`; bind_digit:1479 and
# amazon_bedrock:1982 `params`).
#
# WHY THIS FILE EXISTS. Perl reaches these keys by a different route than the
# reference does. Call.pm's verbs take a slurpy `%opts` and hand it to
# _execute / _start_action, which spread it onto the wire VERBATIM. There is no
# per-verb named parameter to re-key, so there is also nothing that can silently
# re-key it WRONG at the emitter -- but that is exactly why a construction-level
# test proves nothing here. What must be pinned is the end-to-end property that
# a caller writing the RELAY wire key reaches the wire with that key intact, and
# that the spread does not drop, rename, or swallow it.
#
# The collision hazard that made these keys unreachable in the C++ port does not
# arise in Perl: a slurpy hash has no fixed parameter names for a wire key to
# collide with, so `params => {...}` lands in $opts{params} and spreads through
# untouched. `params` is asserted on all three of its verbs below precisely
# because it is the key most likely to be eaten by a bag implementation.
#
# Every assertion below reads the key off the MOCK'S JOURNAL -- the actual
# frame the SDK put on the socket -- not off a constructed object.

use strict;
use warnings;
use Test::More;
use FindBin ();
use lib "$FindBin::Bin/../lib";
use Time::HiRes qw(sleep time);

use RelayMockTest;
use SignalWire::Relay::Client;

sub _connected_client {
    my $client = RelayMockTest::client( contexts => ['default'] );
    $client->connect;
    return $client;
}

sub _pump_until {
    my ( $client, $secs, $cb ) = @_;
    my $deadline = time() + $secs;
    while ( time() < $deadline ) {
        return 1 if $cb->();
        eval { $client->_read_once };
    }
    return $cb->() ? 1 : 0;
}

sub _answered_inbound_call {
    my ( $client, $call_id ) = @_;
    my $captured;
    $client->on_call(
        sub {
            my ($call) = @_;
            $captured = $call;
            $call->answer;
        }
    );
    RelayMockTest::inbound_call( call_id => $call_id, auto_states => ['created'] );
    _pump_until( $client, 5, sub { $captured } );
    _pump_until( $client, 1, sub { 0 } );
    $captured->state('answered');
    return $captured;
}

# Params of the single journaled frame for $method.
#
# Returns a hashref ALWAYS -- never undef -- so a caller can go on to assert
# individual keys even when nothing was journaled. Those assertions then fail
# on their own terms instead of exploding on an undef deref, which keeps a
# failure readable as "these N keys are wrong" rather than a dead test file.
sub _wire_params {
    my ( $method, $label ) = @_;
    my $entries = RelayMockTest::journal_recv( method => $method );
    is( scalar @$entries, 1, "$label: exactly one $method frame journaled" );
    return ( ref $entries eq 'ARRAY' && @$entries ) ? $entries->[0]{frame}{params} : {};
}

# Drive a verb that is EXPECTED to reach the wire, without letting a rejected
# frame take the whole test file down with it.
#
# mock_relay validates each RPC's params against the RELAY schema and answers a
# bad frame with JSON-RPC -32602. Call.pm's A2 contract turns any non-2xx result
# into a die (correctly -- a caller must see a server-side failure). Uncaught,
# that die aborts the FILE: every later subtest is skipped and the run reports
# "No tests run" instead of one precise red.
#
# That matters specifically for the mutation proof this file exists to support.
# If a wrong wire key is ever emitted, the mock rejects the frame, and an
# unguarded call would destroy the evidence of WHICH key broke. Trapping the die
# here keeps the failure local: the frame is still journaled before the server
# rejects it, so the key assertions below still run and still fail precisely.
sub _drive {
    my ( $label, $code ) = @_;
    my $ok = eval { $code->(); 1 };
    ok( $ok, "$label: verb dispatched without a server-side rejection" )
        or diag("verb died: $@");
    return $ok;
}

# ---------------------------------------------------------------------------
# 1 + 2. media -> "play"   (play, play_and_collect)
# ---------------------------------------------------------------------------

subtest 'play: media lands under wire key "play"' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'remap-play' );
    _drive( 'play',
        sub { $call->play( play => [ { type => 'tts', params => { text => 'hi' } } ] ) } );

    my $p = _wire_params( 'calling.play', 'play' );
    ok( exists $p->{play},   'wire key "play" present' );
    ok( !exists $p->{media}, 'reference-side param name "media" is NOT on the wire' );
    is( ref $p->{play},              'ARRAY', '"play" carries the media list' );
    is( $p->{play}[0]{type},         'tts',   '"play"[0].type survived the spread' );
    is( $p->{play}[0]{params}{text}, 'hi',    '"play"[0].params.text survived the spread' );

    $client->disconnect;
};

subtest 'play_and_collect: media lands under wire key "play"' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'remap-pac' );
    _drive(
        'play_and_collect',
        sub {
            $call->play_and_collect(
                play    => [ { type => 'tts', params => { text => 'Press 1' } } ],
                collect => { digits => { max => 1 } },
            );
        }
    );

    my $p = _wire_params( 'calling.play_and_collect', 'play_and_collect' );
    ok( exists $p->{play},   'wire key "play" present' );
    ok( !exists $p->{media}, 'reference-side param name "media" is NOT on the wire' );
    is( $p->{play}[0]{type},         'tts',     '"play"[0].type survived the spread' );
    is( $p->{play}[0]{params}{text}, 'Press 1', '"play"[0].params.text survived' );
    is( $p->{collect}{digits}{max},  1,         'sibling "collect" key unharmed' );

    $client->disconnect;
};

# ---------------------------------------------------------------------------
# 3. input_method -> "input"   (pay)
# ---------------------------------------------------------------------------

subtest 'pay: input method lands under wire key "input"' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'remap-pay' );
    _drive(
        'pay',
        sub {
            $call->pay(
                payment_connector_url => 'https://pay.example/connect',
                input                 => 'dtmf',
            );
        }
    );

    my $p = _wire_params( 'calling.pay', 'pay' );
    is( $p->{input}, 'dtmf', 'wire key "input" carries the value' );
    ok( !exists $p->{input_method}, 'reference-side param name "input_method" is NOT on the wire' );
    is( $p->{payment_connector_url},
        'https://pay.example/connect', 'sibling "payment_connector_url" unharmed' );

    $client->disconnect;
};

# ---------------------------------------------------------------------------
# 4. stream_obj -> "stream"   (join_conference)
# ---------------------------------------------------------------------------

subtest 'join_conference: stream object lands under wire key "stream"' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'remap-jc' );
    _drive(
        'join_conference',
        sub {
            $call->join_conference(
                name   => 'room-1',
                stream => { url => 'wss://stream.example/sock' },
            );
        }
    );

    my $p = _wire_params( 'calling.join_conference', 'join_conference' );
    is_deeply(
        $p->{stream},
        { url => 'wss://stream.example/sock' },
        'wire key "stream" carries the stream object'
    );
    ok( !exists $p->{stream_obj}, 'reference-side param name "stream_obj" is NOT on the wire' );
    is( $p->{name}, 'room-1', 'sibling "name" unharmed' );

    $client->disconnect;
};

# ---------------------------------------------------------------------------
# 5, 6, 7. bind_params / ai_params -> "params"
#
# This is the key the C++ port could not reach: a bag whose own parameter was
# named `params` swallowed it. Perl's slurpy hash has no such name, so the key
# must arrive intact -- and must NOT be confused with the RELAY envelope's own
# `params` object, which is why each assertion reads frame.params.params.
# ---------------------------------------------------------------------------

subtest 'bind_digit: bind params land under wire key "params"' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'remap-bd' );
    _drive(
        'bind_digit',
        sub {
            $call->bind_digit(
                digits      => '123',
                bind_method => 'calling.play',
                params      => { play => [ { type => 'tts', params => { text => 'bound' } } ] },
            );
        }
    );

    my $p = _wire_params( 'calling.bind_digit', 'bind_digit' );
    ok( exists $p->{params}, 'wire key "params" present inside the RPC params object' );
    is( $p->{params}{play}[0]{params}{text},
        'bound', '"params" carries the nested bind payload intact' );
    ok( !exists $p->{bind_params}, 'reference-side param name "bind_params" is NOT on the wire' );
    is( $p->{digits},      '123',          'sibling "digits" unharmed' );
    is( $p->{bind_method}, 'calling.play', 'sibling "bind_method" unharmed' );

    $client->disconnect;
};

subtest 'ai: ai params land under wire key "params"' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'remap-ai' );
    _drive(
        'ai',
        sub {
            $call->ai(
                prompt => { text        => 'You are helpful.' },
                params => { temperature => '0.7', barge_confidence => '0.5' },
            );
        }
    );

    my $p = _wire_params( 'calling.ai', 'ai' );
    ok( exists $p->{params}, 'wire key "params" present inside the RPC params object' );
    is( $p->{params}{temperature},      '0.7', '"params".temperature survived the spread' );
    is( $p->{params}{barge_confidence}, '0.5', '"params".barge_confidence survived the spread' );
    ok( !exists $p->{ai_params}, 'reference-side param name "ai_params" is NOT on the wire' );
    is_deeply( $p->{prompt}, { text => 'You are helpful.' }, 'sibling "prompt" unharmed' );

    $client->disconnect;
};

subtest 'amazon_bedrock: ai params land under wire key "params"' => sub {
    my $client = _connected_client();
    my $call   = _answered_inbound_call( $client, 'remap-bedrock' );
    _drive(
        'amazon_bedrock',
        sub {
            $call->amazon_bedrock(
                prompt => { text        => 'You are helpful.' },
                params => { temperature => '0.7' },
            );
        }
    );

    my $p = _wire_params( 'calling.amazon_bedrock', 'amazon_bedrock' );
    ok( exists $p->{params}, 'wire key "params" present inside the RPC params object' );
    is( $p->{params}{temperature}, '0.7', '"params".temperature survived the spread' );
    ok( !exists $p->{ai_params}, 'reference-side param name "ai_params" is NOT on the wire' );
    is_deeply( $p->{prompt}, { text => 'You are helpful.' }, 'sibling "prompt" unharmed' );

    # amazon_bedrock is its own RPC, not calling.ai with an engine switch.
    my $ai_frames = RelayMockTest::journal_recv( method => 'calling.ai' );
    is( scalar @$ai_frames, 0, 'amazon_bedrock did NOT route through calling.ai' );

    $client->disconnect;
};

done_testing();
