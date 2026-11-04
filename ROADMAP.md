# Sherlock Custom Edition — Roadmap

This roadmap records the agreed target configuration. Items below are planned unless explicitly marked complete in the repository.

## Project decisions

- Deployment: native Rails + PostgreSQL + Nginx + systemd; no Docker requirement.
- Supported host targets: Debian 11/12/13 (Debian 12/13 recommended; Debian 11 is EOL compatibility only).
- Access: one self-hosted instance at a user-owned HTTPS subdomain, supporting multiple invited users.
- User model: preserve upstream multi-user invite flow and administrator user management.
- Statistics sources: automatic tracker API, manual entry, CSV import, and JSON import.
- History: immutable, timestamped snapshots; corrections create new records rather than overwriting history.
- UI: preserve the upstream Sherlock visual design and navigation where possible.

## Phase 0 — Rights and source baseline

- [ ] Keep the maintainer's written permission or a clear licence record with the project governance materials; the source tree itself has no standalone LICENSE file.
- [ ] Confirm the exact upstream commit to use as the base.
- [ ] Keep upstream attribution, notices, and any required licence terms.
- [x] Bundle the imported Sherlock v2 application baseline under `sherlock-v2/`, preserving upstream attribution and notices.
- [x] Record the upstream source inventory and schema/import/export contract in `docs/UPSTREAM_AUDIT.md`.
- [x] Complete a clean full Rails test baseline and dependency/security checks on the bundled source in CI.

**Gate:** retain evidence of the maintainer permission already obtained for this project and preserve all upstream attribution. The audited upstream tree has no standalone LICENSE file; do not imply an OSI/open-source licence that is not present.

## Phase 1 — Multi-user account compatibility

- [x] Upstream first-run setup creates the initial administrator account.
- [x] Preserve upstream invite-based registration and administrator user management in the native installation.
- [x] Keep first-run setup protected by a private token without disabling subsequent user registration.
- [x] Add regression tests for invitation creation, joining, permissions, single-user mode, and multi-user tracker isolation.

## Phase 2 — Unified statistics model

- [x] Preserve existing tracker snapshots and chart compatibility.
- [x] Add a validated source/provenance field: API, manual, CSV, or JSON.
- [x] Store observation time, import batch reference, creator attribution, and optional notes.
- [x] Use bytes as canonical storage units; keep units explicit at input boundaries.
- [x] Keep unavailable values distinct from zero.
- [x] Validate manual/import values and preserve API-reported fields without silently replacing source values.
- [ ] Enforce duplicate protection without overwriting historical observations.

## Phase 3 — Manual statistics entry

- [x] Add tracker-specific append-only Add Statistics workflow matching the existing UI; corrections create new observations.
- [x] Allow optional fields because trackers expose different metrics.
- [x] Validate timestamps, numbers, byte units, and tracker ownership on the server.
- [x] Record the creator and timestamp for each manual observation; retain prior observations.
- [x] Display manual/API/import source labels and observation times in recent history.
- [x] Add tests for zero, null, large byte values, timezone handling, and invalid input.

## Phase 4 — CSV and JSON import/export

- [x] Upstream already provides JSON account-data export/import and per-connection CSV history export; preserve and test both.
- [ ] CSV statistics template with preview and column mapping (distinct from existing history CSV export).
- [x] Strict CSV size, row-count, encoding, timestamp, tracker ownership and field validation.
- [x] Validate the complete CSV before a single atomic insert; skip duplicates and repeated imports.
- [ ] Add a downloadable row-error report for rejected CSV files.
- [ ] Versioned Custom Edition JSON format for statistics with schema validation, without changing upstream account-backup JSON semantics.
- [x] Never export tracker API keys, passkeys, Rails secrets, database credentials, or local creator/batch IDs.
- [x] Test that invalid later CSV rows insert nothing and repeated CSV/JSON imports skip existing timestamps.

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

- [x] Run full application tests and dependency/security scanning in CI.
- [ ] Test fresh install and upgrade on Debian 12 and 13; separately test the EOL Debian 11 path.
- [ ] Verify systemd restart, Nginx proxy, HTTPS renewal, backup, and restore.
- [ ] Publish versioned releases and complete operator documentation.
- [ ] Document supported trackers and exact tested adapter versions.

## Current status

- [x] Native deployment scaffold, shell regression tests, source audit, and Debian release compatibility jobs.
- [x] Multi-user + hybrid manual/automatic + CSV/JSON target architecture documented.
- [ ] Versioned Custom Edition JSON statistics interchange, CSV preview/mapping/error report, and additional tracker integrations.
- [x] Manual-statistics and CSV-import regression suite passes in the Rails CI job.
- [x] Preserve the exact local PostgreSQL cluster on upgrades; fail closed if the configured cluster cannot be identified.
- [x] Create a verified pre-upgrade database and credentials backup before modifying an existing install.
- [x] Stop the app service before source replacement and database migrations.
- [x] Persist the release tag in the native environment for footer/update checks.
- [ ] Full fresh-install verification on real Debian VPS hosts.

