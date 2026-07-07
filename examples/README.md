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
# Run any example directly (scripts/_env.sh sets up PERL5LIB for you)
source scripts/_env.sh
perl -Ilib examples/simple_agent.pl

# Check syntax without running
perl -Ilib -c examples/simple_agent.pl
```

## Examples by Category

### Getting Started

| File | Description |
|------|-------------|
| [simple_agent.pl](simple_agent.pl) | Full-featured agent with POM prompts, SWAIG tools, multilingual support, and LLM parameter tuning |
| [simple_static.pl](simple_static_agent.pl) | Traditional static agent with fixed configuration (no dynamic callback) |
| [simple_dynamic_agent.pl](simple_dynamic_agent.pl) | Agent with per-request dynamic configuration callback |
| [simple_dynamic_enhanced.pl](simple_dynamic_enhanced.pl) | Enhanced dynamic config: VIP, department, customer ID, language |
| [declarative.pl](declarative_agent.pl) | Declarative prompt definition with subsections and post-prompt summaries |
| [custom_path.pl](custom_path_agent.pl) | Agent at a custom route (/chat) with mood-based personalization |
| [multi_agent_server.pl](multi_agent_server.pl) | Multiple agents on one server: healthcare, finance, retail |

### Dynamic Configuration

| File | Description |
|------|-------------|
| [comprehensive_dynamic.pl](comprehensive_dynamic_agent.pl) | Advanced per-request config: tier-based features, industry prompts, A/B testing |

### Contexts and Steps

| File | Description |
|------|-------------|
| [contexts_demo.pl](contexts_demo.pl) | Multi-persona workflow with context switching and step navigation |
| [gather_info.pl](gather_info_demo.pl) | Gather-info mode for structured data collection (patient intake) |

### DataMap (Server-Side Tools)

| File | Description |
|------|-------------|
| [datamap_demo.pl](datamap_demo.pl) | DataMap builder API for creating tools that execute on SignalWire servers |
| [advanced_datamap.pl](advanced_datamap_demo.pl) | Advanced DataMap: expressions, webhooks, form encoding, fallback chains |

### SWML Services

| File | Description |
|------|-------------|
| [auto_vivified.pl](auto_vivified_example.pl) | Auto-vivified verb methods on SWMLService |
| [swml_service.pl](swml_service_example.pl) | Basic SWML service: voicemail, IVR menu, call transfer, call recording |
| [dynamic_swml_service.pl](dynamic_swml_service.pl) | Dynamic SWML with per-request document generation (greeting/router) |
| [swml_service_routing.pl](swml_service_routing_example.pl) | Path-based routing with multiple SWML sections |

### Skills

| File | Description |
|------|-------------|
| [skills_demo.pl](skills_demo.pl) | Loading and configuring built-in skills (datetime, math, web_search) |
| [joke_skill.pl](joke_skill_demo.pl) | Joke skill via the modular skills system with DataMap |
| [web_search.pl](web_search_agent.pl) | Web search agent using Google Custom Search API skill |
| [web_search_multi_instance.pl](web_search_multi_instance_demo.pl) | Multiple web search instances (general, news, quick) |
| [wikipedia.pl](wikipedia_demo.pl) | Wikipedia search skill for factual information retrieval |
| [datasphere.pl](datasphere.pl) | DataSphere skill with multiple instances and custom tool names |
| [datasphere_multi_instance.pl](datasphere_multi_instance_demo.pl) | DataSphere multi-instance with custom tool names |
| [datasphere_serverless_env.pl](datasphere_serverless_env.pl) | DataSphere serverless from environment variables |
| [datasphere_webhook_env.pl](datasphere_webhook_env_demo.pl) | Webhook-based DataSphere from environment variables |

### SWAIG Features

| File | Description |
|------|-------------|
| [swaig_features.pl](swaig_features_agent.pl) | Enhanced SWAIG: fillers, multilingual fillers, forecast tools |
| [joke_agent.pl](joke_agent.pl) | Raw data_map configuration with API Ninjas joke API |

### LLM Parameter Tuning

| File | Description |
|------|-------------|
| [llm_params.pl](llm_params_demo.pl) | Three agent personalities: precise, creative, customer service |

### Session and State

| File | Description |
|------|-------------|
| [session_state.pl](session_and_state_demo.pl) | Session lifecycle: on_summary, global_data, tool result actions |
| [call_flow.pl](call_flow_and_actions_demo.pl) | Call flow verbs (pre/post-answer), debug events, transfer/SMS/hold actions |

### Virtual Helpers (FunctionResult Actions)

| File | Description |
|------|-------------|
| [record_call.pl](record_call_example.pl) | Record/stop recording: basic, advanced, compliance, and workflows |
| [room_and_sip.pl](room_and_sip_example.pl) | Join rooms, SIP REFER transfers, conferences, escalation workflows |
| [tap.pl](tap_example.pl) | WebSocket/RTP tap streaming: monitoring, compliance, multi-tap |

### Deployment

| File | Description |
|------|-------------|
| [kubernetes.pl](kubernetes_ready_agent.pl) | Kubernetes-ready agent with health checks and env config |
| [lambda_agent.pl](lambda_agent.pl) | AWS Lambda / serverless deployment pattern |
| [multi_endpoint.pl](multi_endpoint_agent.pl) | Multiple endpoints (SWML, SWAIG, health) from a single agent |

### RELAY Client

| File | Description |
|------|-------------|
| [relay_demo.pl](relay_answer_and_welcome.pl) | RELAY client: answer inbound calls and play TTS over WebSocket |

### REST Client

| File | Description |
|------|-------------|
| [rest_demo.pl](rest_demo.pl) | REST client: list resources, search numbers, manage agents |

### Prefab Agents

| File | Description |
|------|-------------|
| [dynamic_info_gatherer.pl](dynamic_info_gatherer_example.pl) | Dynamic InfoGatherer with callback-based question selection |
| [prefab_info_gatherer.pl](info_gatherer_example.pl) | InfoGatherer prefab for structured data collection |
| [prefab_survey.pl](survey_agent_example.pl) | Survey prefab for conducting structured surveys |
| [concierge.pl](concierge_agent_example.pl) | Concierge prefab for venue amenities, services, and hours |
| [receptionist.pl](receptionist_agent_example.pl) | Receptionist prefab for call routing to departments |
| [faq_bot.pl](faq_bot_agent.pl) | FAQ Bot prefab for answering questions from a knowledge base |

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

For web search:

```bash
export GOOGLE_SEARCH_API_KEY=your-api-key
export GOOGLE_SEARCH_ENGINE_ID=your-engine-id
```

For joke agent:

```bash
export API_NINJAS_KEY=your-api-key
```

