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


def perltidy_outputs(outs: dict, repo_root: Path) -> None:
    """Tidy every ``.pm`` value in ``outs`` in place using the repo .perltidyrc.

    ``-st`` reads stdin / writes stdout; ``-se`` sends errors to stderr (so no
    ``.ERR`` sidecar files are written). Deterministic: same input -> same output.
    """
    tidy = perltidy_bin()
    profile = repo_root / ".perltidyrc"
    for fn in list(outs):
        if not fn.endswith(".pm"):
            continue
        proc = subprocess.run(
            [tidy, f"-pro={profile}", "-st", "-se"],
            input=outs[fn],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0 or not proc.stdout:
            raise SystemExit(
                f"perltidy failed on generated {fn}:\n{proc.stderr}"
            )
        outs[fn] = proc.stdout
