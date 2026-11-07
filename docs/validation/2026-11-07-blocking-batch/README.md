# BlockingQueue partial batch transfers

`BlockingQueue` now supports non-blocking `tryPutSlice`/`tryGetSlice` and
cancelable `putSlice`/`getSlice`. Each locks once, copies the available prefix
with at most two ring-segment `memcpy` operations, advances the queue once and
returns the transferred count. Input and queue storage must not alias; unused
output suffixes remain untouched.

Blocking forms wait only until at least one slot or value is available, then
return partial progress. A canceled wait therefore cannot hide an earlier
partial transfer from the same call. Moving one element or using a singleton
queue delegates to the scalar operation, preserving the small-input path.
Multi-element transfers broadcast the corresponding condition so multiple
MPMC waiters can consume newly available capacity or values.

Tests cover empty slices, full/empty boundaries, partial prefixes, untouched
suffixes, scalar/slice mixing, two-segment wrap and quiescent length. A
two-producer/two-consumer fixture uses different producer and consumer batch
sizes, checks every value exactly once and runs under TSan. Existing scalar
blocking tests remain enabled.

## Fixed-CPU benchmark

The benchmark pins two producers to CPUs 24-25, two consumers to CPUs 26-27,
and serial controls to CPU 31. Allocation, affinity and thread creation occur
before timing. Consumers write private output slices; every value, duplicate,
checksum and final empty queue is checked after timing. Measurements alternate
scalar/batch and serial/parallel order. [`results.json`](results.json) retains
all samples and source hashes.

| Case | API | serial_ns | parallel_ns | speedup | Scalar/batch parallel ratio |
|---|---|---:|---:|---:|---:|
| 2 × 500K, cap 1024, batch 64 | scalar | 26,270,437 | 122,189,449 | 0.215 | — |
| Same | batch | 1,011,502 | 7,849,958 | 0.129 | 15.566x |
| 2 × 500K, cap 1024, batch 256 | scalar | 22,502,341 | 106,736,799 | 0.211 | — |
| Same | batch | 985,505 | 4,943,953 | 0.199 | 21.589x |
| 2 × 100K, cap 1024, batch 1 | scalar | 5,973,640 | 25,336,266 | 0.236 | — |
| Same | slice | 5,281,602 | 25,457,579 | 0.207 | 0.995x |
| 2 × 50K, cap 1, effective batch 1 | scalar | 2,640,107 | 471,097,406 | 0.006 | — |
| Same | slice | 3,090,026 | 474,085,083 | 0.007 | 0.994x |

Batch 64 reduces the parallel median by 93.6%; batch 256 by 95.4%.
One-element and singleton parallel controls stay within roughly 1% of scalar,
satisfying the small-input parity requirement. Same-thread batches also
amortize mutex acquisition, improving batch-64 by about 26x in this sample.

```sh
zig build bench-blocking-batch -Doptimize=ReleaseFast -- \
  500000 1024 64 24,25 26,27 31 9
```

## Verification

- Debug and ReleaseSafe: 89 library tests plus three integration tests passed.
- ThreadSanitizer: all 89 library tests passed.
- Single-threaded ReleaseSafe: 71 passed and 18 thread/platform tests skipped.
- Test instances compiled for WASM/WASI atomics, Windows GNU, aarch64 macOS,
  and x86_64 musl Linux.
- The final ReleaseFast benchmark smoke completed with verified outputs.

These measurements cover one mutex/condition implementation, topology and
payload. They establish the lock-amortized batch path and scalar parity, not a
universal best batch size.
