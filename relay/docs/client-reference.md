# Client Reference

`SignalWire::Relay::Client` owns the RELAY WebSocket transport, performs
the `signalwire.connect` handshake, runs a synchronous JSON-RPC request/
response loop, and routes server-pushed events to the right `Call` or
`Message`.

## Constructor

```perl
use SignalWire::Relay::Client;

my $client = SignalWire::Relay::Client->new(
    project   => $ENV{SIGNALWIRE_PROJECT_ID},   # legacy auth
    token     => $ENV{SIGNALWIRE_API_TOKEN},    # legacy auth
    jwt_token => $my_jwt,                        # alternative auth (pass your own JWT)
    host      => $ENV{SIGNALWIRE_SPACE},        # REQUIRED
    contexts  => ['default'],                   # topics to subscribe to
);
```

Authentication requires either `project` + `token` or `jwt_token`. The
`host` parameter is **required** — construction dies immediately if it is
missing or empty. `contexts` must be an arrayref.

## Methods

### `connect`

Opens the WebSocket and runs the `signalwire.connect` handshake in one
call. Returns the authenticate result on success and dies on failure.

```perl
$client->connect;
```

### `connect_ws` / `authenticate`

Lower-level lifecycle control. `connect_ws` opens the WebSocket (returns a
true value on success) and `authenticate` performs the handshake. This is
the form used in the bundled examples:

```perl
$client->connect_ws or die "WebSocket connect failed\n";
$client->authenticate;
```

### `run`

Blocking entry point. Drives the event loop, reading frames and dispatching
events. Call it after connecting.

On an UNEXPECTED connection drop, `run` auto-reconnects with exponential backoff
(via `reconnect`), bounded by a maximum consecutive-attempt cap so it never
reconnects forever. An INTENTIONAL `disconnect` (which sets the internal closing
flag) makes `run` return cleanly without reconnecting.

```perl
$client->run;
```

### `disconnect`

Tears down the WebSocket transport.

```perl
$client->disconnect;
```

### `reconnect`

Rejects any pending requests, waits with exponential backoff, then
re-opens the WebSocket and re-authenticates.

### `on_call($cb)`

Register the inbound call handler. The callback receives a
`SignalWire::Relay::Call` object. Returns `$self` for chaining.

```perl
$client->on_call(sub {
    my ($call) = @_;
    $call->answer;
});
```

### `on_message($cb)`

Register the inbound message handler. The callback receives a
`SignalWire::Relay::Event` (a `MessageReceive` event).

```perl
$client->on_message(sub {
    my ($event) = @_;
    printf "SMS from %s: %s\n", $event->from_number, $event->body;
});
```

### `on_event($cb)`

Register a global listener invoked for every event the client receives.

```perl
$client->on_event(sub {
    my ($event) = @_;
    print $event->event_type, "\n";
});
```

### `dial(%opts)`

Place an outbound call. Returns a `SignalWire::Relay::Call` once the remote
party answers (or dies if the dial fails).

- `devices` — nested list of device objects (serial/parallel dial)
- `tag` — optional correlation tag (auto-generated if omitted)
- `timeout` — seconds to wait before giving up (default 120)
- `region`, `max_price_per_minute`, `on_completed` — optional

```perl
my $call = $client->dial(
    devices => [
        [ { type => 'phone', params => {
            to_number   => '+15551234567',
            from_number => '+15559876543',
        } } ],
    ],
);
```

### `send_message(%opts)`

Send an outbound SMS/MMS. Returns a `SignalWire::Relay::Message` that
tracks delivery state. See [Messaging](messaging.md) for full details.

```perl
my $message = $client->send_message(
    to_number   => '+15552222222',
    from_number => '+15551111111',
    body        => 'Hello!',
);
my $event = $message->wait;   # block until delivered/failed
```

### `execute($method, $params)`

Send a raw JSON-RPC request and block for the result. Used internally by
Call methods, but available for custom commands.

```perl
my $result = $client->execute('calling.answer', { node_id => $n, call_id => $c });
```

### `receive($contexts)` / `unreceive($contexts)`

Dynamically subscribe to or unsubscribe from contexts after connecting.
Accepts an arrayref (canonical) or a bare list.

```perl
$client->receive(['new-context']);
$client->unreceive(['old-context']);
```

## Properties

| Property | Description |
|----------|-------------|
| `relay_protocol` | Server-assigned protocol string from the connect response |
| `protocol` | Same value as `relay_protocol` |
| `project` | Project ID |
| `host` | Relay host |
| `contexts` | Initial contexts (arrayref) |
| `session_id` | Server-assigned session id from the connect handshake |
| `connected` | True while the WebSocket is open |

## Connection Behavior

- **Reconnect**: `reconnect` re-opens the WebSocket with exponential
  backoff (1s doubling up to a 30s cap) and re-authenticates. Pending
  requests and dials are rejected before reconnecting.
- **Event ACKs**: Server-initiated events are acknowledged immediately;
  the client also ACKs server pings.
- **Authorization state**: The server sends auth state via a
  `signalwire.authorization.state` event. On reconnect it is sent back for
  fast re-authentication without a full auth roundtrip.
- **Server disconnect**: The server can request a graceful disconnect (for
  example during deployment). The client clears session state when the
  disconnect requests a restart.

## Error Handling

`execute` (and therefore the Call/Message methods built on it) dies with a
`RELAY error: ...` message when the server returns an error. Wrap calls in
`eval` to handle failures:

<!-- snippet: no-compile illustrative fragment with a list-literal yada-yada elision -->
```perl
my $result = eval { $call->play(play => [ ... ]) };
if (my $err = $@) {
    warn "play failed: $err";
}
```

Errors 404 and 410 (call gone) are handled by Call methods, which resolve
the returned action immediately rather than dying.
