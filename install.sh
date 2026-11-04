#!/usr/bin/env bash
set -Eeuo pipefail

# Native Debian installer. Run as root:
# ./install.sh <domain> <application-source-git-url> [branch]

APP_USER=sherlock
APP_GROUP=sherlock
APP_DIR=/opt/sherlock
ETC_DIR=/etc/sherlock
DB_NAME=sherlockdb_prod
DB_USER=sherlockdb_prod_write
PG_VERSION=18
RUBY_VERSION=4.0.9
BUNDLER_VERSION=4.0.20
NODE_VERSION=26.12.0
RUBY_PREFIX="/opt/rubies/${RUBY_VERSION}"
NODE_PREFIX=/opt/node

log() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die 'Run as root.'
[[ $# -ge 2 ]] || die "Usage: $0 <stats.example.com> <application-source-git-url> [branch]"
DOMAIN=${1,,}
REPO_URL=$2
BRANCH=${3:-main}
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || die "Invalid domain: $DOMAIN"
[[ "$REPO_URL" =~ ^(https://|ssh://|git@) ]] || die 'Repository URL must use HTTPS, SSH, or git@ syntax.'

. /etc/os-release
[[ "${ID:-}" == debian ]] || die "This installer supports Debian 12/13; detected ${ID:-unknown}."
[[ "${VERSION_ID%%.*}" == 12 || "${VERSION_ID%%.*}" == 13 ]] || die "Unsupported Debian version: ${VERSION_ID:-unknown}."
[[ ! -e "$APP_DIR" ]] || die "$APP_DIR already exists; refusing to overwrite an existing installation."

read -r -p "Let's Encrypt email: " LE_EMAIL
[[ "$LE_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die 'A valid email address is required.'

export DEBIAN_FRONTEND=noninteractive
log 'Installing build dependencies, Nginx, Certbot, and PostgreSQL prerequisites'
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl git gnupg build-essential autoconf bison \
  libssl-dev libyaml-dev libreadline-dev zlib1g-dev libffi-dev libgdbm-dev libncurses-dev \
  libpq-dev pkg-config python3 make gcc g++ libjemalloc2 postgresql-common nginx certbot \
  python3-certbot-nginx ufw openssl xz-utils

install -d -m 0755 /usr/share/postgresql-common/pgdg
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
printf 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}"
systemctl enable --now "postgresql@${PG_VERSION}-main"
PG_PORT=$(pg_lsclusters --no-header | awk -v v="$PG_VERSION" '$1 == v && $2 == "main" {print $3; exit}')
[[ "$PG_PORT" =~ ^[0-9]+$ ]] || die "PostgreSQL ${PG_VERSION} cluster not found."

log "Building Ruby ${RUBY_VERSION} and Node.js ${NODE_VERSION}"
if [[ ! -x /usr/local/bin/ruby-build ]]; then
  git clone --depth 1 https://github.com/rbenv/ruby-build.git /usr/local/src/ruby-build
  /usr/local/src/ruby-build/install.sh
fi
if [[ ! -x /usr/local/src/node-build/bin/node-build ]]; then
  git clone --depth 1 https://github.com/nodenv/node-build.git /usr/local/src/node-build
fi
if [[ ! -x "$RUBY_PREFIX/bin/ruby" ]]; then
  RUBY_BUILD_BUILD_PATH=/var/tmp/ruby-build ruby-build "$RUBY_VERSION" "$RUBY_PREFIX"
fi
if [[ ! -x "$NODE_PREFIX/bin/node" ]]; then
  NODE_BUILD_BUILD_PATH=/var/tmp/node-build /usr/local/src/node-build/bin/node-build "$NODE_VERSION" "$NODE_PREFIX"
fi
gem install bundler -v "$BUNDLER_VERSION" --no-document
export PATH="$RUBY_PREFIX/bin:$NODE_PREFIX/bin:$PATH"

log 'Preparing dedicated service account and directories'
getent group "$APP_GROUP" >/dev/null || groupadd --system "$APP_GROUP"
id "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_GROUP" --home-dir "$APP_DIR" --create-home --shell /usr/sbin/nologin "$APP_USER"
install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "$APP_DIR"
install -d -o root -g "$APP_GROUP" -m 0750 "$ETC_DIR"

log 'Cloning authorized application source'
git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$APP_DIR"
chown -R "$APP_USER:$APP_GROUP" "$APP_DIR"
for required in .ruby-version .node-version Gemfile.lock config/application.rb; do
  [[ -f "$APP_DIR/$required" ]] || die "Application source is missing required file: $required"
done
[[ "$(tr -d '\r\n' < "$APP_DIR/.ruby-version")" == "$RUBY_VERSION" ]] || die 'Ruby version does not match installer.'
[[ "$(tr -d '\r\n' < "$APP_DIR/.node-version")" == "$NODE_VERSION" ]] || die 'Node.js version does not match installer.'

log 'Installing application dependencies'
runuser -u "$APP_USER" -- env PATH="$RUBY_PREFIX/bin:$NODE_PREFIX/bin:$PATH" RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT='development:test' bash -c "cd '$APP_DIR' && bundle config set --local deployment true && bundle config set --local without 'development test' && bundle install --jobs 2 --retry 3 && npm ci && npm run build"

log 'Creating encrypted production credentials'
install -d -o "$APP_USER" -g "$APP_GROUP" -m 0700 "$APP_DIR/config/credentials"
if [[ ! -f "$APP_DIR/config/credentials/production.yml.enc" ]]; then
  runuser -u "$APP_USER" -- env PATH="$RUBY_PREFIX/bin:$NODE_PREFIX/bin:$PATH" RAILS_ENV=production APP_HOST="$DOMAIN" bash -c "cd '$APP_DIR' && printf 'secret_key_base: %s\n' \"\$(bin/rails secret)\" > /tmp/sherlock-credentials.yml && bin/rails db:encryption:init >> /tmp/sherlock-credentials.yml && EDITOR='cp /tmp/sherlock-credentials.yml' bin/rails credentials:edit --environment production && rm -f /tmp/sherlock-credentials.yml"
fi
[[ -s "$APP_DIR/config/credentials/production.key" ]] || die 'Rails production credentials key missing.'
chown "$APP_USER:$APP_GROUP" "$APP_DIR/config/credentials/production.key" "$APP_DIR/config/credentials/production.yml.enc"
chmod 0600 "$APP_DIR/config/credentials/production.key" "$APP_DIR/config/credentials/production.yml.enc"

log 'Creating PostgreSQL database and role'
DB_PASSWORD=$(openssl rand -hex 32)
if runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then die "Database role $DB_USER already exists."; fi
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -v db_password="$DB_PASSWORD" <<SQL
CREATE ROLE ${DB_USER} LOGIN PASSWORD :'db_password';
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER} ENCODING 'UTF8';
SQL

MASTER_KEY=$(tr -d '\r\n' < "$APP_DIR/config/credentials/production.key")
cat > "$ETC_DIR/sherlock.env" <<ENV
RAILS_ENV=production
APP_HOST=$DOMAIN
RAILS_MASTER_KEY=$MASTER_KEY
DB_HOST=127.0.0.1
DB_PORT=$PG_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
RAILS_MAX_THREADS=3
PORT=3000
FORCE_SSL=true
SOLID_QUEUE_IN_PUMA=true
RAILS_LOG_LEVEL=info
ENV
chown root:"$APP_GROUP" "$ETC_DIR/sherlock.env"
chmod 0640 "$ETC_DIR/sherlock.env"

log 'Preparing database and assets'
runuser -u "$APP_USER" -- env PATH="$RUBY_PREFIX/bin:$NODE_PREFIX/bin:$PATH" RAILS_ENV=production APP_HOST="$DOMAIN" RAILS_MASTER_KEY="$MASTER_KEY" DB_HOST=127.0.0.1 DB_PORT="$PG_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" SECRET_KEY_BASE_DUMMY=1 bash -c "cd '$APP_DIR' && bundle exec rails db:prepare db:seed && bundle exec rails assets:precompile"

cat > /etc/systemd/system/sherlock.service <<UNIT
[Unit]
Description=Sherlock private tracker statistics application
Wants=network-online.target
After=network-online.target postgresql.service
[Service]
Type=simple
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$APP_DIR
EnvironmentFile=$ETC_DIR/sherlock.env
Environment=PATH=$RUBY_PREFIX/bin:$NODE_PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
Environment=WEB_CONCURRENCY=1
ExecStart=/usr/bin/env bundle exec puma -C config/puma.rb
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$APP_DIR/tmp $APP_DIR/log $APP_DIR/storage
[Install]
WantedBy=multi-user.target
UNIT
install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "$APP_DIR/tmp" "$APP_DIR/log" "$APP_DIR/storage"
systemctl daemon-reload
systemctl enable --now sherlock

log 'Waiting for Rails health check'
for i in $(seq 1 60); do
  curl -fsS http://127.0.0.1:3000/up >/dev/null && break
  [[ "$i" -lt 60 ]] || { journalctl -u sherlock -n 80 --no-pager; die 'Rails health check failed.'; }
  sleep 2
done

cat > /etc/nginx/sites-available/sherlock <<NGINX
server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN;
  client_max_body_size 20m;
  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 120s;
  }
}
NGINX
ln -sfn /etc/nginx/sites-available/sherlock /etc/nginx/sites-enabled/sherlock
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx

if ! getent ahosts "$DOMAIN" >/dev/null; then die "DNS does not resolve for $DOMAIN. Set the DNS A record, then run certbot --nginx -d $DOMAIN -m $LE_EMAIL --agree-tos --redirect"; fi
certbot --nginx -d "$DOMAIN" -m "$LE_EMAIL" --agree-tos --non-interactive --redirect
if ufw status 2>/dev/null | grep -q 'Status: active'; then ufw allow 80/tcp; ufw allow 443/tcp; fi

log "Installation complete: https://$DOMAIN"
