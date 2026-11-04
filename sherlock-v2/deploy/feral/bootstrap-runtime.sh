#!/usr/bin/env bash
set -Eeuo pipefail
PREFIX="${SHERLOCK_RUNTIME_PREFIX:-$HOME/.local/opt/sherlock-runtime}"
WORK="${SHERLOCK_BUILD_DIR:-$HOME/.cache/sherlock-feral-build}"
LOG_DIR="${SHERLOCK_STATE_DIR:-$HOME/.local/var/sherlock-feral}"
JOBS="${SHERLOCK_BUILD_JOBS:-2}"
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
step(){ printf '\n==> %s\n' "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Missing build tool: $1 (root access is not used)."; }
fetch(){
 local url="$1" file="$2" sha="$3"
 if [[ -f "$file" ]] && printf '%s  %s\n' "$sha" "$file" | sha256sum -c --status; then return; fi
 mkdir -p "$(dirname "$file")"
 curl --fail --location --retry 3 --connect-timeout 20 "$url" -o "$file"
 printf '%s  %s\n' "$sha" "$file" | sha256sum -c - || die "Checksum failed: $file"
}
mkdir -p "$PREFIX" "$WORK/src" "$WORK/build" "$LOG_DIR"
[[ $EUID -ne 0 ]] || die "Do not run as root."
[[ -r /etc/os-release ]] || die "Cannot identify OS."
. /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 9* ]] || die "Only Debian 9 is supported."
[[ "$(uname -m)" == x86_64 ]] || die "Only x86_64 is supported in this first Feral build."
for c in gcc make curl tar sha256sum pkg-config perl gzip xz bzip2 git patch awk sed ar ranlib nm ld nproc; do need "$c"; done
(( $(gcc -dumpversion | cut -d. -f1) >= 6 )) || die "GCC 6+ required."
PREFIX="$(cd "$PREFIX" && pwd -P)"
export PATH="$PREFIX/bin:/usr/bin:/bin"
export CFLAGS="-O2 -fPIC" CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export LD_LIBRARY_PATH="$PREFIX/lib" PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

step "Build zlib 1.3.1"
if [[ ! -f "$PREFIX/lib/libz.so" ]]; then
 fetch https://github.com/madler/zlib/releases/download/v1.3.1/zlib-1.3.1.tar.gz "$WORK/src/zlib-1.3.1.tar.gz" 9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
 rm -rf "$WORK/build/zlib-1.3.1"; tar -xf "$WORK/src/zlib-1.3.1.tar.gz" -C "$WORK/build"
 (cd "$WORK/build/zlib-1.3.1" && ./configure --prefix="$PREFIX" --shared && make -j"$JOBS" && make install)
fi
[[ -f "$PREFIX/include/zlib.h" && -f "$PREFIX/lib/libz.so" ]] || die "zlib build incomplete."

step "Build libyaml 0.2.5"
if [[ ! -f "$PREFIX/lib/libyaml.so" ]]; then
 fetch https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz "$WORK/src/yaml-0.2.5.tar.gz" c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4
 rm -rf "$WORK/build/yaml-0.2.5"; tar -xf "$WORK/src/yaml-0.2.5.tar.gz" -C "$WORK/build"
 (cd "$WORK/build/yaml-0.2.5" && ./configure --prefix="$PREFIX" --disable-static && make -j"$JOBS" && make install)
fi
[[ -f "$PREFIX/include/yaml.h" && -f "$PREFIX/lib/libyaml.so" ]] || die "libyaml build incomplete."

step "Build OpenSSL 3.5.9 LTS"
if [[ ! -x "$PREFIX/bin/openssl" ]] || ! "$PREFIX/bin/openssl" version | grep -Fq 'OpenSSL 3.5.9'; then
 fetch https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz "$WORK/src/openssl-3.5.9.tar.gz" 603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
 rm -rf "$WORK/build/openssl-3.5.9"; tar -xf "$WORK/src/openssl-3.5.9.tar.gz" -C "$WORK/build"
 (cd "$WORK/build/openssl-3.5.9" && ./Configure linux-x86_64 --prefix="$PREFIX" --libdir=lib --openssldir="$PREFIX/ssl" shared zlib -I"$PREFIX/include" -L"$PREFIX/lib" && make -j"$JOBS" && make install_sw) >"$LOG_DIR/openssl-build.log" 2>&1 || { tail -n 60 "$LOG_DIR/openssl-build.log" >&2; die "OpenSSL build failed; see $LOG_DIR/openssl-build.log"; }
fi
"$PREFIX/bin/openssl" version | grep -F 'OpenSSL 3.5.9' >/dev/null || die "OpenSSL verification failed."

step "Build PostgreSQL 16.15 client libraries and tools"
if [[ ! -x "$PREFIX/bin/pg_config" || ! -x "$PREFIX/bin/pg_isready" || ! -x "$PREFIX/bin/psql" || ! -r "$PREFIX/include/libpq-fe.h" || ! -r "$PREFIX/include/postgres_ext.h" || ! -r "$PREFIX/include/pg_config_ext.h" ]]; then
 fetch https://ftp.postgresql.org/pub/source/v16.15/postgresql-16.15.tar.bz2 "$WORK/src/postgresql-16.15.tar.bz2" c1575341fa7bd40f5274ea465b34390f4dc64cdd0770af327005caaeb9f6b7ed
 rm -rf "$WORK/build/postgresql-16.15"; mkdir -p "$WORK/build/postgresql-16.15"
 tar -xjf "$WORK/src/postgresql-16.15.tar.bz2" -C "$WORK/build"
 (
  cd "$WORK/build/postgresql-16.15"
  CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib" \
   ./configure --prefix="$PREFIX" --with-openssl --without-readline --without-zlib \
    --without-icu --without-llvm --without-gssapi --without-ldap --without-pam \
    --without-perl --without-python --without-tcl --without-systemd
  make -j"$JOBS" -C src/interfaces/libpq
  make -j"$JOBS" -C src/bin/pg_config
  make -j"$JOBS" -C src/bin/psql
  # pg_isready is built and installed by PostgreSQL's src/bin/scripts directory.
  make -j"$JOBS" -C src/bin/scripts
  make -C src/interfaces/libpq install
  # libpq-fe.h includes postgres_ext.h, which in turn includes pg_config_ext.h.
  # Install both companion headers beside libpq-fe.h for standalone pg gem builds.
  install -m 644 src/include/postgres_ext.h "$PREFIX/include/postgres_ext.h"
  install -m 644 src/include/pg_config_ext.h "$PREFIX/include/pg_config_ext.h"
  make -C src/bin/pg_config install
  make -C src/bin/psql install
  make -C src/bin/scripts install
 ) >"$LOG_DIR/postgresql-client-build.log" 2>&1 || { tail -n 80 "$LOG_DIR/postgresql-client-build.log" >&2; die "PostgreSQL client build failed; see $LOG_DIR/postgresql-client-build.log"; }
fi
[[ -r "$PREFIX/include/libpq-fe.h" && -r "$PREFIX/include/postgres_ext.h" && -r "$PREFIX/include/pg_config_ext.h" ]] || die "PostgreSQL libpq development headers are incomplete."
"$PREFIX/bin/pg_config" --version | grep -F 'PostgreSQL 16.15' >/dev/null || die "PostgreSQL client version check failed."
"$PREFIX/bin/pg_isready" --version >/dev/null || die "pg_isready self-test failed."
"$PREFIX/bin/psql" --version | grep -F "16.15" >/dev/null || die "psql client self-test failed."

step "Build Ruby 4.0.9"
if [[ ! -x "$PREFIX/bin/ruby" ]] || [[ "$("$PREFIX/bin/ruby" -e 'print RUBY_VERSION' 2>/dev/null || true)" != 4.0.9 ]]; then
 fetch https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.9.tar.xz "$WORK/src/ruby-4.0.9.tar.xz" a8057adb39f51ad6dc3106237504c93dd792bb515837b4fe7817ae21ed7e51f4
 rm -rf "$WORK/build/ruby-4.0.9"; tar -xf "$WORK/src/ruby-4.0.9.tar.xz" -C "$WORK/build"
 (cd "$WORK/build/ruby-4.0.9" && PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib" ./configure --prefix="$PREFIX" --disable-install-doc --with-openssl-dir="$PREFIX" --with-zlib-dir="$PREFIX" --with-libyaml-dir="$PREFIX" --disable-yjit && make -j"$JOBS" && make install) >"$LOG_DIR/ruby-build.log" 2>&1 || { tail -n 80 "$LOG_DIR/ruby-build.log" >&2; die "Ruby build failed; see $LOG_DIR/ruby-build.log"; }
fi
step "Install private Rust toolchain for the prometheus mmap extension"
RUSTUP_HOME="$PREFIX/rustup"
CARGO_HOME="$PREFIX/cargo"
export RUSTUP_HOME CARGO_HOME
if [[ ! -x "$CARGO_HOME/bin/rustc" ]]; then
 curl --proto '=https' --tlsv1.2 --fail --location --retry 3 https://sh.rustup.rs -o "$WORK/src/rustup-init.sh"
 sh "$WORK/src/rustup-init.sh" -y --no-modify-path --profile minimal --default-toolchain 1.89.0
fi
export PATH="$CARGO_HOME/bin:$PATH"
rustc --version | grep -F 'rustc 1.89.0' >/dev/null || die "Rust 1.89.0 toolchain check failed."
cargo --version >/dev/null || die "Cargo is unavailable."

step "Install temporary Node.js 22 build runtime for glibc 2.17+"
NODE_VERSION=22.21.1
NODE_ARCHIVE="node-v$NODE_VERSION-linux-x64-glibc-217.tar.xz"
NODE_URL="https://unofficial-builds.nodejs.org/download/release/v$NODE_VERSION"
mkdir -p "$PREFIX/node"
if [[ ! -x "$PREFIX/node/node-v$NODE_VERSION-linux-x64-glibc-217/bin/node" ]]; then
 curl --fail --location --retry 3 "$NODE_URL/SHASUMS256.txt" -o "$WORK/src/node-SHASUMS256.txt"
 grep " $NODE_ARCHIVE$" "$WORK/src/node-SHASUMS256.txt" >/dev/null || die "Node.js archive is not listed in its checksum manifest."
 curl --fail --location --retry 3 "$NODE_URL/$NODE_ARCHIVE" -o "$WORK/src/$NODE_ARCHIVE"
 (cd "$WORK/src" && grep " $NODE_ARCHIVE$" node-SHASUMS256.txt | sha256sum -c -)
 rm -rf "$PREFIX/node/node-v$NODE_VERSION-linux-x64-glibc-217"
 tar -xJf "$WORK/src/$NODE_ARCHIVE" -C "$PREFIX/node"
fi
NODE_BIN="$PREFIX/node/node-v$NODE_VERSION-linux-x64-glibc-217/bin"
"$NODE_BIN/node" --version | grep -Fx "v$NODE_VERSION" >/dev/null || die "Node.js version check failed."

export PATH="$PREFIX/bin:$NODE_BIN:$CARGO_HOME/bin:$PATH" LD_LIBRARY_PATH="$PREFIX/lib"
ruby -ropenssl -rzlib -ryaml -e 'abort "wrong Ruby" unless RUBY_VERSION=="4.0.9"; abort "wrong OpenSSL" unless OpenSSL::OPENSSL_VERSION.include?("3.5.9"); puts "Ruby #{RUBY_VERSION} / #{OpenSSL::OPENSSL_VERSION} / zlib #{Zlib::ZLIB_VERSION} / Psych #{Psych::VERSION}"'
gem install bundler -v 4.0.20 --no-document
gem install libclang -v 14.0.6 --no-document
export LIBCLANG_PATH="$(ruby -rlibclang -e 'puts File.dirname(Libclang.path)')"
[[ -f "$LIBCLANG_PATH/libclang.so" ]] || die "Bundled libclang shared library was not found."
bundle _4.0.20_ --version

printf '\nRuntime installed under %s\n' "$PREFIX"
printf 'export PATH="%s/bin:%s/bin:%s/cargo/bin:$PATH"\n' "$PREFIX" "$PREFIX/node/node-v22.21.1-linux-x64-glibc-217" "$PREFIX"
printf 'export LD_LIBRARY_PATH="%s/lib:${LD_LIBRARY_PATH:-}"\n' "$PREFIX"
