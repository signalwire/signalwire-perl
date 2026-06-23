# Call Methods Reference

A `SignalWire::Relay::Call` object represents a live phone call. You get
one from the `on_call` handler (inbound) or `dial` (outbound). All
call-control methods take **named options** (`%opts`); the typed
convenience wrappers (`play_tts`, `detect_digit`, …) take a leading
positional argument plus named options.

## Properties

| Property | Description |
|----------|-------------|
| `call_id` | Unique call identifier |
| `node_id` | Server node handling the call |
| `state` | Current state: `created`, `ringing`, `answered`, `ending`, `ended` |
| `tag` | Correlation tag |
| `device` | Device info (hashref) |
| `context` | Context the inbound call arrived on |
| `peer` | Peer info on a connected call (hashref) |
| `end_reason` | Reason the call ended |

Typed state helpers: `current_state` returns the same wire string as
`state`, and `is_terminal` is true once the call has ended.

## Actions: Blocking vs Fire-and-Forget

Methods like `play`, `record`, and `detect` return **Action** objects
(`SignalWire::Relay::Action` subclasses). The method call itself only waits
for the server to accept the command — the operation runs on the server.
You choose how to handle completion.

### Wait inline (blocking)

```perl
my $action = $call->play(
    media => [ { type => 'tts', params => { text => 'Hello' } } ],
);
$action->wait;   # blocks until playback finishes
# execution continues only after play is done
```

### Fire and forget (background)

```perl
my $action = $call->play(
    media => [ { type => 'tts', params => { text => 'Hello' } } ],
);
# don't call $action->wait — continue immediately while audio plays
$call->send_digits(digits => '1234');

# check later if needed
if ($action->is_done) {
    print "Play result: ", $action->result, "\n";
}
```

### Fire with callback

```perl
my $action = $call->play(
    media        => [ { type => 'tts', params => { text => 'Hello' } } ],
    on_completed => sub {
        my ($a) = @_;
        print "Done in state: ", $a->state, "\n";
    },
);
```

The `on_completed` callback is available on all action-based methods:
`play`, `record`, `play_and_collect`, `collect`, `detect`, `pay`,
`send_fax`, `receive_fax`, `tap`, `stream`, `transcribe`, and `ai`. Errors
in callbacks are caught and logged, never crashing the event loop. The
callback also fires when the call is gone (404/410).

### Action methods summary

| Method | Description |
|--------|-------------|
| `$action->wait(timeout => $secs)` | Block until the action completes (default 30s); returns the terminal event |
| `$action->is_done` | True if the action has completed |
| `$action->result` | The terminal event (or `undef` if not done) |
| `$action->completed` | True if the action reached a terminal state |
| `$action->stop` | Stop the operation on the server |
| `$action->on_completed($cb)` | Register a completion callback |

Some actions also have `pause`, `resume`, and `volume($vol)` (Play) or
`pause`/`resume` and `url`/`duration`/`size` accessors (Record).

## Lifecycle

### `answer(%opts)`

Answer an inbound call.

```perl
$call->answer;
```

### `hangup(%opts)`

End the call.

```perl
$call->hangup;
$call->hangup(reason => 'busy');
```

### `pass`

Decline control, returning the call to routing.

```perl
$call->pass;
```

## Audio Playback

### `play(media => [...], %opts)`

Play audio. Returns a Play action with `stop`, `pause`, `resume`,
`volume($vol)`, and `wait`.

```perl
# TTS
my $action = $call->play(
    media => [ { type => 'tts', params => { text => 'Hello!' } } ],
);
$action->wait;

# Audio file
$call->play(
    media => [ { type => 'audio', params => { url => 'https://example.com/sound.mp3' } } ],
);

# Silence
$call->play(
    media => [ { type => 'silence', params => { duration => 2 } } ],
);

# Ringtone
$call->play(
    media => [ { type => 'ringtone', params => { name => 'us' } } ],
);

# Control playback
$action->pause;
$action->resume;
$action->volume(-3.0);
$action->stop;
```

### Typed play wrappers

These build the media object for you and delegate to `play`:

```perl
$call->play_tts('Hello!', voice => 'en-US-Neural2-A');
$call->play_audio('https://example.com/sound.mp3');
$call->play_silence(2);
$call->play_ringtone('us');
```

## Recording

### `record(%opts)`

Record the call. Returns a Record action with `stop`, `pause`, `resume`,
and `wait`, plus `url`/`duration`/`size` accessors once complete.

```perl
my $action = $call->record(
    record => { format => 'wav', stereo => JSON::true, direction => 'both' },
);
# ... later ...
$action->stop;
$action->wait;
print "Recording URL: ", $action->url, "\n";
```

## Input Collection

### `play_and_collect(play => [...], collect => {...}, %opts)`

Play audio and collect DTMF or speech input. Returns a Collect action.

```perl
my $action = $call->play_and_collect(
    play    => [ { type => 'tts', params => { text => 'Press 1 for sales, 2 for support.' } } ],
    collect => { digits => { max => 1, digit_timeout => 5.0 } },
);
my $event = $action->wait;
my $result = $action->collect_result;
```

A typed wrapper, `prompt_tts`, plays a TTS prompt and collects in one call:

```perl
$call->prompt_tts(
    'Press 1 for sales, 2 for support.',
    { digits => { max => 1, digit_timeout => 5.0 } },
);
```

### `collect(%opts)`

Collect input without playing audio. Returns a standalone Collect action.

```perl
my $action = $call->collect(
    digits => { max => 4, terminators => '#' },
    speech => { language => 'en-US' },
);
my $event = $action->wait;
```

## Bridging

### `connect(%opts)`

Bridge the call to another destination.

```perl
$call->connect(
    devices => [
        [ { type => 'phone', params => {
            to_number   => '+15551234567',
            from_number => '+15559876543',
        } } ],
    ],
    ringback => [ { type => 'ringtone', params => { name => 'us' } } ],
);
```

### `disconnect`

Unbridge a connected call.

```perl
$call->disconnect;
```

## DTMF

### `send_digits(%opts)`

Send DTMF tones.

```perl
$call->send_digits(digits => '1234#');
```

## Detection

### `detect(%opts)`

Detect machine, fax, or digits. Returns a Detect action.

```perl
my $action = $call->detect(
    detect  => { type => 'machine' },
    timeout => 30.0,
);
my $event = $action->wait;
```

Typed wrappers build the detect object for you:

```perl
$call->detect_answering_machine(timeout => 30);
$call->detect_digit(digits => '#');
$call->detect_fax;
```

## SIP Refer

### `refer(%opts)`

Transfer via SIP REFER.

```perl
$call->refer(device => { type => 'sip', params => { to => 'sip:user@example.com' } });
```

## Transfer

### `transfer(%opts)`

Transfer call control to another RELAY app or SWML script.

```perl
$call->transfer(dest => 'https://example.com/swml-endpoint');
```

## Fax

### `send_fax(%opts)`

Returns a Fax action.

```perl
my $action = $call->send_fax(
    document => 'https://example.com/document.pdf',
    identity => '+15551234567',
);
my $event = $action->wait;
print "Result: ", $action->fax_result->{direction} // '', "\n";
```

### `receive_fax(%opts)`

```perl
my $action = $call->receive_fax;
$action->wait;
```

## Tap (Media Interception)

### `tap(%opts)`

Intercept call media and stream to an RTP endpoint. Returns a Tap action.

```perl
my $action = $call->tap(
    tap    => { type => 'audio', params => { direction => 'both' } },
    device => { type => 'rtp', params => { addr => '192.168.1.100', port => 5000 } },
);
```

## Streaming

### `stream(%opts)`

Stream call audio to a WebSocket endpoint. Returns a Stream action.

```perl
my $action = $call->stream(
    url   => 'wss://example.com/audio',
    codec => 'PCMU',
);
# Stop streaming
$action->stop;
```

## Payment

### `pay(%opts)`

Collect a payment via DTMF. Returns a Pay action.

```perl
my $action = $call->pay(
    payment_connector_url => 'https://pay.example.com',
    charge_amount         => '25.99',
    currency              => 'usd',
);
my $event = $action->wait;
print "Result: ", $action->pay_result->{status} // '', "\n";
```

## Conference

### `join_conference(%opts)` / `leave_conference(%opts)`

```perl
$call->join_conference(name => 'my_conference', beep => 'onEnter');
$call->leave_conference(conference_id => 'conf-123');
```

## Hold

### `hold` / `unhold`

```perl
$call->hold;
# ... later ...
$call->unhold;
```

## Denoise

### `denoise` / `denoise_stop`

```perl
$call->denoise;
# ... later ...
$call->denoise_stop;
```

## Transcription

### `transcribe(%opts)`

Returns a Transcribe action.

```perl
my $action = $call->transcribe(status_url => 'https://example.com/transcription');
# ... later ...
$action->stop;
```

## Live Transcribe / Translate

### `live_transcribe(%opts)` / `live_translate(%opts)`

```perl
$call->live_transcribe(start => { language => 'en-US' });
$call->live_translate(start => { source => 'en-US', target => 'es' });
```

## Echo

### `echo(%opts)`

Echo audio back to the caller (useful for testing).

```perl
$call->echo(timeout => 30);
```

## AI Agent

### `ai(%opts)`

Start an AI agent session on the call. Returns an AI action.

```perl
my $action = $call->ai(
    prompt    => { text => 'You are a helpful support agent.' },
    SWAIG     => { functions => [] },
    ai_params => { end_of_speech_timeout => 3000 },
);
my $event = $action->wait;
```

### `amazon_bedrock(%opts)`

Connect to an Amazon Bedrock AI agent.

### `ai_message(%opts)`

Send a message to an active AI session.

### `ai_hold(%opts)` / `ai_unhold(%opts)`

Put an AI session on/off hold.

## Rooms

### `join_room(%opts)` / `leave_room(%opts)`

```perl
$call->join_room(name => 'my_room');
$call->leave_room;
```

## Queue

### `queue_enter(%opts)` / `queue_leave(%opts)`

```perl
$call->queue_enter(queue_name => 'support');
$call->queue_leave(queue_name => 'support', queue_id => 'q-123');
```

## Digit Bindings

### `bind_digit(%opts)` / `clear_digit_bindings(%opts)`

Bind a DTMF sequence to trigger a RELAY method.

```perl
$call->bind_digit(
    digits      => '*1',
    bind_method => 'calling.play',
    bind_params => { play => [ { type => 'tts', params => { text => 'You pressed star-1' } } ] },
);
$call->clear_digit_bindings;
```

## User Events

### `user_event(%opts)`

Send a custom event.

```perl
$call->user_event(event => 'order_placed', order_id => '12345');
```

## Event Handling

### `on($cb)`

Register an event listener on this call. The callback is invoked as
`$cb->($call, $event)` for every dispatched event.

```perl
$call->on(sub {
    my ($c, $event) = @_;
    if ($event->event_type eq 'calling.call.play') {
        print "Play state: ", $event->state, "\n";
    }
});
```

See [Events](events.md) for the full list of event types and their fields.
