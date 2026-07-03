#!/usr/bin/env python3
"""Generate the RELAY-protocol wire-type surface for signalwire-perl.

Perl realization of SESSION_CHANGESET_FOR_PORTS.md item I — the
``signalwire.relay.protocol_types_generated`` module — mirroring python's
``generate_relay_protocol``, go's ``emitRelayProtocolFile``, TS's
``protocol.types.generated.ts`` and php's ``generate_relay_protocol.py``.

Source: the canonical porting-sdk ``relay-protocol/*.json`` — one standalone
JSON-Schema file per RELAY WS method+phase, named
``<domain>.<method>.(params|result).json`` (draft-2020-12, extracted from the C#
switchblade Params/Result classes). NOT derived from openapi (a separate
generator), which is why it lives in its own script rather than generate_rest.py.

The class name derives from the schema's ``x-method`` (fallback: the filename
base) with dots/underscores folded and PascalCased, plus the phase suffix:

  calling.ai_hold.params.json  (x-method "calling.ai_hold", x-phase "params")
      -> package CallingAiHoldParams
  signalwire.connect.result.json                             -> SignalwireConnectResult

The emit/drop rule is the SAME as generate_rest.py's / generate_swml_verbs.py's
wire-type emitter (the shared ``is_object_schema`` test): an OBJECT schema WITH
properties becomes a method-less Moo data class; an object schema with NO
properties (or a non-object / scalar / union) is NOT surfaced — the reference
records those as a module-level ``TypeAlias = dict[str, Any]`` its enumerator
drops, so emitting nothing matches the reference surface.

That drop accounts for the 128 source files -> 123 surfaced classes exactly:
  * 2 files are the ``.event.json`` phase (messaging.receive / messaging.state)
    — NOT params/result, so not part of this params/result module at all.
  * 126 params/result files -> 126 candidate names, of which 3 are empty-object
    placeholder schemas (calling.call params + result, signalwire.disconnect
    result) with no properties -> aliases, NOT surfaced.
  126 - 3 = 123 == the oracle's 123 method-less classes exactly (0/0).

The relay JSON schemas carry no ``$ref`` (every nested object is inline).

Output layout: one class per file under
  lib/SignalWire/Relay/Generated/<ClassName>.pm
in package ``SignalWire::Relay::Generated::<ClassName>``. The surface + signature
enumerators route every file under ``Relay/Generated/`` to the oracle module
``signalwire.relay.protocol_types_generated`` BY PATH (winning over the package
map so an existing Relay SDK class — Call/Client/CallState/… one level up — is
never misrouted).

Usage:
    python3 scripts/generate_relay_protocol.py            # write into the repo tree
    python3 scripts/generate_relay_protocol.py --check    # GEN-FRESH: fail if stale
    python3 scripts/generate_relay_protocol.py --out DIR  # scratch: emit into DIR
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Reuse the shared emit helpers from generate_rest.py (is_object_schema,
# type_name, perl_attr_name). Import by path so the generators never diverge on
# the emit rule — exactly like generate_swml_verbs.py.
# ---------------------------------------------------------------------------

def _load_rest_generator():
    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location("generate_rest", here / "generate_rest.py")
    if spec is None or spec.loader is None:  # pragma: no cover
        raise SystemExit("generate_relay_protocol.py: cannot load generate_rest.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GR = _load_rest_generator()


def resolve_porting_sdk() -> Path:
    return GR.resolve_porting_sdk()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


# ---------------------------------------------------------------------------
# Filename / x-method -> class name.
# ---------------------------------------------------------------------------

# (filename phase tail, package-name suffix). Only params/result are surfaced;
# the ``.event.json`` files (x-phase "event") are a different phase and excluded.
_PHASES = (("params", "Params"), ("result", "Result"))


def _pascal_method(method: str) -> str:
    """PascalCase a RELAY method identifier: dots and underscores are word
    separators, so ``calling.ai_hold`` -> ``CallingAiHold`` and
    ``signalwire.connect`` -> ``SignalwireConnect`` (note: ``signalwire`` folds to
    ``Signalwire``, matching the oracle — this is the wire domain token, not the
    ``SignalWire`` brand). Mirrors go's pascal(strings.ReplaceAll(method,".","_"))."""
    parts = [p for p in re.split(r"[._\-\s]", method) if p]
    return "".join(w[:1].upper() + w[1:] for w in parts)


# ---------------------------------------------------------------------------
# Emit.
# ---------------------------------------------------------------------------

RELAY_HEADER = (
    "# Code generated by scripts/generate_relay_protocol.py; DO NOT EDIT.\n"
    "#\n"
    "# AUTO-GENERATED from porting-sdk/relay-protocol/*.{{params,result}}.json — regenerate with:\n"
    "#   python3 scripts/generate_relay_protocol.py\n"
    "#\n"
    "# {desc}\n"
)


def _emit_class(pl_name: str, properties: dict, source_desc: str) -> str:
    """Emit one method-less Moo data package for a RELAY params/result object
    schema. `has` accessors carry the snake wire key; no methods (surface records
    only the class name)."""
    pkg = f"SignalWire::Relay::Generated::{pl_name}"
    desc = f"Generated RELAY protocol wire type {pl_name!r} ({source_desc})."
    out = RELAY_HEADER.format(desc=desc)
    out += f"package {pkg};\n"
    out += "use strict;\n"
    out += "use warnings;\n"
    out += "use Moo;\n\n"
    out += "# Pure data DTO: one read-only accessor per property carrying the snake\n"
    out += "# wire key; no methods (the reference records this as a method-less type).\n"
    used: set[str] = set()
    for wire_key in properties:
        attr = GR.perl_attr_name(wire_key)
        while attr in used:
            attr += "_"
        used.add(attr)
        if attr != wire_key:
            out += f"# wire key: {wire_key}\n"
        out += GR.perl_has_decl(attr) + "\n"
    out += "\n1;\n"
    return out


def build_outputs(psdk: Path) -> dict:
    relay_dir = psdk / "relay-protocol"
    if not relay_dir.is_dir():
        raise SystemExit(
            f"generate_relay_protocol.py: {relay_dir} not found (need porting-sdk adjacency)"
        )

    by_name: dict = {}
    for p in relay_dir.iterdir():
        if p.is_file() and p.suffix == ".json":
            by_name[p.name] = p

    outs: dict = {}
    emitted_names: set = set()

    # Iterate params files first, then result files — sorted within each phase —
    # to reproduce the reference decl order (Params block, then Result block).
    for phase, suffix in _PHASES:
        tail = "." + phase + ".json"
        for name in sorted(n for n in by_name if n.endswith(tail)):
            node = json.loads(by_name[name].read_text())
            if not isinstance(node, dict):
                continue
            method = node.get("x-method") or name[: -len(tail)]
            pl_name = GR.type_name(_pascal_method(method) + suffix)
            # Same object-vs-alias split as the REST / SWML wire-type emitters: an
            # object WITH properties -> data class; an empty-object / scalar / union
            # placeholder -> a `TypeAlias = dict[str,Any]` the reference enumerator
            # drops, so emit nothing (keeps the surface at the oracle's 123).
            if not GR.is_object_schema(node):
                continue
            if pl_name in emitted_names:
                continue
            emitted_names.add(pl_name)
            outs[f"{pl_name}.pm"] = _emit_class(
                pl_name, node.get("properties") or {}, f"method {method!r}, {phase}")

    return outs


# ---------------------------------------------------------------------------
# Driver.
# ---------------------------------------------------------------------------

def main(argv) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="GEN-FRESH: exit non-zero if stale")
    ap.add_argument("--out", default="", help="scratch: emit into this dir")
    args = ap.parse_args(argv)

    psdk = resolve_porting_sdk()
    outs = build_outputs(psdk)

    if args.out:
        out_dir = Path(args.out)
    else:
        out_dir = repo_root() / "lib" / "SignalWire" / "Relay" / "Generated"

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
            sys.stderr.write("GEN-FRESH FAIL: %d generated RELAY-protocol file(s) stale:\n" % len(stale))
            for s in stale:
                sys.stderr.write("  - %s\n" % s)
            return 1
        print("GEN-FRESH: generated RELAY-protocol files match porting-sdk/relay-protocol/*.json.")
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    for fn, src in outs.items():
        p = out_dir / fn
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(src)
    print(f"generated {len(outs)} RELAY-protocol file(s) into {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
