#!/usr/bin/env bash
# Sherlock: native Debian installer (no Docker).  Debian 12 and 13 are the target; 11 and
# Ubuntu 22.04+ are best effort.
#
#   sudo bash deploy/install-debian.sh --domain sherlock.example.com --letsencrypt you@example.com
#   sudo bash deploy/install-debian.sh --domain 192.168.1.10 --no-ssl      # private network, plain HTTP
#
# Safe to run again: re-running updates the app from the current checkout and keeps the database,
# the credentials and your settings.
#
# What it sets up
#   * apt packages, PostgreSQL (18 from the PGDG repository, else what Debian ships)
#   * Ruby (the version in .ruby-version) compiled with ruby-build under /opt/rubies
#   * the app in /opt/sherlock, run by the system user "sherlock" (systemd unit "sherlock")
#   * /etc/sherlock/sherlock.env (settings) and /etc/sherlock/credentials (BACK THIS UP)
#   * optionally nginx as reverse proxy, with a Let's Encrypt certificate

set -Eeuo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_USER=sherlock
APP_HOME=/var/lib/sherlock
INSTALL_DIR=/opt/sherlock
CONF_DIR=/etc/sherlock
ENV_FILE=$CONF_DIR/sherlock.env
CRED_DIR=$CONF_DIR/credentials
RUBIES_DIR=/opt/rubies
SERVICE=sherlock
# ruby-build release pinned by commit, so a moved tag can't change what gets built.
RUBY_BUILD_TAG=v20261023
RUBY_BUILD_COMMIT=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92

OPT_DOMAIN="" OPT_SSL="" OPT_PROXY="" OPT_EMAIL="" OPT_PORT="" OPT_DB_PASSWORD=""
ASSUME_YES=0

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
trap 'printf "\033[31mInstall stopped at line %s. Fix the problem and run the script again; it is safe to repeat.\033[0m\n" "$LINENO" >&2' ERR

usage() {
  cat <<'EOF'
Usage: sudo bash deploy/install-debian.sh --domain HOST [options]

  --domain HOST        Host name (or IP) Sherlock is reached at. Required on the first run.
  --no-ssl             Plain HTTP (FORCE_SSL=false). Only for a private network.
  --proxy nginx|none   nginx (default): install nginx in front, Sherlock listens on 127.0.0.1 only.
                       none: Sherlock listens on 0.0.0.0:PORT, bring your own proxy.
  --letsencrypt EMAIL  With nginx: get a free HTTPS certificate (domain must point here, port 80 open).
  --port N             Port of the Rails server (default 3000).
  --db-password PW     Database password (default: random, kept in /etc/sherlock/sherlock.env).
  -y, --yes            No questions.
  -h, --help           This text.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)      OPT_DOMAIN="${2:?--domain needs a value}"; shift 2 ;;
    --no-ssl)      OPT_SSL=false; shift ;;
    --proxy)       OPT_PROXY="${2:?--proxy needs nginx or none}"; shift 2 ;;
    --letsencrypt) OPT_EMAIL="${2:?--letsencrypt needs an email}"; shift 2 ;;
    --port)        OPT_PORT="${2:?--port needs a value}"; shift 2 ;;
    --db-password) OPT_DB_PASSWORD="${2:?--db-password needs a value}"; shift 2 ;;
    -y|--yes)      ASSUME_YES=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage >&2; die "Unknown option: $1" ;;
  esac
done

# Value of KEY from an existing env file (so a re-run keeps earlier choices).
env_get() { [[ -f $ENV_FILE ]] && sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 || true; }

# Run a command as the app user, in the app folder, with the service's settings loaded.
# Usage: app_run [-b] CMD ARGS...   (-b: also put Node on the PATH, for the build)
NODE_BIN=""
app_run() {
  local path="$RUBY_DIR/bin:/usr/local/bin:/usr/bin:/bin"
  if [[ ${1:-} == -b ]]; then path="$NODE_BIN:$path"; shift; fi
  runuser -u "$APP_USER" -- env -C "$INSTALL_DIR" HOME="$APP_HOME" LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$path" \
    bash -c 'set -a; . "$0"; set +a; exec "$@"' "$ENV_FILE" "$@"
}

# ------------------------------------------------------------------------------------------------
preflight() {
  say "Checking the system"
  [[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0 ..."
  [[ -f $SRC_DIR/Gemfile && -f $SRC_DIR/config/application.rb ]] || die "Run this from the Sherlock checkout (can't find the app next to $0)."
  command -v apt-get >/dev/null || die "This installer needs apt (Debian or Ubuntu)."
  [[ -d /run/systemd/system ]] || die "systemd isn't running here (container?). This installer needs systemd."
  # shellcheck disable=SC1091
  . /etc/os-release
  CODENAME="${VERSION_CODENAME:-}"
  case "${ID:-}:${VERSION_ID:-}" in
    debian:12|debian:13) info "Debian $VERSION_ID ($CODENAME)" ;;
    debian:11)           warn "Debian 11 is end-of-life. It may work, but move to Debian 12 or 13." ;;
    ubuntu:2[246].*)     warn "Ubuntu isn't the main target, but should work." ;;
    *) die "Unsupported system: ${PRETTY_NAME:-unknown}. Use Debian 12 or 13." ;;
  esac
  case "$(uname -m)" in
    x86_64) NODE_ARCH=x64 ;;
    aarch64) NODE_ARCH=arm64 ;;
    *) die "Unsupported CPU $(uname -m) (x86_64 and aarch64 only)." ;;
  esac
  local kb; kb=$(awk '/^(MemTotal|SwapTotal):/ {s+=$2} END {print s}' /proc/meminfo)
  (( kb > 1500000 )) || warn "Under 1.5 GB of RAM plus swap: compiling Ruby may run out of memory. Add swap if it does."
}

settings() {
  say "Settings"
  RUBY_VERSION="$(tr -d '[:space:]' < "$SRC_DIR/.ruby-version")"
  NODE_VERSION="$(tr -d '[:space:]' < "$SRC_DIR/.node-version")"
  # Node 26 needs a newer glibc than Debian 11 has; 24 is plenty for esbuild.
  [[ $CODENAME == bullseye ]] && NODE_VERSION=24.22.2

  APP_HOST="${OPT_DOMAIN:-$(env_get APP_HOST)}"
  if [[ -z $APP_HOST && -t 0 && $ASSUME_YES -eq 0 ]]; then read -r -p "Host name Sherlock is served on: " APP_HOST; fi
  [[ -n $APP_HOST ]] || die "Give the host name with --domain."
  APP_HOST="${APP_HOST,,}"
  [[ $APP_HOST =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?$ ]] || die "Invalid host name: $APP_HOST"

  FORCE_SSL="${OPT_SSL:-$(env_get FORCE_SSL)}"; FORCE_SSL="${FORCE_SSL:-true}"
  PORT="${OPT_PORT:-$(env_get PORT)}"; PORT="${PORT:-3000}"
  [[ $PORT =~ ^[0-9]+$ ]] || die "--port must be a number."
  local was; was="$(env_get BIND_ADDRESS)"
  PROXY="${OPT_PROXY:-$([[ $was == 0.0.0.0 ]] && echo none || echo nginx)}"
  [[ $PROXY == nginx || $PROXY == none ]] || die "--proxy must be nginx or none."
  BIND_ADDRESS=$([[ $PROXY == nginx ]] && echo 127.0.0.1 || echo 0.0.0.0)
  if [[ $PROXY == nginx && $FORCE_SSL == true && -z $OPT_EMAIL ]] && ! grep -qs "managed by Certbot" /etc/nginx/sites-available/$SERVICE; then
    die "HTTPS needs a certificate: add --letsencrypt you@example.com, or use --no-ssl on a private network, or --proxy none with your own HTTPS proxy."
  fi

  DB_NAME=sherlockdb_prod DB_USER=sherlockdb_prod_write DB_HOST=127.0.0.1
  DB_PASSWORD="${OPT_DB_PASSWORD:-$(env_get DB_PASSWORD)}"; DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 24)}"
  [[ $DB_PASSWORD =~ ^[A-Za-z0-9._~-]+$ ]] || die "The database password may only use letters, digits and . _ ~ -"
  APP_VERSION="$(git -C "$SRC_DIR" describe --tags --abbrev=0 2>/dev/null || true)"; APP_VERSION="${APP_VERSION:-$(env_get APP_VERSION)}"; APP_VERSION="${APP_VERSION:-unknown}"

  info "Host $APP_HOST (FORCE_SSL=$FORCE_SSL), Rails on $BIND_ADDRESS:$PORT, proxy: $PROXY"
  info "Ruby $RUBY_VERSION, Node $NODE_VERSION (build only)"
  if [[ -t 0 && $ASSUME_YES -eq 0 ]]; then
    local a; read -r -p "Continue? [Y/n] " a || true
    [[ -z $a || $a =~ ^[Yy] ]] || die "Stopped."
  fi
}

# ------------------------------------------------------------------------------------------------
packages() {
  say "Installing system packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git openssl rsync xz-utils tar patch file sudo tzdata \
    build-essential autoconf bison pkg-config \
    libssl-dev zlib1g-dev libyaml-dev libffi-dev libreadline-dev libncurses-dev libgmp-dev libgdbm-dev libdb-dev uuid-dev \
    libpq-dev libjemalloc2 libatomic1 postgresql-common
}

postgres() {
  say "PostgreSQL"
  # Sherlock is developed on PostgreSQL 18. Use the PGDG repository when it has it.
  if ! apt-cache policy postgresql-18 | grep -q 'Candidate: [0-9]'; then
    /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y >/dev/null 2>&1 || warn "Couldn't add the PGDG repository."
  fi
  if apt-cache policy postgresql-18 | grep -q 'Candidate: [0-9]'; then
    apt-get install -y --no-install-recommends postgresql-18
  else
    warn "PostgreSQL 18 isn't available; using the PostgreSQL that comes with $CODENAME."
    apt-get install -y --no-install-recommends postgresql
  fi
  systemctl enable --now postgresql >/dev/null 2>&1 || true
  # Use the newest cluster that is (or can be) running.
  local line; line="$(pg_lsclusters -h | sort -k1,1n | tail -n 1)"
  [[ -n $line ]] || die "PostgreSQL has no cluster. Check pg_lsclusters."
  read -r PG_MAJOR PG_CLUSTER DB_PORT _ <<<"$line"
  pg_ctlcluster "$PG_MAJOR" "$PG_CLUSTER" start 2>/dev/null || true
  for _ in $(seq 1 30); do pg_isready -q -h 127.0.0.1 -p "$DB_PORT" && break; sleep 1; done
  pg_isready -q -h 127.0.0.1 -p "$DB_PORT" || die "PostgreSQL $PG_MAJOR/$PG_CLUSTER doesn't answer on port $DB_PORT."
  info "Using PostgreSQL $PG_MAJOR/$PG_CLUSTER on port $DB_PORT"

  # The password goes in through stdin, so it never shows up in `ps`.
  local enc opts=""
  enc="$(cd / && runuser -u postgres -- psql -X -Atq -p "$DB_PORT" -d template1 -c "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname='template1'")"
  [[ $enc == UTF8 ]] || opts="TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8'"
  ( cd / && runuser -u postgres -- psql -X -q -p "$DB_PORT" -d postgres -v ON_ERROR_STOP=1 -v opts="$opts" ) <<SQL
\set u '$DB_USER'
\set pw '$DB_PASSWORD'
\set db '$DB_NAME'
SELECT format('CREATE ROLE %I LOGIN', :'u') WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'u') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'u', :'pw') \gexec
SELECT format('CREATE DATABASE %I OWNER %I %s', :'db', :'u', :'opts') WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db') \gexec
SQL
  info "Database $DB_NAME, user $DB_USER"
}

# ------------------------------------------------------------------------------------------------
build_ruby() {
  say "Ruby $RUBY_VERSION"
  RUBY_DIR="$RUBIES_DIR/$RUBY_VERSION"
  if [[ -x $RUBY_DIR/bin/ruby ]]; then info "Already built in $RUBY_DIR"; return; fi
  local rb=/opt/ruby-build
  if [[ -d $rb/.git ]]; then
    git -C "$rb" fetch -q --depth 1 origin "refs/tags/$RUBY_BUILD_TAG:refs/tags/$RUBY_BUILD_TAG"
    git -C "$rb" checkout -q --detach "$RUBY_BUILD_TAG"
  else
    git clone -q --depth 1 --branch "$RUBY_BUILD_TAG" https://github.com/rbenv/ruby-build.git "$rb"
  fi
  [[ "$(git -C "$rb" rev-parse HEAD)" == "$RUBY_BUILD_COMMIT" ]] || die "ruby-build $RUBY_BUILD_TAG isn't the expected commit; refusing to build with it."
  "$rb/bin/ruby-build" --definitions | grep -qx "$RUBY_VERSION" || die "ruby-build doesn't know Ruby $RUBY_VERSION."
  info "Compiling Ruby (5 to 15 minutes). Log: /var/log/sherlock-ruby-build.log"
  install -d "$RUBIES_DIR"
  RUBY_CONFIGURE_OPTS=--disable-install-doc "$rb/bin/ruby-build" "$RUBY_VERSION" "$RUBY_DIR" >/var/log/sherlock-ruby-build.log 2>&1 \
    || { tail -n 30 /var/log/sherlock-ruby-build.log >&2; die "Building Ruby failed."; }
}

NODE_TMP=""
node_for_build() {
  NODE_TMP="$(mktemp -d /var/tmp/sherlock-node.XXXXXX)"; chmod 755 "$NODE_TMP"
  trap '[[ -z $NODE_TMP ]] || rm -rf "$NODE_TMP"' EXIT
  local name="node-v$NODE_VERSION-linux-$NODE_ARCH" base="https://nodejs.org/dist/v$NODE_VERSION"
  info "Downloading Node.js $NODE_VERSION (only used for the build)"
  curl -fsSL "$base/$name.tar.xz" -o "$NODE_TMP/$name.tar.xz" || die "Couldn't download $base/$name.tar.xz"
  curl -fsSL "$base/SHASUMS256.txt" -o "$NODE_TMP/SHASUMS256.txt"
  ( cd "$NODE_TMP" && grep " $name.tar.xz\$" SHASUMS256.txt | sha256sum -c --quiet - ) || die "Node.js download doesn't match its checksum."
  tar -xJf "$NODE_TMP/$name.tar.xz" -C "$NODE_TMP"
  chmod -R a+rX "$NODE_TMP"
  NODE_BIN="$NODE_TMP/$name/bin"
}

# ------------------------------------------------------------------------------------------------
user_and_files() {
  say "User, folders and settings"
  getent group "$APP_USER" >/dev/null || groupadd --system "$APP_USER"
  id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_USER" --home-dir "$APP_HOME" --create-home --shell /usr/sbin/nologin "$APP_USER"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$APP_HOME"
  install -d -m 0755 "$CONF_DIR"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$CRED_DIR"

  local tmp; tmp="$(mktemp)"
  {
    echo "# Written by deploy/install-debian.sh. Edit, then: sudo systemctl restart $SERVICE"
    echo "RAILS_ENV=production"
    echo "APP_HOST=$APP_HOST"
    echo "FORCE_SSL=$FORCE_SSL"
    echo "PORT=$PORT"
    echo "BIND_ADDRESS=$BIND_ADDRESS"
    echo "DB_HOST=$DB_HOST"
    echo "DB_PORT=$DB_PORT"
    echo "DB_NAME=$DB_NAME"
    echo "DB_USER=$DB_USER"
    echo "DB_PASSWORD=$DB_PASSWORD"
    echo "APP_VERSION=$APP_VERSION"
    echo "SOLID_QUEUE_IN_PUMA=true"
    echo "METRICS_BIND=127.0.0.1"
    echo "# --- your own settings (RAILS_LOG_LEVEL, JOB_CONCURRENCY, METRICS_PORT, ...) are kept below ---"
    [[ -f $ENV_FILE ]] && grep -vE '^(# Written by|# Edit|# --- your own|$|(RAILS_ENV|APP_HOST|FORCE_SSL|PORT|BIND_ADDRESS|DB_HOST|DB_PORT|DB_NAME|DB_USER|DB_PASSWORD|APP_VERSION|SOLID_QUEUE_IN_PUMA|METRICS_BIND)=)' "$ENV_FILE" || true
  } > "$tmp"
  install -o root -g "$APP_USER" -m 0640 "$tmp" "$ENV_FILE"; rm -f "$tmp"
}

sync_app() {
  say "Copying the app to $INSTALL_DIR"
  install -d "$INSTALL_DIR"
  if [[ "$(realpath -m "$SRC_DIR")" != "$(realpath -m "$INSTALL_DIR")" ]]; then
    rsync -a --delete \
      --exclude /.git --exclude /.bundle --exclude /node_modules --exclude /vendor/bundle \
      --exclude /tmp --exclude /log --exclude /config/credentials \
      --exclude /public/assets --exclude /app/assets/builds \
      "$SRC_DIR/" "$INSTALL_DIR/"
  fi
  find "$INSTALL_DIR/bin" -maxdepth 1 -type f -exec chmod 0755 {} +
  install -d "$INSTALL_DIR"/{tmp/pids,tmp/cache,log,app/assets/builds,.bundle}
  ln -sfn "$CRED_DIR" "$INSTALL_DIR/config/credentials"     # keys live outside the app folder
  printf -- '---\nBUNDLE_DEPLOYMENT: "true"\nBUNDLE_PATH: "vendor/bundle"\nBUNDLE_WITHOUT: "development:test"\n' > "$INSTALL_DIR/.bundle/config"
  chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
}

build_app() {
  say "Installing gems and building assets"
  node_for_build
  local bv; bv="$(awk '/^BUNDLED WITH/ {getline; gsub(/ /, ""); print; exit}' "$INSTALL_DIR/Gemfile.lock")"
  [[ -z $bv ]] || "$RUBY_DIR/bin/gem" install bundler -v "$bv" --no-document >/dev/null
  app_run -b bundle install --jobs "$(nproc)" || die "bundle install failed (usually a missing system library; read the error above)."
  app_run -b npm ci --no-audit --no-fund --loglevel=error
  app_run -b env SECRET_KEY_BASE_DUMMY=1 APP_HOST=build.invalid ./bin/rails assets:precompile
  app_run -b bundle exec bootsnap precompile --gemfile app/ lib/ >/dev/null 2>&1 || warn "bootsnap precompile skipped."
  rm -rf "$INSTALL_DIR/node_modules" "$NODE_TMP"; NODE_TMP=""
}

credentials() {
  say "Credentials"
  if [[ -f $CRED_DIR/production.yml.enc && -f $CRED_DIR/production.key ]]; then info "Kept the existing ones in $CRED_DIR"; return; fi
  [[ ! -f $CRED_DIR/production.yml.enc ]] || die "$CRED_DIR/production.yml.enc exists but production.key is missing. Restore the key from your backup."
  local tmp; tmp="$(mktemp -p "$CRED_DIR" .new.XXXXXX)"; chown "$APP_USER:$APP_USER" "$tmp"; chmod 600 "$tmp"
  { echo "secret_key_base: $(app_run ./bin/rails secret)"; app_run ./bin/rails db:encryption:init | tail -n 4; } > "$tmp"
  app_run env APP_HOST=setup EDITOR="cp $tmp" ./bin/rails credentials:edit --environment production >/dev/null
  rm -f "$tmp"
  [[ -f $CRED_DIR/production.key && -f $CRED_DIR/production.yml.enc ]] || die "Creating the credentials failed."
  chmod 600 "$CRED_DIR"/production.key "$CRED_DIR"/production.yml.enc
  warn "Back up $CRED_DIR/production.key now: without it saved API keys can't be decrypted."
}

database() {
  say "Preparing the database"
  export PGPASSWORD="$DB_PASSWORD"
  psql -X -q -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "SELECT 1" >/dev/null \
    || die "Can't log in to $DB_NAME as $DB_USER on port $DB_PORT."
  # db/structure.sql comes from PostgreSQL 18 and starts with "SET transaction_timeout", which PostgreSQL 16
  # and older reject. On such servers load it once without that line; db:prepare then just migrates.
  if (( PG_MAJOR < 17 )) && [[ "$(psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "SELECT to_regclass('sherlockdb.schema_migrations') IS NOT NULL")" != t ]]; then
    info "PostgreSQL $PG_MAJOR: loading the schema without the PostgreSQL 17+ setting"
    sed '/^SET transaction_timeout = 0;$/d' "$SRC_DIR/db/structure.sql" \
      | psql -X -q -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f - >/dev/null
  fi
  unset PGPASSWORD
  app_run ./bin/rails db:prepare db:seed
}

install_service() {
  say "systemd service"
  local preload=""
  [[ -e /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 ]] && preload="Environment=LD_PRELOAD=/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2"
  cat > /etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=Sherlock (private tracker stats)
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
Environment=LANG=C.UTF-8
Environment=PATH=$RUBY_DIR/bin:/usr/local/bin:/usr/bin:/bin
$preload
# Same as the Docker entrypoint: create/migrate the database and refresh the tracker list.
ExecStartPre=$INSTALL_DIR/bin/rails db:prepare db:seed
ExecStart=$INSTALL_DIR/bin/rails server -b \${BIND_ADDRESS} -p \${PORT}
Restart=on-failure
RestartSec=5
TimeoutStartSec=600
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
  cat > /usr/local/bin/sherlock-ctl <<EOF
#!/usr/bin/env bash
# sherlock-ctl status|start|stop|restart|logs|rails ARGS   (e.g. rails 'users:reset_password[alice]')
set -euo pipefail
cmd="\${1:-help}"; shift || true
case "\$cmd" in
  status|start|stop|restart) exec systemctl "\$cmd" $SERVICE ;;
  logs) exec journalctl -u $SERVICE -n 200 -f "\$@" ;;
  rails)
    [[ \$EUID -eq 0 ]] || exec sudo "\$0" rails "\$@"
    exec runuser -u $APP_USER -- env -C $INSTALL_DIR HOME=$APP_HOME LANG=C.UTF-8 PATH="$RUBY_DIR/bin:/usr/bin:/bin" \\
      bash -c 'set -a; . $ENV_FILE; set +a; exec ./bin/rails "\$@"' _ "\$@" ;;
  *) sed -n '2p' "\$0"; exit 1 ;;
esac
EOF
  chmod 755 /usr/local/bin/sherlock-ctl
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null 2>&1
}

nginx_proxy() {
  [[ $PROXY == nginx ]] || return 0
  say "nginx"
  apt-get install -y --no-install-recommends nginx
  local conf=/etc/nginx/sites-available/$SERVICE host=${APP_HOST%%:*}
  if [[ -e $conf ]] && ! grep -qE '^# Written by Sherlock|managed by Certbot' "$conf"; then
    die "$conf exists and isn't ours; not overwriting it."
  fi
  if ! grep -qs "managed by Certbot" "$conf"; then
    cat > /etc/nginx/conf.d/sherlock-upgrade.conf <<'EOF'
# WebSocket upgrade for Turbo Streams / Action Cable.
map $http_upgrade $sherlock_connection_upgrade { default upgrade; '' close; }
EOF
    cat > "$conf" <<EOF
# Written by Sherlock
server {
  listen 80;
  server_name $host;
  client_max_body_size 50m;
  location / {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$sherlock_connection_upgrade;
    proxy_read_timeout 120s;
  }
}
EOF
    ln -sfn "$conf" /etc/nginx/sites-enabled/$SERVICE
  fi
  nginx -t || die "The nginx configuration is invalid."
  systemctl enable --now nginx >/dev/null 2>&1
  systemctl reload nginx
  if [[ -n $OPT_EMAIL ]]; then
    apt-get install -y --no-install-recommends certbot python3-certbot-nginx
    certbot --nginx -d "$host" -m "$OPT_EMAIL" --agree-tos --no-eff-email --redirect -n \
      || die "Certificate issuance failed. Check that DNS points here and ports 80/443 are open, then run this script again."
  fi
}

start() {
  say "Starting Sherlock"
  systemctl restart "$SERVICE"
  for _ in $(seq 1 90); do
    if curl -fs -o /dev/null -m 3 "http://127.0.0.1:$PORT/up"; then info "Up: http://127.0.0.1:$PORT/up"; return; fi
    systemctl is-active --quiet "$SERVICE" || break
    sleep 2
  done
  journalctl -u "$SERVICE" -n 40 --no-pager >&2 || true
  die "Sherlock didn't come up. Logs: journalctl -u $SERVICE -e"
}

summary() {
  local url="http://${APP_HOST}"
  [[ $FORCE_SSL == true ]] && url="https://${APP_HOST}"
  [[ $PROXY == none ]] && url="http://${APP_HOST%%:*}:$PORT"
  cat <<EOF

Sherlock is installed.  Open $url and create the first account: it becomes the admin.
  Settings  $ENV_FILE   (then: sudo systemctl restart $SERVICE)
  Status    sudo sherlock-ctl status | logs | restart
  Reset     sudo sherlock-ctl rails 'users:reset_password[username]'
  Update    git pull, then run this script again (no options needed)
  BACK UP   $CRED_DIR/production.key  (and dump the database: sudo -u postgres pg_dump -Fc $DB_NAME)
EOF
  [[ $PROXY == none ]] && echo "  Rails listens on 0.0.0.0:$PORT: put an HTTPS reverse proxy in front or firewall the port."
  return 0
}

main() {
  preflight
  settings
  packages
  postgres
  user_and_files
  build_ruby
  sync_app
  build_app
  credentials
  database
  install_service
  nginx_proxy
  start
  summary
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main; fi
