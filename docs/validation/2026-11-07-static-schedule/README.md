# Opt-in contiguous static scheduling

`ParallelOptions.schedule` now selects `.dynamic` (the default) or `.static`.
Dynamic scheduling retains the existing atomic chunk cursor so faster lanes
can absorb work from slower lanes. Static scheduling assigns each dispatch
future one balanced, contiguous span of chunk indices and removes the shared
cursor from callback execution. Planned chunks, lane caps, caller
participation, ordered results/errors and cancellation semantics are
unchanged.

Dispatch selects separate generic kernels once. The dynamic kernel retains
the original pointer-sized Future input and branch-free atomic claim loop;
static uses a lane-index input and contains no schedule branch or shared
cursor in its callback loop. Opting into static therefore does not enlarge or
slow the default dynamic Future path.

A dispatch future can run on any worker and an unclaimed future can still be
executed by the caller during join. Static therefore guarantees contiguous
work per dispatch lane, not a mapping from chunk spans to `Worker.index`.
There is no work redistribution after a static future begins; callers should
use it only for predictable chunk costs. Irregular and heterogeneous work
should keep the dynamic default.

Implementation tests repeat both schedules over worker counts 0-4 and lane
caps 1-5. They verify exact coverage, caller participation, maximum active
lanes, noncommutative result order, chunk-index error precedence, zero-worker
fallback, fallible/infallible element folds and range folds. Existing
allocation, context lifetime, cancellation and nested-dispatch tests continue
to use the dynamic default.

## Fixed-CPU comparison

Every process runs on CPUs 24-31 with eight lanes, verifies its checksum and
reports the best of seven paired serial/parallel repetitions. Five outer
rounds alternate schedule order. [`results.json`](results.json) retains every
process result and source hash. Table cells are medians of the five process
results.

| Uniform workload | Schedule | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| 4,096 one-item chunks | dynamic | 1,087 | 212,226 | 0.01x |
| 4,096 one-item chunks | static | 1,086 | 11,165 | 0.10x |
| 65,536 items / 4,096 chunks | dynamic | 17,087 | 210,608 | 0.08x |
| 65,536 items / 4,096 chunks | static | 17,291 | 13,612 | 1.27x |
| 16M SIMD flat sum / 128 chunks | dynamic | 15,109,005 | 2,369,479 | 6.38x |
| 16M SIMD flat sum / 128 chunks | static | 14,500,925 | 2,296,064 | 6.32x |
| 1M compute / 128 chunks | dynamic | 109,405,311 | 14,116,420 | 7.75x |
| 1M compute / 128 chunks | static | 109,401,549 | 14,110,127 | 7.75x |

Static reduces the 4K-chunk dispatch median by 94.7% (about 19x) and the 64K
scan by 93.5% (about 15.5x). The ordinary flat workload improves about 3.1%;
compute is unchanged. A 512-chunk compute probe favored dynamic because slow
static spans could not be redistributed, confirming that static must remain
opt-in rather than replacing the default.

The formal flat comparison opts into static. The table below was captured
while compute also used static-16; a subsequent grain sweep moved compute to
dynamic-128 and is recorded in the
[compute grain report](../2026-11-07-compute-grain/README.md). The three-round
medians for this static-schedule checkpoint were:

| Workload | parz | Spice | Rayon | OpenMP |
|---|---:|---:|---:|---:|
| tree 1K | 0.001 ms / 0.99x | 0.003 ms / 0.72x | 0.013 ms / 0.14x | 0.303 ms / 0.00x |
| tree 100K | 0.078 ms / 2.01x | 0.250 ms / 0.88x | 0.163 ms / 1.16x | 0.292 ms / 0.54x |
| tree 10M | 9.413 ms / 2.34x | 10.604 ms / 2.34x | 12.815 ms / 1.84x | 10.334 ms / 2.12x |
| flat 16M | 2.280 ms / 6.27x | 3.959 ms / 3.59x | 2.572 ms / 5.07x | 3.075 ms / 4.68x |
| compute 1M | 14.121 ms / 7.75x | 14.873 ms / 7.29x | 13.741 ms / 7.93x | 13.576 ms / 7.90x |

The checksum gate passed. Parz remains fastest on all measured tree sizes and
the flat sum; compute remains about 3-4% behind Rayon/OpenMP, so global
theoretical optimality is not claimed.

## Verification

- Debug and ReleaseSafe: 84 library tests plus three integration tests passed.
- ThreadSanitizer: all 84 library tests passed.
- Single-threaded ReleaseSafe: 68 passed and 16 thread/platform tests skipped.
- Test instances compiled for WASM/WASI atomics, Windows GNU, aarch64 macOS,
  and x86_64 musl Linux.
- The ReleaseFast parz/Spice comparison build and three-round checksum gate
  passed.
