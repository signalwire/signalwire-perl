# SNIPPET_RUN_ALLOW.md

Snippets excused from the SNIPPET-RUN gate (each must run to a zero exit against
the mock, or carry an inline `<!-- snippet: no-run <reason> -->` marker). An entry
here is the last resort for a snippet that genuinely cannot run standalone AND
cannot carry an inline marker. Format:

    - <path>:<line> — <reason> (approver, date)

- README.md:54 — quickstart is an `<!-- include: -->` block synced from examples/quickstart_agent.pl and ends in `$agent->run` (blocking HTTP server); the README-INCLUDE gate requires the include comment immediately above the fence, which precludes an inline `no-run` marker, so it is excused here (burn-perl, 2026-07-09; anchor refreshed 2026-07-23)
- README.md:151 — `<!-- include: -->` block synced from relay/examples/quickstart_relay.pl; makes a live RELAY WebSocket connection (real network) and cannot carry an inline `no-run` marker under the README-INCLUDE gate (burn-perl, 2026-07-09; anchor refreshed 2026-07-23)
- README.md:194 — `<!-- include: -->` block synced from rest/examples/quickstart_rest.pl; makes a live REST call (SDK REST base is https://{space}, no mock override) and cannot carry an inline `no-run` marker under the README-INCLUDE gate (burn-perl, 2026-07-09; anchor refreshed 2026-07-23)
