# Cumulative optimization validation — in progress

The optimization goal is **not complete**. Current source passes Debug and
ReleaseSafe (127 tests each), TSan (123 library tests), serial fallback,
WASM and five native cross-target compilations. Sync/2D/irregular/NUMA smoke
checks also pass. The fixed-CPU cumulative cold-scan comparison still signals
a regression. Final E/P-core, caller, sync performance gates and commit/push
remain required. Do not treat
this intermediate record as a passing final performance report.

The original baseline is `04ab4e1`; the flat checkpoint is `85bdeb6`; the
pre-module checkpoint is `609509c`. All version comparisons build the same
current harness against both source roots and verify every checksum. Raw
samples, complete commands, source/harness hashes and machine-code hashes
where available are retained beside each `results.json`.

## Current implementation

`parallel.zig` is a compatible export facade. Index/grid callbacks, range
callbacks, folds, planning, dispatch, cancellation and serial fallback live in
semantic `parallel/` modules. Worker, Task and Future remain together in
`core.zig`; pool lifecycle, options, context lifetime and heartbeat live in
`scheduler/`. [The reproducible source audit](source-equivalence.json) checks
49 unchanged bodies, 55 retained named tests and four added contract tests.

Default heartbeat preserves the original periodic metadata path. Complete
parking and `skip_idle_heartbeat_metadata` are explicit choices, both false by
default. Heartbeat retains a static `Heartbeat(Pool).run(*Pool)` thread entry.
Normal execution-state returns avoid extra notifications. Actual state
exhaustion sets a mutex-protected pressure bit; each capacity return then
notifies while ready work remains. Emptying the ready set clears pressure.
The tests cover repeated 1–4 worker runs and two simultaneously blocked peers.
[The negative control](state-return-negative-control.log) restores the
incomplete empty-to-nonempty wake strategy and fails with
`ReadyPeerWasStranded`, while draining outstanding callbacks safely.

## Retained trials and unresolved performance signal

All measurements use Zig 0.16 ReleaseFast on an Intel i9-13900K, alternating
serial/parallel paths and revision order. E placement is caller 31, workers
24–30; P placement is caller 14, workers 0,2,4,6,8,10,12. The host is not
isolated. Cold preparation sleeps 100 ms outside the clock interval.

The initial fragmented core layout and direct generic heartbeat entry were
withdrawn after cold-scan/medium-tree signals. [Typed heartbeat tree trials](typed-heartbeat-tree/results.json)
passed the medium and large tree rows. A separate default dispatch frame
trial did not improve cold scan and was withdrawn. Exact rejected source
snapshots/patches are in [rejected](rejected/); the accepted typed entry change
is recorded in [typed-heartbeat.patch](typed-heartbeat.patch).

Unfixed heartbeat placement produced a +10.77% cold-scan signal even for
[identical source and identical `.text` bytes](cold-same-source/results.json).
Benchmark-only heartbeat placement on a separate CPU 23 reduced that
[seven-round calibration](cold-fixed-heartbeat-calibration/results.json) to
+1.46%. The library does not implicitly pin heartbeat.

With heartbeat fixed, the cumulative cold scan still signalled
[+8.88%](final-cold-fixed/results.json),
[+11.20% confirmation](final-cold-fixed-confirmation/results.json), and
[+15.49% in 21 shorter process batches](cold-short-batches/results.json).
These signals must be corrected or explained by stronger controlled evidence
before completion; passing a subset of rows does not close this issue.

Stage isolation rows passed: [flat versus original](cold-flat-checkpoint/results.json),
[scheduler checkpoint versus flat](cold-scheduler-checkpoint/results.json),
and [final versus scheduler checkpoint](cold-final-vs-checkpoint/results.json).
The stage medians do not replace a cumulative comparison.

Earlier initial-layout full comparisons are in `module-e`, `cumulative-e`,
`cumulative-p`, their confirmation directories and `final-e`. They describe
those trial sources, not the final source now on disk.

## Reproduction

```sh
python3 docs/validation/2026-11-11-final/compare_bodies.py --baseline /path/to/609509c
python3 scripts/perf_gate.py --first-call-only --idle-ms 100 --heartbeat-cpu 23 \
  --baseline /path/to/04ab4e1 --cpus 24-31 --rounds 7 --output /tmp/parz-cold
python3 scripts/perf_gate.py --first-call-only --only first-scan --cold-samples 3 \
  --idle-ms 100 --heartbeat-cpu 23 --baseline /path/to/04ab4e1 \
  --cpus 24-31 --rounds 21 --output /tmp/parz-cold-short
```

Check logs are in [checks](checks/). `checks/results.json` records passing
Windows x86_64/AArch64, macOS AArch64 and Linux musl x86_64/AArch64 compile
checks, plus all correctness and smoke commands. TSan is recorded separately
in `tsan.log`.
