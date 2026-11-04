#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="$ROOT/install.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

grep -Fq 'sed -n "/^active_record_encryption:/,\$p"' "$INSTALLER"
if grep -Fq 'db:encryption:init | tail -n 4' "$INSTALLER"; then
  echo "ERROR: installer still copies the Rails instruction line into credentials." >&2
  exit 1
fi

ENCRYPTION_OUTPUT=$(cat <<'OUTPUT'
Add this entry to the credentials of the target environment:

active_record_encryption:
  primary_key: primary-key-example
  deterministic_key: deterministic-key-example
  key_derivation_salt: salt-example
OUTPUT
)

ENCRYPTION_YAML=$(printf "%s\n" "$ENCRYPTION_OUTPUT" | sed -n '/^active_record_encryption:/,$p')
[[ -n "$ENCRYPTION_YAML" ]]
for required_key in primary_key deterministic_key key_derivation_salt; do
  grep -Eq "^[[:space:]]+$required_key:" <<< "$ENCRYPTION_YAML"
done

{
  printf 'secret_key_base: %s\n' "$(printf '%064d' 0)"
  printf '%s\n' "$ENCRYPTION_YAML"
} > "$TMP/credentials.yml"

ruby -ryaml -e '
  data = YAML.safe_load_file(ARGV.fetch(0))
  abort "missing secret_key_base" unless data.fetch("secret_key_base").length == 64
  encryption = data.fetch("active_record_encryption")
  %w[primary_key deterministic_key key_derivation_salt].each do |key|
    abort "missing #{key}" unless encryption.fetch(key).end_with?("-example")
  end
  abort "unexpected instruction key" if data.key?("Add this entry to the credentials of the target environment")
' "$TMP/credentials.yml"

echo "PASS: Rails encryption setup output is reduced to valid credentials YAML."
