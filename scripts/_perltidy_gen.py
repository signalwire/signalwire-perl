"""Shared perltidy backstop for the Perl code generators (AGENT_RULES §5).

The generators emit Perl targeting perltidy's style directly, but perltidy also
applies context-dependent ALIGNMENT (consecutive `has` `=>` columns, trailing
`()` on use-lines, long method-call wrapping) that a straight-line emitter can't
reproduce by hand. Running perltidy over every generated ``.pm`` as a final pass
makes a fresh regen byte-identical to ``perltidy --assert-tidy`` output, so
GEN-FRESH (compares generator output to disk) and the FMT gate (asserts tidy on
disk) BOTH pass simultaneously.

Usage in a generator's ``build_outputs`` (just before ``return outs``)::

    from _perltidy_gen import perltidy_outputs
    perltidy_outputs(outs, repo_root())
"""

from __future__ import annotations

import os
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def perltidy_bin() -> str:
    """Locate perltidy, matching the FMT gate. Fail loud if absent."""
    for cand in (
        os.environ.get("PERLTIDY"),
        shutil.which("perltidy"),
        str(Path.home() / "perl5" / "bin" / "perltidy"),
    ):
        if cand and Path(cand).is_file():
            return cand
    raise SystemExit(
        "perltidy not found (needed for the §5 generated-code format backstop); "
        "set PERLTIDY or install perltidy so generated output is FMT-clean at emit."
    )


def perltidy_env() -> dict:
    """Environment for the perltidy subprocess, with the local::lib on @INC.

    FINDING perltidy is not enough to RUN it. ``~/perl5/bin/perltidy`` is a thin
    wrapper whose shebang is ``#!/usr/bin/perl`` -- SYSTEM perl, whose default
    ``@INC`` does NOT include ``~/perl5/lib/perl5`` where ``Perl::Tidy.pm`` was
    installed. So the wrapper can never load its own module unless PERL5LIB says
    where it is, and every generator died with "Can't locate Perl/Tidy.pm in @INC"
    even though ``perltidy`` resolved and ``cpanm`` reported it "up to date".

    scripts/_env.sh already exports exactly this PERL5LIB, and CLAUDE.md documents
    _env.sh as what "makes the code generators' perltidy backstop work from any
    CWD" -- but a generator invoked directly (``python3 scripts/generate_rest.py``,
    which is how the GEN-FRESH gate and every agent runs it) never sources a bash
    script, so the guarantee did not hold. Applying it here makes it true for EVERY
    caller regardless of shell setup, which is what the doc already promises.

    Respects an existing PERL5LIB (prepends, never clobbers) and honours
    PERL_LOCAL_LIB_ROOT the same way _env.sh does.
    """
    env = dict(os.environ)
    ll_root = Path(env.get("PERL_LOCAL_LIB_ROOT") or (Path.home() / "perl5"))
    ll_lib = ll_root / "lib" / "perl5"
    if ll_lib.is_dir():
        existing = env.get("PERL5LIB", "")
        parts = [p for p in existing.split(os.pathsep) if p]
        if str(ll_lib) not in parts:
            env["PERL5LIB"] = os.pathsep.join([str(ll_lib), *parts])
    return env


def perltidy_outputs(outs: dict, repo_root: Path) -> None:
    """Tidy every ``.pm`` value in ``outs`` in place using the repo .perltidyrc.

    ``-st`` reads stdin / writes stdout; ``-se`` sends errors to stderr (so no
    ``.ERR`` sidecar files are written). Deterministic: same input -> same output.

    Each file's tidy is an independent subprocess, so they run CONCURRENTLY across
    cores — perltidy over the ~1186 generated files was the bulk of the GEN-FRESH
    gate's wall-clock; fanning out is a straight speedup with identical output
    (each ``.pm`` is tidied in isolation; order is irrelevant).
    """
    tidy = perltidy_bin()
    env = perltidy_env()
    profile = repo_root / ".perltidyrc"
    targets = [fn for fn in outs if fn.endswith(".pm")]

    def _tidy_one(fn: str) -> tuple[str, str]:
        proc = subprocess.run(
            [tidy, f"-pro={profile}", "-st", "-se"],
            input=outs[fn],
            capture_output=True,
            text=True,
            env=env,
        )
        if proc.returncode != 0 or not proc.stdout:
            raise SystemExit(f"perltidy failed on generated {fn}:\n{proc.stderr}")
        return fn, proc.stdout

    # Threads are the right pool: the work is entirely in the perltidy subprocess
    # (GIL released during subprocess.run). Cap workers at cores (min headroom).
    workers = max(1, (os.cpu_count() or 4) - 1)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for fn, tidied in pool.map(_tidy_one, targets):
            outs[fn] = tidied
