#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR=/opt/sherlock
APP_USER=sherlock
RUBY_BIN=/opt/rubies/4.0.9/bin
NODE_BIN=/opt/node/bin

[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
[[ -d "$APP_DIR/.git" ]] || { echo "$APP_DIR is not a Git checkout." >&2; exit 1; }
set -a
. /etc/sherlock/sherlock.env
set +a

systemctl stop sherlock
runuser -u "$APP_USER" -- env PATH="$RUBY_BIN:$NODE_BIN:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin" RAILS_ENV=production APP_HOST="$APP_HOST" RAILS_MASTER_KEY="$RAILS_MASTER_KEY" DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" RAILS_MAX_THREADS="${RAILS_MAX_THREADS:-3}" BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT='development:test' bash -c "cd '$APP_DIR' && git pull --ff-only && bundle install --jobs 2 --retry 3 && npm ci && npm run build && SECRET_KEY_BASE_DUMMY=1 APP_HOST=build.invalid bundle exec rails assets:precompile && bundle exec rails db:migrate db:seed && rm -rf node_modules"
systemctl start sherlock
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:3000/up >/dev/null; then echo 'Update complete; health check passed.'; exit 0; fi
  sleep 2
done
journalctl -u sherlock -n 100 --no-pager
exit 1
