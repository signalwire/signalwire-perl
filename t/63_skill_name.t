#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# SignalWire::Skills::SkillName — the typed closed set of built-in skill
# names. The core guarantee (mirroring the cross-port Tier-1 idiom proof):
# a named constant and the bare wire string load the IDENTICAL skill, so
# parity with the Python reference (bare str) is preserved and custom
# skills keep working. Drives real AgentBase->add_skill behavior — no mocks.

use_ok('SignalWire::Skills::SkillName');
use_ok('SignalWire::Skills::SkillRegistry');
use_ok('SignalWire::Agent::AgentBase');

# Import the named constants the idiomatic way (Exporter). Imported names
# are used as plain barewords at the call site — the autocomplete payoff.
use SignalWire::Skills::SkillName qw(DATETIME MATH WEB_SEARCH
    API_NINJAS_TRIVIA DATASPHERE_SERVERLESS);

# ------------------------------------------------------------------
# 1. Constants ARE the canonical wire strings.
# ------------------------------------------------------------------
subtest 'constants equal wire strings' => sub {
    is(DATETIME, 'datetime', 'DATETIME constant');
    is(WEB_SEARCH, 'web_search', 'WEB_SEARCH constant');
    is(API_NINJAS_TRIVIA, 'api_ninjas_trivia', 'API_NINJAS_TRIVIA constant');
    is(DATASPHERE_SERVERLESS, 'datasphere_serverless',
        'DATASPHERE_SERVERLESS constant');
    # Fully-qualified call form also works (constants are subs).
    is(SignalWire::Skills::SkillName::JOKE(), 'joke', 'FQ JOKE() constant');
};

# ------------------------------------------------------------------
# 2. ->all is the full closed set and matches the registry exactly.
# ------------------------------------------------------------------
subtest 'all lists every built-in, matching the registry' => sub {
    my $all = SignalWire::Skills::SkillName->all;
    is(ref $all, 'ARRAY', 'all returns an arrayref');
    is(scalar @$all, 17, '17 built-in skill names');

    # Single source of truth: SkillName->all must equal SkillRegistry's
    # registered set. If a builtin is added/removed, this catches drift
    # between the constants module and the registry.
    SignalWire::Skills::SkillRegistry->clear_registry;
    my $registered = SignalWire::Skills::SkillRegistry->list_skills;
    is_deeply($all, $registered,
        'SkillName->all matches SkillRegistry->list_skills exactly');
};

# ------------------------------------------------------------------
# 3. ->is_builtin membership: built-in true, custom/unknown false.
# ------------------------------------------------------------------
subtest 'is_builtin membership' => sub {
    ok(SignalWire::Skills::SkillName->is_builtin('datetime'), 'datetime is built-in');
    ok(SignalWire::Skills::SkillName->is_builtin(MATH),
        'MATH constant is built-in');
    ok(!SignalWire::Skills::SkillName->is_builtin('my_custom_skill'),
        'custom skill is not built-in');
    ok(!SignalWire::Skills::SkillName->is_builtin('datetiem'),
        'typo is not built-in');
    ok(!SignalWire::Skills::SkillName->is_builtin(undef), 'undef is not built-in');
};

# ------------------------------------------------------------------
# 4. The core proof: named constant and bare string load the IDENTICAL
#    skill. add_skill via the constant === add_skill via the string.
# ------------------------------------------------------------------
subtest 'constant and string load the identical skill' => sub {
    # Add via the named constant.
    my $agent_const = SignalWire::Agent::AgentBase->new(name => 'const_agent');
    my ($ok_c, $err_c) = $agent_const->add_skill(DATETIME);
    ok($ok_c, 'add_skill(DATETIME) succeeds') or diag($err_c);
    ok($agent_const->has_skill('datetime'),
        'has_skill("datetime") true after adding via constant');
    ok($agent_const->has_skill(DATETIME),
        'has_skill(DATETIME) true — same skill key');
    # The constant actually loaded the real skill: its tools are registered.
    ok(exists $agent_const->tools->{get_current_time},
        'datetime tool registered when added via constant');

    # Add via the bare string (Python-parity path).
    my $agent_str = SignalWire::Agent::AgentBase->new(name => 'str_agent');
    my ($ok_s, $err_s) = $agent_str->add_skill('datetime');
    ok($ok_s, "add_skill('datetime') succeeds") or diag($err_s);
    ok($agent_str->has_skill(DATETIME),
        'has_skill(DATETIME) true after adding via string — same skill');
    ok(exists $agent_str->tools->{get_current_time},
        'datetime tool registered when added via string');

    # Identical outcome: both agents loaded the same skill key and the same
    # underlying tool set.
    is_deeply(
        [sort @{ $agent_const->list_skills }],
        [sort @{ $agent_str->list_skills }],
        'constant-loaded and string-loaded agents have identical skill lists',
    );
    is_deeply(
        [sort keys %{ $agent_const->tools }],
        [sort keys %{ $agent_str->tools }],
        'constant-loaded and string-loaded agents register identical tools',
    );
};

# ------------------------------------------------------------------
# 5. remove_skill accepts the constant too (it's just the string).
# ------------------------------------------------------------------
subtest 'remove_skill accepts the constant' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'remove_agent');
    $agent->add_skill(MATH);
    ok($agent->has_skill('math'), 'math loaded');

    my $removed = $agent->remove_skill(MATH);
    ok($removed, 'remove_skill(MATH) returns true');
    ok(!$agent->has_skill('math'), 'math removed via constant');
};

done_testing;
