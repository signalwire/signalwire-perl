#!/usr/bin/env python3
"""Generate the typed SWML-verbs CONFIG surface for signalwire-perl.

Perl realization of SESSION_CHANGESET_FOR_PORTS.md item D2 — the
``signalwire.core.swml_verbs_generated`` module — mirroring python's
``swml_verbs_generated.py``, go's ``emitSwmlVerbs``, TS's ``swml_verbs_generated.ts``
and php's ``generate_swml_verbs.py``.

Source: the CANONICAL porting-sdk ``schema.json`` ``$defs`` (engine-derived; the
ai/connect/... verb configs are carried INLINE). The pipeline mirrors the python
reference's render_swml_verbs exactly:

  0. Drop deprecated verbs (dial/eval/if — owner ruling 2026-09-24), then HOIST
     every inline property-bearing object into a named $def with the reference's
     deterministic path-derived name (``<Verb>Config`` for a verb root, ``<Verb>``-
     prefixed descendants: AiConfig, AiParams, AiSWAIGFunctionsItem, ...).

  1. One method-less Moo data package per OBJECT $def (originals + hoisted) — one
     read-only ``has`` accessor per property carrying the snake wire key, no
     methods. Emit/drop rule is the SAME as generate_rest.py's wire-type emitter:
     object schema -> data class; scalar / array / union alias -> NOT surfaced.
     The SWAIG envelope types (SwaigAction / SwaigResponse + their interiors) are
     owned by the SWAIG generator and skipped here.

  2. One ``<Verb>Config`` data package per remaining SWMLMethod.anyOf verb whose
     inner schema is a oneOf union / inline object (the flattened UNION of its
     variant properties). Hand-written verbs (answer/hangup/ai/play/say) are
     excluded from the flatten, matching the reference hand_written set.

  The emitted class set equals the oracle's ``signalwire.core.swml_verbs_generated``
  (187 classes at porting-sdk bd22268).

Unlike PHP, Perl package names are unrestricted — Goto/Return/Switch/Unset are
valid leaves, so NO reserved-word suffix is needed (perl -c confirmed).

Output layout: one class per file under
  lib/SignalWire/SWML/Generated/<ClassName>.pm
in package ``SignalWire::REST::Namespaces::Generated::SWMLVerbs`` — no, in package
``SignalWire::SWML::Generated::<ClassName>``. The surface + signature enumerators
route every file under ``SWML/Generated/`` to the oracle module
``signalwire.core.swml_verbs_generated`` BY PATH (a type name that also exists as
a REST wire type — 125 of the 155 recur — lands in the right module); the
SURFACE-DIFF gen-type leaf fold then collapses the cross-module duplicates on both
sides.

Usage:
    python3 scripts/generate_swml_verbs.py            # write into the repo tree
    python3 scripts/generate_swml_verbs.py --check    # GEN-FRESH: fail if stale
    python3 scripts/generate_swml_verbs.py --out DIR  # scratch: emit into DIR
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _perltidy_gen import perltidy_outputs


# ---------------------------------------------------------------------------
# Reuse the shared emit helpers from generate_rest.py (is_object_schema,
# type_name, perl_attr_name, perl_str, TYPES_HEADER). Import by path so the two
# generators never diverge on the emit rule.
# ---------------------------------------------------------------------------


def _load_rest_generator():
    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location(
        "generate_rest", here / "generate_rest.py"
    )
    if spec is None or spec.loader is None:  # pragma: no cover
        raise SystemExit("generate_swml_verbs.py: cannot load generate_rest.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GR = _load_rest_generator()


def resolve_porting_sdk() -> Path:
    return GR.resolve_porting_sdk()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


# ---------------------------------------------------------------------------
# schema.json $defs model.
# ---------------------------------------------------------------------------

# Verbs the reference hand-writes with richer ergonomics; excluded from the
# <Verb>Config flatten (matches go's handWrittenVerbs / the reference hand_written
# set). Only affects which Config classes are emitted — every $defs OBJECT schema
# is still emitted as a data class regardless.
HAND_WRITTEN_VERBS = {"answer", "hangup", "ai", "play", "say"}


def _load_defs(psdk: Path) -> dict:
    doc = json.loads((psdk / "schema.json").read_text())
    defs = doc.get("$defs")
    if not defs:
        raise SystemExit("generate_swml_verbs.py: schema.json has no $defs")
    return defs


def _ref_leaf(ref: str) -> str:
    return ref.rsplit("/", 1)[-1] if ref else ref


def _type_str(node: dict):
    t = node.get("type")
    if isinstance(t, list):
        return next((x for x in t if x != "null"), None)
    return t


def _pascal(s: str) -> str:
    parts = re.split(r"[_\-\s.]", s)
    return "".join(w[:1].upper() + w[1:] for w in parts if w)


# ---------------------------------------------------------------------------
# Deprecated-verb drop + inline-object hoisting — a faithful port of the python
# reference generator (porting-sdk/scripts/generate_python_rest_types.py:
# swml_verb_is_deprecated / drop_deprecated_swml_verbs / _presence_only /
# _without_presence_allof / _is_inline_object / hoist_inline_objects). The
# engine-derived schema.json carries most verb configs INLINE (``AI.ai`` is an
# anyOf whose object arm is the whole typed ai config); hoisting lifts every
# inline property-bearing object into a named $def with the SAME deterministic
# path-derived name the reference uses (AiConfig, AiParams, AiSWAIGFunctionsItem,
# ...), so the perl class set compares equal to the oracle's
# ``signalwire.core.swml_verbs_generated``. Keep this in lockstep with the
# reference: a naming divergence surfaces as DRIFT on every hoisted class.
# ---------------------------------------------------------------------------


def _swml_verb_is_deprecated(wrapper: dict) -> bool:
    if wrapper.get("deprecated") is True:
        return True
    props = wrapper.get("properties") or {}
    return any(
        isinstance(v, dict) and v.get("deprecated") is True for v in props.values()
    )


def _drop_deprecated_swml_verbs(defs: dict) -> dict:
    """``defs`` without its deprecated verbs (owner ruling 2026-09-24: deprecated
    verbs — dial/eval/if — are not SDK surface)."""
    swml_method = defs.get("SWMLMethod") or {}
    kept_arms: list = []
    dropped: list = []
    for arm in swml_method.get("anyOf") or []:
        wrapper = str(arm.get("$ref") or "").rsplit("/", 1)[-1]
        wdef = defs.get(wrapper)
        if isinstance(wdef, dict) and _swml_verb_is_deprecated(wdef):
            dropped.append(wrapper)
            continue
        kept_arms.append(arm)
    if not dropped:
        return defs
    out = {k: v for k, v in defs.items() if k not in dropped}
    out["SWMLMethod"] = {**swml_method, "anyOf": kept_arms}
    return out


_PRESENCE_KEYS = frozenset({"required", "anyOf", "oneOf", "allOf"})


def _presence_only(arms) -> bool:
    """Every arm constrains only WHICH keys are present (required clauses combined by
    anyOf/oneOf/allOf) — the engine's one-of rules, which add no key and no type."""
    if not isinstance(arms, list) or not arms:
        return False
    for arm in arms:
        if not isinstance(arm, dict) or not arm or not set(arm) <= _PRESENCE_KEYS:
            return False
        req = arm.get("required")
        if req is not None and not (
            isinstance(req, list) and all(isinstance(r, str) for r in req)
        ):
            return False
        for key in ("anyOf", "oneOf", "allOf"):
            if key in arm and not _presence_only(arm[key]):
                return False
    return True


def _without_presence_allof(node: dict) -> dict:
    if _presence_only(node.get("allOf")):
        return {k: v for k, v in node.items() if k != "allOf"}
    return node


def _is_inline_object(node) -> bool:
    if isinstance(node, dict):
        node = _without_presence_allof(node)
    return (
        isinstance(node, dict)
        and "$ref" not in node
        and bool(node.get("properties"))
        and node.get("type") in ("object", None)
        and not (node.get("anyOf") or node.get("oneOf") or node.get("allOf"))
    )


def _hoist_inline_objects(defs: dict, verb_roots: dict) -> dict:
    """Lift every inline property-bearing object into its own named $def. Names:
    a verb root is ``<Verb>Config`` with ``<Verb>``-prefixed descendants; any other
    object is ``<Parent><Key>``; an array element adds ``Item``; a union with ONE
    object arm gives that arm the union's name, several arms take
    ``<Name><ArmTitle>`` (or ``<Name>Variant<i>``). Collisions get a numeric
    suffix. Originals first, hoisted after, in walk order."""
    taken: set = set(defs)
    hoisted: dict = {}
    name_of: dict = {}

    def claim(name: str) -> str:
        cand, n = name, 2
        while cand in taken:
            cand, n = f"{name}{n}", n + 1
        taken.add(cand)
        return cand

    def walk_children(node: dict, prefix: str) -> dict:
        out = dict(node)
        if isinstance(node.get("properties"), dict):
            out["properties"] = {
                k: visit(v, prefix + _pascal(k), prefix + _pascal(k))
                for k, v in node["properties"].items()
            }
        if isinstance(node.get("items"), dict):
            out["items"] = visit(node["items"], prefix + "Item", prefix + "Item")
        if isinstance(node.get("prefixItems"), list):
            out["prefixItems"] = [
                visit(p, f"{prefix}Item{i + 1}", f"{prefix}Item{i + 1}")
                for i, p in enumerate(node["prefixItems"])
            ]
        if isinstance(node.get("additionalProperties"), dict):
            out["additionalProperties"] = visit(
                node["additionalProperties"], prefix + "Value", prefix + "Value"
            )
        for key in ("anyOf", "oneOf", "allOf"):
            arms = node.get(key)
            if not isinstance(arms, list):
                continue
            n_obj = sum(1 for a in arms if _is_inline_object(a))
            new_arms = []
            for i, arm in enumerate(arms):
                if n_obj > 1 and _is_inline_object(arm):
                    suffix = _pascal(
                        re.sub(r"[^A-Za-z0-9]+", " ", str(arm.get("title") or ""))
                    )
                    arm_name = f"{prefix}{suffix or f'Variant{i + 1}'}"
                    new_arms.append(visit(arm, arm_name, arm_name))
                else:
                    new_arms.append(visit(arm, name_of[id(node)], prefix))
            out[key] = new_arms
        return out

    def visit(node, name: str, prefix: str):
        if not isinstance(node, dict):
            return node
        if _is_inline_object(node):
            final = claim(name)
            child_prefix = prefix if prefix != name else final
            hoisted[final] = {}  # reserve walk order before descending
            hoisted[final] = walk_children(_without_presence_allof(node), child_prefix)
            ref = {"$ref": f"#/$defs/{final}"}
            for keep in ("description", "title", "deprecated", "x-api-state"):
                if keep in node:
                    ref[keep] = node[keep]
            return ref
        name_of[id(node)] = name
        return walk_children(node, prefix)

    out: dict = {}
    for def_name, sch in defs.items():
        if not isinstance(sch, dict):
            out[def_name] = sch
            continue
        verb = verb_roots.get(def_name)
        if verb is not None:
            props = dict(sch.get("properties") or {})
            base = _pascal(verb)
            props[verb] = visit(props[verb], base + "Config", base)
            out[def_name] = {**sch, "properties": props}
        else:
            name_of[id(sch)] = def_name
            out[def_name] = walk_children(sch, def_name)
    out.update(hoisted)
    return out


# The SWAIG response ENVELOPE types are declared once, by the SWAIG module
# (signalwire.core.swaig_actions_generated / lib/SignalWire/SWAIG/Generated);
# the SWML module skips them and their hoisted interiors (mirrors the reference
# SWAIG_ENVELOPE_TYPES skip in _emit_swml_verbs).
SWAIG_ENVELOPE_TYPES = ("SwaigAction", "SwaigResponse")


def _is_swaig_envelope(name: str) -> bool:
    return any(
        name == n or (name.startswith(n) and name[len(n) : len(n) + 1].isupper())
        for n in SWAIG_ENVELOPE_TYPES
    )


def _prepare_defs(defs: dict) -> dict:
    """drop deprecated verbs, then hoist inline objects (keyed off SWMLMethod's
    verb wrappers) — the reference render_swml_verbs pipeline."""
    defs = _drop_deprecated_swml_verbs(defs)
    verb_roots: dict = {}
    for arm in (defs.get("SWMLMethod") or {}).get("anyOf") or []:
        wrapper = str(arm.get("$ref") or "").rsplit("/", 1)[-1]
        wprops = list(((defs.get(wrapper) or {}).get("properties") or {}).keys())
        if wprops:
            verb_roots[wrapper] = wprops[0]
    return _hoist_inline_objects(defs, verb_roots)


def _flatten_union(defs: dict, node) -> dict:
    """Return the UNION of properties across allOf/oneOf/anyOf, following $ref
    (mirrors go's flattenUnion / the reference _flatten_union). First-seen wins."""
    out: dict = {}

    def walk(n) -> None:
        if not n:
            return
        ref = n.get("$ref")
        if ref:
            walk(defs.get(_ref_leaf(ref)))
            return
        for sub in n.get("allOf") or []:
            walk(sub)
        for name, psc in (n.get("properties") or {}).items():
            out.setdefault(name, psc)
        for sub in n.get("oneOf") or []:
            walk(sub)
        for sub in n.get("anyOf") or []:
            walk(sub)

    walk(node)
    return out


# ---------------------------------------------------------------------------
# Emit.
# ---------------------------------------------------------------------------

SWML_HEADER = (
    "# Code generated by scripts/generate_swml_verbs.py; DO NOT EDIT.\n"
    "#\n"
    "# AUTO-GENERATED from porting-sdk/schema.json ($defs) — regenerate with:\n"
    "#   python3 scripts/generate_swml_verbs.py\n"
    "#\n"
    "# {desc}\n"
)


def _emit_class(
    pl_name: str, properties: dict, source_desc: str, schema_name: str, psdk: Path
) -> str:
    """Emit one method-less Moo data package for an object/config schema. The
    surface records only the class name; `has` accessors are not `sub` decls, so
    the class stays method-less on both enumerators.

    The SDK-surface overlay (x-sdk-overlay.yaml) is consulted by (wire key, SPEC
    schema name = `schema_name`, e.g. `AIParams`): hidden -> dropped from the
    surface (still wire), deprecated -> emitted but flagged with a comment."""
    pkg = f"SignalWire::SWML::Generated::{pl_name}"
    desc = f"Generated SWML verb config type {pl_name!r} ({source_desc})."
    out = SWML_HEADER.format(desc=desc)
    out += f"package {pkg};\n"
    out += "use strict;\n"
    out += "use warnings;\n"
    out += "use Moo;\n\n"
    out += "# Pure data DTO: one read-only accessor per property carrying the snake\n"
    out += (
        "# wire key; no methods (the reference records this as a method-less type).\n"
    )
    used: set[str] = set()
    for wire_key in properties:
        if GR.overlay_hidden(psdk, wire_key, schema_name):
            continue  # hidden: drop from the SDK surface entirely (still wire).
        attr = GR.perl_attr_name(wire_key)
        while attr in used:
            attr += "_"
        used.add(attr)
        if attr != wire_key:
            out += f"# wire key: {wire_key}\n"
        if GR.overlay_deprecated(psdk, wire_key, schema_name):
            out += f"# deprecated: {wire_key}\n"
        out += GR.perl_has_decl(attr) + "\n"
    out += "\n1;\n"
    return out


def build_outputs(psdk: Path) -> dict:
    defs = _prepare_defs(_load_defs(psdk))
    outs: dict = {}
    emitted_names: set = set()

    # 1. One data class per OBJECT $defs schema (drop scalar/array/union aliases —
    #    same rule as the REST wire-type emitter).
    for raw_name, node in defs.items():
        if not isinstance(node, dict):
            continue
        if _is_swaig_envelope(raw_name):
            continue
        if not GR.is_object_schema(node):
            continue
        pl_name = GR.type_name(raw_name)
        if pl_name in emitted_names:
            continue
        emitted_names.add(pl_name)
        outs[f"{pl_name}.pm"] = _emit_class(
            pl_name,
            node.get("properties") or {},
            f"$defs schema {raw_name!r}",
            raw_name,
            psdk,
        )

    # 2. One <Verb>Config data class per SWMLMethod.anyOf verb whose inner schema
    #    is an inline object / oneOf union (flattened union of variant props).
    sm = defs.get("SWMLMethod")
    if sm:
        for ref in sm.get("anyOf") or []:
            wrapper = _ref_leaf(ref.get("$ref", ""))
            wdef = defs.get(wrapper)
            if not wdef or not (wdef.get("properties") or {}):
                continue
            verb = next(iter(wdef["properties"].keys()))
            if verb in HAND_WRITTEN_VERBS:
                continue
            inner = wdef["properties"][verb]
            # A $ref / plain-string verb payload has no inline object shape to
            # flatten into a Config struct (go's guard).
            if _type_str(inner) == "string" or inner.get("$ref"):
                continue
            has_inline = _type_str(inner) == "object" and bool(inner.get("properties"))
            if not inner.get("oneOf") and not has_inline:
                continue
            props = _flatten_union(defs, inner)
            if not props:
                continue
            cfg_name = _pascal(verb) + "Config"
            pl_name = GR.type_name(cfg_name)
            if pl_name in emitted_names:
                continue
            emitted_names.add(pl_name)
            outs[f"{pl_name}.pm"] = _emit_class(
                pl_name,
                props,
                f"flattened SWMLMethod verb {verb!r} config",
                cfg_name,
                psdk,
            )

    # §5 format backstop: tidy every generated .pm so GEN-FRESH and the FMT
    # gate both pass (perltidy aligns consecutive `has` declarations, which a
    # straight-line emitter cannot reproduce).
    perltidy_outputs(outs, repo_root())
    return outs


# ---------------------------------------------------------------------------
# Driver.
# ---------------------------------------------------------------------------


def main(argv) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check", action="store_true", help="GEN-FRESH: exit non-zero if stale"
    )
    ap.add_argument("--out", default="", help="scratch: emit into this dir")
    args = ap.parse_args(argv)

    psdk = resolve_porting_sdk()
    outs = build_outputs(psdk)

    if args.out:
        out_dir = Path(args.out)
    else:
        out_dir = repo_root() / "lib" / "SignalWire" / "SWML" / "Generated"

    if args.check:
        stale: list = []
        for fn, src in outs.items():
            p = out_dir / fn
            if not p.is_file() or p.read_text() != src:
                stale.append(str(p))
        expected = set(outs.keys())
        if out_dir.is_dir():
            for p in sorted(out_dir.rglob("*.pm")):
                rel = p.relative_to(out_dir).as_posix()
                if rel not in expected:
                    stale.append(f"{p} (leftover — not in generator output)")
        if stale:
            sys.stderr.write(
                f"GEN-FRESH FAIL: {len(stale)} generated SWML-verb file(s) stale:\n"
            )
            for s in stale:
                sys.stderr.write(f"  - {s}\n")
            return 1
        print(
            "GEN-FRESH: generated SWML-verb files match porting-sdk/schema.json ($defs)."
        )
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    for fn, src in outs.items():
        p = out_dir / fn
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(src)
    print(f"generated {len(outs)} SWML-verb file(s) into {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
