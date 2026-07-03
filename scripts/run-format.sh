#!/usr/bin/env bash
# scripts/run-format.sh — the CANONICAL way to format signalwire-perl.
#
# Tool: Perl::Tidy (perltidy), config .perltidyrc. This is the SINGLE entry point
# for formatting — run-ci, agents, humans, and docs all go through it; nothing
# invokes perltidy directly anymore. Self-bootstraps its environment (see
# scripts/_env.sh: the PERL5LIB fix that lets perltidy locate Perl::Tidy) so it
# works from ANY directory with ANY shell setup.
#
#   run-format.sh            APPLY   — reformat lib/ + bin/ + Perl scripts in
#                                      place (perltidy -b), exit 0 even if it
#                                      changed files. Idempotent: a 2nd run is a
#                                      no-op.
#   run-format.sh --check    VERIFY  — read-only; exit non-zero if anything is
#                                      not already tidy (perltidy --assert-tidy).
#                                      This is the CI FMT gate.
#
# Formats BOTH hand-written AND generated code — the generated .pm tree is
# perltidy-clean by construction (the generators run the same perltidy backstop,
# scripts/_perltidy_gen.py), so --check stays green.
#
# NOTE: perltidy over the 1100+ generated .pm files is SLOW (a minute-plus) —
# that is expected work, not a hang.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"
_sw_ensure_perl_tools || exit 1

cd "$REPO_ROOT"

if ! command -v perltidy >/dev/null 2>&1; then
    echo "ERROR: perltidy not found on PATH after bootstrap. Install it with:" >&2
    echo "         cpanm --local-lib=\"\${PERL_LOCAL_LIB_ROOT:-\$HOME/perl5}\" Perl::Tidy" >&2
    exit 1
fi

CHECK=0
case "${1:-}" in
    --check) CHECK=1 ;;
    "") ;;
    *) echo "usage: run-format.sh [--check]" >&2; exit 2 ;;
esac

PROFILE="$REPO_ROOT/.perltidyrc"
rc=0

if [ "$CHECK" -eq 1 ]; then
    # VERIFY-ONLY: fail if any file is not already tidy. No writes.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        perltidy --profile="$PROFILE" --assert-tidy -nst -se --outfile=/dev/null "$f" || rc=1
    done < <(_sw_perl_source_files)
    if [ "$rc" -ne 0 ]; then
        echo "FMT: some files are not tidy — run 'bash scripts/run-format.sh' to fix." >&2
    fi
    exit "$rc"
fi

# APPLY: reformat in place (-b), deleting the .bak (-bext='/').
while IFS= read -r f; do
    [ -n "$f" ] || continue
    perltidy --profile="$PROFILE" -b -bext='/' "$f"
done < <(_sw_perl_source_files)

# A residual issue perltidy could not auto-fix must still surface as a failure.
while IFS= read -r f; do
    [ -n "$f" ] || continue
    perltidy --profile="$PROFILE" --assert-tidy -nst -se --outfile=/dev/null "$f" || rc=1
done < <(_sw_perl_source_files)

exit "$rc"
