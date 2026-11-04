#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/sherlock-v2/deploy/install.sh"
BACKUP="$ROOT/scripts/backup.sh"
APP_CONFIG="$ROOT/sherlock-v2/config/application.rb"

# Existing installations must resolve their saved port before choosing a package.
existing_block=$(sed -n '/if (( EXISTING_INSTALL == 1 )); then/,/else/p' "$INSTALLER")
grep -Fq 'pg_lsclusters -h | awk -v p="$DB_PORT" ' <<<"$existing_block"
grep -Fq 'Existing install uses local PostgreSQL port $DB_PORT' <<<"$existing_block"
grep -Fq 'if [[ -n "$OPT_PG_VERSION" && "$OPT_PG_VERSION" != "$PG_MAJOR" ]]' <<<"$existing_block"

# The upgrade path must run stop, backup, and then modify before replacing source or migrating.
main_block=$(sed -n '/^main() {/,/^}/p' "$INSTALLER")
backup_line=$(grep -n 'run_pre_upgrade_backup' <<<"$main_block" | head -n 1 | cut -d: -f1)
stop_line=$(grep -n 'stop_existing_service' <<<"$main_block" | head -n 1 | cut -d: -f1)
sync_line=$(grep -n 'sync_source' <<<"$main_block" | head -n 1 | cut -d: -f1)
migration_line=$(grep -n 'prepare_database' <<<"$main_block" | head -n 1 | cut -d: -f1)
[[ -n "$backup_line" && -n "$stop_line" && -n "$sync_line" && -n "$migration_line" ]]
(( stop_line < backup_line && backup_line < sync_line && sync_line < migration_line ))

grep -Fq 'APP_VERSION' "$INSTALLER"
grep -Fq 'echo "APP_VERSION=$APP_VERSION"' "$INSTALLER"
grep -Fq 'APP_VERSION' "$APP_CONFIG"

grep -Fq 'SERVER_MAJOR=$((SERVER_VERSION_NUM / 10000))' "$BACKUP"
grep -Fq 'CLIENT_MAJOR >= SERVER_MAJOR' "$BACKUP"
grep -Fq '"$PG_RESTORE_BIN" --list "$DB_DUMP_TMP"' "$BACKUP"
grep -Fq 'APP_DIR=${SHERLOCK_INSTALL_DIR:-/opt/sherlock}' "$BACKUP"
grep -Fq 'ENV_FILE="$ETC_DIR/sherlock.env"' "$BACKUP"

echo "PASS: native PostgreSQL selection, backup preflight, upgrade ordering, and version contract"
