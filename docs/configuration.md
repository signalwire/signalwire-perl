# Configuration Guide

This guide explains how SignalWire AI Agents (SWML-based services) are configured
in the Perl SDK. Configuration comes from two sources: constructor parameters and
environment variables. An agent works with zero configuration, using sensible
defaults.

## Overview

SWML (SignalWire Markup Language) is the JSON document format that defines agent
behavior during calls. Agents are configured through their Moo constructor
parameters and a small set of environment variables. There is no separate JSON
configuration-file loader in the Perl SDK; everything is set either in code or via
the environment.

## Quick Start

### Zero Configuration (Default)

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
use lib 'lib';
use SignalWire::Agent::AgentBase;

# Works with defaults: name 'agent', port 3000, auto-generated basic auth
my $agent = SignalWire::Agent::AgentBase->new;
$agent->run;
```

### With Explicit Settings

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
my $agent = SignalWire::Agent::AgentBase->new(
    name  => 'my-agent',
    route => '/agent',
    host  => '0.0.0.0',
    port  => 8080,
);
$agent->run;
```

You can also override host and port at serve time:

```perl
$agent->run(host => '127.0.0.1', port => 3001);
```

## Constructor Parameters

Common parameters accepted by `SignalWire::Agent::AgentBase->new`:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `name` | `'agent'` | Agent name |
| `route` | `/` | HTTP route the agent is served on |
| `host` | `0.0.0.0` | Bind host |
| `port` | `$PORT` env or `3000` | Bind port |
| `basic_auth_user` | auto-generated | HTTP basic auth username |
| `basic_auth_password` | auto-generated | HTTP basic auth password |

Most behavior (prompt, languages, skills, params, contexts) is configured by
calling methods on the agent after construction, not by constructor arguments.

## Environment Variables

The Perl SDK reads the following environment variables (the same `SWML_*` names
used across the SDK family):

### Authentication

- `SWML_BASIC_AUTH_USER` - HTTP basic auth username (otherwise auto-generated)
- `SWML_BASIC_AUTH_PASSWORD` - HTTP basic auth password (otherwise auto-generated)

### Networking

- `SWML_HOST` - Default bind host for SWML services
- `SWML_PORT` - Default bind port for SWML services
- `PORT` - Fallback port for `AgentBase` when not otherwise set
- `SWML_PROXY_URL_BASE` - Public base URL when the agent is behind a reverse proxy
  (used to build webhook URLs)

### TLS / SSL

- `SWML_SSL_ENABLED` - Enable HTTPS when truthy (`true`, `1`, or `yes`)
- `SWML_SSL_CERT_PATH` - Path to the TLS certificate
- `SWML_SSL_KEY_PATH` - Path to the TLS private key

When `SWML_SSL_ENABLED` is truthy and both cert and key paths resolve, the agent
serves HTTPS directly.

### Request Signing

- `SIGNALWIRE_SIGNING_KEY` - Key used to validate signed SWAIG tool-token requests

### RELAY connection timings (read by `SignalWire::Relay::Client`)

Advanced/testing knobs for the RELAY WebSocket client. Each defaults to the
production value; **leave them unset in production.** They exist so a half-open,
black-hole, or reconnect scenario can be driven inside a bounded test window —
the analog of the Python reference's monkeypatchable `_EXECUTE_TIMEOUT` /
`RECONNECT_MIN_DELAY` module constants.

- `SIGNALWIRE_RELAY_REQUEST_TIMEOUT_MS` - Timeout in milliseconds for a single
  RELAY request/response round-trip before it raises a `RelayError`
  (default 30000 = 30s). This is what bounds detection of a half-open peer.
- `SIGNALWIRE_RELAY_RECONNECT_MIN_DELAY_S` - Minimum backoff delay in seconds
  before the first reconnect attempt after a disconnect (default 1). Each
  subsequent attempt doubles it.
- `SIGNALWIRE_RELAY_RECONNECT_MAX_DELAY_S` - Maximum delay in seconds that the
  exponential reconnect backoff caps at (default 30).

### Schema validation

- `SWML_SKIP_SCHEMA_VALIDATION` - When truthy (`1`, `true`, or `yes`), skips the
  SWML document schema-validation step. This is a **security/debugging toggle**:
  validation normally rejects malformed SWML before it reaches the platform, so
  disabling it removes that guard. Leave it unset in production; set it only when
  intentionally bypassing validation (e.g. testing a document the schema does not
  yet cover).

### Web-service security (read by `SignalWire::Core::SecurityConfig`)

These knobs harden the built-in HTTP server. Each is secure by default; set the
env var to override.

- `SWML_DOMAIN` - Public domain name for the service (used in generated URLs / TLS).
- `SWML_ALLOWED_HOSTS` - Comma-separated allow-list of `Host` headers the server
  accepts (default `*`). Narrow this in production to block Host-header spoofing.
- `SWML_CORS_ORIGINS` - Comma-separated allow-list of CORS origins (default `*`).
- `SWML_SSL_VERIFY_MODE` - Peer-certificate verification mode (default
  `CERT_REQUIRED`).
- `SWML_MAX_REQUEST_SIZE` - Maximum accepted request body size in bytes
  (default 10485760 = 10 MiB).
- `SWML_RATE_LIMIT` - Maximum requests per minute per client (default 60).
- `SWML_REQUEST_TIMEOUT` - Per-request timeout in seconds (default 30).
- `SWML_USE_HSTS` - Emit an HTTP Strict-Transport-Security header when truthy
  (default enabled).
- `SWML_HSTS_MAX_AGE` - HSTS `max-age` in seconds (default 31536000 = 1 year).

## TLS / HTTPS

There are two ways to serve HTTPS:

### 1. Explicit serve options

Passing both `ssl_cert` and `ssl_key` to `run`/`serve` always enables TLS:

```perl
$agent->run(
    host     => '0.0.0.0',
    port     => 443,
    ssl_cert => '/etc/ssl/cert.pem',
    ssl_key  => '/etc/ssl/key.pem',
);
```

### 2. Environment variables

Otherwise the SSL/TLS environment variables are consulted. TLS is enabled only
when `SWML_SSL_ENABLED` is truthy AND both `SWML_SSL_CERT_PATH` and
`SWML_SSL_KEY_PATH` resolve:

```bash
export SWML_SSL_ENABLED=true
export SWML_SSL_CERT_PATH=/etc/ssl/cert.pem
export SWML_SSL_KEY_PATH=/etc/ssl/key.pem
PERL5LIB="lib" perl my_agent.pl
```

## Reverse Proxy

When the agent runs behind a reverse proxy (the proxy terminates TLS and forwards
to the agent over plain HTTP), set `SWML_PROXY_URL_BASE` to the public base URL so
generated webhook URLs point at the proxy:

```bash
export SWML_PROXY_URL_BASE=https://agent.example.com
```

## Best Practices

1. **Keep secrets in environment variables** - Set `SWML_BASIC_AUTH_PASSWORD` and
   `SIGNALWIRE_SIGNING_KEY` from the environment rather than hard-coding them.

2. **Use defaults for development** - An agent runs with no configuration on port
   3000 with auto-generated basic auth credentials (printed when the agent starts).

3. **Terminate TLS at a proxy in production** - Run the agent over HTTP behind a
   proxy and set `SWML_PROXY_URL_BASE`, or serve HTTPS directly via `SWML_SSL_ENABLED`
   plus `SWML_SSL_CERT_PATH` / `SWML_SSL_KEY_PATH`.

## Troubleshooting

### Authentication Issues

1. If you did not set `SWML_BASIC_AUTH_USER`/`SWML_BASIC_AUTH_PASSWORD` (or the
   constructor parameters), credentials are auto-generated and printed at startup.
2. Confirm the credentials the client sends match what the agent expects.

### TLS Not Engaging

1. Confirm `SWML_SSL_ENABLED` is set to `true`, `1`, or `yes`.
2. Confirm both `SWML_SSL_CERT_PATH` and `SWML_SSL_KEY_PATH` point at readable
   files.
3. Remember that explicit `ssl_cert`/`ssl_key` serve options override the
   environment and always enable TLS.

For more on authentication and signing, see the [Security Guide](security.md).
