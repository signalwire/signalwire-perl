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
   up. As of 2026-04-30 phase-4 audit: ZERO open source-side stubs —
   all 22 previously-tracked stubs have been closed by accepting the
   Python-canonical signatures and exercising them with Test::More
   tests under t/.


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
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.__init__: Perl declares the skill's constructor explicitly (Moo `extends` SkillBase); Python's same skill now simply inherits `SkillBase.__init__` verbatim, so the reference no longer emits a per-skill ctor. Same construction contract (agent, params) — Perl just keeps it explicit.
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.__init__: Perl declares the skill's constructor explicitly (Moo `extends` SkillBase); Python's same skill now inherits `SkillBase.__init__` verbatim, so the reference no longer emits a per-skill ctor. Same construction contract.
signalwire.skills.weather_api.skill.WeatherApiSkill.__init__: Perl declares the skill's constructor explicitly (Moo `extends` SkillBase); Python's same skill now inherits `SkillBase.__init__` verbatim, so the reference no longer emits a per-skill ctor. Same construction contract.


## Idiom: Perl-side helpers replicated on AgentBase

signalwire.core.agent_base.AgentBase.create_tool_token: Perl AgentBase exposes ``create_tool_token`` directly (Moo composition flattens the StateMixin helper onto AgentBase); Python keeps the same helper one level out on a mixin class. Functionally equivalent — the Perl audit reports it as port-only because the Python class itself doesn't redeclare the method.
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

signalwire.relay.call.Call.wait_for_answered: no Call-level state-wait primitive in the Perl port (state is tracked, but blocking wait-on-state lives on Client's read-loop, not on Call); omitted rather than stubbed
signalwire.relay.call.Call.wait_for_ringing: no Call-level state-wait primitive in the Perl port (state is tracked, but blocking wait-on-state lives on Client's read-loop, not on Call); omitted rather than stubbed
signalwire.relay.call.Call.wait_for_ending: no Call-level state-wait primitive in the Perl port (state is tracked, but blocking wait-on-state lives on Client's read-loop, not on Call); omitted rather than stubbed


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

signalwire.agent_server.AgentServer.register_global_routing_callback: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.agent_server.AgentServer.register_sip_username: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.agent_server.AgentServer.setup_sip_routing: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.agent_base.AgentBase.add_answer_verb: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.agent_base.AgentBase.enable_sip_routing: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.agent_base.AgentBase.register_sip_username: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.auth_handler.AuthHandler.__init__: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.auth_handler.AuthHandler.flask_decorator: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.auth_handler.AuthHandler.get_fastapi_dependency: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.auth_handler.AuthHandler.verify_api_key: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.auth_handler.AuthHandler.verify_basic_auth: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.auth_handler.AuthHandler.verify_bearer_token: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.config_loader.ConfigLoader.__init__: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.config_loader.ConfigLoader.find_config_file: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.config_loader.ConfigLoader.get_section: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.config_loader.ConfigLoader.merge_with_env: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.config_loader.ConfigLoader.substitute_vars: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.mixins.prompt_mixin.PromptMixin.set_prompt_pom: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.mixins.serverless_mixin.ServerlessMixin.handle_serverless_request: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.mixins.web_mixin.WebMixin.register_routing_callback: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.pom_builder.PomBuilder.add_section: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.pom_builder.PomBuilder.add_subsection: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.pom_builder.PomBuilder.add_to_section: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.pom_builder.PomBuilder.get_section: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.pom_builder.PomBuilder.has_section: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.security_config.SecurityConfig.__init__: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.security_config.SecurityConfig.get_security_headers: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.security_config.SecurityConfig.log_config: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.security_config.SecurityConfig.should_allow_host: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.skill_base.SkillBase.update_skill_data: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.skill_manager.SkillManager.get_skill: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swaig_function.SWAIGFunction.__init__: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swaig_function.SWAIGFunction.execute: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swaig_function.SWAIGFunction.to_swaig: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_builder.SWMLBuilder.ai: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_builder.SWMLBuilder.answer: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_builder.SWMLBuilder.hangup: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_builder.SWMLBuilder.play: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_builder.SWMLBuilder.say: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_handler.AIVerbHandler.build_config: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_handler.VerbHandlerRegistry.get_handler: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_handler.VerbHandlerRegistry.has_handler: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_handler.VerbHandlerRegistry.register_handler: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_renderer.SwmlRenderer.render_function_response_swml: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_renderer.SwmlRenderer.render_swml: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_service.SWMLService.add_section: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_service.SWMLService.add_verb: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_service.SWMLService.add_verb_to_section: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_service.SWMLService.manual_set_proxy_url: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_service.SWMLService.register_verb_handler: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.core.swml_service.SWMLService.serve: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.prefabs.info_gatherer.InfoGathererAgent.on_swml_request: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.prefabs.info_gatherer.InfoGathererAgent.set_question_callback: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.relay.call.Call.wait_for: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.relay.call.Call.wait_for_ended: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.relay.client.RelayError.__init__: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.skills.registry.SkillRegistry.get_skill_class: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.utils.schema_utils.SchemaUtils.get_verb_parameters: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.utils.schema_utils.SchemaUtils.get_verb_properties: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.utils.schema_utils.SchemaUtils.get_verb_required_properties: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.utils.schema_utils.SchemaUtils.validate_verb: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.utils.schema_utils.SchemaValidationError.__init__: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.web.web_service.WebService.__init__: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.web.web_service.WebService.add_directory: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.web.web_service.WebService.remove_directory: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.
signalwire.web.web_service.WebService.start: Perl method takes an idiomatic %opts/positional signature; params surface as untyped `any` (Perl signatures aren't introspectable) vs the reference's concrete types — loose-param idiom, PORT_SIGNATURE_OMISSIONS.


## Reference-oracle gap: symbol in python_surface but not python_signatures

These symbols exist in the surface oracle (python_surface.json) and are
genuinely implemented by the Perl port, but the signature oracle
(enumerate_python_signatures.py) did not enumerate them, so the DRIFT
gate reports them as `missing-reference` (in port, not in the signature
reference). The SURFACE gate is clean for all of them (they match the
reference surface, hence not in PORT_ADDITIONS.md). Excused as a
reference-oracle gap, not port-invented surface.

signalwire.agents.bedrock.BedrockAgent.set_inference_params: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.agents.bedrock.BedrockAgent.set_llm_model: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.agents.bedrock.BedrockAgent.set_llm_temperature: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.agents.bedrock.BedrockAgent.set_post_prompt_llm_params: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.agents.bedrock.BedrockAgent.set_prompt_llm_params: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
signalwire.agents.bedrock.BedrockAgent.set_voice: reference-oracle gap — present in python_surface.json (port matches the reference surface) but not enumerated in python_signatures.json; real capability, signature-oracle blind spot.
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
signalwire.core.mixins.tool_mixin.ToolMixin.define_tools: Perl `define_tools($tool_defs)` accepts the batch tool-definition list as a positional arg (Moo/AgentBase idiom); the reference `define_tools(self)` reads them from instance state — same batch-registration capability, different arg-passing.
signalwire.core.pom_builder.PomBuilder.from_sections: Perl `from_sections($class_or_self, $sections)` is a dual-invocant classmethod; the `$class_or_self` receiver is stripped as a @staticmethod-style receiver, leaving `sections` vs the reference classmethod's `(cls, sections)` — classmethod-receiver idiom.
signalwire.relay.event.DenoiseEvent.__init__: Perl DenoiseEvent doesn't model the base RelayEvent `call_id` as a Moo attr (this event carries no call_id in the Perl port); Python keeps `call_id` on the base with `''` default.
signalwire.relay.event.EchoEvent.__init__: Perl EchoEvent doesn't model the base RelayEvent `call_id` as a Moo attr; Python keeps `call_id` on the base with `''` default.
signalwire.relay.event.HoldEvent.__init__: Perl HoldEvent doesn't model the base RelayEvent `call_id` as a Moo attr; Python keeps `call_id` on the base with `''` default.
signalwire.relay.event.QueueEvent.__init__: Perl QueueEvent doesn't model the base RelayEvent `call_id` nor `queue_id`/`queue_name` as Moo attrs; the Perl SDK reads queue identity from the underlying CallQueue payload — a subset of the reference's dataclass fields.


## Idiom: reference-only attributes with no Perl method (Plack/PSGI + security)

signalwire.web.web_service.WebService.app: Perl WebService wraps a Plack/PSGI coderef (psgi_app) rather than a FastAPI app instance; the reference's `.app` FastAPI accessor has no direct equivalent in Plack land (mirrors agent_server.AgentServer.app).
signalwire.web.web_service.WebService.security: Perl WebService applies security headers inline (_security_headers) rather than exposing a SecurityConfig accessor attribute; the reference's `.security` accessor has no first-class Perl equivalent.
