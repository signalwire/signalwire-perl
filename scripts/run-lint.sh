#!/usr/bin/env bash
# scripts/run-lint.sh — the CANONICAL way to lint signalwire-perl.
#
# Tool: Perl::Critic (perlcritic) at severity 4, config .perlcriticrc, burned to
# ZERO findings. This is the SINGLE entry point for linting — run-ci, agents,
# humans, and docs all go through it; nothing invokes perlcritic directly
# anymore. Self-bootstraps its environment (scripts/_env.sh: the PERL5LIB fix
# that lets perlcritic locate Perl::Critic) so it works from ANY directory.
#
#   run-lint.sh          Run perlcritic sev 4 over the WHOLE Perl tree — the
#                        hand-written source (lib minus **/Generated/, + bin +
#                        Perl scripts) AND the generated lib/**/Generated/ tree;
#                        report findings; exit non-zero on ANY finding.
#   run-lint.sh --hand   Fast dev subset: lint ONLY the hand-written source,
#                        skipping the generated tree. NOT the blocking gate —
#                        the CI LINT gate lints everything (bare invocation).
#
# The generated tree IS linted by the blocking gate: the ~1107 generated .pm are
# emitted by the four code generators, which target perlcritic-clean output, so
# they are perlcritic-clean by construction — but the gate proves that on every
# run rather than trusting it (generated code is linted exactly like hand-written,
# no carve-out). `--hand` exists only as a faster inner-loop while iterating on
# hand-written code; it deliberately does NOT gate. Full-tree critique adds wall
# time (perlcritic is single-threaded per file, so the xargs -P fan-out below
# keeps it bounded), which is the price of not excluding generated code.
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
    echo "         cpanm --local-lib=\"\${PERL_LOCAL_LIB_ROOT:-\$HOME/perl5}\" Perl::Critic@$SW_PERLCRITIC_VERSION" >&2
    exit 1
fi

# Perl::Critic is pinned EXACT in the cpanfile because new releases add policies
# and tighten existing ones, and every policy at severity >= 4 is blocking here —
# so an unpinned analyser can red this gate on code nobody touched. Assert the
# LOADED version, not just the manifest: a local::lib populated before the pin was
# tightened keeps its old copy indefinitely.
_sw_assert_module_version Perl::Critic "$SW_PERLCRITIC_VERSION" || exit 1

SCOPE=all
case "${1:-}" in
    "")      ;;
    --hand)  SCOPE=hand ;;
    --all)   SCOPE=all ;;  # back-compat alias for the (now default) full-tree scope
    *) echo "usage: run-lint.sh [--hand]   (perlcritic has no autofix; report-only)" >&2; exit 2 ;;
esac

PROFILE="$REPO_ROOT/.perlcriticrc"

# Job count: cores minus a little headroom, floor 1.
_jobs() { local n; n="$( (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4)"; echo "$(( n > 2 ? n - 1 : 1 ))"; }

# Emit the file list for the selected scope. Default (all) = hand-written source
# PLUS the generated tree; --hand = hand-written only (fast dev subset).
_files() {
    _sw_perl_hand_source_files
    [ "$SCOPE" = all ] && _sw_perl_generated_source_files
    return 0
}

# Fan perlcritic across cores; ANY file with a finding makes the whole gate fail.
# xargs returns 123 if any invocation exited non-zero — map that to rc=1.
if _files | xargs -P "$(_jobs)" -I{} perlcritic --profile "$PROFILE" --severity 4 "{}"; then
    exit 0
else
    exit 1
fi
