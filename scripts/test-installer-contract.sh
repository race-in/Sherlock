#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/install.sh"

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
if grep -Fq 'rm -f /etc/nginx/sites-enabled/default' "$INSTALLER"; then
  echo "ERROR: installer would remove the server's default Nginx site." >&2
  exit 1
fi

echo "PASS: installer targets the selected PostgreSQL cluster and preserves existing Nginx sites"
