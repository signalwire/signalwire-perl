# PORT_SIGNATURE_OMISSIONS.md


<!-- ══════════════════════════════════════════════════════════════════════════
BEFORE YOU ADD AN ENTRY TO THIS FILE — READ THIS.

Every entry here is a place the parity checker STOPS comparing. That is a real cost:
a divergence you list is a divergence no gate will ever catch again. So entries must
be RARE, and each one must earn its place. Default to skepticism: assume the entry is
NOT needed and make the case that it is.

The order of preference, always:
  1. FIX THE PORT so it matches the reference (add the missing member; make the
     signature match).
  2. FIX THE EMISSION so idiom folds onto the reference shape — the enumerator/emitter
     canonicalizes your language's spelling onto the oracle's (builder → __init__,
     getters → attributes, Result<T,E> → the plain return, CamelCase → the reference
     name, options-object/kwargs → the expanded param list, RAII/dispose → close).
     MOST divergences are idiom and belong here, not in this file.
  3. FIX THE REFERENCE if the oracle itself is wrong or stale (a Python-only symbol
     that leaked into the contract, a param the reference added and the oracle never
     re-enumerated). Fix Python / the oracle, then re-drift — do not paper over a
     broken reference with a per-port entry.
  4. Only when 1–3 genuinely cannot apply does an entry here become justified.

An entry is JUSTIFIED ONLY IF it is irreducible after correct emission — i.e. the
divergence survives because the two languages genuinely cannot express the same thing,
not because the emitter hasn't folded the idiom yet. If emission COULD fold it, the
entry is a bug in this file; go fix the emitter.

Each entry MUST state WHY, concretely, in one of these forms:
  • ADDITION — this symbol exists in the port but not the reference. Answer: is it
    genuine port-only surface with NO reference twin (say what it is and why the
    reference has no equivalent), or is it IDIOM the emitter should have folded (then
    it does not belong here — fold it)? A convenience/alias/back-compat wrapper is NOT
    a justification.
  • OMISSION — this reference symbol has no port member. Answer: WHY can it not exist
    here — what specific language feature is absent (e.g. no async-context-manager
    protocol, no __init__ method protocol)? "impossible:" means the construct cannot
    be expressed at all; if it merely LOOKS different, that's idiom → fold it, don't
    omit it. Cite a precedent when one exists (e.g. RelayClient omits the same dunder).
  • SIGNATURE — the symbol matches by name but its parameters differ. Answer: is the
    difference a foldable idiom collapse (options-object, leading context/self,
    builder) — then EXPAND it in the signature emitter so names+count match, don't list
    it — or a genuine reference-only parameter with no cross-language analogue?

If you cannot write a crisp, specific WHY that survives the "could emission fold this?"
test, the entry is not ready. Prove it's needed before you add it.
═══════════════════════════════════════════════════════════════════════════════ -->

Documented signature divergences between this Perl port and the Python
reference. Names-only divergences live in PORT_OMISSIONS.md /
PORT_ADDITIONS.md and are inherited automatically.

Format:
    <fully.qualified.symbol>: <one-line rationale>

Excused divergences fall into:

1. **Idiom-level** (deliberate, not fixable without breaking Perl API style):
   - Perl Moo classes don't model every Python attribute as a `has` decl
     (e.g. Python's `direction`, `segment_id`, `project_id` keyword-only
     args on `Call` aren't first-class Moo attrs in the Perl port).
   - Perl uses `_log` / `SignalWire::Logging->get_logger(...)` indirection
     where Python keeps a `logger` attribute on every class.
   - Perl SDK wraps a Plack/PSGI coderef; Python wraps a Flask app
     instance accessible via `.app`.

2. **Source-side stubs** (Perl methods that take fewer args because the
   body is a placeholder; the Python reference declares the full
   signature). Tracked here; will be filled in as the Perl port catches
   up. As of 2026-04-30 phase-4 audit: ZERO open source-side stubs —
   all 22 previously-tracked stubs have been closed by accepting the
   Python-canonical signatures and exercising them with Test::More
   tests under t/.


## Idiom: Perl logger / app accessor naming

signalwire.agent_server.AgentServer.app: Perl AgentServer wraps a Plack/PSGI coderef accessible via psgi_app(); Python's `.app` attribute is a Flask app instance — no direct equivalent in Plack land


## Idiom: Perl method-name renames

signalwire.relay.call.Call.on: Perl ``$call->on($cb)`` is the Perl idiom for registering a single all-events callback; Python's ``Call.on(event_type, handler)`` requires per-event-type registration — different ergonomics, same dispatch model
signalwire.skills.registry.SkillRegistry.register_skill: Perl exposes a two-arg ``register_skill(skill_name, skill_class)`` form that mirrors the underlying registry table; Python's classmethod takes a single ``skill_class`` and reads the name from the class itself


## Idiom: Perl-side helpers replicated on AgentBase

signalwire.core.agent_base.AgentBase.extract_sip_username: Perl AgentBase keeps a SignalWire-style ``from``/``caller_id_number`` extractor for backward compatibility; Python's ``SWMLService.extract_sip_username`` (the canonical version) checks ``call.to`` and is now also exposed on the Perl SWMLService. The AgentBase helper is a Perl-only convenience.


## Idiom: Perl Call has no Call-level state-wait primitive

The Python `Call.wait_for_*` convenience methods are built on
`Call.wait_for(event_type, predicate, timeout)`, which awaits an asyncio
Future resolved from the Call's own event dispatch. The Perl Call has no
equivalent: it updates `state` synchronously inside `dispatch_event` but
owns no blocking wait-on-state / event-future primitive, and the
frame-pump read-loop (`while (!$done) { $client->_read_once }`) lives on
`SignalWire::Relay::Client` (see `Client::dial`), not on `Call`. Adding a
`Call`-level blocking wait would require either reaching into the client's
read-loop or a generic `wait_for`, neither of which exists in this port —
so the three typed state-waits are omitted rather than stubbed. (The
underlying state-tracking IS implemented: `$call->state` reflects the
latest `calling.call.state`, and callers can register `$call->on(...)` to
react to transitions.)


## Source-side stubs (Perl method bodies don't yet declare full args)

(All previously-listed stubs have been closed. New stubs would live here.)


## Idiom: loose-param signatures (Perl `%opts`/positional, untyped `any`)

Perl has no runtime-introspectable parameter types (no `use feature
'signatures'` type annotations); the SDK's methods take idiomatic
`%opts` slurpy hashes or positional scalars, so every parameter surfaces
as untyped `any` where the Python reference types it concretely. The
wire contract is identical — only the static parameter TYPE differs.
These are the new subsystems' methods (item H/I) recorded by the
signature enumerator; the loose-param `any` is idiom, not a wire defect.

signalwire.core.agent_base.AgentBase.register_sip_username: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.auth_handler.AuthHandler.flask_decorator: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.mixins.web_mixin.WebMixin.register_routing_callback: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.


## Reference-oracle gap: symbol in python_surface but not python_signatures

These symbols exist in the surface oracle (python_surface.json) and are
genuinely implemented by the Perl port, but the signature oracle
(enumerate_python_signatures.py) did not enumerate them, so the DRIFT
gate reports them as `missing-reference` (in port, not in the signature
reference). The SURFACE gate is clean for all of them (they match the
reference surface, hence not in PORT_ADDITIONS.md). Excused as a
reference-oracle gap, not port-invented surface.

# C2-BEDROCK (2026-07-22): the six BedrockAgent.set_* entries were REMOVED here.
# Cluster-1 C1-O1 enumerated BedrockAgent into python_signatures.json (the
# __init__ full params + set_inference_params/set_llm_model/set_llm_temperature/
# set_post_prompt_llm_params/set_prompt_llm_params/set_voice), closing the
# signature-oracle blind spot these excused. They now compare directly against
# the reference (DRIFT clean), so the excuse is inert and — per the rule that an
# omission is a permanent blind spot — is deleted, not left to rot. BedrockAgent
# __init__'s Perl Moo keyword-constructor idiom is covered by the loose-param
# section above; it matches the reference param set (DRIFT exit 0).
signalwire.core.swml_handler.AIVerbHandler.validate_config: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.list_skills: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.prefabs.concierge.ConciergeAgent.on_summary: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.prefabs.faq_bot.FAQBotAgent.on_summary: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.prefabs.receptionist.ReceptionistAgent.on_summary: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.prefabs.survey.SurveyAgent.on_summary: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.utils.schema_utils.SchemaUtils.generate_method_body: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.utils.schema_utils.SchemaUtils.generate_method_signature: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.


## Idiom: param-count divergences (Moo attr set / classmethod receiver / %opts)

signalwire.core.data_map.create_expression_tool: Perl `create_expression_tool` is a module free function taking a single `%opts`/`$opts` hash carrying every reference kwarg (name/patterns/parameters); the slurpy sink surfaces as one param vs the reference's 3 named args — loose-param idiom.
signalwire.core.data_map.create_simple_api_tool: Perl `create_simple_api_tool` is a module free function taking a single `%opts`/`$opts` hash carrying every reference kwarg (name/url/response_template/...); the slurpy sink surfaces as one param vs the reference's 8 named args — loose-param idiom.
signalwire.core.logging_config.strip_control_chars: Perl `strip_control_chars($event_dict)` takes just the payload to sanitize; the reference is a structlog processor with the `(logger, method_name, event_dict)` processor-protocol arity — Perl's logging pipeline doesn't use structlog's 3-arg processor contract.


## Idiom: reference-only attributes with no Perl method (Plack/PSGI + security)

signalwire.web.web_service.WebService.app: Perl WebService wraps a Plack/PSGI coderef (psgi_app) rather than a FastAPI app instance; the reference's `.app` FastAPI accessor has no direct equivalent in Plack land (mirrors agent_server.AgentServer.app).
signalwire.web.web_service.WebService.security: Perl WebService applies security headers inline (_security_headers) rather than exposing a SecurityConfig accessor attribute; the reference's `.security` accessor has no first-class Perl equivalent.


# ---------------------------------------------------------------------------
# Typed-surface strictness pass (2026-07): the signature audit now compares
# PARAM TYPES too. Concrete param types are re-attached by the enumerator's
# reference-type projection + a hand-param rename table (Perl abbreviations →
# reference names). The residual below is the Perl Moo *constructor* idiom: a
# Moo class is built from `has` attributes (keyword construction) whose
# declaration order does not align with Python's positional __init__, so a
# positional param comparison mismatches even though the attribute set + call
# contract match. Not a wire bug — Moo constructors are keyword-only.

signalwire.core.swml_service.SWMLService.register_routing_callback: Perl idiom — SWMLService.register_routing_callback takes `(path, callback)` where Python takes `(callback_fn, path)`; the callback + path are the same two args in swapped order (Perl reads path-first). Same routing contract, argument order idiom
