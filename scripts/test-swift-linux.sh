#!/usr/bin/env bash
# Builds libzen_core, regenerates the Swift bindings and runs the ZenCore
# Swift tests on Linux. Needs a Swift toolchain on PATH (swift.org, 6.0+)
# and the system NSS (see env-linux.sh).
#
#   ZEN_NETWORK_TESTS=1 scripts/test-swift-linux.sh   # also hit accounts.firefox.com
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=env-linux.sh
. "$ROOT/scripts/env-linux.sh"

"$ROOT/scripts/generate-swift-bindings.sh"
LIB_DIR="$ROOT/core/target/debug"
cd "$ROOT/core/swift/ZenCore"
LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  swift test -Xlinker -L"$LIB_DIR" -Xlinker -rpath -Xlinker "$LIB_DIR" "$@"
