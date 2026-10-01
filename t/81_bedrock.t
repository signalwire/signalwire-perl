#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

# Real-behavior tests for SignalWire::Agents::Bedrock (class BedrockAgent) —
# the Amazon Bedrock voice-to-voice agent. Parity with Python's
# signalwire.agents.bedrock.BedrockAgent, mirroring Ruby's
# tests/bedrock_agent_test.rb. render_swml returns a hashref (like Ruby's
# base render), so the transformed amazon_bedrock verb is read off that.

use_ok('SignalWire::Agents::Bedrock');

# Pull the amazon_bedrock verb object out of a rendered SWML doc.
sub bedrock_verb {
    my ($agent) = @_;
    my $main = $agent->render_swml->{sections}{main};
    for my $v (@$main) {
        return $v->{amazon_bedrock} if ref $v eq 'HASH' && exists $v->{amazon_bedrock};
    }
    return;
}

subtest 'defaults' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    is( $agent->name,  'bedrock_agent', 'default name' );
    is( $agent->route, '/bedrock',      'default route' );
};

subtest 'renders amazon_bedrock verb not ai' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    $agent->set_prompt_text('Hello');
    my $main = $agent->render_swml->{sections}{main};
    ok( ( grep { ref $_ eq 'HASH' && exists $_->{amazon_bedrock} } @$main ),
        'amazon_bedrock verb present' );
    ok( !( grep { ref $_ eq 'HASH' && exists $_->{ai} } @$main ), 'ai verb transformed away' );
};

subtest 'voice and inference params in prompt' => sub {
    my $agent = SignalWire::Agents::Bedrock->new(
        voice_id    => 'joanna',
        temperature => 0.3,
        top_p       => 0.8,
    );
    $agent->set_prompt_text('Hi');
    my $prompt = bedrock_verb($agent)->{prompt};
    is( $prompt->{voice_id}, 'joanna', 'voice_id in prompt' );
    cmp_ok( abs( $prompt->{temperature} - 0.3 ), '<', 1e-9, 'temperature in prompt' );
    cmp_ok( abs( $prompt->{top_p} - 0.8 ),       '<', 1e-9, 'top_p in prompt' );
};

subtest 'system_prompt constructor arg' => sub {
    my $agent = SignalWire::Agents::Bedrock->new( system_prompt => 'You are helpful' );
    is( bedrock_verb($agent)->{prompt}{text}, 'You are helpful', 'system_prompt applied as text' );
};

subtest 'bedrock object keys with tool and post_prompt' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    $agent->set_prompt_text('Hi');
    $agent->define_tool( name => 't', description => 'd', handler => sub { {} } );
    $agent->set_post_prompt('summarize');
    my $ab = bedrock_verb($agent);

    ok( exists $ab->{prompt},      'prompt key present' );
    ok( exists $ab->{SWAIG},       'SWAIG key present (tool defined)' );
    ok( exists $ab->{post_prompt}, 'post_prompt key present' );
};

subtest 'nil keys dropped' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    $agent->set_prompt_text('Hi');
    my $ab = bedrock_verb($agent);
    ok( !exists $ab->{post_prompt}, 'unset post_prompt dropped (not undef-valued)' );
    ok( !exists $ab->{SWAIG},       'no tools -> SWAIG dropped' );
    ok( !exists $ab->{global_data}, 'no global_data -> dropped' );
};

subtest 'set_voice' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    $agent->set_prompt_text('Hi');
    my $ret = $agent->set_voice('stephen');
    is( $ret,                                     $agent,    'set_voice returns self' );
    is( bedrock_verb($agent)->{prompt}{voice_id}, 'stephen', 'voice updated' );
};

subtest 'set_inference_params partial update' => sub {
    my $agent = SignalWire::Agents::Bedrock->new( temperature => 0.7, top_p => 0.9 );
    $agent->set_prompt_text('Hi');
    $agent->set_inference_params( temperature => 0.2 );
    my $prompt = bedrock_verb($agent)->{prompt};
    cmp_ok( abs( $prompt->{temperature} - 0.2 ), '<', 1e-9, 'temperature updated' );
    cmp_ok( abs( $prompt->{top_p} - 0.9 ),       '<', 1e-9, 'top_p unchanged (partial update)' );
};

subtest 'set_llm_temperature redirects to inference' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    $agent->set_prompt_text('Hi');
    $agent->set_llm_temperature(0.42);
    cmp_ok( abs( bedrock_verb($agent)->{prompt}{temperature} - 0.42 ),
        '<', 1e-9, 'temperature set via redirect' );
};

subtest 'set_llm_model is noop returns self' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    is( $agent->set_llm_model('anthropic.claude'), $agent, 'noop returns self' );
};

subtest 'set_prompt_llm_params noop returns self' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    is( $agent->set_prompt_llm_params( temperature => 0.5 ), $agent, 'noop returns self' );
};

subtest 'set_post_prompt_llm_params noop returns self' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    is( $agent->set_post_prompt_llm_params( model => 'gpt-4o' ), $agent, 'noop returns self' );
};

subtest 'text-model-only prompt keys stripped' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    $agent->set_prompt_text('Hi');

    # Inject a text-model-only param into the prompt config. It must not
    # survive into the bedrock prompt object.
    $agent->prompt_llm_params( { presence_penalty => 0.5 } );
    my $prompt = bedrock_verb($agent)->{prompt};
    ok( !exists $prompt->{presence_penalty}, 'presence_penalty stripped' );
    ok( exists $prompt->{text},              'text prompt survives' );
};

subtest 'to_string / stringification representation (__repr__)' => sub {
    my $agent    = SignalWire::Agents::Bedrock->new( name => 'myb', voice_id => 'joanna' );
    my $expected = "BedrockAgent(name='myb', route='/bedrock', voice='joanna')";
    is( $agent->to_string, $expected, 'to_string representation' );
    is( "$agent",          $expected, 'overloaded stringification' );
};

subtest 'is AgentBase subclass' => sub {
    my $agent = SignalWire::Agents::Bedrock->new;
    isa_ok( $agent, 'SignalWire::Agent::AgentBase', 'BedrockAgent' );
};

done_testing;
