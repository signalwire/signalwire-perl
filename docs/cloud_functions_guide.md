# SignalWire AI Agents - Serverless & Cloud Deployment Guide

This guide covers deploying SignalWire AI Agents (Perl SDK) to serverless and
container platforms.

## Overview

A Perl agent is a standard PSGI application. `$agent->psgi_app` returns a PSGI
coderef that can be served by any Plack handler, wrapped by a PSGI-to-platform
adapter (AWS Lambda, etc.), or run directly with `$agent->run`. The SDK can detect
which environment it is running in so logging and behavior adapt automatically.

## Execution Mode Detection

The SDK exposes `SignalWire::Core::LoggingConfig::get_execution_mode`, which
inspects environment variables and returns one of `cgi`, `lambda`,
`google_cloud_function`, `azure_function`, or `server`. Precedence (first match
wins):

| Mode | Detected when these env vars are set |
|------|--------------------------------------|
| `cgi` | `GATEWAY_INTERFACE` |
| `lambda` | `AWS_LAMBDA_FUNCTION_NAME` or `LAMBDA_TASK_ROOT` |
| `google_cloud_function` | `FUNCTION_TARGET`, `K_SERVICE`, or `GOOGLE_CLOUD_PROJECT` |
| `azure_function` | `AZURE_FUNCTIONS_ENVIRONMENT`, `FUNCTIONS_WORKER_RUNTIME`, or `AzureWebJobsStorage` |
| `server` | none of the above (default) |

```perl
use SignalWire::Core::LoggingConfig qw(get_execution_mode);
my $mode = get_execution_mode();   # e.g. 'lambda' or 'server'
```

## AWS Lambda

An agent is configured identically to a normal server deployment; in Lambda you
bridge events to the PSGI app via a PSGI-to-Lambda adapter (for example
`AWS::Lambda::PSGI`).

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
use lib 'lib';
use SignalWire;
use SignalWire::Agent::AgentBase;
use SignalWire::SWAIG::FunctionResult;

my $agent = SignalWire::Agent::AgentBase->new(
    name  => 'lambda-agent',
    route => '/',
);

$agent->add_language(name => 'English', code => 'en-US', voice => 'inworld.Mark');
$agent->set_params({ ai_model => 'gpt-4.1-nano' });
$agent->prompt_add_section('Role', 'You are a helpful AI assistant running in AWS Lambda.');

$agent->define_tool(
    name        => 'greet_user',
    description => 'Greet a user by name',
    parameters  => {
        type       => 'object',
        properties => { name => { type => 'string', description => 'Name of the user' } },
    },
    handler => sub {
        my ($args, $raw) = @_;
        my $name = $args->{name} // 'friend';
        return SignalWire::SWAIG::FunctionResult->new("Hello $name!");
    },
);

# In a Lambda handler, wrap the PSGI app with a PSGI-to-Lambda adapter:
#   my $app = $agent->psgi_app;
#   # adapter bridges the Lambda event to $app
#
# For local testing, just run it normally:
$agent->run;
```

See `examples/lambda_agent.pl` for the complete example.

## Container / Kubernetes Deployment

For container platforms, run the agent's built-in HTTP server. The agent serves
unauthenticated `/health` and `/ready` endpoints suitable for liveness and
readiness probes, and reads `PORT` from the environment.

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
use lib 'lib';
use SignalWire;
use SignalWire::Agent::AgentBase;

my $port = $ENV{PORT} || 8080;

my $agent = SignalWire::Agent::AgentBase->new(
    name  => 'k8s-agent',
    route => '/',
    host  => '0.0.0.0',
    port  => $port,
);

$agent->add_language(name => 'English', code => 'en-US', voice => 'inworld.Mark');
$agent->run;
```

See `examples/kubernetes_ready_agent.pl` for the complete example.

## Authentication

Agents use HTTP Basic Authentication. Credentials are auto-generated if not set,
or you can supply them via constructor parameters or the
`SWML_BASIC_AUTH_USER` / `SWML_BASIC_AUTH_PASSWORD` environment variables (see the
[Security Guide](security.md)). The `/health` and `/ready` endpoints are exempt
from auth so platform probes succeed.

## Environment Variables

Set SignalWire credentials and agent configuration in your platform's environment:

```bash
# SignalWire credentials
export SIGNALWIRE_PROJECT_ID="your-project-id"
export SIGNALWIRE_API_TOKEN="your-token"

# Basic auth (optional; auto-generated if unset)
export SWML_BASIC_AUTH_USER="your-username"
export SWML_BASIC_AUTH_PASSWORD="your-password"

# Public base URL when behind a proxy / function gateway
export SWML_PROXY_URL_BASE="https://your-public-host"
```

When the agent is reachable at a public URL that differs from its bind address
(behind a function gateway or reverse proxy), set `SWML_PROXY_URL_BASE` so
generated webhook URLs are correct.

## Testing

Use the `swaig-test` CLI to exercise an agent locally before deployment (see the
[CLI Guide](cli_guide.md) for full usage):

```bash
# Dump the generated SWML for an agent file
bin/swaig-test --file examples/lambda_agent.pl --dump-swml

# List the agent's SWAIG tools
bin/swaig-test --file examples/lambda_agent.pl --list-tools

# Execute a tool with parameters
bin/swaig-test --file examples/lambda_agent.pl --exec greet_user --param name=Alice
```

You can also test a running agent over HTTP:

```bash
# Test without auth (should return 401)
curl http://localhost:3000/

# Test with valid auth
curl -u username:password http://localhost:3000/
```

## Best Practices

### Security
- Use HTTPS endpoints (terminate TLS at the platform gateway or serve directly; see the [Security Guide](security.md))
- Set strong basic auth credentials via environment variables
- Configure `SIGNALWIRE_SIGNING_KEY` for webhook signature validation

### Operations
- Use `/health` and `/ready` for liveness/readiness probes
- Set `SWML_PROXY_URL_BASE` when behind a gateway so webhook URLs resolve publicly
- Right-size memory and timeout settings for your workload

## Troubleshooting

### Check the Detected Mode

```perl
use SignalWire::Core::LoggingConfig qw(get_execution_mode);
print "Detected mode: ", get_execution_mode(), "\n";
```

### Check Generated URLs

```perl
use SignalWire::Agent::AgentBase;
my $agent = SignalWire::Agent::AgentBase->new(name => 'test');
print "Base URL: ", $agent->get_full_url, "\n";
print "Auth URL: ", $agent->get_full_url(include_auth => 1), "\n";
```

### Authentication Issues
- Verify the username/password match exactly (case-sensitive)
- Confirm the `Authorization` header is being sent
- If you did not set credentials, look for the auto-generated values printed at startup

## Examples

- `examples/lambda_agent.pl` - AWS Lambda / serverless deployment
- `examples/kubernetes_ready_agent.pl` - Kubernetes-ready agent with health/ready endpoints
