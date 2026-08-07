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
# The generated tree IS linted by the blocking gate: the 1132 generated .pm are
# emitted by the four code generators, which target perlcritic-clean output, so
# they are perlcritic-clean by construction — but the gate proves that on every
# run rather than trusting it (generated code is linted exactly like hand-written,
# no carve-out). `--hand` exists only as a faster inner-loop while iterating on
# hand-written code; it deliberately does NOT gate. Full-tree critique adds wall
# time (perlcritic is single-threaded per file, so the xargs -P fan-out below
# keeps it bounded), which is the price of not excluding generated code.
#
# perlcritic has no autofix, so there is no --fix mode (report-only).
# Files are critiqued in PARALLEL (xargs -P) and in BATCHES (xargs -n 64) —
# perlcritic is single-threaded per file, so fan-out across cores is a straight
# speedup, and batching amortises its per-process policy-load startup across 64
# files instead of paying it once per file. Both are result-identical; see the
# invocation at the bottom of this file for the measurement.

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
#
# BATCHING (-n 64, NOT -I{}). `-I{}` forces exactly ONE perlcritic process PER
# FILE, and perlcritic's startup cost — loading Perl::Critic and compiling every
# policy module in the profile — dwarfs the actual critique of a small .pm.
# Across 1479 files (333 hand-written + 1146 generated) that startup was paid
# 1479 times. `-n 64` hands each process
# a BATCH so the policy set is loaded once per batch instead of once per file;
# perlcritic critiques each file in the batch independently and emits the SAME
# per-file output, so findings are unchanged (proven: sorted output byte-
# identical, same md5, 1479 lines both ways, and a negative control — an
# injected violation in a hand-written AND a generated file — still reds the
# gate). `-P` is retained — this is batching ON TOP of the existing fan-out,
# not a serialisation.
#   MEASURED apples-to-apples — same tree, same 1479-file list, same 7-way -P,
#   back-to-back on the same box:
#     -I{}  551.0s      -n 64  16.5s      = 33x
# Batch size 64 gives ~23 batches across 7 workers — enough chunks to keep every
# worker fed to the end (128 leaves ~12 chunks and balanced measurably worse).
# ARG_MAX is a non-issue: the longest 64-path batch here is 5.3 KB against a
# 1 MB ARG_MAX, and xargs self-limits by command length regardless.
if _files | xargs -P "$(_jobs)" -n 64 perlcritic --profile "$PROFILE" --severity 4; then
    exit 0
else
    exit 1
fi
