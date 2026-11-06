Flat APIs now publish one future per execution lane. The caller runs its retained lane immediately, and each lane claims disjoint chunks from an atomic index. Results and errors are stored by chunk index and combined after every lane has joined. This enforces `ParallelOptions.max_workers`, including the caller, without changing the serial threshold fallback or the scheduler’s plain-store fork protocol.

Dispatch storage uses one 4 KiB stack fallback allocator for chunk results and lane futures. The single-lane path uses a plain chunk cursor. Larger storage falls back to the caller-supplied allocator. Allocation failures occur before any lane future is forked and release the caller slot.

Linux pinning selects the first allowed sibling for each physical core, including CPU sets that exclude the core’s absolute first sibling. Selection is captured during `Pool.init`. Automatic worker count reserves one selected CPU for the caller; explicit counts are bounded by the selected list, so background workers do not wrap onto the same selected CPU. Idle heartbeat pacing uses the number of successfully spawned workers.

Implementation: `571ca6bde4cc8aa9be34adf0029115d15092105c`. Baseline: `7eb693c463f47cb5e2d1c8dfc3cac874d04a8dd6`. Source hashes, binary hashes, Zig version, CPU set, and host load are in [environment.json](environment.json).

The old worker-cap implementation failed the concurrent callback test; [cap-before.log](cap-before.log) records that failure. The final test repeats 0–4 background workers and caps 1–5, checks concurrent callback counts, caller participation, and exact coverage. Fold tests verify associative but noncommutative sequence hashes and first-error ordering. Tests also cover zero execute states, nested capped calls, cancellation cleanup, result allocation failure, and lane-future allocation failure.

`scripts/check.sh` completed with exit code 0: Debug and ReleaseSafe unit/integration tests, native single-threaded fallback, TSan, WASM/WASI compilation, and Windows GNU, aarch64 macOS, and x86_64 musl Linux test-instance compilation. The library has 54 unit tests. [gates.log](gates.log) records the final serial/TSan results and smoke runs. [affinity-subset.log](affinity-subset.log) records four passing affinity tests under CPU set `{1,2}`.

Performance comparisons use fixed input, CPU set `0,2,4,6,8,10,12,14`, and an 8-lane pool. Both revisions use the same benchmark harness, which validates every measured checksum. Baseline/candidate order alternates over five rounds. Table entries are medians of the process results; each process selects its best paired inner serial and parallel times. [default-before-after.json](default-before-after.json) contains all samples.

| Workload | Count | Variant | serial_ns | parallel_ns | speedup |
|---|---:|---|---:|---:|---:|
| tree | 1000 | before | 1505 | 3425 | 0.439 |
| tree | 1000 | after | 1732 | 4128 | 0.420 |
| tree-err | 1000 | before | 1384 | 3539 | 0.391 |
| tree-err | 1000 | after | 1493 | 3698 | 0.404 |
| tree-err | 1000000 | before | 1531152 | 1026289 | 1.492 |
| tree-err | 1000000 | after | 1638505 | 951369 | 1.722 |
| flat | 16000003 | before | 7262289 | 2052685 | 3.538 |
| flat | 16000003 | after | 7185951 | 2090622 | 3.437 |
| compute | 1000003 | before | 62335762 | 10946006 | 5.695 |
| compute | 1000003 | after | 62436329 | 10463166 | 5.967 |
| compute-inf | 1000003 | before | 62405108 | 11312670 | 5.516 |
| compute-inf | 1000003 | after | 62756994 | 9060830 | 6.926 |

CPU fold improved in this batch. Flat scans and small tree measurements vary with host load; these samples do not establish a universal throughput improvement. The isolated [default-lane-experiment.json](default-lane-experiment.json) compared only the default flat dispatch change and showed roughly 5–7% lower CPU fold time. [join-or-call-experiment.json](join-or-call-experiment.json) tested a recursive join API substitution that did not show a stable gain; that substitution was not adopted.

The following candidate-only measurements alternate cap order over three rounds. Cap 0 uses all eight pool lanes. [capped-samples.json](capped-samples.json) contains every sample.

| Workload | Cap | serial_ns | parallel_ns | speedup |
|---|---:|---:|---:|---:|
| flat | 0 | 7097482 | 2010654 | 3.530 |
| flat | 2 | 6974413 | 3844835 | 1.814 |
| flat | 4 | 6964141 | 2424442 | 2.872 |
| compute | 0 | 62409730 | 10229926 | 6.101 |
| compute | 2 | 62619620 | 32987754 | 1.898 |
| compute | 4 | 62128995 | 17122507 | 3.628 |
| compute-inf | 0 | 62434268 | 10328814 | 6.045 |
| compute-inf | 2 | 62442282 | 31818297 | 1.962 |
| compute-inf | 4 | 62694523 | 17064213 | 3.674 |

The strict 1000-node tree gate remains failing: `serial_ns=1701`, `parallel_ns=3280`, `speedup=0.519` against the 0.9 floor. [strict-parity.log](strict-parity.log) contains paired medians and checksum validation from the dedicated tree harness. This is a different statistic from the comparison tables above.

```sh
PARZ_BENCH_CPUS=0,2,4,6,8,10,12,14
# Strict gate remains failing.
taskset -c "$PARZ_BENCH_CPUS" zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000 heartbeat gate
taskset -c "$PARZ_BENCH_CPUS" zig-out/bin/compare-parz compute 1000003 8 0 16 heartbeat 10000 2
```

The overall goal remains active. The strict small-input parity target is unachieved, measurements cover this host and CPU set, and built-in NUMA-aware allocation remains unimplemented.
