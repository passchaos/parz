#!/bin/sh
# Core verification gates for parz.
#
# Usage:
#   scripts/check.sh             # tests, TSan, WASM compile, sync benchmark
#   scripts/check.sh --compare   # also run the cross-library regression gate
set -eu
cd "$(dirname "$0")/.."

zig build test
zig build test -Doptimize=ReleaseSafe
zig test src/root.zig -fsanitize-thread -OReleaseSafe
zig test src/root.zig -target wasm32-wasi -mcpu=generic+atomics \
    -OReleaseSafe --test-no-exec
for target in x86_64-windows-gnu aarch64-macos x86_64-linux-musl; do
    zig build-obj src/root.zig -target "$target" -OReleaseSafe \
        -femit-bin="/tmp/parz-cross-$target.o"
done
zig build bench-sync -Doptimize=ReleaseFast

if [ "${1:-}" = "--compare" ]; then
    SPICE_DIR="${SPICE_DIR:-/tmp/spice}" \
        python3 bench/compare/run_compare.py \
        --rounds 2 --lanes "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)" --gate
fi
