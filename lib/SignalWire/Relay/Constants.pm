package SignalWire::Relay::Constants;
use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    PROTOCOL_VERSION
    CALL_STATES CALL_STATE_CREATED CALL_STATE_RINGING CALL_STATE_ANSWERED CALL_STATE_ENDING CALL_STATE_ENDED
    CALL_TERMINAL_STATES
    CALL_END_REASONS
    DIAL_STATES DIAL_STATE_DIALING DIAL_STATE_ANSWERED DIAL_STATE_FAILED
    DIAL_TERMINAL_STATES
    MESSAGE_STATES MESSAGE_STATE_QUEUED MESSAGE_STATE_INITIATED MESSAGE_STATE_SENT
    MESSAGE_STATE_DELIVERED MESSAGE_STATE_UNDELIVERED MESSAGE_STATE_FAILED MESSAGE_STATE_RECEIVED
    MESSAGE_TERMINAL_STATES
    EVENT_TYPES
    ACTION_TERMINAL_STATES
);

our %EXPORT_TAGS = ( all => \@EXPORT_OK, );

# Protocol version for signalwire.connect
use constant PROTOCOL_VERSION => { major => 2, minor => 0, revision => 0 };

# --- Call States ---
use constant CALL_STATE_CREATED  => 'created';
use constant CALL_STATE_RINGING  => 'ringing';
use constant CALL_STATE_ANSWERED => 'answered';
use constant CALL_STATE_ENDING   => 'ending';
use constant CALL_STATE_ENDED    => 'ended';

use constant CALL_STATES => [
    CALL_STATE_CREATED, CALL_STATE_RINGING, CALL_STATE_ANSWERED, CALL_STATE_ENDING,
    CALL_STATE_ENDED,
];

use constant CALL_TERMINAL_STATES => { (CALL_STATE_ENDED) => 1, };

# --- Call End Reasons ---
use constant CALL_END_REASONS => {
    hangup   => 'hangup',
    cancel   => 'cancel',
    busy     => 'busy',
    noAnswer => 'noAnswer',
    decline  => 'decline',
    error    => 'error',
};

# --- Dial States ---
use constant DIAL_STATE_DIALING  => 'dialing';
use constant DIAL_STATE_ANSWERED => 'answered';
use constant DIAL_STATE_FAILED   => 'failed';

use constant DIAL_STATES => [ DIAL_STATE_DIALING, DIAL_STATE_ANSWERED, DIAL_STATE_FAILED, ];

# A dial completes when it is answered (success) or failed (failure);
# 'dialing' is the in-progress, non-terminal state. This matches the
# client's dial dispatch: DIAL_STATE_ANSWERED resolves the pending dial,
# DIAL_STATE_FAILED rejects it (see Relay::Client::_handle_dial_event).
use constant DIAL_TERMINAL_STATES => {
    (DIAL_STATE_ANSWERED) => 1,
    (DIAL_STATE_FAILED)   => 1,
};

# --- Message States ---
use constant MESSAGE_STATE_QUEUED      => 'queued';
use constant MESSAGE_STATE_INITIATED   => 'initiated';
use constant MESSAGE_STATE_SENT        => 'sent';
use constant MESSAGE_STATE_DELIVERED   => 'delivered';
use constant MESSAGE_STATE_UNDELIVERED => 'undelivered';
use constant MESSAGE_STATE_FAILED      => 'failed';
use constant MESSAGE_STATE_RECEIVED    => 'received';

use constant MESSAGE_STATES => [
    MESSAGE_STATE_QUEUED,      MESSAGE_STATE_INITIATED,
    MESSAGE_STATE_SENT,        MESSAGE_STATE_DELIVERED,
    MESSAGE_STATE_UNDELIVERED, MESSAGE_STATE_FAILED,
    MESSAGE_STATE_RECEIVED,
];

use constant MESSAGE_TERMINAL_STATES => {
    (MESSAGE_STATE_DELIVERED)   => 1,
    (MESSAGE_STATE_UNDELIVERED) => 1,
    (MESSAGE_STATE_FAILED)      => 1,
};

# --- Event Types ---
use constant EVENT_TYPES => {

    # Call state events
    'calling.call.state'      => 'CallState',
    'calling.call.receive'    => 'CallReceive',
    'calling.call.dial'       => 'CallDial',
    'calling.call.connect'    => 'CallConnect',
    'calling.call.disconnect' => 'CallDisconnect',

    # Action events
    'calling.call.play'        => 'CallPlay',
    'calling.call.record'      => 'CallRecord',
    'calling.call.collect'     => 'CallCollect',
    'calling.call.detect'      => 'CallDetect',
    'calling.call.fax'         => 'CallFax',
    'calling.call.tap'         => 'CallTap',
    'calling.call.stream'      => 'CallStream',
    'calling.call.transcribe'  => 'CallTranscribe',
    'calling.call.pay'         => 'CallPay',
    'calling.call.send_digits' => 'CallSendDigits',
    'calling.call.refer'       => 'CallRefer',

    # Conference events
    'calling.conference' => 'Conference',

    # AI events
    'calling.call.ai' => 'CallAI',

    # Messaging events
    'messaging.receive' => 'MessageReceive',
    'messaging.state'   => 'MessageState',

    # System events
    'signalwire.authorization.state' => 'AuthorizationState',
    'signalwire.disconnect'          => 'Disconnect',
};

# --- Action Terminal States (per event type) ---
use constant ACTION_TERMINAL_STATES => {
    'calling.call.play'       => { finished => 1, error    => 1 },
    'calling.call.record'     => { finished => 1, no_input => 1 },
    'calling.call.detect'     => { finished => 1, error    => 1 },
    'calling.call.collect'    => { finished => 1, error    => 1, no_input => 1, no_match => 1 },
    'calling.call.fax'        => { finished => 1, error    => 1 },
    'calling.call.tap'        => { finished => 1 },
    'calling.call.stream'     => { finished => 1 },
    'calling.call.transcribe' => { finished => 1 },
    'calling.call.pay'        => { finished => 1, error => 1 },
};

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::Constants - protocol version, call/dial/message states, and event types for RELAY

=head1 SYNOPSIS

    use SignalWire::Relay::Constants qw(
        PROTOCOL_VERSION CALL_STATE_ANSWERED CALL_TERMINAL_STATES EVENT_TYPES
    );

    my $ver   = PROTOCOL_VERSION;              # { major => 2, minor => 0, revision => 0 }
    my $klass = EVENT_TYPES->{'calling.call.state'};   # 'CallState'

    # ...or import everything:
    use SignalWire::Relay::Constants qw(:all);

=head1 DESCRIPTION

L<SignalWire::Relay::Constants> is a C<use constant> package collecting the
RELAY WebSocket protocol constants: the protocol version, the enumerated
call/dial/message states and their terminal-state sets, the event-type
dispatch map, and per-event action terminal states. Every constant is
exportable by name or via the C<:all> tag.

=head1 CONSTANTS

=over 4

=item PROTOCOL_VERSION

Hashref C<< { major => 2, minor => 0, revision => 0 } >> for
C<signalwire.connect>.

=item Call states

C<CALL_STATE_CREATED>, C<CALL_STATE_RINGING>, C<CALL_STATE_ANSWERED>,
C<CALL_STATE_ENDING>, C<CALL_STATE_ENDED> (scalars); C<CALL_STATES> (an
ordered arrayref of all five); C<CALL_TERMINAL_STATES> (a set hashref of the
terminal states); and C<CALL_END_REASONS> (a hashref of end-reason values:
hangup, cancel, busy, noAnswer, decline, error).

=item Dial states

C<DIAL_STATE_DIALING>, C<DIAL_STATE_ANSWERED>, C<DIAL_STATE_FAILED>
(scalars); C<DIAL_STATES> (arrayref); C<DIAL_TERMINAL_STATES> (a set
hashref -- answered and failed are terminal; dialing is in-progress).

=item Message states

C<MESSAGE_STATE_QUEUED>, C<MESSAGE_STATE_INITIATED>, C<MESSAGE_STATE_SENT>,
C<MESSAGE_STATE_DELIVERED>, C<MESSAGE_STATE_UNDELIVERED>,
C<MESSAGE_STATE_FAILED>, C<MESSAGE_STATE_RECEIVED> (scalars);
C<MESSAGE_STATES> (arrayref); C<MESSAGE_TERMINAL_STATES> (a set hashref of
delivered/undelivered/failed).

=item EVENT_TYPES

A hashref mapping each RELAY event name (e.g. C<calling.call.state>,
C<messaging.receive>, C<signalwire.disconnect>) to its handler class name
(e.g. C<CallState>, C<MessageReceive>, C<Disconnect>).

=item ACTION_TERMINAL_STATES

A hashref, keyed by action event name (C<calling.call.play>,
C<calling.call.record>, ...), of the set of states that complete that
action (e.g. C<< { finished => 1, error => 1 } >>).

=back

=head1 SEE ALSO

L<SignalWire::Relay::Client>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
