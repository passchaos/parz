# Sharded MPSC batch transfers

`ShardedMpscQueue` now exposes `tryPushSlice(shard_index, values)` and
`tryPopSlice(output)`. Each producer delegates to its private SPSC shard, so a
batch prefix is published with one release and producers never contend on a
global reservation cursor. The single consumer starts at its round-robin
cursor, visits each shard at most once, and fills an output prefix. If one
shard fills the output, the next call starts at the following shard.

Ordering remains FIFO per shard and intentionally has no cross-shard global
order. Scalar and slice operations can be mixed. Empty slices return zero,
partial transfers leave the output suffix untouched, counters may wrap, and
all operations allocate only during queue initialization.

Tests cover scalar/slice mixing across counter wrap, full and partial pushes,
empty inputs and outputs, untouched suffixes, scalar consumption after batch
production, exact quiescent length, and per-shard FIFO. A concurrent fixture
mixes scalar and batches from four producers with scalar and batch consumer
calls across wrap. Every value and per-shard sequence is checked under TSan.
Failing-allocation injection at every shard initialization point verifies that
all already-created shards are released.

## Fixed-CPU benchmark

The benchmark prebuilds identical producer inputs, pins producers to CPUs
24-27 and the consumer to CPU 31, excludes allocation/thread startup from
timing, and validates every value, per-producer FIFO, checksum and final empty
queue. Nine measurements alternate scalar/batch and serial/parallel order;
table cells are medians. [`results.json`](results.json) retains raw samples and
source hashes.

| Case | API | serial_ns | parallel_ns | speedup | Scalar/batch parallel ratio |
|---|---|---:|---:|---:|---:|
| 4 × 750K, cap/shard 1024, batch 64 | scalar | 14,779,516 | 147,959,275 | 0.100 | — |
| Same | batch | 8,132,048 | 9,824,501 | 0.828 | 15.060x |
| 4 × 750K, cap/shard 1024, batch 256 | scalar | 15,265,708 | 152,266,238 | 0.100 | — |
| Same | batch | 7,907,388 | 8,033,356 | 0.984 | 18.954x |
| 4 × 100K, cap/shard 1024, batch 1 | scalar | 3,944,031 | 20,798,172 | 0.190 | — |
| Same | slice | 4,775,709 | 21,178,229 | 0.226 | 0.982x |
| 4 × 50K, cap/shard 1, effective batch 1 | scalar | 1,977,330 | 17,509,687 | 0.113 | — |
| Same | slice | 2,423,546 | 17,133,971 | 0.141 | 1.022x |

Batch 64 reduces the parallel median by 93.4%; batch 256 by 94.7%. Effective
one-element paths remain within about 2% of scalar, showing that the wrapper
does not impose a material parallel penalty on tiny queues.

For context, the globally ordered four-producer `MpscQueue` batch-64 median in
the same session was 39.136 ms, while sharded batch-64 was 9.825 ms. This
roughly 4x difference reflects the deliberately weaker per-shard ordering and
private producer cursors; the sharded queue is not a semantic replacement
when global reservation order is required.

```sh
zig build bench-sharded-mpsc-batch -Doptimize=ReleaseFast -- \
  750000 1024 64 24,25,26,27 31 9
```

## Verification

- Debug and ReleaseSafe: 87 library tests plus three integration tests passed.
- ThreadSanitizer: all 87 library tests passed.
- Single-threaded ReleaseSafe: 70 passed and 17 thread/platform tests skipped.
- Test instances compiled for WASM/WASI atomics, Windows GNU, aarch64 macOS,
  and x86_64 musl Linux.
- The ReleaseFast full benchmark and final smoke completed with verified FIFO
  and checksums.

These results cover one CPU topology and payload. They establish the batch API
and its intended no-contention producer path, not universal optimality for all
batch sizes or consumer workloads.
