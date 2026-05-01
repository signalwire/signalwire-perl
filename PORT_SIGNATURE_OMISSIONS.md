# PORT_SIGNATURE_OMISSIONS.md

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
   up.


## Idiom: Perl logger / app accessor naming

signalwire.agent_server.AgentServer.app: Perl AgentServer wraps a Plack/PSGI coderef accessible via psgi_app(); Python's `.app` attribute is a Flask app instance — no direct equivalent in Plack land
signalwire.agent_server.AgentServer.logger: Perl uses SignalWire::Logging->get_logger(...) directly rather than a per-class logger attribute; Python keeps a `.logger` accessor on every class
signalwire.core.skill_base.SkillBase.logger: Perl SkillBase doesn't expose a logger attribute; subclasses use SignalWire::Logging directly when they need to log
signalwire.core.skill_manager.SkillManager.logger: Perl SkillManager doesn't expose a logger attribute; logging happens through SignalWire::Logging
signalwire.skills.registry.SkillRegistry.logger: Perl SkillRegistry doesn't expose a logger attribute; logging happens through SignalWire::Logging


## Idiom: Perl method-name renames

signalwire.relay.call.Call.on: Perl ``$call->on($cb)`` is the Perl idiom for registering a single all-events callback; Python's ``Call.on(event_type, handler)`` requires per-event-type registration — different ergonomics, same dispatch model
signalwire.skills.registry.SkillRegistry.register_skill: Perl exposes a two-arg ``register_skill(skill_name, skill_class)`` form that mirrors the underlying registry table; Python's classmethod takes a single ``skill_class`` and reads the name from the class itself


## Idiom: Perl Moo constructor shapes

signalwire.relay.call.Call.__init__: Perl Moo Call doesn't model `project_id`, `direction`, or `segment_id` as `has` attrs (the Perl SDK derives them from the Relay event payload at dispatch time rather than tracking them on the Call object); Python keeps them as constructor kwargs
signalwire.prefabs.survey.SurveyAgent.__init__: Perl SurveyAgent uses `survey_questions` (matching the SDK's other survey_* attrs) where Python uses `questions`; the constructor accepts both via Moo's open hash-arg interface but the canonical Perl attribute name differs


## Idiom: Perl event-class attribute coverage

signalwire.relay.event.CallReceiveEvent.__init__: Perl CallReceive doesn't model `direction`, `project_id`, or `segment_id` as Moo attrs; the Perl event objects expose only the subset the SDK actively consumes
signalwire.relay.event.CollectEvent.__init__: Perl CollectEvent doesn't model `final` flag as a Moo attr; the Perl SDK reads completion state from the underlying CallCollect payload
signalwire.relay.event.ConferenceEvent.__init__: Perl ConferenceEvent doesn't model `name` / `status` as Moo attrs; the Perl SDK reads them from the conference payload directly
signalwire.relay.event.MessageReceiveEvent.__init__: Perl MessageReceive doesn't model the base RelayEvent `call_id` (messaging events are call-id-less)
signalwire.relay.event.MessageStateEvent.__init__: Perl MessageState doesn't model the base RelayEvent `call_id` (messaging events are call-id-less)
signalwire.relay.event.ReferEvent.__init__: Perl ReferEvent doesn't model `sip_refer_to`, `sip_refer_response_code`, `sip_notify_response_code` as Moo attrs; the Perl SDK doesn't expose those SIP details (they live in the underlying CallRefer payload)
signalwire.relay.event.RelayEvent.__init__: Perl base RelayEvent omits `call_id` (subclasses add it where applicable); Python keeps it on the base class with `''` default
signalwire.relay.event.StreamEvent.__init__: Perl StreamEvent doesn't model `url` / `name` as Moo attrs; the Perl SDK reads them from the underlying CallStream payload
signalwire.relay.event.TranscribeEvent.__init__: Perl TranscribeEvent doesn't model `url`, `recording_id`, `duration`, `size` as Moo attrs; the Perl SDK reads them from the underlying CallTranscribe payload


## Source-side stubs (Perl method bodies don't yet declare full args)

signalwire.core.agent.prompt.manager.PromptManager.define_contexts: Perl PromptManager.define_contexts() takes no args and returns the existing context_builder; Python takes a list-of-Context arg
signalwire.core.agent_base.AgentBase.on_summary: Perl on_summary($cb) takes a single callback; Python takes (summary, raw_data) — Perl invokes the callback via dispatch, Python's signature represents the callback contract directly
signalwire.core.contexts.create_simple_context: free function in Python; Perl ports it via the ContextBuilder helper instead — no module-level free function
signalwire.core.logging_config.get_logger: Python module-level `get_logger(name)` factory; Perl exposes `SignalWire::Logging->get_logger($name)` only as a class method, not a module-level free function
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_hints: Perl uses ``@h`` slurpy-array (caller passes ``add_hints('a', 'b', 'c')``); Python takes a single list arg ``add_hints(['a','b','c'])`` — different call shapes, equivalent contract
signalwire.core.mixins.auth_mixin.AuthMixin.get_basic_auth_credentials: Perl ``get_basic_auth_credentials()`` takes no args and returns the (user, password) tuple; Python optionally takes ``include_source`` for richer return
signalwire.core.mixins.prompt_mixin.PromptMixin.define_contexts: see PromptManager.define_contexts above (mirror)
signalwire.core.mixins.web_mixin.WebMixin.on_swml_request: Perl on_swml_request(request_data, callback_path) returns a hashref; Python's third ``request`` param exposes the underlying Flask request — Plack equivalent isn't first-class in the Perl signature
signalwire.core.swml_service.SWMLService.get_basic_auth_credentials: see AuthMixin.get_basic_auth_credentials above (mirror)
signalwire.core.swml_service.SWMLService.extract_sip_username: Python SWMLService has a top-level ``extract_sip_username``; Perl exposes the same logic on AgentBase.extract_sip_username (Perl port collapses the duplication onto AgentBase)
signalwire.core.agent_base.AgentBase.extract_sip_username: see SWMLService.extract_sip_username — Perl puts the helper on AgentBase only
signalwire.core.swml_service.SWMLService.schema_utils: Perl SWMLService doesn't expose a schema_utils property; verb-schema lookup goes through SignalWire::Utils::SchemaUtils directly
signalwire.core.swml_service.SWMLService.security: Perl SWMLService doesn't expose a security property; SignalWire::Security::SessionManager is wired via _session_manager attribute instead
signalwire.core.swml_service.SWMLService.verb_registry: Perl SWMLService doesn't expose a verb_registry property; verb registration goes through SignalWire::Utils::SchemaUtils->instance() directly
signalwire.core.agent_base.AgentBase.create_tool_token: Perl AgentBase has create_tool_token (helper for SWAIG token minting); Python's reference declares it on a subclass mixin — port-only on AgentBase but functionally equivalent
signalwire.relay.call.Call.leave_room: Perl Call.leave_room() doesn't accept the Python kwargs slurpy; the Perl SDK doesn't pass extra params to the Relay leave_room dispatch
signalwire.relay.client.RelayClient.receive: Perl ``receive(@ctxs)`` uses slurpy-array (caller passes ``receive('ctx1', 'ctx2')``); Python takes a single list arg — different call shapes, equivalent contract
signalwire.relay.client.RelayClient.unreceive: see RelayClient.receive above (mirror)
signalwire.core.security.session_manager.SessionManager.activate_session: Perl SessionManager.activate_session() is a stub returning 1; Python takes (call_id) and updates internal session state
signalwire.core.security.session_manager.SessionManager.end_session: Perl SessionManager.end_session() is a stub returning 1; Python takes (call_id)
signalwire.core.security.session_manager.SessionManager.get_session_metadata: Perl SessionManager.get_session_metadata() is a stub returning {}; Python takes (call_id) and returns per-session data
signalwire.core.security.session_manager.SessionManager.set_session_metadata: Perl SessionManager.set_session_metadata() is a stub returning 1; Python takes (call_id, key, value)
