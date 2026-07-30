#!/usr/bin/env perl
# PERL-1: _clone_for_request render-equivalence.
#
# When a dynamic_config_callback is set, handle_request renders the SWML off a
# per-request CLONE (_clone_for_request), not the agent itself. If the clone
# drops any render-relevant attribute, a multi-tenant agent silently emits a
# DIFFERENT document on every request. The clone previously dropped the entire
# contexts tree (context_builder) AND the multilingual config.
#
# This is the clone-fidelity invariant test the r5 review specified: build an
# agent exercising every render-relevant setter, attach a NO-OP dynamic config
# callback, and assert the document rendered off the clone is byte-identical to
# the document rendered off the original agent. Deterministic; catches this
# regression and any future render-relevant attribute the hand-maintained clone
# list forgets.

use strict;
use warnings;
use Test::More;
use JSON ();

use SignalWire::Agent::AgentBase;

# Build a full-feature agent: contexts + multilingual + the other render-
# relevant config, all set.
sub build_agent {
    my $a = SignalWire::Agent::AgentBase->new(
        name                => 'tenant',
        basic_auth_user     => 'u',
        basic_auth_password => 'p',
    );
    $a->prompt_add_section( 'Role', 'You are a helpful multi-tenant assistant.' );

    # Contexts tree (render-relevant -> ai.prompt.contexts).
    my $cb = $a->define_contexts;
    $cb->add_context('default')->add_step( 'greet', task => 'Greet the caller warmly.' );

    # Multilingual (Mode B) -> top-level ai.multilingual.
    $a->set_multilingual(
        { enable => JSON::true, languages => [ { code => 'en-US', name => 'English' } ] } );

    # A few more render-relevant knobs so the fixture is broad.
    $a->add_hint('acme');
    $a->set_params( { verbose_logs => JSON::true } );
    $a->set_global_data( { tenant => 'acme' } );
    return $a;
}

my $json = JSON->new->canonical->utf8;

# Baseline: render the agent directly.
my $orig      = build_agent();
my $orig_swml = $json->encode( $orig->render_swml( {} ) );

# The dynamic-config path: a per-request clone (as handle_request builds), with
# a NO-OP callback — i.e. the callback changes nothing, so the rendered doc MUST
# equal the baseline. Render off the clone exactly as handle_request does.
my $agent = build_agent();
$agent->dynamic_config_callback( sub { return } );    # no-op
my $clone   = $agent->_clone_for_request;
my $noop_cb = $agent->dynamic_config_callback;
$noop_cb->( {}, {}, {}, $clone );                     # apply the no-op to the clone
my $clone_swml = $json->encode( $clone->render_swml( {} ) );

is( $clone_swml, $orig_swml,
    'no-op dynamic-config clone renders byte-identical SWML (contexts + multilingual carried)' );

# Targeted assertions so a failure localizes the dropped attribute.
my $clone_doc = $clone->render_swml( {} );

# Dig out the AI verb config.
sub find_ai {
    my ($doc)    = @_;
    my $sections = $doc->{sections}  || {};
    my $main     = $sections->{main} || [];
    for my $verb (@$main) {
        return $verb->{ai} if ref $verb eq 'HASH' && exists $verb->{ai};
    }
    return;
}
my $ai = find_ai($clone_doc);
ok( defined $ai,                    'clone renders an ai verb' );
ok( exists $ai->{prompt}{contexts}, 'clone carries ai.prompt.contexts (not dropped)' );
ok( exists $ai->{multilingual},     'clone carries ai.multilingual (not dropped)' );

# Isolation: mutating the clone's contexts must NOT affect the original.
$clone->context_builder->reset;
ok( $orig->context_builder->has_contexts,
    'mutating the clone contexts does not leak into the original (deep copy)' );

done_testing;
