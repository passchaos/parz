Flat ranges now contain only nonempty, balanced chunks, respect `min_chunk`, and avoid overflowing planning intermediates. The same cursor is used by ranges and both fold variants. Cancellation block endpoints also use saturating addition.

The one-slot MPSC ring now distinguishes empty, reserved, and ready states. Requested capacities 0 and 1 retain an actual capacity of one. Concurrent producers cannot overwrite an unconsumed value.

Serial range and fold helpers destroy the temporary worker context that callbacks actually modified. The regression test exercised scratch allocation through all three helpers, both below the serial threshold and with an exhausted caller slot, using zero background workers. Before the fix, the assertions passed but the allocator reported six leaks and the test process exited with code 1. The fixed test passes without leaks.

Error-union futures with inputs no larger than one machine word initialize their pending previous pointer and omit the local join handler check. Plain values and wider inputs retain their original initialization and guard. Pending joins, errors, shared execution, and caller fallback are checked repeatedly with 0–4 background workers. The existing recursive integration test also checks repeated results across worker counts.

Implementation: `7ec35c2a158398b9eea56bfe39ee63d731361ce2`. Baseline: `a6f1514a8781de2241235f6453f41bc802710e6d`. Exact source hashes, benchmark binary hashes, Zig version, CPU topology, and host load are in [environment.json](environment.json).

`scripts/check.sh` completed with exit code 0. [gates.log](gates.log) contains the final serial/TSan results and benchmark smoke output.

| Validation | Result |
|---|---|
| `zig build test` | Debug unit and integration tests passed |
| `zig build test -Doptimize=ReleaseSafe` | ReleaseSafe unit and integration tests passed |
| `zig test src/root.zig -fsingle-threaded -OReleaseSafe` | 38 passed, 9 thread-dependent tests skipped |
| `zig test src/root.zig -fsanitize-thread -OReleaseSafe` | All 47 unit tests passed |
| WASM/WASI with atomics | Unit-test instances compiled, execution not attempted |
| Windows GNU, aarch64 macOS, x86_64 musl Linux | Unit-test instances compiled, execution not attempted |
| Sync, 2D, zero-worker skewed tree | Native smoke runs completed |

The cross-target gate now compiles test instances, replacing the earlier build-object check of generic declarations. The strict parity gate is separate from these correctness checks.

All timing comparisons below use CPU set `0,2,4,6,8,10,12,14` and 8 lanes. Library comparisons alternate the baseline and candidate process order over five rounds. Each process alternates serial and parallel runs nine times and validates its checksum before reporting its result. Table entries are medians of the five process results; each process reports its best inner times. Raw samples are in [before-after.json](before-after.json).

| Workload | Input | Revision | serial_ns | parallel_ns | speedup |
|---|---:|---|---:|---:|---:|
| tree | 1000 | before | 1345 | 2334 | 0.576 |
| tree | 1000 | after | 1425 | 2490 | 0.572 |
| tree-err | 1000 | before | 1383 | 3915 | 0.353 |
| tree-err | 1000 | after | 1455 | 3431 | 0.424 |
| tree-err | 1000000 | before | 1464423 | 925841 | 1.582 |
| tree-err | 1000000 | after | 1506588 | 798557 | 1.887 |
| flat | 16000003 | before | 6465145 | 1668363 | 3.875 |
| flat | 16000003 | after | 6490890 | 1727282 | 3.758 |
| compute | 1000003 | before | 62301783 | 10611455 | 5.871 |
| compute | 1000003 | after | 62156327 | 10150384 | 6.124 |
| compute-inf | 1000003 | before | 61886410 | 10390233 | 5.956 |
| compute-inf | 1000003 | after | 61973593 | 10019429 | 6.185 |

The error-union tree improved in this batch. Plain tree ratios were essentially unchanged. Flat and compute results vary across batches; these samples do not establish a general throughput improvement or theoretical optimality.

The new irregular benchmark warms both paths, validates every result against an independent sum over node storage, alternates which path runs first, and reports nine-run medians. `mixed` distributes fixed pseudo-random costs; `skewed` makes every node in the left subtree cost 32 units while right-subtree nodes cost one.

| Profile | Nodes | serial_ns | parallel_ns | speedup |
|---|---:|---:|---:|---:|
| [mixed](irregular-mixed.log) | 200000 | 35233625 | 7611604 | 4.629 |
| [skewed](irregular-skewed.log) | 200000 | 47637053 | 11775248 | 4.046 |

The strict tree gate requires speedup at least 0.9, rejecting a slowdown greater than roughly 11%. It validates every checksum before making the timing decision. The 1000-node gate remains failing; the million-node control passes. These are paired medians from the dedicated tree harness, so they use a different statistic from the comparison table above.

| Gate | serial_ns | parallel_ns | speedup | Result |
|---|---:|---:|---:|---|
| [1000 nodes](small-tree.log) | 1709 | 3230 | 0.529 | FAIL |
| [1000000 nodes](parity-large-control.log) | 1652829 | 775094 | 2.132 | PASS |

Experiments are retained to guide later work. [inline-experiment.json](inline-experiment.json) records forcing error-union recursion inline, which made both small and large error-union trees slower. [join-branch-experiment.json](join-branch-experiment.json) records dropping the handler guard for every future type; the plain small tree did not benefit. [broad-join-fold-confirmation.json](broad-join-fold-confirmation.json) records the noisier fold measurements from a broader error-union variant. The final specialization keeps the wider-input paths intact and applies the safe pending initialization only to the optimized types.

Reproduce the strict gate and the irregular profiles with:

```sh
PARZ_BENCH_CPUS=0,2,4,6,8,10,12,14
# Expected failure until small-input parity is improved.
taskset -c "$PARZ_BENCH_CPUS" zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000 heartbeat gate
taskset -c "$PARZ_BENCH_CPUS" zig build bench-irregular -Doptimize=ReleaseFast -- 200000 8 9 mixed
taskset -c "$PARZ_BENCH_CPUS" zig build bench-irregular -Doptimize=ReleaseFast -- 200000 8 9 skewed
```

The goal remains active. Small-input parity is unachieved, the available timing evidence covers this host and CPU set, and built-in NUMA-aware allocation remains unimplemented. Follow-up audits should check automatic affinity worker counts against the selected physical-core CPU list and per-call worker caps against actual executing lanes.
