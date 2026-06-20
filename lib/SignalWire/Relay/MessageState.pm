package SignalWire::Relay::MessageState;

# Copyright (c) 2025 SignalWire
# Licensed under the MIT License.
#
# The RELAY message-delivery states, as a typed, named closed set.
#
# An SMS message moves through queued -> initiated -> sent and then to a
# terminal delivery outcome: delivered (success), undelivered, or failed.
# 'received' is the state of an inbound message. The Perl port has carried
# these as bare strings (Message->state, set from the 'messaging.state'
# event's message_state field; Relay::Message resolves the message when the
# state is terminal). This module hoists that vocabulary into a single
# source of truth — named constants whose values ARE the wire strings —
# mirroring the Tier-1 constants idiom of SignalWire::SWAIG::Tap /
# RecordCall / SkillName / Logging::LogLevel.
#
# Grounded in the Python reference's relay/constants.py (MESSAGE_STATE_* /
# MESSAGE_TERMINAL_STATES) and the port's own SignalWire::Relay::Constants
# (MESSAGE_STATES / MESSAGE_TERMINAL_STATES, the single source the lists are
# derived from here).
#
# ★ THREE STATE VOCABULARIES — NEVER CONFLATE. MessageState is NOT CallState
# and NOT DialState:
#   - CallState  terminal: { ended }
#   - DialState  terminal: { answered, failed }
#   - MessageState terminal: { delivered, undelivered, failed }
# 'failed' is terminal in BOTH DialState and MessageState, but they are
# still different vocabularies (MessageState has no 'answered'/'dialing';
# DialState has no 'delivered'). Keep this module message-only.
#
# ★ These mirror SERVER-emitted values that can grow. The membership
# predicates (is_state / is_terminal) therefore return FALSE on an unknown
# value — they never die — so a forward-compatible server state is handled
# gracefully (the Perl equivalent of a #[non_exhaustive] enum).
#
# Perl has no real enums, so these constants buy no compile-time typo
# checking. The constants ARE the canonical wire strings, so nothing about
# Message->state changes: it still reads/writes a plain string, preserving
# Python parity and forward-compat.
#
#     use SignalWire::Relay::MessageState qw(SENT DELIVERED FAILED);
#     $msg->state eq DELIVERED;                                # constant
#     $msg->state eq 'delivered';                              # string (parity)
#     SignalWire::Relay::MessageState->is_terminal($msg->state); # done?
#     SignalWire::Relay::MessageState->is_terminal('sent');   # 0

use strict;
use warnings;

use Exporter 'import';

use SignalWire::Relay::Constants qw(MESSAGE_STATES MESSAGE_TERMINAL_STATES);

# Message-delivery states. Values are the exact strings the server sends in
# the 'messaging.state' event's message_state field. Keep in lockstep with
# SignalWire::Relay::Constants::MESSAGE_STATES.
use constant {
    QUEUED      => 'queued',
    INITIATED   => 'initiated',
    SENT        => 'sent',
    DELIVERED   => 'delivered',
    UNDELIVERED => 'undelivered',
    FAILED      => 'failed',
    RECEIVED    => 'received',
};

our @EXPORT_OK = qw(
    QUEUED INITIATED SENT DELIVERED UNDELIVERED FAILED RECEIVED
);
our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

# Canonical ordered set, single-sourced from Relay::Constants.
my @STATES = @{ MESSAGE_STATES() };

my %IS_STATE = map { $_ => 1 } @STATES;

# Terminal states, single-sourced from MESSAGE_TERMINAL_STATES
# ({ delivered, undelivered, failed }).
my %IS_TERMINAL = %{ MESSAGE_TERMINAL_STATES() };

# MessageState->states — arrayref of the message-delivery states, in order.
sub states {
    return [@STATES];
}

# MessageState->is_state($value) — true if $value is a known message state.
# Returns false (never dies) on undef or an unknown/forward-compat value.
sub is_state {
    my ( $class, $value ) = @_;
    return 0 unless defined $value;
    return exists $IS_STATE{$value} ? 1 : 0;
}

# MessageState->is_terminal($value) — true if $value is a terminal delivery
# state (delivered, undelivered, or failed). Returns false on undef, an
# in-flight state (queued/initiated/sent) or 'received', or an
# unknown/forward-compat value — it never dies.
sub is_terminal {
    my ( $class, $value ) = @_;
    return 0 unless defined $value;
    return $IS_TERMINAL{$value} ? 1 : 0;
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::MessageState - RELAY message-delivery states as a typed closed set

=head1 SYNOPSIS

    use SignalWire::Relay::MessageState qw(QUEUED SENT DELIVERED FAILED);

    # Named constants and bare wire strings are interchangeable:
    $msg->state eq DELIVERED;     # constant
    $msg->state eq 'delivered';   # string (Python parity)

    # Membership / terminality (false on unknown — never dies):
    SignalWire::Relay::MessageState->is_state('sent');            # 1
    SignalWire::Relay::MessageState->is_terminal('delivered');    # 1
    SignalWire::Relay::MessageState->is_terminal('failed');       # 1
    SignalWire::Relay::MessageState->is_terminal('sent');         # 0
    @{ SignalWire::Relay::MessageState->states };  # queued..received

=head1 DESCRIPTION

The RELAY message-delivery states, surfaced as typed, named constants. An
outbound SMS moves through C<queued> E<8594> C<initiated> E<8594> C<sent>
and then to a terminal outcome of C<delivered>, C<undelivered>, or
C<failed>; C<received> is the state of an inbound message. Each constant's
value is the exact wire string the server sends in the C<messaging.state>
event's C<message_state> field.

The constants B<are> the canonical wire strings, so nothing about
C<< SignalWire::Relay::Message->state >> changes: it still reads and writes
a plain string. That keeps parity with the Python reference (bare C<str>)
and leaves forward-compatible server states working.

Grounded in the Python reference's C<relay/constants.py>
(C<MESSAGE_STATE_*> / C<MESSAGE_TERMINAL_STATES>) and the port's
L<SignalWire::Relay::Constants> (C<MESSAGE_STATES> /
C<MESSAGE_TERMINAL_STATES>), which are the single source the lists below
are derived from.

=head2 Three distinct state vocabularies

L<CallState|SignalWire::Relay::CallState>,
L<DialState|SignalWire::Relay::DialState>, and C<MessageState> are
B<distinct> sets and must never be conflated. C<failed> is terminal in both
C<DialState> and C<MessageState>, but the sets are otherwise disjoint
(C<MessageState> has no C<dialing>/C<answered>; C<DialState> has no
C<delivered>).

=head1 CONSTANTS

Exported on request via L<Exporter>; C<:all> pulls every state.

    QUEUED      => 'queued'        UNDELIVERED => 'undelivered'
    INITIATED   => 'initiated'     FAILED      => 'failed'
    SENT        => 'sent'          RECEIVED    => 'received'
    DELIVERED   => 'delivered'

=head1 METHODS

=head2 states

    my $aref = SignalWire::Relay::MessageState->states;

Arrayref of the message-delivery states, in order.

=head2 is_state

    my $bool = SignalWire::Relay::MessageState->is_state($value);

True if C<$value> is a known message state. Returns false (never dies) on
C<undef> or an unknown/forward-compatible value.

=head2 is_terminal

    my $bool = SignalWire::Relay::MessageState->is_terminal($value);

True if C<$value> is a terminal delivery state (C<delivered>,
C<undelivered>, or C<failed>). Returns false on C<undef>, an in-flight
state, C<received>, or an unknown value — it never dies, since these mirror
server-emitted values that can grow.

=head1 SEE ALSO

L<SignalWire::Relay::Message>, L<SignalWire::Relay::Constants>,
L<SignalWire::Relay::CallState>, L<SignalWire::Relay::DialState>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
