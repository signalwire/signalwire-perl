#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# SignalWire::SWAIG::Tap — the typed closed sets for the two validated
# string params of FunctionResult->tap: the tap DIRECTION (speak/hear/both)
# and the RTP CODEC (PCMU/PCMA). The core guarantee (mirroring SkillName /
# RecordCall / the cross-port Tier-1 idiom proof): a named constant and the
# bare wire string produce the IDENTICAL tap action, so Python parity holds.
# Drives REAL FunctionResult->tap behavior and asserts on the produced SWML
# wire shape — no mocks.
#
# ★ The tap direction set is {speak,HEAR,both}, DISTINCT from record_call's
# {speak,LISTEN,both} (t/65). This test pins the difference so the two
# never get unified.

use_ok('SignalWire::SWAIG::Tap');
use_ok('SignalWire::SWAIG::FunctionResult');

use SignalWire::SWAIG::Tap qw(SPEAK HEAR BOTH PCMU PCMA);

# Pull the tap params back out of a FunctionResult's serialized action
# list (tap -> execute_swml -> add_action('SWML', ...) under
# sections/main/[0]/tap).
sub tap_params {
    my ($result) = @_;
    my $hash = $result->to_hash;
    return $hash->{action}[0]{SWML}{sections}{main}[0]{tap};
}

# ------------------------------------------------------------------
# 1. Constants ARE the canonical wire strings.
# ------------------------------------------------------------------
subtest 'constants equal wire strings' => sub {
    is( SPEAK, 'speak', 'SPEAK constant' );
    is( HEAR,  'hear',  'HEAR constant' );
    is( BOTH,  'both',  'BOTH constant' );
    is( PCMU,  'PCMU',  'PCMU constant' );
    is( PCMA,  'PCMA',  'PCMA constant' );

    # Fully-qualified call form also works (constants are subs).
    is( SignalWire::SWAIG::Tap::HEAR(), 'hear', 'FQ HEAR() constant' );
    is( SignalWire::SWAIG::Tap::PCMA(), 'PCMA', 'FQ PCMA() constant' );
};

# ------------------------------------------------------------------
# 1b. tap DIRECTION is NOT record_call DIRECTION — the 3-vocab guard.
#     tap uses 'hear'; record_call uses 'listen'. They must not share.
# ------------------------------------------------------------------
subtest 'tap direction is distinct from record_call direction' => sub {
    ok( SignalWire::SWAIG::Tap->is_direction('hear'), "tap accepts 'hear'" );
    ok( !SignalWire::SWAIG::Tap->is_direction('listen'),
        "tap REJECTS 'listen' (that is record_call's word, not tap's)" );
    is_deeply( SignalWire::SWAIG::Tap->directions,
        [qw(speak hear both)], 'tap directions are speak/hear/both, NOT speak/listen/both' );
};

# ------------------------------------------------------------------
# 2. ->directions / ->codecs are the full closed sets, matching the
#    values tap actually validates against. Single source of truth:
#    probe tap's own `die` guards so the module can't drift from the
#    accepted sets.
# ------------------------------------------------------------------
subtest 'directions/codecs match what tap accepts' => sub {
    is_deeply( SignalWire::SWAIG::Tap->directions,
        [qw(speak hear both)], 'directions lists speak, hear, both' );
    is_deeply( SignalWire::SWAIG::Tap->codecs, [qw(PCMU PCMA)], 'codecs lists PCMU, PCMA' );

    # Every advertised direction is ACCEPTED by tap (no die).
    for my $dir ( @{ SignalWire::SWAIG::Tap->directions } ) {
        my $r  = SignalWire::SWAIG::FunctionResult->new;
        my $ok = eval { $r->tap( 'rtp://1.2.3.4:5000', direction => $dir ); 1 };
        ok( $ok, "tap accepts direction '$dir'" ) or diag($@);
    }

    # Every advertised codec is ACCEPTED by tap.
    for my $codec ( @{ SignalWire::SWAIG::Tap->codecs } ) {
        my $r  = SignalWire::SWAIG::FunctionResult->new;
        my $ok = eval { $r->tap( 'rtp://1.2.3.4:5000', codec => $codec ); 1 };
        ok( $ok, "tap accepts codec '$codec'" ) or diag($@);
    }

    # Conversely, a value OUTSIDE each set is REJECTED — proving the
    # module's set is exactly tap's accepted set, not a superset.
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok( !eval { $r->tap( 'rtp://1.2.3.4:5000', direction => 'sideways' ); 1 },
            "tap rejects direction 'sideways' (outside the set)" );
        ok(
            !SignalWire::SWAIG::Tap->is_direction('sideways'),
            "is_direction('sideways') false — module agrees"
        );
    }
    {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        ok(
            !eval { $r->tap( 'rtp://1.2.3.4:5000', codec => 'OPUS' ); 1 },
            "tap rejects codec 'OPUS' (RELAY superset codec, outside SWAIG tap's set)"
        );
        ok( !SignalWire::SWAIG::Tap->is_codec('OPUS'), "is_codec('OPUS') false — module agrees" );
    }
};

# ------------------------------------------------------------------
# 3. is_direction / is_codec membership.
# ------------------------------------------------------------------
subtest 'membership predicates' => sub {
    ok( SignalWire::SWAIG::Tap->is_direction('both'),  'both is a direction' );
    ok( SignalWire::SWAIG::Tap->is_direction(HEAR),    'HEAR constant is a direction' );
    ok( !SignalWire::SWAIG::Tap->is_direction('PCMU'), 'a codec is not a direction' );
    ok( !SignalWire::SWAIG::Tap->is_direction(undef),  'undef is not a direction' );

    ok( SignalWire::SWAIG::Tap->is_codec('PCMU'),  'PCMU is a codec' );
    ok( SignalWire::SWAIG::Tap->is_codec(PCMA),    'PCMA constant is a codec' );
    ok( !SignalWire::SWAIG::Tap->is_codec('hear'), 'a direction is not a codec' );
    ok( !SignalWire::SWAIG::Tap->is_codec(undef),  'undef is not a codec' );
};

# ------------------------------------------------------------------
# 4. The core proof: tap via the named constants and via the bare strings
#    produce the IDENTICAL wire action. Exercises the real
#    tap -> execute_swml -> add_action path; assertion is on the
#    serialized SWML params (real behavior, no mocks).
# ------------------------------------------------------------------
subtest 'constant and string produce the identical tap action' => sub {

    # Use non-default values so the keys are actually emitted (tap omits
    # direction=both and codec=PCMU as they are the defaults).
    my $by_const = SignalWire::SWAIG::FunctionResult->new;
    $by_const->tap( 'rtp://1.2.3.4:5000', direction => HEAR, codec => PCMA );

    my $by_str = SignalWire::SWAIG::FunctionResult->new;
    $by_str->tap( 'rtp://1.2.3.4:5000', direction => 'hear', codec => 'PCMA' );

    my $p_const = tap_params($by_const);
    my $p_str   = tap_params($by_str);

    is( $p_const->{direction}, 'hear', 'constant path serialized direction => hear' );
    is( $p_const->{codec},     'PCMA', 'constant path serialized codec => PCMA' );

    # Whole serialized action objects are byte-for-byte identical.
    is_deeply( $by_const->to_hash, $by_str->to_hash,
        'constant-built and string-built tap actions are identical' );

    # And every advertised value round-trips onto the wire unchanged when
    # passed as the constant. (Pair each non-default scalar with a peer that
    # forces emission, since the matching default is suppressed by gating.)
    my %dir_const = ( speak => SPEAK, hear => HEAR, both => BOTH );
    for my $dir ( @{ SignalWire::SWAIG::Tap->directions } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;

        # codec=PCMA forces the tap object to carry codec; direction is the
        # value under test. For direction 'both' (the default) the key is
        # intentionally omitted — assert that, matching Python's gating.
        $r->tap(
            'rtp://1.2.3.4:5000',
            direction => $dir_const{$dir},
            codec     => PCMA
        );
        if ( $dir eq 'both' ) {
            ok( !exists tap_params($r)->{direction},
                "default direction 'both' via constant is omitted (Python gating)" );
        } else {
            is( tap_params($r)->{direction},
                $dir, "constant for direction '$dir' lands as '$dir' on the wire" );
        }
    }
    my %codec_const = ( PCMU => PCMU, PCMA => PCMA );
    for my $codec ( @{ SignalWire::SWAIG::Tap->codecs } ) {
        my $r = SignalWire::SWAIG::FunctionResult->new;
        $r->tap(
            'rtp://1.2.3.4:5000',
            direction => HEAR,
            codec     => $codec_const{$codec}
        );
        if ( $codec eq 'PCMU' ) {
            ok( !exists tap_params($r)->{codec},
                "default codec 'PCMU' via constant is omitted (Python gating)" );
        } else {
            is( tap_params($r)->{codec},
                $codec, "constant for codec '$codec' lands as '$codec' on the wire" );
        }
    }
};

# ------------------------------------------------------------------
# 5. Default gating sanity: with all defaults, tap emits ONLY uri
#    (direction=both and codec=PCMU are the defaults, suppressed; rtp_ptime
#    default 20 suppressed). This pins the emission contract the constants
#    ride on.
# ------------------------------------------------------------------
subtest 'tap default gating: only uri emitted at defaults' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new;
    $r->tap('rtp://1.2.3.4:5000');    # all defaults
    my $p = tap_params($r);
    is_deeply( [ sort keys %$p ], ['uri'], 'all-defaults tap emits exactly the uri key' );
    is( $p->{uri}, 'rtp://1.2.3.4:5000', 'uri value' );

    # The default direction/codec, supplied EXPLICITLY as constants, still
    # suppress (constant value == default value).
    my $r2 = SignalWire::SWAIG::FunctionResult->new;
    $r2->tap( 'rtp://1.2.3.4:5000', direction => BOTH, codec => PCMU );
    is_deeply( $r->to_hash, $r2->to_hash,
        'explicit default constants produce the identical action as omitting them' );
};

done_testing;
