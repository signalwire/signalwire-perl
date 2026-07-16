# Changelog

All notable changes to the SignalWire Perl SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 4.0.0

Converges the REST resource-deletion method name to `delete`, matching every other
SignalWire SDK and the Python reference. The `CrudResource` base and every generated
resource class now expose `delete($id)` directly.

### Changed (BREAKING)
- `CrudResource->delete_resource($id)` is renamed to `CrudResource->delete($id)`.
  Every CRUD resource reached via `$client-><namespace>` (phone numbers, video rooms,
  queues, verified callers, datasphere documents, …) now removes with
  `->delete($id)` instead of `->delete_resource($id)`. The documented
  `->delete($id)` form on the already-`delete`-named resources is unchanged.

### Fixed
- CRUD resources built on `CrudResource` previously lacked a `delete` method entirely
  (only `delete_resource` was inherited); `->delete($id)` — the name shown in the docs
  and used by every sibling SDK — now works on all of them.

## 3.2.0

Adds the `messages` (plural) REST resource — `$client->messages` over
`/api/messaging/messages` — for sending and redacting messages. This is DISTINCT
from message logs (`$client->logs->messages`, the read-side log query).

### Added
- `$client->messages->create(...)` — send an outbound SMS/MMS message
  (`POST /api/messaging/messages`), generated from the `messages` REST spec.
- `$client->messages->update($message_id, ...)` — redact a message
  (`PATCH /api/messaging/messages/{message_id}`).

## 3.1.0

Adds the `projects` (plural) full-CRUD REST resource — `$client->projects` over
`/api/projects` — distinct from the singular `project` token namespace.

### Added
- `$client->projects` — full-CRUD Projects resource (list/get/create/update/delete)
  plus `rotate_signing_key`, generated from the `projects` REST spec.

## 3.0.2

Release-readiness baseline for the generated-REST surface. This version unifies
the Perl port onto the cross-port 3.0.2 pre-release marker and establishes the
committed API surface floor (`port_signatures.baseline.json`).

### Added
- `CHANGELOG.md` documenting releases.
- SEMVER-DIFF release gate: the version bump is checked against the public API
  surface diff versus the committed release floor.
- Strict IGNORE-LEDGER-VERIFY: every `DOC_AUDIT_IGNORE.md` entry now carries an
  accurate auto-accept category or structured reason/approver/date fields.

### Changed
- The RELAY client `User-Agent` (`SignalWire::Relay::Client`) now derives from the
  distribution `$VERSION` (single source of truth in `lib/SignalWire.pm`), so it
  can never go stale against the released version — matching the REST client.
