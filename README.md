# Sherlock v2 — Native Debian Deployment Kit

This repository currently contains the **native deployment scaffold only**. It does not redistribute the upstream Sherlock application source.

## Stack

- Debian 12/13
- Ruby 4.0.9, Bundler 4.0.20
- Node.js 26.12.0
- PostgreSQL 18
- Puma managed by systemd
- Solid Queue inside Puma for the documented single-server setup
- Nginx reverse proxy and Let's Encrypt TLS
- No Docker

## Important scope notice

This is a deployment kit, **not yet Sherlock Custom Edition**. It does not implement the planned single-user-only mode, manual statistics entry, CSV/JSON import, or additional tracker adapters. The upstream app remains unchanged and may retain its upstream multi-user/invite behavior.

The supplied upstream archive did not contain a standalone LICENSE file. Before redistributing or publishing modified upstream source, obtain and verify the maintainer's permission/license. This repository therefore keeps the deployment tooling separate from upstream application source.

## Requirements

- Debian 12 or 13
- At least 4 GB RAM and 30 GB free disk recommended
- A DNS A record such as `stats.example.com` pointing to the VPS
- TCP 80/443 allowed in provider firewall
- An authorized Git repository containing the Sherlock application source, including `.ruby-version`, `.node-version`, `Gemfile.lock`, and Rails files

## Install

Copy this directory to the VPS and run as root:

```bash
chmod +x install.sh
./install.sh stats.example.com https://github.com/OWNER/APP-SOURCE.git main
```

The installer installs system packages, builds the pinned Ruby/Node versions, installs PostgreSQL 18, clones the application source into `/opt/sherlock`, prepares credentials/database, builds assets, installs systemd and Nginx, and requests the TLS certificate.

It refuses to overwrite an existing `/opt/sherlock` installation or an existing database role.

## Operations

```bash
systemctl status sherlock
journalctl -u sherlock -f
systemctl restart sherlock
curl -fsS http://127.0.0.1:3000/up
```

- Dashboard: `https://stats.example.com`
- Update: `bash scripts/update.sh` (run as root)
- Backup: `bash scripts/backup.sh` (run as root)

## Security and backups

- Rails binds behind Nginx; do not expose port 3000 publicly.
- `/etc/sherlock/sherlock.env` is root-owned and group-readable only by the service account group.
- Back up `/opt/sherlock/config/credentials/production.key` and `production.yml.enc` securely.
- Never commit production keys, API keys, database passwords, or `sherlock.env`.
- Store the database dump and credential archive separately and securely.
- Verify restore procedures before relying on backups.

## Files

- `install.sh`: native Debian installation
- `templates/sherlock.service`: systemd service template
- `templates/nginx-http.conf`: HTTP reverse proxy template (Certbot upgrades it to HTTPS)
- `scripts/update.sh`: fast-forward update and migration
- `scripts/backup.sh`: PostgreSQL and encrypted Rails credential backup

## Validation status

Shell syntax was checked locally. The installer has **not** been run on a target VPS, and live DNS/HTTPS/database deployment has not been verified. The custom application features listed above are not implemented in this repository yet.
