# Upstream Sherlock v2 source audit

**Audited repository:** https://codeberg.org/whatstatus/sherlock-v2.git  
**Audited commit:** `6eaecd7e249687ca2e302e7d7f5e81f91f082d53`  
**Audit method:** fresh shallow clone in GitHub Actions, source inventory of Rails models/controllers/routes/migrations, schema and test files, plus the Debian compatibility jobs.

## What the upstream application already does

- First-run setup creates the initial administrator account.
- Authentication uses Rails sessions and `has_secure_password`.
- The normal join flow accepts invites; admins can issue personal/open invites and manage users. This is multi-user behavior, not a single-user-only installation.
- Tracker connections and immutable snapshots are already modeled with `Connection`, `Snapshot` and `History`.
- Existing tracker engines include Gazelle, HDBits, BTN, GazelleGames, UNIT3D, Anthelion and AnimeBytes.
- Account-data JSON export/import already exists through `User#export`, `User#import!`, and the settings data/export/import controllers.
- Per-connection history CSV export already exists through `History#to_csv`.
- The database stores the tracker history in the `sherlockdb.snapshots` table. Persisted snapshots are read-only; history is append-oriented.
- Upstream has Rails integration, model, job and adapter tests under `test/`.

## Differences from the Custom Edition target

| Requirement | Audited upstream baseline | Work still required |
|---|---|---|
| Single-user instance | First-run admin + invite-based joins + admin user management | Block invite registration and all second-user creation paths; enforce in database and test concurrency |
| Manual statistics | No manual snapshot entry workflow was found in the audited controllers/routes | Add validated manual observations while preserving immutable snapshot history |
| CSV | CSV export exists for connection history | Add CSV statistics import with preview, transactional writes and an error report |
| JSON | User/account backup import/export exists | Add a versioned statistics interchange format without breaking the existing account-backup format |
| Tracker support | Seven existing adapter families are registered | Add DesiGaane and SuperBits only after verifying their permitted API methods and live response contracts |
| Provenance | Snapshot values are API-polled data | Add explicit source/audit metadata for API vs manual vs imported observations |

## Licensing and redistribution gate

The audit inventory found a `README.md` but no root or nearby `LICENSE`, `LICENCE`, `COPYING`, or `NOTICE` file. A public repository being readable does not itself grant permission to redistribute modified source. Codeberg's licensing guidance explains that, absent another agreement, copyright law otherwise reserves reuse and distribution rights. Obtain a clear licence or written maintainer permission before importing or publishing upstream application source or a derivative fork.

This repository therefore remains a deployment/extension repository and does not copy the upstream Rails application into GitHub.

## Verification limits

The existing Debian CI checks resolve production gems, build the frontend and load `db/structure.sql` on Debian 11/12/13. These checks do not run the complete upstream Rails test suite or prove the application boots behind Nginx with TLS on a real VPS. The upstream test inventory is recorded by the audit job; a full upstream test run and fresh-host end-to-end install remain release gates.
