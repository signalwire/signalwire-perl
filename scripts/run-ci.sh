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
#     * S2 concurrent wave: the pure-Python side-effect-free gates (all GEN-FRESH*,
#       DRIFT, NO-CHEAT, EMISSION, SKILL-CONTRACT, SWAIG-COVERAGE, SURFACE-DIFF,
#       DOC-AUDIT, SWAIG-CLI) overlap — they share no mutable state.
#     * S1 fail-fast: heavy gates (TEST, LINT, FMT, REST-COVERAGE, SPEC-PARITY) are
#       deferred behind the cheap wave, so a trivial cheap-gate failure surfaces in
#       seconds; --fail-fast aborts the run before TEST starts.
#   HARD ordering is data-dependency ONLY:
#     * DRIFT reads port_signatures.json that SIGNATURES writes → deps=SIGNATURES.
#     * SURFACE-FRESH + SURFACE-DIFF regenerate port_surface.json in place (and
#       restore it), DOC-AUDIT reads it, FMT rewrites lib/**/*.pm in place, and TEST
#       loads lib/ + reads port_surface.json → all five share res=surface (the
#       working-tree-mutation group) so no reader ever sees a half-written file.
#   The shared _env.sh env (PERL5LIB / PATH / PERLTIDY) is exported before the gates
#   are registered, so every scheduler worker subshell inherits it.
#   Per-gate PASS/FAIL + the FAILED_GATES tally preserved exactly; each gate's output
#   captured + replayed atomically.
#
# Flags:
#   --fail-fast   stop launching new gates at the first failure (local dev loop).

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
# Bootstrap the FMT/LINT/TEST dev-deps up-front so GEN-FRESH (which shells out to
# perltidy) and every gate below have them. Fail loud if they can't be resolved.
_sw_ensure_perl_tools || exit 1

echo "==> running CI gates for $PORT_NAME (porting-sdk at $PORTING_SDK_DIR)"

pick_free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

# ARTIFACT-DENY (Day-one) — no porting-process artifact may ship inside the PUBLISHED
# package. MANIFEST is the authoritative published listing: `make manifest` regenerates
# it modulo MANIFEST.SKIP (which already excludes port_*.json, PORT_*.md, CHECKLIST.md,
# audit_coverage*, tidy.err, .sw-tmp/, etc.), so feeding MANIFEST to --listing checks the
# REAL shipped set (not the git-ls-files proxy). Restore the committed MANIFEST after —
# `make manifest` rewrites it and would otherwise dirty the tree.
dayone_artifact_deny() {
    perl Makefile.PL >/dev/null 2>&1 || { echo "Makefile.PL failed" >&2; return 1; }
    make manifest >/dev/null 2>&1 || { echo "make manifest failed" >&2; return 1; }
    python3 "$PORTING_SDK_DIR/scripts/artifact_deny.py" --port perl --listing - <MANIFEST
    local rc=$?
    # Restore the committed MANIFEST and sweep the ExtUtils::MakeMaker byproducts
    # (all .gitignore'd, but leave no scratch behind per the repo cleanup rule).
    git checkout -- MANIFEST 2>/dev/null || true
    rm -f MANIFEST.bak MYMETA.json MYMETA.yml Makefile Makefile.old pm_to_blib
    return $rc
}

# SURFACE-FRESH — Layer B (the symbol-level surface) is NOT gated by DRIFT (Layer A
# / signatures only), so port_surface.json can silently rot. Regenerate it IN PLACE
# via the Perl surface enumerator, compare the committed copy modulo the volatile
# generated_from git-sha, then always restore the working copy.
surface_fresh_gate() {
    if ! git show HEAD:port_surface.json > "$PORT_ROOT/.sw-tmp/committed_surface.json" 2>/dev/null; then
        cp "$PORT_ROOT/port_surface.json" "$PORT_ROOT/.sw-tmp/committed_surface.json"
    fi
    perl scripts/enumerate_surface.pl >/dev/null || return $?
    python3 "$PORTING_SDK_DIR/scripts/check_surface_freshness.py" \
        --committed "$PORT_ROOT/.sw-tmp/committed_surface.json" \
        --fresh "$PORT_ROOT/port_surface.json"
    local rc=$?
    git checkout -- port_surface.json 2>/dev/null
    return $rc
}

# REST-COVERAGE — every implemented REST route covered success+error. Self-
# contained: spins its own mock, runs t/rest/ serially, replays the journal.
rest_coverage_gate() {
    local port
    port="$(pick_free_port)" || { echo "could not allocate a free port" >&2; return 1; }
    local mock_pkg_parent="$PORTING_SDK_DIR/test_harness/mock_signalwire"
    export PYTHONPATH="$mock_pkg_parent${PYTHONPATH:+:$PYTHONPATH}"
    python3 -m mock_signalwire --host 127.0.0.1 --port "$port" --log-level error \
        >"$PORT_ROOT/.sw-tmp/rest_cov_mock_perl.$$.log" 2>&1 &
    local mock_pid=$!
    # shellcheck disable=SC2064
    trap "kill $mock_pid 2>/dev/null" RETURN
    local i ready=0
    for i in $(seq 1 60); do
        if ! kill -0 "$mock_pid" 2>/dev/null; then
            echo "mock_signalwire died on port $port — log:" >&2
            cat "$PORT_ROOT/.sw-tmp/rest_cov_mock_perl.$$.log" >&2
            return 1
        fi
        if python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$port/__mock__/health',timeout=1)" 2>/dev/null; then
            ready=1
            break
        fi
        sleep 0.5
    done
    if [ "$ready" -ne 1 ]; then
        echo "mock_signalwire on port $port not healthy within 30s" >&2
        return 1
    fi
    python3 -c "import urllib.request; urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:$port/__mock__/journal/reset',method='POST'),timeout=5).read()"
    MOCK_SIGNALWIRE_PORT="$port" prove -Ilib -It/lib -j1 -r t/rest/ || return 1
    python3 -m mock_signalwire.rest_coverage \
        --mock-url "http://127.0.0.1:$port" \
        --spec-root "$PORTING_SDK_DIR/rest-apis" \
        --allowlist "$PORTING_SDK_DIR/REST_COVERAGE_BASELINE.md" \
        --allowlist "$PORT_ROOT/REST_COVERAGE_GAPS.md" \
        --gap-baseline "$PORTING_SDK_DIR/REST_COVERAGE_GAP_BASELINE.md"
}

# SPEC-PARITY — implemented routes == canonical spec. route_registry.pl drives the
# live RestClient through a recording HttpClient and captures every dispatched route.
spec_parity_gate() {
    local mock_pkg_parent="$PORTING_SDK_DIR/test_harness/mock_signalwire"
    export PYTHONPATH="$mock_pkg_parent${PYTHONPATH:+:$PYTHONPATH}"
    local registry
    registry="$(mktemp)"
    perl -Ilib scripts/route_registry.pl >"$registry" 2>/dev/null || {
        rm -f "$registry"
        return 1
    }
    python3 "$PORTING_SDK_DIR/scripts/diff_spec_implementation.py" \
        --registry-json "$registry" \
        --gaps "$PORTING_SDK_DIR/SPEC_IMPLEMENTATION_GAPS.md"
    local rc=$?
    rm -f "$registry"
    return $rc
}

# SURFACE-DIFF — diff the port's public surface against the Python reference.
# Regenerate the surface in place, diff, restore unconditionally.
surface_diff_gate() {
    local committed="$PORT_ROOT/.sw-tmp/committed_surface_diff_${PORT_NAME}.$$"
    git show HEAD:port_surface.json >"$committed" 2>/dev/null \
        || cp port_surface.json "$committed"
    perl scripts/enumerate_surface.pl --output port_surface.json
    local regen_rc=$?
    if [ "$regen_rc" -ne 0 ]; then
        git checkout -- port_surface.json 2>/dev/null || true
        rm -f "$committed"
        echo "surface regen failed (exit $regen_rc)" >&2
        return "$regen_rc"
    fi
    python3 "$PORTING_SDK_DIR/scripts/diff_port_surface.py" \
        --reference "$PORTING_SDK_DIR/python_surface.json" \
        --port-surface port_surface.json \
        --omissions "$PORT_ROOT/PORT_OMISSIONS.md" \
        --additions "$PORT_ROOT/PORT_ADDITIONS.md"
    local rc=$?
    git checkout -- port_surface.json 2>/dev/null || true
    rm -f "$committed"
    return $rc
}

# ---- register gates ----------------------------------------------------------
sched_init "$@"

sched_gate GEN-FRESH desc="generate_rest.py --check (generated REST layer matches specs)" \
    -- python3 scripts/generate_rest.py --check

sched_gate GEN-FRESH-SWML desc="generate_swml_verbs.py --check (generated SWML-verb types match schema.json)" \
    -- python3 scripts/generate_swml_verbs.py --check

sched_gate GEN-FRESH-RELAY desc="generate_relay_protocol.py --check (generated RELAY types match relay-protocol)" \
    -- python3 scripts/generate_relay_protocol.py --check

sched_gate GEN-FRESH-SWAIG desc="generate_swaig_payloads.py --check (generated SWAIG payloads match swaig-specs)" \
    -- python3 scripts/generate_swaig_payloads.py --check

sched_gate GEN-FRESH-TESTS desc="generate_rest_tests.py --check (generated REST wire-test suite matches route-registry × spec oracle)" \
    -- python3 scripts/generate_rest_tests.py --check

# TEST joins res=surface — the working-tree-mutation group. FMT rewrites lib/**/*.pm
# in place via `perltidy -b` when run locally; SURFACE-FRESH / SURFACE-DIFF rewrite
# port_surface.json in place then `git checkout --` restore it. TEST `perl -c`-compiles
# every bundled example and loads every SDK module for its 130+ test files, and
# t/53/t/54 additionally read port_surface.json — so overlapping TEST with a gate
# mid-rewrite makes a module/surface file load a transient/half-written copy and fail
# nondeterministically (the moving `example parses:` / surface-audit failures). Sharing
# the surface resource serializes TEST against those mutators; it still overlaps every
# read-only gate (LINT, the differs, generators-in-check-mode).
sched_gate TEST defer=1 res=surface desc="run-tests.sh (prove -Ilib -It/lib -r t/)" \
    -- bash scripts/run-tests.sh

sched_gate SIGNATURES desc="regenerate port_signatures.json" \
    -- python3 scripts/enumerate_signatures.py

sched_gate DRIFT deps=SIGNATURES desc="diff_port_signatures vs python reference" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_port_signatures.py" \
        --reference "$PORTING_SDK_DIR/python_signatures.json" \
        --port-signatures "$PORT_ROOT/port_signatures.json" \
        --surface-omissions "$PORT_ROOT/PORT_OMISSIONS.md" \
        --surface-additions "$PORT_ROOT/PORT_ADDITIONS.md" \
        --omissions "$PORT_ROOT/PORT_SIGNATURE_OMISSIONS.md"

sched_gate SURFACE-FRESH res=surface desc="check_surface_freshness (regen port_surface.json)" \
    --fn surface_fresh_gate

sched_gate NO-CHEAT desc="audit_no_cheat_tests" \
    -- python3 "$PORTING_SDK_DIR/scripts/audit_no_cheat_tests.py" --root "$PORT_ROOT"

sched_gate REST-COVERAGE defer=1 desc="every implemented REST route covered success+error (parity + allowlist)" \
    --fn rest_coverage_gate

sched_gate SPEC-PARITY defer=1 desc="implemented routes == canonical spec (modulo SPEC_IMPLEMENTATION_GAPS.md)" \
    --fn spec_parity_gate

sched_gate EMISSION desc="diff_port_emission vs python to_dict()" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_port_emission.py" \
        --dump-cmd "perl bin/emit-corpus.pl" \
        --port-repo "$PORT_ROOT"

# BEHAVIORAL-* (Layer D) — run the shared behavioral corpus through the port's
# dump programs and structurally byte-compare against the signalwire-python oracle.
# 2>/dev/null suppresses perl's experimental-feature warnings on stderr so ONLY JSON
# reaches stdout; --python-sdk pins the oracle source (never the caller's CWD/env).
sched_gate BEHAVIORAL-WIRE desc="diff_port_wire vs python oracle (Layer D)" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_port_wire.py" \
        --port perl --python-sdk "$PYTHON_SDK_DIR" \
        --dump-cmd "perl -Ilib bin/wire-dump.pl 2>/dev/null"

sched_gate BEHAVIORAL-SWML desc="diff_port_swml vs python oracle (Layer D)" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_port_swml.py" \
        --port perl --python-sdk "$PYTHON_SDK_DIR" \
        --dump-cmd "perl -Ilib bin/swml-dump.pl 2>/dev/null"

sched_gate BEHAVIORAL-STATE desc="diff_port_state vs python oracle (Layer D)" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_port_state.py" \
        --port perl --python-sdk "$PYTHON_SDK_DIR" \
        --dump-cmd "perl -Ilib bin/state-dump.pl 2>/dev/null"

sched_gate BEHAVIORAL-HTTP desc="diff_port_http vs python oracle (Layer D)" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_port_http.py" \
        --port perl --python-sdk "$PYTHON_SDK_DIR" \
        --dump-cmd "perl -Ilib bin/http-dump.pl 2>/dev/null"

sched_gate BEHAVIORAL-WIRE-RELAY desc="diff_port_wire_relay vs python oracle (Layer D)" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_port_wire_relay.py" \
        --port perl --python-sdk "$PYTHON_SDK_DIR" \
        --dump-cmd "perl -Ilib bin/wire-relay-dump.pl 2>/dev/null"

# FMT joins res=surface: run locally (no CI) it rewrites lib/**/*.pm in place via
# `perltidy -b`, which a concurrent TEST (`perl -c` / module load) or surface-enumerator
# (loads lib/) would otherwise read mid-write. Under CI (--check) it's read-only, but the
# label is harmless there and keeps local and CI scheduling identical.
sched_gate FMT defer=1 res=surface desc="run-format.sh (local: apply; CI: --check)" \
    -- bash scripts/run-format.sh ${CI:+--check}

sched_gate LINT defer=1 desc="run-lint.sh (perlcritic severity 4, zero findings)" \
    -- bash scripts/run-lint.sh

sched_gate DOC-AUDIT res=surface desc="audit_docs vs port_surface.json" \
    -- python3 "$PORTING_SDK_DIR/scripts/audit_docs.py" \
        --root "$PORT_ROOT" \
        --surface "$PORT_ROOT/port_surface.json" \
        --ignore "$PORT_ROOT/DOC_AUDIT_IGNORE.md"

sched_gate SURFACE-DIFF res=surface desc="diff_port_surface vs python reference" \
    --fn surface_diff_gate

sched_gate SKILL-CONTRACT desc="diff_skill_contracts vs python reference" \
    -- python3 "$PORTING_SDK_DIR/scripts/diff_skill_contracts.py" \
        --dump-cmd "perl bin/emit-skills.pl" \
        --port-repo "$PORT_ROOT"

sched_gate SWAIG-CLI desc="swaig-test shared mini-contract (verbs/serverless-reject/default-action)" \
    -- python3 "$PORTING_SDK_DIR/scripts/audit_swaig_cli_contract.py" \
        --port perl \
        --cmd "perl -I$PORT_ROOT/lib $PORT_ROOT/bin/swaig-test" \
        --require-url-model \
        --default-action-argv='--url|http://user:pass@127.0.0.1:1/' \
        --no-serverless-argv='--url|http://user:pass@127.0.0.1:1/|--simulate-serverless|lambda|--list-tools'

sched_gate SWAIG-COVERAGE desc="every engine SWAIG action emittable by FunctionResult (or allowlisted)" \
    -- python3 "$PORTING_SDK_DIR/scripts/swaig_coverage.py" --check \
        --emission "$PORT_ROOT/lib/SignalWire/SWAIG/FunctionResult.pm"

sched_gate DOC-LANG-PURITY res=dayone desc="no python-verbatim docs in a non-python port" \
    -- python3 "$PORTING_SDK_DIR/scripts/doc_lang_purity.py" --port perl --repo .

sched_gate DOC-LINKS res=dayone desc="every relative markdown link resolves to a tracked file" \
    -- python3 "$PORTING_SDK_DIR/scripts/doc_links.py" --port perl --repo .

sched_gate README-INCLUDE res=dayone desc="doc code blocks are byte-identical to their gate-compiled fixture regions" \
    -- python3 "$PORTING_SDK_DIR/scripts/readme_include.py" --port perl --repo .

sched_gate ROOT-HYGIENE res=dayone desc="no audit/scratch clutter tracked at repo root (allowlist ROOT_HYGIENE_ALLOW.md)" \
    -- python3 "$PORTING_SDK_DIR/scripts/root_hygiene.py" --port perl --repo .

sched_gate IGNORE-LEDGER-VERIFY res=dayone desc="no laundered false-absence entries in DOC_AUDIT_IGNORE.md" \
    -- python3 "$PORTING_SDK_DIR/scripts/ignore_ledger_verify.py" --port perl --repo .

sched_gate META-CONSISTENT res=dayone desc="package metadata consistency" \
    -- python3 "$PORTING_SDK_DIR/scripts/meta_consistent.py" --port perl --repo .

sched_gate ARTIFACT-DENY res=dayone desc="no porting artifacts in the PUBLISHED package (authoritative listing)" \
    --fn dayone_artifact_deny

# ---- expansion gates (Tier 5, now BLOCKING — backlog burned + allowlists approved) ---
# Wired the same way as the Day-one gates above: single approvable
# `python3 "$PORTING_SDK_DIR/scripts/<gate>.py" --port perl --repo .` prefix, NO
# --report-only. Each was verified to exit 0 enforcing before wiring.
#   * ROUTE-COLLISION is NOT wired for perl: route_collision.py has no default
#     registry command for perl and, fed perl's route_registry.pl, currently flags
#     2 ROUTE-SPLIT findings (call_flows/conference_rooms list_addresses, singular-
#     vs-plural fabric path) with no human-approved ROUTE_COLLISION_ALLOW.md — a
#     real disposition, held for a follow-up, not silenced here.
sched_gate GEN-TYPE-DEGENERACY res=dayone desc="no degenerate generated typed aliases (allowlist GEN_TYPE_DEGENERACY_ALLOW.md)" \
    -- python3 "$PORTING_SDK_DIR/scripts/gen_type_degeneracy.py" --port perl --repo .

sched_gate PUBLIC-JARGON res=dayone desc="no porting/internal jargon leaked into the public surface" \
    -- python3 "$PORTING_SDK_DIR/scripts/public_jargon.py" --port perl --repo .

sched_gate GEN-IDIOM res=dayone desc="generated code is not lint-excluded (holds to the same idiom bar)" \
    -- python3 "$PORTING_SDK_DIR/scripts/gen_idiom.py" --port perl --repo .

sched_gate RELEASE-FRESH res=dayone desc="publish workflow runs the gates before publishing (publish.yml gated)" \
    -- python3 "$PORTING_SDK_DIR/scripts/release_fresh.py" --port perl --repo .

sched_run
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "==> CI PASS"
else
    echo "==> CI FAIL (gates:$FAILED_GATES )"
fi
exit "$rc"
