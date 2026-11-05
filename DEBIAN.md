# Running Sherlock on Debian without Docker

The step-by-step guide is in the [README](README.md#install-on-debian-without-docker). This page is the short reference.

`deploy/install-debian.sh` installs everything natively on Debian 12 or 13 (Debian 11 and Ubuntu 22.04+
are best effort), on x86_64 or aarch64. It does what the Dockerfile and `bin/docker-entrypoint` do, with
systemd instead of a container.

```sh
git clone https://github.com/race-in/Sherlock.git && cd Sherlock
# public server with a domain: nginx + free HTTPS certificate
sudo bash deploy/install-debian.sh --domain sherlock.example.com --letsencrypt you@example.com
# private network, plain HTTP
sudo bash deploy/install-debian.sh --domain 192.168.1.10 --no-ssl
```

Without root (no sudo) run the same script as a normal user: `bash deploy/install-debian.sh --domain localhost`. It then installs into
`~/.local/share/sherlock` and `~/.config/sherlock`, runs as you with its own PostgreSQL cluster, and lists any missing
system packages for an administrator to install. Details: [README](README.md#install-without-root-rootless).

Run `bash deploy/install-debian.sh --help` for all options. Open the site afterwards and create the first
account: it becomes the admin. Everyone else joins with invites.

| What | Where |
|---|---|
| App | `/opt/sherlock` (runs as system user `sherlock`) |
| Settings | `/etc/sherlock/sherlock.env`, then `sudo systemctl restart sherlock` |
| Credentials | `/etc/sherlock/credentials/` — **back up `production.key`** |
| Service | `sherlock.service` (web, and tracker polling inside Puma) |
| Helper | `sudo sherlock-ctl status\|logs\|restart\|rails ARGS` |

The settings file takes the variables from the README's configuration table (`FORCE_SSL`, `JOB_CONCURRENCY`,
`RAILS_LOG_LEVEL`, ...) plus `BIND_ADDRESS` and `METRICS_BIND` (worker metrics, default `127.0.0.1`).

**What the installer does:** installs apt packages; installs PostgreSQL 18 (PGDG repository, else Debian's
own version; databases older than 17 get `db/structure.sql` loaded without its `SET transaction_timeout`
line); builds the Ruby from `.ruby-version` with a commit-pinned ruby-build; downloads the Node.js from
`.node-version` with a checksum check, only for the asset build; creates the encrypted credentials; creates
the database and runs `db:prepare db:seed`; installs the systemd unit; optionally nginx and certbot.

**Updating:** `git pull`, then run the same script again. Database, credentials and settings are kept. Make a
backup first: `sudo -u postgres pg_dump -Fc sherlockdb_prod > sherlock.dump`.

**Lost the admin password?** `sudo sherlock-ctl rails 'users:reset_password[username]'`.
