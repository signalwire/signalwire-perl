# Security Configuration Guide

This guide covers the security features available in the Perl SignalWire AI Agents
SDK for SWML-based services (SWML -- SignalWire Markup Language -- is the JSON
document format that defines agent behavior during calls).

## Overview

Security is controlled through environment variables and constructor parameters,
with secure defaults: HTTP basic auth is enabled by default with auto-generated
credentials, webhook signatures are validated when a signing key is configured,
and outbound URLs are validated against private/internal addresses.

## Quick Start

### Basic HTTPS Setup

To serve HTTPS directly:

```bash
export SWML_SSL_ENABLED=true
export SWML_SSL_CERT_PATH=/path/to/cert.pem
export SWML_SSL_KEY_PATH=/path/to/key.pem
```

### Basic Authentication

Basic authentication is enabled by default with auto-generated credentials. To set
custom credentials:

```bash
export SWML_BASIC_AUTH_USER=myusername
export SWML_BASIC_AUTH_PASSWORD=mysecurepassword
```

## Environment Variables

### SSL/TLS Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SWML_SSL_ENABLED` | `false` | Enable HTTPS (`true`, `1`, `yes` to enable) |
| `SWML_SSL_CERT_PATH` | - | Path to the SSL certificate file |
| `SWML_SSL_KEY_PATH` | - | Path to the SSL private key file |

HTTPS is served directly only when `SWML_SSL_ENABLED` is truthy AND both cert and
key paths resolve. Alternatively, passing `ssl_cert` and `ssl_key` to
`run`/`serve` always enables TLS.

### Authentication

| Variable | Default | Description |
|----------|---------|-------------|
| `SWML_BASIC_AUTH_USER` | auto-generated | Basic auth username |
| `SWML_BASIC_AUTH_PASSWORD` | auto-generated | Basic auth password |

When not set, both the username and password are auto-generated and printed at
startup.

### Webhook Signature Validation

| Variable | Default | Description |
|----------|---------|-------------|
| `SIGNALWIRE_SIGNING_KEY` | - | Key used to validate incoming webhook signatures |

### Outbound URL Validation (SSRF Protection)

| Variable | Default | Description |
|----------|---------|-------------|
| `SWML_ALLOW_PRIVATE_URLS` | `false` | When truthy (`1`, `true`, `yes`), allow outbound requests to private/internal addresses |

### Reverse Proxy

| Variable | Default | Description |
|----------|---------|-------------|
| `SWML_PROXY_URL_BASE` | - | Public base URL when the agent is behind a reverse proxy (used for webhook URL generation) |

## Service Usage

SWML-based agents pick up the security configuration automatically:

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
use lib 'lib';
use SignalWire::Agent::AgentBase;

my $agent = SignalWire::Agent::AgentBase->new(
    name  => 'secure-agent',
    route => '/agent',
);

# Serves HTTPS if SWML_SSL_ENABLED=true (and cert/key resolve),
# or pass ssl_cert/ssl_key explicitly.
$agent->run;
```

Serving HTTPS with explicit certificate paths:

```perl
$agent->run(
    host     => '0.0.0.0',
    port     => 443,
    ssl_cert => '/etc/ssl/certs/server.crt',
    ssl_key  => '/etc/ssl/private/server.key',
);
```

## Basic Authentication

Credentials are compared using a timing-safe comparison (HMAC-based) to mitigate
timing attacks. You can read the active credentials from the agent:

```perl
my $user = $agent->basic_auth_user;
my $pass = $agent->basic_auth_password;
```

## Webhook Signature Validation

When `SIGNALWIRE_SIGNING_KEY` is set (or a `signing_key` is passed to the agent),
incoming webhook requests are validated against the `X-SignalWire-Signature`
header (with `X-Twilio-Signature` accepted as a fallback). Requests with an
invalid signature are rejected.

## SWAIG Tool Tokens

The agent can issue and validate short-lived signed tokens for individual SWAIG
tools, requiring a configured `signing_key` (or `SIGNALWIRE_SIGNING_KEY`):

```perl
# Issue a token for a tool
my $token = $agent->create_tool_token('get_time', $call_id);

# Validate it later
my $ok = $agent->validate_tool_token('get_time', $token, $call_id);
```

## SSRF Protection

Outbound URLs (for example webhook destinations) are validated against
private/internal address ranges. By default, requests to private addresses are
rejected. Set `SWML_ALLOW_PRIVATE_URLS=true` to allow them (useful for local
development or internal-only deployments).

## Best Practices

### 1. Production HTTPS Setup

For production, serve HTTPS with valid certificates or terminate TLS at a reverse
proxy and set `SWML_PROXY_URL_BASE`:

```bash
export SWML_SSL_ENABLED=true
export SWML_SSL_CERT_PATH=/etc/ssl/certs/server.crt
export SWML_SSL_KEY_PATH=/etc/ssl/private/server.key
```

### 2. Strong Authentication

Always set strong credentials in production:

```bash
export SWML_BASIC_AUTH_USER=api_user
export SWML_BASIC_AUTH_PASSWORD=$(openssl rand -base64 32)
```

### 3. Webhook Signing

Set `SIGNALWIRE_SIGNING_KEY` so incoming webhooks are signature-verified, and so
SWAIG tool tokens can be issued and validated.

### 4. Certificate Management

- Use certificates from a trusted CA in production.
- For development, generate a self-signed certificate:

```bash
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes
```

## Troubleshooting

### SSL Certificate Issues

1. Check the file paths exist and are readable:
   ```bash
   ls -la "$SWML_SSL_CERT_PATH" "$SWML_SSL_KEY_PATH"
   ```

2. Verify certificate validity:
   ```bash
   openssl x509 -in "$SWML_SSL_CERT_PATH" -text -noout
   ```

3. Confirm the key and certificate match:
   ```bash
   openssl x509 -noout -modulus -in "$SWML_SSL_CERT_PATH" | openssl md5
   openssl rsa  -noout -modulus -in "$SWML_SSL_KEY_PATH"  | openssl md5
   ```

### Authentication Issues

1. If you did not set custom credentials, look for the auto-generated values in the
   startup output.
2. Test with curl:
   ```bash
   curl -u username:password http://localhost:3000/
   ```

### Outbound Request Blocked

If a webhook or outbound request to an internal host is being rejected, allow
private URLs explicitly (only when you trust the destinations):

```bash
export SWML_ALLOW_PRIVATE_URLS=true
```

## Security Checklist

Before deploying to production:

- [ ] HTTPS enabled with valid certificates (or TLS terminated at a trusted proxy)
- [ ] Strong basic auth credentials set
- [ ] `SIGNALWIRE_SIGNING_KEY` configured for webhook signature validation
- [ ] `SWML_ALLOW_PRIVATE_URLS` left disabled unless internal destinations are required
- [ ] SSL certificate expiration monitored

For environment-variable and constructor configuration details, see the
[Configuration Guide](configuration.md).
