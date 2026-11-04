#!/usr/bin/env bash
set -Eeuo pipefail

APP_ROOT=${1:-}
[[ -n "$APP_ROOT" && -d "$APP_ROOT" ]] || {
  echo "Usage: $0 /path/to/sherlock-app" >&2
  exit 2
}

python3 - "$APP_ROOT" <<'PY'
from pathlib import Path
import os
import stat
import sys
import tempfile

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
    Path("config/initializers/yabeda.rb"): (
        'Host: "0.0.0.0", Port: ENV.fetch("METRICS_PORT", 9394).to_i',
        'Host: ENV.fetch("METRICS_HOST", "127.0.0.1"), Port: ENV.fetch("METRICS_PORT", 9394).to_i',
    ),
}

# Validate every expected source before changing any file. This prevents a
# source-layout mismatch late in the patch list from leaving a half-patched app.
updates: dict[Path, tuple[str, int]] = {}
errors = False

for relative, (upstream, patched) in patches.items():
    path = root / relative
    if not path.is_file() or path.is_symlink():
        print(f"ERROR: expected regular application file missing: {path}", file=sys.stderr)
        errors = True
        continue

    content = path.read_text(encoding="utf-8")
    upstream_count = content.count(upstream)
    patched_count = content.count(patched)

    if patched_count == 1 and upstream_count == 0:
        print(f"OK: already patched {relative}")
        continue
    if upstream_count == 1 and patched_count == 0:
        updates[relative] = (content.replace(upstream, patched, 1), stat.S_IMODE(path.stat().st_mode))
        continue

    print(
        f"ERROR: unexpected source layout in {relative}; "
        f"expected exactly one upstream line or one already-patched line "
        f"(found upstream={upstream_count}, patched={patched_count}).",
        file=sys.stderr,
    )
    errors = True

if errors:
    sys.exit(1)

# Each file replacement is atomic. All source validation has already passed.
for relative, (content, mode) in updates.items():
    path = root / relative
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    print(f"PATCHED: {relative}")
PY
