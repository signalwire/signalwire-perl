# WIRE_VIOLATIONS_ALLOW.md — signed exceptions to the STRICT-MOCKS wire-truth gate

The STRICT-MOCKS consumer (`porting-sdk/scripts/assert_no_wire_violations.py`, wired
into REST-COVERAGE) reads the mock journal after a run and fails on ANY
`wire_violation` — a request/frame that put a shape on the wire the OpenAPI/RELAY
spec does not declare (an undeclared query param, an unknown body key, an unknown
frame field). A wire violation is a spec bug or a real defect; the fix is to make
the wire match the spec, NOT to allowlist it.

This file exists for the rare, genuinely-justified exception, and each entry needs a
human-signed reason. Format (one per line):

    - <kind>:<name> — reason (approver, date)

where `<kind>` is the violation kind (`unknown_query_param`, `unknown_body_key`,
`unknown_frame_field`, `duplicate_command_id`) and `<name>` is the offending
key/param name. A bare `kind:name` with no ` — reason` is NOT matched, so it cannot
silently widen the allowlist.

## Currently empty

No entries. The wired gate (REST-COVERAGE) runs wire-clean against the reference.

The `page_token`/`page_size` pagination params are declared on the relevant
`list_*` operations in the spec this port builds against (fabric addresses,
relay-rest recordings, etc.), so the pagination test fixture
(`t/rest/16_pagination_mock.t`) uses the real `page_token` cursor param — no parked
gap here (unlike ports pinned to an older porting-sdk spec revision that still
lacks that declaration).
