#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR=/opt/sherlock
ETC_DIR=/etc/sherlock
APP_USER=sherlock
APP_GROUP=sherlock
PG_BINDIR=${PG_BINDIR:-}
if [[ -z "$PG_BINDIR" ]]; then
  PG_BINDIR=$(pg_config --bindir 2>/dev/null || true)
fi
if [[ ! -x "$PG_BINDIR/pg_restore" ]]; then
  PG_RESTORE_PATH=$(command -v pg_restore || true)
  [[ -n "$PG_RESTORE_PATH" ]] && PG_BINDIR=$(dirname "$PG_RESTORE_PATH")
fi
PG_BINDIR=${PG_BINDIR:-/usr/lib/postgresql/18/bin}

die() { echo "ERROR: $*" >&2; exit 1; }

validate_environment_file() {
  local file=$1
  local key value
  declare -A seen=()
  while IFS='=' read -r key value || [[ -n ${key:-} ]]; do
    if [[ -z "$key" || "$key" == \#* ]]; then
      continue
    fi
    [[ "$key" =~ ^[A-Z_]+$ ]] || die "Invalid setting in archived environment file."
    [[ "$value" =~ ^[A-Za-z0-9_./:@+-]+$ ]] || die "Unsafe value in archived environment setting: $key"
    case "$key" in
      RAILS_ENV|APP_HOST|RAILS_MASTER_KEY|DB_HOST|DB_PORT|DB_NAME|DB_USER|DB_PASSWORD|BUNDLE_PATH|RAILS_MAX_THREADS|DB_POOL|APP_GIT_BRANCH|PORT|FORCE_SSL|SOLID_QUEUE_IN_PUMA|METRICS_BIND|RAILS_LOG_LEVEL|SINGLE_USER_MODE|FIRST_RUN_TOKEN|BIND_ADDRESS|JOB_CONCURRENCY|METRICS_PORT) ;;
      *) die "Unexpected environment setting in archive: $key" ;;
    esac
    [[ -z ${seen[$key]+x} ]] || die "Duplicate environment setting: $key"
    seen[$key]=1
  done < "$file"
  for key in RAILS_ENV APP_HOST DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD; do
    [[ -n ${seen[$key]+x} ]] || die "Required environment setting is missing: $key"
  done
}

verify_secrets_archive() {
  local archive=$1
  local expected actual listing tmp
  [[ -s "$archive" ]] || die "Secrets archive is missing or empty: $archive"
  expected=$(printf '%s\n' \
    'config/credentials/production.key' \
    'config/credentials/production.yml.enc' \
    'sherlock.env' | LC_ALL=C sort)
  actual=$(tar -tzf "$archive" | LC_ALL=C sort) || die "Cannot list secrets archive: $archive"
  [[ "$actual" == "$expected" ]] || die "Unexpected files in secrets archive; refusing unsafe extraction."
  listing=$(tar -tvzf "$archive") || die "Cannot inspect secrets archive file types."
  while IFS= read -r line; do
    [[ "${line:0:1}" == "-" ]] || die "Secrets archive may contain regular files only."
  done <<< "$listing"
  tmp=$(mktemp -d /tmp/sherlock-archive-verify.XXXXXX)
  # Even a rejected archive may contain sensitive credentials. Always remove
  # the temporary extraction directory if validation exits early.
  trap 'rm -rf "$tmp"' EXIT
  tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$tmp"
  validate_environment_file "$tmp/sherlock.env"
  rm -rf "$tmp"
  trap - EXIT
}


verify_backup_pair() {
  local dump=$1 archive=$2 dump_base archive_base archive_db_name dump_stamp archive_stamp archived_env

  [[ -s "$dump" ]] || die "Database dump is missing or empty: $dump"
  [[ -s "$archive" ]] || die "Secrets archive is missing or empty: $archive"
  verify_secrets_archive "$archive"

  dump_base=$(basename -- "$dump")
  archive_base=$(basename -- "$archive")
  archived_env=$(tar -xOzf "$archive" sherlock.env) || die "Cannot read archived Sherlock environment."
  archive_db_name=$(printf '%s\n' "$archived_env" | awk -F= '$1 == "DB_NAME" { sub(/^[^=]*=/, ""); print; exit }')
  [[ "$archive_db_name" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || die "Invalid DB_NAME in secrets archive."

  [[ "$dump_base" == "$archive_db_name-"*.dump ]] || die "Database dump filename does not match archived DB_NAME ($archive_db_name)."
  [[ "$archive_base" == sherlock-secrets-*.tar.gz ]] || die "Unexpected secrets archive filename."
  dump_stamp=${dump_base#"$archive_db_name-"}
  dump_stamp=${dump_stamp%.dump}
  archive_stamp=${archive_base#sherlock-secrets-}
  archive_stamp=${archive_stamp%.tar.gz}

  [[ "$dump_stamp" =~ ^[0-9]{8}T[0-9]{6}\.[0-9]{9}Z-[0-9]+$ ]] || die "Database dump filename has an invalid backup timestamp."
  [[ "$archive_stamp" =~ ^[0-9]{8}T[0-9]{6}\.[0-9]{9}Z-[0-9]+$ ]] || die "Secrets archive filename has an invalid backup timestamp."
  [[ "$dump_stamp" == "$archive_stamp" ]] || die "Database dump and secrets archive are from different backup runs."

  echo "PASS: database dump and secrets archive belong to backup $dump_stamp for $archive_db_name."
}

if [[ ${1:-} == --verify-pair ]]; then
  [[ $# -eq 3 ]] || die "Usage: $0 --verify-pair <database.dump> <secrets-archive.tar.gz>"
  verify_backup_pair "$2" "$3"
  exit 0
fi

if [[ ${1:-} == --verify ]]; then
  [[ $# -eq 2 ]] || die "Usage: $0 --verify <secrets-archive.tar.gz>"
  verify_secrets_archive "$2"
  echo "PASS: secrets archive members, file types, and environment file are valid."
  exit 0
fi

if [[ ${1:-} == --verify-dump ]]; then
  [[ $# -eq 2 ]] || die "Usage: $0 --verify-dump <database.dump>"
  [[ -x "$PG_BINDIR/pg_restore" ]] || die "PostgreSQL pg_restore is missing at $PG_BINDIR/pg_restore."
  VERIFY_DUMP=$(realpath -- "$2")
  [[ -f "$VERIFY_DUMP" && -s "$VERIFY_DUMP" ]] || die "Database dump is missing or empty: $VERIFY_DUMP"
  "$PG_BINDIR/pg_restore" --list "$VERIFY_DUMP" >/dev/null ||
    die "PostgreSQL dump is invalid or unreadable: $VERIFY_DUMP"
  echo "PASS: PostgreSQL dump archive is readable."
  exit 0
fi

[[ $EUID -eq 0 ]] || die "Run as root."
[[ $# -eq 2 ]] || die "Usage: $0 <database.dump> <secrets-archive.tar.gz>"
[[ -d "$APP_DIR" && -d "$APP_DIR/config/credentials" ]] || die "Sherlock application is not installed at $APP_DIR."
id "$APP_USER" >/dev/null 2>&1 || die "Service user $APP_USER does not exist."
getent group "$APP_GROUP" >/dev/null || die "Service group $APP_GROUP does not exist."
[[ -x "$PG_BINDIR/pg_restore" && -x "$PG_BINDIR/pg_dump" ]] || die "Detected PostgreSQL client tools are missing."

DB_DUMP=$(realpath -- "$1")
SECRETS_ARCHIVE=$(realpath -- "$2")
[[ -f "$DB_DUMP" && -s "$DB_DUMP" ]] || die "Database dump is missing or empty: $DB_DUMP"
[[ -x "$PG_BINDIR/pg_restore" ]] || die "PostgreSQL 18 pg_restore is missing."
verify_backup_pair "$DB_DUMP" "$SECRETS_ARCHIVE"
"$PG_BINDIR/pg_restore" --list "$DB_DUMP" >/dev/null || die "PostgreSQL dump is invalid or unreadable; the live database has not been changed."

RESTORE_TMP=$(mktemp -d /tmp/sherlock-restore.XXXXXX)
trap 'rm -rf "$RESTORE_TMP"' EXIT
tar --no-same-owner --no-same-permissions -xzf "$SECRETS_ARCHIVE" -C "$RESTORE_TMP"
for required in \
  "$RESTORE_TMP/config/credentials/production.key" \
  "$RESTORE_TMP/config/credentials/production.yml.enc" \
  "$RESTORE_TMP/sherlock.env"; do
  [[ -s "$required" ]] || die "Required restore file is empty or missing: $required"
done

RESTORED_KEY=$(tr -d '\r\n' < "$RESTORE_TMP/config/credentials/production.key")
ENV_KEY=$(sed -n 's/^RAILS_MASTER_KEY=//p' "$RESTORE_TMP/sherlock.env" | head -n 1)
[[ -n "$RESTORED_KEY" ]] || die "The archived Rails production key is empty."
if [[ -n "$ENV_KEY" && "$RESTORED_KEY" != "$ENV_KEY" ]]; then
  die "Rails master key in the environment archive does not match production.key."
fi

set -a
. "$RESTORE_TMP/sherlock.env"
set +a
read -r -p "This replaces database $DB_NAME. Type RESTORE to continue: " CONFIRM
[[ "$CONFIRM" == RESTORE ]] || die "Restore cancelled."

DB_PORT=${DB_PORT:-5432}
DB_HOST=${DB_HOST:-127.0.0.1}
case "$DB_HOST" in
  localhost|127.0.0.1|::1) ;;
  *) die "Automatic restore is limited to a local PostgreSQL server. This backup targets DB_HOST=$DB_HOST; restore it with an external-database-specific procedure instead." ;;
esac

CREDENTIALS_DIR="$APP_DIR/config/credentials"
if [[ -L "$CREDENTIALS_DIR" ]]; then
  CREDENTIALS_DIR=$(readlink -f -- "$CREDENTIALS_DIR") || die "Cannot resolve the application's credentials symlink."
  [[ "$CREDENTIALS_DIR" == "$ETC_DIR/credentials" ]] || die "Unexpected credentials symlink target: $CREDENTIALS_DIR"
fi

systemctl stop sherlock
install -d -o "$APP_USER" -g "$APP_GROUP" -m 0700 "$CREDENTIALS_DIR"
install -o "$APP_USER" -g "$APP_GROUP" -m 0600 \
  "$RESTORE_TMP/config/credentials/production.key" \
  "$CREDENTIALS_DIR/production.key"
install -o "$APP_USER" -g "$APP_GROUP" -m 0600 \
  "$RESTORE_TMP/config/credentials/production.yml.enc" \
  "$CREDENTIALS_DIR/production.yml.enc"
install -o root -g "$APP_GROUP" -m 0640 \
  "$RESTORE_TMP/sherlock.env" "$ETC_DIR/sherlock.env"

runuser -u postgres -- "$PG_BINDIR/psql" -p "$DB_PORT" -v ON_ERROR_STOP=1 \
  -v db_user="$DB_USER" -v db_password="$DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_password') \gexec
SQL

runuser -u postgres -- "$PG_BINDIR/dropdb" --if-exists --force -p "$DB_PORT" "$DB_NAME"
runuser -u postgres -- "$PG_BINDIR/createdb" -p "$DB_PORT" --owner "$DB_USER" --encoding UTF8 "$DB_NAME"
PGPASSWORD="$DB_PASSWORD" "$PG_BINDIR/pg_restore" \
  --no-owner --no-acl --exit-on-error \
  -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" "$DB_DUMP"

systemctl start sherlock
for attempt in $(seq 1 60); do
  if curl -fsS "http://127.0.0.1:${PORT:-3000}/up" >/dev/null; then
    echo "Restore complete; health check passed: https://$APP_HOST"
    exit 0
  fi
  sleep 2
done
journalctl -u sherlock -n 100 --no-pager
die "Restore finished but the application health check failed."
