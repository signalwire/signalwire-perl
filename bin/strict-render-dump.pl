#!/usr/bin/env perl
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# strict-render-dump.pl — the Perl port's STRICT-RENDER dump program for the
# cross-port negative differ (porting-sdk/scripts/diff_port_strict_render.py).
#
# Where swml-dump.pl pins what a VALID build RENDERS, this program pins what a
# MISSHAPEN build must DO: raise/die instead of silently dropping or accepting
# it. It builds EACH of the 18 strict_render_corpus cases in Perl idiom, wraps
# each build in an eval{} block, and treats a die (a set $@) as "raised" and a
# clean build as "ok". It emits ONE JSON object mapping
#
#     case-id -> "raised" | "ok"
#
# to stdout (JSON only). The strict-render differ compares each case's outcome
# against the python oracle. The SDK's validation-warning storm goes to stderr,
# so the wired dump-cmd is:
#
#     perl -Ilib bin/strict-render-dump.pl 2>/dev/null
#
# SWMLService cases  -> a Service with full_validation ON + add_verb(name,cfg).
# AgentBase cases    -> define_tool + define_contexts -> add_context -> add_step
#                       -> set_text/set_functions/set_valid_contexts, then the
#                       ContextBuilder validate (via to_hash).

use strict;
use warnings;
use feature 'signatures';
no warnings 'experimental::signatures';

use FindBin qw($RealBin);
use File::Spec;
use JSON ();

use lib File::Spec->catdir( $RealBin, File::Spec->updir, 'lib' );

use SignalWire::SWML::Service;
use SignalWire::Agent::AgentBase;

# Build a Service with strict validation enabled (mirrors python's
# SWMLService(schema_validation=True)).
sub new_service {
    my $svc = SignalWire::SWML::Service->new( name => 's', route => '/s' );
    $svc->full_validation(1);
    return $svc;
}

# Build an AgentBase with strict validation on (contexts validate on to_hash).
sub new_agent {
    return SignalWire::Agent::AgentBase->new( name => 'a', route => '/a' );
}

# Run one SWMLService verb-level case. "raised" iff the build dies.
sub run_swml_case ($build) {
    my $ok = eval {
        $build->();
        1;
    };
    return ( $ok && !$@ ) ? 'ok' : 'raised';
}

# Run one AgentBase contexts-level case: a fresh agent handed to $build.
# "raised" iff the build dies.
sub run_agent_case ($build) {
    my $agent = new_agent();
    my $ok    = eval {
        $build->($agent);
        1;
    };
    return ( $ok && !$@ ) ? 'ok' : 'raised';
}

sub main {
    my %out;

    # ==============================================================
    # Verb-level strict render (SWMLService, validation ON)
    # ==============================================================

    # unknown verb 'foobar' must raise.
    $out{strict_unknown_verb} = run_swml_case(
        sub {
            new_service()->add_verb( 'foobar', {} );
        }
    );

    # misspelled 'maxduration' (should be max_duration) must raise.
    $out{strict_answer_misspelled_key} = run_swml_case(
        sub {
            new_service()->add_verb( 'answer', { maxduration => 5 } );
        }
    );

    # unknown key 'wibble' on a closed verb must raise.
    $out{strict_answer_unknown_key} = run_swml_case(
        sub {
            new_service()->add_verb( 'answer', { wibble => 1 } );
        }
    );

    # misspelled 'urlz' (should be urls) must raise.
    $out{strict_play_misspelled_key} = run_swml_case(
        sub {
            new_service()->add_verb( 'play', { urlz => ['say:hi'] } );
        }
    );

    # a valid key plus an unknown extra key still must raise.
    $out{strict_play_valid_plus_unknown_key} = run_swml_case(
        sub {
            new_service()->add_verb( 'play', { url => 'say:hi', foo => 1 } );
        }
    );

    # misspelled 'formatt' (should be format) must raise.
    $out{strict_record_misspelled_key} = run_swml_case(
        sub {
            new_service()->add_verb( 'record', { formatt => 'wav' } );
        }
    );

    # max_duration must be numeric; a string must raise.
    $out{strict_answer_wrong_type} = run_swml_case(
        sub {
            new_service()->add_verb( 'answer', { max_duration => 'notanumber' } );
        }
    );

    # GAP1: misspelled top-level ai key 'temperatur' must raise.
    $out{strict_ai_misspelled_top_key} = run_swml_case(
        sub {
            new_service()->add_verb( 'ai', { prompt => { text => 'hi' }, temperatur => 0.5 } );
        }
    );

    # GAP1: unknown top-level ai key 'zzz' must raise.
    $out{strict_ai_unknown_top_key} = run_swml_case(
        sub {
            new_service()->add_verb( 'ai', { prompt => { text => 'hi' }, zzz => 1 } );
        }
    );

    # the ai verb requires a prompt; omitting it must raise.
    $out{strict_ai_missing_prompt} = run_swml_case(
        sub {
            new_service()->add_verb( 'ai', { post_prompt => { text => 'bye' } } );
        }
    );

    # ---- good documents must still render ----

    # a valid answer verb must render.
    $out{strict_answer_ok} = run_swml_case(
        sub {
            new_service()->add_verb( 'answer', { max_duration => 5 } );
        }
    );

    # a valid play verb must render.
    $out{strict_play_ok} = run_swml_case(
        sub {
            new_service()->add_verb( 'play', { url => 'say:hi' } );
        }
    );

    # a valid ai verb must render.
    $out{strict_ai_ok} = run_swml_case(
        sub {
            new_service()->add_verb( 'ai', { prompt => { text => 'hi' } } );
        }
    );

    # ai.params is the DELIBERATE open door; a key inside it must render.
    $out{strict_ai_params_open_ok} = run_swml_case(
        sub {
            new_service()
                ->add_verb( 'ai',
                { prompt => { text => 'hi' }, params => { some_future_param => 1 } } );
        }
    );

    # ==============================================================
    # Contexts-level strict render (AgentBase; dangling refs)
    # ==============================================================

    # GAP2/F3: step whitelists 'get_datetime', an unregistered/non-native
    # function — dangling reference must raise.
    $out{strict_dangling_step_function} = run_agent_case(
        sub ($agent) {
            $agent->define_tool(
                name        => 'order_status',
                description => 'look up an order',
                parameters  => {},
                handler     => sub { return; },
            );
            my $cb   = $agent->define_contexts;
            my $ctx  = $cb->add_context('default');
            my $step = $ctx->add_step('help');
            $step->set_text('help');
            $step->set_functions( [ 'order_status', 'get_datetime' ] );
            $cb->to_hash;
        }
    );

    # a step referencing a registered tool must render.
    $out{strict_registered_step_function_ok} = run_agent_case(
        sub ($agent) {
            $agent->define_tool(
                name        => 'order_status',
                description => 'look up an order',
                parameters  => {},
                handler     => sub { return; },
            );
            my $cb   = $agent->define_contexts;
            my $ctx  = $cb->add_context('default');
            my $step = $ctx->add_step('help');
            $step->set_text('help');
            $step->set_functions( ['order_status'] );
            $cb->to_hash;
        }
    );

    # reserved native tools (next_step/change_context) are not dangling.
    $out{strict_reserved_native_function_ok} = run_agent_case(
        sub ($agent) {
            my $cb   = $agent->define_contexts;
            my $ctx  = $cb->add_context('default');
            my $step = $ctx->add_step('help');
            $step->set_text('help');
            $step->set_functions( [ 'next_step', 'change_context' ] );
            $cb->to_hash;
        }
    );

    # valid_contexts references an undefined context — must raise.
    $out{strict_dangling_valid_context} = run_agent_case(
        sub ($agent) {
            my $cb   = $agent->define_contexts;
            my $ctx  = $cb->add_context('default');
            my $step = $ctx->add_step('help');
            $step->set_text('help');
            $step->set_valid_contexts( ['nowhere'] );
            $cb->to_hash;
        }
    );

    print JSON->new->canonical->encode( \%out ), "\n";
    return 0;
}

exit main();
