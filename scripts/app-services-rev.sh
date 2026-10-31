#!/usr/bin/env bash
# Prints the application-services revision the Rust core pins (core/Cargo.toml).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sed -n 's/^fxa-client = .*rev = "\([0-9a-f]*\)".*/\1/p' "$ROOT/core/Cargo.toml"
