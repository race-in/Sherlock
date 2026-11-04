#!/usr/bin/env bash
set -Eeuo pipefail

[[ $# -ge 2 ]] || {
  echo "Usage: $0 <hostname> <nginx-config-path> [path ...]" >&2
  exit 2
}
DOMAIN=${1,,}
shift
[[ "$DOMAIN" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]] || {
  echo "Invalid hostname: $DOMAIN" >&2
  exit 2
}

# Match an exact hostname in any position of a server_name directive.
# Nginx allows multiple names on one line; dots in the hostname must be literal.
ESCAPED_DOMAIN=${DOMAIN//./\\.}
PATTERN="^[[:space:]]*server_name[[:space:]]+([^;]*[[:space:]])?${ESCAPED_DOMAIN}([[:space:];]|$)"

for path in "$@"; do
  [[ -e "$path" ]] || continue
  if grep -R -n -E -- "$PATTERN" "$path" 2>/dev/null; then
    exit 0
  fi
done
exit 1
