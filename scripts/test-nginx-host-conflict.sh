#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/scripts/check-nginx-host-conflict.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/sites-enabled" "$TMP/conf.d"
cat > "$TMP/sites-enabled/single.conf" <<'NGINX'
server {
    listen 80;
    server_name stats.example.com;
}
NGINX
if ! bash "$HELPER" stats.example.com "$TMP/sites-enabled"; then
  echo "ERROR: exact single server_name was not detected." >&2
  exit 1
fi

cat > "$TMP/sites-enabled/multiple.conf" <<'NGINX'
server {
    listen 443 ssl;
    server_name old.example.com stats.example.com www.example.com;
}
NGINX
if ! bash "$HELPER" stats.example.com "$TMP/sites-enabled"; then
  echo "ERROR: hostname in a multi-name server_name directive was not detected." >&2
  exit 1
fi

if bash "$HELPER" stats2.example.com "$TMP/sites-enabled"; then
  echo "ERROR: unrelated hostname was reported as a conflict." >&2
  exit 1
fi

cat > "$TMP/conf.d/comment.conf" <<'NGINX'
# server_name stats.example.com;
NGINX
if bash "$HELPER" stats.example.com "$TMP/conf.d"; then
  echo "ERROR: commented server_name was reported as a conflict." >&2
  exit 1
fi

echo "PASS: Nginx hostname conflict detection"
