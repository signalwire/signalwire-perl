# PORT_OMISSIONS.md

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
signalwire.core.mixins.tool_mixin.ToolMixin.tool: impossible: Python @tool decorator-protocol API; Perl/Moo has no method-decorator feature — tools register via define_tool directly (TS+PHP omit identically)
signalwire.core.security.webhook_middleware.make_webhook_validation_dependency: impossible: framework-bound factory returning a FastAPI dependency; Perl ships the equivalent as the SignalWire::Security::WebhookMiddleware Plack middleware (a PORT_ADDITION) — the FastAPI-dependency FORM has no Plack analog (TS/PHP ship native middleware likewise)
signalwire.livewire.Agent: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.llm_node: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.on_enter: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.on_exit: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.on_user_turn_completed: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.session: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.stt_node: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.tts_node: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.update_instructions: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Agent.update_tools: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentHandoff: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentHandoff.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentServer: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentServer.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentServer.rtc_session: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.generate_reply: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.history: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.interrupt: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.say: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.start: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.update_agent: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.AgentSession.userdata: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.ChatContext: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.ChatContext.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.ChatContext.append: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.function_tool: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.InferenceLLM: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.InferenceLLM.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.InferenceSTT: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.InferenceSTT.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.InferenceTTS: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.InferenceTTS.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.JobContext: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.JobContext.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.JobContext.connect: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.JobContext.wait_for_participant: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.JobProcess: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.JobProcess.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.CartesiaTTS: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.CartesiaTTS.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.DeepgramSTT: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.DeepgramSTT.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.ElevenLabsTTS: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.ElevenLabsTTS.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.OpenAILLM: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.OpenAILLM.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.SileroVAD: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.SileroVAD.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.plugins.SileroVAD.load: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.Room: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.run_app: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.RunContext: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.RunContext.__init__: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.RunContext.userdata: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.StopResponse: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
signalwire.livewire.ToolError: approved: livewire is LiveKit-agents-compat; LiveKit ships no Perl agents SDK (only Python + Node/TS), so it is not ported to Perl (§I.1/L21)
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
