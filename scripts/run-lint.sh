#!/usr/bin/env bash
# scripts/run-lint.sh — the CANONICAL way to lint signalwire-perl.
#
# Tool: Perl::Critic (perlcritic) at severity 4, config .perlcriticrc, burned to
# ZERO findings. This is the SINGLE entry point for linting — run-ci, agents,
# humans, and docs all go through it; nothing invokes perlcritic directly
# anymore. Self-bootstraps its environment (scripts/_env.sh: the PERL5LIB fix
# that lets perlcritic locate Perl::Critic) so it works from ANY directory.
#
#   run-lint.sh    Run perlcritic sev 4 over lib/ + bin/ + Perl scripts; report
#                  findings; exit non-zero on ANY finding.
#
# perlcritic has no autofix, so there is no --fix mode (report-only).

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

case "${1:-}" in
    "") ;;
    *) echo "usage: run-lint.sh   (perlcritic has no autofix; report-only)" >&2; exit 2 ;;
esac

PROFILE="$REPO_ROOT/.perlcriticrc"
rc=0

# severity pinned both in .perlcriticrc and on the command line so this
# reproduces a bare `perlcritic --severity 4 lib/`.
while IFS= read -r f; do
    [ -n "$f" ] || continue
    perlcritic --profile "$PROFILE" --severity 4 "$f" || rc=1
done < <(_sw_perl_source_files)

exit "$rc"
