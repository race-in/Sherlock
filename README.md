# Sherlock v2 — Native Debian Deployment Kit

[![CI](https://github.com/race-in/Sherlock/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/race-in/Sherlock/actions/workflows/ci.yml)

Native (non-Docker) deployment scaffold for Debian 11, 12, and 13. This repository currently contains deployment tooling only; it does **not** contain the planned Sherlock Custom Edition features.

## Supported platform matrix

| OS | Codename | Runtime | PostgreSQL 18 package source | Notes |
|---|---|---|---|---|
| Debian 11 | Bullseye | Ruby 4.0.9 + official Node.js 26.12.0 binary | Frozen PGDG archive | EOL; install requires explicit confirmation |
| Debian 12 | Bookworm | Ruby 4.0.9 + official Node.js 26.12.0 binary | Current PGDG repository | Supported OS |
| Debian 13 | Trixie | Ruby 4.0.9 + official Node.js 26.12.0 binary | Current PGDG repository | Supported OS |

Supported CPU architectures: `amd64` and `arm64`.

### Debian 11 warning

Debian 11 Bullseye reached Debian LTS end-of-life on **31 August 2026**. It no longer receives free security updates from Debian LTS. The PostgreSQL project has also moved the Bullseye PGDG repository to its frozen archive; packages there receive no further PGDG updates. For an internet-facing production server, use Debian 12 or 13. The installer requires confirmation on Debian 11 (`Type YES`) or `ALLOW_EOL_DEBIAN11=1`.

On Debian 11, after you explicitly accept the EOL warning, the installer backs up and rewrites official Bullseye APT source entries to `archive.debian.org`, disables expired security/backports suites, and turns off the stale Release-file date check for the archive. Third-party repositories are left unchanged. These archive packages are frozen; no Debian LTS security updates are available.

## Stack

- Ruby 4.0.9, compiled locally by `ruby-build`
- Bundler 4.0.20
- Node.js 26.12.0 official Linux binary, SHA-256 verified against Node.js `SHASUMS256.txt`
- PostgreSQL 18
- Puma managed by systemd; Solid Queue runs inside Puma for the single-server setup
- Nginx reverse proxy and Let's Encrypt TLS
- No Docker

Node.js 26's official Linux binaries require glibc 2.28 or newer; the installer checks this before installation and installs `libatomic1`, required by current Node.js Linux binaries. This avoids compiling Node.js with a compiler newer than Debian 11/12's stock GCC.

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

Copy this deployment kit to the VPS, then run as root:

```bash
chmod +x install.sh
./install.sh stats.example.com https://github.com/OWNER/APP-SOURCE.git main
```

On Debian 11, accept the EOL warning by typing `YES`, or use:

```bash
ALLOW_EOL_DEBIAN11=1 ./install.sh stats.example.com https://github.com/OWNER/APP-SOURCE.git main
```

The installer:

1. Detects Debian release and CPU architecture.
2. Installs build dependencies, Nginx, Certbot, and PostgreSQL prerequisites.
3. Configures PGDG for Debian 12/13, or the frozen `apt-archive.postgresql.org` Bullseye repository for Debian 11.
4. Installs PostgreSQL 18 and creates the database and role. Rails loads `db/structure.sql`, which creates the `sherlockdb` schema.
5. Clones the authorized app source to `/opt/sherlock` and applies two small, idempotent deployment-only patches: bind Puma to loopback and use a separate database pool setting.
6. Builds Ruby 4.0.9, installs the checksum-verified Node.js 26.12.0 binary, then installs Bundler/gems/npm dependencies.
7. Creates encrypted Rails production credentials and a root-managed environment file.
8. Creates the PostgreSQL database (the app's own `structure.sql` creates its schema), prepares the database, compiles assets, configures systemd and Nginx, and requests a Let's Encrypt certificate.

It refuses to overwrite an existing `/opt/sherlock` directory or an existing database role.

## Deployment helper scripts

- `scripts/patch-native-app.sh`: applies the local-only Puma loopback bind and database-pool patches; fails closed if the expected upstream source lines change.
- `scripts/prepare-bullseye-archive.sh`: backs up and adapts official Debian 11 APT source entries after EOL consent.
- `scripts/compatibility-check.sh`: reports supported Debian releases, CPU architecture, and glibc compatibility.
- `scripts/test-native-patches.sh` and `scripts/test-bullseye-archive.sh`: regression tests run in CI.

## Operations

```bash
systemctl status sherlock
journalctl -u sherlock -f
systemctl restart sherlock
curl -fsS http://127.0.0.1:3000/up
```

- Dashboard: `https://stats.example.com`
- Update: `bash scripts/update.sh` (run as root; takes a database/credentials backup first)
- Backup: `bash scripts/backup.sh` (run as root; creates atomic, mode-0600 backups)

Do not expose port 3000 publicly. Nginx is the public entry point and proxies to localhost.

## Security and backups

- Rails binds behind Nginx; port 3000 must remain private.
- `/etc/sherlock/sherlock.env` is root-owned and readable only by the application group.
- Back up `config/credentials/production.key` securely; without it, encrypted credentials and saved API keys cannot be decrypted.
- Puma is patched to listen only on `127.0.0.1:3000`; Nginx is the only public web entry point.
- The database connection pool uses `DB_POOL=10` independently from Puma's `RAILS_MAX_THREADS=3`, leaving room for Solid Queue jobs.
- Never commit production keys, API keys, database passwords, or `sherlock.env`.
- Store the database dump and credential archive separately and securely.
- Verify restore procedures before relying on backups.


### Restore a backup

**Warning:** restoring replaces the current database. Verify both backup files and keep a copy of `/etc/sherlock/sherlock.env` before proceeding.

Run as root and replace the example timestamp with the files you want to restore:

```bash
systemctl stop sherlock
set -a
. /etc/sherlock/sherlock.env
set +a

DB_DUMP=/var/backups/sherlock/sherlockdb_prod-YYYYMMDDTHHMMSSZ.dump
CREDENTIALS_ARCHIVE=/var/backups/sherlock/sherlock-credentials-YYYYMMDDTHHMMSSZ.tar.gz

runuser -u postgres -- dropdb --if-exists --force "$DB_NAME"
runuser -u postgres -- createdb --owner "$DB_USER" --encoding UTF8 "$DB_NAME"
PGPASSWORD="$DB_PASSWORD" /usr/lib/postgresql/18/bin/pg_restore \
  --no-owner --no-acl --exit-on-error \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$DB_DUMP"

tar -xzf "$CREDENTIALS_ARCHIVE" -C /opt/sherlock
chown sherlock:sherlock /opt/sherlock/config/credentials/production.key /opt/sherlock/config/credentials/production.yml.enc
chmod 0600 /opt/sherlock/config/credentials/production.key /opt/sherlock/config/credentials/production.yml.enc
systemctl start sherlock
```

This assumes the PostgreSQL role, database environment file, and service account still exist. The credentials archive contains sensitive decryption material; store it securely.

## Current scope

This repository is a **native deployment scaffold**, not yet the complete Sherlock Custom Edition. It does not implement single-user-only enforcement, manual statistics entry, CSV/JSON import/export workflows, or additional tracker adapters. The upstream app may still retain its existing multi-user/invite behavior.

The supplied upstream archive did not contain a standalone LICENSE file. Before redistributing or publishing modified upstream source, obtain and verify the maintainer's permission/license. This repository therefore keeps deployment tooling separate from upstream application source.
- This GitHub repository contains deployment tooling only, not the Rails application source. Do not pass `https://github.com/race-in/Sherlock.git` as the application-source URL to `install.sh`; provide a separate authorized repository containing the complete Rails source tree.
- This GitHub repository contains deployment tooling only, not the Rails application source. Do not pass `https://github.com/race-in/Sherlock.git` as the application-source URL to `install.sh`; provide a separate authorized repository containing the complete Rails source tree.

## Validation status

- GitHub Actions validates Bash syntax, ShellCheck, workflow YAML, deployment patch tests, and Bullseye APT-source migration tests.
- The CI matrix checks Debian 11/12/13 release, architecture, and glibc compatibility in containers.
- The native patcher was smoke-tested against the supplied Sherlock v2 source archive; Puma Ruby syntax and `database.yml` ERB syntax were checked locally.
- Full package installation, PostgreSQL repository resolution, systemd startup, DNS, and HTTPS still need verification on real Debian 11/12/13 VPS instances.
- Debian 11 uses an archived PostgreSQL repository and an end-of-life operating system; it is a compatibility path, not the recommended production target.

## References

- [Debian 11 LTS end-of-life announcement](https://www.debian.org/News/2026/20260831)
- [PostgreSQL Debian installation instructions](https://www.postgresql.org/download/linux/debian/)
- [PostgreSQL PGDG archive](https://apt-archive.postgresql.org/)
- [Node.js build/platform requirements](https://github.com/nodejs/node/blob/main/BUILDING.md)
- [Node.js 26.12.0 release downloads](https://nodejs.org/en/download/archive/v26.12.0)
- [Ruby/OpenSSL compatibility](https://ruby.github.io/openssl/)