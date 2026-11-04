#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT=${1:-}
[[ -n "$APP_ROOT" && -d "$APP_ROOT" ]] || {
  echo "Usage: $0 /path/to/sherlock-app" >&2
  exit 2
}

python3 - "$APP_ROOT" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
patches = {
    Path("config/puma.rb"): (
        'port ENV.fetch("PORT", 3000)',
        'bind "tcp://127.0.0.1:#{ENV.fetch(\'PORT\', 3000)}"',
    ),
    Path("config/database.yml"): (
        'pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 10 } %>',
        'pool: <%= ENV.fetch("DB_POOL") { ENV.fetch("RAILS_MAX_THREADS") { 10 } } %>',
    ),
}

failed = False
for relative, (upstream, patched) in patches.items():
    path = root / relative
    if not path.is_file():
        print(f"ERROR: expected application file missing: {path}", file=sys.stderr)
        failed = True
        continue
    content = path.read_text(encoding="utf-8")
    upstream_count = content.count(upstream)
    patched_count = content.count(patched)

    if patched_count == 1 and upstream_count == 0:
        print(f"OK: already patched {relative}")
        continue
    if upstream_count == 1 and patched_count == 0:
        path.write_text(content.replace(upstream, patched, 1), encoding="utf-8")
        print(f"PATCHED: {relative}")
        continue

    print(
        f"ERROR: unexpected source layout in {relative}; "
        f"expected exactly one upstream line or one already-patched line "
        f"(found upstream={upstream_count}, patched={patched_count}).",
        file=sys.stderr,
    )
    failed = True

if failed:
    sys.exit(1)
PY
