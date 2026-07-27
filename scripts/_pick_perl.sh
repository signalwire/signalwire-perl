#!/usr/bin/env bash
# scripts/_pick_perl.sh — choose the ONE Perl interpreter the gates should use.
#
# Prints an absolute path (or a bare `perl`) on stdout. Used by scripts/_env.sh to
# set $SW_PERL; not meant to be called directly, but harmless if it is.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS — "first perl on PATH" is wrong on Windows
# ---------------------------------------------------------------------------
# A Windows runner has several Perls at once (nightly Multi-OS run 30238072907):
#   1. what actions-setup-perl installed and exported PERL5LIB for
#      (C:\hostedtoolcache\windows\perl\<ver>\x64) — the one we WANT;
#   2. Strawberry's (C:\Strawberry\perl\bin) — ships with the runner image;
#   3. MSYS/Git-for-Windows perl (/usr/bin/perl, /usr/share/perl5/core_perl).
#
# The steps run under `shell: bash` = C:\Program Files\Git\bin\bash.EXE, which
# injects the MSYS /usr/bin AHEAD of whatever actions-setup-perl prepended to the
# Windows PATH. So `command -v perl` yields #3 — precisely the install whose @INC
# has no TAP::Harness::Env. Measured: run 30239532589, after the harness was
# correctly routed through $SW_PERL, still failed with
#   ERROR: /usr/bin/perl cannot load App::Prove
# because SW_PERL had been resolved with `command -v perl`.
#
# THE RULE: select on EVIDENCE, not on PATH position — the right interpreter is
# one that can actually load the harness. We probe candidates for App::Prove and
# take the first that succeeds. That is self-validating: it cannot pick an
# interpreter that would then fail the way #2/#3 did.
#
# Ordering rationale: the toolcache install (#1) is tried FIRST because it is the
# one the workflow provisioned and set PERL5LIB for — using any other install
# would silently ignore the deps `cpanm --installdeps` just installed into it.
# Bare `perl` is tried before Strawberry so a normal POSIX box (where PATH perl is
# simply correct) resolves immediately and this whole dance is a no-op.

set -uo pipefail

# Does this interpreter exist AND can it load the test harness?
_usable() {
    [ -n "${1:-}" ] || return 1
    command -v "$1" >/dev/null 2>&1 || return 1
    "$1" -MApp::Prove -e1 >/dev/null 2>&1
}

_candidates() {
    # 1. Whatever actions-setup-perl put in the hosted toolcache. RUNNER_TOOL_CACHE
    #    is set by GitHub Actions; glob every installed version/arch under it.
    #    Newest-first so a multi-version cache prefers the latest.
    if [ -n "${RUNNER_TOOL_CACHE:-}" ] && [ -d "$RUNNER_TOOL_CACHE/perl" ]; then
        # Layout is <cache>/perl/<version>/<arch>/bin/perl[.exe] — depth 4 below
        # <cache>/perl. Newest-first so a multi-version cache prefers the latest.
        find "$RUNNER_TOOL_CACHE/perl" -mindepth 4 -maxdepth 4 -type f \
            \( -name 'perl.exe' -o -name 'perl' \) 2>/dev/null | sort -Vr
    fi

    # 2. The ordinary case: whatever `perl` PATH offers. On POSIX this is the
    #    right answer and the loop below stops here.
    command -v perl 2>/dev/null

    # 3. Strawberry, as a last resort on Windows images.
    for p in /c/Strawberry/perl/bin/perl.exe /c/Strawberry/perl/bin/perl \
             "C:/Strawberry/perl/bin/perl.exe"; do
        [ -x "$p" ] && echo "$p"
    done
}

# First candidate that can load App::Prove wins.
while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    if _usable "$cand"; then
        echo "$cand"
        exit 0
    fi
done <<EOF
$(_candidates)
EOF

# Nothing could load App::Prove. Emit the best-available interpreter anyway so the
# CALLER fails loud with its own actionable message (run-tests.sh names the
# interpreter and how to fix it) rather than this helper dying cryptically here.
fallback="$(command -v perl 2>/dev/null || true)"
echo "${fallback:-perl}"
