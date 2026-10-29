# Source this on macOS to build and test the core against the NSS built by
# `scripts/build-nss.sh desktop` (static, like the mobile builds).
#
#   . scripts/env-macos.sh
export NSS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.build-deps/application-services/libs/desktop/darwin/nss"
export NSS_STATIC=1
