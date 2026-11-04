#!/usr/bin/env bash
set -Eeuo pipefail

# Native Debian installer. Run as root:
# ./install.sh <stats.example.com> <application-source-git-url> [branch]
# On Debian 11, confirm its EOL state with ALLOW_EOL_DEBIAN11=1.

APP_USER=sherlock
APP_GROUP=sherlock
APP_DIR=/opt/sherlock
ETC_DIR=/etc/sherlock
DB_NAME=sherlockdb_prod
DB_USER=sherlockdb_prod_write
PG_VERSION=18
RUBY_PREFIX_BASE=/opt/rubies
NODE_PREFIX=/opt/node
NODE_DIST_BASE=https://nodejs.org/dist
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

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
[[ "${ID:-}" == debian ]] || die "This installer supports Debian 11/12/13; detected ${ID:-unknown}."
DEBIAN_MAJOR=${VERSION_ID%%.*}
case "$DEBIAN_MAJOR" in
  11) DEBIAN_CODENAME=bullseye ;;
  12) DEBIAN_CODENAME=bookworm ;;
  13) DEBIAN_CODENAME=trixie ;;
  *) die "Unsupported Debian release: ${VERSION_ID:-unknown}. Supported: 11, 12, 13." ;;
esac

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) NODE_ARCH=x64 ;;
  arm64) NODE_ARCH=arm64 ;;
  *) die "Unsupported architecture: $ARCH. Supported: amd64 and arm64." ;;
esac
GLIBC_VERSION=$(getconf GNU_LIBC_VERSION | awk '{print $2}')
dpkg --compare-versions "$GLIBC_VERSION" ge 2.28 || die "glibc $GLIBC_VERSION is too old; Node.js 26.12.0 requires glibc >= 2.28."

# Fail before installing or compiling the stack if the public hostname is not ready.
getent ahosts "$DOMAIN" >/dev/null || die "DNS for $DOMAIN does not resolve yet. Create its A/AAAA record pointing to this VPS and rerun."
FREE_KB=$(df -Pk /opt | awk 'NR == 2 {print $4}')
RAM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
if [[ "$FREE_KB" =~ ^[0-9]+$ ]] && (( FREE_KB < 20 * 1024 * 1024 )); then
  echo "WARNING: less than 20 GiB free on /opt; Ruby/native gem compilation and assets may run out of disk." >&2
fi
if [[ "$RAM_KB" =~ ^[0-9]+$ ]] && (( RAM_KB < 3 * 1024 * 1024 )); then
  echo "WARNING: less than 3 GiB RAM; Ruby compilation may be OOM-killed. 4 GiB or more is recommended." >&2
fi

if [[ "$DEBIAN_MAJOR" == 11 ]]; then
  cat >&2 <<'WARNING'
WARNING: Debian 11 (Bullseye) reached Debian LTS end-of-life on 2026-08-31.
It no longer receives security updates from the Debian LTS team. PostgreSQL 18
packages for Bullseye are available only from the frozen PGDG archive and will
not receive further PGDG updates. Debian 12 or 13 is strongly recommended for
an internet-facing production server.
WARNING
  if [[ "${ALLOW_EOL_DEBIAN11:-0}" != 1 ]]; then
    read -r -p 'Type YES to continue on end-of-life Debian 11: ' EOL_CONFIRM
    [[ "$EOL_CONFIRM" == YES ]] || die 'Aborted. Upgrade to Debian 12/13 or set ALLOW_EOL_DEBIAN11=1 after accepting the risk.'
  fi
fi

[[ ! -e "$APP_DIR" ]] || die "$APP_DIR already exists; refusing to overwrite an existing installation."
[[ ! -e "$ETC_DIR/sherlock.env" ]] || die "$ETC_DIR/sherlock.env already exists; refusing to overwrite an existing configuration."
[[ ! -e /etc/systemd/system/sherlock.service ]] || die "sherlock.service already exists; inspect the existing service before installing."
[[ -f "$SCRIPT_DIR/scripts/patch-native-app.sh" ]] || die "Missing deployment patcher: $SCRIPT_DIR/scripts/patch-native-app.sh"
if [[ "$DEBIAN_MAJOR" == 11 ]]; then
  [[ -f "$SCRIPT_DIR/scripts/prepare-bullseye-archive.sh" ]] || die "Missing Bullseye archive helper."
  bash "$SCRIPT_DIR/scripts/prepare-bullseye-archive.sh"
fi
read -r -p "Let's Encrypt email: " LE_EMAIL
[[ "$LE_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die 'A valid email address is required.'

export DEBIAN_FRONTEND=noninteractive
log "Installing system dependencies for Debian $DEBIAN_MAJOR ($DEBIAN_CODENAME)"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git build-essential autoconf bison \
  libssl-dev libyaml-dev libreadline-dev zlib1g-dev libffi-dev libgdbm-dev \
  libncurses-dev libgmp-dev libdb-dev libpq-dev pkg-config python3 make gcc g++ \
  libjemalloc2 libatomic1 postgresql-common nginx certbot python3-certbot-nginx \
  ufw openssl xz-utils iproute2

log "Configuring PostgreSQL ${PG_VERSION} package repository"
install -d -m 0755 /usr/share/postgresql-common/pgdg
curl -fsSLo /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc
if [[ "$DEBIAN_MAJOR" == 11 ]]; then
  # Bullseye's PGDG distribution was archived on 2026-08-31. It is frozen.
  printf 'deb [check-valid-until=no signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt-archive.postgresql.org/pub/repos/apt bullseye-pgdg main\n' \
    > /etc/apt/sources.list.d/pgdg.list
else
  printf 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt %s-pgdg main\n' "$DEBIAN_CODENAME" \
    > /etc/apt/sources.list.d/pgdg.list
fi
apt-get update
apt-get install -y "postgresql-${PG_VERSION}" "postgresql-client-${PG_VERSION}" libpq-dev
systemctl enable --now postgresql

PG_PORT=$(pg_lsclusters --no-header | awk -v v="$PG_VERSION" '$1 == v && $2 == "main" {print $3; exit}')
[[ "$PG_PORT" =~ ^[0-9]+$ ]] || die "PostgreSQL ${PG_VERSION} main cluster not found. Inspect: pg_lsclusters"

log 'Preparing dedicated application account and directories'
getent group "$APP_GROUP" >/dev/null || groupadd --system "$APP_GROUP"
id "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_GROUP" --home-dir /var/lib/sherlock --create-home --shell /usr/sbin/nologin "$APP_USER"
install -d -o root -g "$APP_GROUP" -m 0750 "$ETC_DIR"

STAGING_DIR=
TMP_NODE_DIR=
cleanup_install_temps() {
  if [[ -n "$TMP_NODE_DIR" && -d "$TMP_NODE_DIR" ]]; then
    rm -rf "$TMP_NODE_DIR"
  fi
  if [[ -n "$STAGING_DIR" && -d "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup_install_temps EXIT

log 'Cloning authorized application source into a temporary directory'
STAGING_DIR=$(mktemp -d /opt/.sherlock-install.XXXXXX)
git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$STAGING_DIR"
chown -R "$APP_USER:$APP_GROUP" "$STAGING_DIR"
for required in .ruby-version .node-version Gemfile.lock package-lock.json config/application.rb; do
  [[ -f "$STAGING_DIR/$required" ]] || die "Application source is missing required file: $required"
done
RUBY_VERSION=$(tr -d '\r\n' < "$STAGING_DIR/.ruby-version")
NODE_VERSION=$(tr -d '\r\n' < "$STAGING_DIR/.node-version")
[[ "$RUBY_VERSION" == 4.0.9 ]] || die "Unsupported application Ruby version: $RUBY_VERSION (installer is pinned for 4.0.9)."
[[ "$NODE_VERSION" == 26.12.0 ]] || die "Unsupported application Node.js version: $NODE_VERSION (installer is pinned for 26.12.0)."
RUBY_PREFIX="$RUBY_PREFIX_BASE/$RUBY_VERSION"
install -d -m 0755 /usr/local/libexec/sherlock
install -o root -g root -m 0755 "$SCRIPT_DIR/scripts/patch-native-app.sh" /usr/local/libexec/sherlock/patch-native-app.sh
runuser -u "$APP_USER" -- bash /usr/local/libexec/sherlock/patch-native-app.sh "$STAGING_DIR"
# Keep generated Rails production secrets out of Git status and accidental commits.
printf '\n/config/credentials/\n' >> "$STAGING_DIR/.git/info/exclude"
mv "$STAGING_DIR" "$APP_DIR"
STAGING_DIR=

log "Building Ruby ${RUBY_VERSION} against the host OpenSSL (>= 1.1.1)"
RUBY_BUILD_TAG=v20261023
RUBY_BUILD_COMMIT=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92
RUBY_BUILD_DIR="/usr/local/src/ruby-build-$RUBY_BUILD_TAG"
if [[ ! -d "$RUBY_BUILD_DIR/.git" ]]; then
  git clone --depth 1 --branch "$RUBY_BUILD_TAG" https://github.com/rbenv/ruby-build.git "$RUBY_BUILD_DIR"
fi
ACTUAL_RUBY_BUILD_COMMIT=$(git -C "$RUBY_BUILD_DIR" rev-parse HEAD)
[[ "$ACTUAL_RUBY_BUILD_COMMIT" == "$RUBY_BUILD_COMMIT" ]] || die "ruby-build $RUBY_BUILD_TAG commit mismatch: $ACTUAL_RUBY_BUILD_COMMIT"
"$RUBY_BUILD_DIR/install.sh"
if [[ ! -x "$RUBY_PREFIX/bin/ruby" ]]; then
  install -d -m 0755 "$RUBY_PREFIX_BASE"
  MAKE_OPTS=-j2 RUBY_BUILD_BUILD_PATH=/var/tmp/ruby-build ruby-build "$RUBY_VERSION" "$RUBY_PREFIX"
fi
"$RUBY_PREFIX/bin/ruby" -ropenssl -e 'abort "Ruby OpenSSL extension is not available" unless OpenSSL::OPENSSL_VERSION'
gem install bundler -v 4.0.20 --no-document

log "Installing official Node.js ${NODE_VERSION} binary for ${NODE_ARCH}"
NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
TMP_NODE_DIR=$(mktemp -d)
curl -fsSLo "$TMP_NODE_DIR/SHASUMS256.txt" "$NODE_DIST_BASE/v$NODE_VERSION/SHASUMS256.txt"
curl -fsSLo "$TMP_NODE_DIR/$NODE_TARBALL" "$NODE_DIST_BASE/v$NODE_VERSION/$NODE_TARBALL"
grep -E "^[0-9a-f]{64}  ${NODE_TARBALL}$" "$TMP_NODE_DIR/SHASUMS256.txt" > "$TMP_NODE_DIR/node.sha256" \
  || die "No official SHA-256 checksum found for $NODE_TARBALL"
(cd "$TMP_NODE_DIR" && sha256sum --check node.sha256)
install -d -m 0755 "$NODE_PREFIX"
tar -xJf "$TMP_NODE_DIR/$NODE_TARBALL" -C "$NODE_PREFIX" --strip-components=1
"$NODE_PREFIX/bin/node" --version | grep -Fx "v$NODE_VERSION" >/dev/null || die 'Installed Node.js version verification failed.'
"$NODE_PREFIX/bin/npm" --version
rm -rf "$TMP_NODE_DIR"
TMP_NODE_DIR=

export PATH="$RUBY_PREFIX/bin:$NODE_PREFIX/bin:$PATH"
log 'Installing Ruby and JavaScript application dependencies'
runuser -u "$APP_USER" -- env PATH="$PATH" RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT='development:test' bash -c \
  "cd '$APP_DIR' && bundle config set --local deployment true && bundle config set --local without 'development test' && bundle install --jobs 2 --retry 3 && npm ci && npm run build"

log 'Creating encrypted production credentials'
install -d -o "$APP_USER" -g "$APP_GROUP" -m 0700 "$APP_DIR/config/credentials"
if [[ ! -f "$APP_DIR/config/credentials/production.yml.enc" ]]; then
  runuser -u "$APP_USER" -- env PATH="$PATH" RAILS_ENV=production APP_HOST="$DOMAIN" bash -c '
    set -Eeuo pipefail
    umask 077
    cd /opt/sherlock
    CREDENTIALS_TMP=$(mktemp /tmp/sherlock-credentials.XXXXXX)
    trap '\''rm -f "$CREDENTIALS_TMP"'\'' EXIT
    {
      printf "secret_key_base: %s\\n" "$(bin/rails secret)"
      bin/rails db:encryption:init | tail -n 4
    } > "$CREDENTIALS_TMP"
    EDITOR="cp $CREDENTIALS_TMP" bin/rails credentials:edit --environment production
  '
fi
[[ -s "$APP_DIR/config/credentials/production.key" ]] || die 'Rails production credentials key missing.'
chown "$APP_USER:$APP_GROUP" "$APP_DIR/config/credentials/production.key" "$APP_DIR/config/credentials/production.yml.enc"
chmod 0600 "$APP_DIR/config/credentials/production.key" "$APP_DIR/config/credentials/production.yml.enc"

log 'Creating PostgreSQL database and role'
DB_PASSWORD=$(openssl rand -hex 32)
if runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1; then
  die "Database role $DB_USER already exists; refusing to alter it."
fi
if runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
  die "Database $DB_NAME already exists; refusing to modify it."
fi
runuser -u postgres -- psql -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER} ENCODING 'UTF8';
SQL
# Rails db:prepare loads db/structure.sql, which creates and owns the sherlockdb schema.
# Do not pre-create the schema here or structure:load will fail on a fresh database.

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
DB_POOL=10
APP_GIT_BRANCH=$BRANCH
PORT=3000
FORCE_SSL=true
SOLID_QUEUE_IN_PUMA=true
METRICS_HOST=127.0.0.1
RAILS_LOG_LEVEL=info
ENV
chown root:"$APP_GROUP" "$ETC_DIR/sherlock.env"
chmod 0640 "$ETC_DIR/sherlock.env"

log 'Preparing database and compiling production assets'
runuser -u "$APP_USER" -- env PATH="$PATH" RAILS_ENV=production APP_HOST="$DOMAIN" RAILS_MASTER_KEY="$MASTER_KEY" \
  DB_HOST=127.0.0.1 DB_PORT="$PG_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" DB_POOL=10 \
  SECRET_KEY_BASE_DUMMY=1 bash -c "cd '$APP_DIR' && bundle exec rails db:prepare db:seed && bundle exec rails assets:precompile && rm -rf node_modules"

install -d -o "$APP_USER" -g "$APP_GROUP" -m 0750 "$APP_DIR/tmp" "$APP_DIR/log" "$APP_DIR/storage"
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
systemctl daemon-reload
systemctl enable --now sherlock

log 'Waiting for Rails health check'
for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:3000/up >/dev/null; then break; fi
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
nginx -t
systemctl enable --now nginx

if ufw status 2>/dev/null | grep -q 'Status: active'; then
  ufw allow 80/tcp
  ufw allow 443/tcp
fi
certbot --nginx -d "$DOMAIN" -m "$LE_EMAIL" --agree-tos --non-interactive --redirect

log "Installation complete: https://$DOMAIN"
