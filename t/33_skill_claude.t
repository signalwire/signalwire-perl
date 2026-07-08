#!/usr/bin/env perl
# claude_skills builtin — real SKILL.md file discovery (#72).
#
# Parity with Python's claude_skills skill: walk skills_path, parse each
# subdirectory's SKILL.md (YAML frontmatter + body), register one SWAIG tool
# per skill (with a section enum for supporting .md files), and substitute
# $ARGUMENTS / ${CLAUDE_*} in the returned body.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Spec ();

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

my $factory = SignalWire::Skills::SkillRegistry->get_factory('claude_skills');
ok( defined $factory, 'factory found' );

# --- Build a temp skills dir with a sample skill (SKILL.md + a section) ---
my $root = tempdir( CLEANUP => 1 );
my $skill_dir = File::Spec->catdir( $root, 'code-review' );
make_path($skill_dir);

open my $fh, '>', File::Spec->catfile( $skill_dir, 'SKILL.md' ) or die $!;
print {$fh} <<'MD';
---
name: code-review
description: Review a diff for correctness bugs
argument-hint: the diff or files to review
---

Review the following for correctness. Focus: $ARGUMENTS
Skill dir: ${CLAUDE_SKILL_DIR}
MD
close $fh;

# A supporting section file (becomes a section enum value).
open my $sfh, '>', File::Spec->catfile( $skill_dir, 'checklist.md' ) or die $!;
print {$sfh} "Checklist body.\n";
close $sfh;

subtest 'construction' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'cs' );
    my $skill = $factory->new( agent => $agent, params => { skills_path => $root } );
    is( $skill->skill_name, 'claude_skills', 'skill_name' );
    ok( $skill->supports_multiple_instances, 'multi-instance' );
};

subtest 'setup requires an existing skills_path' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'cs_nopath' );
    my $skill = $factory->new( agent => $agent, params => {} );
    ok( !$skill->setup, 'setup returns false without skills_path' );

    my $bad = $factory->new(
        agent  => $agent,
        params => { skills_path => File::Spec->catdir( $root, 'does-not-exist' ) },
    );
    ok( !$bad->setup, 'setup returns false for a non-existent skills_path' );
};

subtest 'discovers SKILL.md and registers a declared tool' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'cs_reg' );
    my $skill = $factory->new( agent => $agent, params => { skills_path => $root } );
    ok( $skill->setup, 'setup succeeds' );
    $skill->register_tools;

    ok( exists $agent->tools->{claude_code_review}, 'claude_code_review tool registered' );
    my $tool = $agent->tools->{claude_code_review};
    is( $tool->{description}, 'Review a diff for correctness bugs', 'description from frontmatter' );

    # The supporting checklist.md surfaces as a section enum value.
    my $section = $tool->{parameters}{properties}{section};
    ok( $section, 'section parameter present (supporting .md discovered)' );
    is_deeply( $section->{enum}, ['checklist'], 'checklist section discovered' );
};

subtest 'custom prefix' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'cs_prefix' );
    my $skill = $factory->new( agent => $agent, params => { skills_path => $root, tool_prefix => 'sk_' } );
    ok( $skill->setup, 'setup' );
    $skill->register_tools;
    ok( exists $agent->tools->{sk_code_review}, 'custom prefix applied to tool name' );
};

subtest 'handler substitutes $ARGUMENTS and ${CLAUDE_SKILL_DIR}' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'cs_exec' );
    my $skill = $factory->new( agent => $agent, params => { skills_path => $root } );
    $skill->setup;
    $skill->register_tools;

    my $tool   = $agent->tools->{claude_code_review};
    my $result = $tool->{_handler}->( { arguments => 'file.pm' }, {} );
    my $text   = ref($result) && $result->can('response') ? $result->response : "$result";
    like( $text, qr/Focus: file\.pm/, '$ARGUMENTS substituted into body' );
    like( $text, qr/\QSkill dir: \E\Q$skill_dir\E/, '${CLAUDE_SKILL_DIR} substituted' );
    unlike( $text, qr/\$ARGUMENTS/, 'no bare $ARGUMENTS left' );
};

subtest 'hints derived from skill names' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'cs_hints' );
    my $skill = $factory->new( agent => $agent, params => { skills_path => $root } );
    $skill->setup;
    my $hints = $skill->get_hints;
    ok( ( grep { $_ eq 'code' } @$hints ),   'code hint from skill name' );
    ok( ( grep { $_ eq 'review' } @$hints ), 'review hint from skill name' );
};

subtest 'parameter schema' => sub {
    my $schema = $factory->get_parameter_schema;
    ok( exists $schema->{skills_path}, 'has skills_path' );
    ok( exists $schema->{tool_prefix}, 'has tool_prefix' );
};

done_testing;
