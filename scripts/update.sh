#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR=/opt/sherlock
APP_USER=sherlock
RUBY_BIN=/opt/rubies/4.0.9/bin
NODE_BIN=/opt/node/bin
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PATCHER="$SCRIPT_DIR/scripts/patch-native-app.sh"
MIGRATION_STARTED=0
PREVIOUS_COMMIT=
BACKUP_PATH=

[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
if [[ -f "$APP_DIR/.sherlock-native-install" ]]; then
  echo "This is a bundled native installation. Update from the full Sherlock source checkout and rerun sherlock-v2/deploy/install.sh; scripts/update.sh is for the legacy Git-checkout deployment only." >&2
  exit 1
fi
[[ -d "$APP_DIR/.git" ]] || { echo "$APP_DIR is not a Git checkout." >&2; exit 1; }
[[ -f "$PATCHER" && ! -L "$PATCHER" ]] || { echo "Current deployment patcher missing or unsafe: $PATCHER" >&2; exit 1; }
[[ -f "$SCRIPT_DIR/backup.sh" ]] || { echo 'backup.sh is missing; refusing to update without a backup.' >&2; exit 1; }

set -a
. /etc/sherlock/sherlock.env
set +a
APP_GIT_BRANCH=${APP_GIT_BRANCH:-main}
[[ "$APP_GIT_BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$APP_GIT_BRANCH" != *..* ]] \
  || { echo "Unsafe APP_GIT_BRANCH in /etc/sherlock/sherlock.env." >&2; exit 1; }
PREVIOUS_COMMIT=$(runuser -u "$APP_USER" -- git -C "$APP_DIR" rev-parse HEAD)

restore_service() {
  local status=$?
  if (( status != 0 )); then
    echo "Update failed (exit $status)." >&2
    if (( MIGRATION_STARTED == 0 )); then
      echo "Restoring application source commit $PREVIOUS_COMMIT." >&2
      runuser -u "$APP_USER" -- git -C "$APP_DIR" reset --hard "$PREVIOUS_COMMIT" || true
      runuser -u "$APP_USER" -- bash "$PATCHER" "$APP_DIR" || true
      systemctl start sherlock || true
    else
      systemctl stop sherlock || true
      echo "Database migration had started. Sherlock has been stopped to avoid running mismatched code against a partially migrated database." >&2
      echo "Inspect the migration logs, verify the database, and restore the matching backup before starting the service." >&2
    fi
    echo "Backup location: ${BACKUP_PATH:-check /var/backups/sherlock}" >&2
  fi
}
systemctl stop sherlock
trap restore_service EXIT

BACKUP_OUTPUT=$(bash "$SCRIPT_DIR/backup.sh")
printf '%s\n' "$BACKUP_OUTPUT"
BACKUP_PATH=$(printf '%s\n' "$BACKUP_OUTPUT" | sed -n 's/^Database backup: //p' | tail -n 1)

runuser -u "$APP_USER" -- env \
  PATH="$RUBY_BIN:$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
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
  PATH="$RUBY_BIN:$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
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
for _ in $(seq 1 60); do
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
