package SignalWire::Relay::DialState;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# The RELAY dial-outcome states, as a typed, named closed set.
#
# An outbound dial reports its progress via the 'calling.call.dial' event's
# dial_state field: 'dialing' while in progress, then a terminal outcome of
# 'answered' (a leg picked up — the dial succeeded) or 'failed' (no leg
# answered — the dial failed). The Perl port has carried these as bare
# strings (SignalWire::Relay::Client::_handle_dial_event resolves the
# pending dial on 'answered' and rejects on 'failed'). This module hoists
# that vocabulary into a single source of truth — named constants whose
# values ARE the wire strings — mirroring the Tier-1 constants idiom of
# SignalWire::SWAIG::Tap / RecordCall / SkillName / Logging::LogLevel.
#
# Grounded in the port's SignalWire::Relay::Constants (DIAL_STATES /
# DIAL_TERMINAL_STATES, the single source the lists are derived from) and
# the dial dispatch in Relay::Client. (The Python reference's
# relay/constants.py enumerates CALL_STATE_* / CONNECT_STATE_* but leaves
# the dial-outcome vocabulary implicit in its dial handler — the same place
# Perl grounds it.)
#
# ★ THREE STATE VOCABULARIES — NEVER CONFLATE. DialState is NOT CallState
# and NOT MessageState:
#   - CallState  terminal: { ended }       ('answered' is NON-terminal there)
#   - DialState  terminal: { answered, failed }
#   - MessageState terminal: { delivered, undelivered, failed }
# 'answered' is a TERMINAL DialState but a NON-terminal CallState — the same
# string, opposite terminality, because they are different vocabularies.
# 'failed' is a DialState/MessageState value, NOT a CallState. Keep this
# module dial-only.
#
# ★ These mirror SERVER-emitted values that can grow. The membership
# predicates (is_state / is_terminal) therefore return FALSE on an unknown
# value — they never die — so a forward-compatible server state is handled
# gracefully (the Perl equivalent of a #[non_exhaustive] enum).
#
# Perl has no real enums, so these constants buy no compile-time typo
# checking. The constants ARE the canonical wire strings, so the dial flow
# is unchanged: it still compares plain strings, preserving Python parity
# and forward-compat.
#
#     use SignalWire::Relay::DialState qw(DIALING ANSWERED FAILED);
#     $event->dial_state eq ANSWERED;                        # constant
#     $event->dial_state eq 'answered';                      # string (parity)
#     SignalWire::Relay::DialState->is_terminal('answered'); # 1 (dial done)
#     SignalWire::Relay::DialState->is_terminal('dialing');  # 0

use strict;
use warnings;

use Exporter 'import';

use SignalWire::Relay::Constants qw(DIAL_STATES DIAL_TERMINAL_STATES);

# Dial-outcome states. Values are the exact strings the server sends in the
# 'calling.call.dial' event's dial_state field. Keep in lockstep with
# SignalWire::Relay::Constants::DIAL_STATES.
use constant {
    DIALING  => 'dialing',
    ANSWERED => 'answered',
    FAILED   => 'failed',
};

our @EXPORT_OK   = qw( DIALING ANSWERED FAILED );
our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

# Canonical ordered set, single-sourced from Relay::Constants.
my @STATES = @{ DIAL_STATES() };

my %IS_STATE = map { $_ => 1 } @STATES;

# Terminal states, single-sourced from DIAL_TERMINAL_STATES
# ({ answered, failed }).
my %IS_TERMINAL = %{ DIAL_TERMINAL_STATES() };

# DialState->states — arrayref of the dial-outcome states, in order.
sub states {
    return [@STATES];
}

# DialState->is_state($value) — true if $value is a known dial state.
# Returns false (never dies) on undef or an unknown/forward-compat value.
sub is_state {
    my ( $class, $value ) = @_;
    return 0 unless defined $value;
    return exists $IS_STATE{$value} ? 1 : 0;
}

# DialState->is_terminal($value) — true if $value is a terminal dial state
# (the dial finished: 'answered' or 'failed'). Returns false on undef, the
# in-progress 'dialing' state, or an unknown/forward-compat value — it
# never dies.
sub is_terminal {
    my ( $class, $value ) = @_;
    return 0 unless defined $value;
    return $IS_TERMINAL{$value} ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::DialState - RELAY dial-outcome states as a typed closed set

=head1 SYNOPSIS

    use SignalWire::Relay::DialState qw(DIALING ANSWERED FAILED);

    # Named constants and bare wire strings are interchangeable:
    $event->dial_state eq ANSWERED;     # constant
    $event->dial_state eq 'answered';   # string (Python parity)

    # Membership / terminality (false on unknown — never dies):
    SignalWire::Relay::DialState->is_state('dialing');         # 1
    SignalWire::Relay::DialState->is_terminal('answered');     # 1
    SignalWire::Relay::DialState->is_terminal('failed');       # 1
    SignalWire::Relay::DialState->is_terminal('dialing');      # 0
    @{ SignalWire::Relay::DialState->states };  # dialing, answered, failed

=head1 DESCRIPTION

The RELAY dial-outcome states, surfaced as typed, named constants. An
outbound dial reports progress via the C<calling.call.dial> event's
C<dial_state> field: C<dialing> while in progress, then a terminal outcome
of C<answered> (a leg picked up — the dial succeeded) or C<failed> (no leg
answered). Each constant's value is the exact wire string the server sends.

The constants B<are> the canonical wire strings, so the dial flow is
unchanged: it still compares plain strings (see
L<SignalWire::Relay::Client>'s dial dispatch, which resolves a pending dial
on C<answered> and rejects on C<failed>). That keeps parity with the Python
reference and leaves forward-compatible server states working.

Grounded in the port's L<SignalWire::Relay::Constants> (C<DIAL_STATES> /
C<DIAL_TERMINAL_STATES>), which are the single source the lists below are
derived from.

=head2 Three distinct state vocabularies

L<CallState|SignalWire::Relay::CallState>, C<DialState>, and
L<MessageState|SignalWire::Relay::MessageState> are B<distinct> sets and
must never be conflated. C<answered> is a B<terminal> C<DialState> but a
B<non-terminal> C<CallState> — the same string with opposite terminality,
because they are different vocabularies. C<failed> is not a C<CallState> at
all.

=head1 CONSTANTS

Exported on request via L<Exporter>; C<:all> pulls every state.

    DIALING  => 'dialing'
    ANSWERED => 'answered'
    FAILED   => 'failed'

=head1 METHODS

=head2 states

    my $aref = SignalWire::Relay::DialState->states;

Arrayref of the dial-outcome states, in order.

=head2 is_state

    my $bool = SignalWire::Relay::DialState->is_state($value);

True if C<$value> is a known dial state. Returns false (never dies) on
C<undef> or an unknown/forward-compatible value.

=head2 is_terminal

    my $bool = SignalWire::Relay::DialState->is_terminal($value);

True if C<$value> is a terminal dial state (C<answered> or C<failed>).
Returns false on C<undef>, the in-progress C<dialing> state, or an unknown
value — it never dies, since these mirror server-emitted values that can
grow.

=head1 SEE ALSO

L<SignalWire::Relay::Client>, L<SignalWire::Relay::Constants>,
L<SignalWire::Relay::CallState>, L<SignalWire::Relay::MessageState>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
