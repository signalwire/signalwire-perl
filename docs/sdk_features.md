# SignalWire AI Agents SDK: Why the SDK, Not Raw SWML

## The Problem with Raw SWML

SWML (SignalWire Markup Language) is a JSON document format that defines how an agent behaves during a call -- 30+ verbs, an AI verb with dozens of parameters, SWAIG (SignalWire AI Gateway) function definitions with JSON Schema, post-prompt URLs, webhook authentication, language arrays, pronunciation rules, hints, global data, contexts, steps, gather configs. Writing it by hand means constructing deeply nested JSON, manually building authenticated webhook URLs, hand-coding parameter schemas, and deploying separate webhook servers for your tools. Every agent becomes a bespoke JSON engineering project.

The SDK eliminates all of this. You write Perl. The SDK generates correct SWML, serves it over HTTP, and handles its own webhook callbacks -- all in one process, deployable to any platform.

---

## The Self-Referencing Pipeline

The SDK's core architectural insight is that the agent is both the **SWML generator** and the **SWAIG webhook handler** in a single stateless microservice.

```
SignalWire requests SWML → Agent generates document
  ↓
SWML contains webhook URLs → URLs point back to the agent itself
  ↓
AI calls a function → SignalWire POSTs to agent's /swaig/ endpoint
  ↓
Agent executes function locally → Returns result to AI
  ↓
Call ends → SignalWire POSTs analytics to agent's /post_prompt/ endpoint
```

The agent auto-detects its own public URL -- including behind ngrok, load balancers, API Gateway, or any reverse proxy (via `X-Forwarded-Host`, `Forwarded` header, or `SWML_PROXY_URL_BASE` env var). It embeds Basic Auth credentials directly into the webhook URLs. It generates per-call security tokens for each function. The developer writes none of this:

<!-- snippet: no-run starts a blocking HTTP server (->run/->serve) -->
```perl
package WeatherAgent;
use Moo;
extends 'SignalWire::Agent::AgentBase';
use SignalWire::SWAIG::FunctionResult;

sub BUILD {
    my ($self) = @_;
    $self->prompt_add_section('Role', 'You help with weather.');

    $self->define_tool(
        name        => 'get_weather',
        description => 'Get weather',
        parameters  => {
            type       => 'object',
            properties => { city => { type => 'string' } },
            required   => ['city'],
        },
        handler => sub {
            my ($args, $raw_data) = @_;
            my $city = $args->{city};
            # ... fetch weather ...
            return SignalWire::SWAIG::FunctionResult->new("72\x{b0}F and sunny in $city");
        },
    );
}

package main;
my $agent = WeatherAgent->new( name => 'weather', route => '/weather' );
$agent->run;
```

That's a complete agent: HTTP server, SWML generation, authenticated webhook routing, function execution, and response formatting. The generated SWML contains the full AI configuration, function schemas, and webhook URLs pointing back to the running process -- all computed automatically.

---

## Prompt Object Model (POM)

Raw SWML prompts are flat strings. The SDK provides structured prompt building:

```perl
$agent->prompt_add_section('Role', 'You are a travel booking assistant.');
$agent->prompt_add_section('Rules', '',
    bullets => [
        'Never make up flight information',
        'Always confirm before booking',
        'Use the search tool for real data',
    ]);
$agent->prompt_add_section('Personality', 'Friendly but professional.');
```

POM sections are rendered by the platform into a format the LLM understands with proper hierarchy. You can add subsections, append to existing sections, check if sections exist, and compose prompts programmatically -- including from skills that inject their own sections.

---

## Tools: Three Ways

### 1. Defined Functions (Local Execution)

```perl
$self->define_tool(
    name        => 'lookup_order',
    description => 'Look up an order',
    parameters  => {
        type       => 'object',
        properties => { order_id => { type => 'string' } },
        required   => ['order_id'],
    },
    handler => sub {
        my ($args, $raw_data) = @_;
        my $order  = $db->get( $args->{order_id} );
        my $result = SignalWire::SWAIG::FunctionResult->new(
            "Order $order->{id}: $order->{status}" );
        $result->add_action( 'set_global_data', { current_order => $order } );
        return $result;
    },
);
```

The SDK converts this into a SWAIG function definition with JSON Schema parameters, creates a secure webhook URL, routes inbound POST requests to the handler, parses arguments, and formats the response -- including the 20+ SWAIG actions (transfer, hold, context_switch, toggle_functions, etc.) that tools can return.

Each tool is registered with an explicit `parameters` JSON Schema and an
anonymous-sub `handler`. A tool with no parameters uses an empty schema:

```perl
$self->define_tool(
    name        => 'lookup_order',
    description => 'Look up an order by ID',
    parameters  => { type => 'object', properties => {} },
    handler     => sub {
        my ($args, $raw_data) = @_;
        my $order = $db->get( $args->{order_id} );
        return SignalWire::SWAIG::FunctionResult->new(
            "Order $order->{id}: $order->{status}" );
    },
);
```

### 2. DataMap (Server-Side Execution)

```perl
use SignalWire::SWAIG::FunctionResult;
use SignalWire::DataMap;

my $data_map = SignalWire::DataMap->new('check_stock')
    ->purpose('Check product stock levels')
    ->parameter('sku', 'string', 'Product SKU', required => 1)
    ->webhook('GET', 'https://api.warehouse.com/stock/${args.sku}')
    ->output(SignalWire::SWAIG::FunctionResult->new('Stock for ${args.sku}: ${response.quantity} units'))
    ->fallback_output(SignalWire::SWAIG::FunctionResult->new('Could not check stock right now'));

$agent->register_swaig_function( $data_map->to_swaig_function );
```

DataMap tools execute on SignalWire's servers -- no webhook needed. The SDK generates the `data_map` structure in the SWML with variable expansion (`${args.*}`, `${response.*}`, `${global_data.*}`), foreach iteration, expression matching, and error handling. Your agent never receives the callback; SignalWire handles the entire API call.

### 3. Skills (Packaged Integrations)

```perl
$agent->add_skill('web_search', { api_key => '...', search_engine_id => '...' });
$agent->add_skill('datetime');
$agent->add_skill('math');
```

One line. The skill auto-registers its tools, injects prompt sections, adds speech hints, and validates dependencies. No manual wiring.

---

## The Skills System

Skills are self-contained modules that package tools, prompts, hints, and configuration into a single `add_skill()` call. Each skill:

- Inherits from `SignalWire::Skills::SkillBase` with required `setup` and `register_tools` methods
- Declares `required_packages` and `required_env_vars` for dependency validation
- Calls `$self->define_tool(...)` to register SWAIG functions
- Can inject prompt sections via `get_prompt_sections`
- Can provide speech hints via `get_hints`
- Can contribute global data via `get_global_data`
- Supports multiple instances with different configs (e.g., two `web_search` skills with different engines) via `supports_multiple_instances`

**Built-in skills:** `datetime`, `math`, `web_search`, `wikipedia_search`, `weather_api`, `google_maps`, `datasphere`, `datasphere_serverless`, `native_vector_search`, `spider`, `swml_transfer`, `play_background_file`, `info_gatherer`, `api_ninjas_trivia`, `joke`, `claude_skills`, `custom_skills`.

The elegance is composability: skills don't know about each other, but they all register cleanly into the same agent. A single agent can combine web search, datetime, a custom booking tool, and a DataMap stock checker -- all declared in `BUILD`, all generating correct SWML with proper function definitions, all routed to the right handler.

---

## Contexts and Steps: Priming the State Machine

The contexts/steps system lets you define structured workflows declaratively. Instead of hoping the LLM follows instructions about conversation flow, you mechanically enforce it:

```perl
my $ctx = $agent->define_contexts;

my $greeting = $ctx->add_context('default');
my $step1    = $greeting->add_step('welcome');
$step1->set_text('Greet the user and ask how you can help.');
$step1->set_valid_steps(['collect_info']);
$step1->set_functions(['check_hours']);   # Only this tool available here

my $step2 = $greeting->add_step('collect_info');
$step2->set_text("Collect the user's name and email.");
$step2->set_step_criteria('User has provided both name and email');
$step2->set_gather_info(output_key => 'user_profile');
$step2->add_gather_question('name',  'What is your name?',  type => 'string');
$step2->add_gather_question('email', 'What is your email?', type => 'string', confirm => 1);
$step2->set_valid_steps(['confirm']);

my $step3 = $greeting->add_step('confirm');
$step3->set_text('Confirm the information and say goodbye.');
$step3->set_functions('none');   # No tools -- just confirm and end
```

This generates SWML with a complete contexts/steps structure. The platform enforces navigation rules, restricts which functions are available at each step, collects structured data with typed questions and confirmation, and tracks transitions with trigger attribution in the enriched call_log. The LLM can't skip steps, can't call restricted tools, and can't navigate to disallowed contexts -- not because it was told not to, but because the mechanisms don't exist in its world. This is PGI (Programmatically Governed Inference) in practice.

**Multi-context** agents can define separate conversation modes (e.g., "sales" and "support") with isolated function sets, and use `set_valid_contexts()` to control switching. Context transitions support 4-mode reset (consolidate x full_reset) with conversation history summarization or archival.

---

## Programmatically Governed Inference (PGI)

The contexts/steps system is the SDK's implementation of a broader architectural discipline: **Programmatically Governed Inference**. PGI starts from a single design rule: *do not tell the AI anything it does not need to know.*

Current AI models are extraordinarily good at language -- understanding loosely phrased human input, mapping intent onto structured actions, and rendering system decisions back into natural speech. They are also inconsistent, non-deterministic, and prone to confident error. These are not bugs that will be fixed in the next model generation. They are properties of probabilistic inference itself. The industry's dominant response -- prompt harder and hope ("prompt and pray") -- treats the model as the brain of the system. PGI rejects this entirely. The model is not the brain. It is a controlled participant inside a deterministic system that was always in charge.

### The Four Layers

PGI is enforced through four layers of constraint, each operating independently. Only the first depends on the model's cooperation. The remaining three are mechanical.

**Layer 1: Semantic Constraints** -- The model receives a prompt describing its role and instructions for how to behave. This is the weakest layer; it depends on probabilistic compliance. PGI treats it as guidance, not enforcement. The remaining layers are the law.

**Layer 2: Schema Constraints** -- At each step, the model sees only the tools registered for that step. Tools belonging to other steps do not exist in its function schema. The model cannot call them, reference them, or reason about them. This is the difference between telling someone not to open a door and removing the door from the building.

**Layer 3: Transition Constraints** -- Each step defines which steps it can transition to. The platform validates every transition against this whitelist. The model cannot skip phases, loop back to completed steps, or jump to unreachable states. The conversational flow is governed by the same deterministic logic as any well-designed state machine.

**Layer 4: Execution Authority** -- When the model calls a tool, it is making a request, not issuing a command. The tool handler accesses authoritative state, applies business logic, and returns both a response for the model to speak and a set of actions for the platform to execute. The model does not update state. The model does not decide what happens next. The platform does.

### PGI in Practice: Blackjack

```perl
my $betting = $ctx->add_step('betting');
$betting->set_functions(['place_bet']);
$betting->set_valid_steps(['playing']);

my $playing = $ctx->add_step('playing');
$playing->set_functions([ 'hit', 'stand', 'double_down' ]);
$playing->set_valid_steps(['hand_complete']);

my $lost = $ctx->add_step('you_lost');
$lost->set_functions([]);
$lost->set_valid_steps([]);
```

During the betting step, the model can only call `place_bet`. It cannot deal cards, draw cards, or resolve hands because those functions are not in its schema. When the tool handler transitions to the playing step, `place_bet` disappears and `hit`, `stand`, `double_down` appear. The model's capabilities change not because it was told to behave differently, but because the available operations were mechanically replaced.

The `you_lost` step has zero functions and zero valid transitions. The game is over. A user can beg, negotiate, or attempt social engineering. None of it works, because the mechanism for continuing does not exist. There is nothing for the model to comply with or resist. The interaction is structurally complete.

The tool handler demonstrates execution authority -- the model has no idea a step change is about to happen:

```perl
sub handle_hit {
    my ($args, $raw_data) = @_;
    my $game  = $raw_data->{global_data}{game_state};
    my $card  = pop @{ $game->{deck} };
    push @{ $game->{player_hand} }, $card;
    my $score = calculate_hand( $game->{player_hand} );

    my $result = SignalWire::SWAIG::FunctionResult->new(
        "You drew " . format_card($card) . ". Your total is $score."
    );
    $result->update_global_data({ game_state => $game });

    $result->swml_change_step('you_lost') if $score > 21;

    return $result;
}
```

The model speaks the result. The platform changes the step. The model's world changes without its participation.

### Data Isolation

PGI extends to how data flows through the system. The model operates on a projection of reality, not the full truth. Authoritative state lives in structured data (`global_data`) that the model sees only in curated subsets. In a blackjack game, the model knows the player's chip count and visible cards. It does not know the deck composition, the dealer's hidden card, or the internal scoring calculations. In an ordering system, the model knows which items have been added. It does not know the internal pricing logic, tax calculations, or inventory state.

The model cannot hallucinate a price it has never seen. It cannot promise availability it has no knowledge of. It can only report what the system tells it to report.

### Why PGI, Not Guardrails

PGI produces a property that makes it fundamentally different from guardrails, output filtering, or any other containment strategy: **the model does not know it is being governed.** It does not know that other tools exist elsewhere in the system. It does not know that a state machine is managing the interaction. It sees its current world -- a prompt, a set of functions, a conversation history -- and operates within it. There is nothing to reason around, nothing to game, nothing to circumvent.

The strongest test of any PGI system: replace the model with a rigid scripted menu ("press 1 for tacos, press 2 for drinks") and the system would still produce correct outcomes. The tool handlers would still validate input, enforce business rules, and manage state. The experience would be worse, but every order would be accurate and every transition would follow the rules. The model makes the interaction natural. The software makes it correct. In a PGI system, those are independent properties.

The SDK's contexts/steps/function restrictions are the primitives that make PGI mechanical rather than aspirational. The developer defines steps, scopes tools to steps, declares transitions, and writes tool handlers that return structured results with platform actions. The platform enforces all of it. The developer brings domain expertise. The SDK provides the governance infrastructure.

---

## Deployment: One `run()` Call

<!-- snippet: no-run references a user-defined agent subclass not in this snippet -->
```perl
my $agent = MyAgent->new;
$agent->run;
```

That single call auto-detects the environment and does the right thing:

| Environment | Detection | What Happens |
|-------------|-----------|--------------|
| **Standalone** | Default | Starts a Plack/PSGI HTTP server |
| **AWS Lambda** | Lambda context object | Returns Lambda-formatted response |
| **Google Cloud Functions** | GCF environment markers | Returns Flask-compatible response |
| **Azure Functions** | Azure context object | Returns Azure HttpResponse |
| **CGI** | CGI environment variables | Reads stdin, writes stdout |

Each mode handles authentication differently (HTTP Basic Auth, API Gateway authorizers, function-level auth), constructs webhook URLs using the correct public endpoint (Lambda function URL, GCF URL, Azure app URL), and formats request/response bodies per platform. You write one agent, deploy it anywhere.

For standalone mode, the SDK provides:
- Kubernetes health (`/health`) and readiness (`/ready`) probes (no auth)
- SSL/TLS support via `SWML_SSL_ENABLED`, `SWML_SSL_CERT_PATH`, `SWML_SSL_KEY_PATH`
  (or an explicit `ssl_cert` / `ssl_key` pair passed to `serve`/`run`)
- CORS configuration

---

## Multi-Agent Hosting

<!-- snippet: no-run references a user-defined agent subclass not in this snippet -->
```perl
use SignalWire::Server::AgentServer;

my $server = SignalWire::Server::AgentServer->new( host => '0.0.0.0', port => 3000 );
$server->register( SalesAgent->new,   '/sales' );
$server->register( SupportAgent->new, '/support' );
$server->register( TriageAgent->new,  '/triage' );
$server->run;
```

One process, multiple agents, route-based dispatch. Each agent gets its own SWML endpoint and SWAIG callback routing. SIP routing can map usernames to specific agents.

---

## Dynamic Configuration and Multi-Tenancy

```perl
$agent->set_dynamic_config_callback(sub {
    my ($query_params, $body_params, $headers, $agent) = @_;

    my $tenant = $headers->{'x-tenant-id'} // 'default';
    my $config = load_tenant_config($tenant);
    $agent->prompt_add_section('Company', $config->{company_info});
    $agent->set_global_data({ tenant_id => $tenant, tier => $config->{tier} });
    if ($config->{tier} eq 'premium') {
        $agent->add_skill('advanced_search');
    }
});
```

Each inbound request creates an **ephemeral copy** of the agent. The callback customizes it per-request -- different prompts, skills, global data, languages, tools. The original agent is unchanged. This enables multi-tenancy from a single deployment: one agent instance serves hundreds of tenants with tailored behavior.

---

## Search System

The SDK includes a hybrid search engine for local knowledge bases, exposed
through the `native_vector_search` skill. It reads a self-contained
`.swsearch` index file (or connects to a remote search server), and can
auto-build the index from a source directory on first use.

**In agents** (local mode, auto-building the index if it is missing):
```perl
$agent->add_skill('native_vector_search', {
    tool_name   => 'search_docs',
    description  => 'Search product documentation',
    index_file  => 'knowledge.swsearch',
    build_index => 1,
    source_dir  => './docs',
    file_types  => [ 'md', 'txt' ],
    count       => 5,
});
```

**Remote mode** (connecting to a running search server):
```perl
$agent->add_skill('native_vector_search', {
    tool_name  => 'search_docs',
    remote_url => 'http://localhost:8001',
    index_name => 'default',
});
```

The search system supports:
- **Document processing:** PDF, DOCX, Excel, PowerPoint, HTML, Markdown, plain text
- **Chunking strategies:** sentence, sliding window, paragraph, page, semantic, topic, QA-optimized, markdown-aware, JSON
- **Embedding models:** mini (384d, fast), base (768d), large
- **Hybrid search:** Vector similarity + keyword matching + filename search + metadata search
- **Backends:** SQLite (`.swsearch` files for local/serverless) or PostgreSQL (pgvector for production)
- **Dependencies:** the search backend's Perl modules are declared in the `cpanfile`; `cpanm --installdeps .` pulls them in

The `.swsearch` format is a self-contained SQLite database with embeddings, chunks, and metadata -- deploy it alongside your agent to Lambda or any serverless platform.

---

## Prefab Agents

Production-ready patterns for common use cases:

```perl
use SignalWire::Prefabs::InfoGatherer;
use SignalWire::Prefabs::Receptionist;

# Collect structured data
my $gatherer = SignalWire::Prefabs::InfoGatherer->new(
    questions => [
        { key_name => 'name',  question_text => 'What is your name?' },
        { key_name => 'issue', question_text => 'Describe your issue', confirm => 1 },
    ],
);

# Route calls to departments
my $receptionist = SignalWire::Prefabs::Receptionist->new(
    departments => [
        { name => 'Sales',   number => '+15551234567', description => 'Product inquiries' },
        { name => 'Support', number => '+15559876543', description => 'Technical help' },
    ],
);
```

Five prefabs: **InfoGatherer**, **Survey**, **Receptionist**, **FAQBot**, **Concierge**. Each generates complete SWML with appropriate prompts, tools, and workflows. You instantiate, customize, deploy.

---

## AI Configuration

Everything the platform supports, the SDK exposes as methods:

```perl
# LLM tuning
$agent->set_prompt_llm_params(temperature => 0.3, top_p => 0.9, barge_confidence => 0.7);

# Multi-language
$agent->add_language(
    name             => 'Spanish',
    code             => 'es-ES',
    voice            => 'google.es-ES-Neural2-A',
    speech_fillers   => ['Un momento...'],
    function_fillers => ['Buscando...'],
);

# Speech recognition
$agent->add_hints([ 'SignalWire', 'SWML', 'SWAIG' ]);
$agent->add_pronunciation('SignalWire', 'Signal Wire');

# Vision, thinking, inner dialog
$agent->set_params({ enable_vision => JSON::true, vision_model => 'gpt-4o' });
$agent->set_params({ enable_thinking => JSON::true, thinking_model => 'o4-mini' });

# Interruption control
$agent->set_params({
    barge_match_string => '^(stop|cancel|nevermind)$',
    barge_min_words    => 2,
    barge_confidence   => 0.8,
});

# Native functions with custom fillers
$agent->set_native_functions([ 'check_time', 'wait_for_user' ]);
$agent->add_internal_filler('check_time', 'en', [ 'Let me check the time...' ]);

# Call recording (set on the agent constructor or via the attributes)
$agent->record_call(1);
$agent->record_format('wav');
$agent->record_stereo(1);

# Call flow verbs
$agent->add_pre_answer_verb('play', { url => 'ringback.wav' });
$agent->add_post_ai_verb('hangup', {});
```

Each of these would require understanding and manually constructing the correct SWML JSON structure. The SDK provides named methods with proper defaults.

---

## swaig-test CLI

Test without deploying:

```bash
# List available tools (file mode: load the agent script in-process)
swaig-test --file my_agent.pl --list-tools

# Execute a specific tool with a parameter
swaig-test --file my_agent.pl --exec get_weather --param city="San Francisco"

# Dump generated SWML for inspection
swaig-test --file my_agent.pl --dump-swml

# URL mode: test a running agent over HTTP (auth embedded in the URL)
swaig-test --url http://user:pass@localhost:3000/ --list-tools
swaig-test --url http://user:pass@localhost:3000/ --exec get_weather --param city="San Francisco"
```

---

## Authentication

The SDK handles auth automatically:

- **Auto-generated credentials:** If no env vars set, generates `user_XXXX` / random password and prints to console
- **Environment variables:** `SWML_BASIC_AUTH_USER` / `SWML_BASIC_AUTH_PASSWORD`
- **Embedded in URLs:** Webhook URLs include `user:pass@host` automatically
- **Per-function tokens:** Secure functions get `__token=...` query params with expiration
- **Platform-specific:** Different auth handling for Lambda, CGI, GCF, Azure (each platform has its own auth mechanism)

---

## What You'd Have to Build Without the SDK

| Capability | Without SDK | With SDK |
|-----------|-------------|----------|
| SWML document | Hand-craft JSON | Auto-generated from Python |
| Webhook server | Build and deploy separately | Built into the agent process |
| URL routing | Manual Plack/PSGI setup | Automatic route registration |
| Auth tokens | Manual JWT/token system | Auto-generated per call/function |
| Proxy detection | Parse headers yourself | Automatic (ngrok, LB, CDN) |
| Tool schemas | Write JSON Schema by hand | `define_tool()` |
| Serverless deploy | Platform-specific handler code | `agent.run()` auto-detects |
| Multi-language | Manually construct language arrays | `add_language()` one-liner |
| State machine | Manually build contexts JSON | Fluent `define_contexts()` API |
| Structured data collection | Build gather configs by hand | `add_gather_question()` chain |
| Search/RAG | Build entire pipeline | `add_skill("native_vector_search")` |
| Multi-agent | Separate deployments + router | `AgentServer` with route registration |
| Dynamic config | Custom middleware | `set_dynamic_config_callback()` |
| Post-call analytics | Parse raw webhook payload | `on_summary()` callback |
| Health checks | Manual endpoints | Built-in `/health` and `/ready` |
| Call recording | Manual SWML verb insertion | `record_call()` |
| SSL/TLS | Manual cert configuration | Env var driven |

The SDK turns what would be a multi-file infrastructure project into a single Perl class. The SWML is correct by construction. The webhooks route themselves. The auth is automatic. The deployment is universal. The developer focuses on what the agent should *do*, not how to wire it together.
