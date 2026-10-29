#!/usr/bin/env bash
# Builds NSS with application-services' own scripts, at the same
# application-services rev the Rust core pins, for the architectures we ship:
#   desktop  macOS arm64 (core tests)  -> libs/desktop/darwin-aarch64/nss
#   ios      arm64, arm64-sim          -> libs/ios/<arch>/nss
#   android  arm64-v8a                 -> libs/android/arm64-v8a/nss
# For ios and android, scripts/nss/build-all-<platform>.sh replace upstream's
# per-platform loops, which build more architectures than we use.
#
# Usage: scripts/build-nss.sh <desktop|ios|android>
# Output under .build-deps/application-services/libs/
# Needs: macOS with Xcode, gyp-next (pip install gyp-next), ninja, python3;
# for Android, ANDROID_NDK_HOME (NDK r27+).
set -euo pipefail

PLATFORM="${1:?usage: build-nss.sh <desktop|ios|android>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REV="$(sed -n 's/^fxa-client = .*rev = "\([0-9a-f]*\)".*/\1/p' "$ROOT/core/Cargo.toml")"
AS="$ROOT/.build-deps/application-services"

if [[ ! -d "$AS/.git" ]]; then
  git init -q "$AS"
  git -C "$AS" remote add origin https://github.com/mozilla/application-services
fi
if [[ "$(git -C "$AS" rev-parse -q --verify HEAD || true)" != "$REV" ]]; then
  git -C "$AS" fetch -q --depth 1 origin "$REV"
  git -C "$AS" checkout -q -f FETCH_HEAD
fi

if [[ -f "$ROOT/scripts/nss/build-all-$PLATFORM.sh" ]]; then
  cp "$ROOT/scripts/nss/build-all-$PLATFORM.sh" "$AS/libs/build-all-$PLATFORM.sh"
fi

if [[ "$PLATFORM" == "android" ]]; then
  : "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an NDK r27+}"
  export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
  export ANDROID_NDK_API_VERSION="${ANDROID_NDK_API_VERSION:-28}"
fi

cd "$AS/libs"
./build-all.sh "$PLATFORM"
echo "NSS for $PLATFORM: $AS/libs/$PLATFORM"
