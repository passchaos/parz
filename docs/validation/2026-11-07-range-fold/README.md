# Ordered range folds and SIMD flat reduction

`parallelFoldRange` and `parallelFoldRangeInfallible` invoke a direct callback
once per planned nonempty `Chunk`, then combine results in chunk-index order.
They reuse the existing lane dispatch and bounded stack fallback: there is no
iterator layer, work stealing, hot-path lock or hidden per-item allocation.
The fallible form selects errors by chunk index. The uncancelled infallible
form stores plain result values and uses a plain-return callback.

Serial-threshold and caller-slot-exhaustion fallbacks create one temporary
lane and pass the complete input range to the callback. Its worker index
matches its context-construction index, and the mutated context is destroyed
after the call. Empty inputs return the identity without constructing a
context or invoking user code. Cancellation is checked before and after each
range callback and after ordered reduction; long callbacks can inspect their
token internally.

Tests cover deterministic noncommutative combination over 0-4 workers,
repeated runs, chunk-index error precedence, zero-worker and exhausted-caller
fallbacks, pre-cancellation, callback-exit and final-reduction cancellation,
temporary-context lifetime, empty inputs, stack-only dispatch, allocation
failures before callbacks, and caller-slot release after failure.

## Fixed-CPU performance

The formal 16M-element flat comparison now uses the infallible range API with
a portable `@Vector(8, u64)` kernel. `flat-element` uses the ordinary
per-element infallible fold in the same candidate binary. Each process checks
all results and reports the best of seven paired serial/parallel repetitions.
Five outer processes alternate path order on CPUs 24-31 with eight lanes. The
table reports medians of process results; [`results.json`](results.json)
retains every sample and source hash.

| 16M `u64` sum | serial_ns | parallel_ns | speedup |
|---|---:|---:|---:|
| element infallible fold | 14,844,661 | 3,095,690 | 4.80x |
| SIMD range fold | 14,688,273 | 2,369,421 | 6.23x |

The SIMD range path reduces parallel median time by 23.5%. A scalar range
callback emitted essentially the same instruction count as the inlined
per-element callback, confirming that the API abstraction itself is removed;
the retained gain comes from allowing a domain-specific chunk kernel.

Vector-width controls use identical input and dispatch. `u64x8` improved the
parallel median about 0.9% over `u64x4`; `u64x16` then regressed about 1.1%
against `u64x8` in its alternating batch. `u64x8` is retained. It expresses
portable vectors rather than requiring AVX-512; LLVM lowers it for the target.

The range API did not change generic compute throughput: its five-run median
was 14,140,668 ns versus 14,120,075 ns for the existing infallible element
fold. The 1K and 10M tree controls were also unchanged within host variation.
This supports adding the range API for direct kernels without replacing the
ordinary element API.

The final three-round cross-implementation medians were:

| Workload | parz | Spice | Rayon | OpenMP |
|---|---:|---:|---:|---:|
| tree 1K | 0.002 ms / 0.99x | 0.003 ms / 0.72x | 0.013 ms / 0.14x | 0.281 ms / 0.01x |
| tree 100K | 0.103 ms / 2.09x | 0.249 ms / 0.89x | 0.169 ms / 1.13x | 0.302 ms / 0.53x |
| tree 10M | 9.232 ms / 2.76x | 10.733 ms / 2.36x | 12.902 ms / 1.88x | 10.226 ms / 2.12x |
| flat 16M | 2.317 ms / 6.43x | 3.906 ms / 3.60x | 2.507 ms / 5.08x | 3.050 ms / 4.80x |
| compute 1M | 14.165 ms / 7.73x | 15.073 ms / 7.20x | 13.719 ms / 7.95x | 13.573 ms / 7.91x |

Parz is the fastest measured implementation for every tree size and the flat
sum on this fixed CPU set. Compute remains about 3-4% behind Rayon/OpenMP, so
the broader theoretical-optimality goal remains active.

Reproduce the public comparison with:

```sh
SPICE_DIR=/tmp/spice python3 bench/compare/run_compare.py \
  --rounds 3 --lanes 8 --cpus 24-31 --gate
```

## Verification

- Debug and ReleaseSafe: 84 library tests plus three integration tests passed.
- ThreadSanitizer: all 84 library tests passed.
- Single-threaded ReleaseSafe: 68 passed and 16 thread/platform tests skipped.
- Test instances compiled for WASM/WASI atomics, Windows GNU, aarch64 macOS,
  and x86_64 musl Linux.
- The ReleaseFast parz/Spice comparison build and the three-round eight-lane
  checksum gate passed.
