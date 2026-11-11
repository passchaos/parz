# Scheduler optimization trials in progress

Verified baseline for this phase: `85bdeb6`, exported at
`/tmp/parz-opt-20261111/flat-checkpoint`. The scheduler changes in the current
worktree are not yet committed or fully validated.

Current implementation:

- A bounded ready-owner list plus priority bitmap replaces worker-array scans.
  Default bitmap selection preserves registered-index priority. Optional
  `fair_shared_owners` uses round robin; an initial four-caller run reduced
  p95 from 493303 to 333676 ns but increased group time 2–4%, so round robin
  is opt-in and default priority needs new measurements.
- Default heartbeat remains periodic. An atomic caller-presence cache skips
  the pool mutex and idle worker flag writes when all background workers wait.
  Stop is atomic so this idle path can still terminate correctly.
- Complete parking is explicit (`park_idle_heartbeat=false` by default).
  Flat admission uses `claimFlatCaller`/`beginFlat`; recursive `Worker.begin`
  requests heartbeat demand. Parking tests cover held callers, wake and stop.
  Automatic default parking failed cold-latency gates and is not accepted.

Latest Debug gate: **114 tests passed** (111 library + 3 integration).
ReleaseSafe, TSan, serial, cross-target checks and complete default-policy
performance gates remain required for this worktree before committing.

Preserved datasets and patches:

| Path under `/tmp/parz-opt-20261111` | Evidence |
|---|---|
| `heartbeat-idle/results.json` | Immediate parking removed ~14K/s idle wakes; held recursive caller remained paced |
| `heartbeat-flat-controls/results.json` | Automatic park: 64K +8%, first scan +15%; rejected |
| `heartbeat-pinned-controls/results.json` | Heartbeat pinning did not fix regressions; rejected |
| `heartbeat-grace-controls/results.json` | 10 ms grace passed burst/2 ms idle rows |
| `heartbeat-long-idle-controls/results.json` | Grace still failed after 100 ms idle: first scan +56%, heavy +24% |
| `heartbeat-demand-long-idle/results.json` | Demand-based flat entry still failed cold gates; no automatic default |
| `ready-demand-long-idle-confirmed/results.json` | Ready-owner lookup alone did not make automatic parking acceptable |
| `ready-callers/results.json` | Initial round-robin throughput and latency observations |
| `ready-callers-confirmation/results.json` | Seven-round confirmation; four-caller group +2.35% |
| `heartbeat-first-park.patch`, `heartbeat-pinned-park.patch`, `heartbeat-grace-park.patch`, `heartbeat-demand-candidate.patch`, `ready-demand-auto-park.patch` | Exact rejected/intermediate source snapshots |

The current default-preserving priority bitmap was added after those datasets;
do not cite the older round-robin/automatic-parking results as proof for it.
Next: measure default bitmap and periodic idle shortcuts, profile precise CPU
runtime via `/proc/.../schedstat`, then run all correctness and performance
gates. The remaining sync, NUMA/lazy-arena and source-module work stays in the
[full backlog](../../OPTIMIZATION_BACKLOG.md).
