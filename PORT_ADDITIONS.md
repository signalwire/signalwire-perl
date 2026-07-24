# PORT_ADDITIONS.md


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

Symbols the Perl port ships that have no Python-reference equivalent.
One line per symbol: `<fully.qualified.symbol>: <one-sentence rationale>`.
Checked by `scripts/diff_port_surface.py` against `python_surface.json`.

See also: PORT_OMISSIONS.md for Python-reference symbols the port does not implement.

---

signalwire.agent_server.AgentServer.list_agents: port-only accessor: Perl convention surfaces a list-style getter where Python uses a generator or direct attribute access
signalwire.agent_server.AgentServer.psgi_app: port-only: Perl ports use Plack/PSGI; psgi_app returns a coderef any Plack handler consumes
signalwire.agents.bedrock.BedrockAgent.render_swml: port-only public alias: BedrockAgent overrides the public render_swml (Perl's user-facing SWML dump) to swap the ai verb for amazon_bedrock; Python keeps this internal as _render_swml (mirrors AgentBase.render_swml addition)
signalwire.core.contexts.ContextBuilder.attach_agent: port-only: weak-ref back to agent so validate() can check reserved tool-name collisions; Python avoids this via Python-level closures
signalwire.core.contexts.ContextBuilder.has_contexts: port-only: explicit presence check used in AgentBase build path; Python uses `if cb.contexts` idiom
signalwire.core.function_result.FunctionResult.to_json: port-only: convenience serializer; Python uses json.dumps(result.to_dict())
signalwire.core.function_result.RecordCall: perl_constants_idiom: SignalWire::SWAIG::RecordCall is a constants package single-sourcing the two closed-set string params record_call already validates inline — FORMAT (wav/mp3) and the write-side record DIRECTION (speak/listen/both). record_call still takes plain strings (the constants ARE the wire strings) so Python parity + custom callers are unchanged; this is the accepted-values source of truth + autocomplete, not a new compile-time check (record_call's own `die` still rejects bad values).
signalwire.core.function_result.RecordCall.directions: perl_constants_idiom: RecordCall->directions returns the accepted record-direction set [speak,listen,both] (see RecordCall).
signalwire.core.function_result.RecordCall.formats: perl_constants_idiom: RecordCall->formats returns the accepted recording-format set [wav,mp3] (see RecordCall).
signalwire.core.function_result.RecordCall.is_direction: perl_constants_idiom: RecordCall->is_direction($v) membership check over the record-direction set (see RecordCall).
signalwire.core.function_result.RecordCall.is_format: perl_constants_idiom: RecordCall->is_format($v) membership check over the recording-format set (see RecordCall).
signalwire.core.function_result.Tap: perl_constants_idiom: SignalWire::SWAIG::Tap is a constants package single-sourcing the two closed-set string params tap already validates inline — the tap DIRECTION (speak/HEAR/both — note 'hear', NOT record_call's 'listen') and the RTP CODEC (PCMU/PCMA — the SWAIG-tap 2-value set, NOT the RELAY connect superset). tap still takes plain strings (the constants ARE the wire strings) so Python parity + custom callers are unchanged; this is the accepted-values source of truth + autocomplete, not a new compile-time check (tap's own `die` still rejects bad values). Kept distinct from RecordCall so the three direction vocabularies / two codec vocabularies never unify.
signalwire.core.function_result.Tap.directions: perl_constants_idiom: Tap->directions returns the accepted tap-direction set [speak,hear,both] — distinct from RecordCall's [speak,listen,both] (see Tap).
signalwire.core.function_result.Tap.codecs: perl_constants_idiom: Tap->codecs returns the accepted SWAIG-tap codec set [PCMU,PCMA] — a strict subset of the RELAY connect codec superset (see Tap).
signalwire.core.function_result.Tap.is_direction: perl_constants_idiom: Tap->is_direction($v) membership check over the tap-direction set; rejects 'listen' (see Tap).
signalwire.core.function_result.Tap.is_codec: perl_constants_idiom: Tap->is_codec($v) membership check over the tap-codec set (see Tap).
signalwire.core.function_result.JoinConference: perl_constants_idiom: SignalWire::SWAIG::JoinConference is a constants package single-sourcing the four closed-set string params FunctionResult->join_conference already validates inline — BEEP (true/false/onEnter/onExit), RECORD (do-not-record/record-from-start), TRIM (trim-silence/do-not-trim), and the callback METHOD (GET/POST). join_conference still takes plain strings (the constants ARE the wire strings) so Python parity + custom callers are unchanged; this is the accepted-values source of truth + autocomplete, not a new compile-time check (join_conference's own `die` still rejects bad values, mirroring the reference's exact ValueError messages). The same Tier-1 idiom as RecordCall/Tap; kept distinct so the vocabularies never unify. Python validates these inline with no constants class.
signalwire.core.function_result.JoinConference.beeps: perl_constants_idiom: JoinConference->beeps returns the accepted beep-behaviour set [true,false,onEnter,onExit] (see JoinConference).
signalwire.core.function_result.JoinConference.records: perl_constants_idiom: JoinConference->records returns the accepted recording-mode set [do-not-record,record-from-start] (see JoinConference).
signalwire.core.function_result.JoinConference.trims: perl_constants_idiom: JoinConference->trims returns the accepted silence-trim set [trim-silence,do-not-trim] (see JoinConference).
signalwire.core.function_result.JoinConference.methods: perl_constants_idiom: JoinConference->methods returns the accepted callback HTTP-method set [GET,POST] (see JoinConference).
signalwire.core.function_result.JoinConference.is_beep: perl_constants_idiom: JoinConference->is_beep($v) membership check over the beep-behaviour set (see JoinConference).
signalwire.core.function_result.JoinConference.is_record: perl_constants_idiom: JoinConference->is_record($v) membership check over the recording-mode set (see JoinConference).
signalwire.core.function_result.JoinConference.is_trim: perl_constants_idiom: JoinConference->is_trim($v) membership check over the silence-trim set (see JoinConference).
signalwire.core.function_result.JoinConference.is_method: perl_constants_idiom: JoinConference->is_method($v) membership check over the callback HTTP-method set (see JoinConference).
signalwire.core.logging_config.debug: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.logging_config.error: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.logging_config.info: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.logging_config.warn: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.logging_config.LogLevel: perl_constants_idiom: SignalWire::Logging::LogLevel is a constants package single-sourcing the four log levels (debug/info/warn/error, ascending severity) that otherwise live only in SignalWire::Logging's private %LEVELS table. The logger's `level` attribute, SIGNALWIRE_LOG_LEVEL, and debug/info/warn/error still take/emit plain strings (the constants ARE the level strings) so Python stdlib-level-name parity is unchanged; this is the source of truth + autocomplete + a validation/severity helper, not a compile-time check.
signalwire.core.logging_config.LogLevel.all: perl_constants_idiom: LogLevel->all returns the four levels as an arrayref in ascending severity (see LogLevel).
signalwire.core.logging_config.LogLevel.is_valid: perl_constants_idiom: LogLevel->is_valid($level) membership check over the log-level set (see LogLevel).
signalwire.core.logging_config.LogLevel.severity: perl_constants_idiom: LogLevel->severity($level) returns the ascending-severity integer (debug=0..error=3) mirroring SignalWire::Logging's internal threshold numbers (see LogLevel).
signalwire.core.skill_manager.SkillManager.list_skills: port-only accessor: Perl convention surfaces a list-style getter where Python uses a generator or direct attribute access
signalwire.core.swml_builder.SWMLBuilder.add_raw_verb: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.add_verb: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.clear_section: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.get_section: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.has_section: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.to_hash: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.to_json: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.to_pretty_json: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_service.ParameterSchema: perl_tier2_builder_idiom: SignalWire::SWAIG::ParameterSchema is a fluent, typed builder (Moo + signatures + POD) for the JSON-Schema `parameters` blob define_tool() takes — the Perl realization of the cross-port Tier-2 flagship "typed SWAIG tool-parameter builder". ->to_hash produces the EXACT SAME `{ type=>'object', properties=>{...}, required=>[...] }` hashref the hand-written nested-hashref form produces, byte-identical (required omitted when empty); it is a convenience over the SAME wire output, NOT a new format. The untyped-hashref path into define_tool is untouched, so Python parity + every existing caller are unchanged (additive). Closed-set integration: ->enum takes an arrayref and the Tier-1 constant modules (RecordCall->formats/directions, Tap->directions/codecs) drop straight in as schema `enum:[...]`. Proven byte-identical in t/69_parameter_schema.t.
signalwire.core.swml_service.ParameterSchema.__init__: perl_tier2_builder_idiom: ParameterSchema->new constructs an empty builder (Moo root __init__); the fluent kind-methods accumulate onto it (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.array: perl_tier2_builder_idiom: ParameterSchema->array($name,$desc,of=>...) adds an `{ type=>'array', items=>{...} }` property; `of` may be a kind name, a nested ParameterSchema, or a hashref items schema (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.boolean: perl_tier2_builder_idiom: ParameterSchema->boolean($name,$desc) adds a `{ type=>'boolean' }` property (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.enum: perl_tier2_builder_idiom: ParameterSchema->enum($name,$values,$desc) adds a closed-set `{ type=>'string', enum=>[@$values] }` property; pass a Tier-1 constant set (RecordCall->formats, Tap->codecs, ...) so the schema enum is single-sourced from the set the verb validates against (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.integer: perl_tier2_builder_idiom: ParameterSchema->integer($name,$desc) adds an `{ type=>'integer' }` property (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.number: perl_tier2_builder_idiom: ParameterSchema->number($name,$desc) adds a `{ type=>'number' }` property (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.object: perl_tier2_builder_idiom: ParameterSchema->object($name,$desc,properties=>...) adds a nested `{ type=>'object', properties=>{...}, required=>[...] }` property; `properties` may be a nested ParameterSchema, a coderef given a child schema, or a hashref (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.required: perl_tier2_builder_idiom: ParameterSchema->required(@names) marks already-declared properties required (accumulates, de-dupes on emit); equivalent to passing required=>1 on the kind call (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.string: perl_tier2_builder_idiom: ParameterSchema->string($name,$desc) adds a `{ type=>'string' }` property (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.to_dict: perl_tier2_builder_idiom: ParameterSchema->to_dict is an alias for ->to_hash (SDK serialiser naming), identical output (see ParameterSchema).
signalwire.core.swml_service.ParameterSchema.to_hash: perl_tier2_builder_idiom: ParameterSchema->to_hash renders the JSON-Schema `parameters` hashref define_tool() takes — byte-identical to the hand-written literal, required omitted when empty (see ParameterSchema).
signalwire.core.swml_service.SWMLService.can: port-only: Perl can() accessor (Moo plumbing) — surfaced because SWMLService defines it; harmless but recorded
signalwire.core.swml_service.SWMLService.get_all_functions: tool_mixin_lifted: Perl exposes the tool registry's accessors directly on SWMLService; Python keeps these on ToolRegistry (accessed via agent.tool_registry.get_all_functions()).
signalwire.core.swml_service.SWMLService.get_basic_auth_credentials_with_source: port-only: Perl exposes a "with-source" variant that also returns where the credentials came from (env vs config vs explicit), used by debug routes; Python uses get_basic_auth_credentials() and infers source from logs.
signalwire.core.swml_service.SWMLService.get_function: tool_mixin_lifted: Perl exposes the tool registry's accessors directly on SWMLService; Python keeps these on ToolRegistry (accessed via agent.tool_registry.get_function()).
signalwire.core.swml_service.SWMLService.handle_additional_route: port-only: Perl exposes a hook for subclasses to mount extra routes onto the inherited PSGI app; Python achieves this via @app.route decorators.
signalwire.core.swml_service.SWMLService.has_function: tool_mixin_lifted: Perl exposes the tool registry's accessors directly on SWMLService; Python keeps these on ToolRegistry (accessed via agent.tool_registry.has_function()).
signalwire.core.swml_service.SWMLService.list_tool_names: port-only convenience accessor: returns the registered tool names in insertion order. Used by ContextBuilder->validate to surface reserved-name collisions; Python uses `cb._tools.keys()` directly.
signalwire.core.swml_service.SWMLService.on_swml_request: web_mixin_lifted: Perl rolls up WebMixin onto SWMLService so subclasses (notably AgentBase) can override the SWML-request hook directly; Python keeps on_swml_request on WebMixin (mirrors tool_mixin_lifted pattern).
signalwire.core.swml_service.SWMLService.remove_function: tool_mixin_lifted: Perl exposes the tool registry's mutators directly on SWMLService; Python keeps these on ToolRegistry (accessed via agent.tool_registry.remove_function()).
signalwire.core.swml_service.SWMLService.render_main_swml: port-only public hook: Perl exposes the main-section render path so subclasses can override; Python achieves this via _render_document overrides.
signalwire.core.swml_service.SWMLService.render_swml: port-only public alias: Perl exposes render_swml as the method users call to dump SWML; Python keeps this internal
signalwire.core.swml_service.SWMLService.swaig_pre_dispatch: port-only public hook: subclasses (notably AgentBase) override this to inject session-token validation and dynamic-config callbacks into the /swaig request path; Python uses _swaig_pre_dispatch (private with leading underscore).
signalwire.core.swml_service.SWMLService.to_psgi_app: port-only: Perl ports use Plack/PSGI; psgi_app returns a coderef any Plack handler consumes
signalwire.skills.datasphere.skill.DataSphereSkill.search_knowledge: port-only public method: Perl exposes the search call as a public method so the audit harness can drive it directly without going through the full SWAIG dispatch path. Python keeps the equivalent (_search_knowledge_handler) private.
signalwire.skills.spider.skill.SpiderSkill.scrape_url: port-only public method: Perl exposes the fetch+strip path as a public method so the audit harness can drive it without going through SWAIG dispatch. Python keeps the equivalent (_scrape_url_handler) private.
signalwire.skills.web_search.skill.WebSearchSkill.search_web: port-only public method: Perl exposes the Google-CSE call as a public method so the audit harness can drive it without going through SWAIG dispatch. Python keeps the equivalent (_search_web_handler) private.
signalwire.relay.call.Action.on_completed: port-only Action/Message helper; Python packs this into wait()/dispatch paths
signalwire.relay.call.Action.stop: port-only Action/Message helper; Python packs this into wait()/dispatch paths
signalwire.relay.call.Call.current_state: tier3-typed-state port-only: SignalWire::Relay::CallState-typed view of the call lifecycle state, alongside the bare-string ``state`` accessor (parity). Returns the same wire string ``state`` does (the CallState constants ARE the wire strings); the typed companion to CallState->is_state/->is_terminal. Python reads the bare ``state`` attribute.
signalwire.relay.call.Call.dispatch_event: port-only dispatcher/passthrough helper for Perl-idiomatic event plumbing
signalwire.relay.call.Call.is_terminal: tier3-typed-state port-only: true once the call reached a terminal lifecycle state (CallState terminal set = {ended}); delegates to SignalWire::Relay::CallState so the terminal definition is single-sourced. Returns false (never dies) on an unknown/forward-compat state. Python checks ``state == 'ended'`` inline.
signalwire.relay.call.CollectAction.collect_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.DetectAction.detect_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.FaxAction.fax_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.PayAction.pay_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.RecordAction.duration: port-only: Perl RecordAction exposes url/duration/size as explicit accessors; Python uses attribute-style access
signalwire.relay.call.RecordAction.size: port-only: Perl RecordAction exposes url/duration/size as explicit accessors; Python uses attribute-style access
signalwire.relay.call.RecordAction.url: port-only: Perl RecordAction exposes url/duration/size as explicit accessors; Python uses attribute-style access
signalwire.relay.call_state.CallState: tier3-typed-state port-only: SignalWire::Relay::CallState names the RELAY call-lifecycle states {created,ringing,answered,ending,ended} as a single-sourced closed set (the Tier-1 constants idiom; values ARE the wire strings). Grounded in Python relay/constants.py CALL_STATE_*; Call->state still reads/writes the bare string (parity). Perl has no real enums, so this is documentation + autocomplete + membership/terminality predicates, not compile-time typo checking.
signalwire.relay.call_state.CallState.is_state: tier3-typed-state port-only: CallState->is_state($v) membership over the call-state closed set; false (never dies) on undef/unknown (see CallState).
signalwire.relay.call_state.CallState.is_terminal: tier3-typed-state port-only: CallState->is_terminal($v) — terminal set {ended}; false (never dies) on undef/unknown/forward-compat (see CallState). NEVER conflated with DialState/MessageState ('answered' is non-terminal here, terminal for a dial).
signalwire.relay.call_state.CallState.states: tier3-typed-state port-only: CallState->states is the ordered arrayref of call-lifecycle states (see CallState).
signalwire.relay.client.Constants: port-only: SignalWire::Relay::Constants holds Blade/JSON-RPC constants; Python inlines them
signalwire.relay.client.RelayClient.authenticate: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.connect_ws: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.disconnect_ws: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.on_event: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.reconnect: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.device.Device: tier3-typed-shape port-only: SignalWire::Relay::Device types the SHAPE of the {type,params} RELAY device object that the relay layer otherwise passes as a raw hashref across dial/connect/refer/tap. Grounded in relay-protocol/calling.{connect,dial}.params.json. ``type`` stays a string (the device-type set is an open ``{"type":"string"}``, not enumerated). Additive — relay verbs still accept a raw hashref; to_hash yields the identical wire hashref. Python passes the raw dict.
signalwire.relay.device.Device.__init__: tier3-typed-shape port-only: Device->new constructs the typed {type,params} shape (Moo root __init__ with required `type`); relay verbs still accept a raw hashref, so this is additive (see Device). Python passes the raw dict with no constructor.
signalwire.relay.device.Device.to_hash: tier3-typed-shape port-only: Device->to_hash yields the canonical {type,params} wire hashref — byte-identical to the hand-written form (see Device).
signalwire.relay.dial_state.DialState: tier3-typed-state port-only: SignalWire::Relay::DialState names the RELAY dial-outcome states {dialing,answered,failed} as a single-sourced closed set (values ARE the wire strings). Grounded in the port's Relay::Constants DIAL_STATES + Relay::Client dial dispatch (resolve on answered, reject on failed). The dial flow still compares bare strings (parity). NEVER conflated with CallState/MessageState.
signalwire.relay.dial_state.DialState.is_state: tier3-typed-state port-only: DialState->is_state($v) membership over the dial-outcome set; false (never dies) on undef/unknown (see DialState).
signalwire.relay.dial_state.DialState.is_terminal: tier3-typed-state port-only: DialState->is_terminal($v) — terminal set {answered,failed}; false (never dies) on undef/the in-progress 'dialing'/unknown (see DialState). 'answered' is terminal here but NON-terminal for a CallState.
signalwire.relay.dial_state.DialState.states: tier3-typed-state port-only: DialState->states is the ordered arrayref of dial-outcome states (see DialState).
signalwire.relay.event.AuthorizationStateEvent: port-only event subclass Perl emits explicitly; Python folds these into RelayEvent/CallState
signalwire.relay.event.CallDisconnectEvent: port-only event subclass Perl emits explicitly; Python folds these into RelayEvent/CallState
signalwire.relay.event.DisconnectEvent: port-only event subclass Perl emits explicitly; Python folds these into RelayEvent/CallState
signalwire.relay.message.Message.current_state: tier3-typed-state port-only: SignalWire::Relay::MessageState-typed view of the delivery state, alongside the bare-string ``state`` accessor (parity). Returns the same wire string ``state`` does (the MessageState constants ARE the wire strings); the typed companion to MessageState->is_state/->is_terminal. Python reads the bare ``state`` attribute.
signalwire.relay.message.Message.dispatch_event: port-only dispatcher/passthrough helper for Perl-idiomatic event plumbing
signalwire.relay.message.Message.is_terminal: tier3-typed-state port-only: true when the current ``state`` is a terminal delivery state (MessageState terminal set = {delivered,undelivered,failed}); delegates to SignalWire::Relay::MessageState (single-sourced). Distinct from is_done (the resolved ``completed`` flag). Returns false (never dies) on an unknown/forward-compat state.
signalwire.relay.message.Message.on_completed: port-only dispatcher/passthrough helper for Perl-idiomatic event plumbing
signalwire.relay.message_state.MessageState: tier3-typed-state port-only: SignalWire::Relay::MessageState names the RELAY message-delivery states {queued,initiated,sent,delivered,undelivered,failed,received} as a single-sourced closed set (values ARE the wire strings). Grounded in Python relay/constants.py MESSAGE_STATE_*; Message->state still reads/writes the bare string (parity). NEVER conflated with CallState/DialState.
signalwire.relay.message_state.MessageState.is_state: tier3-typed-state port-only: MessageState->is_state($v) membership over the message-state set; false (never dies) on undef/unknown (see MessageState).
signalwire.relay.message_state.MessageState.is_terminal: tier3-typed-state port-only: MessageState->is_terminal($v) — terminal set {delivered,undelivered,failed}; false (never dies) on undef/in-flight/received/unknown (see MessageState).
signalwire.relay.message_state.MessageState.states: tier3-typed-state port-only: MessageState->states is the ordered arrayref of message-delivery states (see MessageState).
signalwire.rest._pagination.PaginatedIterator.all: port-only: drains the iterator into a list (Perl idiom for `list(iter)`); Python uses `list(it)` directly
signalwire.rest.namespaces.relay_rest_types_generated.PhoneCallHandler.values: port-only: authoritative list accessor for the call_handler enum; Python uses the type/enum class directly (the REST-generated oracle houses PhoneCallHandler as a relay-rest generated type)
signalwire.skills.registry.CustomSkills: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.CustomSkills.get_parameter_schema: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.CustomSkills.register_tools: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.CustomSkills.setup: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.SkillRegistry.clear_registry: port-only registry helper: Perl exposes these for test isolation and dynamic loading
signalwire.skills.registry.SkillRegistry.get_factory: port-only registry helper: Perl exposes these for test isolation and dynamic loading
signalwire.skills.skill_name.SkillName: perl_constants_idiom: SignalWire::Skills::SkillName is a constants package naming the 18 built-in skills as a single-sourced closed set (mirrors the cross-port Tier-1 enum proof); add_skill/remove_skill/has_skill still take the string (the constants ARE the wire strings) so Python str parity + custom skills are unchanged. Perl has no real enums, so this is documentation + autocomplete + a validation list, not compile-time typo checking.
signalwire.skills.skill_name.SkillName.all: perl_constants_idiom: SkillName->all returns the sorted arrayref of built-in skill names for iteration/validation (see SkillName).
signalwire.skills.skill_name.SkillName.is_builtin: perl_constants_idiom: SkillName->is_builtin($name) membership check over the built-in closed set (see SkillName).
signalwire.utils.schema_utils.SchemaUtils.get_verb: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.get_verb_names: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.has_verb: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.instance: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.verb_count: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.web.web_service.WebService.file_allowed: port-only public helper: Perl exposes the size+extension filter as a callable predicate (Ruby's file_allowed?); Python keeps it private as _is_file_allowed
signalwire.web.web_service.WebService.psgi_app: port-only: Perl ports use Plack/PSGI; WebService.psgi_app returns the static-file-serving coderef any Plack handler consumes; Python builds a FastAPI app internally
signalwire.core.security.webhook_middleware.wrap: perl-idiom port-only: Plack middleware wrap() instance method (Plack convention) — Python uses make_webhook_validation_dependency factory function instead

# --- item H/I surface-align additions ---

# AuthHandler Plack analogs of Python's Flask/FastAPI-bound methods. Perl's
# standard web interface is PSGI/Plack; plack_middleware/plack_dependency are
# the direct analogs (same shape as Ruby's rack_* additions). The parity names
# flask_decorator/get_fastapi_dependency are also present (real impls).
signalwire.core.auth_handler.AuthHandler.plack_middleware: port-only: PSGI/Plack analog of the Flask decorator; wraps a PSGI app and 401s unauthenticated requests (Python's web binding is Flask/FastAPI)
signalwire.core.auth_handler.AuthHandler.plack_dependency: port-only: PSGI/Plack analog of the FastAPI dependency; a PSGI-env callable returning the auth decision (Python's web binding is FastAPI)
signalwire.core.auth_handler.BasicCredentials: port-only: perl-idiom data class carrying HTTP Basic username/password. Python binds FastAPI's HTTPBasicCredentials (an external framework type, not its own class); Perl has no such framework binding, so it re-expresses the same {username,password} carrier as its own typed class fed to verify_basic_auth. Additive; the wire/verification behaviour is unchanged.
signalwire.core.auth_handler.BasicCredentials.__init__: port-only: BasicCredentials->new({username,password}) constructs the carrier (see BasicCredentials).
signalwire.core.auth_handler.BasicCredentials.username: port-only: BasicCredentials->username accessor (see BasicCredentials).
signalwire.core.auth_handler.BasicCredentials.password: port-only: BasicCredentials->password accessor (see BasicCredentials).
signalwire.core.auth_handler.BearerCredentials: port-only: perl-idiom data class carrying an HTTP Bearer token, fed to verify_bearer_token. Python binds FastAPI's bearer/HTTPAuthorizationCredentials (external framework type); Perl re-expresses the same {credentials} carrier as its own typed class. Additive; behaviour unchanged.
signalwire.core.auth_handler.BearerCredentials.__init__: port-only: BearerCredentials->new({credentials}) constructs the carrier (see BearerCredentials).
signalwire.core.auth_handler.BearerCredentials.credentials: port-only: BearerCredentials->credentials accessor — the bearer token string (see BearerCredentials).
signalwire.core.auth_handler.AuthError: perl_idiom_typed_error: SignalWire::Core::AuthError is a perl-idiom typed exception carrying a 401 response + message, THROWN when auth fails. Python returns a bare 401 response inline with no error class; Perl's idiom is a typed die/throw so the caller can distinguish the auth-failure path (mirrors the cross-port typed-error idiom). The 401 wire response is byte-identical to Python's inline 401; only the control-flow shape (raise vs return) differs.
signalwire.core.auth_handler.AuthError.__init__: perl_idiom_typed_error: AuthError->new({message,response}) constructs the typed error (see AuthError).
signalwire.core.auth_handler.AuthError.message: perl_idiom_typed_error: AuthError->message accessor — the human-readable failure reason (see AuthError).
signalwire.core.auth_handler.AuthError.response: perl_idiom_typed_error: AuthError->response accessor — the 401 PSGI response the error carries (see AuthError).

# RelayError typed accessors. Python's RelayError exposes code/message as plain
# attributes (only __init__ on the surface); Perl exposes them as explicit
# read accessors (same idiom as the RecordAction url/duration/size accessors).
signalwire.relay.client.RelayError.code: port-only: Perl RelayError exposes code as an explicit accessor; Python uses attribute-style access
signalwire.relay.client.RelayError.message: port-only: Perl RelayError exposes message as an explicit accessor; Python uses attribute-style access

# from_payload on the Perl-only RELAY events. from_payload is inherited from the
# base Event and projected onto every event class; the three Perl-only events
# (already PORT_ADDITIONS as classes) therefore also carry it.
signalwire.relay.event.AuthorizationStateEvent.from_payload: port-only: from_payload inherited from the base Event onto the Perl-only AuthorizationStateEvent
signalwire.relay.event.CallDisconnectEvent.from_payload: port-only: from_payload inherited from the base Event onto the Perl-only CallDisconnectEvent
signalwire.relay.event.DisconnectEvent.from_payload: port-only: from_payload inherited from the base Event onto the Perl-only DisconnectEvent

## Mixin-flatten folded additions (agentbase-family keys)

agentbase-family.list_tool_names: port-only helper used by ContextBuilder->validate to surface reserved-name collisions; no Python twin (folds to agentbase-family via the mixin-flatten fold).
agentbase-family.psgi_app: port-only: Perl ports use Plack/PSGI; psgi_app returns a coderef any Plack handler consumes; no Python twin (folds to agentbase-family).
agentbase-family.record_format: port-only accessor: Perl declares `has record_format => (is => 'rw')` so callers read/set the recording format; Python models record_format as a set_answer_config constructor param with no surface accessor (folds to agentbase-family).
agentbase-family.record_stereo: port-only accessor: Perl declares `has record_stereo => (is => 'rw')` so callers read/set stereo recording; Python models record_stereo as a set_answer_config constructor param with no surface accessor (folds to agentbase-family).
agentbase-family.set_answer_config: port-only helper: wires AnswerConfig into SWML rendering; Python threads these through AIConfigMixin (folds to agentbase-family).
agentbase-family.create_tool_token: composition-delegate: Perl rolls SessionManager.create_tool_token up onto AgentBase; Python houses it on the SessionManager helper (reference twin signalwire.core.security.session_manager.SessionManager.create_tool_token). The mixin-flatten fold spans inheritance, not composition delegates (ALLOWLIST_DISCIPLINE.md §4c cat 1), so it surfaces here until that fold is extended.
agentbase-family.get_contexts: composition-delegate: Perl exposes get_contexts() on AgentBase; Python houses it on the PromptManager helper (signalwire.core.agent.prompt.manager.PromptManager.get_contexts). Same §4c cat-1 composition-delegate rationale as create_tool_token.
agentbase-family.get_raw_prompt: composition-delegate: Perl exposes get_raw_prompt() on AgentBase; Python houses it on PromptManager (PromptManager.get_raw_prompt). §4c cat-1 composition-delegate.
agentbase-family.render_swml: composition-delegate: Perl exposes render_swml() on AgentBase; Python houses it on the SwmlRenderer helper (signalwire.core.swml_renderer.SwmlRenderer.render_swml). §4c cat-1 composition-delegate.

## Raw-key twins for the SIGNATURE diff (dual-key convention; folded twins above)

signalwire.core.agent_base.AgentBase.create_tool_token: composition-delegate raw key for the SIGNATURE diff (folds to agentbase-family for SURFACE): Perl rolls SessionManager.create_tool_token up onto AgentBase; Python houses it on SessionManager.
signalwire.core.agent_base.AgentBase.render_swml: raw key for the SIGNATURE diff (folds to agentbase-family for SURFACE): Perl exposes render_swml() on AgentBase as the user-facing SWML dump; Python keeps it on the SwmlRenderer helper / internal _render_swml.
signalwire.core.agent_base.AgentBase.set_answer_config: raw key for the SIGNATURE diff (folds to agentbase-family for SURFACE): port-only helper wiring AnswerConfig into SWML rendering; Python threads these through AIConfigMixin.
signalwire.rest._base.HttpClient.delete_request: perl-idiom port-only: the low-level HTTP transport method is named delete_request on HttpClient to read as an HTTP-verb helper (paired with get/post/put/patch); the Python parity name delete is also exposed via the enumerator alias.
