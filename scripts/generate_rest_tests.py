#!/usr/bin/env python3
"""Generate the full-mock REST wire-test suite for signalwire-perl.

This is the Perl realisation of porting-sdk/REST_TEST_GENERATOR_RULES.md (the
portable REST *test* generator; reference:
generate_python_rest_types.py::generate_rest_tests; mirrors
signalwire-ruby/scripts/generate_rest_tests.py + signalwire-php/scripts/
generate_rest_tests.py + signalwire-go/cmd/generate-rest-tests +
signalwire-typescript/scripts/generate-rest-tests.ts). For every REST route the
SDK actually implements it emits, into t/rest/generated/<spec>_generated.t:

  - a SUCCESS test: call the real SDK method against the shared MockTest harness
    (a fresh MockTest::client), assert the mock journaled the expected
    (method, matched_route);
  - an ERROR test: arm a 500 for that route, assert the SDK raises
    SignalWire::REST::HttpClient::Error with ->status_code == 500.

The assertion oracle is INDEPENDENT of the resource generator (RULES §1):
  - the (method, path) to call + the via method come from the route registry
    (scripts/route_registry.pl — captured from the REAL client) and the per-via
    call plan (scripts/rest_test_plan.pl — reflected from the real client), NOT
    re-walked here;
  - the matched_route to assert comes from the OpenAPI operationId
    (<spec_dir>.<operationId>) — the same value the mock derives its route table
    from. A generated test therefore catches SDK-vs-contract drift, not a
    generator self-snapshot.

Inputs joined by (METHOD, normalized-path) (RULES §2): the registry's deduped
routes (path params already {id}) x the spec operationIds (spec path normalized
the SAME way before the join). Routing collisions are resolved
longest-template-wins (RULES §7) so the asserted route is the one the mock
ACTUALLY journals (e.g. GET /rooms/{id} vs GET /rooms/{name}).

Call args are sentinel-faithful BY CONSTRUCTION (RULES §4): rest_test_plan.pl
reflects each via method's REQUIRED params off the live client and emits a Perl
literal token per required param (one 'x' positional per {id} path segment, plus
`key => 'x'` for every SDK-required kwarg). Perl has no formal signature
reflection, so the plan RE-INVOKES every via with exactly those tokens and
confirms it reproduces the registry's captured (verb, path) — a token shape that
would not reach the route is a hard error, never a silently-wrong test.

GEN-FRESH: `--check` reproduces the committed *_generated.t and exits non-zero if
any file differs. Resolves porting-sdk via $PORTING_SDK or sibling.

Usage:
    python3 scripts/generate_rest_tests.py           # (re)write the test files
    python3 scripts/generate_rest_tests.py --check   # GEN-FRESH: fail if stale
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.stderr.write("generate_rest_tests.py requires PyYAML (pip install pyyaml)\n")
    raise


# ---------------------------------------------------------------------------
# Resolution.
# ---------------------------------------------------------------------------


def resolve_porting_sdk() -> Path:
    env = os.environ.get("PORTING_SDK")
    if env and (Path(env) / "rest-apis").is_dir():
        return Path(env).resolve()
    here = Path(__file__).resolve()
    for parent in here.parents:
        cand = parent.parent / "porting-sdk"
        if (cand / "rest-apis").is_dir():
            return cand.resolve()
    raise SystemExit(
        "generate_rest_tests.py: porting-sdk not found (set $PORTING_SDK or clone adjacent)"
    )


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


# ---------------------------------------------------------------------------
# 1. Capture from the real client (RULES §3) — shell the committed Perl helpers.
#    route_registry.pl: the SDK's deduped routes (via-merged, {id}-normalized).
#    rest_test_plan.pl:  per-via call plan (chain, member, sentinel args).
# ---------------------------------------------------------------------------


def _run_perl(script: Path) -> dict:
    proc = subprocess.run(
        ["perl", "-Ilib", str(script)],
        cwd=str(repo_root()),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        raise SystemExit(f"{script.name} exited {proc.returncode} — capture incomplete")
    out = proc.stdout
    # Any stray SDK warning would go to stderr; stdout is pure JSON, but slice
    # from the first '{' defensively.
    i = out.find("{")
    if i > 0:
        out = out[i:]
    return json.loads(out)


def load_routes() -> list[dict]:
    reg = _run_perl(repo_root() / "scripts" / "route_registry.pl")
    if reg.get("errors"):
        raise SystemExit(
            f"route_registry.pl reported {len(reg['errors'])} capture error(s) — Set B incomplete"
        )
    return reg["routes"]


def load_plan() -> dict[str, dict]:
    plan = _run_perl(repo_root() / "scripts" / "rest_test_plan.pl")
    if plan.get("errors"):
        raise SystemExit(
            f"rest_test_plan.pl reported {len(plan['errors'])} capture error(s) — plan incomplete"
        )
    # Index by via (unique per plan entry).
    return {e["via"]: e for e in plan["plan"]}


# ---------------------------------------------------------------------------
# 2. The join — registry routes x spec operationIds by (method, normalized-path).
# ---------------------------------------------------------------------------

_BRACE = re.compile(r"\{[^}]+\}")


def norm_params(p: str) -> str:
    """Every {param} → {id} (registry already does this; do it to the spec path
    so renamed params — {token_id}, {name} — line up)."""
    return _BRACE.sub("{id}", p)


def wire_key(p: str) -> str:
    """Every {param} → X: the wire-identical key used for collision ranking."""
    return _BRACE.sub("X", p)


def spec_prefix(doc: dict) -> str:
    url = ((doc.get("servers") or [{}])[0]).get("url", "")
    i = url.find("signalwire.com")
    return url[i + len("signalwire.com") :] if i >= 0 else ""


def spec_dirs_with_openapi(psdk: Path) -> list[str]:
    root = psdk / "rest-apis"
    out = [
        d.name for d in root.iterdir() if d.is_dir() and (d / "openapi.yaml").is_file()
    ]
    return sorted(out)


def build_join(routes: list[dict], psdk: Path, spec_dirs: list[str]) -> list[dict]:
    """Return one joined row per registry route that has a spec op AND a via.

    Row: {method, path, op_id (<spec>.<operationId>), via, spec}. The via is the
    registry's via[0] — the same accessor go/ts/php/ruby pick — and the op_id is
    the longest-template collision winner the mock actually journals (RULES §7).
    """
    op_by: dict[str, str] = {}  # "METHOD normPath" -> <spec>.<operationId>
    wire_winner: dict[str, tuple[int, str]] = {}  # "METHOD wireKey" -> (len, route)
    verbs = ("get", "post", "put", "patch", "delete")

    for spec in spec_dirs:
        doc = yaml.safe_load((psdk / "rest-apis" / spec / "openapi.yaml").read_text())
        prefix = spec_prefix(doc)
        for path_key, body in (doc.get("paths") or {}).items():
            orig = prefix + path_key
            full = _BRACE.sub("{id}", orig)
            wk = _BRACE.sub("X", orig)
            for verb in verbs:
                op = body.get(verb)
                if not isinstance(op, dict):
                    continue
                op_id = op.get("operationId")
                if not op_id:
                    continue
                route = f"{spec}.{op_id}"
                op_by[f"{verb.upper()} {full}"] = route
                wkey = f"{verb.upper()} {wk}"
                cur = wire_winner.get(wkey)
                if cur is None or len(orig) > cur[0]:
                    wire_winner[wkey] = (len(orig), route)

    rows: list[dict] = []
    for r in routes:
        via_list = r.get("via") or []
        if not via_list:
            continue  # helper route with no via — skip
        method = r["method"]
        np = norm_params(r["path_template"])
        if f"{method} {np}" not in op_by:
            continue  # no spec op for this route — coverage finding, not a bug
        winner = wire_winner.get(f"{method} {wire_key(r['path_template'])}")
        if winner is None:
            continue
        op_id = winner[1]
        spec = op_id[: op_id.index(".")]
        rows.append(
            {
                "method": method,
                "path": np,
                "op_id": op_id,
                "via": via_list[0],
                "spec": spec,
            }
        )
    return rows


# ---------------------------------------------------------------------------
# 3. Emit — one t/rest/generated/<spec>_generated.t per spec namespace.
# ---------------------------------------------------------------------------


def slug(via: str) -> str:
    """The resource.method tail of the via, slugified — stable for GEN-FRESH.

    e.g. video.rooms.list_streams → rooms_list_streams; calling.calling.dial →
    calling_dial. Non-alnum → '_', trailing '_' trimmed. Used to name the
    subtest.
    """
    tail = via[via.index(".") + 1 :] if "." in via else via
    return re.sub(r"_+$", "", re.sub(r"[^A-Za-z0-9]+", "_", tail))


def call_expr(plan_entry: dict) -> str:
    """The literal Perl call `$client->ns->res->member(args)`."""
    chain = "->".join(plan_entry["chain"])
    args = ", ".join(plan_entry["args"])
    call = f"$client->{chain}->{plan_entry['member']}"
    return f"{call}({args})" if args else f"{call}()"


HEADER_TMPL = """#!/usr/bin/env perl
# Code generated by scripts/generate_rest_tests.py; DO NOT EDIT.
#
# AUTO-GENERATED full-mock REST wire tests for the '{spec}' namespace — regenerate:
#   python3 scripts/generate_rest_tests.py
#
# Each route the SDK implements (captured from the real client by
# scripts/route_registry.pl + scripts/rest_test_plan.pl, joined to the spec
# operationId) gets a SUCCESS test (call it, assert method + matched_route on the
# mock journal) and an ERROR test (arm a 500, assert
# SignalWire::REST::HttpClient::Error with ->status_code == 500). The assertion
# oracle is the spec operationId — independent of the resource generator — so
# these catch SDK-vs-contract drift, not a generator self-snapshot. Full-mock
# harness (MockTest against porting-sdk mock_signalwire).
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";
use Test::More;
use MockTest;

"""


def emit_spec_file(spec: str, rows: list[dict]) -> str:
    body = HEADER_TMPL.format(spec=spec)
    for r in rows:
        name = r["_name"]
        call = r["_call"]
        method = r["method"]
        op_id = r["op_id"]
        body += f"""subtest '{name}_success' => sub {{
    my $client = MockTest::client();
    {call};
    my $last = MockTest::journal_last();
    is($last->{{method}}, '{method}', 'method {method}');
    is($last->{{matched_route}}, '{op_id}', 'matched_route {op_id}');
}};

subtest '{name}_error' => sub {{
    my $client = MockTest::client();
    MockTest::scenario_set('{op_id}', 500, {{ error => 'x' }});
    my $ok = eval {{ {call}; 1 }};
    ok(!$ok, 'call raised');
    my $e = $@;
    isa_ok($e, 'SignalWire::REST::HttpClient::Error');
    is($e->status_code, 500, 'status 500');
    is(MockTest::journal_last()->{{matched_route}}, '{op_id}', 'matched_route {op_id}');
}};

"""
    body += "done_testing();\n"
    return body


# ---------------------------------------------------------------------------
# Driver.
# ---------------------------------------------------------------------------


def build_outputs(psdk: Path) -> tuple[dict[str, str], list[str], int]:
    """Return ({filename: source}, uncovered_vias, n_routes_covered)."""
    routes = load_routes()
    plan = load_plan()
    spec_dirs = spec_dirs_with_openapi(psdk)
    rows = build_join(routes, psdk, spec_dirs)

    by_spec: dict[str, list[dict]] = {}
    uncovered: list[str] = []
    covered_vias: set[str] = set()

    for row in rows:
        via = row["via"]
        entry = plan.get(via)
        if entry is None:
            uncovered.append(f"{via} ({row['method']} {row['path']})")
            continue
        row = dict(row)
        row["_call"] = call_expr(entry)
        row["_slug"] = slug(via)
        by_spec.setdefault(row["spec"], []).append(row)
        covered_vias.add(via)

    outs: dict[str, str] = {}
    for spec in sorted(by_spec):
        srows = by_spec[spec]
        # Deterministic ordering: sort by (via + method).
        srows.sort(key=lambda r: r["via"] + r["method"])
        # Ensure unique subtest names within the file.
        used: set[str] = set()
        for r in srows:
            name = r["_slug"]
            base = name
            k = 2
            while name in used:
                name = f"{base}_{k}"
                k += 1
            used.add(name)
            r["_name"] = name
        fn = f"{spec.replace('-', '_')}_generated.t"
        outs[fn] = emit_spec_file(spec, srows)

    return outs, uncovered, len(covered_vias)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--check", action="store_true", help="GEN-FRESH: exit non-zero if stale"
    )
    ap.add_argument("--out", default="", help="scratch: emit into this dir")
    args = ap.parse_args(argv)

    psdk = resolve_porting_sdk()
    outs, uncovered, n_covered = build_outputs(psdk)

    out_dir = Path(args.out) if args.out else (repo_root() / "t" / "rest" / "generated")

    if uncovered:
        sys.stderr.write(
            f"\nUNCOVERED ({len(uncovered)} joined route(s) with no reflectable via plan):\n"
        )
        for u in uncovered:
            sys.stderr.write(f"  - {u}\n")

    if args.check:
        stale = []
        for fn, src in outs.items():
            p = out_dir / fn
            if not p.is_file() or p.read_text() != src:
                stale.append(str(p))
        expected = set(outs.keys())
        if out_dir.is_dir():
            stale.extend(
                f"{p} (leftover — not in generator output)"
                for p in sorted(out_dir.glob("*_generated.t"))
                if p.name not in expected
            )
        if stale:
            sys.stderr.write(
                f"GEN-FRESH FAIL: {len(stale)} generated REST test file(s) stale:\n"
            )
            for s in stale:
                sys.stderr.write(f"  - {s}\n")
            return 1
        total = sum(src.count("subtest '") for src in outs.values())
        print(
            f"GEN-FRESH: {len(outs)} generated REST test file(s) up to date "
            f"({total} subtests, {n_covered} routes)."
        )
        return 0

    out_dir.mkdir(parents=True, exist_ok=True)
    # Remove any stale files no longer emitted.
    expected = set(outs.keys())
    for p in sorted(out_dir.glob("*_generated.t")):
        if p.name not in expected:
            p.unlink()
    for fn, src in outs.items():
        (out_dir / fn).write_text(src)
    total = sum(src.count("subtest '") for src in outs.values())
    print(
        f"generated {len(outs)} REST test file(s) into {out_dir} "
        f"({total} subtests across {len(outs)} namespaces, {n_covered} routes covered)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
