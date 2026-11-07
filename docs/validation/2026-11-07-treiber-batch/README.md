# TreiberStack batch publication and removal

`TreiberStack.pushSlice(nodes)` links a contiguous caller-owned node slice,
reserves its count once and publishes the chain with one successful head CAS.
It is equivalent to scalar pushes in slice order: the last slice element is
the first item popped. Only the tail link changes when a competing producer
wins the CAS.

The single consumer can call `popSlice(output)` to traverse a stack-order
prefix and detach it with one successful CAS, then decrement the count once.
The unused output suffix remains untouched. Empty operations are no-ops and
one-element slices inline the scalar methods; larger bodies stay outlined to
avoid caller code growth. The existing single-consumer ABA argument is
unchanged because producers only prepend and cannot remove a node.

Tests cover exact mixed scalar/batch LIFO order, empty and partial outputs,
untouched suffixes and node reuse after complete removal. Four concurrent
producers alternate scalar pushes and 31-node slices while the consumer mixes
scalar and 37-node pops. Every node is observed exactly once, the approximate
concurrent count never exceeds the total, and final count/head are empty. The
fixture passes under TSan.

## Fixed-CPU benchmark

The benchmark pins four producers to CPUs 24-27 and the consumer to CPU 31.
Node initialization is timed identically in scalar and batch paths; thread
startup and affinity are excluded. The consumer records values into a private
output array, and duplicate/checksum/final-stack checks run after timing. Nine
measurements alternate scalar/batch and serial/parallel order.
[`results.json`](results.json) retains raw samples and source hashes.

| Case | API | serial_ns | parallel_ns | speedup | Scalar/batch parallel ratio |
|---|---|---:|---:|---:|---:|
| 4 × 250K, batch 64 | scalar | 20,364,429 | 98,747,420 | 0.206 | — |
| Same | batch | 3,219,681 | 3,254,862 | 0.989 | 30.338x |
| 4 × 250K, batch 256 | scalar | 20,402,696 | 98,137,843 | 0.208 | — |
| Same | batch | 3,969,505 | 3,089,188 | 1.285 | 31.768x |
| 4 × 100K, batch 1 | scalar | 8,150,495 | 39,528,189 | 0.206 | — |
| Same | slice | 8,190,134 | 39,167,975 | 0.209 | 1.009x |

Batch 64 reduces the parallel median by 96.7%; batch 256 by 96.9%.
The one-element slice path is effectively identical to scalar. At batch 256,
parallel publication/removal is faster than the same-thread batch path because
producers initialize and link disjoint node ranges concurrently.

```sh
zig build bench-treiber-batch -Doptimize=ReleaseFast -- \
  250000 64 24,25,26,27 31 9
```

## Verification

- Debug and ReleaseSafe: 91 library tests plus three integration tests passed.
- ThreadSanitizer: all 91 library tests passed.
- Single-threaded ReleaseSafe: 72 passed and 19 thread/platform tests skipped.
- Test instances compiled for WASM/WASI atomics, Windows GNU, aarch64 macOS,
  and x86_64 musl Linux.
- The final ReleaseFast smoke and full benchmark completed with every-value
  and checksum validation.

These results cover contiguous node slices and one topology. They establish
the CAS/count amortization path, not optimality for arbitrary noncontiguous
node collections.
