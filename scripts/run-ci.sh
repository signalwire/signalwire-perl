#!/usr/bin/env bash
# run-ci.sh — canonical local-and-CI gate runner for signalwire-perl.
#
# Same script invoked locally (`bash scripts/run-ci.sh`) AND by the
# GitHub Actions workflow. No drift between local and CI behavior.
#
# Gates (in order, fail-fast):
#   1. prove -Ilib -It/lib t/             — language test runner
#   2. signature regen                    — python adapter + signature_dump.pl
#   3. drift gate                         — porting-sdk diff_port_signatures.py
#   4. surface-fresh gate                 — porting-sdk check_surface_freshness.py
#                                           (regens port_surface.json via
#                                           enumerate_surface.pl and fails if the
#                                           committed copy is STALE — closes the
#                                           Layer-B-not-gated hole; Layer A above
#                                           only gates signatures)
#   5. no-cheat gate                      — porting-sdk audit_no_cheat_tests.py
#   5b. rest-coverage gate                — porting-sdk rest_coverage checker:
#                                           every implemented REST route covered
#                                           success+error on the canonical path
#                                           (spins its own mock, runs t/rest/
#                                           serially, replays the journal)
#   6. emission gate                      — porting-sdk diff_port_emission.py
#                                           (byte-compares bin/emit-corpus.pl's
#                                           FunctionResult serialisation vs
#                                           Python's to_dict() over the shared
#                                           81-entry corpus; no mocks/network)
#   7. fmt gate                           — Perl::Tidy (local: apply; CI: --assert-tidy)
#   8. lint gate                          — Perl::Critic severity 4, zero findings
#   9. doc-audit gate                     — porting-sdk audit_docs.py
#  10. surface-diff gate                  — porting-sdk diff_port_surface.py
#  11. skill-contract gate                — porting-sdk diff_skill_contracts.py

set -u
set -o pipefail

PORT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

FAILED_GATES=""

run_gate() {
    local name="$1"; shift
    local description="$1"; shift
    local logfile
    logfile="$(mktemp)"
    "$@" >"$logfile" 2>&1
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "[$name] $description ... PASS"
        rm -f "$logfile"
        return 0
    fi
    echo "[$name] $description ... FAIL: exit $rc"
    sed 's/^/    /' "$logfile" | tail -40
    rm -f "$logfile"
    FAILED_GATES="$FAILED_GATES $name"
    return $rc
}

cd "$PORT_ROOT"

# Make a local::lib visible to the gates when one is present.
#
# In CI the SDK's CPAN deps are installed onto the runner's perl via
# `cpanm --installdeps .` (see .github/workflows/test.yml), so they're already
# on @INC and this is a no-op. For LOCAL `bash scripts/run-ci.sh` runs, devs
# install deps into a local::lib at ~/perl5 (the convention documented in
# CLAUDE.md); that dir is NOT on the default @INC, so without this the TEST
# gate fails with "Can't locate Plack/Request.pm" / "Protocol/WebSocket" even
# though the code is fine. Prepend it when it exists — keyed off $HOME (never a
# hard-coded path), and guarded so CI/containers without ~/perl5 are unaffected.
LOCAL_LIB_DIR="${PERL_LOCAL_LIB_ROOT:-$HOME/perl5}/lib/perl5"
if [ -d "$LOCAL_LIB_DIR" ]; then
    export PERL5LIB="$LOCAL_LIB_DIR${PERL5LIB:+:$PERL5LIB}"
fi

# Same local::lib, same reason — but for the FMT/LINT gate EXECUTABLES. The
# perltidy / perlcritic scripts (CPAN develop-deps) install into the local::lib's
# bin/ alongside the modules above; that dir is NOT on the default PATH, so a
# LOCAL run would hit `perltidy: command not found` even though it's installed.
# Prepend it when it exists — same $HOME keying + existence guard as PERL5LIB, so
# CI (deps on the system perl, already on PATH) is unaffected.
LOCAL_LIB_BIN="${PERL_LOCAL_LIB_ROOT:-$HOME/perl5}/bin"
if [ -d "$LOCAL_LIB_BIN" ]; then
    export PATH="$LOCAL_LIB_BIN:$PATH"
fi

# Bootstrap the FMT/LINT develop-deps if missing. CI installs them via
# `cpanm --with-develop --installdeps .` (.github/workflows/test.yml), but a
# fresh LOCAL checkout has neither perltidy nor perlcritic on PATH, so the FMT
# and LINT gates would die with "command not found" rather than run. Rather than
# require every dev to remember the cpanm incantation, self-heal: when either
# binary is unresolvable, install the cpanfile's `on 'develop'` block into the
# local::lib (~/perl5 by convention) and re-expose its bin/ on PATH. Skipped in
# CI ($CI set — deps already on the system perl) and when cpanm is unavailable
# (then the gates fail loudly with an actionable message, as before). Keyed off
# $HOME, never a hard-coded path.
ensure_dev_tools() {
    [ -n "${CI:-}" ] && return 0                          # CI installs its own deps
    if command -v perltidy >/dev/null 2>&1 && command -v perlcritic >/dev/null 2>&1; then
        return 0                                          # already resolvable
    fi
    if ! command -v cpanm >/dev/null 2>&1; then
        echo "==> WARN: perltidy/perlcritic missing and cpanm unavailable;" \
             "FMT/LINT gates will fail. Install App::cpanminus + cpanfile develop deps." >&2
        return 0
    fi
    local lib_root="${PERL_LOCAL_LIB_ROOT:-$HOME/perl5}"
    echo "==> bootstrapping FMT/LINT dev-deps (Perl::Tidy, Perl::Critic) into $lib_root ..."
    cpanm --local-lib="$lib_root" --notest --quiet --with-develop --installdeps "$PORT_ROOT" \
        || echo "==> WARN: dev-dep bootstrap failed; FMT/LINT gates may fail." >&2
    # (Re)expose the local::lib now that it's populated.
    LOCAL_LIB_DIR="$lib_root/lib/perl5"
    [ -d "$LOCAL_LIB_DIR" ] && export PERL5LIB="$LOCAL_LIB_DIR${PERL5LIB:+:$PERL5LIB}"
    LOCAL_LIB_BIN="$lib_root/bin"
    [ -d "$LOCAL_LIB_BIN" ] && export PATH="$LOCAL_LIB_BIN:$PATH"
}
ensure_dev_tools

echo "==> running CI gates for $PORT_NAME (porting-sdk at $PORTING_SDK_DIR)"

# Gate 0: GEN-FRESH — the REST resource + client-tree layer under
# lib/SignalWire/REST/Namespaces/Generated/ is GENERATED from the canonical specs
# (porting-sdk/rest-apis/ + x-sdk-* markup) by scripts/generate_rest.py. This gate
# fails if the committed generated files are stale vs a fresh run (a spec/markup
# change not regenerated, or a hand-edit to a generated file). Regenerate with
# `python3 scripts/generate_rest.py`.
run_gate "GEN-FRESH" "generate_rest.py --check (generated REST layer matches specs)" \
    python3 scripts/generate_rest.py --check

# Gate 0b: GEN-FRESH-SWML — the SWML-verbs typed CONFIG surface under
# lib/SignalWire/SWML/Generated/ is GENERATED from porting-sdk/schema.json ($defs)
# by scripts/generate_swml_verbs.py (item D2). Fails if stale. Regenerate with
# `python3 scripts/generate_swml_verbs.py`.
run_gate "GEN-FRESH-SWML" "generate_swml_verbs.py --check (generated SWML-verb types match schema.json)" \
    python3 scripts/generate_swml_verbs.py --check

# Gate 0c: GEN-FRESH-RELAY — the RELAY protocol wire types under
# lib/SignalWire/Relay/Generated/ are GENERATED from porting-sdk/relay-protocol/*.json
# by scripts/generate_relay_protocol.py (item I). Fails if stale. Regenerate with
# `python3 scripts/generate_relay_protocol.py`.
run_gate "GEN-FRESH-RELAY" "generate_relay_protocol.py --check (generated RELAY types match relay-protocol)" \
    python3 scripts/generate_relay_protocol.py --check

# Gate 0d: GEN-FRESH-SWAIG — the SWAIG read-side payloads under
# lib/SignalWire/SWAIG/Generated/ are GENERATED from porting-sdk/swaig-specs/*.yaml
# by scripts/generate_swaig_payloads.py (item D1). Fails if stale. Regenerate with
# `python3 scripts/generate_swaig_payloads.py`.
run_gate "GEN-FRESH-SWAIG" "generate_swaig_payloads.py --check (generated SWAIG payloads match swaig-specs)" \
    python3 scripts/generate_swaig_payloads.py --check

# Gate 0e: GEN-FRESH-TESTS — the generated full-mock REST wire-test suite under
# t/rest/generated/<spec>_generated.t is GENERATED (changeset item E) from the
# route-registry × spec-operationId oracle by scripts/generate_rest_tests.py
# (route_registry.pl + rest_test_plan.pl captured off the REAL client, joined to
# the OpenAPI operationId). Each implemented route gets a SUCCESS test (assert
# method + matched_route) and an ERROR test (arm a 500, assert
# HttpClient::Error->status_code == 500). These generated tests ARE part of the
# REST coverage suite; this gate fails if a spec/route changed without
# regenerating (or a generated test file was hand-edited). Regenerate with
# `python3 scripts/generate_rest_tests.py`. Mirrors the go/php/ts/ruby REST
# test-GEN-FRESH gate.
run_gate "GEN-FRESH-TESTS" "generate_rest_tests.py --check (generated REST wire-test suite matches route-registry × spec oracle)" \
    python3 scripts/generate_rest_tests.py --check

# Gate 1: prove
run_gate "TEST" "prove -Ilib -It/lib t/" \
    prove -Ilib -It/lib t/

# Gate 2: signature regen
run_gate "SIGNATURES" "regenerate port_signatures.json" \
    python3 scripts/enumerate_signatures.py

# Gate 3: drift gate
run_gate "DRIFT" "diff_port_signatures vs python reference" \
    python3 "$PORTING_SDK_DIR/scripts/diff_port_signatures.py" \
        --reference "$PORTING_SDK_DIR/python_signatures.json" \
        --port-signatures "$PORT_ROOT/port_signatures.json" \
        --surface-omissions "$PORT_ROOT/PORT_OMISSIONS.md" \
        --surface-additions "$PORT_ROOT/PORT_ADDITIONS.md" \
        --omissions "$PORT_ROOT/PORT_SIGNATURE_OMISSIONS.md"

# Gate 4: surface-fresh — Layer B (the symbol-level surface) is NOT gated by the
# drift gate above (that's Layer A / signatures only), so port_surface.json can
# silently rot. Regenerate it IN PLACE via the Perl surface enumerator and fail
# if the committed copy differs (modulo the volatile generated_from git-sha,
# which check_surface_freshness.py strips). Always restore the working copy so a
# stale-but-uncommitted regen never leaks past this gate.
surface_fresh_gate() {
    # Snapshot the committed surface (fallback to the working copy if HEAD has none).
    if ! git show HEAD:port_surface.json > /tmp/committed_surface.json 2>/dev/null; then
        cp "$PORT_ROOT/port_surface.json" /tmp/committed_surface.json
    fi
    # Regenerate in place (writes port_surface.json; warnings go to stderr).
    perl scripts/enumerate_surface.pl >/dev/null || return $?
    # Compare modulo provenance.
    python3 "$PORTING_SDK_DIR/scripts/check_surface_freshness.py" \
        --committed /tmp/committed_surface.json \
        --fresh "$PORT_ROOT/port_surface.json"
    local rc=$?
    # Restore the working copy regardless of outcome.
    git checkout -- port_surface.json 2>/dev/null
    return $rc
}
run_gate "SURFACE-FRESH" "check_surface_freshness (regen port_surface.json)" \
    surface_fresh_gate

# Gate 5: no-cheat
run_gate "NO-CHEAT" "audit_no_cheat_tests" \
    python3 "$PORTING_SDK_DIR/scripts/audit_no_cheat_tests.py" --root "$PORT_ROOT"

# Gate 5b: REST-COVERAGE — every canonical REST route the SDK implements must be
# exercised with BOTH a success (2xx) AND an error (4xx/5xx) response on the
# correct on-the-wire path (parity). Measured by replaying the mock journal of a
# REST-suite run through porting-sdk's rest_coverage checker. Accepted gaps —
# routes with no SDK method, malformed canonical routes, mock-router collisions —
# are allowlisted: the shared baseline (porting-sdk/REST_COVERAGE_BASELINE.md) +
# this port's REST_COVERAGE_GAPS.md. A stale entry (route now covered) fails the
# gate. Self-contained: spins its OWN mock (probe-then-spawn with cleanup), resets
# the journal, runs the t/rest/ suite SERIALLY (prove -j1) against that one mock so
# all traffic lands in one journal, then checks that journal. Same shape as the
# go/python/java/typescript gate.
#
# The mock is pre-spawned here (rather than letting the suite self-spawn on first
# probe) so the run is deterministic and all REST traffic shares one journal; the
# suite reuses it via the MOCK_SIGNALWIRE_PORT env + the harness's probe-or-reuse.
# Pick a free TCP port on 127.0.0.1 (bind :0, read the OS-assigned port,
# release). Never reuse a hardcoded port — a leftover or concurrent mock
# squatting a fixed port otherwise makes the gate hang on its health poll.
pick_free_port() {
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}
rest_coverage_gate() {
    local port
    port="$(pick_free_port)" || { echo "could not allocate a free port" >&2; return 1; }
    local mock_pkg_parent="$PORTING_SDK_DIR/test_harness/mock_signalwire"
    export PYTHONPATH="$mock_pkg_parent${PYTHONPATH:+:$PYTHONPATH}"
    python3 -m mock_signalwire --host 127.0.0.1 --port "$port" --log-level error \
        >/tmp/rest_cov_mock_perl.$$.log 2>&1 &
    local mock_pid=$!
    # shellcheck disable=SC2064
    trap "kill $mock_pid 2>/dev/null" RETURN
    # Fail LOUD if the mock dies mid-startup or never becomes healthy — never hang.
    local i ready=0
    for i in $(seq 1 60); do
        if ! kill -0 "$mock_pid" 2>/dev/null; then
            echo "mock_signalwire died on port $port — log:" >&2
            cat "/tmp/rest_cov_mock_perl.$$.log" >&2
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
    # Run the REST suite serially against this one mock (one shared journal). The
    # harness probes 127.0.0.1:$port (MOCK_SIGNALWIRE_PORT), finds it healthy, and
    # reuses it instead of self-spawning.
    # -r so the generated wire-test suite under t/rest/generated/ (changeset E)
    # is picked up too — prove does NOT recurse into subdirs without it, and the
    # generated tests ARE part of the REST coverage journal.
    MOCK_SIGNALWIRE_PORT="$port" prove -Ilib -It/lib -j1 -r t/rest/ || return 1
    python3 -m mock_signalwire.rest_coverage \
        --mock-url "http://127.0.0.1:$port" \
        --spec-root "$PORTING_SDK_DIR/rest-apis" \
        --allowlist "$PORTING_SDK_DIR/REST_COVERAGE_BASELINE.md" \
        --allowlist "$PORT_ROOT/REST_COVERAGE_GAPS.md" \
        --gap-baseline "$PORTING_SDK_DIR/REST_COVERAGE_GAP_BASELINE.md"
}
run_gate "REST-COVERAGE" "every implemented REST route covered success+error (parity + allowlist)" \
    rest_coverage_gate

# Gate 5c: SPEC-PARITY — the routes the SDK actually IMPLEMENTS must equal the
# canonical spec route set, modulo porting-sdk/SPEC_IMPLEMENTATION_GAPS.md. This
# is the spec-first guard REST-COVERAGE can't give: REST-COVERAGE only proves
# *tested* routes match the spec, so a route the SDK implements that the spec
# doesn't define (or vice versa) would slip past it. Set B is built by
# scripts/route_registry.pl — it drives the live RestClient through a recording
# HttpClient and captures every dispatched (method, path), so it sees every
# implemented route whether or not it's tested (not a source scrape, not the
# journal). The shared porting-sdk diff consumes that JSON via --registry-json.
#
# --registry-json lands in porting-sdk via PR #45 (the local tree already has
# it; CI on this PR depends on porting-sdk#45 being merged first).
spec_parity_gate() {
    local mock_pkg_parent="$PORTING_SDK_DIR/test_harness/mock_signalwire"
    export PYTHONPATH="$mock_pkg_parent${PYTHONPATH:+:$PYTHONPATH}"
    local registry
    registry="$(mktemp)"
    # Pure JSON to stdout; any SDK chatter would go to stderr (discarded).
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
run_gate "SPEC-PARITY" "implemented routes == canonical spec (modulo SPEC_IMPLEMENTATION_GAPS.md)" \
    spec_parity_gate

# Gate 6: emission — byte-compare FunctionResult serialisation vs Python's
# to_dict() over the shared 81-entry corpus. Pure serialisation: no mock
# servers, no network — just signalwire-python adjacent (already required by
# the drift gate) and bin/emit-corpus.pl. See porting-sdk/IDIOM_PASS_JOURNAL.md
# §4 Tier-0 and scripts/diff_port_emission.py.
run_gate "EMISSION" "diff_port_emission vs python to_dict()" \
    python3 "$PORTING_SDK_DIR/scripts/diff_port_emission.py" \
        --dump-cmd "perl bin/emit-corpus.pl" \
        --port-repo "$PORT_ROOT"

# The set of Perl source files the FMT + LINT gates police: every module under
# lib/ plus the repo's hand-written Perl tooling (bin/ + scripts/). Kept in one
# place so FMT and LINT police exactly the same files. enumerate_signatures.py
# is Python (skipped); enumerate_surface.pl / signature_dump.pl are Perl.
perl_source_files() {
    find lib -type f -name '*.pm'
    echo bin/emit-corpus.pl
    echo bin/emit-skills.pl
    echo bin/swaig-test
    echo scripts/enumerate_surface.pl
    echo scripts/signature_dump.pl
    echo scripts/route_registry.pl
    echo scripts/rest_test_plan.pl
}

# Gate 7: FMT — the language format gate (perl: Perl::Tidy). perltidy is the
# Perl analog of gofmt / rustfmt / google-java-format: SOURCE-STYLE ONLY and
# proven wire-/surface-neutral (a full reformat leaves port_signatures.json +
# port_surface.json byte-identical and EMISSION 81/81 — verified in the FMT
# rollout). Config is the committed .perltidyrc. Mirrors the go/ruby/java FMT
# shape:
#   * LOCAL ($CI unset)  → `perltidy -b`: reformats your working tree in place
#     (deleting the .bak via -bext='/') so you never hand-run it; notes if it
#     changed files. A residual non-tidy file then still fails the --assert-tidy
#     check below.
#   * CI ($CI=true)      → `perltidy --assert-tidy` (read-only, output to
#     /dev/null): FAILS if any source file is not already tidy.
fmt_gate() {
    local f rc=0
    if [ -n "${CI:-}" ]; then
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            perltidy --profile="$PORT_ROOT/.perltidyrc" --assert-tidy \
                -nst -se --outfile=/dev/null "$f" || rc=1
        done < <(perl_source_files)
    else
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            perltidy --profile="$PORT_ROOT/.perltidyrc" -b -bext='/' "$f"
        done < <(perl_source_files)
        if ! git diff --quiet 2>/dev/null; then
            echo "    (FMT auto-applied formatting to your working tree — review & stage)"
        fi
        # A residual issue perltidy can't fix must still fail the gate.
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            perltidy --profile="$PORT_ROOT/.perltidyrc" --assert-tidy \
                -nst -se --outfile=/dev/null "$f" || rc=1
        done < <(perl_source_files)
    fi
    return $rc
}
run_gate "FMT" "perltidy (local: apply; CI: --assert-tidy)" fmt_gate

# Gate 8: LINT — the language lint gate (perl: Perl::Critic at severity 4,
# burned to ZERO). This is the blocking quality floor, ratcheted from the
# original severity-5 floor to 4 by FIXING source idiomatically
# (RequireFinalReturn / RequireArgUnpacking / RequireLocalizedPunctuationVars).
# The only disabled policies (.perlcriticrc) are the handful justified by
# wire/surface parity or a heuristic that does not fit the code — never style,
# never to hide a finding (each carries a one-line rationale; see the file).
# severity is pinned both in .perlcriticrc and on the command line so the gate
# reproduces a bare `perlcritic lib/`. Mirrors the go vet+golangci / ruby
# rubocop blocking-lint gate.
lint_gate() {
    local f rc=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        perlcritic --profile "$PORT_ROOT/.perlcriticrc" --severity 4 "$f" || rc=1
    done < <(perl_source_files)
    return $rc
}
run_gate "LINT" "perlcritic severity 4, zero findings" lint_gate

# Gate 9: DOC-AUDIT — every method/class referenced in docs/ + examples/ fenced
# code blocks must resolve to a real symbol in the port surface (catches
# phantom-API doc promises). Uses the committed port_surface.json (the
# SURFACE-FRESH gate above already proved it is fresh) + DOC_AUDIT_IGNORE.md for
# intentional non-symbol references. Mirrors .github/workflows/doc-audit.yml.
run_gate "DOC-AUDIT" "audit_docs vs port_surface.json" \
    python3 "$PORTING_SDK_DIR/scripts/audit_docs.py" \
        --root "$PORT_ROOT" \
        --surface "$PORT_ROOT/port_surface.json" \
        --ignore "$PORT_ROOT/DOC_AUDIT_IGNORE.md"

# Gate 10: SURFACE-DIFF — diff the port's public surface against the Python
# reference (omissions + additions). The signature DRIFT gate (Layer A) checks
# method *signatures*; this checks surface *membership* — public symbols the
# port has that Python doesn't and vice-versa. Mirrors
# .github/workflows/surface-audit.yml. Regenerate the surface in place via the
# Perl enumerator, diff, then restore the committed copy unconditionally so the
# gate is side-effect free.
surface_diff_gate() {
    local committed="/tmp/committed_surface_diff_${PORT_NAME}.$$"
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
run_gate "SURFACE-DIFF" "diff_port_surface vs python reference" \
    surface_diff_gate

# Gate 11: SKILL-CONTRACT — the surface/drift/emission gates see signatures +
# symbol names + FunctionResult serialisation; NONE sees a built-in skill's
# SWAIG tool contract ({name, parameters, required, enum} each skill registers).
# This differ closes that gap: it builds the Python oracle by instantiating each
# covered reference skill, runs the Perl skill-dump program (bin/emit-skills.pl,
# which reads the SAME shared corpus), and structurally compares the two.
# DESCRIPTIONS + implementation (handler vs DataMap) are not compared — only
# name/param-name/param-type/enum/required. Mirrors the go/ruby/java SKILL-
# CONTRACT gate. Same prereqs as EMISSION (signalwire-python adjacent; no
# network).
run_gate "SKILL-CONTRACT" "diff_skill_contracts vs python reference" \
    python3 "$PORTING_SDK_DIR/scripts/diff_skill_contracts.py" \
        --dump-cmd "perl bin/emit-skills.pl" \
        --port-repo "$PORT_ROOT"

# SWAIG-CLI — lightweight shared swaig-test mini-contract (NOT python parity;
# python's in-process simulator surface is reference-only). Black-box: invokes
# `perl bin/swaig-test --help` + golden invocations and asserts the shared verbs
# are documented and no-action errors (the cross-port majority default). Perl
# has no --simulate-serverless, so the no-serverless clause asserts the flag is
# rejected as an unknown option (no half-accept).
run_gate "SWAIG-CLI" "swaig-test shared mini-contract (verbs/serverless-reject/default-action)" \
    python3 "$PORTING_SDK_DIR/scripts/audit_swaig_cli_contract.py" \
        --port perl \
        --cmd "perl -I$PORT_ROOT/lib $PORT_ROOT/bin/swaig-test" \
        --require-url-model \
        --default-action-argv='--url|http://user:pass@127.0.0.1:1/' \
        --no-serverless-argv='--url|http://user:pass@127.0.0.1:1/|--simulate-serverless|lambda|--list-tools'

# SWAIG-COVERAGE — the SWAIG back-pressure gate (SWAIG_PIPELINE §5): every engine
# response action in the vendored swaig-specs/swaig-response.yaml must be emittable
# by the port's FunctionResult, or be signed off in SWAIG_COVERAGE_ALLOWLIST.md.
# The shared checker scrapes perl's FunctionResult (add_action('key',…) + the
# top-level keys of `push @{ $self->action }, {…}` action hashrefs — .pm scraper in
# swaig_coverage.py). Current: engine 27, perl emits 25, the 2 gaps
# (back_to_back_functions, user_event) are the shared signed-off allowlist.
run_gate "SWAIG-COVERAGE" "every engine SWAIG action emittable by FunctionResult (or allowlisted)" \
    python3 "$PORTING_SDK_DIR/scripts/swaig_coverage.py" --check \
        --emission "$PORT_ROOT/lib/SignalWire/SWAIG/FunctionResult.pm"

if [ -z "$FAILED_GATES" ]; then
    echo "==> CI PASS"
    exit 0
else
    echo "==> CI FAIL (gates:$FAILED_GATES )"
    exit 1
fi
