# SignalWire AI Agents SDK - Complete API Reference

This document provides a comprehensive reference for all public APIs in the SignalWire AI Agents SDK.

## Table of Contents

1. [AgentBase Class](#agentbase-class) - Core agent functionality
2. [SwaigFunctionResult Class](#swaigfunctionresult-class) - SWAIG (SignalWire AI Gateway) function response handling
3. [DataMap Class](#datamap-class) - Serverless API tools that execute on SignalWire's servers
4. [Context System](#context-system) - Structured workflows
5. [State Management](#state-management) - Persistent state
6. [Skills System](#skills-system) - Modular capabilities
7. [Utility Classes](#utility-classes) - Supporting classes

---

## AgentBase Class

The `AgentBase` class is the foundation for creating AI agents. It extends `SignalWire::SWML::Service` (the base class for generating SWML -- SignalWire Markup Language -- documents) and provides comprehensive functionality for building conversational AI agents. Agents are `Moo` packages that `extends 'SignalWire::Agent::AgentBase'` and configure themselves in `BUILD`.

### Constructor

Construct an agent with `SignalWire::Agent::AgentBase->new(...)` (or, from a subclass, `MyAgent->new(...)`). Constructor options are passed as `key => value` pairs:

```perl
use SignalWire::Agent::AgentBase;
my $agent = SignalWire::Agent::AgentBase->new(
    name          => 'my-agent',
    route         => '/',
    host          => '0.0.0.0',
    port          => 3000,
    use_pom       => 1,
    auto_answer   => 1,
    record_call   => 0,
    record_format => 'mp4',
    record_stereo => 1,
);
```

**Parameters:**
- `name` (Str): Human-readable name for the agent
- `route` (Str): HTTP route path for the agent (default: "/")
- `host` (Str): Host address to bind to (default: "0.0.0.0")
- `port` (Int): Port number to listen on (default: 3000, or `$ENV{PORT}`)
- `basic_auth_user` / `basic_auth_password` (Str): Username/password for HTTP basic auth (auto-generated when not set)
- `use_pom` (Bool): Whether to use Prompt Object Model (default: 1)
- `auto_answer` (Bool): Automatically answer incoming calls (default: 1)
- `record_call` (Bool): Record calls by default (default: 0)
- `record_format` (Str): Recording format: "mp4", "wav", "mp3" (default: "mp4")
- `record_stereo` (Bool): Record in stereo (default: 1)

See the [Configuration Guide](configuration.md) for details on JSON configuration files with environment-variable substitution.

### Core Methods

#### Deployment and Execution

##### `run(%opts)`
Auto-detects deployment environment and runs the agent appropriately. Accepts optional `host` / `port` overrides (and, for serverless dispatch, `event` / `context` / `mode`). Delegates to `serve` for the HTTP-server case.

**Parameters:**
- `host` (Str): Override host address
- `port` (Int): Override port number
- `event` / `context`: Event/context objects for serverless environments
- `mode` (Str): Force a specific mode: "server", "lambda", "cgi", "cloud_function"

**Usage:**
```perl
# Auto-detect / run the HTTP server
$agent->run;

# Override host and port
$agent->run( host => 'localhost', port => 8080 );

# Serverless dispatch (CGI / Lambda / Cloud Functions)
$agent->handle_serverless_request( event => $event, context => $context );
```

##### `serve(%opts)`
Explicitly run as an HTTP server using Plack/PSGI.

**Parameters:**
- `host` (Str): Host address to bind to
- `port` (Int): Port number to listen on

**Usage:**
```perl
$agent->serve;                              # Use constructor defaults
$agent->serve( host => '0.0.0.0', port => 3000 );
```

### Prompt Configuration

#### Text-Based Prompts

##### `set_prompt_text($text)`
Set the agent's prompt as raw text. Returns `$self` for chaining.

**Parameters:**
- `$text` (Str): The complete prompt text

**Usage:**
```perl
$agent->set_prompt_text('You are a helpful customer service agent.');
```

##### `set_post_prompt($text)`
Set additional text to append after the main prompt. Returns `$self` for chaining.

**Parameters:**
- `$text` (Str): Text to append after main prompt

**Usage:**
```perl
$agent->set_post_prompt('Always be polite and professional.');
```

#### LLM Parameter Configuration

##### `set_prompt_llm_params`

```perl
$agent->set_prompt_llm_params( %params );
```
Set Language Model parameters for the main prompt. Accepts any parameters which will be passed through to the SignalWire server. The server validates and applies parameters based on the target model's capabilities. Returns `$self` for chaining.

**Common Parameters:**
- `temperature`: Controls randomness. Lower = more focused
- `top_p`: Nucleus sampling threshold
- `barge_confidence`: ASR confidence to interrupt
- `presence_penalty`: Topic diversity control
- `frequency_penalty`: Repetition control

Note: No defaults are sent unless explicitly set. Invalid parameters for the selected model will be handled/ignored by the server.

**Usage:**
```perl
# Configure for consistent, professional responses
$agent->set_prompt_llm_params(
    temperature       => 0.3,
    top_p             => 0.9,
    barge_confidence  => 0.7,
    presence_penalty  => 0.1,
    frequency_penalty => 0.2,
);
```

##### `set_post_prompt_llm_params`

```perl
$agent->set_post_prompt_llm_params( %params );
```
Set Language Model parameters for the post-prompt. Accepts any parameters which will be passed through to the SignalWire server. The server validates and applies parameters based on the target model's capabilities. Returns `$self` for chaining.

**Common Parameters:**
- `temperature`: Controls randomness. Lower = more focused
- `top_p`: Nucleus sampling threshold
- `presence_penalty`: Topic diversity control
- `frequency_penalty`: Repetition control

Note: barge_confidence is not applicable to post-prompt. No defaults are sent unless explicitly set.

**Usage:**
```perl
# Configure for focused summaries
$agent->set_post_prompt_llm_params(
    temperature => 0.2,
    top_p       => 0.9,
);
```

#### Structured Prompts (POM)

##### `prompt_add_section`

```perl
$agent->prompt_add_section( $title, $body, bullets => \@bullets );
```
Add a structured section to the prompt using Prompt Object Model. `$title` and `$body` are positional; `bullets` is an optional named argument. Returns `$self` for chaining.

**Parameters:**
- `$title` (Str): Section title/heading
- `$body` (Str): Main section content (optional)
- `bullets` (ArrayRef[Str]): List of bullet points

**Usage:**
```perl
# Simple section
$agent->prompt_add_section( 'Role', 'You are a customer service representative.' );

# Section with bullets
$agent->prompt_add_section(
    'Guidelines',
    'Follow these principles:',
    bullets => [ 'Be helpful', 'Stay professional', 'Listen carefully' ],
);

# Section describing a process
$agent->prompt_add_section(
    'Process',
    'Follow these steps:',
    bullets => [ 'Greet the customer', 'Identify their need', 'Provide solution' ],
);
```

##### `prompt_add_to_section`

```perl
$agent->prompt_add_to_section( $title, body => $body, bullets => \@bullets );
```
Add content to an existing prompt section (auto-creating it when absent). `$title` is positional; `body` and `bullets` are named arguments. Returns `$self` for chaining.

**Parameters:**
- `$title` (Str): Title of the section to modify
- `body` (Str): Additional body text to append
- `bullets` (ArrayRef[Str]): Bullet points to add

**Usage:**
```perl
# Add body text to an existing section
$agent->prompt_add_to_section( 'Guidelines', body => 'Remember to always verify customer identity.' );

# Add a single bullet
$agent->prompt_add_to_section( 'Process', bullets => ['Document the interaction'] );

# Add multiple bullets
$agent->prompt_add_to_section( 'Process', bullets => [ 'Follow up', 'Close ticket' ] );
```

##### `prompt_add_subsection`

```perl
$agent->prompt_add_subsection( $parent_title, $title, $body, bullets => \@bullets );
```
Add a subsection to an existing prompt section (auto-creating the parent when absent). `$parent_title`, `$title`, and `$body` are positional; `bullets` is a named argument. Returns `$self` for chaining.

**Parameters:**
- `$parent_title` (Str): Title of parent section
- `$title` (Str): Subsection title
- `$body` (Str): Subsection content (optional)
- `bullets` (ArrayRef[Str]): Subsection bullet points

**Usage:**
```perl
$agent->prompt_add_subsection(
    'Guidelines',
    'Escalation Rules',
    'Escalate when:',
    bullets => [ 'Customer is angry', 'Technical issue beyond scope' ],
);
```

### Voice and Language Configuration

##### `add_language`

```perl
$agent->add_language(
    name  => $name,
    code  => $code,
    voice => $voice,
    # optional: speech_fillers, function_fillers, engine, model, params
);
```
Configure voice and language settings for the agent. All arguments are named (`key => value`). Returns `$self` for chaining.

**Parameters:**
- `name` (Str): Human-readable language name
- `code` (Str): Language code (e.g., "en-US", "es-ES")
- `voice` (Str): Voice identifier (e.g., "rime.spore", "nova.luna")
- `speech_fillers` (ArrayRef[Str]): Filler phrases during speech processing
- `function_fillers` (ArrayRef[Str]): Filler phrases during function execution
- `engine` (Str): TTS engine to use
- `model` (Str): AI model to use

**Usage:**
```perl
# Basic language setup
$agent->add_language( name => 'English', code => 'en-US', voice => 'rime.spore' );

# With custom fillers
$agent->add_language(
    name             => 'English',
    code             => 'en-US',
    voice            => 'nova.luna',
    speech_fillers   => [ 'Let me think...', 'One moment...' ],
    function_fillers => [ 'Processing...', 'Looking that up...' ],
);
```

##### `set_languages($languages)`
Set multiple language configurations at once. Returns `$self` for chaining.

**Parameters:**
- `$languages` (ArrayRef[HashRef]): List of language configuration hashrefs

**Usage:**
```perl
$agent->set_languages([
    { name => 'English', code => 'en-US', voice => 'rime.spore' },
    { name => 'Spanish', code => 'es-ES', voice => 'nova.luna' },
]);
```

### Speech Recognition Configuration

##### `add_hint($hint)`
Add a single speech recognition hint. Returns `$self` for chaining.

**Parameters:**
- `$hint` (Str): Word or phrase to improve recognition accuracy

**Usage:**
```perl
$agent->add_hint('SignalWire');
```

##### `add_hints($hints)`
Add multiple speech recognition hints. Returns `$self` for chaining.

**Parameters:**
- `$hints` (ArrayRef[Str]): List of words/phrases for better recognition

**Usage:**
```perl
$agent->add_hints([ 'SignalWire', 'SWML', 'API', 'webhook', 'SIP' ]);
```

##### `add_pattern_hint($config)`
Add a pattern-based hint for speech recognition. Takes a single hashref with `hint`, `pattern`, `replace`, and optional `ignore_case`. Returns `$self` for chaining.

**Parameters (hashref keys):**
- `hint` (Str): The hint phrase
- `pattern` (Str): Regex pattern to match
- `replace` (Str): Replacement text
- `ignore_case` (Bool): Case-insensitive matching (default: false)

**Usage:**
```perl
$agent->add_pattern_hint({
    hint    => 'phone number',
    pattern => '(\d{3})-(\d{3})-(\d{4})',
    replace => '(\1) \2-\3',
});
```

##### `add_pronunciation`

```perl
$agent->add_pronunciation( replace => $text, with => $replacement, ignore_case => 0 );
```
Add a pronunciation rule for text-to-speech. All arguments are named. Returns `$self` for chaining.

**Parameters:**
- `replace` (Str): Text to replace
- `with` (Str): Replacement pronunciation
- `ignore_case` (Bool): Case-insensitive replacement (default: false)

**Usage:**
```perl
$agent->add_pronunciation( replace => 'API',  with => 'A P I' );
$agent->add_pronunciation( replace => 'SWML', with => 'swim-el' );
```

##### `set_pronunciations($pronunciations)`
Set multiple pronunciation rules at once. Returns `$self` for chaining.

**Parameters:**
- `$pronunciations` (ArrayRef[HashRef]): List of pronunciation rule hashrefs

**Usage:**
```perl
$agent->set_pronunciations([
    { replace => 'API',  with => 'A P I' },
    { replace => 'SWML', with => 'swim-el', ignore_case => 1 },
]);
```

### AI Parameters Configuration

##### `set_param($key, $value)`
Set a single AI parameter. Returns `$self` for chaining.

**Parameters:**
- `$key` (Str): Parameter name
- `$value` (Any): Parameter value

**Usage:**
```perl
$agent->set_param( 'ai_model', 'gpt-4.1-nano' );
$agent->set_param( 'end_of_speech_timeout', 500 );
```

##### `set_params($params)`
Set multiple AI parameters at once (merged with existing). Returns `$self` for chaining.

**Parameters:**
- `$params` (HashRef): Hashref of parameter key-value pairs

**Common Parameters:**
- `ai_model`: AI model to use ("gpt-4.1-nano", "gpt-4.1-mini", etc.)
- `end_of_speech_timeout`: Milliseconds to wait for speech end (default: 1000)
- `attention_timeout`: Milliseconds before attention timeout (default: 30000)
- `background_file_volume`: Volume for background audio (-60 to 0 dB)
- `temperature`: AI creativity/randomness (0.0 to 2.0)
- `max_tokens`: Maximum response length
- `top_p`: Nucleus sampling parameter (0.0 to 1.0)

**Usage:**
```perl
$agent->set_params({
    ai_model               => 'gpt-4.1-nano',
    end_of_speech_timeout  => 500,
    attention_timeout      => 15000,
    background_file_volume => -20,
    temperature            => 0.7,
});
```

### Global Data Management

##### `set_global_data($data)`
Set global data available to the AI and functions. Returns `$self` for chaining.

**Parameters:**
- `$data` (HashRef): Global data hashref

**Usage:**
```perl
$agent->set_global_data({
    company_name      => 'Acme Corp',
    support_hours     => '9 AM - 5 PM EST',
    escalation_number => '+1-555-0123',
});
```

##### `update_global_data($data)`
Update existing global data (merge with existing). Returns `$self` for chaining.

**Parameters:**
- `$data` (HashRef): Data to merge with existing global data

**Usage:**
```perl
$agent->update_global_data({
    current_promotion => '20% off all services',
    promotion_expires => '2024-12-31',
});
```

### Function Definition

##### `define_tool`

```perl
$self->define_tool(
    name        => $name,
    description => $description,
    parameters  => $parameters,   # JSON-schema hashref
    handler     => sub { my ( $args, $raw_data ) = @_; ... },
    # optional: secure, fillers, webhook_url, and any additional SWAIG fields
);
```
Define a custom SWAIG function/tool. All arguments are named (`key => value`). Returns `$self` for chaining. Any extra `key => value` pairs beyond the recognized ones are passed through as additional SWAIG function properties.

**Parameters:**
- `name` (Str): Function name
- `description` (Str): Function description for the AI
- `parameters` (HashRef): JSON schema for function parameters
- `handler` (CodeRef): Anonymous sub to execute when called; receives `($args, $raw_data)` and returns a `SignalWire::SWAIG::FunctionResult`
- `secure` (Bool): Require a security token (default: true)
- `fillers` (HashRef): Language-specific filler phrases
- `webhook_url` (Str): Custom webhook URL

**Usage:**
```perl
$self->define_tool(
    name        => 'get_weather',
    description => 'Get current weather for a location',
    parameters  => {
        type       => 'object',
        properties => {
            location => {
                type        => 'string',
                description => 'City name',
            },
        },
        required => ['location'],
    },
    handler => sub {
        my ( $args, $raw_data ) = @_;
        require SignalWire::SWAIG::FunctionResult;
        my $location = $args->{location} // 'Unknown';
        return SignalWire::SWAIG::FunctionResult->new(
            "The weather in $location is sunny and 75\x{b0}F" );
    },
    fillers => { 'en-US' => [ 'Checking weather...', 'Looking up forecast...' ] },
);
```

Because Perl has no method decorators, tools are registered by calling `define_tool` (typically inside `BUILD`) rather than by annotating a method. The handler is an anonymous sub that closes over the agent when needed.

**Usage (in a Moo agent subclass):**
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    $self->define_tool(
        name        => 'get_time',
        description => 'Get current time',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ( $args, $raw_data ) = @_;
            require SignalWire::SWAIG::FunctionResult;
            return SignalWire::SWAIG::FunctionResult->new( 'Current time: ' . localtime );
        },
    );
}

1;
```

##### `register_swaig_function($function_hash)`
Register a pre-built SWAIG function hashref (for example, one produced by `DataMap->to_swaig_function`). Returns `$self` for chaining.

**Parameters:**
- `$function_hash` (HashRef): Complete SWAIG function definition

**Usage:**
```perl
use SignalWire::DataMap;
# Register a DataMap tool
my $weather_tool = SignalWire::DataMap->new('get_weather')
    ->webhook( 'GET', 'https://api.weather.com/...' );
$agent->register_swaig_function( $weather_tool->to_swaig_function );
```

### Session Lifecycle Hooks

SignalWire AI agents support special SWAIG functions that are automatically called at specific points in the conversation lifecycle:

##### `startup_hook`
Called when a new conversation/call begins. Register it as a tool named `startup_hook`.

**Implementation:**
```perl
$self->define_tool(
    name        => 'startup_hook',
    description => 'Called when a new conversation starts to initialize state',
    parameters  => { type => 'object', properties => {} },
    handler     => sub {
        my ( $args, $raw_data ) = @_;
        require SignalWire::SWAIG::FunctionResult;
        my $call_id = $raw_data->{call_id};
        # Initialize session resources, load user data, etc.
        return SignalWire::SWAIG::FunctionResult->new('Session initialized');
    },
);
```

##### `hangup_hook`
Called when a conversation/call ends. Register it as a tool named `hangup_hook`.

**Implementation:**
```perl
$self->define_tool(
    name        => 'hangup_hook',
    description => 'Called when conversation ends to clean up resources',
    parameters  => { type => 'object', properties => {} },
    handler     => sub {
        my ( $args, $raw_data ) = @_;
        require SignalWire::SWAIG::FunctionResult;
        my $call_id = $raw_data->{call_id};
        # Clean up resources, save session data, etc.
        return SignalWire::SWAIG::FunctionResult->new('Session ended');
    },
);
```

**Common Use Cases:**
- Loading user preferences at session start
- Initializing session-specific resources
- Logging conversation metrics
- Cleaning up temporary data
- Saving conversation summaries

### Skills System

##### `add_skill`

```perl
$agent->add_skill( $skill_name, $params );
```
Add a modular skill to the agent. `$params` is an optional configuration hashref. Returns `$self` for chaining.

**Parameters:**
- `$skill_name` (Str): Name of the skill to add
- `$params` (HashRef): Skill configuration parameters (optional)

**Available Skills:**
- `datetime`: Current date/time information
- `math`: Mathematical calculations
- `web_search`: Google Custom Search integration
- `datasphere`: SignalWire DataSphere search
- `native_vector_search`: Local document search

**Usage:**
```perl
# Simple skill
$agent->add_skill('datetime');
$agent->add_skill('math');

# Skill with configuration
$agent->add_skill('web_search', {
    api_key          => 'your-google-api-key',
    search_engine_id => 'your-search-engine-id',
    num_results      => 3,
});

# Multiple instances with different names
$agent->add_skill('web_search', {
    api_key          => 'your-api-key',
    search_engine_id => 'general-engine',
    tool_name        => 'search_general',
});

$agent->add_skill('web_search', {
    api_key          => 'your-api-key',
    search_engine_id => 'news-engine',
    tool_name        => 'search_news',
});
```

##### `remove_skill($skill_name)`
Remove a skill from the agent. Returns `$self` for chaining.

**Parameters:**
- `$skill_name` (Str): Name of skill to remove

**Usage:**
```perl
$agent->remove_skill('web_search');
```

##### `list_skills()`
Get the list of currently added skills.

**Returns:**
- ArrayRef[Str]: Names of active skills

**Usage:**
```perl
my $active_skills = $agent->list_skills;
print "Active skills: @$active_skills\n";
```

##### `has_skill($skill_name)`
Check whether a skill is currently added.

**Parameters:**
- `$skill_name` (Str): Name of skill to check

**Returns:**
- Bool: true if the skill is active

**Usage:**
```perl
if ( $agent->has_skill('web_search') ) {
    print "Web search is available\n";
}
```

### Native Functions

##### `set_native_functions($function_names)`
Enable specific native SWML functions. Returns `$self` for chaining.

**Parameters:**
- `$function_names` (ArrayRef[Str]): List of native function names to enable

**Available Native Functions:**
- `transfer`: Transfer calls
- `hangup`: End calls
- `play`: Play audio files
- `record`: Record audio
- `send_sms`: Send SMS messages

**Usage:**
```perl
$agent->set_native_functions([ 'transfer', 'hangup', 'send_sms' ]);
```

##### `set_internal_fillers($internal_fillers)`
Set custom filler phrases for internal/native SWAIG functions. Returns `$self` for chaining.

**Parameters:**
- `$internal_fillers` (HashRef): Function name → language code → filler-phrases arrayref

**Available Internal Functions:**
- `next_step`: Moving between workflow steps (contexts system)
- `change_context`: Switching contexts in workflows  
- `check_time`: Getting current time
- `wait_for_user`: Waiting for user input
- `wait_seconds`: Pausing for specified duration
- `get_visual_input`: Processing visual data

**Usage:**
```perl
$agent->set_internal_fillers({
    next_step => {
        'en-US' => [ 'Moving to the next step...', "Let's continue..." ],
        'es'    => [ 'Pasando al siguiente paso...', 'Continuemos...' ],
    },
    check_time => {
        'en-US' => [ 'Let me check the time...', 'Getting current time...' ],
    },
});
```

##### `add_internal_filler($function_name, $language_code, $fillers)`
Add internal fillers for a specific function and language. Returns `$self` for chaining.

**Parameters:**
- `$function_name` (Str): Name of the internal function
- `$language_code` (Str): Language code (e.g., "en-US", "es", "fr")
- `$fillers` (ArrayRef[Str]): List of filler phrases

**Usage:**
```perl
$agent->add_internal_filler( 'next_step', 'en-US', [
    "Great! Let's move to the next step...",
    'Perfect! Moving forward...',
]);
```

### Function Includes

##### `add_function_include($include)`
Include external SWAIG functions from another service. Takes a single hashref with `url`, `functions`, and optional `meta_data`. Returns `$self` for chaining.

**Parameters (hashref keys):**
- `url` (Str): URL of external SWAIG service
- `functions` (ArrayRef[Str]): List of function names to include
- `meta_data` (HashRef): Additional metadata

**Usage:**
```perl
$agent->add_function_include({
    url       => 'https://external-service.com/swaig',
    functions => [ 'external_function1', 'external_function2' ],
    meta_data => { service => 'external', version => '1.0' },
});
```

##### `set_function_includes($includes)`
Set multiple function includes at once. Returns `$self` for chaining.

**Parameters:**
- `$includes` (ArrayRef[HashRef]): List of function-include configurations

**Usage:**
```perl
$agent->set_function_includes([
    {
        url       => 'https://service1.com/swaig',
        functions => [ 'func1', 'func2' ],
    },
    {
        url       => 'https://service2.com/swaig',
        functions => ['func3'],
        meta_data => { priority => 'high' },
    },
]);
```

### Webhook Configuration

##### `set_web_hook_url($url)`
Set the default webhook URL for SWAIG functions. Returns `$self` for chaining.

**Parameters:**
- `$url` (Str): Default webhook URL

**Usage:**
```perl
$agent->set_web_hook_url('https://myserver.com/webhook');
```

##### `set_post_prompt_url($url)`
Set the URL for post-prompt processing. Returns `$self` for chaining.

**Parameters:**
- `$url` (Str): Post-prompt webhook URL

**Usage:**
```perl
$agent->set_post_prompt_url('https://myserver.com/post-prompt');
```

##### `add_swaig_query_params(%params)`
Add query parameters to be included in all SWAIG webhook URLs. Arguments are named (`key => value`). Returns `$self` for chaining.

This is useful for preserving dynamic-configuration state across SWAIG callbacks. For example, if your dynamic config adds skills based on query parameters, you can pass those same parameters through to the SWAIG webhook so the same configuration is applied.

**Parameters:**
- `%params`: Query-parameter key-value pairs

**Usage:**
```perl
# In a dynamic config callback, preserve configuration parameters
$agent->set_dynamic_config_callback( sub {
    my ( $query_params, $body_params, $headers, $agent ) = @_;
    my $customer_id = $query_params->{customer_id};
    if ($customer_id) {
        # Pass through to SWAIG callbacks
        $agent->add_swaig_query_params( customer_id => $customer_id );
        $agent->add_skill( 'customer_lookup', { customer_id => $customer_id } );
    }
});
```

##### `clear_swaig_query_params()`
Clear all SWAIG query parameters. Returns `$self` for chaining.

**Usage:**
```perl
$agent->clear_swaig_query_params;
```

### Debug Events

##### `enable_debug_events($level)`
Enable the debug-event webhook for this agent. When enabled, the AI module will POST real-time debug events to a `/debug_events` endpoint on this agent during calls. Events are automatically logged via the agent's structured logger and can optionally be handled with a custom callback via `on_debug_event()`. Returns `$self` for chaining.

**Parameters:**
- `$level` (Int): Debug-event verbosity level. `1` = high-level events (barge, errors, session start/end, step changes). `2+` = adds high-volume events (every LLM request/response, conversation_add). Default: `1`

**Usage:**
```perl
$agent->enable_debug_events;      # level 1 (default)
$agent->enable_debug_events(2);   # include high-volume events
```

**How it works:**
- Registers a `/debug_events` POST endpoint on the agent's HTTP server
- Auto-sets `debug_webhook_url` and `debug_webhook_level` in the SWML `params` during rendering
- The URL is built automatically using the same auth/proxy logic as other webhook URLs
- No manual URL configuration needed

**Event types at level 1:**

| Event label | Description |
|-------------|-------------|
| `session_start` | AI session started (model, TTS engine, voice, language) |
| `session_end` | AI session ended (reason, duration, token counts) |
| `barge` | User interrupted AI speech (barge type, elapsed ms) |
| `step_change` | Conversation step changed |
| `context_change` | Conversation context changed |
| `llm_error` | LLM error (fatal, retry, max_retries) |
| `voice_error` | TTS voice configuration or runtime error |
| `hold` | Call placed on hold or taken off hold |
| `filler` | Filler phrase spoken (thinking or function filler) |
| `consolidation` | Token consolidation triggered |
| `process_action` | Webhook action being processed |
| `gather_start` | Gather flow started |
| `gather_complete` | Gather flow completed |

**Additional events at level 2+:**

| Event label | Description |
|-------------|-------------|
| `llm_request` | LLM API request initiated (input tokens) |
| `llm_response` | LLM API response received (duration, output tokens) |
| `conversation_add` | Entry added to conversation history |

### Call Flow Verb Insertion

These methods allow you to customize the SWML call flow by inserting verbs at different stages of the call lifecycle.

##### `add_pre_answer_verb($verb_name, $config)`
Add a verb to run before the call is answered (while still ringing). Returns `$self` for chaining.

**Safe pre-answer verbs:** `transfer`, `execute`, `return`, `label`, `goto`, `request`, `switch`, `cond`, `if`, `eval`, `set`, `unset`, `hangup`, `send_sms`, `sleep`, `stop_record_call`, `stop_denoise`, `stop_tap`

**Parameters:**
- `$verb_name` (Str): The SWML verb name
- `$config` (HashRef): Verb configuration hashref

**Usage:**
```perl
# Send SMS before answering
$agent->add_pre_answer_verb( 'send_sms', {
    to   => '+15551234567',
    from => '+15559876543',
    body => 'Incoming call from AI agent',
});

# Set variables before answer
$agent->add_pre_answer_verb( 'set', { call_start => '${system.timestamp}' } );
```

##### `add_answer_verb($config)`
Configure the answer verb that connects the call. Returns `$self` for chaining.

**Parameters:**
- `$config` (HashRef, optional): Answer-verb configuration (e.g., `{ max_duration => 3600 }`)

**Usage:**
```perl
# Set maximum call duration to 1 hour
$agent->add_answer_verb({ max_duration => 3600 });
```

##### `add_post_answer_verb($verb_name, $config)`
Add a verb to run after the call is answered but before the AI starts. Returns `$self` for chaining.

**Parameters:**
- `$verb_name` (Str): The SWML verb name (e.g., "play", "sleep")
- `$config` (HashRef): Verb configuration hashref

**Usage:**
```perl
# Play a welcome message before the AI starts
$agent->add_post_answer_verb( 'play', {
    url => 'say:Welcome to our AI assistant. This call may be recorded.',
});

# Add a brief pause
$agent->add_post_answer_verb( 'sleep', { duration => 1 } );
```

##### `add_post_ai_verb($verb_name, $config)`
Add a verb to run after the AI conversation ends. Returns `$self` for chaining.

**Parameters:**
- `$verb_name` (Str): The SWML verb name (e.g., "hangup", "transfer", "request")
- `$config` (HashRef): Verb configuration hashref

**Usage:**
```perl
# Clean hangup after the AI ends
$agent->add_post_ai_verb( 'hangup', {} );

# Transfer to a human after the AI conversation
$agent->add_post_ai_verb( 'transfer', { to => '+15551234567' } );

# Log call completion
$agent->add_post_ai_verb( 'request', {
    url    => 'https://myserver.com/call-complete',
    method => 'POST',
});
```

##### `clear_pre_answer_verbs()`
Remove all pre-answer verbs. Returns `$self` for chaining.

##### `clear_post_answer_verbs()`
Remove all post-answer verbs. Returns `$self` for chaining.

##### `clear_post_ai_verbs()`
Remove all post-AI verbs. Returns `$self` for chaining.

**Method Chaining Example:**
```perl
$agent->add_pre_answer_verb( 'set', { source => 'ai_agent' } )
      ->add_answer_verb({ max_duration => 1800 })
      ->add_post_answer_verb( 'play', { url => 'say:Hello!' } )
      ->add_post_ai_verb( 'hangup', {} );
```

### Dynamic Configuration

##### `set_dynamic_config_callback($callback)`
Set a callback for per-request dynamic configuration. The callback is an anonymous sub that receives `($query_params, $headers, $body, $agent)`. Returns `$self` for chaining.

**Parameters:**
- `$callback` (CodeRef): Sub that receives `($query_params, $headers, $body, $agent)`

**Usage:**
```perl
$agent->set_dynamic_config_callback( sub {
    my ( $query_params, $body_params, $headers, $agent ) = @_;

    # Configure based on the request
    if ( ( $query_params->{language} // '' ) eq 'spanish' ) {
        $agent->add_language( name => 'Spanish', code => 'es-ES', voice => 'nova.luna' );
    }

    # Set customer-specific data
    my $customer_id = $headers->{'X-Customer-ID'};
    if ($customer_id) {
        $agent->set_global_data({ customer_id => $customer_id });
    }
});
```

### SIP Integration

##### `enable_sip_routing`

```perl
$agent->enable_sip_routing( auto_map => 1, path => '/sip' );
```
Enable SIP-based routing for voice calls. Arguments are named. Returns `$self` for chaining.

**Parameters:**
- `auto_map` (Bool): Automatically map SIP usernames (default: 1)
- `path` (Str): SIP routing endpoint path (default: "/sip")

**Usage:**
```perl
$agent->enable_sip_routing;
```

##### `register_sip_username($sip_username)`
Register a specific SIP username for this agent. Returns `$self` for chaining.

**Parameters:**
- `$sip_username` (Str): SIP username to register

**Usage:**
```perl
$agent->register_sip_username('support');
$agent->register_sip_username('sales');
```

##### `register_routing_callback($path, $callback)`
Register custom routing logic for SIP calls. The callback receives the request env and parsed body and returns an agent route (or `undef`). Returns `$self` for chaining.

**Parameters:**
- `$path` (Str): Routing endpoint path (e.g., "/sip")
- `$callback` (CodeRef): Sub that returns an agent route based on the request

**Usage:**
```perl
$agent->register_routing_callback( '/sip', sub {
    my ( $request, $body ) = @_;
    my $sip_username = $body->{sip_username} // '';
    return '/support-agent' if $sip_username eq 'support';
    return '/sales-agent'   if $sip_username eq 'sales';
    return undef;
});
```

### Utility Methods

##### `get_name()`
Get the agent's name.

**Returns:**
- Str: Agent name

##### `psgi_app()`
Get the agent as a PSGI application coderef, for mounting in any Plack handler or larger PSGI application.

**Returns:**
- CodeRef: A PSGI application

**Usage:**
```perl
# Mount the agent in a larger Plack app
use Plack::Builder;

my $app = builder {
    mount '/agent' => $agent->psgi_app;
};
```

### Event Handlers

##### `on_summary`
Handle conversation summaries. This is triggered when the AI generates a summary based on your `post_prompt` configuration. Register a handler by passing an anonymous sub (`$agent->on_summary(sub { ... })`), or override `sub on_summary` in a subclass. The handler receives `($summary, $raw_data)`.

**Parameters:**
- `$summary` (HashRef): Parsed summary data (from `post_prompt_data.parsed[0]`)
- `$raw_data` (HashRef): Complete raw POST data including `post_prompt_data` with both `raw` and `parsed` fields

**Usage (callback registration):**
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Configure the post-prompt to request a JSON summary
    $self->set_post_prompt(<<'PROMPT');
Return a JSON summary of the conversation:
{
    "topic": "MAIN_TOPIC",
    "satisfied": true/false,
    "follow_up_needed": true/false,
    "key_points": ["point1", "point2"]
}
PROMPT

    # Register a summary handler
    $self->on_summary( sub {
        my ( $summary, $raw_data ) = @_;
        if ($summary) {
            my $topic     = $summary->{topic}     // 'Unknown';
            my $satisfied = $summary->{satisfied} // 0;
            print "Call about: $topic, Customer satisfied: $satisfied\n";

            # Save to database, send to CRM, trigger follow-up, etc.
            if ( $summary->{follow_up_needed} ) {
                $self->schedule_follow_up($summary);
            }
        }

        # Access the raw summary text if needed
        if ( $raw_data && $raw_data->{post_prompt_data} ) {
            my $raw_text = $raw_data->{post_prompt_data}{raw} // '';
            print "Raw summary: $raw_text\n";
        }
    });
}

1;
```

##### `on_debug_event`
Register a handler for debug webhook events. Pass an anonymous sub; requires `enable_debug_events()` to have been called first.

The handler receives:
- `$event_type` (Str): The event label (e.g. `"barge"`, `"llm_error"`, `"session_start"`)
- `$data` (HashRef): The full event payload including `call_id`, `label`, and event-specific fields

**Usage:**
```perl
use SignalWire::Agent::AgentBase;
my $agent = SignalWire::Agent::AgentBase->new( name => 'my_agent' );
$agent->enable_debug_events;

$agent->on_debug_event( sub {
    my ( $event_type, $data ) = @_;
    my $call_id = $data->{call_id};
    if ( $event_type eq 'llm_error' ) {
        print "LLM error on call $call_id: " . ( $data->{event} // '' ) . "\n";
    }
    elsif ( $event_type eq 'barge' ) {
        print "Barge after " . ( $data->{barge_elapsed_ms} // 0 ) . "ms\n";
    }
    elsif ( $event_type eq 'session_end' ) {
        print "Call ended: " . ( $data->{reason} // '' )
            . ", duration: " . ( $data->{duration_ms} // 0 ) . "ms\n";
    }
});
```

**Usage (subclass style):**
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;
    $self->enable_debug_events(2);
    $self->on_debug_event( sub {
        my ( $event_type, $data ) = @_;
        $self->alert_ops_team($data) if $event_type eq 'llm_error';
    });
}

1;
```

> **Note:** Even without registering a handler, all debug events are automatically logged via the agent's structured logger when `enable_debug_events()` is called.

##### `on_function_call($name, $args, $raw_data)`
Override in a subclass to handle function calls with custom logic. The default implementation dispatches to the handler registered via `define_tool`.

**Parameters:**
- `$name` (Str): Function name being called
- `$args` (HashRef): Function arguments
- `$raw_data` (HashRef): Raw request data

**Returns:**
- The function result (typically a `SignalWire::SWAIG::FunctionResult`)

**Usage:**
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub on_function_call {
    my ( $self, $name, $args, $raw_data ) = @_;
    if ( $name eq 'get_weather' ) {
        require SignalWire::SWAIG::FunctionResult;
        my $location = $args->{location};
        # Custom weather logic
        return SignalWire::SWAIG::FunctionResult->new("Weather in $location: Sunny");
    }
    return $self->SUPER::on_function_call( $name, $args, $raw_data );
}

1;
```

##### `on_request($request_data, $callback_path)`
Override in a subclass to handle general requests. The default implementation delegates to `on_swml_request`.

**Parameters:**
- `$request_data` (HashRef): Request data
- `$callback_path` (Str): Callback path

**Returns:**
- HashRef of response modifications, or undef for no change

##### `on_swml_request($request_data, $callback_path, $request)`
Override in a subclass to handle SWML generation requests.

**Parameters:**
- `$request_data` (HashRef): Request data
- `$callback_path` (Str): Callback path
- `$request`: The PSGI `$env` hashref (analogous to Python's request object)

**Returns:**
- HashRef of SWML modifications, or undef for no change

### Authentication

##### `validate_basic_auth($username, $password)`
Override in a subclass to implement custom basic-authentication logic.

**Parameters:**
- `$username` (Str): Username from basic auth
- `$password` (Str): Password from basic auth

**Returns:**
- Bool: true if credentials are valid

**Usage:**
```perl
package MyAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';

sub validate_basic_auth {
    my ( $self, $username, $password ) = @_;
    # Custom auth logic
    return $username eq 'admin' && $password eq 'secret';
}

1;
```

##### `get_basic_auth_credentials($include_source)`
Get basic-auth credentials from the environment or constructor. Returns a list `($user, $password)`, or `($user, $password, $source)` when `$include_source` is truthy (source is one of "provided", "environment", or "generated").

**Parameters:**
- `$include_source` (Bool): Include source information (default: false)

**Returns:**
- List: `($username, $password)` or `($username, $password, $source)`

### Context System

##### `define_contexts()`
Define structured workflow contexts for the agent. Called with no arguments it returns the `ContextBuilder` for fluent chaining.

**Returns:**
- ContextBuilder: Builder for creating contexts and steps

**Usage:**
```perl
my $contexts = $agent->define_contexts;

$contexts->add_context('greeting')
    ->add_step('welcome')
    ->set_text('Welcome! How can I help?')
    ->set_valid_steps(['menu']);

$contexts->add_context('main_menu')
    ->add_step('menu')
    ->set_text('Choose: 1) Support 2) Sales 3) Billing')
    ->set_functions([ 'transfer_to_support', 'transfer_to_sales' ]);
```

This concludes Part 1 of the API reference covering the AgentBase class. The document will continue with SwaigFunctionResult, DataMap, and other components in subsequent parts.

---

## SwaigFunctionResult Class

The `SignalWire::SWAIG::FunctionResult` class is used to create structured responses from SWAIG functions. It handles both natural-language responses and structured actions that the agent should execute. (The Python `SwaigFunctionResult` maps to Perl's `SignalWire::SWAIG::FunctionResult`.)

### Constructor

```perl
use SignalWire::SWAIG::FunctionResult;
SignalWire::SWAIG::FunctionResult->new( $response, post_process => $bool );
```

**Parameters:**
- `$response` (Str): Natural-language response text for the AI to speak (optional)
- `post_process` (Bool): Whether to let the AI take another turn before executing actions (default: false)

**Post-processing Behavior:**
- `post_process => 0` (default): Execute actions immediately after the AI response
- `post_process => 1`: Let the AI respond to the user one more time, then execute actions

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;

# Simple response
my $result = SignalWire::SWAIG::FunctionResult->new("The weather is sunny and 75\x{b0}F");

# Response with post-processing enabled
my $result2 = SignalWire::SWAIG::FunctionResult->new( "I'll transfer you now", post_process => 1 );

# Empty response (actions only)
my $result3 = SignalWire::SWAIG::FunctionResult->new;
```

### Core Methods

#### Response Configuration

##### `set_response($response)`
Set or update the natural-language response text. Returns `$self` for chaining.

**Parameters:**
- `$response` (Str): The text the AI should speak

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new;
$result->set_response('I found your order information');
```

##### `set_post_process($post_process)`
Enable or disable post-processing for this result. Returns `$self` for chaining.

**Parameters:**
- `$post_process` (Bool): true to let the AI respond once more before executing actions

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new("I'll help you with that");
$result->set_post_process(1);   # Let the AI handle follow-up questions first
```

#### Action Management

##### `add_action($name, $data)`
Add a structured action to execute. Returns `$self` for chaining.

**Parameters:**
- `$name` (Str): Action name/type (e.g., "play", "transfer", "set_global_data")
- `$data` (Any): Action data - can be a string, boolean, hashref, or arrayref

**Usage:**
```perl
# Simple action with a boolean
$result->add_action( 'hangup', JSON::true );

# Action with string data
$result->add_action( 'play', 'welcome.mp3' );

# Action with hashref data
$result->add_action( 'set_global_data', { customer_id => '12345', status => 'verified' } );

# Action with arrayref data
$result->add_action( 'send_sms', [ '+15551234567', 'Your order is ready!' ] );
```

##### `add_actions($actions)`
Add multiple actions at once. Returns `$self` for chaining.

**Parameters:**
- `$actions` (ArrayRef[HashRef]): List of action hashrefs

**Usage:**
```perl
$result->add_actions([
    { play => 'hold_music.mp3' },
    { set_global_data => { status => 'on_hold' } },
    { wait => 5000 },
]);
```

### Call Control Actions

#### Call Transfer and Connection

##### `connect($destination, %opts)`
Transfer or connect the call to another destination. Returns `$self` for chaining.

**Parameters:**
- `$destination` (Str): Phone number, SIP address, or other destination
- `final` (Bool): Permanent transfer (true) vs temporary transfer (false) (default: true)
- `from` (Str): Override caller ID

**Transfer Types:**
- `final => 1`: Permanent transfer - the call exits the agent completely
- `final => 0`: Temporary transfer - the call returns to the agent if the far end hangs up

**Usage:**
```perl
# Permanent transfer to a phone number
$result->connect( '+15551234567', final => 1 );

# Temporary transfer to a SIP address with a custom caller ID
$result->connect( 'support@company.com', final => 0, from => '+15559876543' );

# Transfer with a response
my $result = SignalWire::SWAIG::FunctionResult->new('Transferring you to our sales team');
$result->connect('sales@company.com');
```

##### `swml_transfer($dest, $ai_response, %opts)`
Create a SWML-based transfer with an AI-response setup. Returns `$self` for chaining.

**Parameters:**
- `$dest` (Str): Transfer destination
- `$ai_response` (Str): AI response when the transfer completes
- `final` (Bool): Permanent (true) vs temporary (false) transfer (default: true)

**Usage:**
```perl
$result->swml_transfer(
    '+15551234567',
    "You've been transferred back to me. How else can I help?",
);
```

##### `sip_refer($to_uri)`
Perform a SIP REFER transfer. Returns `$self` for chaining.

**Parameters:**
- `$to_uri` (Str): SIP URI to transfer to

**Usage:**
```perl
$result->sip_refer('sip:support@company.com');
```

#### Call Management

##### `hangup()`
End the call immediately. Returns `$self` for chaining.

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new('Thank you for calling. Goodbye!');
$result->hangup;
```

##### `hold($timeout)`
Put the call on hold. Returns `$self` for chaining.

**Parameters:**
- `$timeout` (Int): Hold timeout in seconds (default: 300)

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new('Please hold while I look that up');
$result->hold(60);
```

##### `stop()`
Stop current audio playback or recording. Returns `$self` for chaining.

**Usage:**
```perl
$result->stop;
```

#### Audio Control

##### `say($text)`
Add text for the AI to speak. Returns `$self` for chaining.

**Parameters:**
- `$text` (Str): Text to speak

**Usage:**
```perl
$result->say('Please wait while I process your request');
```

##### `play_background_file($filename, %opts)`
Play an audio file in the background. Returns `$self` for chaining.

**Parameters:**
- `$filename` (Str): Audio file path or URL
- `wait` (Bool): Wait for the file to finish before continuing (default: false)

**Usage:**
```perl
# Play hold music in the background
$result->play_background_file('hold_music.mp3');

# Play an announcement and wait for completion
$result->play_background_file( 'important_announcement.wav', wait => 1 );
```

##### `stop_background_file()`
Stop background audio playback. Returns `$self` for chaining.

**Usage:**
```perl
$result->stop_background_file;
```

### Data Management Actions

##### `set_global_data($data)`
Set global data for the conversation. Returns `$self` for chaining.

**Parameters:**
- `$data` (HashRef): Global data to set

**Usage:**
```perl
$result->set_global_data({
    customer_id     => '12345',
    order_status    => 'shipped',
    tracking_number => '1Z999AA1234567890',
});
```

##### `update_global_data($data)`
Update existing global data (merge with existing). Returns `$self` for chaining.

**Parameters:**
- `$data` (HashRef): Data to merge

**Usage:**
```perl
$result->update_global_data({
    last_interaction => '2024-01-15T10:30:00Z',
    agent_notes      => 'Customer satisfied with resolution',
});
```

##### `remove_global_data($keys)`
Remove specific keys from global data. Returns `$self` for chaining.

**Parameters:**
- `$keys` (Str | ArrayRef[Str]): Key name or arrayref of key names to remove

**Usage:**
```perl
# Remove a single key
$result->remove_global_data('temporary_data');

# Remove multiple keys
$result->remove_global_data([ 'temp1', 'temp2', 'cache_data' ]);
```

##### `set_metadata($data)`
Set metadata for the conversation. Returns `$self` for chaining.

**Parameters:**
- `$data` (HashRef): Metadata to set

**Usage:**
```perl
$result->set_metadata({
    call_type  => 'support',
    priority   => 'high',
    department => 'technical',
});
```

##### `remove_metadata($keys)`
Remove specific metadata keys. Returns `$self` for chaining.

**Parameters:**
- `$keys` (Str | ArrayRef[Str]): Key name or arrayref of key names to remove

**Usage:**
```perl
$result->remove_metadata([ 'temporary_flag', 'debug_info' ]);
```

### AI Behavior Control

##### `set_end_of_speech_timeout($milliseconds)`
Adjust how long to wait for speech to end. Returns `$self` for chaining.

**Parameters:**
- `$milliseconds` (Int): Timeout in milliseconds

**Usage:**
```perl
# Shorter timeout for quick responses
$result->set_end_of_speech_timeout(300);

# Longer timeout for thoughtful responses
$result->set_end_of_speech_timeout(2000);
```

##### `set_speech_event_timeout($milliseconds)`
Set the timeout for speech events. Returns `$self` for chaining.

**Parameters:**
- `$milliseconds` (Int): Timeout in milliseconds

**Usage:**
```perl
$result->set_speech_event_timeout(5000);
```

##### `wait_for_user(%opts)`
Control whether to wait for user input. Arguments are named. Returns `$self` for chaining.

**Parameters:**
- `enabled` (Bool): Enable/disable waiting for the user
- `timeout` (Int): Timeout in milliseconds
- `answer_first` (Bool): Answer the call before waiting (default: false)

**Usage:**
```perl
# Wait for user input with a 10-second timeout
$result->wait_for_user( enabled => 1, timeout => 10000 );

# Don't wait for the user (immediate response)
$result->wait_for_user( enabled => 0 );
```

##### `toggle_functions($function_toggles)`
Enable or disable specific functions. Returns `$self` for chaining.

**Parameters:**
- `$function_toggles` (ArrayRef[HashRef]): List of function-toggle configurations

**Usage:**
```perl
$result->toggle_functions([
    { function => 'transfer_to_sales', active => JSON::true },
    { function => 'end_call',          active => JSON::false },
    { function => 'escalate',          active => JSON::true },
]);
```

##### `enable_functions_on_timeout($enabled)`
Control whether functions are enabled when a timeout occurs. Returns `$self` for chaining.

**Parameters:**
- `$enabled` (Bool): Enable functions on timeout (default: true)

**Usage:**
```perl
$result->enable_functions_on_timeout(0);   # Disable functions on timeout
```

##### `enable_extensive_data($enabled)`
Enable extensive data collection. Returns `$self` for chaining.

**Parameters:**
- `$enabled` (Bool): Enable extensive data (default: true)

**Usage:**
```perl
$result->enable_extensive_data(1);
```

##### `update_settings($settings)`
Update various AI settings. Returns `$self` for chaining.

**Parameters:**
- `$settings` (HashRef): Settings to update

**Usage:**
```perl
$result->update_settings({
    temperature           => 0.8,
    max_tokens            => 150,
    end_of_speech_timeout => 800,
});
```

### Context and Conversation Control

##### `switch_context(%opts)`
Switch conversation context or reset the conversation. Arguments are named. Returns `$self` for chaining.

**Parameters:**
- `system_prompt` (Str): New system prompt
- `user_prompt` (Str): New user prompt
- `consolidate` (Bool): Consolidate conversation history (default: false)
- `full_reset` (Bool): Completely reset the conversation (default: false)

**Usage:**
```perl
# Switch to a technical-support context
$result->switch_context(
    system_prompt => 'You are now a technical support specialist',
    user_prompt   => 'The customer needs technical help',
);

# Reset the conversation completely
$result->switch_context( full_reset => 1 );

# Consolidate conversation history
$result->switch_context( consolidate => 1 );
```

##### `simulate_user_input($text)`
Simulate user input for testing or automation. Returns `$self` for chaining.

**Parameters:**
- `$text` (Str): Text to simulate as user input

**Usage:**
```perl
$result->simulate_user_input('I need help with my order');
```

### Communication Actions

##### `send_sms(%opts)`
Send an SMS message. Arguments are named. Either `body` or `media` must be provided. Returns `$self` for chaining.

**Parameters:**
- `to_number` (Str): Recipient phone number (required)
- `from_number` (Str): Sender phone number (required)
- `body` (Str): SMS message text
- `media` (ArrayRef[Str]): List of media URLs
- `tags` (ArrayRef[Str]): Message tags
- `region` (Str): SignalWire region

**Usage:**
```perl
# Simple text message
$result->send_sms(
    to_number   => '+15551234567',
    from_number => '+15559876543',
    body        => 'Your order #12345 has shipped!',
);

# Message with media and tags
$result->send_sms(
    to_number   => '+15551234567',
    from_number => '+15559876543',
    body        => "Here's your receipt",
    media       => ['https://example.com/receipt.pdf'],
    tags        => [ 'receipt', 'order_12345' ],
);
```

### Recording and Media

##### `record_call(%opts)`
Start call recording. Arguments are named. Returns `$self` for chaining.

**Parameters:**
- `control_id` (Str): Unique identifier for this recording
- `stereo` (Bool): Record in stereo (default: false)
- `format` (Str): Recording format: "wav", "mp3", "mp4" (default: "wav")
- `direction` (Str): Recording direction: "speak", "listen", "both" (default: "both")
- `terminators` (Str): DTMF keys to stop recording
- `beep` (Bool): Play a beep before recording (default: false)
- `input_sensitivity` (Num): Input sensitivity level (default: 44.0)
- `initial_timeout` (Num): Initial timeout in seconds
- `end_silence_timeout` (Num): End-silence timeout in seconds
- `max_length` (Num): Maximum recording length in seconds
- `status_url` (Str): Webhook URL for recording status

**Usage:**
```perl
# Basic recording
$result->record_call( format => 'mp3', direction => 'both' );

# Recording with a control ID and settings
$result->record_call(
    control_id  => 'customer_call_001',
    stereo      => 1,
    format      => 'wav',
    beep        => 1,
    max_length  => 300.0,
    terminators => '#*',
);
```

##### `stop_record_call(%opts)`
Stop call recording. Returns `$self` for chaining.

**Parameters:**
- `control_id` (Str): Control ID of the recording to stop

**Usage:**
```perl
$result->stop_record_call;
$result->stop_record_call( control_id => 'customer_call_001' );
```

### Conference and Room Management

##### `join_room($name)`
Join a SignalWire room. Returns `$self` for chaining.

**Parameters:**
- `$name` (Str): Room name to join

**Usage:**
```perl
$result->join_room('support_room_1');
```

##### `join_conference($name, %opts)`
Join a conference call. `$name` is positional; the remaining options are named. Returns `$self` for chaining.

**Parameters:**
- `$name` (Str): Conference name
- `muted` (Bool): Join muted (default: false)
- `beep` (Str): Beep setting: "true", "false", "onEnter", "onExit" (default: "true")
- `start_on_enter` (Bool): Start the conference when this participant enters (default: true)
- `end_on_exit` (Bool): End the conference when this participant exits (default: false)
- `wait_url` (Str): URL for hold music/content
- `max_participants` (Int): Maximum participants (default: 250)
- `record` (Str): Recording setting (default: "do-not-record")
- `region` (Str): SignalWire region
- `trim` (Str): Trim setting for recordings (default: "trim-silence")
- `coach` (Str): Coach participant identifier
- `status_callback_event` (Str): Status-callback events
- `status_callback` (Str): Status-callback URL
- `status_callback_method` (Str): Status-callback HTTP method (default: "POST")
- `recording_status_callback` (Str): Recording status-callback URL
- `recording_status_callback_method` (Str): Recording status-callback method (default: "POST")
- `recording_status_callback_event` (Str): Recording status-callback events (default: "completed")

**Usage:**
```perl
# Basic conference join
$result->join_conference('sales_meeting');

# Conference with recording and settings
$result->join_conference(
    'support_conference',
    muted            => 0,
    beep             => 'onEnter',
    record           => 'record-from-start',
    max_participants => 10,
);
```

### Payment Processing

##### `pay(%opts)`
Process a payment through the call. Arguments are named. Returns `$self` for chaining.

**Parameters:**
- `payment_connector_url` (Str): Payment-processor webhook URL (required)
- `input_method` (Str): Input method: "dtmf", "speech" (default: "dtmf")
- `status_url` (Str): Payment-status webhook URL
- `payment_method` (Str): Payment method: "credit-card" (default: "credit-card")
- `timeout` (Int): Input timeout in seconds (default: 5)
- `max_attempts` (Int): Maximum retry attempts (default: 1)
- `security_code` (Bool): Require a security code (default: true)
- `postal_code` (Bool | Str): Require a postal code (default: true)
- `min_postal_code_length` (Int): Minimum postal-code length (default: 0)
- `token_type` (Str): Token type: "reusable", "one-time" (default: "reusable")
- `charge_amount` (Str): Amount to charge
- `currency` (Str): Currency code (default: "usd")
- `language` (Str): Language for prompts (default: "en-US")
- `voice` (Str): Voice for prompts (default: "woman")
- `description` (Str): Payment description
- `valid_card_types` (Str): Accepted card types (default: "visa mastercard amex")
- `parameters` (ArrayRef[HashRef]): Additional parameters
- `prompts` (ArrayRef[HashRef]): Custom prompts

**Usage:**
```perl
# Basic payment processing
$result->pay(
    payment_connector_url => 'https://payment-processor.com/webhook',
    charge_amount         => '29.99',
    description           => 'Monthly subscription',
);

# Payment with custom settings
$result->pay(
    payment_connector_url => 'https://payment-processor.com/webhook',
    input_method          => 'speech',
    timeout               => 10,
    max_attempts          => 3,
    security_code         => 1,
    postal_code           => 1,
    charge_amount         => '149.99',
    currency              => 'usd',
    description           => 'Premium service upgrade',
);
```

### Call Monitoring

##### `tap($uri, %opts)`
Start call tapping/monitoring. `$uri` is positional; the rest are named. Returns `$self` for chaining.

**Parameters:**
- `$uri` (Str): URI to send tapped audio to
- `control_id` (Str): Unique identifier for this tap
- `direction` (Str): Tap direction: "both", "inbound", "outbound" (default: "both")
- `codec` (Str): Audio codec: "PCMU", "PCMA", "G722" (default: "PCMU")
- `rtp_ptime` (Int): RTP packet time in milliseconds (default: 20)
- `status_url` (Str): Status webhook URL

**Usage:**
```perl
# Basic call tapping
$result->tap('sip:monitor@company.com');

# Tap with specific settings
$result->tap(
    'sip:quality@company.com',
    control_id => 'quality_monitor_001',
    direction  => 'both',
    codec      => 'G722',
);
```

##### `stop_tap(%opts)`
Stop call tapping. Returns `$self` for chaining.

**Parameters:**
- `control_id` (Str): Control ID of the tap to stop

**Usage:**
```perl
$result->stop_tap;
$result->stop_tap( control_id => 'quality_monitor_001' );
```

### Advanced SWML Execution

##### `execute_swml($swml_content, %opts)`
Execute custom SWML content. `$swml_content` may be a hashref or a JSON string. Returns `$self` for chaining.

**Parameters:**
- `$swml_content` (HashRef | Str): SWML document or content to execute
- `transfer` (Bool): Whether this is a transfer operation (default: false)

**Usage:**
```perl
# Execute custom SWML
my $custom_swml = {
    version  => '1.0.0',
    sections => {
        main => [
            { play => { url  => 'https://example.com/custom.mp3' } },
            { say  => { text => 'Custom SWML execution' } },
        ],
    },
};
$result->execute_swml($custom_swml);
```

### Utility Methods

##### `to_hash()`
Convert the result to a hashref for serialization (the Perl equivalent of Python's `to_dict()`). Use `to_json()` to get the JSON string directly.

**Returns:**
- HashRef: Hashref representation of the result

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new('Hello world');
$result->add_action( 'play', 'music.mp3' );
my $result_hash = $result->to_hash;
# $result_hash is { response => 'Hello world', action => [ { play => 'music.mp3' } ] }
```

### Static Helper Methods

##### `create_payment_prompt(%opts)`
Create a payment-prompt configuration hashref. Callable as a class or instance method. Arguments are named.

**Parameters:**
- `for_situation` (Str): Situation identifier (required)
- `actions` (ArrayRef[HashRef]): List of action configurations (required)
- `card_type` (Str): Card type for prompts
- `error_type` (Str): Error type for error prompts

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $prompt = SignalWire::SWAIG::FunctionResult->create_payment_prompt(
    for_situation => 'card_number',
    actions       => [
        SignalWire::SWAIG::FunctionResult->create_payment_action( 'say', 'Please enter your card number' ),
    ],
);
```

##### `create_payment_action($action_type, $phrase)`
Create a payment-action configuration hashref. Callable as a class or instance method.

**Parameters:**
- `$action_type` (Str): Action type
- `$phrase` (Str): Action phrase

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $action = SignalWire::SWAIG::FunctionResult->create_payment_action( 'say', 'Enter your card number' );
```

##### `create_payment_parameter($name, $value)`
Create a payment-parameter configuration hashref. Callable as a class or instance method.

**Parameters:**
- `$name` (Str): Parameter name
- `$value` (Str): Parameter value

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
my $param = SignalWire::SWAIG::FunctionResult->create_payment_parameter( 'merchant_id', '12345' );
```

### Method Chaining

All mutating methods return `$self`, enabling fluent method chaining:

```perl
use SignalWire::SWAIG::FunctionResult;
my $result = SignalWire::SWAIG::FunctionResult->new("I'll help you with that")
    ->set_post_process(1)
    ->update_global_data({ status => 'helping' })
    ->set_end_of_speech_timeout(800)
    ->add_action( 'play', 'thinking.mp3' );

# Complex workflow
my $result2 = SignalWire::SWAIG::FunctionResult->new('Processing your payment')
    ->set_post_process(1)
    ->update_global_data({ payment_status => 'processing' })
    ->pay(
        payment_connector_url => 'https://payments.com/webhook',
        charge_amount         => '99.99',
        description           => 'Service payment',
    )
    ->send_sms(
        to_number   => '+15551234567',
        from_number => '+15559876543',
        body        => 'Payment confirmation will be sent shortly',
    );
```

This concludes Part 2 of the API reference covering the SwaigFunctionResult class. The document will continue with DataMap and other components in subsequent parts.

---

## DataMap Class

The `SignalWire::DataMap` class provides a declarative approach to creating SWAIG tools that integrate with REST APIs without requiring webhook infrastructure. DataMap tools execute on SignalWire's server infrastructure, eliminating the need to expose webhook endpoints.

### Constructor

```perl
use SignalWire::DataMap;
SignalWire::DataMap->new($function_name);
```

**Parameters:**
- `$function_name` (Str): Name of the SWAIG function this DataMap will create

**Usage:**
```perl
use SignalWire::DataMap;

# Create a new DataMap tool
my $weather_map = SignalWire::DataMap->new('get_weather');
my $search_map  = SignalWire::DataMap->new('search_docs');
```

### Core Configuration Methods

#### Function Metadata

##### `purpose($description)`
Set the function description/purpose. Returns `$self` for chaining.

**Parameters:**
- `$description` (Str): Human-readable description of what this function does

**Usage:**
```perl
use SignalWire::DataMap;
my $data_map = SignalWire::DataMap->new('get_weather')
    ->purpose('Get current weather information for any city');
```

##### `description($description)`
Alias for `purpose()` - set the function description. Returns `$self` for chaining.

**Parameters:**
- `$description` (Str): Function description

**Usage:**
```perl
use SignalWire::DataMap;
my $data_map = SignalWire::DataMap->new('search_api')
    ->description('Search our knowledge base for information');
```

#### Parameter Definition

##### `parameter($name, $param_type, $description, %opts)`
Add a function parameter with JSON-schema validation. `$name`, `$param_type`, and `$description` are positional; `required` and `enum` are named. Returns `$self` for chaining.

**Parameters:**
- `$name` (Str): Parameter name
- `$param_type` (Str): JSON-schema type: "string", "number", "boolean", "array", "object"
- `$description` (Str): Parameter description for the AI
- `required` (Bool): Whether the parameter is required (default: false)
- `enum` (ArrayRef[Str]): List of allowed values for validation

**Usage:**
```perl
# Required string parameter
$data_map->parameter( 'location', 'string', 'City name or ZIP code', required => 1 );

# Optional number parameter
$data_map->parameter( 'days', 'number', 'Number of forecast days' );

# Enum parameter with allowed values
$data_map->parameter( 'units', 'string', 'Temperature units',
    enum => [ 'celsius', 'fahrenheit' ] );

# Boolean parameter
$data_map->parameter( 'include_alerts', 'boolean', 'Include weather alerts' );

# Array parameter
$data_map->parameter( 'categories', 'array', 'Search categories to include' );
```

### API Integration Methods

#### HTTP Webhook Configuration

##### `webhook($method, $url, %opts)`
Configure an HTTP API call. `$method` and `$url` are positional; the rest are named. Returns `$self` for chaining.

**Parameters:**
- `$method` (Str): HTTP method: "GET", "POST", "PUT", "DELETE", "PATCH"
- `$url` (Str): API endpoint URL (supports `${variable}` substitution)
- `headers` (HashRef): HTTP headers to send
- `form_param` (Str): Send the JSON body as a single form parameter with this name
- `input_args_as_params` (Bool): Merge function arguments into URL parameters (default: false)
- `require_args` (ArrayRef[Str]): Only execute if these arguments are present

**Variable Substitution in URLs:**
- `${args.parameter_name}`: Function argument values
- `${global_data.key}`: Call-wide data store (user info, call state - NOT credentials)
- `${meta_data.call_id}`: Call and function metadata

**Usage:**
```perl
# Simple GET request with parameter substitution
$data_map->webhook( 'GET', 'https://api.weather.com/v1/current?key=API_KEY&q=${args.location}' );

# POST request with authentication headers
$data_map->webhook(
    'POST',
    'https://api.company.com/search',
    headers => {
        Authorization  => 'Bearer YOUR_TOKEN',
        'Content-Type' => 'application/json',
    },
);

# Webhook that requires specific arguments
$data_map->webhook(
    'GET',
    'https://api.service.com/data?id=${args.customer_id}',
    require_args => ['customer_id'],
);

# Use global data for call-related info (NOT credentials)
$data_map->webhook(
    'GET',
    'https://api.service.com/customer/${global_data.customer_id}/orders',
    headers => { Authorization => 'Bearer YOUR_API_TOKEN' },   # Use static credentials
);
```

##### `params($data)`
Set the request params for the most recent webhook -- this is the method for
POST/PUT request data as well as query parameters. Returns `$self` for chaining.

**Parameters:**
- `$data` (HashRef): Query parameters (supports `${variable}` substitution)

**Usage:**
```perl
# URL parameters with substitution
$data_map->params({
    api_key => 'YOUR_API_KEY',
    q       => '${args.location}',
    units   => '${args.units}',
    lang    => 'en',
});
```

#### Multiple Webhooks and Fallbacks

DataMap supports multiple webhook configurations for fallback scenarios:

```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;
# Primary API with fallback
my $data_map = SignalWire::DataMap->new('search_with_fallback')
    ->purpose('Search with multiple API fallbacks')
    ->parameter( 'query', 'string', 'Search query', required => 1 )

    # Primary API
    ->webhook( 'GET', 'https://api.primary.com/search?q=${args.query}' )
    ->output( SignalWire::SWAIG::FunctionResult->new('Primary result: ${response.title}') )

    # Fallback API
    ->webhook( 'GET', 'https://api.fallback.com/search?q=${args.query}' )
    ->output( SignalWire::SWAIG::FunctionResult->new('Fallback result: ${response.title}') )

    # Final fallback if all APIs fail
    ->fallback_output( SignalWire::SWAIG::FunctionResult->new('Sorry, all search services are currently unavailable') );
```

### Response Processing

#### Basic Output

##### `output($result)`
Set the response template for successful API calls. Returns `$self` for chaining.

**Parameters:**
- `$result` (FunctionResult): Response template with variable substitution

**Variable Substitution in Outputs:**
- `${response.field}`: API response fields
- `${response.nested.field}`: Nested response fields
- `${response.array[0].field}`: Array element fields
- `${args.parameter}`: Original function arguments
- `${global_data.key}`: Call-wide data store (user info, call state)

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
# Simple response template
$data_map->output(
    SignalWire::SWAIG::FunctionResult->new(
        'Weather in ${args.location}: ${response.current.condition.text}, ${response.current.temp_f}F' )
);

# Response with actions
$data_map->output(
    SignalWire::SWAIG::FunctionResult->new('Found ${response.total_results} results')
        ->update_global_data({ last_search => '${args.query}' })
        ->add_action( 'play', 'search_complete.mp3' )
);

# Complex response with nested data
$data_map->output(
    SignalWire::SWAIG::FunctionResult->new(
        'Order ${response.order.id} status: ${response.order.status}. Estimated delivery: ${response.order.delivery.estimated_date}' )
);
```

##### `fallback_output($result)`
Set the response used when all webhooks fail. Returns `$self` for chaining.

**Parameters:**
- `$result` (FunctionResult): Fallback response

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
$data_map->fallback_output(
    SignalWire::SWAIG::FunctionResult->new('Sorry, the service is temporarily unavailable. Please try again later.')
        ->add_action( 'play', 'service_unavailable.mp3' )
);
```

#### Array Processing

##### `foreach($foreach_config)`
Process array responses by iterating over elements. In Perl, `foreach` takes a hashref that must include `input_key` (the array field in the response), `output_key` (the accumulator name referenced in the output template), and `append` (the per-element template). An optional `max` limits how many elements are processed. Must be called after a `webhook`. Returns `$self` for chaining.

**Parameters:**
- `$foreach_config` (HashRef): Configuration with `input_key`, `output_key`, `append`, and optional `max`

**Array Processing:**
```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;
# Process an array of search results
my $data_map = SignalWire::DataMap->new('search_docs')
    ->webhook( 'GET', 'https://api.docs.com/search?q=${args.query}' )
    ->foreach({
        input_key  => 'results',
        output_key => 'formatted',
        max        => 3,   # process only the first 3 items
        append     => '${this.title} - ${this.summary}\n',
    })
    ->output( SignalWire::SWAIG::FunctionResult->new('Found: ${formatted}') );
```

**Foreach Template Variable Access:**
- `${this.field}`: Current array element field
- `${this.nested.field}`: Nested fields in the current element

### Pattern-Based Processing

#### Expression Matching

##### `expression($test_value, $pattern, $output, %opts)`
Add pattern-based responses without API calls. `$test_value`, `$pattern`, and `$output` are positional; `nomatch_output` is named. Returns `$self` for chaining.

**Parameters:**
- `$test_value` (Str): Template string to test against the pattern
- `$pattern` (Str | Regexp): Regex pattern string or a compiled `qr//`
- `$output` (FunctionResult): Response when the pattern matches
- `nomatch_output` (FunctionResult): Response when the pattern doesn't match

**Usage:**
```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;
# Command-based responses
my $control_map = SignalWire::DataMap->new('file_control')
    ->purpose('Control file playback')
    ->parameter( 'command',  'string', 'Playback command', required => 1 )
    ->parameter( 'filename', 'string', 'File to control' )

    # Start commands
    ->expression(
        '${args.command}',
        'start|play|begin',
        SignalWire::SWAIG::FunctionResult->new('Starting playback')
            ->add_action( 'start_playback', { file => '${args.filename}' } )
    )

    # Stop commands
    ->expression(
        '${args.command}',
        'stop|pause|halt',
        SignalWire::SWAIG::FunctionResult->new('Stopping playback')
            ->add_action( 'stop_playback', JSON::true )
    )

    # Volume commands
    ->expression(
        '${args.command}',
        'volume (\d+)',
        SignalWire::SWAIG::FunctionResult->new('Setting volume to ${match.1}')
            ->add_action( 'set_volume', '${match.1}' )
    );
```

**Pattern Matching Variables:**
- `${match.0}`: Full match
- `${match.1}`, `${match.2}`, etc.: Capture groups
- `${match.group_name}`: Named capture groups

### Error Handling

##### `error_keys($keys)`
Specify response fields that indicate errors. Returns `$self` for chaining.

**Parameters:**
- `$keys` (ArrayRef[Str]): List of field names that indicate API errors

**Usage:**
```perl
# Treat these response fields as errors
$data_map->error_keys([ 'error', 'error_message', 'status_code' ]);

# If the API returns { error => 'Not found' }, DataMap treats this as an error
```

##### `global_error_keys($keys)`
Set global error keys for all webhooks in this DataMap. Returns `$self` for chaining.

**Parameters:**
- `$keys` (ArrayRef[Str]): Global error field names

**Usage:**
```perl
$data_map->global_error_keys([ 'error', 'message', 'code' ]);
```

### Advanced Configuration

##### `webhook_expressions($expressions)`
Add expression-based webhook selection. Returns `$self` for chaining.

**Parameters:**
- `$expressions` (ArrayRef[HashRef]): List of expression configurations

**Usage:**
```perl
# Different APIs based on input
$data_map->webhook_expressions([
    {
        test    => '${args.type}',
        pattern => 'weather',
        webhook => {
            method => 'GET',
            url    => 'https://weather-api.com/current?q=${args.location}',
        },
    },
    {
        test    => '${args.type}',
        pattern => 'news',
        webhook => {
            method => 'GET',
            url    => 'https://news-api.com/search?q=${args.query}',
        },
    },
]);
```

### Complete DataMap Examples

#### Simple Weather API

```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;
my $weather_tool = SignalWire::DataMap->new('get_weather')
    ->purpose('Get current weather information')
    ->parameter( 'location', 'string', 'City name or ZIP code', required => 1 )
    ->parameter( 'units', 'string', 'Temperature units', enum => [ 'celsius', 'fahrenheit' ] )
    ->webhook( 'GET', 'https://api.weather.com/v1/current?key=API_KEY&q=${args.location}&units=${args.units}' )
    ->output(
        SignalWire::SWAIG::FunctionResult->new(
            'Weather in ${args.location}: ${response.current.condition.text}, ${response.current.temp_f}F' )
    )
    ->error_keys(['error']);

# Register with the agent
$agent->register_swaig_function( $weather_tool->to_swaig_function );
```

#### Search with Array Processing

```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;
my $search_tool = SignalWire::DataMap->new('search_knowledge')
    ->purpose('Search company knowledge base')
    ->parameter( 'query', 'string', 'Search query', required => 1 )
    ->parameter( 'category', 'string', 'Search category', enum => [ 'docs', 'faq', 'policies' ] )
    ->webhook(
        'POST',
        'https://api.company.com/search',
        headers => { Authorization => 'Bearer TOKEN' },
    )
    ->params({
        query    => '${args.query}',
        category => '${args.category}',
        limit    => 5,
    })
    ->foreach({
        input_key  => 'results',
        output_key => 'formatted',
        append     => '${this.title} - ${this.summary}\n',
    })
    ->output( SignalWire::SWAIG::FunctionResult->new('Found: ${formatted}') )
    ->fallback_output( SignalWire::SWAIG::FunctionResult->new('Search service is temporarily unavailable') );
```

#### Command Processing (No API)

```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;
my $control_tool = SignalWire::DataMap->new('system_control')
    ->purpose('Control system functions')
    ->parameter( 'action', 'string', 'Action to perform', required => 1 )
    ->parameter( 'target', 'string', 'Target for the action' )

    # Restart commands
    ->expression(
        '${args.action}',
        'restart|reboot',
        SignalWire::SWAIG::FunctionResult->new('Restarting ${args.target}')
            ->add_action( 'restart_service', { service => '${args.target}' } )
    )

    # Status commands
    ->expression(
        '${args.action}',
        'status|check',
        SignalWire::SWAIG::FunctionResult->new('Checking status of ${args.target}')
            ->add_action( 'check_status', { service => '${args.target}' } )
    )

    # Default for unrecognized commands
    ->expression(
        '${args.action}',
        '.*',
        SignalWire::SWAIG::FunctionResult->new('Unknown command: ${args.action}'),
        nomatch_output => SignalWire::SWAIG::FunctionResult->new('Please specify a valid action'),
    );
```

### Conversion and Registration

##### `to_swaig_function()`
Convert the DataMap to a SWAIG function hashref for registration.

**Returns:**
- HashRef: Complete SWAIG function definition

**Usage:**
```perl
use SignalWire::DataMap;
# Build the DataMap
my $weather_map = SignalWire::DataMap->new('get_weather')
    ->purpose('Get weather')
    ->parameter( 'location', 'string', 'City', required => 1 );

# Convert to a SWAIG function and register
my $swaig_function = $weather_map->to_swaig_function;
$agent->register_swaig_function($swaig_function);
```

### Convenience Functions

The `SignalWire::DataMap` package provides helper functions for common DataMap patterns. They are called as class methods (`SignalWire::DataMap::create_simple_api_tool(...)`).

##### `create_simple_api_tool(%opts)`

Create a simple API-integration tool. Arguments are named.

**Parameters:**
- `name` (Str): Function name
- `url` (Str): API endpoint URL
- `response_template` (Str): Response template string
- `parameters` (HashRef): Parameter definitions
- `method` (Str): HTTP method (default: "GET")
- `headers` (HashRef): HTTP headers
- `error_keys` (ArrayRef[Str]): Error field names

**Usage:**
```perl
use SignalWire::DataMap;

my $weather = SignalWire::DataMap::create_simple_api_tool(
    name              => 'get_weather',
    url               => 'https://api.weather.com/v1/current?key=API_KEY&q=${location}',
    response_template => 'Weather in ${location}: ${response.current.condition.text}',
    parameters        => {
        location => {
            type        => 'string',
            description => 'City name',
            required    => 1,
        },
    },
);

$agent->register_swaig_function( $weather->to_swaig_function );
```

##### `create_expression_tool(%opts)`

Create a pattern-based tool without API calls. Arguments are named. `patterns` is a hashref mapping a test-value template to `[ $pattern, $function_result ]`.

**Parameters:**
- `name` (Str): Function name
- `patterns` (HashRef): Test-value => `[ pattern, FunctionResult ]` mappings
- `parameters` (HashRef): Parameter definitions

**Usage:**
```perl
use SignalWire::DataMap;
use SignalWire::SWAIG::FunctionResult;

my $file_control = SignalWire::DataMap::create_expression_tool(
    name     => 'file_control',
    patterns => {
        '${args.command}' => [
            'start.*',
            SignalWire::SWAIG::FunctionResult->new->add_action( 'start_playback', JSON::true ),
        ],
    },
    parameters => {
        command => {
            type        => 'string',
            description => 'Playback command',
            required    => 1,
        },
    },
);

$agent->register_swaig_function( $file_control->to_swaig_function );
```

### Method Chaining

All DataMap methods return `$self`, enabling fluent method chaining:

```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;
my $complete_tool = SignalWire::DataMap->new('comprehensive_search')
    ->purpose('Comprehensive search with fallbacks')
    ->parameter( 'query', 'string', 'Search query', required => 1 )
    ->parameter( 'category', 'string', 'Search category', enum => [ 'all', 'docs', 'faq' ] )
    ->webhook( 'GET', 'https://primary-api.com/search?q=${args.query}&cat=${args.category}' )
    ->output( SignalWire::SWAIG::FunctionResult->new('Primary: ${response.title}') )
    ->webhook( 'GET', 'https://backup-api.com/search?q=${args.query}' )
    ->output( SignalWire::SWAIG::FunctionResult->new('Backup: ${response.title}') )
    ->fallback_output( SignalWire::SWAIG::FunctionResult->new('All search services unavailable') )
    ->error_keys([ 'error', 'message' ]);
```

This concludes Part 3 of the API reference covering the DataMap class. The document will continue with Context System and other components in subsequent parts. 

---

## Context System

The Context System enhances traditional prompt-based agents by adding structured workflows with sequential steps on top of a base prompt. Each step contains its own guidance, completion criteria, and function restrictions while building upon the agent's foundational prompt.

### ContextBuilder Class

The `ContextBuilder` is accessed via `$agent->define_contexts` and provides the main interface for creating structured workflows.

#### Getting Started

```perl
# Access the context builder
my $contexts = $agent->define_contexts;

# Create contexts and steps
$contexts->add_context('greeting')
    ->add_step('welcome')
    ->set_text('Welcome! How can I help you today?')
    ->set_step_criteria('User has stated their need')
    ->set_valid_steps(['menu']);
```

##### `add_context($name)`
Create a new context in the workflow.

**Parameters:**
- `$name` (Str): Unique context name

**Returns:**
- Context: Context object for method chaining

**Usage:**
```perl
# Create multiple contexts
my $greeting_context  = $contexts->add_context('greeting');
my $main_menu_context = $contexts->add_context('main_menu');
my $support_context   = $contexts->add_context('support');
```

### Context Class

The Context object represents a conversation context containing multiple steps with enhanced features. All setters return the Context for method chaining:

- `add_step($name)` — Create a new step in this context (returns a Step).
- `set_valid_contexts($contexts)` — Set which contexts can be accessed from this context (arrayref of names).
- `set_post_prompt($post_prompt)` — Override the agent's post-prompt when this context is active.
- `set_system_prompt($system_prompt)` — Trigger a context switch with new system instructions (makes this a Context Switch Context).
- `set_consolidate($bool)` — Whether to consolidate conversation history when entering this context.
- `set_full_reset($bool)` — Whether to do complete system-prompt replacement vs injection.
- `set_user_prompt($user_prompt)` — User message to inject when entering this context.
- `set_prompt($prompt)` — Set a simple string prompt that applies to all steps in this context.
- `add_section($title, $body)` — Add a POM-style section to the context prompt.
- `add_bullets($title, $bullets)` — Add a POM-style bullet section to the context prompt (arrayref of bullets).

**Context Types:**

1. **Workflow Container Context** (no `system_prompt`): Organizes steps without conversation state changes
2. **Context Switch Context** (has `system_prompt`): Triggers conversation state changes when entered, processing entry parameters like a `context_switch` SWAIG action

**Prompt Hierarchy:** Base Agent Prompt → Context Prompt → Step Prompt

#### Usage Examples

```perl
# Workflow container context (just organizes steps)
my $main_context = $contexts->add_context('main');
$main_context->set_prompt('Follow standard customer service protocols');

# Context switch context (changes AI behavior)
my $billing_context = $contexts->add_context('billing');
$billing_context->set_system_prompt('You are now a billing specialist')
    ->set_consolidate(1)
    ->set_user_prompt('Customer needs billing assistance')
    ->add_section( 'Department', 'Billing Department' )
    ->add_bullets( 'Services', [ 'Account inquiries', 'Payments', 'Refunds' ] );

# Full reset context (complete conversation reset)
my $manager_context = $contexts->add_context('manager');
$manager_context->set_system_prompt('You are a senior manager')
    ->set_full_reset(1)
    ->set_consolidate(1);
```

---

## Skills System

The Skills System provides modular, reusable capabilities that can be easily added to any agent.

### Available Built-in Skills

#### `datetime` Skill
Provides current date and time information.

**Parameters:**
- `timezone` (Optional[str]): Timezone for date/time (default: system timezone)
- `format` (Optional[str]): Custom date/time format string

**Usage:**
```perl
# Basic datetime skill
$agent->add_skill('datetime');

# With timezone
$agent->add_skill('datetime', { timezone => 'America/New_York' });

# With custom format
$agent->add_skill('datetime', {
    timezone => 'UTC',
    format   => '%Y-%m-%d %H:%M:%S %Z',
});
```

#### `math` Skill
Safe mathematical expression evaluation.

**Parameters:**
- `precision` (Optional[int]): Decimal precision for results (default: 2)
- `max_expression_length` (Optional[int]): Maximum expression length (default: 100)

**Usage:**
```perl
# Basic math skill
$agent->add_skill('math');

# With custom precision
$agent->add_skill('math', { precision => 4 });
```

#### `web_search` Skill
Google Custom Search API integration with web scraping.

**Parameters:**
- `api_key` (str): Google Custom Search API key (required)
- `search_engine_id` (str): Google Custom Search Engine ID (required)
- `num_results` (Optional[int]): Number of results to return (default: 3)
- `tool_name` (Optional[str]): Custom tool name for multiple instances
- `delay` (Optional[float]): Delay between requests in seconds
- `no_results_message` (Optional[str]): Custom message when no results found

**Usage:**
```perl
# Basic web search
$agent->add_skill('web_search', {
    api_key          => 'your-google-api-key',
    search_engine_id => 'your-search-engine-id',
});

# Multiple search instances
$agent->add_skill('web_search', {
    api_key          => 'your-api-key',
    search_engine_id => 'general-engine-id',
    tool_name        => 'search_general',
    num_results      => 5,
});

$agent->add_skill('web_search', {
    api_key          => 'your-api-key',
    search_engine_id => 'news-engine-id',
    tool_name        => 'search_news',
    num_results      => 3,
    delay            => 0.5,
});
```

#### `datasphere` Skill
SignalWire DataSphere knowledge search integration.

**Parameters:**
- `space_name` (str): DataSphere space name (required)
- `project_id` (str): DataSphere project ID (required)
- `token` (str): DataSphere access token (required)
- `document_id` (Optional[str]): Specific document to search
- `tool_name` (Optional[str]): Custom tool name for multiple instances
- `count` (Optional[int]): Number of results to return (default: 3)
- `tags` (Optional[List[str]]): Filter by document tags

**Usage:**
```perl
# Basic DataSphere search
$agent->add_skill('datasphere', {
    space_name => 'my-space',
    project_id => 'my-project',
    token      => 'my-token',
});

# Multiple DataSphere instances
$agent->add_skill('datasphere', {
    space_name  => 'my-space',
    project_id  => 'my-project',
    token       => 'my-token',
    document_id => 'drinks-menu',
    tool_name   => 'search_drinks',
    count       => 5,
});

$agent->add_skill('datasphere', {
    space_name => 'my-space',
    project_id => 'my-project',
    token      => 'my-token',
    tool_name  => 'search_policies',
    tags       => [ 'HR', 'Policies' ],
});
```

#### `native_vector_search` Skill
Local document search with vector similarity and keyword search.

**Parameters:**
- `index_path` (str): Path to search index file (required)
- `tool_name` (Optional[str]): Custom tool name (default: "search_documents")
- `max_results` (Optional[int]): Maximum results to return (default: 5)
- `similarity_threshold` (Optional[float]): Minimum similarity score 0.0-1.0 (default: 0.0). Higher values are stricter, lower values are more permissive. Typical range: 0.2-0.4 for all-MiniLM-L6-v2, 0.3-0.5 for all-mpnet-base-v2

**Usage:**
```perl
# Basic local search
$agent->add_skill('native_vector_search', {
    index_path => './knowledge.swsearch',
});

# With custom settings
$agent->add_skill('native_vector_search', {
    index_path           => './docs.swsearch',
    tool_name            => 'search_docs',
    max_results          => 10,
    similarity_threshold => 0.25,
});
```

### Creating Custom Skills

#### Skill Structure

Create a new skill by extending `SignalWire::Skills::SkillBase` (a Moo package). Override `setup` and `register_tools`, and optionally `get_hints`, `get_global_data`, and `get_prompt_sections`. Register the class with the skill registry so it can be added by name.

```perl
package SignalWire::Skills::Builtin::CustomSkill;
use Moo;
use SignalWire::DataMap;
use SignalWire::SWAIG::FunctionResult;
extends 'SignalWire::Skills::SkillBase';

use SignalWire::Skills::SkillRegistry;
SignalWire::Skills::SkillRegistry->register_skill( 'custom_skill', __PACKAGE__ );

has '+skill_name'        => ( default => sub { 'custom_skill' } );
has '+skill_description' => ( default => sub { 'Description of what this skill does' } );
has '+skill_version'     => ( default => sub { '1.0.0' } );
has '+required_packages' => ( default => sub { [] } );       # Perl modules needed
has '+required_env_vars' => ( default => sub { ['API_KEY'] } );

sub setup {
    my ($self) = @_;
    # Validate and store configuration
    unless ( $self->params->{api_key} ) {
        warn "api_key parameter is required\n";
        return 0;
    }
    return 1;
}

sub register_tools {
    my ($self) = @_;
    my $api_key = $self->params->{api_key};

    # DataMap-based tool
    my $tool = SignalWire::DataMap->new('custom_function')
        ->description('Custom API integration')
        ->parameter( 'query', 'string', 'Search query', required => 1 )
        ->webhook( 'GET', "https://api.example.com/search?key=$api_key&q=\${args.query}" )
        ->output( SignalWire::SWAIG::FunctionResult->new('Found: ${response.title}') );

    return $self->agent->register_swaig_function( $tool->to_swaig_function );
}

sub get_hints {
    my ($self) = @_;
    return [ 'custom search', 'find information' ];
}

sub get_global_data {
    my ($self) = @_;
    return { skill_version => $self->skill_version };
}

sub get_prompt_sections {
    my ($self) = @_;
    return [{
        title   => 'Custom Search Capability',
        body    => 'You can search our custom database for information.',
        bullets => [ 'Use the custom_function to search', 'Results are real-time' ],
    }];
}

1;
```

#### Skill Registration

Built-in skills live under `lib/SignalWire/Skills/Builtin/` and register themselves with `SignalWire::Skills::SkillRegistry->register_skill($name, __PACKAGE__)` at load time. To add a custom skill:

1. Create a package under `lib/SignalWire/Skills/Builtin/` (or your own namespace).
2. Extend `SignalWire::Skills::SkillBase` and implement `setup` and `register_tools`.
3. Call `SignalWire::Skills::SkillRegistry->register_skill('your_skill', __PACKAGE__)`.
4. The skill is then available via `$agent->add_skill('your_skill')`.

---

## Utility Classes

### SignalWire::SWAIG::SWAIGFunction Class

Represents a SWAIG function definition with metadata and validation. In most cases you register tools with `$self->define_tool(...)` rather than constructing this directly.

#### Constructor

```perl
use SignalWire::SWAIG::SWAIGFunction;
SignalWire::SWAIG::SWAIGFunction->new(
    name        => $name,
    description => $description,
    parameters  => $parameters,   # JSON-schema hashref
    handler     => sub { my ( $args, $raw_data ) = @_; ... },
    # optional: secure, fillers, required, webhook_url, and extra SWAIG fields
);
```

**Parameters:**
- `name` (Str): Function name (required)
- `description` (Str): Function description (required)
- `parameters` (HashRef): JSON schema for parameters
- `handler` (CodeRef): Sub to execute when the function is called (required)
- `secure` (Bool): Require a security token (default: false)
- `fillers` (HashRef): Language-specific filler phrases
- Any additional `key => value` pairs are stored as extra SWAIG fields

#### Usage

```perl
use SignalWire::SWAIG::SWAIGFunction;
use SignalWire::SWAIG::FunctionResult;

# Create a SWAIG function
my $swaig_func = SignalWire::SWAIG::SWAIGFunction->new(
    name        => 'get_weather',
    description => 'Get current weather',
    parameters  => {
        type       => 'object',
        properties => {
            location => { type => 'string', description => 'City name' },
        },
        required => ['location'],
    },
    secure  => 1,
    fillers => { 'en-US' => ['Checking weather...'] },
    handler => sub {
        my ( $args, $raw_data ) = @_;
        return SignalWire::SWAIG::FunctionResult->new('Sunny');
    },
);
```

### SignalWire::SWML::Service Class

Base class providing SWML document generation and HTTP service capabilities. `SignalWire::Agent::AgentBase` extends this class.

#### Key Methods

##### `render_swml()`
Generate the complete SWML document for the service.

##### `handle_request($request_data)`
Handle an incoming HTTP request and generate the appropriate response.

### Dynamic Configuration

The dynamic-configuration callback receives the agent instance directly, allowing you to configure it based on request data. The callback is an anonymous sub receiving `($query_params, $headers, $body, $agent)`.

**Usage:**
```perl
$agent->set_dynamic_config_callback( sub {
    my ( $query_params, $body_params, $headers, $agent ) = @_;

    # Configure based on the request
    if ( ( $query_params->{lang} // '' ) eq 'es' ) {
        $agent->add_language( name => 'Spanish', code => 'es-ES', voice => 'nova.luna' );
    }

    # Customer-specific configuration
    my $customer_id = $headers->{'X-Customer-ID'};
    if ($customer_id) {
        $agent->set_global_data({ customer_id => $customer_id });
        $agent->prompt_add_section( 'Customer Context', "You are helping customer $customer_id" );
    }

    # Add skills dynamically
    if ( ( $query_params->{enable_search} // '' ) eq 'true' ) {
        $agent->add_skill( 'web_search', { provider => 'google' } );
    }
});
```

---

## Environment Variables

The SDK supports various environment variables for configuration:

### Authentication
- `SWML_BASIC_AUTH_USER`: Basic auth username
- `SWML_BASIC_AUTH_PASSWORD`: Basic auth password

### SSL/HTTPS
- `SWML_SSL_ENABLED`: Enable SSL (true/false)
- `SWML_SSL_CERT_PATH`: Path to SSL certificate
- `SWML_SSL_KEY_PATH`: Path to SSL private key
- `SWML_DOMAIN`: Domain name for SSL

### Proxy Support
- `SWML_PROXY_URL_BASE`: Base URL for proxy server

### Skills Configuration
- `GOOGLE_SEARCH_API_KEY`: Google Custom Search API key
- `GOOGLE_SEARCH_ENGINE_ID`: Google Custom Search Engine ID
- `DATASPHERE_SPACE_NAME`: DataSphere space name
- `DATASPHERE_PROJECT_ID`: DataSphere project ID
- `DATASPHERE_TOKEN`: DataSphere access token

### Usage

```perl
use SignalWire::Agent::AgentBase;
# Set environment variables
$ENV{SWML_BASIC_AUTH_USER}     = 'admin';
$ENV{SWML_BASIC_AUTH_PASSWORD} = 'secret';
$ENV{GOOGLE_SEARCH_API_KEY}    = 'your-api-key';

# The agent will automatically use these
my $agent = SignalWire::Agent::AgentBase->new( name => 'My Agent' );
$agent->add_skill('web_search', {
    search_engine_id => 'your-engine-id',
    # api_key will be read from the environment
});
```

---

## Complete Example

Here's a comprehensive example using multiple SDK components:

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
package ComprehensiveAgent;
use Moo;
use SignalWire::DataMap;
use SignalWire::SWAIG::FunctionResult;
extends 'SignalWire::Agent::AgentBase';

sub BUILD {
    my ($self) = @_;

    # Configure voice and language
    $self->add_language(
        name           => 'English',
        code           => 'en-US',
        voice          => 'rime.spore',
        speech_fillers => [ 'Let me check...', 'One moment...' ],
    );

    # Add speech recognition hints
    $self->add_hints([ 'SignalWire', 'customer service', 'technical support' ]);

    # Configure AI parameters
    $self->set_params({
        ai_model              => 'gpt-4.1-nano',
        end_of_speech_timeout => 800,
        temperature           => 0.7,
    });

    # Add skills
    $self->add_skill('datetime');
    $self->add_skill('math');
    $self->add_skill('web_search', {
        api_key          => 'your-google-api-key',
        search_engine_id => 'your-engine-id',
        num_results      => 3,
    });

    # Set up structured workflow
    $self->_setup_contexts;

    # Add custom tools
    $self->_register_custom_tools;

    # Register a class-method tool
    $self->define_tool(
        name        => 'transfer_to_billing',
        description => 'Transfer call to billing department',
        parameters  => { type => 'object', properties => {} },
        handler     => sub {
            my ( $args, $raw_data ) = @_;
            return SignalWire::SWAIG::FunctionResult->new('Transferring you to our billing department')
                ->update_global_data({ last_action => 'transfer_to_billing' })
                ->connect( 'billing@company.com', final => 0 );
        },
    );

    # Handle conversation summaries
    $self->on_summary( sub {
        my ( $summary, $raw_data ) = @_;
        require Data::Dumper;
        print "Conversation completed: " . Data::Dumper::Dumper($summary);
        # Could save to a database, send notifications, etc.
    });

    # Set global data
    $self->set_global_data({
        company_name  => 'Acme Corp',
        support_hours => '9 AM - 5 PM EST',
        version       => '2.0',
    });
}

sub _setup_contexts {
    my ($self) = @_;
    my $contexts = $self->define_contexts;

    # Greeting context
    my $greeting = $contexts->add_context('greeting');
    $greeting->add_step('welcome')
        ->set_text('Hello! Welcome to Acme Corp support. How can I help you today?')
        ->set_step_criteria('Customer has explained their issue')
        ->set_valid_steps(['categorize']);

    $greeting->add_step('categorize')
        ->add_section( 'Current Task', "Categorize the customer's request" )
        ->add_bullets( 'Categories', [
            'Technical issue - use diagnostic tools',
            'Billing question - transfer to billing',
            'General inquiry - handle directly',
        ])
        ->set_functions([ 'transfer_to_billing', 'run_diagnostics' ])
        ->set_step_criteria('Request categorized and action taken');

    # Technical support context
    my $tech = $contexts->add_context('technical_support');
    $tech->add_step('diagnose')
        ->set_text('Let me run some diagnostics to identify the issue.')
        ->set_functions([ 'run_diagnostics', 'check_system_status' ])
        ->set_step_criteria('Diagnostics completed')
        ->set_valid_steps(['resolve']);

    $tech->add_step('resolve')
        ->set_text("Based on the diagnostics, here's how we'll fix this.")
        ->set_functions([ 'apply_fix', 'schedule_technician' ])
        ->set_step_criteria('Issue resolved or escalated');

    return $self;
}

sub _register_custom_tools {
    my ($self) = @_;

    # Customer lookup tool
    my $lookup_tool = SignalWire::DataMap->new('lookup_customer')
        ->description('Look up customer information')
        ->parameter( 'customer_id', 'string', 'Customer ID', required => 1 )
        ->webhook( 'GET', 'https://api.company.com/customers/${args.customer_id}',
            headers => { Authorization => 'Bearer YOUR_TOKEN' } )
        ->output( SignalWire::SWAIG::FunctionResult->new('Customer: ${response.name}, Status: ${response.status}') )
        ->error_keys(['error']);

    $self->register_swaig_function( $lookup_tool->to_swaig_function );

    # System control tool
    my $control_tool = SignalWire::DataMap->new('system_control')
        ->description('Control system functions')
        ->parameter( 'action', 'string', 'Action to perform', required => 1 )
        ->parameter( 'target', 'string', 'Target system' )
        ->expression( '${args.action}', 'restart|reboot',
            SignalWire::SWAIG::FunctionResult->new('Restarting ${args.target}')
                ->add_action( 'restart_system', { target => '${args.target}' } ) )
        ->expression( '${args.action}', 'status|check',
            SignalWire::SWAIG::FunctionResult->new('Checking ${args.target} status')
                ->add_action( 'check_status', { target => '${args.target}' } ) );

    $self->register_swaig_function( $control_tool->to_swaig_function );

    return $self;
}

1;

# Run the agent
package main;
my $agent = ComprehensiveAgent->new(
    name        => 'Comprehensive Agent',
    auto_answer => 1,
    record_call => 1,
);
$agent->run;
```

This concludes the complete API reference for the SignalWire AI Agents SDK. The SDK provides a comprehensive framework for building sophisticated AI agents with modular capabilities, structured workflows, persistent state, and deployment across multiple environments.