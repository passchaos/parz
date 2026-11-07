Uncancelled `parallelFoldInfallible` calls now store plain `T` chunk results
and invoke a chunk callback returning `T`. Calls with a cancellation token
retain their error-union result path and cancellation checks. Allocation and
context errors still propagate through the public `anyerror!T` return.

The value path uses the same caller admission, lane cap, balanced partitions,
dynamic chunk claims, retained caller lane and ordered reduction as before.
All lane futures are joined before reduction. It has no per-chunk error tag
to store or inspect. No scheduler, queue or fork/join protocol change is made.

For 256 `u64` chunks, the original error-union result array occupies all 4096
bytes of the stack fallback buffer. Eight lane futures then require one
256-byte pool allocation. Plain results occupy 2048 bytes, so both arrays fit
in the existing buffer. Larger types or configurations may still use the
pool allocator fallback; the feature does not promise heap-free dispatch for
all inputs.

The independent [allocation fixture](allocation-fixture.zig) forbids pool
allocations after startup. It [fails against baseline](allocation-baseline.log)
`ae2f359` with `OutOfMemory` and [passes against the value path](allocation-value.log).
The implementation test repeats this workload across worker counts 0–4 and
either zero or 16 execution states, checking results, no allocation attempts
and caller-slot release. Further tests cover result-array and lane-future
allocation failures, absence of callback execution before those failures,
successful retry, and associative but noncommutative sequence hashes across
worker counts 0–4, caps 1–5, repeated runs and both cancellation modes. Existing
actual cancellation tests remain enabled.

The benchmark prebuilds identical input, warms and verifies both API paths,
alternates serial/parallel and cancellation-mode order over nine inner rounds,
and checks every result. A pointer memory compiler barrier precedes timing to
keep serial reads inside each measurement. It uses a counting pool allocator;
the map callbacks allocate nothing, so recorded allocations are dispatch
fallbacks. Pool setup, input allocation and affinity setup precede timing.
Five outer rounds alternate baseline/candidate process order. Serial scan
checks against an independent arithmetic sum; compute checks against the
serial checksum. Serial functions retain 64-byte alignment.

E-core placement uses caller 31 and workers 24–30. P-core placement uses
caller 14 and workers 0, 2, 4, 6, 8, 10, 12. The zero-worker case uses the same
caller CPU and forces the same 256-chunk plan in both revisions. Table entries
are medians of process medians; speedup is the median reported ratio.

| Case, no cancellation token | Revision | serial_ns | parallel_ns | speedup | Dispatch allocations |
|---|---|---:|---:|---:|---:|
| E, scan 4096, 8 lanes | baseline | 1,073 | 21,385 | 0.051 | 1 × 256 bytes |
| E, scan 4096, 8 lanes | value | 1,092 | 21,737 | 0.050 | 0 |
| E, scan 1,000,003, 8 lanes | baseline | 336,121 | 76,599 | 4.436 | 1 × 256 bytes |
| E, scan 1,000,003, 8 lanes | value | 335,988 | 75,364 | 4.490 | 0 |
| E, compute 1,000,003, 8 lanes | baseline | 109,330,341 | 14,123,166 | 7.741 | 1 × 256 bytes |
| E, compute 1,000,003, 8 lanes | value | 109,299,159 | 14,109,011 | 7.746 | 0 |
| E, scan 4096, zero workers | baseline | 1,084 | 1,907 | 0.573 | 0 |
| E, scan 4096, zero workers | value | 1,091 | 1,205 | 0.905 | 0 |
| P, scan 4096, 8 lanes | baseline | 1,043 | 19,811 | 0.053 | 1 × 256 bytes |
| P, scan 4096, 8 lanes | value | 1,087 | 19,816 | 0.055 | 0 |
| P, scan 1,000,003, 8 lanes | baseline | 260,651 | 51,244 | 5.095 | 1 × 256 bytes |
| P, scan 1,000,003, 8 lanes | value | 271,729 | 51,598 | 5.201 | 0 |
| P, compute 1,000,003, 8 lanes | baseline | 70,402,068 | 8,634,153 | 8.161 | 1 × 256 bytes |
| P, compute 1,000,003, 8 lanes | value | 70,375,793 | 8,681,383 | 8.070 | 0 |
| P, scan 4096, zero workers | baseline | 1,072 | 2,503 | 0.428 | 0 |
| P, scan 4096, zero workers | value | 1,092 | 1,449 | 0.772 | 0 |

Zero-worker dispatch time falls about 37% on E cores and 42% on P cores in
these runs. Multi-lane times change little; no general multi-lane throughput
gain is claimed. The verified capability gain is removal of the measured
heap fallback and successful operation when that allocator is unavailable.
Calls with a token continue to record one 256-byte fallback allocation.
The host has other active work; timing claims are limited to these recorded
inputs and CPU placements. [Environment](environment.json) records hashes,
compiler version, placement and load. [E-core](e-core-comparison.json) and
[P-core](p-core-comparison.json) results and their sample logs retain every
process median, timing and allocation record. Each timed checksum is checked
before its sample is accepted.

```sh
taskset -c 24-31 zig build bench-infallible-fold -Doptimize=ReleaseFast -- scan 4096 8 31 1 64 9
taskset -c 24-31 zig build bench-infallible-fold -Doptimize=ReleaseFast -- scan 1000003 8 31 1 64 9
taskset -c 24-31 zig build bench-infallible-fold -Doptimize=ReleaseFast -- compute 1000003 8 31 1024 64 9
taskset -c 24-31 zig build bench-infallible-fold -Doptimize=ReleaseFast -- scan 4096 1 31 1 256 9
```

[Debug](debug.log) and [ReleaseSafe](release-safe.log) each passed all 75
library tests and three integration tests. [TSan](tsan.log) passed all 75
library tests. [Single-threaded mode](single-threaded.log) passed 60 with 15
concurrency/platform skips. Final test instances compiled for
[WASM/WASI with atomics](wasm32-wasi.log), [Windows GNU](x86_64-windows-gnu.log),
[aarch64 macOS](aarch64-macos.log) and [x86_64 Linux musl](x86_64-linux-musl.log).
The [current fold smoke](fold-smoke.log) validates both token modes and
records zero allocations without a token and one 256-byte allocation with it.

The scheduler core is unchanged. The [strict 1000-node tree gate](strict-parity.log)
still fails: `serial_ns=1510`, `parallel_ns=3211`, `speedup=0.470`, below 0.9.
The [million-node control](large-tree-control.log) passes with
`serial_ns=1767401`, `parallel_ns=773276`, `speedup=2.286`. The overall goal
remains active; reduced flat-fold storage does not establish recursive
small-input parity or theoretical optimality.
