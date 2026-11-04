# Sherlock on Feral Hosting (Debian 9, rootless)

This deployment adapter is separate from the native Debian installer. It never uses
sudo, apt, systemd, a system-wide PostgreSQL server, or a system-wide web server.

## Compatibility gate

The host is expected to report Debian GNU/Linux 9 (Stretch). The Rails application
currently requires Ruby >= 3.2 and a working OpenSSL >= 1.1.1 runtime. Debian 9's
system OpenSSL (1.0.2) is too old for that Ruby/OpenSSL combination. Do not point
Ruby at the system OpenSSL and do not silently downgrade TLS verification.

The adapter deliberately checks these prerequisites before changing files:
- Ruby >= 3.2 with OpenSSL >= 1.1.1
- Bundler compatible with the checked-in Gemfile.lock
- PostgreSQL client libraries usable by the `pg` gem
- Node/npm only when assets need to be built (precompiled assets are preferred)
- an external PostgreSQL database and credentials
- a user-writable application directory and an available unprivileged TCP port

A runtime bootstrap for Stretch must build a private OpenSSL and Ruby under the
user's home directory. That bootstrap is a separate step; the adapter must not
pretend the Debian 9 system packages satisfy it.

## Intended layout

- Application: `$HOME/.local/opt/sherlock`
- Runtime/config: `$HOME/.config/sherlock-feral`
- Logs and PID: `$HOME/.local/var/sherlock-feral`
- Backups: `$HOME/.local/var/sherlock-feral/backups`

## Diagnose the Feral slot first

Run this read-only report over SSH before attempting installation:

\`\`\`sh
bash sherlock-v2/deploy/feral/diagnose.sh
\`\`\`

It reports Debian/glibc, compiler/build tools, Ruby/OpenSSL, Node, PostgreSQL client tools, storage and limits. It does not read credentials or modify files. Keep the output so the Debian 9 runtime strategy can be checked against the actual shared-hosting environment.

## Install from the Feral development branch only

Do not install from `main`. Clone the dedicated development branch directly on the Feral slot:

```sh
git clone --branch feature/feral-rootless-edition --single-branch --recurse-submodules https://github.com/race-in/Sherlock.git Sherlock-Feral
cd Sherlock-Feral/sherlock-v2
bash ./deploy/feral/diagnose.sh
```

Review the diagnostic output first. When the private Ruby/OpenSSL runtime and external PostgreSQL prerequisites are ready, install from this same checkout:

```sh
bash ./deploy/feral/install.sh --domain stats.example.com --port 18443 --db-host DB_HOST --db-name DB_NAME --db-user DB_USER
```

The development branch is the deployment source of truth for this Feral test. Update it with `git pull --ff-only origin feature/feral-rootless-edition` before testing a newer commit; do not switch this checkout to `main`.

The installer is intentionally fail-closed. It validates the host/runtime/database
before replacing an existing application. It requires the database to be provisioned
outside this installer; the configured DB user must be able to create the
`sherlockdb` schema and run migrations.

The installer creates private `RAILS_MASTER_KEY` and `SECRET_KEY_BASE` values automatically. Database settings and `APP_HOST` are written to the private environment file (mode 0600). Do not publish or share this file.

## Process controls

```sh
bash "$HOME/.local/opt/sherlock/deploy/feral/control.sh" start
bash "$HOME/.local/opt/sherlock/deploy/feral/control.sh" status
bash "$HOME/.local/opt/sherlock/deploy/feral/control.sh" logs
bash "$HOME/.local/opt/sherlock/deploy/feral/control.sh" restart
bash "$HOME/.local/opt/sherlock/deploy/feral/control.sh" stop
```

The process runs as the account owner, binds to loopback by default, and is managed
with a PID file and nohup rather than systemd. Configure the Feral-supported
subdomain/reverse-proxy mechanism to forward to that loopback port. Do not expose
Puma directly to the public internet.

## Important limitation

Debian 9 is end-of-life. This adapter does not make Stretch secure or supported by
Debian. If a private modern OpenSSL/Ruby toolchain cannot be built on the slot, stop
there; do not weaken TLS or overwrite the host's system libraries. The Feral slot
must be tested directly before this deployment can be called production-ready.
