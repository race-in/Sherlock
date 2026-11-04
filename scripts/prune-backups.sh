#!/usr/bin/env bash
set -Eeuo pipefail

DEST="$1"
RETENTION_DAYS="$2"

[[ -n "$DEST" && -n "$RETENTION_DAYS" ]] || {
  echo "Usage: $0 <backup-directory> <retention-days>" >&2
  exit 2
}
[[ "$RETENTION_DAYS" =~ ^[1-9][0-9]*$ ]] || {
  echo "Retention days must be a positive integer." >&2
  exit 2
}
[[ -d "$DEST" && ! -L "$DEST" ]] || {
  echo "Backup directory is missing or is a symlink: $DEST" >&2
  exit 1
}

while IFS= read -r -d '' manifest; do
  manifest_base=$(basename -- "$manifest")
  stamp=$(printf '%s\n' "$manifest_base" | sed -e 's/^manifest-//' -e 's/\.txt$//')
  [[ "$stamp" =~ ^[0-9]{8}T[0-9]{6}\.[0-9]{9}Z-[0-9]+$ ]] || {
    echo "WARN: ignoring manifest with invalid timestamp: $manifest" >&2
    continue
  }

  db_name=$(sed -n 's/^database=//p' "$manifest" | head -n 1)
  secrets_name=$(sed -n 's/^secrets_archive=//p' "$manifest" | head -n 1)
  [[ "$db_name" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || {
    echo "WARN: ignoring manifest with invalid database name: $manifest" >&2
    continue
  }
  [[ "$secrets_name" == "sherlock-secrets-$stamp.tar.gz" ]] || {
    echo "WARN: ignoring manifest with mismatched secrets archive name: $manifest" >&2
    continue
  }
  grep -Fxq "created_at_utc=$stamp" "$manifest" || {
    echo "WARN: ignoring manifest with mismatched creation timestamp: $manifest" >&2
    continue
  }

  dump="$DEST/$db_name-$stamp.dump"
  secrets="$DEST/$secrets_name"
  if [[ ! -f "$dump" || -L "$dump" || ! -s "$dump" ||
        ! -f "$secrets" || -L "$secrets" || ! -s "$secrets" ]]; then
    echo "WARN: retaining incomplete backup set: $stamp" >&2
    continue
  fi

  if find "$manifest" -maxdepth 0 -type f -mtime "+$RETENTION_DAYS" -print -quit | grep -q .; then
    rm -f -- "$dump" "$secrets" "$manifest"
    echo "Pruned complete backup set older than $RETENTION_DAYS days: $stamp"
  fi
done < <(find "$DEST" -maxdepth 1 -type f -name 'manifest-*.txt' -print0)
