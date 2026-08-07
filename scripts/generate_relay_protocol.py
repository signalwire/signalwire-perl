#!/usr/bin/env python3
"""Generate the RELAY-protocol wire-type surface for signalwire-perl.

Perl realization of SESSION_CHANGESET_FOR_PORTS.md item I — the
``signalwire.relay.protocol_types_generated`` module — mirroring python's
``generate_relay_protocol``, go's ``emitRelayProtocolFile``, TS's
``protocol.types.generated.ts`` and php's ``generate_relay_protocol.py``.

Source: the canonical porting-sdk ``combined-specs/relay.yaml``, read through the
shared reader ``porting-sdk/scripts/relay_protocol_shapes.py`` (ledger row R11).
That reader serves ``{method: schema_node}`` per phase, merging the shapes carried
on a registered method (``methods.<name>.request.params_dto`` /
``.response.result``) with the six per phase the extractor found for methods the
vendored spec does not register (``<phase>_shapes_unattached.methods.<name>``) —
64 methods per phase either way.

This replaced a directory of standalone per-method JSON-Schema files
(``relay-protocol/<domain>.<method>.(params|result).json``, draft-2020-12,
extracted from the C# switchblade Params/Result classes). The method name now
comes from the document's own key rather than from an ``x-method`` field with a
filename fallback, and the phase from the block it was carried in rather than from
a filename suffix. NOT derived from openapi (a separate generator), which is why
this lives in its own script rather than generate_rest.py.

The class name is the PascalCased method identifier — dots and underscores folded
— plus the phase suffix:

  calling.ai_hold    (params phase) -> package CallingAiHoldParams
  signalwire.connect (result phase) -> package SignalwireConnectResult

The emit/drop rule is the SAME as generate_rest.py's / generate_swml_verbs.py's
wire-type emitter (the shared ``is_object_schema`` test): an OBJECT schema WITH
properties becomes a method-less Moo data class; an object schema with NO
properties (or a non-object / scalar / union) is NOT surfaced — the reference
records those as a module-level ``TypeAlias = dict[str, Any]`` its enumerator
drops, so emitting nothing matches the reference surface.

That drop accounts for 128 candidate shapes -> 123 surfaced classes exactly:
  * 64 params shapes, 2 of them property-less placeholders -> 62 classes.
  * 64 result shapes, 3 of them property-less -> 61 classes.
  The 5 placeholders:
      - calling.call params + result, signalwire.disconnect result (original 3)
      - calling.conference params + result — NET-NEW (porting-sdk be7a34f).
        mod_infrastructure 9755ef7 registered a second protocol method
        ("conference") at relay.c:18915 via
        ``swclt_sess_register_protocol_method``; it has no switchblade
        Params/Result class, so the extractor vendored permissive placeholders
        with no ``properties``. New SERVER surface, not drift — and because they
        carry no properties the existing drop rule excludes them with NO generator
        change and NO emitted diff.
  62 + 61 = 123 == the oracle's 123 method-less classes exactly (0/0).

(The combined document omits the ``type: object`` the per-file envelope used to
declare; ``is_object_schema``'s ``(type is None and properties)`` branch covers
that, so the emit verdict is unchanged. Pinned by
``porting-sdk/tests/test_relay_protocol_shapes.py``.)

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
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _perltidy_gen import perltidy_outputs


# ---------------------------------------------------------------------------
# Reuse the shared emit helpers from generate_rest.py (is_object_schema,
# type_name, perl_attr_name). Import by path so the generators never diverge on
# the emit rule — exactly like generate_swml_verbs.py.
# ---------------------------------------------------------------------------


def _load_rest_generator():
    here = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location(
        "generate_rest", here / "generate_rest.py"
    )
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
# Method identifier -> class name.
# ---------------------------------------------------------------------------

# (phase, package-name suffix). Only params/result are surfaced; the ``event``
# phase is a different phase and is not served by the shared reader at all.
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
    "# AUTO-GENERATED from porting-sdk/combined-specs/relay.yaml — regenerate with:\n"
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
    out += (
        "# wire key; no methods (the reference records this as a method-less type).\n"
    )
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


def _load_relay_shapes(psdk: Path):
    """The shared porting-sdk reader for ``combined-specs/relay.yaml`` (ledger R11).

    Loaded by FILE PATH — the same way this script already loads generate_rest.py —
    because porting-sdk is a sibling checkout, not an installed package.
    """
    path = psdk / "scripts" / "relay_protocol_shapes.py"
    if not path.is_file():
        raise SystemExit(
            f"generate_relay_protocol.py: {path} not found (need porting-sdk adjacency)"
        )
    spec = importlib.util.spec_from_file_location("relay_protocol_shapes", path)
    if spec is None or spec.loader is None:  # pragma: no cover
        raise SystemExit(f"generate_relay_protocol.py: cannot load {path}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build_outputs(psdk: Path) -> dict:
    RPS = _load_relay_shapes(psdk)

    outs: dict = {}
    emitted_names: set = set()

    # Params first, then result — each mapping already ordered by method name — to
    # reproduce the reference decl order (Params block, then Result block).
    for phase, suffix in _PHASES:
        for method, node in RPS.shapes(psdk, phase).items():
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
                pl_name, node.get("properties") or {}, f"method {method!r}, {phase}"
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
            sys.stderr.write(
                f"GEN-FRESH FAIL: {len(stale)} generated RELAY-protocol file(s) stale:\n"
            )
            for s in stale:
                sys.stderr.write(f"  - {s}\n")
            return 1
        print(
            "GEN-FRESH: generated RELAY-protocol files match porting-sdk/combined-specs/relay.yaml."
        )
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
