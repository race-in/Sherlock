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

rewrite_list_file() {
  local source_file=$1
  local temp_file
  temp_file=$(mktemp)
  awk '
    function rewrite_uri(value) {
      gsub(/https:\/\/deb\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/http:\/\/deb\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/https:\/\/ftp\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/http:\/\/ftp\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/https:\/\/httpredir\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/http:\/\/httpredir\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/https:\/\/security\.debian\.org\/debian-security/, "http://archive.debian.org/debian-security", value)
      gsub(/http:\/\/security\.debian\.org\/debian-security/, "http://archive.debian.org/debian-security", value)
      return value
    }
    {
      if ($0 ~ /^[[:space:]]*#/ || $0 !~ /^[[:space:]]*deb(-src)?[[:space:]]/) {
        print
        next
      }
      if ($0 ~ /bullseye-backports(-sloppy)?([[:space:]]|$)/) {
        print "# Disabled after Debian 11 LTS EOL: " $0
        next
      }
      line = rewrite_uri($0)
      if (line ~ /archive\.debian\.org/ && line !~ /check-valid-until=/) {
        if (line ~ /^deb(-src)?[[:space:]]+\[[^]]*\]/) {
          sub(/\]/, " check-valid-until=no]", line)
        } else {
          sub(/^(deb-src|deb)[[:space:]]+/, "&[check-valid-until=no] ", line)
        }
      }
      print line
    }
  ' "$source_file" > "$temp_file"

  if ! cmp -s "$source_file" "$temp_file"; then
    cp -a "$source_file" "$BACKUP_DIR/$(basename "$source_file").bak"
    cat "$temp_file" > "$source_file"
    echo "Updated: $source_file"
  fi
  rm -f "$temp_file"
}

rewrite_deb822_file() {
  local source_file=$1
  local temp_file
  temp_file=$(mktemp)
  awk '
    BEGIN { RS = ""; ORS = "" }
    function rewrite_uri(value) {
      gsub(/https:\/\/deb\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/http:\/\/deb\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/https:\/\/ftp\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/http:\/\/ftp\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/https:\/\/httpredir\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/http:\/\/httpredir\.debian\.org\/debian/, "http://archive.debian.org/debian", value)
      gsub(/https:\/\/security\.debian\.org\/debian-security/, "http://archive.debian.org/debian-security", value)
      gsub(/http:\/\/security\.debian\.org\/debian-security/, "http://archive.debian.org/debian-security", value)
      return value
    }
    {
      count = split($0, lines, "\n")
      drop_stanza = 0
      has_archive = 0
      has_validity_option = 0
      for (i = 1; i <= count; i++) {
        if (lines[i] ~ /^Suites:[[:space:]]*/) {
          value = lines[i]
          sub(/^Suites:[[:space:]]*/, "", value)
          suite_count = split(value, suites, /[[:space:]]+/)
          kept = ""
          for (j = 1; j <= suite_count; j++) {
            if (suites[j] == "" || suites[j] == "bullseye-backports" || suites[j] == "bullseye-backports-sloppy") {
              continue
            }
            kept = kept (kept == "" ? "" : " ") suites[j]
          }
          if (kept == "") {
            drop_stanza = 1
          } else {
            lines[i] = "Suites: " kept
          }
        }
      }
      if (drop_stanza) next
      output = ""
      for (i = 1; i <= count; i++) {
        if (lines[i] ~ /^URIs:[[:space:]]*/) {
          lines[i] = rewrite_uri(lines[i])
          if (lines[i] ~ /archive\.debian\.org/) has_archive = 1
        }
        if (lines[i] ~ /^Check-Valid-Until:[[:space:]]*/) has_validity_option = 1
        output = output (i == 1 ? "" : "\n") lines[i]
      }
      if (has_archive && !has_validity_option) output = output "\nCheck-Valid-Until: no"
      printf "%s\n\n", output
    }
  ' "$source_file" > "$temp_file"

  if ! cmp -s "$source_file" "$temp_file"; then
    cp -a "$source_file" "$BACKUP_DIR/$(basename "$source_file").bak"
    cat "$temp_file" > "$source_file"
    echo "Updated: $source_file"
  fi
  rm -f "$temp_file"
}

if [[ -f "$APT_DIR/sources.list" ]]; then
  rewrite_list_file "$APT_DIR/sources.list"
fi
if [[ -d "$APT_DIR/sources.list.d" ]]; then
  while IFS= read -r -d '' source_file; do
    rewrite_list_file "$source_file"
  done < <(find "$APT_DIR/sources.list.d" -maxdepth 1 -type f -name '*.list' -print0 | sort -z)

  while IFS= read -r -d '' source_file; do
    rewrite_deb822_file "$source_file"
  done < <(find "$APT_DIR/sources.list.d" -maxdepth 1 -type f -name '*.sources' -print0 | sort -z)
fi

# Older kit versions wrote a global validity override. Remove only our one-line setting
# and preserve any other administrator-supplied APT options in that file.
APT_CONF="$APT_DIR/apt.conf.d/99sherlock-bullseye-archive"
if [[ -f "$APT_CONF" ]]; then
  TEMP_CONF=$(mktemp)
  awk '$0 != "Acquire::Check-Valid-Until \"false\";" { print }' "$APT_CONF" > "$TEMP_CONF"
  if cmp -s "$APT_CONF" "$TEMP_CONF"; then
    rm -f "$TEMP_CONF"
  else
    cp -a "$APT_CONF" "$BACKUP_DIR/$(basename "$APT_CONF").bak"
    if [[ -s "$TEMP_CONF" ]]; then
      cat "$TEMP_CONF" > "$APT_CONF"
    else
      rm -f "$APT_CONF"
    fi
    rm -f "$TEMP_CONF"
    echo "Removed the legacy global APT validity override."
  fi
fi

echo "Bullseye APT sources now use archive.debian.org."
echo "Check-Valid-Until is disabled only on archived Debian source entries; third-party repositories keep normal Release-date validation."
echo "Bullseye security packages are retained only from the frozen archive; no further Debian LTS security updates exist. Expired backports suites are disabled."
echo "Original source backups: $BACKUP_DIR"
