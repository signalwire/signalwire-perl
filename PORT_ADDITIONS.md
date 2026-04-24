# PORT_ADDITIONS.md

Symbols the Perl port ships that have no Python-reference equivalent.
One line per symbol: `<fully.qualified.symbol>: <one-sentence rationale>`.
Checked by `scripts/diff_port_surface.py` against `python_surface.json`.

See also: PORT_OMISSIONS.md for Python-reference symbols we deliberately skip.

---

signalwire.agent_server.AgentServer.list_agents: port-only accessor: Perl convention surfaces a list-style getter where Python uses a generator or direct attribute access
signalwire.agent_server.AgentServer.psgi_app: port-only: Perl ports use Plack/PSGI; psgi_app returns a coderef any Plack handler consumes
signalwire.core.agent_base.AgentBase.list_tool_names: port-only helper used by ContextBuilder->validate to surface reserved-name collisions
signalwire.core.agent_base.AgentBase.psgi_app: port-only: Perl ports use Plack/PSGI; psgi_app returns a coderef any Plack handler consumes
signalwire.core.agent_base.AgentBase.render_swml: port-only public alias: Perl exposes render_swml as the method users call to dump SWML; Python keeps this internal
signalwire.core.agent_base.AgentBase.set_answer_config: port-only helper: wires AnswerConfig into SWML rendering; Python threads these through AIConfigMixin
signalwire.core.contexts.ContextBuilder.attach_agent: port-only: weak-ref back to agent so validate() can check reserved tool-name collisions; Python avoids this via Python-level closures
signalwire.core.contexts.ContextBuilder.has_contexts: port-only: explicit presence check used in AgentBase build path; Python uses `if cb.contexts` idiom
signalwire.core.contexts.ContextBuilder.to_hashref: port-only: alias to to_dict that returns the nested hashref explicitly (Perl idiom)
signalwire.core.function_result.FunctionResult.to_json: port-only: convenience serializer; Python uses json.dumps(result.to_dict())
signalwire.core.logging_config.debug: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.logging_config.error: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.logging_config.info: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.logging_config.warn: port-only: Perl exports package-level logging functions; Python uses a logger handle (get_logger().debug(...))
signalwire.core.skill_manager.SkillManager.list_skills: port-only accessor: Perl convention surfaces a list-style getter where Python uses a generator or direct attribute access
signalwire.core.swml_builder.SWMLBuilder.add_raw_verb: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.add_verb: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.clear_section: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.get_section: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.has_section: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.to_hash: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.to_json: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_builder.SWMLBuilder.to_pretty_json: port-only: SWML::Document public helper that Python keeps on SWMLService or private
signalwire.core.swml_service.SWMLService.can: port-only: Perl can() accessor (Moo plumbing) — surfaced because SWMLService defines it; harmless but recorded
signalwire.core.swml_service.SWMLService.render_swml: port-only public alias: Perl exposes render_swml as the method users call to dump SWML; Python keeps this internal
signalwire.core.swml_service.SWMLService.to_psgi_app: port-only: Perl ports use Plack/PSGI; psgi_app returns a coderef any Plack handler consumes
signalwire.relay.call.Action.on_completed: port-only Action/Message helper; Python packs this into wait()/dispatch paths
signalwire.relay.call.Action.stop: port-only Action/Message helper; Python packs this into wait()/dispatch paths
signalwire.relay.call.Call.dispatch_event: port-only dispatcher/passthrough helper for Perl-idiomatic event plumbing
signalwire.relay.call.Call.pass: port-only dispatcher/passthrough helper for Perl-idiomatic event plumbing
signalwire.relay.call.CollectAction.collect_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.DetectAction.detect_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.FaxAction.fax_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.PayAction.pay_result: port-only: strongly-typed Perl accessor for the result payload on each Action subclass
signalwire.relay.call.RecordAction.duration: port-only: Perl RecordAction exposes url/duration/size as explicit accessors; Python uses attribute-style access
signalwire.relay.call.RecordAction.size: port-only: Perl RecordAction exposes url/duration/size as explicit accessors; Python uses attribute-style access
signalwire.relay.call.RecordAction.url: port-only: Perl RecordAction exposes url/duration/size as explicit accessors; Python uses attribute-style access
signalwire.relay.client.Constants: port-only: SignalWire::Relay::Constants holds Blade/JSON-RPC constants; Python inlines them
signalwire.relay.client.RelayClient.authenticate: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.connect_ws: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.disconnect_ws: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.on_event: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.client.RelayClient.reconnect: port-only: Perl surfaces individual WebSocket lifecycle steps; Python packs these into connect()
signalwire.relay.event.AuthorizationStateEvent: port-only event subclass Perl emits explicitly; Python folds these into RelayEvent/CallState
signalwire.relay.event.CallDisconnectEvent: port-only event subclass Perl emits explicitly; Python folds these into RelayEvent/CallState
signalwire.relay.event.DisconnectEvent: port-only event subclass Perl emits explicitly; Python folds these into RelayEvent/CallState
signalwire.relay.event.RelayEvent.parse_event: port-only: Perl uses a class-method parser; Python uses the module-level parse_event() function
signalwire.relay.message.Message.dispatch_event: port-only dispatcher/passthrough helper for Perl-idiomatic event plumbing
signalwire.relay.message.Message.on_completed: port-only dispatcher/passthrough helper for Perl-idiomatic event plumbing
signalwire.rest.call_handler.PhoneCallHandler.values: port-only: authoritative list accessor for the enum; Python uses the enum class directly
signalwire.rest.namespaces.calling.CallingNamespace.update_call: port-only helper for updating an in-flight call; Python clients use client.calls(sid).update()
signalwire.rest.namespaces.fabric.AddressesResource: port-only: Perl Fabric::Addresses is a resource class that extends Base; Python uses FabricAddresses (under a different name) or folds addresses into Resource
signalwire.rest.namespaces.fabric.AddressesResource.get: port-only: Perl Fabric::Addresses is a resource class that extends Base; Python uses FabricAddresses (under a different name) or folds addresses into Resource
signalwire.rest.namespaces.fabric.AddressesResource.list: port-only: Perl Fabric::Addresses is a resource class that extends Base; Python uses FabricAddresses (under a different name) or folds addresses into Resource
signalwire.rest.namespaces.fabric.Resource: port-only: internal helper class for the Fabric resource indirection; Python does not expose a top-level Resource class
signalwire.rest.namespaces.fabric.Resource.list_addresses: port-only: internal helper class for the Fabric resource indirection; Python does not expose a top-level Resource class
signalwire.rest.namespaces.fabric.ResourcePUT: port-only: internal helper class for the Fabric resource indirection; Python does not expose a top-level Resource class
signalwire.skills.registry.CustomSkills: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.CustomSkills.get_parameter_schema: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.CustomSkills.register_tools: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.CustomSkills.setup: port-only: SignalWire::Skills::Builtin::CustomSkills is the Perl harness for loading user-supplied skill packages; Python has no equivalent class
signalwire.skills.registry.SkillRegistry.clear_registry: port-only registry helper: Perl exposes these for test isolation and dynamic loading
signalwire.skills.registry.SkillRegistry.get_factory: port-only registry helper: Perl exposes these for test isolation and dynamic loading
signalwire.utils.schema_utils.SchemaUtils.get_verb: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.get_verb_names: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.has_verb: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.instance: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
signalwire.utils.schema_utils.SchemaUtils.verb_count: port-only: Perl SchemaUtils exposes verb-introspection helpers (get_verb, get_verb_names, has_verb, verb_count, instance); Python keeps these internal
