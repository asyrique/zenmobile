# Source this on Linux to build and test the core against the system NSS
# (Ubuntu: apt install libnss3). Release and mobile builds link a static NSS
# built by application-services' libs/build-all.sh instead.
#
#   . scripts/env-linux.sh
NSS_SHIM="${XDG_CACHE_HOME:-$HOME/.cache}/zenmobile/nss-system"
mkdir -p "$NSS_SHIM/include"
ln -sfn "/usr/lib/$(uname -m)-linux-gnu" "$NSS_SHIM/lib"
export NSS_DIR="$NSS_SHIM"
