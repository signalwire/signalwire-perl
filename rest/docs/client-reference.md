# RestClient Reference

## Constructor

```perl
use SignalWire::REST::RestClient;
my $client = SignalWire::REST::RestClient->new(
    project => $ENV{SIGNALWIRE_PROJECT_ID},   # required
    token   => $ENV{SIGNALWIRE_API_TOKEN},    # required
    host    => $ENV{SIGNALWIRE_SPACE},        # required, e.g. example.signalwire.com
);
```

All three parameters are required; the client dies at construction if any are missing.

Authentication uses HTTP Basic Auth (`project:token`).

## Namespaces

There are 21 namespace accessors on the client. Every API surface is available as a lazily-built accessor:

### Fabric API

| Accessor | Description |
|----------|-------------|
| `$client->fabric->swml_scripts` | SWML script resources (CRUD + addresses) |
| `$client->fabric->swml_webhooks` | SWML webhook resources |
| `$client->fabric->ai_agents` | AI agent resources |
| `$client->fabric->relay_applications` | Relay application resources |
| `$client->fabric->call_flows` | Call flow resources (+ versions) |
| `$client->fabric->conference_rooms` | Conference room resources |
| `$client->fabric->freeswitch_connectors` | FreeSWITCH connector resources |
| `$client->fabric->subscribers` | Subscriber resources (+ SIP endpoints) |
| `$client->fabric->sip_endpoints` | SIP endpoint resources |
| `$client->fabric->sip_gateways` | SIP gateway resources |
| `$client->fabric->cxml_scripts` | cXML script resources |
| `$client->fabric->cxml_webhooks` | cXML webhook resources |
| `$client->fabric->cxml_applications` | cXML application resources (no create) |
| `$client->fabric->resources` | Generic resource operations |
| `$client->fabric->addresses` | Fabric addresses (list/get only) |
| `$client->fabric->tokens` | Subscriber/guest/invite/embed token creation |

(16 Fabric sub-resources.)

### Calling API

| Accessor | Description |
|----------|-------------|
| `$client->calling` | REST call control -- 38 commands via POST |

### Relay REST Resources

| Accessor | Description |
|----------|-------------|
| `$client->phone_numbers` | Phone number management (+ search, typed binding helpers) |
| `$client->addresses` | Address management |
| `$client->queues` | Queue management (+ members) |
| `$client->recordings` | Recording management |
| `$client->number_groups` | Number group management (+ memberships) |
| `$client->verified_callers` | Verified caller ID management (+ verification flow) |
| `$client->sip_profile` | Project SIP profile (get/update) |
| `$client->lookup` | Phone number lookup |
| `$client->short_codes` | Short code management |
| `$client->imported_numbers` | Import external phone numbers |
| `$client->mfa` | Multi-factor authentication (SMS/call/verify) |
| `$client->registry` | 10DLC brand/campaign registry |

### Other APIs

| Accessor | Description |
|----------|-------------|
| `$client->datasphere` | Datasphere document management and semantic search |
| `$client->video` | Video rooms, sessions, recordings, conferences |
| `$client->logs` | Message, voice, fax, and conference logs |
| `$client->project` | API token management |
| `$client->pubsub` | PubSub token creation |
| `$client->chat` | Chat token creation |

> Note: the project-token namespace is reached via `$client->project`. The
> `project` credential passed to the constructor is stored privately (as
> `_project_id`) so it does not collide with this generated `project` accessor.

## Error Handling

REST methods `die` with a **typed error object** on any failure. Trap it with `eval`
and inspect the object, or just stringify it for a human-readable message:

```perl
my $agent = eval { $client->fabric->ai_agents->get('bad-id') };
if (my $err = $@) {
    warn "Request failed: $err";   # stringifies to "GET <url> returned <code>: <body>"
}
```

### The typed error family

All REST failures are raised as one exception family, so a single `eval` catches
every kind of failure — HTTP-error responses and transport failures alike:

- **`SignalWireRestError`** — the base class, raised on any HTTP response with
  status `>= 400`. It carries the full failure envelope as read-only accessors:

  | Accessor        | Meaning                                                        |
  |-----------------|----------------------------------------------------------------|
  | `status_code`   | the HTTP status (`404`, `422`, `429`, `500`, …)                |
  | `body`          | the parsed JSON body (hashref) or the raw string if not JSON   |
  | `url`           | the request path                                               |
  | `method`        | the HTTP method (`GET`, `POST`, …)                             |

- **`SignalWireRestTransportError`** — a **subclass** of `SignalWireRestError`,
  raised when the request never reached a response at all (connection refused, DNS
  failure, connection reset, TLS error, read timeout, or a cancelled
  `abort_signal`). Its `status_code` is `undef` (no HTTP status ever arrived) and
  its `body` carries the underlying transport message. Because it is a subclass, an
  `eval` catching `SignalWireRestError` handles transport failures too.

- **`SignalWire::REST::HttpClient::Error`** — a back-compat alias for
  `SignalWireRestError` (the same class); older `isa` checks against this name keep
  working.

```perl
use Scalar::Util qw(blessed);

my $agent = eval { $client->fabric->ai_agents->get('bad-id') };
if (my $err = $@) {
    if ( blessed($err) && $err->isa('SignalWireRestError') ) {
        if ( $err->isa('SignalWireRestTransportError') ) {
            # Never reached the server (no status_code).
            warn "transport failure: " . $err->body;
        }
        elsif ( $err->status_code == 404 ) {
            warn "not found: " . $err->method . ' ' . $err->url;
        }
        else {
            warn "HTTP " . $err->status_code . ": " . encode_json( $err->body );
        }
    }
    else {
        die $err;   # not one of ours — re-raise
    }
}
```

Distinguishing the two lets a caller retry a transient transport failure while
surfacing a `422`/`404` to the user, all from one `eval`.

## Session Behavior

- A single HTTP client is shared across all namespaces for connection reuse.
- Content-Type is `application/json`.
- DELETE requests returning 204 return an empty hashref.
