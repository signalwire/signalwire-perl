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

# Is POSIX::tzset actually usable on this build?
#
# tzset() is how a changed $ENV{TZ} is made visible to localtime/strftime. It is
# NOT implemented on Win32 — POSIX.xs croaks "POSIX::tzset not implemented on
# this architecture", which aborted both handlers below on every Windows run
# (observed at Datetime.pm:38 on the nightly Multi-OS lane). Probe once, at
# load, rather than per call.
my $TZSET_OK = do {
    local $@;
    my $probe = eval {
        POSIX::tzset();
        1;
    };
    $probe ? 1 : 0;
};

# Format the current time in $tz using $format.
#
# Returns ($formatted, $tz_honoured). When tzset() is unavailable the requested
# zone CANNOT be applied — $ENV{TZ} alone does not affect localtime there — so
# we report the local zone and say so, rather than silently labelling local time
# with the requested zone's name (which would be a wrong answer presented as a
# right one).
sub _format_in_tz {
    my ( $format, $tz ) = @_;

    if ( !$TZSET_OK ) {
        return ( strftime( $format, localtime ), 0 );
    }

    local $ENV{TZ} = $tz;
    POSIX::tzset();
    my $out = strftime( $format, localtime );

    # Restore the process's original zone. $ENV{TZ} is already restored by the
    # `local` going out of scope, but tzset() must run again for the C library
    # to pick that up.
    POSIX::tzset();
    return ( $out, 1 );
}

# "The current time in US/Eastern is 09:14:02 EDT", or, where the requested zone
# could not be applied, an explicit note to that effect.
sub _describe {
    my ( $label, $tz, $value, $honoured ) = @_;
    return "The current $label in $tz is $value" if $honoured;
    return "The current $label is $value (server local time; this platform "
        . "cannot switch to $tz)";
}

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
            my ( $time, $honoured ) = _format_in_tz( '%H:%M:%S %Z', $tz );
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new(
                response => _describe( 'time', $tz, $time, $honoured ) );
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
            my ( $date, $honoured ) = _format_in_tz( '%Y-%m-%d', $tz );
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new(
                response => _describe( 'date', $tz, $date, $honoured ) );
        },
    );
}

# Speech-recognition hints for this skill. Empty by design — the reference
# ships the same explicit empty override as the documented extension point
# (e.g. "time", "date", "today", "now", "timezone" would go here). Python
# parity: ``DateTimeSkill.get_hints``.
sub get_hints {
    return [];
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

L<SignalWire::Skills::Builtin::Datetime> registers two handler-based SWAIG tools:

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
