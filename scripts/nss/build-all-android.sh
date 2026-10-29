#!/usr/bin/env bash
# Stands in for application-services' libs/build-all-android.sh
# (scripts/build-nss.sh copies it over). Builds NSS only for arm64-v8a, the one
# ABI Zen Mobile ships; upstream also builds x86_64 and armeabi-v7a.
#
# Called by upstream's build-all.sh (which downloads, verifies and patches the
# NSS sources) from the libs/ directory, with `abspath` exported.
set -euo pipefail

NSS_SRC_PATH="$1"
# Sets ANDROID_NDK_ROOT, ANDROID_NDK_API_VERSION and NDK_HOST_TAG.
# shellcheck disable=SC1091
source android_defaults.sh

DIST_DIR="$(abspath "android/arm64-v8a/nss")"
if [[ -d "$DIST_DIR" ]]; then
  echo "$DIST_DIR already exists. Skipping."
else
  ./build-nss-android.sh "$NSS_SRC_PATH" "$DIST_DIR" \
    "${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}" \
    aarch64-linux-android "${ANDROID_NDK_API_VERSION}"
fi
