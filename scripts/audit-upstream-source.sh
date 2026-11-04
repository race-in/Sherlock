#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR=${1:-}
[[ -n "$APP_DIR" && -d "$APP_DIR" ]] || {
  echo "Usage: $0 /path/to/upstream-sherlock-checkout" >&2
  exit 2
}

echo "=== UPSTREAM SOURCE AUDIT ==="
printf 'commit='
git -C "$APP_DIR" rev-parse HEAD
printf 'remote='
git -C "$APP_DIR" remote get-url origin

echo "--- Licence and project metadata ---"
find "$APP_DIR" -maxdepth 2 -type f \
  \( -iname 'license*' -o -iname 'copying*' -o -iname 'notice*' -o -iname 'authors*' \
     -o -iname 'readme*' -o -iname 'contributing*' -o -iname 'code_of_conduct*' \) \
  -printf '%P\n' | sort

echo "--- Rails application directories ---"
for directory in app/models app/controllers app/jobs app/services app/mailers app/helpers app/views db/migrate; do
  if [[ -d "$APP_DIR/$directory" ]]; then
    echo "[$directory]"
    find "$APP_DIR/$directory" -type f -name '*.rb' -o -type f -name '*.erb' 2>/dev/null \
      | sed "s#^$APP_DIR/##" | sort
  fi
done

echo "--- Routes ---"
if [[ -f "$APP_DIR/config/routes.rb" ]]; then
  sed -n '1,260p' "$APP_DIR/config/routes.rb"
fi

echo "--- Model source ---"
if [[ -d "$APP_DIR/app/models" ]]; then
  while IFS= read -r file; do
    echo "### ${file#"$APP_DIR/"}"
    sed -n '1,240p' "$file"
  done < <(find "$APP_DIR/app/models" -type f -name '*.rb' | sort)
fi

echo "--- Statistics, tracker, authentication and import/export references ---"
grep -R -n -E 'class .*Statistic|class .*Tracker|devise|has_secure_password|registration|invite|tracker|upload|download|ratio|csv|json|snapshot|history' \
  "$APP_DIR/app/controllers" "$APP_DIR/app/jobs" "$APP_DIR/app/services" "$APP_DIR/config/routes.rb" \
  --include='*.rb' 2>/dev/null | head -n 300 || true

echo "--- Selected controller and configuration source ---"
for relative in \
  app/controllers/application_controller.rb \
  app/controllers/concerns/authentication.rb \
  app/controllers/first_runs_controller.rb \
  app/controllers/joins_controller.rb \
  app/controllers/sessions_controller.rb \
  app/controllers/admin/base_controller.rb \
  app/controllers/admin/users_controller.rb \
  app/controllers/settings/imports_controller.rb \
  app/controllers/settings/exports_controller.rb \
  app/controllers/settings/data_controller.rb \
  app/models/site.rb \
  app/models/instance_setting.rb \
  app/models/engines.rb \
  config/application.rb \
  README.md Gemfile; do
  file="$APP_DIR/$relative"
  [[ -f "$file" ]] || continue
  echo "### $relative"
  sed -n '1,300p' "$file"
done

echo "--- Database table inventory ---"
if [[ -f "$APP_DIR/db/structure.sql" ]]; then
  grep -E '^CREATE TABLE|^CREATE SEQUENCE|^CREATE TYPE|^CREATE UNIQUE INDEX|^ALTER TABLE ONLY .* ADD CONSTRAINT' \
    "$APP_DIR/db/structure.sql" | head -n 300
fi

echo "--- Test inventory ---"
for directory in test spec; do
  if [[ -d "$APP_DIR/$directory" ]]; then
    find "$APP_DIR/$directory" -type f | sed "s#^$APP_DIR/##" | sort | head -n 250
  fi
done

echo "--- Exact data columns for accounts, tracker connections and snapshots ---"
if [[ -f "$APP_DIR/db/structure.sql" ]]; then
  awk '
    /^CREATE TABLE sherlockdb\\.(users|connections|snapshots) \\(/ { show = 1 }
    show { print }
    show && /^\\);$/ { show = 0; print "" }
    /^CREATE (UNIQUE )?INDEX .*\\b(on users|on connections|on snapshots)/ { print }
  ' "$APP_DIR/db/structure.sql"
fi

echo "--- User import/export contract ---"
if [[ -f "$APP_DIR/app/models/user.rb" ]]; then
  grep -n -E -A65 -B8 'IMPORT_COLUMNS|def export|def import!|def import_rows' "$APP_DIR/app/models/user.rb"
fi

echo "=== END UPSTREAM SOURCE AUDIT ==="
