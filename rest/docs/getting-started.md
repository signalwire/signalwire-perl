# Getting Started with the REST Client

The REST client provides synchronous access to all SignalWire APIs using standard HTTP requests. No WebSocket connection required.

## Installation

The REST client ships with the SignalWire Perl SDK. Install it and its dependencies with `cpanm`:

```bash
cpanm --installdeps .
```

The SDK requires Perl 5.36 or newer. If you are not using a `cpanfile`, the REST client's runtime dependencies are `Moo`, `JSON`, and `HTTP::Tiny`:

```bash
cpanm Moo JSON HTTP::Tiny
```

## Configuration

You need three things to connect:

| Parameter | Env Var | Description |
|-----------|---------|-------------|
| `project` | `SIGNALWIRE_PROJECT_ID` | Your SignalWire project ID |
| `token`   | `SIGNALWIRE_API_TOKEN`  | Your SignalWire API token |
| `host`    | `SIGNALWIRE_SPACE`      | Your space hostname (e.g. `example.signalwire.com`) |

## Minimal Example

```perl
use strict;
use warnings;
use SignalWire::REST::RestClient;

my $client = SignalWire::REST::RestClient->new(
    project => 'your-project-id',
    token   => 'your-api-token',
    host    => 'example.signalwire.com',
);

# List your AI agents
my $agents = $client->fabric->ai_agents->list;
use Data::Dumper;
print Dumper($agents);
```

Pull the credentials from the environment so they stay out of your source:

```bash
export SIGNALWIRE_PROJECT_ID=your-project-id
export SIGNALWIRE_API_TOKEN=your-api-token
export SIGNALWIRE_SPACE=example.signalwire.com
```

```perl
use SignalWire::REST::RestClient;

my $client = SignalWire::REST::RestClient->new(
    project => $ENV{SIGNALWIRE_PROJECT_ID},
    token   => $ENV{SIGNALWIRE_API_TOKEN},
    host    => $ENV{SIGNALWIRE_SPACE},
);

my $agents = $client->fabric->ai_agents->list;
```

All three constructor arguments are required; the client dies at construction if any are missing.

## CRUD Pattern

Most resources follow the same CRUD pattern:

```perl
# List
my $items = $client->fabric->ai_agents->list;

# Create (named arguments)
my $agent = $client->fabric->ai_agents->create(
    name   => 'Support',
    prompt => { text => 'Be helpful' },
);

# Get by ID
$agent = $client->fabric->ai_agents->get('agent-uuid');

# Update
$client->fabric->ai_agents->update('agent-uuid', name => 'Updated Name');

# Delete
$client->fabric->ai_agents->delete('agent-uuid');
```

Fabric resources also support listing addresses:

```perl
my $addresses = $client->fabric->ai_agents->list_addresses('agent-uuid');
```

## Error Handling

Methods `die` on any non-2xx HTTP response. Wrap calls in `eval` to trap the error:

```perl
my $agent = eval { $client->fabric->ai_agents->get('nonexistent-id') };
if (my $err = $@) {
    warn "Request failed: $err";
}
```

## Next Steps

- [Client Reference](client-reference.md) -- all namespaces and constructor options
- [Fabric Resources](fabric.md) -- managing AI agents, SWML scripts, and more
- [Calling Commands](calling.md) -- REST-based call control
- [All Namespaces](namespaces.md) -- phone numbers, video, datasphere, and more
