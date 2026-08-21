#!/usr/bin/env perl
# `hangup.reason` — the SDK validates the value set the ENGINE validates.
#
# The engine's contract is stated once, in C, at
# mod_infrastructure/relay_apis.c:1105:
#
#     JSON_CHECK_STRING_MATCHES_OPTIONAL(reason, "hangup,cancel,busy,noAnswer,decline,error")
#
# and a non-match is a hard reject (libks ks_json_check.h sets *error_msg and
# returns 0). The SWML layer types the field as a bare string
# (swml_schema.c:1571) and swml.c forwards it verbatim into the `end` RPC on
# the same call, so the contract a document must satisfy is the COMPOSITION of
# the two layers — exactly these six values.
#
# This replaces t/102_schema_sdk_widen.t, which asserted that `no_answer` must
# be accepted because the node carried `x-sdk-widen: true`. The engine refuses
# `no_answer` (it spells it camelCase `noAnswer`), so that test pinned a bug:
# the bundled schema listed only hangup|busy|decline and the validator dropped
# the value set entirely on marked nodes — which accepted the three engine
# values the schema omitted, but accepted everything else too.
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

# The six values from relay_apis.c:1105, in source order.
my @ENGINE_REASONS = qw(hangup cancel busy noAnswer decline error);

sub strict_service {
    my $svc = SignalWire::SWML::Service->new( name => 'hangup-reason', route => '/w' );
    $svc->full_validation(1);
    return $svc;
}

subtest 'the validator really is on (guards against a vacuous pass)' => sub {
    my $svc = strict_service();
    ok( $svc->full_validation, 'full_validation is enabled via the accessor' );
    ok( defined $svc->schema_utils->_full_validator,
        'a full validator is wired — const/enum are genuinely enforced here' );

    my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { bogus_key => 1 } );
    ok( !$ok, 'an unrelated schema violation is still rejected' );
};

subtest 'every value the engine accepts validates' => sub {
    my $svc = strict_service();

    # cancel, noAnswer and error were absent from the schema's old three-const
    # union and validated only because the widen transform removed the
    # constraint altogether.
    for my $reason (@ENGINE_REASONS) {
        my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { reason => $reason } );
        ok( $ok, "engine reason '$reason' is accepted" )
            or diag( join( '; ', @$errs ) );
    }
};

subtest 'a value the engine refuses is rejected' => sub {
    my $svc = strict_service();

    # The behaviour change, and it is intended: these previously validated.
    # Rejecting locally is STRICTER and correct — the caller gets a clear
    # client-side error instead of an opaque server-side call failure.
    # 'no_answer' is the snake_case near-miss; the engine spells it 'noAnswer'.
    for my $reason (qw(no_answer some_future_reason HANGUP)) {
        my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { reason => $reason } );
        ok( !$ok, "reason '$reason' is refused by relay_apis.c:1105 and must be rejected" );
    }
};

subtest 'the base type is still enforced' => sub {
    my $svc = strict_service();

    my ( $ok, $errs ) = $svc->schema_utils->validate_verb( 'hangup', { reason => 42 } );
    ok( !$ok, 'a number is rejected' );

    my ( $ok2, $errs2 ) = $svc->schema_utils->validate_verb( 'hangup', { reason => {} } );
    ok( !$ok2, 'an object is rejected' );
};

subtest 'the bundled schema publishes the engine values' => sub {
    my $svc    = strict_service();
    my $schema = $svc->schema_utils->schema;
    my $reason = $schema->{'$defs'}{Hangup}{properties}{hangup}{properties}{reason};

    ok( !exists $reason->{'x-sdk-widen'}, 'the widen marker is gone from hangup.reason' );
    is_deeply( $reason->{enum}, \@ENGINE_REASONS, 'hangup.reason publishes the six engine values' );
};

subtest 'const and enum are enforced generally' => sub {

    # Blast radius: with the widen relaxation removed, a const/enum is enforced
    # everywhere, marked or not. Driven directly against the validator.
    my $v = SignalWire::Utils::SchemaValidator->new(
        schema => {
            type       => 'object',
            properties => {
                c => { type => 'string', const => 'only' },
                e => { type => 'string', enum  => [ 'a', 'b' ] },
            },
        },
    );

    ok( $v->is_valid( { c  => 'only' } ),  'a const accepts its value' );
    ok( !$v->is_valid( { c => 'other' } ), 'a const rejects a value outside it' );
    ok( $v->is_valid( { e  => 'a' } ),     'an enum accepts a listed value' );
    ok( !$v->is_valid( { e => 'c' } ),     'an enum rejects a value outside it' );
    ok( !$v->is_valid( { c => 42 } ),      'the declared type is still enforced' );
};

done_testing();
