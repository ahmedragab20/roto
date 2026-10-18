#!/usr/bin/env bash
# Builds native/fff-bridge, the static library behind app search.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v cargo >/dev/null; then
  echo "error: app search needs Rust to build fff; install it from https://rustup.rs" >&2
  exit 1
fi

# Keep the builder's home folder (and so their user name) out of the binary:
# Rust records source paths for panic messages.
export RUSTFLAGS="${RUSTFLAGS:-} --remap-path-prefix=$HOME=~ --remap-path-prefix=$ROOT=roto"
export MACOSX_DEPLOYMENT_TARGET=14.0

LIB="$ROOT/native/fff-bridge/target/release/libfff_bridge.a"
before="$(stat -f %m "$LIB" 2>/dev/null || echo none)"
cargo build --release --locked --manifest-path "$ROOT/native/fff-bridge/Cargo.toml"

# SwiftPM does not track the library as an input, so it would keep linking
# the old one. Removing what links it makes the next swift build relink.
if [[ "$(stat -f %m "$LIB")" != "$before" ]]; then
  rm -rf "$ROOT"/.build/*/roto "$ROOT"/.build/*/rotoPackageTests.xctest
fi
