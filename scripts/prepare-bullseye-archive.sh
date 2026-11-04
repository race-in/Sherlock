#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 || -n "${APT_SOURCE_ROOT:-}" ]] || { echo "Run as root." >&2; exit 1; }
ROOT=${APT_SOURCE_ROOT:-/}
APT_DIR="$ROOT/etc/apt"
[[ -d "$APT_DIR" ]] || { echo "APT directory not found: $APT_DIR" >&2; exit 1; }

STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="$ROOT/var/backups/sherlock-apt-sources-$STAMP"
mkdir -p "$BACKUP_DIR"
chmod 0700 "$BACKUP_DIR"

python3 - "$APT_DIR" "$BACKUP_DIR" "$ROOT" <<'PY'
from pathlib import Path
import re
import shutil
import sys

apt_dir = Path(sys.argv[1])
backup_dir = Path(sys.argv[2])
root = Path(sys.argv[3])

list_files = ([apt_dir / "sources.list"] if (apt_dir / "sources.list").exists() else [])
list_files += sorted((apt_dir / "sources.list.d").glob("*.list")) if (apt_dir / "sources.list.d").exists() else []
deb822_files = sorted((apt_dir / "sources.list.d").glob("*.sources")) if (apt_dir / "sources.list.d").exists() else []

replacements = (
    ("https://deb.debian.org/debian", "https://archive.debian.org/debian"),
    ("http://deb.debian.org/debian", "https://archive.debian.org/debian"),
    ("https://ftp.debian.org/debian", "https://archive.debian.org/debian"),
    ("http://ftp.debian.org/debian", "https://archive.debian.org/debian"),
    ("https://httpredir.debian.org/debian", "https://archive.debian.org/debian"),
    ("http://httpredir.debian.org/debian", "https://archive.debian.org/debian"),
)
removed_suites = {"bullseye-security", "bullseye-backports", "bullseye-backports-sloppy"}

def rewrite_uri(value: str) -> str:
    for old, new in replacements:
        value = value.replace(old, new)
    return value

changed = []
for path in list_files:
    original = path.read_text(encoding="utf-8")
    lines = []
    modified = False
    for line in original.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            lines.append(line)
            continue
        if "security.debian.org" in stripped or re.search(r"\bbullseye-security\b", stripped):
            lines.append("# Disabled after Debian 11 LTS EOL: " + line)
            modified = True
            continue
        updated = rewrite_uri(line)
        if updated != line:
            modified = True
        lines.append(updated)
    if modified:
        shutil.copy2(path, backup_dir / (path.name + ".bak"))
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        changed.append(str(path))

for path in deb822_files:
    original = path.read_text(encoding="utf-8")
    stanzas = re.split(r"\n\s*\n", original.strip()) if original.strip() else []
    output = []
    modified = False
    for stanza in stanzas:
        lines = stanza.splitlines()
        fields = {}
        for line in lines:
            if line and not line[0].isspace() and ":" in line:
                key, value = line.split(":", 1)
                fields[key.lower()] = value.strip()
        uris = fields.get("uris", "")
        suites = fields.get("suites", "").split()
        if "security.debian.org" in uris or any(suite in removed_suites for suite in suites):
            kept = [suite for suite in suites if suite not in removed_suites]
            if not kept:
                modified = True
                continue
            new_lines = []
            for line in lines:
                if line.lower().startswith("suites:"):
                    new_lines.append("Suites: " + " ".join(kept))
                else:
                    new_lines.append(line)
            lines = new_lines
            modified = True
        new_lines = [rewrite_uri(line) for line in lines]
        if new_lines != lines:
            modified = True
        output.append("\n".join(new_lines))
    if modified:
        shutil.copy2(path, backup_dir / (path.name + ".bak"))
        path.write_text("\n\n".join(output).rstrip() + "\n", encoding="utf-8")
        changed.append(str(path))

apt_conf = apt_dir / "apt.conf.d" / "99sherlock-bullseye-archive"
apt_conf.parent.mkdir(parents=True, exist_ok=True)
conf = 'Acquire::Check-Valid-Until "false";\n'
if not apt_conf.exists() or apt_conf.read_text(encoding="utf-8") != conf:
    if apt_conf.exists():
        shutil.copy2(apt_conf, backup_dir / (apt_conf.name + ".bak"))
    apt_conf.write_text(conf, encoding="utf-8")
    changed.append(str(apt_conf))

print("Bullseye APT sources now use archive.debian.org.")
print("Disabled expired Bullseye security/backports suites (there are no further Debian LTS updates).")
print("Backup:", backup_dir)
for item in changed:
    print("Updated:", item)
PY

echo "Bullseye archive source preparation complete. No Debian 11 security updates are available."
