# DOC_AUDIT_IGNORE

<!--
  Names the Layer C doc/example auditor (`porting-sdk/scripts/audit_docs.py`)
  should skip when checking this port's docs and examples.

  Every entry MUST have a rationale. If a name here maps to a real Perl
  API, delete it — the audit will catch typos only when this list is
  tight. If an entry is a genuine external or cross-language carryover,
  keep it with an explanation.

  Format: one name per line; `name: rationale` accepted; `#` comments
  allowed. Free-form prose belongs inside HTML comments like this one.

  The audit's regex treats `word.word(` as a method call. Most entries
  below are Python SDK references that appear inside ```python fenced
  blocks in the docs — the Perl documentation (Layer C content
  migration) reuses the Python SDK's prose and examples to illustrate
  concepts the Perl port mirrors behaviourally. They are NOT references
  to Perl APIs.
-->

## Python stdlib (inside ```python code blocks in docs)

# datetime / time

# logging / os.path — Python standard library utility calls in example code
warning: Python stdlib logging.Logger.warning (Python code block)

# threading — Python's `threading.Thread(...)` inside a web-service code sample

## Python SignalWire SDK API (shown for concept parity, not Perl API)

# AgentBase / SkillBase camelCase convenience aliases (Python sugar only)

# SWMLService document lifecycle (Python prose; Perl port exposes
# equivalent semantics via the generated document)
build_document: Python SWMLService lifecycle method (Python code block)
build_voicemail_document: Python SWMLService subclass override (Python code block)
add_answer_verb: Python SWMLService helper (Python code block)
add_verb_to_section: Python SWMLService helper (Python code block)

# SIP routing — Python SDK mixins (Perl port offers equivalent routing
# via SWML + AgentServer; these exact names are Python-only)
enable_sip_routing: Python SDK mixin method (Python code block)
register_sip_username: Python SDK mixin method (Python code block)
register_routing_callback: Python SDK mixin method (Python code block)
setup_sip_routing: Python AgentServer method (Python code block)
register_customer_route: Python user-defined route (Python code block)
register_product_route: Python user-defined route (Python code block)

# FastAPI / Starlette ecosystem (shown in Python web_service examples)
add_directory: Python FastAPI StaticFiles mount (Python code block)
remove_directory: Python FastAPI StaticFiles unmount (Python code block)

# Relay event / call methods (Python-only names; Perl Relay uses
# idiomatic method names -- see relay/docs for Perl forms)

# Miscellaneous Python SDK method names in illustrative snippets
register_knowledge_base_tool: Python agent-internal helper (Python code block)
start: Python web-service/agent-server start method (Python code block)
tool: Python @AgentBase.tool(...) decorator (Python code block, decorator syntax)
validate_packages: Python third-party skills helper (Python code block)

## User-code placeholders in pedagogical Python snippets

<!--
  These names appear inside illustrative Python examples where they stand
  for code the READER would write (custom configs, analytics hooks,
  sample business logic). They are not API to implement.
-->

alert_ops_team: user-supplied hook in prose example (Python code block)
apply_custom_config: user-supplied hook in prose example (Python code block)
apply_default_config: user-supplied hook in prose example (Python code block)
get_customer_config: user-supplied hook in prose example (Python code block)
get_customer_settings: user-supplied hook in prose example (Python code block)
get_customer_tier: user-supplied hook in prose example (Python code block)
is_valid_customer: user-supplied hook in prose example (Python code block)
load_user_preferences: user-supplied hook in prose example (Python code block)
schedule_follow_up: user-supplied hook in prose example (Python code block)
send_to_analytics: user-supplied hook in prose example (Python code block)
load_session_state: user-supplied external-store accessor in the session-hooks prose example (the reader persists/loads session state in their own datastore; not a port API)
delete_session_state: user-supplied external-store accessor in the session-hooks prose example (the reader cleans up their own datastore; not a port API)

## Example-local attributes on custom-skill demo packages

<!--
  agent_guide.md's custom Weather skill (a reader-authored SkillBase subclass)
  declares its own Moo `has` attributes; they are accessed as `$self->NAME(...)`
  inside that example package. They are not SDK surface (the auditor resolves
  against port_surface.json, not example-local packages).
-->
default_units: example-local Moo attribute declared with `has` on the custom Weather skill package in agent_guide.md (reader-authored, not port surface)
timeout: example-local Moo attribute declared with `has` on the custom Weather skill package in agent_guide.md (reader-authored, not port surface)

## Real AgentBase attribute accessors (data attributes, not in the method surface)

<!--
  record_format / record_stereo are genuine AgentBase Moo attributes
  (`has record_format => (is => 'rw')`, `has record_stereo => ...`) used as
  `$agent->record_format('wav')` in sdk_features.md. port_surface.json records
  them as constructor/data attributes rather than methods, so the doc auditor's
  method resolver does not see them — the reference is valid, the accessor exists.
-->
record_format: real AgentBase Moo attribute accessor (has record_format => is rw); recorded as a data attribute, not a method, in port_surface.json
record_stereo: real AgentBase Moo attribute accessor (has record_stereo => is rw); recorded as a data attribute, not a method, in port_surface.json

## Private/underscored helpers in Python examples

<!--
  Leading-underscore Python method names inside illustrative Python code
  blocks showing how Python's AgentBase is extended internally. They are
  not Perl port surface.
-->

_configure_instructions: Python internal helper referenced in subclassing example
_register_custom_tools: Python internal helper referenced in subclassing example
_setup_contexts: Python internal helper referenced in subclassing example
_setup_static_config: Python internal helper referenced in subclassing example
_test_api_connection: Python internal helper referenced in subclassing example

## Regex false positives

<!--
  The `.name(` regex fires on strings that happen to contain a dot-word
  followed by `(`. These are not method calls.
-->

Mark: part of the voice identifier "inworld.Mark" in comments/strings (e.g. `voice => 'inworld.Mark'` inside a hashref - not a method call)
pl: appears in the substring ".pl(" inside the comment "joke_agent.pl (raw data_map)."
pm: appears in the substring ".pm(" inside a code comment path "lib/SignalWire/Skills/Builtin/Weather.pm (registered above)" - not a method call

## Audit-harness internals

<!--
  examples/relay_audit_harness.pl uses a private hook on Relay::Client to
  emit a method-bearing JSON-RPC frame back to the audit fixture (the
  fixture watches for `method:"signalwire.event"` from the client to
  count an event as dispatched; Python's bare-result ack does not
  satisfy that watcher). Calling the private helper from a harness is
  intentional and not part of the public API surface.
-->
_send: private hook used by examples/relay_audit_harness.pl to emit method-bearing ack frame to the audit fixture

## Private agent/swmlservice render helpers used by examples

<!--
  Some Perl examples drive Plack::Runner directly via `parse_options`
  (real Perl module method, in the Plack distribution — not part of the
  port's public surface) before handing the resulting PSGI app to the
  runner. The audit's regex picks up the method call but it isn't a
  port symbol.
-->
parse_options: Plack::Runner method called by SWML standalone examples
sleep: Perl built-in (and the SWML `sleep` verb the auto-vivified example illustrates) — appears in `sleep(...)` syntax inside an example
new: Perl/Moo constructor — appears in 148+ ClassName->new(...) call sites in docs and examples; not a port symbol to resolve
not_a_real_verb: intentional placeholder in swml_service_guide.md demonstrating that an unknown verb name dies ("Can't locate method ...") — not a port API

## Perl stdlib / CPAN module functions + doc placeholder (2026-07-08)

<!--
  Pre-existing DOC-AUDIT flags (present on the parent commit, before the AI-params
  change); all are standard Perl module functions or a doc placeholder, none an SDK method.
-->

Dumper: Data::Dumper::Dumper — core Perl debug serializer (api_reference example)
blessed: Scalar::Util::blessed — core ref-type check (skills_audit_harness)
decode_json: JSON::PP/JSON::XS decode_json — standard JSON module function
encode_json: JSON::PP/JSON::XS encode_json — standard JSON module function
uri_escape: URI::Escape::uri_escape — standard URI-encoding CPAN function
VERB: `$self->VERB($section, $config)` doc placeholder for any SWML verb name (swml_service_guide.md), not a literal method
