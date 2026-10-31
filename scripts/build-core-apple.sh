#!/usr/bin/env bash
# Builds the Rust core as a static library for Apple platforms and wraps the
# slices in core/swift/ZenCore/ZenCoreRust.xcframework. NSS is linked
# statically, so each archive is self-contained apart from system libraries
# (declared in ZenCore's Package.swift). arm64 only.
#
# Usage: scripts/build-core-apple.sh [slice...]
#   slices: ios (devices), ios-sim (Apple silicon simulators), macos (for
#   running the Swift tests on a Mac). Default: ios ios-sim.
# Needs: macOS + Xcode, NSS from `scripts/build-nss.sh ios` (and `desktop`
# for macos), and the matching `rustup target add` for each slice.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBS="$ROOT/.build-deps/application-services/libs"
NSS_IOS="${NSS_IOS_DIR:-$LIBS/ios}"
NSS_MACOS="${NSS_MACOS_DIR:-$LIBS/desktop/darwin-aarch64/nss}"
PROFILE="${CARGO_PROFILE:-release}"
OUT_DIR="$PROFILE"; [[ "$PROFILE" == "dev" ]] && OUT_DIR=debug
export IPHONEOS_DEPLOYMENT_TARGET=17.0 MACOSX_DEPLOYMENT_TARGET=14.0

SLICES=("$@")
[[ ${#SLICES[@]} -eq 0 ]] && SLICES=(ios ios-sim)

cd "$ROOT/core"
XCF_ARGS=()
for slice in "${SLICES[@]}"; do
  case "$slice" in
    ios) triple=aarch64-apple-ios; nss="$NSS_IOS/arm64/nss" ;;
    ios-sim) triple=aarch64-apple-ios-sim; nss="$NSS_IOS/arm64-sim/nss" ;;
    macos) triple=aarch64-apple-darwin; nss="$NSS_MACOS" ;;
    *) echo "unknown slice $slice" >&2; exit 1 ;;
  esac
  NSS_DIR="$nss" NSS_STATIC=1 \
    cargo rustc -p zen-core --lib --profile "$PROFILE" --target "$triple" --crate-type staticlib
  XCF_ARGS+=(-library "target/$triple/$OUT_DIR/libzen_core.a")
done

XCF="$ROOT/core/swift/ZenCore/ZenCoreRust.xcframework"
rm -rf "$XCF"
xcodebuild -create-xcframework "${XCF_ARGS[@]}" -output "$XCF"
echo "Built $XCF (${SLICES[*]})"
