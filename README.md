# Sherlock v2 — Native Debian Deployment Kit

[![CI](https://github.com/race-in/Sherlock/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/race-in/Sherlock/actions/workflows/ci.yml)

Native (non-Docker) deployment scaffold for Debian 11, 12, and 13. This repository currently contains deployment tooling only; it does **not** contain the planned Sherlock Custom Edition features.

## Supported platform matrix

| OS | Codename | Runtime | PostgreSQL 18 package source | Notes |
|---|---|---|---|---|
| Debian 11 | Bullseye | Ruby 4.0.9 + official Node.js 24.22.2 build runtime | Frozen PGDG archive | EOL; install requires explicit confirmation |
| Debian 12 | Bookworm | Ruby 4.0.9 + official Node.js 26.12.0 binary | Current PGDG repository | Supported OS |
| Debian 13 | Trixie | Ruby 4.0.9 + official Node.js 26.12.0 binary | Current PGDG repository | Supported OS |

Supported CPU architectures: `amd64` and `arm64`.

### Debian 11 warning

Debian 11 Bullseye reached Debian LTS end-of-life on **31 August 2026**. It no longer receives free security updates from Debian LTS. The PostgreSQL project has also moved the Bullseye PGDG repository to its frozen archive; packages there receive no further PGDG updates. For an internet-facing production server, use Debian 12 or 13. The installer requires confirmation on Debian 11 (`Type YES`) or `ALLOW_EOL_DEBIAN11=1`.

On Debian 11, after you explicitly accept the EOL warning, the installer backs up and rewrites official Bullseye APT source entries to `http://archive.debian.org` so a minimal host can bootstrap before installing CA certificates. APT still verifies signed repository metadata. It keeps the frozen security archive for matching dependency versions and disables expired backports suites and turns off the stale Release-file date check for the archive. Third-party repositories are left unchanged. These archive packages are frozen; no Debian LTS security updates are available.

## Stack

- Ruby 4.0.9, compiled locally by pinned `ruby-build v20261023` (commit SHA verified by the installer)
- Bundler 4.0.20; application gems install under `/var/lib/sherlock/bundle`, owned by the dedicated service user (not the root-owned Ruby installation).
- Official Node.js Linux binary with SHA-256 verification against Node.js `SHASUMS256.txt` (24.22.2 on Debian 11; 26.12.0 on Debian 12/13)
- PostgreSQL 18
- Puma managed by systemd; Solid Queue runs inside Puma for the single-server setup
- Nginx reverse proxy and Let's Encrypt TLS
- No Docker

Node.js' official Linux x64/arm64 platform table specifies kernel >= 4.18 and glibc >= 2.28, and its official Linux binaries are built in a RHEL 8 environment. The installer uses those documented kernel/glibc floors for Node.js 24 and 26. Debian 11 still uses Node.js 24.22.2 because its older system `libstdc++` cannot satisfy the newer C++ runtime symbols required by the Node.js 26 build; Debian 12/13 use Node.js `26.12.0`. The upstream Sherlock source's `.node-version` remains pinned and checked at `26.12.0`; on Debian 11 only, the compatible Node 24 runtime executes npm/esbuild. The actual versioned binary is checksum-verified and executed by both the installer and Debian CI runtime tests, which catches missing C++ runtime symbols as well as version mismatches. The installer installs `libatomic1` for Node 26. It uses the ASCII PostgreSQL signing key directly with APT's `signed-by` support, so it does not install the unnecessary `gnupg` package.

Ruby's bundled OpenSSL extension supports OpenSSL 1.1.1 and newer. The installer checks that Ruby can load OpenSSL after compilation.

## Requirements

- Fresh Debian 11, 12, or 13 install (Debian 12/13 strongly recommended)
- `amd64` or `arm64`
- At least 4 GB RAM and 30 GB free disk recommended; Ruby and native gems are compiled locally
- DNS A/AAAA record such as `stats.example.com` pointing to the VPS
- TCP ports 80 and 443 reachable from the Internet
- A Git repository containing the Sherlock application source and these exact version files:
  - `.ruby-version`: `4.0.9`
  - `.node-version`: `26.12.0`
  - `Gemfile.lock`, `package-lock.json`, and Rails application files

## Install

Clone this deployment repository on the VPS. The GitHub repository contains the native installer; the Rails application source remains upstream on Codeberg:

```bash
git clone https://github.com/race-in/Sherlock.git sherlock-deploy
cd sherlock-deploy
sudo ./install.sh stats.example.com https://codeberg.org/whatstatus/sherlock-v2.git main
```

Replace `stats.example.com` with your real subdomain. Before running the installer, point its DNS A/AAAA record to the VPS and allow inbound TCP 80/443. The installer prompts for the Let's Encrypt email address.

The app source is cloned into `/opt/sherlock` on the VPS and receives three deployment-only patches there: Puma loopback binding, a separate database pool setting, and worker metrics loopback binding. Those patches are local to the VPS; they do not change the upstream Codeberg repository. Do not publish or redistribute patched upstream application source until its licence or maintainer permission has been confirmed.

On Debian 11, accept the EOL warning by typing `YES`, or use:

```bash
sudo env ALLOW_EOL_DEBIAN11=1 ./install.sh stats.example.com https://codeberg.org/whatstatus/sherlock-v2.git main
```

The installer:

1. Detects Debian release and CPU architecture.
2. Installs build dependencies, Nginx, Certbot, and PostgreSQL prerequisites.
3. Configures PGDG for Debian 12/13, or the frozen `apt-archive.postgresql.org` Bullseye repository for Debian 11.
4. Installs PostgreSQL 18 and creates a dedicated database role. The database is created after credentials are ready; Rails loads `db/structure.sql`, which creates the `sherlockdb` schema.
5. Clones the authorized app source to `/opt/sherlock` and applies three small, idempotent deployment-only patches: bind Puma and worker metrics to loopback, and separate the database connection pool setting.
6. Builds Ruby 4.0.9, installs a checksum-verified Node.js runtime compatible with the host Debian release (Node 24.22.2 on Debian 11; Node 26.12.0 on Debian 12/13), then installs Bundler gems into the service-owned `/var/lib/sherlock/bundle` path and builds JavaScript assets.
7. Creates encrypted Rails production credentials and a root-managed environment file.
8. Creates/prepares the PostgreSQL database, compiles production assets, configures systemd and Nginx, and requests a Let's Encrypt certificate.

It refuses to overwrite an existing `/opt/sherlock` directory or an existing database role.

## Deployment helper scripts

- `scripts/patch-native-app.sh`: applies the local-only Puma loopback bind and database-pool patches; fails closed if the expected upstream source lines change.
- `scripts/check-nginx-host-conflict.sh`: refuses an existing exact `server_name` collision before adding the Sherlock virtual host; existing/default Nginx sites are left intact.
- `scripts/prepare-bullseye-archive.sh`: backs up and adapts official Debian 11 APT source entries after EOL consent.
- `scripts/compatibility-check.sh`: reports supported Debian releases, CPU architecture, and glibc compatibility.
- `scripts/test-native-patches.sh`, `scripts/test-bullseye-archive.sh`, `scripts/test-backup-restore.sh`, `scripts/test-nginx-host-conflict.sh`, and `scripts/test-installer-contract.sh` and `scripts/test-credentials-generation.sh`: regression tests run in CI, including Ruby/ERB syntax checks and valid Rails encryption credentials YAML generation.
- `scripts/test-apt-dependencies.sh`: resolves the native installer dependency set, installs PostgreSQL 18 in each Debian CI image, and loads the upstream `db/structure.sql` using a dedicated application-style database role to verify schema creation and ownership.
- `scripts/test-node-runtime.sh`: downloads the selected official Node.js runtime, verifies its published SHA-256 checksum, runs Node.js/npm, and runs the upstream Sherlock frontend build on each Debian image. `scripts/test-ruby-runtime.sh` compiles the pinned Ruby 4.0.9 toolchain, installs Bundler 4.0.20, and resolves the upstream Sherlock production gems.

## Operations

```bash
systemctl status sherlock
journalctl -u sherlock -f
systemctl restart sherlock
curl -fsS http://127.0.0.1:3000/up
```

- Dashboard: `https://stats.example.com`
- Update: pull the latest deployment scripts first, then run the updater as root; it takes a database/credentials backup before changing the app:

  ```bash
  cd sherlock-deploy
  git pull --ff-only
  sudo bash scripts/update.sh
  ```

- Backup: `sudo bash scripts/backup.sh` (writes mode-0600 files into a mode-0700, root-owned directory; each file is finalized by an atomic rename)

Do not expose port 3000 publicly. Nginx is the public entry point and proxies to localhost.

## Security and backups

- Rails binds behind Nginx; port 3000 must remain private.
- `/etc/sherlock/sherlock.env` is root-owned and readable only by the application group.
- Ruby itself is root-owned under `/opt/rubies`; application gems are isolated in the service-user-owned `/var/lib/sherlock/bundle` and the same `BUNDLE_PATH` is used by systemd and updates.
- Back up `config/credentials/production.key` securely; without it, encrypted credentials and saved API keys cannot be decrypted.
- Puma is patched to listen only on `127.0.0.1:3000`; Nginx is the only public web entry point.
- The Solid Queue worker's Prometheus exporter is patched to listen only on `127.0.0.1:9394` by default, preventing tracker/poll metrics from being exposed on every network interface.
- The database connection pool uses `DB_POOL=10` independently from Puma's `RAILS_MAX_THREADS=3`, leaving room for Solid Queue jobs.
- Never commit production keys, API keys, database passwords, or `sherlock.env`.
- Store the database dump and credential archive separately and securely.
- Verify restore procedures before relying on backups.


### Restore a backup

**Warning:** restoring replaces the current database. Use a verified database dump and its matching secrets archive from the same backup timestamp. The secrets archive contains the Rails master key, encrypted Rails credentials, and database password; store it as a highly sensitive file.

First verify the secrets archive and PostgreSQL dump, then restore as root:

```bash
sudo bash scripts/restore.sh --verify-pair \
  /var/backups/sherlock/sherlockdb_prod-TIMESTAMP.dump \
  /var/backups/sherlock/sherlock-secrets-TIMESTAMP.tar.gz
sudo bash scripts/restore.sh \
  /var/backups/sherlock/sherlockdb_prod-TIMESTAMP.dump \
  /var/backups/sherlock/sherlock-secrets-TIMESTAMP.tar.gz
```

The restore script validates the archive member list, file types, and environment values; verifies the dump and secrets archive have the same generated backup timestamp and database name; checks that the Rails master key matches the encrypted credentials; asks for an explicit `RESTORE` confirmation; restores `/etc/sherlock/sherlock.env` and the Rails credentials with restrictive permissions; reconciles the PostgreSQL role password; replaces the database; and waits for the Rails health endpoint. A mismatched or partial pair is rejected before the live database is changed.

This is designed for a Sherlock installation already provisioned on the target VPS with PostgreSQL 18, the service account, and the application directory. For a new host, run the native installer first, then restore. Confirm the application version is compatible with the database dump before restoring.

## Security

See [SECURITY.md](SECURITY.md) for private vulnerability reporting and deployment safety guidance.

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the agreed Custom Edition implementation plan and release gates.

## Current scope

This repository is a **native deployment scaffold**, not yet the complete Sherlock Custom Edition. It does not implement single-user-only enforcement, manual statistics entry, CSV/JSON import/export workflows, or additional tracker adapters. The upstream app may still retain its existing multi-user/invite behavior.

The supplied upstream archive did not contain a standalone LICENSE file. Before redistributing or publishing modified upstream source, obtain and verify the maintainer's permission/license. This repository therefore keeps deployment tooling separate from upstream application source.
- This GitHub repository contains deployment tooling only, not the Rails application source. Do not pass `https://github.com/race-in/Sherlock.git` as the application-source URL to `install.sh`; provide a separate authorized repository containing the complete Rails source tree.

## Validation status

- GitHub Actions validates Bash syntax, ShellCheck, workflow YAML, deployment patch tests, Bullseye APT-source migration tests, simulated native dependency installation, the actual checksum-verified Node.js/npm binaries, the upstream frontend build, and the pinned Ruby/Bundler/gem installation against Debian 11/12/13 images.
- The CI matrix checks Debian 11/12/13 release and x86_64/glibc compatibility in containers. The installer and runtime scripts also support ARM64, but ARM64 has not yet been exercised by this CI matrix.
- The native patcher was smoke-tested against the supplied Sherlock v2 source archive; Puma Ruby syntax and `database.yml` ERB syntax were checked locally.
- Full package installation, PostgreSQL repository resolution, systemd startup, DNS, and HTTPS still need verification on real Debian 11/12/13 VPS instances.
- Debian 11 uses an archived PostgreSQL repository and an end-of-life operating system; it is a compatibility path, not the recommended production target.

## References

- [Debian 11 LTS end-of-life announcement](https://www.debian.org/News/2026/20260831)
- [PostgreSQL Debian installation instructions](https://www.postgresql.org/download/linux/debian/)
- [PostgreSQL PGDG archive](https://apt-archive.postgresql.org/)
- [Node.js build/platform requirements](https://github.com/nodejs/node/blob/main/BUILDING.md)
- [Node.js 26.12.0 release downloads](https://nodejs.org/en/download/archive/v26.12.0)
- [Node.js 24.22.2 release downloads](https://nodejs.org/en/download/archive/v24.22.2)
- [ruby-build v20261023 release](https://github.com/rbenv/ruby-build/releases/tag/v20261023)
- [Ruby/OpenSSL compatibility](https://ruby.github.io/openssl/)