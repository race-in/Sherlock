#!/usr/bin/env bash
set -Eeuo pipefail

. /etc/os-release
[[ "$ID" == debian ]] || { echo "Debian 11/12/13 required." >&2; exit 1; }
case "$(cut -d. -f1 <<< "$VERSION_ID")" in 11|12|13) ;; *) echo "Unsupported Debian release: $VERSION_ID" >&2; exit 1 ;; esac

RUBY_VERSION=4.0.9
BUNDLER_VERSION=4.0.20
RUBY_BUILD_TAG=v20261023
RUBY_BUILD_COMMIT=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92
case "$(cut -d. -f1 <<< "$VERSION_ID")" in
  11) NODE_VERSION=24.22.2 ;;
  12|13) NODE_VERSION=26.12.0 ;;
esac
case "$(dpkg --print-architecture)" in
  amd64) NODE_ARCH=x64 ;;
  arm64) NODE_ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(dpkg --print-architecture)." >&2; exit 1 ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd)
APP_SOURCE_DIR="$SCRIPT_DIR/../sherlock-v2"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  autoconf bison build-essential ca-certificates curl git \
  libdb-dev libffi-dev libgdbm-dev libgmp-dev libncurses-dev \
  libpq-dev libreadline-dev libssl-dev libyaml-dev pkg-config python3 zlib1g-dev \
  libatomic1 xz-utils postgresql-18 postgresql-client-18

TMP_DIR=$(mktemp -d)
chmod 0755 "$TMP_DIR"
RUBY_PREFIX="$TMP_DIR/ruby"
RUBY_BUILD_DIR="$TMP_DIR/ruby-build"
NODE_PREFIX="$TMP_DIR/node"
APP_DIR="$TMP_DIR/sherlock"
BUNDLE_PATH="$TMP_DIR/bundle"
APP_HOME="$TMP_DIR/home"
PG_PORT=""
DB_ROLE="sherlock_runtime_test_$$"
DB_NAME="sherlock_runtime_test_$$"
DB_PASSWORD=$(openssl rand -hex 24)

cleanup() {
  if [[ -n "$PG_PORT" ]] && pg_isready -q -h 127.0.0.1 -p "$PG_PORT"; then
    runuser -u postgres -- psql -p "$PG_PORT" -Atc \
      "SELECT datname FROM pg_database WHERE datname LIKE '$DB_NAME%'" 2>/dev/null |
      while IFS= read -r db; do
        [[ -n "$db" ]] && runuser -u postgres -- dropdb --if-exists -p "$PG_PORT" "$db" >/dev/null 2>&1 || true
      done
    runuser -u postgres -- psql -p "$PG_PORT" -c "DROP ROLE IF EXISTS \"$DB_ROLE\"" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Rails test:prepare invokes jsbundling-rails, so provide the official, checksum-verified
# Node.js runtime used by the native installer. Bullseye needs Node 24 because its glibc is older.
NODE_DIST_BASE=https://nodejs.org/dist
NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
mkdir -p "$NODE_PREFIX"
curl -fsSLo "$TMP_DIR/SHASUMS256.txt" "$NODE_DIST_BASE/v$NODE_VERSION/SHASUMS256.txt"
curl -fsSLo "$TMP_DIR/$NODE_TARBALL" "$NODE_DIST_BASE/v$NODE_VERSION/$NODE_TARBALL"
grep -E "^[0-9a-f]{64}  ${NODE_TARBALL}$" "$TMP_DIR/SHASUMS256.txt" > "$TMP_DIR/node.sha256" \
  || { echo "Official SHA-256 entry missing for $NODE_TARBALL." >&2; exit 1; }
(cd "$TMP_DIR" && sha256sum --check node.sha256)
tar -xJf "$TMP_DIR/$NODE_TARBALL" -C "$NODE_PREFIX" --strip-components=1
[[ "$("$NODE_PREFIX/bin/node" --version)" == "v$NODE_VERSION" ]] || {
  echo "Node.js runtime version mismatch." >&2
  exit 1
}
"$NODE_PREFIX/bin/npm" --version
RUNTIME_PATH="$RUBY_PREFIX/bin:$NODE_PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

git clone --depth 1 --branch "$RUBY_BUILD_TAG" \
  https://github.com/rbenv/ruby-build.git "$RUBY_BUILD_DIR"
ACTUAL_COMMIT=$(git -C "$RUBY_BUILD_DIR" rev-parse HEAD)
[[ "$ACTUAL_COMMIT" == "$RUBY_BUILD_COMMIT" ]] || {
  echo "ruby-build commit mismatch: expected $RUBY_BUILD_COMMIT, got $ACTUAL_COMMIT." >&2
  exit 1
}

MAKE_OPTS=-j2 RUBY_BUILD_BUILD_PATH="$TMP_DIR/ruby-build-cache" \
  "$RUBY_BUILD_DIR/bin/ruby-build" "$RUBY_VERSION" "$RUBY_PREFIX"
"$RUBY_PREFIX/bin/ruby" -ropenssl -e \
  'abort "Ruby OpenSSL extension is unavailable" unless OpenSSL::OPENSSL_VERSION; puts "Ruby runtime OK:", RUBY_VERSION, OpenSSL::OPENSSL_VERSION'
"$RUBY_PREFIX/bin/gem" install bundler -v "$BUNDLER_VERSION" --no-document
"$RUBY_PREFIX/bin/bundle" --version

groupadd --system sherlock-runtime-test
useradd --system --gid sherlock-runtime-test --home-dir "$APP_HOME" --create-home --shell /usr/sbin/nologin sherlock-runtime-test
install -d -o sherlock-runtime-test -g sherlock-runtime-test -m 0750 "$APP_DIR" "$BUNDLE_PATH" "$APP_HOME"
cp -a "$APP_SOURCE_DIR/." "$APP_DIR/"
# Test the exact bundled Rails source; the legacy patcher is covered separately by test-native-patches.sh.
chown -R sherlock-runtime-test:sherlock-runtime-test "$APP_DIR"

APP_RUBY_VERSION=$(tr -d '\r\n' < "$APP_DIR/.ruby-version")
APP_NODE_VERSION=$(tr -d '\r\n' < "$APP_DIR/.node-version")
[[ "$APP_RUBY_VERSION" == "$RUBY_VERSION" ]] || {
  echo "Unexpected bundled Ruby pin: $APP_RUBY_VERSION." >&2
  exit 1
}
[[ "$APP_NODE_VERSION" == 26.12.0 ]] || {
  echo "Unexpected bundled Node pin: $APP_NODE_VERSION." >&2
  exit 1
}

runuser -u sherlock-runtime-test -- env \
  HOME="$APP_HOME" PATH="$RUNTIME_PATH" \
  BUNDLE_PATH="$BUNDLE_PATH" BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development \
  bash -ec '
    cd "$1"
    bundle config set --local deployment true
    bundle config set --local path "$BUNDLE_PATH"
    bundle config set --local without development
    bundle install --jobs 2 --retry 3
    bundle check
    bundle exec rails --version
  ' -- "$APP_DIR"

# Run the real Rails suite against the PostgreSQL 18 cluster provisioned for this Debian matrix job.
PG_PORT=$(pg_lsclusters --no-header | awk '$1 == 18 && $4 == "online" {print $3; exit}')
[[ "$PG_PORT" =~ ^[0-9]+$ ]] || { echo "PostgreSQL 18 cluster is not online." >&2; exit 1; }
pg_isready -h 127.0.0.1 -p "$PG_PORT"
MULTI_USER_DB_NAME="${DB_NAME}_multi"
runuser -u postgres -- psql -p "$PG_PORT" -v ON_ERROR_STOP=1 \
  -v role_name="$DB_ROLE" -v role_password="$DB_PASSWORD" -v database_name="$DB_NAME" \
  -v multi_database_name="$MULTI_USER_DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN SUPERUSER PASSWORD %L', :'role_name', :'role_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'database_name', :'role_name', 'UTF8') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L',  :'multi_database_name', :'role_name', 'UTF8') \gexec
SQL

runuser -u sherlock-runtime-test -- env \
  HOME="$APP_HOME" PATH="$RUNTIME_PATH" \
  BUNDLE_PATH="$BUNDLE_PATH" BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development \
  RAILS_ENV=test CI=true \
  TEST_DB_HOST=127.0.0.1 TEST_DB_PORT="$PG_PORT" TEST_DB_USER="$DB_ROLE" \
  TEST_DB_PASSWORD="$DB_PASSWORD" TEST_DB_NAME="$DB_NAME" \
  bash -ec '
    cd "$1"
    bundle exec rails db:prepare
    bundle exec rails test
  ' -- "$APP_DIR"


# Verify native deployment's default multi-user mode: invite routes remain present and multiple
# independent accounts can be persisted. This is deliberately not a single-user test.
MULTI_USER_SMOKE="$APP_DIR/tmp/multi_user_mode_smoke.rb"
install -d -o sherlock-runtime-test -g sherlock-runtime-test "$APP_DIR/tmp"
cat > "$MULTI_USER_SMOKE" <<'RUBY'
required = %w[new_join join settings_invites admin_users admin_invites]
names = Rails.application.routes.named_routes.names.map(&:to_s)
missing = required - names
abort "Multi-user routes are missing: #{missing.join(', ')}" if missing.any?

2.times do |index|
  User.create!(
    username: "multi-user-#{index}",
    password: "multi-user-password",
    time_zone: "UTC"
  )
end
abort "Expected two accounts in multi-user mode, found #{User.count}" unless User.count == 2
puts "PASS: invite/admin routes and multiple account creation are enabled"
RUBY
chown sherlock-runtime-test:sherlock-runtime-test "$MULTI_USER_SMOKE"

runuser -u sherlock-runtime-test -- env \
  HOME="$APP_HOME" PATH="$RUNTIME_PATH" \
  BUNDLE_PATH="$BUNDLE_PATH" BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development \
  RAILS_ENV=test CI=true SINGLE_USER_MODE=false \
  TEST_DB_HOST=127.0.0.1 TEST_DB_PORT="$PG_PORT" TEST_DB_USER="$DB_ROLE" \
  TEST_DB_PASSWORD="$DB_PASSWORD" TEST_DB_NAME="$MULTI_USER_DB_NAME" \
  bash -ec '
    cd "$1"
    bundle exec rails db:prepare
    bundle exec rails runner -e test tmp/multi_user_mode_smoke.rb
  ' -- "$APP_DIR"

printf 'PASS: Debian %s compiled Ruby %s, resolved gems, passed Rails tests and passed multi-user mode checks on PostgreSQL 18.\n' "$(cut -d. -f1 <<< "$VERSION_ID")" "$RUBY_VERSION"
