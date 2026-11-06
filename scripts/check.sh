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
zig build bench-sync -Doptimize=ReleaseFast

if [ "${1:-}" = "--compare" ]; then
    SPICE_DIR="${SPICE_DIR:-/tmp/spice}" \
        python3 bench/compare/run_compare.py \
        --rounds 2 --lanes "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)" --gate
fi
