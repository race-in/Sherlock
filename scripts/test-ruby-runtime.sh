#!/usr/bin/env bash
set -Eeuo pipefail

. /etc/os-release
[[ "${ID:-}" == debian ]] || { echo "Debian 11/12/13 required." >&2; exit 1; }
case "${VERSION_ID%%.*}" in 11|12|13) ;; *) echo "Unsupported Debian release: ${VERSION_ID:-unknown}" >&2; exit 1 ;; esac

RUBY_VERSION=4.0.9
BUNDLER_VERSION=4.0.20
RUBY_BUILD_TAG=v20261023
RUBY_BUILD_COMMIT=b6a92c15f0df872047c74f7dfa0b92dfd4de8a92
APP_SOURCE_URL=${APP_SOURCE_URL:-https://codeberg.org/whatstatus/sherlock-v2.git}

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  autoconf bison build-essential ca-certificates curl git \
  libdb-dev libffi-dev libgdbm-dev libgmp-dev libncurses-dev \
  libpq-dev libreadline-dev libssl-dev libyaml-dev pkg-config python3 zlib1g-dev

TMP_DIR=$(mktemp -d)
chmod 0755 "$TMP_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT
RUBY_PREFIX="$TMP_DIR/ruby"
RUBY_BUILD_DIR="$TMP_DIR/ruby-build"
APP_DIR="$TMP_DIR/sherlock"
BUNDLE_PATH="$TMP_DIR/bundle"
APP_HOME="$TMP_DIR/home"

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
git clone --depth 1 --no-tags "$APP_SOURCE_URL" "$APP_DIR"
# Exercise the exact local deployment patcher against the live upstream source,
# not only the synthetic fixtures in test-native-patches.sh.
bash "$SCRIPT_DIR/patch-native-app.sh" "$APP_DIR"
chown -R sherlock-runtime-test:sherlock-runtime-test "$APP_DIR"

APP_RUBY_VERSION=$(tr -d '\r\n' < "$APP_DIR/.ruby-version")
APP_NODE_VERSION=$(tr -d '\r\n' < "$APP_DIR/.node-version")
[[ "$APP_RUBY_VERSION" == "$RUBY_VERSION" ]] || {
  echo "Unexpected upstream Ruby pin: $APP_RUBY_VERSION." >&2
  exit 1
}
[[ "$APP_NODE_VERSION" == 26.12.0 ]] || {
  echo "Unexpected upstream Node pin: $APP_NODE_VERSION." >&2
  exit 1
}

runuser -u sherlock-runtime-test -- env \
  HOME="$APP_HOME" PATH="$RUBY_PREFIX/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  BUNDLE_PATH="$BUNDLE_PATH" BUNDLE_DEPLOYMENT=1 BUNDLE_WITHOUT='development:test' \
  bash -ec '
    cd "$1"
    bundle config set --local deployment true
    bundle config set --local path "$BUNDLE_PATH"
    bundle config set --local without "development test"
    bundle install --jobs 2 --retry 3
    bundle check
    bundle exec rails --version
  ' -- "$APP_DIR"

printf 'PASS: Debian %s compiled Ruby %s, installed Bundler %s, and resolved upstream Sherlock production gems.\n' "${VERSION_ID%%.*}" "$RUBY_VERSION" "$BUNDLER_VERSION"
