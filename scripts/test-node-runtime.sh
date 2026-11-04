#!/usr/bin/env bash
set -Eeuo pipefail

. /etc/os-release
[[ "${ID:-}" == debian ]] || { echo "Debian 11/12/13 required." >&2; exit 1; }
MAJOR=${VERSION_ID%%.*}
case "$MAJOR" in
  11) NODE_VERSION=24.22.2; MIN_GLIBC=2.28; MIN_KERNEL=4.18 ;;
  12|13) NODE_VERSION=26.12.0; MIN_GLIBC=2.34; MIN_KERNEL=5.14 ;;
  *) echo "Unsupported Debian release: $VERSION_ID" >&2; exit 1 ;;
esac

case "$(dpkg --print-architecture)" in
  amd64) NODE_ARCH=x64 ;;
  arm64) NODE_ARCH=arm64 ;;
  *) echo "Unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;;
esac

GLIBC=$(getconf GNU_LIBC_VERSION | awk '{print $2}')
KERNEL=$(uname -r | cut -d- -f1)
dpkg --compare-versions "$GLIBC" ge "$MIN_GLIBC" || {
  echo "Node.js $NODE_VERSION needs glibc >= $MIN_GLIBC; found $GLIBC." >&2
  exit 1
}
dpkg --compare-versions "$KERNEL" ge "$MIN_KERNEL" || {
  echo "Node.js $NODE_VERSION needs kernel >= $MIN_KERNEL; found $KERNEL." >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl xz-utils libatomic1 git

NODE_DIST_BASE=https://nodejs.org/dist
NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/node"

curl -fsSLo "$TMP_DIR/SHASUMS256.txt" "$NODE_DIST_BASE/v$NODE_VERSION/SHASUMS256.txt"
curl -fsSLo "$TMP_DIR/$NODE_TARBALL" "$NODE_DIST_BASE/v$NODE_VERSION/$NODE_TARBALL"
grep -E "^[0-9a-f]{64}  ${NODE_TARBALL}$" "$TMP_DIR/SHASUMS256.txt" > "$TMP_DIR/node.sha256" \
  || { echo "Official SHA-256 entry missing for $NODE_TARBALL." >&2; exit 1; }
(cd "$TMP_DIR" && sha256sum --check node.sha256)
tar -xJf "$TMP_DIR/$NODE_TARBALL" -C "$TMP_DIR/node" --strip-components=1

export PATH="$TMP_DIR/node/bin:$PATH"
ACTUAL_NODE=$(node --version)
[[ "$ACTUAL_NODE" == "v$NODE_VERSION" ]] || {
  echo "Node.js version mismatch: expected v$NODE_VERSION, got $ACTUAL_NODE." >&2
  exit 1
}
node -e 'const v = process.versions; if (!v.v8 || !v.modules) process.exit(1); console.log("Node runtime OK:", process.version, "V8", v.v8)'
npm --version

APP_SOURCE_DIR=${APP_SOURCE_DIR:-"$SCRIPT_DIR/../sherlock-v2"}
[[ -f "$APP_SOURCE_DIR/package.json" && -f "$APP_SOURCE_DIR/package-lock.json" ]] || {
  echo "Bundled Sherlock source is missing package.json or package-lock.json: $APP_SOURCE_DIR" >&2
  exit 1
}
cp -a "$APP_SOURCE_DIR" "$TMP_DIR/sherlock"
APP_NODE_PIN=$(tr -d '\r\n' < "$TMP_DIR/sherlock/.node-version")
[[ "$APP_NODE_PIN" == 26.12.0 ]] || {
  echo "Unexpected upstream .node-version: $APP_NODE_PIN (expected 26.12.0)." >&2
  exit 1
}
(
  cd "$TMP_DIR/sherlock"
  npm ci --no-audit --no-fund
  npm run build
)
printf 'PASS: Debian %s runs official Node.js %s (%s) and builds Sherlock frontend with glibc %s.\n' "$MAJOR" "$NODE_VERSION" "$NODE_ARCH" "$GLIBC"
