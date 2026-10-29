#!/usr/bin/env bash
# Installs the Skip CLI's Linux build (enough for `skip android build`; full
# app builds need macOS) and puts it on PATH via $GITHUB_PATH.
set -euo pipefail

VERSION="${SKIP_VERSION:-1.9.20}"
CHECKSUM="${SKIP_LINUX_CHECKSUM:-b98f5de51818c4802d584c2802f96d45fbf1babc7c1c25f94dc6cb6e7b88f57f}"
DEST="${RUNNER_TOOL_CACHE:-$HOME/.local}/skip-$VERSION"

mkdir -p "$DEST"
cd "$DEST"
curl -sSfLO "https://github.com/skiptools/skip/releases/download/$VERSION/skip-linux.zip"
echo "$CHECKSUM  skip-linux.zip" | sha256sum -c -
unzip -q -o skip-linux.zip
BIN="$DEST/skip.artifactbundle/$(uname -m)-swift-linux-musl"
chmod +x "$BIN/skip"
[[ -n "${GITHUB_PATH:-}" ]] && echo "$BIN" >> "$GITHUB_PATH"
"$BIN/skip" version
