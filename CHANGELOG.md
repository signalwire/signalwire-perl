# Changelog

All notable changes to the SignalWire Perl SDK are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
