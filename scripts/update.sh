#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR=/opt/sherlock
APP_USER=sherlock
RUBY_BIN=/opt/rubies/4.0.9/bin
NODE_BIN=/opt/node/bin
PATCHER=/usr/local/libexec/sherlock/patch-native-app.sh
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MIGRATION_STARTED=0
PREVIOUS_COMMIT=
BACKUP_PATH=

[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -d "$APP_DIR/.git" ]] || { echo "$APP_DIR is not a Git checkout." >&2; exit 1; }
[[ -x "$PATCHER" ]] || { echo "Native deployment patcher missing: $PATCHER" >&2; exit 1; }
[[ -f "$SCRIPT_DIR/backup.sh" ]] || { echo 'backup.sh is missing; refusing to update without a backup.' >&2; exit 1; }

set -a
. /etc/sherlock/sherlock.env
set +a
APP_GIT_BRANCH=${APP_GIT_BRANCH:-main}
PREVIOUS_COMMIT=$(runuser -u "$APP_USER" -- git -C "$APP_DIR" rev-parse HEAD)

restore_service() {
  local status=$?
  if (( status != 0 )); then
    echo "Update failed (exit $status)." >&2
    if (( MIGRATION_STARTED == 0 )); then
      echo "Restoring application source commit $PREVIOUS_COMMIT." >&2
      runuser -u "$APP_USER" -- git -C "$APP_DIR" reset --hard "$PREVIOUS_COMMIT" || true
      runuser -u "$APP_USER" -- bash "$PATCHER" "$APP_DIR" || true
    else
      echo "Database migration had started. Do not reset code automatically; inspect logs and restore the backup if needed." >&2
    fi
    systemctl start sherlock || true
    echo "Backup location: ${BACKUP_PATH:-check /var/backups/sherlock}" >&2
  fi
}
systemctl stop sherlock
trap restore_service EXIT

BACKUP_OUTPUT=$(bash "$SCRIPT_DIR/backup.sh")
printf '%s\n' "$BACKUP_OUTPUT"
BACKUP_PATH=$(printf '%s\n' "$BACKUP_OUTPUT" | sed -n 's/^Database backup: //p' | tail -n 1)

runuser -u "$APP_USER" -- env \
  PATH="$RUBY_BIN:$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin" \
  RAILS_ENV=production APP_HOST="$APP_HOST" RAILS_MASTER_KEY="$RAILS_MASTER_KEY" \
  DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" \
  RAILS_MAX_THREADS="${RAILS_MAX_THREADS:-3}" DB_POOL="${DB_POOL:-10}" \
  BUNDLE_PATH="${BUNDLE_PATH:-/var/lib/sherlock/bundle}" \
  BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT='development:test' \
  bash -s -- "$APP_DIR" "$APP_GIT_BRANCH" "$PATCHER" <<'UPDATE'
set -Eeuo pipefail
APP_DIR=$1
APP_GIT_BRANCH=$2
PATCHER=$3
cd "$APP_DIR"
git fetch --depth 1 origin "$APP_GIT_BRANCH"
git reset --hard FETCH_HEAD
bash "$PATCHER" "$APP_DIR"
bundle install --jobs 2 --retry 3
npm ci
npm run build
SECRET_KEY_BASE_DUMMY=1 APP_HOST=build.invalid bundle exec rails assets:precompile
UPDATE

MIGRATION_STARTED=1
runuser -u "$APP_USER" -- env \
  PATH="$RUBY_BIN:$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin" \
  RAILS_ENV=production APP_HOST="$APP_HOST" RAILS_MASTER_KEY="$RAILS_MASTER_KEY" \
  DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" DB_POOL="${DB_POOL:-10}" \
  BUNDLE_PATH="${BUNDLE_PATH:-/var/lib/sherlock/bundle}" \
  BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT='development:test' \
  bash -s -- "$APP_DIR" <<'MIGRATE'
set -Eeuo pipefail
cd "$1"
bundle exec rails db:migrate db:seed
rm -rf node_modules
MIGRATE

systemctl start sherlock
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:3000/up >/dev/null; then
    trap - EXIT
    echo 'Update complete; health check passed.'
    echo "Database backup: $BACKUP_PATH"
    exit 0
  fi
  sleep 2
done
journalctl -u sherlock -n 100 --no-pager
exit 1
