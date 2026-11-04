#!/usr/bin/env bash
set -Eeuo pipefail

. /etc/os-release
[[ "${ID:-}" == debian ]] || { echo "Unsupported OS: ${ID:-unknown}; Debian 11/12/13 required." >&2; exit 1; }
MAJOR=${VERSION_ID%%.*}
case "$MAJOR" in
  11) CODENAME=bullseye; STATUS='EOL compatibility only; Debian security updates ended 2026-08-31' ;;
  12) CODENAME=bookworm; STATUS='Supported Debian release (LTS)' ;;
  13) CODENAME=trixie; STATUS='Supported Debian release' ;;
  *) echo "Unsupported Debian ${VERSION_ID:-unknown}; supported: 11, 12, 13." >&2; exit 1 ;;
esac
ARCH=$(dpkg --print-architecture)
case "$ARCH" in amd64|arm64) ;; *) echo "Unsupported architecture: $ARCH; amd64/arm64 required." >&2; exit 1 ;; esac
GLIBC=$(getconf GNU_LIBC_VERSION | awk '{print $2}')
dpkg --compare-versions "$GLIBC" ge 2.28 || { echo "glibc $GLIBC is below Node.js 26 minimum 2.28." >&2; exit 1; }
printf 'PASS: Debian %s (%s), architecture %s, glibc %s\n' "$MAJOR" "$CODENAME" "$ARCH" "$GLIBC"
printf 'INFO: %s\n' "$STATUS"
if [[ "$MAJOR" == 11 ]]; then
  echo 'WARNING: PostgreSQL 18 is fetched from the frozen PGDG Bullseye archive; OS and package updates are not guaranteed.'
else
  echo 'INFO: PostgreSQL 18 uses the current PGDG repository.'
fi
