#!/usr/bin/env bash
set -Eeuo pipefail

. /etc/os-release
[[ "${ID:-}" == debian ]] || { echo "Debian required." >&2; exit 1; }
MAJOR=${VERSION_ID%%.*}
case "$MAJOR" in
  11) CODENAME=bullseye; PGDG_HOST=apt-archive.postgresql.org; PGDG_SUITE=bullseye-pgdg ;;
  12) CODENAME=bookworm; PGDG_HOST=apt.postgresql.org; PGDG_SUITE=bookworm-pgdg ;;
  13) CODENAME=trixie; PGDG_HOST=apt.postgresql.org; PGDG_SUITE=trixie-pgdg ;;
  *) echo "Unsupported Debian release: $VERSION_ID" >&2; exit 1 ;;
esac

if [[ "$MAJOR" == 11 ]]; then
  APT_SOURCE_ROOT=/ bash scripts/prepare-bullseye-archive.sh
fi

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl
install -d -m 0755 /usr/share/postgresql-common/pgdg
curl -fsSLo /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc

if [[ "$MAJOR" == 11 ]]; then
  printf 'deb [check-valid-until=no signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://%s/pub/repos/apt %s main\n' "$PGDG_HOST" "$PGDG_SUITE" \
    > /etc/apt/sources.list.d/pgdg.list
else
  printf 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://%s/pub/repos/apt %s main\n' "$PGDG_HOST" "$PGDG_SUITE" \
    > /etc/apt/sources.list.d/pgdg.list
fi

apt-get update
apt-get install --simulate --no-install-recommends \
  ca-certificates curl git build-essential autoconf bison \
  libssl-dev libyaml-dev libreadline-dev zlib1g-dev libffi-dev libgdbm-dev \
  libncurses-dev libgmp-dev libdb-dev libpq-dev pkg-config python3 make gcc g++ \
  libjemalloc2 libatomic1 postgresql-common postgresql-18 postgresql-client-18 \
  nginx certbot python3-certbot-nginx ufw openssl xz-utils iproute2

echo "PASS: Debian $MAJOR APT repositories and native installer package dependencies resolve."
