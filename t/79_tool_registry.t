#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Real-behavior tests for SignalWire::Core::Agent::Tools::Registry —
# the standalone SWAIG function registry (parity with Python's
# signalwire.core.agent.tools.registry.ToolRegistry, mirroring Ruby's
# tests/tool_registry_test.rb).

use_ok('SignalWire::Core::Agent::Tools::Registry');

my $CLASS = 'SignalWire::Core::Agent::Tools::Registry';

subtest 'define_tool and get' => sub {
    my $r = $CLASS->new;
    $r->define_tool(
        name        => 'greet',
        description => 'Say hi',
        parameters  => { name => { type => 'string' } },
    );
    my $fn = $r->get_function('greet');
    ok( defined $fn, 'function stored' );
    is( $fn->{function},    'greet',  'function name key' );
    is( $fn->{description}, 'Say hi', 'description key' );
};

subtest 'has_function' => sub {
    my $r = $CLASS->new;
    $r->define_tool( name => 'a', description => 'd' );
    ok( $r->has_function('a'),        'present function' );
    ok( !$r->has_function('missing'), 'absent function' );
};

subtest 'get_function missing returns undef' => sub {
    my $r = $CLASS->new;
    is( $r->get_function('nope'), undef, 'undef for missing' );
};

subtest 'define_tool normalises parameters into object schema' => sub {
    my $r = $CLASS->new;
    $r->define_tool(
        name        => 't',
        description => 'd',
        parameters  => { city => { type => 'string' } },
    );
    my $schema = $r->get_function('t')->{parameters};
    is( $schema->{type}, 'object', 'wrapped in object schema' );
    is_deeply( $schema->{properties}, { city => { type => 'string' } }, 'properties preserved' );
};

subtest 'define_tool injects required' => sub {
    my $r = $CLASS->new;
    $r->define_tool(
        name        => 't',
        description => 'd',
        parameters  => { city => { type => 'string' } },
        required    => ['city'],
    );
    my $schema = $r->get_function('t')->{parameters};
    ok( ( grep { $_ eq 'city' } @{ $schema->{required} } ), 'required includes city' );
};

subtest 'define_tool optional fields' => sub {
    my $r = $CLASS->new;
    $r->define_tool(
        name            => 't',
        description     => 'd',
        wait_file       => 'https://x/w.mp3',
        wait_file_loops => 2,
        webhook_url     => 'https://x/hook',
        fillers         => { 'en-US' => ['wait'] },
    );
    my $fn = $r->get_function('t');
    is( $fn->{wait_file},       'https://x/w.mp3', 'wait_file' );
    is( $fn->{wait_file_loops}, 2,                 'wait_file_loops' );
    is( $fn->{webhook_url},     'https://x/hook',  'webhook_url' );
    is_deeply( $fn->{fillers}, { 'en-US' => ['wait'] }, 'fillers' );
};

subtest 'define_tool swaig_fields merged' => sub {
    my $r = $CLASS->new;
    $r->define_tool(
        name         => 't',
        description  => 'd',
        swaig_fields => { meta_data => { k => 'v' } },
    );
    is_deeply( $r->get_function('t')->{meta_data}, { k => 'v' }, 'extra field merged' );
};

subtest 'define_tool duplicate raises' => sub {
    my $r = $CLASS->new;
    $r->define_tool( name => 'dup', description => 'd' );
    eval { $r->define_tool( name => 'dup', description => 'd2' ); 1 };
    like( $@, qr/Tool with name 'dup' already exists/, 'duplicate dies' );
};

subtest 'register_swaig_function' => sub {
    my $r = $CLASS->new;
    $r->register_swaig_function( { function => 'weather', parameters => {} } );
    ok( $r->has_function('weather'), 'registered' );
    is( $r->get_function('weather')->{function}, 'weather', 'function name preserved' );
};

subtest 'register_swaig_function missing name raises' => sub {
    my $r = $CLASS->new;
    eval { $r->register_swaig_function( { parameters => {} } ); 1 };
    like( $@, qr/must contain 'function' field/, 'missing name dies' );
};

subtest 'register_swaig_function duplicate raises' => sub {
    my $r = $CLASS->new;
    $r->register_swaig_function( { function => 'x' } );
    eval { $r->register_swaig_function( { function => 'x' } ); 1 };
    like( $@, qr/Tool with name 'x' already exists/, 'duplicate dies' );
};

subtest 'get_all_functions returns copy' => sub {
    my $r = $CLASS->new;
    $r->define_tool( name => 'a', description => 'd' );
    $r->register_swaig_function( { function => 'b' } );
    my $all = $r->get_all_functions;
    is_deeply( [ sort keys %$all ], [qw(a b)], 'both functions present' );

    # Mutating the returned hash must not affect the registry.
    delete $all->{a};
    ok( $r->has_function('a'), 'registry unaffected by copy mutation' );
};

subtest 'remove_function' => sub {
    my $r = $CLASS->new;
    $r->define_tool( name => 'a', description => 'd' );
    is( $r->remove_function('a'), 1, 'removed returns 1' );
    ok( !$r->has_function('a'), 'gone after remove' );
};

subtest 'remove_function missing returns false' => sub {
    my $r = $CLASS->new;
    is( $r->remove_function('nope'), 0, 'missing remove returns 0' );
};

done_testing;
