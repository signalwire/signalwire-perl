#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

my $factory = SignalWire::Skills::SkillRegistry->get_factory('api_ninjas_trivia');
ok(defined $factory, 'factory found');

subtest 'construction' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'trivia');
    my $skill = $factory->new(agent => $agent, params => {});
    is($skill->skill_name, 'api_ninjas_trivia', 'skill_name');
    ok($skill->supports_multiple_instances, 'multi-instance');
};

subtest 'registers tool' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'trivia_reg');
    my $skill = $factory->new(agent => $agent, params => {});
    $skill->setup;
    $skill->register_tools;
    ok(exists $agent->tools->{get_trivia}, 'get_trivia registered');
    my $enum = $agent->tools->{get_trivia}{parameters}{properties}{category}{enum};
    ok(scalar @$enum > 10, 'many categories');
};

subtest 'custom tool_name and categories' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'trivia_custom');
    my $skill = $factory->new(agent => $agent, params => {
        tool_name  => 'quiz',
        categories => ['music', 'sportsleisure'],
    });
    $skill->setup;
    $skill->register_tools;
    ok(exists $agent->tools->{quiz}, 'custom tool name');
    my $enum = $agent->tools->{quiz}{parameters}{properties}{category}{enum};
    is_deeply($enum, ['music', 'sportsleisure'], 'custom categories');
};

subtest 'get_tools returns raw tool definitions' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'trivia_gt');
    my $skill = $factory->new(agent => $agent, params => {
        tool_name => 'quiz',
        api_key   => 'k',
        categories => ['music', 'geography'],
    });
    my $tools = $skill->get_tools;
    is(ref $tools, 'ARRAY', 'returns arrayref');
    is(scalar @$tools, 1, 'one tool definition');
    is($tools->[0]{function}, 'quiz', 'function name');
    is_deeply($tools->[0]{parameters}{properties}{category}{enum},
        ['music', 'geography'], 'enum categories');
    ok(exists $tools->[0]{data_map}{webhooks}, 'has data_map webhooks');
    is($tools->[0]{data_map}{webhooks}[0]{headers}{'X-Api-Key'}, 'k', 'api key header');
    # register_tools consumes get_tools -> same wire shape reaches the agent
    $skill->register_tools;
    is_deeply($agent->tools->{quiz}{parameters}{properties}{category}{enum},
        $tools->[0]{parameters}{properties}{category}{enum},
        'register_tools registers the get_tools definition');
};

subtest 'instance key with tool_name' => sub {
    my $agent = SignalWire::Agent::AgentBase->new(name => 'trivia_key');
    my $skill = $factory->new(agent => $agent, params => { tool_name => 'my_trivia' });
    is($skill->get_instance_key, 'api_ninjas_trivia:my_trivia', 'custom instance key');
};

subtest 'parameter schema' => sub {
    my $schema = $factory->get_parameter_schema;
    ok(exists $schema->{api_key}, 'has api_key');
    ok(exists $schema->{categories}, 'has categories');
};

done_testing;
