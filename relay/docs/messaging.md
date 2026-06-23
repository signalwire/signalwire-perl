# Messaging

Send and receive SMS/MMS messages through the RELAY client.

## Sending Messages

Use `send_message` to send an outbound SMS or MMS. It returns a
`SignalWire::Relay::Message` that tracks delivery state.

```perl
my $message = $client->send_message(
    to_number   => '+15552222222',
    from_number => '+15551111111',
    body        => 'Hello from SignalWire!',
);
```

### Wait for delivery

```perl
my $message = $client->send_message(
    to_number   => '+15552222222',
    from_number => '+15551111111',
    body        => 'Hello!',
);
my $event = $message->wait;   # blocks until delivered/failed
print "Final state: ", $message->state, "\n";
if ($message->reason) {
    print "Reason: ", $message->reason, "\n";
}
```

### Fire and forget

```perl
my $message = $client->send_message(
    to_number   => '+15552222222',
    from_number => '+15551111111',
    body        => 'Hello!',
);
# don't call $message->wait — continue immediately
```

### Callback on completion

```perl
my $message = $client->send_message(
    to_number    => '+15552222222',
    from_number  => '+15551111111',
    body         => 'Hello!',
    on_completed => sub {
        my ($m) = @_;
        print "Delivery: ", $m->state, "\n";
    },
);
```

### MMS (media messages)

```perl
my $message = $client->send_message(
    to_number   => '+15552222222',
    from_number => '+15551111111',
    body        => 'Check this out!',
    media       => ['https://example.com/image.jpg'],
);
```

### All parameters

```perl
my $message = $client->send_message(
    to_number    => '+15552222222',   # required — E.164 format
    from_number  => '+15551111111',   # required — E.164 format
    body         => 'Message text',   # required if no media
    media        => ['https://...'],  # required if no body
    context      => 'my_context',     # context for state events (default: relay protocol)
    tags         => ['vip', 'support'], # optional tags for searching in the UI
    region       => 'us',             # optional origination region
    on_completed => sub { ... },      # optional completion callback
);
```

At least one of `body` or `media` is required.

## Receiving Messages

Register a handler with `on_message` to receive inbound SMS/MMS. The
callback receives a `SignalWire::Relay::Event::MessageReceive`.

```perl
use SignalWire::Relay::Client;

my $client = SignalWire::Relay::Client->new(
    project  => $ENV{SIGNALWIRE_PROJECT_ID},
    token    => $ENV{SIGNALWIRE_API_TOKEN},
    host     => $ENV{SIGNALWIRE_SPACE},
    contexts => ['default'],
);

$client->on_message(sub {
    my ($event) = @_;
    print "From: ", $event->from_number, "\n";
    print "To: ",   $event->to_number,   "\n";
    print "Body: ", $event->body,        "\n";
    if (@{ $event->media }) {
        print "Media: ", join(', ', @{ $event->media }), "\n";
    }

    # Reply back
    $client->send_message(
        to_number   => $event->from_number,
        from_number => $event->to_number,
        body        => 'You said: ' . $event->body,
    );
});

$client->connect_ws or die "Connection failed\n";
$client->authenticate;
$client->run;
```

## Message Object

The object returned by `send_message`.

### Properties

| Property | Description |
|----------|-------------|
| `message_id` | Unique message identifier |
| `context` | Context the message belongs to |
| `direction` | `inbound` or `outbound` |
| `from_number` | Sender phone number (E.164) |
| `to_number` | Recipient phone number (E.164) |
| `body` | Text body of the message |
| `media` | Media URLs (arrayref, MMS) |
| `segments` | Number of message segments |
| `state` | Current message state |
| `reason` | Failure reason (on `undelivered` or `failed`) |
| `tags` | Tags attached to the message (arrayref) |
| `result` | Terminal event (or `undef` if not done) |

### Methods

| Method | Description |
|--------|-------------|
| `$message->wait(timeout => $secs)` | Block until terminal state (default 30s); returns the terminal event |
| `$message->is_done` | True once the message has resolved (completed) |
| `$message->is_terminal` | True when the current `state` is a terminal delivery state |
| `$message->current_state` | The current delivery state (same wire string as `state`) |
| `$message->on($cb)` | Register a listener `$cb->($message, $event)` for state-change events |
| `$message->on_completed($cb)` | Register a callback fired once with `$message` when it completes |

### Message States

Outbound messages progress through these states:

| State | Description |
|-------|-------------|
| `queued` | Message accepted and queued for sending |
| `initiated` | Sending has started |
| `sent` | Message sent to carrier |
| `delivered` | Delivered to recipient (terminal) |
| `undelivered` | Delivery failed (terminal) — check `reason` |
| `failed` | Failed to send (terminal) — check `reason` |

Inbound messages always arrive with state `received`.

## Event Types

| `event_type` | Class | Description |
|--------------|-------|-------------|
| `messaging.receive` | `Event::MessageReceive` | Inbound message received |
| `messaging.state` | `Event::MessageState` | Outbound message state change |

See [Events](events.md) for the full list of fields on each.

## Combining Calls and Messages

The same client handles both calls and messages:

```perl
my $client = SignalWire::Relay::Client->new(
    project  => $ENV{SIGNALWIRE_PROJECT_ID},
    token    => $ENV{SIGNALWIRE_API_TOKEN},
    host     => $ENV{SIGNALWIRE_SPACE},
    contexts => ['default'],
);

$client->on_call(sub {
    my ($call) = @_;
    $call->answer;
    $call->play(media => [ { type => 'tts', params => { text => 'Hello!' } } ]);
    $call->hangup;
});

$client->on_message(sub {
    my ($event) = @_;
    printf "SMS from %s: %s\n", $event->from_number, $event->body;
});

$client->connect_ws or die "Connection failed\n";
$client->authenticate;
$client->run;
```
