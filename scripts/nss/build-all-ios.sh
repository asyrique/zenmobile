#!/usr/bin/env bash
# Stands in for application-services' libs/build-all-ios.sh (scripts/build-nss.sh
# copies it over). Builds NSS only for what Zen Mobile ships: arm64 devices and
# arm64 simulators. Upstream also builds x86_64 simulators, merges everything
# into universal libraries with lipo, and checks out the Glean submodule; we
# use none of those.
#
# Called by upstream's build-all.sh (which downloads, verifies and patches the
# NSS sources) from the libs/ directory, with `abspath` exported.
set -euo pipefail

NSS_SRC_PATH="$1"
IOS_MIN_SDK_VERSION=17.0

for ARCH in arm64 arm64-sim; do
  DIST_DIR="$(abspath "ios/${ARCH}/nss")"
  if [[ -d "$DIST_DIR" ]]; then
    echo "$DIST_DIR already exists. Skipping."
  else
    ./build-nss-ios.sh "$NSS_SRC_PATH" "$DIST_DIR" "$ARCH" "$IOS_MIN_SDK_VERSION"
  fi
done
