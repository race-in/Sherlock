# Sherlock Custom Edition

[![CI](https://github.com/race-in/Sherlock/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/race-in/Sherlock/actions/workflows/ci.yml?query=branch%3Asherlock-v2-native-integration)

A native, self-hosted Sherlock deployment for Debian 11, 12 and 13. The Rails application source is bundled in [`sherlock-v2/`](sherlock-v2/), with its own native installer. Docker is not required.

> **Project status:** this repository bundles the Sherlock v2 application baseline and a native single-user deployment mode. The native installer disables registration/invite routes, enforces a one-account invariant in Rails, and protects first-run setup with a random one-time token. Manual statistics entry, custom CSV/JSON statistics import, and additional tracker adapters remain roadmap work.

## Install on a VPS

Use Debian 12 or 13 for an internet-facing server. Debian 11 is end-of-life and is supported only as a compatibility path.

1. Create a DNS A/AAAA record for a subdomain such as `stats.example.com`, pointing to your VPS.
2. Allow inbound TCP ports 80 and 443.
3. Run:

```bash
git clone --recurse-submodules https://github.com/race-in/Sherlock.git
cd Sherlock/sherlock-v2
sudo ./deploy/install.sh --domain stats.example.com --letsencrypt you@example.com
```

Replace the example hostname and email. The installer builds the pinned Ruby runtime, downloads and checksum-verifies the Node.js build runtime, installs PostgreSQL, creates encrypted Rails credentials, configures systemd and Nginx, obtains a Let's Encrypt certificate, and checks the local Rails health endpoint. It enables single-user mode and prints a 64-character one-time setup token only while the database has no account; enter that token on the first-run page. Keep the token private. Existing databases with more than one account are rejected without deleting data.

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
sudo ./deploy/install.sh
```

The installer preserves the existing environment file, database and encrypted credentials. Review the installer output and check `sudo sherlock-ctl status` after an update. For important data, take a PostgreSQL and credentials backup before upgrading; do not rely on an untested backup.

## Application features

The bundled application currently provides tracker dashboards and history, tracker API connections, snapshot charts, comparison views, Prometheus metrics, and qui integration. The upstream invite/account code remains in the source for attribution and compatibility, but the native installer disables user-creation routes and enforces one account. See [the bundled application README](sherlock-v2/README.md) for upstream behavior and configuration details.

## Custom Edition roadmap

The target is a private single-user instance with automatic and manual statistics, timestamped history, CSV/JSON import/export, and additional permitted tracker integrations. Single-user installation controls are implemented in the native deployment path; manual statistics, custom statistics import/export and additional adapters remain planned work, not completed features.

See [ROADMAP.md](ROADMAP.md) for phases, acceptance criteria and release gates. The root legacy installer is a separate deployment scaffold; use only `sherlock-v2/deploy/install.sh` for the bundled native app.

## Security and source

- Never commit production credentials, Rails master keys, tracker API keys, database passwords or backup archives.
- Keep Nginx as the public entry point; do not expose Puma or the worker metrics port.
- Treat database dumps and credential archives as sensitive.
- Report deployment vulnerabilities privately using the repository's Security tab; see [SECURITY.md](SECURITY.md).
- The bundled application originated from [whatstatus/sherlock-v2 on Codeberg](https://codeberg.org/whatstatus/sherlock-v2). Preserve upstream attribution and notices.

## Validation

GitHub Actions runs shell syntax checks, ShellCheck, deployment regression tests, an upstream source inventory, and Debian 11/12/13 compatibility jobs. The Node frontend build, Ruby/Rails tests, and PostgreSQL schema checks validate the bundled `sherlock-v2/` tree; the separate source-inventory job compares against upstream Codeberg. CI container results do not replace a fresh-install test on real VPS hosts. DNS, certificate issuance, systemd startup, upgrade behavior and restore procedures must be verified in a controlled deployment before production use.

