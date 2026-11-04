#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
RESTORE="$ROOT/scripts/restore.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/app/config/credentials" "$TMP/etc"
printf 'test-master-key\n' > "$TMP/app/config/credentials/production.key"
printf 'encrypted-placeholder\n' > "$TMP/app/config/credentials/production.yml.enc"
cat > "$TMP/etc/sherlock.env" <<'ENV'
RAILS_ENV=production
APP_HOST=stats.example.com
RAILS_MASTER_KEY=test-master-key
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=sherlockdb_prod
DB_USER=sherlockdb_prod_write
DB_PASSWORD=0123456789abcdef0123456789abcdef
ENV

tar -czf "$TMP/good.tar.gz" \
  -C "$TMP/app" config/credentials/production.key config/credentials/production.yml.enc \
  -C "$TMP/etc" sherlock.env
bash "$RESTORE" --verify "$TMP/good.tar.gz"

mkdir -p "$TMP/evil"
printf 'payload\n' > "$TMP/evil/payload"
tar -czf "$TMP/evil.tar.gz" -C "$TMP/evil" payload
if bash "$RESTORE" --verify "$TMP/evil.tar.gz" >/dev/null 2>&1; then
  echo "ERROR: unexpected archive member was accepted." >&2
  exit 1
fi

cat > "$TMP/etc/evil.env" <<'ENV'
RAILS_ENV=production
APP_HOST=stats.example.com
RAILS_MASTER_KEY=test-master-key
DB_HOST=127.0.0.1
DB_PORT=5432
DB_NAME=sherlockdb_prod
DB_USER=sherlockdb_prod_write
DB_PASSWORD=$(touch /tmp/should-not-run)
ENV
tar -czf "$TMP/evil-env.tar.gz" \
  -C "$TMP/app" config/credentials/production.key config/credentials/production.yml.enc \
  -C "$TMP/etc" evil.env
# Rename the malicious environment member to the expected archive member.
mkdir -p "$TMP/malicious/config/credentials"
cp "$TMP/app/config/credentials/production.key" "$TMP/malicious/config/credentials/production.key"
cp "$TMP/app/config/credentials/production.yml.enc" "$TMP/malicious/config/credentials/production.yml.enc"
cp "$TMP/etc/evil.env" "$TMP/malicious/sherlock.env"
tar -czf "$TMP/malicious-env.tar.gz" -C "$TMP/malicious" config/credentials/production.key config/credentials/production.yml.enc sherlock.env
if bash "$RESTORE" --verify "$TMP/malicious-env.tar.gz" >/dev/null 2>&1; then
  echo "ERROR: unsafe environment content was accepted." >&2
  exit 1
fi

tar -czf "$TMP/incomplete.tar.gz" \
  -C "$TMP/app" config/credentials/production.key config/credentials/production.yml.enc
if bash "$RESTORE" --verify "$TMP/incomplete.tar.gz" >/dev/null 2>&1; then
  echo "ERROR: incomplete secrets archive was accepted." >&2
  exit 1
fi

# Verify a PostgreSQL dump before it is ever allowed to replace a live database.
mkdir -p "$TMP/fake-pg"
cat > "$TMP/fake-pg/pg_restore" <<'PG'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${1:-}" == --list && $# -eq 2 ]] || exit 2
grep -Fxq 'VALID-POSTGRES-DUMP' "$2"
PG
chmod 0755 "$TMP/fake-pg/pg_restore"
printf 'VALID-POSTGRES-DUMP\n' > "$TMP/valid.dump"
PG_BINDIR="$TMP/fake-pg" bash "$RESTORE" --verify-dump "$TMP/valid.dump"

printf 'NOT-A-POSTGRES-DUMP\n' > "$TMP/invalid.dump"
if PG_BINDIR="$TMP/fake-pg" bash "$RESTORE" --verify-dump "$TMP/invalid.dump" >/dev/null 2>&1; then
  echo "ERROR: invalid PostgreSQL dump was accepted." >&2
  exit 1
fi

echo "PASS: restore archive and PostgreSQL dump preflight validation"
