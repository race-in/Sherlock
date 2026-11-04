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

PGPASSWORD="$DB_PASSWORD" /usr/lib/postgresql/18/bin/pg_dump \
  -h "${DB_HOST:-127.0.0.1}" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -Fc \
  --no-owner --no-acl --file="$DB_DUMP_TMP"

tar -czf "$SECRETS_TMP" \
  -C /opt/sherlock config/credentials/production.key config/credentials/production.yml.enc \
  -C /etc/sherlock sherlock.env

{
  printf 'created_at_utc=%s\n' "$STAMP"
  printf 'application_commit=%s\n' "$(runuser -u sherlock -- git -C /opt/sherlock rev-parse HEAD)"
  printf 'database=%s\n' "$DB_NAME"
  printf 'secrets_archive=%s\n' "sherlock-secrets-$STAMP.tar.gz"
  printf 'postgres_client_version=%s\n' "$(/usr/lib/postgresql/18/bin/pg_dump --version)"
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
