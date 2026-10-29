#!/usr/bin/env bash
# Builds the Rust core as a static library for iOS devices and the
# simulator, and wraps both in core/swift/ZenCore/ZenCoreRust.xcframework.
# NSS is linked statically, so the archive is self-contained apart from
# system libraries (declared in ZenCore's Package.swift).
#
# Usage: scripts/build-core-ios.sh
# Needs: macOS + Xcode, NSS from `scripts/build-nss.sh ios`, and
# `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NSS_ROOT="${NSS_IOS_DIR:-$ROOT/.build-deps/application-services/libs/ios}"
PROFILE="${CARGO_PROFILE:-release}"
OUT_DIR="$PROFILE"; [[ "$PROFILE" == "dev" ]] && OUT_DIR=debug
export IPHONEOS_DEPLOYMENT_TARGET=17.0

build() {
  local triple="$1" nss_arch="$2"
  NSS_DIR="$NSS_ROOT/$nss_arch/nss" NSS_STATIC=1 \
    cargo rustc -p zen-core --lib --profile "$PROFILE" --target "$triple" --crate-type staticlib
}

cd "$ROOT/core"
build aarch64-apple-ios arm64
build aarch64-apple-ios-sim arm64-sim

XCF="$ROOT/core/swift/ZenCore/ZenCoreRust.xcframework"
rm -rf "$XCF"
xcodebuild -create-xcframework \
  -library "target/aarch64-apple-ios/$OUT_DIR/libzen_core.a" \
  -library "target/aarch64-apple-ios-sim/$OUT_DIR/libzen_core.a" \
  -output "$XCF"
echo "Built $XCF"
