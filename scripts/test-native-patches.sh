#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PATCHER="$ROOT/scripts/patch-native-app.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

make_app() {
  local app=$1
  mkdir -p "$app/config/initializers"
  cat > "$app/config/puma.rb" <<'PUMA'
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count
port ENV.fetch("PORT", 3000)
PUMA
  cat > "$app/config/database.yml" <<'DB'
default: &default
  adapter: postgresql
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 10 } %>
DB
  cat > "$app/config/initializers/yabeda.rb" <<'YABEDA'
Yabeda::Prometheus::Exporter.rack_handler.run(Yabeda::Prometheus::Exporter.rack_app,
  Host: "0.0.0.0", Port: ENV.fetch("METRICS_PORT", 9394).to_i, AccessLog: [])
YABEDA
}

mkdir -p "$TMP/app"
make_app "$TMP/app"

bash "$PATCHER" "$TMP/app"
grep -Fq "bind \"tcp://127.0.0.1:#{ENV.fetch('PORT', 3000)}\"" "$TMP/app/config/puma.rb"
grep -Fq 'pool: <%= ENV.fetch("DB_POOL") { ENV.fetch("RAILS_MAX_THREADS") { 10 } } %>' "$TMP/app/config/database.yml"
grep -Fq 'Host: ENV.fetch("METRICS_HOST", "127.0.0.1")' "$TMP/app/config/initializers/yabeda.rb"

ruby -c "$TMP/app/config/puma.rb"
ruby -c "$TMP/app/config/initializers/yabeda.rb"
ruby -rerb -e 'RubyVM::InstructionSequence.compile(ERB.new(File.read(ARGV.fetch(0))).src)' \
  "$TMP/app/config/database.yml"

# Patching again must be idempotent.
bash "$PATCHER" "$TMP/app"

# Unknown source in the final patch target must fail before earlier files change.
mkdir -p "$TMP/bad"
make_app "$TMP/bad"
sed -i 's/Host: "0.0.0.0"/Host: "0.0.0.1"/' "$TMP/bad/config/initializers/yabeda.rb"
if bash "$PATCHER" "$TMP/bad" >/dev/null 2>&1; then
  echo "ERROR: patcher accepted an unknown metrics config." >&2
  exit 1
fi
grep -Fq 'port ENV.fetch("PORT", 3000)' "$TMP/bad/config/puma.rb"
grep -Fq 'pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 10 } %>' "$TMP/bad/config/database.yml"
grep -Fq 'Host: "0.0.0.1"' "$TMP/bad/config/initializers/yabeda.rb"

# A symlink must not be modified through its target.
mkdir -p "$TMP/symlink/config/initializers" "$TMP/real/config/initializers"
make_app "$TMP/real"
ln -s "$TMP/real/config/puma.rb" "$TMP/symlink/config/puma.rb"
cp "$TMP/real/config/database.yml" "$TMP/symlink/config/database.yml"
cp "$TMP/real/config/initializers/yabeda.rb" "$TMP/symlink/config/initializers/yabeda.rb"
if bash "$PATCHER" "$TMP/symlink" >/dev/null 2>&1; then
  echo "ERROR: patcher accepted a symlink application config." >&2
  exit 1
fi
grep -Fq 'port ENV.fetch("PORT", 3000)' "$TMP/real/config/puma.rb"

echo "PASS: native application patch syntax, idempotency, drift detection, and preflight atomicity"
