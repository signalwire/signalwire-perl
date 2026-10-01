#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use JSON ();

# SignalWire::SWAIG::JoinConference — the typed closed sets for the four
# validated string params of FunctionResult->join_conference: BEEP
# (true/false/onEnter/onExit), RECORD (do-not-record/record-from-start),
# TRIM (trim-silence/do-not-trim), and the callback METHOD (GET/POST,
# shared by status_callback_method and recording_status_callback_method).
# The core guarantee (mirroring RecordCall / SkillName / the cross-port
# Tier-1 idiom proof): a named constant and the bare wire string produce
# the IDENTICAL join_conference action, so Python parity holds. Drives REAL
# FunctionResult->join_conference behavior and asserts on the produced SWML
# wire shape — no mocks.

use_ok('SignalWire::SWAIG::JoinConference');
use_ok('SignalWire::SWAIG::FunctionResult');

use SignalWire::SWAIG::JoinConference qw(
    BEEP_TRUE BEEP_FALSE ON_ENTER ON_EXIT
    DO_NOT_RECORD RECORD_FROM_START
    TRIM_SILENCE DO_NOT_TRIM
    GET POST
);

# Pull the join_conference payload back out of a serialized result. With
# any non-default param it is the hashref under
# action[0]/SWML/sections/main/[0]/join_conference.
sub jc_payload {
    my ($result) = @_;
    my $hash = JSON::decode_json( JSON::encode_json( $result->to_hash ) );
    return $hash->{action}[0]{SWML}{sections}{main}[0]{join_conference};
}

# ------------------------------------------------------------------
# 1. Constants ARE the canonical wire strings.
# ------------------------------------------------------------------
subtest 'constants equal wire strings' => sub {
    is( BEEP_TRUE,         'true',              'BEEP_TRUE constant' );
    is( BEEP_FALSE,        'false',             'BEEP_FALSE constant' );
    is( ON_ENTER,          'onEnter',           'ON_ENTER constant (camelCase value)' );
    is( ON_EXIT,           'onExit',            'ON_EXIT constant (camelCase value)' );
    is( DO_NOT_RECORD,     'do-not-record',     'DO_NOT_RECORD constant' );
    is( RECORD_FROM_START, 'record-from-start', 'RECORD_FROM_START constant' );
    is( TRIM_SILENCE,      'trim-silence',      'TRIM_SILENCE constant' );
    is( DO_NOT_TRIM,       'do-not-trim',       'DO_NOT_TRIM constant' );
    is( GET,               'GET',               'GET constant' );
    is( POST,              'POST',              'POST constant' );

    # Fully-qualified call form also works (constants are subs).
    is( SignalWire::SWAIG::JoinConference::ON_ENTER(), 'onEnter', 'FQ ON_ENTER() constant' );
};

# ------------------------------------------------------------------
# 2. ->beeps / ->records / ->trims / ->methods are the full closed sets,
#    matching the values join_conference actually validates against.
#    Single source of truth: probe join_conference's own `die` guards so
#    the module can't drift from the accepted sets.
# ------------------------------------------------------------------
subtest 'sets match what join_conference accepts' => sub {
    is_deeply(
        SignalWire::SWAIG::JoinConference->beeps,
        [qw(true false onEnter onExit)],
        'beeps set'
    );
    is_deeply(
        SignalWire::SWAIG::JoinConference->records,
        [ 'do-not-record', 'record-from-start' ],
        'records set'
    );
    is_deeply(
        SignalWire::SWAIG::JoinConference->trims,
        [ 'trim-silence', 'do-not-trim' ],
        'trims set'
    );
    is_deeply( SignalWire::SWAIG::JoinConference->methods, [qw(GET POST)], 'methods set' );

    # Every advertised value is ACCEPTED by join_conference (no die).
    for my $b ( @{ SignalWire::SWAIG::JoinConference->beeps } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( eval { $r->join_conference( 'c', beep => $b ); 1 },
            "join_conference accepts beep '$b'" )
            or diag($@);
    }
    for my $rec ( @{ SignalWire::SWAIG::JoinConference->records } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( eval { $r->join_conference( 'c', record => $rec ); 1 },
            "join_conference accepts record '$rec'" )
            or diag($@);
    }
    for my $t ( @{ SignalWire::SWAIG::JoinConference->trims } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( eval { $r->join_conference( 'c', trim => $t ); 1 },
            "join_conference accepts trim '$t'" )
            or diag($@);
    }
    for my $m ( @{ SignalWire::SWAIG::JoinConference->methods } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok(
            eval { $r->join_conference( 'c', status_callback_method => $m ); 1 },
            "join_conference accepts status_callback_method '$m'"
        ) or diag($@);
        my $r2 = SignalWire::SWAIG::FunctionResult->new;
        ok(
            eval { $r2->join_conference( 'c', recording_status_callback_method => $m ); 1 },
            "join_conference accepts recording_status_callback_method '$m'"
        ) or diag($@);
    }

    # Conversely, a value OUTSIDE each set is REJECTED — proving the
    # module's set is exactly join_conference's accepted set.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( !eval { $r->join_conference( 'c', beep => 'sometimes' ); 1 },
            "join_conference rejects beep 'sometimes'" );
        ok(
            !SignalWire::SWAIG::JoinConference->is_beep('sometimes'),
            "is_beep('sometimes') false — module agrees"
        );
    }
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( !eval { $r->join_conference( 'c', record => 'maybe' ); 1 },
            "join_conference rejects record 'maybe'" );
        ok(
            !SignalWire::SWAIG::JoinConference->is_record('maybe'),
            "is_record('maybe') false — module agrees"
        );
    }
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( !eval { $r->join_conference( 'c', trim => 'kinda' ); 1 },
            "join_conference rejects trim 'kinda'" );
        ok( !SignalWire::SWAIG::JoinConference->is_trim('kinda'),
            "is_trim('kinda') false — module agrees" );
    }
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( !eval { $r->join_conference( 'c', status_callback_method => 'PUT' ); 1 },
            "join_conference rejects status_callback_method 'PUT'" );
        ok( !SignalWire::SWAIG::JoinConference->is_method('PUT'),
            "is_method('PUT') false — module agrees" );
    }
};

# ------------------------------------------------------------------
# 3. is_* membership predicates.
# ------------------------------------------------------------------
subtest 'membership predicates' => sub {
    ok( SignalWire::SWAIG::JoinConference->is_beep('onExit'), 'onExit is a beep' );
    ok( SignalWire::SWAIG::JoinConference->is_beep(ON_ENTER), 'ON_ENTER constant is a beep' );
    ok( !SignalWire::SWAIG::JoinConference->is_beep('do-not-record'),
        'a record mode is not a beep' );
    ok( !SignalWire::SWAIG::JoinConference->is_beep(undef), 'undef is not a beep' );

    ok( SignalWire::SWAIG::JoinConference->is_record(RECORD_FROM_START),
        'RECORD_FROM_START constant is a record mode' );
    ok( !SignalWire::SWAIG::JoinConference->is_record('true'), 'a beep is not a record mode' );

    ok( SignalWire::SWAIG::JoinConference->is_trim(DO_NOT_TRIM), 'DO_NOT_TRIM constant is a trim' );
    ok( SignalWire::SWAIG::JoinConference->is_method(POST),      'POST constant is a method' );
    ok(
        !SignalWire::SWAIG::JoinConference->is_method('get'),
        'lowercase get is not an accepted method (case-sensitive)'
    );
    ok( !SignalWire::SWAIG::JoinConference->is_method(undef), 'undef is not a method' );
};

# ------------------------------------------------------------------
# 4. The core proof: join_conference via the named constants and via the
#    bare strings produce the IDENTICAL wire action. Exercises the real
#    join_conference -> execute_swml -> add_action path; assertion is on
#    the serialized SWML params (real behavior, no mocks).
# ------------------------------------------------------------------
subtest 'constant and string produce the identical join_conference action' => sub {
    my $by_const = SignalWire::SWAIG::FunctionResult->new;
    $by_const->join_conference(
        'lobby',
        beep                             => ON_ENTER,
        record                           => RECORD_FROM_START,
        trim                             => DO_NOT_TRIM,
        status_callback_method           => GET,
        recording_status_callback_method => POST,
    );

    my $by_str = SignalWire::SWAIG::FunctionResult->new;
    $by_str->join_conference(
        'lobby',
        beep                             => 'onEnter',
        record                           => 'record-from-start',
        trim                             => 'do-not-trim',
        status_callback_method           => 'GET',
        recording_status_callback_method => 'POST',
    );

    my $p_const = jc_payload($by_const);
    is( $p_const->{beep},   'onEnter',             'constant path serialized beep' );
    is( $p_const->{record}, 'record-from-start',   'constant path serialized record' );
    is( $p_const->{trim},   'do-not-trim',         'constant path serialized trim' );
    is( $p_const->{status_callback_method}, 'GET', 'constant path status_callback_method' );

    # Whole serialized action objects are byte-for-byte identical.
    is_deeply( $by_const->to_hash, $by_str->to_hash,
        'constant-built and string-built join_conference actions are identical' );
};

done_testing;
