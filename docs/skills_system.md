# SignalWire Agents Skills System

The SignalWire Agents SDK includes a modular skills system that lets you add capabilities to your agents with simple one-liner calls and configurable parameters.

## What's New

Instead of manually implementing every agent capability, you can add a skill in one line:

```perl
use lib 'lib';
use SignalWire::Agent::AgentBase;

# Create an agent
my $agent = SignalWire::Agent::AgentBase->new(name => 'My Assistant');

# Add skills with one-liners
$agent->add_skill('web_search', {
    api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
    search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
});                              # Web search capability
$agent->add_skill('datetime');  # Current date/time info
$agent->add_skill('math');      # Mathematical calculations

# Add a skill with custom parameters
$agent->add_skill('web_search', {
    api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
    search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
    num_results      => 3,   # Get 3 search results instead of default
});

# Your agent now has all these capabilities automatically
```

## Architecture

The skills system consists of:

### Core Infrastructure
- **`SignalWire::Skills::SkillBase`** - Base class for all skills (Moo-based) with parameter support
- **`SignalWire::Skills::SkillManager`** - Handles loading/unloading and lifecycle management with parameters
- **`AgentBase->add_skill()`** - Simple method to add skills to agents with optional parameters

### Discovery & Registry
- **`SignalWire::Skills::SkillRegistry`** - Registers and looks up skills by name
- **Validation** - Checks required Perl packages and environment variables

### Built-in Skills
The SDK ships 18 built-in skills under `lib/SignalWire/Skills/Builtin/`:

`datetime`, `math`, `web_search`, `weather_api`, `wikipedia_search`, `joke`,
`google_maps`, `spider`, `native_vector_search`, `datasphere`,
`datasphere_serverless`, `play_background_file`, `swml_transfer`,
`api_ninjas_trivia`, `claude_skills`, `custom_skills`, `info_gatherer`,
`mcp_gateway`.

## Available Skills

### Web Search (`web_search`)
Search the web using the Google Custom Search API and return formatted snippets.

**Requirements:**
- A Google Custom Search API key and search engine ID (passed as parameters, or
  available via the `GOOGLE_API_KEY` environment variable as a fallback for `api_key`)

**Parameters:**
- `api_key` (required) - Google Custom Search API key
- `search_engine_id` (required) - Google Custom Search engine ID (alias: `cx`)
- `num_results` (default: 3, range 1-10) - Number of search results to retrieve
- `response_prefix` (default: "") - Text to prepend to responses
- `response_postfix` (default: "") - Text to append to responses
- `per_page_timeout` (default: 2.0) - Maximum seconds to wait on the HTTP fetch
- `overall_deadline` (default: 10.0) - Wall-clock budget in seconds for the whole tool call
- `tool_name` (default: "web_search") - Override the default tool name

This skill supports multiple instances (give each a distinct `tool_name`).

**Tools provided:**
- `web_search(query)` - Search and return formatted result snippets

**Usage examples:**
```perl
# Basic usage
$agent->add_skill('web_search', {
    api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
    search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
});

# More comprehensive results
$agent->add_skill('web_search', {
    api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
    search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
    num_results      => 5,
});
```

### Date/Time (`datetime`)
Get current date and time information.

**Requirements:** None

**Parameters:** None (no configurable parameters beyond the base)

**Usage example:**
```perl
$agent->add_skill('datetime');
```

### Math (`math`)
Perform basic mathematical calculations.

**Requirements:** None

**Parameters:** None (no configurable parameters beyond the base)

**Usage example:**
```perl
$agent->add_skill('math');
```

### Native Vector Search (`native_vector_search`)
Search a document index using vector similarity and keyword search, either
against a local knowledge base or a remote search server.

**Requirements:** None beyond the core SDK.

**Parameters:**
- `tool_name` (default: "search_knowledge") - Custom name for the search tool
- `description` - Override the tool description
- `remote_url` - URL of a remote search server
- `index_name` - Index name on the remote server
- `count` (default: 3) - Number of search results to return
- `hints` - Extra speech-recognition hints (arrayref)

This skill supports multiple instances (give each a distinct `tool_name`).

**Tools provided:**
- `search_knowledge(query, count)` - Search documents (tool name configurable)

**Usage examples:**
```perl
# Default local search
$agent->add_skill('native_vector_search', {
    tool_name => 'search_docs',
});

# Remote search server
$agent->add_skill('native_vector_search', {
    remote_url => 'http://localhost:8001',
    index_name => 'knowledge',
});

# Multiple instances for different collections
$agent->add_skill('native_vector_search', {
    tool_name => 'search_examples',
});
```

### SWML Transfer (`swml_transfer`)
Transfer calls between agents or destinations using regex pattern matching.

**Requirements:** None

**Parameters:**
- `tool_name` (default: "transfer_call") - Custom name for the transfer function
- `description` (default: "Transfer call based on pattern matching") - Tool description
- `parameter_name` (default: "transfer_type") - Name of the parameter for the transfer function
- `parameter_description` - Parameter description
- `transfers` (required) - Hashref mapping regex patterns to transfer configurations:
  - Pattern (key): regex pattern to match (e.g. `'/sales/i'`)
  - Configuration (value): a hashref with `url` (required), `message`,
    `return_message`, and `post_process`
- `default_message` - Message when no pattern matches

This skill supports multiple instances (give each a distinct `tool_name`).

**Tools provided:**
- `transfer_call(transfer_type)` (or custom `tool_name`) - Transfer based on pattern matching

**Usage examples:**
```perl
# Simple transfer between departments
$agent->add_skill('swml_transfer', {
    tool_name => 'transfer_to_department',
    transfers => {
        '/sales/i' => {
            url            => 'https://example.com/sales',
            message        => 'Transferring to sales...',
            return_message => 'Sales transfer complete.',
        },
        '/support/i' => {
            url            => 'https://example.com/support',
            message        => 'Transferring to support...',
            return_message => 'Support transfer complete.',
        },
    },
});

# Multiple instances for different transfer types
$agent->add_skill('swml_transfer', {
    tool_name      => 'route_call',
    parameter_name => 'department',
    transfers      => {
        '/sales|billing/i' => {
            url          => 'https://api.company.com/sales',
            message      => 'Connecting to sales team...',
            post_process => 1,
        },
        '/technical|support/i' => {
            url          => 'https://api.company.com/support',
            message      => 'Connecting to support team...',
            post_process => 1,
        },
    },
    default_message => 'Would you like sales or support?',
});
```

## Usage Examples

### Basic Usage
<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
use lib 'lib';
use SignalWire::Agent::AgentBase;

# Create agent and add skills
my $agent = SignalWire::Agent::AgentBase->new(
    name  => 'Assistant',
    route => '/assistant',
);
$agent->add_skill('datetime');
$agent->add_skill('math');
$agent->add_skill('web_search', {
    api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
    search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
});

# Start the agent
$agent->run;
```

### Skills with Custom Parameters
<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
use lib 'lib';
use SignalWire::Agent::AgentBase;

# Create agent
my $agent = SignalWire::Agent::AgentBase->new(
    name  => 'Research Assistant',
    route => '/research',
);

# Add web search optimized for research (more results)
$agent->add_skill('web_search', {
    api_key          => $ENV{GOOGLE_SEARCH_API_KEY},
    search_engine_id => $ENV{GOOGLE_SEARCH_ENGINE_ID},
    num_results      => 5,
});

# Add other skills without parameters
$agent->add_skill('datetime');
$agent->add_skill('math');

# Start the agent
$agent->run;
```

### Runtime Skill Management
```perl
use SignalWire::Agent::AgentBase;
my $agent = SignalWire::Agent::AgentBase->new(name => 'Dynamic Agent');

# Add skills with different configurations
$agent->add_skill('math');
$agent->add_skill('datetime');

# Check what's loaded
my $skills = $agent->list_skills;

# Remove a skill
$agent->remove_skill('math');

# Check if a specific skill is loaded
if ($agent->has_skill('datetime')) {
    print "Date/time capabilities available\n";
}
```

## Creating Custom Skills

Create a new skill by extending `SignalWire::Skills::SkillBase` and registering
it with the skill registry:

```perl
package SignalWire::Skills::Builtin::MySkill;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill('my_skill', __PACKAGE__);

has '+skill_name'        => ( default => sub { 'my_skill' } );
has '+skill_description' => ( default => sub { 'Does something with configurable parameters' } );
has '+skill_version'     => ( default => sub { '1.0.0' } );
has '+required_env_vars' => ( default => sub { ['API_KEY'] } );

sub setup {
    my ($self) = @_;
    return 0 unless $self->validate_env_vars;
    return 1;
}

sub register_tools {
    my ($self) = @_;
    my $max_items = $self->params->{max_items} // 10;

    $self->define_tool(
        name        => 'my_function',
        description => "Does something cool (max $max_items items)",
        parameters  => {
            type       => 'object',
            properties => {
                input => { type => 'string', description => 'Input parameter' },
            },
            required => ['input'],
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new(
                "Processed: $args->{input} (max_items=$max_items)");
        },
    );
}

sub get_hints { return ['custom', 'skill', 'awesome'] }

sub _get_prompt_sections {
    return [
        {
            title => 'Custom Capability',
            body  => 'You can do custom things with my_skill.',
        }
    ];
}

sub get_parameter_schema {
    return {
        %{ SignalWire::Skills::SkillBase->get_parameter_schema },
        max_items => { type => 'integer', default => 10 },
    };
}

1;
```

Once registered, the skill is available via `add_skill`:
```perl
# Use defaults
$agent->add_skill('my_skill');

# Use custom parameters
$agent->add_skill('my_skill', {
    max_items => 20,
});
```

## Quick Start

1. **Run the demo:**
   ```bash
   PERL5LIB="lib" perl examples/skills_demo.pl
   ```

2. **For web search, set environment variables:**
   ```bash
   export GOOGLE_SEARCH_API_KEY="your_api_key"
   export GOOGLE_SEARCH_ENGINE_ID="your_engine_id"
   ```

## Benefits

- **One-liner integration** - `$agent->add_skill('skill_name')`
- **Configurable parameters** - `$agent->add_skill('skill_name', { param => 'value' })`
- **Dependency validation** - Checks packages and environment variables
- **Modular architecture** - Skills are self-contained and reusable
- **Extensible** - Easy to create custom skills with parameters
- **Multiple instances** - Skills that support it can be added more than once with distinct tool names

The skills system makes SignalWire agents more modular, maintainable, and configurable.
