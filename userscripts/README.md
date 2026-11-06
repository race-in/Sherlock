# Sherlock browser userscripts

These userscripts are optional browser-local helpers for the Sherlock dashboard. They do not change the Rails application, tracker credentials, or server-side tracker records.

## Files

- `Sherlock-Native-Tracker-Cards.user.js` — native tracker cards, browser-local profile capture, stats history, sidebar integration, CSV export, and UNIT3D recognition. Tracker labels display the abbreviation; the full canonical name remains in local storage as `full_name` for validation.
- `Sherlock-Tracker-Sync-Local.user.js` — local custom-tracker helper. Tracker labels display the abbreviation; `fullName` stores the canonical name.
- `tracker-identities.json` — the 205-entry identity source extracted from the supplied Private Tracker List. It records the name, short code, and whether the code was present in the source or derived because no official abbreviation was provided.
- `tests/test_sherlock_identity.js` — offline regression tests for identity lookup, abbreviations, UNIT3D parsing/capture, host normalization, and existing parser helpers.

## Identity rules

1. Known hosts resolve through an explicit host-to-tracker mapping.
2. The 205-entry directory supplies the canonical full name and abbreviation.
3. For the 32 entries with no abbreviation in the supplied list, a stable generated short code is used and marked `generated` in `tracker-identities.json`.
4. The additional 364 Jackett-only rows in the supplied file do not provide a separate abbreviation column. They are not represented as official codes; unlisted sites use a deterministic name-derived fallback.
5. Full canonical names remain stored for identity matching; dashboard cards, sidebar labels, notifications, and other tracker-name displays use the short code.

## Offline tests

Run from this directory:

```sh
node tests/test_sherlock_identity.js
```