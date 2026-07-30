#!/usr/bin/env perl
# `x-sdk-widen` — a const-union that is a HINT, not a closed set.
#
# Some SWML schema fields enumerate their KNOWN values while the platform
# accepts any value of the base type. The spec marks those fields
# `x-sdk-widen: true`. An SDK that enforces the union on such a field is
# STRICTER THAN THE PLATFORM: it rejects documents the server would have
# happily executed. That is the failure direction nobody looks for, because
# every test written against the enumerated values still passes.
#
# Owner ruling: anything that can do something useful with that value should
# read it and use it.
#
# `$defs/Hangup.reason` is the field that carries the marker today. Its union
# is {hangup, busy, decline}; `no_answer` is a real platform reason that is not
# in it. Before this, perl's SchemaValidator implemented `const`/`enum` (it is
# a hand-rolled Draft-2020-12 evaluator, not a no-op) and had no notion of the
# marker at all, so:
#
#     $svc->hangup({ reason => 'no_answer' })   -> died: schema validation error
#
# WIDENING IS NOT "STOP CHECKING". A widened field keeps its BASE TYPE: a
# string field still rejects 42. Only the value-set constraints (`const` /
# `enum`) are relaxed, and only on a node that actually carries the marker.
#
# The `full_validation` trap this test must not fall into: the attribute is
# declared `init_arg => undef`, so `Service->new(full_validation => 1)`
# SILENTLY DOES NOTHING. It has to be set through the accessor, or the whole
# test passes vacuously against a validator that was never enabled.

use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::SWML::Service;
use SignalWire::Utils::SchemaValidator;

sub strict_service {
    my $svc = SignalWire::SWML::Service->new( name => 'widen', route => '/w' );
    $svc->full_validation(1);
    return $svc;
}

subtest 'the validator really is on (guards against a vacuous pass)' => sub {
    my $svc = strict_service();
    ok( $svc->full_validation, 'full_validation is enabled via the accessor' );
    ok( defined $svc->schema_utils->_full_validator,
        'a full validator is wired — const/enum are genuinely enforced here' );

    # Negative control: an unwidened violation must still be caught, or this
    # file could pass simply because nothing is ever rejected.
    my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { bogus_key => 1 } );
    ok( !$ok, 'an unrelated schema violation is still rejected' );
};

subtest 'x-sdk-widen: a value outside the const-union is ACCEPTED' => sub {
    my $svc = strict_service();

    # The enumerated values must keep working.
    for my $reason (qw(hangup busy decline)) {
        my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { reason => $reason } );
        ok( $ok, "enumerated reason '$reason' still accepted" )
            or diag( join( '; ', @$errs ) );
    }

    # ...and so must a real platform value the union does not list. This is
    # the whole point of the marker.
    my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { reason => 'no_answer' } );
    ok( $ok, "widened reason 'no_answer' accepted — the union is a hint, not a closed set" )
        or diag( join( '; ', @$errs ) );
};

subtest 'x-sdk-widen relaxes the VALUE SET, never the TYPE' => sub {
    my $svc = strict_service();

    # `reason` is a string field. Widening it must not turn it into "anything
    # goes" — a number is still wrong, and an SDK that accepted it would be
    # LOOSER than the platform, which is the opposite failure.
    my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { reason => 42 } );
    ok( !$ok, 'a number is still rejected on a widened string field' );

    my ( $ok2, $errs2 ) = $svc->schema_utils->validate_verb( 'hangup', { reason => {} } );
    ok( !$ok2, 'an object is still rejected on a widened string field' );
};

subtest 'widening is scoped to the marked node only' => sub {
    # A const with NO marker keeps enforcing. Driven directly against the
    # validator so the assertion is about the widen rule itself rather than
    # about whichever schema fields happen to carry the marker today.
    my $v = SignalWire::Utils::SchemaValidator->new(
        schema => {
            type       => 'object',
            properties => {
                closed => { type => 'string', const => 'only' },
                open   => { type => 'string', const => 'only', 'x-sdk-widen' => JSON::true },
            },
        },
    );

    ok( !$v->is_valid( { closed => 'other' } ),
        'an UNMARKED const still rejects a value outside it' );

    ok( $v->is_valid( { open => 'other' } ), 'a MARKED const accepts a value outside it' )
        or diag( join( '; ', $v->validate( { open => 'other' } ) ) );

    ok( !$v->is_valid( { open => 42 } ),
        'the marked field still enforces its declared type' );
};

subtest 'a marked enum widens the same way a marked const does' => sub {
    my $v = SignalWire::Utils::SchemaValidator->new(
        schema => {
            type       => 'object',
            properties => {
                closed => { type => 'string', enum => [ 'a', 'b' ] },
                open   => { type => 'string', enum => [ 'a', 'b' ], 'x-sdk-widen' => JSON::true },
            },
        },
    );

    ok( !$v->is_valid( { closed => 'c' } ),
        'an UNMARKED enum still rejects a value outside it' );

    ok( $v->is_valid( { open => 'c' } ), 'a MARKED enum accepts a value outside it' )
        or diag( join( '; ', $v->validate( { open => 'c' } ) ) );

    ok( !$v->is_valid( { open => 42 } ),
        'the marked enum field still enforces its declared type' );
};

done_testing();
