# CLI Guide

This guide covers the command-line tool included with the Perl SignalWire Agents
SDK.

## Overview

The `swaig-test` CLI tool (in `bin/swaig-test`) tests SWAIG agent endpoints. SWAIG
(SignalWire AI Gateway) is the platform's AI tool-calling system; SWML (SignalWire
Markup Language) is the JSON document format that defines agent behavior during
calls. The tool can:

- **Dump SWML**: fetch and display the SWML document an agent generates
- **List tools**: list the SWAIG functions an agent exposes
- **Execute a tool**: invoke a SWAIG function by name with parameters

It works in two modes:

- **URL mode** (`--url`): make real HTTP requests to a running agent
- **File mode** (`--file`): load a Perl agent/service script in-process (no HTTP)
  and read its runtime tool registry

## Usage

```text
swaig-test - CLI tool for testing SWAIG agent endpoints

Usage:
  swaig-test --url URL   [OPTIONS]
  swaig-test --file PATH [OPTIONS]

Options:
  --url URL           Agent URL with embedded auth (http://user:pass@host:port/route)
  --file PATH         Path to a Perl script that builds an SWML::Service /
                      AgentBase instance. Loads the file in-process (no HTTP)
                      and reads the runtime tool registry.
  --dump-swml         Fetch and display the SWML document
  --list-tools        List available SWAIG functions
  --exec NAME         Execute a SWAIG function by name
  --param key=value   Parameter for --exec (repeatable)
  --raw               Output compact JSON (no pretty-printing)
  --verbose           Show request/response details on stderr
  --help, -h          Show this help message
```

`--url` and `--file` are mutually exclusive, and exactly one of `--dump-swml`,
`--list-tools`, or `--exec NAME` is required.

## URL Mode

URL mode makes real HTTP requests to a running agent. Embed the basic-auth
credentials in the URL.

```bash
# Dump the SWML document
swaig-test --url http://user:pass@localhost:3000/ --dump-swml

# List the agent's SWAIG functions
swaig-test --url http://user:pass@localhost:3000/ --list-tools

# Execute a function with a parameter
swaig-test --url http://user:pass@localhost:3000/ --exec get_weather --param location=London

# Compact JSON output (pipe to jq)
swaig-test --url http://user:pass@localhost:3000/ --dump-swml --raw | jq '.'
```

## File Mode

File mode loads a Perl agent or `SWML::Service` script in-process and reads its
runtime tool registry. No HTTP server is started.

```bash
# List tools defined by an agent script
swaig-test --file examples/swmlservice_swaig_standalone.pl --list-tools

# Execute a tool from the loaded script
swaig-test --file examples/swmlservice_swaig_standalone.pl --exec lookup_competitor --param competitor=ACME
```

File mode is useful for quickly checking which tools an agent registers and how
they behave before deploying the agent behind an HTTP server.

## Parameters

Pass function arguments to `--exec` with repeatable `--param key=value` options:

```bash
swaig-test --url http://user:pass@localhost:3000/ \
  --exec search_knowledge \
  --param query="SignalWire features" \
  --param count=3
```

## Output Control

- By default, JSON output is pretty-printed.
- `--raw` emits compact JSON suitable for piping to tools like `jq`.
- `--verbose` prints request/response details to stderr (stdout stays clean).

```bash
# Pretty SWML (default)
swaig-test --url http://user:pass@localhost:3000/ --dump-swml

# Raw JSON for automation
swaig-test --url http://user:pass@localhost:3000/ --dump-swml --raw | jq '.sections.main[].ai.SWAIG.functions'

# Verbose request/response tracing
swaig-test --url http://user:pass@localhost:3000/ --exec get_time --verbose
```

## Examples

```bash
# Inspect a running agent
swaig-test --url http://user:pass@localhost:3000/ --list-tools
swaig-test --url http://user:pass@localhost:3000/ --dump-swml

# Inspect an agent script without running it
swaig-test --file examples/simple_agent.pl --list-tools
swaig-test --file examples/datamap_demo.pl --list-tools

# Execute a tool over HTTP
swaig-test --url http://user:pass@localhost:3000/ --exec greet_user --param name=Alice
```

## Getting Help

```bash
swaig-test --help
```

## Related Documentation

- [SWAIG Reference](swaig_reference.md) - SWAIG functions and tool definitions
- [SWML Service Guide](swml_service_guide.md) - SWML document generation
- [Cloud Functions & Deployment Guide](cloud_functions_guide.md) - testing before deployment
