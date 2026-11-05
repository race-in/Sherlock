#!/usr/bin/env bash
# Sherlock: native installer for Debian 12 and 13 (Debian 11 and Ubuntu 22.04+ best effort). No Docker.
# It works in two modes, chosen by who runs it:
#
#   ROOT      sudo bash deploy/install-debian.sh --domain sherlock.example.com --letsencrypt you@example.com
#             A system install: apt packages, PostgreSQL service, systemd unit, nginx and HTTPS.
#
#   ROOTLESS  bash deploy/install-debian.sh --domain localhost
#             Run as a normal user, no sudo. Everything lives in your home folder, Sherlock runs as you
#             (systemd --user service, or plain background processes), with its own PostgreSQL cluster
#             or one you point it at. Missing system packages are listed instead of installed.
#
# Safe to run again: re-running updates the app from the current checkout and keeps the database,
# the credentials and your settings.
# Run with --help for all options.

set -Eeuo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE=sherlock
# ruby-build release pinned by commit, so a moved tag can't change what gets built.
RUBY_BUILD_TAG=v20261023
RUBY_BUILD_COMMIT=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92

OPT_DOMAIN="" OPT_SSL="" OPT_PROXY="" OPT_EMAIL="" OPT_PORT="" OPT_BIND=""
OPT_DB_HOST="" OPT_DB_PORT="" OPT_DB_NAME="" OPT_DB_USER="" OPT_DB_PASSWORD=""
ASSUME_YES=0
MODE=root

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
trap 'printf "\033[31mInstall stopped at line %s. Fix the problem and run the script again; it is safe to repeat.\033[0m\n" "$LINENO" >&2' ERR

usage() {
  cat <<'EOF'
Usage:
  sudo bash deploy/install-debian.sh --domain HOST [options]     system install (root)
       bash deploy/install-debian.sh --domain HOST [options]     rootless install (normal user)

  --domain HOST        Host name (or IP) Sherlock is reached at. Required on the first run.
  --ssl | --no-ssl     FORCE_SSL on/off. Root default: on (needs --letsencrypt with nginx).
                       Rootless default: off, because there is no proxy; use --ssl if your own
                       HTTPS proxy sits in front.
  --port N             Port of the Rails server (default 3000).
  --bind ADDR          Address Rails listens on. Default: 127.0.0.1, except 0.0.0.0 with --proxy none.
  --db-host HOST       Use an existing PostgreSQL instead of installing one (also --db-port,
                       --db-name, --db-user, --db-password). The user must be able to create
                       the "sherlockdb" schema in the database.
  --db-password PW     Database password (default: random, kept in the settings file).
  -y, --yes            No questions.
  -h, --help           This text.

Root only:
  --proxy nginx|none   nginx (default): install nginx in front, Rails listens on 127.0.0.1 only.
                       none: Rails listens on 0.0.0.0:PORT, bring your own proxy.
  --letsencrypt EMAIL  With nginx: get a free HTTPS certificate (domain must point here, port 80 open).

Where things go
  root      app /opt/sherlock, settings /etc/sherlock, service "sherlock", command /usr/local/bin/sherlock-ctl
  rootless  app ~/.local/share/sherlock/app, settings ~/.config/sherlock, command ~/.local/bin/sherlock-ctl
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)      OPT_DOMAIN="${2:?--domain needs a value}"; shift 2 ;;
    --ssl)         OPT_SSL=true; shift ;;
    --no-ssl)      OPT_SSL=false; shift ;;
    --proxy)       OPT_PROXY="${2:?--proxy needs nginx or none}"; shift 2 ;;
    --letsencrypt) OPT_EMAIL="${2:?--letsencrypt needs an email}"; shift 2 ;;
    --port)        OPT_PORT="${2:?--port needs a value}"; shift 2 ;;
    --bind)        OPT_BIND="${2:?--bind needs an address}"; shift 2 ;;
    --db-host)     OPT_DB_HOST="${2:?--db-host needs a value}"; shift 2 ;;
    --db-port)     OPT_DB_PORT="${2:?--db-port needs a value}"; shift 2 ;;
    --db-name)     OPT_DB_NAME="${2:?--db-name needs a value}"; shift 2 ;;
    --db-user)     OPT_DB_USER="${2:?--db-user needs a value}"; shift 2 ;;
    --db-password) OPT_DB_PASSWORD="${2:?--db-password needs a value}"; shift 2 ;;
    -y|--yes)      ASSUME_YES=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage >&2; die "Unknown option: $1" ;;
  esac
done

# ------------------------------------------------------------------------------------------------
# Paths for the two modes
# ------------------------------------------------------------------------------------------------
init_paths() {
  if [[ $EUID -eq 0 ]]; then
    MODE=root
    APP_USER=sherlock; APP_HOME=/var/lib/sherlock
    INSTALL_DIR=/opt/sherlock; CONF_DIR=/etc/sherlock
    RUBIES_DIR=/opt/rubies; RUBY_BUILD_DIR=/opt/ruby-build
    CTL=/usr/local/bin/sherlock-ctl
    LOG_DIR=/var/log/sherlock
  else
    MODE=user
    APP_USER="$(id -un)"; APP_HOME="$HOME"
    local data="${XDG_DATA_HOME:-$HOME/.local/share}/sherlock"
    INSTALL_DIR="$data/app"; CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sherlock"
    RUBIES_DIR="$data/rubies"; RUBY_BUILD_DIR="$data/ruby-build"
    PGDATA="$data/pgdata"; RUN_DIR="$data/run"; LOG_DIR="$data/log"
    CTL="$HOME/.local/bin/sherlock-ctl"
  fi
  ENV_FILE="$CONF_DIR/sherlock.env"
  CRED_DIR="$CONF_DIR/credentials"
}

# Value of KEY from an existing settings file (so a re-run keeps earlier choices).
env_get() { [[ -f $ENV_FILE ]] && sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 || true; }

# Run a command as the app user, in the app folder, with the service's settings loaded.
# Usage: app_run [-b] CMD ARGS...   (-b: also put Node on the PATH, for the build)
NODE_BIN=""
app_run() {
  local path="$RUBY_DIR/bin:/usr/local/bin:/usr/bin:/bin"
  if [[ ${1:-} == -b ]]; then path="$NODE_BIN:$path"; shift; fi
  local -a cmd=(env -C "$INSTALL_DIR" HOME="$APP_HOME" LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH="$path"
    bash -c 'set -a; . "$0"; set +a; exec "$@"' "$ENV_FILE" "$@")
  if [[ $MODE == root ]]; then runuser -u "$APP_USER" -- "${cmd[@]}"; else "${cmd[@]}"; fi
}

# ------------------------------------------------------------------------------------------------
preflight() {
  say "Checking the system ($MODE mode: $([[ $MODE == root ]] && echo "system install" || echo "installing for $APP_USER, no root needed"))"
  [[ -f $SRC_DIR/Gemfile && -f $SRC_DIR/config/application.rb ]] || die "Run this from the Sherlock checkout (can't find the app next to $0)."
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
  if [[ $MODE == root ]]; then
    command -v apt-get >/dev/null || die "A root install needs apt (Debian or Ubuntu)."
    [[ -d /run/systemd/system ]] || die "systemd isn't running here (container?). Run as a normal user for a rootless install."
  else
    [[ -n ${OPT_EMAIL} ]] && die "--letsencrypt needs a root install (it sets up nginx). For HTTPS rootless, put your own proxy in front and use --ssl."
    [[ -z ${OPT_PROXY} || $OPT_PROXY == none ]] || die "--proxy nginx needs a root install."
  fi
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

  local ssl_default=true; [[ $MODE == user ]] && ssl_default=false
  FORCE_SSL="${OPT_SSL:-$(env_get FORCE_SSL)}"; FORCE_SSL="${FORCE_SSL:-$ssl_default}"
  PORT="${OPT_PORT:-$(env_get PORT)}"; PORT="${PORT:-3000}"
  [[ $PORT =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "--port must be a number from 1 to 65535."
  (( PORT >= 1024 )) || [[ $MODE == root ]] || die "A rootless install can't listen on port $PORT. Use 1024 or higher."

  if [[ $MODE == root ]]; then
    local was; was="$(env_get BIND_ADDRESS)"
    PROXY="${OPT_PROXY:-$([[ $was == 0.0.0.0 ]] && echo none || echo nginx)}"
    [[ $PROXY == nginx || $PROXY == none ]] || die "--proxy must be nginx or none."
    if [[ $PROXY == nginx && $FORCE_SSL == true && -z $OPT_EMAIL ]] && ! grep -qs "managed by Certbot" /etc/nginx/sites-available/$SERVICE; then
      die "HTTPS needs a certificate: add --letsencrypt you@example.com, or use --no-ssl on a private network, or --proxy none with your own HTTPS proxy."
    fi
  else
    PROXY=none
  fi
  BIND_ADDRESS="${OPT_BIND:-}"
  if [[ -z $BIND_ADDRESS ]]; then
    BIND_ADDRESS="$(env_get BIND_ADDRESS)"
    [[ -n $BIND_ADDRESS ]] || BIND_ADDRESS=$([[ $MODE == root && $PROXY == nginx || $MODE == user ]] && echo 127.0.0.1 || echo 0.0.0.0)
  fi

  # Database: an existing server, or a local one this script manages.
  EXTERNAL_DB=0
  local old_host; old_host="$(env_get DB_HOST)"
  if [[ -n $OPT_DB_HOST || ( -n $old_host && $old_host != 127.0.0.1 ) ]]; then EXTERNAL_DB=1; fi
  DB_HOST="${OPT_DB_HOST:-$(env_get DB_HOST)}"; DB_HOST="${DB_HOST:-127.0.0.1}"
  DB_NAME="${OPT_DB_NAME:-$(env_get DB_NAME)}"; DB_NAME="${DB_NAME:-sherlockdb_prod}"
  DB_USER="${OPT_DB_USER:-$(env_get DB_USER)}"; DB_USER="${DB_USER:-sherlockdb_prod_write}"
  local port_default=5432; [[ $MODE == user ]] && port_default=54329   # a rootless cluster stays clear of a system one
  DB_PORT="${OPT_DB_PORT:-$(env_get DB_PORT)}"; DB_PORT="${DB_PORT:-$port_default}"
  [[ $DB_PORT =~ ^[0-9]+$ ]] || die "--db-port must be a number."
  [[ $DB_HOST =~ ^[A-Za-z0-9._:%-]+$ ]] || die "--db-host contains unsupported characters."
  [[ $DB_NAME =~ ^[a-z_][a-z0-9_]*$ && $DB_USER =~ ^[a-z_][a-z0-9_]*$ ]] || die "Database and user names may only use lowercase letters, digits and underscores."
  DB_PASSWORD="${OPT_DB_PASSWORD:-$(env_get DB_PASSWORD)}"
  if [[ $EXTERNAL_DB -eq 1 && -z $DB_PASSWORD ]]; then
    [[ -t 0 && $ASSUME_YES -eq 0 ]] || die "Give the database password with --db-password."
    read -r -s -p "Password of $DB_USER on $DB_HOST: " DB_PASSWORD; echo
  fi
  DB_PASSWORD="${DB_PASSWORD:-$(openssl rand -hex 24)}"
  [[ $DB_PASSWORD =~ ^[A-Za-z0-9._~-]+$ ]] || die "The database password may only use letters, digits and . _ ~ -"
  APP_VERSION="$(git -C "$SRC_DIR" describe --tags --abbrev=0 2>/dev/null || true)"; APP_VERSION="${APP_VERSION:-$(env_get APP_VERSION)}"; APP_VERSION="${APP_VERSION:-unknown}"

  info "Host $APP_HOST (FORCE_SSL=$FORCE_SSL), Rails on $BIND_ADDRESS:$PORT$([[ $MODE == root ]] && echo ", proxy: $PROXY")"
  info "Ruby $RUBY_VERSION, Node $NODE_VERSION (build only)"
  if (( EXTERNAL_DB )); then info "Database: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME (existing server)"; else info "Database: PostgreSQL on this machine, port $DB_PORT"; fi
  if [[ -t 0 && $ASSUME_YES -eq 0 ]]; then
    local a; read -r -p "Continue? [Y/n] " a || true
    [[ -z $a || $a =~ ^[Yy] ]] || die "Stopped."
  fi
}

# ------------------------------------------------------------------------------------------------
# System packages
# ------------------------------------------------------------------------------------------------
BUILD_PACKAGES=(ca-certificates curl gnupg git openssl rsync xz-utils tar patch file sudo tzdata
  build-essential autoconf bison pkg-config
  libssl-dev zlib1g-dev libyaml-dev libffi-dev libreadline-dev libncurses-dev libgmp-dev libgdbm-dev libdb-dev uuid-dev
  libpq-dev libjemalloc2 libatomic1)

packages_root() {
  say "Installing system packages"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends "${BUILD_PACKAGES[@]}" postgresql-common
}

have_cmd()    { command -v "$1" >/dev/null 2>&1; }
have_header() { printf '#include <%s>\n' "$1" | cc -E -x c - >/dev/null 2>&1; }

# Rootless: nothing can be installed, so check what Ruby and the gems need and say what is missing.
packages_user() {
  say "Checking the build tools and libraries"
  local -a missing=()
  local c
  for c in cc make git curl openssl rsync tar xz patch bison autoconf pkg-config; do
    have_cmd "$c" || case "$c" in
      cc|make) missing+=(build-essential) ;;
      xz) missing+=(xz-utils) ;;
      pkg-config) missing+=(pkg-config) ;;
      *) missing+=("$c") ;;
    esac
  done
  if have_cmd cc; then
    local h
    for h in "openssl/ssl.h:libssl-dev" "zlib.h:zlib1g-dev" "yaml.h:libyaml-dev" "ffi.h:libffi-dev" \
             "readline/readline.h:libreadline-dev" "ncurses.h:libncurses-dev" "gmp.h:libgmp-dev" \
             "gdbm.h:libgdbm-dev" "db.h:libdb-dev" "uuid/uuid.h:uuid-dev" "libpq-fe.h:libpq-dev"; do
      have_header "${h%%:*}" || missing+=("${h##*:}")
    done
  fi
  if (( ! EXTERNAL_DB )); then
    PG_BIN="$(find_pg_bin)"
    [[ -n $PG_BIN ]] || missing+=(postgresql)
  fi
  if (( ${#missing[@]} )); then
    mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort -u)
    printf '\nMissing packages: %s\nAsk an administrator to run (or run it with sudo yourself):\n\n  sudo apt-get install -y %s\n' "${missing[*]}" "${missing[*]}" >&2
    if [[ " ${missing[*]} " == *" postgresql "* ]]; then
      printf '\nThat starts a system PostgreSQL service you do not need; stop it with\n  sudo systemctl disable --now postgresql\nSherlock runs its own cluster in your home folder. Or skip PostgreSQL entirely by pointing at one you\nalready have: --db-host HOST --db-user USER --db-password PW\n' >&2
    fi
    die "Install the packages above, then run this script again."
  fi
  info "Everything needed is installed."
}

# Newest PostgreSQL server binaries (initdb, pg_ctl, postgres) on this machine, or nothing.
find_pg_bin() {
  local d
  for d in $(compgen -G '/usr/lib/postgresql/*/bin' | sort -V -r); do
    [[ -x $d/initdb && -x $d/pg_ctl && -x $d/postgres ]] && { echo "$d"; return; }
  done
}

# ------------------------------------------------------------------------------------------------
# PostgreSQL
# ------------------------------------------------------------------------------------------------
postgres_root() {
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

# Rootless: a private cluster in the home folder. Its superuser is the database user Sherlock logs in as,
# it listens on 127.0.0.1 only (password required) and keeps its socket in the run folder.
pg_user_opts() { printf -- '-p %s -k %s -c listen_addresses=127.0.0.1 -c unix_socket_directories=%s' "$DB_PORT" "$RUN_DIR" "$RUN_DIR"; }

postgres_user() {
  say "PostgreSQL (private cluster in $PGDATA)"
  PG_BIN="${PG_BIN:-$(find_pg_bin)}"
  [[ -n $PG_BIN ]] || die "No PostgreSQL server binaries found under /usr/lib/postgresql. Install postgresql, or use --db-host."
  PG_MAJOR="$(basename "$(dirname "$PG_BIN")")"
  install -d -m 0700 "$RUN_DIR" "$LOG_DIR"
  if [[ ! -f $PGDATA/PG_VERSION ]]; then
    info "Creating the cluster (PostgreSQL $PG_MAJOR)"
    local pwf; pwf="$(mktemp)"; printf '%s\n' "$DB_PASSWORD" > "$pwf"
    "$PG_BIN/initdb" -D "$PGDATA" -U "$DB_USER" --pwfile="$pwf" -E UTF8 --locale=C.UTF-8 \
      --auth-local=trust --auth-host=scram-sha-256 >/dev/null || { rm -f "$pwf"; die "initdb failed."; }
    rm -f "$pwf"
  elif [[ "$(cat "$PGDATA/PG_VERSION")" != "$PG_MAJOR" ]]; then
    # Keep using the version that made the data; its binaries sit next to the newer ones.
    local ver; ver="$(cat "$PGDATA/PG_VERSION")"
    PG_BIN="$(dirname "$(dirname "$PG_BIN")")/$ver/bin"
    [[ -x $PG_BIN/pg_ctl ]] || die "The cluster in $PGDATA is PostgreSQL $ver but its binaries ($PG_BIN) are gone."
    PG_MAJOR="$ver"
  fi
  if ! "$PG_BIN/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1; then
    "$PG_BIN/pg_ctl" -D "$PGDATA" -l "$LOG_DIR/postgres.log" -o "$(pg_user_opts)" -w start >/dev/null \
      || { tail -n 20 "$LOG_DIR/postgres.log" >&2; die "PostgreSQL didn't start. Log: $LOG_DIR/postgres.log"; }
  fi
  PG_STARTED_BY_INSTALLER=1
  # The password is already set by initdb. Create the application database over the private socket.
  if ! "$PG_BIN/psql" -X -Atq -h "$RUN_DIR" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1; then
    "$PG_BIN/psql" -X -q -h "$RUN_DIR" -p "$DB_PORT" -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE $DB_NAME ENCODING 'UTF8'" >/dev/null
  fi
  # A re-run with another --db-password must still work.
  "$PG_BIN/psql" -X -q -h "$RUN_DIR" -p "$DB_PORT" -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -v pw="$DB_PASSWORD" -v u="$DB_USER" \
    <<<"ALTER ROLE :\"u\" PASSWORD :'pw';" >/dev/null
  info "Running on port $DB_PORT, database $DB_NAME"
}

# ------------------------------------------------------------------------------------------------
build_ruby() {
  say "Ruby $RUBY_VERSION"
  RUBY_DIR="$RUBIES_DIR/$RUBY_VERSION"
  if [[ -x $RUBY_DIR/bin/ruby ]]; then info "Already built in $RUBY_DIR"; return; fi
  local rb=$RUBY_BUILD_DIR log="$LOG_DIR/ruby-build.log"
  install -d "$LOG_DIR" "$RUBIES_DIR"
  if [[ -d $rb/.git ]]; then
    git -C "$rb" fetch -q --depth 1 origin "refs/tags/$RUBY_BUILD_TAG:refs/tags/$RUBY_BUILD_TAG"
    git -C "$rb" checkout -q --detach "$RUBY_BUILD_TAG"
  else
    git clone -q --depth 1 --branch "$RUBY_BUILD_TAG" https://github.com/rbenv/ruby-build.git "$rb"
  fi
  [[ "$(git -C "$rb" rev-parse HEAD)" == "$RUBY_BUILD_COMMIT" ]] || die "ruby-build $RUBY_BUILD_TAG isn't the expected commit; refusing to build with it."
  "$rb/bin/ruby-build" --definitions | grep -qx "$RUBY_VERSION" || die "ruby-build doesn't know Ruby $RUBY_VERSION."
  info "Compiling Ruby (5 to 15 minutes). Log: $log"
  RUBY_CONFIGURE_OPTS=--disable-install-doc "$rb/bin/ruby-build" "$RUBY_VERSION" "$RUBY_DIR" >"$log" 2>&1 \
    || { tail -n 30 "$log" >&2; die "Building Ruby failed."; }
}

NODE_TMP=""
node_for_build() {
  NODE_TMP="$(mktemp -d "${TMPDIR:-/var/tmp}/sherlock-node.XXXXXX")"; chmod 755 "$NODE_TMP"
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
  say "Folders and settings"
  if [[ $MODE == root ]]; then
    getent group "$APP_USER" >/dev/null || groupadd --system "$APP_USER"
    id -u "$APP_USER" >/dev/null 2>&1 || useradd --system --gid "$APP_USER" --home-dir "$APP_HOME" --create-home --shell /usr/sbin/nologin "$APP_USER"
    install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$APP_HOME"
    install -d -m 0755 "$CONF_DIR"
    install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$CRED_DIR"
    install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$LOG_DIR"
  else
    install -d -m 0700 "$CONF_DIR" "$CRED_DIR" "$LOG_DIR" "$(dirname "$INSTALL_DIR")"
  fi

  local tmp; tmp="$(mktemp)"
  {
    echo "# Written by deploy/install-debian.sh. Edit, then restart: sherlock-ctl restart"
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
  if [[ $MODE == root ]]; then install -o root -g "$APP_USER" -m 0640 "$tmp" "$ENV_FILE"; else install -m 0600 "$tmp" "$ENV_FILE"; fi
  rm -f "$tmp"
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
  if [[ $MODE == root ]]; then chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"; fi
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
  local tmp; tmp="$(mktemp -p "$CRED_DIR" .new.XXXXXX)"; chmod 600 "$tmp"
  [[ $MODE == user ]] || chown "$APP_USER:$APP_USER" "$tmp"
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
    || die "Can't log in to $DB_NAME as $DB_USER on $DB_HOST:$DB_PORT."
  if (( EXTERNAL_DB )); then
    PG_MAJOR=$(( $(psql -X -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -Atc "SHOW server_version_num") / 10000 ))
  fi
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

# ------------------------------------------------------------------------------------------------
# Services and the sherlock-ctl helper
# ------------------------------------------------------------------------------------------------
jemalloc_path() { local p; p="/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2"; if [[ -e $p ]]; then echo "$p"; fi; }

install_service_root() {
  say "systemd service"
  local jem; jem="$(jemalloc_path)"
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
${jem:+Environment=LD_PRELOAD=$jem}
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
  cat > "$CTL" <<EOF
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
  chmod 755 "$CTL"
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null 2>&1
}

# Rootless: systemd --user units when a user manager is running, otherwise plain background processes.
install_service_user() {
  say "Service (rootless)"
  local jem; jem="$(jemalloc_path)"
  SYSTEMD_USER=0
  if have_cmd systemctl && [[ -n ${XDG_RUNTIME_DIR:-} ]] && systemctl --user show-environment >/dev/null 2>&1; then SYSTEMD_USER=1; fi
  local pgstart=""
  if (( ! EXTERNAL_DB )); then
    pgstart="$PG_BIN/postgres -D $PGDATA $(pg_user_opts)"
  fi
  if (( SYSTEMD_USER )); then
    local ud="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
    install -d "$ud"
    local after="" requires=""
    if [[ -n $pgstart ]]; then
      cat > "$ud/$SERVICE-postgres.service" <<EOF
[Unit]
Description=Sherlock's private PostgreSQL

[Service]
ExecStart=$pgstart
ExecStop=$PG_BIN/pg_ctl -D $PGDATA -m fast stop
Restart=on-failure

[Install]
WantedBy=default.target
EOF
      after="After=$SERVICE-postgres.service"; requires="Requires=$SERVICE-postgres.service"
    fi
    cat > "$ud/$SERVICE.service" <<EOF
[Unit]
Description=Sherlock (private tracker stats)
$after
$requires

[Service]
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
Environment=LANG=C.UTF-8
Environment=PATH=$RUBY_DIR/bin:/usr/local/bin:/usr/bin:/bin
${jem:+Environment=LD_PRELOAD=$jem}
ExecStartPre=$INSTALL_DIR/bin/rails db:prepare db:seed
ExecStart=$INSTALL_DIR/bin/rails server -b \${BIND_ADDRESS} -p \${PORT}
Restart=on-failure
RestartSec=5
TimeoutStartSec=600

[Install]
WantedBy=default.target
EOF
    # The installer started PostgreSQL by hand to prepare the database; hand it over to systemd.
    if [[ -n ${PG_STARTED_BY_INSTALLER:-} ]]; then "$PG_BIN/pg_ctl" -D "$PGDATA" -m fast stop >/dev/null 2>&1 || true; fi
    systemctl --user daemon-reload
    systemctl --user enable "$SERVICE.service" ${pgstart:+"$SERVICE-postgres.service"} >/dev/null 2>&1
  fi

  install -d "$(dirname "$CTL")"
  cat > "$CTL" <<EOF
#!/usr/bin/env bash
# sherlock-ctl status|start|stop|restart|logs|rails ARGS   (e.g. rails 'users:reset_password[alice]')
set -euo pipefail
SYSTEMD_USER=$SYSTEMD_USER
INSTALL_DIR='$INSTALL_DIR'; ENV_FILE='$ENV_FILE'; RUBY_BIN='$RUBY_DIR/bin'; LOG_DIR='$LOG_DIR'
PGDATA='$PGDATA'; PG_BIN='${PG_BIN:-}'; PG_OPTS='$([[ -n $pgstart ]] && pg_user_opts)'; RUN_DIR='$RUN_DIR'
PIDFILE="\$RUN_DIR/sherlock.pid"
JEM='$jem'
mkdir -p "\$RUN_DIR" "\$LOG_DIR"
alive() { [[ -f \$PIDFILE ]] && kill -0 "\$(cat "\$PIDFILE")" 2>/dev/null; }
pg_up()   { [[ -z \$PG_BIN ]] || "\$PG_BIN/pg_ctl" -D "\$PGDATA" status >/dev/null 2>&1 || "\$PG_BIN/pg_ctl" -D "\$PGDATA" -l "\$LOG_DIR/postgres.log" -o "\$PG_OPTS" -w start >/dev/null; }
pg_down() { [[ -z \$PG_BIN ]] || "\$PG_BIN/pg_ctl" -D "\$PGDATA" -m fast stop >/dev/null 2>&1 || true; }
run_app() {
  cd "\$INSTALL_DIR"; set -a; . "\$ENV_FILE"; set +a
  export LANG=C.UTF-8 PATH="\$RUBY_BIN:\$PATH"; [[ -z \$JEM ]] || export LD_PRELOAD="\$JEM"
  exec "\$@"
}
start_plain() {
  alive && { echo "Sherlock is already running (pid \$(cat "\$PIDFILE"))."; return; }
  pg_up
  ( run_app bash -c './bin/rails db:prepare db:seed && exec ./bin/rails server -b "\$BIND_ADDRESS" -p "\$PORT"' ) >>"\$LOG_DIR/sherlock.log" 2>&1 &
  echo \$! > "\$PIDFILE"
  echo "Started (pid \$!). Logs: sherlock-ctl logs"
}
stop_plain() {
  if alive; then kill "\$(cat "\$PIDFILE")" 2>/dev/null || true; for _ in \$(seq 1 30); do alive || break; sleep 1; done; fi
  rm -f "\$PIDFILE"; pg_down; echo "Stopped."
}
cmd="\${1:-help}"; shift || true
case "\$cmd" in
  start|stop|restart|status)
    if (( SYSTEMD_USER )); then
      units=(sherlock.service); [[ -z \$PG_BIN ]] || units=(sherlock-postgres.service sherlock.service)
      case "\$cmd" in
        stop) systemctl --user stop sherlock.service ;;
        *)    systemctl --user "\$cmd" "\${units[@]}" ;;
      esac
    else
      case "\$cmd" in
        start) start_plain ;;
        stop) stop_plain ;;
        restart) stop_plain; start_plain ;;
        status) if alive; then echo "Sherlock is running (pid \$(cat "\$PIDFILE"))."; else echo "Sherlock is not running."; exit 3; fi ;;
      esac
    fi ;;
  logs) if (( SYSTEMD_USER )); then exec journalctl --user -u sherlock.service -n 200 -f "\$@"; else exec tail -n 200 -f "\$LOG_DIR/sherlock.log" "\$@"; fi ;;
  rails) run_app ./bin/rails "\$@" ;;
  *) sed -n '2p' "\$0"; exit 1 ;;
esac
EOF
  chmod 755 "$CTL"
}

nginx_proxy() {
  [[ $MODE == root && $PROXY == nginx ]] || return 0
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
  if [[ $MODE == root ]]; then
    systemctl restart "$SERVICE"
  else
    "$CTL" stop >/dev/null 2>&1 || true
    "$CTL" start
  fi
  for _ in $(seq 1 90); do
    if curl -fs -o /dev/null -m 3 "http://127.0.0.1:$PORT/up"; then info "Up: http://127.0.0.1:$PORT/up"; return; fi
    if [[ $MODE == root ]]; then systemctl is-active --quiet "$SERVICE" || break; fi
    sleep 2
  done
  if [[ $MODE == root ]]; then journalctl -u "$SERVICE" -n 40 --no-pager >&2 || true; else tail -n 40 "$LOG_DIR/sherlock.log" >&2 || true; fi
  die "Sherlock didn't come up. Check the logs: sherlock-ctl logs"
}

summary() {
  local url="http://${APP_HOST}"
  [[ $FORCE_SSL == true ]] && url="https://${APP_HOST}"
  [[ $PROXY == none ]] && url="http://${APP_HOST%%:*}:$PORT"
  [[ $PROXY == none && $FORCE_SSL == true ]] && url="https://${APP_HOST%%:*}  (via your HTTPS proxy to port $PORT)"
  cat <<EOF

Sherlock is installed.  Open $url and create the first account: it becomes the admin.
  Settings  $ENV_FILE   (then: sherlock-ctl restart)
  Control   $([[ $MODE == root ]] && echo "sudo ")sherlock-ctl status | start | stop | restart | logs
  Reset     $([[ $MODE == root ]] && echo "sudo ")sherlock-ctl rails 'users:reset_password[username]'
  Update    git pull, then run this script again (no options needed)
  BACK UP   $CRED_DIR/production.key, and the database ($([[ $MODE == root ]] && echo "sudo -u postgres pg_dump -Fc $DB_NAME" || echo "pg_dump -Fc -h ${PGDATA:+$RUN_DIR}${PGDATA:-$DB_HOST} -p $DB_PORT -U $DB_USER $DB_NAME"))
EOF
  if [[ $MODE == root && $PROXY == none ]]; then echo "  Rails listens on 0.0.0.0:$PORT: put an HTTPS reverse proxy in front or firewall the port."; fi
  if [[ $MODE == user ]]; then
    case ":$PATH:" in *":$(dirname "$CTL"):"*) ;; *) echo "  Add ~/.local/bin to your PATH to use sherlock-ctl, or call $CTL." ;; esac
    if (( SYSTEMD_USER )); then
      echo "  It starts at login. To keep it running after you log out (needs an administrator): sudo loginctl enable-linger $APP_USER"
    else
      echo "  No systemd user session here, so Sherlock runs as a background process: start it again after a reboot with 'sherlock-ctl start'."
    fi
    [[ $BIND_ADDRESS != 127.0.0.1 ]] || echo "  It listens on 127.0.0.1 only. Use --bind 0.0.0.0 (and a firewall) to reach it from other machines."
  fi
  return 0
}

main() {
  init_paths
  preflight
  settings
  if [[ $MODE == root ]]; then
    packages_root
    (( EXTERNAL_DB )) || postgres_root
  else
    packages_user
    (( EXTERNAL_DB )) || postgres_user
  fi
  user_and_files
  build_ruby
  sync_app
  build_app
  credentials
  database
  if [[ $MODE == root ]]; then install_service_root; else install_service_user; fi
  nginx_proxy
  start
  summary
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main; fi
