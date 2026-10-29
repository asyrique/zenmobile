#!/usr/bin/env bash
# Builds NSS for iOS or Android with application-services' own scripts, at
# the same application-services rev the Rust core pins.
#
# Usage: scripts/build-nss.sh <ios|android>
# Output: .build-deps/application-services/libs/<ios|android>/<arch>/nss
# Needs: gyp-next (pip install gyp-next), ninja, python3; for Android,
# ANDROID_NDK_HOME (NDK r27+). iOS needs macOS with Xcode.
set -euo pipefail

PLATFORM="${1:?usage: build-nss.sh <ios|android>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REV="$(sed -n 's/^fxa-client = .*rev = "\([0-9a-f]*\)".*/\1/p' "$ROOT/core/Cargo.toml")"
AS="$ROOT/.build-deps/application-services"

if [[ ! -d "$AS/.git" ]]; then
  git init -q "$AS"
  git -C "$AS" remote add origin https://github.com/mozilla/application-services
fi
if [[ "$(git -C "$AS" rev-parse -q --verify HEAD || true)" != "$REV" ]]; then
  git -C "$AS" fetch -q --depth 1 origin "$REV"
  git -C "$AS" checkout -q FETCH_HEAD
fi

if [[ "$PLATFORM" == "android" ]]; then
  : "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an NDK r27+}"
  export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
  export ANDROID_NDK_API_VERSION="${ANDROID_NDK_API_VERSION:-28}"
fi

cd "$AS/libs"
./build-all.sh "$PLATFORM"
echo "NSS for $PLATFORM: $AS/libs/$PLATFORM"
