# Source this to build and test the core on a Mac against the NSS built by
# `scripts/build-nss.sh desktop` (static, like the mobile builds).
#
#   . scripts/env.sh
export NSS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.build-deps/application-services/libs/desktop/darwin-aarch64/nss"
export NSS_STATIC=1
