#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Real-behavior tests for SignalWire::Core::Agent::Tools::TypeInference —
# the SWAIG schema-inference module functions (infer_schema,
# create_typed_handler_wrapper). Parity with Python's
# signalwire.core.agent.tools.type_inference, mirroring Ruby's
# tests/tool_type_inference_test.rb. Perl coderefs carry no
# parameter-name reflection, so a caller supplies the parameter
# descriptors explicitly (the direct analog of Ruby's [kind, name] pairs).

use_ok('SignalWire::Core::Agent::Tools::TypeInference');

# The two symbols are module-level functions (the package has no
# constructor and no instances), so they are called as plain functions.
sub TI_infer_schema { return SignalWire::Core::Agent::Tools::TypeInference::infer_schema(@_) }
sub TI_wrap {
    return SignalWire::Core::Agent::Tools::TypeInference::create_typed_handler_wrapper(@_);
}

# A typed handler with a required keyword, an optional keyword, and the
# raw_data channel — described explicitly.
my $typed_params = [
    { name => 'city',     kind => 'keyreq' },
    { name => 'days',     kind => 'key' },
    { name => 'raw_data', kind => 'key' },
];

subtest 'infer_schema from keyword params' => sub {
    my ( $params, $required, $desc, $is_typed, $has_raw ) =
        TI_infer_schema( sub { }, params => $typed_params );

    is_deeply( [ sort keys %$params ], [qw(city days)], 'named params (raw_data excluded)' );
    is( $params->{city}{type}, 'string', 'default string type' );
    is_deeply( $required, ['city'], 'city required (no default); days optional' );
    is( $desc,     undef, 'description always undef' );
    ok( $is_typed, 'is_typed true' );
    ok( $has_raw,  'raw_data detected' );
};

subtest 'raw_data excluded from schema' => sub {
    my ($params) = TI_infer_schema( sub { }, params => $typed_params );
    ok( !exists $params->{raw_data}, 'raw_data not a schema property' );
};

subtest 'type override map' => sub {
    my ($params) = TI_infer_schema(
        sub { },
        params => [ { name => 'count', kind => 'keyreq' }, { name => 'ratio', kind => 'key' } ],
        types  => { count => 'Integer', ratio => 'number' },
    );
    is( $params->{count}{type}, 'integer', 'class-name override -> integer' );
    is( $params->{ratio}{type}, 'number',  'schema-string override -> number' );
};

subtest 'descriptions map' => sub {
    my ($params) = TI_infer_schema(
        sub { },
        params       => [ { name => 'city', kind => 'keyreq' } ],
        descriptions => { city => 'The target city' },
    );
    is( $params->{city}{description}, 'The target city', 'per-param description applied' );
};

subtest 'positional required and optional' => sub {
    my ( $params, $required ) = TI_infer_schema(
        sub { },
        params => [ { name => 'a', kind => 'req' }, { name => 'b', kind => 'opt' } ],
    );
    is_deeply( [ sort keys %$params ], [qw(a b)], 'both positional params' );
    is_deeply( $required, ['a'], 'a required, b optional (default)' );
};

subtest 'legacy (args) handler is not typed' => sub {
    my ( $params, $required, $desc, $is_typed, $has_raw ) =
        TI_infer_schema( sub { }, params => [ { name => 'args', kind => 'req' } ] );
    is_deeply( $params,   {},    'no params' );
    is_deeply( $required, [],    'no required' );
    is( $desc, undef, 'no description' );
    ok( !$is_typed, 'not typed' );
    ok( !$has_raw,  'no raw_data' );
};

subtest 'legacy (args, raw_data) handler is not typed' => sub {
    my ( undef, undef, undef, $is_typed ) = TI_infer_schema(
        sub { },
        params => [ { name => 'args', kind => 'req' }, { name => 'raw_data', kind => 'req' } ],
    );
    ok( !$is_typed, 'legacy 2-arg not typed' );
};

subtest 'splat handler falls back to untyped' => sub {
    my ( undef, undef, undef, $is_typed ) =
        TI_infer_schema( sub { }, params => [ { name => 'kwargs', kind => 'keyrest' } ] );
    ok( !$is_typed, 'splat -> untyped fallback' );
};

subtest 'zero-param handler is typed' => sub {
    my ( $params, $required, undef, $is_typed, $has_raw ) =
        TI_infer_schema( sub { }, params => [] );
    is_deeply( $params,   {}, 'empty params' );
    is_deeply( $required, [], 'empty required' );
    ok( $is_typed,  'zero-param IS typed' );
    ok( !$has_raw,  'no raw_data' );
};

subtest 'only raw_data handler is typed with raw' => sub {
    my ( $params, undef, undef, $is_typed, $has_raw ) =
        TI_infer_schema( sub { }, params => [ { name => 'raw_data', kind => 'keyreq' } ] );
    is_deeply( $params, {}, 'no schema params' );
    ok( $is_typed, 'typed' );
    ok( $has_raw,  'raw_data present' );
};

subtest 'wrapper explodes args into keywords' => sub {
    my $wrapper = TI_wrap(
        sub {
            my %kw = @_;
            return "$kw{city}-$kw{days}";
        },
        0,
    );
    is( $wrapper->( { city => 'NYC', days => 5 }, undef ), 'NYC-5', 'args exploded to kwargs' );
};

subtest 'wrapper passes raw_data when declared' => sub {
    my $wrapper = TI_wrap(
        sub {
            my %kw = @_;
            return "$kw{city}/$kw{raw_data}{id}";
        },
        1,
    );
    is( $wrapper->( { city => 'NYC' }, { id => 7 } ), 'NYC/7', 'raw_data forwarded as keyword' );
};

subtest 'wrapper handles non-hash args' => sub {
    my $wrapper = TI_wrap(
        sub {
            my %kw = @_;
            return scalar keys %kw;
        },
        0,
    );
    is( $wrapper->( undef, undef ), 0, 'undef args -> empty kwargs' );
};

done_testing;
