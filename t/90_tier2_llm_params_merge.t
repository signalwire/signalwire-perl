#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# =============================================================================
# Behavioral contract #2 — set_prompt_llm_params / set_post_prompt_llm_params
# MERGE (not replace).
#
# Python (ai_config_mixin.py): self._prompt_llm_params.update(params) — merges.
# Call the setter twice with DISTINCT keys, render, and assert BOTH keys are
# present on the rendered AI verb. A replace-stub would drop the first key.
# =============================================================================

use SignalWire::Agent::AgentBase;

# Pull the ai verb's prompt/post_prompt blocks out of a rendered SWML doc.
sub ai_blocks {
    my ($agent) = @_;
    my $swml    = $agent->render_swml;
    my ($ai)    = map { $_->{ai} } grep { exists $_->{ai} } @{ $swml->{sections}{main} };
    return $ai;
}

subtest 'set_prompt_llm_params merges across two calls' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'merge', use_pom => 1 );
    $agent->prompt_add_section( 'Role', 'You are a test agent.' );

    $agent->set_prompt_llm_params( temperature => 0.5 );
    $agent->set_prompt_llm_params( top_p       => 0.9 );

    my $ai = ai_blocks($agent);
    ok( defined $ai, 'AI verb rendered' );

    # BOTH keys must survive the second call (merge, not replace).
    is( $ai->{prompt}{temperature}, 0.5, 'temperature from the FIRST call is retained' );
    is( $ai->{prompt}{top_p},       0.9, 'top_p from the SECOND call is present' );
};

subtest 'set_post_prompt_llm_params merges across two calls' => sub {
    my $agent = SignalWire::Agent::AgentBase->new( name => 'merge_post', use_pom => 1 );
    $agent->prompt_add_section( 'Role', 'You are a test agent.' );

    # A post_prompt must exist for the post_prompt block to render.
    $agent->set_post_prompt('Summarize the conversation.');

    $agent->set_post_prompt_llm_params( temperature      => 0.3 );
    $agent->set_post_prompt_llm_params( presence_penalty => 0.2 );

    my $ai = ai_blocks($agent);
    ok( defined $ai,               'AI verb rendered' );
    ok( exists $ai->{post_prompt}, 'post_prompt block present' );

    is( $ai->{post_prompt}{temperature},
        0.3, 'post_prompt temperature from the FIRST call is retained' );
    is( $ai->{post_prompt}{presence_penalty},
        0.2, 'post_prompt presence_penalty from the SECOND call is present' );
};

done_testing;
