# Sherlock Custom Edition — Roadmap

This roadmap records the agreed target configuration. Items below are planned unless explicitly marked complete in the repository.

## Project decisions

- Deployment: native Rails + PostgreSQL + Nginx + systemd; no Docker requirement.
- Supported host targets: Debian 11/12/13 (Debian 12/13 recommended; Debian 11 is EOL compatibility only).
- Access: one private instance at a user-owned HTTPS subdomain.
- User model: single-user only; no public registration or invite flow.
- Statistics sources: automatic tracker API, manual entry, CSV import, and JSON import.
- History: immutable, timestamped snapshots; corrections create new records rather than overwriting history.
- UI: preserve the upstream Sherlock visual design and navigation where possible.

## Phase 0 — Rights and source baseline

- [ ] Keep the maintainer's written permission or a clear licence record with the project governance materials; the source tree itself has no standalone LICENSE file.
- [ ] Confirm the exact upstream commit to use as the base.
- [ ] Keep upstream attribution, notices, and any required licence terms.
- [x] Bundle the imported Sherlock v2 application baseline under `sherlock-v2/`, preserving upstream attribution and notices.
- [x] Record the upstream source inventory and schema/import/export contract in `docs/UPSTREAM_AUDIT.md`.
- [ ] Complete a clean full Rails test baseline on the bundled source in the Debian CI matrix.

**Gate:** retain evidence of the maintainer permission already obtained for this project and preserve all upstream attribution. The audited upstream tree has no standalone LICENSE file; do not imply an OSI/open-source licence that is not present.

## Phase 1 — Single-user mode

- [x] Upstream first-run setup creates the initial administrator account.
- [ ] Make the installation permanently single-user: disable invite joins and every user-creation path after first-run.
- [ ] Enforce the one-account invariant in both Rails model/controller paths and PostgreSQL, including concurrent requests.
- [ ] Preserve existing connection ownership and historical data migrations.
- [ ] Add regression tests proving a second account cannot be created.

## Phase 2 — Unified statistics model

- [ ] Preserve existing tracker snapshots and chart compatibility.
- [ ] Add a validated source/provenance field: API, manual, CSV, or JSON.
- [ ] Store observation time, import batch reference, and optional notes.
- [ ] Use bytes as canonical storage units; keep units explicit at input boundaries.
- [ ] Keep unavailable values distinct from zero.
- [ ] Validate ratio and tracker-reported fields without silently replacing source values.
- [ ] Enforce duplicate protection without overwriting historical observations.

## Phase 3 — Manual statistics entry

- [ ] Add tracker-specific Add/Edit Statistics workflow matching the existing UI.
- [ ] Allow optional fields because trackers expose different metrics.
- [ ] Validate timestamps, numbers, units, and tracker identity on the server.
- [ ] Record every manual correction in an audit trail.
- [ ] Display manual/API/import source badges and observation times.
- [ ] Add tests for zero, null, large byte values, timezone handling, and invalid input.

## Phase 4 — CSV and JSON import/export

- [x] Upstream already provides JSON account-data export/import and per-connection CSV history export; preserve and test both.
- [ ] CSV statistics template with preview and column mapping (distinct from existing history CSV export).
- [ ] Strict CSV size, row-count, encoding, timestamp, tracker and field validation.
- [ ] Transactional statistics import with duplicate detection and downloadable error report.
- [ ] Versioned Custom Edition JSON format for statistics with schema validation, without changing upstream account-backup JSON semantics.
- [ ] Never export tracker API keys, passkeys, Rails secrets, or database credentials.
- [ ] Test rollback on partial failures and repeated imports.

## Phase 5 — Tracker integrations

- [x] Preserve existing upstream tracker engines: Gazelle, HDBits, BTN, GazelleGames, UNIT3D, Anthelion and AnimeBytes.
- [ ] Add a safe tracker-definition registry for documented/read-only API fields.
- [ ] Add DesiGaane and SuperBits only after verifying their live API endpoints, authentication scopes, and tracker rules.
- [ ] Add UNIT3D/Gazelle/custom adapters with server-side schema validation.
- [ ] Do not execute arbitrary tracker-provided scripts or scrape where prohibited.
- [ ] Add per-tracker rate limits, timeouts, pause-on-429 handling, and adapter contract tests.

## Phase 6 — Dashboard and analytics

- [ ] Overall upload/download totals with explicit aggregation rules.
- [ ] Per-tracker ratio and buffer comparison.
- [ ] Daily/weekly/monthly growth charts.
- [ ] Manual vs automatic history visibility.
- [ ] Historical export and database backup/restore verification.

## Phase 7 — Production release

- [ ] Run full application tests and security scanning.
- [ ] Test fresh install and upgrade on Debian 12 and 13; separately test the EOL Debian 11 path.
- [ ] Verify systemd restart, Nginx proxy, HTTPS renewal, backup, and restore.
- [ ] Publish versioned releases and complete operator documentation.
- [ ] Document supported trackers and exact tested adapter versions.

## Current status

- [x] Native deployment scaffold, shell regression tests, source audit, and Debian release compatibility jobs.
- [x] Single-user + hybrid manual/automatic + CSV/JSON target architecture documented.
- [ ] Full Sherlock Custom Edition application features.
- [ ] Full fresh-install verification on real Debian VPS hosts.

