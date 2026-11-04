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

# Install PostgreSQL 18 in the actual Debian container, start its cluster, and
# validate the same sherlockdb structure load performed by the native installer.
apt-get install -y --no-install-recommends git openssl postgresql-18 postgresql-client-18 libpq-dev
PG_PORT=$(pg_lsclusters --no-header | awk -v v=18 '$1 == v && $2 == "main" {print $3; exit}')
[[ "$PG_PORT" =~ ^[0-9]+$ ]] || { echo "PostgreSQL 18 main cluster missing." >&2; exit 1; }
pg_ctlcluster 18 main start
pg_isready -h 127.0.0.1 -p "$PG_PORT"

TMP_DIR=$(mktemp -d)
DB_ROLE="sherlock_ci_$(date +%s%N)_role"
DB_NAME="sherlock_ci_$(date +%s%N)"
DB_PASSWORD=$(openssl rand -hex 24)
cleanup() {
  if [[ -n "${DB_NAME:-}" ]]; then
    runuser -u postgres -- dropdb --if-exists -p "$PG_PORT" "$DB_NAME" >/dev/null 2>&1 || true
  fi
  if [[ -n "${DB_ROLE:-}" ]]; then
    runuser -u postgres -- psql -p "$PG_PORT" -v ON_ERROR_STOP=1 -c "DROP ROLE IF EXISTS \"$DB_ROLE\"" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

git clone --depth 1 --no-tags https://codeberg.org/whatstatus/sherlock-v2.git "$TMP_DIR/sherlock"
runuser -u postgres -- psql -p "$PG_PORT" -v ON_ERROR_STOP=1 \
  -v role_name="$DB_ROLE" -v role_password="$DB_PASSWORD" -v database_name="$DB_NAME" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role_name', :'role_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I ENCODING %L', :'database_name', :'role_name', 'UTF8') \gexec
SQL

PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p "$PG_PORT" -U "$DB_ROLE" -d "$DB_NAME" \
  -v ON_ERROR_STOP=1 -f "$TMP_DIR/sherlock/db/structure.sql"
TABLE_COUNT=$(PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p "$PG_PORT" -U "$DB_ROLE" -d "$DB_NAME" \
  -Atc "SELECT count(*) FROM information_schema.tables WHERE table_schema='sherlockdb' AND table_type='BASE TABLE'")
SCHEMA_OWNER=$(PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p "$PG_PORT" -U "$DB_ROLE" -d "$DB_NAME" \
  -Atc "SELECT pg_get_userbyid(nspowner) FROM pg_namespace WHERE nspname='sherlockdb'")
[[ "$TABLE_COUNT" =~ ^[0-9]+$ && "$TABLE_COUNT" -ge 20 ]] || {
  echo "Expected Sherlock tables were not loaded; found $TABLE_COUNT." >&2
  exit 1
}
[[ "$SCHEMA_OWNER" == "$DB_ROLE" ]] || {
  echo "sherlockdb schema owner is '$SCHEMA_OWNER', expected '$DB_ROLE'." >&2
  exit 1
}

echo "PASS: Debian $MAJOR resolved native package dependencies and PostgreSQL 18 loaded the upstream structure as the dedicated application role."
