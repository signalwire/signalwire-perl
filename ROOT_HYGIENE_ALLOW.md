# Root-hygiene allowlist

These files are tracked at the repo ROOT deliberately. They are the porting-audit
CONTRACT files: the shared porting-sdk audit scripts (and this repo's own audit
recipe) read them at the repo root by relative path. Moving them to `eng/` would
break the shared cross-port pipeline, which this repo cannot edit. Each entry is a
load-bearing audit-contract file, not clutter.

- CHECKLIST.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- DOC_AUDIT_IGNORE.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- PORT_ADDITIONS.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- PORT_EXAMPLE_OMISSIONS.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- PORT_OMISSIONS.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- PORT_SIGNATURE_OMISSIONS.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- PORT_TEST_OMISSIONS.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- REST_COVERAGE_GAPS.md — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- audit_coverage.json — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- audit_coverage_baseline.json — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- port_signatures.json — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- port_surface.json — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- ROOT_HYGIENE_ALLOW.md — this allowlist file (read by root_hygiene gate at repo root) (orchestrator, 2026-07-06)
- ARTIFACT_DENY_ALLOW.md — artifact-deny allowlist file read by the artifact_deny gate at repo root (orchestrator, 2026-07-06)
- EXAMPLES_RUN_ALLOW.md — examples-run allowlist file read by the porting-sdk examples_run gate at repo root (burn-perl, 2026-07-09)
- SNIPPET_RUN_ALLOW.md — snippet-run allowlist file read by the porting-sdk snippet_run gate at repo root (burn-perl, 2026-07-09)
