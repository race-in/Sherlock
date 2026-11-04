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
SINGLE_USER_DB_NAME="${DB_NAME}_single"
runuser -u postgres -- psql -p "$PG_PORT" -v ON_ERROR_STOP=1 \
  -v role_name="$DB_ROLE" -v role_password="$DB_PASSWORD" -v database_name="$DB_NAME" \
  -v single_database_name="$SINGLE_USER_DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN SUPERUSER PASSWORD %L', :'role_name', :'role_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'database_name', :'role_name', 'UTF8') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'single_database_name', :'role_name', 'UTF8') \gexec
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

# Exercise the single-user routes, first-run token and account invariant in a clean database.
# This keeps the upstream multi-user fixtures/tests above unchanged.
SINGLE_USER_TOKEN=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
install -d -o sherlock-runtime-test -g sherlock-runtime-test "$APP_DIR/tmp"
SINGLE_USER_SMOKE="$APP_DIR/tmp/single_user_mode_smoke.rb"
cat > "$SINGLE_USER_SMOKE" <<'RUBY'
require "action_dispatch/testing/integration"

names = Rails.application.routes.named_routes.names.map(&:to_s)
blocked = %w[join new_join join_profile join_check opt_in settings_invites admin_invites admin_users]
present = names.select { |name| blocked.any? { |prefix| name == prefix || name.start_with?("#{prefix}_") } }
abort "Single-user routes are still enabled: #{present.join(', ')}" if present.any?
required = %w[first_run admin_sites admin_settings dashboard]
missing = required - names
abort "Required single-user routes are missing: #{missing.join(', ')}" if missing.any?

web = ActionDispatch::Integration::Session.new(Rails.application)
attributes = { username: "single-admin", password: "single-user-password", time_zone: "UTC" }
web.post("/first_run", params: { user: attributes, setup_token: "wrong-token" })
abort "First-run accepted an invalid setup token" unless web.response.status == 422
abort "Invalid setup token created an account" if User.exists?

web.post("/first_run", params: { user: attributes, setup_token: ENV.fetch("FIRST_RUN_TOKEN") })
abort "First-run did not create the admin with the valid token (HTTP #{web.response.status})" unless (300..399).cover?(web.response.status)
user = User.find_by!(username: "single-admin")
abort "First account was not made admin" unless user.is_admin?
user.complete_onboarding!

web.get("/dashboard")
abort "Single-user dashboard failed to render (HTTP #{web.response.status})" unless (200..299).cover?(web.response.status)
web.get("/admin/sites")
abort "Single-user Admin/Sites page failed to render (HTTP #{web.response.status})" unless (200..299).cover?(web.response.status)
web.get("/join")
abort "Join route should be disabled in single-user mode" unless web.response.status == 404

second = User.new(username: "second-account", password: "second-user-password", time_zone: "UTC")
abort "Second account was accepted in single-user mode" if second.save
abort "Second-account rejection did not report the single-user invariant" unless second.errors.full_messages.any? { |message| message.include?("one account only") }

begin
  User.connection.execute(<<~SQL)
    INSERT INTO sherlockdb.users (username, password_digest, created_at, updated_at)
    VALUES ('direct-sql-second-account', 'not-a-login-digest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
  SQL
  abort "PostgreSQL unique index allowed direct SQL to create a second account"
rescue ActiveRecord::RecordNotUnique => error
  raise unless error.message.include?("users_single_user_mode_idx")
end

# A multi-row INSERT in one SQL statement must also fail atomically; this is why the database
# boundary is a unique index rather than a row trigger that only counts existing rows.
begin
  User.connection.execute(<<~SQL)
    INSERT INTO sherlockdb.users (username, password_digest, created_at, updated_at)
    VALUES
      ('direct-sql-row-a', 'not-a-login-digest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('direct-sql-row-b', 'not-a-login-digest', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
  SQL
  abort "PostgreSQL unique index allowed a multi-row insert"
rescue ActiveRecord::RecordNotUnique => error
  raise unless error.message.include?("users_single_user_mode_idx")
end

puts "PASS: single-user routes, token gate, rendered pages, Rails invariant and PostgreSQL unique index"
RUBY
chown sherlock-runtime-test:sherlock-runtime-test "$SINGLE_USER_SMOKE"

runuser -u sherlock-runtime-test -- env \
  HOME="$APP_HOME" PATH="$RUBY_PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  BUNDLE_PATH="$BUNDLE_PATH" BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT=development \
  RAILS_ENV=test CI=true SINGLE_USER_MODE=true FIRST_RUN_TOKEN="$SINGLE_USER_TOKEN" \
  TEST_DB_HOST=127.0.0.1 TEST_DB_PORT="$PG_PORT" TEST_DB_USER="$DB_ROLE" \
  TEST_DB_PASSWORD="$DB_PASSWORD" TEST_DB_NAME="$SINGLE_USER_DB_NAME" \
  bash -ec '
    cd "$1"
    bundle exec rails db:prepare
    bundle exec rails runner -e test tmp/single_user_mode_smoke.rb
  ' -- "$APP_DIR"

printf 'PASS: Debian %s compiled Ruby %s, resolved gems, passed Rails tests and passed single-user mode checks on PostgreSQL 18.\n' "$(cut -d. -f1 <<< "$VERSION_ID")" "$RUBY_VERSION"
