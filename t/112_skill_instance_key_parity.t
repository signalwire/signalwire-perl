#!/usr/bin/env perl

# Skill get_instance_key / get_hints / cleanup parity with the Python reference.
#
# The signature oracle previously dropped whole skill classes whose every method
# was a base-identical override (porting-sdk 8496c77). Once it stopped doing
# that, these per-skill overrides became visible as real missing surface. They
# are NOT cosmetic: get_instance_key is the SkillManager registry key, so a
# wrong formula silently collapses two distinct instances onto one slot (or
# refuses a legitimate second instance).
#
# Reference formulas (signalwire/skills/<name>/skill.py):
#   datasphere            f"{SKILL_NAME}_{params.get('tool_name','search_knowledge')}"
#   datasphere_serverless f"{SKILL_NAME}_{params.get('tool_name','search_knowledge')}"
#   swml_transfer         f"{SKILL_NAME}_{params.get('tool_name','transfer_call')}"
#   web_search            f"{SKILL_NAME}_{search_engine_id|'default'}_{tool_name|'web_search'}"
#   info_gatherer         "info_gatherer_<prefix>" when prefix set, else "info_gatherer"
# Each DIFFERS from SkillBase's default ("<name>" or "<name>:<tool_name>"), which
# is exactly why the reference overrides it.

use strict;
use warnings;
use Test::More;

use SignalWire::Agent::AgentBase;
use SignalWire::Skills::SkillRegistry;

sub skill_for {
    my ( $name, $params ) = @_;
    my $factory = SignalWire::Skills::SkillRegistry->get_factory($name);
    die "no factory for $name" unless $factory;
    my $agent = SignalWire::Agent::AgentBase->new( name => "t112_$name" );
    return $factory->new( agent => $agent, params => $params || {} );
}

subtest 'get_instance_key: datasphere' => sub {
    is( skill_for('datasphere')->get_instance_key,
        'datasphere_search_knowledge', 'default tool_name folds into the key' );
    is( skill_for( 'datasphere', { tool_name => 'lookup' } )->get_instance_key,
        'datasphere_lookup', 'explicit tool_name' );
};

subtest 'get_instance_key: datasphere_serverless' => sub {
    is(
        skill_for('datasphere_serverless')->get_instance_key,
        'datasphere_serverless_search_knowledge',
        'default tool_name'
    );
    is( skill_for( 'datasphere_serverless', { tool_name => 'q' } )->get_instance_key,
        'datasphere_serverless_q', 'explicit tool_name' );
};

subtest 'get_instance_key: swml_transfer' => sub {
    is( skill_for('swml_transfer')->get_instance_key,
        'swml_transfer_transfer_call', 'default tool_name is transfer_call' );
    is( skill_for( 'swml_transfer', { tool_name => 'xfer' } )->get_instance_key,
        'swml_transfer_xfer', 'explicit tool_name' );
};

subtest 'get_instance_key: web_search keys on BOTH engine id and tool name' => sub {
    is(
        skill_for('web_search')->get_instance_key,
        'web_search_default_web_search',
        'both defaults'
    );
    is( skill_for( 'web_search', { search_engine_id => 'cse1' } )->get_instance_key,
        'web_search_cse1_web_search', 'engine id only' );
    is(
        skill_for( 'web_search', { search_engine_id => 'cse1', tool_name => 'find' } )
            ->get_instance_key,
        'web_search_cse1_find',
        'engine id + tool name'
    );

    # The point of the override: two instances differing ONLY by engine id must
    # not collide. SkillBase's default key would return 'web_search' for both.
    isnt(
        skill_for( 'web_search', { search_engine_id => 'a' } )->get_instance_key,
        skill_for( 'web_search', { search_engine_id => 'b' } )->get_instance_key,
        'distinct engine ids yield distinct keys'
    );
};

subtest 'get_instance_key: info_gatherer keys on prefix, not tool_name' => sub {
    is( skill_for('info_gatherer')->get_instance_key, 'info_gatherer', 'no prefix -> bare name' );
    is( skill_for( 'info_gatherer', { prefix => 'intake' } )->get_instance_key,
        'info_gatherer_intake', 'prefix folds in' );

    # tool_name must NOT affect the key here (the reference keys on prefix only)
    is( skill_for( 'info_gatherer', { tool_name => 'zzz' } )->get_instance_key,
        'info_gatherer', 'tool_name is not part of the info_gatherer key' );
};

subtest 'get_hints is a per-skill override returning an arrayref' => sub {
    for my $name (qw( datetime joke math web_search )) {
        my $h = skill_for($name)->get_hints;
        is( ref $h,     'ARRAY', "$name get_hints returns arrayref" );
        is( scalar @$h, 0,       "$name get_hints is empty (matches reference)" );
    }
};

subtest 'cleanup is callable and idempotent' => sub {
    for my $name (qw( datasphere native_vector_search )) {
        my $s = skill_for($name);
        ok( $s->can('cleanup'), "$name can cleanup" );
        eval { $s->cleanup; $s->cleanup; 1 } or diag $@;
        is( $@, '', "$name cleanup runs twice without dying" );
    }
};

done_testing;
