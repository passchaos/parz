`MpscQueue.tryPushSlice` reserves an available input prefix with one enqueue
CAS for capacities of four or more, then publishes each slot with its existing
release sequence store. One- and two-slot queues use scalar operations.
For larger queues, `tryPopSlice` copies the consecutive ready prefix and updates
the owner-only consumer position once. Both APIs accept empty slices, return
a partial transfer count, cap each transfer at capacity, and allocate nothing. Scalar
and batch operations may be mixed. Single-element requests and singleton
queues use the scalar path directly; two-slot queues perform at most two
scalar operations. Another producer may interleave between those two pushes;
per-producer FIFO is preserved.

A producer first acquires every free slot's sequence, then attempts to move
the enqueue position over the entire prefix. CAS failure invalidates the
candidate prefix and restarts validation at the returned position. A
successful CAS owns all those slots until they are published. Each slot's
release/acquire sequence protocol protects its payload and authorizes later
reuse. Reservation and slot arithmetic wrap with `+%`, preserving the
existing ring protocol across `usize` overflow.

The single consumer cannot pass an unpublished reservation. Both pop APIs
require the current slot's exact ready sequence; a later producer's published
slots remain inaccessible until the earlier producer publishes. Scalar pop
now checks that equality once rather than retrying the same consumer position.
Only this consumer advances that position, and no valid slot can advance to a
later cycle before it has consumed the current one. FIFO follows reservation
order, with FIFO within each producer; completion order does not choose the
output sequence. A stalled producer can delay access to later ready slots,
as in the existing scalar queue.

The new tests compare randomized scalar/slice operations against an
independent FIFO model at requested capacities 0, 1, 2, 3, 8 and 64. They seed
positions near `usize` overflow, verify exact partial counts and untouched
output suffixes, fill and drain wrapped rings, and check wide aligned payloads
and zero-size elements. A paused-reservation fixture proves the consumer
does not skip a hole. Four concurrent mixed scalar/batch producers transfer
distinct values twice at capacities 1, 2, 8 and 1024, across counter overflow;
the consumer checks every producer's full sequence and the total checksum.

The benchmark uses prebuilt identical inputs and receiver buffers. It checks
every warmup and measured transfer for both checksum and per-producer FIFO,
then reports medians of nine measurements. It alternates scalar/batch API and
serial/parallel order; queue allocation, thread startup and CPU affinity setup
precede timing. Serial means all queue operations occur on the consumer
thread. Parallel means fixed producer threads and a fixed consumer CPU. FIFO
checking is common measured work in all paths, so results describe verified
transfer throughput, including that work.

Each table row records `serial_ns`, `parallel_ns` and their ratio. The final
column compares scalar and batch **parallel** times for the same fixed input;
it does not claim parallel scaling relative to same-thread execution.

| Case | API | serial_ns | parallel_ns | speedup | Scalar/batch parallel ratio |
|---|---|---:|---:|---:|---:|
| E, 1 producer × 1M, capacity 1024, batch 64 | scalar | 10,666,171 | 42,384,711 | 0.252 |  |
| E, 1 producer × 1M, capacity 1024, batch 64 | batch | 4,101,660 | 11,914,415 | 0.344 | 3.557 |
| E, 4 producers × 750K, capacity 1024, batch 64 | scalar | 32,199,234 | 426,233,373 | 0.076 |  |
| E, 4 producers × 750K, capacity 1024, batch 64 | batch | 12,492,254 | 39,286,910 | 0.318 | 10.849 |
| E, 4 producers × 750K, capacity 1024, batch 8 | scalar | 32,034,570 | 410,379,283 | 0.078 |  |
| E, 4 producers × 750K, capacity 1024, batch 8 | batch | 14,597,405 | 48,495,728 | 0.301 | 8.462 |
| E, 4 producers × 750K, capacity 1024, batch 1 | scalar | 23,263,221 | 410,221,549 | 0.057 |  |
| E, 4 producers × 750K, capacity 1024, batch 1 | batch | 23,372,761 | 410,732,429 | 0.057 | 0.999 |
| E, 4 producers × 50K, capacity 1, effective batch 1 | scalar | 1,913,254 | 24,770,433 | 0.077 |  |
| E, 4 producers × 50K, capacity 1, effective batch 1 | batch | 1,949,020 | 23,778,938 | 0.082 | 1.042 |
| P, 4 producers × 750K, capacity 1024, batch 64 | scalar | 37,950,450 | 501,952,754 | 0.076 |  |
| P, 4 producers × 750K, capacity 1024, batch 64 | batch | 9,821,808 | 29,587,654 | 0.332 | 16.965 |
| E, 4 producers × 100K, capacity 2, batch 2 | scalar | 4,514,254 | 72,575,519 | 0.062 |  |
| E, 4 producers × 100K, capacity 2, batch 2 | batch | 4,789,197 | 72,163,228 | 0.066 | 1.006 |
| E, 4 producers × 100K, capacity 8, batch 8 | scalar | 4,252,418 | 61,240,979 | 0.069 |  |
| E, 4 producers × 100K, capacity 8, batch 8 | batch | 1,979,846 | 21,949,551 | 0.090 | 2.790 |

E-core cases use producers 24–27 and consumer 31; the one-producer case uses
producer 24. The P-core case uses producers 0, 2, 4, 6 and consumer 14, all on
distinct physical cores. [Environment](environment.json) records source
hashes, Zig 0.16.0 and topology. The host is loaded; these are bounded results
for the recorded workloads and CPU placement. [Results](results.json) and
the corresponding per-case logs retain all measurements. The initial
[smoke](initial-smoke.log) used 400K total items and also verified FIFO and checksum;
the [final smoke](smoke.log) uses the final implementation and benchmark.

Applying the general batch path to capacity two initially regressed parallel
time: [first measurement](initial-capacity-two.log) had a scalar/batch ratio of
0.936, and [confirmation](initial-capacity-two-confirm.log) had 0.794. The
[two-slot fallback](two-slot-fallback.patch) uses at most two direct scalar
operations, preserving partial-transfer and per-producer FIFO semantics. Its
first two ratios were 1.006 and 0.985, and the final harness recorded 1.006.
Capacity eight retains the batch path and its final ratio is 2.790.

When the effective batch is one, the final benchmark specializes that loop
with a known one-element input/output slice. It still invokes the actual
scalar and slice APIs and performs the same FIFO and checksum checks. This
separates direct single-element API costs from the variable batch loop
scaffolding. The earlier [variable-length single-item](runtime-length-single-item.log)
and [singleton](runtime-length-singleton.log) logs are preserved, including
the singleton's 0.859 parallel ratio. The final direct-singleton ratio is
1.042; this does not prove that every variable-length slice caller has zero
overhead. All final multi-item cases were remeasured with the same final
benchmark source. Earlier samples remain under `initial-*` and
`before-one-item-specialization-*` filenames.

```sh
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 1000000 1024 64 24 31 9
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 750000 1024 64 24,25,26,27 31 9
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 750000 1024 8 24,25,26,27 31 9
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 750000 1024 1 24,25,26,27 31 9
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 50000 1 64 24,25,26,27 31 9
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 750000 1024 64 0,2,4,6 14 9
```

[Debug](debug.log) and [ReleaseSafe](release-safe.log) each passed all 71
library tests and three integration tests. [TSan](tsan.log) passed all 71
library tests. [Single-threaded mode](single-threaded.log) passed 57 tests
with 14 concurrency/platform skips.

The final test instances compiled successfully for
[WASM/WASI with atomics](wasm32-wasi.log),
[Windows GNU](x86_64-windows-gnu.log), [aarch64 macOS](aarch64-macos.log) and
[x86_64 Linux musl](x86_64-linux-musl.log). The [sync smoke](sync-smoke.log)
completed, with SPSC checksum 499999500000.

The scheduler core is byte-identical to baseline `ea34b6e`, as recorded in
the environment metadata. The [strict 1000-node tree gate](strict-parity.log)
still fails: `serial_ns=1682`, `parallel_ns=3522`, `speedup=0.478`, below the
0.9 floor. The [million-node control](large-control.log) passes with
`serial_ns=1751253`, `parallel_ns=815263`, `speedup=2.148`. MPSC throughput
improvements do not establish small-tree parity or theoretical optimality.
The overall goal remains active.
