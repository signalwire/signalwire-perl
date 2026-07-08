#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use_ok('SignalWire::Skills::SkillBase');
use_ok('SignalWire::Skills::SkillManager');
use_ok('SignalWire::DataMap');
use_ok('SignalWire::SWAIG::FunctionResult');
use_ok('SignalWire');

# A minimal concrete skill for exercising SkillBase instance helpers.
{

    package TestSkill;
    use Moo;
    extends 'SignalWire::Skills::SkillBase';
    has '+skill_name'        => ( default => sub { 'test_skill' } );
    has '+skill_description' => ( default => sub { 'A test skill' } );
    sub setup          { return 1 }
    sub register_tools { return }
}

# A fake agent object for the weak_ref agent attribute.
{

    package FakeAgent;
    sub new { return bless {}, shift }
}

# ---------------------------------------------------------------------------
# SkillBase: get_skill_data / update_skill_data / validate_packages
# ---------------------------------------------------------------------------
subtest 'SkillBase get_skill_data' => sub {
    my $skill = TestSkill->new( agent => FakeAgent->new );

    # namespace = "skill:test_skill"
    is( ref $skill->get_skill_data(undef), 'HASH', 'undef raw_data -> empty hashref' );
    is_deeply( $skill->get_skill_data(undef), {}, 'empty when nothing present' );

    my $raw = { global_data => { 'skill:test_skill' => { count => 3 } } };
    is_deeply( $skill->get_skill_data($raw), { count => 3 }, 'reads namespaced slice' );

    my $other = { global_data => { 'skill:other' => { x => 1 } } };
    is_deeply( $skill->get_skill_data($other), {}, 'ignores other namespaces' );
};

subtest 'SkillBase get_skill_data honours prefix param' => sub {
    my $skill = TestSkill->new( agent => FakeAgent->new, params => { prefix => 'myns' } );
    my $raw = { global_data => { 'skill:myns' => { v => 42 } } };
    is_deeply( $skill->get_skill_data($raw), { v => 42 }, 'prefix drives namespace' );
};

subtest 'SkillBase update_skill_data' => sub {
    my $skill  = TestSkill->new( agent => FakeAgent->new );
    my $result = SignalWire::SWAIG::FunctionResult->new('done');

    my $ret = $skill->update_skill_data( $result, { saved => 'yes' } );
    is( $ret, $result, 'returns the result for chaining' );

    my $h = $result->to_hash;
    # The action carries a set_global_data under the skill namespace.
    my $json = JSON::encode_json($h);
    like( $json, qr/skill:test_skill/, 'namespaced key emitted into result' );
    like( $json, qr/"saved"/,          'skill data payload present' );
};

subtest 'SkillBase validate_packages' => sub {
    {

        package OkPkgSkill;
        use Moo;
        extends 'SignalWire::Skills::SkillBase';
        has '+skill_name'        => ( default => sub { 'okpkg' } );
        has '+skill_description' => ( default => sub { 'ok' } );
        has '+required_packages' => ( default => sub { ['Scalar::Util'] } );
        sub setup          { 1 }
        sub register_tools { }
    }
    {

        package BadPkgSkill;
        use Moo;
        extends 'SignalWire::Skills::SkillBase';
        has '+skill_name'        => ( default => sub { 'badpkg' } );
        has '+skill_description' => ( default => sub { 'bad' } );
        has '+required_packages' => ( default => sub { ['No::Such::Module::XYZ'] } );
        sub setup          { 1 }
        sub register_tools { }
    }

    my $ok = OkPkgSkill->new( agent => FakeAgent->new );
    is( $ok->validate_packages, 1, 'loadable package validates' );

    my $bad = BadPkgSkill->new( agent => FakeAgent->new );
    is( $bad->validate_packages, 0, 'missing package fails validation' );

    my $none = TestSkill->new( agent => FakeAgent->new );
    is( $none->validate_packages, 1, 'no required packages -> true' );
};

# ---------------------------------------------------------------------------
# SkillManager: get_skill / list_loaded_skills
# ---------------------------------------------------------------------------
subtest 'SkillManager get_skill / list_loaded_skills' => sub {
    my $agent = FakeAgent->new;
    my $mgr   = SignalWire::Skills::SkillManager->new( agent => $agent );

    is_deeply( $mgr->list_loaded_skills, [], 'no skills loaded initially' );
    is( $mgr->get_skill('nope'), undef, 'get_skill on empty returns undef' );

    my $skill = TestSkill->new( agent => $agent );
    $mgr->loaded_skills->{'test_skill'} = $skill;

    is( $mgr->get_skill('test_skill'), $skill, 'get_skill returns loaded instance' );
    is( $mgr->get_skill('absent'),     undef,  'get_skill unknown -> undef' );
    is_deeply( $mgr->list_loaded_skills, ['test_skill'], 'lists loaded instance key' );
};

# ---------------------------------------------------------------------------
# DataMap module-level factory functions
# ---------------------------------------------------------------------------
subtest 'DataMap::create_simple_api_tool' => sub {
    my $dm = SignalWire::DataMap::create_simple_api_tool(
        name              => 'get_weather',
        url               => 'https://api.example.com?q=${args.city}',
        response_template => 'Temp: ${response.temp}',
        method            => 'GET',
        parameters        => { city => { type => 'string', description => 'City', required => 1 } },
        error_keys        => ['error'],
    );
    isa_ok( $dm, 'SignalWire::DataMap' );

    my $fn = $dm->to_swaig_function;
    is( $fn->{function}, 'get_weather', 'function name' );
    is_deeply( $fn->{parameters}{required}, ['city'], 'required param carried through' );
    is( $fn->{data_map}{webhooks}[0]{method}, 'GET', 'webhook method' );
    is( $fn->{data_map}{webhooks}[0]{url}, 'https://api.example.com?q=${args.city}', 'webhook url' );
    ok( $fn->{data_map}{webhooks}[0]{output}, 'output template attached to webhook' );
};

subtest 'DataMap::create_expression_tool' => sub {
    my $r = SignalWire::SWAIG::FunctionResult->new('matched');
    my $dm = SignalWire::DataMap::create_expression_tool(
        name       => 'classify',
        patterns   => { '${args.text}' => [ '/hello/i', $r ] },
        parameters => { text => { type => 'string', description => 'Input' } },
    );
    isa_ok( $dm, 'SignalWire::DataMap' );

    my $fn = $dm->to_swaig_function;
    is( $fn->{function}, 'classify', 'function name' );
    is( scalar @{ $fn->{data_map}{expressions} }, 1, 'one expression' );
    is( $fn->{data_map}{expressions}[0]{string}, '${args.text}', 'expression test value' );
    ok( !exists $fn->{data_map}{webhooks}, 'expression tool has no webhooks' );
};

# ---------------------------------------------------------------------------
# Top-level list_skills
# ---------------------------------------------------------------------------
subtest 'SignalWire::list_skills' => sub {
    my $skills = SignalWire::list_skills();
    is( ref $skills, 'ARRAY', 'returns arrayref of skill names' );
    ok( scalar(@$skills) > 0, 'at least one built-in skill registered' );
    ok( ( grep { $_ eq 'datetime' } @$skills ), 'datetime skill present' );
};

done_testing;
