#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PRUNE="$ROOT/scripts/prune-backups.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BACKUPS="$TMP/backups"
mkdir -m 0700 "$BACKUPS"

make_set() {
  local stamp=$1
  local db_name=${2:-sherlockdb_prod}
  local secrets_name="sherlock-secrets-$stamp.tar.gz"

  printf 'dump\\n' > "$BACKUPS/$db_name-$stamp.dump"
  printf 'secrets\\n' > "$BACKUPS/$secrets_name"
  cat > "$BACKUPS/manifest-$stamp.txt" <<MANIFEST
created_at_utc=$stamp
application_commit=0123456789abcdef
database=$db_name
secrets_archive=$secrets_name
MANIFEST
}

OLD=20261001T010203.123456789Z-100
NEW=20261103T010203.123456789Z-101
INCOMPLETE=20261001T010203.123456789Z-102
BADSTAMP=not-a-valid-timestamp
MISMATCH=20261001T010203.123456789Z-103

make_set "$OLD"
make_set "$NEW"
make_set "$INCOMPLETE"
make_set "$MISMATCH"
rm "$BACKUPS/sherlock-secrets-$INCOMPLETE.tar.gz"
sed -i 's/^secrets_archive=.*/secrets_archive=sherlock-secrets-20261001T010204.123456789Z-999.tar.gz/' \
  "$BACKUPS/manifest-$MISMATCH.txt"

printf 'dump\\n' > "$BACKUPS/anotherdb-$BADSTAMP.dump"
printf 'secrets\\n' > "$BACKUPS/sherlock-secrets-$BADSTAMP.tar.gz"
printf 'database=sherlockdb_prod\\nsecrets_archive=sherlock-secrets-%s.tar.gz\\ncreated_at_utc=%s\\n' \
  "$BADSTAMP" "$BADSTAMP" > "$BACKUPS/manifest-$BADSTAMP.txt"

touch -d '10 days ago' \
  "$BACKUPS/sherlockdb_prod-$OLD.dump" \
  "$BACKUPS/sherlock-secrets-$OLD.tar.gz" \
  "$BACKUPS/manifest-$OLD.txt"
touch -d '1 day ago' \
  "$BACKUPS/sherlockdb_prod-$NEW.dump" \
  "$BACKUPS/sherlock-secrets-$NEW.tar.gz" \
  "$BACKUPS/manifest-$NEW.txt"
touch -d '10 days ago' \
  "$BACKUPS/sherlockdb_prod-$INCOMPLETE.dump" \
  "$BACKUPS/manifest-$INCOMPLETE.txt"
touch -d '10 days ago' \
  "$BACKUPS/sherlockdb_prod-$MISMATCH.dump" \
  "$BACKUPS/sherlock-secrets-$MISMATCH.tar.gz" \
  "$BACKUPS/manifest-$MISMATCH.txt"
touch -d '10 days ago' \
  "$BACKUPS/anotherdb-$BADSTAMP.dump" \
  "$BACKUPS/sherlock-secrets-$BADSTAMP.tar.gz" \
  "$BACKUPS/manifest-$BADSTAMP.txt"

if bash "$PRUNE" >/dev/null 2>&1; then
  echo 'ERROR: missing arguments were accepted.' >&2
  exit 1
else
  status=$?
  [[ $status -eq 2 ]] || {
    echo "ERROR: missing arguments returned status $status instead of 2." >&2
    exit 1
  }
fi
if bash "$PRUNE" "$BACKUPS" 0 >/dev/null 2>&1; then
  echo 'ERROR: zero retention days were accepted.' >&2
  exit 1
fi
bash "$PRUNE" "$BACKUPS" 7

for path in \
  "$BACKUPS/sherlockdb_prod-$OLD.dump" \
  "$BACKUPS/sherlock-secrets-$OLD.tar.gz" \
  "$BACKUPS/manifest-$OLD.txt"; do
  [[ ! -e "$path" ]] || {
    echo "ERROR: old complete backup was not pruned: $path" >&2
    exit 1
  }
done

for path in \
  "$BACKUPS/sherlockdb_prod-$NEW.dump" \
  "$BACKUPS/sherlock-secrets-$NEW.tar.gz" \
  "$BACKUPS/manifest-$NEW.txt" \
  "$BACKUPS/sherlockdb_prod-$INCOMPLETE.dump" \
  "$BACKUPS/manifest-$INCOMPLETE.txt" \
  "$BACKUPS/sherlockdb_prod-$MISMATCH.dump" \
  "$BACKUPS/sherlock-secrets-$MISMATCH.tar.gz" \
  "$BACKUPS/manifest-$MISMATCH.txt" \
  "$BACKUPS/anotherdb-$BADSTAMP.dump" \
  "$BACKUPS/sherlock-secrets-$BADSTAMP.tar.gz" \
  "$BACKUPS/manifest-$BADSTAMP.txt"; do
  [[ -e "$path" ]] || {
    echo "ERROR: recent, invalid, or incomplete backup data was removed: $path" >&2
    exit 1
  }
done

ln -s "$BACKUPS" "$TMP/backup-link"
if bash "$PRUNE" "$TMP/backup-link" 7 >/dev/null 2>&1; then
  echo 'ERROR: symlink backup directory was accepted.' >&2
  exit 1
fi

echo 'PASS: backup retention removes only old, complete, matching backup sets'
