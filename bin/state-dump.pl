#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# state-dump.pl — the Perl port's STATE dump program for the cross-port state
# differ (porting-sdk/scripts/diff_port_state.py).
#
# For each state_corpus case it builds the target object, applies the mutation
# chain via the Perl SDK's native API, reads the observable state through the
# public accessor / rendered representation, and prints ONE JSON object mapping
#
#     case-id -> observed-state
#
# to stdout. The differ canonicalizes both sides and byte-compares against the
# python oracle. Only stdout carries JSON. Mirrors signalwire-go/cmd/state-dump.
#
# Run from the signalwire-perl repo root:
#
#     perl -Ilib bin/state-dump.pl

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::Agent::AgentBase;
use SignalWire::Server::AgentServer;
use SignalWire::SWML::Service;
use SignalWire::Skills::SkillRegistry;
use SignalWire::Prefabs::InfoGatherer;

# A minimal custom verb handler — the Perl analog of the corpus's throwaway
# "greet" handler (only needs get_verb_name for register_verb_handler).
{

    package GreetVerbHandler;
    sub new { return bless { name => $_[1] }, $_[0]; }
    sub get_verb_name { return $_[0]->{name}; }
}

sub demo_agent {
    return SignalWire::Agent::AgentBase->new( name => 'demo', route => '/demo' );
}

sub jbool ($v) { return $v ? JSON::true : JSON::false; }

# submit_answer_delta drives InfoGatherer.submit_answer and reduces the result
# to the observable delta (mirrors diff_port_state _observe "submit_answer_delta"):
# the set_global_data action's question_index + answers, plus a `done` flag
# derived from the completion message.
sub submit_answer_delta ( $ig, $args, $raw_data ) {
    my $res = $ig->submit_answer( $args, $raw_data );
    my $m   = $res->to_hash;
    my $gd  = {};
    for my $act ( @{ $m->{action} // [] } ) {
        if ( ref $act eq 'HASH' && exists $act->{set_global_data} ) {
            $gd = $act->{set_global_data};
            last;
        }
    }
    my $resp = $m->{response} // '';
    return {
        question_index => $gd->{question_index},
        answers        => $gd->{answers},
        done           => jbool( index( $resp, 'All questions have been answered' ) >= 0 ),
    };
}

# contexts_nav renders the builder and reduces to per-context {name, valid_steps}.
sub contexts_nav ($cb) {
    my $m   = $cb->to_hash;
    my %nav = ();
    for my $cname ( keys %$m ) {
        my $steps   = $m->{$cname}{steps} // [];
        my @reduced = map { { name => $_->{name}, valid_steps => $_->{valid_steps} } } @$steps;
        $nav{$cname} = \@reduced;
    }
    return \%nav;
}

sub main {
    my %out;

    # ---- global_data: set MERGES into the accumulated global data ----
    {
        my $a = demo_agent();
        $a->set_global_data( { company => 'SignalWire', tier => 'gold' } );
        $out{state_set_global_data} = $a->global_data;
    }
    {
        my $a = demo_agent();
        $a->update_global_data( { k1 => 'v1' } );
        $a->update_global_data( { k2 => 'v2' } );
        $out{state_update_global_data} = $a->global_data;
    }
    {
        # MERGE semantics: overlapping key wins, sibling survives.
        my $a = demo_agent();
        $a->set_global_data( { a => 1, b => 2 } );
        $a->set_global_data( { b => 99, c => 3 } );
        $out{state_global_data_merge} = $a->global_data;
    }

    # ---- sip-username registration on AgentBase (lowercased set) ----
    {
        my $a = demo_agent();
        $a->register_sip_username('Bob');
        $a->register_sip_username('alice');
        $out{state_register_sip_username} = [ sort @{ $a->sip_usernames } ];
    }
    {
        # dedup + case-fold: "Bob","BOB","bob" collapse to one.
        my $a = demo_agent();
        $a->register_sip_username('Bob');
        $a->register_sip_username('BOB');
        $a->register_sip_username('bob');
        $out{state_register_sip_username_dedup} = [ sort @{ $a->sip_usernames } ];
    }

    # ---- AgentServer sip-username mapping (username -> route) + lookup ----
    {
        my $s = SignalWire::Server::AgentServer->new;
        $s->setup_sip_routing( route => '/sip', auto_map => 0 );
        $s->register_sip_username( 'Bob',   '/agent' );
        $s->register_sip_username( 'sales', '/sales' );
        $out{server_sip_username_mapping} = {
            mapping        => $s->_sip_username_mapping,
            lookup_bob     => $s->_lookup_sip_route('bob'),
            lookup_BOB     => $s->_lookup_sip_route('BOB'),
            lookup_missing => $s->_lookup_sip_route('nope'),
        };
    }
    {
        # unregister removes the agent route from the registry.
        my $s = SignalWire::Server::AgentServer->new;
        $s->register( SignalWire::Agent::AgentBase->new( name => 'agent', route => '/agent' ), '/agent' );
        $s->register( SignalWire::Agent::AgentBase->new( name => 'other', route => '/other' ), '/other' );
        $s->unregister('/agent');
        $out{server_unregister} = [ sort keys %{ $s->get_agents } ];
    }

    # ---- routing-callback registration on SWMLService (path-normalized) ----
    {
        my $svc = SignalWire::SWML::Service->new( name => 'svc', route => '/svc' );
        my $noop = sub { return; };
        $svc->register_routing_callback( '/sip/', $noop );
        $svc->register_routing_callback( 'voice', $noop );
        $out{state_register_routing_callback} = [ sort keys %{ $svc->routing_callbacks } ];
    }

    # ---- verb-handler registration (verb_registry: "ai" preloaded) ----
    {
        my $svc = SignalWire::SWML::Service->new( name => 'svc', route => '/svc' );
        $svc->register_verb_handler( GreetVerbHandler->new('greet') );
        # Observe the introspectable verb registry directly (ships "ai" preloaded,
        # accrues registered handlers) — the STATE observable, no new public API.
        my $handlers = $svc->verb_registry->{handlers};
        $out{state_register_verb_handler} = {
            verbs       => [ sort keys %$handlers ],
            has_greet   => jbool( exists $handlers->{greet} ),
            has_ai      => jbool( exists $handlers->{ai} ),
            has_missing => jbool( exists $handlers->{nope} ),
        };
    }

    # ---- skill registration (SkillRegistry: name -> class, idempotent) ----
    {
        SignalWire::Skills::SkillRegistry->register_skill( 'custom_alpha', 'Some::Class' );
        SignalWire::Skills::SkillRegistry->register_skill( 'custom_beta',  'Some::Class' );
        SignalWire::Skills::SkillRegistry->register_skill( 'custom_alpha', 'Some::Class' );    # idempotent
        # Observe only the names this case registered (the class-global registry
        # may also hold auto-loaded builtins; the corpus observes the custom set,
        # which land in list_all_skill_sources's non-builtin "registered" bucket).
        my $sources = SignalWire::Skills::SkillRegistry->list_all_skill_sources;
        $out{state_register_skill} = [ sort grep { /^custom_/ } @{ $sources->{registered} } ];
    }

    # ---- InfoGatherer.submit_answer: records answer + advances index ----
    {
        my $ig = SignalWire::Prefabs::InfoGatherer->new(
            name      => 'demo',
            route     => '/demo',
            questions => [
                { key_name => 'name',  question_text => 'What is your name?' },
                { key_name => 'email', question_text => 'What is your email?' },
            ],
        );
        $out{infogatherer_submit_answer_first} = submit_answer_delta(
            $ig,
            { answer => 'Alice' },
            {   global_data => {
                    questions => [
                        { key_name => 'name',  question_text => 'What is your name?' },
                        { key_name => 'email', question_text => 'What is your email?' },
                    ],
                    question_index => 0,
                    answers        => [],
                }
            }
        );
    }
    {
        my $ig = SignalWire::Prefabs::InfoGatherer->new(
            name      => 'demo',
            route     => '/demo',
            questions => [
                { key_name => 'name',  question_text => 'What is your name?' },
                { key_name => 'email', question_text => 'What is your email?' },
            ],
        );
        $out{infogatherer_submit_answer_last} = submit_answer_delta(
            $ig,
            { answer => 'a@b.com' },
            {   global_data => {
                    questions => [
                        { key_name => 'name',  question_text => 'What is your name?' },
                        { key_name => 'email', question_text => 'What is your email?' },
                    ],
                    question_index => 1,
                    answers        => [ { key_name => 'name', answer => 'Alice' } ],
                }
            }
        );
    }

    # ---- contexts/steps navigation (valid_steps rendered per step) ----
    {
        my $a  = demo_agent();
        my $cb = $a->define_contexts;
        my $ctx = $cb->add_context('default');
        $ctx->add_step('greet')->set_text('Greet the caller.')->set_valid_steps( ['collect'] );
        $ctx->add_step('collect')->set_text('Collect their info.')->set_valid_steps( ['greet'] );
        $out{state_contexts_navigation} = contexts_nav($cb);
    }

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
