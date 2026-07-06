#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Spec;

use SignalWire::Skills::SkillRegistry;
use SignalWire::Agent::AgentBase;

# ============================================================
# 1. list_skills returns all 17
# ============================================================
subtest 'list all skills' => sub {
    SignalWire::Skills::SkillRegistry->clear_registry;
    my $skills = SignalWire::Skills::SkillRegistry->list_skills;
    is(scalar @$skills, 17, '17 skills');
};

# ============================================================
# 2. get_factory for each skill
# ============================================================
subtest 'get_factory all skills' => sub {
    my @expected = qw(
        api_ninjas_trivia claude_skills custom_skills datasphere
        datasphere_serverless datetime google_maps info_gatherer
        joke math native_vector_search
        play_background_file spider swml_transfer weather_api
        web_search wikipedia_search
    );
    for my $name (@expected) {
        my $factory = SignalWire::Skills::SkillRegistry->get_factory($name);
        ok(defined $factory, "$name: factory found");
    }
};

# ============================================================
# 3. get_factory returns undef for unknown
# ============================================================
subtest 'get_factory unknown' => sub {
    my $factory = SignalWire::Skills::SkillRegistry->get_factory('totally_fake');
    ok(!defined $factory, 'unknown skill returns undef');
};

# ============================================================
# 4. clear_registry
# ============================================================
subtest 'clear_registry' => sub {
    SignalWire::Skills::SkillRegistry->clear_registry;
    # After clearing, list_skills will re-load all builtins
    my $skills = SignalWire::Skills::SkillRegistry->list_skills;
    is(scalar @$skills, 17, 're-loaded after clear');
};

# ============================================================
# 5. Skills sorted alphabetically
# ============================================================
subtest 'skills sorted' => sub {
    my $skills = SignalWire::Skills::SkillRegistry->list_skills;
    my @sorted = sort @$skills;
    is_deeply($skills, \@sorted, 'skills are sorted');
};

# ============================================================
# 6. All skills instantiate and setup
# ============================================================
subtest 'all skills instantiate' => sub {
    # Network-only skills require mandatory config (e.g. remote_url) and
    # deliberately return false from setup() when it is absent — matches the
    # Python/ruby reference. They still instantiate; we just don't assert a
    # truthy bare setup for them.
    # claude_skills now requires a skills_path (real SKILL.md discovery,
    # #72) and returns false from setup() without it — matches Python
    # ClaudeSkillsSkill.setup.
    my %requires_config = ( native_vector_search => 1, claude_skills => 1 );

    my $skills = SignalWire::Skills::SkillRegistry->list_skills;
    for my $name (@$skills) {
        my $agent = SignalWire::Agent::AgentBase->new(name => "test_$name");
        my $factory = SignalWire::Skills::SkillRegistry->get_factory($name);
        my $skill = eval { $factory->new(agent => $agent, params => {}) };
        ok(defined $skill, "$name: instantiated") or diag($@);
        my $ok = eval { $skill->setup };
        if ($requires_config{$name}) {
            ok(!$ok, "$name: setup false without required config") or diag($@);
        }
        else {
            ok($ok, "$name: setup") or diag($@);
        }
    }
};

# ============================================================
# 7. register_skill custom skill
# ============================================================
subtest 'register custom skill' => sub {
    {
        package MyCustomSkill;
        use Moo;
        extends 'SignalWire::Skills::SkillBase';
        has '+skill_name'        => (default => sub { 'test_custom' });
        has '+skill_description' => (default => sub { 'Test custom skill' });
        sub setup { 1 }
        sub register_tools {}
    }
    SignalWire::Skills::SkillRegistry->register_skill('test_custom', 'MyCustomSkill');
    my $factory = SignalWire::Skills::SkillRegistry->get_factory('test_custom');
    is($factory, 'MyCustomSkill', 'custom skill registered');
};

# ============================================================
# 8-11. add_skill_directory parity with Python's
#       signalwire.skills.registry.SkillRegistry.add_skill_directory.
# ============================================================
subtest 'add_skill_directory: valid path' => sub {
    SignalWire::Skills::SkillRegistry->clear_registry;
    my $tmpdir = tempdir(CLEANUP => 1);
    SignalWire::Skills::SkillRegistry->add_skill_directory($tmpdir);
    my $paths = SignalWire::Skills::SkillRegistry->_external_paths;
    ok((grep { $_ eq $tmpdir } @$paths), 'tmpdir present in external_paths');
};

subtest 'add_skill_directory: nonexistent path' => sub {
    SignalWire::Skills::SkillRegistry->clear_registry;
    eval {
        SignalWire::Skills::SkillRegistry->add_skill_directory(
            '/no/such/path/swperl_abc123_does_not_exist'
        );
    };
    my $err = $@;
    ok($err, 'raised an error');
    like($err, qr/does not exist/, 'error mentions does-not-exist');
};

subtest 'add_skill_directory: not a directory' => sub {
    SignalWire::Skills::SkillRegistry->clear_registry;
    my (undef, $filename) = tempfile(UNLINK => 1);
    eval {
        SignalWire::Skills::SkillRegistry->add_skill_directory($filename);
    };
    my $err = $@;
    ok($err, 'raised an error');
    like($err, qr/not a directory/, 'error mentions not-a-directory');
};

subtest 'add_skill_directory: dedup' => sub {
    SignalWire::Skills::SkillRegistry->clear_registry;
    my $tmpdir = tempdir(CLEANUP => 1);
    SignalWire::Skills::SkillRegistry->add_skill_directory($tmpdir);
    SignalWire::Skills::SkillRegistry->add_skill_directory($tmpdir);
    my $paths = SignalWire::Skills::SkillRegistry->_external_paths;
    my $count = grep { $_ eq $tmpdir } @$paths;
    is($count, 1, 'tmpdir present exactly once');
};

done_testing;
