#!/usr/bin/env bash
# scripts/_env.sh — shared tool-environment bootstrap for signalwire-perl.
#
# Sourced (never executed) by run-format.sh / run-lint.sh / run-tests.sh and by
# run-ci.sh, so the Perl toolchain (perltidy, perlcritic, and the runtime deps
# the test suite + code generators need) resolves NO MATTER what directory the
# caller invokes from and NO MATTER how bare the caller's shell is.
#
# ---------------------------------------------------------------------------
# THE BUG THIS FIXES
# ---------------------------------------------------------------------------
# The dev toolchain lives in a local::lib at ~/perl5 (the convention documented
# in CLAUDE.md and set up by the CI `cpanm` bootstrap):
#     perltidy          -> ~/perl5/bin/perltidy
#     perlcritic        -> ~/perl5/bin/perlcritic
#     Perl::Tidy        -> ~/perl5/lib/perl5/Perl/Tidy.pm
#     (+ Plack/WebSocket/... runtime deps under ~/perl5/lib/perl5)
#
# Neither ~/perl5/bin nor ~/perl5/lib/perl5 is on the default PATH / @INC. The
# nasty part: `~/perl5/bin/perltidy` is a thin wrapper that `use`s Perl::Tidy —
# it does NOT add its own local::lib to @INC — so running it from a bare shell
# dies with `Can't locate Perl/Tidy.pm in @INC` EVEN when you give the full
# path. The GENERATORS' perltidy backstop (scripts/_perltidy_gen.py) shells out
# to that same binary, so `python3 scripts/generate_rest.py --check` (GEN-FRESH)
# fails from a bare shell for the same reason. Exporting PERL5LIB (so the wrapper
# can find Perl::Tidy) + PATH (so `perltidy`/`perlcritic` resolve by name) fixes
# ALL of it: the three scripts, run-ci, and the generators.
#
# Idempotent + side-effect-free to source. Keyed off $HOME (never a hard-coded
# path); the same $HOME + existence guards run-ci already used, so CI (deps on
# the system perl, already on @INC/PATH) is unaffected.

# Resolve the repo root from THIS file's own location (works when sourced from
# any CWD). BASH_SOURCE[0] is _env.sh even when sourced.
_ENV_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$_ENV_SH_DIR")"
export REPO_ROOT

# ---------------------------------------------------------------------------
# SW_PERL — the ONE interpreter every gate must use, and PERL5LIB's separator
# ---------------------------------------------------------------------------
# On a Windows runner, three Perls are typically in play at once and mixing them
# is fatal (nightly Multi-OS run 30238072907):
#   1. the one `actions-setup-perl` installed and set PERL5LIB for
#      (C:\hostedtoolcache\windows\perl\5.38.5-thr\x64) — the one we WANT;
#   2. Strawberry's (C:\Strawberry\perl\bin) — ships with the runner image;
#   3. an MSYS/Git-for-Windows core_perl (/usr/share/perl5/core_perl) — comes
#      with the `shell: bash` (C:\Program Files\Git\bin\bash.EXE) the step runs in.
# The step ran Strawberry's `prove`, which then resolved App::Prove out of the
# MSYS core_perl and died: "Can't locate TAP/Harness/Env.pm in @INC". A `prove`
# from one install loading modules from another CANNOT work. Resolving the
# interpreter (not the script) and running the harness THROUGH it makes the
# interpreter and its @INC the same install by construction.
#
# SW_PERL honours an explicit override, else takes the first `perl` on PATH.
# Callers must invoke "$SW_PERL", never a bare `prove`/`perltidy`/`perlcritic`
# whose own shebang picks a DIFFERENT perl than the one we resolved.
SW_PERL="${SW_PERL:-$(command -v perl 2>/dev/null || echo perl)}"
export SW_PERL

# PERL5LIB's separator is PLATFORM-DEPENDENT: ':' on POSIX, ';' on Win32 (where
# paths carry drive letters, so ':' cannot be a separator). Hardcoding ':' here
# corrupted the Windows value — perl split `D:\a\...\perl5;D:\a\...` on ':' and
# @INC came out as the entries `D`, `\a\...\perl5;D`, `\a\...`: every ':' eaten,
# still ';'-joined, not one usable directory among them. Ask the interpreter we
# actually resolved (never assume), and fall back to ':' only if that fails.
SW_PATH_SEP="$("$SW_PERL" -MConfig -e 'print $Config{path_sep}' 2>/dev/null)"
[ -n "$SW_PATH_SEP" ] || SW_PATH_SEP=':'
export SW_PATH_SEP

# The local::lib root — override with PERL_LOCAL_LIB_ROOT, else ~/perl5.
PERL_LL_ROOT="${PERL_LOCAL_LIB_ROOT:-$HOME/perl5}"

# --- PERL5LIB: so the perltidy/perlcritic wrappers (and the test suite, and the
#     generators' perltidy backstop) can locate Perl::Tidy / Perl::Critic / the
#     runtime deps. Prepend with the PLATFORM separator, preserving any existing
#     PERL5LIB (on Windows that is the ';'-joined value setup-perl exported —
#     splitting or re-joining it on ':' destroys it). ---------------------------
if [ -d "$PERL_LL_ROOT/lib/perl5" ]; then
    export PERL5LIB="$PERL_LL_ROOT/lib/perl5${PERL5LIB:+$SW_PATH_SEP$PERL5LIB}"
fi

# --- PATH: so `perltidy` / `perlcritic` resolve by bare name. ----------------
if [ -d "$PERL_LL_ROOT/bin" ]; then
    export PATH="$PERL_LL_ROOT/bin:$PATH"
fi

# --- PERLTIDY: pin the binary the generators' backstop (_perltidy_gen.py) uses
#     to the local::lib copy, so GEN-FRESH uses the same perltidy as the FMT
#     gate regardless of what else is on PATH. Only when it exists. -----------
if [ -x "$PERL_LL_ROOT/bin/perltidy" ]; then
    export PERLTIDY="$PERL_LL_ROOT/bin/perltidy"
fi

# --- Bootstrap the dev-deps if perltidy/perlcritic still aren't resolvable. ---
# CI installs them onto the system perl (skip via $CI). A fresh LOCAL checkout
# may have neither; self-heal by installing the cpanfile `develop` block into
# the local::lib, then re-expose it. If cpanm is unavailable we FAIL LOUD with an
# actionable hint (the caller — a gate script — will then exit non-zero, never
# silently pass).
_sw_ensure_perl_tools() {
    [ -n "${CI:-}" ] && return 0                    # CI installs its own deps
    if command -v perltidy >/dev/null 2>&1 \
        && command -v perlcritic >/dev/null 2>&1 \
        && perl -MPerl::Tidy -e1 >/dev/null 2>&1; then
        return 0                                     # already fully resolvable
    fi
    if ! command -v cpanm >/dev/null 2>&1; then
        echo "ERROR: perltidy/perlcritic (Perl::Tidy/Perl::Critic) not resolvable and" >&2
        echo "       cpanm is unavailable to bootstrap them. Install App::cpanminus, then:" >&2
        echo "         cpanm --local-lib=$PERL_LL_ROOT --with-develop --installdeps $REPO_ROOT" >&2
        return 1
    fi
    echo "==> _env.sh: bootstrapping Perl dev-deps (Perl::Tidy, Perl::Critic) into $PERL_LL_ROOT ..." >&2
    cpanm --local-lib="$PERL_LL_ROOT" --notest --quiet --with-develop \
        --installdeps "$REPO_ROOT" >&2 || {
        echo "ERROR: dev-dep bootstrap failed; see cpanm output above. Try manually:" >&2
        echo "         cpanm --local-lib=$PERL_LL_ROOT --with-develop --installdeps $REPO_ROOT" >&2
        return 1
    }
    # Re-expose the now-populated local::lib (platform separator, as above).
    [ -d "$PERL_LL_ROOT/lib/perl5" ] && export PERL5LIB="$PERL_LL_ROOT/lib/perl5${PERL5LIB:+$SW_PATH_SEP$PERL5LIB}"
    [ -d "$PERL_LL_ROOT/bin" ] && export PATH="$PERL_LL_ROOT/bin:$PATH"
    [ -x "$PERL_LL_ROOT/bin/perltidy" ] && export PERLTIDY="$PERL_LL_ROOT/bin/perltidy"
    return 0
}

# ---------------------------------------------------------------------------
# Running a Perl-shipped CLI tool through the RESOLVED interpreter
# ---------------------------------------------------------------------------
# `prove`, `perltidy` and `perlcritic` are all Perl SCRIPTS with a shebang. Two
# ways that betrays us:
#   * PATH order picks a script belonging to a DIFFERENT perl install than
#     $SW_PERL (the Windows failure above: Strawberry's prove, MSYS's App::Prove);
#   * even with an absolute path, the shebang (`#!/usr/bin/perl`) re-launches
#     SYSTEM perl, whose @INC lacks the local::lib — which is why a full path to
#     ~/perl5/bin/perltidy still died with "Can't locate Perl/Tidy.pm" (see the
#     BUG note at the top of this file).
# Both vanish if we run the tool's MODULE through $SW_PERL: one interpreter, its
# own @INC, no shebang and no PATH lookup in the loop.
#
#   _sw_perl_tool <Module::Name> <entry-perl-code> [args...]
#
# `App::Prove`'s documented programmatic entry point is
# `App::Prove->new->process_args(@ARGV)->run`; perltidy/perlcritic keep using
# their wrappers (they are found via PATH but now under the corrected PERL5LIB).
_sw_perl_tool() {
    local module="$1" entry="$2"
    shift 2
    "$SW_PERL" "-M$module" -e "$entry" -- "$@"
}

# True when $SW_PERL can load the named module — use to fail LOUD with a real
# diagnostic instead of letting a tool die with a confusing @INC dump.
_sw_perl_has_module() {
    "$SW_PERL" "-M$1" -e1 >/dev/null 2>&1
}

# The set of Perl source files the FMT + LINT gates police: every module under
# lib/ plus the repo's hand-written Perl tooling (bin/ + the Perl scripts). Kept
# in ONE place here so run-format.sh and run-lint.sh police EXACTLY the same
# files (and it stays in sync with run-ci's historical list). Emits one path per
# line, relative to the repo root; callers run from "$REPO_ROOT".
#
# This is the FULL list — it INCLUDES the ~1107 generated .pm under
# lib/**/Generated/. run-lint.sh (perlcritic) uses this: perlcritic has no
# in-generator backstop, so LINT must keep covering the generated tree.
_sw_perl_source_files() {
    _sw_perl_hand_source_files
    find lib -type f -name '*.pm' -path '*/Generated/*'
}

# The HAND-WRITTEN subset only — the generated .pm under lib/**/Generated/ are
# EXCLUDED. Used by the FMT gate (run-format.sh) exclusively.
#
# Why the FMT gate can skip the generated tree: those files are perltidy-clean BY
# CONSTRUCTION — the four code generators run the identical perltidy backstop
# (scripts/_perltidy_gen.py) as their final emit pass, and the
# GEN-FRESH{,-SWML,-RELAY,-SWAIG} gates byte-compare the on-disk generated tree
# against a fresh (backstopped) regen. So "generated tree is tidy" is already
# PROVEN by GEN-FRESH; re-running perltidy over it in the FMT gate is redundant
# work that dominated run-format.sh's wall-clock (~1107 of 1186 files). If a
# generated file ever drifted non-tidy, GEN-FRESH would catch it (the regen would
# no longer match disk). The FMT gate therefore polices only the hand-written
# tree, where perltidy is the only backstop. (LINT still covers everything via
# _sw_perl_source_files above — perlcritic has no generator backstop.)
_sw_perl_hand_source_files() {
    find lib -type f -name '*.pm' -not -path '*/Generated/*'
    echo bin/emit-corpus.pl
    echo bin/emit-skills.pl
    echo bin/swaig-test
    echo scripts/enumerate_surface.pl
    echo scripts/signature_dump.pl
    echo scripts/route_registry.pl
    echo scripts/rest_test_plan.pl
}
