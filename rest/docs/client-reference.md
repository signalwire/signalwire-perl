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

REST methods `die` on any non-2xx HTTP response. Trap errors with `eval`:

```perl
my $agent = eval { $client->fabric->ai_agents->get('bad-id') };
if (my $err = $@) {
    warn "Request failed: $err";
}
```

## Session Behavior

- A single HTTP client is shared across all namespaces for connection reuse.
- Content-Type is `application/json`.
- DELETE requests returning 204 return an empty hashref.
