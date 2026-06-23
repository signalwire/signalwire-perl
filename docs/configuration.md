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

```perl
use lib 'lib';
use SignalWire::Agent::AgentBase;

# Works with defaults: name 'agent', port 3000, auto-generated basic auth
my $agent = SignalWire::Agent::AgentBase->new;
$agent->run;
```

### With Explicit Settings

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

Otherwise the `SWML_SSL_*` environment variables are consulted. TLS is enabled only
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
   proxy and set `SWML_PROXY_URL_BASE`, or serve HTTPS directly via `SWML_SSL_*`.

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
