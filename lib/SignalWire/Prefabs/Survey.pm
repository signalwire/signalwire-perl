package SignalWire::Prefabs::Survey;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use JSON qw(encode_json);
extends 'SignalWire::Agent::AgentBase';

has survey_name  => ( is => 'ro', default => sub { 'Survey' } );
has questions    => ( is => 'ro', default => sub { [] } );
has introduction => ( is => 'ro', default => sub { '' } );
has conclusion   => ( is => 'ro', default => sub { '' } );
has brand_name   => ( is => 'ro', default => sub { '' } );
has max_retries  => ( is => 'ro', default => sub { 2 } );

sub BUILD {
    my ( $self, $args ) = @_;

    $self->name('survey')   if $self->name eq 'agent';
    $self->route('/survey') if $self->route eq '/';
    $self->use_pom(1);

    my $questions = $self->questions;

    $self->set_global_data(
        {
            survey_name    => $self->survey_name,
            questions      => $questions,
            question_index => 0,
            answers        => {},
            completed      => JSON::false,
        }
    );

    my $intro = $self->introduction || "Welcome to the ${\$self->survey_name}.";
    $self->prompt_add_section(
        'Survey Introduction',
        $intro,
        bullets => [
            'Introduce the survey to the user',
            'Ask each question in sequence',
            'Validate responses based on question type',
            'Thank the user when complete',
        ],
    );

    # Build question descriptions
    my @q_bullets;
    for my $q (@$questions) {
        my $desc = "Q: $q->{text} (type: $q->{type})";
        $desc .= " [required]" if $q->{required};
        push @q_bullets, $desc;
    }
    $self->prompt_add_section( 'Survey Questions', '', bullets => \@q_bullets );

    # Register survey tools
    $self->define_tool(
        name        => 'submit_survey_answer',
        description => 'Submit an answer for the current survey question',
        parameters  => {
            type       => 'object',
            properties => {
                question_id => { type => 'string', description => 'ID of the question' },
                answer      => { type => 'string', description => 'The answer' },
            },
            required => [ 'question_id', 'answer' ],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new(
                response => "Survey answer for $a->{question_id}: $a->{answer}", );
        },
    );

    # Register validate_response tool
    $self->define_tool(
        name        => 'validate_response',
        description => "Validate a response against the question's constraints",
        parameters  => {
            type       => 'object',
            properties => {
                question_id => { type => 'string', description => 'ID of the question' },
                response    => { type => 'string', description => 'The response to validate' },
            },
            required => [ 'question_id', 'response' ],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            return $self->validate_response( $a, $raw );
        },
    );

    # Register log_response tool
    $self->define_tool(
        name        => 'log_response',
        description => 'Record a validated survey response',
        parameters  => {
            type       => 'object',
            properties => {
                question_id => { type => 'string', description => 'ID of the question' },
                response    => { type => 'string', description => 'The response to record' },
            },
            required => [ 'question_id', 'response' ],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            return $self->log_response( $a, $raw );
        },
    );
    return;
}

# Tool: validate_response — Python parity
# (signalwire.prefabs.survey.SurveyAgent.validate_response).
#
# Validates a user's answer against the constraints of the identified
# question (rating range, multiple-choice options, yes/no, required
# open-ended) and returns a human-readable validity message.
sub validate_response {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $question_id = $args->{question_id} // '';
    my $response    = $args->{response}    // '';

    my ($question) = grep { ( $_->{id} // '' ) eq $question_id } @{ $self->questions };
    unless ($question) {
        return SignalWire::SWAIG::FunctionResult->new(
            response => "Error: Question with ID '$question_id' not found." );
    }

    my $message = $self->_validation_message( $question, $response )
        // "Response to '$question_id' is valid.";
    return SignalWire::SWAIG::FunctionResult->new( response => $message );
}

# Tool: log_response — Python parity
# (signalwire.prefabs.survey.SurveyAgent.log_response).
#
# Acknowledges that a validated response has been recorded, naming the
# question by its text. A real implementation would persist the answer.
sub log_response {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $question_id   = $args->{question_id} // '';
    my ($question)    = grep { ( $_->{id} // '' ) eq $question_id } @{ $self->questions };
    my $question_text = $question ? ( $question->{text} // '' ) : '';

    return SignalWire::SWAIG::FunctionResult->new(
        response => "Response to '$question_text' has been recorded." );
}

# Lifecycle hook: on_summary — Python parity
# (signalwire.prefabs.survey.SurveyAgent.on_summary).
#
# Logs the completed survey results; structured (hashref) summaries are
# emitted as pretty JSON.
sub on_summary {
    my ( $self, $summary, $raw_data ) = @_;
    return if !defined $summary;

    my $ok = eval {
        if ( ref $summary eq 'HASH' ) {
            print 'Survey completed: ' . JSON->new->canonical->pretty->encode($summary);
        } else {
            print "Survey summary (unstructured): $summary\n";
        }
        1;
    };
    print "Error processing survey summary: $@" if !$ok;
    return;
}

# Return an error message for an invalid response, or undef when the
# response is valid for the question's type.
sub _validation_message {
    my ( $self, $question, $response ) = @_;
    my $type = $question->{type} // '';

    if ( $type eq 'rating' ) {
        return _rating_error( $question, $response );
    } elsif ( $type eq 'multiple_choice' ) {
        return _multiple_choice_error( $question, $response );
    } elsif ( $type eq 'yes_no' ) {
        return _yes_no_error($response);
    } elsif ( $type eq 'open_ended' ) {
        return _open_ended_error( $question, $response );
    }
    return;
}

sub _rating_error {
    my ( $question, $response ) = @_;
    my $scale = $question->{scale} // 5;
    my $val   = $response;
    $val =~ s/^\s+|\s+$//g;
    my $rating = ( $val =~ /^-?\d+$/ ) ? int($val) : undef;
    return if defined $rating && $rating >= 1 && $rating <= $scale;
    return "Invalid rating. Please provide a number between 1 and $scale.";
}

sub _multiple_choice_error {
    my ( $question, $response ) = @_;
    my @options = @{ $question->{options} // [] };
    my $norm    = lc($response);
    $norm =~ s/^\s+|\s+$//g;
    return if grep { $norm eq lc($_) } @options;
    return 'Invalid choice. Please select one of: ' . join( ', ', @options ) . '.';
}

sub _yes_no_error {
    my ($response) = @_;
    my $norm = lc($response);
    $norm =~ s/^\s+|\s+$//g;
    return if grep { $norm eq $_ } qw(yes no y n);
    return "Please answer with 'yes' or 'no'.";
}

sub _open_ended_error {
    my ( $question, $response ) = @_;
    my $required = exists $question->{required} ? $question->{required} : 1;
    my $trimmed  = $response;
    $trimmed =~ s/^\s+|\s+$//g;
    return 'A response is required for this question.'
        if $trimmed eq '' && $required;
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Prefabs::Survey - ready-made survey-administering AI agent

=head1 SYNOPSIS

    use SignalWire::Prefabs::Survey;

    my $agent = SignalWire::Prefabs::Survey->new(
        survey_name      => 'Customer Satisfaction',
        questions => [
            { id => 'q1', text => 'Rate our service 1-5', type => 'rating', scale => 5 },
            { id => 'q2', text => 'Would you recommend us?', type => 'yes_no' },
        ],
        introduction => 'We would love your feedback.',
        conclusion   => 'Thank you for your time.',
    );

    $agent->run;

=head1 DESCRIPTION

L<SignalWire::Prefabs::Survey> is a ready-made subclass of
L<SignalWire::Agent::AgentBase> that administers a structured survey:
it introduces the survey, asks each question in sequence, validates
responses against each question's constraints, and records them.

C<BUILD> names the agent C<survey> and mounts it at C</survey> (unless
overridden), enables POM sections, seeds global data (survey name,
questions, index, answers, completed flag), builds the introduction and
question prompt sections, and registers the C<submit_survey_answer>,
C<validate_response>, and C<log_response> SWAIG tools.

Question hashrefs carry an C<id>, C<text>, and C<type>. Supported types
are C<rating> (with a C<scale>), C<multiple_choice> (with C<options>),
C<yes_no>, and C<open_ended> (honoring C<required>).

=head1 ATTRIBUTES

Constructor attributes (all C<ro>):

=over 4

=item C<survey_name>

The survey's display name (default C<'Survey'>).

=item C<questions>

Arrayref of question hashrefs (default C<[]>).

=item C<introduction>

Introductory text (default empty; a generated welcome is used when blank).

=item C<conclusion>

Closing text (default empty).

=item C<brand_name>

Optional brand name (default empty).

=item C<max_retries>

Maximum answer retries per question (default C<2>).

=back

=head1 METHODS

=over 4

=item C<validate_response($args, $raw_data)>

Tool handler. Validates a response against the identified question's
constraints (rating range, multiple-choice options, yes/no, required
open-ended) and returns a human-readable validity message.

=item C<log_response($args, $raw_data)>

Tool handler. Acknowledges that a validated response has been recorded,
naming the question by its text.

=item C<on_summary($summary, $raw_data)>

Lifecycle hook. Logs the completed survey results; hashref summaries are
emitted as pretty JSON.

=back

=head1 SEE ALSO

L<SignalWire::Agent::AgentBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
