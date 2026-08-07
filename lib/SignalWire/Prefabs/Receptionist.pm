package SignalWire::Prefabs::Receptionist;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.

use strict;
use warnings;
use Moo;
use JSON qw(encode_json);
extends 'SignalWire::Agent::AgentBase';

has departments => ( is => 'ro', default => sub { [] } );
has greeting =>
    ( is => 'ro', default => sub { 'Thank you for calling. How can I help you today?' } );
has voice => ( is => 'ro', default => sub { 'rime.spore' } );

sub BUILD {
    my ( $self, $args ) = @_;

    $self->name('receptionist')   if $self->name eq 'agent';
    $self->route('/receptionist') if $self->route eq '/';
    $self->use_pom(1);

    my $departments = $self->departments;

    $self->set_global_data(
        {
            departments => $departments,
            caller_info => {},
        }
    );

    # Build department list for prompt
    my @dept_bullets;
    for my $dept (@$departments) {
        push @dept_bullets, "$dept->{name}: $dept->{description}";
    }

    $self->prompt_add_section(
        'Receptionist Role',
        $self->greeting,
        bullets => [
            'Greet the caller warmly',
            'Determine which department they need',
            'Transfer them to the correct department',
            @dept_bullets,
        ],
    );

    # Register transfer tool
    $self->define_tool(
        name        => 'transfer_to_department',
        description => 'Transfer the caller to the specified department',
        parameters  => {
            type       => 'object',
            properties => {
                department => { type => 'string', description => 'Department name to transfer to' },
            },
            required => ['department'],
        },
        handler => sub {
            my ( $a, $raw ) = @_;
            return $self->_transfer_to_department( $a, $raw );
        },
    );
    return;
}

# Tool handler: transfer_to_department — actually CONNECT the caller to the
# department's phone number. Python parity (prefabs/receptionist.py
# _transfer_call_handler): look up the department (from the live global_data,
# falling back to construction departments), then attach a real connect()
# action (final => 1, a permanent transfer) so the call is transferred — not
# just an acknowledgement string. A stub that returns text with no connect()
# never transfers the call.
sub _transfer_to_department {
    my ( $self, $args, $raw_data ) = @_;
    require SignalWire::SWAIG::FunctionResult;

    my $dept_name = $args->{department} // '';

    my $gdata =
        ( ref $raw_data eq 'HASH' && ref $raw_data->{global_data} eq 'HASH' )
        ? $raw_data->{global_data}
        : $self->global_data;
    my $departments =
        ( ref $gdata eq 'HASH' && ref $gdata->{departments} eq 'ARRAY' )
        ? $gdata->{departments}
        : $self->departments;

    my $department;
    for my $dept (@$departments) {
        if ( lc( $dept->{name} ) eq lc($dept_name) ) {
            $department = $dept;
            last;
        }
    }

    unless ($department) {
        return SignalWire::SWAIG::FunctionResult->new(
            response => "Sorry, I couldn't find the $dept_name department." );
    }

    my $transfer_number = $department->{number} // '';

    my $result = SignalWire::SWAIG::FunctionResult->new(
        response => "I'll transfer you to our $dept_name department now. Thank you for calling!",
        post_process => 1,
    );

    # final => 1: a permanent transfer (call exits the agent).
    $result->connect( $transfer_number, final => 1 );
    return $result;
}

# Lifecycle hook: on_summary — Python parity
# (signalwire.prefabs.receptionist.ReceptionistAgent.on_summary).
#
# No-op extension point: the base receptionist does not process the
# transfer summary. Subclasses override this to handle the summary
# (mirrors Python's ``def on_summary(...): pass``).
sub on_summary {
    my ( $self, $summary, $raw_data ) = @_;
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Prefabs::Receptionist - ready-made call-routing receptionist AI agent

=head1 SYNOPSIS

    use SignalWire::Prefabs::Receptionist;

    my $agent = SignalWire::Prefabs::Receptionist->new(
        departments => [
            { name => 'Sales',   description => 'New orders and quotes', number => '+15551112222' },
            { name => 'Support', description => 'Help with your account', number => '+15553334444' },
        ],
        greeting => 'Thank you for calling Acme. How can I help?',
        voice    => 'rime.spore',
    );

    $agent->run;

=head1 DESCRIPTION

L<SignalWire::Prefabs::Receptionist> is a ready-made
subclass of L<SignalWire::Agent::AgentBase> that greets callers,
determines which department they need, and transfers them to that
department's phone number via a real C<connect> action.

C<BUILD> names the agent C<receptionist> and mounts it at C</receptionist>
(unless overridden), enables POM sections, seeds global data with the
department list, builds the receptionist prompt, and registers the
C<transfer_to_department> SWAIG tool.

=head1 ATTRIBUTES

Constructor attributes (all C<ro>):

=over 4

=item C<departments>

Arrayref of C<< { name => ..., description => ..., number => ... } >>
hashrefs (default C<[]>).

=item C<greeting>

The opening greeting line (default a generic thank-you-for-calling line).

=item C<voice>

The TTS voice identifier (default C<rime.spore>).

=back

=head1 METHODS

=over 4

=item C<on_summary($summary, $raw_data)>

Lifecycle hook. A no-op extension point in the base receptionist;
subclasses override it to process the transfer summary.

=back

The C<transfer_to_department> SWAIG tool is registered in C<BUILD>; its
handler looks up the requested department and attaches a permanent
C<< connect(final => 1) >> action so the caller is actually transferred.

=head1 SEE ALSO

L<SignalWire::Agent::AgentBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
