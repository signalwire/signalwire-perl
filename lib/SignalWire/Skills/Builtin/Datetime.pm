package SignalWire::Skills::Builtin::Datetime;
use strict;
use warnings;
use Moo;
use POSIX qw(strftime);
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'datetime', __PACKAGE__ );

has '+skill_name' => ( default => sub { 'datetime' } );
has '+skill_description' =>
    ( default => sub { 'Get current date, time, and timezone information' } );
has '+supports_multiple_instances' => ( default => sub { 0 } );

sub setup { return 1 }

sub register_tools {
    my ($self) = @_;

    $self->define_tool(
        name        => 'get_current_time',
        description => 'Get the current time, optionally in a specific timezone',
        parameters  => {
            type       => 'object',
            properties => {
                timezone => {
                    type        => 'string',
                    description => 'Timezone (e.g. UTC, US/Eastern)',
                    default     => 'UTC'
                },
            },
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            my $tz = $args->{timezone} // 'UTC';
            local $ENV{TZ} = $tz;
            POSIX::tzset();
            my $time = strftime( '%H:%M:%S %Z', localtime );
            POSIX::tzset();    # Reset
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new(
                response => "The current time in $tz is $time" );
        },
    );

    return $self->define_tool(
        name        => 'get_current_date',
        description => 'Get the current date',
        parameters  => {
            type       => 'object',
            properties => {
                timezone => {
                    type        => 'string',
                    description => 'Timezone (e.g. UTC, US/Eastern)',
                    default     => 'UTC'
                },
            },
        },
        handler => sub {
            my ( $args, $raw ) = @_;
            my $tz = $args->{timezone} // 'UTC';
            local $ENV{TZ} = $tz;
            POSIX::tzset();
            my $date = strftime( '%Y-%m-%d', localtime );
            POSIX::tzset();
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new(
                response => "The current date in $tz is $date" );
        },
    );
}

sub _get_prompt_sections {
    return [
        {
            title   => 'Date and Time Information',
            body    => 'You can get the current date and time in any timezone.',
            bullets => [
                'Use get_current_time to get the current time',
                'Use get_current_date to get the current date',
            ],
        }
    ];
}

sub get_parameter_schema {
    return { %{ SignalWire::Skills::SkillBase->get_parameter_schema }, };
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Skills::Builtin::Datetime - current date/time/timezone skill

=head1 SYNOPSIS

    $agent->add_skill('datetime');

=head1 DESCRIPTION

L<SignalWire::Skills::Builtin::Datetime> is the Perl port of the Python reference
C<signalwire.skills.datetime.skill>. It registers two handler-based SWAIG tools:

=over

=item *

C<get_current_time> - the current time, optionally in a specific C<timezone> (an
optional string param, default C<UTC>).

=item *

C<get_current_date> - the current date, optionally in a specific C<timezone> (an
optional string param, default C<UTC>).

=back

Each handler sets C<$ENV{TZ}> locally, calls C<POSIX::tzset>, formats the value
with C<strftime>, and returns a L<SignalWire::SWAIG::FunctionResult>. The skill
takes no configuration parameters and does not support multiple instances.

=head1 METHODS

=over

=item C<register_tools>

Registers the C<get_current_time> and C<get_current_date> tools with the agent.

=item C<setup>

Instance setup hook; returns true.

=item C<get_parameter_schema>

Returns the base skill schema (this skill adds no parameters).

=back

=head1 SEE ALSO

L<SignalWire::Skills::SkillBase>, L<SignalWire::SWAIG::FunctionResult>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
