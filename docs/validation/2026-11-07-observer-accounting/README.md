Concurrent SPSC length observers now read the released head before the tail and clamp the snapshot to queue capacity. The queue’s producer/consumer paths are unchanged. The original pressure test failed because a third thread could observe an old tail and a newer head, causing wrapping subtraction. [spsc-before.log](spsc-before.log) and [spsc-after.log](spsc-after.log) record the negative and positive tests.

Treiber pushes reserve the count before publishing the head. A consumer that can see a node can therefore see the count increment before subtracting it. `len()` includes reservations still being published and is exact when quiescent. The old stress test did not reliably expose the short underflow window; this change is supported by the publication ordering analysis and the new repeated concurrent count/checksum test, rather than a claimed deterministic old failure. [stack-before.log](stack-before.log) and [lengths-after.log](lengths-after.log) retain those observations.

`Future.joinOrCall` uses `tryJoin` followed by `getOutput`, or invokes the caller fallback directly. This avoids constructing an optional output in the helper itself. The public result and fallback semantics are preserved; no general throughput gain is claimed from this source simplification.

Implementation: `4ef14b1ace8bc0f859bd923a0ce4a1747001094d`. Baseline: `4db585899a649d5871defc378a2a302164f682be`. Exact source/binary hashes, CPU set, Zig version, and host load are in [environment.json](environment.json).

`scripts/check.sh` exited with code 0: Debug and ReleaseSafe unit/integration tests, native single-threaded fallback, TSan, WASM/WASI test-instance compilation, Windows GNU, aarch64 macOS, and x86_64 musl Linux compilation. All 56 library tests passed under TSan. [gates.log](gates.log) contains the final results and smoke output.

Fixed input and CPU set `0,2,4,6,8,10,12,14` were used for five alternating baseline/candidate rounds. Each process validates every measured checksum and selects its best paired inner times. The following entries are medians of the five process outputs. [before-after.json](before-after.json) stores every sample.

| Workload | Count | Variant | serial_ns | parallel_ns | speedup |
|---|---:|---|---:|---:|---:|
| tree | 1000 | before | 1438 | 2293 | 0.627 |
| tree | 1000 | after | 1440 | 2311 | 0.623 |
| tree-err | 1000 | before | 1473 | 3293 | 0.447 |
| tree-err | 1000 | after | 1463 | 3407 | 0.429 |
| flat | 16000003 | before | 6822160 | 1743343 | 3.913 |
| flat | 16000003 | after | 6880972 | 1645433 | 4.182 |
| compute | 1000003 | before | 61872806 | 10709221 | 5.778 |
| compute | 1000003 | after | 61781290 | 10678525 | 5.786 |
| compute-inf | 1000003 | before | 62405753 | 10799040 | 5.779 |
| compute-inf | 1000003 | after | 62204289 | 10549569 | 5.896 |

The small tree and CPU fold measurements are broadly similar between revisions. Flat timing improved in this sample set, but host variability and the tiny source change do not establish a general performance gain.

Cold-path experiments were rejected. [cold-path-experiment.json](cold-path-experiment.json) combined a non-inlined sharing helper, a separate slow join helper, and direct join results. Error-union tree measurements worsened. [sharing-only-experiment.json](sharing-only-experiment.json) isolated the sharing helper and produced inconsistent plain/error-union results. These scheduler code-shape changes are absent from the final implementation.

The microbenchmark now accepts node and lane counts, validates every result independently against the node count, alternates each callback shape with serial traversal, and reports nine-run medians. It disables heartbeat sharing to isolate local call/join costs. [micro.log](micro.log) contains raw paired measurements.

| Micro callback | serial_ns | parallel_ns | speedup |
|---|---:|---:|---:|
| plain | 2384 | 4046 | 0.589 |
| error-union | 2414 | 4474 | 0.540 |

The strict 1000-node tree gate remains failing: `serial_ns=1563`, `parallel_ns=2963`, `speedup=0.528` is below 0.9. [strict-parity.log](strict-parity.log) records the checksum-verified paired median result.

```sh
PARZ_BENCH_CPUS=0,2,4,6,8,10,12,14
taskset -c "$PARZ_BENCH_CPUS" zig build bench-micro -Doptimize=ReleaseFast -- 1000 8
taskset -c "$PARZ_BENCH_CPUS" zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000 heartbeat gate
```

The goal remains active. Small-input parity is still unachieved, built-in NUMA-aware allocation remains unimplemented, and the available runtime performance evidence covers this host and CPU set.
