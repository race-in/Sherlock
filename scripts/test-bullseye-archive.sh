#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PREPARER="$ROOT/scripts/prepare-bullseye-archive.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/etc/apt/sources.list.d" "$TMP/etc/apt/apt.conf.d" "$TMP/var/backups"
cat > "$TMP/etc/apt/sources.list" <<'LIST'
deb https://deb.debian.org/debian bullseye main
deb [arch=amd64] https://deb.debian.org/debian bullseye-updates main
deb https://security.debian.org/debian-security bullseye-security main
deb https://deb.debian.org/debian bullseye-backports main
deb https://download.docker.com/linux/debian bullseye stable
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

Types: deb
URIs: https://deb.debian.org/debian
Suites: bullseye-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://download.docker.com/linux/debian
Suites: bullseye stable
Components: stable
Signed-By: /usr/share/keyrings/docker-archive-keyring.gpg
DEB822

APT_SOURCE_ROOT="$TMP" bash "$PREPARER"
grep -Fq 'http://archive.debian.org/debian bullseye main' "$TMP/etc/apt/sources.list"
grep -Fq 'http://archive.debian.org/debian bullseye-updates main' "$TMP/etc/apt/sources.list"
grep -Fq 'http://archive.debian.org/debian-security bullseye-security main' "$TMP/etc/apt/sources.list"
grep -Fq 'deb [check-valid-until=no] https://download.docker.com/linux/debian bullseye stable' "$TMP/etc/apt/sources.list" && {
  echo "ERROR: third-party APT source was rewritten." >&2
  exit 1
}
grep -Fxq 'deb https://download.docker.com/linux/debian bullseye stable' "$TMP/etc/apt/sources.list"
grep -Fq 'check-valid-until=no' "$TMP/etc/apt/sources.list"
grep -Fq 'Check-Valid-Until: no' "$TMP/etc/apt/sources.list.d/debian.sources"
grep -Fq 'URIs: http://archive.debian.org/debian-security' "$TMP/etc/apt/sources.list.d/debian.sources"
grep -Fq 'Suites: bullseye-security' "$TMP/etc/apt/sources.list.d/debian.sources"
# A single deb822 stanza containing base, updates, and security suites must
# be split and routed through each suite's correct archive URI.
grep -A1 -F 'URIs: http://archive.debian.org/debian' "$TMP/etc/apt/sources.list.d/debian.sources" | grep -Fxq 'Suites: bullseye'
grep -A1 -F 'URIs: http://archive.debian.org/debian' "$TMP/etc/apt/sources.list.d/debian.sources" | grep -Fxq 'Suites: bullseye-updates'
grep -A1 -F 'URIs: http://archive.debian.org/debian-security' "$TMP/etc/apt/sources.list.d/debian.sources" | grep -Fxq 'Suites: bullseye-security'
! grep -q 'bullseye-backports' "$TMP/etc/apt/sources.list.d/debian.sources"
grep -Fq 'URIs: https://download.docker.com/linux/debian' "$TMP/etc/apt/sources.list.d/debian.sources"
! grep -A1 'URIs: https://download.docker.com/linux/debian' "$TMP/etc/apt/sources.list.d/debian.sources" | grep -q 'Check-Valid-Until'
[[ ! -f "$TMP/etc/apt/apt.conf.d/99sherlock-bullseye-archive" ]]
find "$TMP/var/backups" -mindepth 1 -maxdepth 1 -type d | grep -q .

echo "PASS: Bullseye archive migration is scoped to official Debian sources"
