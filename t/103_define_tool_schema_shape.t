#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# PERL-6: $agent->define_tool must emit a VALID SWAIG parameters schema even
# when the caller passes a bare property map (the natural idiom). Previously the
# bare map was stored verbatim — an invalid schema with no { type => 'object',
# properties => {...} } wrapper. Mirrors the python reference's
# SWAIGFunction._ensure_parameter_structure (wrap-unless-already-object).

use SignalWire::Agent::AgentBase;

my $a = SignalWire::Agent::AgentBase->new(
    name                => 't',
    basic_auth_user     => 'u',
    basic_auth_password => 'p',
);

subtest 'bare property map is wrapped into an object schema' => sub {
    $a->define_tool(
        name        => 'get_weather',
        description => 'weather',
        parameters  => { city => { type => 'string', description => 'City name' } },
        handler     => sub { },
    );
    my $p = $a->get_function('get_weather')->{parameters};
    is( $p->{type}, 'object', 'type => object injected' );
    is( ref $p->{properties}, 'HASH', 'properties is a hash' );
    is( $p->{properties}{city}{type}, 'string', 'the bare map is nested under properties' );
    ok( !exists $p->{city}, 'the property is NOT left at the top level (was the bug)' );
};

subtest 'required list is merged into the wrapped schema' => sub {
    $a->define_tool(
        name        => 'book',
        description => 'book',
        parameters  => { date => { type => 'string' } },
        required    => ['date'],
        handler     => sub { },
    );
    my $p = $a->get_function('book')->{parameters};
    is( $p->{type}, 'object', 'wrapped' );
    is_deeply( $p->{required}, ['date'], 'required merged' );
    # `required` must not leak into the tool definition as a sibling of parameters.
    ok( !exists $a->get_function('book')->{required},
        'required is consumed, not stored as a top-level tool field' );
};

subtest 'a full object schema passes through unchanged' => sub {
    my $schema = {
        type       => 'object',
        properties => { x => { type => 'number' } },
        required   => ['x'],
    };
    $a->define_tool(
        name        => 'calc',
        description => 'calc',
        parameters  => $schema,
        handler     => sub { },
    );
    my $p = $a->get_function('calc')->{parameters};
    is( $p->{type}, 'object', 'type preserved' );
    is( $p->{properties}{x}{type}, 'number', 'properties preserved' );
    is_deeply( $p->{required}, ['x'], 'required preserved' );
};

subtest 'no parameters yields the canonical empty object schema' => sub {
    $a->define_tool( name => 'noop', description => 'noop', handler => sub { } );
    my $p = $a->get_function('noop')->{parameters};
    is( $p->{type}, 'object', 'type => object' );
    is_deeply( $p->{properties}, {}, 'empty properties' );
};

done_testing;
