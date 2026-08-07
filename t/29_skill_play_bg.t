#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

my $factory = SignalWire::Skills::SkillRegistry->get_factory('play_background_file');
ok( defined $factory, 'factory found' );

subtest 'construction' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'pbg' );
    my $skill = $factory->new( agent => $agent, params => {} );
    is( $skill->skill_name, 'play_background_file', 'skill_name' );
    ok( $skill->supports_multiple_instances, 'multi-instance' );
};

subtest 'registers DataMap tool with files' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'pbg_reg' );
    my $skill = $factory->new(
        agent  => $agent,
        params => {
            files => [
                { key => 'music', description => 'Music', url => 'http://x.com/music.mp3' },
                { key => 'hold',  description => 'Hold',  url => 'http://x.com/hold.mp3' },
            ],
        }
    );
    $skill->setup;
    $skill->register_tools;
    ok( exists $agent->tools->{play_background_file}, 'tool registered' );
    my $func = $agent->tools->{play_background_file};
    ok( exists $func->{data_map}, 'has data_map' );
    my $enum = $func->{parameters}{properties}{action}{enum};
    ok( grep( { $_ eq 'stop' } @$enum ),        'has stop action' );
    ok( grep( { $_ eq 'start_music' } @$enum ), 'has start_music' );
    ok( grep( { $_ eq 'start_hold' } @$enum ),  'has start_hold' );
};

subtest 'custom tool_name' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'pbg_custom' );
    my $skill = $factory->new(
        agent  => $agent,
        params => {
            tool_name => 'bg_player',
            files     => [],
        }
    );
    $skill->setup;
    $skill->register_tools;
    ok( exists $agent->tools->{bg_player}, 'custom name' );
};

subtest 'get_tools returns raw tool definitions' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'pbg_gt' );
    my $skill = $factory->new(
        agent  => $agent,
        params => {
            files =>
                [ { key => 'music', description => 'Music', url => 'http://x.com/music.mp3' }, ],
        }
    );
    my $tools = $skill->get_tools;
    is( ref $tools,            'ARRAY',                'returns arrayref' );
    is( scalar @$tools,        1,                      'one tool definition' );
    is( $tools->[0]{function}, 'play_background_file', 'function name' );
    my $enum = $tools->[0]{parameters}{properties}{action}{enum};
    ok( grep( { $_ eq 'stop' } @$enum ),           'has stop action' );
    ok( grep( { $_ eq 'start_music' } @$enum ),    'has start_music action' );
    ok( exists $tools->[0]{data_map}{expressions}, 'has data_map expressions' );

    # register_tools consumes get_tools -> same wire shape reaches the agent
    $skill->register_tools;
    is_deeply(
        $agent->tools->{play_background_file}{data_map},
        $tools->[0]{data_map},
        'register_tools registers the get_tools data_map'
    );
};

subtest 'parameter schema' => sub {
    my $schema = $factory->get_parameter_schema;
    ok( exists $schema->{files},     'has files' );
    ok( exists $schema->{tool_name}, 'has tool_name' );
};

done_testing;
