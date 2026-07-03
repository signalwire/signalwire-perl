package SignalWire::Prefabs::InfoGatherer;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use JSON qw(encode_json);
extends 'SignalWire::Agent::AgentBase';

has questions => ( is => 'ro', default => sub { [] } );

# Registered per-request question callback (dynamic mode) and the
# original static question list captured at construction.
has question_callback => ( is => 'rw', default => sub { undef } );
has static_questions  => ( is => 'rw', default => sub { undef } );

# Fallback questions used in dynamic mode when no callback is registered
# or the callback raises (mirrors Python's / ruby's fallback list).
my $FALLBACK_QUESTIONS = [
    { key_name => 'name',    question_text => 'What is your name?' },
    { key_name => 'message', question_text => 'How can I help you today?' },
];

sub BUILD {
    my ( $self, $args ) = @_;

    # Set defaults
    $self->name('info_gatherer')   if $self->name eq 'agent';
    $self->route('/info_gatherer') if $self->route eq '/';
    $self->use_pom(1);

    my $questions = $self->questions;

    # Capture the static question list; an empty list means dynamic mode
    # (questions resolved per-request via set_question_callback).
    $self->static_questions( ( $questions && @$questions ) ? $questions : undef );

    # Set global data
    $self->set_global_data(
        {
            questions      => $questions,
            question_index => 0,
            answers        => [],
        }
    );

    # Build prompt
    $self->prompt_add_section(
        'Information Gathering',
'You are an information-gathering assistant. Your job is to ask the user a series of questions and collect their answers.',
        bullets => [
            'Ask questions one at a time in order',
            'Wait for the user to answer before asking the next question',
            'Confirm answers when the question requires confirmation',
            'Use start_questions to begin and submit_answer for each response',
        ],
    );

    # Register tools
    $self->define_tool(
        name        => 'start_questions',
        description => 'Start the question-gathering process and return the first question',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ( $a, $raw ) = @_;
            return $self->start_questions( $a, $raw );
        },
    );

    $self->define_tool(
        name        => 'submit_answer',
        description => 'Submit an answer to the current question',
        parameters  => {
            type       => 'object',
            properties => {
                answer            => { type => 'string', description => 'The answer' },
                confirmed_by_user =>
                    { type => 'boolean', description => 'User confirmed this answer' },
            },
            required => ['answer'],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            return $self->submit_answer( $a, $raw );
        },
    );
    return;
}

# Register a callback for dynamic, per-request question configuration —
# Python parity (InfoGathererAgent.set_question_callback). The callback
# receives (query_params, body_params, headers) and returns the list of
# questions to ask on that call. Returns $self for chaining.
sub set_question_callback {
    my ( $self, $callback ) = @_;
    $self->question_callback($callback);
    return $self;
}

# Tool handler: start_questions — returns the first configured question.
sub start_questions {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my @questions = @{ $self->questions };
    unless (@questions) {
        return SignalWire::SWAIG::FunctionResult->new(
            response => "I don't have any questions to ask." );
    }

    my $first = $questions[0];
    my $n     = scalar @questions;
    return SignalWire::SWAIG::FunctionResult->new(
        response => "[Question 1 of $n]: \"$first->{question_text}\"" );
}

# Tool handler: submit_answer — records the answer for the current
# question (state is tracked in global_data in a real deployment).
sub submit_answer {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;
    my $answer = $args->{answer} // '';
    return SignalWire::SWAIG::FunctionResult->new( response => "Answer recorded: $answer" );
}

# Lifecycle hook: on_swml_request — Python parity
# (InfoGathererAgent.on_swml_request). In dynamic mode, invokes the
# registered question callback (or a fallback) and returns a
# { global_data => {...} } hashref that AgentBase merges into the SWML
# response. In static mode this is a no-op (returns undef).
sub on_swml_request {
    my ( $self, $request_data, $callback_path, %opts ) = @_;
    my $request = $opts{request};

    # Static mode: questions are already configured.
    return if defined $self->static_questions;

    # Dynamic mode with no callback: fall back to default questions.
    return { global_data => _fresh_global_data($FALLBACK_QUESTIONS) }
        if !defined $self->question_callback;

    my $resolved = $self->_resolve_dynamic_questions( $request_data, $request );
    return { global_data => _fresh_global_data($resolved) };
}

# Invoke the per-request question callback; fall back to
# FALLBACK_QUESTIONS on any error (matching Python / ruby).
sub _resolve_dynamic_questions {
    my ( $self, $request_data, $request ) = @_;

    my $query_params = _request_attr( $request, 'query_params' );
    my $headers      = _request_attr( $request, 'headers' );
    my $body_params  = $request_data // {};

    my $questions = eval {
        my $q = $self->question_callback->( $query_params, $body_params, $headers );
        die "callback must return a non-empty arrayref\n"
            unless ref $q eq 'ARRAY' && @$q;
        $q;
    };
    if ($@) {
        print "Error in question callback: $@";
        return $FALLBACK_QUESTIONS;
    }
    return $questions;
}

sub _request_attr {
    my ( $request, $name ) = @_;
    return {} unless $request;
    if ( ref $request eq 'HASH' ) {
        return $request->{$name} // {};
    }
    return ( $request->can($name) ? $request->$name : undef ) // {};
}

sub _fresh_global_data {
    my ($questions) = @_;
    return {
        questions      => $questions,
        question_index => 0,
        answers        => [],
    };
}

1;
