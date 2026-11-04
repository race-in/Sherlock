# Security Policy

## Reporting a vulnerability

Please do **not** publish credentials, API keys, database dumps, exploit details, or an unpatched vulnerability in a public issue.

Use GitHub's private vulnerability reporting for this repository:
- Open the repository's **Security** tab.
- Select **Report a vulnerability** (private vulnerability reporting / security advisory).

Include the affected commit, Debian release and architecture, reproduction steps, impact, and relevant redacted logs. Never attach an unredacted Sherlock database or credentials archive.

## Deployment safety

- Keep Rails/Puma port 3000 bound to loopback; expose only Nginx on ports 80/443.
- Keep the worker Prometheus exporter on loopback (`METRICS_BIND=127.0.0.1`) unless a separately authenticated private monitoring path is configured. Do not expose port 9394 publicly.
- Do not publish the environment file, Rails production keys, API keys, PostgreSQL passwords, or backup archives.
- Backups contain both tracker statistics and the Rails decryption key. Treat them as highly sensitive and store them off-host with restricted access.
- If an API key or Rails production key is exposed, rotate/revoke it at the relevant service and replace the affected secrets.
- Debian 11 is end-of-life; use Debian 12 or 13 for internet-facing production deployments.

## Scope

This repository contains the Sherlock Rails application under `sherlock-v2/`, native deployment tooling, and local deployment patches. Application vulnerabilities in the bundled tree, authentication/session handling, credential storage, import/export, metrics exposure, or installer/update/backup/restore behavior are in scope. Preserve upstream attribution and coordinate vulnerabilities that also affect the upstream project with its maintainers. Vulnerabilities in third-party tracker websites themselves should be reported to those services.

**Deployment status:** the canonical native installer sets `SINGLE_USER_MODE=true`, requires a random one-time setup token before first-account creation, removes invite/join/user-management routes, and serializes every Rails user-creation path before allowing the first account only. This protection applies only to installations made with `sherlock-v2/deploy/install.sh`; the root legacy installer and manual deployments do not automatically enable it. Keep the setup token private and do not expose the app until HTTPS is configured. A full production-host install and penetration/regression test remain release gates.
