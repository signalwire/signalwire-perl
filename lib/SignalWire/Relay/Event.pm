package SignalWire::Relay::Event;
use strict;
use warnings;
use Moo;

# Subroutine signatures (stable since Perl 5.36, the SDK's floor), enabled
# file-wide.
use feature 'signatures';

# Base event class -- all relay events inherit from this.
# Python parity: RelayEvent base carries call_id (dataclass field), populated
# from params.call_id by from_payload for every subclass.
has 'call_id'    => ( is => 'ro', default => sub { '' } );
has 'event_type' => ( is => 'ro', default => sub { '' } );
has 'timestamp'  => ( is => 'ro', default => sub { 0 } );
has 'params'     => ( is => 'ro', default => sub { {} } );

# Class-method constructor from a raw ``{event_type, params}`` payload hashref.
# Mirrors the Python reference's RelayEvent.from_payload / every subclass's
# from_payload: build an instance of the invoking class, copying the payload's
# ``params`` fields up into the typed attributes (Moo ignores unknown keys, so
# a forward-compatible server shape is never rejected). Inherited by every
# typed subclass, so ``PlayEvent->from_payload($payload)`` yields a populated
# ::CallPlay-equivalent — the cross-language surface records from_payload on
# each event class.
sub from_payload ( $class, $payload = undef ) {
    $payload //= {};
    my $event_type = $payload->{event_type} // '';
    my $params     = $payload->{params}     // {};
    my %args       = ( event_type => $event_type, params => $params );
    $args{timestamp} = $params->{timestamp} if defined $params->{timestamp};
    for my $key ( keys %$params ) {
        $args{$key} = $params->{$key};
    }
    return $class->new(%args);
}

# --- Subclasses for each event type ---

# Call state change: created, ringing, answered, ending, ended
package SignalWire::Relay::Event::CallState;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'tag' => ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{tag} // '' } );
has 'call_state' => ( is => 'ro', default => sub { '' } );
has 'direction'  => ( is => 'ro', default => sub { '' } ); # Python parity: CallStateEvent.direction
has 'device'     => ( is => 'ro', default => sub { {} } );
has 'end_reason' => ( is => 'ro', default => sub { '' } );
has 'peer' => ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{peer} // {} } );

# Inbound call offer
package SignalWire::Relay::Event::CallReceive;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id'    => ( is => 'ro', default => sub { '' } );
has 'node_id'    => ( is => 'ro', default => sub { '' } );
has 'tag'        => ( is => 'ro', default => sub { '' } );
has 'call_state' => ( is => 'ro', default => sub { '' } );
has 'device'     => ( is => 'ro', default => sub { {} } );
has 'context'    => ( is => 'ro', default => sub { '' } );

# Python parity: CallReceiveEvent.direction/project_id/segment_id
has 'direction'  => ( is => 'ro', default => sub { '' } );
has 'project_id' => ( is => 'ro', default => sub { '' } );
has 'segment_id' => ( is => 'ro', default => sub { '' } );

# Dial completion
package SignalWire::Relay::Event::CallDial;
use Moo;
extends 'SignalWire::Relay::Event';
has 'tag' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'dial_state' => ( is => 'ro', default => sub { '' } );
has 'call'       => ( is => 'ro', default => sub { {} } );

# Connect state
package SignalWire::Relay::Event::CallConnect;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'connect_state' => ( is => 'ro', default => sub { '' } );
has 'peer'          => ( is => 'ro', default => sub { {} } );

# Disconnect state
package SignalWire::Relay::Event::CallDisconnect;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' => ( is => 'ro', default => sub { '' } );

# Play state
package SignalWire::Relay::Event::CallPlay;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );

# Record state
package SignalWire::Relay::Event::CallRecord;
use Moo;
use feature 'signatures';
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );
has 'url'        => ( is => 'ro', default => sub { '' } );
has 'duration'   => ( is => 'ro', default => sub { 0 } );
has 'size'       => ( is => 'ro', default => sub { 0 } );
has 'record'     => ( is => 'ro', default => sub { {} } );

# Python parity: RecordEvent.from_payload resolves url/duration/size from the
# nested ``record`` object first, falling back to the flat params — the wire
# sends the finished-recording metadata under params.record{}.
sub from_payload ( $class, $payload = undef ) {
    my $self = $class->SUPER::from_payload($payload);
    my $p    = ( $payload && ref $payload->{params} eq 'HASH' ) ? $payload->{params} : {};
    my $rec  = ref $p->{record} eq 'HASH'                       ? $p->{record}       : {};
    $self->{url}      = $rec->{url}      // $p->{url}      // '';
    $self->{duration} = $rec->{duration} // $p->{duration} // 0;
    $self->{size}     = $rec->{size}     // $p->{size}     // 0;
    return $self;
}

# Collect result
package SignalWire::Relay::Event::CallCollect;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );    # Python parity: CollectEvent.state
has 'result'     => ( is => 'ro', default => sub { {} } );

# Python parity: CollectEvent.final is Optional[bool] defaulting to None (NOT
# false) — the base from_payload copies params.final up verbatim, so it stays
# undef when the wire omits it.
has 'final' => ( is => 'ro', default => sub { undef } );

# Detect result
package SignalWire::Relay::Event::CallDetect;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'detect'     => ( is => 'ro', default => sub { {} } );

# Fax state (send_fax / receive_fax)
package SignalWire::Relay::Event::CallFax;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'fax'        => ( is => 'ro', default => sub { {} } );

# Tap state
package SignalWire::Relay::Event::CallTap;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );
has 'tap'        => ( is => 'ro', default => sub { {} } );
has 'device'     => ( is => 'ro', default => sub { {} } );    # Python parity: TapEvent.device

# Stream state
package SignalWire::Relay::Event::CallStream;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );

# Python parity: StreamEvent.name/url
has 'name' => ( is => 'ro', default => sub { '' } );
has 'url'  => ( is => 'ro', default => sub { '' } );

# Transcribe state
package SignalWire::Relay::Event::CallTranscribe;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );

# Python parity: TranscribeEvent.url/recording_id/duration/size
has 'url'          => ( is => 'ro', default => sub { '' } );
has 'recording_id' => ( is => 'ro', default => sub { '' } );
has 'duration'     => ( is => 'ro', default => sub { 0 } );
has 'size'         => ( is => 'ro', default => sub { 0 } );

# Pay state
package SignalWire::Relay::Event::CallPay;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );
has 'result' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{result} // {} } );

# Send digits event
package SignalWire::Relay::Event::CallSendDigits;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'state'      => ( is => 'ro', default => sub { '' } );

# SIP REFER event
package SignalWire::Relay::Event::CallRefer;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'refer_state' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{refer_state} // '' } );

# Python parity: ReferEvent.state/sip_refer_to/sip_refer_response_code/sip_notify_response_code
has 'state'                    => ( is => 'ro', default => sub { '' } );
has 'sip_refer_to'             => ( is => 'ro', default => sub { '' } );
has 'sip_refer_response_code'  => ( is => 'ro', default => sub { '' } );
has 'sip_notify_response_code' => ( is => 'ro', default => sub { '' } );

# Conference event
package SignalWire::Relay::Event::Conference;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'conference_id' => ( is => 'ro', default => sub { '' } );

# Python parity: ConferenceEvent.name/status
has 'name'   => ( is => 'ro', default => sub { '' } );
has 'status' => ( is => 'ro', default => sub { '' } );

# AI event (routed to the reference's CallingErrorEvent surface)
package SignalWire::Relay::Event::CallAI;
use Moo;
extends 'SignalWire::Relay::Event';
has 'call_id' => ( is => 'ro', default => sub { '' } );
has 'node_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{node_id} // '' } );
has 'control_id' =>
    ( init_arg => undef, is => 'lazy', builder => sub { $_[0]->params->{control_id} // '' } );

# Python parity: CallingErrorEvent.code/message
has 'code'    => ( is => 'ro', default => sub { '' } );
has 'message' => ( is => 'ro', default => sub { '' } );

# Denoise state change (calling.call.denoise)
package SignalWire::Relay::Event::CallDenoise;
use Moo;
extends 'SignalWire::Relay::Event';
has 'denoised' => ( is => 'ro', default => sub { 0 } );

# Echo state change (calling.call.echo)
package SignalWire::Relay::Event::CallEcho;
use Moo;
extends 'SignalWire::Relay::Event';
has 'state' => ( is => 'ro', default => sub { '' } );

# Hold/unhold state change (calling.call.hold)
package SignalWire::Relay::Event::CallHold;
use Moo;
extends 'SignalWire::Relay::Event';
has 'state' => ( is => 'ro', default => sub { '' } );

# Queue state change (calling.call.queue)
package SignalWire::Relay::Event::CallQueue;
use Moo;
use feature 'signatures';
extends 'SignalWire::Relay::Event';
has 'control_id' => ( is => 'ro', default => sub { '' } );
has 'status'     => ( is => 'ro', default => sub { '' } );
has 'position'   => ( is => 'ro', default => sub { 0 } );
has 'size'       => ( is => 'ro', default => sub { 0 } );
has 'queue_id'   => ( is => 'ro', default => sub { '' } );
has 'queue_name' => ( is => 'ro', default => sub { '' } );

# Python parity: QueueEvent.from_payload RENAMES params.id -> queue_id and
# params.name -> queue_name (the wire uses the bare id/name keys).
sub from_payload ( $class, $payload = undef ) {
    my $self = $class->SUPER::from_payload($payload);
    my $p    = ( $payload && ref $payload->{params} eq 'HASH' ) ? $payload->{params} : {};
    $self->{queue_id}   = $p->{id}   // '';
    $self->{queue_name} = $p->{name} // '';
    return $self;
}

# Inbound message
package SignalWire::Relay::Event::MessageReceive;
use Moo;
extends 'SignalWire::Relay::Event';
has 'message_id'    => ( is => 'ro', default => sub { '' } );
has 'context'       => ( is => 'ro', default => sub { '' } );
has 'direction'     => ( is => 'ro', default => sub { 'inbound' } );
has 'from_number'   => ( is => 'ro', default => sub { '' } );
has 'to_number'     => ( is => 'ro', default => sub { '' } );
has 'body'          => ( is => 'ro', default => sub { '' } );
has 'media'         => ( is => 'ro', default => sub { [] } );
has 'segments'      => ( is => 'ro', default => sub { 0 } );
has 'message_state' => ( is => 'ro', default => sub { 'received' } );
has 'tags'          => ( is => 'ro', default => sub { [] } );

# Outbound message state change
package SignalWire::Relay::Event::MessageState;
use Moo;
extends 'SignalWire::Relay::Event';
has 'message_id'    => ( is => 'ro', default => sub { '' } );
has 'context'       => ( is => 'ro', default => sub { '' } );
has 'direction'     => ( is => 'ro', default => sub { 'outbound' } );
has 'from_number'   => ( is => 'ro', default => sub { '' } );
has 'to_number'     => ( is => 'ro', default => sub { '' } );
has 'body'          => ( is => 'ro', default => sub { '' } );
has 'media'         => ( is => 'ro', default => sub { [] } );
has 'segments'      => ( is => 'ro', default => sub { 0 } );
has 'message_state' => ( is => 'ro', default => sub { '' } );
has 'reason'        => ( is => 'ro', default => sub { '' } );
has 'tags'          => ( is => 'ro', default => sub { [] } );

# Authorization state
package SignalWire::Relay::Event::AuthorizationState;
use Moo;
extends 'SignalWire::Relay::Event';
has 'authorization_state' => ( is => 'ro', default => sub { '' } );

# Server disconnect
package SignalWire::Relay::Event::Disconnect;
use Moo;
extends 'SignalWire::Relay::Event';
has 'restart' => ( is => 'ro', default => sub { 0 } );

# --- Factory method ---
package SignalWire::Relay::Event;

# Map event_type string to class name
my %EVENT_CLASS_MAP = (
    'calling.call.state'             => 'SignalWire::Relay::Event::CallState',
    'calling.call.receive'           => 'SignalWire::Relay::Event::CallReceive',
    'calling.call.dial'              => 'SignalWire::Relay::Event::CallDial',
    'calling.call.connect'           => 'SignalWire::Relay::Event::CallConnect',
    'calling.call.disconnect'        => 'SignalWire::Relay::Event::CallDisconnect',
    'calling.call.play'              => 'SignalWire::Relay::Event::CallPlay',
    'calling.call.record'            => 'SignalWire::Relay::Event::CallRecord',
    'calling.call.collect'           => 'SignalWire::Relay::Event::CallCollect',
    'calling.call.detect'            => 'SignalWire::Relay::Event::CallDetect',
    'calling.call.fax'               => 'SignalWire::Relay::Event::CallFax',
    'calling.call.tap'               => 'SignalWire::Relay::Event::CallTap',
    'calling.call.stream'            => 'SignalWire::Relay::Event::CallStream',
    'calling.call.transcribe'        => 'SignalWire::Relay::Event::CallTranscribe',
    'calling.call.pay'               => 'SignalWire::Relay::Event::CallPay',
    'calling.call.send_digits'       => 'SignalWire::Relay::Event::CallSendDigits',
    'calling.call.refer'             => 'SignalWire::Relay::Event::CallRefer',
    'calling.call.denoise'           => 'SignalWire::Relay::Event::CallDenoise',
    'calling.call.echo'              => 'SignalWire::Relay::Event::CallEcho',
    'calling.call.hold'              => 'SignalWire::Relay::Event::CallHold',
    'calling.call.queue'             => 'SignalWire::Relay::Event::CallQueue',
    'calling.conference'             => 'SignalWire::Relay::Event::Conference',
    'calling.call.ai'                => 'SignalWire::Relay::Event::CallAI',
    'messaging.receive'              => 'SignalWire::Relay::Event::MessageReceive',
    'messaging.state'                => 'SignalWire::Relay::Event::MessageState',
    'signalwire.authorization.state' => 'SignalWire::Relay::Event::AuthorizationState',
    'signalwire.disconnect'          => 'SignalWire::Relay::Event::Disconnect',
);

sub parse_event ( $class_or_self, $event_type, $params = undef ) {
    $params //= {};

    my $event_class = $EVENT_CLASS_MAP{$event_type} // 'SignalWire::Relay::Event';

    # Python parity: parse_event dispatches to the typed class's from_payload so
    # its per-class renames/fallbacks apply (e.g. QueueEvent queue_id<-id,
    # RecordEvent url<-record.url). Reconstruct the {event_type, params}
    # payload the from_payload constructors expect.
    return $event_class->from_payload( { event_type => $event_type, params => $params } );
}

1;

__END__

=encoding utf-8

=head1 NAME

SignalWire::Relay::Event - typed RELAY event objects and their factory

=head1 SYNOPSIS

    use SignalWire::Relay::Event;

    my $event = SignalWire::Relay::Event->parse_event(
        'calling.call.state',
        { call_id => $id, call_state => 'answered' },
    );

    $event->event_type;   # 'calling.call.state'
    $event->call_state;   # 'answered'  (on the ::CallState subclass)

=head1 DESCRIPTION

L<SignalWire::Relay::Event> is the base class for every RELAY event the
client receives. Each concrete event type is a small read-only Moo
subclass that exposes the fields relevant to it (for example
C<::CallState> carries C<call_state> / C<end_reason> / C<peer>, while
C<::MessageReceive> carries C<from_number> / C<body> / C<media>). All
subclasses inherit C<event_type>, C<timestamp>, and the raw C<params>
hashref from the base class.

The event objects are read-only data carriers built from the server
payload; they deliberately carry no C<isa> constraints so a forward-
compatible server shape is never rejected — unknown fields are simply
ignored by Moo.

=head1 METHODS

=head2 parse_event

    my $event = SignalWire::Relay::Event->parse_event($event_type, $params);

Class-method factory. Looks C<$event_type> up in the internal event-class
map and returns an instance of the matching subclass, populated from
C<$params> (which defaults to an empty hashref). Unknown event types fall
back to a base L<SignalWire::Relay::Event> carrying the raw type and
params. Normally called by L<SignalWire::Relay::Client> as it demultiplexes
the WebSocket stream.

=head1 EVENT TYPES

The recognised C<event_type> strings and their subclasses include the
C<calling.call.*> family (state, receive, dial, connect, disconnect, play,
record, collect, detect, fax, tap, stream, transcribe, pay, send_digits,
refer, ai), C<calling.conference>, C<messaging.receive> /
C<messaging.state>, and the C<signalwire.*> session events
(C<authorization.state>, C<disconnect>).

=head1 SEE ALSO

L<SignalWire::Relay::Client>, L<SignalWire::Relay::Call>,
L<SignalWire::Relay::Message>.

=head1 LICENSE

Copyright (c) 2025 SignalWire. Licensed under the MIT License.

=cut
