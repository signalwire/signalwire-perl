package SignalWire::Agents::Bedrock;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# Bedrock Agent - Amazon Bedrock voice-to-voice integration.
#
# Perl port of signalwire.agents.bedrock.BedrockAgent
# (signalwire-python/signalwire/signalwire/agents/bedrock.py),
# structurally mirroring Ruby's SignalWire::Agents::BedrockAgent
# (signalwire-ruby/lib/signalwire/agents/bedrock.rb).
#
# BedrockAgent extends AgentBase to support Amazon Bedrock's
# voice-to-voice model while keeping compatibility with all SignalWire
# agent features (skills, POM, SWAIG functions, post-prompt). The one
# difference from a standard agent is that it emits SWML with the
# dedicated `amazon_bedrock` verb instead of `ai`.

use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor).
use feature 'signatures';
extends 'SignalWire::Agent::AgentBase';

# Prompt keys that apply to text models but not to Bedrock's
# voice-to-voice model; stripped from the prompt config.
my @TEXT_MODEL_ONLY_PROMPT_KEYS = qw(barge_confidence presence_penalty frequency_penalty);

# ---------- attributes ----------

has voice_id    => ( is => 'rw', default => sub { 'matthew' } );
has temperature => ( is => 'rw', default => sub { 0.7 } );
has top_p       => ( is => 'rw', default => sub { 0.9 } );
has max_tokens  => ( is => 'rw', default => sub { 1024 } );

# system_prompt is a construction-only convenience: if set, it is applied
# via set_prompt_text after the base agent is built (see BUILD).
has system_prompt => ( is => 'ro', default => sub { undef } );

# ---------- construction ----------

# Python parity: __init__(name="bedrock_agent", route="/bedrock",
# system_prompt=None, voice_id="matthew", temperature=0.7, top_p=0.9,
# max_tokens=1024, **kwargs). AgentBase defaults name='agent' / route='/';
# override them to the Bedrock defaults only when left unset, then apply
# an optional system_prompt.
sub BUILD ( $self, $args ) {
    $self->name('bedrock_agent') if $self->name eq 'agent';
    $self->route('/bedrock')     if $self->route eq '/';

    $self->set_prompt_text( $self->system_prompt )
        if defined $self->system_prompt && length $self->system_prompt;
    return;
}

# ---------- SWML render override ----------

# Render the SWML document, transforming the `ai` verb into an
# `amazon_bedrock` verb.
#
# Python parity: _render_swml overrides the base render to swap the `ai`
# verb structure for `amazon_bedrock`. Perl's render_swml (like Ruby's
# base render) builds a hashref (not a JSON string), so this operates on
# that hashref directly.
sub render_swml ( $self, $request_env = undef ) {
    my $swml = $self->SUPER::render_swml($request_env);

    my $main = eval { $swml->{sections}{main} };
    return $swml unless ref $main eq 'ARRAY';

    for my $i ( 0 .. $#$main ) {
        my $verb = $main->[$i];
        next unless ref $verb eq 'HASH' && exists $verb->{ai};
        $main->[$i] = { amazon_bedrock => $self->_build_bedrock_object( $verb->{ai} ) };
        last;
    }
    return $swml;
}

# ---------- Bedrock-specific setters ----------

# Set the Bedrock voice id. Returns $self.
sub set_voice ( $self, $voice_id ) {
    $self->voice_id($voice_id);
    return $self;
}

# Update Bedrock inference parameters. Only defined values are applied.
# Python parity: set_inference_params(temperature=None, top_p=None,
# max_tokens=None). Returns $self.
sub set_inference_params ( $self, %opts ) {
    $self->temperature( $opts{temperature} ) if defined $opts{temperature};
    $self->top_p( $opts{top_p} )             if defined $opts{top_p};
    $self->max_tokens( $opts{max_tokens} )   if defined $opts{max_tokens};
    return $self;
}

# Set LLM model — not applicable for Bedrock (fixed voice-to-voice model).
# Logs a warning and does nothing. Returns $self.
sub set_llm_model ( $self, $model ) {
    $self->_logger->warn(
        "set_llm_model('$model') called but Bedrock uses a fixed voice-to-voice model");
    return $self;
}

# Set LLM temperature — redirects to set_inference_params. Returns $self.
sub set_llm_temperature ( $self, $temperature ) {
    return $self->set_inference_params( temperature => $temperature );
}

# Set post-prompt LLM parameters — not applicable for Bedrock (the
# post-prompt uses OpenAI configured server-side). Warns and no-ops.
# Returns $self.
sub set_post_prompt_llm_params ( $self, %params ) {
    $self->_logger->warn(
'set_post_prompt_llm_params() called but Bedrock post-prompt uses OpenAI configured in C code'
    );
    return $self;
}

# Set prompt LLM parameters — use set_inference_params instead for
# Bedrock. Warns and no-ops. Returns $self.
sub set_prompt_llm_params ( $self, %params ) {
    $self->_logger->warn('set_prompt_llm_params() called - use set_inference_params() for Bedrock');
    return $self;
}

# String representation of the agent.
#
# Python parity: __repr__. Perl has no __repr__ dunder — the enumerator
# maps this to_string method onto __repr__ via %METHOD_OVERRIDES. It is
# also wired as the overloaded stringification operator so `"$agent"`
# yields the same representation.
# Overload stringification via a thin shim: Perl passes ($self, $other,
# $swap) to an overload handler, so we can't point '""' straight at the
# single-arg to_string; the shim drops the extra overload args.
use overload '""' => sub { $_[0]->to_string }, fallback => 1;

sub to_string ($self) {
    return sprintf( "BedrockAgent(name='%s', route='%s', voice='%s')",
        $self->name, $self->route, $self->voice_id, );
}

# ---------- private helpers ----------

# Build the amazon_bedrock verb object from the base `ai` config. Voice +
# inference params live inside the prompt config; only defined keys are
# emitted (matches the Python reference and the amazon_bedrock schema).
sub _build_bedrock_object ( $self, $ai_config ) {
    my %object = (
        prompt          => $self->_add_voice_to_prompt( $ai_config->{prompt} || {} ),
        SWAIG           => $ai_config->{SWAIG},
        params          => $ai_config->{params},
        global_data     => $ai_config->{global_data},
        post_prompt     => $ai_config->{post_prompt},
        post_prompt_url => $ai_config->{post_prompt_url},
    );
    delete $object{$_} for grep { !defined $object{$_} } keys %object;
    return \%object;
}

# Add voice + inference params to the prompt object, stripping
# text-model-only keys.
sub _add_voice_to_prompt ( $self, $prompt_config ) {
    my %filtered = %{ $prompt_config || {} };
    delete $filtered{$_} for @TEXT_MODEL_ONLY_PROMPT_KEYS;
    $filtered{voice_id}    = $self->voice_id;
    $filtered{temperature} = $self->temperature;
    $filtered{top_p}       = $self->top_p;
    return \%filtered;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Agents::Bedrock - Amazon Bedrock voice-to-voice agent

=head1 SYNOPSIS

    use SignalWire::Agents::Bedrock;

    my $agent = SignalWire::Agents::Bedrock->new(
        name          => 'my_bedrock',
        route         => '/bedrock',
        system_prompt => 'You are a helpful assistant.',
        voice_id      => 'matthew',
        temperature   => 0.7,
    );

    $agent->set_voice('joanna')->set_inference_params( top_p => 0.95 );

    my $swml = $agent->render_swml;   # emits the amazon_bedrock verb
    print "$agent\n";                 # BedrockAgent(name='...', route='...', voice='...')

=head1 DESCRIPTION

L<SignalWire::Agents::Bedrock> (class C<BedrockAgent>) is the Perl port of
C<signalwire.agents.bedrock.BedrockAgent>. It extends
L<SignalWire::Agent::AgentBase>, so it keeps every standard agent feature
(POM, skills, SWAIG functions, post-prompt). The only difference is that
C<render_swml> transforms the base C<ai> verb into an C<amazon_bedrock>
verb whose object carries the voice and inference parameters inside its
prompt config, stripping text-model-only keys
(C<barge_confidence>, C<presence_penalty>, C<frequency_penalty>) and
emitting only the keys the schema expects (C<prompt>, C<SWAIG>,
C<params>, C<global_data>, C<post_prompt>, C<post_prompt_url>).

=head2 Methods

=over 4

=item * C<new(%opts)> — C<name> (default C<bedrock_agent>), C<route>
(default C</bedrock>), C<system_prompt>, C<voice_id> (default
C<matthew>), C<temperature> (0.7), C<top_p> (0.9), C<max_tokens> (1024),
plus any AgentBase arguments.

=item * C<set_voice($voice_id)> — set the Bedrock voice id.

=item * C<set_inference_params(temperature =E<gt> ..., top_p =E<gt> ...,
max_tokens =E<gt> ...)> — update inference params (only defined values).

=item * C<set_llm_temperature($t)> — redirects to C<set_inference_params>.

=item * C<set_llm_model($m)>, C<set_prompt_llm_params(%p)>,
C<set_post_prompt_llm_params(%p)> — warn and no-op (not applicable to
Bedrock).

=item * C<to_string> — the C<BedrockAgent(name=..., route=..., voice=...)>
representation (also the overloaded stringification; the cross-language
enumerator maps it onto Python's C<__repr__>).

=back

All setters return C<$self> for chaining.

=head1 SEE ALSO

L<SignalWire::Agent::AgentBase>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
