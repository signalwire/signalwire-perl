#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Real-behavior tests for SignalWire::Core::Agent::Prompt::Manager —
# the standalone prompt manager (parity with Python's
# signalwire.core.agent.prompt.manager.PromptManager, mirroring Ruby's
# tests/prompt_manager_test.rb).

use_ok('SignalWire::Core::Agent::Prompt::Manager');

my $CLASS = 'SignalWire::Core::Agent::Prompt::Manager';

subtest 'set_prompt_text and get' => sub {
    my $pm = $CLASS->new;
    $pm->set_prompt_text('You are helpful.');
    is( $pm->get_prompt,     'You are helpful.', 'get_prompt returns raw text' );
    is( $pm->get_raw_prompt, 'You are helpful.', 'get_raw_prompt returns raw text' );
};

subtest 'post_prompt' => sub {
    my $pm = $CLASS->new;
    $pm->set_post_prompt('Summarize the call');
    is( $pm->get_post_prompt, 'Summarize the call', 'post prompt stored' );
};

subtest 'prompt_add_section builds POM array' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_section( 'Personality', body => 'Be helpful' );
    $pm->prompt_add_section( 'Rules', bullets => [ 'Be concise', 'Be accurate' ] );
    my $prompt = $pm->get_prompt;

    is( ref $prompt, 'ARRAY', 'get_prompt returns an arrayref in POM mode' );
    is( scalar @$prompt, 2, 'two sections' );
    is( $prompt->[0]{title}, 'Personality', 'first section title' );
    is( $prompt->[0]{body},  'Be helpful',  'first section body' );
    is_deeply( $prompt->[1]{bullets}, [ 'Be concise', 'Be accurate' ], 'second section bullets' );
};

subtest 'prompt_add_to_section appends body' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_section( 'Intro', body => 'Hello' );
    $pm->prompt_add_to_section( 'Intro', body => 'World' );
    is( $pm->get_prompt->[0]{body}, "Hello\n\nWorld", 'body appended with blank line' );
};

subtest 'prompt_add_to_section creates when absent' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_to_section( 'New', bullet => 'first' );
    my $section = $pm->get_prompt->[0];
    is( $section->{title}, 'New', 'section created' );
    is_deeply( $section->{bullets}, ['first'], 'bullet added' );
};

subtest 'prompt_add_subsection' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_section( 'Main', body => 'Top' );
    $pm->prompt_add_subsection( 'Main', 'Sub', body => 'Sub body', bullets => [qw(a b)] );
    my $sub = $pm->get_prompt->[0]{subsections}[0];
    is( $sub->{title}, 'Sub',      'subsection title' );
    is( $sub->{body},  'Sub body', 'subsection body' );
    is_deeply( $sub->{bullets}, [qw(a b)], 'subsection bullets' );
};

subtest 'prompt_add_subsection creates parent' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_subsection( 'Parent', 'Child', body => 'b' );
    my $section = $pm->get_prompt->[0];
    is( $section->{title},                 'Parent', 'parent created' );
    is( $section->{subsections}[0]{title}, 'Child',  'child added under parent' );
};

subtest 'prompt_has_section' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_section( 'Foo', body => 'bar' );
    ok( $pm->prompt_has_section('Foo'),   'existing section found' );
    ok( !$pm->prompt_has_section('Baz'),  'absent section not found' );
};

subtest 'set_prompt_pom' => sub {
    my $pm = $CLASS->new;
    $pm->set_prompt_pom( [ { title => 'Intro', body => 'Hi' } ] );
    ok( $pm->prompt_has_section('Intro'), 'section from POM array present' );
    is( $pm->get_prompt->[0]{title}, 'Intro', 'title from POM array' );
};

subtest 'get_prompt undef when empty' => sub {
    my $pm = $CLASS->new;
    is( $pm->get_prompt, undef, 'empty manager yields undef prompt' );
};

subtest 'mode exclusivity: section while text set raises' => sub {
    my $pm = $CLASS->new;
    $pm->set_prompt_text('raw');

    # First section: text set but POM empty -> allowed (matches Python).
    $pm->prompt_add_section( 'S1', body => 'b' );

    # Second section: text set AND POM non-empty -> dies.
    eval { $pm->prompt_add_section( 'S2', body => 'b' ); 1 };
    like( $@, qr/Cannot use both prompt_text and POM sections/, 'exclusivity guard fires' );
};

subtest 'pom then text does not raise (asymmetric guard)' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_section( 'Sec', body => 'b' );
    eval { $pm->set_prompt_text('raw'); 1 };
    is( $@, '', 'no error when text set after POM' );
    is( $pm->get_raw_prompt, 'raw', 'raw text stored' );
};

subtest 'define_contexts from hashref' => sub {
    my $pm = $CLASS->new;
    $pm->define_contexts( { default => { steps => [] } } );
    my $c = $pm->get_contexts;
    is( ref $c, 'HASH', 'contexts is a hashref' );
    ok( exists $c->{default}, 'default context present' );
};

subtest 'define_contexts from ContextBuilder' => sub {
    require SignalWire::Contexts::ContextBuilder;
    my $cb  = SignalWire::Contexts::ContextBuilder->new;
    my $ctx = $cb->add_context('default');
    $ctx->add_step('greeting')->set_text('Say hello');
    my $pm = $CLASS->new;
    $pm->define_contexts($cb);
    my $c = $pm->get_contexts;
    is( ref $c, 'HASH', 'materialised to hashref' );
    ok( exists $c->{default}, 'default context present' );
};

subtest 'define_contexts invalid raises' => sub {
    my $pm = $CLASS->new;
    eval { $pm->define_contexts('nope'); 1 };
    like( $@, qr/must be a hashref or a ContextBuilder/, 'invalid input dies' );
};

subtest 'contexts take precedence in get_prompt' => sub {
    my $pm = $CLASS->new;
    $pm->prompt_add_section( 'Sec', body => 'b' );
    $pm->define_contexts( { default => { steps => [] } } );
    is( $pm->get_prompt, undef, 'contexts suppress prompt sections' );
};

subtest 'returns self for chaining' => sub {
    my $pm = $CLASS->new;
    is( $pm->set_prompt_text('x'),  $pm, 'set_prompt_text chains' );
    is( $pm->set_post_prompt('x'),  $pm, 'set_post_prompt chains' );

    my $pm2 = $CLASS->new;
    is( $pm2->prompt_add_section( 'T', body => 'b' ),        $pm2, 'prompt_add_section chains' );
    is( $pm2->prompt_add_to_section( 'T', body => 'more' ),  $pm2, 'prompt_add_to_section chains' );
    is( $pm2->prompt_add_subsection( 'T', 'S', body => 'b' ), $pm2, 'prompt_add_subsection chains' );
};

done_testing;
