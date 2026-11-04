#!/usr/bin/env bash
# Fail-closed, rootless installer for Feral Debian 9 slots.
set -Eeuo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="${SHERLOCK_HOME:-$HOME/.local/opt/sherlock}"
CONF_DIR="${SHERLOCK_CONFIG_DIR:-$HOME/.config/sherlock-feral}"
STATE_DIR="${SHERLOCK_STATE_DIR:-$HOME/.local/var/sherlock-feral}"
ENV_FILE="$CONF_DIR/sherlock.env"
CRED_DIR="$CONF_DIR/credentials"
RUNTIME_PREFIX="${SHERLOCK_RUNTIME_PREFIX:-$HOME/.local/opt/sherlock-runtime}"
NODE_BIN="$RUNTIME_PREFIX/node/node-v22.21.1-linux-x64-glibc-217/bin"

DOMAIN=""
PORT=18443
DB_HOST=""
DB_PORT=5432
DB_NAME=""
DB_USER=""
DB_PASSWORD="${SHERLOCK_DB_PASSWORD:-}"
PGSSLMODE="${SHERLOCK_PGSSLMODE:-require}"

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
  SHERLOCK_DB_PASSWORD may be set to avoid an interactive prompt (keep it out of shell history).
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

[[ $EUID -ne 0 ]] || die "Do not execute this installer as the superuser."
[[ -f "$SRC_DIR/Gemfile" && -f "$SRC_DIR/config/application.rb" ]] || die "Run from a Sherlock source checkout."
CURRENT_BRANCH="$(git -C "$SRC_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[[ "$CURRENT_BRANCH" == "feature/feral-rootless-edition" ]] ||
  die "Install only from feature/feral-rootless-edition (current checkout: ${CURRENT_BRANCH:-detached/unknown})."
[[ "$(uname -s)" == Linux ]] || die "Feral deployment requires Linux."
[[ -r /etc/os-release ]] || die "Cannot identify operating system."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 9* ]] ||
  die "Expected Debian 9 (Stretch); found ${PRETTY_NAME:-unknown}. This branch targets the Feral Debian 9 slot."

info "Checking rootless runtime prerequisites"
[[ -x "$RUNTIME_PREFIX/bin/ruby" ]] || die "Private runtime missing. Run bash ./deploy/feral/bootstrap-runtime.sh first."
export RUSTUP_HOME="$RUNTIME_PREFIX/rustup" CARGO_HOME="$RUNTIME_PREFIX/cargo"
export PATH="$RUNTIME_PREFIX/bin:$NODE_BIN:$CARGO_HOME/bin:$PATH"
export LD_LIBRARY_PATH="$RUNTIME_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export CARGO_BUILD_JOBS="${SHERLOCK_BUILD_JOBS:-2}"
command -v cargo >/dev/null || die "Private Rust/Cargo runtime missing. Re-run bootstrap-runtime.sh."
LIBCLANG_PATH="$(ruby -rlibclang -e 'puts File.dirname(Libclang.path)' 2>/dev/null)" || die "Private libclang gem missing. Re-run bootstrap-runtime.sh."
export LIBCLANG_PATH
export BUNDLE_APP_CONFIG="$CONF_DIR/bundle"
command -v ruby >/dev/null || die "Ruby >= 3.2 is required. Debian 9 system Ruby is too old; install a private runtime first."
ruby -e 'require "rubygems"; abort "Ruby >= 3.2 required" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.2.0")' ||
  die "Ruby >= 3.2 is required."
ruby -ropenssl -e 'v=OpenSSL::OPENSSL_VERSION[/\d+\.\d+\.\d+/].split(".").map(&:to_i); abort "OpenSSL >= 1.1.1 required" if v < [1,1,1]' ||
  die "Ruby must be linked against OpenSSL >= 1.1.1 (not Debian 9 system OpenSSL 1.0.2)."
command -v bundle >/dev/null || die "Bundler is missing for this Ruby."
command -v pg_config >/dev/null || die "PostgreSQL development/client libraries (pg_config) are required."
command -v pg_isready >/dev/null || die "pg_isready is required to verify the external database before changing files."
command -v psql >/dev/null || die "psql is required to authenticate and provision the application schema."
[[ "$PGSSLMODE" =~ ^(disable|allow|prefer|require|verify-ca|verify-full)$ ]] || die "Invalid SHERLOCK_PGSSLMODE value."
command -v git >/dev/null || die "git is required."
command -v curl >/dev/null || die "curl is required."
command -v sha256sum >/dev/null || die "sha256sum is required."
command -v npm >/dev/null || die "Private Node.js/npm runtime missing. Re-run bootstrap-runtime.sh."

info "Authenticating to PostgreSQL and preparing the Sherlock schema"
export PGSSLMODE
export PGPASSWORD="$DB_PASSWORD"
PGCONNECT_TIMEOUT=10 psql --no-psqlrc --set=ON_ERROR_STOP=1 \
  --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" --dbname="$DB_NAME" \
  --command='CREATE SCHEMA IF NOT EXISTS sherlockdb AUTHORIZATION CURRENT_USER;' >/dev/null || \
  die "Could not authenticate or create schema sherlockdb. Check DB credentials, SSL, and schema privileges."
psql --no-psqlrc --set=ON_ERROR_STOP=1 \
  --host="$DB_HOST" --port="$DB_PORT" --username="$DB_USER" --dbname="$DB_NAME" \
  --tuples-only --no-align \
  --command="SELECT CASE WHEN has_schema_privilege(current_user, 'sherlockdb', 'USAGE') AND has_schema_privilege(current_user, 'sherlockdb', 'CREATE') THEN 'ok' ELSE 'missing' END;" |
  grep -qx 'ok' || die "Database role $DB_USER lacks USAGE/CREATE on schema sherlockdb. Fix schema ownership/permissions before installing."
unset PGPASSWORD

info "Checking available disk space and target paths"
umask 077
mkdir -p "$(dirname "$APP_DIR")" "$CONF_DIR" "$STATE_DIR"
chmod 700 "$CONF_DIR" "$STATE_DIR"
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

info "Preparing application directory"
mkdir -p "$APP_DIR"
# Preserve user data and env/config outside the app tree; replace only tracked application files.
tar -C "$SRC_DIR" --exclude='./.git' --exclude='./node_modules' --exclude='./tmp' -cf - . |
  tar -C "$APP_DIR" -xf -
touch "$APP_DIR/.sherlock-feral-install"
mkdir -p "$APP_DIR/tmp/pids" "$APP_DIR/log" "$CRED_DIR"
chmod 700 "$CRED_DIR"
if [[ -e "$APP_DIR/config/credentials" && ! -L "$APP_DIR/config/credentials" ]]; then
  [[ -d "$APP_DIR/config/credentials" ]] || die "$APP_DIR/config/credentials is not a directory or managed symlink."
  if find "$APP_DIR/config/credentials" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    die "$APP_DIR/config/credentials contains files. Back them up/migrate them to $CRED_DIR before retrying."
  fi
  rmdir "$APP_DIR/config/credentials"
fi
ln -sfn "$CRED_DIR" "$APP_DIR/config/credentials"

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
EOF
  chmod 600 "$ENV_FILE"
else
  chmod 600 "$ENV_FILE"
  if ! grep -q '^PGSSLMODE=' "$ENV_FILE"; then
    printf 'PGSSLMODE=%s\n' "$PGSSLMODE" >> "$ENV_FILE"
  fi
  echo "Existing environment file preserved: $ENV_FILE"
fi

info "Preparing encrypted Rails production credentials"
if [[ ! -s "$CRED_DIR/production.yml.enc" || ! -s "$CRED_DIR/production.key" ]]; then
  [[ ! -s "$CRED_DIR/production.yml.enc" && ! -s "$CRED_DIR/production.key" ]] ||
    die "Incomplete Rails credentials pair in $CRED_DIR. Restore both files from backup."
  CRED_TMP="$(mktemp "$CONF_DIR/credentials.XXXXXX")"
  chmod 600 "$CRED_TMP"
  (
    cd "$APP_DIR"
    set -a; . "$ENV_FILE"; set +a
    export RAILS_ENV=production APP_HOST=setup
    {
      echo "secret_key_base: $(bundle exec rails secret)"
      bundle exec rails db:encryption:init | tail -n 4
    } > "$CRED_TMP"
    EDITOR="cp $CRED_TMP" bundle exec rails credentials:edit --environment production >/dev/null
  ) || { rm -f "$CRED_TMP"; die "Rails production credentials could not be created."; }
  rm -f "$CRED_TMP"
  [[ -s "$CRED_DIR/production.yml.enc" && -s "$CRED_DIR/production.key" ]] || die "Rails credentials files were not created."
  chmod 600 "$CRED_DIR/production.key" "$CRED_DIR/production.yml.enc"
fi

info "Building frontend assets"
if [[ ! -d "$APP_DIR/public/assets" || -z "$(find "$APP_DIR/public/assets" -type f -print -quit 2>/dev/null)" ]]; then
  (
    cd "$APP_DIR"
    npm ci --no-audit --no-fund
    npm run build
    set -a; . "$ENV_FILE"; set +a
    SECRET_KEY_BASE_DUMMY=1 APP_HOST=build.invalid RAILS_ENV=production bundle exec rails assets:precompile
  )
  rm -rf "$APP_DIR/node_modules"
fi

info "Running database migrations"
(
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  cd "$APP_DIR"
  export RAILS_ENV=production
  bundle exec rails db:prepare db:seed
)

info "Installation files are ready"
echo "Application: $APP_DIR"
echo "Environment: $ENV_FILE"
echo "Controller:  $APP_DIR/deploy/feral/control.sh"
echo "Rails credentials: $CRED_DIR (keep production.key private and backed up)."
echo "Configure the Feral subdomain proxy to http://127.0.0.1:$PORT, then start with control.sh."
