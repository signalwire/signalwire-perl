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
- port_signatures.baseline.json — load-bearing SEMVER-DIFF release-floor file; mirrors port_signatures.json; must be at root, must not ship (orchestrator, 2026-07-13)
- port_surface.json — required audit-contract file read by porting-sdk audit scripts (orchestrator, 2026-07-06)
- ROOT_HYGIENE_ALLOW.md — this allowlist file (read by root_hygiene gate at repo root) (orchestrator, 2026-07-06)
- ARTIFACT_DENY_ALLOW.md — artifact-deny allowlist file read by the artifact_deny gate at repo root (orchestrator, 2026-07-06)
- EXAMPLES_RUN_ALLOW.md — examples-run allowlist file read by the porting-sdk examples_run gate at repo root (burn-perl, 2026-07-09)
- SNIPPET_RUN_ALLOW.md — snippet-run allowlist file read by the porting-sdk snippet_run gate at repo root (burn-perl, 2026-07-09)
- WIRE_VIOLATIONS_ALLOW.md — STRICT-MOCKS signed-exception ledger read by porting-sdk assert_no_wire_violations.py / examples_run.py / snippet_run.py at repo root (mike@signalwire.com, 2026-07-18)
- WIRED_MODES.md — load-bearing run-ci mode manifest read by porting-sdk check_wired_modes.py at repo root (the WIRED-MODES merge-coherence guard, plan a-bar 1.6/D7); must be at root (lane-perl, 2026-07-19)
- .doc_surface_floor — DOC-SURFACE coverage-ratchet floor read at ./.doc_surface_floor by porting-sdk doc_surface.py (plan 6.3); must be at root, must ratchet in-repo (docs-perl, 2026-07-29)
