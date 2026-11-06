Every nested `Task` now uses its worker's current local tail. A reclaimed shared future can therefore fork descendants onto the owner's actual local list, where heartbeat and `kickstart` can offer them to idle lanes. `Task` contains only the worker pointer; the local tail is initialized with worker registration and reset when a caller slot is claimed or released. Fork still appends with plain stores and allocates no memory.

The regression starts with a parent future, forks another future in a nested call, and shares the parent while retaining the nested future. The nested future is joined locally. In the old implementation, the parent Task's copied tail still pointed to the detached shared parent. After reclaiming that parent, its fallback callback appended descendant jobs behind the detached job, so `kickstart` saw an empty owner list and offered no descendants. The returned values remained correct, but subsequent parallelism was lost.

The identical [regression fixture](reclaim-fixture.zig) fails against the committed baseline `2a3537a` and passes against the new implementation. [Before](reclaim-before.log) and [after](reclaim-after.log) retain the ReleaseSafe results. The baseline was exported without implementation modifications. Its exact commit, source hashes, benchmark hashes, CPU model and load are in [environment.json](environment.json).

Sharing always retains the owner's current local tail. Comparing a future's job with that owner-only pointer therefore proves that the matching job has not been published to another lane. The local tail join uses plain links and returns false/null for caller execution without loading atomic state. Non-tail jobs retain the acquire/tag checks, shared reclaim and event-wait paths. `popWithPrev` unlinks the local tail using its known predecessor; Debug and ReleaseSafe assert the local state, tail and predecessor relationship.

The new unit test repeats the descendant-publication scenario ten times for every worker count 0–4, both with no execution states and with 16 states. This covers deterministic caller reclaim and actual worker execution, and checks that the caller's local head/tail are empty afterward. Recursive integration now uses distinct node values, checks an independent arithmetic sum, and repeats every worker count 0–4. Existing error, pending-future, wide-payload, caller-fallback, per-worker-context and ordered flat-fold tests continue to pass.

Debug and ReleaseSafe each passed 63 library tests and three integration tests: [Debug](debug.log), [ReleaseSafe](release-safe.log). [TSan](tsan.log) passed all 63 library tests. [Single-threaded mode](single-threaded.log) passed 51 tests with 12 concurrency/platform skips. WASM/WASI with atomics, Windows GNU, aarch64 macOS and x86_64 Linux musl test instances [compiled successfully](cross-targets.log).

The tree and micro benchmarks now optionally pin the caller after pool initialization and background startup. They pin each background worker, reject a caller CPU outside the allowed set or already assigned to a worker, and print placement. This avoids reducing the pool's captured CPU set when pinning the caller. In this comparison the allowed set is `24-31`, caller CPU is 31, and background workers use CPUs 24–30 on an i9-13900K. Micro uses one lane and disables heartbeat to isolate local call/fork/join cost.

Baseline and candidate use identical benchmark sources. Each process warms both paths, alternates serial and parallel runs nine times, verifies every checksum independently against node count, and reports paired medians. An outer runner alternates baseline/candidate process order across five rounds. The table contains medians of those five process medians. [before-after.json](before-after.json) retains each process result; [paired-samples.log](paired-samples.log) retains every inner sample and placement record.

| Workload | Revision | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| 1000-node local plain callback | baseline | 1,526 | 3,039 | 0.502 |
| 1000-node local plain callback | current | 1,505 | 3,028 | 0.497 |
| 1000-node local error-union callback | baseline | 1,477 | 3,401 | 0.434 |
| 1000-node local error-union callback | current | 1,470 | 3,218 | 0.457 |
| 1000-node heartbeat tree, 8 lanes | baseline | 1,477 | 3,364 | 0.439 |
| 1000-node heartbeat tree, 8 lanes | current | 1,491 | 3,239 | 0.460 |
| 100,000-node heartbeat tree, 8 lanes | baseline | 161,859 | 138,268 | 1.171 |
| 100,000-node heartbeat tree, 8 lanes | current | 159,890 | 138,483 | 1.155 |
| 1,000,000-node heartbeat tree, 8 lanes | baseline | 1,821,030 | 829,120 | 2.196 |
| 1,000,000-node heartbeat tree, 8 lanes | current | 1,819,050 | 736,160 | 2.471 |

The small error-union paths improve modestly in this set; plain and medium-tree times are effectively unchanged. The million-node parallel median is about 11% lower. These measurements cover this input and CPU set on a host with other active workloads. They establish the comparison and the restored descendant scheduling behavior; theoretical optimality remains unproven.

```sh
taskset -c 24-31 zig build bench-micro -Doptimize=ReleaseFast -- 1000 1 31
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000 heartbeat gate 31
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000000 heartbeat gate 31
```

The final [1000-node strict parity gate](strict-parity.log) still fails: `serial_ns=1673`, `parallel_ns=3396`, `speedup=0.493`, below 0.9. The [million-node control](large-tree-control.log) passes with `serial_ns=1971187`, `parallel_ns=819753`, `speedup=2.405`. The overall optimization goal remains active.
