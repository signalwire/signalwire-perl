#!/usr/bin/env bash
# scripts/run-tests.sh — the CANONICAL way to run signalwire-perl's tests.
#
# Tool: App::Prove (-Ilib -It/lib -r t/), driven through $SW_PERL. This is the
# SINGLE entry point for testing — run-ci, agents, humans, and docs all go
# through it; nothing invokes prove directly anymore. Self-bootstraps its
# environment (scripts/_env.sh: $SW_PERL, the platform-correct PERL5LIB, and the
# local::lib runtime deps — Plack, Protocol::WebSocket, etc. — on @INC) so the
# suite works from ANY directory with ANY shell setup, on POSIX AND Windows.
#
# Why NOT a bare `prove` (nightly Multi-OS run 30238072907): on a Windows runner
# PATH offered Strawberry's `prove`, whose @INC then resolved App::Prove from an
# MSYS core_perl that has no TAP::Harness::Env — a `prove` from one Perl install
# loading modules from another. Running the harness MODULE through $SW_PERL makes
# the interpreter and its @INC the same install by construction, so there is no
# PATH-order question left to get wrong. See scripts/_env.sh for the full note.
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

# Fail LOUD, with the interpreter named, if the chosen perl can't load the
# harness — far more actionable than prove's raw @INC dump.
if ! _sw_perl_has_module App::Prove; then
    echo "ERROR: $SW_PERL cannot load App::Prove (part of core perl / Test::Harness)." >&2
    echo "       Install it for THAT interpreter, or point SW_PERL at one that has it:" >&2
    echo "         cpanm --notest Test::Harness" >&2
    exit 1
fi

# Run tests in PARALLEL (prove -j) — the test suite is the CI wall-clock driver (~11min
# serial); the mock-using tests are concurrency-safe (each picks its own free port via
# PortPicker when MOCK_*_PORT isn't the pre-spawned one — see t/lib/MockTest.pm), so
# fanning across cores is a straight win. Measured green + ~3.5x on t/rest/. Job count =
# cores (min 1); override with PROVE_JOBS.
jobs="${PROVE_JOBS:-$( (command -v nproc >/dev/null && nproc) || sysctl -n hw.ncpu 2>/dev/null || echo 4 )}"

# --- Win32: clamp to -j1, because the HARNESS cannot multiplex there. ---------
#
# THIS IS NOT "serialise the tests to make them pass." The tests are genuinely
# concurrency-safe (each picks its own free port via PortPicker) and STAY PARALLEL
# on POSIX, where the ~3.5x above was measured. This is a platform limitation of
# Test::Harness itself, in its own source:
#
#   TAP/Parser/Multiplexer.pm:12
#     use constant SELECT_OK => !( IS_VMS || IS_WIN32 );
#
# With SELECT_OK false, NO parser is ever added to the IO::Select set (line 84);
# every one goes on the `avid` "can't select" list instead. `_iter` then drains
# `avid->[0]` to completion before looking at any other parser — it BLOCKS on
# $parser->next for the first job. So `-j4` on Windows does not fan out: it spawns
# 4 children, reads exactly one, and the unread siblings fill their pipe buffers
# with nobody draining them and wedge. (TAP/Parser/Iterator/Process.pm:95 shows the
# same fork dependency: `return unless $Config{d_fork} || $IS_WIN32` — Win32 has no
# real fork, only interpreter-thread emulation.)
#
# Observed twice on the nightly Multi-OS lane: run 30240112956 (4h57m, cancelled)
# and 30258476574 (still wedged at 40min), both with NOT ONE line of captured TEST
# output — prove emitted nothing at all before hanging, which is exactly what
# blocking on an un-drained child looks like. macOS finished the same suite in
# 2m37s on that run.
#
# So on Win32 -j>1 is not slow, it is BROKEN. Clamp to 1: slower than POSIX, but
# finite. An explicit PROVE_JOBS still wins (override deliberately, e.g. to
# re-test the harness behaviour) — the clamp only overrides the core-count default.
case "${OSTYPE:-}" in
    msys* | cygwin* | win32*) _sw_is_win32=1 ;;
    *) _sw_is_win32="$("$SW_PERL" -e 'print(($^O =~ /^(MS)?Win32$/) ? 1 : 0)' 2>/dev/null || echo 0)" ;;
esac
if [ "${_sw_is_win32:-0}" = "1" ] && [ -z "${PROVE_JOBS:-}" ] && [ "$jobs" != "1" ]; then
    echo "==> run-tests.sh: Win32 detected — clamping prove to -j1 (Test::Harness" >&2
    echo "    cannot select() on Win32, so -j>1 wedges; see the note above)." >&2
    jobs=1
fi

# Optional filter passthrough: default to the whole tree, else run exactly what
# the caller named.
# The body of the real `prove` script, inlined verbatim: process_args() is called
# in VOID context (it returns nothing — it is NOT chainable, so
# `->process_args(@ARGV)->run` dies with "Can't call method run on an undefined
# value"), and run() returns a BOOLEAN that must be mapped to an exit code, or a
# failing suite would exit 0 and the gate would pass on red.
# `_sw_perl_tool` is a shell FUNCTION, so it cannot be `exec`'d — run it and let
# its exit status propagate (set -e is in force).
PROVE_ENTRY='my $a = App::Prove->new; $a->process_args(@ARGV); exit($a->run ? 0 : 1);'

if [ "$#" -eq 0 ]; then
    _sw_perl_tool App::Prove "$PROVE_ENTRY" -j"$jobs" -Ilib -It/lib -r t/
else
    _sw_perl_tool App::Prove "$PROVE_ENTRY" -j"$jobs" -Ilib -It/lib -r "$@"
fi
