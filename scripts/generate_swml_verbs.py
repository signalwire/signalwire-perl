#!/usr/bin/env python3
"""Generate the typed SWML-verbs CONFIG surface for signalwire-perl.

Perl realization of SESSION_CHANGESET_FOR_PORTS.md item D2 — the
``signalwire.core.swml_verbs_generated`` module — mirroring python's
``swml_verbs_generated.py``, go's ``emitSwmlVerbs``, TS's ``swml_verbs_generated.ts``
and php's ``generate_swml_verbs.py``.

Source: the CANONICAL porting-sdk ``schema.json`` ``$defs`` (167 defs). The perl
repo also vendors a copy at ``lib/SignalWire/SWML/schema.json`` (identical $defs
object-schema set); this generator reads the porting-sdk canonical so the port
tracks the shared source, exactly like generate_rest.py.

What is emitted (matching the Python SURFACE oracle's 155 method-less types — the
reference's ``_SwmlVerbs`` verb-METHOD protocol is ``_``-prefixed and NOT part of
the cross-port surface oracle, so only the CONFIG type surface is emitted):

  1. One method-less Moo data package per ``$defs`` OBJECT schema (133) — one
     read-only ``has`` accessor per property carrying the snake wire key, no
     methods. Emit/drop rule is the SAME as generate_rest.py's wire-type emitter:
     object schema -> data class; scalar / array / oneOf / anyOf / allOf union
     alias -> NOT surfaced (the reference's enumerator drops module-level scalar
     TypeAlias / inline union). Drops the 34 non-object $defs (SWMLMethod, SWMLVar,
     CondParams, Languages, POM, Action, …).

  2. One ``<Verb>Config`` data package per SWMLMethod.anyOf verb whose inner schema
     is an inline object / oneOf union (22) — the flattened UNION of the verb's
     variant properties (mirrors go's flattenUnion / the reference _flatten_union).
     Hand-written verbs (answer/hangup/ai/play/say) are excluded from the Config
     flatten, matching go's handWrittenVerbs / the reference hand_written set.

  133 object classes + 22 Config classes = 155 == the oracle exactly (0/0).

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
    defs = _load_defs(psdk)
    outs: dict = {}
    emitted_names: set = set()

    # 1. One data class per OBJECT $defs schema (drop scalar/array/union aliases —
    #    same rule as the REST wire-type emitter).
    for raw_name, node in defs.items():
        if not isinstance(node, dict):
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
