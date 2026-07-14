#!/usr/bin/env python3
"""enumerate_signatures.py — emit port_signatures.json for the Perl SDK.

Phase 4-Perl of the cross-language signature audit. Pipeline:

    1. ``perl scripts/signature_dump.pl`` parses every .pm under lib/ via
       regex (best-effort), extracts package/sub/has declarations, and
       writes raw JSON to stdout.
    2. This wrapper applies the Perl→Python package mapping derived from
       scripts/enumerate_surface.pl (PACKAGE_TO_PY) and emits
       port_signatures.json conforming to surface_schema_v2.json.

Caveats (documented in PORT_SIGNATURE_OMISSIONS.md):
    - Perl is dynamically typed without ``use feature 'signatures'``;
      every parameter type is ``any``.
    - The regex parser handles the SDK's idiomatic ``my (...) = @_;``
      and ``my $x = shift;`` patterns. Conditional unpack, slurpy
      ``@rest``, and signatures-feature opt-in surface as drift in the
      diff.
    - A future port-side refactor to Type::Tiny ``signature_for`` would
      give us runtime-introspectable signatures with types; tracked as a
      separate program.

Usage:
    python3 scripts/enumerate_signatures.py
    python3 scripts/enumerate_signatures.py --raw raw.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORT_ROOT = HERE.parent

# Python reference oracle. Used to project Perl's idiomatic ``%opts``
# slurpy hash and similar single-hashref patterns into the canonical
# Python keyword-argument shape so the cross-language diff doesn't fail
# on what is functionally the same kwargs contract.
PSDK_CANDIDATES = [
    p for p in (
        # explicit override wins
        (Path(os.environ["PORTING_SDK"]) / "python_signatures.json")
        if os.environ.get("PORTING_SDK") else None,
        # default adjacency layout: porting-sdk beside the port repo
        PORT_ROOT.parent / "porting-sdk" / "python_signatures.json",
    ) if p is not None
]


def _load_python_reference() -> dict:
    for p in PSDK_CANDIDATES:
        if p.is_file():
            return json.loads(p.read_text(encoding="utf-8"))
    return {"modules": {}}


PYTHON_REFERENCE = _load_python_reference()


# ---------------------------------------------------------------------------
# Reference-type projection for hand-written params (typed-surface strictness).
#
# Perl is dynamically typed without ``use feature 'signatures'`` type info — the
# regex parser recovers a param's NAME and sigil/kind but NOT its TYPE, so the
# generic per-param path records ``type: any``. That is NOT "Perl can't express
# this type" — the concrete type the param accepts IS the contract it implements,
# recorded in the Python oracle (the same way the generated REST layer already
# unfolds its typed sidecar, and PHP re-attaches PHPDoc types). This pass
# re-attaches that concrete type onto a hand-written param ONLY when the method
# is present in the reference AND carries a param of the SAME NAME the reference
# types concretely. It is a rename/remap, NOT an omission: it never invents a
# param, never changes a kind, only rewrites a bare ``any`` — a real future param
# drift (drop/rename/retype) still surfaces.
def _build_ref_param_type_index() -> dict:
    idx: dict = {}
    for mod, me in PYTHON_REFERENCE.get("modules", {}).items():
        for cls, ce in me.get("classes", {}).items():
            for meth, sig in ce.get("methods", {}).items():
                pt = {
                    p["name"]: p["type"]
                    for p in sig.get("params", [])
                    if p.get("name")
                    and p.get("kind") not in ("self", "cls")
                    and p.get("type", "any") != "any"
                }
                if pt:
                    idx[(mod, cls, meth)] = pt
        for fn, sig in me.get("functions", {}).items():
            pt = {
                p["name"]: p["type"]
                for p in sig.get("params", [])
                if p.get("name")
                and p.get("kind") not in ("self", "cls")
                and p.get("type", "any") != "any"
            }
            if pt:
                idx[(mod, None, fn)] = pt
    return idx


REF_PARAM_TYPES = _build_ref_param_type_index()

# Hand-written param RENAMES (renames, NOT omissions — same param slot, same wire
# role; only the Perl-side identifier differs from the reference-recorded name).
# The Perl port idiomatically abbreviates (``desc``↔``description``,
# ``ms``↔``milliseconds``, ``cb``↔``handler``/``callback``, ``lang``↔
# ``language_code``, ``c``/``fr``/``sp``/``pp``/``up``/``iso`` ↔ the semantic
# name). Renaming keeps the two comparing EQUAL AND lets the reference-type
# projection attach the concrete type; a real future param drift still surfaces.
# Scoped to methods whose param COUNT matches the reference (a genuine 1:1
# rename) — Perl Moo *constructor* idioms (``__init__`` with a different
# attribute shape) are NOT renamed here; they stay in PORT_SIGNATURE_OMISSIONS.
# Keyed (py_module, py_class_or_None, method) -> {perl_param: reference_param}.
PERL_HAND_PARAM_RENAMES: dict[tuple, dict[str, str]] = {
    ("signalwire.core.agent_base", "AgentBase", "on_debug_event"): {"cb": "handler"},
    ("signalwire.core.contexts", "Context", "add_enter_filler"): {"lang": "language_code"},
    ("signalwire.core.contexts", "Context", "add_exit_filler"): {"lang": "language_code"},
    ("signalwire.core.contexts", "Context", "set_consolidate"): {"c": "consolidate"},
    ("signalwire.core.contexts", "Context", "set_enter_fillers"): {"fillers": "enter_fillers"},
    ("signalwire.core.contexts", "Context", "set_exit_fillers"): {"fillers": "exit_fillers"},
    ("signalwire.core.contexts", "Context", "set_full_reset"): {"fr": "full_reset"},
    ("signalwire.core.contexts", "Context", "set_isolated"): {"iso": "isolated"},
    ("signalwire.core.contexts", "Context", "set_post_prompt"): {"pp": "post_prompt"},
    ("signalwire.core.contexts", "Context", "set_system_prompt"): {"sp": "system_prompt"},
    ("signalwire.core.contexts", "Context", "set_user_prompt"): {"up": "user_prompt"},
    ("signalwire.core.contexts", "Step", "set_reset_consolidate"): {"c": "consolidate"},
    ("signalwire.core.contexts", "Step", "set_reset_full_reset"): {"fr": "full_reset"},
    ("signalwire.core.contexts", "Step", "set_reset_system_prompt"): {"sp": "system_prompt"},
    ("signalwire.core.contexts", "Step", "set_reset_user_prompt"): {"up": "user_prompt"},
    ("signalwire.core.data_map", "DataMap", "description"): {"desc": "description"},
    ("signalwire.core.data_map", "DataMap", "parameter"): {"type": "param_type"},
    ("signalwire.core.data_map", "DataMap", "purpose"): {"desc": "description"},
    ("signalwire.core.function_result", "FunctionResult", "set_end_of_speech_timeout"): {"ms": "milliseconds"},
    ("signalwire.core.function_result", "FunctionResult", "set_speech_event_timeout"): {"ms": "milliseconds"},
    ("signalwire.core.function_result", "FunctionResult", "toggle_functions"): {"toggles": "function_toggles"},
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "set_internal_fillers"): {"fillers": "internal_fillers"},
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "set_languages"): {"langs": "languages"},
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "set_native_functions"): {"funcs": "function_names"},
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "set_pronunciations"): {"prons": "pronunciations"},
    ("signalwire.core.mixins.web_mixin", "WebMixin", "manual_set_proxy_url"): {"url": "proxy_url"},
    ("signalwire.core.mixins.web_mixin", "WebMixin", "set_dynamic_config_callback"): {"cb": "callback"},
    ("signalwire.core.skill_manager", "SkillManager", "has_skill"): {"key": "skill_identifier"},
    ("signalwire.core.skill_manager", "SkillManager", "unload_skill"): {"key": "skill_identifier"},
    ("signalwire.relay.client", "RelayClient", "on_call"): {"cb": "handler"},
    ("signalwire.relay.client", "RelayClient", "on_message"): {"cb": "handler"},
    ("signalwire.relay.message", "Message", "on"): {"cb": "handler"},
}


# Return-type reconciliation for methods whose Perl return is an idiomatic
# value the regex parser can only record as bare ``any``, but which implements a
# NAMED cross-port capability the oracle types concretely. Keyed
# (py_module, py_class_or_None, method) -> canonical reference return type.
#
# ``as_router`` is the "embed my routes in a host app" mountable unit. Python's
# WebMixin.as_router / SWMLService.as_router return a ``HostAppRouter`` (a FastAPI
# APIRouter). Perl's routable unit is a PSGI application coderef
# (``sub { my $env = shift; ...; [$status,$headers,$body] }``, mountable in any
# Plack app via ``Plack::Builder`` ``mount``) — the SAME capability in Perl's
# idiom, returned by ``as_router`` (which returns ``$self->to_psgi_app``). The
# ``CodeRef`` maps to ``callable<...>`` in the perl type-alias table, but for
# this named cross-port unit we reconcile it to the SHARED ``HostAppRouter``
# class-ref (mirrors Ruby's ``Rack::Builder`` → HostAppRouter and Go's
# ``http.Handler`` → HostAppRouter mappings in porting-sdk/type_aliases.yaml), so
# as_router drifts 0 against the reference on a named type rather than the ``any``
# wildcard. Applied ONLY when the port currently records the return as ``any``
# (never overrides a concrete type the port already carries).
PERL_RETURN_TYPE_OVERRIDES: dict[tuple, str] = {
    ("signalwire.core.mixins.web_mixin", "WebMixin", "as_router"):
        "class:signalwire.core.web.HostAppRouter",
    ("signalwire.core.swml_service", "SWMLService", "as_router"):
        "class:signalwire.core.web.HostAppRouter",
    # webhook_middleware.validate — the decomposed, framework-free
    # validation core. It returns a PSGI-style reject triple
    # ``[status, headers, body]`` or ``undef`` to pass. The regex parser only
    # sees a bare ``any`` return; reconcile it to the oracle's cross-port
    # ``optional<(int, dict<string,string>, string)>`` decision-triple type.
    # (An arrayref IS a PSGI response, so this is the SAME shape dotnet ships
    # as WebhookValidationMiddleware.Validate and Rack/PSGI middleware are.)
    ("signalwire.core.security.webhook_middleware", None, "validate"):
        "optional<tuple<int,dict<string,string>,string>>",
}


def apply_return_type_overrides(out_modules: dict) -> None:
    """Reconcile a named-capability method's idiomatic ``any`` return to the
    canonical reference return type (see PERL_RETURN_TYPE_OVERRIDES). In place.
    Only rewrites a bare ``any`` return — never a concrete type already present."""
    def apply(key: tuple, sig: dict) -> None:
        rt = PERL_RETURN_TYPE_OVERRIDES.get(key)
        if rt is not None and sig.get("returns", "any") == "any":
            sig["returns"] = rt

    for mod, me in out_modules.items():
        for cls, ce in me.get("classes", {}).items():
            for meth, sig in ce.get("methods", {}).items():
                apply((mod, cls, meth), sig)
        for fn, sig in me.get("functions", {}).items():
            apply((mod, None, fn), sig)


def apply_hand_param_renames(out_modules: dict) -> None:
    """Rewrite Perl-idiom hand-written param identifiers to the reference name so
    the projection + diff compare EQUAL (see PERL_HAND_PARAM_RENAMES). In place."""
    def apply(key: tuple, sig: dict) -> None:
        rn = PERL_HAND_PARAM_RENAMES.get(key)
        if not rn:
            return
        for p in sig.get("params", []):
            new = rn.get(p.get("name"))
            if new is not None:
                p["name"] = new

    for mod, me in out_modules.items():
        for cls, ce in me.get("classes", {}).items():
            for meth, sig in ce.get("methods", {}).items():
                apply((mod, cls, meth), sig)
        for fn, sig in me.get("functions", {}).items():
            apply((mod, None, fn), sig)


def project_reference_param_types(out_modules: dict) -> None:
    """Re-attach reference-documented concrete param types onto hand-written
    params the parser recorded as bare ``any`` (see the block comment above).
    In place."""
    def apply(key: tuple, sig: dict) -> None:
        ref_types = REF_PARAM_TYPES.get(key)
        if not ref_types:
            return
        for p in sig.get("params", []):
            if p.get("kind") in ("self", "cls"):
                continue
            if p.get("type") != "any":
                continue  # never override a type the port already carries
            rt = ref_types.get(p.get("name"))
            if rt is not None:
                p["type"] = rt

    for mod, me in out_modules.items():
        for cls, ce in me.get("classes", {}).items():
            for meth, sig in ce.get("methods", {}).items():
                apply((mod, cls, meth), sig)
        for fn, sig in me.get("functions", {}).items():
            apply((mod, None, fn), sig)


# ---------------------------------------------------------------------------
# Generated REST resource-tree signature projection (item B).
#
# The REST resource + client-tree surface is GENERATED (scripts/generate_rest.py).
# Each generated package SignalWire::REST::Namespaces::Generated::<Name> projects
# onto the oracle signature module signalwire.rest.namespaces.<ns>_resources_generated
# (the 6 containers onto _client_tree_generated). Perl has no runtime-introspectable
# signature, so the generator emits a `rest_signatures.json` SIDECAR carrying the
# canonical typed-param records for every method it emits inline; we unfold those
# onto the regex-parsed subs (the sidecar IS the source of truth — mirrors php/go).
#
# The generated resource classes INHERIT their CRUD (list/create/get/update/delete)
# from the hand/generated bases; those methods are NOT emitted inline, so they carry
# no sidecar record and we do NOT project them here. The cross-port DRIFT gate
# resolves them structurally: the reference publishes a `crud_base` per resource
# class, and `crud_satisfied()` treats a port that has the class (but no crud_base)
# as satisfying the inherited CRUD methods (the binding lives in the reference; the
# resolved per-method form is idiom). So projecting each class's OWN methods + a
# constructor is sufficient for the method-set join this turn (typed create/update
# bodies + the crud_base binding are the follow-up typed-inputs pass).
GENERATED_SIG_PROJECTION = {
    "Addresses": ("relay_rest", "Base"),
    "AiAgents": ("fabric", "FabricResource"),
    "CallFlows": ("fabric", "FabricResource"),
    "Calling": ("calling", "Base"),
    "Chat": ("chat", "Base"),
    "ConferenceLogs": ("logs", "Base"),
    "ConferenceRooms": ("fabric", "FabricResource"),
    "CxmlApplications": ("fabric", "Base"),
    "CxmlScripts": ("fabric", "FabricResource"),
    "CxmlWebhooks": ("fabric", "FabricResource"),
    "DatasphereDocuments": ("datasphere", "CrudResource"),
    "DatasphereNamespace": ("_client_tree", "Base"),
    "FabricAddresses": ("fabric", "ReadResource"),
    "FabricNamespace": ("_client_tree", "Base"),
    "FabricTokens": ("fabric", "Base"),
    "FaxLogs": ("fax", "ReadResource"),
    "FreeswitchConnectors": ("fabric", "FabricResource"),
    "GenericResources": ("fabric", "Base"),
    "ImportedNumbers": ("relay_rest", "Base"),
    "LogsNamespace": ("_client_tree", "Base"),
    "Lookup": ("relay_rest", "Base"),
    "MessageLogs": ("message", "ReadResource"),
    "Mfa": ("relay_rest", "Base"),
    "NumberGroups": ("relay_rest", "CrudResource"),
    "PhoneNumbers": ("relay_rest", "CrudResource"),
    "ProjectNamespace": ("_client_tree", "Base"),
    "ProjectTokens": ("project", "Base"),
    "PubSub": ("pubsub", "Base"),
    "Queues": ("relay_rest", "CrudResource"),
    "Recordings": ("relay_rest", "Base"),
    "RegistryBrands": ("relay_rest", "Base"),
    "RegistryCampaigns": ("relay_rest", "Base"),
    "RegistryNamespace": ("_client_tree", "Base"),
    "RegistryNumbers": ("relay_rest", "Base"),
    "RegistryOrders": ("relay_rest", "Base"),
    "RelayApplications": ("fabric", "FabricResource"),
    "ShortCodes": ("relay_rest", "Base"),
    "SipEndpoints": ("fabric", "FabricResource"),
    "SipGateways": ("fabric", "FabricResource"),
    "SipProfile": ("relay_rest", "Base"),
    "Subscribers": ("fabric", "FabricResource"),
    "SwmlScripts": ("fabric", "FabricResource"),
    "SwmlWebhooks": ("fabric", "FabricResource"),
    "VerifiedCallers": ("relay_rest", "CrudResource"),
    "VideoConferenceTokens": ("video", "Base"),
    "VideoConferences": ("video", "CrudResource"),
    "VideoNamespace": ("_client_tree", "Base"),
    "VideoRoomRecordings": ("video", "Base"),
    "VideoRoomSessions": ("video", "ReadResource"),
    "VideoRoomTokens": ("video", "Base"),
    "VideoRooms": ("video", "CrudResource"),
    "VideoStreams": ("video", "Base"),
    "VoiceLogs": ("voice", "ReadResource"),
}

# The two generated bases + client-tree containers project onto these oracle
# signature classes under signalwire.rest._base (the Perl ReadResource == oracle
# ReadResource; the Perl FabricResource carries list_addresses == CrudWithAddresses).
GENERATED_BASE_MODULE = "signalwire.rest._base"


def _load_rest_sidecar() -> dict:
    p = PORT_ROOT / "lib" / "SignalWire" / "REST" / "Namespaces" / "Generated" / "rest_signatures.json"
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8")).get("methods", {})
    return {}


REST_SIDECAR = _load_rest_sidecar()


def python_signature(module: str, cls: str | None, method: str) -> dict | None:
    """Return the Python reference signature for the given canonical
    (module, class, method). Returns None if not found."""
    mod_entry = PYTHON_REFERENCE.get("modules", {}).get(module)
    if not mod_entry:
        return None
    if cls:
        cls_entry = mod_entry.get("classes", {}).get(cls)
        if not cls_entry:
            return None
        return cls_entry.get("methods", {}).get(method)
    return mod_entry.get("functions", {}).get(method)

# ---------------------------------------------------------------------------
# Perl→Python mapping. Parsed at import-time from enumerate_surface.pl so the
# table stays single-sourced.
# ---------------------------------------------------------------------------

def load_package_map() -> dict[str, dict[str, str | None]]:
    pl = (HERE / "enumerate_surface.pl").read_text(encoding="utf-8")
    # Match lines like:
    #   'SignalWire::Agent::AgentBase' => { module => 'signalwire.core.agent_base', class => 'AgentBase' },
    # Package name is `SignalWire` optionally followed by `::…` (the usual FQ
    # packages) OR a bare `SignalWire<Ident>` leaf like `SignalWireRestError`
    # (the canonical REST error is a bare-leaf package for Python-name parity).
    pattern = re.compile(
        r"'(SignalWire(?:::[^']+|[A-Za-z0-9_]*)?)'\s*=>\s*\{\s*module\s*=>\s*'([^']+)'\s*,\s*class\s*=>\s*(?:'([^']+)'|undef)"
    )
    out: dict = {}
    for m in pattern.finditer(pl):
        pkg, mod, cls = m.group(1), m.group(2), m.group(3)
        out[pkg] = {"module": mod, "class": cls}
    return out


PACKAGE_TO_PY = load_package_map()

# Methods we never emit (Moo internals + Perl-only helpers)
SKIP_METHODS = {
    "BUILDARGS", "BUILD", "DEMOLISH", "DOES",
    "import", "AUTOLOAD", "DESTROY", "can", "isa", "VERSION",
    "new",  # Moo provides ::new automatically
}


# Perl-side parent classes for which subclass overrides should be
# suppressed if they're not redefined in Python's subclass-side
# signature inventory. Pattern: Python's enumerate_python_signatures.py
# walks the AST and only records methods literally redefined on the
# subclass; Perl's regex parser sees ``sub setup { 1 }`` as a real
# subclass method even though it's just a thin Moo override of the
# inherited stub.
#
# Map: parent canonical (module, class) -> set of method names whose
# emissions on subclasses should be filtered out.
PARENT_OVERRIDE_FILTER: dict = {
    ("signalwire.core.skill_base", "SkillBase"): {
        "setup", "cleanup", "get_hints", "get_global_data",
        "get_parameter_schema", "get_prompt_sections", "get_skill_data",
        "get_instance_key", "register_tools",
        "define_tool", "update_skill_data",
        "validate_env_vars", "validate_packages",
    },
    # AgentBase overrides SWMLService.handle_request in Python source, but the
    # signature oracle's AST walker records handle_request ONLY on SWMLService
    # (AgentBase's redefinition is signature-identical, so it is not re-recorded
    # on the subclass). Perl's regex parser sees the literal `sub handle_request`
    # on the AgentBase package and would emit a subclass entry — filter it so the
    # method is covered by the inherited SWMLService signature, matching the
    # oracle. (SURFACE requires the symbol on AgentBase, and it is present there;
    # this filter is signatures-only.)
    ("signalwire.core.swml_service", "SWMLService"): {
        "handle_request",
    },
}

# Map of Perl-package -> the canonical (Python-module, Python-class)
# parent it ultimately extends. Used together with
# PARENT_OVERRIDE_FILTER above.
PERL_SUBCLASS_PARENT = {
    # Every Perl skill in lib/SignalWire/Skills/Builtin/ extends
    # SignalWire::Skills::SkillBase.
    "skill_base_subclass": ("signalwire.core.skill_base", "SkillBase"),
}

# Perl packages whose subs project as Python module-level FREE FUNCTIONS
# (rather than as methods on a class).  Packages map with class=undef in
# PACKAGE_TO_PY but only those listed here have their subs emitted as
# free functions; others (e.g. SignalWire::Logging, which is a Moo class
# whose instance methods would otherwise leak) get suppressed.
FREE_FN_PACKAGES = {
    "SignalWire",  # top-level RestClient/register_skill/add_skill_directory/list_skills_with_params
    "SignalWire::Core::Agent::Tools::TypeInference",  # infer_schema + create_typed_handler_wrapper (module-level fns)
    "SignalWire::Core::LoggingConfig",
    "SignalWire::Contexts",  # create_simple_context() helper
    "SignalWire::Utils",
    "SignalWire::Utils::UrlValidator",
    "SignalWire::Security::WebhookValidator",  # validate_webhook_signature, validate_request
    "SignalWire::Security::WebhookMiddleware",  # make_webhook_validation_dependency
    "SignalWire::Security::SecurityUtils",  # filter_sensitive_headers, redact_url, is_valid_hostname
}

# Free-function name overrides — for cases where the Python canonical
# name doesn't follow Perl/snake_case. Python's top-level
# ``signalwire.RestClient`` is a factory function but uses PascalCase
# (it mirrors the class name). The Perl source-side sub is also named
# ``RestClient`` — emit it as-is rather than lower-casing.
FREE_FN_NAME_OVERRIDES = {
    "RestClient": "RestClient",
}


# Method-name renames: Perl idiomatic names projected back to the Python
# canonical ones. The canonical Perl method (``to_hash``) and its
# Python sibling (``to_dict``) describe the same operation; emit the
# Perl method UNDER both names so the cross-language diff finds it
# under either path. Pattern: native_perl_name -> [canonical_python_name, ...].
PERL_METHOD_ALIASES = {
    # Perl uses ``hash`` for the dict-like data structure; Python uses
    # ``dict``. The serialization helper is named accordingly.
    "to_hash": ["to_dict"],
    # Perl reserves the bareword ``delete`` for the built-in hash
    # operator; CrudResource and HttpClient use ``delete_resource`` /
    # ``delete_request`` to avoid shadowing it. Both describe the same
    # HTTP DELETE / resource-removal operation as Python's ``delete``.
    "delete_resource": ["delete"],
    "delete_request": ["delete"],
}

# Per-(package, native-sub) method RENAMES: the Perl idiomatic sub name is
# projected to the canonical Python name and the native name is NOT also
# emitted (unlike PERL_METHOD_ALIASES which keeps both). Mirrors the surface
# enumerator's %METHOD_OVERRIDES for the reserved-word / dunder cases:
#   * Relay::Call `pass` -> reference's reserved-word-escaped `pass_`
#     (Python renamed the `pass` keyword collision to `pass_`).
#   * SWAIG::SWAIGFunction `call` -> the callable-protocol dunder `__call__`
#     (the non-__init__ dunder filter then drops it, matching the signature
#     oracle which does not record __call__ — same as the surface handling
#     where __call__ is a python_surface-only symbol).
PERL_METHOD_RENAMES = {
    ("SignalWire::Relay::Call", "pass"): "pass_",
    ("SignalWire::SWAIG::SWAIGFunction", "call"): "__call__",
}


# Moo attribute renames: Perl's leading-underscore private attrs that
# map to Python's public attribute name. Same pattern as
# PERL_METHOD_ALIASES — emit the synthesized getter under both names.
PERL_ATTR_ALIASES = {
    # Perl SDK uses ``_logger`` / ``_log`` private slots whose getter
    # is functionally Python's public ``logger`` attribute.
    "_logger": ["logger"],
    "_log": ["logger"],
}


# AgentBase methods that Python keeps on mixin classes. The Perl port has
# them all flattened on AgentBase via Moo composition; we project them onto
# the canonical Python mixin paths so the diff doesn't show them as
# missing-reference (port-only) under signalwire.core.agent_base.AgentBase.
MIXIN_PROJECTIONS = {
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin"): [
        "add_function_include", "add_hint", "add_hints", "add_internal_filler",
        "add_language", "add_pattern_hint", "add_pronunciation",
        "add_mcp_server", "enable_mcp_server",
        "enable_debug_events",
        "get_language_params",
        "set_function_includes", "set_global_data", "set_internal_fillers",
        "set_language_params",
        "set_languages", "set_multilingual", "set_native_functions",
        "set_param", "set_params",
        "set_post_prompt_llm_params", "set_prompt_llm_params",
        "set_pronunciations", "update_global_data",
    ],
    ("signalwire.core.mixins.prompt_mixin", "PromptMixin"): [
        "contexts",
        "define_contexts", "get_post_prompt", "get_prompt",
        "prompt_add_section",
        "prompt_add_subsection", "prompt_add_to_section",
        "prompt_has_section", "reset_contexts", "set_post_prompt",
        "set_prompt_pom",
        "set_prompt_text",
    ],
    # ServerlessMixin: serverless request dispatch is folded onto AgentBase in
    # Perl (Moo composition); the reference houses it on ServerlessMixin.
    ("signalwire.core.mixins.serverless_mixin", "ServerlessMixin"): [
        "handle_serverless_request",
    ],
    # Python additionally extracted a ``PromptManager`` class that
    # PromptMixin delegates to. The user-facing surface is identical
    # (``agent.prompt_manager.X`` ≡ ``agent.X``). Project the same set of
    # AgentBase methods to PromptManager so the cross-language audit
    # treats both paths as covered.
    ("signalwire.core.agent.prompt.manager", "PromptManager"): [
        "define_contexts", "get_contexts", "get_post_prompt", "get_prompt",
        "get_raw_prompt",
        "prompt_add_section", "prompt_add_subsection", "prompt_add_to_section",
        "prompt_has_section", "set_post_prompt", "set_prompt_pom",
        "set_prompt_text",
    ],
    ("signalwire.core.mixins.skill_mixin", "SkillMixin"): [
        "add_skill", "has_skill", "list_skills", "remove_skill",
    ],
    ("signalwire.core.mixins.tool_mixin", "ToolMixin"): [
        "define_tool", "define_tools", "on_function_call",
        "register_swaig_function",
    ],
    ("signalwire.core.agent.tools.registry", "ToolRegistry"): [
        "define_tool", "register_swaig_function",
        "has_function", "get_function", "get_all_functions",
        "remove_function",
    ],
    ("signalwire.core.mixins.auth_mixin", "AuthMixin"): [
        "validate_basic_auth", "get_basic_auth_credentials",
    ],
    ("signalwire.core.mixins.web_mixin", "WebMixin"): [
        "as_router", "enable_debug_routes", "get_app",
        "manual_set_proxy_url", "register_routing_callback", "run", "serve",
        "set_dynamic_config_callback", "setup_graceful_shutdown",
        "on_request", "on_swml_request",
    ],
    ("signalwire.core.mixins.mcp_server_mixin", "MCPServerMixin"): [
        "add_mcp_server",
    ],
    ("signalwire.core.mixins.state_mixin", "StateMixin"): [
        "validate_tool_token",
    ],
}


# Methods where the Perl source uses an idiomatic single-scalar argument
# (typically ``$opts`` / ``$args`` / ``$lang`` / ``$pron`` / ``$cb``) that
# stands in for Python's named keyword arguments. The signature_dump.pl
# parser sees this as a single positional scalar; the diff sees it as a
# real arity mismatch. In Perl style, the single scalar holds ALL the
# keyword args, so functionally the contract is identical to Python's
# kwargs. Names listed here are projected to mirror the Python reference.
#
# This is a NAMED whitelist (not a heuristic) so we never silently swap
# a real positional argument for kwargs projection.
PERL_HASHREF_KWARG_METHODS = {
    # AIConfigMixin: hashref-style kwargs. The Perl source has these on
    # AgentBase (which Moo flattens); they get re-projected onto the
    # AIConfigMixin canonical path during mixin projection.
    ("signalwire.core.agent_base", "AgentBase", "add_pattern_hint"),
    ("signalwire.core.agent_base", "AgentBase", "add_pronunciation"),
    ("signalwire.core.agent_base", "AgentBase", "add_language"),
    ("signalwire.core.agent_base", "AgentBase", "add_internal_filler"),
    ("signalwire.core.agent_base", "AgentBase", "add_function_include"),
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "add_pattern_hint"),
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "add_pronunciation"),
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "add_language"),
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "add_internal_filler"),
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin", "add_function_include"),
    # PhoneNumbersResource: extra kwargs hashref
    ("signalwire.rest.namespaces.phone_numbers", "PhoneNumbersResource", "set_ai_agent"),
    ("signalwire.rest.namespaces.phone_numbers", "PhoneNumbersResource", "set_call_flow"),
    ("signalwire.rest.namespaces.phone_numbers", "PhoneNumbersResource", "set_cxml_application"),
    ("signalwire.rest.namespaces.phone_numbers", "PhoneNumbersResource", "set_cxml_webhook"),
    ("signalwire.rest.namespaces.phone_numbers", "PhoneNumbersResource", "set_relay_application"),
    ("signalwire.rest.namespaces.phone_numbers", "PhoneNumbersResource", "set_relay_topic"),
    ("signalwire.rest.namespaces.phone_numbers", "PhoneNumbersResource", "set_swml_webhook"),
    # webhook_middleware.validate — free FUNCTION (class None). The Perl
    # source is ``sub validate { my ($method,$url,$headers,$body,%opts)=@_; }``
    # where the trailing ``%opts`` slurpy carries the reference's keyword-only
    # ``signing_key``. Whitelisting it here projects that keyword param from
    # the oracle (mirroring the class-method kwargs idiom) so the decomposed
    # validate core drifts 0 on the cross-port contract.
    ("signalwire.core.security.webhook_middleware", None, "validate"),
}


def _project_kwargs_from_python(
    py_sig: dict, leading_positionals: list[dict]
) -> list[dict] | None:
    """Build a parameter list that combines the Perl-source's leading
    positional params (everything before the slurpy/kwarg sink) with the
    Python reference's named keyword params (the kwargs the slurpy
    represents in Perl).

    Returns None if the python signature isn't usable (no params or only
    self).
    """
    if not py_sig:
        return None
    py_params = py_sig.get("params", [])
    if len(py_params) <= 1:
        return None
    # Skip the python self/cls receiver so we can match against
    # leading_positionals (which already includes self).
    py_after_self = [p for p in py_params if p.get("kind") not in ("self", "cls")]
    n_perl_pos = len([p for p in leading_positionals if p.get("kind") not in ("self", "cls")])
    # The leading positional args from the Perl source map 1:1 to the
    # first N python params. Any python params beyond that are what the
    # Perl ``%opts`` slurpy / hashref carries.
    if n_perl_pos > len(py_after_self):
        # Perl has more leading positionals than python total — projection
        # would lose information; bail out.
        return None
    # Use the names from python, but keep "self" from leading_positionals.
    out = list(leading_positionals)
    for p in py_after_self[n_perl_pos:]:
        # Project the python param verbatim except force ``type=any``
        # (Perl is dynamically typed; we don't claim the python type).
        proj = {
            "name": p.get("name", ""),
            "type": "any",
            "required": p.get("required", True),
        }
        kind = p.get("kind")
        if kind == "var_keyword":
            proj["kind"] = "var_keyword"
            proj["type"] = "dict<string,any>"
            proj["required"] = False  # a splat/kwargs tail is never required
        elif kind == "var_positional":
            proj["kind"] = "var_positional"
            proj["type"] = "list<any>"
            proj["required"] = False
        elif kind == "keyword":
            proj["kind"] = "keyword"
        out.append(proj)
    return out


def _generated_module(ns: str) -> str:
    if ns == "_client_tree":
        return "signalwire.rest.namespaces._client_tree_generated"
    return f"signalwire.rest.namespaces.{ns}_resources_generated"


SWML_VERBS_MODULE = "signalwire.core.swml_verbs_generated"


def project_swml_verbs(cls: str, type_entry: dict, out_modules: dict) -> None:
    """Project a generated SWML-verb config class (SignalWire::SWML::Generated::<Name>)
    onto the oracle signature module signalwire.core.swml_verbs_generated (item D2).
    Each `has` accessor is a zero-arg getter member (self -> any); the diff-tool
    gen-payload fold keys these as gen-payload.<Class>.<field>, matching the
    reference's generated swml_verbs_generated field set. Method-less config classes
    (no properties) still record the bare class (empty member set)."""
    methods: dict = {}
    for a in type_entry.get("attributes", []):
        attr = (a.get("name") or "").lstrip("+")
        if not attr or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", attr):
            continue
        methods.setdefault(attr, {"params": [{"name": "self", "kind": "self"}], "returns": "any"})
    out_modules.setdefault(SWML_VERBS_MODULE, {"classes": {}})
    out_modules[SWML_VERBS_MODULE]["classes"].setdefault(cls, {"methods": {}})
    out_modules[SWML_VERBS_MODULE]["classes"][cls]["methods"].update(methods)


_SWAIG_SUB_MODULE = {
    "PostPrompt": "signalwire.core.post_prompt_generated",
    "SwaigRequest": "signalwire.core.swaig_request_generated",
    "SwaigActions": "signalwire.core.swaig_actions_generated",
}


def project_swaig(sub: str, cls: str, type_entry: dict, out_modules: dict) -> None:
    """Project a generated SWAIG payload class (SignalWire::SWAIG::Generated::<Sub>::<Name>)
    onto its oracle signature module by <Sub> (item D1). Each `has` accessor is a
    zero-arg getter member (self -> any); the gen-payload fold keys class-typed
    fields as gen-payload.<Class>.<field> (matching the reference's recorded fields),
    while a scalar field is excused by the diff-tool as a port-side state accessor."""
    mod = _SWAIG_SUB_MODULE.get(sub)
    if not mod:
        return
    methods: dict = {}
    for a in type_entry.get("attributes", []):
        attr = (a.get("name") or "").lstrip("+")
        if not attr or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", attr):
            continue
        methods.setdefault(attr, {"params": [{"name": "self", "kind": "self"}], "returns": "any"})
    out_modules.setdefault(mod, {"classes": {}})
    out_modules[mod]["classes"].setdefault(cls, {"methods": {}})
    out_modules[mod]["classes"][cls]["methods"].update(methods)


def _sig_from_parsed_method(m: dict) -> dict:
    """Best-effort signature for a generated method the sidecar doesn't cover
    (should be rare — only methods emitted without a body record). Mirrors the
    generic per-param handling in collect(): first positional is the receiver."""
    params_out: list[dict] = []
    for i, p in enumerate(m.get("parameters", [])):
        pname = (p.get("name") or "").lstrip("+")
        sigil = p.get("sigil", "")
        if i == 0 and pname in ("self", "class", "s") and not sigil:
            params_out.append({"name": "self", "kind": "cls" if pname == "class" else "self"})
            continue
        if not pname or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", pname):
            continue
        param: dict = {"name": pname, "type": "any", "required": True}
        if sigil == "@":
            param["kind"] = "var_positional"; param["type"] = "list<any>"
            # A slurpy tail (@args / %opts) is a splat door — you can always call
            # without passing anything into it, so it is NEVER required. Marking it
            # required makes the checker treat it as a mandatory extra param and drift
            # vs the reference (whose **kwargs/**params tail is dropped entirely).
            param["required"] = False
        elif sigil == "%":
            param["kind"] = "var_keyword"; param["type"] = "dict<string,any>"
            param["required"] = False  # var_keyword tail is optional (see above)
        params_out.append(param)
    if not params_out or params_out[0].get("kind") not in ("self", "cls"):
        params_out.insert(0, {"name": "self", "kind": "self"})
    return {"params": params_out, "returns": "any"}


def project_generated(gname: str, type_entry: dict, out_modules: dict) -> None:
    """Project a generated resource/container/base class onto its oracle signature
    module, unfolding the generator's typed-param SIDECAR onto each own method."""
    # The two generated bases map onto signalwire.rest._base.
    if gname in ("ReadResource", "FabricResource"):
        cls = "ReadResource" if gname == "ReadResource" else "FabricResource"
        methods: dict = {}
        for meth in type_entry.get("methods", []):
            name = meth.get("name", "")
            if name in SKIP_METHODS or name.startswith("_"):
                continue
            # Perl Generated::FabricResource carries list_addresses -> the oracle
            # houses it on CrudWithAddresses; keep the same base-module class map as
            # the surface enumerator.
            sidecar = REST_SIDECAR.get(f"{gname}::{name}")
            sig = ({"params": [{"name": "self", "kind": "self"}] + [dict(r) for r in sidecar],
                    "returns": "any"} if sidecar else _sig_from_parsed_method(meth))
            methods[name] = sig
        target_cls = "CrudWithAddresses" if gname == "FabricResource" else "ReadResource"
        if methods:
            out_modules.setdefault(GENERATED_BASE_MODULE, {"classes": {}})
            out_modules[GENERATED_BASE_MODULE]["classes"].setdefault(target_cls, {"methods": {}})
            out_modules[GENERATED_BASE_MODULE]["classes"][target_cls]["methods"].update(methods)
        return

    if gname == "ResourceTree":
        return
    proj = GENERATED_SIG_PROJECTION.get(gname)
    if not proj:
        return
    ns, _base = proj
    mod = _generated_module(ns)

    methods = {
        "__init__": {"params": [{"name": "self", "kind": "self"},
                                {"name": "http", "type": "any", "required": True}],
                     "returns": "void"},
    }
    for meth in type_entry.get("methods", []):
        name = meth.get("name", "")
        if name in SKIP_METHODS or (name.startswith("_") and not name.startswith("__")):
            continue
        # delete_resource -> delete (the CrudResource-base hand name), though the
        # generated Base classes already emit `delete` directly.
        canon = "delete" if name == "delete_resource" else name
        sidecar = REST_SIDECAR.get(f"{gname}::{name}")
        if sidecar is not None:
            methods[canon] = {
                "params": [{"name": "self", "kind": "self"}] + [dict(r) for r in sidecar],
                "returns": "any",
            }
        else:
            methods[canon] = _sig_from_parsed_method(meth)

    # paginate() lives on the generated ReadResource base and is inherited by each
    # ReadResource-based leaf resource. The reference oracle records it LITERALLY on
    # every such leaf class (Python's enumerator publishes the inherited method), and
    # it is NOT one of the crud_base-governed CRUD methods, so DRIFT demands it
    # per-class. Project it onto each ReadResource-based leaf so the method-set joins.
    if _base == "ReadResource":
        methods["paginate"] = {
            "params": [
                {"name": "self", "kind": "self"},
                {"name": "params", "type": "dict<string,any>", "required": False, "kind": "var_keyword"},
            ],
            "returns": "any",
        }

    # Container classes expose their sub-resource accessors as Moo `has ... lazy`
    # attributes (init_arg => undef). The oracle records these as zero-arg getter
    # methods (self -> class:<Resource>); emit them so the client-tree join matches.
    for a in type_entry.get("attributes", []):
        attr = (a.get("name") or "").lstrip("+")
        if not attr or attr.startswith("_") or attr in methods:
            continue
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", attr):
            continue
        methods[attr] = {"params": [{"name": "self", "kind": "self"}], "returns": "any"}

    out_modules.setdefault(mod, {"classes": {}})
    out_modules[mod]["classes"].setdefault(gname, {"methods": {}})
    out_modules[mod]["classes"][gname]["methods"].update(methods)


def collect(raw: dict) -> dict:
    out_modules: dict = {}

    # Build a Perl-package -> entry index so we can walk `extends` chains
    # for attribute inheritance. Moo's auto-`new` accepts every parent's
    # attribute as a named constructor arg, so the canonical __init__
    # signature must include inherited attrs.
    #
    # Multi-package files (e.g. lib/SignalWire/Relay/Event.pm declares
    # ``package SignalWire::Relay::Event;`` once at top with all the
    # ``has`` attributes, then re-opens the same package later for the
    # ``parse_event`` factory). The signature_dump.pl emits these as
    # separate type entries; merge them so attrs+methods+extends from
    # every reopening are unioned under a single full_name.
    by_full_name: dict = {}
    for t in raw.get("types", []):
        full = t.get("full_name")
        if not full:
            continue
        if full not in by_full_name:
            by_full_name[full] = {
                "full_name": full,
                "attributes": [],
                "methods": [],
                "extends": [],
            }
        agg = by_full_name[full]
        # Dedupe attributes by name (later reopenings shouldn't clobber).
        seen_attrs = {a.get("name") for a in agg["attributes"]}
        for a in t.get("attributes", []) or []:
            if a.get("name") not in seen_attrs:
                agg["attributes"].append(a)
                seen_attrs.add(a.get("name"))
        seen_methods = {m.get("name") for m in agg["methods"]}
        for m in t.get("methods", []) or []:
            if m.get("name") not in seen_methods:
                agg["methods"].append(m)
                seen_methods.add(m.get("name"))
        for e in t.get("extends", []) or []:
            if e not in agg["extends"]:
                agg["extends"].append(e)
    # Replace the raw types list with the merged versions so the rest of
    # collect() iterates over the unioned entries.
    raw = {"types": list(by_full_name.values())}

    def collect_inherited_attrs(entry: dict, seen: set) -> list:
        """Walk extends chain and concatenate attributes (parent first,
        then child). Stops on cycles via `seen`."""
        full = entry.get("full_name")
        if full in seen:
            return []
        seen.add(full)
        out: list = []
        for parent_name in entry.get("extends", []) or []:
            parent = by_full_name.get(parent_name)
            if parent:
                out.extend(collect_inherited_attrs(parent, seen))
        out.extend(entry.get("attributes", []))
        return out

    for type_entry in raw.get("types", []):
        full = type_entry.get("full_name", "")

        # --- Generated SWAIG read-side payloads (item D1) — path-routed ---
        # SignalWire::SWAIG::Generated::<Sub>::<Name> -> the <Sub>'s core.*_generated
        # module; `has` accessors become zero-arg members (gen-payload fold keys the
        # class-typed fields; scalar fields excused as port-side state accessors).
        m = re.match(r"^SignalWire::SWAIG::Generated::(\w+)::(\w+)$", full)
        if m:
            project_swaig(m.group(1), m.group(2), type_entry, out_modules)
            continue

        # --- Generated SWML-verb CONFIG types (item D2) — path-routed ---
        # SignalWire::SWML::Generated::<Name> -> signalwire.core.swml_verbs_generated
        # (its `has` accessors become zero-arg members; the gen-payload fold keys
        # them gen-payload.<Class>.<field>). Path routing wins so a config type name
        # that collides with an SDK builder or recurs as a REST wire type lands here.
        m = re.match(r"^SignalWire::SWML::Generated::(\w+)$", full)
        if m:
            project_swml_verbs(m.group(1), type_entry, out_modules)
            continue

        # --- Generated REST resource-tree projection (item B) ---
        m = re.match(r"^SignalWire::REST::Namespaces::Generated::(\w+)$", full)
        if m:
            project_generated(m.group(1), type_entry, out_modules)
            continue

        target = PACKAGE_TO_PY.get(full)
        if not target:
            # Port-only / not in mapping; skip (surface audit handles via PORT_ADDITIONS)
            continue

        mod = target["module"]
        canonical_class = target["class"]

        methods_out: dict = {}
        functions_out: dict = {}

        # Compute the chain of Perl ancestors so we can apply the
        # PARENT_OVERRIDE_FILTER below. Walks ``extends`` recursively
        # via by_full_name.
        ancestor_perl_classes: set = set()
        def _walk_ancestors(entry: dict, seen: set):
            full = entry.get("full_name")
            if full in seen:
                return
            seen.add(full)
            for parent_name in entry.get("extends", []) or []:
                ancestor_perl_classes.add(parent_name)
                p = by_full_name.get(parent_name)
                if p:
                    _walk_ancestors(p, seen)
        _walk_ancestors(type_entry, set())
        # Translate ancestor Perl classes into canonical (module, class)
        # tuples so we can index into PARENT_OVERRIDE_FILTER.
        ancestor_canonical: set = set()
        for anc in ancestor_perl_classes:
            atarget = PACKAGE_TO_PY.get(anc)
            if atarget and atarget["class"]:
                ancestor_canonical.add((atarget["module"], atarget["class"]))
        # Filter set: any method names this Perl class would emit that
        # are inherited boilerplate from one of its parents and that
        # Python's signature inventory does not redefine on the subclass.
        skipped_due_to_parent: set = set()
        for parent_key, method_names in PARENT_OVERRIDE_FILTER.items():
            if parent_key in ancestor_canonical:
                # Only filter when Python's reference DOESN'T list the
                # method on this subclass — that's the indicator that
                # Python keeps the implementation on the base class.
                py_subclass_methods = (
                    PYTHON_REFERENCE
                    .get("modules", {})
                    .get(mod, {})
                    .get("classes", {})
                    .get(canonical_class or "", {})
                    .get("methods", {})
                )
                for name in method_names:
                    if name not in py_subclass_methods:
                        skipped_due_to_parent.add(name)

        for m in type_entry.get("methods", []):
            native = m.get("name", "")
            # Per-package method rename (reserved-word / dunder). Apply before
            # the SKIP / dunder filters so a rename onto a non-__init__ dunder
            # (e.g. call -> __call__) is dropped by the dunder filter below,
            # and a rename onto a normal name (pass -> pass_) is recorded.
            renamed = PERL_METHOD_RENAMES.get((full, native))
            if renamed is not None:
                native = renamed
            if native in SKIP_METHODS:
                continue
            if native in skipped_due_to_parent:
                continue
            if native.startswith("_") and not native.startswith("__"):
                continue
            # Python's enumerate_python_signatures.py records only ``__init__``
            # among dunder methods (the others are runtime protocol hooks
            # like ``__iter__``/``__next__``/``__repr__`` that the Python
            # AST walker skips). Match that policy so the Perl iterator
            # doesn't surface false-positive port-only dunders.
            if native.startswith("__") and native.endswith("__") and native != "__init__":
                continue
            # Free-function name override — preserve PascalCase for the
            # canonical Python ``signalwire.RestClient`` factory.
            method_canonical = FREE_FN_NAME_OVERRIDES.get(native, native)
            params = m.get("parameters", [])
            # Zero-param Perl method: ``sub foo { return []; }`` style
            # stubs don't declare ``my ($self) = @_;`` because they
            # don't reference self. Functionally they're still instance
            # methods (the Moo dispatcher provides $self even though
            # the body ignores it). Infer the self receiver so the
            # canonical signature has the right arity.
            if not params and canonical_class is not None:
                params_out = [{"name": "self", "kind": "self"}]
                saw_receiver = True
                methods_out[method_canonical] = {
                    "params": params_out,
                    "returns": "void" if native == "BUILD" else "any",
                }
                continue
            # Strip $self / $class as the canonical receiver
            params_out = []
            saw_receiver = False
            for i, p in enumerate(params):
                pname = p.get("name", "").lstrip("+")
                sigil = p.get("sigil", "")
                # First positional param is the invocant. Perl SDK uses
                # `$self`, `$class`, or short `$s` aliases for the same
                # role; normalize all of them to the canonical "self".
                # ``$class_or_self`` is the SDK convention for methods
                # that can be invoked either as a classmethod
                # (FunctionResult->create_payment_action(...)) or as
                # an instance method ($fr->create_payment_action(...))
                # — these mirror Python's ``@staticmethod``-decorated
                # helpers, so we strip the receiver entirely.
                if i == 0 and pname == "class_or_self" and not sigil:
                    # Python's equivalent is a @staticmethod with no
                    # receiver — mirror that by dropping the param.
                    saw_receiver = True
                    continue
                if i == 0 and pname in ("self", "class", "s") and not sigil:
                    params_out.append({
                        "name": "self",
                        "kind": "cls" if pname == "class" else "self",
                    })
                    saw_receiver = True
                    continue
                if not pname:
                    continue
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", pname):
                    continue
                # Sigil-driven kind: ``@x`` -> var_positional (Perl array
                # slurp ≡ Python ``*args``); ``%x`` -> var_keyword (Perl
                # hash slurp ≡ Python ``**kwargs``); ``$x`` -> positional.
                param: dict = {
                    "name": pname,
                    "type": "any",
                    "required": True,
                }
                if sigil == "@":
                    param["kind"] = "var_positional"
                    param["type"] = "list<any>"
                    param["required"] = False  # slurpy tail is never required
                elif sigil == "%":
                    param["kind"] = "var_keyword"
                    param["type"] = "dict<string,any>"
                    param["required"] = False  # var_keyword tail is never required
                params_out.append(param)

            # Perl-idiom projection: the canonical Perl ``%opts`` slurpy
            # hash IS the kwargs sink — semantically identical to Python's
            # named keyword args. When the source-side dump shows the
            # last param is ``%opts`` (var_keyword), expand it into the
            # Python reference's named keyword parameters so the
            # cross-language diff sees a 1:1 contract instead of an arity
            # mismatch. Same logic for the ``%foo`` hash hash specialty
            # like ``add_language(%lang)``: the slurpy carries every
            # python-named kwarg.
            # Free FUNCTIONS (class None) get the same slurpy→keyword
            # projection, but ONLY when whitelisted in
            # PERL_HASHREF_KWARG_METHODS keyed ``(mod, None, method)`` — a
            # free function's ``%opts`` sink is projected deliberately (e.g.
            # webhook_middleware.validate's keyword-only signing_key), never
            # heuristically, so an unrelated free-function ``%opts`` tail is
            # left as a plain var_keyword.
            fn_kwargs_whitelisted = (
                canonical_class is None
                and (mod, None, method_canonical) in PERL_HASHREF_KWARG_METHODS
            )
            if (
                params_out
                and params_out[-1].get("kind") == "var_keyword"
                and (canonical_class is not None or fn_kwargs_whitelisted)
            ):
                py_sig = python_signature(mod, canonical_class, method_canonical)
                leading = params_out[:-1]
                projected = _project_kwargs_from_python(py_sig, leading)
                if projected is not None:
                    params_out = projected

            # Single-scalar hashref kwargs idiom (e.g. ``add_language($lang)``,
            # ``set_ai_agent($id, $args)``): the source-side dump shows a
            # single trailing positional that semantically holds all the
            # Python keyword args. Whitelisted by canonical method name
            # so we never silently swap a real scalar argument.
            elif (
                canonical_class is not None
                and (mod, canonical_class, method_canonical) in PERL_HASHREF_KWARG_METHODS
            ):
                py_sig = python_signature(mod, canonical_class, method_canonical)
                # Drop the trailing scalar (it represents the kwargs sink),
                # keep everything before it.
                if params_out and params_out[-1].get("kind") not in ("self", "cls"):
                    leading = params_out[:-1]
                else:
                    leading = list(params_out)
                projected = _project_kwargs_from_python(py_sig, leading)
                if projected is not None:
                    params_out = projected

            sig = {
                "params": params_out,
                "returns": "void" if native == "BUILD" else "any",
            }
            if canonical_class is None:
                # Module-level function (no class).  Perl packages mapped
                # with class=undef expose their subs as module-level free
                # functions in the canonical inventory — but ONLY when the
                # package is explicitly listed in FREE_FN_PACKAGES below.
                # SignalWire::Logging maps to logging_config with class=undef
                # purely so its Logger instance methods don't pollute the
                # surface; we don't want those instance methods leaking up
                # as fake free functions.
                if full in FREE_FN_PACKAGES:
                    functions_out[method_canonical] = sig
                continue
            methods_out[method_canonical] = sig
            # Emit canonical-Python aliases (e.g. Perl's ``to_hash`` is
            # the same operation as Python's ``to_dict``). Without these
            # aliases the cross-language diff sees missing-port for
            # ``to_dict`` and missing-reference for ``to_hash``.
            for alias in PERL_METHOD_ALIASES.get(native, []):
                if alias not in methods_out:
                    methods_out[alias] = sig

        # Moo/Moose attributes → emit as zero-arg getter methods
        for a in type_entry.get("attributes", []):
            attr = a.get("name", "").lstrip("+")
            if not attr or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", attr):
                continue
            # Skip underscore-prefix Perl-private attrs (Perl convention:
            # ``_logger``, ``_http``, ``_sip_routing_enabled``) — they
            # mirror Python's leading-underscore privates which the
            # Python AST walker excludes from the canonical surface.
            # Hand-curated PERL_ATTR_ALIASES still gets to project a
            # public alias for the cases where the canonical Python
            # name differs (e.g. ``_logger`` -> ``logger``).
            getter_sig = {
                "params": [{"name": "self", "kind": "self"}],
                "returns": "any",
            }
            if attr.startswith("_"):
                # Emit only the alias (if any), not the underscore form.
                for alias in PERL_ATTR_ALIASES.get(attr, []):
                    if alias not in methods_out:
                        methods_out[alias] = getter_sig
                continue
            if attr not in methods_out:
                methods_out[attr] = getter_sig
            for alias in PERL_ATTR_ALIASES.get(attr, []):
                if alias not in methods_out:
                    methods_out[alias] = getter_sig

        # Synthesize __init__ for every Moo/Moose class. Perl/Moo provides
        # ``new`` automatically based on attributes; cross-language audit
        # treats this as the canonical ``__init__`` constructor. The params
        # are the class's named attributes (Moo's hash-arg constructor).
        # Perl convention prefixes private attributes with `_` (e.g.
        # ``_http``, ``_base_path``); Python's matching ``__init__`` takes
        # them as positional ``http``/``base_path``. We strip a single
        # leading underscore for the canonical name so the cross-language
        # diff treats them as equivalent.
        # Synthesize __init__ when the class is a Moo-style resource — it
        # either declares its own attributes or extends one of the SDK's
        # resource bases (Base / CrudResource) which provide _http +
        # _base_path. Python sometimes redefines __init__ on a subclass
        # for documentation even when the signature is identical to the
        # parent's; for parity we walk the extends chain and emit the
        # full attribute list.
        own_attrs = type_entry.get("attributes", []) or []
        # Heuristic for emitting __init__:
        # - Classes that declare their own attributes always get an
        #   __init__ (the attrs are constructor args).
        # - Classes that inherit from Base/CrudResource without adding
        #   any of their own attrs are pure leaf resources whose __init__
        #   is the inherited (http, base_path); Python doesn't redefine
        #   __init__ on such classes either.
        # - Classes that don't extend a known resource base (top-level
        #   namespace orchestrators like Calling/Compat/Logs) get a
        #   synthesized __init__ from whatever attrs the class body owns.
        # Synthesize __init__ only when Python's reference signature
        # inventory has an __init__ for this class. Skip the synthesis
        # in two cases:
        #
        #   1. Python class in inventory but no __init__ entry: Python
        #      inherits the parent's __init__; emitting a Perl-side
        #      __init__ would falsely surface as missing-reference.
        #
        #   2. Python class not in inventory at all (e.g. some skill
        #      subclasses where the Python AST walker excluded them):
        #      we have no canonical signature to project against, and
        #      emitting Moo-synthesized params introduces false drift.
        #      The class itself is documented in PORT_OMISSIONS / surface
        #      audit if relevant.
        #
        # Class qualifies for synthesis if it has own attrs OR inherited
        # attrs (pure leaf-resource classes that only ``extends Base``
        # take their __init__ shape from the inherited http/base_path
        # constructor; Python redefines __init__ on the leaf to document
        # the inherited shape). Also qualify when Python's reference
        # __init__ takes only ``self`` — Moo provides a no-arg constructor
        # implicitly even when the Perl class has no attrs of its own.
        inherited_attrs_for_synth = collect_inherited_attrs(type_entry, set())
        py_init_for_synthesis = python_signature(mod, canonical_class, "__init__")
        py_init_self_only = (
            py_init_for_synthesis is not None
            and len(py_init_for_synthesis.get("params", [])) == 1
        )
        synth_init = (
            "__init__" not in methods_out
            and canonical_class is not None
            and (own_attrs or inherited_attrs_for_synth or py_init_self_only)
            and py_init_for_synthesis is not None
        )
        if synth_init:
            init_params: list[dict] = [{"name": "self", "kind": "self"}]
            inherited = collect_inherited_attrs(type_entry, set())
            seen_names: set = set()
            for a in inherited:
                pname = a.get("name", "").lstrip("+")
                if not pname:
                    continue
                canonical = pname.lstrip("_")
                if not canonical or canonical.startswith("_"):
                    continue
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", canonical):
                    continue
                if canonical in seen_names:
                    continue
                seen_names.add(canonical)
                init_params.append({
                    "name": canonical,
                    "type": "any",
                    "required": not a.get("default") and a.get("required", False),
                })
            # Project the synthesized __init__ to Python's reference shape
            # when the Perl Moo class declares every Python positional arg
            # as a Moo attribute. Moo accepts every attribute as a named
            # arg regardless of kind, so we can adopt Python's per-param
            # ``kind`` (positional/keyword) verbatim. We also reorder the
            # Perl attrs to match the Python signature order so the diff
            # zips them up correctly. Any Perl-only attrs that Python
            # doesn't have are appended at the end (they're additive).
            #
            # Skip the projection when Python has positional attrs Perl
            # doesn't model — this would cause the position-zip diff
            # to mismatch downstream params on kind alone. Such cases
            # are real divergence and belong in PORT_SIGNATURE_OMISSIONS.
            py_init = python_signature(mod, canonical_class, "__init__")
            if py_init:
                py_params = py_init.get("params", [])
                # Map perl attr name -> the {name, type, required} we built.
                perl_by_name: dict = {}
                for p in init_params[1:]:  # skip self
                    perl_by_name[p["name"]] = p
                # Project Perl-attr-driven __init__ to Python's reference
                # shape, adopting Python's per-param ``kind`` for every
                # Perl attr that has a Python counterpart. The remaining
                # Perl-only attrs are emitted at the end with no explicit
                # kind (default ``positional``); the diff tolerates port
                # extras as long as they're optional (which Moo attrs
                # always are when they have a default).
                projected: list[dict] = [{"name": "self", "kind": "self"}]
                used_perl_names: set = set()
                for pyp in py_params:
                    if pyp.get("kind") in ("self", "cls"):
                        continue
                    name = pyp.get("name")
                    if name in perl_by_name:
                        # Adopt Python's kind so keyword-only stays keyword-only.
                        port_param = dict(perl_by_name[name])
                        if pyp.get("kind") == "keyword":
                            port_param["kind"] = "keyword"
                        projected.append(port_param)
                        used_perl_names.add(name)
                    elif pyp.get("kind") == "var_keyword":
                        # Python's **kwargs is handled by Perl Moo's open
                        # constructor — emit as var_keyword.
                        projected.append({
                            "name": name,
                            "kind": "var_keyword",
                            "type": "dict<string,any>",
                            "required": pyp.get("required", False),
                        })
                # Append Perl-only attrs (port-extra) at the end. Moo
                # accepts them as named args; emit them WITHOUT a
                # ``kind`` marker so the diff treats them as
                # ``positional`` (the default) — but since they're
                # extras (more params than Python), the diff already
                # tolerates them as "port-side optional extras" so
                # long as they're optional.
                for p in init_params[1:]:
                    if p["name"] not in used_perl_names:
                        port_param = dict(p)
                        projected.append(port_param)
                init_params = projected
            methods_out["__init__"] = {
                "params": init_params,
                "returns": "void",
            }

        # Emit module-level free functions (class=undef packages).
        if functions_out:
            out_modules.setdefault(mod, {"classes": {}})
            out_modules[mod].setdefault("functions", {})
            out_modules[mod]["functions"].update(functions_out)

        if not methods_out or canonical_class is None:
            continue

        out_modules.setdefault(mod, {"classes": {}})
        out_modules[mod]["classes"].setdefault(canonical_class, {"methods": {}})
        out_modules[mod]["classes"][canonical_class]["methods"].update(methods_out)

    # -----------------------------------------------------------------
    # Reconcile: RELAY event surface (mirror enumerate_surface.pl).
    #   (a) `from_payload` is a class-method constructor DECLARED ONCE on the
    #       base SignalWire::Relay::Event and INHERITED by every typed event
    #       subclass. The reference records from_payload on every event class
    #       (RelayEvent + all *Event subclasses) as a classmethod (cls, payload).
    #       The regex parser only sees the literal `sub from_payload` on the
    #       base package, so project it onto every recorded event class with
    #       the reference-canonical (cls, payload:dict) shape. Real inherited
    #       capability (RULES §2 idiom-via-enumerator), not invented surface.
    #   (b) `parse_event` is declared as a `sub` in the base Event package, so
    #       the parser attributed it to the RelayEvent class; the reference
    #       exposes it as a MODULE-level function. Move it onto functions[].
    ev = out_modules.get("signalwire.relay.event")
    if ev:
        ev_classes = ev.get("classes", {})
        # (b) parse_event: class-method -> module function.
        for cls_name, cls_entry in ev_classes.items():
            if "parse_event" in cls_entry.get("methods", {}):
                cls_entry["methods"].pop("parse_event")
                ev.setdefault("functions", {})
                # The reference exposes parse_event(payload) as a module
                # free function. Project its canonical single-param shape
                # (the class-method attribution's params are the RelayEvent
                # constructor attrs, not this factory's args).
                py_fn = python_signature("signalwire.relay.event", None, "parse_event")
                if py_fn:
                    fn_sig = {
                        "params": [{"name": p.get("name", ""), "type": "any",
                                    "required": p.get("required", True)}
                                   for p in py_fn.get("params", [])
                                   if p.get("kind") not in ("self", "cls")],
                        "returns": "any",
                    }
                else:
                    fn_sig = {"params": [{"name": "payload", "type": "any",
                                          "required": True}], "returns": "any"}
                ev["functions"].setdefault("parse_event", fn_sig)
        # (a) from_payload: project onto every event class (classmethod shape).
        from_payload_sig = {
            "params": [
                {"name": "cls", "kind": "cls"},
                {"name": "payload", "type": "dict<string,any>", "required": True},
            ],
            "returns": "any",
        }
        for cls_name, cls_entry in ev_classes.items():
            if not (cls_name.endswith("Event") or cls_name == "RelayEvent"):
                continue
            cls_entry.setdefault("methods", {})
            cls_entry["methods"].setdefault("from_payload", dict(from_payload_sig))

    # -----------------------------------------------------------------
    # Reconcile: RELAY call surface — StandaloneCollectAction inherits
    # start_input_timers from its parent CollectAction (Perl
    # `SignalWire::Relay::Action::StandaloneCollect extends ...::Collect`);
    # the reference records it on StandaloneCollectAction too. The static
    # parser sees the `sub start_input_timers` only on CollectAction, so
    # project the inherited method (mirror enumerate_surface.pl). Real
    # inherited capability, not invented surface.
    rc = out_modules.get("signalwire.relay.call", {}).get("classes", {})
    collect_a = rc.get("CollectAction", {}).get("methods", {})
    standalone_a = rc.get("StandaloneCollectAction", {}).get("methods")
    if standalone_a is not None and "start_input_timers" in collect_a \
            and "start_input_timers" not in standalone_a:
        standalone_a["start_input_timers"] = dict(collect_a["start_input_timers"])

    # -----------------------------------------------------------------
    # Reconcile: RELAY action control methods projected onto concrete actions.
    # The reference no longer factors the controls into abstract mixin bases
    # (StoppableAction/PausableAction/VolumeAction are gone); it projects them
    # directly onto each concrete action. Perl's concrete actions
    # `extends SignalWire::Relay::Action`, whose `sub stop` the per-package
    # regex parser doesn't attribute to the subclass. Project the inherited
    # `stop` (control_id-only, dict return) onto every concrete *Action class.
    # pause/resume/volume are defined on the concrete subclasses themselves
    # (Play/Record/Collect), so the parser already records them and the
    # reference-type projection concretizes their param types below.
    _relay_stop_sig = {
        "params": [{"name": "self", "kind": "self"}],
        "returns": "dict<string,any>",
    }
    for _cls_name, _cls_entry in rc.items():
        if not _cls_name.endswith("Action") or _cls_name == "Action":
            continue
        _methods = _cls_entry.setdefault("methods", {})
        _methods.setdefault("stop", dict(_relay_stop_sig))

    # -----------------------------------------------------------------
    # Reconcile: DataMap factory helpers are MODULE-level free functions in the
    # reference (signalwire.core.data_map.create_expression_tool /
    # create_simple_api_tool), but Perl declares them as `sub`s in the
    # SignalWire::DataMap package so the parser attributes them to the DataMap
    # class. Move them off the class onto the module functions[] (mirror
    # enumerate_surface.pl's data_map free-function block).
    dm = out_modules.get("signalwire.core.data_map")
    if dm:
        dm_cls = dm.get("classes", {}).get("DataMap", {}).get("methods", {})
        for fn_name in ("create_expression_tool", "create_simple_api_tool"):
            if fn_name in dm_cls:
                sig = dm_cls.pop(fn_name)
                dm.setdefault("functions", {})
                fn_sig = {
                    "params": [p for p in sig.get("params", [])
                               if p.get("kind") not in ("self", "cls")],
                    "returns": sig.get("returns", "any"),
                }
                dm["functions"].setdefault(fn_name, fn_sig)

    # -----------------------------------------------------------------
    # Reconcile: RelayError.__init__. Perl's SignalWire::Relay::Client::RelayError
    # is a plain die-based error class with a hand-written `new` (in SKIP_METHODS)
    # and `code`/`message` accessors — it declares no Moo `has` attrs, so the
    # __init__ synthesis path doesn't fire. The reference records
    # RelayError.__init__(self, code, message). Project the constructor with the
    # Perl-loose (any-typed) params matching the reference arity.
    rce = out_modules.get("signalwire.relay.client", {}).get("classes", {}).get("RelayError")
    if rce is not None and "__init__" not in rce.get("methods", {}):
        py_init = python_signature("signalwire.relay.client", "RelayError", "__init__")
        if py_init:
            init_params = [{"name": "self", "kind": "self"}]
            for p in py_init.get("params", []):
                if p.get("kind") in ("self", "cls"):
                    continue
                init_params.append({
                    "name": p.get("name", ""),
                    "type": "any",
                    "required": p.get("required", True),
                })
            rce.setdefault("methods", {})["__init__"] = {
                "params": init_params, "returns": "void",
            }

    # Mixin projection: Perl flattens all mixin methods onto AgentBase via
    # Moo composition; some helpers also live on SWMLService (parent).
    # Project them onto canonical Python mixin paths.
    ab_entry = out_modules.get("signalwire.core.agent_base", {}).get("classes", {}).get("AgentBase")
    svc_entry = out_modules.get("signalwire.core.swml_service", {}).get("classes", {}).get("SWMLService")
    if ab_entry or svc_entry:
        ab_methods = ab_entry["methods"] if ab_entry else {}
        svc_methods = svc_entry["methods"] if svc_entry else {}
        combined = {**svc_methods, **ab_methods}
        projected: set[str] = set()
        for (target_mod, target_cls), expected in MIXIN_PROJECTIONS.items():
            present = {m: combined[m] for m in expected if m in combined}
            if not present:
                continue
            # Re-run kwargs/hashref projection now that the canonical
            # (mixin module, mixin class, method) is known. The original
            # Pre-mixin projection used signalwire.core.agent_base.AgentBase
            # paths, but the python reference houses the same method on
            # the mixin path (e.g. signalwire.core.mixins.web_mixin.WebMixin.run).
            re_projected_present: dict = {}
            for m_name, sig in present.items():
                params = sig.get("params", [])
                if (
                    params
                    and params[-1].get("kind") == "var_keyword"
                ):
                    py_sig = python_signature(target_mod, target_cls, m_name)
                    leading = params[:-1]
                    proj = _project_kwargs_from_python(py_sig, leading)
                    if proj is not None:
                        sig = {**sig, "params": proj}
                # Hashref-kwargs idiom on mixin path: AIConfigMixin's
                # hashref-style helpers (add_pattern_hint, add_pronunciation,
                # add_language) live on AgentBase pre-projection; their
                # whitelist entry is keyed on the mixin path. Apply the
                # projection here so the mixin sees the kwargs-expanded
                # signature.
                elif (target_mod, target_cls, m_name) in PERL_HASHREF_KWARG_METHODS:
                    py_sig = python_signature(target_mod, target_cls, m_name)
                    if params and params[-1].get("kind") not in ("self", "cls"):
                        leading = params[:-1]
                    else:
                        leading = list(params)
                    proj = _project_kwargs_from_python(py_sig, leading)
                    if proj is not None:
                        sig = {**sig, "params": proj}
                re_projected_present[m_name] = sig
            out_modules.setdefault(target_mod, {"classes": {}})
            out_modules[target_mod]["classes"].setdefault(target_cls, {"methods": {}})
            out_modules[target_mod]["classes"][target_cls]["methods"].update(re_projected_present)
            projected.update(present)
        for n in projected:
            ab_methods.pop(n, None)
            # Also pop from SWMLService when the method is purely a
            # mixin (Python reference doesn't list it on SWMLService).
            # If Python's SWMLService genuinely has the method as well
            # (e.g. inherited or duplicated), leave it.
            if (
                n in svc_methods
                and PYTHON_REFERENCE.get("modules", {})
                .get("signalwire.core.swml_service", {}).get("classes", {})
                .get("SWMLService", {}).get("methods", {}).get(n) is None
            ):
                svc_methods.pop(n, None)
        if ab_entry and not ab_methods:
            out_modules["signalwire.core.agent_base"]["classes"].pop("AgentBase", None)
            if not out_modules["signalwire.core.agent_base"]["classes"]:
                out_modules.pop("signalwire.core.agent_base")

    # Typed-surface strictness: rename Perl-idiom hand-written params to the
    # reference identifier, THEN re-attach reference-documented concrete param
    # types onto hand-written params the parser recorded as bare ``any``.
    apply_hand_param_renames(out_modules)
    project_reference_param_types(out_modules)
    apply_return_type_overrides(out_modules)

    sorted_modules = {}
    for k in sorted(out_modules):
        entry = out_modules[k]
        sorted_modules[k] = {
            "classes": {
                cls: {"methods": dict(sorted(entry["classes"][cls]["methods"].items()))}
                for cls in sorted(entry["classes"])
            }
        }
        # Module-level free functions (e.g. SignalWire::Logging subs that
        # project onto signalwire.core.logging_config.functions.X).
        if entry.get("functions"):
            sorted_modules[k]["functions"] = dict(sorted(entry["functions"].items()))
    return {
        "version": "2",
        "generated_from": "signalwire-perl via best-effort regex parser",
        "modules": sorted_modules,
    }


def run_dump() -> dict:
    cp = subprocess.run(
        ["perl", str(HERE / "signature_dump.pl"), str(PORT_ROOT / "lib")],
        cwd=PORT_ROOT, capture_output=True, text=True, timeout=120,
    )
    if cp.returncode != 0:
        raise RuntimeError(f"signature_dump.pl failed:\n{cp.stderr}")
    raw = json.loads(cp.stdout)
    augment_with_bareword_has(raw)
    return raw


def augment_with_bareword_has(raw: dict) -> None:
    """Post-process the raw signature dump to also pick up Moo ``has``
    declarations using BAREWORDS rather than quoted names. The
    signature_dump.pl regex only matches quoted forms ``has 'name' =>``
    / ``has "name" =>`` but a portion of the SDK uses the unquoted
    form ``has name =>`` (notably SkillBase, SkillManager, SkillRegistry,
    AgentServer). Rather than touch signature_dump.pl, we scan the
    library here in Python and union any missing attrs by package name.
    """
    by_full_name: dict = {}
    for t in raw.get("types", []):
        full = t.get("full_name")
        if full and full not in by_full_name:
            by_full_name[full] = t

    bareword_has = re.compile(
        r"^\s*has\s+([A-Za-z_][A-Za-z0-9_]*)\s*=>",
        re.MULTILINE,
    )
    pkg_pattern = re.compile(r"^\s*package\s+([\w:]+)\s*;", re.MULTILINE)

    lib_root = PORT_ROOT / "lib"
    if not lib_root.is_dir():
        return
    for pm_path in lib_root.rglob("*.pm"):
        text = pm_path.read_text(encoding="utf-8", errors="ignore")
        # Per-file: split by `package X;` declarations and scan each
        # block. (Signature_dump.pl effectively does the same by
        # tracking the current package as it walks lines.)
        pkg_matches = list(pkg_pattern.finditer(text))
        if not pkg_matches:
            continue
        for i, pkg_m in enumerate(pkg_matches):
            pkg_name = pkg_m.group(1)
            start = pkg_m.end()
            end = pkg_matches[i + 1].start() if i + 1 < len(pkg_matches) else len(text)
            block = text[start:end]
            # Collect bareword has-decls in this block.
            new_attrs = bareword_has.findall(block)
            if not new_attrs:
                continue
            entry = by_full_name.get(pkg_name)
            if entry is None:
                # Synthesize a stub entry; the rest of collect() handles it.
                entry = {
                    "full_name": pkg_name,
                    "attributes": [],
                    "methods": [],
                    "extends": [],
                }
                by_full_name[pkg_name] = entry
                raw.setdefault("types", []).append(entry)
            existing = {a.get("name") for a in entry.get("attributes", [])}
            for n in new_attrs:
                if n not in existing:
                    entry.setdefault("attributes", []).append({"name": n})
                    existing.add(n)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, default=None)
    parser.add_argument("--out", type=Path, default=PORT_ROOT / "port_signatures.json")
    args = parser.parse_args()

    if args.raw and args.raw.is_file():
        raw = json.loads(args.raw.read_text(encoding="utf-8"))
    else:
        raw = run_dump()

    canonical = collect(raw)
    args.out.write_text(json.dumps(canonical, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    n_mods = len(canonical["modules"])
    n_methods = sum(sum(len(c["methods"]) for c in m.get("classes", {}).values()) for m in canonical["modules"].values())
    print(f"enumerate_signatures: wrote {args.out} ({n_mods} modules, {n_methods} methods)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
