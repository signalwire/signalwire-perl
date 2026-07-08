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
