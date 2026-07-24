# PORT_OMISSIONS.md


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

Python-reference symbols the Perl port does not implement, each with an
explicit impossible:/approved: rationale.
One line per symbol: `<fully.qualified.symbol>: <one-sentence rationale>`.
Checked by `scripts/diff_port_surface.py` against `python_surface.json`.

See also: PORT_ADDITIONS.md for Perl-only extensions.


## Reference-symbol omissions (impossible:/approved: only)

Each line: `<symbol>: impossible: <why the OO-idiom cousin TS/PHP also can't>` or
`<symbol>: approved: <human sign-off>`. Everything else is a bug — the gate
(`diff_port_surface.py`) rejects any other prefix. Item H/I pass, 2026-07.

signalwire.core.agent.tools.decorator.ToolDecorator: impossible: Python @tool decorator-protocol API; Perl/Moo has no method-decorator feature — tools register via define_tool directly (TS+PHP omit identically)
signalwire.core.agent.tools.decorator.ToolDecorator.create_class_decorator: impossible: Python @tool decorator-protocol API; Perl/Moo has no method-decorator feature — tools register via define_tool directly (TS+PHP omit identically)
signalwire.core.agent.tools.decorator.ToolDecorator.create_instance_decorator: impossible: Python @tool decorator-protocol API; Perl/Moo has no method-decorator feature — tools register via define_tool directly (TS+PHP omit identically)
signalwire.core.agent.tools.registry.ToolRegistry.register_class_decorated_tools: impossible: Python @tool decorator-protocol API; Perl/Moo has no method-decorator feature — tools register via define_tool directly (TS+PHP omit identically)
signalwire.core.mixins.mcp_server_mixin.MCPServerMixin: impossible: method-less Python mixin class hosting add_mcp_server/enable_mcp_server; per the user ruling those two methods ARE ported (folded onto AIConfigMixin/AgentBase, present), but the standalone mixin CLASS itself has no Perl home — Perl composes AgentBase via roles, not a named MCPServerMixin class (TS/PHP fold identically)
signalwire.core.mixins.tool_mixin.ToolMixin.tool: impossible: Python @tool decorator-protocol API; Perl/Moo has no method-decorator feature — tools register via define_tool directly (TS+PHP omit identically). Raw ToolMixin.tool key for the SIGNATURE diff; folded agentbase-family.tool twin excused for the SURFACE diff.
agentbase-family.tool: impossible: Python @tool decorator-protocol API (folds to agentbase-family via the mixin-flatten fold); Perl/Moo has no method-decorator feature — tools register via define_tool directly (TS+PHP omit identically)
signalwire.agent_server.AgentServer.logger: impossible: Python holds a logging.Logger as a composition attr (logger -> class:logging_config.get_logger); Perl has no logger-attribute idiom exposing a Logger class — it logs via warn/module-level helpers, so there is no self-only accessor returning a Logger (TS/PHP getter-idiom ports surface theirs; Perl's Moo class does not).
signalwire.core.skill_base.SkillBase.logger: impossible: see AgentServer.logger — Perl SkillBase exposes no logger composition accessor (no Logger-class-holding attr in the Perl logging idiom).
signalwire.core.skill_manager.SkillManager.logger: impossible: see AgentServer.logger — Perl SkillManager exposes no logger composition accessor.
signalwire.skills.registry.SkillRegistry.logger: impossible: see AgentServer.logger — Perl SkillRegistry exposes no logger composition accessor.
signalwire.web.web_service.WebService.security: impossible: Python's WebService holds a SecurityConfig composition attr (security -> class:security_config.SecurityConfig); Perl's WebService applies security inline via a private _security_headers() sub and exposes no self-only accessor returning a SecurityConfig class.
signalwire.core.security.webhook_middleware.make_webhook_validation_dependency: impossible: framework-bound factory returning a FastAPI dependency; Perl ships the equivalent as the SignalWire::Security::WebhookMiddleware Plack middleware (a PORT_ADDITION) — the FastAPI-dependency FORM has no Plack analog (TS/PHP ship native middleware likewise)
signalwire.relay.client.RelayClient.__aenter__: impossible: Python async-context-manager protocol dunder; Perl uses explicit connect+disconnect — no __aenter__/__aexit__ equivalent (TS/PHP omit identically)
signalwire.relay.client.RelayClient.__aexit__: impossible: Python async-context-manager protocol dunder; Perl uses explicit connect+disconnect — no __aenter__/__aexit__ equivalent (TS/PHP omit identically)
signalwire.ai_chat.client.AIChatClient.__aenter__: impossible: Python async-context-manager protocol dunder; Perl has no context-manager language protocol — the AIChat client is used directly (construct-and-call), no with-block enter (TS/PHP omit identically)
signalwire.ai_chat.client.AIChatClient.__aexit__: impossible: Python async-context-manager protocol dunder; Perl has no context-manager language protocol — no with-block exit (TS/PHP omit identically)
signalwire.relay.client.RelayClient.__del__: impossible: Python finalizer dunder; Perl has no deterministic __del__ finalizer protocol (TS/PHP omit identically)
signalwire.relay.message.Message.__repr__: impossible: Python object-repr dunder; Perl provides the equivalent via a to_string method where user-facing, but the __repr__ FORM has no Perl analog on this data carrier (TS/PHP omit identically)
signalwire.rest._base.FabricResourcePUT: impossible: the Perl generated FabricResource base collapses the reference's CrudWithAddresses -> FabricResource(PATCH) / FabricResourcePUT(PUT) marker split into a single base carrying list_addresses; the PUT-vs-PATCH verb is baked per-resource via _update_method in each generated class's BUILDARGS, so there is no separate method-less PUT marker class to emit (a generated-layout limit the TS/PHP generators hit identically)



# ---------------------------------------------------------------------------
# NOTE — AIParams fields dropped via porting-sdk/rest-apis/x-sdk-overlay.yaml
# ---------------------------------------------------------------------------
# The following 5 fields of the spec schema AIParams (schema.json $defs/AIParams
# and components/schemas/AIParams in the calling + fabric REST specs) are HIDDEN
# from the SDK surface by the single authoritative overlay x-sdk-overlay.yaml —
# still accepted on the wire, dropped from the generated Perl AIParams data
# packages (REST Types/Calling, Types/Fabric, and SWML/Generated):
#   - audible_debug
#   - audible_latency
#   - verbose_logs
#   - enable_accounting
#   - cache_mode
# Reason: hidden via x-sdk-overlay.yaml: server-internal AI param, dropped from
# SDK surface per overlay policy (approved).
#
# These are NOT ledgered as diff_port_surface.py symbol lines: the surface oracle
# records AIParams as a method-less TYPE (class name only) and does not track its
# field members, so field-level hides never surface as SURFACE-DIFF omissions
# (the gate passes clean). This note is documentation only; the checker skips
# every '#'-prefixed line. languages_enabled is NOT dropped — it is emitted and
# marked '# deprecated:' per the overlay's deprecated list, so it is not recorded
# here either.

## B1 composition-attr / generated-model field-accessor omissions (fold branch)
# porting-sdk fix/agentbase-mixin-flatten-fold enriched the surface oracle with class-ref
# composition attributes + generated-model per-field accessors. Perl models generated payload
# classes as method-less DTOs and does not surface Moo `has` accessors as API — same idiom
# disposition ruby/ts/php take (wire JSON identical). See ALLOWLIST_DISCIPLINE.md §4c/§6-B1.


# Raw-key twins for the SIGNATURE diff (dual-key convention)
