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
mkdir -p "$TMP/app/config/initializers"
cat > "$TMP/app/config/initializers/yabeda.rb" <<'YABEDA'
Yabeda::Prometheus::Exporter.rack_handler.run(Yabeda::Prometheus::Exporter.rack_app,
  Host: "0.0.0.0", Port: ENV.fetch("METRICS_PORT", 9394).to_i, AccessLog: [])
YABEDA

bash "$PATCHER" "$TMP/app"
grep -Fq "bind \"tcp://127.0.0.1:#{ENV.fetch('PORT', 3000)}\"" "$TMP/app/config/puma.rb"
grep -Fq 'pool: <%= ENV.fetch("DB_POOL") { ENV.fetch("RAILS_MAX_THREADS") { 10 } } %>' "$TMP/app/config/database.yml"
grep -Fq 'Host: ENV.fetch("METRICS_HOST", "127.0.0.1")' "$TMP/app/config/initializers/yabeda.rb"

# Check that the generated Ruby configuration remains syntactically valid.
ruby -c "$TMP/app/config/puma.rb"
ruby -c "$TMP/app/config/initializers/yabeda.rb"
ruby -rerb -e 'RubyVM::InstructionSequence.compile(ERB.new(File.read(ARGV.fetch(0))).src)' \
  "$TMP/app/config/database.yml"

# Patching again must be idempotent.
bash "$PATCHER" "$TMP/app"

# Unknown upstream source must fail closed.
mkdir -p "$TMP/bad/config"
printf 'port 3000\n' > "$TMP/bad/config/puma.rb"
cp "$TMP/app/config/database.yml" "$TMP/bad/config/database.yml"
mkdir -p "$TMP/bad/config/initializers"
cp "$TMP/app/config/initializers/yabeda.rb" "$TMP/bad/config/initializers/yabeda.rb"
if bash "$PATCHER" "$TMP/bad" >/dev/null 2>&1; then
  echo "ERROR: patcher accepted an unknown Puma config." >&2
  exit 1
fi

echo "PASS: native application patches, idempotency, and drift detection"
