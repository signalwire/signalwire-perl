# Events

RELAY events are server-pushed notifications about call state changes and
operation results. They arrive over the WebSocket as `signalwire.event`
JSON-RPC messages, are parsed into typed `SignalWire::Relay::Event`
objects, and are routed to the correct `Call` or `Message`.

## Listening for Events

### On a Call

Register a listener with `on`. The callback receives the call and the
event; filter by `event_type`:

```perl
$client->on_call(sub {
    my ($call) = @_;

    $call->on(sub {
        my ($c, $event) = @_;
        if ($event->event_type eq 'calling.call.play') {
            print "Play state: ", $event->state, "\n";
        }
        elsif ($event->event_type eq 'calling.call.state'
            && $event->call_state eq 'ended') {
            print "Call ended: ", $event->end_reason, "\n";
        }
    });
});
```

### Globally on the Client

Register `on_event` to see every event the client receives:

```perl
$client->on_event(sub {
    my ($event) = @_;
    print $event->event_type, "\n";
});
```

### Via Actions

Actions returned by `play`, `record`, etc. have a `wait` method that blocks
until the operation completes and returns the terminal event:

```perl
my $action = $call->play(
    play => [ { type => 'tts', params => { text => 'Hello' } } ],
);
my $event = $action->wait(timeout => 30);
# $event is the terminal SignalWire::Relay::Event
```

## Event Types and Their Classes

Each `event_type` string maps to a typed `SignalWire::Relay::Event`
subclass with the fields relevant to it. All subclasses inherit
`event_type`, `timestamp`, and the raw `params` hashref from the base
class.

| `event_type` | Class | Key fields |
|--------------|-------|-----------|
| `calling.call.state` | `Event::CallState` | `call_id`, `call_state`, `end_reason`, `device`, `peer`, `tag` |
| `calling.call.receive` | `Event::CallReceive` | `call_id`, `call_state`, `device`, `node_id`, `context`, `tag` |
| `calling.call.dial` | `Event::CallDial` | `tag`, `dial_state`, `call` |
| `calling.call.connect` | `Event::CallConnect` | `call_id`, `connect_state`, `peer` |
| `calling.call.disconnect` | `Event::CallDisconnect` | `call_id`, `node_id` |
| `calling.call.play` | `Event::CallPlay` | `control_id`, `state` |
| `calling.call.record` | `Event::CallRecord` | `control_id`, `state`, `url`, `duration`, `size`, `record` |
| `calling.call.collect` | `Event::CallCollect` | `control_id`, `result` |
| `calling.call.detect` | `Event::CallDetect` | `control_id`, `detect` |
| `calling.call.fax` | `Event::CallFax` | `control_id`, `fax` |
| `calling.call.tap` | `Event::CallTap` | `control_id`, `state`, `tap` |
| `calling.call.stream` | `Event::CallStream` | `control_id`, `state` |
| `calling.call.transcribe` | `Event::CallTranscribe` | `control_id`, `state` |
| `calling.call.pay` | `Event::CallPay` | `control_id`, `state`, `result` |
| `calling.call.send_digits` | `Event::CallSendDigits` | `control_id`, `state` |
| `calling.call.refer` | `Event::CallRefer` | `call_id`, `refer_state` |
| `calling.call.ai` | `Event::CallAI` | `call_id`, `control_id` |
| `calling.conference` | `Event::Conference` | `call_id`, `conference_id` |
| `messaging.receive` | `Event::MessageReceive` | `message_id`, `from_number`, `to_number`, `body`, `media`, `tags`, `message_state` |
| `messaging.state` | `Event::MessageState` | `message_id`, `from_number`, `to_number`, `body`, `message_state`, `reason`, `tags` |
| `signalwire.authorization.state` | `Event::AuthorizationState` | `authorization_state` |
| `signalwire.disconnect` | `Event::Disconnect` | `restart` |

## Parsing Events

`SignalWire::Relay::Event` exposes a class-method factory, `parse_event`,
that the client uses to demultiplex the WebSocket stream. You can use it
directly:

```perl
use SignalWire::Relay::Event;

my $event = SignalWire::Relay::Event->parse_event(
    'calling.call.state',
    { call_id => $id, call_state => 'answered' },
);

$event->event_type;   # 'calling.call.state'
$event->call_state;   # 'answered'
```

Unknown event types fall back to a base `SignalWire::Relay::Event`
carrying the raw type and `params`.

## Call States

```
created -> ringing -> answered -> ending -> ended
```

The terminal state is `ended`. Use `$call->is_terminal` to test whether a
call has reached it, or read `$call->state` / `$call->current_state` for
the current value.

## End Reasons

When a call reaches the `ended` state, the `end_reason` field on a
`calling.call.state` event indicates why:

| Reason | Description |
|--------|-------------|
| `hangup` | Normal hangup |
| `cancel` | Caller cancelled |
| `busy` | Destination busy |
| `noAnswer` | No answer |
| `decline` | Call declined |
| `error` | Error occurred |

## Message States

Outbound messages progress through `queued` → `initiated` → `sent` →
`delivered` (or `undelivered` / `failed`). The terminal states are
`delivered`, `undelivered`, and `failed`. Inbound messages arrive with
state `received`. See [Messaging](messaging.md) for details.
