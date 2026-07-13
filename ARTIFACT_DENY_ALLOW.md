# Artifact-deny allowlist

These files are TRACKED in the repo (they are the porting-audit contract + in-repo
audit tooling) but are EXCLUDED from the published CPAN distribution by
`MANIFEST.SKIP`. The `git ls-files` proxy flags them, but the authoritative package
listing is clean:

    perl -MExtUtils::Manifest=maniskip -e '...apply MANIFEST.SKIP to MANIFEST...' \
      | python3 ~/src/porting-sdk/scripts/artifact_deny.py --port perl --listing -
    => [artifact-deny] perl: clean

Each entry below is proven to be excluded from `make dist` by a corresponding
`MANIFEST.SKIP` rule (verified 2026-07-06); it ships in-repo only.

- CHECKLIST.md — audit contract; excluded from dist via MANIFEST.SKIP ^CHECKLIST\.md$ (orchestrator, 2026-07-06)
- DOC_AUDIT_IGNORE.md — audit contract; excluded via MANIFEST.SKIP ^DOC_AUDIT_IGNORE\.md$ (orchestrator, 2026-07-06)
- PORT_ADDITIONS.md — audit contract; excluded via MANIFEST.SKIP ^PORT_.*\.md$ (orchestrator, 2026-07-06)
- PORT_EXAMPLE_OMISSIONS.md — audit contract; excluded via MANIFEST.SKIP ^PORT_.*\.md$ (orchestrator, 2026-07-06)
- PORT_OMISSIONS.md — audit contract; excluded via MANIFEST.SKIP ^PORT_.*\.md$ (orchestrator, 2026-07-06)
- PORT_SIGNATURE_OMISSIONS.md — audit contract; excluded via MANIFEST.SKIP ^PORT_.*\.md$ (orchestrator, 2026-07-06)
- PORT_TEST_OMISSIONS.md — audit contract; excluded via MANIFEST.SKIP ^PORT_.*\.md$ (orchestrator, 2026-07-06)
- REST_COVERAGE_GAPS.md — audit contract; excluded via MANIFEST.SKIP ^REST_COVERAGE_GAPS\.md$ (orchestrator, 2026-07-06)
- audit_coverage.json — audit contract; excluded via MANIFEST.SKIP ^audit_coverage.*\.json$ (orchestrator, 2026-07-06)
- audit_coverage_baseline.json — audit contract; excluded via MANIFEST.SKIP ^audit_coverage.*\.json$ (orchestrator, 2026-07-06)
- port_signatures.json — audit contract; excluded via MANIFEST.SKIP ^port_signatures.*\.json$ (orchestrator, 2026-07-06)
- port_signatures.baseline.json — load-bearing SEMVER-DIFF release-floor file; mirrors port_signatures.json; must be at root, must not ship; excluded via MANIFEST.SKIP ^port_signatures.*\.json$ (orchestrator, 2026-07-13)
- port_surface.json — audit contract; excluded via MANIFEST.SKIP ^port_surface.*\.json$ (orchestrator, 2026-07-06)
- examples/relay_audit_harness.pl — in-repo audit tooling; excluded via MANIFEST.SKIP ^examples/.*audit_harness.*\.pl$ (orchestrator, 2026-07-06)
- examples/rest_audit_harness.pl — in-repo audit tooling; excluded via MANIFEST.SKIP ^examples/.*audit_harness.*\.pl$ (orchestrator, 2026-07-06)
- examples/skills_audit_harness.pl — in-repo audit tooling; excluded via MANIFEST.SKIP ^examples/.*audit_harness.*\.pl$ (orchestrator, 2026-07-06)
