# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Perl port of the SignalWire AI Agents SDK -- a framework for building, deploying, and managing AI agents as microservices. The SDK provides tools for creating self-contained web applications that expose HTTP endpoints to interact with the SignalWire platform.

The Perl SDK uses Moo for object orientation, Plack/PSGI for HTTP serving, and JSON for serialization. It mirrors the Python SDK's architecture with Perl-idiomatic conventions.

## Development Commands

### Testing
```bash
# Run all tests
PERL5LIB="lib:t/lib" prove -r t/

# Run specific test files
PERL5LIB="lib" prove t/unit/core/agent_base.t

# Run with verbose output
PERL5LIB="lib" prove -v t/

# Syntax check a single file
PERL5LIB="/home/devuser/perl5/lib/perl5" perl -Ilib -c lib/SignalWire/Agents/Agent/AgentBase.pm

# Syntax check an example
PERL5LIB="/home/devuser/perl5/lib/perl5" perl -Ilib -c examples/simple_agent.pl
```

### Installation and Setup
```bash
# Install dependencies via cpanfile
cpanm --installdeps .

# Or install individual deps
cpanm Moo JSON Plack HTTP::Tiny MIME::Base64 Digest::SHA IO::Socket::SSL Protocol::WebSocket
```

### Environment
```bash
# Always use this when running Perl commands in this repo
export PERL5LIB="/home/devuser/perl5/lib/perl5"

# Or prefix commands
PERL5LIB="/home/devuser/perl5/lib/perl5" perl -Ilib script.pl
```

## Architecture Overview

### Core Components
1. **AgentBase** (`lib/SignalWire/Agents/Agent/AgentBase.pm`) -- Base class for all AI agents (Moo-based)
2. **SWML::Service** (`lib/SignalWire/Agents/SWML/Service.pm`) -- Foundation for SWML document management
3. **AgentServer** (`lib/SignalWire/Agents/Server/AgentServer.pm`) -- Multi-agent hosting server
4. **Skills System** (`lib/SignalWire/Agents/Skills/`) -- Modular capabilities framework
5. **Contexts** (`lib/SignalWire/Agents/Contexts/ContextBuilder.pm`) -- Structured workflow management
6. **DataMap** (`lib/SignalWire/Agents/DataMap.pm`) -- Server-side API integration without webhooks
7. **Relay Client** (`lib/SignalWire/Agents/Relay/`) -- Real-time WebSocket call control
8. **REST Client** (`lib/SignalWire/Agents/REST/`) -- Synchronous HTTP API client

### Key Patterns

#### Agent Creation
Agents use Moo `extends` from `AgentBase` and configure in BUILD:
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agents::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;
    $self->prompt_add_section('Role', 'You are a helpful assistant.');
    $self->define_tool(
        name        => 'get_time',
        description => 'Get the current time',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ($args, $raw) = @_;
            require SignalWire::Agents::SWAIG::FunctionResult;
            return SignalWire::Agents::SWAIG::FunctionResult->new("The time is " . localtime);
        },
    );
}
```

#### Tool Definition
Tools use `define_tool()` with anonymous sub handlers:
```perl
$self->define_tool(
    name        => 'tool_name',
    description => 'What the tool does',
    parameters  => {
        type       => 'object',
        properties => {
            param1 => { type => 'string', description => 'A parameter' },
        },
        required => ['param1'],
    },
    handler => sub {
        my ($args, $raw_data) = @_;
        return SignalWire::Agents::SWAIG::FunctionResult->new("Result: $args->{param1}");
    },
);
```

#### FunctionResult
```perl
use SignalWire::Agents::SWAIG::FunctionResult;

# Simple response
my $result = SignalWire::Agents::SWAIG::FunctionResult->new("Response text");

# With actions
$result->add_action('set_global_data', { key => 'value' });
$result->hangup;
$result->connect('+15551234567');
```

#### DataMap Tools
```perl
use SignalWire::Agents::DataMap;

my $tool = SignalWire::Agents::DataMap->new('get_weather')
    ->description('Get weather for a location')
    ->parameter('city', 'string', 'City name', required => 1)
    ->webhook('GET', 'https://api.weather.com/v1?q=${args.city}')
    ->output(SignalWire::Agents::SWAIG::FunctionResult->new('Weather: ${response.temp}'));

$agent->register_swaig_function($tool->to_swaig_function);
```

#### Contexts
```perl
my $ctx = $self->define_contexts;
$ctx->add_context('sales', prompt => 'You are a sales agent.');
```

#### Skills
```perl
$agent->add_skill('datetime');
$agent->add_skill('math');
$agent->add_skill('web_search', {
    api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
    search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
});
```

#### RELAY Client
```perl
use SignalWire::Agents::Relay::Client;

my $client = SignalWire::Agents::Relay::Client->new(
    project  => $ENV{SIGNALWIRE_PROJECT_ID},
    token    => $ENV{SIGNALWIRE_API_TOKEN},
    host     => $ENV{SIGNALWIRE_SPACE} // 'relay.signalwire.com',
    contexts => ['default'],
);

$client->on_call(sub {
    my ($call) = @_;
    $call->answer;
    $call->play(media => [{ type => 'tts', params => { text => 'Hello!' } }]);
    $call->hangup;
});

$client->connect_ws;
$client->authenticate;
$client->run;
```

#### REST Client
```perl
use SignalWire::Agents::REST::SignalWireClient;

my $client = SignalWire::Agents::REST::SignalWireClient->new(
    project => $ENV{SIGNALWIRE_PROJECT_ID},
    token   => $ENV{SIGNALWIRE_API_TOKEN},
    host    => $ENV{SIGNALWIRE_SPACE},
);

# Namespaced access
my $numbers = $client->phone_numbers->list;
my $agent   = $client->fabric->ai_agents->create(name => 'Bot', prompt => { text => '...' });
```

### Testing Architecture
- **Tests** in `t/` organized by component
- **Test runner**: `prove` with PERL5LIB set to include `lib`
- **Syntax checks**: `perl -Ilib -c file.pm` for modules, `perl -Ilib -c file.pl` for scripts

### Deployment Patterns
- **Local development**: `$agent->run()` starts a Plack HTTP server
- **Multi-agent servers**: Use `AgentServer` class with `register()`
- **PSGI**: `$agent->psgi_app` returns a PSGI coderef for any Plack handler

## Important Implementation Notes

### Perl-Specific Conventions
- All classes use `Moo` (not Moose) for lightweight OO
- Attributes use `has` with `is => 'rw'` or `is => 'ro'`
- JSON encoding/decoding via `JSON` module (uses `JSON::XS` when available)
- Error handling with `die`/`eval` (not exceptions framework)
- Hash refs for configuration, array refs for lists
- Anonymous subs for callbacks and handlers
- Method chaining: most setters return `$self`

### Module Loading
- `use lib 'lib'` in scripts to find SDK modules
- `use SignalWire::Agents` loads core modules
- Relay and REST clients loaded separately as needed

### Security
- Basic auth auto-generated unless `SWML_BASIC_AUTH_USER`/`SWML_BASIC_AUTH_PASSWORD` set
- Timing-safe string comparison for auth
- Session management via `SessionManager`

## File Locations
- Core: `lib/SignalWire/Agents/` (Agent, SWML, SWAIG, DataMap, Contexts, etc.)
- Skills: `lib/SignalWire/Agents/Skills/Builtin/` (datetime, math, web_search, etc.)
- Prefabs: `lib/SignalWire/Agents/Prefabs/` (InfoGatherer, Survey, Receptionist, etc.)
- Relay: `lib/SignalWire/Agents/Relay/` (Client, Call, Action, Event, etc.)
- REST: `lib/SignalWire/Agents/REST/` (SignalWireClient, HttpClient, Namespaces/)
- Examples: `examples/` (agent examples)
- Relay examples: `relay/examples/` (RELAY client examples)
- REST examples: `rest/examples/` (REST client examples)
- Docs: `docs/` (architecture, guides, references)
- Tests: `t/` (unit tests)
