#!/usr/bin/env bash
# Builds libzen_core for macOS, regenerates the Swift bindings and runs the
# ZenCore Swift tests natively. Needs NSS from `scripts/build-nss.sh desktop`.
#
#   ZEN_NETWORK_TESTS=1 scripts/test-swift.sh   # also hit accounts.firefox.com
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env.sh
. "$ROOT/scripts/env.sh"

"$ROOT/scripts/generate-swift-bindings.sh"
# Debug, to reuse the build generate-swift-bindings.sh just made.
CARGO_PROFILE=dev "$ROOT/scripts/build-core-apple.sh" macos
cd "$ROOT/core/swift/ZenCore"
swift test "$@"
