# Upstream Sherlock v2 source audit

**Audited repository:** https://codeberg.org/whatstatus/sherlock-v2.git  
**Audited upstream commit:** `6eaecd7e249687ca2e302e7d7f5e81f91f082d53`  
**Audit method:** fresh shallow clone in GitHub Actions, source inventory of Rails models/controllers/routes/migrations, schema and tests, plus the Debian compatibility jobs.

## Repository integration

The audited Rails application baseline is bundled in this repository under `sherlock-v2/`. The root-level native deployment scripts are retained for compatibility, while the canonical bundled-source installer is `sherlock-v2/deploy/install.sh`.

The native-runtime CI jobs validate the bundled source: Node installs dependencies and builds its frontend; Ruby installs the pinned gems, prepares PostgreSQL, and runs the Rails test suite; the database compatibility job loads the bundled `db/structure.sql`. A separate upstream inventory job still clones Codeberg so source drift and upstream changes can be compared.

## What the upstream application already does

- First-run setup creates the initial administrator account.
- Authentication uses Rails sessions and `has_secure_password`.
- The normal join flow accepts invites; admins can issue personal/open invites and manage users. This is multi-user behavior, not a single-user-only installation.
- Tracker connections and immutable snapshots are already modeled with `Connection`, `Snapshot` and `History`.
- Existing tracker engines include Gazelle, HDBits, BTN, GazelleGames, UNIT3D, Anthelion and AnimeBytes.
- Account-data JSON export/import already exists through `User#export`, `User#import!`, and the settings data/export/import controllers.
- Per-connection history CSV export already exists through `History#to_csv`.
- The database stores tracker history in the `sherlockdb.snapshots` table. Persisted snapshots are read-only and history is append-oriented.
- Upstream has Rails integration, model, job and adapter tests under `test/`.

## Differences from the Custom Edition target

| Requirement | Audited upstream baseline | Work still required |
|---|---|---|
| Single-user instance | First-run admin + invite-based joins + admin user management | Provision the first account privately; block invite registration and all second-user creation paths; enforce the one-account invariant and test concurrency |
| Manual statistics | No manual snapshot entry workflow was found in the audited controllers/routes | Add validated manual observations while preserving immutable snapshot history |
| CSV | CSV export exists for connection history | Add CSV statistics import with preview, transactional writes and an error report |
| JSON | User/account backup import/export exists | Add a versioned statistics interchange format without breaking the existing account-backup JSON format |
| Tracker support | Seven existing adapter families are registered | Add DesiGaane and SuperBits only after verifying their permitted API methods and live response contracts |
| Provenance | Snapshot values are API-polled data | Add explicit source/audit metadata for API vs manual vs imported observations |

## Licensing and attribution

The audited upstream tree contains project documentation but no root or nearby standalone `LICENSE`, `LICENCE`, `COPYING`, or `NOTICE` file. A public repository being readable does not itself grant permission to redistribute modified source. The project owner has reported that maintainer permission was obtained; retain that written permission in the project's private governance records and preserve all upstream attribution/notices in this repository. Do not claim that the upstream source is under an OSI-approved licence unless a licence is actually supplied.

## Verification limits

GitHub Actions validates shell helpers and runs Debian 11/12/13 compatibility jobs against the bundled source. The Ruby job runs the Rails test suite with PostgreSQL; the Node job builds the frontend; and the schema job loads the bundled database structure. These container checks do not prove that a fresh install boots behind Nginx with TLS, that systemd behaves correctly after reboots, or that backup/restore succeeds on a real VPS. DNS, certificate issuance, real-host service startup, upgrade behavior and restore procedures remain release gates.
