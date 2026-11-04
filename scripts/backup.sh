#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
STAMP="$(date -u +%Y%m%dT%H%M%S.%NZ)-${BASHPID}"
DEST=${1:-/var/backups/sherlock}
install -d -m 0700 "$DEST"
chown root:root "$DEST"
chmod 0700 "$DEST"
TMP_DIR=$(mktemp -d "$DEST/.sherlock-backup.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

set -a
. /etc/sherlock/sherlock.env
set +a

DB_DUMP_TMP="$TMP_DIR/${DB_NAME}-$STAMP.dump"
SECRETS_TMP="$TMP_DIR/sherlock-secrets-$STAMP.tar.gz"
MANIFEST_TMP="$TMP_DIR/manifest.txt"

PG_DUMP_BIN=${PG_DUMP_BIN:-$(command -v pg_dump || true)}
[[ -n "$PG_DUMP_BIN" && -x "$PG_DUMP_BIN" ]] || {
  echo "PostgreSQL pg_dump client is missing; install the matching postgresql-client package." >&2
  exit 1
}
PGPASSWORD="$DB_PASSWORD" "$PG_DUMP_BIN" \
  -h "${DB_HOST:-127.0.0.1}" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -Fc \
  --no-owner --no-acl --file="$DB_DUMP_TMP"

tar -czf "$SECRETS_TMP" \
  -C /opt/sherlock config/credentials/production.key config/credentials/production.yml.enc \
  -C /etc/sherlock sherlock.env

{
  printf 'created_at_utc=%s\n' "$STAMP"
  APP_COMMIT=""
  if APP_COMMIT=$(runuser -u sherlock -- git -C /opt/sherlock rev-parse --verify HEAD 2>/dev/null); then
    :
  elif [[ -f /opt/sherlock/.sherlock-native-install ]]; then
    APP_COMMIT=$(sed -n 's/^source_commit=//p' /opt/sherlock/.sherlock-native-install | head -n 1)
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
