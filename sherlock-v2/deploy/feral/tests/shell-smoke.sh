#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
bash -n "$ROOT/deploy/feral/install.sh"
bash -n "$ROOT/deploy/feral/control.sh"
grep -q 'VERSION_ID:-}.*9' "$ROOT/deploy/feral/install.sh"
grep -q 'systemd' "$ROOT/deploy/feral/README.md"
grep -q 'nohup' "$ROOT/deploy/feral/control.sh"
grep -q 'BUNDLE_FORCE_RUBY_PLATFORM=true' "$ROOT/deploy/feral/install.sh"
echo "Feral rootless shell smoke checks passed."
