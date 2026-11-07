SPSC now supports `tryPushSlice` and `tryPopSlice`. Each returns the transferred prefix length, including zero for full/empty or empty slices. FIFO ordering is preserved across scalar and slice operations. A pop leaves the unused output suffix untouched. The caller's slices must not alias queue storage; endpoints remain single-producer/single-consumer. The methods allocate no memory and keep the existing queue metadata/buffer layout and scalar API.

Producer free space is bounded by its cached acquired head; the cache refreshes when the requested prefix needs more space. Consumer readable data is bounded by its cached acquired tail; it refreshes when the requested output needs more data. Copies touch only the acquired prefix. One release store publishes/frees each batch after all copies finish. At ring wrap, at most two contiguous copies are used; small word-sized prefixes use a bounded direct loop. Counter addition/subtraction retain wrapping arithmetic.

Empty slices return immediately. One-element slices and singleton-capacity queues delegate to the scalar operation. Small wrappers remain inline while bulk bodies are separate, so the scalar shortcut avoids bulk copy code. Queue initialization/deinitialization and allocation provenance are unchanged.

New tests compare randomized scalar/batch operations with independent FIFO counts across requested capacities 0,1,2,3,8,64, seeded near `usize` overflow. They check partial transfers, ring wrap, empty inputs/outputs and untouched output suffixes. Zero-sized elements are covered. Concurrent mixed transfer repeats capacities 1,2,8,64,1024, with differing producer/consumer batch lengths, scalar interleaving and a third-party length observer. Every received value and checksum are checked after joining both threads.

[Debug](debug.log) and [ReleaseSafe](release-safe.log) each passed 67 library tests and three integration tests. [TSan](tsan.log) passed all 67 library tests. [Single-threaded](single-threaded.log) passed 54 tests with 13 concurrency/platform skips. WASM/WASI with atomics, Windows GNU, aarch64 macOS and x86_64 Linux musl test instances [compiled successfully](cross-targets.log).

The focused benchmark uses the same prebuilt sequence and receiving scratch buffer in both paths. The scalar producer/consumer loop transfers into those buffers with per-item APIs; the batch path transfers the same data with slice APIs. Both verify each payload against input, checksum and final queue length in every warmup and sample. Allocation, CPU pinning and thread creation occur before timing. Serial paths fill/drain the same capacity-bounded transfer groups on one thread. Nine rounds alternate scalar/batch and serial/parallel order and report medians.

Requested batch sizes are clamped to actual queue capacity for the receiving buffer; the header prints both requested and effective sizes. Effective size one uses one-element slices with a compile-time known length in both benchmark paths. Thus the singleton control exercises each API's one-element path without the generic large-batch caller loop. Earlier experimental timings used unequal receiving work and are superseded by the final logs.

The host is an i9-13900K using Zig 0.16.0 ReleaseFast. E-core transfer pins producer 24 and consumer 26; P-core transfer pins producer 0 and consumer 2. Inputs and placements are fixed for every comparison. Source hashes and parameters are in [environment.json](environment.json), and raw samples are retained in the linked logs.

| Configuration | API | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| [3M items, cap 1024, batch 1, E cores](batch-1.log) | scalar | 2,381,212 | 5,930,987 | 0.401 |
| Same | slice | 2,341,304 | 6,080,094 | 0.385 |
| [3M items, cap 1024, batch 8, E cores](batch-8.log) | scalar | 5,883,318 | 7,585,821 | 0.776 |
| Same | slice | 5,943,014 | 7,011,305 | 0.848 |
| [3M items, cap 1024, batch 64, E cores](batch-64.log) | scalar | 5,412,619 | 8,920,651 | 0.607 |
| Same | slice | 2,888,050 | 4,035,320 | 0.716 |
| [3M items, cap 1024, batch 256, E cores](batch-256.log) | scalar | 5,857,272 | 8,628,813 | 0.679 |
| Same | slice | 3,288,056 | 3,113,050 | 1.056 |
| [100k items, cap 1, effective batch 1, E cores](capacity-1.log) | scalar | 58,923 | 19,580,900 | 0.003 |
| Same | slice | 71,114 | 19,531,427 | 0.004 |
| [3M items, cap 1024, batch 64, P cores](pcores.log) | scalar | 4,428,809 | 36,449,771 | 0.122 |
| Same | slice | 2,058,632 | 5,336,559 | 0.386 |
| [1000 items, cap 1024, batch 64, E cores](small-input.log) | scalar | 2,144 | 2,617 | 0.819 |
| Same | slice | 1,073 | 1,937 | 0.554 |

The separate `comparison` rows in the logs divide scalar parallel time by slice parallel time: batch 64 is 2.211x on E cores and 6.830x on P cores in this set; batch 256 is 2.772x on E cores. Effective one-element parallel transfers are essentially equal. Capacity-one serial timing differs by about 12 us over 100k transfers in this tiny control. These figures describe this buffered transfer workload on a host with other active work. They do not establish a universal optimal batch size; batching trades notification granularity for fewer publication operations.

```sh
zig build bench-spsc-batch -Doptimize=ReleaseFast -- 3000000 1024 64 24 26 9
zig build bench-spsc-batch -Doptimize=ReleaseFast -- 100000 1 64 24 26 9
zig build bench-spsc-batch -Doptimize=ReleaseFast -- 3000000 1024 64 0 2 9
```

The overall optimization goal remains active. SPSC batching does not change the scheduler or solve its strict 1000-node tree gate. The prior [scheduler parity evidence](../2026-11-07-future-init/strict-parity.log) remains applicable to the unchanged scheduler implementation: `serial_ns=1503`, `parallel_ns=3128`, `speedup=0.480`, below 0.9.
