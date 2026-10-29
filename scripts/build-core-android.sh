#!/usr/bin/env bash
# Builds libzen_core.so for Android and puts it where the app build finds it:
#   core/swift/ZenCore/lib/android/<abi>/       (Swift links against it)
#   app/Android/app/src/main/jniLibs/<abi>/     (packaged into the APK)
#
# Usage: scripts/build-core-android.sh [abi...]   (default: arm64-v8a)
# Needs: ANDROID_NDK_HOME, NSS from scripts/build-nss.sh android, and
# `rustup target add aarch64-linux-android` (or the ABI's triple).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"
NSS_ROOT="${NSS_ANDROID_DIR:-$ROOT/.build-deps/application-services/libs/android}"
API="${ANDROID_API_LEVEL:-28}"
PROFILE="${CARGO_PROFILE:-release}"
case "$(uname -s)" in
  Darwin) HOST_TAG=darwin-x86_64 ;;
  *) HOST_TAG=linux-x86_64 ;;
esac
TC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG/bin"

ABIS=("$@")
[[ ${#ABIS[@]} -eq 0 ]] && ABIS=(arm64-v8a)

for ABI in "${ABIS[@]}"; do
  case "$ABI" in
    arm64-v8a) TRIPLE=aarch64-linux-android ;;
    x86_64) TRIPLE=x86_64-linux-android ;;
    *) echo "unsupported ABI $ABI" >&2; exit 1 ;;
  esac
  ENV_TRIPLE="${TRIPLE//-/_}"
  UPPER_TRIPLE="$(echo "$ENV_TRIPLE" | tr '[:lower:]' '[:upper:]')"
  export "CC_$ENV_TRIPLE=$TC/$TRIPLE$API-clang"
  export "CXX_$ENV_TRIPLE=$TC/$TRIPLE$API-clang++"
  export "AR_$ENV_TRIPLE=$TC/llvm-ar"
  export "RANLIB_$ENV_TRIPLE=$TC/llvm-ranlib"
  export "CARGO_TARGET_${UPPER_TRIPLE}_LINKER=$TC/$TRIPLE$API-clang"
  export NSS_DIR="$NSS_ROOT/$ABI/nss" NSS_STATIC=1

  (cd "$ROOT/core" && cargo rustc -p zen-core --lib --profile "$PROFILE" --target "$TRIPLE" --crate-type cdylib)

  OUT_DIR="$PROFILE"; [[ "$PROFILE" == "dev" ]] && OUT_DIR=debug
  LIB="$ROOT/core/target/$TRIPLE/$OUT_DIR/libzen_core.so"
  for DEST in "$ROOT/core/swift/ZenCore/lib/android/$ABI" "$ROOT/app/Android/app/src/main/jniLibs/$ABI"; do
    mkdir -p "$DEST"
    cp "$LIB" "$DEST/"
  done
  echo "Built $LIB"
done
