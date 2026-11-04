#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/install.sh"
UPDATER="$ROOT/scripts/update.sh"

python3 - "$INSTALLER" "$UPDATER" <<'PY'
from pathlib import Path
import sys

installer = Path(sys.argv[1]).read_text(encoding="utf-8")
updater = Path(sys.argv[2]).read_text(encoding="utf-8")

required_installer = {
    "PostgreSQL role pre-check uses detected cluster port": 'psql -p "$PG_PORT" -tAc "SELECT 1 FROM pg_roles',
    "PostgreSQL database pre-check uses detected cluster port": 'psql -p "$PG_PORT" -tAc "SELECT 1 FROM pg_database',
    "PostgreSQL creation uses detected cluster port": 'psql -p "$PG_PORT" -v ON_ERROR_STOP=1',
    "Nginx host conflict preflight": "check-nginx-host-conflict.sh",
    "Debian 11 Node compatibility pin": "11) NODE_BINARY_VERSION=24.22.2; NODE_MIN_GLIBC=2.28; NODE_MIN_KERNEL=4.18 ;;",
    "Debian 12/13 Node compatibility pin": "12|13) NODE_BINARY_VERSION=26.12.0; NODE_MIN_GLIBC=2.34; NODE_MIN_KERNEL=5.14 ;;",
    "Safe branch name validation": '[[ "$BRANCH" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$BRANCH" != *..* ]]',
    "Existing Ruby runtime version validation": 'ACTUAL_RUBY_VERSION=$("$RUBY_PREFIX/bin/ruby" -e \'print RUBY_VERSION\')',
    "Bundler installed into selected Ruby runtime": '$RUBY_PREFIX/bin/gem install bundler -v 4.0.20 --no-document',
}
for label, expected in required_installer.items():
    if expected not in installer:
        raise SystemExit(f"ERROR: installer missing contract: {label}")

if 'rm -f /etc/nginx/sites-enabled/default' in installer:
    raise SystemExit("ERROR: installer would remove the server's default Nginx site.")

if 'PATCHER="$SCRIPT_DIR/scripts/patch-native-app.sh"' not in updater:
    raise SystemExit("ERROR: updater does not use the current deployment repository patcher.")

print("PASS: installer and updater contracts are safe")
PY
