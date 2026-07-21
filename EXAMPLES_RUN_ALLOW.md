# EXAMPLES_RUN allowlist

Examples that LEGITIMATELY require real credentials or a live/driver harness the
mock SignalWire environment cannot provide, and so are skipped by the EXAMPLES-RUN
gate (`porting-sdk/scripts/examples_run.py`). Each entry names the missing
dependency and the approver. The mock injects only `SIGNALWIRE_*` creds + a
loopback REST endpoint; it does NOT provide third-party API keys, real datasphere
document IDs, a mock RELAY WebSocket, or the audit-driver fixture env
(`REST_OPERATION` / `SKILL_NAME` / `SIGNALWIRE_RELAY_HOST` + a loopback fixture
port), which these examples require. This is NOT a place to hide a real example
bug; every entry names a concrete external requirement. Mirrors the ruby/php
allowlists (same examples, user-approved 2026-07-07).

- examples/joke_agent.pl — needs real API_NINJAS_KEY creds; example exit(1)s without it by design, not mockable (approver: user, 2026-07-09)
- examples/joke_skill_demo.pl — same: add_skill('joke') needs real API_NINJAS_KEY creds, not mockable (approver: user, 2026-07-09)
- examples/web_search_agent.pl — needs real GOOGLE_SEARCH_API_KEY + GOOGLE_SEARCH_ENGINE_ID creds; exit(1)s without them, not mockable (approver: user, 2026-07-09)
- examples/datasphere_serverless_env.pl — needs real DATASPHERE_DOCUMENT_ID + datasphere creds, not mockable (approver: user, 2026-07-09)
- examples/datasphere_webhook_env_demo.pl — needs real DATASPHERE_DOCUMENT_ID + datasphere creds, not mockable (approver: user, 2026-07-09)
- examples/relay_answer_and_welcome.pl — opens a live RELAY WebSocket to SIGNALWIRE_SPACE; the shared harness runs only mock_signalwire (REST), no mock_relay, so this needs a real relay endpoint (approver: user, 2026-07-09)
- examples/relay_audit_harness.pl — RELAY audit driver probe; needs porting-sdk audit_relay_handshake.py to inject SIGNALWIRE_RELAY_HOST + a loopback WS fixture, not a standalone run (approver: user, 2026-07-09)
- examples/rest_audit_harness.pl — REST audit driver probe; needs porting-sdk audit_rest_transport.py to inject REST_OPERATION + REST_FIXTURE_URL, not a standalone run (approver: user, 2026-07-09)
- examples/skills_audit_harness.pl — skills audit driver probe; needs porting-sdk audit_skills_dispatch.py to inject SKILL_NAME + SKILL_FIXTURE_URL, not a standalone run (approver: user, 2026-07-09)
- relay/examples/quickstart_relay.pl — connect_ws()/authenticate() opens a live RELAY WebSocket to SIGNALWIRE_SPACE and dies on failure; the shared harness runs only mock_signalwire (REST), no mock_relay, so this canonical RELAY quickstart needs a real relay endpoint (same class + reason as the owner-approved examples/relay_answer_and_welcome.pl and php relay/examples/quickstart_relay.php, approver: user, 2026-07-09)
- relay/examples/relay_answer_and_welcome.pl — opens a live RELAY WebSocket to SIGNALWIRE_SPACE; the shared harness runs only mock_signalwire (REST), no mock_relay, so this needs a real relay endpoint (subtree mirror of the owner-approved examples/relay_answer_and_welcome.pl and php relay/examples/relay_answer_and_welcome.php, approver: user, 2026-07-09)
- relay/examples/relay_dial_and_play.pl — opens a live RELAY WebSocket + requires a real RELAY_FROM_NUMBER/RELAY_TO_NUMBER on your project; the shared harness runs only mock_signalwire (REST), no mock_relay, so this needs a real relay endpoint (same class + reason as the owner-approved php relay/examples/relay_dial_and_play.php, approver: user, 2026-07-09)
- relay/examples/relay_ivr_connect.pl — opens a live RELAY WebSocket to SIGNALWIRE_SPACE; the shared harness runs only mock_signalwire (REST), no mock_relay, so this needs a real relay endpoint (same class + reason as the owner-approved php relay/examples/relay_ivr_connect.php, approver: user, 2026-07-09)
