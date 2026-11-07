Reusing the calling Task instead of constructing a Task for each callback was
rejected. The experiment saved and restored the worker pointer around the
callback to preserve worker rebinding isolation. The error-union recursive
frame grew from 104 to 120 bytes, and the initial error-union and large-tree
measurements regressed. The production scheduler was restored to the
`ea34b6e` baseline before MPSC work began.

The baseline compiler already passes the worker directly through the optimized
recursive adapter; the source-level temporary Task does not imply an extra
Task allocation in this instantiation. Reusing an address adds indirection and
pointer restoration. The [baseline](baseline-recursion.s) and
[experimental](reuse-recursion.s) disassemblies show the frame reservations.
The [patch](rejected-reuse.patch) retains the rejected source change.

The exploratory comparison uses identical tree and microbenchmark sources
against an exported baseline, caller CPU 31 and workers 24–30. Every process
warms both paths, checks each checksum against node count, alternates
serial/parallel runs nine times and reports medians. Three outer rounds
alternate baseline/candidate process order. The table gives medians of those
process medians; [samples](quick-samples.log), [results](quick-comparison.json)
and [environment](environment.json) retain the underlying evidence.

| Workload | Revision | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| Local plain, 1000 nodes | baseline | 2,008 | 3,356 | 0.598 |
| Local plain, 1000 nodes | reuse | 1,830 | 3,007 | 0.596 |
| Local error-union, 1000 nodes | baseline | 1,506 | 3,285 | 0.455 |
| Local error-union, 1000 nodes | reuse | 1,818 | 3,463 | 0.518 |
| Heartbeat, 1000 nodes | baseline | 1,519 | 3,217 | 0.468 |
| Heartbeat, 1000 nodes | reuse | 1,479 | 3,320 | 0.443 |
| Heartbeat, 1M nodes | baseline | 1,858,416 | 765,604 | 2.512 |
| Heartbeat, 1M nodes | reuse | 1,721,842 | 799,457 | 2.154 |

Speedup is the median reported process ratio, rather than a ratio recomputed
from independently aggregated columns. Serial timing varies on this loaded
host even with 64-byte function alignment. The plain callback sample alone
does not establish a portable gain. The larger frame and slower error-union
parallel times provide no basis to apply the experiment. This is an initial
performance rejection; no claim of functional validation of the rejected
Task semantics is made. The overall goal and strict small-tree gate remain
open.
