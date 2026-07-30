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

# Registry key for this skill instance. Overrides SkillBase's default, which
# keys on `tool_name`; info_gatherer has no single tool_name — `prefix` is what
# differentiates two instances, driving BOTH tool names
# (`<prefix>_start_questions` / `<prefix>_submit_answer`) and the global_data
# namespace. Keying on prefix is therefore what lets two prefixed instances
# load onto one agent side by side. Python parity:
# ``InfoGathererSkill.get_instance_key``.
sub get_instance_key {
    my ($self) = @_;
    my $prefix = $self->params->{prefix};
    return $prefix ? 'info_gatherer_' . $prefix : 'info_gatherer';
}

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

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::InfoGatherer - collect answers to a configurable list of questions

=head1 SYNOPSIS

    $agent->add_skill('info_gatherer', {
        questions => [
            { key_name => 'name',  question_text => 'What is your name?' },
            { key_name => 'email', question_text => 'What is your email?', confirm => 1 },
        ],
    });

    # Optionally namespace the tools and set a completion message:
    $agent->add_skill('info_gatherer', {
        prefix             => 'intake',
        questions          => [ ... ],
        completion_message => 'Thanks, all done!',
    });

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::InfoGatherer> drives a small state
machine that asks the user a configured sequence of questions and records the
answers.

It registers two handler-based SWAIG tools (their names optionally prefixed via
the C<prefix> param):

=over

=item *

C<start_questions> - present the first question.

=item *

C<submit_answer> - store the current answer (accepts C<answer> and
C<confirmed_by_user>), advance to the next question, or, when finished, emit the
completion message and toggle both tools off.

=back

Per-instance state (the question list, current index, and collected answers) is
persisted in namespaced skill data across turns. The skill supports multiple
instances.

=head1 METHODS

=over

=item C<get_instance_key>

Returns the SkillManager registry key for this instance: C<"info_gatherer_<prefix>">
when a C<prefix> is configured, otherwise C<"info_gatherer">. Keys on C<prefix>
rather than a tool name because C<prefix> is what actually differentiates two
instances — it drives both tool names (C<< <prefix>_start_questions >> /
C<< <prefix>_submit_answer >>) and the global-data namespace. At most one
un-prefixed instance is therefore possible.

=item C<register_tools>

Registers the C<start_questions> and C<submit_answer> tools with the agent.

=item C<get_global_data>

Returns the skill's initial namespaced state (questions, index 0, empty answers).

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the configuration schema: C<questions> (required array), C<prefix>, and
C<completion_message>.

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
