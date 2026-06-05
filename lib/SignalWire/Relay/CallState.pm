package SignalWire::Relay::CallState;
# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# The RELAY call-lifecycle states, as a typed, named closed set.
#
# A call moves through created -> ringing -> answered -> ending -> ended.
# The Perl port has carried these as bare strings (Call->state defaults to
# 'created'; the server-sent 'calling.call.state' event's call_state is a
# raw string). This module hoists that vocabulary into a single source of
# truth — named constants whose values ARE the wire strings — co-located
# with the relay layer, mirroring the Tier-1 constants idiom of
# SignalWire::SWAIG::Tap / RecordCall / SkillName / Logging::LogLevel.
#
# Grounded in the Python reference's relay/constants.py (CALL_STATE_* /
# CALL_STATES) and the port's own SignalWire::Relay::Constants
# (CALL_STATES / CALL_TERMINAL_STATES, the single source the terminal set
# is derived from here).
#
# ★ THREE STATE VOCABULARIES — NEVER CONFLATE. CallState, DialState, and
# MessageState are distinct sets with distinct terminal members:
#   - CallState  terminal: { ended }
#   - DialState  terminal: { answered, failed }
#   - MessageState terminal: { delivered, undelivered, failed }
# 'answered' appears in BOTH CallState (non-terminal) and DialState
# (terminal); 'failed' is NOT a CallState at all. Mixing the vocabularies
# would mis-classify terminality. Keep this module call-only.
#
# ★ These mirror SERVER-emitted values that can grow. The membership
# predicates (is_state / is_terminal) therefore return FALSE on an unknown
# value — they never die — so a forward-compatible server state is handled
# gracefully rather than crashing the consumer (the Perl equivalent of a
# #[non_exhaustive] enum).
#
# Perl has no real enums, so these constants buy no compile-time typo
# checking. The constants ARE the canonical wire strings, so nothing about
# Call->state changes: it still reads/writes a plain string, preserving
# Python parity and forward-compat.
#
#     use SignalWire::Relay::CallState qw(ANSWERED ENDED);
#     $call->state eq ANSWERED;                          # constant
#     $call->state eq 'answered';                        # string (parity)
#     SignalWire::Relay::CallState->is_terminal($call->state);  # ended?
#     SignalWire::Relay::CallState->is_state('ringing'); # 1

use strict;
use warnings;

use Exporter 'import';

use SignalWire::Relay::Constants qw(CALL_STATES CALL_TERMINAL_STATES);

# Call lifecycle states. Values are the exact strings the server sends in
# the 'calling.call.state' event's call_state field. Keep in lockstep with
# SignalWire::Relay::Constants::CALL_STATES.
use constant {
    CREATED  => 'created',
    RINGING  => 'ringing',
    ANSWERED => 'answered',
    ENDING   => 'ending',
    ENDED    => 'ended',
};

our @EXPORT_OK = qw( CREATED RINGING ANSWERED ENDING ENDED );
our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

# Canonical ordered set, single-sourced from Relay::Constants so this
# module can never drift from the protocol constants the rest of the relay
# layer already uses.
my @STATES = @{ CALL_STATES() };

my %IS_STATE = map { $_ => 1 } @STATES;

# Terminal states, single-sourced from CALL_TERMINAL_STATES ({ ended }).
my %IS_TERMINAL = %{ CALL_TERMINAL_STATES() };

# CallState->states — arrayref of the call lifecycle states, in order.
sub states {
    return [@STATES];
}

# CallState->is_state($value) — true if $value is a known call state.
# Returns false (never dies) on undef or an unknown/forward-compat value.
sub is_state {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return exists $IS_STATE{$value} ? 1 : 0;
}

# CallState->is_terminal($value) — true if $value is a terminal call state
# (the call has ended). Returns false on undef, a non-terminal state, or an
# unknown/forward-compat value — it never dies.
sub is_terminal {
    my ($class, $value) = @_;
    return 0 unless defined $value;
    return $IS_TERMINAL{$value} ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::CallState - RELAY call-lifecycle states as a typed closed set

=head1 SYNOPSIS

    use SignalWire::Relay::CallState qw(CREATED RINGING ANSWERED ENDING ENDED);

    # Named constants and bare wire strings are interchangeable:
    $call->state eq ANSWERED;     # constant
    $call->state eq 'answered';   # string (Python parity)

    # Membership / terminality (false on unknown — never dies):
    SignalWire::Relay::CallState->is_state('ringing');        # 1
    SignalWire::Relay::CallState->is_terminal('ended');       # 1
    SignalWire::Relay::CallState->is_terminal('answered');    # 0
    SignalWire::Relay::CallState->is_terminal('made_up');     # 0
    @{ SignalWire::Relay::CallState->states };  # created..ended

=head1 DESCRIPTION

The RELAY call-lifecycle states, surfaced as typed, named constants. A call
moves through C<created> E<8594> C<ringing> E<8594> C<answered> E<8594>
C<ending> E<8594> C<ended>. Each constant's value is the exact wire string
the server sends in the C<calling.call.state> event's C<call_state> field.

The constants B<are> the canonical wire strings, so nothing about
C<< SignalWire::Relay::Call->state >> changes: it still reads and writes a
plain string. That keeps parity with the Python reference (bare C<str>) and
leaves forward-compatible server states working — an unknown string is
simply not in this set.

Grounded in the Python reference's C<relay/constants.py>
(C<CALL_STATE_*> / C<CALL_STATES>) and the port's
L<SignalWire::Relay::Constants> (C<CALL_STATES> / C<CALL_TERMINAL_STATES>),
which are the single source the lists below are derived from.

=head2 Three distinct state vocabularies

L<CallState|SignalWire::Relay::CallState>,
L<DialState|SignalWire::Relay::DialState>, and
L<MessageState|SignalWire::Relay::MessageState> are B<distinct> sets with
B<distinct> terminal members and must never be conflated. C<answered> is a
B<non-terminal> C<CallState> but a B<terminal> C<DialState>; C<failed> is
not a C<CallState> at all. Each module owns its own terminal set.

=head1 CONSTANTS

Exported on request via L<Exporter>; C<:all> pulls every state.

    CREATED  => 'created'
    RINGING  => 'ringing'
    ANSWERED => 'answered'
    ENDING   => 'ending'
    ENDED    => 'ended'

=head1 METHODS

=head2 states

    my $aref = SignalWire::Relay::CallState->states;

Arrayref of the call lifecycle states, in lifecycle order.

=head2 is_state

    my $bool = SignalWire::Relay::CallState->is_state($value);

True if C<$value> is a known call state. Returns false (never dies) on
C<undef> or an unknown/forward-compatible value.

=head2 is_terminal

    my $bool = SignalWire::Relay::CallState->is_terminal($value);

True if C<$value> is a terminal call state (the only terminal C<CallState>
is C<ended>). Returns false on C<undef>, a non-terminal state, or an
unknown value — it never dies, since these mirror server-emitted values
that can grow.

=head1 SEE ALSO

L<SignalWire::Relay::Call>, L<SignalWire::Relay::Constants>,
L<SignalWire::Relay::DialState>, L<SignalWire::Relay::MessageState>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
