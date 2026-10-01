#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# SignalWire::SWAIG::RecordCall — the typed closed sets for the two
# validated string params of FunctionResult->record_call: the recording
# FORMAT (wav/mp3) and the record DIRECTION (speak/listen/both). The core
# guarantee (mirroring SkillName / the cross-port Tier-1 idiom proof): a
# named constant and the bare wire string produce the IDENTICAL record_call
# action, so Python parity holds. Drives REAL FunctionResult->record_call
# behavior and asserts on the produced SWML wire shape — no mocks.

use_ok('SignalWire::SWAIG::RecordCall');
use_ok('SignalWire::SWAIG::FunctionResult');

use SignalWire::SWAIG::RecordCall qw(WAV MP3 MP4 SPEAK LISTEN BOTH);

# Pull the record_call params back out of a FunctionResult's serialized
# action list (record_call -> add_action('SWML', ...) under
# sections/main/[0]/record_call).
sub record_params {
    my ($result) = @_;
    my $hash = $result->to_hash;
    return $hash->{action}[0]{SWML}{sections}{main}[0]{record_call};
}

# ------------------------------------------------------------------
# 1. Constants ARE the canonical wire strings.
# ------------------------------------------------------------------
subtest 'constants equal wire strings' => sub {
    is( WAV,    'wav',    'WAV constant' );
    is( MP3,    'mp3',    'MP3 constant' );
    is( SPEAK,  'speak',  'SPEAK constant' );
    is( LISTEN, 'listen', 'LISTEN constant' );
    is( BOTH,   'both',   'BOTH constant' );

    # Fully-qualified call form also works (constants are subs).
    is( SignalWire::SWAIG::RecordCall::MP3(), 'mp3', 'FQ MP3() constant' );
};

# ------------------------------------------------------------------
# 2. ->formats / ->directions are the full closed sets, matching the
#    values record_call actually validates against. Single source of
#    truth: probe record_call's own `die` guards so the module can't
#    drift from the accepted sets.
# ------------------------------------------------------------------
subtest 'formats/directions match what record_call accepts' => sub {
    is_deeply( SignalWire::SWAIG::RecordCall->formats,
        [qw(wav mp3 mp4)], 'formats lists wav, mp3, mp4' );
    is_deeply( SignalWire::SWAIG::RecordCall->directions,
        [qw(speak listen both)], 'directions lists speak, listen, both' );

    # Every advertised format is ACCEPTED by record_call (no die).
    for my $fmt ( @{ SignalWire::SWAIG::RecordCall->formats } ) {
        my $r  = SignalWire::SWAIG::FunctionResult->new;
        my $ok = eval { $r->record_call( format => $fmt ); 1 };
        ok( $ok, "record_call accepts format '$fmt'" ) or diag($@);
    }

    # Every advertised direction is ACCEPTED by record_call.
    for my $dir ( @{ SignalWire::SWAIG::RecordCall->directions } ) {
        my $r  = SignalWire::SWAIG::FunctionResult->new;
        my $ok = eval { $r->record_call( direction => $dir ); 1 };
        ok( $ok, "record_call accepts direction '$dir'" ) or diag($@);
    }

    # Conversely, a value OUTSIDE each set is REJECTED — proving the
    # module's set is exactly record_call's accepted set, not a superset.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok(
            !eval { $r->record_call( format => 'ogg' ); 1 },
            "record_call rejects format 'ogg' (outside the set)"
        );
        ok(
            !SignalWire::SWAIG::RecordCall->is_format('ogg'),
            "is_format('ogg') false — module agrees"
        );
    }
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok(
            !eval { $r->record_call( direction => 'sideways' ); 1 },
            "record_call rejects direction 'sideways' (outside the set)"
        );
        ok(
            !SignalWire::SWAIG::RecordCall->is_direction('sideways'),
            "is_direction('sideways') false — module agrees"
        );
    }
};

# ------------------------------------------------------------------
# 3. is_format / is_direction membership.
# ------------------------------------------------------------------
subtest 'membership predicates' => sub {
    ok( SignalWire::SWAIG::RecordCall->is_format('wav'),   'wav is a format' );
    ok( SignalWire::SWAIG::RecordCall->is_format(MP3),     'MP3 constant is a format' );
    ok( !SignalWire::SWAIG::RecordCall->is_format('both'), 'a direction is not a format' );
    ok( !SignalWire::SWAIG::RecordCall->is_format(undef),  'undef is not a format' );

    ok( SignalWire::SWAIG::RecordCall->is_direction('both'), 'both is a direction' );
    ok( SignalWire::SWAIG::RecordCall->is_direction(SPEAK),  'SPEAK constant is a direction' );
    ok( !SignalWire::SWAIG::RecordCall->is_direction('wav'), 'a format is not a direction' );
    ok( !SignalWire::SWAIG::RecordCall->is_direction(undef), 'undef is not a direction' );
};

# ------------------------------------------------------------------
# 4. The core proof: record_call via the named constants and via the bare
#    strings produce the IDENTICAL wire action. Exercises the real
#    record_call -> execute_swml -> add_action path; assertion is on the
#    serialized SWML params (real behavior, no mocks).
# ------------------------------------------------------------------
subtest 'constant and string produce the identical record_call action' => sub {
    my $by_const = SignalWire::SWAIG::FunctionResult->new;
    $by_const->record_call( format => MP3, direction => BOTH );

    my $by_str = SignalWire::SWAIG::FunctionResult->new;
    $by_str->record_call( format => 'mp3', direction => 'both' );

    my $p_const = record_params($by_const);
    my $p_str   = record_params($by_str);

    is( $p_const->{format},    'mp3',  'constant path serialized format => mp3' );
    is( $p_const->{direction}, 'both', 'constant path serialized direction => both' );

    # Whole serialized action objects are byte-for-byte identical.
    is_deeply( $by_const->to_hash, $by_str->to_hash,
        'constant-built and string-built record_call actions are identical' );

    # And every advertised value round-trips onto the wire unchanged when
    # passed as the constant.
    my %fmt_const = ( wav => WAV, mp3 => MP3, mp4 => MP4 );
    for my $fmt ( @{ SignalWire::SWAIG::RecordCall->formats } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        $r->record_call( format => $fmt_const{$fmt} );
        is( record_params($r)->{format},
            $fmt, "constant for format '$fmt' lands as '$fmt' on the wire" );
    }
    my %dir_const = ( speak => SPEAK, listen => LISTEN, both => BOTH );
    for my $dir ( @{ SignalWire::SWAIG::RecordCall->directions } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        $r->record_call( direction => $dir_const{$dir} );
        is( record_params($r)->{direction},
            $dir, "constant for direction '$dir' lands as '$dir' on the wire" );
    }
};

# ------------------------------------------------------------------
# 5. Dropped-keys restoration: the slurpy-%opts body used to read only
#    control_id/stereo/format/direction and silently drop the rest.
#    Python emits beep + input_sensitivity UNCONDITIONALLY (even at their
#    defaults) and the remaining keys conditionally. Assert every key
#    reaches the SWML wire shape with Python's exact gating.
# ------------------------------------------------------------------
subtest 'record_call always-on keys: beep + input_sensitivity (defaults)' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new;
    $r->record_call;    # all defaults
    my $p = record_params($r);

    # Even with zero opts, Python emits these five unconditionally.
    is_deeply(
        [ sort keys %$p ],
        [ sort qw(stereo format direction beep input_sensitivity) ],
        'all-defaults record_call emits exactly the 5 always-on keys',
    );
    is( $p->{format},    'wav',  'format default' );
    is( $p->{direction}, 'both', 'direction default' );

    # beep defaults false but is STILL emitted (was dropped before the fix).
    ok( defined $p->{beep}, 'beep key present at default' );
    ok( !$p->{beep},        'beep default is false' );

    # input_sensitivity defaults 44.0 and is emitted as a number (was dropped).
    cmp_ok( $p->{input_sensitivity}, '==', 44, 'input_sensitivity default 44.0 emitted' );

    # stereo default false, emitted.
    ok( defined $p->{stereo}, 'stereo key present' );
    ok( !$p->{stereo},        'stereo default false' );
};

subtest 'record_call conditional keys reach the SWML when set' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new;
    $r->record_call(
        control_id          => 'rec1',
        stereo              => 1,
        format              => 'mp3',
        direction           => 'speak',
        terminators         => '#',
        beep                => 1,
        input_sensitivity   => 50.5,
        initial_timeout     => 0,                    # is-not-None gate: 0 MUST still emit
        end_silence_timeout => 2.5,
        max_length          => 30,
        status_url          => 'https://x.test/s',
    );
    my $p = record_params($r);

    is( $p->{control_id}, 'rec1', 'control_id' );
    ok( $p->{stereo}, 'stereo true' );
    is( $p->{format},      'mp3',   'format' );
    is( $p->{direction},   'speak', 'direction' );
    is( $p->{terminators}, '#',     'terminators reaches SWML (was dropped)' );
    ok( $p->{beep}, 'beep true reaches SWML (was dropped)' );
    cmp_ok( $p->{input_sensitivity}, '==', 50.5, 'input_sensitivity passthrough (was dropped)' );

    # The numeric-timeout trio uses Python's `is not None` gate: a literal 0
    # still emits. This is the subtle case the old truthiness body would lose.
    ok( exists $p->{initial_timeout}, 'initial_timeout=0 still emitted (is-not-None gate)' );
    cmp_ok( $p->{initial_timeout}, '==', 0, 'initial_timeout value 0' );
    cmp_ok( $p->{end_silence_timeout}, '==', 2.5,
        'end_silence_timeout reaches SWML (was dropped)' );
    cmp_ok( $p->{max_length}, '==', 30, 'max_length reaches SWML (was dropped)' );
    is( $p->{status_url}, 'https://x.test/s', 'status_url reaches SWML (was dropped)' );
};

subtest 'record_call omits conditional keys left unset' => sub {

    # With only the two always-on numerics/bools present plus format/direction,
    # none of the optional keys should appear (matches Python's gating).
    my $r = SignalWire::SWAIG::FunctionResult->new;
    $r->record_call( format => 'mp4', direction => 'listen' );
    my $p = record_params($r);
    for my $k (
        qw(control_id terminators initial_timeout end_silence_timeout
        max_length status_url)
        )
    {
        ok( !exists $p->{$k}, "unset optional key '$k' omitted" );
    }

    # but the always-on ones are still there
    ok( exists $p->{beep},              'beep still present' );
    ok( exists $p->{input_sensitivity}, 'input_sensitivity still present' );
};

done_testing;
