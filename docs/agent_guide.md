# SignalWire AI Agent Guide

## Table of Contents
- [Introduction](#introduction)
- [Architecture Overview](#architecture-overview)
- [Creating an Agent](#creating-an-agent)
- [Prompt Building](#prompt-building)
- [SWAIG Functions (SignalWire AI Gateway)](#swaig-functions)
- [Skills System](#skills-system)
- [Multilingual Support](#multilingual-support)
- [Agent Configuration](#agent-configuration)
- [Dynamic Agent Configuration](#dynamic-agent-configuration)
  - [Overview](#overview)
  - [Setting Up Dynamic Configuration](#setting-up-dynamic-configuration)
  - [Dynamic Configuration Methods](#dynamic-configuration-methods)
  - [Request Data Access](#request-data-access)
  - [Configuration Examples](#configuration-examples)
  - [Use Cases](#use-cases)
  - [Migration Guide](#migration-guide)
  - [Best Practices](#best-practices)
- [Advanced Features](#advanced-features)
  - [State Management](#state-management)
  - [SIP Routing](#sip-routing)
  - [Custom Routing](#custom-routing)
- [Prefab Agents](#prefab-agents)
- [API Reference](#api-reference)
- [Examples](#examples)

## Introduction

The `AgentBase` class provides the foundation for creating AI-powered agents using the SignalWire AI Agent SDK. It extends the `SWMLService` class, inheriting all its SWML (SignalWire Markup Language) document creation and serving capabilities, while adding AI-specific functionality. SWML is the JSON document format that tells the SignalWire platform how an agent should behave during a call.

Key features of `AgentBase` include:

- Structured prompt building with POM (Prompt Object Model)
- SWAIG (SignalWire AI Gateway) function definitions -- SWAIG is the platform's AI tool-calling system with native access to the media stack
- Multilingual support
- Agent configuration (hint handling, pronunciation rules, etc.)
- State management for conversations

This guide explains how to create and customize your own AI agents, with examples based on the SDK's sample implementations.

## Architecture Overview

The Agent SDK architecture consists of several layers:

1. **SWMLService**: The base layer for SWML document creation and serving
2. **AgentBase**: Extends SWMLService with AI agent functionality
3. **Custom Agents**: Your specific agent implementations that extend AgentBase

Here's how these components relate to each other:

```
┌─────────────┐
│ Your Agent  │ (Extends AgentBase with your specific functionality)
└─────▲───────┘
      │
┌─────┴───────┐
│  AgentBase  │ (Adds AI functionality to SWMLService)
└─────▲───────┘
      │
┌─────┴───────┐
│ SWMLService │ (Provides SWML document creation and web service)
└─────────────┘
```

## Creating an Agent

To create an agent, extend the `AgentBase` class and define your agent's behavior:

```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Define agent personality and behavior
    $self->prompt_add_section('Personality', 'You are a helpful and friendly assistant.');
    $self->prompt_add_section('Goal', 'Help users with their questions and tasks.');
    $self->prompt_add_section('Instructions', '',
        bullets => [
            'Answer questions clearly and concisely',
            "If you don't know, say so",
            'Use the provided tools when appropriate',
        ],
    );

    # Add a post-prompt for summary
    $self->set_post_prompt('Please summarize the key points of this conversation.');
}

1;
```

Construct it with the standard agent options (POM is on by default):

```perl
my $agent = MyAgent->new(
    name  => 'my-agent',
    route => '/agent',
    host  => '0.0.0.0',
    port  => 3000,
);
```

## Running Your Agent

The SignalWire AI Agent SDK provides a `run()` method that automatically detects the execution environment and configures the agent appropriately. This method works across all deployment modes:

### Deployment with `run()`

<!-- snippet: no-compile references MyAgent, a reader-defined example package with no module file -->
```perl
use lib 'lib';
use MyAgent;

my $agent = MyAgent->new(name => 'my-agent', route => '/agent');

print "Starting agent server...\n";
print "Note: Works in any deployment mode (server/CGI/Lambda)\n";
$agent->run;  # Auto-detects environment
```

The `run()` method automatically detects and configures for:

- **HTTP Server**: When run directly, starts an HTTP server
- **CGI**: When CGI environment variables are detected, operates in CGI mode  
- **AWS Lambda**: When Lambda environment is detected, configures for serverless execution

### Deployment Modes

#### HTTP Server Mode
When run directly (e.g., `perl my_agent.pl`), the agent starts an HTTP server:

```perl
# Automatically starts HTTP server when run directly
$agent->run;
```

#### CGI Mode  
When CGI environment variables are present, operates in CGI mode with clean HTTP output:

```perl
# Same code - automatically detects CGI environment
$agent->run;
```

#### AWS Lambda Mode
When AWS Lambda environment is detected, configures for serverless execution:

```perl
# Same code - automatically detects Lambda environment
$agent->run;
```

### Environment Detection

The SDK automatically detects the execution environment:

| Environment | Detection Method | Behavior |
|-------------|------------------|----------|
| **HTTP Server** | Default when no serverless environment detected | Starts a Plack/PSGI server on specified host/port |
| **CGI** | `GATEWAY_INTERFACE` environment variable present | Processes single CGI request and exits |
| **AWS Lambda** | `AWS_LAMBDA_FUNCTION_NAME` environment variable | Handles Lambda event/context |
| **Google Cloud** | `FUNCTION_NAME` or `K_SERVICE` variables | Processes Cloud Function request |
| **Azure Functions** | `AZURE_FUNCTIONS_*` variables | Handles Azure Function request |

### Logging Configuration

The SDK includes a central logging system that automatically configures based on the deployment environment:

```perl
# Logging is automatically configured based on environment
# No manual setup required in most cases

# Optional: Override logging mode via environment variable
# SIGNALWIRE_LOG_MODE=off      # Disable all logging
# SIGNALWIRE_LOG_MODE=stderr   # Log to stderr
# SIGNALWIRE_LOG_MODE=default  # Use default logging
# SIGNALWIRE_LOG_MODE=auto     # Auto-detect (default)
```

The logging system automatically:
- **CGI Mode**: Sets logging to 'off' to avoid interfering with HTTP headers
- **Lambda Mode**: Configures appropriate logging for serverless environment
- **Server Mode**: Uses structured logging with timestamps and levels
- **Debug Mode**: Enhanced logging when debug flags are set

## Prompt Building

There are several ways to build prompts for your agent:

### 1. Using Prompt Sections (POM)

The Prompt Object Model (POM) provides a structured way to build prompts:

```perl
# Add a section with just body text
$self->prompt_add_section('Personality', 'You are a friendly assistant.');

# Add a section with bullet points
$self->prompt_add_section('Instructions', '',
    bullets => [
        'Answer questions clearly',
        'Be helpful and polite',
        'Use functions when appropriate',
    ],
);

# Add a section with both body and bullets
$self->prompt_add_section('Context',
    'The user is calling about technical support.',
    bullets => [
        'They may need help with their account',
        'Check for existing tickets',
    ],
);
```

### 2. Using Raw Text Prompts

For simpler agents, you can set the prompt directly as text:

```perl
$self->set_prompt_text(<<'PROMPT');
You are a helpful assistant. Your goal is to provide clear and concise information
to the user. Answer their questions to the best of your ability.
PROMPT
```

### 3. Setting a Post-Prompt

The post-prompt is sent to the AI after the conversation for summary or analysis:

```perl
$self->set_post_prompt(<<'POST');
Analyze the conversation and extract:
1. Main topics discussed
2. Action items or follow-ups needed
3. Whether the user's questions were answered satisfactorily
POST
```

## SWAIG Functions

SWAIG (SignalWire AI Gateway) functions allow the AI agent to perform actions and access external systems during a call. The AI decides when to call a function based on the conversation; SWAIG handles invocation, parameter passing, and delivering the result back to the AI. There are two types of SWAIG functions you can define:

### SWAIG functions ARE LLM tools — descriptions matter

Before writing your first SWAIG function, internalize this: a SWAIG function is **exactly the same concept** as a "tool" in native OpenAI / Anthropic tool calling. There is no separate "SWAIG layer" between your function and the model. Each SWAIG function is rendered into the OpenAI tool schema format on every turn:

```json
{
  "type": "function",
  "function": {
    "name":        "your_function_name",
    "description": "your description text",
    "parameters":  { /* your JSON schema */ }
  }
}
```

That schema is sent to the model as part of the same API call that produces the next assistant message. The model reads:

- the **function `description`** to decide WHEN to call this tool
- the **per-parameter `description` strings** inside `parameters` to decide HOW to fill in each argument

This means **descriptions are prompt engineering**, not developer documentation. They are not a comment for the next human reading the code — they are instructions to the LLM that directly determine whether the model picks your tool when the user's request matches it.

Compare:

| Bad (model often misses the tool) | Good (model picks it reliably) |
|---|---|
| `description => 'Lookup function'` | `description => "Look up a customer's account details by their account number. Use this BEFORE quoting any account-specific information (balance, plan, status, billing date). Don't use it for general product questions."` |
| `description => 'the id'` (parameter) | `description => "The customer's 8-digit account number, no dashes or spaces. Ask the user if they don't provide it."` |

A vague description is the #1 cause of "the model has the right tool but doesn't call it" failures. When you find yourself debugging why the model isn't picking a tool that obviously matches the user's request, the first thing to check is whether the description tells the model — in plain language — when to use it and what makes it the right choice over sibling tools.

**Tool count matters too.** LLM tool selection accuracy degrades noticeably past ~7-8 simultaneously-active tools per call. If you have many tools, partition them across steps using `$step->set_functions(...)` so only the relevant subset is active at any moment. See `contexts_guide.md` for the per-step whitelist mechanism.

### 1. Local Webhook Functions (Standard)

These are the traditional SWAIG functions that are handled locally by your agent:

```perl
use SignalWire::SWAIG::FunctionResult;

$self->define_tool(
    name        => 'get_weather',
    description => 'Get the current weather for a location',
    parameters  => {
        type       => 'object',
        properties => {
            location => {
                type        => 'string',
                description => 'The city or location to get weather for',
            },
        },
    },
    secure  => 1,  # Optional, defaults to true
    handler => sub {
        my ($args, $raw_data) = @_;

        # Extract the location parameter
        my $location = $args->{location} // 'Unknown location';

        # Here you would typically call a weather API
        # For this example, we'll return mock data
        my $weather_data = "It's sunny and 72F in $location.";

        # Return a FunctionResult
        return SignalWire::SWAIG::FunctionResult->new($weather_data);
    },
);
```

### 2. External Webhook Functions

External webhook functions allow you to delegate function execution to external services instead of handling them locally. This is useful when you want to:
- Use existing web services or APIs directly
- Distribute function processing across multiple servers
- Integrate with third-party systems that provide their own endpoints

To create an external webhook function, add a `webhook_url` parameter to `define_tool`:

```perl
$self->define_tool(
    name        => 'get_weather_external',
    description => 'Get weather from external service',
    parameters  => {
        type       => 'object',
        properties => {
            location => {
                type        => 'string',
                description => 'The city or location to get weather for',
            },
        },
    },
    webhook_url => 'https://your-service.com/weather-endpoint',
    handler     => sub {
        # This handler will never be called locally when webhook_url is provided.
        # The external service at webhook_url receives the function call instead.
        return SignalWire::SWAIG::FunctionResult->new('This should not be reached for external webhooks');
    },
);
```

#### How External Webhooks Work

When you specify a `webhook_url`:

1. **Function Registration**: The function is registered with your agent as usual
2. **SWML Generation**: The generated SWML includes the external webhook URL instead of your local endpoint
3. **SignalWire Processing**: When the AI calls the function, SignalWire makes an HTTP POST request directly to your external URL
4. **Payload Format**: The external service receives a JSON payload with the function call data:

```json
{
    "function": "get_weather_external",
    "argument": {
        "parsed": [{"location": "New York"}],
        "raw": "{\"location\": \"New York\"}"
    },
    "call_id": "abc123-def456-ghi789",
    "call": { /* call information */ },
    "vars": { /* call variables */ }
}
```

5. **Response Handling**: Your external service should return a JSON response that SignalWire will process.

#### Mixing Local and External Functions

You can mix both types of functions in the same agent:

```perl
package HybridAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';
use SignalWire::SWAIG::FunctionResult;

sub BUILD {
    my ($self) = @_;

    # Local function - handled by this agent
    $self->define_tool(
        name        => 'get_help',
        description => 'Get help information',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            return SignalWire::SWAIG::FunctionResult->new('I can help you with weather and news!');
        },
    );

    # External function - handled by external service
    $self->define_tool(
        name        => 'get_weather',
        description => 'Get current weather',
        parameters  => {
            type       => 'object',
            properties => { location => { type => 'string', description => 'City name' } },
        },
        webhook_url => 'https://weather-service.com/api/weather',
        handler     => sub { },  # Not called for external webhooks
    );

    # Another external function - different service
    $self->define_tool(
        name        => 'get_news',
        description => 'Get latest news',
        parameters  => {
            type       => 'object',
            properties => { topic => { type => 'string', description => 'News topic' } },
        },
        webhook_url => 'https://news-service.com/api/news',
        handler     => sub { },  # Not called for external webhooks
    );
}

1;
```

#### Testing External Webhooks

You can test external webhook functions using the CLI tool:

```bash
# Test local function
swaig-test --file examples/my_agent.pl --exec get_help

# Test external webhook function
swaig-test --file examples/my_agent.pl --verbose --exec get_weather --param location="New York"

# List all functions with their types
swaig-test --file examples/my_agent.pl --list-tools
```

The CLI tool will automatically detect external webhook functions and make HTTP requests to the external services, simulating what SignalWire does in production.

### 3. Handlers and Raw Data

Every SWAIG handler is an anonymous sub that receives two arguments: the parsed
argument hashref and the raw request hashref. Declare the JSON Schema explicitly
via the `parameters` option (Perl has no type-hint inference — the schema is
always spelled out):

```perl
$self->define_tool(
    name        => 'get_weather',
    description => 'Get the weather forecast',
    parameters  => {
        type       => 'object',
        properties => {
            city  => { type => 'string', description => 'Name of the city to look up' },
            units => {
                type        => 'string',
                description => 'Temperature units to use',
                enum        => ['celsius', 'fahrenheit'],
            },
        },
        required => ['city'],
    },
    handler => sub {
        my ($args, $raw_data) = @_;
        my $city  = $args->{city};
        my $units = $args->{units} // 'celsius';
        return SignalWire::SWAIG::FunctionResult->new("It's sunny in $city (showing $units)");
    },
);
```

**Accessing raw_data in handlers:**

The second handler argument is always the raw request data, so you can read
call-level fields such as `call_id` alongside the parsed arguments:

```perl
$self->define_tool(
    name        => 'check_call',
    description => 'Check the current call',
    parameters  => {
        type       => 'object',
        properties => { query => { type => 'string', description => 'What to check' } },
        required   => ['query'],
    },
    handler => sub {
        my ($args, $raw_data) = @_;
        my $call_id = ($raw_data && $raw_data->{call_id}) // 'unknown';
        return SignalWire::SWAIG::FunctionResult->new("Call $call_id: query=$args->{query}");
    },
);
```

### Function Parameters

The parameters for a SWAIG function are defined using JSON Schema:

```perl
parameters => {
    type       => 'object',
    properties => {
        parameter_name => {
            type        => 'string',   # Can be string, number, integer, boolean, array, object
            description => 'Description of the parameter',
            # Optional attributes:
            enum        => ['option1', 'option2'],  # For enumerated values
            minimum     => 0,                        # For numeric types
            maximum     => 100,                      # For numeric types
            pattern     => '^[A-Z]+$',               # For string validation
        },
    },
},
```

### Function Results

To return results from a SWAIG function, use the `SignalWire::SWAIG::FunctionResult` class:

```perl
# Basic result with just text
return SignalWire::SWAIG::FunctionResult->new("Here's the result");

# Result with a single action
return SignalWire::SWAIG::FunctionResult->new("Here's the result with an action")
    ->add_action('say', 'I found the information you requested.');

# Result with multiple actions using add_actions
return SignalWire::SWAIG::FunctionResult->new('Multiple actions example')
    ->add_actions([
        { playback_bg    => { file => 'https://example.com/music.mp3' } },
        { set_global_data => { key => 'value' } },
    ]);

# Alternative way to add multiple actions sequentially
return SignalWire::SWAIG::FunctionResult->new('Sequential actions example')
    ->add_action('say', 'I found the information you requested.')
    ->add_action('playback_bg', { file => 'https://example.com/music.mp3' });
```

In the examples above:
- `add_action(name, data)` adds a single action with the given name and data
- `add_actions(actions)` adds multiple actions at once from a list of action objects

### Native Functions

The agent can use SignalWire's built-in functions:

```perl
# Enable native functions
$self->set_native_functions([
    'check_time',
    'wait_seconds',
]);
```

### Function Includes

You can include functions from remote sources:

```perl
# Include remote functions
$self->add_function_include({
    url       => 'https://api.example.com/functions',
    functions => ['get_weather', 'get_news'],
    meta_data => { session_id => 'unique-session-123' },  # Use for session tracking, NOT credentials
});
```

### SWAIG Function Security

The SDK implements an automated security mechanism for SWAIG functions to ensure that only authorized calls can be made to your functions. This is important because SWAIG functions often provide access to sensitive operations or data.

#### Token-Based Security

By default, all SWAIG functions are marked as `secure=True`, which enables token-based security:

```perl
$self->define_tool(
    name        => 'get_account_details',
    description => 'Get customer account details',
    parameters  => {
        type       => 'object',
        properties => { account_id => { type => 'string' } },
    },
    secure  => 1,  # This is the default, can be omitted
    handler => sub {
        my ($args, $raw_data) = @_;
        # Implementation
    },
);
```

When a function is marked as secure:

1. The SDK automatically generates a secure token for each function when rendering the SWML document
2. The token is added to the function's URL as a query parameter: `?token=X2FiY2RlZmcuZ2V0X3RpbWUuMTcxOTMxNDI1...`
3. When the function is called, the token is validated before executing the function

These security tokens have important properties:
- **Completely stateless**: The system doesn't need to store tokens or track sessions
- **Self-contained**: Each token contains all information needed for validation
- **Function-specific**: A token for one function can't be used for another
- **Session-bound**: Tokens are tied to a specific call/session ID
- **Time-limited**: Tokens expire after a configurable duration (default: 60 minutes)
- **Cryptographically signed**: Tokens can't be tampered with or forged

This stateless design provides several benefits:
- **Server resilience**: Tokens remain valid even if the server restarts
- **No memory consumption**: No need to track sessions or store tokens in memory
- **High scalability**: Multiple servers can validate tokens without shared state
- **Load balancing**: Requests can be distributed across multiple servers freely

The token system secures both SWAIG functions and post-prompt endpoints:
- SWAIG function calls for interactive AI capabilities
- Post-prompt requests for receiving conversation summaries

You can disable token security for specific functions when appropriate:

```perl
$self->define_tool(
    name        => 'get_public_information',
    description => "Get public information that doesn't require security",
    parameters  => { type => 'object', properties => {} },
    secure      => 0,  # Disable token security for this function
    handler     => sub {
        my ($args, $raw_data) = @_;
        # Implementation
    },
);
```

#### Token Expiration

The default token expiration is 60 minutes (3600 seconds), but you can configure this when initializing your agent:

```perl
my $agent = MyAgent->new(
    name              => 'my_agent',
    token_expiry_secs => 1800,  # Set token expiration to 30 minutes
);
```

The expiration timer resets each time a function is successfully called, so as long as there is activity at least once within the expiration period, the tokens will remain valid throughout the entire conversation.

#### Custom Token Validation

You can override the default token validation by implementing your own `validate_tool_token` method in your custom agent class.

## Skills System

The Skills System allows you to extend your agents with reusable capabilities via one-liner calls. Skills are modular, reusable components that can be easily added to any agent and configured with parameters.

### Quick Start

```perl
package SkillfulAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Add skills with one-liners
    $self->add_skill('web_search');    # Web search capability
    $self->add_skill('datetime');      # Current date/time info
    $self->add_skill('math');          # Mathematical calculations

    # Configure skills with parameters
    $self->add_skill('web_search', {
        num_results => 3,     # Get 3 search results instead of default 1
        delay       => 0.5,   # Add delay between requests
    });
}

1;
```

### Available Built-in Skills

#### Web Search Skill (`web_search`)
Provides web search capabilities using Google Custom Search API with web scraping.

**Requirements:**
- Packages: `beautifulsoup4`, `requests`

**Parameters:**
- `api_key` (required): Google Custom Search API key
- `search_engine_id` (required): Google Custom Search Engine ID
- `num_results` (default: 1): Number of search results to return
- `delay` (default: 0): Delay in seconds between requests
- `tool_name` (default: "web_search"): Custom name for the search tool
- `no_results_message` (default: "I couldn't find any results for '{query}'. This might be due to a very specific query or temporary issues. Try rephrasing your search or asking about a different topic."): Custom message to return when no search results are found. Use `{query}` as a placeholder for the search query.

**Multiple Instance Support:**
The web_search skill supports multiple instances with different search engines and tool names, allowing you to search different data sources:

**Example:**
```perl
# Basic single instance
$agent->add_skill('web_search', {
    api_key          => 'your-google-api-key',
    search_engine_id => 'your-search-engine-id',
});
# Creates tool: web_search

# Fast single result (previous default)
$agent->add_skill('web_search', {
    api_key          => 'your-google-api-key',
    search_engine_id => 'your-search-engine-id',
    num_results      => 1,
    delay            => 0,
});

# Multiple results with delay
$agent->add_skill('web_search', {
    api_key          => 'your-google-api-key',
    search_engine_id => 'your-search-engine-id',
    num_results      => 5,
    delay            => 1.0,
});

# Multiple instances with different search engines
$agent->add_skill('web_search', {
    api_key          => 'your-google-api-key',
    search_engine_id => 'general-search-engine-id',
    tool_name        => 'search_general',
    num_results      => 1,
});
# Creates tool: search_general

$agent->add_skill('web_search', {
    api_key          => 'your-google-api-key',
    search_engine_id => 'news-search-engine-id',
    tool_name        => 'search_news',
    num_results      => 3,
    delay            => 0.5,
});
# Creates tool: search_news

# Custom no results message
$agent->add_skill('web_search', {
    api_key            => 'your-google-api-key',
    search_engine_id   => 'your-search-engine-id',
    no_results_message => "Sorry, I couldn't find information about '{query}'. Please try a different search term.",
});
```

#### DateTime Skill (`datetime`)
Provides current date and time information with timezone support.

**Requirements:**
- Packages: `pytz`

**Tools Added:**
- `get_current_time`: Get current time with optional timezone
- `get_current_date`: Get current date with optional timezone

**Example:**
```perl
$agent->add_skill('datetime');
# Agent can now tell users the current time and date
```

#### Math Skill (`math`)
Provides safe mathematical expression evaluation.

**Requirements:**
- None (uses built-in Python functionality)

**Tools Added:**
- `calculate`: Evaluate mathematical expressions safely

**Example:**
```perl
$agent->add_skill('math');
# Agent can now perform calculations like "2 + 3 * 4"
```

#### DataSphere Skill (`datasphere`)
Provides knowledge search capabilities using SignalWire DataSphere, a cloud-hosted document search and retrieval-augmented generation (RAG) service.

**Requirements:**
- Packages: `requests`

**Parameters:**
- `space_name` (required): SignalWire space name
- `project_id` (required): SignalWire project ID 
- `token` (required): SignalWire authentication token
- `document_id` (required): DataSphere document ID to search
- `count` (default: 1): Number of search results to return
- `distance` (default: 3.0): Distance threshold for search matching
- `tags` (optional): List of tags to filter search results
- `language` (optional): Language code to limit search
- `pos_to_expand` (optional): List of parts of speech for synonym expansion (e.g., ["NOUN", "VERB"])
- `max_synonyms` (optional): Maximum number of synonyms to use for each word
- `tool_name` (default: "search_knowledge"): Custom name for the search tool
- `no_results_message` (default: "I couldn't find any relevant information for '{query}' in the knowledge base. Try rephrasing your question or asking about a different topic."): Custom message when no results found

**Multiple Instance Support:**
The DataSphere skill supports multiple instances with different tool names, allowing you to search multiple knowledge bases:

**Example:**
```perl
# Basic single instance
$agent->add_skill('datasphere', {
    space_name  => 'my-space',
    project_id  => 'my-project',
    token       => 'my-token',
    document_id => 'general-knowledge',
});
# Creates tool: search_knowledge

# Multiple instances for different knowledge bases
$agent->add_skill('datasphere', {
    space_name  => 'my-space',
    project_id  => 'my-project',
    token       => 'my-token',
    document_id => 'product-docs',
    tool_name   => 'search_products',
    tags        => ['Products', 'Features'],
    count       => 3,
});
# Creates tool: search_products

$agent->add_skill('datasphere', {
    space_name         => 'my-space',
    project_id         => 'my-project',
    token              => 'my-token',
    document_id        => 'support-kb',
    tool_name          => 'search_support',
    no_results_message => "I couldn't find support information about '{query}'. Try contacting our support team.",
    distance           => 5.0,
});
# Creates tool: search_support
```

#### Native Vector Search Skill (`native_vector_search`)
Provides local document search capabilities using vector similarity and keyword search. This skill works entirely offline with local `.swsearch` index files or can connect to remote search servers.

**Requirements:**
- The native vector search dependencies must be installed (`cpanm --installdeps .` pulls them in from the `cpanfile`)

**Parameters:**
- `tool_name` (default: "search_knowledge"): Custom name for the search tool
- `description` (default: "Search the local knowledge base for information"): Tool description
- `index_file` (optional): Path to local `.swsearch` index file
- `remote_url` (optional): URL of remote search server (e.g., "http://localhost:8001")
- `index_name` (default: "default"): Index name on remote server (for remote mode)
- `build_index` (default: False): Auto-build index if missing
- `source_dir` (optional): Source directory for auto-building index
- `file_types` (default: ["md", "txt"]): File types to include when building index
- `count` (default: 3): Number of search results to return
- `distance_threshold` (default: 0.0): Minimum similarity score for results
- `tags` (optional): List of tags to filter search results
- `response_prefix` (optional): Text to prepend to all search responses
- `response_postfix` (optional): Text to append to all search responses
- `no_results_message` (default: "No information found for '{query}'"): Custom message when no results found

**Multiple Instance Support:**
The native vector search skill supports multiple instances with different indexes and tool names:

**Example:**
```perl
# Local mode with auto-build
$agent->add_skill('native_vector_search', {
    tool_name   => 'search_docs',
    description  => 'Search SDK concepts guide',
    build_index => 1,
    source_dir  => './docs',
    index_file  => 'concepts.swsearch',
    count       => 5,
});
# Creates tool: search_docs

# Remote mode connecting to search server
$agent->add_skill('native_vector_search', {
    tool_name   => 'search_knowledge',
    description => 'Search the knowledge base',
    remote_url  => 'http://localhost:8001',
    index_name  => 'concepts',
    count       => 3,
});
# Creates tool: search_knowledge

# Multiple local indexes
$agent->add_skill('native_vector_search', {
    tool_name       => 'search_examples',
    description     => 'Search code examples',
    index_file      => 'examples.swsearch',
    response_prefix => 'From the examples:',
});
# Creates tool: search_examples

# Voice-optimized responses using concepts guide
$agent->add_skill('native_vector_search', {
    tool_name          => 'search_docs',
    index_file         => 'concepts.swsearch',
    response_prefix    => 'Based on the comprehensive SDK guide:',
    response_postfix   => 'Would you like more specific information?',
    no_results_message => "I couldn't find information about '{query}' in the concepts guide.",
});
```

**Building Search Indexes:**
Before using local mode, you need to build search indexes:

```bash
# Build index from documentation
sw-search docs --output docs.swsearch

# Build with custom settings
sw-search ./knowledge \
    --output knowledge.swsearch \
    --file-types md,txt,pdf \
    --chunk-size 500 \
    --verbose
```

### Skill Management

```perl
# Check what skills are loaded
my @loaded_skills = $agent->list_skills;
print 'Loaded skills: ' . join(', ', @loaded_skills) . "\n";

# Check if a specific skill is loaded
if ($agent->has_skill('web_search')) {
    print "Web search is available\n";
}

# Remove a skill (if needed)
$agent->remove_skill('math');
```

### Advanced Skill Configuration with swaig_fields

Skills support a special `swaig_fields` parameter that allows you to customize how SWAIG functions are registered. When you pass `swaig_fields` to a skill, they are automatically merged into all tool definitions created by that skill through the `SkillBase.define_tool()` wrapper method.

```perl
# Add a skill with swaig_fields to customize SWAIG function properties
$agent->add_skill('math', {
    precision    => 2,   # Regular skill parameter
    swaig_fields => {    # Special fields merged into SWAIG function automatically
        secure  => 0,    # Override default security requirement
        fillers => {
            'en-US' => ['Let me calculate that...', 'Computing the result...'],
            'es-ES' => ['Dejame calcular eso...', 'Calculando el resultado...'],
        },
    },
});

# Add web search with custom security and fillers
$agent->add_skill('web_search', {
    num_results  => 3,
    delay        => 0.5,
    swaig_fields => {
        secure  => 1,    # Require authentication
        fillers => {
            'en-US' => ['Searching the web...', 'Looking that up...', 'Finding information...'],
        },
    },
});
```

The `swaig_fields` can include any parameter accepted by `define_tool()`:
- `secure`: Boolean indicating if the function requires authentication
- `fillers`: Hashref mapping language codes to arrays of filler phrases
- Any other fields supported by the SWAIG function system

**Implementation Note**: The `SkillBase` class provides a `define_tool()` wrapper method that automatically injects `swaig_fields` into all tool definitions. Skills should use `$self->define_tool(...)` instead of `$self->agent->define_tool(...)` to get automatic swaig_fields support without manual handling.

### Error Handling

The skills system provides detailed error messages for common issues. `add_skill`
returns a `($ok, $error)` pair rather than throwing, so check the status:

```perl
my ($ok, $error) = $agent->add_skill('web_search');
unless ($ok) {
    print "Failed to load skill: $error\n";
    # Output: "Failed to load skill: Skill 'web_search' missing required environment variables"
}
```

### Creating Custom Skills

You can create your own skills by extending the `SkillBase` class:

```perl
package SignalWire::Skills::Builtin::Weather;
use strict;
use warnings;
use Moo;
extends 'SignalWire::Skills::SkillBase';
use SignalWire::SWAIG::FunctionResult;

# Register the skill under its public name
use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill('weather', __PACKAGE__);

has '+skill_name'        => ( default => sub { 'weather' } );
has '+skill_description' => ( default => sub { 'Get weather information for locations' } );
has '+skill_version'     => ( default => sub { '1.0.0' } );
has '+required_packages' => ( default => sub { [] } );
has '+required_env_vars' => ( default => sub { ['WEATHER_API_KEY'] } );

has default_units => ( is => 'rw', default => sub { 'fahrenheit' } );
has timeout       => ( is => 'rw', default => sub { 10 } );

# Setup the skill - validate dependencies and initialize
sub setup {
    my ($self) = @_;
    return 0 unless $self->validate_env_vars && $self->validate_packages;

    # Get configuration parameters
    $self->default_units( $self->params->{units}   // 'fahrenheit' );
    $self->timeout(       $self->params->{timeout} // 10 );

    return 1;
}

# Register tools with the agent
sub register_tools {
    my ($self) = @_;
    $self->define_tool(
        name        => 'get_weather',
        description => 'Get current weather for a location',
        parameters  => {
            type       => 'object',
            properties => {
                location => { type => 'string', description => 'City or location name' },
                units    => {
                    type        => 'string',
                    description => 'Temperature units (fahrenheit or celsius)',
                    enum        => ['fahrenheit', 'celsius'],
                },
            },
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            my $location = $args->{location} // '';
            my $units    = $args->{units}    // $self->default_units;

            return SignalWire::SWAIG::FunctionResult->new('Please provide a location')
                unless length $location;

            # Your weather API integration here
            my $weather_data = "Weather for $location: 72F and sunny";
            return SignalWire::SWAIG::FunctionResult->new($weather_data);
        },
    );
}

# Return speech recognition hints
sub get_hints {
    my ($self) = @_;
    return ['weather', 'temperature', 'forecast', 'conditions'];
}

# Return prompt sections to add to the agent
sub get_prompt_sections {
    my ($self) = @_;
    return [
        {
            title   => 'Weather Information',
            body    => 'You can provide current weather information for any location.',
            bullets => [
                'Use get_weather tool when users ask about weather',
                'Always specify the location clearly',
                'Include temperature and conditions in your response',
            ],
        },
    ];
}

1;
```

**Using the custom skill:**
```perl
# Place the skill under lib/SignalWire/Skills/Builtin/Weather.pm (registered above).
# Then use it in your agent:

$agent->add_skill('weather', {
    units   => 'celsius',
    timeout => 15,
});
```

### Skills with Dynamic Configuration

Skills work with dynamic configuration:

```perl
package DynamicSkillAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;
    $self->set_dynamic_config_callback(sub {
        my ($query_params, $body_params, $headers, $agent) = @_;

        # Add different skills based on request parameters
        my $tier = $query_params->{tier} // 'basic';

        # Basic skills for all users
        $agent->add_skill('datetime');
        $agent->add_skill('math');

        # Premium skills for premium users
        if ($tier eq 'premium') {
            $agent->add_skill('web_search', {
                num_results => 5,
                delay       => 0.5,
            });
        }
        elsif ($tier eq 'basic') {
            $agent->add_skill('web_search', {
                num_results => 1,
                delay       => 0,
            });
        }
    });
}

1;
```

### Best Practices

1. **Choose appropriate parameters**: Configure skills for your use case
   ```perl
   # For speed (customer service)
   $agent->add_skill('web_search', { num_results => 1, delay => 0 });

   # For research (detailed analysis)
   $agent->add_skill('web_search', { num_results => 5, delay => 1.0 });
   ```

2. **Handle missing dependencies gracefully**:
   ```perl
   my ($ok, $error) = $agent->add_skill('web_search');
   unless ($ok) {
       warn "Web search unavailable: $error\n";
       # Continue without web search capability
   }
   ```

3. **Document your custom skills**: Include clear descriptions and parameter documentation

4. **Test skills in isolation**: Create simple test scripts to verify skill functionality

For more detailed information about the skills system architecture and advanced customization, see the [Skills System guide](skills_system.md).

## Multilingual Support

Agents can support multiple languages:

```perl
# Add English language
$self->add_language(
    name             => 'English',
    code             => 'en-US',
    voice            => 'en-US-Neural2-F',
    speech_fillers   => ['Let me think...', 'One moment please...'],
    function_fillers => ["I'm looking that up...", 'Let me check that...'],
);

# Add Spanish language
$self->add_language(
    name           => 'Spanish',
    code           => 'es',
    voice          => 'rime.spore:multilingual',
    speech_fillers => ['Un momento por favor...', 'Estoy pensando...'],
);
```

### Voice Formats

There are different ways to specify voices:

```perl
# Simple format
$self->add_language(name => 'English', code => 'en-US', voice => 'en-US-Neural2-F');

# Explicit parameters with engine and model
$self->add_language(
    name   => 'British English',
    code   => 'en-GB',
    voice  => 'spore',
    engine => 'rime',
    model  => 'multilingual',
);

# Combined string format
$self->add_language(
    name  => 'Spanish',
    code  => 'es',
    voice => 'rime.spore:multilingual',
);
```

## Agent Configuration

### Adding Hints

Hints help the AI understand certain terms better:

```perl
# Simple hints (list of words)
$self->add_hints(['SignalWire', 'SWML', 'SWAIG']);

# Pattern hint with replacement
$self->add_pattern_hint({
    hint        => 'AI Agent',
    pattern     => 'AI\\s+Agent',
    replace     => 'A.I. Agent',
    ignore_case => 1,
});
```

### Adding Pronunciation Rules

Pronunciation rules help the AI speak certain terms correctly:

```perl
# Add pronunciation rule
$self->add_pronunciation('API', 'A P I', ignore_case => 0);
$self->add_pronunciation('SIP', 'sip',   ignore_case => 1);
```

### Setting AI Parameters

Configure various AI behavior parameters:

```perl
# Set AI parameters
$self->set_params({
    wait_for_user         => JSON::false,
    end_of_speech_timeout => 1000,
    ai_volume             => 5,
    languages_enabled     => JSON::true,
    local_tz              => 'America/Los_Angeles',
});
```

### Setting Global Data

Provide global data for the AI to reference:

```perl
# Set global data
$self->set_global_data({
    company_name       => 'SignalWire',
    product            => 'AI Agent SDK',
    supported_features => [
        'Voice AI',
        'Telephone integration',
        'SWAIG functions',
    ],
});
```

### Customizing LLM Parameters

The SDK provides methods to fine-tune the Language Model parameters for both the main prompt and post-prompt, giving you precise control over the AI's behavior:

```perl
# Set LLM parameters for the main prompt
# These parameters are passed to the server which validates them based on the model
$self->set_prompt_llm_params(
    temperature       => 0.7,   # Controls randomness
    top_p             => 0.9,   # Nucleus sampling threshold
    barge_confidence  => 0.6,   # ASR confidence to interrupt
    presence_penalty  => 0.0,   # Penalizes token repetition
    frequency_penalty => 0.0,   # Penalizes frequent word usage
);

# Set different parameters for the post-prompt
$self->set_post_prompt_llm_params(
    temperature => 0.3,    # Lower temperature for consistent summaries
    top_p       => 0.95,   # Slightly wider token selection
);
```

**Common Use Cases:**

- **Customer Service**: Low temperature (0.2-0.4) for consistent, professional responses
- **Creative Tasks**: Higher temperature (0.7-0.9) for varied, creative outputs
- **Technical Support**: Very low temperature (0.1-0.3) with high confidence for accuracy
- **General Assistant**: Medium temperature (0.5-0.7) for balanced interaction

For detailed information about each parameter and advanced tuning strategies, see [LLM Parameters Guide](llm_parameters.md).

## Dynamic Agent Configuration

Dynamic agent configuration allows you to configure agents per-request based on parameters from the HTTP request (query parameters, body data, headers). This enables patterns like multi-tenant applications, A/B testing, personalization, and localization.

### Overview

There are two main approaches to agent configuration:

#### Static Configuration (Traditional)
```perl
package StaticAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Configuration happens once at startup
    $self->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
    $self->set_params({ end_of_speech_timeout => 500 });
    $self->prompt_add_section('Role', 'You are a customer service agent.');
    $self->set_global_data({ service_level => 'standard' });
}

1;
```

**Pros**: Simple, fast, predictable
**Cons**: Same behavior for all users, requires separate agents for different configurations

#### Dynamic Configuration (New)
```perl
package DynamicAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # No static configuration - set up dynamic callback instead
    $self->set_dynamic_config_callback(sub {
        my ($query_params, $body_params, $headers, $agent) = @_;

        # Configuration happens fresh for each request
        my $tier = $query_params->{tier} // 'standard';

        if ($tier eq 'premium') {
            $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
            $agent->set_params({ end_of_speech_timeout => 300 });  # Faster
            $agent->prompt_add_section('Role', 'You are a premium customer service agent.');
            $agent->set_global_data({ service_level => 'premium' });
        }
        else {
            $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
            $agent->set_params({ end_of_speech_timeout => 500 });  # Standard
            $agent->prompt_add_section('Role', 'You are a customer service agent.');
            $agent->set_global_data({ service_level => 'standard' });
        }
    });
}

1;
```

**Pros**: Highly flexible, single agent serves multiple configurations, enables advanced use cases
**Cons**: Slightly more complex, configuration overhead per request

### Setting Up Dynamic Configuration

Use the `set_dynamic_config_callback()` method to register a callback function that will be called for each request:

```perl
package MyDynamicAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Register the dynamic configuration callback.
    # The callback is invoked for every request to configure the agent.
    # Its arguments are:
    #   $query_params - hashref of query string parameters from the URL
    #   $body_params  - hashref of parsed JSON body from POST requests
    #   $headers      - hashref of HTTP headers from the request
    #   $agent        - the agent instance to configure
    $self->set_dynamic_config_callback(sub {
        my ($query_params, $body_params, $headers, $agent) = @_;

        # Your dynamic configuration logic here
    });
}

1;
```

The callback function receives four parameters:
- **query_params**: Dictionary of URL query parameters
- **body_params**: Dictionary of parsed JSON body (empty for GET requests)
- **headers**: Dictionary of HTTP headers
- **agent**: The agent instance to configure dynamically

### Dynamic Configuration Methods

The `agent` parameter in your callback is the actual agent instance, allowing you to use all the same configuration methods you would use during initialization:

#### Language Configuration
```perl
# Add languages with voice configuration
$agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
$agent->add_language(name => 'Spanish', code => 'es-ES', voice => 'rime.spore:mistv2');
```

#### Prompt Building
```perl
# Add prompt sections
$agent->prompt_add_section('Role', 'You are a helpful assistant.');
$agent->prompt_add_section('Guidelines', '',
    bullets => [
        'Be professional and courteous',
        'Provide accurate information',
        'Ask clarifying questions when needed',
    ],
);

# Set raw prompt text
$agent->set_prompt_text('You are a specialized AI assistant...');

# Set post-prompt for summary
$agent->set_post_prompt('Summarize the key points of this conversation.');
```

#### AI Parameters
```perl
# Configure AI behavior
$agent->set_params({
    end_of_speech_timeout  => 300,
    attention_timeout      => 20000,
    background_file_volume => -30,
});
```

#### Global Data
```perl
# Set data available to the AI
$agent->set_global_data({
    customer_tier    => 'premium',
    features_enabled => ['advanced_support', 'priority_queue'],
    session_info     => { start_time => '2024-01-01T00:00:00Z' },
});

# Update existing global data
$agent->update_global_data({ additional_info => 'value' });
```

#### Speech Recognition Hints
```perl
# Add hints for better speech recognition
$agent->add_hints(['SignalWire', 'SWML', 'API', 'technical']);
$agent->add_pronunciation('API', 'A P I');
```

#### Function Configuration
```perl
# Set native functions
$agent->set_native_functions(['transfer', 'hangup']);

# Add function includes
$agent->add_function_include({
    url       => 'https://api.example.com/functions',
    functions => ['get_account_info', 'update_profile'],
});
```

### Request Data Access

Your callback function receives detailed information about the incoming request:

#### Query Parameters
```perl
sub configure_agent_dynamically {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Extract query parameters
    my $tier        = $query_params->{tier}     // 'standard';
    my $language    = $query_params->{language} // 'en';
    my $customer_id = $query_params->{customer_id};
    my $debug       = lc($query_params->{debug} // '') eq 'true';

    # Use parameters for configuration
    if ($tier eq 'premium') {
        $agent->set_params({ end_of_speech_timeout => 300 });
    }

    if ($customer_id) {
        $agent->set_global_data({ customer_id => $customer_id });
    }
}

# Request: GET /agent?tier=premium&language=es&customer_id=12345&debug=true
```

#### POST Body Parameters
```perl
sub configure_agent_dynamically {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Extract from POST body
    my $user_profile = $body_params->{user_profile} // {};
    my $preferences  = $body_params->{preferences}  // {};

    # Configure based on profile
    if (($user_profile->{language} // '') eq 'es') {
        $agent->add_language(name => 'Spanish', code => 'es-ES', voice => 'rime.spore:mistv2');
    }

    if (($preferences->{voice_speed} // '') eq 'fast') {
        $agent->set_params({ end_of_speech_timeout => 200 });
    }
}

# Request: POST /agent with JSON body:
# {
#   "user_profile": {"language": "es", "region": "mx"},
#   "preferences": {"voice_speed": "fast", "tone": "formal"}
# }
```

#### HTTP Headers
```perl
sub configure_agent_dynamically {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Extract headers
    my $user_agent = $headers->{'user-agent'}      // '';
    my $auth_token = $headers->{authorization}     // '';
    my $locale     = $headers->{'accept-language'} // 'en-US';

    # Configure based on headers
    if (index(lc($user_agent), 'mobile') >= 0) {
        $agent->set_params({ end_of_speech_timeout => 400 });  # Longer for mobile
    }

    if ($locale =~ /^es/) {
        $agent->add_language(name => 'Spanish', code => 'es-ES', voice => 'rime.spore:mistv2');
    }
}
```

### Configuration Examples

#### Simple Multi-Tenant Configuration
```perl
sub configure_agent_dynamically {
    my ($query_params, $body_params, $headers, $agent) = @_;
    my $tenant = $query_params->{tenant} // 'default';

    # Tenant-specific configuration
    if ($tenant eq 'healthcare') {
        $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
        $agent->prompt_add_section('Compliance',
            'Follow HIPAA guidelines and maintain patient confidentiality.');
        $agent->set_global_data({
            industry         => 'healthcare',
            compliance_level => 'hipaa',
        });
    }
    elsif ($tenant eq 'finance') {
        $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
        $agent->prompt_add_section('Compliance',
            'Follow financial regulations and protect sensitive data.');
        $agent->set_global_data({
            industry         => 'finance',
            compliance_level => 'pci',
        });
    }
}
```

#### Language and Localization
```perl
sub configure_agent_dynamically {
    my ($query_params, $body_params, $headers, $agent) = @_;
    my $language = $query_params->{language} // 'en';
    my $region   = $query_params->{region}   // 'us';

    # Configure language and voice
    if ($language eq 'es') {
        if ($region eq 'mx') {
            $agent->add_language(name => 'Spanish (Mexico)', code => 'es-MX', voice => 'rime.spore:mistv2');
        }
        else {
            $agent->add_language(name => 'Spanish', code => 'es-ES', voice => 'rime.spore:mistv2');
        }
        $agent->prompt_add_section('Language', 'Respond in Spanish.');
    }
    elsif ($language eq 'fr') {
        $agent->add_language(name => 'French', code => 'fr-FR', voice => 'rime.alois');
        $agent->prompt_add_section('Language', 'Respond in French.');
    }
    else {
        $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
    }

    # Regional customization
    my $currency = $region eq 'us' ? 'USD' : $region eq 'eu' ? 'EUR' : 'MXN';
    $agent->set_global_data({
        language => $language,
        region   => $region,
        currency => $currency,
    });
}
```

#### A/B Testing Configuration
```perl
sub configure_agent_dynamically {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Determine test group (could be from query param, user ID hash, etc.)
    my $test_group = $query_params->{test_group} // 'A';

    if ($test_group eq 'A') {
        # Control group - standard configuration
        $agent->set_params({ end_of_speech_timeout => 500 });
        $agent->prompt_add_section('Style', 'Use a standard conversational approach.');
        $agent->set_global_data({ test_group => 'A', features => ['basic'] });
    }
    else {
        # Test group B - experimental features
        $agent->set_params({ end_of_speech_timeout => 300 });
        $agent->prompt_add_section('Style',
            'Use an enhanced, more interactive conversational approach.');
        $agent->set_global_data({ test_group => 'B', features => ['basic', 'enhanced'] });
    }
}
```

#### Customer Tier-Based Configuration
```perl
sub configure_agent_dynamically {
    my ($query_params, $body_params, $headers, $agent) = @_;
    my $customer_id = $query_params->{customer_id};
    my $tier        = $query_params->{tier} // 'standard';

    # Base configuration
    $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');

    # Tier-specific configuration
    my @features;
    if ($tier eq 'enterprise') {
        $agent->set_params({
            end_of_speech_timeout => 200,    # Fastest response
            attention_timeout     => 30000,  # Longest attention span
        });
        $agent->prompt_add_section('Service Level',
            'You provide white-glove enterprise support with priority handling.');
        @features = ('all_features', 'dedicated_support', 'custom_integration');
    }
    elsif ($tier eq 'premium') {
        $agent->set_params({
            end_of_speech_timeout => 300,
            attention_timeout     => 20000,
        });
        $agent->prompt_add_section('Service Level',
            'You provide premium support with enhanced features.');
        @features = ('premium_features', 'priority_support');
    }
    else {
        $agent->set_params({
            end_of_speech_timeout => 500,
            attention_timeout     => 15000,
        });
        $agent->prompt_add_section('Service Level',
            'You provide standard customer support.');
        @features = ('basic_features');
    }

    # Set global data
    my $global_data = { tier => $tier, features => \@features };
    $global_data->{customer_id} = $customer_id if $customer_id;
    $agent->set_global_data($global_data);
}
```

### Use Cases

#### Multi-Tenant SaaS Applications
Perfect for SaaS platforms where each customer needs different agent behavior:

```text
# Different tenants get different capabilities
# /agent?tenant=acme&industry=healthcare
# /agent?tenant=globex&industry=finance
```

Benefits:
- Single agent deployment serves all customers
- Tenant-specific branding and behavior
- Industry-specific compliance and terminology
- Custom feature sets per subscription level

#### A/B Testing and Experimentation
Test different agent configurations with real users:

```text
# Split traffic between different configurations
# /agent?test_group=A  (control)
# /agent?test_group=B  (experimental)
```

Benefits:
- Compare agent performance metrics
- Test new features with subset of users
- Gradual rollout of improvements
- Data-driven optimization

#### Personalization and User Preferences
Adapt agent behavior to individual user preferences:

```text
# Personalized based on user profile
# /agent?user_id=123&voice_speed=fast&formality=casual
```

Benefits:
- Improved user experience
- Accessibility support (voice speed, etc.)
- Cultural and linguistic adaptation
- Learning from user interactions

#### Geographic and Cultural Localization
Adapt to different regions and cultures:

```text
# Location-based configuration
# /agent?country=mx&language=es&timezone=America/Mexico_City
```

Benefits:
- Local language and dialect support
- Cultural appropriateness
- Regional business practices
- Time zone aware responses

### Migration Guide

#### Converting Static Agents to Dynamic

**Step 1: Move Configuration to Callback**

Before (Static):
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Static configuration
    $self->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
    $self->set_params({ end_of_speech_timeout => 500 });
    $self->prompt_add_section('Role', 'You are a helpful assistant.');
    $self->set_global_data({ version => '1.0' });
}

1;
```

After (Dynamic):
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Set up dynamic configuration
    $self->set_dynamic_config_callback(sub {
        my ($query_params, $body_params, $headers, $agent) = @_;

        # Same configuration, but now dynamic
        $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
        $agent->set_params({ end_of_speech_timeout => 500 });
        $agent->prompt_add_section('Role', 'You are a helpful assistant.');
        $agent->set_global_data({ version => '1.0' });
    });
}

1;
```

**Step 2: Add Parameter-Based Logic**

```perl
$self->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Start with base configuration
    $agent->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
    $agent->prompt_add_section('Role', 'You are a helpful assistant.');

    # Add parameter-based customization
    my $timeout = int($query_params->{timeout} // 500);
    $agent->set_params({ end_of_speech_timeout => $timeout });

    my $version = $query_params->{version} // '1.0';
    $agent->set_global_data({ version => $version });
});
```

**Step 3: Test Both Approaches**

You can support both static and dynamic patterns during migration:

```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

has use_dynamic => ( is => 'ro', default => sub { 0 } );

sub BUILD {
    my ($self) = @_;

    if ($self->use_dynamic) {
        $self->set_dynamic_config_callback(sub {
            my ($query_params, $body_params, $headers, $agent) = @_;
            # New dynamic configuration
            # ... dynamic config logic
        });
    }
    else {
        # Keep static configuration for backward compatibility
        $self->_setup_static_config;
    }
}

sub _setup_static_config {
    my ($self) = @_;
    # Original static configuration
    $self->add_language(name => 'English', code => 'en-US', voice => 'rime.spore:mistv2');
    # ... rest of static config
}

1;
```

### Best Practices

#### Performance Considerations

1. **Keep Callbacks Lightweight**
```perl
$self->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Good: Simple parameter extraction and configuration
    my $tier = $query_params->{tier} // 'standard';
    $agent->set_params($TIER_CONFIGS{$tier});

    # Avoid: Heavy computation or external API calls
    # my $customer_data = expensive_api_call($customer_id);  # Don't do this
});
```

2. **Cache Configuration Data**
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

has tier_configs => (
    is      => 'ro',
    default => sub {
        {
            basic      => { end_of_speech_timeout => 500 },
            premium    => { end_of_speech_timeout => 300 },
            enterprise => { end_of_speech_timeout => 200 },
        };
    },
);

sub BUILD {
    my ($self) = @_;
    $self->set_dynamic_config_callback(sub {
        my ($query_params, $body_params, $headers, $agent) = @_;
        my $tier = $query_params->{tier} // 'basic';
        $agent->set_params($self->tier_configs->{$tier});
    });
}

1;
```

3. **Use Default Values**
```perl
$self->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Always provide defaults
    my $language = $query_params->{language} // 'en';
    my $tier     = $query_params->{tier}     // 'standard';

    # Handle invalid values gracefully
    $language = 'en' unless grep { $_ eq $language } qw(en es fr);
});
```

#### Security Considerations

1. **Validate Input Parameters**
```perl
$self->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Validate and sanitize inputs
    my $tier = $query_params->{tier} // 'standard';
    $tier = 'basic' unless grep { $_ eq $tier } qw(basic premium enterprise);  # Safe default

    # Validate numeric parameters, clamping to a reasonable range
    my $timeout = $query_params->{timeout};
    $timeout = ($timeout && $timeout =~ /^\d+$/) ? $timeout : 500;  # Safe default
    $timeout = 100  if $timeout < 100;
    $timeout = 2000 if $timeout > 2000;
});
```

2. **Protect Sensitive Configuration**
```perl
$self->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Don't expose internal configuration via parameters
    # Bad: $agent->set_global_data({ api_key => $query_params->{api_key} });

    # Good: Use internal mapping for call-related data only
    my $customer_id = $query_params->{customer_id};
    if ($customer_id && $self->is_valid_customer($customer_id)) {
        # Store call-related customer info, NOT sensitive credentials
        $agent->set_global_data({
            customer_id   => $customer_id,
            customer_tier => $self->get_customer_tier($customer_id),
            account_type  => 'premium',
        });
    }
});
```

3. **Rate Limiting for Complex Configurations**
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

has _config_cache => ( is => 'ro', default => sub { {} } );

# Cache expensive lookups
sub get_customer_config {
    my ($self, $customer_id) = @_;
    return $self->_config_cache->{$customer_id}
        //= $self->database->get_customer_settings($customer_id);
}

sub BUILD {
    my ($self) = @_;
    $self->set_dynamic_config_callback(sub {
        my ($query_params, $body_params, $headers, $agent) = @_;
        my $customer_id = $query_params->{customer_id};
        if ($customer_id) {
            $agent->set_global_data($self->get_customer_config($customer_id));
        }
    });
}

1;
```

#### Error Handling

1. **Graceful Degradation**
```perl
$self->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Try custom configuration; fall back on failure
    my $ok = eval {
        $self->apply_custom_config($query_params, $agent);
        1;
    };
    unless ($ok) {
        # Log error but don't fail the request
        warn "config_error: $@";

        # Fall back to default configuration
        $self->apply_default_config($agent);
    }
});
```

2. **Configuration Validation**
```perl
$self->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    # Validate required parameters
    unless ($query_params->{tenant}) {
        $agent->set_global_data({ error => 'Missing tenant parameter' });
        return;
    }

    # Validate configuration makes sense
    my $language = $query_params->{language} // 'en';
    my $region   = $query_params->{region}   // 'us';

    if ($language eq 'es' && $region eq 'us') {
        # Adjust for Spanish speakers in US
        $agent->add_language(name => 'Spanish (US)', code => 'es-US', voice => 'rime.spore:mistv2');
    }
});
```

Dynamic agent configuration enables sophisticated, multi-tenant AI applications while maintaining the familiar AgentBase API. Start with simple parameter-based configuration and gradually add more complex logic as your use cases evolve.

## Advanced Features

### Debug Events

The debug events system provides real-time visibility into what the AI module is doing during a call. When enabled, the module POSTs structured JSON events to your agent throughout the call lifecycle — session start/end, barge interruptions, LLM errors, step changes, and more.

#### Basic Setup

```perl
my $agent = SignalWire::Agent::AgentBase->new(name => 'my_agent');
$agent->enable_debug_events;  # That's it — events are auto-logged
$agent->serve;
```

With just `enable_debug_events`, every debug event is logged through the agent's structured logger. No other configuration is needed — the SDK automatically:
- Registers a `/debug_events` endpoint on the agent
- Sets `debug_webhook_url` and `debug_webhook_level` in the SWML params
- Logs each incoming event with its type and payload

#### Custom Event Handler

To act on specific events (alerting, metrics, custom logging), register a handler:

```perl
my $agent = SignalWire::Agent::AgentBase->new(name => 'my_agent');
$agent->enable_debug_events;

$agent->on_debug_event(sub {
    my ($event_type, $data) = @_;
    my $call_id = $data->{call_id};

    if ($event_type eq 'barge') {
        printf "[%s] Caller interrupted after %sms\n", $call_id, $data->{barge_elapsed_ms};
    }
    elsif ($event_type eq 'llm_error') {
        printf "[%s] LLM error: %s\n", $call_id, $data->{event};
        alert_ops_team($data);
    }
    elsif ($event_type eq 'session_end') {
        my $duration = ($data->{duration_ms} // 0) / 1000;
        printf "[%s] Call ended after %.1fs — reason: %s\n", $call_id, $duration, $data->{reason};
    }
});

$agent->serve;
```

The handler is called for every event in addition to the default structured logging.

#### Verbosity Levels

- **Level 1** (default): High-level events — session start/end, barge, errors, step changes, hold, filler, gather flow, action processing
- **Level 2+**: Adds high-volume events — every LLM request/response, conversation history additions

```perl
$agent->enable_debug_events(2);  # Include LLM request/response events
```

For the complete list of event types and their payloads, see the [API Reference](api_reference.md#debug-events).

### Session Lifecycle Hooks

SignalWire provides special SWAIG functions that are automatically called at specific points during a voice session's lifecycle. These hooks enable you to perform initialization tasks when a call starts and cleanup tasks when a call ends.

#### Overview

Session lifecycle hooks are special SWAIG functions that SignalWire calls automatically:
- `startup_hook`: Called immediately when a new voice session begins
- `hangup_hook`: Called when a voice session ends (regardless of how it ended)

These hooks are particularly useful for:
- Initializing session state or resources
- Loading user preferences or history
- Logging session start/end events
- Cleaning up temporary resources
- Saving session data for analytics

#### Implementation

To implement lifecycle hooks, define them as regular SWAIG functions with these specific names:

```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';
use SignalWire::SWAIG::FunctionResult;
use POSIX qw(strftime);

sub BUILD {
    my ($self) = @_;

    $self->define_tool(
        name        => 'startup_hook',
        description => 'Called when the voice session starts',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ($args, $raw_data) = @_;

            # Extract session information
            my $call_id     = $raw_data->{call_id};
            my $from_number = $raw_data->{from_number};
            my $to_number   = $raw_data->{to_number};

            # Log session start
            print "Session started: $call_id from $from_number\n";

            # Carry per-call data forward via global_data (durable state should
            # go to external storage keyed by $call_id — see the notes below)
            return SignalWire::SWAIG::FunctionResult->new('Session initialized successfully')
                ->update_global_data({
                    session_start     => strftime('%Y-%m-%dT%H:%M:%S', localtime),
                    from              => $from_number,
                    to                => $to_number,
                    interaction_count => 0,
                });
        },
    );

    $self->define_tool(
        name        => 'hangup_hook',
        description => 'Called when the voice session ends',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ($args, $raw_data) = @_;

            # Extract session information
            my $call_id = $raw_data->{call_id};

            # Retrieve any persisted session data (e.g. from external storage)
            my $state = $self->load_session_state($call_id);

            if ($state) {
                # Log session metrics
                print "Session ended: $call_id\n";
                print "Interactions: " . ($state->{interaction_count} // 0) . "\n";

                # Clean up state (optional - SignalWire cleans up automatically)
                $self->delete_session_state($call_id);
            }

            return SignalWire::SWAIG::FunctionResult->new('Session cleanup completed');
        },
    );
}

1;
```

#### Common Use Cases

##### 1. User Preference Loading
```perl
$self->define_tool(
    name        => 'startup_hook',
    description => 'Called when the voice session starts',
    parameters  => { type => 'object', properties => {} },
    handler     => sub {
        my ($args, $raw_data) = @_;
        my $caller_id = $raw_data->{from_number};

        # Load user preferences from database
        my $preferences = $self->load_user_preferences($caller_id);

        # Carry the loaded preferences forward for quick access
        return SignalWire::SWAIG::FunctionResult->new('User preferences loaded')
            ->update_global_data({
                user_preferences => $preferences,
                language         => $preferences->{language} // 'en-US',
                previous_orders  => $preferences->{recent_orders} // [],
            });
    },
);
```

##### 2. Analytics and Logging
```perl
$self->define_tool(
    name        => 'hangup_hook',
    description => 'Called when the voice session ends',
    parameters  => { type => 'object', properties => {} },
    handler     => sub {
        my ($args, $raw_data) = @_;
        my $call_id = $raw_data->{call_id};
        my $state   = $self->load_session_state($call_id);

        # Send analytics data
        my $analytics_data = {
            call_id          => $call_id,
            duration         => $state->{duration},
            functions_called => $state->{functions_called} // [],
            outcome          => $state->{outcome} // 'unknown',
        };

        # Post to analytics service
        $self->send_to_analytics($analytics_data);

        return SignalWire::SWAIG::FunctionResult->new('Analytics data sent');
    },
);
```

#### Important Notes

1. **Function Names**: The hooks must be named exactly `startup_hook` and `hangup_hook` for SignalWire to call them
2. **Error Handling**: Always implement proper error handling in hooks - failures shouldn't crash the voice session
3. **Timing**: `startup_hook` is called before the AI starts speaking to the caller
4. **Session Data**: Any data you need to persist across the session should be stored in external storage (Redis, database, etc.)
5. **Return Values**: Both hooks must return a `SignalWire::SWAIG::FunctionResult` object

### SIP Routing

SIP routing allows your agents to receive voice calls via SIP addresses. The SDK supports both individual agent-level routing and centralized server-level routing.

#### Individual Agent SIP Routing

Enable SIP routing on a single agent:

```perl
# Enable SIP routing with automatic username mapping based on agent name
$agent->enable_sip_routing(auto_map => 1);

# Register additional SIP usernames for this agent
$agent->register_sip_username('support_agent');
$agent->register_sip_username('help_desk');
```

When `auto_map=True`, the agent automatically registers SIP usernames based on:
- The agent's name (e.g., `support@domain`)
- The agent's route path (e.g., `/support` becomes `support@domain`)
- Common variations (e.g., removing vowels for shorter dialing)

#### Server-Level SIP Routing (Multi-Agent)

For multi-agent setups, centralized routing is more efficient:

```perl
use SignalWire::Server::AgentServer;

# Create an AgentServer
my $server = SignalWire::Server::AgentServer->new(host => '0.0.0.0', port => 3000);

# Register multiple agents
$server->register($registration_agent);  # Route: /register
$server->register($support_agent);       # Route: /support

# Set up central SIP routing
$server->setup_sip_routing(route => '/sip', auto_map => 1);

# Register additional SIP username mappings
$server->register_sip_username('signup', '/register');    # signup@domain -> registration agent
$server->register_sip_username('help',   '/support');     # help@domain -> support agent
```

With server-level routing:
- Each agent is reachable via its name (when `auto_map=True`)
- Additional SIP usernames can be mapped to specific agent routes
- All SIP routing is handled at a single endpoint (`/sip` by default)

#### How SIP Routing Works

1. A SIP call comes in with a username (e.g., `support@yourdomain`)
2. The SDK extracts the username part (`support`)
3. The system checks if this username is registered:
   - In individual routing: The current agent checks its own username list
   - In server routing: The server checks its central mapping table
4. If a match is found, the call is routed to the appropriate agent

### Custom Routing

You can dynamically handle requests to different paths using routing callbacks:

```perl
# Enable custom routing in BUILD or anytime after construction.
# register_routing_callback takes the path first, then the callback coderef.
$self->register_routing_callback('/customer', sub {
    my ($request, $body) = @_;

    # Process customer-related requests.
    #   $request - the request object
    #   $body    - parsed JSON body as a hashref
    # Return a URL string to redirect to, or undef to process normally.

    my $customer_id = $body->{customer_id};

    # You can redirect to another agent/service if needed
    if ($customer_id && $customer_id =~ /^vip-/) {
        return "/vip-handler/$customer_id";
    }

    # Or return undef to process the request with on_swml_request
    return undef;
});
```

Then override `on_swml_request` to customize the SWML for the routed path:

```perl
# Customize SWML based on the route in on_swml_request.
#   $request_data - the request body data
#   $callback_path - the path that triggered the routing callback
sub on_swml_request {
    my ($self, $request_data, $callback_path) = @_;

    if (defined $callback_path && $callback_path eq '/customer') {
        # Serve customer-specific content
        return {
            sections => {
                main => [
                    { answer => {} },
                    { play   => { url => 'say:Welcome to customer service!' } },
                ],
            },
        };
    }

    # Other path handling...
    return undef;
}
```

### Customizing SWML Requests

You can modify the SWML document based on request data by overriding the `on_swml_request` method:

```perl
# Customize the SWML document based on request data.
#   $request_data  - the request data (body for POST or query params for GET)
#   $callback_path - the path that triggered the routing callback
# Return a hashref with modifications to apply to the document, or undef.
sub on_swml_request {
    my ($self, $request_data, $callback_path) = @_;

    if ($request_data && exists $request_data->{caller_type}) {
        # Example: change the AI behavior based on caller type
        if ($request_data->{caller_type} eq 'vip') {
            return {
                sections => {
                    main => [
                        # Keep the first verb (answer), modify the AI verb params
                        {
                            ai => {
                                params => {
                                    wait_for_user         => JSON::false,
                                    end_of_speech_timeout => 500,  # More responsive
                                },
                            },
                        },
                    ],
                },
            };
        }
    }

    # You can also use the callback_path to serve different content per route
    if (defined $callback_path && $callback_path eq '/customer') {
        return {
            sections => {
                main => [
                    { answer => {} },
                    { play   => { url => 'say:Welcome to our customer service line.' } },
                ],
            },
        };
    }

    # Return undef to use the default document
    return undef;
}
```

### Conversation Summary Handling

Process conversation summaries:

```perl
# Register a summary handler. The callback receives:
#   $summary  - the summary (hashref/string) or undef if none was found
#   $raw_data - the complete raw POST data from the request
$agent->on_summary(sub {
    my ($summary, $raw_data) = @_;
    if ($summary) {
        # Log the summary
        require JSON;
        print 'conversation_summary: ' . JSON::encode_json($summary) . "\n";

        # Save the summary to a database, send notifications, etc.
        # ...
    }
});
```

### Custom Webhook URLs

You can override the default webhook URLs for SWAIG functions and post-prompt delivery:

```perl
# In your agent initialization or setup code:

# Override the webhook URL for all SWAIG functions
$agent->set_web_hook_url('https://external-service.example.com/handle-swaig');

# Override the post-prompt delivery URL
$agent->set_post_prompt_url('https://analytics.example.com/conversation-summaries');

# These methods allow you to:
# 1. Send function calls to external services instead of handling them locally
# 2. Send conversation summaries to analytics services or other systems
# 3. Use special URLs with pre-configured authentication
```

## Prefab Agents

Prefab agents are pre-configured agent implementations designed for specific use cases. They provide ready-to-use functionality with customization options, saving development time and ensuring consistent patterns.

### Built-in Prefabs

The SDK includes several built-in prefab agents:

#### InfoGathererAgent

Collects structured information from users:

```perl
use SignalWire::Prefabs::InfoGatherer;

my $agent = SignalWire::Prefabs::InfoGatherer->new(
    name      => 'info-gatherer',
    route     => '/info-gatherer',
    questions => [
        { field => 'full_name', question_text => 'What is your full name?' },
        { field => 'email',     question_text => 'What is your email address?' },
        { field => 'reason',    question_text => 'How can I help you today?' },
    ],
);

$agent->serve(host => '0.0.0.0', port => 8000);
```

#### FAQBotAgent

Answers questions from a predefined FAQ knowledge base:

```perl
use SignalWire::Prefabs::FAQBot;

my $agent = SignalWire::Prefabs::FAQBot->new(
    name    => 'knowledge-base',
    route   => '/knowledge-base',
    persona => "I'm a product documentation assistant.",
    faqs    => [
        { question => 'What is SignalWire?', answer => 'A communications platform with voice, video, and messaging APIs.' },
        { question => 'What is SWML?',        answer => 'SignalWire Markup Language, for defining communications workflows.' },
    ],
    suggest_related => 1,
);

$agent->serve(host => '0.0.0.0', port => 8000);
```

#### Concierge

Provides virtual concierge services for a venue — answering questions about
services, amenities, and hours of operation:

```perl
use SignalWire::Prefabs::Concierge;

my $agent = SignalWire::Prefabs::Concierge->new(
    name       => 'concierge',
    route      => '/concierge',
    venue_name => 'Oceanview Resort',
    services   => ['room service', 'spa bookings', 'restaurant reservations'],
    amenities  => {
        'infinity pool' => {
            hours       => '7:00 AM - 10:00 PM',
            location    => 'Main Level, Ocean View',
            description => 'Heated infinity pool overlooking the ocean.',
        },
    },
    welcome_message => 'Welcome to Oceanview Resort. How can I help you today?',
);

$agent->serve(host => '0.0.0.0', port => 8000);
```

#### SurveyAgent

Conducts structured surveys with different question types:

```perl
use SignalWire::Prefabs::Survey;

my $agent = SignalWire::Prefabs::Survey->new(
    name             => 'satisfaction-survey',
    route            => '/survey',
    survey_name      => 'Customer Satisfaction',
    introduction     => "We'd like to know about your recent experience with our product.",
    survey_questions => [
        {
            id       => 'satisfaction',
            text     => 'On a scale of 1-5, how satisfied are you with our product?',
            type     => 'rating',
            required => 1,
        },
        {
            id       => 'feedback',
            text     => 'Do you have any specific feedback about how we can improve?',
            type     => 'open_ended',
            required => 0,
        },
    ],
);

$agent->serve(host => '0.0.0.0', port => 8000);
```

#### ReceptionistAgent

Handles call routing and department transfers:

```perl
use SignalWire::Prefabs::Receptionist;

my $agent = SignalWire::Prefabs::Receptionist->new(
    name        => 'acme-receptionist',
    route       => '/reception',
    departments => [
        { name => 'sales',   description => 'For product inquiries and pricing', number => '+15551235555' },
        { name => 'support', description => 'For technical assistance',          number => '+15551236666' },
        { name => 'billing', description => 'For payment and invoice questions',  number => '+15551237777' },
    ],
    greeting => 'Thank you for calling ACME Corp. How may I direct your call?',
    voice    => 'rime.spore:mistv2',
);

$agent->serve(host => '0.0.0.0', port => 8000);
```

### Creating Your Own Prefabs

You can create your own prefab agents by extending `AgentBase` or any existing prefab. Custom prefabs can be created directly within your project or packaged as reusable libraries.

#### Basic Prefab Structure

A well-designed prefab should:

1. Extend `AgentBase` or another prefab
2. Take configuration parameters in the constructor
3. Apply configuration to set up the agent
4. Provide appropriate default values
5. Include domain-specific tools

Example of a custom support agent prefab:

```perl
package CustomerSupportAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';
use SignalWire::SWAIG::FunctionResult;

# Custom configuration attributes
has product_name        => ( is => 'ro', required => 1 );
has knowledge_base_path => ( is => 'ro', default  => sub { undef } );
has support_email       => ( is => 'ro', default  => sub { undef } );
has escalation_path     => ( is => 'ro', default  => sub { undef } );

sub BUILD {
    my ($self) = @_;

    # Configure prompt
    $self->prompt_add_section('Personality',
        'I am a customer support agent for ' . $self->product_name . '.');
    $self->prompt_add_section('Goal', 'Help customers solve their problems effectively.');

    # Add standard instructions
    $self->_configure_instructions;

    # Register default tools if appropriate paths are configured
    $self->register_knowledge_base_tool if $self->knowledge_base_path;

    # Register domain-specific tools
    $self->define_tool(
        name        => 'escalate_issue',
        description => 'Escalate a customer issue to a human agent',
        parameters  => {
            type       => 'object',
            properties => {
                issue_summary  => { type => 'string', description => 'Brief summary of the issue' },
                customer_email => { type => 'string', description => "Customer's email address" },
            },
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            # Implementation...
            return SignalWire::SWAIG::FunctionResult->new('Issue escalated successfully.');
        },
    );

    $self->define_tool(
        name        => 'send_support_email',
        description => 'Send a follow-up email to the customer',
        parameters  => {
            type       => 'object',
            properties => {
                customer_email   => { type => 'string' },
                issue_summary    => { type => 'string' },
                resolution_steps => { type => 'string' },
            },
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            # Implementation...
            return SignalWire::SWAIG::FunctionResult->new('Follow-up email sent successfully.');
        },
    );
}

# Configure standard instructions based on settings
sub _configure_instructions {
    my ($self) = @_;
    my @instructions = (
        'Be professional but friendly.',
        "Verify the customer's identity before sharing account details.",
    );
    if ($self->escalation_path) {
        push @instructions, 'For complex issues, offer to escalate to ' . $self->escalation_path . '.';
    }
    $self->prompt_add_section('Instructions', '', bullets => \@instructions);
}

# Register the knowledge base search tool if configured
sub register_knowledge_base_tool {
    my ($self) = @_;
    # Implementation...
}

1;
```

#### Using the Custom Prefab

```perl
# Create an instance of the custom prefab
my $support_agent = CustomerSupportAgent->new(
    product_name        => 'SignalWire Voice API',
    knowledge_base_path => './product_docs',
    support_email       => 'support@example.com',
    escalation_path     => 'tier 2 support',
    name                => 'voice-support',
    route               => '/voice-support',
);

# Start the agent
$support_agent->serve(host => '0.0.0.0', port => 8000);
```

#### Customizing Existing Prefabs

You can also extend and customize the built-in prefabs:

```perl
package EnhancedGatherer;
use Moo;
extends 'SignalWire::Prefabs::InfoGatherer';
use SignalWire::SWAIG::FunctionResult;

sub BUILD {
    my ($self) = @_;

    # Add an additional instruction
    $self->prompt_add_section('Instructions', '',
        bullets => ['Verify all information carefully.']);

    # Add an additional custom tool
    $self->define_tool(
        name        => 'check_customer',
        description => 'Check customer status in database',
        parameters  => {
            type       => 'object',
            properties => { email => { type => 'string' } },
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            # Implementation...
            return SignalWire::SWAIG::FunctionResult->new('Customer status: Active');
        },
    );
}

1;
```

### Best Practices for Prefab Design

1. **Clear Documentation**: Document the purpose, parameters, and extension points
2. **Sensible Defaults**: Provide working defaults that make sense for the use case
3. **Error Handling**: Implement robust error handling with helpful messages
4. **Modular Design**: Keep prefabs focused on a specific use case
5. **Consistent Interface**: Maintain consistent patterns across related prefabs
6. **Extension Points**: Provide clear ways for others to extend your prefab
7. **Configuration Options**: Make all key behaviors configurable

### Making Prefabs Distributable

To create distributable prefabs that can be used across multiple projects:

1. **Package Structure**: Create a proper Perl distribution (a `cpanfile`/`Makefile.PL` with your modules under `lib/`)
2. **Documentation**: Include clear usage examples (POD in each module)
3. **Configuration**: Support both code and file-based configuration
4. **Testing**: Include tests for your prefab (under `t/`)
5. **Publishing**: Publish to CPAN or share via GitHub

Example distribution structure:

```text
My-Prefab-Agents/
├── README.md
├── cpanfile
├── Makefile.PL
├── examples/
│   └── support_agent_example.pl
├── t/
│   └── support.t
└── lib/
    └── My/Prefab/Agents/
        ├── Support.pm
        ├── Retail.pm
        └── Utils/
            └── KnowledgeBase.pm
```

## API Reference

### Constructor Parameters

- `name`: Agent name/identifier (required)
- `route`: HTTP route path (default: "/")
- `host`: Host to bind to (default: "0.0.0.0")
- `port`: Port to bind to (default: 3000)
- `basic_auth`: Optional `[username, password]` arrayref
- `use_pom`: Whether to use POM for prompts (default: true)
- `token_expiry_secs`: Security token expiry time (default: 3600)
- `auto_answer`: Auto-answer calls (default: true)
- `record_call`: Record calls (default: false)
- `schema_path`: Optional path to schema.json file
- `suppress_logs`: Whether to suppress structured logs (default: False)

### Prompt Methods

- `prompt_add_section($title, $body, bullets => [...], numbered => 0, numbered_bullets => 0)`
- `prompt_add_subsection($parent_title, $title, body => ..., bullets => [...])`
- `prompt_add_to_section($title, body => ..., bullet => ..., bullets => [...])`
- `set_prompt_text($prompt_text)`
- `set_post_prompt($prompt_text)`

### SWAIG Methods

- `define_tool(name => ..., description => ..., parameters => {...}, handler => sub {...}, secure => 1, fillers => {...})`
- `set_native_functions($arrayref)`
- `add_function_include({ url => ..., functions => [...], meta_data => {...} })`

### Configuration Methods

- `add_hint($hint)` and `add_hints($arrayref)`
- `add_pattern_hint({ hint => ..., pattern => ..., replace => ..., ignore_case => 0 })`
- `add_pronunciation($replace, $with_text, ignore_case => 0)`
- `add_language(name => ..., code => ..., voice => ..., speech_fillers => [...], function_fillers => [...], engine => ..., model => ...)`
- `set_param($key, $value)` and `set_params($hashref)`
- `set_global_data($hashref)` and `update_global_data($hashref)`

### SIP Routing Methods

- `enable_sip_routing(auto_map => 1, path => '/sip')`: Enable SIP routing for an agent
- `register_sip_username($sip_username)`: Register a SIP username for an agent
- `auto_map_sip_usernames()`: Automatically register SIP usernames based on agent attributes

#### AgentServer SIP Methods

- `setup_sip_routing(route => '/sip', auto_map => 1)`: Set up central SIP routing for a server
- `register_sip_username($username, $route)`: Map a SIP username to an agent route

### Service Methods

- `serve(host => ..., port => ...)` / `run`: Start the web server (auto-detects the deployment environment)
- `psgi_app()`: Return a PSGI coderef for this agent (use with any Plack handler)
- `on_swml_request($request_data, $callback_path)`: Customize SWML based on request data and path
- `on_summary($summary, $raw_data)` or `on_summary(sub {...})`: Handle post-prompt summaries
- `on_function_call($name, $args, $raw_data)`: Process SWAIG function calls
- `register_routing_callback($path, $callback_fn)`: Register a callback for custom path routing
- `set_web_hook_url($url)`: Override the default web_hook_url with a supplied URL string
- `set_post_prompt_url($url)`: Override the default post_prompt_url with a supplied URL string

### Endpoint Methods

The SDK provides several endpoints for different purposes:

- Root endpoint (`/`): Serves the main SWML document
- SWAIG endpoint (`/swaig`): Handles SWAIG function calls
- Post-prompt endpoint (`/post_prompt`): Processes conversation summaries
- Debug endpoint (`/debug`): Serves the SWML document with debug headers
- Debug events endpoint (`/debug_events`): Receives real-time debug events from the AI module (see [Debug Events](#debug-events))
- SIP routing endpoint (configurable, default `/sip`): Handles SIP routing requests

## Testing

The SignalWire AI Agent SDK provides a `swaig-test` CLI tool (in `bin/swaig-test`) that lets you exercise a SWAIG agent's tools and inspect its generated SWML without deploying it. It can load an agent from a local file (`--file`) or hit a running agent over HTTP (`--url`).

### Local Agent Testing

Test your agents locally before deployment:

```bash
# List available functions in a local agent file
swaig-test --file examples/my_agent.pl --list-tools

# Execute a SWAIG function (pass arguments as key=value pairs)
swaig-test --file examples/my_agent.pl --exec get_weather --param location="New York"

# Generate the SWML document the agent would serve
swaig-test --file examples/my_agent.pl --dump-swml
```

### Testing a Running Agent Over HTTP

Point `swaig-test` at a live endpoint (basic-auth credentials can be embedded in the URL):

```bash
# Dump the SWML served by a running agent
swaig-test --url http://user:pass@localhost:3000/ --dump-swml

# List its tools
swaig-test --url http://user:pass@localhost:3000/ --list-tools

# Execute a tool against the live agent
swaig-test --url http://user:pass@localhost:3000/ --exec get_weather --param location=London

# Pretty-print the raw SWML JSON
swaig-test --url http://user:pass@localhost:3000/ --dump-swml --raw | jq '.'
```

### Testing Best Practices

1. **Test locally first**: Use `--file` to exercise the agent before deploying it
2. **Verify the SWML**: `--dump-swml` shows exactly what the platform will receive
3. **Exercise each tool**: Run `--exec` for every SWAIG function with representative `--param` values
4. **Use verbose mode**: Enable `--verbose` for detailed request/response tracing

For more detailed testing documentation, see the [CLI Guide](cli_guide.md).

## Examples

### Simple Question-Answering Agent

```perl
package SimpleAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';
use SignalWire::SWAIG::FunctionResult;
use POSIX qw(strftime);

sub BUILD {
    my ($self) = @_;

    # Configure agent personality
    $self->prompt_add_section('Personality', 'You are a friendly and helpful assistant.');
    $self->prompt_add_section('Goal', 'Help users with basic tasks and answer questions.');
    $self->prompt_add_section('Instructions', '',
        bullets => [
            'Be concise and direct in your responses.',
            "If you don't know something, say so clearly.",
            'Use the get_time function when asked about the current time.',
        ],
    );

    $self->define_tool(
        name        => 'get_time',
        description => 'Get the current time',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ($args, $raw_data) = @_;
            my $formatted_time = strftime('%H:%M:%S', localtime);
            return SignalWire::SWAIG::FunctionResult->new("The current time is $formatted_time");
        },
    );
}

1;

package main;

my $agent = SimpleAgent->new(name => 'simple', route => '/simple');
print "Starting agent server...\n";
print "Note: Works in any deployment mode (server/CGI/Lambda)\n";
$agent->run;
```

### Multi-Language Customer Service Agent

```perl
package CustomerServiceAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';
use SignalWire::SWAIG::FunctionResult;

sub BUILD {
    my ($self) = @_;

    # Configure agent personality
    $self->prompt_add_section('Personality',
        'You are a helpful customer service representative for SignalWire.');
    $self->prompt_add_section('Knowledge',
        'You can answer questions about SignalWire products and services.');
    $self->prompt_add_section('Instructions', '',
        bullets => [
            'Greet customers politely',
            'Answer questions about SignalWire products',
            'Use check_account_status when customer asks about their account',
            'Use create_support_ticket for unresolved issues',
        ],
    );

    # Add language support
    $self->add_language(
        name             => 'English',
        code             => 'en-US',
        voice            => 'en-US-Neural2-F',
        speech_fillers   => ['Let me think...', 'One moment please...'],
        function_fillers => ["I'm looking that up...", 'Let me check that...'],
    );

    $self->add_language(
        name           => 'Spanish',
        code           => 'es',
        voice          => 'rime.spore:multilingual',
        speech_fillers => ['Un momento por favor...', 'Estoy pensando...'],
    );

    # Enable languages
    $self->set_params({ languages_enabled => JSON::true });

    # Add company information
    $self->set_global_data({
        company_name  => 'SignalWire',
        support_hours => '9am-5pm ET, Monday through Friday',
        support_email => 'support@signalwire.com',
    });

    $self->define_tool(
        name        => 'check_account_status',
        description => "Check the status of a customer's account",
        parameters  => {
            type       => 'object',
            properties => {
                account_id => { type => 'string', description => "The customer's account ID" },
            },
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            my $account_id = $args->{account_id};
            # In a real implementation, this would query a database
            return SignalWire::SWAIG::FunctionResult->new("Account $account_id is in good standing.");
        },
    );

    $self->define_tool(
        name        => 'create_support_ticket',
        description => 'Create a support ticket for an unresolved issue',
        parameters  => {
            type       => 'object',
            properties => {
                issue    => { type => 'string', description => 'Brief description of the issue' },
                priority => {
                    type        => 'string',
                    description => 'Ticket priority',
                    enum        => ['low', 'medium', 'high', 'critical'],
                },
            },
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            my $issue    = $args->{issue}    // '';
            my $priority = $args->{priority} // 'medium';

            # Generate a ticket ID (in a real system, this would create a database entry)
            my $ticket_id = sprintf 'TICKET-%04d', (unpack('%32C*', $issue) % 10000);

            return SignalWire::SWAIG::FunctionResult->new(
                "Support ticket $ticket_id has been created with $priority priority. "
                . 'A support representative will contact you shortly.'
            );
        },
    );
}

1;

package main;

my $agent = CustomerServiceAgent->new(name => 'customer-service', route => '/support');
print "Starting customer service agent...\n";
print "Note: Works in any deployment mode (server/CGI/Lambda)\n";
$agent->run;
```

### Dynamic Agent Configuration Examples

For working examples of dynamic agent configuration, see these files in the `examples` directory:

- **`simple_static_agent.pl`**: Traditional static configuration approach
- **`simple_dynamic_agent.pl`**: Same agent but using dynamic configuration
- **`simple_dynamic_enhanced.pl`**: Enhanced version that actually uses request parameters
- **`comprehensive_dynamic_agent.pl`**: Advanced multi-tier, multi-industry dynamic agent
- **`custom_path_agent.pl`**: Dynamic agent with custom routing path
- **`multi_agent_server.pl`**: Multiple specialized dynamic agents on one server

These examples demonstrate the progression from static to dynamic configuration and show real-world use cases like multi-tenant applications, A/B testing, and personalization.

For more examples, see the `examples` directory in the SignalWire AI Agent SDK repository.

To build a search index from this guide (see the Native Vector Search skill above):

```bash
# Build index from the comprehensive concepts guide
sw-search docs/agent_guide.md --output concepts.swsearch

# Build from multiple sources
sw-search docs/agent_guide.md examples README.md --output comprehensive.swsearch

# Traditional directory approach with custom settings
sw-search ./knowledge \
    --output knowledge.swsearch \
    --file-types md,txt,pdf \
    --chunking-strategy sentence \
    --max-sentences-per-chunk 8 \
    --verbose
```