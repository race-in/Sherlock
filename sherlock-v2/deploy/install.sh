#!/usr/bin/env bash
# Sherlock: native installer for Debian 11 (bullseye), 12 (bookworm) and 13 (trixie).
#
# What it does (every step is safe to run again, so re-running it also updates Sherlock):
#   1. installs build tools and libraries with apt
#   2. installs PostgreSQL (18 if the repository has it) and creates the database and user
#   3. builds the Ruby version in .ruby-version under /opt/rubies (Debian ships none that is new enough)
#   4. copies the app to /opt/sherlock, installs gems, builds JavaScript and CSS (Node is only used
#      for the build, in a temporary directory)
#   5. creates the encrypted credentials (secret key and the key that encrypts saved API keys)
#   6. installs and starts the "sherlock" systemd service (web server and tracker polling in one)
#   7. optionally sets up nginx as the reverse proxy, with a Let's Encrypt certificate
#
# Run it as root from the project folder:   sudo ./deploy/install.sh --domain sherlock.example.com
# Run it with --help for all options.

set -Eeuo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------------------------
# Settings. Order of precedence: command line > existing /etc/sherlock/sherlock.env > default.
# ---------------------------------------------------------------------------------------------
APP_USER=sherlock
APP_HOME=/var/lib/sherlock
INSTALL_DIR=/opt/sherlock
CONF_DIR=/etc/sherlock
ENV_FILE="$CONF_DIR/sherlock.env"
CRED_DIR="$CONF_DIR/credentials"
RUBIES_DIR=/opt/rubies
RUBY_BUILD_DIR=/opt/ruby-build
SERVICE=sherlock

OPT_DOMAIN=""
OPT_FORCE_SSL=""          # true / false
OPT_PORT=""
OPT_PROXY=""              # nginx / none
OPT_LE_EMAIL=""
OPT_DB_HOST=""
OPT_DB_PORT=""
OPT_DB_NAME=""
OPT_DB_USER=""
OPT_DB_PASSWORD=""
OPT_PG_VERSION=""
OPT_RUBY_VERSION=""
OPT_NODE_VERSION=""
ASSUME_YES=0
FORCE_OS=0

CODENAME=""
ARCH=""
MULTIARCH=""
PG_MAJOR=""
EXTERNAL_DB=0
EXISTING_INSTALL=0

# ---------------------------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_BOLD=$'\033[1m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_OFF=$'\033[0m'
else
  C_BOLD=""; C_RED=""; C_YEL=""; C_GRN=""; C_OFF=""
fi
step() { printf '\n%s==> %s%s\n' "$C_BOLD" "$*" "$C_OFF"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s%s%s\n' "$C_GRN" "$*" "$C_OFF"; }
warn() { printf '%sWARNING:%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%sERROR:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

ERR_SHOWN=0
on_error() {
  local rc=$? line=$1
  if [[ $ERR_SHOWN -eq 0 ]]; then
    ERR_SHOWN=1
    printf '%sInstall stopped (exit %s, line %s). Fix the problem and run the installer again; finished steps are skipped or redone safely.%s\n' "$C_RED" "$rc" "$line" "$C_OFF" >&2
  fi
}
trap 'on_error $LINENO' ERR

usage() {
  cat <<'EOF'
Usage: sudo ./deploy/install.sh --domain HOST [options]

Basics
  --domain HOST          Domain Sherlock is served on (APP_HOST). Required on the first run.
  --no-ssl               Serve plain HTTP (FORCE_SSL=false): no redirect to HTTPS, no secure cookies.
                         Only for a private network.
  --proxy nginx|none     nginx (default): install nginx and proxy port 80 to Sherlock, which then only
                         listens on 127.0.0.1. none: Sherlock listens on 0.0.0.0:PORT, bring your own proxy.
  --letsencrypt EMAIL    With --proxy nginx: get a free HTTPS certificate for the domain (needs the
                         domain to point at this server and port 80 to be reachable).
  --port N               Port Sherlock listens on (default 3000).

Database (default: install PostgreSQL on this machine)
  --db-host HOST         Use an existing PostgreSQL instead (also --db-port, --db-name, --db-user,
                         --db-password). The user must be allowed to create the "sherlockdb" schema.
  --pg-version N         PostgreSQL major version to install (default: 18, falls back to 17, then to
                         what Debian ships).

Other
  --install-dir DIR      Where the app lives (default /opt/sherlock).
  --ruby-version X.Y.Z   Ruby to build (default: the one in .ruby-version).
  --node-version X.Y.Z   Node.js used for the build only (default: the one in .node-version).
  -y, --yes              Don't ask questions.
  --force                Continue on a system that isn't Debian 11/12/13 (Ubuntu 22.04+ usually works).
  -h, --help             This text.

Files it creates:  /opt/sherlock (app), /etc/sherlock/sherlock.env (settings and DB password),
                   /etc/sherlock/credentials (BACK THIS UP: without the key, saved API keys are lost),
                   /etc/systemd/system/sherlock.service, /usr/local/bin/sherlock-ctl.
EOF
}

# ---------------------------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --domain)          OPT_DOMAIN="${2:?--domain needs a value}"; shift 2 ;;
      --no-ssl)          OPT_FORCE_SSL=false; shift ;;
      --ssl)             OPT_FORCE_SSL=true; shift ;;
      --proxy)           OPT_PROXY="${2:?--proxy needs nginx or none}"; shift 2 ;;
      --letsencrypt)     OPT_LE_EMAIL="${2:?--letsencrypt needs an email address}"; shift 2 ;;
      --port)            OPT_PORT="${2:?--port needs a value}"; shift 2 ;;
      --db-host)         OPT_DB_HOST="${2:?--db-host needs a value}"; shift 2 ;;
      --db-port)         OPT_DB_PORT="${2:?--db-port needs a value}"; shift 2 ;;
      --db-name)         OPT_DB_NAME="${2:?--db-name needs a value}"; shift 2 ;;
      --db-user)         OPT_DB_USER="${2:?--db-user needs a value}"; shift 2 ;;
      --db-password)     OPT_DB_PASSWORD="${2:?--db-password needs a value}"; shift 2 ;;
      --pg-version)      OPT_PG_VERSION="${2:?--pg-version needs a value}"; shift 2 ;;
      --install-dir)     INSTALL_DIR="${2:?--install-dir needs a value}"; shift 2 ;;
      --ruby-version)    OPT_RUBY_VERSION="${2:?--ruby-version needs a value}"; shift 2 ;;
      --node-version)    OPT_NODE_VERSION="${2:?--node-version needs a value}"; shift 2 ;;
      -y|--yes)          ASSUME_YES=1; shift ;;
      --force)           FORCE_OS=1; shift ;;
      -h|--help)         usage; exit 0 ;;
      *)                 usage >&2; die "Unknown option: $1" ;;
    esac
  done
  [[ -z "$OPT_PROXY" || "$OPT_PROXY" == nginx || "$OPT_PROXY" == none ]] || die "--proxy must be nginx or none"
  [[ -z "$OPT_PORT" || "$OPT_PORT" =~ ^[0-9]+$ ]] || die "--port must be a number"
  [[ -z "$OPT_PORT" || ( "$OPT_PORT" -ge 1 && "$OPT_PORT" -le 65535 ) ]] || die "--port must be between 1 and 65535"
  [[ -z "$OPT_PG_VERSION" || "$OPT_PG_VERSION" =~ ^[0-9]+$ ]] || die "--pg-version must be a number like 18"
  [[ "$INSTALL_DIR" == /* ]] || die "--install-dir must be an absolute path"
}

# ---------------------------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------------------------
# Value of KEY in the existing env file, or empty.
env_get() {
  [[ -f "$ENV_FILE" ]] || return 0
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1
}

# First non-empty of: command line value, existing env value, default.
pick() { # pick CLI_VALUE ENV_KEY DEFAULT
  if [[ -n "$1" ]]; then printf '%s' "$1"; return; fi
  local existing; existing="$(env_get "$2")"
  if [[ -n "$existing" ]]; then printf '%s' "$existing"; else printf '%s' "$3"; fi
}

random_hex() { openssl rand -hex "${1:-24}"; }

apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }

confirm() { # confirm "question" default(y/n)
  [[ $ASSUME_YES -eq 1 || ! -t 0 ]] && return 0
  local ans; read -r -p "$1 [Y/n] " ans || true
  [[ -z "$ans" || "$ans" =~ ^[Yy] ]]
}

# Run a command as the app user, with the app's Ruby (and optionally Node) on the PATH.
APP_PATH_PREFIX=""
as_app() {
  runuser -u "$APP_USER" -- env \
    HOME="$APP_HOME" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    PATH="${APP_PATH_PREFIX}/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    "$@"
}

# Run bin/rails (or any command) in the app folder as the app user with the service's settings.
in_app() {
  ( cd "$INSTALL_DIR"
    set -a
    # shellcheck disable=SC1090
    . "$ENV_FILE"
    set +a
    as_app "$@" )
}

# ---------------------------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------------------------
preflight() {
  step "Checking the system"
  [[ $EUID -eq 0 ]] || die "Run this as root: sudo $0 ..."
  [[ -f "$SRC_DIR/config/application.rb" && -f "$SRC_DIR/Gemfile" ]] \
    || die "Can't find the Sherlock source next to this script ($SRC_DIR). Run it from the project folder."
  if [[ -e "$INSTALL_DIR" ]]; then
    [[ -f "$INSTALL_DIR/.sherlock-native-install" ]] \
      || die "$INSTALL_DIR already exists and is not marked as a Sherlock native installation; refusing to overwrite it."
    EXISTING_INSTALL=1
  fi
  command -v apt-get >/dev/null || die "This installer needs apt (Debian or a Debian-based system)."
  command -v systemctl >/dev/null && [[ -d /run/systemd/system ]] \
    || die "systemd isn't running here (a container without systemd?). Use the Docker setup in the README instead."

  # shellcheck disable=SC1091
  . /etc/os-release
  CODENAME="${VERSION_CODENAME:-}"
  [[ -n "$CODENAME" ]] || CODENAME="$(lsb_release -cs 2>/dev/null || true)"
  case "${ID:-}:${VERSION_ID:-}" in
    debian:11|debian:12|debian:13) ok "Debian ${VERSION_ID} (${CODENAME})" ;;
    ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) warn "Ubuntu ${VERSION_ID} isn't the main target, but should work." ;;
    *)
      [[ $FORCE_OS -eq 1 ]] || die "Unsupported system: ${PRETTY_NAME:-unknown}. Debian 11, 12 and 13 are supported (--force to try anyway)."
      warn "Unsupported system ${PRETTY_NAME:-unknown}, continuing because of --force."
      [[ -n "$CODENAME" ]] || die "Can't tell the release codename."
      ;;
  esac

  case "$(uname -m)" in
    x86_64)  ARCH=x64 ;;
    aarch64) ARCH=arm64 ;;
    *) die "Unsupported CPU: $(uname -m). Only x86_64 and aarch64 are supported." ;;
  esac
  MULTIARCH="$(uname -m)-linux-gnu"

  local mem_kb swap_kb
  mem_kb="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
  swap_kb="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"
  if (( mem_kb + swap_kb < 1500000 )); then
    warn "Less than 1.5 GB of memory plus swap. Compiling Ruby and the gems may run out of memory; add some swap if it does."
  fi
  local free_mb; free_mb="$(df -Pm /opt | awk 'NR==2 {print $4}')"
  (( free_mb > 3000 )) || warn "Only ${free_mb} MB free under /opt. The build needs about 3 GB."
}

resolve_settings() {
  step "Settings"
  local ruby_default node_default
  ruby_default="$(tr -d '[:space:]' < "$SRC_DIR/.ruby-version")"
  node_default="$(tr -d '[:space:]' < "$SRC_DIR/.node-version")"
  RUBY_VERSION="${OPT_RUBY_VERSION:-$ruby_default}"
  NODE_VERSION="${OPT_NODE_VERSION:-$node_default}"
  [[ "$RUBY_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid Ruby version: $RUBY_VERSION"
  [[ "$NODE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid Node.js version: $NODE_VERSION"

  # Debian 11's kernel/glibc are too old for the pinned Node 26 binary.
  # Node 24 is sufficient for the frontend toolchain (esbuild requires Node >= 18).
  case "$CODENAME" in
    bullseye)
      [[ "$NODE_VERSION" == 26.12.0 || "$NODE_VERSION" == 24.22.2 ]] \
        || die "Debian 11 supports the Node.js 24.22.2 build runtime only."
      NODE_VERSION=24.22.2
      ;;
    bookworm|trixie)
      [[ "$NODE_VERSION" == 26.12.0 ]] \
        || die "Debian 12/13 use the pinned Node.js 26.12.0 build runtime."
      ;;
  esac

  APP_HOST="$(pick "$OPT_DOMAIN" APP_HOST "")"
  if [[ -z "$APP_HOST" ]]; then
    if [[ -t 0 && $ASSUME_YES -eq 0 ]]; then
      read -r -p "Domain Sherlock will be served on (e.g. sherlock.example.com): " APP_HOST
    fi
    [[ -n "$APP_HOST" ]] || die "Give the domain with --domain sherlock.example.com"
  fi
  APP_HOST="${APP_HOST,,}"
  [[ "$APP_HOST" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}(:[0-9]+)?$ ]] \
    || die "Give a fully qualified domain name, for example sherlock.example.com (got: $APP_HOST)."

  FORCE_SSL="$(pick "$OPT_FORCE_SSL" FORCE_SSL true)"
  [[ "$FORCE_SSL" == true || "$FORCE_SSL" == false ]] || die "FORCE_SSL must be true or false."
  PORT="$(pick "$OPT_PORT" PORT 3000)"
  [[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || die "PORT must be between 1 and 65535."

  # The proxy choice is remembered through BIND_ADDRESS: 127.0.0.1 means "behind nginx".
  local default_proxy=nginx
  [[ "$(env_get BIND_ADDRESS)" == 0.0.0.0 ]] && default_proxy=none
  PROXY="${OPT_PROXY:-$default_proxy}"
  if [[ "$PROXY" == nginx ]]; then BIND_ADDRESS=127.0.0.1; else BIND_ADDRESS=0.0.0.0; fi

  if [[ -n "$OPT_DB_HOST" || ( -n "$(env_get DB_HOST)" && "$(env_get DB_HOST)" != 127.0.0.1 ) ]]; then
    EXTERNAL_DB=1
    DB_HOST="$(pick "$OPT_DB_HOST" DB_HOST "")"
  else
    DB_HOST=127.0.0.1
  fi
  DB_NAME="$(pick "$OPT_DB_NAME" DB_NAME sherlockdb_prod)"
  DB_USER="$(pick "$OPT_DB_USER" DB_USER sherlockdb_prod_write)"
  DB_PORT="$(pick "$OPT_DB_PORT" DB_PORT 5432)"
  [[ "$DB_PORT" =~ ^[0-9]+$ ]] && (( DB_PORT >= 1 && DB_PORT <= 65535 )) || die "DB_PORT must be between 1 and 65535."
  [[ "$DB_HOST" =~ ^[A-Za-z0-9._:%-]+$ ]] || die "DB_HOST contains unsupported characters."
  DB_PASSWORD="$(pick "$OPT_DB_PASSWORD" DB_PASSWORD "")"
  if [[ $EXTERNAL_DB -eq 1 && -z "$DB_PASSWORD" ]]; then
    [[ -t 0 && $ASSUME_YES -eq 0 ]] || die "Give the database password with --db-password."
    read -r -s -p "Password of $DB_USER on $DB_HOST: " DB_PASSWORD; echo
  fi
  [[ "$DB_NAME" =~ ^[a-z_][a-z0-9_]*$ && "$DB_USER" =~ ^[a-z_][a-z0-9_]*$ ]] \
    || die "Database and user names may only use lowercase letters, digits and underscores."
  [[ -n "$DB_PASSWORD" ]] || DB_PASSWORD="$(random_hex 24)"
  [[ "$DB_PASSWORD" =~ ^[A-Za-z0-9._~-]+$ ]] || die "Use only letters, digits and . _ ~ - in the database password (it is stored in an env file)."

  info "Host:      $APP_HOST  (FORCE_SSL=$FORCE_SSL)"
  info "Listening: $BIND_ADDRESS:$PORT  (proxy: $PROXY)"
  info "Ruby:      $RUBY_VERSION    Node (build only): $NODE_VERSION"
  if [[ $EXTERNAL_DB -eq 1 ]]; then info "Database:  $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME (existing server)"
  else info "Database:  PostgreSQL on this machine, database $DB_NAME"; fi
  confirm "Continue?" y || die "Stopped."
}

# ---------------------------------------------------------------------------------------------
# apt
# ---------------------------------------------------------------------------------------------
# Debian 11 reached its end of life: its repositories move to archive.debian.org.
fix_bullseye_apt() {
  [[ "$CODENAME" == bullseye && "${ID:-}" == debian ]] || return 0
  local helper="$SRC_DIR/../scripts/prepare-bullseye-archive.sh"
  [[ -f "$helper" ]] || die "Missing tested Bullseye archive helper: $helper"
  bash "$helper"

}

install_base_packages() {
  step "Installing system packages"
  fix_bullseye_apt
  apt-get update -qq || die "apt-get update failed. Check the network and /etc/apt/sources.list."
  # Build tools for Ruby and the gems, libraries Ruby links against, and everything the installer needs.
  apt_install ca-certificates curl gnupg git openssl rsync xz-utils tar patch file \
    build-essential autoconf bison pkg-config \
    libssl-dev zlib1g-dev libyaml-dev libffi-dev libreadline-dev libncurses-dev libgmp-dev libdb-dev libpq-dev libgdbm-dev uuid-dev \
    libjemalloc2 libatomic1
}

# ---------------------------------------------------------------------------------------------
# PostgreSQL
# ---------------------------------------------------------------------------------------------
PGDG_KEY=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc
PGDG_FPR=B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8

add_pgdg_repo() { # add_pgdg_repo BASE_URL
  install -d -m 0755 "$(dirname "$PGDG_KEY")"
  if [[ ! -s "$PGDG_KEY" ]]; then
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o "$PGDG_KEY.tmp"
    local fpr; fpr="$(gpg --show-keys --with-colons "$PGDG_KEY.tmp" | awk -F: '$1=="fpr" {print $10; exit}')"
    [[ "$fpr" == "$PGDG_FPR" ]] || { rm -f "$PGDG_KEY.tmp"; die "The PostgreSQL repository key has an unexpected fingerprint ($fpr)."; }
    mv "$PGDG_KEY.tmp" "$PGDG_KEY"
  fi
  local deb_arch opts; deb_arch="$(dpkg --print-architecture)"
  opts="arch=$deb_arch signed-by=$PGDG_KEY"
  # The archive's Release files are frozen and may be past their Valid-Until date.
  [[ "$1" == *apt-archive* ]] && opts+=" check-valid-until=no"
  echo "deb [$opts] $1 ${CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
}

pg_available() { # pg_available MAJOR: is postgresql-MAJOR installable?
  local cand; cand="$(apt-cache policy "postgresql-$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  [[ -n "$cand" && "$cand" != "(none)" ]]
}

choose_pg_version() {
  local wanted=("${OPT_PG_VERSION:-18}")
  [[ -n "$OPT_PG_VERSION" ]] || wanted+=(17)
  local repos=(https://apt.postgresql.org/pub/repos/apt)
  # Debian 11 left the main PostgreSQL repository and moved to the archive.
  [[ "$CODENAME" == bullseye ]] && repos=(https://apt-archive.postgresql.org/pub/repos/apt https://apt.postgresql.org/pub/repos/apt)

  local repo v
  for repo in "${repos[@]}"; do
    add_pgdg_repo "$repo"
    if ! apt-get update -qq 2>/dev/null; then rm -f /etc/apt/sources.list.d/pgdg.list; continue; fi
    for v in "${wanted[@]}"; do
      if pg_available "$v"; then PG_MAJOR="$v"; return 0; fi
    done
  done
  rm -f /etc/apt/sources.list.d/pgdg.list
  apt-get update -qq || true
  PG_MAJOR=""
  if [[ -n "$OPT_PG_VERSION" ]]; then die "PostgreSQL $OPT_PG_VERSION isn't available for ${CODENAME}."; fi
  warn "The PostgreSQL repository has no version 18 or 17 for ${CODENAME}. Using the PostgreSQL that Debian ships."
}

install_local_postgres() {
  step "Installing PostgreSQL"
  # Reuse a server that is already running for the chosen version; otherwise install one.
  choose_pg_version
  if [[ -n "$PG_MAJOR" ]]; then
    apt_install "postgresql-$PG_MAJOR" libpq-dev
  else
    apt_install postgresql libpq-dev
    PG_MAJOR="$(find /usr/lib/postgresql -mindepth 1 -maxdepth 1 -printf '%f\n' | sort -n | tail -n 1)"
  fi
  systemctl enable --now postgresql >/dev/null 2>&1 || true

  # The cluster port is not always 5432 (another cluster may have been there first).
  local line
  line="$(pg_lsclusters -h | awk -v v="$PG_MAJOR" '$1==v {print; exit}')"
  [[ -n "$line" ]] || die "PostgreSQL $PG_MAJOR was installed but has no cluster. Check: pg_lsclusters"
  DB_PORT="$(awk '{print $3}' <<<"$line")"
  if [[ "$(awk '{print $4}' <<<"$line")" != online ]]; then
    pg_ctlcluster "$PG_MAJOR" "$(awk '{print $2}' <<<"$line")" start || true
  fi

  for _ in $(seq 1 30); do pg_isready -q -h /var/run/postgresql -p "$DB_PORT" && break; sleep 1; done
  pg_isready -q -h /var/run/postgresql -p "$DB_PORT" || die "PostgreSQL doesn't answer on port $DB_PORT."
  ok "PostgreSQL $PG_MAJOR is running on port $DB_PORT"
}

# Run psql as the postgres superuser on the local cluster (peer authentication over the socket).
pg_super() { ( cd / && runuser -u postgres -- psql -X -q -p "$DB_PORT" -v ON_ERROR_STOP=1 "$@" ); }

provision_local_database() {
  step "Creating the database and user"
  local enc dbopts=""
  enc="$(pg_super -d template1 -Atc "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = 'template1'")"
  # A cluster made under the C/POSIX locale is SQL_ASCII; Sherlock needs UTF8.
  if [[ "$enc" != UTF8 ]]; then
    dbopts="TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8'"
  fi
  # On a first install, never adopt an unrelated database or alter an existing role.
  if (( EXISTING_INSTALL == 0 )); then
    if pg_super -d postgres -Atc "SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER'" | grep -q 1; then
      die "Database role $DB_USER already exists; refusing to alter an unrelated role."
    fi
    if pg_super -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1; then
      die "Database $DB_NAME already exists; refusing to modify an unrelated database."
    fi
  fi
  # The password goes in through stdin (\set), not the command line, so `ps` never shows it.
  pg_super -d postgres -v dbopts="$dbopts" <<SQL
\set u '$DB_USER'
\set pw '$DB_PASSWORD'
\set db '$DB_NAME'
SELECT format('CREATE ROLE %I LOGIN', :'u')
 WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'u') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'u', :'pw') \gexec
SELECT format('CREATE DATABASE %I OWNER %I %s', :'db', :'u', :'dbopts')
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db') \gexec
SQL
  ok "Database $DB_NAME, user $DB_USER"
}

# psql as the app's database user, over TCP like the app does.
db_psql() {
  PGPASSWORD="$DB_PASSWORD" PGCONNECT_TIMEOUT=10 \
    psql -X -q -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 "$@"
}

check_db_connection() {
  db_psql -Atc "SELECT 1" >/dev/null 2>&1 \
    || die "Can't log in to $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME. Check the host, user, password and pg_hba.conf."
  local ver; ver="$(db_psql -Atc "SHOW server_version_num")"
  DB_SERVER_MAJOR=$(( ver / 10000 ))
  info "Connected to PostgreSQL $DB_SERVER_MAJOR"
  (( DB_SERVER_MAJOR >= 14 )) || warn "PostgreSQL $DB_SERVER_MAJOR is old (Sherlock is built and tested on 18). It may work, but upgrade when you can."
}

# db/structure.sql is dumped by PostgreSQL 18 and starts with "SET transaction_timeout", which
# PostgreSQL 16 and older refuse. On such servers, load the file once without that line; after
# that, normal migrations (db:prepare) work the same on every version.
load_schema_for_old_postgres() {
  (( DB_SERVER_MAJOR < 17 )) || return 0
  local present
  present="$(db_psql -Atc "SELECT to_regclass('sherlockdb.schema_migrations') IS NOT NULL")"
  [[ "$present" == t ]] && return 0
  info "PostgreSQL $DB_SERVER_MAJOR: loading the schema without the PostgreSQL 17+ setting"
  sed '/^SET transaction_timeout = 0;$/d' "$SRC_DIR/db/structure.sql" | db_psql -f - >/dev/null
}

# ---------------------------------------------------------------------------------------------
# Users, folders, settings file
# ---------------------------------------------------------------------------------------------
create_user_and_dirs() {
  step "Creating the $APP_USER user and folders"
  getent group "$APP_USER" >/dev/null 2>&1 || groupadd --system "$APP_USER"
  if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --gid "$APP_USER" --home-dir "$APP_HOME" --create-home --shell /usr/sbin/nologin "$APP_USER"
  else
    usermod --append --groups "$APP_USER" "$APP_USER"
  fi
  install -d -o "$APP_USER" -g "$APP_USER" -m 0750 "$APP_HOME"
  install -d -m 0755 "$CONF_DIR"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0700 "$CRED_DIR"
  install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "$INSTALL_DIR"
}

write_env_file() {
  step "Writing $ENV_FILE"
  local tmp; tmp="$(mktemp)"
  # The worker metrics endpoint is private regardless of the web proxy mode.
  local metrics_bind=127.0.0.1
  {
    echo "# Managed by deploy/install.sh. Values below the marker are yours and are kept on updates."
    echo "# After editing: sudo systemctl restart $SERVICE"
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
    echo "SOLID_QUEUE_IN_PUMA=true"
    echo "METRICS_BIND=$metrics_bind"
    echo "# --- your own settings (RAILS_LOG_LEVEL, JOB_CONCURRENCY, METRICS_PORT, ...) ---"
    if [[ -f "$ENV_FILE" ]]; then
      grep -vE '^(# Managed by deploy|# After editing|# --- your own|$|(RAILS_ENV|APP_HOST|FORCE_SSL|PORT|BIND_ADDRESS|DB_HOST|DB_PORT|DB_NAME|DB_USER|DB_PASSWORD|SOLID_QUEUE_IN_PUMA|METRICS_BIND)=)' "$ENV_FILE" || true
    fi
  } > "$tmp"
  install -o root -g "$APP_USER" -m 0640 "$tmp" "$ENV_FILE"
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------------------------
# Ruby and Node
# ---------------------------------------------------------------------------------------------
install_ruby() {
  step "Ruby $RUBY_VERSION"
  RUBY_DIR="$RUBIES_DIR/$RUBY_VERSION"
  if [[ -x "$RUBY_DIR/bin/ruby" && "$("$RUBY_DIR/bin/ruby" -e 'print RUBY_VERSION')" == "$RUBY_VERSION" ]]; then
    ok "Already built in $RUBY_DIR"
  else
    RUBY_BUILD_TAG=v20261023
    RUBY_BUILD_COMMIT=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92
    if [[ -d "$RUBY_BUILD_DIR/.git" ]]; then
      git -C "$RUBY_BUILD_DIR" fetch -q --depth 1 origin "refs/tags/$RUBY_BUILD_TAG:refs/tags/$RUBY_BUILD_TAG"
      git -C "$RUBY_BUILD_DIR" checkout -q --detach "$RUBY_BUILD_TAG"
    else
      git clone -q --depth 1 --branch "$RUBY_BUILD_TAG" https://github.com/rbenv/ruby-build.git "$RUBY_BUILD_DIR"
    fi
    local ruby_build_commit
    ruby_build_commit="$(git -C "$RUBY_BUILD_DIR" rev-parse HEAD)"
    [[ "$ruby_build_commit" == "$RUBY_BUILD_COMMIT" ]] \
      || die "ruby-build $RUBY_BUILD_TAG commit mismatch: $ruby_build_commit"
    "$RUBY_BUILD_DIR/bin/ruby-build" --definitions | grep -qx "$RUBY_VERSION" \
      || die "ruby-build doesn't know Ruby $RUBY_VERSION. Check --ruby-version."
    info "Compiling Ruby. This takes 5 to 15 minutes."
    install -d "$RUBIES_DIR"
    RUBY_CONFIGURE_OPTS="--disable-install-doc" \
      "$RUBY_BUILD_DIR/bin/ruby-build" --verbose "$RUBY_VERSION" "$RUBY_DIR" > "/var/log/sherlock-ruby-build.log" 2>&1 \
      || { tail -n 30 /var/log/sherlock-ruby-build.log >&2; die "Building Ruby failed. Full log: /var/log/sherlock-ruby-build.log"; }
    ok "Ruby $RUBY_VERSION installed in $RUBY_DIR"
  fi
  APP_PATH_PREFIX="$RUBY_DIR/bin:"
}

# Node.js is only needed to bundle the JavaScript. Use the official binary in a temporary folder,
# so Debian's old nodejs package and the system stay untouched.
NODE_TMP=""
fetch_node() {
  NODE_TMP="$(mktemp -d /var/tmp/sherlock-node.XXXXXX)"
  chmod 755 "$NODE_TMP"
  local name="node-v${NODE_VERSION}-linux-${ARCH}"
  local base="https://nodejs.org/dist/v${NODE_VERSION}"
  info "Downloading Node.js $NODE_VERSION (build only)"
  curl -fsSL "$base/$name.tar.xz" -o "$NODE_TMP/$name.tar.xz" \
    || die "Couldn't download $base/$name.tar.xz. Check --node-version."
  curl -fsSL "$base/SHASUMS256.txt" -o "$NODE_TMP/SHASUMS256.txt"
  ( cd "$NODE_TMP" && grep " $name.tar.xz\$" SHASUMS256.txt | sha256sum -c --quiet - ) \
    || die "The Node.js download doesn't match its checksum."
  tar -xJf "$NODE_TMP/$name.tar.xz" -C "$NODE_TMP"
  NODE_BIN="$NODE_TMP/$name/bin"
  "$NODE_BIN/node" --version | grep -Fx "v$NODE_VERSION" >/dev/null \
    || die "Node.js runtime version check failed (expected v$NODE_VERSION)."
  chmod -R a+rX "$NODE_TMP"
}
cleanup_node() {
  if [[ -n "$NODE_TMP" ]]; then rm -rf "$NODE_TMP"; fi
  NODE_TMP=""
}
trap cleanup_node EXIT

# ---------------------------------------------------------------------------------------------
# The app
# ---------------------------------------------------------------------------------------------
sync_source() {
  step "Copying the app to $INSTALL_DIR"
  # Never replace an unexpected file or recursively delete a real credentials directory.
  if [[ -e "$INSTALL_DIR/config/credentials" && ! -L "$INSTALL_DIR/config/credentials" && ! -d "$INSTALL_DIR/config/credentials" ]]; then
    die "$INSTALL_DIR/config/credentials exists but is not a directory or managed symlink; refusing to replace it."
  fi
  # A real credentials directory may contain keys from a manual/older install.
  # Never recursively delete it; require the operator to migrate or back it up.
  if [[ -d "$INSTALL_DIR/config/credentials" && ! -L "$INSTALL_DIR/config/credentials" ]]; then
    if find "$INSTALL_DIR/config/credentials" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
      die "$INSTALL_DIR/config/credentials is a non-empty real directory. Back up/migrate its contents to $CRED_DIR before retrying."
    fi
    rmdir "$INSTALL_DIR/config/credentials"
  fi

  if [[ "$(realpath "$SRC_DIR")" != "$(realpath "$INSTALL_DIR")" ]]; then
    rsync -a --delete \
      --exclude '/.git' --exclude '/.forgejo' --exclude '/.bundle' \
      --exclude '/.sherlock-native-install' \
      --exclude '/node_modules' --exclude '/vendor/bundle' \
      --exclude '/tmp' --exclude '/log' --exclude '/config/credentials' \
      --exclude '/public/assets' --exclude '/app/assets/builds' \
      "$SRC_DIR/" "$INSTALL_DIR/"
  fi
  install -d "$INSTALL_DIR/tmp/pids" "$INSTALL_DIR/tmp/cache" "$INSTALL_DIR/log" "$INSTALL_DIR/app/assets/builds"
  # Production credentials live outside the application tree.
  ln -sfn "$CRED_DIR" "$INSTALL_DIR/config/credentials"

  # Same bundler settings the Dockerfile uses, in the app's own config so the service sees them too.
  install -d "$INSTALL_DIR/.bundle"
  cat > "$INSTALL_DIR/.bundle/config" <<EOF
---
BUNDLE_DEPLOYMENT: "true"
BUNDLE_PATH: "vendor/bundle"
BUNDLE_WITHOUT: "development:test"
EOF
  chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
  printf 'managed_by=sherlock-deploy/install.sh\\n' > "$INSTALL_DIR/.sherlock-native-install"
  chown root:"$APP_USER" "$INSTALL_DIR/.sherlock-native-install"
  chmod 0640 "$INSTALL_DIR/.sherlock-native-install"
}

build_app() {
  step "Installing gems"
  fetch_node
  in_app_build() { ( cd "$INSTALL_DIR"; as_app env RAILS_ENV=production "$@" ); }
  APP_PATH_PREFIX="$RUBY_DIR/bin:$NODE_BIN:"

  # The lockfile pins the bundler version; install it where the app user can't (and needn't) write.
  local bundler_version
  bundler_version="$(awk '/^BUNDLED WITH/ {getline; gsub(/ /, ""); print; exit}' "$INSTALL_DIR/Gemfile.lock")"
  if [[ -n "$bundler_version" ]]; then
    "$RUBY_DIR/bin/gem" install bundler -v "$bundler_version" --no-document >/dev/null
  fi

  in_app_build bundle install --jobs "$(nproc)" \
    || die "bundle install failed. A missing system library is the usual cause; read the error above."
  in_app_build bundle exec bootsnap precompile --gemfile >/dev/null 2>&1 || warn "bootsnap precompile of gems skipped."

  step "Building JavaScript and CSS"
  in_app_build npm ci --no-audit --no-fund --loglevel=error
  in_app_build env SECRET_KEY_BASE_DUMMY=1 APP_HOST=build.invalid ./bin/rails assets:precompile \
    || die "assets:precompile failed."
  in_app_build bundle exec bootsnap precompile app/ lib/ >/dev/null 2>&1 || warn "bootsnap precompile of the app skipped."
  rm -rf "$INSTALL_DIR/node_modules"
  cleanup_node
  APP_PATH_PREFIX="$RUBY_DIR/bin:"
  chown -R "$APP_USER:$APP_USER" "$INSTALL_DIR"
}

# Same steps as the README's Docker setup, minus Docker.
create_credentials() {
  step "Credentials"
  if [[ -f "$CRED_DIR/production.yml.enc" && -f "$CRED_DIR/production.key" ]]; then
    ok "Already there in $CRED_DIR (kept)"
    return
  fi
  if [[ -f "$CRED_DIR/production.yml.enc" && ! -f "$CRED_DIR/production.key" ]]; then
    die "$CRED_DIR/production.yml.enc exists but production.key is missing. Restore the key from your backup. A new key can't read the old file."
  fi
  local tmp; tmp="$(mktemp -p "$CRED_DIR" .new-credentials.XXXXXX)"
  chown "$APP_USER:$APP_USER" "$tmp"; chmod 600 "$tmp"
  (
    cd "$INSTALL_DIR"
    export RAILS_ENV=production APP_HOST=setup
    { echo "secret_key_base: $(as_app ./bin/rails secret)"
      as_app ./bin/rails db:encryption:init | tail -n 4
    } > "$tmp"
    EDITOR="cp $tmp" as_app ./bin/rails credentials:edit --environment production >/dev/null
  )
  rm -f "$tmp"
  [[ -f "$CRED_DIR/production.key" && -f "$CRED_DIR/production.yml.enc" ]] || die "Creating the credentials failed."
  chmod 600 "$CRED_DIR"/production.key "$CRED_DIR"/production.yml.enc
  ok "Created $CRED_DIR/production.key and production.yml.enc"
  warn "Back up $CRED_DIR/production.key now. Without it the saved API keys can't be decrypted."
}

prepare_database() {
  step "Preparing the database"
  check_db_connection
  load_schema_for_old_postgres
  in_app ./bin/rails db:prepare db:seed
}

# ---------------------------------------------------------------------------------------------
# systemd, helper command, nginx
# ---------------------------------------------------------------------------------------------
install_service() {
  step "Installing the systemd service"
  local preload=""
  [[ -e "/usr/lib/$MULTIARCH/libjemalloc.so.2" ]] && preload="Environment=LD_PRELOAD=/usr/lib/$MULTIARCH/libjemalloc.so.2"
  cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Sherlock (private tracker stats)
Documentation=file://$INSTALL_DIR/README.md
After=network-online.target postgresql.service
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
Environment=LANG=C.UTF-8
Environment=PATH=$RUBY_DIR/bin:/usr/local/bin:/usr/bin:/bin
$preload
# Creates or migrates the database and refreshes the tracker list, like the Docker entrypoint.
ExecStartPre=$INSTALL_DIR/bin/rails db:prepare db:seed
ExecStart=$INSTALL_DIR/bin/rails server -b \${BIND_ADDRESS} -p \${PORT}
Restart=on-failure
RestartSec=5
TimeoutStartSec=600
TimeoutStopSec=60
LimitNOFILE=65536
SyslogIdentifier=$SERVICE

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "/etc/systemd/system/$SERVICE.service"

  cat > /usr/local/bin/sherlock-ctl <<EOF
#!/usr/bin/env bash
# Helper for the native Sherlock install.
#   sherlock-ctl status | start | stop | restart | logs
#   sherlock-ctl rails ARGS...     e.g.  sherlock-ctl rails 'users:reset_password[alice]'
set -euo pipefail
cmd="\${1:-help}"; shift || true
case "\$cmd" in
  status|start|stop|restart) exec systemctl "\$cmd" $SERVICE ;;
  logs)    exec journalctl -u $SERVICE -n 200 -f "\$@" ;;
  rails)
    [[ \$EUID -eq 0 ]] || exec sudo "\$0" rails "\$@"
    cd $INSTALL_DIR
    set -a; . $ENV_FILE; set +a
    exec runuser -u $APP_USER -- env HOME=$APP_HOME LANG=C.UTF-8 PATH="$RUBY_DIR/bin:\$PATH" ./bin/rails "\$@" ;;
  *) sed -n '2,4p' "\$0"; exit 1 ;;
esac
EOF
  chmod 755 /usr/local/bin/sherlock-ctl
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null 2>&1
}

setup_nginx() {
  [[ "$PROXY" == nginx ]] || return 0
  step "Setting up nginx"
  apt_install nginx
  local conf=/etc/nginx/sites-available/$SERVICE
  local conflict_checker="$SRC_DIR/../scripts/check-nginx-host-conflict.sh"
  [[ -f "$conflict_checker" ]] || die "Missing Nginx hostname conflict checker: $conflict_checker"
  local -a nginx_scan_paths=()
  local candidate
  for candidate in /etc/nginx/sites-enabled/* /etc/nginx/conf.d/*; do
    [[ -e "$candidate" || -L "$candidate" ]] || continue
    [[ "$candidate" == "/etc/nginx/sites-enabled/$SERVICE" || "$candidate" == /etc/nginx/conf.d/sherlock-upgrade.conf ]] && continue
    nginx_scan_paths+=("$candidate")
  done
  if (( ${#nginx_scan_paths[@]} > 0 )) && bash "$conflict_checker" "${APP_HOST%%:*}" "${nginx_scan_paths[@]}"; then
    die "An existing Nginx virtual host already declares ${APP_HOST%%:*}; refusing a duplicate server_name."
  fi
  if [[ -e "$conf" ]] && ! grep -qE '^# Written by deploy/install\.sh|managed by Certbot' "$conf"; then
    die "$conf already exists and is not managed by this installer; refusing to overwrite it."
  fi
  if [[ -e /etc/nginx/conf.d/sherlock-upgrade.conf ]] && ! grep -q 'Lets WebSocket connections' /etc/nginx/conf.d/sherlock-upgrade.conf; then
    die "/etc/nginx/conf.d/sherlock-upgrade.conf already exists and is not managed by this installer."
  fi
  if [[ -f "$conf" ]] && grep -q "managed by Certbot" "$conf"; then
    ok "The nginx site was extended by Certbot; leaving it alone."
  else
    cat > /etc/nginx/conf.d/sherlock-upgrade.conf <<'EOF'
# Lets WebSocket connections (Turbo Streams) through the proxy.
map $http_upgrade $sherlock_connection_upgrade {
  default upgrade;
  ''      close;
}
EOF
    local listen6=""
    [[ -e /proc/net/if_inet6 ]] && listen6="listen [::]:80;"
    cat > "$conf" <<EOF
# Written by deploy/install.sh
server {
  listen 80;
  $listen6
  server_name ${APP_HOST%%:*};

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

  if [[ -n "$OPT_LE_EMAIL" ]]; then
    step "Getting an HTTPS certificate"
    apt_install certbot python3-certbot-nginx
    certbot --nginx -d "${APP_HOST%%:*}" -m "$OPT_LE_EMAIL" --agree-tos --no-eff-email --redirect -n \
      || die "Let's Encrypt certificate issuance failed. Check DNS and inbound TCP 80/443, then rerun the installer or issue the certificate manually."
  elif [[ "$FORCE_SSL" == true ]]; then
    warn "FORCE_SSL is on but no certificate was set up: browsers won't keep the login over plain HTTP."
    warn "Re-run with --letsencrypt you@example.com, add TLS yourself, or use --no-ssl on a private network."
  fi
}

start_service() {
  step "Starting Sherlock"
  systemctl restart "$SERVICE"
  for _ in $(seq 1 90); do
    if curl -fs -o /dev/null -m 3 "http://127.0.0.1:$PORT/up"; then
      ok "Sherlock answers on http://127.0.0.1:$PORT/up"
      return 0
    fi
    systemctl is-active --quiet "$SERVICE" || break
    sleep 2
  done
  journalctl -u "$SERVICE" -n 40 --no-pager >&2 || true
  die "Sherlock didn't come up. Logs: journalctl -u $SERVICE -e"
}

summary() {
  local scheme=http
  [[ "$FORCE_SSL" == true ]] && scheme=https
  local APP_URL="$scheme://$APP_HOST"
  if [[ "$PROXY" == none && "$FORCE_SSL" == false ]]; then APP_URL="http://${APP_HOST%%:*}:$PORT"; fi
  cat <<EOF

${C_GRN}${C_BOLD}Sherlock is installed.${C_OFF}

  Open:          $APP_URL   (the first account you create becomes the admin)
  Settings:      $ENV_FILE   (then: sudo systemctl restart $SERVICE)
  Logs:          sudo sherlock-ctl logs
  Status:        sudo sherlock-ctl status
  Lost admin?    sudo sherlock-ctl rails 'users:reset_password[username]'
  Update:        unpack the new version, then run its deploy/install.sh again (no options needed)

  ${C_BOLD}Back up $CRED_DIR/production.key${C_OFF}: without it the saved API keys can't be decrypted.
EOF
  if [[ "$PROXY" == none ]]; then
    echo "  Sherlock listens on 0.0.0.0:$PORT. Put a reverse proxy with HTTPS in front, or firewall the port."
  fi
}

main() {
  parse_args "$@"
  preflight
  resolve_settings
  install_base_packages
  create_user_and_dirs
  if [[ $EXTERNAL_DB -eq 1 ]]; then
    apt_install postgresql-client libpq-dev
  else
    install_local_postgres
    provision_local_database
  fi
  write_env_file
  install_ruby
  sync_source
  build_app
  create_credentials
  prepare_database
  install_service
  setup_nginx
  start_service
  summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
