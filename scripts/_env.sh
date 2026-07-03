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

# The local::lib root — override with PERL_LOCAL_LIB_ROOT, else ~/perl5.
PERL_LL_ROOT="${PERL_LOCAL_LIB_ROOT:-$HOME/perl5}"

# --- PERL5LIB: so the perltidy/perlcritic wrappers (and the test suite, and the
#     generators' perltidy backstop) can locate Perl::Tidy / Perl::Critic / the
#     runtime deps. Prepend, preserving any existing PERL5LIB. -----------------
if [ -d "$PERL_LL_ROOT/lib/perl5" ]; then
    export PERL5LIB="$PERL_LL_ROOT/lib/perl5${PERL5LIB:+:$PERL5LIB}"
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
    # Re-expose the now-populated local::lib.
    [ -d "$PERL_LL_ROOT/lib/perl5" ] && export PERL5LIB="$PERL_LL_ROOT/lib/perl5${PERL5LIB:+:$PERL5LIB}"
    [ -d "$PERL_LL_ROOT/bin" ] && export PATH="$PERL_LL_ROOT/bin:$PATH"
    [ -x "$PERL_LL_ROOT/bin/perltidy" ] && export PERLTIDY="$PERL_LL_ROOT/bin/perltidy"
    return 0
}

# The set of Perl source files the FMT + LINT gates police: every module under
# lib/ plus the repo's hand-written Perl tooling (bin/ + the Perl scripts). Kept
# in ONE place here so run-format.sh and run-lint.sh police EXACTLY the same
# files (and it stays in sync with run-ci's historical list). Emits one path per
# line, relative to the repo root; callers run from "$REPO_ROOT".
_sw_perl_source_files() {
    find lib -type f -name '*.pm'
    echo bin/emit-corpus.pl
    echo bin/emit-skills.pl
    echo bin/swaig-test
    echo scripts/enumerate_surface.pl
    echo scripts/signature_dump.pl
    echo scripts/route_registry.pl
    echo scripts/rest_test_plan.pl
}
