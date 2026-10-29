#!/usr/bin/env bash
# Installs the swift.org toolchain (and optionally its Android SDK) on an
# Ubuntu 24.04 CI runner, and puts it on PATH via $GITHUB_PATH.
#
# Usage: scripts/ci/install-swift-linux.sh [--android]
set -euo pipefail

VERSION="${SWIFT_VERSION:-6.3.3}"
ANDROID_SDK_CHECKSUM="${SWIFT_ANDROID_SDK_CHECKSUM:-d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5}"
DEST="${RUNNER_TOOL_CACHE:-$HOME/.local}/swift-$VERSION"
BASE="https://download.swift.org/swift-$VERSION-release"

if [[ ! -x "$DEST/usr/bin/swift" ]]; then
  mkdir -p "$DEST"
  curl -sSfL "$BASE/ubuntu2404/swift-$VERSION-RELEASE/swift-$VERSION-RELEASE-ubuntu24.04.tar.gz" \
    | tar xz -C "$DEST" --strip-components=1
fi
export PATH="$DEST/usr/bin:$PATH"
[[ -n "${GITHUB_PATH:-}" ]] && echo "$DEST/usr/bin" >> "$GITHUB_PATH"
swift --version

if [[ "${1:-}" == "--android" ]]; then
  : "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an NDK r27+}"
  BUNDLE="swift-$VERSION-RELEASE_android.artifactbundle"
  # `swift sdk list` names SDKs without the .artifactbundle suffix.
  INSTALLED="$(swift sdk list)"
  if ! grep -q "swift-$VERSION-RELEASE_android" <<<"$INSTALLED"; then
    swift sdk install "$BASE/android-sdk/swift-$VERSION-RELEASE/$BUNDLE.tar.gz" --checksum "$ANDROID_SDK_CHECKSUM"
  fi
  # Where SwiftPM unpacked it varies (~/.swiftpm, ~/.config/swiftpm, and a
  # URL install may nest the bundle one level deeper), so look it up.
  SETUP="$(find "$HOME/.swiftpm" "$HOME/.config/swiftpm" "$HOME/.local/share/swiftpm" \
    -path "*/swift-android/scripts/setup-android-sdk.sh" 2>/dev/null | head -1 || true)"
  [[ -n "$SETUP" ]] || { echo "Swift Android SDK setup script not found" >&2; exit 1; }
  bash "$SETUP"
  SDK_BUNDLE="$(dirname "$(dirname "$(dirname "$SETUP")")")"
  echo "Swift Android SDK: $SDK_BUNDLE"
  if [[ -n "${GITHUB_ENV:-}" ]]; then echo "SWIFT_ANDROID_SDK_BUNDLE=$SDK_BUNDLE" >> "$GITHUB_ENV"; fi
fi
