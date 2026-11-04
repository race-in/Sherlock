#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR=${1:-}
[[ -n "$APP_DIR" && -d "$APP_DIR" ]] || {
  echo "Usage: $0 /path/to/upstream-sherlock" >&2
  exit 2
}
[[ -f "$APP_DIR/Gemfile" && -f "$APP_DIR/config/routes.rb" ]] || {
  echo "ERROR: source tree is not a Rails application." >&2
  exit 1
}

printf '%s\n' '=== UPSTREAM SHERLOCK AUDIT (STRUCTURE ONLY) ==='
printf 'commit=%s\n' "$(git -C "$APP_DIR" rev-parse HEAD)"
printf 'origin=%s\n' "$(git -C "$APP_DIR" remote get-url origin)"
printf 'ruby_pin=%s\n' "$(tr -d '\r\n' < "$APP_DIR/.ruby-version")"
printf 'node_pin=%s\n' "$(tr -d '\r\n' < "$APP_DIR/.node-version")"

license_count=$(find "$APP_DIR" -maxdepth 2 -type f \
  \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \) \
  -not -path '*/vendor/*' -print | wc -l)
printf 'license_files=%s\n' "$license_count"
if (( license_count > 0 )); then
  find "$APP_DIR" -maxdepth 2 -type f \
    \( -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname 'COPYING' -o -iname 'COPYING.*' \) \
    -not -path '*/vendor/*' -printf '%P\n' | sort
else
  echo 'LICENSE_STATUS=NO_STANDALONE_LICENSE_FOUND'
fi

printf '%s\n' '--- Authentication dependencies ---'
grep -nEi 'devise|warden|authlogic|has_secure_password|rodauth' "$APP_DIR/Gemfile" "$APP_DIR/Gemfile.lock" 2>/dev/null | head -40 || true

printf '%s\n' '--- User/account model files ---'
find "$APP_DIR/app/models" -maxdepth 3 -type f -name '*.rb' -printf '%P\n' 2>/dev/null | sort | head -100 || true
printf '%s\n' '--- User/account controller files ---'
find "$APP_DIR/app/controllers" -maxdepth 4 -type f -name '*.rb' -printf '%P\n' 2>/dev/null | sort | grep -Ei 'user|account|session|registration|application_controller' | head -100 || true
printf '%s\n' '--- Authentication-related route declarations ---'
grep -nEi 'devise|user|account|session|registration|sign.?up|invite' "$APP_DIR/config/routes.rb" 2>/dev/null | head -100 || true

printf '%s\n' '--- Database table names ---'
if [[ -f "$APP_DIR/db/structure.sql" ]]; then
  grep -E '^CREATE TABLE (public\.)?[a-zA-Z0-9_]+' "$APP_DIR/db/structure.sql" \
    | sed -E 's/^CREATE TABLE (public\.)?//' | sed -E 's/[ (].*$//' | sort -u | head -200
elif [[ -f "$APP_DIR/db/schema.rb" ]]; then
  grep -E '^[[:space:]]*create_table "' "$APP_DIR/db/schema.rb" \
    | sed -E 's/.*create_table "([^"]+)".*/\1/' | sort -u | head -200
fi

printf '%s\n' '--- Recent migrations ---'
find "$APP_DIR/db/migrate" -maxdepth 1 -type f -name '*.rb' -printf '%f\n' 2>/dev/null | sort | tail -60 || true

printf '%s\n' '--- Relevant source counts ---'
for dir in app/models app/controllers app/views app/jobs app/services db/migrate test spec; do
  if [[ -d "$APP_DIR/$dir" ]]; then
    count=$(find "$APP_DIR/$dir" -type f | wc -l)
    printf '%s=%s\n' "$dir" "$count"
  fi
done
printf '%s\n' '=== END UPSTREAM AUDIT ==='
