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
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PORT_ROOT = HERE.parent

# ---------------------------------------------------------------------------
# Perl→Python mapping. Parsed at import-time from enumerate_surface.pl so the
# table stays single-sourced.
# ---------------------------------------------------------------------------

def load_package_map() -> dict[str, dict[str, str | None]]:
    pl = (HERE / "enumerate_surface.pl").read_text(encoding="utf-8")
    # Match lines like:
    #   'SignalWire::Agent::AgentBase' => { module => 'signalwire.core.agent_base', class => 'AgentBase' },
    pattern = re.compile(
        r"'(SignalWire(?:::[^']+)?)'\s*=>\s*\{\s*module\s*=>\s*'([^']+)'\s*,\s*class\s*=>\s*(?:'([^']+)'|undef)"
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


# AgentBase methods that Python keeps on mixin classes. The Perl port has
# them all flattened on AgentBase via Moo composition; we project them onto
# the canonical Python mixin paths so the diff doesn't show them as
# missing-reference (port-only) under signalwire.core.agent_base.AgentBase.
MIXIN_PROJECTIONS = {
    ("signalwire.core.mixins.ai_config_mixin", "AIConfigMixin"): [
        "add_function_include", "add_hint", "add_hints", "add_internal_filler",
        "add_language", "add_pattern_hint", "add_pronunciation",
        "enable_debug_events",
        "set_function_includes", "set_global_data", "set_internal_fillers",
        "set_languages", "set_native_functions", "set_param", "set_params",
        "set_post_prompt_llm_params", "set_prompt_llm_params",
        "set_pronunciations", "update_global_data",
    ],
    ("signalwire.core.mixins.prompt_mixin", "PromptMixin"): [
        "define_contexts", "get_post_prompt", "get_prompt",
        "prompt_add_section",
        "prompt_add_subsection", "prompt_add_to_section",
        "prompt_has_section", "reset_contexts", "set_post_prompt",
        "set_prompt_text",
    ],
    ("signalwire.core.mixins.skill_mixin", "SkillMixin"): [
        "add_skill", "has_skill", "list_skills", "remove_skill",
    ],
    ("signalwire.core.mixins.tool_mixin", "ToolMixin"): [
        "define_tool", "on_function_call", "register_swaig_function",
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
        "enable_debug_routes", "manual_set_proxy_url", "run", "serve",
        "set_dynamic_config_callback",
    ],
    ("signalwire.core.mixins.mcp_server_mixin", "MCPServerMixin"): [
        "add_mcp_server",
    ],
    ("signalwire.core.mixins.state_mixin", "StateMixin"): [
        "validate_tool_token",
    ],
}


def collect(raw: dict) -> dict:
    out_modules: dict = {}

    for type_entry in raw.get("types", []):
        full = type_entry.get("full_name", "")
        target = PACKAGE_TO_PY.get(full)
        if not target:
            # Port-only / not in mapping; skip (surface audit handles via PORT_ADDITIONS)
            continue

        mod = target["module"]
        canonical_class = target["class"]

        methods_out: dict = {}

        for m in type_entry.get("methods", []):
            native = m.get("name", "")
            if native in SKIP_METHODS:
                continue
            if native.startswith("_") and not native.startswith("__"):
                continue
            method_canonical = native
            params = m.get("parameters", [])
            # Strip $self / $class as the canonical receiver
            params_out = []
            saw_receiver = False
            for i, p in enumerate(params):
                pname = p.get("name", "").lstrip("+")
                if i == 0 and pname in ("self", "class"):
                    params_out.append({
                        "name": "self",
                        "kind": "self" if pname == "self" else "cls",
                    })
                    saw_receiver = True
                    continue
                if not pname:
                    continue
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", pname):
                    continue
                params_out.append({
                    "name": pname,
                    "type": "any",
                    "required": True,
                })
            sig = {
                "params": params_out,
                "returns": "void" if native == "BUILD" else "any",
            }
            if canonical_class is None:
                # Module-level function (no class)
                continue
            methods_out[method_canonical] = sig

        # Moo/Moose attributes → emit as zero-arg getter methods
        for a in type_entry.get("attributes", []):
            attr = a.get("name", "").lstrip("+")
            if not attr or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", attr):
                continue
            if attr in methods_out:
                continue
            methods_out[attr] = {
                "params": [{"name": "self", "kind": "self"}],
                "returns": "any",
            }

        # Synthesize __init__ for every Moo/Moose class. Perl/Moo provides
        # ``new`` automatically based on attributes; cross-language audit
        # treats this as the canonical ``__init__`` constructor. The params
        # are the class's named attributes (Moo's hash-arg constructor).
        if "__init__" not in methods_out and canonical_class is not None:
            init_params: list[dict] = [{"name": "self", "kind": "self"}]
            for a in type_entry.get("attributes", []):
                pname = a.get("name", "").lstrip("+")
                if not pname or pname.startswith("_"):
                    continue
                if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", pname):
                    continue
                init_params.append({
                    "name": pname,
                    "type": "any",
                    "required": not a.get("default") and a.get("required", False),
                })
            methods_out["__init__"] = {
                "params": init_params,
                "returns": "void",
            }

        if not methods_out or canonical_class is None:
            continue

        out_modules.setdefault(mod, {"classes": {}})
        out_modules[mod]["classes"].setdefault(canonical_class, {"methods": {}})
        out_modules[mod]["classes"][canonical_class]["methods"].update(methods_out)

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
            out_modules.setdefault(target_mod, {"classes": {}})
            out_modules[target_mod]["classes"].setdefault(target_cls, {"methods": {}})
            out_modules[target_mod]["classes"][target_cls]["methods"].update(present)
            projected.update(present)
        for n in projected:
            ab_methods.pop(n, None)
        if ab_entry and not ab_methods:
            out_modules["signalwire.core.agent_base"]["classes"].pop("AgentBase", None)
            if not out_modules["signalwire.core.agent_base"]["classes"]:
                out_modules.pop("signalwire.core.agent_base")

    sorted_modules = {}
    for k in sorted(out_modules):
        entry = out_modules[k]
        sorted_modules[k] = {
            "classes": {
                cls: {"methods": dict(sorted(entry["classes"][cls]["methods"].items()))}
                for cls in sorted(entry["classes"])
            }
        }
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
    return json.loads(cp.stdout)


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
