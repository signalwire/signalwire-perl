# Changelog

All notable changes to the SignalWire Perl SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 3.0.0

The first release of the generated-REST surface, and the fleet-wide convergence
version: every SignalWire SDK port declares 3.0.0. Nothing in the 3.x/4.x range was
ever published, so the previously-drafted unreleased 3.0.2 / 3.1.0 / 3.2.0 / 4.0.0
entries are consolidated here rather than shipped as a staggered series of majors.

### Changed (BREAKING)
- `CrudResource->delete_resource($id)` is renamed to `CrudResource->delete($id)`,
  matching every other SignalWire SDK and the Python reference. Every CRUD resource
  reached via `$client-><namespace>` (phone numbers, video rooms, queues, verified
  callers, datasphere documents, …) now removes with `->delete($id)` instead of
  `->delete_resource($id)`. The documented `->delete($id)` form on the
  already-`delete`-named resources is unchanged.
- The RELAY client `User-Agent` (`SignalWire::Relay::Client`) now derives from the
  distribution `$VERSION` (single source of truth in `lib/SignalWire.pm`), so it
  can never go stale against the released version — matching the REST client.

### Added
- `$client->messages` — the `messages` (plural) REST resource over
  `/api/messaging/messages`, for sending and redacting messages. This is DISTINCT
  from message logs (`$client->logs->messages`, the read-side log query).
  `->create(...)` sends an outbound SMS/MMS message
  (`POST /api/messaging/messages`); `->update($message_id, ...)` redacts a message
  (`PATCH /api/messaging/messages/{message_id}`).
- `$client->projects` — full-CRUD Projects resource (list/get/create/update/delete)
  plus `rotate_signing_key`, generated from the `projects` REST spec. Distinct from
  the singular `project` token namespace.
- `CHANGELOG.md` documenting releases.
- SEMVER-DIFF release gate: the version bump is checked against the public API
  surface diff versus the committed release floor
  (`port_signatures.baseline.json`).
- Strict IGNORE-LEDGER-VERIFY: every `DOC_AUDIT_IGNORE.md` entry now carries an
  accurate auto-accept category or structured reason/approver/date fields.

### Fixed
- CRUD resources built on `CrudResource` previously lacked a `delete` method entirely
  (only `delete_resource` was inherited); `->delete($id)` — the name shown in the docs
  and used by every sibling SDK — now works on all of them.
