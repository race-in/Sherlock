#!/usr/bin/env bash
# Checks the rootless parts of install-debian.sh as a normal user, without Ruby or Node:
# the private PostgreSQL cluster, loading db/structure.sql, and the sherlock-ctl helper.
# Needs the PostgreSQL server binaries (apt install postgresql). Run as a non-root user.
set -Eeuo pipefail
[[ $EUID -ne 0 ]] || { echo "Run this as a normal user." >&2; exit 2; }
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOME="$(mktemp -d)"; export HOME
unset XDG_DATA_HOME XDG_CONFIG_HOME XDG_RUNTIME_DIR
cleanup() { [[ -z ${PG_BIN:-} ]] || "$PG_BIN/pg_ctl" -D "$PGDATA" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$HOME"; }
trap cleanup EXIT

set -- --domain localhost -y
# shellcheck disable=SC1091
source "$SRC/deploy/install-debian.sh"
init_paths; CODENAME=bookworm; settings >/dev/null
RUBY_DIR=/nonexistent; EXTERNAL_DB=0
PG_BIN="$(find_pg_bin)"; [[ -n $PG_BIN ]] || { echo "No PostgreSQL server binaries found; install postgresql."; exit 2; }
ok() { printf 'ok  %s\n' "$*"; }

[[ $MODE == user && $INSTALL_DIR == "$HOME/.local/share/sherlock/app" ]] && ok "rootless paths"
postgres_user >/dev/null && ok "private cluster created and started"
postgres_user >/dev/null && ok "second run is idempotent"
export PGPASSWORD="$DB_PASSWORD"
if (( PG_MAJOR < 17 )); then sed '/^SET transaction_timeout = 0;$/d' "$SRC/db/structure.sql"; else cat "$SRC/db/structure.sql"; fi \
  | psql -X -q -h 127.0.0.1 -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f - >/dev/null && ok "db/structure.sql loads"
[[ "$(psql -X -h 127.0.0.1 -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc 'SELECT count(*) > 0 FROM sherlockdb.schema_migrations')" == t ]] && ok "schema_migrations filled"
if PGPASSWORD=wrong psql -X -h 127.0.0.1 -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc 'SELECT 1' >/dev/null 2>&1; then echo "FAIL: wrong password accepted"; exit 1; fi
ok "wrong password is refused"
unset PGPASSWORD

user_and_files >/dev/null
[[ "$(stat -c %a "$ENV_FILE")" == 600 ]] && ok "settings file is private (0600)"
mkdir -p "$INSTALL_DIR/bin"
printf '#!/bin/sh\n[ "$1" = server ] && exec sleep 300\nexit 0\n' > "$INSTALL_DIR/bin/rails"; chmod +x "$INSTALL_DIR/bin/rails"
install_service_user >/dev/null
"$CTL" start >/dev/null; sleep 1
"$CTL" status >/dev/null && ok "sherlock-ctl start/status"
"$CTL" restart >/dev/null; sleep 1; "$CTL" status >/dev/null && ok "sherlock-ctl restart"
"$CTL" rails db:prepare && ok "sherlock-ctl rails passes arguments"
"$CTL" stop >/dev/null
if "$CTL" status >/dev/null 2>&1; then echo "FAIL: still running"; exit 1; fi
ok "sherlock-ctl stop (Rails and PostgreSQL)"
