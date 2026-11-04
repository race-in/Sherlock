#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/install.sh"
UPDATER="$ROOT/scripts/update.sh"

grep -Fq 'psql -p "$PG_PORT" -tAc "SELECT 1 FROM pg_roles' "$INSTALLER" || {
  echo "ERROR: PostgreSQL role pre-check does not target the detected cluster port." >&2
  exit 1
}
grep -Fq 'psql -p "$PG_PORT" -tAc "SELECT 1 FROM pg_database' "$INSTALLER" || {
  echo "ERROR: PostgreSQL database pre-check does not target the detected cluster port." >&2
  exit 1
}
grep -Fq 'psql -p "$PG_PORT" -v ON_ERROR_STOP=1' "$INSTALLER" || {
  echo "ERROR: PostgreSQL role/database creation does not target the detected cluster port." >&2
  exit 1
}
grep -Fq 'check-nginx-host-conflict.sh' "$INSTALLER" || {
  echo "ERROR: installer does not check for an existing Nginx virtual host." >&2
  exit 1
}
grep -Fq '11) NODE_BINARY_VERSION=24.22.2; NODE_MIN_GLIBC=2.28; NODE_MIN_KERNEL=4.18 ;;' "$INSTALLER" || {
  echo "ERROR: Debian 11 Node 24 compatibility pin is missing." >&2
  exit 1
}
grep -Fq '12|13) NODE_BINARY_VERSION=26.12.0; NODE_MIN_GLIBC=2.34; NODE_MIN_KERNEL=5.14 ;;' "$INSTALLER" || {
  echo "ERROR: Debian 12/13 Node 26 compatibility pin is missing." >&2
  exit 1
}
grep -Fq '[[ "$BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$BRANCH" != *..* ]]' "$INSTALLER" || {
  echo "ERROR: installer does not validate branch names before writing the environment file." >&2
  exit 1
}
grep -Fq 'ACTUAL_RUBY_VERSION=' "$INSTALLER" || {
  echo "ERROR: installer does not verify the existing Ruby runtime version." >&2
  exit 1
}
grep -Fq '"$RUBY_PREFIX/bin/gem" install bundler -v 4.0.20 --no-document' "$INSTALLER" || {
  echo "ERROR: installer does not install Bundler into the application Ruby runtime." >&2
  exit 1
}
grep -Fq '"$RUBY_PREFIX/bin/bundle" --version' "$INSTALLER" || {
  echo "ERROR: installer does not verify the application Ruby Bundler executable." >&2
  exit 1
}
if grep -Fq 'rm -f /etc/nginx/sites-enabled/default' "$INSTALLER"; then
  echo "ERROR: installer would remove the server's default Nginx site." >&2
  exit 1
fi

grep -Fq '[[ "$APP_GIT_BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$' "$UPDATER" || {
  echo "ERROR: updater does not validate APP_GIT_BRANCH before git fetch." >&2
  exit 1
}
grep -Fq 'PATCHER="$SCRIPT_DIR/scripts/patch-native-app.sh"' "$UPDATER" || {
  echo "ERROR: updater does not use the current deployment repository patcher." >&2
  exit 1
}

echo "PASS: installer and updater contracts are safe"
