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
      # Some Bullseye source lists use deb.debian.org for bullseye-security.
      # The security suite lives under the separate debian-security archive.
      if (line ~ /bullseye-security([[:space:]]|$)/) {
        gsub(/archive\.debian\.org\/debian([[:space:]]+)/,
             "archive.debian.org/debian-security ", line)
      }
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

    function normalize_uri(uri) {
      if (substr(uri, length(uri), 1) == "/") {
        return substr(uri, 1, length(uri) - 1)
      }
      return uri
    }

    function is_official_debian_uri(uri, normalized) {
      normalized = normalize_uri(uri)
      return normalized == "https://deb.debian.org/debian" ||
             normalized == "http://deb.debian.org/debian" ||
             normalized == "https://ftp.debian.org/debian" ||
             normalized == "http://ftp.debian.org/debian" ||
             normalized == "https://httpredir.debian.org/debian" ||
             normalized == "http://httpredir.debian.org/debian" ||
             normalized == "https://security.debian.org/debian-security" ||
             normalized == "http://security.debian.org/debian-security"
    }

    function rewrite_uri_for_suite(uri, suite, normalized) {
      if (!is_official_debian_uri(uri)) return uri
      normalized = normalize_uri(uri)
      if (suite == "bullseye-security" ||
          index(normalized, "security.debian.org/debian-security") > 0) {
        return "http://archive.debian.org/debian-security"
      }
      return "http://archive.debian.org/debian"
    }

    {
      count = split($0, lines, "\n")
      suites_value = ""
      uris_value = ""
      for (i = 1; i <= count; i++) {
        if (lines[i] ~ /^Suites:[[:space:]]*/) {
          suites_value = lines[i]
          sub(/^Suites:[[:space:]]*/, "", suites_value)
        }
        if (lines[i] ~ /^URIs:[[:space:]]*/) {
          uris_value = lines[i]
          sub(/^URIs:[[:space:]]*/, "", uris_value)
        }
      }

      # Leave third-party-only and non-Bullseye source stanzas byte-for-byte
      # unchanged. Only official Debian repositories are rewritten.
      official = 0
      uri_count = split(uris_value, uri_items, /[[:space:]]+/)
      for (i = 1; i <= uri_count; i++) {
        if (uri_items[i] != "" && is_official_debian_uri(uri_items[i])) official = 1
      }
      if (!official || suites_value == "") {
        printf "%s\n\n", $0
        next
      }

      suite_count = split(suites_value, suites, /[[:space:]]+/)
      emitted = 0
      for (suite_index = 1; suite_index <= suite_count; suite_index++) {
        suite = suites[suite_index]
        if (suite == "") continue
        if (suite == "bullseye-backports" || suite == "bullseye-backports-sloppy") continue

        rewritten_uris = ""
        for (i = 1; i <= uri_count; i++) {
          if (uri_items[i] == "") continue
          new_uri = rewrite_uri_for_suite(uri_items[i], suite)
          rewritten_uris = rewritten_uris (rewritten_uris == "" ? "" : " ") new_uri
        }

        output = ""
        for (i = 1; i <= count; i++) {
          if (lines[i] ~ /^URIs:[[:space:]]*/ ||
              lines[i] ~ /^Suites:[[:space:]]*/ ||
              lines[i] ~ /^Check-Valid-Until:[[:space:]]*/) continue
          output = output (output == "" ? "" : "\n") lines[i]
        }
        if (output != "") output = output "\n"
        output = output "URIs: " rewritten_uris "\nSuites: " suite
        if (index(rewritten_uris, "archive.debian.org") > 0) {
          output = output "\nCheck-Valid-Until: no"
        }
        printf "%s\n\n", output
        emitted++
      }

      # A source stanza containing only disabled Bullseye backports is omitted.
      if (emitted == 0) next
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
