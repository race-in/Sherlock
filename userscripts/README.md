# Sherlock browser userscripts

These are optional browser-local helpers for Sherlock. They do not change the Rails application, tracker credentials, server-side tracker records, or the dashboard's existing layout.

## Files

- `Sherlock-Native-Tracker-Cards-v5.2.10.user.js` — native tracker cards, browser-local profile capture, stats history, sidebar integration, CSV export, and UNIT3D recognition. Visible tracker labels use abbreviations; `full_name` retains the canonical tracker name for matching and validation.
- `Sherlock-Tracker-Sync-Local-v1.3.2.user.js` — local custom-tracker helper. Visible labels use abbreviations; `fullName` retains the canonical tracker name.
- `tracker-identities.json` — all 205 main-list entries from the supplied Private Tracker List, including official and generated abbreviation status.
- `tests/test_sherlock_identity.js` — offline regression tests for the identity directory, host aliases, old-record migration, UNIT3D detection/capture, and stats parsing.

## Identity rules

1. Known hosts keep their existing host-to-tracker mappings. The Native Cards supported-host list and Sync Local supported-host list remain separate and unchanged.
2. Tracker full names and abbreviations are sourced from the 205-entry list. The scripts use the abbreviation for every visible tracker-name label and retain the canonical full name internally.
3. The supplied list includes 173 official abbreviations. For the other 32 entries, deterministic short codes are generated and marked `generated`; they are not presented as official abbreviations.
4. The 364 additional Jackett-only entries have no separate abbreviation column in the supplied source. They use a deterministic fallback when encountered; no unsupported official abbreviation is invented.
5. Legacy records are normalized to abbreviation-first display while preserving stats history, logos, profile details, and sync settings.

## Offline tests

Run from this directory:

```sh
node tests/test_sherlock_identity.js
```