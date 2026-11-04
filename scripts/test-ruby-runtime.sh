#!/usr/bin/env bash
set -Eeuo pipefail

. /etc/os-release
[[ "$ID" == debian ]] || { echo "Debian 11/12/13 required." >&2; exit 1; }
case "$(cut -d. -f1 <<< "$VERSION_ID")" in 11|12|13) ;; *) echo "Unsupported Debian release: $VERSION_ID" >&2; exit 1 ;; esac

RUBY_VERSION=4.0.9
BUNDLER_VERSION=4.0.20
RUBY_BUILD_TAG=v20261023
RUBY_BUILD_COMMIT=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92

SCRIPT_DIR=$(cd -- "$(dirname -- "$BASH_SOURCE")" && pwd)
APP_SOURCE_DIR="$SCRIPT_DIR/../sherlock-v2"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  autoconf bison build-essential ca-certificates curl git \
  libdb-dev libffi-dev libgdbm-dev libgmp-dev libncurses-dev \
  libpq-dev libreadline-dev libssl-dev libyaml-dev pkg-config python3 zlib1g-dev \
  postgresql-18 postgresql-client-18

TMP_DIR=$(mktemp -d)
chmod 0755 "$TMP_DIR"
RUBY_PREFIX="$TMP_DIR/ruby"
RUBY_BUILD_DIR="$TMP_DIR/ruby-build"
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
  HOME="$APP_HOME" PATH="$RUBY_PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
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
runuser -u postgres -- psql -p "$PG_PORT" -v ON_ERROR_STOP=1 \
  -v role_name="$DB_ROLE" -v role_password="$DB_PASSWORD" -v database_name="$DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN SUPERUSER PASSWORD %L', :'role_name', :'role_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'database_name', :'role_name', 'UTF8') \gexec
SQL

runuser -u sherlock-runtime-test -- env \
  HOME="$APP_HOME" PATH="$RUBY_PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  BUNDLE_PATH="$BUNDLE_PATH" BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development \
  RAILS_ENV=test CI=true \
  TEST_DB_HOST=127.0.0.1 TEST_DB_PORT="$PG_PORT" TEST_DB_USER="$DB_ROLE" \
  TEST_DB_PASSWORD="$DB_PASSWORD" TEST_DB_NAME="$DB_NAME" \
  bash -ec '
    cd "$1"
    bundle exec rails db:prepare
    bundle exec rails test
  ' -- "$APP_DIR"

printf 'PASS: Debian %s compiled Ruby %s, resolved test gems, and passed the bundled Sherlock Rails test suite on PostgreSQL 18.\n' "$(cut -d. -f1 <<< "$VERSION_ID")" "$RUBY_VERSION"
