#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# STRICT-RENDER contract (Wave-2 P#5) — the native Perl port of the python
# reference tests/unit/core/test_swml_strict_render.py.
#
# Building/rendering an SWML document with a MISSHAPEN config, an UNKNOWN verb,
# or a MISSPELLED/unknown key must DIE (raise) — not silently drop or accept
# it. A VALID build must still render. This suite pins both directions at the
# Service (verb) level and the AgentBase/ContextBuilder (dangling-ref) level,
# mirroring the shared strict_render_corpus the cross-port differ enforces.

use_ok('SignalWire::SWML::Service');
use_ok('SignalWire::Agent::AgentBase');

# A Service with strict schema validation ON (python: schema_validation=True).
sub svc {
    my $s = SignalWire::SWML::Service->new( name => 's', route => '/s' );
    $s->full_validation(1);
    return $s;
}

# Does building this verb raise? Returns 1 (raised) / 0 (clean).
sub raises_verb {
    my ( $verb, $config ) = @_;
    my $ok = eval { svc()->add_verb( $verb, $config ); 1 };
    return ( $ok && !$@ ) ? 0 : 1;
}

# ------------------------------------------------------------------
# Verb-level: misshapen configs MUST raise.
# ------------------------------------------------------------------
subtest 'unknown verb raises' => sub {
    ok( raises_verb( 'foobar', {} ), "unknown verb 'foobar' raises" );
};

subtest 'misspelled / unknown keys on closed verbs raise' => sub {
    ok( raises_verb( 'answer', { maxduration => 5 } ), 'answer maxduration (misspelled) raises' );
    ok( raises_verb( 'answer', { wibble      => 1 } ), 'answer wibble (unknown) raises' );
    ok( raises_verb( 'play',   { urlz => ['say:hi'] } ), 'play urlz (misspelled) raises' );
    ok( raises_verb( 'play',   { url => 'say:hi', foo => 1 } ), 'play valid+unknown raises' );
    ok( raises_verb( 'record', { formatt => 'wav' } ), 'record formatt (misspelled) raises' );
};

subtest 'wrong-typed config raises' => sub {
    ok( raises_verb( 'answer', { max_duration => 'notanumber' } ),
        'answer max_duration non-numeric raises' );
};

subtest 'ai verb: unknown/misspelled top-level keys raise (GAP1)' => sub {
    ok( raises_verb( 'ai', { prompt => { text => 'hi' }, temperatur => 0.5 } ),
        "ai temperatur (misspelled top key) raises" );
    ok( raises_verb( 'ai', { prompt => { text => 'hi' }, zzz => 1 } ),
        "ai zzz (unknown top key) raises" );
    ok( raises_verb( 'ai', { post_prompt => { text => 'bye' } } ),
        "ai without required prompt raises" );
};

# ------------------------------------------------------------------
# Verb-level: valid configs MUST render (regression guard).
# ------------------------------------------------------------------
subtest 'valid verbs render' => sub {
    ok( !raises_verb( 'answer', { max_duration => 5 } ), 'valid answer renders' );
    ok( !raises_verb( 'play',   { url => 'say:hi' } ),   'valid play renders' );
    ok( !raises_verb( 'ai',     { prompt => { text => 'hi' } } ), 'valid ai renders' );

    # ai.params is the DELIBERATE open door for LLM tuning; a key inside it is
    # not a misspelling and MUST render.
    ok( !raises_verb( 'ai', { prompt => { text => 'hi' }, params => { some_future_param => 1 } } ),
        'ai.params open door renders' );
};

# ------------------------------------------------------------------
# Validation-off path is unchanged: a Service without full_validation
# accepts the same misshapen config without raising (parity: the schema
# pass is a no-op when validation is disabled).
# ------------------------------------------------------------------
subtest 'validation-off path does not raise' => sub {
    my $s  = SignalWire::SWML::Service->new( name => 's', route => '/s' );
    my $ok = eval { $s->add_verb( 'answer', { wibble => 1 } ); 1 };
    ok( $ok, 'add_verb with validation off accepts unknown key (no strict raise)' );
};

# ------------------------------------------------------------------
# Contexts-level: dangling references.
# ------------------------------------------------------------------

# Build a fresh agent + one-context/one-step, running $tweak on the step, then
# validate (via to_hash). Returns 1 (raised) / 0 (clean).
sub raises_ctx {
    my ($tweak) = @_;
    my $ok = eval {
        my $agent = SignalWire::Agent::AgentBase->new( name => 'a', route => '/a' );
        $tweak->($agent);
        1;
    };
    return ( $ok && !$@ ) ? 0 : 1;
}

subtest 'dangling step set_functions reference raises (GAP2/F3)' => sub {
    my $raised = raises_ctx( sub {
        my ($agent) = @_;
        $agent->define_tool(
            name => 'order_status', description => 'look up an order',
            parameters => {}, handler => sub { return; },
        );
        my $cb   = $agent->define_contexts;
        my $ctx  = $cb->add_context('default');
        my $step = $ctx->add_step('help');
        $step->set_text('help');
        $step->set_functions( [ 'order_status', 'get_datetime' ] );  # get_datetime dangling
        $cb->to_hash;
    } );
    ok( $raised, "step whitelisting an unregistered function raises" );
};

subtest 'registered / reserved-native step functions render' => sub {
    my $registered = raises_ctx( sub {
        my ($agent) = @_;
        $agent->define_tool(
            name => 'order_status', description => 'look up an order',
            parameters => {}, handler => sub { return; },
        );
        my $cb   = $agent->define_contexts;
        my $ctx  = $cb->add_context('default');
        my $step = $ctx->add_step('help');
        $step->set_text('help');
        $step->set_functions( ['order_status'] );
        $cb->to_hash;
    } );
    ok( !$registered, "step referencing a registered tool renders" );

    my $native = raises_ctx( sub {
        my ($agent) = @_;
        my $cb   = $agent->define_contexts;
        my $ctx  = $cb->add_context('default');
        my $step = $ctx->add_step('help');
        $step->set_text('help');
        $step->set_functions( [ 'next_step', 'change_context' ] );
        $cb->to_hash;
    } );
    ok( !$native, "reserved native tools (next_step/change_context) are not dangling" );
};

subtest 'dangling valid_contexts reference raises' => sub {
    my $raised = raises_ctx( sub {
        my ($agent) = @_;
        my $cb   = $agent->define_contexts;
        my $ctx  = $cb->add_context('default');
        my $step = $ctx->add_step('help');
        $step->set_text('help');
        $step->set_valid_contexts( ['nowhere'] );
        $cb->to_hash;
    } );
    ok( $raised, "valid_contexts referencing an undefined context raises" );
};

done_testing;
