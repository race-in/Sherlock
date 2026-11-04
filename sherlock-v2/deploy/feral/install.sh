#!/usr/bin/env bash
# Fail-closed, rootless installer for Feral Debian 9 slots.
set -Eeuo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${SHERLOCK_HOME:-$HOME/.local/opt/sherlock}"
CONF_DIR="${SHERLOCK_CONFIG_DIR:-$HOME/.config/sherlock-feral}"
STATE_DIR="${SHERLOCK_STATE_DIR:-$HOME/.local/var/sherlock-feral}"
ENV_FILE="$CONF_DIR/sherlock.env"

DOMAIN=""
PORT=18443
DB_HOST=""
DB_PORT=5432
DB_NAME=""
DB_USER=""
DB_PASSWORD=""

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
usage() {
  cat <<'EOF'
Usage: bash deploy/feral/install.sh --domain HOST --db-host HOST --db-name NAME --db-user USER [options]
  --domain HOST       Public subdomain (required)
  --port PORT         Local Puma port (default 18443)
  --db-host HOST      External PostgreSQL hostname (required)
  --db-port PORT      PostgreSQL port (default 5432)
  --db-name NAME      Database name (required)
  --db-user USER      Database username (required)
  --db-password PASS  Database password (prompted if omitted)
EOF
}
while (($#)); do
  case "$1" in
    --domain) DOMAIN="${2:?missing domain}"; shift 2 ;;
    --port) PORT="${2:?missing port}"; shift 2 ;;
    --db-host) DB_HOST="${2:?missing DB host}"; shift 2 ;;
    --db-port) DB_PORT="${2:?missing DB port}"; shift 2 ;;
    --db-name) DB_NAME="${2:?missing DB name}"; shift 2 ;;
    --db-user) DB_USER="${2:?missing DB user}"; shift 2 ;;
    --db-password) DB_PASSWORD="${2:?missing DB password}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "A valid --domain is required."
[[ "$PORT" =~ ^[0-9]+$ ]] && ((PORT > 1024 && PORT < 65536)) || die "Port must be 1025..65535."
[[ -n "$DB_HOST" && -n "$DB_NAME" && -n "$DB_USER" ]] || die "--db-host, --db-name and --db-user are required."
[[ "$DB_PORT" =~ ^[0-9]+$ ]] && ((DB_PORT > 0 && DB_PORT < 65536)) || die "Invalid database port."
[[ "$DB_PASSWORD" ]] || { read -r -s -p "External PostgreSQL password: " DB_PASSWORD; printf '\n'; }
[[ "$DB_HOST" =~ ^[A-Za-z0-9._:-]+$ ]] || die "Invalid database hostname."
[[ "$DB_NAME" =~ ^[A-Za-z0-9_]+$ ]] || die "Database name may contain only letters, digits and underscores."
[[ "$DB_USER" =~ ^[A-Za-z0-9_.-]+$ ]] || die "Invalid database username."
[[ -n "$DB_PASSWORD" ]] || die "Database password cannot be empty."

[[ $EUID -ne 0 ]] || die "Do not run this installer as root or with sudo."
[[ -f "$SRC_DIR/Gemfile" && -f "$SRC_DIR/config/application.rb" ]] || die "Run from a Sherlock source checkout."
[[ "$(uname -s)" == Linux ]] || die "Feral deployment requires Linux."
[[ -r /etc/os-release ]] || die "Cannot identify operating system."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 9* ]] ||
  die "Expected Debian 9 (Stretch); found ${PRETTY_NAME:-unknown}. This branch targets the Feral Debian 9 slot."

info "Checking rootless runtime prerequisites"
command -v ruby >/dev/null || die "Ruby >= 3.2 is required. Debian 9 system Ruby is too old; install a private runtime first."
ruby -e 'require "rubygems"; abort "Ruby >= 3.2 required" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2.0")' ||
  die "Ruby >= 3.2 is required."
ruby -ropenssl -e 'v=OpenSSL::OPENSSL_VERSION[/\d+\.\d+\.\d+/].split(".").map(&:to_i); abort "OpenSSL >= 1.1.1 required" if v < [1,1,1]' ||
  die "Ruby must be linked against OpenSSL >= 1.1.1 (not Debian 9 system OpenSSL 1.0.2)."
command -v bundle >/dev/null || die "Bundler is missing for this Ruby."
command -v pg_config >/dev/null || die "PostgreSQL development/client libraries (pg_config) are required."
command -v pg_isready >/dev/null || die "pg_isready is required to verify the external database before changing files."
command -v git >/dev/null || die "git is required."
command -v curl >/dev/null || die "curl is required."
command -v sha256sum >/dev/null || die "sha256sum is required."

info "Checking PostgreSQL connectivity"
PGPASSWORD="$DB_PASSWORD" pg_isready -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" >/dev/null ||
  die "PostgreSQL is not accepting connections at $DB_HOST:$DB_PORT/$DB_NAME."

info "Checking available disk space and target paths"
mkdir -p "$(dirname "$APP_DIR")" "$CONF_DIR" "$STATE_DIR"
[[ -w "$(dirname "$APP_DIR")" && -w "$CONF_DIR" && -w "$STATE_DIR" ]] || die "Application/config/state paths must be writable."
if [[ -e "$APP_DIR" && ! -f "$APP_DIR/.sherlock-feral-install" ]]; then
  die "$APP_DIR exists but is not marked as a Feral Sherlock installation; refusing to overwrite it."
fi

info "Installing Ruby dependencies"
cd "$SRC_DIR"
export BUNDLE_WITHOUT="development:test"
export BUNDLE_FORCE_RUBY_PLATFORM=true
export BUNDLE_APP_CONFIG="$CONF_DIR/bundle"
mkdir -p "$BUNDLE_APP_CONFIG"
bundle config set --local path "$HOME/.local/share/sherlock-feral/bundle"
bundle install

info "Building frontend assets"
if [[ ! -d "$SRC_DIR/public/assets" || -z "$(find "$SRC_DIR/public/assets" -type f -print -quit 2>/dev/null)" ]]; then
  command -v node >/dev/null || die "Precompiled public/assets are absent and Node.js is unavailable. Build assets on a compatible machine and deploy them with the source."
  command -v npm >/dev/null || die "npm is required to build frontend assets."
  npm ci
  npm run build
  SECRET_KEY_BASE_DUMMY=1 APP_HOST="$DOMAIN" RAILS_ENV=production bundle exec rails assets:precompile
fi

info "Preparing application directory"
mkdir -p "$APP_DIR"
# Preserve user data and env/config outside the app tree; replace only tracked application files.
tar -C "$SRC_DIR" --exclude='./.git' --exclude='./node_modules' --exclude='./tmp' -cf - . |
  tar -C "$APP_DIR" -xf -
touch "$APP_DIR/.sherlock-feral-install"
mkdir -p "$APP_DIR/tmp/pids" "$APP_DIR/log"

if [[ ! -f "$ENV_FILE" ]]; then
  umask 077
  cat > "$ENV_FILE" <<EOF
RAILS_ENV=production
RAILS_LOG_LEVEL=info
APP_HOST=$DOMAIN
PORT=$PORT
BINDING=127.0.0.1
FORCE_SSL=true
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$(printf '%q' "$DB_PASSWORD")
RAILS_MASTER_KEY=$(openssl rand -hex 16)
SECRET_KEY_BASE=$(openssl rand -hex 64)
EOF
  chmod 600 "$ENV_FILE"
else
  chmod 600 "$ENV_FILE"
  echo "Existing environment file preserved: $ENV_FILE"
fi

info "Running database migrations"
(
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  cd "$APP_DIR"
  export RAILS_ENV=production
  bundle exec rails db:prepare
)

info "Installation files are ready"
echo "Application: $APP_DIR"
echo "Environment: $ENV_FILE"
echo "Controller:  $APP_DIR/deploy/feral/control.sh"
echo "Before starting: set RAILS_MASTER_KEY in $ENV_FILE (chmod 600), then configure the Feral proxy."
