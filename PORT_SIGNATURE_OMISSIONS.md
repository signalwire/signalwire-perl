# PORT_SIGNATURE_OMISSIONS.md

Documented signature divergences between this Perl port and the Python
reference. Names-only divergences live in PORT_OMISSIONS.md /
PORT_ADDITIONS.md and are inherited automatically.

Excused divergences:

1. **Idiom-level**: Perl 5.32 + Moo doesn't have native runtime-
   introspectable signatures. The adapter parses ``my (...) = @_;`` and
   ``my $x = shift;`` patterns from source via best-effort regex. Every
   parameter type is ``any``. Structural drift (param name, count) is
   what's caught. Future port-side adoption of Type::Tiny ``signature_for``
   would unlock typed signatures; tracked as a separate program.

2. **Port maintenance backlog**: real param/arity divergences that should
   be reduced as the Perl port catches up to Python.


## Idiom: Perl Moo constructors

signalwire.agent_server.AgentServer.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.contexts.Context.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.contexts.ContextBuilder.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.contexts.GatherInfo.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.contexts.GatherQuestion.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.contexts.Step.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.data_map.DataMap.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.function_result.FunctionResult.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.security.session_manager.SessionManager.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.skill_base.SkillBase.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.skill_manager.SkillManager.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.swml_builder.SWMLBuilder.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.core.swml_service.SWMLService.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.prefabs.concierge.ConciergeAgent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.prefabs.faq_bot.FAQBotAgent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.prefabs.info_gatherer.InfoGathererAgent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.prefabs.receptionist.ReceptionistAgent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.prefabs.survey.SurveyAgent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.call.Action.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.call.Call.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.client.RelayClient.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.CallReceiveEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.CallStateEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.CallingErrorEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.CollectEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.ConferenceEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.ConnectEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.DetectEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.DialEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.FaxEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.MessageReceiveEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.MessageStateEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.PayEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.PlayEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.RecordEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.ReferEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.RelayEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.SendDigitsEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.StreamEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.TapEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.event.TranscribeEvent.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.relay.message.Message.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.client.RestClient.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.addresses.AddressesResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.calling.CallingNamespace.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.chat.ChatResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.compat.CompatAccounts.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.compat.CompatNamespace.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.compat.CompatPhoneNumbers.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.datasphere.DatasphereDocuments.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.fabric.FabricNamespace.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.fabric.FabricTokens.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.imported_numbers.ImportedNumbersResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.logs.LogsNamespace.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.lookup.LookupResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.mfa.MfaResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.number_groups.NumberGroupsResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.project.ProjectNamespace.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.project.ProjectTokens.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.pubsub.PubSubResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.queues.QueuesResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.recordings.RecordingsResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.registry.RegistryNamespace.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.short_codes.ShortCodesResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.sip_profile.SipProfileResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.verified_callers.VerifiedCallersResource.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.rest.namespaces.video.VideoNamespace.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.search.DocumentProcessor.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.search.IndexBuilder.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.search.SearchEngine.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.search.SearchService.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.search.search_service.SearchRequest.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.search.search_service.SearchResponse.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.search.search_service.SearchResult.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.skills.registry.SkillRegistry.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.skills.spider.skill.SpiderSkill.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.skills.weather_api.skill.WeatherApiSkill.__init__: Perl constructor (Moo new) signature follows Perl conventions
signalwire.utils.schema_utils.SchemaUtils.__init__: Perl constructor (Moo new) signature follows Perl conventions

## Backlog: real signature divergences (944 symbols)

signalwire.agent_server.AgentServer.get_agent: BACKLOG / param-mismatch/ param[1] (route)/ type 'string' vs 'any'; return-mismatch/ returns 'optional<class/signalwire.core.agent
signalwire.agent_server.AgentServer.register: BACKLOG / param-mismatch/ param[1] (agent)/ type 'class/signalwire.core.agent_base.AgentBase' vs 'any'; param-mismatch/ param[2] (
signalwire.agent_server.AgentServer.run: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'event', 'context', 'ho
signalwire.agent_server.AgentServer.serve_static_files: BACKLOG / param-mismatch/ param[1] (directory)/ type 'string' vs 'any'; param-mismatch/ param[2] (route)/ type 'string' vs 'any'; 
signalwire.agent_server.AgentServer.unregister: BACKLOG / param-mismatch/ param[1] (route)/ type 'string' vs 'any'; return-mismatch/ returns 'bool' vs 'any'
signalwire.core.agent_base.AgentBase.add_function_include: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_hint: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_hints: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_internal_filler: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_language: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_mcp_server: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_pattern_hint: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_post_ai_verb: BACKLOG / param-mismatch/ param[1] (verb_name)/ type 'string' vs 'any'; param-mismatch/ param[2] (config)/ name 'config' vs 'verb_
signalwire.core.agent_base.AgentBase.add_post_answer_verb: BACKLOG / param-mismatch/ param[1] (verb_name)/ type 'string' vs 'any'; param-mismatch/ param[2] (config)/ name 'config' vs 'verb_
signalwire.core.agent_base.AgentBase.add_pre_answer_verb: BACKLOG / param-mismatch/ param[1] (verb_name)/ type 'string' vs 'any'; param-mismatch/ param[2] (config)/ name 'config' vs 'verb_
signalwire.core.agent_base.AgentBase.add_pronunciation: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_skill: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.add_swaig_query_params: BACKLOG / param-mismatch/ param[1] (params)/ type 'dict<string,string>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.
signalwire.core.agent_base.AgentBase.basic_auth_password: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.basic_auth_user: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.clear_post_ai_verbs: BACKLOG / return-mismatch/ returns 'class/signalwire.core.agent_base.AgentBase' vs 'any'
signalwire.core.agent_base.AgentBase.clear_post_answer_verbs: BACKLOG / return-mismatch/ returns 'class/signalwire.core.agent_base.AgentBase' vs 'any'
signalwire.core.agent_base.AgentBase.clear_pre_answer_verbs: BACKLOG / return-mismatch/ returns 'class/signalwire.core.agent_base.AgentBase' vs 'any'
signalwire.core.agent_base.AgentBase.clear_swaig_query_params: BACKLOG / return-mismatch/ returns 'class/signalwire.core.agent_base.AgentBase' vs 'any'
signalwire.core.agent_base.AgentBase.contexts: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.define_contexts: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.enable_debug_events: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.enable_mcp_server: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.extract_sip_username: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.get_full_url: BACKLOG / param-mismatch/ param[1] (include_auth)/ name 'include_auth' vs 'opts'; type 'bool' vs 'any'; re; return-mismatch/ retur
signalwire.core.agent_base.AgentBase.get_prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.has_skill: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.list_skills: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.manual_set_proxy_url: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.name: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.on_debug_event: BACKLOG / param-mismatch/ param[1] (handler)/ name 'handler' vs 'cb'; type 'class/Callable' vs 'any'; return-mismatch/ returns 'cl
signalwire.core.agent_base.AgentBase.on_summary: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'summary', 'raw_data'] ; return-mismatch/
signalwire.core.agent_base.AgentBase.port: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.prompt_add_section: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.prompt_add_subsection: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.prompt_add_to_section: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.prompt_has_section: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.remove_skill: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.reset_contexts: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.run: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.serve: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_dynamic_config_callback: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_function_includes: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_global_data: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_internal_fillers: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_languages: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_native_functions: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_param: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_params: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_post_prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_post_prompt_llm_params: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_post_prompt_url: BACKLOG / param-mismatch/ param[1] (url)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.agent_base.Agent
signalwire.core.agent_base.AgentBase.set_prompt_llm_params: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_prompt_text: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_pronunciations: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.agent_base.AgentBase.set_web_hook_url: BACKLOG / param-mismatch/ param[1] (url)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.agent_base.Agent
signalwire.core.agent_base.AgentBase.update_global_data: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._consolidate: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._enter_fillers: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._exit_fillers: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._full_reset: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._initial_step: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._isolated: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._post_prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._prompt_sections: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._prompt_text: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._step_order: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._steps: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._system_prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._system_prompt_sections: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._user_prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._valid_contexts: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context._valid_steps: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context.add_bullets: BACKLOG / param-mismatch/ param[1] (title)/ type 'string' vs 'any'; param-mismatch/ param[2] (bullets)/ type 'list<string>' vs 'an
signalwire.core.contexts.Context.add_enter_filler: BACKLOG / param-mismatch/ param[1] (language_code)/ name 'language_code' vs 'lang'; type 'string' vs 'any'; param-mismatch/ param[
signalwire.core.contexts.Context.add_exit_filler: BACKLOG / param-mismatch/ param[1] (language_code)/ name 'language_code' vs 'lang'; type 'string' vs 'any'; param-mismatch/ param[
signalwire.core.contexts.Context.add_section: BACKLOG / param-mismatch/ param[1] (title)/ type 'string' vs 'any'; param-mismatch/ param[2] (body)/ type 'string' vs 'any'
signalwire.core.contexts.Context.add_step: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 3/ reference=['self', 'name', 'task', 'bullet; return-mismatch/
signalwire.core.contexts.Context.add_system_bullets: BACKLOG / param-mismatch/ param[1] (title)/ type 'string' vs 'any'; param-mismatch/ param[2] (bullets)/ type 'list<string>' vs 'an
signalwire.core.contexts.Context.add_system_section: BACKLOG / param-mismatch/ param[1] (title)/ type 'string' vs 'any'; param-mismatch/ param[2] (body)/ type 'string' vs 'any'
signalwire.core.contexts.Context.get_step: BACKLOG / param-mismatch/ param[1] (name)/ type 'string' vs 'any'; return-mismatch/ returns 'optional<class/signalwire.core.contex
signalwire.core.contexts.Context.move_step: BACKLOG / param-mismatch/ param[1] (name)/ type 'string' vs 'any'; param-mismatch/ param[2] (position)/ type 'int' vs 'any'
signalwire.core.contexts.Context.name: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Context.remove_step: BACKLOG / param-mismatch/ param[1] (name)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.Contex
signalwire.core.contexts.Context.set_consolidate: BACKLOG / param-mismatch/ param[1] (consolidate)/ name 'consolidate' vs 'c'; type 'bool' vs 'any'; return-mismatch/ returns 'class
signalwire.core.contexts.Context.set_enter_fillers: BACKLOG / param-mismatch/ param[1] (enter_fillers)/ name 'enter_fillers' vs 'fillers'; type 'dict<string,l; return-mismatch/ retur
signalwire.core.contexts.Context.set_exit_fillers: BACKLOG / param-mismatch/ param[1] (exit_fillers)/ name 'exit_fillers' vs 'fillers'; type 'dict<string,lis; return-mismatch/ retur
signalwire.core.contexts.Context.set_full_reset: BACKLOG / param-mismatch/ param[1] (full_reset)/ name 'full_reset' vs 'fr'; type 'bool' vs 'any'; return-mismatch/ returns 'class/
signalwire.core.contexts.Context.set_initial_step: BACKLOG / param-mismatch/ param[1] (step_name)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.C
signalwire.core.contexts.Context.set_isolated: BACKLOG / param-mismatch/ param[1] (isolated)/ name 'isolated' vs 'iso'; type 'bool' vs 'any'; return-mismatch/ returns 'class/sig
signalwire.core.contexts.Context.set_post_prompt: BACKLOG / param-mismatch/ param[1] (post_prompt)/ name 'post_prompt' vs 'pp'; type 'string' vs 'any'; return-mismatch/ returns 'cl
signalwire.core.contexts.Context.set_prompt: BACKLOG / param-mismatch/ param[1] (prompt)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.Cont
signalwire.core.contexts.Context.set_system_prompt: BACKLOG / param-mismatch/ param[1] (system_prompt)/ name 'system_prompt' vs 'sp'; type 'string' vs 'any'; return-mismatch/ returns
signalwire.core.contexts.Context.set_user_prompt: BACKLOG / param-mismatch/ param[1] (user_prompt)/ name 'user_prompt' vs 'up'; type 'string' vs 'any'; return-mismatch/ returns 'cl
signalwire.core.contexts.Context.set_valid_contexts: BACKLOG / param-mismatch/ param[1] (contexts)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.conte
signalwire.core.contexts.Context.set_valid_steps: BACKLOG / param-mismatch/ param[1] (steps)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts
signalwire.core.contexts.Context.to_dict: BACKLOG / missing-port/ in reference, not in port
signalwire.core.contexts.Context.to_hash: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.ContextBuilder._agent: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.ContextBuilder._context_order: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.ContextBuilder._contexts: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.ContextBuilder.add_context: BACKLOG / param-mismatch/ param[1] (name)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.Contex
signalwire.core.contexts.ContextBuilder.get_context: BACKLOG / param-mismatch/ param[1] (name)/ type 'string' vs 'any'; return-mismatch/ returns 'optional<class/signalwire.core.contex
signalwire.core.contexts.ContextBuilder.reset: BACKLOG / return-mismatch/ returns 'class/signalwire.core.contexts.ContextBuilder' vs 'any'
signalwire.core.contexts.ContextBuilder.to_dict: BACKLOG / missing-port/ in reference, not in port
signalwire.core.contexts.ContextBuilder.to_hash: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.ContextBuilder.validate: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.core.contexts.GatherInfo._completion_action: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherInfo._output_key: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherInfo._prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherInfo._questions: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherInfo.add_question: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'key', 'question', 'kwa; return-mismatch/
signalwire.core.contexts.GatherInfo.to_dict: BACKLOG / missing-port/ in reference, not in port
signalwire.core.contexts.GatherInfo.to_hash: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherQuestion.confirm: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherQuestion.functions: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherQuestion.key: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherQuestion.prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherQuestion.question: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherQuestion.to_dict: BACKLOG / missing-port/ in reference, not in port
signalwire.core.contexts.GatherQuestion.to_hash: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.GatherQuestion.type: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._end: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._functions: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._gather_info: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._reset_consolidate: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._reset_full_reset: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._reset_system_prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._reset_user_prompt: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._sections: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._skip_to_next_step: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._skip_user_turn: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._step_criteria: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._text: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._valid_contexts: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step._valid_steps: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step.add_bullets: BACKLOG / param-mismatch/ param[1] (title)/ type 'string' vs 'any'; param-mismatch/ param[2] (bullets)/ type 'list<string>' vs 'an
signalwire.core.contexts.Step.add_gather_question: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 2/ reference=['self', 'key', 'question', 'typ; return-mismatch/
signalwire.core.contexts.Step.add_section: BACKLOG / param-mismatch/ param[1] (title)/ type 'string' vs 'any'; param-mismatch/ param[2] (body)/ type 'string' vs 'any'
signalwire.core.contexts.Step.clear_sections: BACKLOG / return-mismatch/ returns 'class/signalwire.core.contexts.Step' vs 'any'
signalwire.core.contexts.Step.name: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.Step.set_end: BACKLOG / param-mismatch/ param[1] (end)/ type 'bool' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.Step' vs 
signalwire.core.contexts.Step.set_functions: BACKLOG / param-mismatch/ param[1] (functions)/ type 'union<list<string>,string>' vs 'any'; return-mismatch/ returns 'class/signal
signalwire.core.contexts.Step.set_gather_info: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'output_key', 'completi; return-mismatch/
signalwire.core.contexts.Step.set_reset_consolidate: BACKLOG / param-mismatch/ param[1] (consolidate)/ name 'consolidate' vs 'c'; type 'bool' vs 'any'; return-mismatch/ returns 'class
signalwire.core.contexts.Step.set_reset_full_reset: BACKLOG / param-mismatch/ param[1] (full_reset)/ name 'full_reset' vs 'fr'; type 'bool' vs 'any'; return-mismatch/ returns 'class/
signalwire.core.contexts.Step.set_reset_system_prompt: BACKLOG / param-mismatch/ param[1] (system_prompt)/ name 'system_prompt' vs 'sp'; type 'string' vs 'any'; return-mismatch/ returns
signalwire.core.contexts.Step.set_reset_user_prompt: BACKLOG / param-mismatch/ param[1] (user_prompt)/ name 'user_prompt' vs 'up'; type 'string' vs 'any'; return-mismatch/ returns 'cl
signalwire.core.contexts.Step.set_skip_to_next_step: BACKLOG / param-mismatch/ param[1] (skip)/ type 'bool' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.Step' vs
signalwire.core.contexts.Step.set_skip_user_turn: BACKLOG / param-mismatch/ param[1] (skip)/ type 'bool' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.Step' vs
signalwire.core.contexts.Step.set_step_criteria: BACKLOG / param-mismatch/ param[1] (criteria)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.St
signalwire.core.contexts.Step.set_text: BACKLOG / param-mismatch/ param[1] (text)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts.Step' 
signalwire.core.contexts.Step.set_valid_contexts: BACKLOG / param-mismatch/ param[1] (contexts)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.conte
signalwire.core.contexts.Step.set_valid_steps: BACKLOG / param-mismatch/ param[1] (steps)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.contexts
signalwire.core.contexts.Step.to_dict: BACKLOG / missing-port/ in reference, not in port
signalwire.core.contexts.Step.to_hash: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.contexts.create_simple_context: BACKLOG / missing-port/ in reference, not in port
signalwire.core.data_map.DataMap._error_keys: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap._expressions: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap._output: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap._parameters: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap._purpose: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap._required_params: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap._webhooks: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap.body: BACKLOG / param-mismatch/ param[1] (data)/ type 'dict<string,any>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.data_
signalwire.core.data_map.DataMap.description: BACKLOG / param-mismatch/ param[1] (description)/ name 'description' vs 'desc'; type 'string' vs 'any'; return-mismatch/ returns '
signalwire.core.data_map.DataMap.error_keys: BACKLOG / param-mismatch/ param[1] (keys)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.data_map.
signalwire.core.data_map.DataMap.expression: BACKLOG / param-mismatch/ param[1] (test_value)/ type 'string' vs 'any'; param-mismatch/ param[2] (pattern)/ type 'union<class/Pat
signalwire.core.data_map.DataMap.fallback_output: BACKLOG / param-mismatch/ param[1] (result)/ type 'class/signalwire.core.function_result.FunctionResult' v; return-mismatch/ retur
signalwire.core.data_map.DataMap.foreach: BACKLOG / param-mismatch/ param[1] (foreach_config)/ name 'foreach_config' vs 'config'; type 'dict<string,; return-mismatch/ retur
signalwire.core.data_map.DataMap.function_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.data_map.DataMap.global_error_keys: BACKLOG / param-mismatch/ param[1] (keys)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.data_map.
signalwire.core.data_map.DataMap.output: BACKLOG / param-mismatch/ param[1] (result)/ type 'class/signalwire.core.function_result.FunctionResult' v; return-mismatch/ retur
signalwire.core.data_map.DataMap.parameter: BACKLOG / param-count-mismatch/ reference has 6 param(s), port has 5/ reference=['self', 'name', 'param_type', '; return-mismatch/
signalwire.core.data_map.DataMap.params: BACKLOG / param-mismatch/ param[1] (data)/ type 'dict<string,any>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.data_
signalwire.core.data_map.DataMap.purpose: BACKLOG / param-mismatch/ param[1] (description)/ name 'description' vs 'desc'; type 'string' vs 'any'; return-mismatch/ returns '
signalwire.core.data_map.DataMap.to_swaig_function: BACKLOG / return-mismatch/ returns 'dict<string,any>' vs 'any'
signalwire.core.data_map.DataMap.webhook: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 4/ reference=['self', 'method', 'url', 'heade; return-mismatch/
signalwire.core.data_map.DataMap.webhook_expressions: BACKLOG / param-mismatch/ param[1] (expressions)/ type 'list<dict<string,any>>' vs 'any'; return-mismatch/ returns 'class/signalwi
signalwire.core.function_result.FunctionResult.action: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.function_result.FunctionResult.add_action: BACKLOG / param-mismatch/ param[1] (name)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_result
signalwire.core.function_result.FunctionResult.add_actions: BACKLOG / param-mismatch/ param[1] (actions)/ type 'list<dict<string,any>>' vs 'any'; return-mismatch/ returns 'class/signalwire.c
signalwire.core.function_result.FunctionResult.add_dynamic_hints: BACKLOG / param-mismatch/ param[1] (hints)/ type 'list<union<dict<string,any>,string>>' vs 'any'; return-mismatch/ returns 'class/
signalwire.core.function_result.FunctionResult.clear_dynamic_hints: BACKLOG / return-mismatch/ returns 'class/signalwire.core.function_result.FunctionResult' vs 'any'
signalwire.core.function_result.FunctionResult.connect: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 3/ reference=['self', 'destination', 'final',; return-mismatch/
signalwire.core.function_result.FunctionResult.create_payment_action: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 3/ reference=['action_type', 'phrase'] port=[; return-mismatch/
signalwire.core.function_result.FunctionResult.create_payment_parameter: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 3/ reference=['name', 'value'] port=['class_o; return-mismatch/
signalwire.core.function_result.FunctionResult.create_payment_prompt: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['for_situation', 'actions', 'ca; return-mismatch/
signalwire.core.function_result.FunctionResult.enable_extensive_data: BACKLOG / param-mismatch/ param[1] (enabled)/ type 'bool' vs 'any'; required False vs True; default True v; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.enable_functions_on_timeout: BACKLOG / param-mismatch/ param[1] (enabled)/ type 'bool' vs 'any'; required False vs True; default True v; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.execute_rpc: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'method', 'params', 'ca; return-mismatch/
signalwire.core.function_result.FunctionResult.execute_swml: BACKLOG / param-mismatch/ param[2] (transfer)/ name 'transfer' vs 'opts'; type 'bool' vs 'any'; required F; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.hangup: BACKLOG / return-mismatch/ returns 'class/signalwire.core.function_result.FunctionResult' vs 'any'
signalwire.core.function_result.FunctionResult.hold: BACKLOG / param-mismatch/ param[1] (timeout)/ type 'int' vs 'any'; required False vs True; default 300 vs ; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.join_conference: BACKLOG / param-count-mismatch/ reference has 19 param(s), port has 3/ reference=['self', 'name', 'muted', 'beep; return-mismatch/
signalwire.core.function_result.FunctionResult.join_room: BACKLOG / param-mismatch/ param[1] (name)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_result
signalwire.core.function_result.FunctionResult.pay: BACKLOG / param-count-mismatch/ reference has 20 param(s), port has 2/ reference=['self', 'payment_connector_url; return-mismatch/
signalwire.core.function_result.FunctionResult.play_background_file: BACKLOG / param-mismatch/ param[1] (filename)/ type 'string' vs 'any'; param-mismatch/ param[2] (wait)/ name 'wait' vs 'opts'; typ
signalwire.core.function_result.FunctionResult.post_process: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.function_result.FunctionResult.record_call: BACKLOG / param-count-mismatch/ reference has 12 param(s), port has 2/ reference=['self', 'control_id', 'stereo'; return-mismatch/
signalwire.core.function_result.FunctionResult.remove_global_data: BACKLOG / param-mismatch/ param[1] (keys)/ type 'union<list<string>,string>' vs 'any'; return-mismatch/ returns 'class/signalwire.
signalwire.core.function_result.FunctionResult.remove_metadata: BACKLOG / param-mismatch/ param[1] (keys)/ type 'union<list<string>,string>' vs 'any'; return-mismatch/ returns 'class/signalwire.
signalwire.core.function_result.FunctionResult.replace_in_history: BACKLOG / param-mismatch/ param[1] (text)/ type 'union<bool,string>' vs 'any'; required False vs True; def; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.response: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.function_result.FunctionResult.rpc_ai_message: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'call_id', 'message_tex; return-mismatch/
signalwire.core.function_result.FunctionResult.rpc_ai_unhold: BACKLOG / param-mismatch/ param[1] (call_id)/ name 'call_id' vs 'opts'; type 'string' vs 'any'; return-mismatch/ returns 'class/si
signalwire.core.function_result.FunctionResult.rpc_dial: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'to_number', 'from_numb; return-mismatch/
signalwire.core.function_result.FunctionResult.say: BACKLOG / param-mismatch/ param[1] (text)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_result
signalwire.core.function_result.FunctionResult.send_sms: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 2/ reference=['self', 'to_number', 'from_numb; return-mismatch/
signalwire.core.function_result.FunctionResult.set_end_of_speech_timeout: BACKLOG / param-mismatch/ param[1] (milliseconds)/ name 'milliseconds' vs 'ms'; type 'int' vs 'any'; return-mismatch/ returns 'cla
signalwire.core.function_result.FunctionResult.set_metadata: BACKLOG / param-mismatch/ param[1] (data)/ type 'dict<string,any>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.funct
signalwire.core.function_result.FunctionResult.set_post_process: BACKLOG / param-mismatch/ param[1] (post_process)/ type 'bool' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_
signalwire.core.function_result.FunctionResult.set_response: BACKLOG / param-mismatch/ param[1] (response)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_re
signalwire.core.function_result.FunctionResult.set_speech_event_timeout: BACKLOG / param-mismatch/ param[1] (milliseconds)/ name 'milliseconds' vs 'ms'; type 'int' vs 'any'; return-mismatch/ returns 'cla
signalwire.core.function_result.FunctionResult.simulate_user_input: BACKLOG / param-mismatch/ param[1] (text)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_result
signalwire.core.function_result.FunctionResult.sip_refer: BACKLOG / param-mismatch/ param[1] (to_uri)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_resu
signalwire.core.function_result.FunctionResult.stop: BACKLOG / return-mismatch/ returns 'class/signalwire.core.function_result.FunctionResult' vs 'any'
signalwire.core.function_result.FunctionResult.stop_background_file: BACKLOG / return-mismatch/ returns 'class/signalwire.core.function_result.FunctionResult' vs 'any'
signalwire.core.function_result.FunctionResult.stop_record_call: BACKLOG / param-mismatch/ param[1] (control_id)/ name 'control_id' vs 'opts'; type 'optional<string>' vs '; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.stop_tap: BACKLOG / param-mismatch/ param[1] (control_id)/ name 'control_id' vs 'opts'; type 'optional<string>' vs '; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.switch_context: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'system_prompt', 'user_; return-mismatch/
signalwire.core.function_result.FunctionResult.swml_change_context: BACKLOG / param-mismatch/ param[1] (context_name)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.functio
signalwire.core.function_result.FunctionResult.swml_change_step: BACKLOG / param-mismatch/ param[1] (step_name)/ type 'string' vs 'any'; return-mismatch/ returns 'class/signalwire.core.function_r
signalwire.core.function_result.FunctionResult.swml_transfer: BACKLOG / param-mismatch/ param[1] (dest)/ type 'string' vs 'any'; param-mismatch/ param[2] (ai_response)/ type 'string' vs 'any'
signalwire.core.function_result.FunctionResult.swml_user_event: BACKLOG / param-mismatch/ param[1] (event_data)/ type 'dict<string,any>' vs 'any'; return-mismatch/ returns 'class/signalwire.core
signalwire.core.function_result.FunctionResult.tap: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 3/ reference=['self', 'uri', 'control_id', 'd; return-mismatch/
signalwire.core.function_result.FunctionResult.to_dict: BACKLOG / missing-port/ in reference, not in port
signalwire.core.function_result.FunctionResult.to_hash: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.function_result.FunctionResult.toggle_functions: BACKLOG / param-mismatch/ param[1] (function_toggles)/ name 'function_toggles' vs 'toggles'; type 'list<di; return-mismatch/ retur
signalwire.core.function_result.FunctionResult.update_global_data: BACKLOG / param-mismatch/ param[1] (data)/ type 'dict<string,any>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.funct
signalwire.core.function_result.FunctionResult.update_settings: BACKLOG / param-mismatch/ param[1] (settings)/ type 'dict<string,any>' vs 'any'; return-mismatch/ returns 'class/signalwire.core.f
signalwire.core.function_result.FunctionResult.wait_for_user: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'enabled', 'timeout', '; return-mismatch/
signalwire.core.logging_config.get_logger: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_function_include: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_hint: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_hints: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_internal_filler: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_language: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_mcp_server: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_pattern_hint: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.add_pronunciation: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.enable_debug_events: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.enable_mcp_server: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_function_includes: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_global_data: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_internal_fillers: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_languages: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_native_functions: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_param: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_params: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_post_prompt_llm_params: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_prompt_llm_params: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.set_pronunciations: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.ai_config_mixin.AIConfigMixin.update_global_data: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.define_contexts: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.get_prompt: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.prompt_add_section: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.prompt_add_subsection: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.prompt_add_to_section: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.prompt_has_section: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.reset_contexts: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.set_post_prompt: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.prompt_mixin.PromptMixin.set_prompt_text: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.skill_mixin.SkillMixin.add_skill: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.skill_mixin.SkillMixin.has_skill: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.skill_mixin.SkillMixin.list_skills: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.skill_mixin.SkillMixin.remove_skill: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.web_mixin.WebMixin.manual_set_proxy_url: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.web_mixin.WebMixin.run: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.web_mixin.WebMixin.serve: BACKLOG / missing-port/ in reference, not in port
signalwire.core.mixins.web_mixin.WebMixin.set_dynamic_config_callback: BACKLOG / missing-port/ in reference, not in port
signalwire.core.security.session_manager.SessionManager._debug_mode: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.security.session_manager.SessionManager.activate_session: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 0/ reference=['self', 'call_id'] port=[]; return-mismatch/ retu
signalwire.core.security.session_manager.SessionManager.create_session: BACKLOG / param-mismatch/ param[1] (call_id)/ type 'optional<string>' vs 'any'; required False vs True; de; return-mismatch/ retur
signalwire.core.security.session_manager.SessionManager.create_tool_token: BACKLOG / param-mismatch/ param[1] (function_name)/ type 'string' vs 'any'; param-mismatch/ param[2] (call_id)/ type 'string' vs '
signalwire.core.security.session_manager.SessionManager.debug_token: BACKLOG / param-mismatch/ param[1] (token)/ type 'string' vs 'any'; return-mismatch/ returns 'dict<string,any>' vs 'any'
signalwire.core.security.session_manager.SessionManager.end_session: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 0/ reference=['self', 'call_id'] port=[]; return-mismatch/ retu
signalwire.core.security.session_manager.SessionManager.generate_token: BACKLOG / param-mismatch/ param[1] (function_name)/ type 'string' vs 'any'; param-mismatch/ param[2] (call_id)/ type 'string' vs '
signalwire.core.security.session_manager.SessionManager.get_session_metadata: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 0/ reference=['self', 'call_id'] port=[]; return-mismatch/ retu
signalwire.core.security.session_manager.SessionManager.secret_key: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.security.session_manager.SessionManager.set_session_metadata: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 0/ reference=['self', 'call_id', 'key', 'valu; return-mismatch/
signalwire.core.security.session_manager.SessionManager.token_expiry_secs: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.security.session_manager.SessionManager.validate_token: BACKLOG / param-mismatch/ param[1] (call_id)/ type 'string' vs 'any'; param-mismatch/ param[2] (function_name)/ type 'string' vs '
signalwire.core.security.session_manager.SessionManager.validate_tool_token: BACKLOG / param-mismatch/ param[1] (function_name)/ type 'string' vs 'any'; param-mismatch/ param[2] (token)/ type 'string' vs 'an
signalwire.core.skill_base.SkillBase.cleanup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'void' 
signalwire.core.skill_base.SkillBase.define_tool: BACKLOG / param-mismatch/ param[1] (kwargs)/ name 'kwargs' vs 'opts'; kind 'var_keyword' vs 'positional'; ; return-mismatch/ retur
signalwire.core.skill_base.SkillBase.get_global_data: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'dict<s
signalwire.core.skill_base.SkillBase.get_hints: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'list<s
signalwire.core.skill_base.SkillBase.get_instance_key: BACKLOG / return-mismatch/ returns 'string' vs 'any'
signalwire.core.skill_base.SkillBase.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.core.skill_base.SkillBase.get_prompt_sections: BACKLOG / return-mismatch/ returns 'list<dict<string,any>>' vs 'any'
signalwire.core.skill_base.SkillBase.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.core.skill_base.SkillBase.setup: BACKLOG / return-mismatch/ returns 'bool' vs 'any'
signalwire.core.skill_base.SkillBase.validate_env_vars: BACKLOG / return-mismatch/ returns 'bool' vs 'any'
signalwire.core.skill_manager.SkillManager.has_skill: BACKLOG / param-mismatch/ param[1] (skill_identifier)/ name 'skill_identifier' vs 'key'; type 'string' vs ; return-mismatch/ retur
signalwire.core.skill_manager.SkillManager.load_skill: BACKLOG / param-mismatch/ param[1] (skill_name)/ type 'string' vs 'any'; param-mismatch/ param[2] (skill_class)/ type 'class/signa
signalwire.core.skill_manager.SkillManager.unload_skill: BACKLOG / param-mismatch/ param[1] (skill_identifier)/ name 'skill_identifier' vs 'key'; type 'string' vs ; return-mismatch/ retur
signalwire.core.swml_builder.SWMLBuilder.add_section: BACKLOG / param-mismatch/ param[1] (section_name)/ name 'section_name' vs 'name'; type 'string' vs 'any'; return-mismatch/ returns
signalwire.core.swml_builder.SWMLBuilder.sections: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_builder.SWMLBuilder.version: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService._logger: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.basic_auth_password: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.basic_auth_user: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.document: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.extract_sip_username: BACKLOG / missing-port/ in reference, not in port
signalwire.core.swml_service.SWMLService.host: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.name: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.port: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.register_routing_callback: BACKLOG / param-mismatch/ param[1] (callback_fn)/ name 'callback_fn' vs 'path'; type 'callable<list<class/; param-mismatch/ param[
signalwire.core.swml_service.SWMLService.route: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.routing_callbacks: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.tool_order: BACKLOG / missing-reference/ in port, not in reference
signalwire.core.swml_service.SWMLService.tools: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action._client: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action._on_completed: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.completed: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.events: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.is_done: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.payload: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.result: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Action.wait: BACKLOG / param-mismatch/ param[1] (timeout)/ name 'timeout' vs 'opts'; type 'optional<float>' vs 'any'; r; return-mismatch/ retur
signalwire.relay.call.Call._actions: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call._client: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call._on_event: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.ai: BACKLOG / param-count-mismatch/ reference has 16 param(s), port has 2/ reference=['self', 'control_id', 'agent',; return-mismatch/
signalwire.relay.call.Call.ai_hold: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'timeout', 'prompt', 'k; return-mismatch/
signalwire.relay.call.Call.ai_message: BACKLOG / param-count-mismatch/ reference has 6 param(s), port has 2/ reference=['self', 'message_text', 'role',; return-mismatch/
signalwire.relay.call.Call.ai_unhold: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'prompt', 'kwargs'] por; return-mismatch/
signalwire.relay.call.Call.amazon_bedrock: BACKLOG / param-count-mismatch/ reference has 8 param(s), port has 2/ reference=['self', 'prompt', 'SWAIG', 'ai_; return-mismatch/
signalwire.relay.call.Call.answer: BACKLOG / param-mismatch/ param[1] (kwargs)/ name 'kwargs' vs 'opts'; kind 'var_keyword' vs 'positional'; ; return-mismatch/ retur
signalwire.relay.call.Call.bind_digit: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 2/ reference=['self', 'digits', 'bind_method'; return-mismatch/
signalwire.relay.call.Call.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.clear_digit_bindings: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'realm', 'kwargs'] port; return-mismatch/
signalwire.relay.call.Call.collect: BACKLOG / param-count-mismatch/ reference has 11 param(s), port has 2/ reference=['self', 'digits', 'speech', 'i; return-mismatch/
signalwire.relay.call.Call.connect: BACKLOG / param-count-mismatch/ reference has 8 param(s), port has 2/ reference=['self', 'devices', 'ringback', ; return-mismatch/
signalwire.relay.call.Call.context: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.denoise: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.Call.denoise_stop: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.Call.detect: BACKLOG / param-count-mismatch/ reference has 6 param(s), port has 2/ reference=['self', 'detect', 'timeout', 'c; return-mismatch/
signalwire.relay.call.Call.device: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.dial_winner: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.disconnect: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.Call.echo: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'timeout', 'status_url'; return-mismatch/
signalwire.relay.call.Call.end_reason: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.hangup: BACKLOG / param-mismatch/ param[1] (reason)/ name 'reason' vs 'opts'; type 'string' vs 'any'; required Fal; return-mismatch/ retur
signalwire.relay.call.Call.hold: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.Call.join_conference: BACKLOG / param-count-mismatch/ reference has 22 param(s), port has 2/ reference=['self', 'name', 'muted', 'beep; return-mismatch/
signalwire.relay.call.Call.join_room: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'name', 'status_url', '; return-mismatch/
signalwire.relay.call.Call.leave_conference: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'conference_id', 'kwarg; return-mismatch/
signalwire.relay.call.Call.leave_room: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 1/ reference=['self', 'kwargs'] port=['self']; return-mismatch/
signalwire.relay.call.Call.live_transcribe: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'action', 'kwargs'] por; return-mismatch/
signalwire.relay.call.Call.live_translate: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'action', 'status_url',; return-mismatch/
signalwire.relay.call.Call.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.on: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'event_type', 'handler'; return-mismatch/
signalwire.relay.call.Call.pay: BACKLOG / param-count-mismatch/ reference has 22 param(s), port has 2/ reference=['self', 'payment_connector_url; return-mismatch/
signalwire.relay.call.Call.peer: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.play: BACKLOG / param-count-mismatch/ reference has 8 param(s), port has 2/ reference=['self', 'media', 'volume', 'dir; return-mismatch/
signalwire.relay.call.Call.play_and_collect: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 2/ reference=['self', 'media', 'collect', 'vo; return-mismatch/
signalwire.relay.call.Call.queue_enter: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'queue_name', 'control_; return-mismatch/
signalwire.relay.call.Call.queue_leave: BACKLOG / param-count-mismatch/ reference has 6 param(s), port has 2/ reference=['self', 'queue_name', 'control_; return-mismatch/
signalwire.relay.call.Call.receive_fax: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'control_id', 'on_compl; return-mismatch/
signalwire.relay.call.Call.record: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'audio', 'control_id', ; return-mismatch/
signalwire.relay.call.Call.refer: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 2/ reference=['self', 'device', 'status_url',; return-mismatch/
signalwire.relay.call.Call.send_digits: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'digits', 'control_id']; return-mismatch/
signalwire.relay.call.Call.send_fax: BACKLOG / param-count-mismatch/ reference has 7 param(s), port has 2/ reference=['self', 'document', 'identity',; return-mismatch/
signalwire.relay.call.Call.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.stream: BACKLOG / param-count-mismatch/ reference has 12 param(s), port has 2/ reference=['self', 'url', 'name', 'codec'; return-mismatch/
signalwire.relay.call.Call.tag: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.Call.tap: BACKLOG / param-count-mismatch/ reference has 6 param(s), port has 2/ reference=['self', 'tap', 'device', 'contr; return-mismatch/
signalwire.relay.call.Call.transcribe: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'control_id', 'status_u; return-mismatch/
signalwire.relay.call.Call.transfer: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'dest', 'kwargs'] port=; return-mismatch/
signalwire.relay.call.Call.unhold: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.Call.user_event: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 2/ reference=['self', 'event', 'kwargs'] port; return-mismatch/
signalwire.relay.call.CollectAction.start_input_timers: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.FaxAction._fax_type: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.call.PlayAction.pause: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.PlayAction.resume: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.call.PlayAction.volume: BACKLOG / param-mismatch/ param[1] (volume)/ name 'volume' vs 'vol'; type 'float' vs 'any'; return-mismatch/ returns 'dict<any,any
signalwire.relay.call.RecordAction.pause: BACKLOG / param-mismatch/ param[1] (behavior)/ name 'behavior' vs 'opts'; type 'optional<string>' vs 'any'; return-mismatch/ retur
signalwire.relay.call.RecordAction.resume: BACKLOG / return-mismatch/ returns 'dict<any,any>' vs 'any'
signalwire.relay.client.RelayClient._calls: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._max_backoff: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._messages: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._on_call: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._on_event: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._on_message: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._pending: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._pending_dials: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._reconnect_attempts: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._socket: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient._ws: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.agent: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.authorization_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.connected: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.contexts: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.dial: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 2/ reference=['self', 'devices', 'tag', 'max_; return-mismatch/
signalwire.relay.client.RelayClient.execute: BACKLOG / param-mismatch/ param[1] (method)/ type 'string' vs 'any'; param-mismatch/ param[2] (params)/ type 'dict<string,any>' vs
signalwire.relay.client.RelayClient.host: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.on_call: BACKLOG / param-mismatch/ param[1] (handler)/ name 'handler' vs 'cb'; type 'class/signalwire.relay.client.; return-mismatch/ retur
signalwire.relay.client.RelayClient.on_message: BACKLOG / param-mismatch/ param[1] (handler)/ name 'handler' vs 'cb'; type 'class/signalwire.relay.client.; return-mismatch/ retur
signalwire.relay.client.RelayClient.path: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.project: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.protocol: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.receive: BACKLOG / param-mismatch/ param[1] (contexts)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'void' vs 'any'
signalwire.relay.client.RelayClient.run: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.relay.client.RelayClient.scheme: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.send_message: BACKLOG / param-count-mismatch/ reference has 9 param(s), port has 2/ reference=['self', 'to_number', 'from_numb; return-mismatch/
signalwire.relay.client.RelayClient.session_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.token: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.client.RelayClient.unreceive: BACKLOG / param-mismatch/ param[1] (contexts)/ type 'list<string>' vs 'any'; return-mismatch/ returns 'void' vs 'any'
signalwire.relay.event.CallReceiveEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallReceiveEvent.call_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallReceiveEvent.context: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallReceiveEvent.device: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallReceiveEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallReceiveEvent.tag: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallStateEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallStateEvent.call_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallStateEvent.device: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallStateEvent.end_reason: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallStateEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallStateEvent.peer: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallStateEvent.tag: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallingErrorEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallingErrorEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CallingErrorEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CollectEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CollectEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CollectEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.CollectEvent.result: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ConferenceEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ConferenceEvent.conference_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ConferenceEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ConnectEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ConnectEvent.connect_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ConnectEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ConnectEvent.peer: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DetectEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DetectEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DetectEvent.detect: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DetectEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DialEvent.call: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DialEvent.dial_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DialEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.DialEvent.tag: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.FaxEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.FaxEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.FaxEvent.fax: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.FaxEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.body: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.context: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.direction: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.from_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.media: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.message_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.message_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.segments: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.tags: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageReceiveEvent.to_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.body: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.context: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.direction: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.from_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.media: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.message_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.message_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.reason: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.segments: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.tags: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.MessageStateEvent.to_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PayEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PayEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PayEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PayEvent.result: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PayEvent.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PlayEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PlayEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PlayEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.PlayEvent.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.duration: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.record: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.size: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RecordEvent.url: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ReferEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ReferEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.ReferEvent.refer_state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RelayEvent.event_type: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RelayEvent.params: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.RelayEvent.timestamp: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.SendDigitsEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.SendDigitsEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.SendDigitsEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.SendDigitsEvent.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.StreamEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.StreamEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.StreamEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.StreamEvent.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TapEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TapEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TapEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TapEvent.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TapEvent.tap: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TranscribeEvent.call_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TranscribeEvent.control_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TranscribeEvent.node_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.event.TranscribeEvent.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message._on_completed: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message._on_event: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.body: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.completed: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.context: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.direction: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.from_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.is_done: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.media: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.message_id: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.on: BACKLOG / param-mismatch/ param[1] (handler)/ name 'handler' vs 'cb'; type 'class/Callable' vs 'any'; return-mismatch/ returns 'vo
signalwire.relay.message.Message.reason: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.segments: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.state: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.tags: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.to_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.relay.message.Message.wait: BACKLOG / param-mismatch/ param[1] (timeout)/ name 'timeout' vs 'opts'; type 'optional<float>' vs 'any'; r; return-mismatch/ retur
signalwire.rest._base.BaseResource._base_path: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.BaseResource._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.CrudResource._update_method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.CrudResource.create: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.CrudResource.delete_resource: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.CrudResource.get: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.CrudResource.list: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.CrudResource.update: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient._auth_header: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient._ua: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.base_url: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.delete_request: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.get: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.host: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.patch: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.post: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.project: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.put: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.HttpClient.token: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.SignalWireRestError.body: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.SignalWireRestError.method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.SignalWireRestError.status_code: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest._base.SignalWireRestError.url: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.addresses: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.calling: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.chat: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.compat: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.datasphere: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.fabric: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.host: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.imported_numbers: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.logs: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.lookup: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.mfa: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.number_groups: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.phone_numbers: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.project: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.project_ns: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.pubsub: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.queues: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.recordings: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.registry: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.short_codes: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.sip_profile: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.token: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.verified_callers: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.client.RestClient.video: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.addresses.AddressesResource.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.addresses.AddressesResource.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.calling.CallingNamespace.ai_hold: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.ai_message: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.ai_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.ai_unhold: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.collect: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.collect_start_input_timers: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.collect_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.denoise: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.denoise_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.detect: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.detect_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.dial: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 0/ reference=['self', 'params'] port=[]
signalwire.rest.namespaces.calling.CallingNamespace.disconnect: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.end: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.live_transcribe: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.live_translate: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.play: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.play_pause: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.play_resume: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.play_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.play_volume: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.receive_fax_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.record: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.record_pause: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.record_resume: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.record_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.refer: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.send_fax_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.stream: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.stream_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.tap: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.tap_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.transcribe: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.transcribe_stop: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.transfer: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.calling.CallingNamespace.user_event: BACKLOG / param-count-mismatch/ reference has 3 param(s), port has 0/ reference=['self', 'call_id', 'params'] po
signalwire.rest.namespaces.chat.ChatResource.create_token: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatAccounts.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatAccounts.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatAccounts.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatApplications.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatCalls.start_recording: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatCalls.start_stream: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatCalls.stop_stream: BACKLOG / param-mismatch/ param[3] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatCalls.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatCalls.update_recording: BACKLOG / param-mismatch/ param[3] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.list_participants: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.list_recordings: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.start_stream: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.stop_stream: BACKLOG / param-mismatch/ param[3] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.update_participant: BACKLOG / param-mismatch/ param[3] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatConferences.update_recording: BACKLOG / param-mismatch/ param[3] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatFaxes.list_media: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatFaxes.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatLamlBins.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatMessages.list_media: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatMessages.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatNamespace._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.account_sid: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.accounts: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.applications: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.calls: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.conferences: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.faxes: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.laml_bins: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.messages: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.phone_numbers: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.queues: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.recordings: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.tokens: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatNamespace.transcriptions: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatPhoneNumbers._available_base: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatPhoneNumbers.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.compat.CompatPhoneNumbers.delete_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatPhoneNumbers.import_number: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatPhoneNumbers.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatPhoneNumbers.list_available_countries: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatPhoneNumbers.purchase: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatPhoneNumbers.search_local: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatPhoneNumbers.search_toll_free: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatPhoneNumbers.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatQueues.dequeue_member: BACKLOG / param-mismatch/ param[3] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatQueues.list_members: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatQueues.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatRecordings.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.compat.CompatRecordings.delete_recording: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatRecordings.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatTokens.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatTokens.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.compat.CompatTokens.delete_token: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatTokens.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.compat.CompatTranscriptions.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.compat.CompatTranscriptions.delete_transcription: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.compat.CompatTranscriptions.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.datasphere.DatasphereDocuments.list_chunks: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.datasphere.DatasphereDocuments.search: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.AutoMaterializedWebhook._auto_helper_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.AutoMaterializedWebhook.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.CallFlowsResource.deploy_version: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.CallFlowsResource.list_addresses: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.CallFlowsResource.list_versions: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.ConferenceRoomsResource.list_addresses: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.CxmlApplicationsResource.create: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 0/ reference=['self', 'kwargs'] port=[]
signalwire.rest.namespaces.fabric.CxmlWebhooksResource._auto_helper_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.addresses: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.ai_agents: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.call_flows: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.conference_rooms: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.cxml_applications: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.cxml_scripts: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.cxml_webhooks: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.freeswitch_connectors: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.relay_applications: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.resources: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.sip_endpoints: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.sip_gateways: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.subscribers: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.swml_scripts: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.swml_webhooks: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricNamespace.tokens: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.FabricTokens.create_embed_token: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.FabricTokens.create_guest_token: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.FabricTokens.create_invite_token: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.FabricTokens.create_subscriber_token: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.FabricTokens.refresh_subscriber_token: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.GenericResources.assign_domain_application: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.GenericResources.assign_phone_route: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.GenericResources.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.fabric.GenericResources.delete_resource: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.fabric.GenericResources.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.GenericResources.list_addresses: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.SubscribersResource.create_sip_endpoint: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.SubscribersResource.list_sip_endpoints: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.SubscribersResource.update_sip_endpoint: BACKLOG / param-mismatch/ param[3] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.fabric.SwmlWebhooksResource._auto_helper_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.imported_numbers.ImportedNumbersResource.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.logs.ConferenceLogs.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.logs.FaxLogs.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.logs.LogsNamespace._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.logs.LogsNamespace.conferences: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.logs.LogsNamespace.fax: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.logs.LogsNamespace.messages: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.logs.LogsNamespace.voice: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.logs.MessageLogs.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.logs.VoiceLogs.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.logs.VoiceLogs.list_events: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.lookup.LookupResource.phone_number: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.mfa.MfaResource.call: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.mfa.MfaResource.sms: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.mfa.MfaResource.verify: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.number_groups.NumberGroupsResource._update_method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.number_groups.NumberGroupsResource.add_membership: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.number_groups.NumberGroupsResource.list_memberships: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource._update_method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.search: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.set_ai_agent: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 3/ reference=['self', 'resource_id', 'agent_i; return-mismatch/
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.set_call_flow: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 3/ reference=['self', 'resource_id', 'flow_id; return-mismatch/
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.set_cxml_application: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 3/ reference=['self', 'resource_id', 'applica; return-mismatch/
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.set_cxml_webhook: BACKLOG / param-count-mismatch/ reference has 6 param(s), port has 3/ reference=['self', 'resource_id', 'url', '; return-mismatch/
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.set_relay_application: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 3/ reference=['self', 'resource_id', 'name', ; return-mismatch/
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.set_relay_topic: BACKLOG / param-count-mismatch/ reference has 5 param(s), port has 3/ reference=['self', 'resource_id', 'topic',; return-mismatch/
signalwire.rest.namespaces.phone_numbers.PhoneNumbersResource.set_swml_webhook: BACKLOG / param-count-mismatch/ reference has 4 param(s), port has 3/ reference=['self', 'resource_id', 'url', '; return-mismatch/
signalwire.rest.namespaces.project.ProjectNamespace._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.project.ProjectNamespace.tokens: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.project.ProjectTokens.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.project.ProjectTokens.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.project.ProjectTokens.delete_token: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.project.ProjectTokens.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.pubsub.PubSubResource.create_token: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.queues.QueuesResource._update_method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.queues.QueuesResource.list_members: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.recordings.RecordingsResource.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.recordings.RecordingsResource.delete_recording: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.recordings.RecordingsResource.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryBrands.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryBrands.create_campaign: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryBrands.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryBrands.list_campaigns: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryCampaigns.create_order: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryCampaigns.list_numbers: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryCampaigns.list_orders: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryCampaigns.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.registry.RegistryNamespace._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.registry.RegistryNamespace.brands: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.registry.RegistryNamespace.campaigns: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.registry.RegistryNamespace.numbers: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.registry.RegistryNamespace.orders: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.registry.RegistryNumbers.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.registry.RegistryNumbers.delete_number: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.short_codes.ShortCodesResource.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.short_codes.ShortCodesResource.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.sip_profile.SipProfileResource.update: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.verified_callers.VerifiedCallersResource._update_method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.verified_callers.VerifiedCallersResource.submit_verification: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoConferences._update_method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoConferences.create_stream: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoConferences.list_conference_tokens: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoConferences.list_streams: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoNamespace._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoNamespace.conference_tokens: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoNamespace.conferences: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoNamespace.room_recordings: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoNamespace.room_sessions: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoNamespace.room_tokens: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoNamespace.rooms: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoNamespace.streams: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoRoomRecordings.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.video.VideoRoomRecordings.delete_recording: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoRoomRecordings.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRoomRecordings.list_events: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRoomSessions.list: BACKLOG / param-mismatch/ param[1] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRoomSessions.list_events: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRoomSessions.list_members: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRoomSessions.list_recordings: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRoomTokens.create: BACKLOG / param-mismatch/ param[1] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRooms._update_method: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoRooms.create_stream: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoRooms.list_streams: BACKLOG / param-mismatch/ param[2] (params)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.rest.namespaces.video.VideoStreams.delete: BACKLOG / missing-port/ in reference, not in port
signalwire.rest.namespaces.video.VideoStreams.delete_stream: BACKLOG / missing-reference/ in port, not in reference
signalwire.rest.namespaces.video.VideoStreams.update: BACKLOG / param-mismatch/ param[2] (kwargs)/ kind 'var_keyword' vs 'positional'; required False vs True; d
signalwire.search.preprocess_document_content: BACKLOG / missing-port/ in reference, not in port
signalwire.search.preprocess_query: BACKLOG / missing-port/ in reference, not in port
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.api_ninjas_trivia.skill.ApiNinjasTriviaSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.claude_skills.skill.ClaudeSkillsSkill.get_hints: BACKLOG / return-mismatch/ returns 'list<string>' vs 'any'
signalwire.skills.claude_skills.skill.ClaudeSkillsSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.claude_skills.skill.ClaudeSkillsSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.claude_skills.skill.ClaudeSkillsSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.claude_skills.skill.ClaudeSkillsSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.claude_skills.skill.ClaudeSkillsSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.claude_skills.skill.ClaudeSkillsSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere.skill.DataSphereSkill._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere.skill.DataSphereSkill.base_url: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere.skill.DataSphereSkill.get_global_data: BACKLOG / return-mismatch/ returns 'dict<string,any>' vs 'any'
signalwire.skills.datasphere.skill.DataSphereSkill.get_hints: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'list<s
signalwire.skills.datasphere.skill.DataSphereSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.datasphere.skill.DataSphereSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.datasphere.skill.DataSphereSkill.setup: BACKLOG / return-mismatch/ returns 'bool' vs 'any'
signalwire.skills.datasphere.skill.DataSphereSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere.skill.DataSphereSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere.skill.DataSphereSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.get_global_data: BACKLOG / return-mismatch/ returns 'dict<string,any>' vs 'any'
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.get_hints: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'list<s
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datasphere_serverless.skill.DataSphereServerlessSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datetime.skill.DateTimeSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.datetime.skill.DateTimeSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.datetime.skill.DateTimeSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.datetime.skill.DateTimeSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datetime.skill.DateTimeSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.datetime.skill.DateTimeSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.google_maps.skill.GoogleMapsSkill.get_hints: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'list<s
signalwire.skills.google_maps.skill.GoogleMapsSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.google_maps.skill.GoogleMapsSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.google_maps.skill.GoogleMapsSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.google_maps.skill.GoogleMapsSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.google_maps.skill.GoogleMapsSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.google_maps.skill.GoogleMapsSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.info_gatherer.skill.InfoGathererSkill.get_global_data: BACKLOG / return-mismatch/ returns 'dict<string,any>' vs 'any'
signalwire.skills.info_gatherer.skill.InfoGathererSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.info_gatherer.skill.InfoGathererSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.info_gatherer.skill.InfoGathererSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.info_gatherer.skill.InfoGathererSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.info_gatherer.skill.InfoGathererSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.info_gatherer.skill.InfoGathererSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.joke.skill.JokeSkill.get_global_data: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'dict<s
signalwire.skills.joke.skill.JokeSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.joke.skill.JokeSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.joke.skill.JokeSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.joke.skill.JokeSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.joke.skill.JokeSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.joke.skill.JokeSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.math.skill.MathSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.math.skill.MathSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.math.skill.MathSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.math.skill.MathSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.math.skill.MathSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.math.skill.MathSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.get_global_data: BACKLOG / return-mismatch/ returns 'dict<string,any>' vs 'any'
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.get_hints: BACKLOG / return-mismatch/ returns 'list<string>' vs 'any'
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.mcp_gateway.skill.MCPGatewaySkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill.get_hints: BACKLOG / return-mismatch/ returns 'list<string>' vs 'any'
signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.native_vector_search.skill.NativeVectorSearchSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.play_background_file.skill.PlayBackgroundFileSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.registry.SkillRegistry.list_skills: BACKLOG / param-mismatch/ param[0] (self)/ kind 'self' vs 'cls'; return-mismatch/ returns 'list<dict<string,string>>' vs 'any'
signalwire.skills.registry.SkillRegistry.register_skill: BACKLOG / param-count-mismatch/ reference has 2 param(s), port has 3/ reference=['self', 'skill_class'] port=['s; return-mismatch/
signalwire.skills.spider.skill.SpiderSkill._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.spider.skill.SpiderSkill.base_url: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.spider.skill.SpiderSkill.get_hints: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'list<s
signalwire.skills.spider.skill.SpiderSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.spider.skill.SpiderSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.spider.skill.SpiderSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.spider.skill.SpiderSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.spider.skill.SpiderSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.spider.skill.SpiderSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.swml_transfer.skill.SWMLTransferSkill.get_hints: BACKLOG / return-mismatch/ returns 'list<string>' vs 'any'
signalwire.skills.swml_transfer.skill.SWMLTransferSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.swml_transfer.skill.SWMLTransferSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.swml_transfer.skill.SWMLTransferSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.swml_transfer.skill.SWMLTransferSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.swml_transfer.skill.SWMLTransferSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.swml_transfer.skill.SWMLTransferSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.weather_api.skill.WeatherApiSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.weather_api.skill.WeatherApiSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.weather_api.skill.WeatherApiSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.weather_api.skill.WeatherApiSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.weather_api.skill.WeatherApiSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.weather_api.skill.WeatherApiSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.web_search.skill.WebSearchSkill._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.web_search.skill.WebSearchSkill.base_url: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.web_search.skill.WebSearchSkill.get_global_data: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'dict<s
signalwire.skills.web_search.skill.WebSearchSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.web_search.skill.WebSearchSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.web_search.skill.WebSearchSkill.setup: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['self'] port=[]; return-mismatch/ returns 'bool' 
signalwire.skills.web_search.skill.WebSearchSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.web_search.skill.WebSearchSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.web_search.skill.WebSearchSkill.skill_version: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.web_search.skill.WebSearchSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill._http: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.base_url: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.get_parameter_schema: BACKLOG / param-count-mismatch/ reference has 1 param(s), port has 0/ reference=['cls'] port=[]; return-mismatch/ returns 'dict<st
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.no_results_message: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.num_results: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.register_tools: BACKLOG / return-mismatch/ returns 'void' vs 'any'
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.search_wiki: BACKLOG / param-mismatch/ param[1] (query)/ type 'string' vs 'any'; return-mismatch/ returns 'string' vs 'any'
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.setup: BACKLOG / return-mismatch/ returns 'bool' vs 'any'
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.skill_description: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.skill_name: BACKLOG / missing-reference/ in port, not in reference
signalwire.skills.wikipedia_search.skill.WikipediaSearchSkill.supports_multiple_instances: BACKLOG / missing-reference/ in port, not in reference
signalwire.utils.schema_utils.SchemaUtils.schema_data: BACKLOG / missing-reference/ in port, not in reference
signalwire.utils.schema_utils.SchemaUtils.verbs: BACKLOG / missing-reference/ in port, not in reference
