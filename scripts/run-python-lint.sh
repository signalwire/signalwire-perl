#!/usr/bin/env bash
# scripts/run-python-lint.sh — the CANONICAL way to lint + format this repo's
# hand-written PYTHON.
#
# WHY A PERL PORT LINTS PYTHON
# ============================
# signalwire-perl ships 7 hand-written Python programs under scripts/: the four
# code generators (REST / RELAY / SWML / SWAIG), the signature enumerator, the
# REST test generator, and scripts/_perltidy_gen.py — which is itself part of the
# FORMAT toolchain (every generator runs it as its final emit pass). They are
# load-bearing gate infrastructure: GEN-FRESH*, SIGNATURES and the FMT contract
# all execute them.
#
# Until 2026-07-30 NO gate linted or formatted a single line of them. They were
# the only hand-written code in this repo held to no bar at all — while the Perl
# they GENERATE was policed by perlcritic and perltidy on every run.
#
# Owner ruling (2026-07-29): one bar for everything. These files are now held to
# the SAME ruleset as the Python reference SDK — the rule selection in ruff.toml
# is copied from signalwire-python/pyproject.toml, not invented here, so the
# fleet applies one identical Python bar.
#
#   run-python-lint.sh          APPLY  — `ruff check --fix` + `ruff format`,
#                                        rewriting in place. Exit non-zero only
#                                        if a finding SURVIVES the autofix.
#   run-python-lint.sh --check  VERIFY — read-only; `ruff check` + `ruff format
#                                        --check`. This is the CI gate.
#
# Same LOCAL-applies / CI---check contract the Perl FMT gate uses.
#
# Config: ruff.toml at the repo root (single source for both check and format).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"

cd "$REPO_ROOT"

if ! command -v ruff >/dev/null 2>&1; then
    echo "ERROR: ruff not found on PATH. Install it with one of:" >&2
    echo "         pip install ruff" >&2
    echo "         brew install ruff" >&2
    echo "       (declared in requirements-dev.txt and in the CI workflow)" >&2
    exit 1
fi

CHECK=0
case "${1:-}" in
    --check) CHECK=1 ;;
    "") ;;
    *) echo "usage: run-python-lint.sh [--check]" >&2; exit 2 ;;
esac

# The scope: every hand-written .py in the repo. `git ls-files` rather than a
# hand list so a NEW Python program is covered the day it lands — the same
# stale-hand-list failure mode that left t/ and examples/ unlinted for so long.
#
# Read into a positional-parameter list, NOT `mapfile`: macOS ships bash 3.2,
# where `mapfile` does not exist (it is a bash-4 builtin) and the gate would die
# with "command not found" on every developer Mac while passing in CI.
set -- $(git ls-files '*.py')

if [ "$#" -eq 0 ]; then
    echo "REPO-LINT(py): no Python files tracked — nothing to do."
    exit 0
fi

# NO_COLOR keeps the output greppable when a caller pipes it (ANSI escapes
# otherwise break a naive `grep -c` on a path pattern and read as "0 findings").
export NO_COLOR=1

rc=0

if [ "$CHECK" -eq 1 ]; then
    ruff check "$@" || rc=1
    ruff format --check "$@" || rc=1
    if [ "$rc" -ne 0 ]; then
        echo "REPO-LINT(py): findings above — run 'bash scripts/run-python-lint.sh' to fix." >&2
    fi
    exit "$rc"
fi

# APPLY: autofix what ruff can, format, then RE-CHECK so a finding the autofix
# could not resolve still fails loudly instead of being silently left behind.
ruff check --fix "$@" || true
ruff format "$@"
ruff check "$@" || rc=1
ruff format --check "$@" || rc=1

exit "$rc"
