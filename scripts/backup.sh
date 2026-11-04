#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
DEST=${1:-/var/backups/sherlock}
install -d -m 0700 "$DEST"
set -a
. /etc/sherlock/sherlock.env
set +a
PGPASSWORD="$DB_PASSWORD" /usr/lib/postgresql/18/bin/pg_dump -h "${DB_HOST:-127.0.0.1}" -p "${DB_PORT:-5432}" -U "$DB_USER" -d "$DB_NAME" -Fc > "$DEST/${DB_NAME}-$STAMP.dump"
tar -czf "$DEST/sherlock-credentials-$STAMP.tar.gz" -C /opt/sherlock config/credentials/production.key config/credentials/production.yml.enc
chmod 0600 "$DEST"/*
echo "Backup created in $DEST. Store the credentials archive separately and securely."
