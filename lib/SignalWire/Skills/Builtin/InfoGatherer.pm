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

# Tool names, honoring an optional prefix (Python parity:
# skills/info_gatherer/skill.py setup()).
sub _start_tool_name {
    my ($self) = @_;
    my $prefix = $self->params->{prefix} // '';
    return $prefix ? "${prefix}_start_questions" : 'start_questions';
}

sub _submit_tool_name {
    my ($self) = @_;
    my $prefix = $self->params->{prefix} // '';
    return $prefix ? "${prefix}_submit_answer" : 'submit_answer';
}

sub _completion_message {
    my ($self) = @_;
    return $self->params->{completion_message}
        // 'Thank you! All questions have been answered. You can now summarize the information collected or ask if there is anything else the user would like to discuss.';
}

sub register_tools {
    my ($self) = @_;

    $self->define_tool(
        name        => $self->_start_tool_name,
        description => 'Start the question sequence with the first question',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ( $args, $raw ) = @_;
            return $self->_handle_start_questions( $args, $raw );
        },
    );

    return $self->define_tool(
        name        => $self->_submit_tool_name,
        description => 'Submit an answer to the current question and move to the next one',
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
            return $self->_handle_submit_answer( $args, $raw );
        },
    );
}

# Handler: start_questions — present the first question from this instance's
# namespaced state (Python parity: _handle_start_questions).
sub _handle_start_questions {
    my ( $self, $args, $raw ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $state          = $self->get_skill_data($raw);
    my $questions      = $state->{questions} // $self->params->{questions} // [];
    my $question_index = $state->{question_index} // 0;

    if ( !( ref $questions eq 'ARRAY' && @$questions )
        || $question_index >= @$questions )
    {
        return SignalWire::SWAIG::FunctionResult->new(
            response => "I don't have any questions to ask." );
    }

    my $current = $questions->[$question_index];
    my $n       = scalar @$questions;
    return SignalWire::SWAIG::FunctionResult->new(
        response => sprintf(
            '[Question %d of %d]: "%s"',
            $question_index + 1,
            $n, $current->{question_text}
        )
    );
}

# Handler: submit_answer — the state machine (Python parity:
# _handle_submit_answer): store { key_name, answer }, advance the index,
# present the next question (or the completion message + toggle the tools off),
# and persist the new namespaced state via update_skill_data.
sub _handle_submit_answer {
    my ( $self, $args, $raw ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $answer    = $args->{answer} // '';
    my $confirmed = $args->{confirmed_by_user};

    my $state          = $self->get_skill_data($raw);
    my $questions      = $state->{questions}      // $self->params->{questions} // [];
    my $question_index = $state->{question_index} // 0;
    my $answers        = $state->{answers}        // [];

    if ( $question_index >= @$questions ) {
        return SignalWire::SWAIG::FunctionResult->new(
            response => 'All questions have already been answered.' );
    }

    my $current  = $questions->[$question_index];
    my $key_name = $current->{key_name} // '';

    # Enforce confirmation when the question requires it.
    if ( $current->{confirm} && !$confirmed ) {
        return SignalWire::SWAIG::FunctionResult->new( response =>
"Before submitting, please read the answer \"$answer\" back to the user and ask them to confirm it is correct. Then call this function again with confirmed set to true."
        );
    }

    my @new_answers = ( @$answers, { key_name => $key_name, answer => $answer } );
    my $new_index   = $question_index + 1;
    my $n           = scalar @$questions;

    my $result;
    if ( $new_index < @$questions ) {
        my $next = $questions->[$new_index];
        $result =
            SignalWire::SWAIG::FunctionResult->new( response =>
                sprintf( '[Question %d of %d]: "%s"', $new_index + 1, $n, $next->{question_text} )
            );
    } else {
        $result = SignalWire::SWAIG::FunctionResult->new( response => $self->_completion_message );
        $result->toggle_functions(
            [
                { function => $self->_start_tool_name,  active => JSON::false },
                { function => $self->_submit_tool_name, active => JSON::false },
            ]
        );
    }

    $self->update_skill_data(
        $result,
        {
            questions      => $questions,
            question_index => $new_index,
            answers        => \@new_answers,
        }
    );
    return $result;
}

sub get_global_data {
    my ($self) = @_;
    return {
        $self->_skill_namespace => {
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
