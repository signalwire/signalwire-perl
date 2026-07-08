#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Tests for the SWML verb-handler trio: SignalWire::SWML::SWMLHandler (base
# interface / Python SWMLVerbHandler), ::AIVerbHandler, and
# ::VerbHandlerRegistry. Mirrors the Ruby tests/swml_handler_test.rb.

use_ok('SignalWire::SWML::SWMLHandler');

my $AI       = 'SignalWire::SWML::SWMLHandler::AIVerbHandler';
my $BASE     = 'SignalWire::SWML::SWMLHandler';
my $REGISTRY = 'SignalWire::SWML::SWMLHandler::VerbHandlerRegistry';

# ------------------------------------------------------------------
# AIVerbHandler
# ------------------------------------------------------------------
subtest 'get_verb_name' => sub {
    is( $AI->new->get_verb_name, 'ai', 'verb name is ai' );
};

subtest 'build_config text prompt wire keys' => sub {
    my $config = $AI->new->build_config( prompt_text => 'hello' );
    is_deeply( $config->{prompt}, { text => 'hello' }, 'prompt is object {text}' );
    is_deeply( $config->{params}, {}, 'params always initialised' );
};

subtest 'build_config pom prompt' => sub {
    my $pom = [ { title => 'Role', body => 'assistant' } ];
    my $config = $AI->new->build_config( prompt_pom => $pom );
    is_deeply( $config->{prompt}, { pom => $pom }, 'prompt is object {pom}' );
};

subtest 'build_config routes top-level keys' => sub {
    my $config = $AI->new->build_config(
        prompt_text => 'hi',
        languages   => [ { code => 'en' } ],
        hints       => [qw(foo)],
        pronounce   => [ { x => 'y' } ],
        global_data => { k => 'v' },
    );
    is_deeply( $config->{languages},   [ { code => 'en' } ], 'languages top-level' );
    is_deeply( $config->{hints},       [qw(foo)],            'hints top-level' );
    is_deeply( $config->{pronounce},   [ { x => 'y' } ],     'pronounce top-level' );
    is_deeply( $config->{global_data}, { k => 'v' },         'global_data top-level' );
    is_deeply( $config->{params},      {},                   'top-level keys not in params' );
};

subtest 'build_config routes other keys into params' => sub {
    my $config = $AI->new->build_config( prompt_text => 'hi', temperature => 0.7, top_p => 0.9 );
    is_deeply( $config->{params}, { temperature => 0.7, top_p => 0.9 }, 'unknown keys in params' );
};

subtest 'build_config post_prompt and swaig' => sub {
    my $swaig  = { functions => [] };
    my $config = $AI->new->build_config(
        prompt_text     => 'hi',
        post_prompt     => 'summarize',
        post_prompt_url => 'https://ex.com/pp',
        swaig           => $swaig,
    );
    is_deeply( $config->{post_prompt}, { text => 'summarize' }, 'post_prompt wrapped' );
    is( $config->{post_prompt_url}, 'https://ex.com/pp', 'post_prompt_url' );
    is_deeply( $config->{SWAIG}, $swaig, 'SWAIG passed through' );
};

subtest 'build_config requires a base prompt' => sub {
    eval { $AI->new->build_config };
    like( $@, qr/must be provided as base prompt/, 'requires base prompt' );
};

subtest 'build_config rejects both prompts' => sub {
    eval { $AI->new->build_config( prompt_text => 'a', prompt_pom => [ { x => 1 } ] ) };
    like( $@, qr/mutually exclusive/, 'rejects both text and pom' );
};

subtest 'validate_config valid' => sub {
    my ( $valid, $errors ) = $AI->new->validate_config( { prompt => { text => 'hi' } } );
    ok( $valid, 'valid' );
    is_deeply( $errors, [], 'no errors' );
};

subtest 'validate_config missing prompt' => sub {
    my ( $valid, $errors ) = $AI->new->validate_config( {} );
    ok( !$valid, 'invalid' );
    ok( ( grep { $_ eq "Missing required field 'prompt'" } @$errors ), 'missing prompt error' );
};

subtest 'validate_config prompt not object' => sub {
    my ( $valid, $errors ) = $AI->new->validate_config( { prompt => 'a bare string' } );
    ok( !$valid, 'invalid' );
    ok( ( grep { $_ eq "'prompt' must be an object" } @$errors ), 'prompt-not-object error' );
};

subtest 'validate_config both text and pom' => sub {
    my ( $valid, $errors ) =
        $AI->new->validate_config( { prompt => { text => 'a', pom => [] } } );
    ok( !$valid, 'invalid' );
    ok( ( grep { /mutually exclusive/ } @$errors ), 'mutual-exclusion error' );
};

subtest 'validate_config bad swaig' => sub {
    my ( $valid, $errors ) =
        $AI->new->validate_config( { prompt => { text => 'a' }, SWAIG => 'nope' } );
    ok( !$valid, 'invalid' );
    ok( ( grep { $_ eq "'SWAIG' must be an object" } @$errors ), 'bad-SWAIG error' );
};

# ------------------------------------------------------------------
# Base SWMLVerbHandler + VerbHandlerRegistry
# ------------------------------------------------------------------
subtest 'base handler abstract methods die' => sub {
    my $base = $BASE->new;
    eval { $base->get_verb_name };
    like( $@, qr/must be implemented/, 'get_verb_name is abstract' );
    eval { $base->validate_config( {} ) };
    like( $@, qr/must be implemented/, 'validate_config is abstract' );
    eval { $base->build_config };
    like( $@, qr/must be implemented/, 'build_config is abstract' );
};

subtest 'registry registers ai by default' => sub {
    my $registry = $REGISTRY->new;
    ok( $registry->has_handler('ai'), 'has ai handler' );
    isa_ok( $registry->get_handler('ai'), $AI );
};

subtest 'registry get missing returns undef' => sub {
    my $registry = $REGISTRY->new;
    ok( !$registry->has_handler('nonexistent'), 'no handler' );
    is( $registry->get_handler('nonexistent'), undef, 'get returns undef' );
};

subtest 'registry register roundtrip' => sub {
    my $registry = $REGISTRY->new;
    my $custom   = CustomVerbHandler->new;
    $registry->register_handler($custom);
    ok( $registry->has_handler('custom'), 'custom registered' );
    is( $registry->get_handler('custom'), $custom, 'same handler returned' );
};

done_testing;

# A minimal custom handler subclass for the registry round-trip test.
package CustomVerbHandler;
use Moo;
extends 'SignalWire::SWML::SWMLHandler';
sub get_verb_name  { return 'custom' }
sub validate_config { return ( 1, [] ) }
sub build_config    { return {} }
1;
