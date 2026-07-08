#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Tests for SignalWire::Utils::SchemaUtils and
# SignalWire::Utils::SchemaValidationError — the standalone schema-utility
# class ported from the Python reference signalwire.utils.schema_utils.
# (Distinct from t/49_schema_utils.t, which covers SignalWire::SWML::Schema.)

use_ok('SignalWire::Utils::SchemaUtils');

sub utils { return SignalWire::Utils::SchemaUtils->new(@_) }

# ------------------------------------------------------------------
# Schema loading + verb extraction
# ------------------------------------------------------------------
subtest 'loads bundled schema and extracts verbs' => sub {
    my $u     = utils();
    my @verbs = $u->get_all_verb_names;
    ok( scalar(@verbs) >= 38, 'at least 38 verbs extracted' );
    ok( ( grep { $_ eq 'answer' } @verbs ), 'includes answer' );
    ok( ( grep { $_ eq 'ai' } @verbs ),     'includes ai' );

    # get_all_verb_names is sorted.
    is_deeply( [@verbs], [ sort @verbs ], 'verb names sorted' );
};

subtest 'load_schema returns a hashref with $defs' => sub {
    my $schema = utils()->load_schema;
    is( ref $schema, 'HASH', 'schema is a hashref' );
    ok( exists $schema->{'$defs'}, 'schema has $defs' );
};

subtest 'get_verb_properties / parameters / required' => sub {
    my $u = utils();

    my $props = $u->get_verb_properties('answer');
    is( ref $props, 'HASH', 'answer properties is a hashref' );

    my $params = $u->get_verb_parameters('answer');
    ok( exists $params->{max_duration}, 'answer has a max_duration parameter' );

    # An unknown verb yields empty structures, never dies.
    is_deeply( $u->get_verb_properties('nope'),          {}, 'unknown verb props empty' );
    is_deeply( $u->get_verb_parameters('nope'),          {}, 'unknown verb params empty' );
    is_deeply( $u->get_verb_required_properties('nope'), [], 'unknown verb required empty' );
};

subtest 'get_verb_required_properties returns the schema required list' => sub {

    # The `execute` verb requires `dest`.
    my $req = utils()->get_verb_required_properties('execute');
    ok( ( grep { $_ eq 'dest' } @$req ), 'execute requires dest' );
};

# ------------------------------------------------------------------
# validate_verb
# ------------------------------------------------------------------
subtest 'validate_verb unknown verb' => sub {
    my ( $valid, $errors ) = utils()->validate_verb( 'not_a_verb', {} );
    ok( !$valid, 'unknown verb invalid' );
    ok( ( grep { /Unknown verb/ } @$errors ), 'unknown-verb error' );
};

subtest 'validate_verb missing required property' => sub {
    my ( $valid, $errors ) = utils()->validate_verb( 'execute', {} );
    ok( !$valid, 'missing required => invalid' );
    ok( ( grep { /Missing required property 'dest'/ } @$errors ), 'names the missing property' );
};

subtest 'validate_verb passes when required present' => sub {
    my ( $valid, $errors ) = utils()->validate_verb( 'execute', { dest => 'sub' } );
    ok( $valid, 'valid when required present' );
    is_deeply( $errors, [], 'no errors' );
};

subtest 'validate_verb short-circuits when validation disabled' => sub {
    my $u = utils( schema_validation => 0 );
    my ( $valid, $errors ) = $u->validate_verb( 'not_a_verb', {} );
    ok( $valid, 'validation disabled => always valid' );
    is_deeply( $errors, [], 'no errors' );
};

subtest 'env var disables validation' => sub {
    local $ENV{SWML_SKIP_SCHEMA_VALIDATION} = 'true';
    my ( $valid, $errors ) = utils()->validate_verb( 'not_a_verb', {} );
    ok( $valid, 'env var disables validation' );
    is_deeply( $errors, [], 'no errors' );
};

# ------------------------------------------------------------------
# validate_document + full_validation_available
# ------------------------------------------------------------------
subtest 'full validation not wired in' => sub {
    my $u = utils();
    ok( !$u->full_validation_available, 'no full validator' );
    my ( $valid, $errors ) = $u->validate_document( { version => '1.0.0' } );
    ok( !$valid, 'document validation reports uninitialised validator' );
    ok( ( grep { /Schema validator not initialized/ } @$errors ), 'names the reason' );
};

# ------------------------------------------------------------------
# Codegen helpers
# ------------------------------------------------------------------
subtest 'generate_method_signature' => sub {
    my $sig = utils()->generate_method_signature('answer');
    like( $sig, qr/\Adef answer\(self, /, 'signature starts with def answer(self, ' );
    like( $sig, qr/\*\*kwargs\) -> bool:/, 'ends with **kwargs) -> bool:' );
    like( $sig, qr/max_duration:/,          'includes the max_duration parameter' );
};

subtest 'generate_method_body' => sub {
    my $body = utils()->generate_method_body('answer');
    like( $body, qr/config = \{\}/,                       'initialises config' );
    like( $body, qr/if max_duration is not None:/,        'guards a parameter' );
    like( $body, qr/return self\.add_verb\('answer', config\)/, 'ends with add_verb call' );
};

# ------------------------------------------------------------------
# SchemaValidationError
# ------------------------------------------------------------------
subtest 'SchemaValidationError message + fields' => sub {
    my $err = SignalWire::Utils::SchemaValidationError->new(
        verb_name => 'ai',
        errors    => [ 'bad prompt', 'no swaig' ],
    );
    is( $err->verb_name, 'ai', 'verb_name' );
    is_deeply( $err->errors, [ 'bad prompt', 'no swaig' ], 'errors' );
    like( "$err", qr/Schema validation failed for 'ai': bad prompt; no swaig/,
        'stringifies to composed message' );
};

done_testing;
