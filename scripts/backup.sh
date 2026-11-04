#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
STAMP="$(date -u +%Y%m%dT%H%M%S.%NZ)-${BASHPID}"
DEST=${1:-/var/backups/sherlock}
APP_DIR=${SHERLOCK_INSTALL_DIR:-/opt/sherlock}
ETC_DIR=${SHERLOCK_CONF_DIR:-/etc/sherlock}
APP_USER=${SHERLOCK_APP_USER:-sherlock}
ENV_FILE="$ETC_DIR/sherlock.env"
install -d -m 0700 "$DEST"
chown root:root "$DEST"
chmod 0700 "$DEST"
TMP_DIR=$(mktemp -d "$DEST/.sherlock-backup.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

set -a
. "$ENV_FILE"
set +a

DB_DUMP_TMP="$TMP_DIR/${DB_NAME}-$STAMP.dump"
SECRETS_TMP="$TMP_DIR/sherlock-secrets-$STAMP.tar.gz"
MANIFEST_TMP="$TMP_DIR/manifest.txt"

PG_DUMP_BIN=${PG_DUMP_BIN:-$(command -v pg_dump || true)}
[[ -n "$PG_DUMP_BIN" && -x "$PG_DUMP_BIN" ]] || {
  echo "PostgreSQL pg_dump client is missing; install the matching postgresql-client package." >&2
  exit 1
}
PSQL_BIN=${PSQL_BIN:-$(command -v psql || true)}
PG_RESTORE_BIN=${PG_RESTORE_BIN:-$(command -v pg_restore || true)}
[[ -n "$PSQL_BIN" && -x "$PSQL_BIN" && -n "$PG_RESTORE_BIN" && -x "$PG_RESTORE_BIN" ]] || {
  echo "PostgreSQL psql/pg_restore clients are missing; install a matching postgresql-client package." >&2
  exit 1
}
SERVER_VERSION_NUM=$(PGPASSWORD="$DB_PASSWORD" "$PSQL_BIN" -X -qAt -h "${DB_HOST:-127.0.0.1}" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -c 'SHOW server_version_num')
[[ "$SERVER_VERSION_NUM" =~ ^[0-9]+$ ]] || { echo "Could not determine PostgreSQL server version." >&2; exit 1; }
SERVER_MAJOR=$((SERVER_VERSION_NUM / 10000))
CLIENT_MAJOR=$("$PG_DUMP_BIN" --version | sed -E 's/.* ([0-9]+)(\.[0-9]+)*$/\1/')
[[ "$CLIENT_MAJOR" =~ ^[0-9]+$ ]] && (( CLIENT_MAJOR >= SERVER_MAJOR )) || {
  echo "pg_dump client major $CLIENT_MAJOR is older than PostgreSQL server major $SERVER_MAJOR. Install a matching or newer client; no backup was created." >&2
  exit 1
}
PGPASSWORD="$DB_PASSWORD" "$PG_DUMP_BIN" \
  -h "${DB_HOST:-127.0.0.1}" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -Fc \
  --no-owner --no-acl --file="$DB_DUMP_TMP"
"$PG_RESTORE_BIN" --list "$DB_DUMP_TMP" >/dev/null || { echo "Generated dump failed archive validation." >&2; exit 1; }

tar -czf "$SECRETS_TMP" \
  -C "$APP_DIR" config/credentials/production.key config/credentials/production.yml.enc \
  -C "$ETC_DIR" sherlock.env

{
  printf 'created_at_utc=%s\n' "$STAMP"
  APP_COMMIT=""
  if APP_COMMIT=$(runuser -u "$APP_USER" -- git -C "$APP_DIR" rev-parse --verify HEAD 2>/dev/null); then
    :
  elif [[ -f "$APP_DIR/.sherlock-native-install" ]]; then
    APP_COMMIT=$(sed -n 's/^source_commit=//p' "$APP_DIR/.sherlock-native-install" | head -n 1)
  fi
  APP_COMMIT=${APP_COMMIT:-unversioned-native-install}
  printf 'application_commit=%s\n' "$APP_COMMIT"
  printf 'database=%s\n' "$DB_NAME"
  printf 'secrets_archive=%s\n' "sherlock-secrets-$STAMP.tar.gz"
  printf 'postgres_client_version=%s\n' "$("$PG_DUMP_BIN" --version)"
} > "$MANIFEST_TMP"

chmod 0600 "$DB_DUMP_TMP" "$SECRETS_TMP" "$MANIFEST_TMP"
DB_FINAL="$DEST/${DB_NAME}-$STAMP.dump"
SECRETS_FINAL="$DEST/sherlock-secrets-$STAMP.tar.gz"
MANIFEST_FINAL="$DEST/manifest-$STAMP.txt"
mv "$DB_DUMP_TMP" "$DB_FINAL"
mv "$SECRETS_TMP" "$SECRETS_FINAL"
mv "$MANIFEST_TMP" "$MANIFEST_FINAL"
rmdir "$TMP_DIR"
trap - EXIT

printf 'Database backup: %s\n' "$DB_FINAL"
printf 'Secrets archive: %s\n' "$SECRETS_FINAL"
printf 'Manifest: %s\n' "$MANIFEST_FINAL"
echo 'Store all backup files securely and test restoration periodically.'
