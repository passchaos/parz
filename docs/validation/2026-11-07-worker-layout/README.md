The scheduler remains byte-for-byte identical to committed `03c23aa`. Two worker padding experiments were rejected after fixed-CPU measurements failed to show stable gains. A new `check-worker-layout` diagnostic reports actual field offsets, worker size and worker/context alignment before further layout changes.

```sh
zig build check-worker-layout -Doptimize=ReleaseSafe
```

The diagnostic covers `void`, an ordinary 64-byte context, and contexts aligned to 16, 64 and 256 bytes. [current-layout.log](current-layout.log) records the compiler output. Source/binary hashes, the baseline commit, Zig version, host load and comparison CPU sets are in [environment.json](environment.json).

The first experiment aligned the heartbeat flag and the remaining metadata to separate 128-byte cache units. This preserved field types and methods but moved hot fields farther from the worker base. It passed Debug unit/integration tests. The second used a zero-sized alignment anchor to align every worker array element while preserving every existing field offset across all five inspected context layouts. Both patches are retained for review: [heartbeat isolation](rejected-isolated.patch), [array alignment](rejected-aligned.patch).

| Context | Current worker bytes | Isolated-heartbeat worker bytes | Aligned-array worker bytes |
|---|---:|---:|---:|
| `void` | 104 | 256 | 128 |
| Ordinary 64-byte context | 168 | 384 | 256 |
| Context aligned to 256 bytes | 512 | 512 | 512 |

The layouts are recorded in [baseline-layout.log](baseline-layout.log), [rejected-isolated-layout.log](rejected-isolated-layout.log) and [rejected-aligned-layout.log](rejected-aligned-layout.log). Array alignment prevents adjacent workers from sharing a cache unit, but does not isolate every field within a worker for arbitrary context types.

Each process fixes the caller and background worker CPUs, warms both paths, checks every checksum against node count, alternates serial/parallel paths nine times and reports medians. Five outer rounds alternate baseline/candidate process order. The serial reference retains 64-byte code alignment. E-core comparisons use caller 31 and workers 24–30; the P-core comparison uses caller 14 and workers 0,2,4,6,8,10,12. All inputs and CPU placement are fixed within each comparison.

| Case | Revision | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| Isolated heartbeat, 1000-node E-core tree | baseline | 1,520 | 3,234 | 0.470 |
| Isolated heartbeat, 1000-node E-core tree | candidate | 1,530 | 3,462 | 0.442 |
| Isolated heartbeat, 100,000-node E-core tree | baseline | 169,310 | 139,532 | 1.213 |
| Isolated heartbeat, 100,000-node E-core tree | candidate | 169,741 | 150,567 | 1.127 |
| Array alignment, initial 1M-node E-core tree | baseline | 2,151,180 | 926,444 | 2.322 |
| Array alignment, initial 1M-node E-core tree | candidate | 2,123,707 | 891,444 | 2.382 |
| Array alignment, confirmation 1M-node E-core tree | baseline | 2,126,131 | 955,748 | 2.225 |
| Array alignment, confirmation 1M-node E-core tree | candidate | 2,089,591 | 984,866 | 2.122 |
| Array alignment, 1M-node P-core tree | baseline | 2,143,358 | 858,602 | 2.496 |
| Array alignment, 1M-node P-core tree | candidate | 2,165,015 | 853,567 | 2.536 |

Heartbeat isolation made small/medium trees slower. Array alignment's initial E-core gain reversed on confirmation, while the P-core large-tree difference was under 1%. Those results do not justify increased worker metadata. The compact layout is retained. These samples establish the decision for the tested inputs and host; they do not establish a general optimum.

All process medians and inner samples are retained in the corresponding `*-comparison.json` and `*-samples.log` files. The experiments made no changes to publication, job ownership, result/error order or caller fallback. After restoring the committed scheduler, the new diagnostic and both [Debug](debug.log) and [ReleaseSafe](release-safe.log) gates passed 63 library tests plus three integration tests. No scheduler/sync concurrency change remains in this commit.

The overall goal remains active. The previous committed [strict parity evidence](../2026-11-07-join-simplification/strict-parity.log) still applies to the unchanged implementation: `serial_ns=1497`, `parallel_ns=3146`, `speedup=0.476`, below 0.9. These rejected layouts do not resolve the small-tree gate; further work should target recursive execution and publication costs.
