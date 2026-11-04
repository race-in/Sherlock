#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INSTALL="$ROOT/deploy/feral/install.sh"
CONTROL="$ROOT/deploy/feral/control.sh"
bash -n "$INSTALL"
bash -n "$CONTROL"
bash -n "$ROOT/deploy/feral/diagnose.sh"
grep -q 'VERSION_ID:-}.*9' "$INSTALL"
grep -q 'OpenSSL::OPENSSL_VERSION' "$INSTALL"
grep -q 'Gem::Version.new("3.2.0")' "$INSTALL"
grep -q 'BUNDLE_FORCE_RUBY_PLATFORM=true' "$INSTALL"
grep -q 'chmod 600' "$INSTALL"
grep -q 'nohup' "$CONTROL"
grep -q '127.0.0.1' "$CONTROL"
if grep -Eq '(^|[[:space:]])(sudo|systemctl|apt-get)([[:space:]]|$)' "$INSTALL"; then
  echo "Feral installer must not require root/system services." >&2
  exit 1
fi
echo "Feral rootless shell smoke checks passed."
