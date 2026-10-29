#!/usr/bin/env bash
# Builds libzen_core.so for Android (arm64-v8a) and puts it where the app
# build finds it:
#   core/swift/ZenCore/lib/android/arm64-v8a/     (Swift links against it)
#   app/Android/app/src/main/jniLibs/arm64-v8a/   (packaged into the APK)
#
# Usage: scripts/build-core-android.sh
# Needs: macOS, ANDROID_NDK_HOME, NSS from `scripts/build-nss.sh android`,
# and `rustup target add aarch64-linux-android`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"
NSS_DIR="${NSS_ANDROID_DIR:-$ROOT/.build-deps/application-services/libs/android}/arm64-v8a/nss"
API="${ANDROID_API_LEVEL:-28}"
PROFILE="${CARGO_PROFILE:-release}"
OUT_DIR="$PROFILE"; [[ "$PROFILE" == "dev" ]] && OUT_DIR=debug
TRIPLE=aarch64-linux-android
TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"

export CC_aarch64_linux_android="$TC/$TRIPLE$API-clang"
export CXX_aarch64_linux_android="$TC/$TRIPLE$API-clang++"
export AR_aarch64_linux_android="$TC/llvm-ar"
export RANLIB_aarch64_linux_android="$TC/llvm-ranlib"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TC/$TRIPLE$API-clang"
export NSS_DIR NSS_STATIC=1

(cd "$ROOT/core" && cargo rustc -p zen-core --lib --profile "$PROFILE" --target "$TRIPLE" --crate-type cdylib)

LIB="$ROOT/core/target/$TRIPLE/$OUT_DIR/libzen_core.so"
for DEST in "$ROOT/core/swift/ZenCore/lib/android/arm64-v8a" "$ROOT/app/Android/app/src/main/jniLibs/arm64-v8a"; do
  mkdir -p "$DEST"
  cp "$LIB" "$DEST/"
done
echo "Built $LIB"
