#!/usr/bin/env bash
# scripts/run-tests.sh — the CANONICAL way to run signalwire-perl's tests.
#
# Tool: prove -Ilib -It/lib -r t/. This is the SINGLE entry point for testing —
# run-ci, agents, humans, and docs all go through it; nothing invokes prove
# directly anymore. Self-bootstraps its environment (scripts/_env.sh: the
# PERL5LIB fix that puts the local::lib runtime deps — Plack, Protocol::WebSocket,
# etc. — on @INC) so the suite works from ANY directory with ANY shell setup.
#
#   run-tests.sh            Run the FULL suite (prove -Ilib -It/lib -r t/).
#   run-tests.sh <filter>   Pass a test file / directory / glob straight through
#                           to prove to run a subset, e.g.
#                             run-tests.sh t/unit/core/agent_base.t
#                             run-tests.sh t/rest/
#
# The shared mocks self-terminate on parent death (porting-sdk f1cd024), so no
# mock cleanup is needed here for the ordinary suite.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"
# Tests need the runtime deps from the local::lib; ensure it's bootstrapped too.
_sw_ensure_perl_tools || exit 1

cd "$REPO_ROOT"

if ! command -v prove >/dev/null 2>&1; then
    echo "ERROR: prove not found on PATH (part of core perl / Test::Harness)." >&2
    exit 1
fi

# Run tests in PARALLEL (prove -j) — the test suite is the CI wall-clock driver (~11min
# serial); the mock-using tests are concurrency-safe (each picks its own free port via
# PortPicker when MOCK_*_PORT isn't the pre-spawned one — see t/lib/MockTest.pm), so
# fanning across cores is a straight win. Measured green + ~3.5x on t/rest/. Job count =
# cores (min 1); override with PROVE_JOBS.
jobs="${PROVE_JOBS:-$( (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4 )}"

# Optional filter passthrough: default to the whole tree, else run exactly what
# the caller named.
if [ "$#" -eq 0 ]; then
    exec prove -j"$jobs" -Ilib -It/lib -r t/
else
    exec prove -j"$jobs" -Ilib -It/lib -r "$@"
fi
