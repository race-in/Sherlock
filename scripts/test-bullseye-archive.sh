#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PREPARER="$ROOT/scripts/prepare-bullseye-archive.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/etc/apt/sources.list.d" "$TMP/etc/apt/apt.conf.d" "$TMP/var/backups"
cat > "$TMP/etc/apt/sources.list" <<'LIST'
deb https://deb.debian.org/debian bullseye main
deb https://deb.debian.org/debian bullseye-updates main
deb https://security.debian.org/debian-security bullseye-security main
LIST
cat > "$TMP/etc/apt/sources.list.d/debian.sources" <<'DEB822'
Types: deb
URIs: https://deb.debian.org/debian
Suites: bullseye bullseye-updates bullseye-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: bullseye-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
DEB822

APT_SOURCE_ROOT="$TMP" bash "$PREPARER"
grep -Fq 'http://archive.debian.org/debian bullseye main' "$TMP/etc/apt/sources.list"
! grep -q 'security.debian.org' "$TMP/etc/apt/sources.list"
grep -Fq 'Suites: bullseye bullseye-updates' "$TMP/etc/apt/sources.list.d/debian.sources"
! grep -q 'bullseye-security' "$TMP/etc/apt/sources.list.d/debian.sources"
grep -Fq 'Acquire::Check-Valid-Until "false";' "$TMP/etc/apt/apt.conf.d/99sherlock-bullseye-archive"
find "$TMP/var/backups" -mindepth 1 -maxdepth 1 -type d | grep -q .

echo "PASS: Bullseye legacy and deb822 APT source migration"
