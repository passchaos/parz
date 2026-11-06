#!/bin/sh
# Core verification gates for parz.
#
# Usage:
#   scripts/check.sh             # tests, serial, TSan, cross compile, benchmarks
#   scripts/check.sh --compare   # also run the cross-library regression gate
set -eu
cd "$(dirname "$0")/.."

zig build test
zig build test -Doptimize=ReleaseSafe
zig test src/root.zig -fsingle-threaded -OReleaseSafe
zig test src/root.zig -fsanitize-thread -OReleaseSafe
zig test src/root.zig -target wasm32-wasi -mcpu=generic+atomics \
    -OReleaseSafe --test-no-exec
for target in x86_64-windows-gnu aarch64-macos x86_64-linux-musl; do
    zig test src/root.zig -target "$target" -OReleaseSafe --test-no-exec \
        -femit-bin="/tmp/parz-cross-$target-test"
done
zig build bench-sync -Doptimize=ReleaseFast
zig build bench-2d -Doptimize=ReleaseFast
zig build bench-irregular -Doptimize=ReleaseFast -- 1000 1 3 skewed

if [ "${1:-}" = "--compare" ]; then
    SPICE_DIR="${SPICE_DIR:-/tmp/spice}" \
        python3 bench/compare/run_compare.py \
        --rounds 2 --lanes "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)" --gate
fi
