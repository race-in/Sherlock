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
for c in gcc make curl tar sha256sum pkg-config perl gzip xz git patch awk sed ar ranlib nm ld nproc; do need "$c"; done
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
 fetch https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz "$WORK/src/openssl-3.5.9.tar.gz" f482705825eb43b47ce08d5cf4287ae062cdbada1a142d728a8d89c387300bf0
 rm -rf "$WORK/build/openssl-3.5.9"; tar -xf "$WORK/src/openssl-3.5.9.tar.gz" -C "$WORK/build"
 (cd "$WORK/build/openssl-3.5.9" && ./Configure linux-x86_64 --prefix="$PREFIX" --openssldir="$PREFIX/ssl" shared zlib -I"$PREFIX/include" -L"$PREFIX/lib" && make -j"$JOBS" && make install_sw) >"$LOG_DIR/openssl-build.log" 2>&1 || { tail -n 60 "$LOG_DIR/openssl-build.log" >&2; die "OpenSSL build failed; see $LOG_DIR/openssl-build.log"; }
fi
"$PREFIX/bin/openssl" version | grep -F 'OpenSSL 3.5.9' >/dev/null || die "OpenSSL verification failed."

step "Build Ruby 4.0.9"
if [[ ! -x "$PREFIX/bin/ruby" ]] || [[ "$("$PREFIX/bin/ruby" -e 'print RUBY_VERSION' 2>/dev/null || true)" != 4.0.9 ]]; then
 fetch https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.9.tar.xz "$WORK/src/ruby-4.0.9.tar.xz" a8057adb39f51ad6dc3106237504c93dd792bb515837b4fe7817ae21ed7e51f4
 rm -rf "$WORK/build/ruby-4.0.9"; tar -xf "$WORK/src/ruby-4.0.9.tar.xz" -C "$WORK/build"
 (cd "$WORK/build/ruby-4.0.9" && PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" CPPFLAGS="-I$PREFIX/include" LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib" ./configure --prefix="$PREFIX" --disable-install-doc --with-openssl-dir="$PREFIX" --with-zlib-dir="$PREFIX" --with-libyaml-dir="$PREFIX" --disable-yjit && make -j"$JOBS" && make install) >"$LOG_DIR/ruby-build.log" 2>&1 || { tail -n 80 "$LOG_DIR/ruby-build.log" >&2; die "Ruby build failed; see $LOG_DIR/ruby-build.log"; }
fi
export PATH="$PREFIX/bin:$PATH" LD_LIBRARY_PATH="$PREFIX/lib"
ruby -ropenssl -rzlib -ryaml -e 'abort "wrong Ruby" unless RUBY_VERSION=="4.0.9"; abort "wrong OpenSSL" unless OpenSSL::OPENSSL_VERSION.include?("3.5.9"); puts "Ruby #{RUBY_VERSION} / #{OpenSSL::OPENSSL_VERSION} / zlib #{Zlib::ZLIB_VERSION} / Psych #{Psych::VERSION}"'
gem install bundler -v 4.0.20 --no-document
bundle _4.0.20_ --version
printf '\nRuntime installed under %s\n' "$PREFIX"
printf 'export PATH="%s/bin:$PATH"\n' "$PREFIX"
printf 'export LD_LIBRARY_PATH="%s/lib:${LD_LIBRARY_PATH:-}"\n' "$PREFIX"
