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

# threading — Python's `threading.Thread(...)` inside a web-service code sample

## Python SignalWire SDK API (shown for concept parity, not Perl API)

# AgentBase / SkillBase camelCase convenience aliases (Python sugar only)

# SWMLService document lifecycle (Python prose; Perl port exposes
# equivalent semantics via the generated document)

# SIP routing — Python SDK mixins (Perl port offers equivalent routing
# via SWML + AgentServer; these exact names are Python-only)

# FastAPI / Starlette ecosystem (shown in Python web_service examples)

# Relay event / call methods (Python-only names; Perl Relay uses
# idiomatic method names -- see relay/docs for Perl forms)

# Miscellaneous Python SDK method names in illustrative snippets

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

## Private/underscored helpers in Python examples

<!--
  Leading-underscore Python method names inside illustrative Python code
  blocks showing how Python's AgentBase is extended internally. They are
  not Perl port surface.
-->


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
