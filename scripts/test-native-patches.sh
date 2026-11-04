#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PATCHER="$ROOT/scripts/patch-native-app.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/app/config"
cat > "$TMP/app/config/puma.rb" <<'PUMA'
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count
port ENV.fetch("PORT", 3000)
PUMA
cat > "$TMP/app/config/database.yml" <<'DB'
default: &default
  adapter: postgresql
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 10 } %>
DB

bash "$PATCHER" "$TMP/app"
grep -Fq 'bind "tcp://127.0.0.1:#{ENV.fetch('''PORT''', 3000)}"' "$TMP/app/config/puma.rb"
grep -Fq 'pool: <%= ENV.fetch("DB_POOL") { ENV.fetch("RAILS_MAX_THREADS") { 10 } } %>' "$TMP/app/config/database.yml"

# Patching again must be idempotent.
bash "$PATCHER" "$TMP/app"

# Unknown upstream source must fail closed.
mkdir -p "$TMP/bad/config"
printf 'port 3000\n' > "$TMP/bad/config/puma.rb"
cp "$TMP/app/config/database.yml" "$TMP/bad/config/database.yml"
if bash "$PATCHER" "$TMP/bad"; then
  echo "ERROR: patcher accepted an unknown Puma config." >&2
  exit 1
fi

echo "PASS: native application patches, idempotency, and drift detection"
