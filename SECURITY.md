# Security Policy

## Reporting a vulnerability

Please do **not** publish credentials, API keys, database dumps, exploit details, or an unpatched vulnerability in a public issue.

Use GitHub's private vulnerability reporting for this repository:
- Open the repository's **Security** tab.
- Select **Report a vulnerability** (private vulnerability reporting / security advisory).

Include the affected commit, Debian release and architecture, reproduction steps, impact, and relevant redacted logs. Never attach an unredacted Sherlock database or credentials archive.

## Deployment safety

- Keep Rails/Puma port 3000 bound to loopback; expose only Nginx on ports 80/443.
- Do not publish the environment file, Rails production keys, API keys, PostgreSQL passwords, or backup archives.
- Backups contain both tracker statistics and the Rails decryption key. Treat them as highly sensitive and store them off-host with restricted access.
- If an API key or Rails production key is exposed, rotate/revoke it at the relevant service and replace the affected secrets.
- Debian 11 is end-of-life; use Debian 12 or 13 for internet-facing production deployments.

## Scope

This repository currently contains native deployment tooling, not the upstream Sherlock application itself. Vulnerabilities in the upstream application or in tracker websites should be reported to their respective maintainers. The deployment scripts can still introduce local privilege, credential-handling, or network-exposure risks and are in scope here.
