The production scheduler remains identical to committed `86504ed`. Three cold-path experiments were rejected. Branch hints emitted unchanged executable code, isolating only the wait helper did not reduce the recursive frame, and complete outlining improved one CPU set while regressing another.

The first trial used `.cold` branch hints for heartbeat sharing, shared reclaim and executing joins. It passed the existing Debug suite of 64 library tests and three integration tests. Its tree executable `.text` SHA-256 is identical to baseline: `56b5539d704c572f54857dc2855a2f7f0d3b95595b2467808cbf41728f614aee`. Timing differences in that trial therefore do not establish an implementation gain.

The second trial made only `Future.joinExecuting` non-inlined. The local stack reservation remained 104 bytes, and error-union small-tree time did not improve. The third also prevented inlining of `Pool.reclaimShared` and `Worker.maybeShare`, reducing the local stack reservation to 88 bytes. All still preserve the same job states, mutex boundaries and caller fallback. Exact experimental patches are retained in [branch hints](rejected-hinted.patch), [wait helper](rejected-wait-helper.patch) and [full outlining](rejected-outlined.patch), with disassemblies beside them.

All timing comparisons use fixed input and fixed caller/background placement. E-core tests use caller 31 and workers 24–30; P-core tests use caller 14 and workers 0,2,4,6,8,10,12. Every process warms both paths, verifies each checksum independently against node count, alternates serial/parallel measurements nine times and reports medians. Five outer rounds alternate baseline/candidate process order. The serial reference retains 64-byte code alignment. All process medians and inner samples are retained in the corresponding comparison JSON and sample logs.

| Comparison | Revision | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| Initial E-core, local plain 1000-node callback | baseline | 1,489 | 3,307 | 0.450 |
| Initial E-core, local plain 1000-node callback | outlined | 1,486 | 2,910 | 0.511 |
| Confirmation E-core, local plain 1000-node callback | baseline | 1,502 | 3,286 | 0.457 |
| Confirmation E-core, local plain 1000-node callback | outlined | 1,500 | 2,971 | 0.505 |
| Initial E-core, 1M-node heartbeat tree | baseline | 1,831,131 | 788,212 | 2.323 |
| Initial E-core, 1M-node heartbeat tree | outlined | 1,848,710 | 729,566 | 2.534 |
| Confirmation E-core, 1M-node heartbeat tree | baseline | 1,929,516 | 769,931 | 2.506 |
| Confirmation E-core, 1M-node heartbeat tree | outlined | 1,955,629 | 757,693 | 2.581 |
| P-core, 100,000-node heartbeat tree | baseline | 155,158 | 168,809 | 0.919 |
| P-core, 100,000-node heartbeat tree | outlined | 155,131 | 178,294 | 0.870 |
| P-core, 1M-node heartbeat tree | baseline | 1,737,747 | 855,824 | 2.030 |
| P-core, 1M-node heartbeat tree | outlined | 1,598,446 | 993,506 | 1.609 |

The E-core plain local improvement reproduced, but error-union small trees stayed essentially unchanged. The P-core million-node parallel time worsened by about 16%, with medium trees also slower. These results do not support applying complete outlining to the general library. A smaller frame does not by itself establish better execution time. Automatic inlining remains in use.

Source/binary hashes, stack reservations, CPU placement and compiler version are recorded in [environment.json](environment.json). The baseline was exported without implementation edits, and all production changes were restored after the comparisons. No scheduler/sync concurrency change remains in this commit.

The overall goal remains active. The existing [strict small-tree gate](../2026-11-07-future-init/strict-parity.log) still applies to the restored implementation: `serial_ns=1503`, `parallel_ns=3128`, `speedup=0.480`, below the 0.9 floor. The current evidence rules out these code-layout changes as a general solution to that gate.
