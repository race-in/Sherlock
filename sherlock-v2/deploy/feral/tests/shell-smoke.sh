#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INSTALL="$ROOT/deploy/feral/install.sh"
CONTROL="$ROOT/deploy/feral/control.sh"
bash -n "$INSTALL"
bash -n "$CONTROL"
bash -n "$ROOT/deploy/feral/diagnose.sh"
bash -n "$ROOT/deploy/feral/bootstrap-runtime.sh"
ruby -c "$ROOT/deploy/feral/puma.rb"
grep -q 'VERSION_ID:-}.*9' "$INSTALL"
grep -q 'OpenSSL::OPENSSL_VERSION' "$INSTALL"
grep -q 'production.yml.enc' "$INSTALL"
grep -q 'PostgreSQL 16.15' "$ROOT/deploy/feral/bootstrap-runtime.sh"
grep -q 'OpenSSL 3.5.9' "$ROOT/deploy/feral/bootstrap-runtime.sh"
grep -q 'node-v22.21.1-linux-x64-glibc-217' "$ROOT/deploy/feral/bootstrap-runtime.sh"
grep -q 'rustc 1.89.0' "$ROOT/deploy/feral/bootstrap-runtime.sh"
grep -q 'libclang -v 14.0.6' "$ROOT/deploy/feral/bootstrap-runtime.sh"
grep -q 'Gem::Version.new("3.2.0")' "$INSTALL"
grep -q 'command -v cargo' "$INSTALL"
grep -q 'LIBCLANG_PATH' "$INSTALL"
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
