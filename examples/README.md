# SignalWire AI Agents SDK (Perl) - Examples

This directory contains working examples demonstrating the features of the SignalWire AI Agents SDK for Perl.

## Setup

```bash
# Install dependencies via cpanfile (from the repository root)
cpanm --installdeps .

# Or install core dependencies manually
cpanm Moo JSON Plack HTTP::Tiny MIME::Base64 Digest::SHA
```

## Running Examples

```bash
# Run any example directly
PERL5LIB="/home/devuser/perl5/lib/perl5" perl -Ilib examples/simple_agent.pl

# Check syntax without running
PERL5LIB="/home/devuser/perl5/lib/perl5" perl -Ilib -c examples/simple_agent.pl
```

## Examples by Category

### Getting Started

| File | Description |
|------|-------------|
| [simple_agent.pl](simple_agent.pl) | Full-featured agent with POM prompts, SWAIG tools, multilingual support, and LLM parameter tuning |
| [simple_dynamic_agent.pl](simple_dynamic_agent.pl) | Agent with per-request dynamic configuration callback |
| [multi_agent_server.pl](multi_agent_server.pl) | Multiple agents on one server: healthcare, finance, retail |

### Contexts and Steps

| File | Description |
|------|-------------|
| [contexts_demo.pl](contexts_demo.pl) | Multi-persona workflow with context switching and step navigation |

### DataMap (Server-Side Tools)

| File | Description |
|------|-------------|
| [datamap_demo.pl](datamap_demo.pl) | DataMap builder API for creating tools that execute on SignalWire servers |

### Skills

| File | Description |
|------|-------------|
| [skills_demo.pl](skills_demo.pl) | Loading and configuring built-in skills (datetime, math, web_search) |

### Session and State

| File | Description |
|------|-------------|
| [session_state.pl](session_state.pl) | Session lifecycle: on_summary, global_data, tool result actions |
| [call_flow.pl](call_flow.pl) | Call flow verbs (pre/post-answer), debug events, transfer/SMS/hold actions |

### RELAY Client

| File | Description |
|------|-------------|
| [relay_demo.pl](relay_demo.pl) | RELAY client: answer inbound calls and play TTS over WebSocket |

### REST Client

| File | Description |
|------|-------------|
| [rest_demo.pl](rest_demo.pl) | REST client: list resources, search numbers, manage agents |

### Prefab Agents

| File | Description |
|------|-------------|
| [prefab_info_gatherer.pl](prefab_info_gatherer.pl) | InfoGatherer prefab for structured data collection |
| [prefab_survey.pl](prefab_survey.pl) | Survey prefab for conducting structured surveys |

## Authentication

Agents auto-generate credentials on startup. To set fixed credentials:

```bash
export SWML_BASIC_AUTH_USER=myuser
export SWML_BASIC_AUTH_PASSWORD=mypassword
perl -Ilib examples/simple_agent.pl
```

## Environment Variables

For RELAY and REST examples:

```bash
export SIGNALWIRE_PROJECT_ID=your-project-id
export SIGNALWIRE_API_TOKEN=your-api-token
export SIGNALWIRE_SPACE=example.signalwire.com
```
