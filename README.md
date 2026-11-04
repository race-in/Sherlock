# Sherlock Custom Edition

[![CI](https://github.com/race-in/Sherlock/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/race-in/Sherlock/actions/workflows/ci.yml?query=branch%3Amain)

A native, self-hosted Sherlock deployment for Debian 11, 12 and 13. The Rails application source is bundled in [`sherlock-v2/`](sherlock-v2/), with its own native installer. Docker is not required.

> **Project status:** this repository bundles the Sherlock v2 application baseline and the upstream multi-user account model in a native deployment. The native installer keeps invite-based registration and account management enabled, and protects initial admin setup with a random first-run token. Manual statistics entry and strict CSV statistics import are implemented and covered by the Rails CI suite. Native updates preserve the configured PostgreSQL cluster, create a protected pre-upgrade database/credentials backup, and stop the service before replacing files or running migrations. A real Debian VPS install/upgrade/restore test remains a separate release gate. A versioned custom JSON statistics format and additional tracker adapters remain roadmap work.

## Install on a VPS

Use Debian 12 or 13 for an internet-facing server. Debian 11 is end-of-life and is supported only as a compatibility path.

1. Create a DNS A/AAAA record for a subdomain such as `stats.example.com`, pointing to your VPS.
2. Allow inbound TCP ports 80 and 443.
3. Run:

```bash
git clone --recurse-submodules https://github.com/race-in/Sherlock.git
cd Sherlock/sherlock-v2
sudo bash ./deploy/install.sh --domain stats.example.com --letsencrypt you@example.com
```

Replace the example hostname and email. The installer builds the pinned Ruby runtime, downloads and checksum-verifies the Node.js build runtime, installs PostgreSQL, creates encrypted Rails credentials, configures systemd and Nginx, obtains a Let's Encrypt certificate, and checks the local Rails health endpoint. It keeps the upstream multi-user mode enabled and prints a 64-character first-run setup token when the database has no account; enter that token when creating the initial admin. After setup, invite-based registration and admin user management work as in upstream Sherlock. Existing multi-user databases are supported.

The canonical application installer is **[`sherlock-v2/deploy/install.sh`](sherlock-v2/deploy/install.sh)**. The root-level `install.sh` and the root `scripts/` directory are retained for the older separate-source deployment scaffold; do not use that legacy entry point for the bundled application.

## Platform support

| Debian | Codename | Ruby | Node.js build runtime | PostgreSQL |
|---|---|---:|---:|---|
| 11 | Bullseye (EOL) | 4.0.9 | 24.22.2 | PGDG frozen archive; fallback documented in installer |
| 12 | Bookworm | 4.0.9 | 26.12.0 | PGDG |
| 13 | Trixie | 4.0.9 | 26.12.0 | PGDG |

Supported architectures: `amd64` and `arm64`. Ruby is compiled locally with a pinned `ruby-build` revision. Node.js is used for asset compilation only and is removed from the temporary build directory afterwards.

Debian 11 requires explicit EOL acceptance. Its frozen package sources do not receive normal Debian LTS or PGDG security updates. Use Debian 12/13 whenever possible.

## Operations

```bash
sudo sherlock-ctl status
sudo sherlock-ctl restart
sudo sherlock-ctl logs
sudo sherlock-ctl rails 'users:reset_password[username]'
curl -fsS http://127.0.0.1:3000/up
```

- Application files: `/opt/sherlock`
- Environment configuration: `/etc/sherlock/sherlock.env`
- Encrypted credentials and master key: `/etc/sherlock/credentials/`
- systemd unit: `sherlock.service`
- Nginx site: `/etc/nginx/sites-available/sherlock`

Keep port 3000 private behind Nginx. The worker metrics listener defaults to loopback even when Sherlock is configured to use an external reverse proxy. Back up `/etc/sherlock/credentials/production.key` securely; without it, saved tracker API keys cannot be decrypted.

### Updating

From the same checkout used for installation:

```bash
cd Sherlock
git pull --ff-only
cd sherlock-v2
sudo bash ./deploy/install.sh
```

For an existing install, the installer first verifies database connectivity and creates a timestamped PostgreSQL custom-format dump plus a matching archive of the environment and encrypted Rails credentials under `/var/backups/sherlock`. The dump is checked with `pg_restore --list`. It then stops the running service before replacing files and preparing migrations. If backup creation fails, the update aborts before application files are changed. If a later upgrade step fails, the service is deliberately left stopped; inspect the error and backup before retrying. Check `sudo sherlock-ctl status` and the local `/up` health endpoint after success. Keep backup files private.

## Application features

The bundled application provides tracker dashboards and history, tracker API connections, snapshot charts, comparison views, Prometheus metrics, and qui integration. The Custom Edition adds append-only manual statistics points with source/user attribution, a recent-history provenance view, and a strict CSV statistics importer that accepts the existing history-export format, rejects invalid values and future timestamps, skips duplicate observations, and records each import batch. Existing JSON account-data import remains compatible and imported snapshots are marked as JSON imports. The upstream invite/account code remains enabled: users can join through invitations and admins can manage accounts. See [Custom statistics documentation](docs/STATISTICS.md) for the manual-entry and CSV workflow, and [the bundled application README](sherlock-v2/README.md) for upstream behavior and configuration details.

## Custom Edition roadmap

The target is a self-hosted multi-user instance with automatic and manual statistics, timestamped history, CSV/JSON import/export, and additional permitted tracker integrations. Manual statistics entry and CSV statistics import are implemented on main and pass the application CI suite. Native install/upgrade and restore still require controlled real-VPS validation before production release. A separate versioned JSON statistics interchange format and additional tracker adapters remain planned.

See [ROADMAP.md](ROADMAP.md) for phases, acceptance criteria and release gates. The root legacy installer is a separate deployment scaffold; use only `sherlock-v2/deploy/install.sh` for the bundled native app.

## Security and source

- Never commit production credentials, Rails master keys, tracker API keys, database passwords or backup archives.
- Keep Nginx as the public entry point; do not expose Puma or the worker metrics port.
- Treat database dumps and credential archives as sensitive.
- Report deployment vulnerabilities privately using the repository's Security tab; see [SECURITY.md](SECURITY.md).
- The bundled application originated from [whatstatus/sherlock-v2 on Codeberg](https://codeberg.org/whatstatus/sherlock-v2). Preserve upstream attribution and notices.

## Validation

GitHub Actions runs shell syntax checks, ShellCheck, deployment regression tests, an upstream source inventory, and Debian 11/12/13 compatibility jobs. The Node frontend build, Ruby/Rails tests, and PostgreSQL schema checks validate the bundled `sherlock-v2/` tree; the separate source-inventory job compares against upstream Codeberg. CI container results do not replace a fresh-install test on real VPS hosts. DNS, certificate issuance, systemd startup, upgrade behavior and restore procedures must be verified in a controlled deployment before production use.

