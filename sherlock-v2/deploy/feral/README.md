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
- PostgreSQL client libraries usable by the `pg` gem, plus `pg_isready` and `psql`
- Node/npm only when assets need to be built (precompiled assets are preferred)
- an external PostgreSQL database and credentials
- a user-writable application directory and an available unprivileged TCP port

The branch bootstrap builds private zlib, libyaml, OpenSSL, Ruby and PostgreSQL
client libraries/tools under the user's home directory. It also installs a temporary
temporary Node.js 22 glibc-2.17-compatible build runtime for asset compilation. No system library
or package is changed.

## Intended layout

- Application: `$HOME/.local/opt/sherlock`
- Runtime/config: `$HOME/.config/sherlock-feral`
- Logs and PID: `$HOME/.local/var/sherlock-feral`
- Backups: `$HOME/.local/var/sherlock-feral/backups`

## Diagnose the Feral slot first

Run this read-only report over SSH before attempting installation:

```sh
bash sherlock-v2/deploy/feral/diagnose.sh
```

It reports Debian/glibc, compiler/build tools, Ruby/OpenSSL, Node, PostgreSQL client tools, storage and limits. It does not read credentials or modify files. Keep the output so the Debian 9 runtime strategy can be checked against the actual shared-hosting environment.

## Install from the Feral development branch only

Do not install from `main`. Clone the dedicated development branch directly on the Feral slot:

```sh
git clone --branch feature/feral-rootless-edition --single-branch --recurse-submodules https://github.com/race-in/Sherlock.git Sherlock-Feral
cd Sherlock-Feral/sherlock-v2
bash ./deploy/feral/diagnose.sh
```

Review the diagnostic output first. Build the private runtimes from this same development branch:
 
```sh
bash ./deploy/feral/bootstrap-runtime.sh
```

This is a long native build. If it fails, inspect logs under `~/.local/var/sherlock-feral/`
and do not continue with the installer. After it succeeds, install from this same checkout:

```sh
bash ./deploy/feral/install.sh --domain stats.example.com --port 18443 --db-host DB_HOST --db-name DB_NAME --db-user DB_USER
```

The development branch is the deployment source of truth for this Feral test. Update it with `git pull --ff-only origin feature/feral-rootless-edition` before testing a newer commit; do not switch this checkout to `main`.

The installer is intentionally fail-closed. It validates the host/runtime/database
before replacing an existing application. The database itself must be provisioned
outside this installer. Before changing the app directory, the installer authenticates
with `psql`, applies PostgreSQL SSL mode (default `require`), creates the
`sherlockdb` schema if absent, and verifies the configured role has schema USAGE
and CREATE privileges. Rails migrations then create the application tables.

For Supabase on an IPv4-only Feral slot, use the **Session Pooler** endpoint and port
`5432` from the Supabase Dashboard's Connect panel. Use the exact pooler hostname
and username shown there (often `postgres.<project-ref>`), set `DB_NAME=postgres`,
and keep `SHERLOCK_PGSSLMODE=require` (the default). Do not use the Transaction
Pooler for this persistent Rails/Puma process. Never put the database password in
shell history or commit it to the repository.

The installer creates encrypted Rails production credentials and a private key under
`~/.config/sherlock-feral/credentials/`. Database settings and `APP_HOST` are written
to a private environment file (mode 0600). The installer also configures Ruby/OpenSSL
to use a readable system CA bundle (normally `/etc/ssl/certs/ca-certificates.crt`) and
persists `SSL_CERT_FILE` / `SSL_CERT_DIR` for Puma and Solid Queue. TLS certificate
verification remains enabled; do not set `VERIFY_NONE` or disable peer verification.

If the hosting proxy forwards a second Host header (for example, an account-specific
inner vhost), add it as a comma-separated `APP_HOST_ALIASES` entry in the private
environment file. The Rails host allowlist reads this setting without weakening
Host Authorization.

Back up the credentials directory securely; do not publish or share either file.

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
