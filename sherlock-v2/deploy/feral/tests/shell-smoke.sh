#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INSTALL="$ROOT/deploy/feral/install.sh"
CONTROL="$ROOT/deploy/feral/control.sh"
BOOTSTRAP="$ROOT/deploy/feral/bootstrap-runtime.sh"

bash -n "$INSTALL"
bash -n "$CONTROL"
bash -n "$ROOT/deploy/feral/diagnose.sh"
bash -n "$BOOTSTRAP"
ruby -c "$ROOT/deploy/feral/puma.rb"

grep -q 'VERSION_ID:-}.*9' "$INSTALL"
grep -q 'OpenSSL::OPENSSL_VERSION' "$INSTALL"
grep -q 'production.yml.enc' "$INSTALL"
grep -q 'PostgreSQL 16.15' "$BOOTSTRAP"
grep -q 'src/bin/psql' "$BOOTSTRAP"
grep -q 'psql.*self-test' "$BOOTSTRAP"
grep -q 'command -v psql' "$INSTALL"
grep -q 'PGSSLMODE=.*require' "$INSTALL"
grep -q 'CREATE SCHEMA IF NOT EXISTS sherlockdb' "$INSTALL"
grep -q 'has_schema_privilege' "$INSTALL"
grep -q 'OpenSSL 3.5.9' "$BOOTSTRAP"
grep -q '^NODE_VERSION=22.21.1$' "$BOOTSTRAP"
grep -q 'linux-x64-glibc-217' "$BOOTSTRAP"
grep -q 'rustc 1.89.0' "$BOOTSTRAP"
grep -q 'libclang -v 14.0.6' "$BOOTSTRAP"
grep -q 'Gem::Version.new("3.2.0")' "$INSTALL"
grep -q 'command -v cargo' "$INSTALL"
grep -q 'LIBCLANG_PATH' "$INSTALL"
grep -q 'RBCONFIG_CPPFLAGS=' "$INSTALL"
grep -q 'RBCONFIG_CPPFLAGS' "$INSTALL"
grep -q 'GCC_INCLUDE.*limits.h' "$INSTALL"
grep -q 'BUNDLE_FORCE_RUBY_PLATFORM=true' "$INSTALL"
grep -q 'chmod 600' "$INSTALL"
grep -q 'nohup' "$CONTROL"
grep -q 'deploy/feral/puma.rb' "$CONTROL"
grep -q '127.0.0.1' "$CONTROL"

if grep -Eq '(^|[[:space:]])(sudo|systemctl|apt-get)([[:space:]]|$)' "$INSTALL"; then
  echo "Feral installer must not require root/system services." >&2
  exit 1
fi

echo "Feral rootless shell smoke checks passed."
