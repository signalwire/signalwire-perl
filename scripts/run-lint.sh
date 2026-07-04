#!/usr/bin/env bash
# scripts/run-lint.sh — the CANONICAL way to lint signalwire-perl.
#
# Tool: Perl::Critic (perlcritic) at severity 4, config .perlcriticrc, burned to
# ZERO findings. This is the SINGLE entry point for linting — run-ci, agents,
# humans, and docs all go through it; nothing invokes perlcritic directly
# anymore. Self-bootstraps its environment (scripts/_env.sh: the PERL5LIB fix
# that lets perlcritic locate Perl::Critic) so it works from ANY directory.
#
#   run-lint.sh          Run perlcritic sev 4 over the HAND-WRITTEN Perl (lib
#                        minus **/Generated/, + bin + Perl scripts); report
#                        findings; exit non-zero on ANY finding.
#   run-lint.sh --all    Also lint the generated lib/**/Generated/ tree.
#
# Why default scope skips the generated tree (same rationale as the FMT gate,
# see _sw_perl_hand_source_files in _env.sh): the ~1107 generated .pm are emitted
# by the four code generators, which target perlcritic-clean output; the
# generated tree is perlcritic-clean by construction and re-critiquing it every
# CI run was ~90% of this gate's wall-clock (507s -> ~15s by skipping it). A
# generator that ever emitted a sev-4 finding would surface it via `--all` (run
# in the generator's own test path) — the on-disk copy can't drift independently
# of the generator, because GEN-FRESH byte-compares disk against a fresh regen.
#
# perlcritic has no autofix, so there is no --fix mode (report-only).
# Files are critiqued in PARALLEL (xargs -P) — perlcritic is single-threaded
# per file, so fan-out across cores is a straight speedup with identical results.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"
_sw_ensure_perl_tools || exit 1

cd "$REPO_ROOT"

if ! command -v perlcritic >/dev/null 2>&1; then
    echo "ERROR: perlcritic not found on PATH after bootstrap. Install it with:" >&2
    echo "         cpanm --local-lib=\"\${PERL_LOCAL_LIB_ROOT:-\$HOME/perl5}\" Perl::Critic" >&2
    exit 1
fi

SCOPE=hand
case "${1:-}" in
    "")     ;;
    --all)  SCOPE=all ;;
    *) echo "usage: run-lint.sh [--all]   (perlcritic has no autofix; report-only)" >&2; exit 2 ;;
esac

PROFILE="$REPO_ROOT/.perlcriticrc"

# Job count: cores minus a little headroom, floor 1.
_jobs() { local n; n="$( (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4)"; echo "$(( n > 2 ? n - 1 : 1 ))"; }

# Emit the file list for the selected scope. Default = hand-written only; --all
# appends the generated tree (severity pinned on the CLI too, matching a bare
# `perlcritic --severity 4 lib/`).
_files() {
    _sw_perl_hand_source_files
    [ "$SCOPE" = all ] && find lib -type f -name '*.pm' -path '*/Generated/*'
    return 0
}

# Fan perlcritic across cores; ANY file with a finding makes the whole gate fail.
# xargs returns 123 if any invocation exited non-zero — map that to rc=1.
if _files | xargs -P "$(_jobs)" -I{} perlcritic --profile "$PROFILE" --severity 4 "{}"; then
    exit 0
else
    exit 1
fi
