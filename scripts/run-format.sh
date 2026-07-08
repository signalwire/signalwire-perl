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
# Scope: only the HAND-WRITTEN Perl tree (_sw_perl_hand_source_files). The ~1107
# generated .pm under lib/**/Generated/ are NOT formatted here — they are
# perltidy-clean by construction (the four generators run the same perltidy
# backstop, scripts/_perltidy_gen.py, as their final emit pass) and the
# GEN-FRESH{,-SWML,-RELAY,-SWAIG} gates already byte-compare the on-disk generated
# tree against a fresh backstopped regen. Formatting them here would be redundant
# with GEN-FRESH and dominated the wall-clock (~1107 of 1186 files). See
# scripts/_env.sh (_sw_perl_hand_source_files) for the full rationale.
#
# Perltidy is per-file independent, so both modes fan out across cores with xargs
# (-P = nproc). --check collects a non-zero exit if ANY file is non-tidy.

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

export PERLTIDY_PROFILE="$REPO_ROOT/.perltidyrc"

# Parallelism: one perltidy per core. nproc (Linux) / hw.ncpu (macOS); default 4.
NCPU="$( { nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null; } | head -n1 )"
case "$NCPU" in ''|*[!0-9]*) NCPU=4 ;; esac

# Batch several files per perltidy invocation to amortize interpreter startup
# without starving cores (hand tree is ~79 files; -n8 gives ~10 batches).
BATCH=8

# assert-tidy (read-only) worker: exits non-zero if ANY file in its batch is not
# tidy, so xargs propagates a non-zero overall exit if ANY child failed.
_fmt_check_batch='rc=0; for f in "$@"; do perltidy --profile="$PERLTIDY_PROFILE" --assert-tidy -nst -se --outfile=/dev/null "$f" || rc=1; done; exit $rc'
# apply worker: reformat in place (-b), deleting the .bak (-bext='/').
_fmt_apply_batch='for f in "$@"; do perltidy --profile="$PERLTIDY_PROFILE" -b -bext="/" "$f" || exit 1; done'
export _fmt_check_batch _fmt_apply_batch

rc=0

if [ "$CHECK" -eq 1 ]; then
    # VERIFY-ONLY: fail if any file is not already tidy. No writes. xargs returns
    # non-zero (123) if any child exited non-zero, so a single non-tidy file in
    # ANY batch fails the gate.
    _sw_perl_hand_source_files \
        | grep -v '^[[:space:]]*$' \
        | xargs -P"$NCPU" -n"$BATCH" sh -c "$_fmt_check_batch" sh \
        || rc=1
    if [ "$rc" -ne 0 ]; then
        echo "FMT: some files are not tidy — run 'bash scripts/run-format.sh' to fix." >&2
    fi
    exit "$rc"
fi

# APPLY: reformat in place across cores.
_sw_perl_hand_source_files \
    | grep -v '^[[:space:]]*$' \
    | xargs -P"$NCPU" -n"$BATCH" sh -c "$_fmt_apply_batch" sh \
    || rc=1

# A residual issue perltidy could not auto-fix must still surface as a failure:
# re-verify (parallel) after applying.
_sw_perl_hand_source_files \
    | grep -v '^[[:space:]]*$' \
    | xargs -P"$NCPU" -n"$BATCH" sh -c "$_fmt_check_batch" sh \
    || rc=1

exit "$rc"
