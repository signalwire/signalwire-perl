#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# t/70_relay_state_enums.t — the Tier-3 typed RELAY state enums:
#   SignalWire::Relay::CallState    {created,ringing,answered,ending,ended}
#   SignalWire::Relay::DialState    {dialing,answered,failed}
#   SignalWire::Relay::MessageState {queued,initiated,sent,delivered,
#                                    undelivered,failed,received}
#
# Each is a constants module (the Tier-1 SkillName/Tap/RecordCall idiom)
# whose constant values ARE the wire strings, with ->states, an is_state
# membership predicate, and an is_terminal predicate. The core guarantees:
#   - constant == wire string;
#   - membership predicates are correct AND return false (never die) on an
#     unknown/forward-compat value and on undef;
#   - is_terminal is correct (the per-vocabulary terminal set);
#   - the THREE vocabularies are NEVER conflated (CallState != DialState !=
#     MessageState — proven by the 'answered' / 'failed' cross-checks);
#   - the typed state accessor on a real Call/Message AGREES with the bare
#     string over a REAL dispatched state event (no mocks — real
#     parse_event + dispatch_event, the same path t/42 exercises).

use_ok('SignalWire::Relay::CallState');
use_ok('SignalWire::Relay::DialState');
use_ok('SignalWire::Relay::MessageState');
use_ok('SignalWire::Relay::Call');
use_ok('SignalWire::Relay::Message');
use_ok('SignalWire::Relay::Event');

# Compile-time imports so the named constants resolve as barewords (mirrors
# t/67's `use SignalWire::SWAIG::Tap qw(...)` alongside its use_ok). The
# three modules are import-namespaced with distinct constants except where
# the wire vocabularies genuinely overlap (ANSWERED, FAILED) — those are
# imported only from CallState here to avoid a redefinition; the per-module
# values are checked via the fully-qualified form in subtest 1.
use SignalWire::Relay::CallState    qw(CREATED RINGING ANSWERED ENDING ENDED);
use SignalWire::Relay::MessageState qw(QUEUED INITIATED SENT DELIVERED UNDELIVERED RECEIVED);

# DialState shares ANSWERED/FAILED with the others, so don't import its
# constants (would collide); load it at compile time so its fully-qualified
# constants resolve cleanly in subtest 1.
use SignalWire::Relay::DialState ();

# ------------------------------------------------------------------
# 1. Constants ARE the canonical wire strings.
# ------------------------------------------------------------------
subtest 'constants equal wire strings' => sub {
    is( SignalWire::Relay::CallState::CREATED(),  'created',  'CallState CREATED' );
    is( SignalWire::Relay::CallState::RINGING(),  'ringing',  'CallState RINGING' );
    is( SignalWire::Relay::CallState::ANSWERED(), 'answered', 'CallState ANSWERED' );
    is( SignalWire::Relay::CallState::ENDING(),   'ending',   'CallState ENDING' );
    is( SignalWire::Relay::CallState::ENDED(),    'ended',    'CallState ENDED' );

    is( SignalWire::Relay::DialState::DIALING(),  'dialing',  'DialState DIALING' );
    is( SignalWire::Relay::DialState::ANSWERED(), 'answered', 'DialState ANSWERED' );
    is( SignalWire::Relay::DialState::FAILED(),   'failed',   'DialState FAILED' );

    is( SignalWire::Relay::MessageState::QUEUED(),      'queued',      'MessageState QUEUED' );
    is( SignalWire::Relay::MessageState::INITIATED(),   'initiated',   'MessageState INITIATED' );
    is( SignalWire::Relay::MessageState::SENT(),        'sent',        'MessageState SENT' );
    is( SignalWire::Relay::MessageState::DELIVERED(),   'delivered',   'MessageState DELIVERED' );
    is( SignalWire::Relay::MessageState::UNDELIVERED(), 'undelivered', 'MessageState UNDELIVERED' );
    is( SignalWire::Relay::MessageState::FAILED(),      'failed',      'MessageState FAILED' );
    is( SignalWire::Relay::MessageState::RECEIVED(),    'received',    'MessageState RECEIVED' );

    # Imported bareword form is identical to the string.
    {

        package T::ImportCheck;
        use SignalWire::Relay::CallState qw(ANSWERED);
        use SignalWire::Relay::DialState ();
        Test::More::is( ANSWERED, 'answered', 'imported CallState::ANSWERED bareword' );
    }
};

# ------------------------------------------------------------------
# 2. ->states are the exact ordered closed sets.
# ------------------------------------------------------------------
subtest 'states list the full closed sets in order' => sub {
    is_deeply(
        SignalWire::Relay::CallState->states,
        [qw(created ringing answered ending ended)],
        'CallState->states'
    );
    is_deeply(
        SignalWire::Relay::DialState->states,
        [qw(dialing answered failed)],
        'DialState->states'
    );
    is_deeply(
        SignalWire::Relay::MessageState->states,
        [qw(queued initiated sent delivered undelivered failed received)],
        'MessageState->states'
    );

    # ->states returns a COPY — mutating it doesn't corrupt the module's set.
    my $s = SignalWire::Relay::CallState->states;
    push @$s, 'bogus';
    is_deeply(
        SignalWire::Relay::CallState->states,
        [qw(created ringing answered ending ended)],
        'CallState->states is a fresh copy each call'
    );
};

# ------------------------------------------------------------------
# 3. is_state membership: every listed value is a member; unknown / undef
#    are NOT — and the predicate returns false rather than dying.
# ------------------------------------------------------------------
subtest 'is_state membership + unknown/undef handling' => sub {
    for my $klass (qw(CallState DialState MessageState)) {
        my $full = "SignalWire::Relay::$klass";
        for my $st ( @{ $full->states } ) {
            ok( $full->is_state($st), "$klass is_state('$st') true" );
        }

        # Unknown value -> false, no die.
        my $unknown_ok = eval { my $r = $full->is_state('totally_made_up_state'); 1 };
        ok( $unknown_ok,                               "$klass is_state(unknown) does not die" );
        ok( !$full->is_state('totally_made_up_state'), "$klass is_state(unknown) is false" );

        # undef -> false, no die.
        my $undef_ok = eval { my $r = $full->is_state(undef); 1 };
        ok( $undef_ok,               "$klass is_state(undef) does not die" );
        ok( !$full->is_state(undef), "$klass is_state(undef) is false" );
    }
};

# ------------------------------------------------------------------
# 4. is_terminal correctness — the per-vocabulary terminal set, with
#    ended/failed (and the dial 'answered') vs the rest.
# ------------------------------------------------------------------
subtest 'is_terminal: CallState terminal = { ended }' => sub {
    ok( SignalWire::Relay::CallState->is_terminal('ended'), "'ended' is terminal" );
    for my $st (qw(created ringing answered ending)) {
        ok( !SignalWire::Relay::CallState->is_terminal($st), "'$st' is NOT terminal" );
    }
    ok(
        !SignalWire::Relay::CallState->is_terminal('made_up'),
        'unknown state is not terminal (and does not die)'
    );
    ok(
        !SignalWire::Relay::CallState->is_terminal(undef),
        'undef is not terminal (and does not die)'
    );
};

subtest 'is_terminal: DialState terminal = { answered, failed }' => sub {
    ok(
        SignalWire::Relay::DialState->is_terminal('answered'),
        "dial 'answered' is terminal (the dial succeeded)"
    );
    ok(
        SignalWire::Relay::DialState->is_terminal('failed'),
        "dial 'failed' is terminal (the dial failed)"
    );
    ok(
        !SignalWire::Relay::DialState->is_terminal('dialing'),
        "'dialing' is NOT terminal (in progress)"
    );
    ok(
        !SignalWire::Relay::DialState->is_terminal('made_up'),
        'unknown dial state is not terminal (and does not die)'
    );
};

subtest 'is_terminal: MessageState terminal = { delivered, undelivered, failed }' => sub {
    for my $st (qw(delivered undelivered failed)) {
        ok( SignalWire::Relay::MessageState->is_terminal($st), "'$st' is terminal" );
    }
    for my $st (qw(queued initiated sent received)) {
        ok( !SignalWire::Relay::MessageState->is_terminal($st), "'$st' is NOT terminal" );
    }
    ok(
        !SignalWire::Relay::MessageState->is_terminal('made_up'),
        'unknown message state is not terminal (and does not die)'
    );
};

# ------------------------------------------------------------------
# 5. THE 3-VOCABULARY GUARD: the sets are distinct and are NEVER unified.
#    'answered' is terminal for a DIAL but NON-terminal for a CALL.
#    'failed' is a Dial/Message state but NOT a Call state at all.
#    'ended' is a Call state only; 'delivered' is a Message state only.
# ------------------------------------------------------------------
subtest '3 vocabularies are distinct (answered/failed cross-checks)' => sub {

    # Same string 'answered', OPPOSITE terminality across vocabularies.
    ok( !SignalWire::Relay::CallState->is_terminal('answered'),
        "CallState: 'answered' is NON-terminal" );
    ok( SignalWire::Relay::DialState->is_terminal('answered'),
        "DialState: 'answered' IS terminal — same string, opposite terminality" );

    # 'failed' is not even a CallState.
    ok( !SignalWire::Relay::CallState->is_state('failed'),   "'failed' is NOT a CallState" );
    ok( SignalWire::Relay::DialState->is_state('failed'),    "'failed' IS a DialState" );
    ok( SignalWire::Relay::MessageState->is_state('failed'), "'failed' IS a MessageState" );

    # 'ended' is a CallState only.
    ok( SignalWire::Relay::CallState->is_state('ended'),     "'ended' IS a CallState" );
    ok( !SignalWire::Relay::DialState->is_state('ended'),    "'ended' is NOT a DialState" );
    ok( !SignalWire::Relay::MessageState->is_state('ended'), "'ended' is NOT a MessageState" );

    # 'delivered' / 'dialing' belong to exactly one vocabulary.
    ok( SignalWire::Relay::MessageState->is_state('delivered'), "'delivered' IS a MessageState" );
    ok( !SignalWire::Relay::CallState->is_state('delivered'),   "'delivered' is NOT a CallState" );
    ok( SignalWire::Relay::DialState->is_state('dialing'),      "'dialing' IS a DialState" );
    ok( !SignalWire::Relay::MessageState->is_state('dialing'),  "'dialing' is NOT a MessageState" );

    # The three ->states lists are pairwise different.
    isnt(
        join( ',', @{ SignalWire::Relay::CallState->states } ),
        join( ',', @{ SignalWire::Relay::DialState->states } ),
        'CallState and DialState are different sets'
    );
    isnt(
        join( ',', @{ SignalWire::Relay::DialState->states } ),
        join( ',', @{ SignalWire::Relay::MessageState->states } ),
        'DialState and MessageState are different sets'
    );
};

# ------------------------------------------------------------------
# 6. The typed accessor on a REAL Call AGREES with the bare string over a
#    REAL dispatched calling.call.state event. No mocks: real parse_event +
#    dispatch_event (the path the client uses), then assert state ==
#    current_state and is_terminal tracks the lifecycle.
# ------------------------------------------------------------------
subtest 'Call: typed accessor agrees with string over a real call.state flow' => sub {
    my $call = SignalWire::Relay::Call->new( call_id => 'call-state-1', node_id => 'n1' );

    # Pristine call: created, not terminal; the typed view agrees.
    is( $call->state,         'created',    'initial state string' );
    is( $call->current_state, $call->state, 'current_state agrees with state (initial)' );
    ok( !$call->is_terminal, 'fresh call is not terminal' );

    # Drive the full lifecycle through real dispatched events.
    my @lifecycle = ( [ ringing => 0 ], [ answered => 0 ], [ ending => 0 ], [ ended => 1 ], );
    for my $step (@lifecycle) {
        my ( $st, $want_terminal ) = @$step;
        my $event = SignalWire::Relay::Event->parse_event(
            'calling.call.state',
            {
                call_id    => 'call-state-1',
                call_state => $st,
            }
        );
        $call->dispatch_event($event);

        # The typed accessor returns EXACTLY the string the bare accessor does.
        is( $call->current_state, $st,          "current_state == '$st' after dispatch" );
        is( $call->current_state, $call->state, "current_state agrees with state ('$st')" );

        # is_terminal tracks the CallState terminal set across the real flow.
        is( $call->is_terminal ? 1 : 0, $want_terminal, "is_terminal == $want_terminal at '$st'" );

        # And the module predicate agrees with the instance method.
        is(
            $call->is_terminal                                        ? 1 : 0,
            SignalWire::Relay::CallState->is_terminal( $call->state ) ? 1 : 0,
            "Call->is_terminal matches CallState->is_terminal at '$st'"
        );
    }
};

# ------------------------------------------------------------------
# 7. Same, for a REAL Message over a dispatched messaging.state event.
# ------------------------------------------------------------------
subtest 'Message: typed accessor agrees with string over a real messaging.state flow' => sub {
    my $msg = SignalWire::Relay::Message->new( message_id => 'msg-state-1' );

    # Non-terminal progression: sent -> not terminal.
    my $sent = SignalWire::Relay::Event->parse_event(
        'messaging.state',
        {
            message_id    => 'msg-state-1',
            message_state => 'sent',
        }
    );
    $msg->dispatch_event($sent);
    is( $msg->state,         'sent',      'state advanced to sent' );
    is( $msg->current_state, $msg->state, 'current_state agrees with state (sent)' );
    ok( !$msg->is_terminal, "'sent' is not a terminal MessageState" );
    ok( !$msg->is_done,     'not done at non-terminal state' );

    # Terminal: delivered -> is_terminal true, and is_done flips too.
    my $delivered = SignalWire::Relay::Event->parse_event(
        'messaging.state',
        {
            message_id    => 'msg-state-1',
            message_state => 'delivered',
        }
    );
    $msg->dispatch_event($delivered);
    is( $msg->current_state, 'delivered', 'current_state == delivered after dispatch' );
    is( $msg->current_state, $msg->state, 'current_state agrees with state (delivered)' );
    ok( $msg->is_terminal, "'delivered' is a terminal MessageState" );
    is(
        $msg->is_terminal                                           ? 1 : 0,
        SignalWire::Relay::MessageState->is_terminal( $msg->state ) ? 1 : 0,
        'Message->is_terminal matches MessageState->is_terminal'
    );
    ok( $msg->is_done, 'is_done also true once the terminal state resolved the message' );
};

done_testing;
