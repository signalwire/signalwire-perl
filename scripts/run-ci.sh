#!/usr/bin/env bash
# run-ci.sh — canonical local-and-CI gate runner for signalwire-perl.
#
# Same script invoked locally (`bash scripts/run-ci.sh`) AND by the
# GitHub Actions workflow. No drift between local and CI behavior.
#
# The FMT / LINT / TEST gates are the ONLY canonical entry points
# scripts/run-format.sh · scripts/run-lint.sh · scripts/run-tests.sh — each
# self-bootstraps its tool environment (scripts/_env.sh) and runs from any CWD.
#
# GATE SCHEDULING (porting-sdk/scripts/gate_scheduler.sh — CI_PERF S1 + S2):
#   Gates run CONCURRENTLY up to a cap (SW_CI_JOBS, default nproc), scheduled by
#   their DATA dependencies:
#     * S2 concurrent wave: the pure-Python side-effect-free suites/gates overlap —
#       they share no mutable state.
#     * S1 fail-fast: heavy gates (TEST, LINT, FMT, and the BEHAVIORAL/GEN/PACKAGE
#       suites) are deferred behind the cheap wave, so a trivial cheap-gate failure
#       surfaces in seconds; --fail-fast aborts the run before TEST starts.
#   HARD ordering is data-dependency ONLY:
#     * The SIGNATURES→DRIFT→SEMVER data dep + the SURFACE-FRESH regenerate-then-
#       restore now live INSIDE the SURFACE suite (enumerate-once, diff-many).
#     * The SURFACE suite regenerates port_surface.json in place (and restores it),
#       DOC-TRUTH's DOC-AUDIT reads it, STATUS-CLAIM reads it, FMT rewrites
#       lib/**/*.pm in place, and TEST loads lib/ + reads port_surface.json → all
#       share res=surface (the working-tree-mutation group) so no reader ever sees
#       a half-written file.
#   The shared _env.sh env (PERL5LIB / PATH / PERLTIDY) is exported before the gates
#   are registered, so every scheduler worker subshell inherits it.
#   Per-gate PASS/FAIL + the FAILED_GATES tally preserved exactly; each gate's output
#   captured + replayed atomically.
#
# Flags:
#   --fail-fast   stop launching new gates at the first failure (local dev loop).
#
# GATE-INVENTORY NOTE: porting-sdk/GATE_INVENTORY.md is GENERATED (by
# gen_gate_inventory.py) from the REFERENCE port's run-ci.sh (signalwire-typescript),
# NOT from this file. This perl run-ci intentionally deviates from that inventory in a
# few port-specific ways, each documented at its gate below: the RELAY behavioral rule
# keeps perl's hyphen spelling BEHAVIORAL-WIRE-RELAY; the SURFACE suite does NOT carry
# ROUTE-COLLISION (route_collision.py is not yet spec-aware for perl's spec-faithful
# ROUTE-SPLIT ×2 — see the SURFACE gate note); and the doc suite is POD-aware (perl's
# reference docs are POD-first). A deviation here is not inventory drift — it is a
# per-port idiom/disposition recorded in place. Load-bearing env/mode lines are
# additionally guarded by the WIRED-MODES gate (WIRED_MODES.md).

set -u
set -o pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PORT_ROOT/.sw-tmp"  # repo-local CI scratch (never /tmp)
PORT_NAME="signalwire-perl"

resolve_porting_sdk() {
    if [ -n "${PORTING_SDK:-}" ] && [ -d "$PORTING_SDK/scripts" ]; then
        echo "$PORTING_SDK"
        return 0
    fi
    if [ -d "$PORT_ROOT/../porting-sdk/scripts" ]; then
        (cd "$PORT_ROOT/../porting-sdk" && pwd)
        return 0
    fi
    return 1
}

PORTING_SDK_DIR="$(resolve_porting_sdk)" || {
    echo "FATAL: porting-sdk not found, clone it adjacent to this repo" >&2
    echo "       (expected $PORT_ROOT/../porting-sdk or \$PORTING_SDK env var)" >&2
    exit 2
}

# signalwire-python (the behavioral ORACLE source) — same adjacency convention the
# EMISSION differ's _resolve_python_sdk() uses: the cross-port CI workflow checks it
# out as a *sibling of porting-sdk in the workspace*, not under ~/src. Resolve it
# here and pass it explicitly to the Layer-D BEHAVIORAL-* differs so the gate never
# depends on the caller's CWD or a ~/src fallback (which is absent in CI).
resolve_python_sdk() {
    if [ -n "${PYTHON_SDK:-}" ] && [ -d "$PYTHON_SDK/signalwire" ]; then
        echo "$PYTHON_SDK"; return 0
    fi
    if [ -d "$PORTING_SDK_DIR/../signalwire-python/signalwire" ]; then
        (cd "$PORTING_SDK_DIR/../signalwire-python" && pwd); return 0
    fi
    if [ -d "$HOME/src/signalwire-python/signalwire" ]; then
        echo "$HOME/src/signalwire-python"; return 0
    fi
    return 1
}
PYTHON_SDK_DIR="$(resolve_python_sdk)" || {
    echo "FATAL: signalwire-python (behavioral oracle) not found" >&2
    echo "       (expected sibling of porting-sdk, or \$PYTHON_SDK env var)" >&2
    exit 2
}

# shellcheck source=/dev/null
source "$PORTING_SDK_DIR/scripts/gate_scheduler.sh"

cd "$PORT_ROOT"

# Tool-environment bootstrap now lives in ONE place — scripts/_env.sh — sourced
# here AND by scripts/run-format.sh / run-lint.sh / run-tests.sh, so the FMT /
# LINT / TEST gates behave identically whether run by this script or standalone
# from any CWD. It prepends the local::lib to PERL5LIB / PATH, pins PERLTIDY, and
# defines _sw_ensure_perl_tools + _sw_perl_source_files. Guarded + $HOME-keyed, so
# CI (deps on the system perl) is unaffected. These EXPORTED vars are inherited by
# every scheduler worker subshell.
# shellcheck source=scripts/_env.sh
source "$PORT_ROOT/scripts/_env.sh"
# Bootstrap the FMT/LINT/TEST dev-deps up-front so the GEN suite (which shells out to
# perltidy) and every gate below have them. Fail loud if they can't be resolved.
_sw_ensure_perl_tools || exit 1

# GATE-ENFORCEMENT: perl's Wave-A findings are BLOCKING, not report-only. The
# widened doc/POD perimeter + real-count checks (audit_docs, count_claim,
# status_claim, semver_diff, …) fail the gate on any finding. The full red list was
# burned to zero before this flip; a NEW Wave-A violation now turns CI red at PR
# time. (Exported so every scheduler worker subshell inherits it.)
export SW_WAVE_A_REPORT_ONLY=0

# STRICT-MOCKS (D3): the REST mock (mock_signalwire) 400s any wire violation
# (unknown body key, malformed value) by DEFAULT instead of silently journaling
# it — so a wrong wire key surfaces LOUD at PR time (in the TEST gate's own mock
# and any test/gate that spawns one), not just in the REST-COVERAGE journal
# post-pass. `:-1` keeps it a DEFAULT a caller can still override to 0 for a
# deliberate non-strict repro. Exported so every scheduler worker subshell (and
# every mock they spawn) inherits it. This is a WIRED MODE — see WIRED_MODES.md;
# check_wired_modes.py fails the gate if this line is ever silently dropped.
export MOCK_SIGNALWIRE_STRICT="${MOCK_SIGNALWIRE_STRICT:-1}"

echo "==> running CI gates for $PORT_NAME (porting-sdk at $PORTING_SDK_DIR)"

# ---- Part 5: the per-gate --fn helpers are now DEAD — reproduced in the suites -
# surface_fresh_gate (SURFACE-FRESH), rest_coverage_gate (REST-COVERAGE),
# spec_parity_gate (SPEC-PARITY), and dayone_artifact_deny (ARTIFACT-DENY) used to
# be defined here as `--fn` gate bodies. Those exact bodies — including the perl
# specifics (Makefile.PL + make manifest → MANIFEST, prove -Ilib -It/lib t/rest/,
# route_registry.pl capture, the MANIFEST restore + MakeMaker byproduct sweep) —
# are now reproduced INSIDE the Part-5 suites (scripts/suites/_surface_fresh.py,
# _rest_coverage.py, _spec_parity.py, _artifact_deny.py). pick_free_port() likewise
# moved into the suites. (Byte-identity vs the old per-gate path is proven by
# porting-sdk's tests/test_suite_parity*.py.)

# ---- register gates ----------------------------------------------------------
sched_init "$@"

# HEAVY (deferred behind the cheap wave for S1 fail-fast). TEST joins res=surface —
# the working-tree-mutation group. FMT rewrites lib/**/*.pm in place via `perltidy
# -b` when run locally; the SURFACE suite rewrites port_surface.json in place then
# restores it. TEST `perl -c`-compiles every bundled example and loads every SDK
# module for its 130+ test files, and t/53/t/54 additionally read port_surface.json
# — so overlapping TEST with a gate mid-rewrite makes a module/surface file load a
# transient/half-written copy and fail nondeterministically. Sharing the surface
# resource serializes TEST against those mutators; it still overlaps every read-only
# gate (LINT, the differ suites in check mode).
sched_gate TEST defer=1 res=surface desc="run-tests.sh (prove -Ilib -It/lib -r t/)" \
    -- bash scripts/run-tests.sh

# ---- Part 5 gate SUITES ------------------------------------------------------
# The former per-gate SIGNATURES/DRIFT/SURFACE-*/SEMVER-DIFF/GEN-TYPE-DEGENERACY/
# GEN-IDIOM/GEN-FRESH*/BEHAVIORAL-*/EMISSION/ERROR-ENVELOPE/PAGINATION-WIRED/
# DOC-WIRE/REST-COVERAGE/SPEC-PARITY/SKILL-CONTRACT/SWAIG-*/WAIT-LIVENESS/DOC-*/
# COUNT-CLAIM/ACCESSOR-TRUTH/STATUS-CLAIM/README-INCLUDE/*-LEDGER/PACKAGE-SMOKE/
# META-CONSISTENT/ARTIFACT-DENY/RELEASE-FRESH gates now run under 6 SUITE engines.
# Each suite emits every original gate NAME as a `[SUITE:RULE] ... PASS/FAIL` rule
# ID (failure identity + allowlists + finding output unchanged). A suite exits
# nonzero iff any of its rules fails. Byte-identity vs the old per-gate path is
# proven by porting-sdk/tests/test_suite_parity*.py.
#
# The `--fn` helpers the old gates used (surface_fresh_gate, rest_coverage_gate,
# spec_parity_gate, dayone_artifact_deny, pick_free_port) are reproduced INSIDE the
# suites, so they are no longer defined here.
#
# Former single-gate scheduler features preserved by the suites internally:
#   * SIGNATURES→DRIFT ordering, the SEMVER-DIFF-reads-SIGNATURES data dep, and the
#     SURFACE-FRESH regenerate-then-restore all live inside the SURFACE suite.
#   * mixed tiers are split with --rules: PACKAGE + BEHAVIORAL each schedule a
#     per-PR line and a nightly line (nightly members broken out below).
# PERL-SPECIFIC vs the TS reference: perl's behavioral RELAY rule keeps perl's exact
# spelling BEHAVIORAL-WIRE-RELAY (hyphen, same as ts). ROUTE-COLLISION runs as a
# standalone gate (scripts/route_collision.sh) rather than inside the SURFACE suite —
# it feeds perl's route_registry.pl to porting-sdk's now-SPEC-AWARE route_collision.py
# (a ROUTE-SPLIT is a finding ONLY when the dispatched path diverges from the spec
# path for the method's operationId). perl's 2 splits (callFlows/conferenceRooms
# list_addresses under the singular call_flow/conference_room sub-paths) are
# spec-faithful platform routing (fabric/openapi.yaml x-sdk mounts), so the gate is
# clean with NO allowlist. DOC-AUDIT + STATUS-CLAIM read perl's on-disk
# port_surface.json (POD-aware), which the SURFACE suite regenerates+restores — so
# SURFACE, DOC-TRUTH, and ROUTE-COLLISION share res=surface.

# SURFACE (parity spine): SIGNATURES→DRIFT ordered, SURFACE-FRESH regen/restore,
# SURFACE-DIFF, SEMVER-DIFF, GEN-TYPE-DEGENERACY, GEN-IDIOM — all read the one
# enumeration. res=surface: SURFACE-FRESH regenerates port_surface.json in place
# (and restores it), so it must not overlap DOC-TRUTH's DOC-AUDIT/STATUS-CLAIM read.
sched_gate SURFACE res=surface desc="surface parity suite (SIGNATURES/DRIFT/SURFACE-FRESH/SURFACE-DIFF/SEMVER-DIFF/GEN-TYPE-DEGENERACY/GEN-IDIOM)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/surface.py" --port perl --repo "$PORT_ROOT"

# ROUTE-COLLISION (spec-aware): build perl's route_registry.pl → feed the SPEC-AWARE
# route_collision.py (a split is a finding only when the dispatched path diverges from
# the spec path for the method's operationId). perl's 2 callFlows/conferenceRooms
# splits are spec-faithful (fabric x-sdk mounts) → clean with NO allowlist. res=surface
# because it reads port_surface.json (must not overlap the SURFACE suite's regen).
sched_gate ROUTE-COLLISION res=surface desc="no split routes / duplicate CRUD bases (spec-aware; fed by route_registry.pl)" \
    -- bash scripts/route_collision.sh

# GEN (regen-from-specs family): the 5 GEN-FRESH rules. The perltidy backstop each
# generator runs needs _env.sh (sourced above, exported into every worker subshell).
sched_gate GEN defer=1 desc="generated-code freshness suite (GEN-FRESH/-TESTS/-RELAY/-SWAIG/-SWML)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/gen.py" --port perl --repo "$PORT_ROOT"

# BEHAVIORAL (one Layer-D pass per rule): the per-PR rules. WAIT-LIVENESS (nightly)
# is the separate line below. NOTE perl's hyphen spelling BEHAVIORAL-WIRE-RELAY.
sched_gate BEHAVIORAL defer=1 desc="behavioral suite (BEHAVIORAL-*/EMISSION/ERROR-ENVELOPE/PAGINATION-WIRED/DOC-WIRE/REST-COVERAGE/SPEC-PARITY/SKILL-CONTRACT/SWAIG-COVERAGE/SWAIG-CLI)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/behavioral.py" --port perl --repo "$PORT_ROOT" \
        --rules BEHAVIORAL-WIRE,BEHAVIORAL-SWML,BEHAVIORAL-STATE,BEHAVIORAL-HTTP,BEHAVIORAL-WIRE-RELAY,EMISSION,ERROR-ENVELOPE,PAGINATION-WIRED,DOC-WIRE,REST-COVERAGE,SPEC-PARITY,SKILL-CONTRACT,SWAIG-COVERAGE,SWAIG-CLI

sched_gate BEHAVIORAL-NIGHTLY tier=nightly defer=1 desc="behavioral suite, nightly rules (WAIT-LIVENESS)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/behavioral.py" --port perl --repo "$PORT_ROOT" \
        --rules WAIT-LIVENESS

# DOC-TRUTH (one markdown+POD walk): DOC-AUDIT/DOC-LINKS/DOC-LANG-PURITY/DOC-ENV/
# COUNT-CLAIM/ACCESSOR-TRUTH/STATUS-CLAIM/README-INCLUDE. POD-aware (perl's docs are
# POD-first). res=surface: DOC-AUDIT + STATUS-CLAIM read perl's on-disk
# port_surface.json, which the SURFACE suite regenerates+restores.
sched_gate DOC-TRUTH res=surface desc="doc-truth suite (DOC-AUDIT/DOC-LINKS/DOC-LANG-PURITY/DOC-ENV/COUNT-CLAIM/ACCESSOR-TRUTH/STATUS-CLAIM/README-INCLUDE)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/doc_truth.py" --port perl --repo "$PORT_ROOT"

# LEDGER: SUPPRESSION-LEDGER + IGNORE-LEDGER-VERIFY.
sched_gate LEDGER res=dayone desc="ledger governance suite (SUPPRESSION-LEDGER/IGNORE-LEDGER-VERIFY)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/ledger.py" --port perl --repo "$PORT_ROOT"

# PACKAGE: per-PR rules (ARTIFACT-DENY/RELEASE-FRESH); nightly rules (PACKAGE-SMOKE/
# META-CONSISTENT) on the separate line below. ARTIFACT-DENY reproduces perl's
# Makefile.PL + make manifest → MANIFEST listing + restore/sweep inside the suite.
sched_gate PACKAGE res=dayone desc="package suite, per-PR rules (ARTIFACT-DENY/RELEASE-FRESH)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/package.py" --port perl --repo "$PORT_ROOT" \
        --rules ARTIFACT-DENY,RELEASE-FRESH

sched_gate PACKAGE-NIGHTLY tier=nightly defer=1 res=dayone desc="package suite, nightly rules (PACKAGE-SMOKE/META-CONSISTENT)" \
    -- python3 "$PORTING_SDK_DIR/scripts/suites/package.py" --port perl --repo "$PORT_ROOT" \
        --rules PACKAGE-SMOKE,META-CONSISTENT

# ---- gates that stay standalone (native toolchains + singletons) -------------
sched_gate NO-CHEAT desc="audit_no_cheat_tests" \
    -- python3 "$PORTING_SDK_DIR/scripts/audit_no_cheat_tests.py" --root "$PORT_ROOT"

# FMT joins res=surface: run locally (no CI) it rewrites lib/**/*.pm in place via
# `perltidy -b`, which a concurrent TEST (`perl -c` / module load) or the surface
# enumerator (loads lib/) would otherwise read mid-write. Under CI (--check) it's
# read-only, but the label is harmless there and keeps local and CI scheduling
# identical.
sched_gate FMT defer=1 res=surface desc="run-format.sh (local: apply; CI: --check)" \
    -- bash scripts/run-format.sh ${CI:+--check}

# LINT joins res=surface too: run locally, FMT's `perltidy -b` rewrites lib/**/*.pm
# in place, and perlcritic (run-lint.sh) reads those same files — a concurrent
# perlcritic reading a file mid-rewrite parse-fails and reds LINT spuriously. Sharing
# the surface resource serializes LINT against the FMT/SURFACE/TEST mutators while it
# still overlaps every read-only gate. (Under CI --check FMT is read-only, but the
# label keeps local and CI scheduling identical.)
sched_gate LINT defer=1 res=surface desc="run-lint.sh (perlcritic severity 4, zero findings)" \
    -- bash scripts/run-lint.sh

# ---- §C1 doc/example/CLI execution gates ------------------------------------
# SNIPPET-COMPILE (documented code fences compile with lib/ on @INC) is HEAVY →
# tier=nightly; DOC-CLI stays per-PR (cheap CLI-parse probe of documented swaig-test
# invocations). EXAMPLES-RUN + SNIPPET-RUN execute/load the shipped examples + doc
# snippets under STRICT-MOCKS on the nightly tier (MOCK_RELAY_STRICT=1: the mock_relay
# REJECTS any inbound frame that violates the RELAY wire spec, so a wrong frame fails
# LOUD instead of being silently journaled). `env VAR=val` (not a bare prefix) keeps
# the command analyzable to the permission matcher.
sched_gate SNIPPET-COMPILE tier=nightly desc="documented code snippets compile (perl -c with lib/ on @INC)" \
    -- python3 "$PORTING_SDK_DIR/scripts/snippet_compile.py" --port perl --repo .

sched_gate DOC-CLI desc="documented swaig-test invocations parse against the real CLI" \
    -- python3 "$PORTING_SDK_DIR/scripts/doc_cli.py" --port perl --repo .

# DEAD-PUBLIC-ERROR stays standalone (source analysis of exported error types — not
# a doc-truth/behavioral rule). ERROR-ENVELOPE/PAGINATION-WIRED/DOC-WIRE run under
# the BEHAVIORAL suite; DOC-ENV/COUNT-CLAIM/ACCESSOR-TRUTH/STATUS-CLAIM under
# DOC-TRUTH.
sched_gate DEAD-PUBLIC-ERROR desc="exported error types are raised/caught/user-signalled (no dead error surface)" \
    -- python3 "$PORTING_SDK_DIR/scripts/dead_public_error.py" --port perl --repo "$PORT_ROOT"

sched_gate EXAMPLES-RUN tier=nightly defer=1 desc="shipped examples load/start against the mock (modulo EXAMPLES_RUN_ALLOW.md; STRICT-MOCKS: MOCK_RELAY_STRICT=1)" \
    -- env MOCK_RELAY_STRICT=1 python3 "$PORTING_SDK_DIR/scripts/examples_run.py" --port perl --repo .

sched_gate SNIPPET-RUN tier=nightly defer=1 desc="dynamic-port doc snippets run to a zero exit against the mock (STRICT-MOCKS: MOCK_RELAY_STRICT=1)" \
    -- env MOCK_RELAY_STRICT=1 python3 "$PORTING_SDK_DIR/scripts/snippet_run.py" --port perl --repo .

# ROOT-HYGIENE + PUBLIC-JARGON stay standalone (source/root analysis, not a suite
# family).
sched_gate ROOT-HYGIENE res=dayone desc="no audit/scratch clutter tracked at repo root (allowlist ROOT_HYGIENE_ALLOW.md)" \
    -- python3 "$PORTING_SDK_DIR/scripts/root_hygiene.py" --port perl --repo .

sched_gate PUBLIC-JARGON res=dayone desc="no porting/internal jargon leaked into the public surface" \
    -- python3 "$PORTING_SDK_DIR/scripts/public_jargon.py" --port perl --repo .

# WIRED-MODES (Part 1.6 / D7): the merge-coherence guard — greps this run-ci.sh for
# every load-bearing env/mode line declared in WIRED_MODES.md (strict-mocks exports)
# and fails loud if a merge ever silently drops one, so a wired mode can't vanish and
# leave a gate green-but-vacuous.
sched_gate WIRED-MODES desc="load-bearing run-ci modes (WIRED_MODES.md) all present" \
    -- python3 "$PORTING_SDK_DIR/scripts/check_wired_modes.py" --port perl --repo .

# ---- summary ----------------------------------------------------------------

sched_run
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "==> CI PASS"
else
    echo "==> CI FAIL (gates:$FAILED_GATES )"
fi
exit "$rc"
