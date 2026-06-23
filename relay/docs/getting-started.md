# Getting Started with RELAY

The RELAY client connects to SignalWire over a WebSocket and gives you
real-time, imperative control over phone calls and messages. The Perl
client is synchronous: operations block until the server responds, and a
blocking event loop (`run`) drives incoming events.

## Requirements

The RELAY client is part of the SignalWire Perl SDK and requires **Perl
5.36 or newer**.

## Installation

Install the SDK's dependencies from the bundled `cpanfile` with
[`cpanm`](https://metacpan.org/pod/App::cpanminus):

```bash
cpanm --installdeps .
```

Or install the RELAY client's dependencies directly:

```bash
cpanm Moo JSON Plack Protocol::WebSocket IO::Socket::SSL
```

## Configuration

You need three things to connect:

| Parameter | Env Var | Description |
|-----------|---------|-------------|
| `project` | `SIGNALWIRE_PROJECT_ID` | Your SignalWire project ID |
| `token`   | `SIGNALWIRE_API_TOKEN`  | Your SignalWire API token |
| `host`    | `SIGNALWIRE_SPACE`      | Your space hostname (e.g. `example.signalwire.com`) — **required** |

Alternatively, authenticate with a JWT token by passing `jwt_token`
instead of `project` + `token`. The `host` parameter is still required.

## Minimal Example

```perl
use strict;
use warnings;
use SignalWire::Relay::Client;

my $client = SignalWire::Relay::Client->new(
    project  => $ENV{SIGNALWIRE_PROJECT_ID},
    token    => $ENV{SIGNALWIRE_API_TOKEN},
    host     => $ENV{SIGNALWIRE_SPACE} // 'relay.signalwire.com',
    contexts => ['default'],
);

$client->on_call(sub {
    my ($call) = @_;
    $call->answer;
    my $action = $call->play(
        media => [ { type => 'tts', params => { text => 'Hello!' } } ],
    );
    $action->wait;
    $call->hangup;
});

$client->connect_ws or die "Connection failed\n";
$client->authenticate;
$client->run;
```

Export your credentials as environment variables so the script picks them
up:

```bash
export SIGNALWIRE_PROJECT_ID=your-project-id
export SIGNALWIRE_API_TOKEN=your-api-token
export SIGNALWIRE_SPACE=example.signalwire.com
```

## Connection Lifecycle

The client separates opening the WebSocket from authenticating:

```perl
$client->connect_ws or die "WebSocket connect failed\n";
$client->authenticate;   # runs the signalwire.connect handshake
$client->run;            # blocking read loop
```

`connect` is a convenience that performs `connect_ws` plus `authenticate`
in one call (and dies on failure):

```perl
$client->connect;        # connect_ws + authenticate
$client->run;
```

When you are done, tear down the transport with `disconnect`.

## Contexts

Contexts are topics your client subscribes to for receiving inbound calls.
When a call arrives on a context you're subscribed to, the handler you
registered with `on_call` is invoked.

```perl
# Subscribe at connect time
my $client = SignalWire::Relay::Client->new(
    project  => $ENV{SIGNALWIRE_PROJECT_ID},
    token    => $ENV{SIGNALWIRE_API_TOKEN},
    host     => $ENV{SIGNALWIRE_SPACE},
    contexts => ['sales', 'support'],
);

# Or dynamically after connecting
$client->receive(['billing']);
$client->unreceive(['sales']);
```

Both `receive` and `unreceive` accept an arrayref of context names.

## Making Outbound Calls

Use `dial` to place an outbound call. It takes named options and blocks
until the remote party answers, returning a live `SignalWire::Relay::Call`:

```perl
my $call = $client->dial(
    devices => [
        [ { type => 'phone', params => {
            to_number   => '+15551234567',
            from_number => '+15559876543',
        } } ],
    ],
);

my $action = $call->play(
    media => [ { type => 'tts', params => { text => 'This is an outbound call.' } } ],
);
$action->wait;
$call->hangup;
```

The `devices` structure is a nested list: the outer list represents serial
attempts; each inner list represents parallel attempts. To try two numbers
simultaneously:

```perl
my $call = $client->dial(
    devices => [
        [
            { type => 'phone', params => { to_number => '+15551111111', from_number => '+15559876543' } },
            { type => 'phone', params => { to_number => '+15552222222', from_number => '+15559876543' } },
        ],
    ],
    timeout => 30,
);
```

`dial` also accepts an optional `tag` (auto-generated if omitted) and a
`timeout` in seconds (default 120).

## Next Steps

- [Call Methods Reference](call-methods.md) — methods available on a Call object
- [Events](events.md) — handling real-time call events
- [Client Reference](client-reference.md) — Client configuration and methods
- [Messaging](messaging.md) — sending and receiving SMS/MMS
