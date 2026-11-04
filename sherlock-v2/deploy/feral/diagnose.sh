#!/usr/bin/env bash
# Read-only environment report for diagnosing Feral's Debian 9 shared slot.
set -u
section() { printf '\n=== %s ===\n' "$1"; }
show() { printf '%-22s %s\n' "$1" "$2"; }
section "Operating system"
if [[ -r /etc/os-release ]]; then . /etc/os-release; show "PRETTY_NAME" "${PRETTY_NAME:-unknown}"; show "VERSION_ID" "${VERSION_ID:-unknown}"; show "VERSION_CODENAME" "${VERSION_CODENAME:-unknown}"; else show "os-release" "missing"; fi
show "kernel" "$(uname -sr 2>/dev/null || echo unknown)"
show "architecture" "$(uname -m 2>/dev/null || echo unknown)"
if command -v getconf >/dev/null 2>&1; then show "glibc" "$(getconf GNU_LIBC_VERSION 2>/dev/null || echo unknown)"; fi
section "Build tools"
for cmd in gcc make git curl wget tar gzip xz bzip2 pkg-config; do
  if command -v "$cmd" >/dev/null 2>&1; then show "$cmd" "$(command -v "$cmd")"; else show "$cmd" "not found"; fi
done
if command -v gcc >/dev/null 2>&1; then show "gcc version" "$(gcc -dumpfullversion -dumpversion 2>/dev/null || gcc --version | head -n 1)"; fi
section "Language runtimes"
if command -v ruby >/dev/null 2>&1; then
  show "ruby" "$(ruby -v 2>&1)"
  show "Ruby OpenSSL" "$(ruby -ropenssl -e 'puts OpenSSL::OPENSSL_VERSION' 2>&1 || true)"
  show "Ruby prefix" "$(ruby -rrbconfig -e 'puts RbConfig::CONFIG["prefix"]' 2>&1 || true)"
else show "ruby" "not found"; fi
for cmd in bundle node npm python3; do
  if command -v "$cmd" >/dev/null 2>&1; then show "$cmd" "$("$cmd" --version 2>&1 | head -n 1)"; else show "$cmd" "not found"; fi
done
section "PostgreSQL client"
for cmd in psql pg_config pg_isready; do
  if command -v "$cmd" >/dev/null 2>&1; then show "$cmd" "$(command -v "$cmd")"; else show "$cmd" "not found"; fi
done
if command -v pg_config >/dev/null 2>&1; then show "libpq version" "$(pg_config --version 2>&1)"; show "libpq path" "$(pg_config --libdir 2>&1)"; fi
section "User limits and storage"
show "user" "$(id 2>/dev/null || echo unknown)"
show "ulimit open files" "$(ulimit -n 2>/dev/null || echo unknown)"
show "home filesystem" "$(df -h "$HOME" 2>/dev/null | tail -n 1 || echo unknown)"
show "home writable" "$([[ -w "$HOME" ]] && echo yes || echo no)"
section "Network tools"
for cmd in ss netstat nc curl; do
  if command -v "$cmd" >/dev/null 2>&1; then show "$cmd" "$(command -v "$cmd")"; else show "$cmd" "not found"; fi
done
printf '\nDiagnostic complete. No files were created and no secrets were read.\n'
