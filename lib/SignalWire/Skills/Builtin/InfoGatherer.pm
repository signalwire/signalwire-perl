package SignalWire::Skills::Builtin::InfoGatherer;
use strict;
use warnings;
use Moo;
use JSON qw(encode_json);
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'info_gatherer', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'info_gatherer' } );
has '+skill_description' =>
    ( default => sub { 'Gather answers to a configurable list of questions' } );
has '+supports_multiple_instances' => ( default => sub { 1 } );

sub setup { return 1 }

sub register_tools {
    my ($self)    = @_;
    my $prefix    = $self->params->{prefix}    // '';
    my $questions = $self->params->{questions} // [];

    my $start_name  = $prefix ? "${prefix}_start_questions" : 'start_questions';
    my $submit_name = $prefix ? "${prefix}_submit_answer"   : 'submit_answer';

    $self->define_tool(
        name        => $start_name,
        description => 'Start the question-gathering process and return the first question',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $first = $questions->[0]{question_text} // 'No questions configured';
            return SignalWire::SWAIG::FunctionResult->new( response => $first, );
        },
    );

    return $self->define_tool(
        name        => $submit_name,
        description => 'Submit an answer to the current question',
        parameters  => {
            type       => 'object',
            properties => {
                answer            => { type => 'string',  description => 'The answer' },
                confirmed_by_user => { type => 'boolean', description => 'Whether user confirmed' },
            },

            # No `required`: the Python reference (skills/info_gatherer/skill.py)
            # passes none on submit_answer and the handler reads answer with a
            # default. Adding it would over-constrain the SWAIG schema vs the
            # reference contract.
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            my $answer = $args->{answer} // '';
            return SignalWire::SWAIG::FunctionResult->new( response => "Answer recorded: $answer",
            );
        },
    );
}

sub get_global_data {
    my ($self) = @_;
    my $ns = $self->params->{prefix} // 'info_gatherer';
    return {
        $ns => {
            questions      => $self->params->{questions} // [],
            question_index => 0,
            answers        => [],
        },
    };
}

sub _get_prompt_sections {
    my ($self) = @_;
    my $key = $self->params->{prefix} // 'info_gatherer';
    return [
        {
            title   => "Info Gatherer ($key)",
            body    => 'Ask the user a series of questions and collect their answers.',
            bullets => [
                'Ask questions one at a time',
                'Wait for the user to answer before proceeding',
                'Confirm answers when required',
            ],
        }
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        questions => { type => 'array',  required => 1, description => 'List of question objects' },
        prefix    => { type => 'string', description => 'Prefix for tool names' },
        completion_message =>
            { type => 'string', description => 'Message after all questions answered' },
    };
}

1;
