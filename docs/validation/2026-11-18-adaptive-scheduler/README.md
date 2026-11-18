# Adaptive scheduler and cold-path optimization

This report covers the 2026-11-18 optimization pass:

- work-aware lane planning for calls that provide `estimated_item_ns`;
- lock-free caller-slot claim/release and a dedicated execute-state free-list
  lock so joins do not contend on the pool mutex;
- adaptive heartbeat as the default, with an out-of-line pacing slow path and
  a tri-state worker flag that preserves the original one-load fast path when
  pacing is disabled;
- optional performance-core and SMT placement policies;
- a configurable heartbeat share batch;
- cold wake-latency and phase-decomposition benchmarks plus gate statistics.

The baseline for the adaptive and topology rows is `2a11f8b`; the lane-planning
baseline is `59456fa`. Both checkouts are built with the current benchmark
sources, every result is checksum-verified, and serial/parallel paths alternate.

## Environment

- Zig 0.16.0, `-OReleaseFast`.
- Intel i9-13900K, host not isolated.
- E placement: caller 31, workers 24-30. P placement: caller 14, workers
  0,2,4,6,8,10,12. Heartbeat is fixed to CPU 23 only for cold first-call rows.
- Five alternating outer rounds unless a row needed a focused confirmation.

## Results

### Work-aware lane planning

`cheap-65536` with `estimated_item_ns=1` caps lanes by useful work
(`min_parallel_lane_ns`, default 20us) instead of waking all eight lanes.

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| cheap-65536 | 12974 | 10701 | 0.825 |

The full flat gate showed no failures: `scan-1m` 0.985, `first-scan` 1.006,
`first-heavy` 1.023, and the remaining rows stayed inside the 5% allowance.
Raw data: `lane-planning-flat.json`.

### Pool-owned dispatch storage

At `chunks_per_worker=1024` (scan 1M, 4096 chunks), the baseline performs one
32768-byte allocation per call; the candidate performs zero after pool
initialization. Timing was noisy on the shared host and is not claimed as a
speedup. Raw data: `pool-scratch-high-chunk.log`.

### Adaptive heartbeat (E placement)

The default heartbeat now waits on a timeout event. A lane with local work
requests pacing from an out-of-line tick slow path; idle waits back off to
`max_idle_heartbeat_interval_ns` (default 1ms). The worker flag is a tri-state
byte (`idle`/`pacing`/`share`), so pools without adaptive pacing keep the
original single-load tick fast path.

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| tree-100k | 100597 | 63511 | 0.631 |
| tree-1m | 537169 | 467823 | 0.871 |
| tree-1k | 1504 | 1496 | 0.995 |
| micro-plain | 3111 | 3005 | 0.966 |
| micro-error-union | 2968 | 2943 | 0.992 |
| flat-1m | 76896 | 74183 | 0.965 |
| flat-16m | 3182487 | 3327687 | 1.046 |
| first-scan | 20806 | 21910 | 1.053 |
| first-heavy | 154184 | 143418 | 0.930 |

The full E-placement run flagged `first-scan` at +5.31%. A focused seven-round
confirmation measured 43367 -> 42561 ns (ratio 0.981), so the flag did not
reproduce; both records are retained (`e-core-full.json`,
`e-core-first-scan-confirmation.json`).

### Adaptive heartbeat (P placement)

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| tree-100k | 124537 | 72135 | 0.579 |
| tree-1m | 460405 | 433060 | 0.941 |
| tree-1k | 1843 | 1796 | 0.974 |
| micro-plain | 3274 | 3243 | 0.991 |
| micro-error-union | 3694 | 3707 | 1.004 |
| first-scan | 15927 | 15353 | 0.964 |
| first-heavy | 86646 | 89720 | 1.035 |

No row exceeded the 5% allowance. Raw data: `p-core-full.json`.

### Idle pacing

`scripts/idle_profile.py --adaptive` against the same source:

| Policy | Voluntary wakeups/s | Scheduler CPU per 2s |
|---|---:|---:|
| periodic default | ~13973 | ~52-58 ms |
| adaptive default | ~949 | ~7-8 ms |

Raw data: `idle-periodic.json`, `idle-adaptive.json`.

### Sync confirmations

The scheduler changes do not touch sync, but the sync gate was re-run. The
first five-round pass contained three noisy rows; focused confirmations were
inside the 5% allowance:

- treiber-batch-scalar parallel ratio 0.988;
- mpsc-2-scalar parallel ratio 1.018;
- sharded-sparse-view lookup parallel ratio 0.998.

Raw data: `sync-treiber-confirmation.json`, `sync-mpsc-confirmation.json`,
`sync-sharded-confirmation.json`.

## Evaluated and retained

- **Future-embedded completion event.** Retained the bounded execute-state
  pool. `cold-phases` shows dispatch is wake-dominated; state acquisition
  happens under the already-held pool mutex and release is one uncontended
  CAS. Removing the pool would delete the documented `max_execute_states`
  fallback contract, and inline dispatch futures would need a Job kind/tag or
  an extra Future field. The measured saving is below run-to-run noise.
- **Per-owner locking and a shared heartbeat mask.** Retained the single pool
  mutex and per-worker state byte. Caller claim/release measured ~0.1-0.6 us
  and cold dispatch is dominated by worker wake; the adaptive heartbeat cut
  idle ticks by ~15x, so per-worker flag writes are not a measured bottleneck.
  A shared mask would add consume contention without evidence of a gain.
- **Static scheduling and recursive grain.** Dynamic remains the default for
  mixed-cost and heterogeneous CPUs. Static scheduling and the benchmark's
  recursive serial depth are caller/benchmark policy; no new fixed-CPU
  evidence justified changing the library default.

## Correctness

- `zig build test` (Debug) and `zig build test -Doptimize=ReleaseSafe`: 129
  tests each.
- `zig test src/root.zig -fsanitize-thread -OReleaseSafe`: 129 tests.
- `scripts/check.sh`: Debug/ReleaseSafe, small-tree parity, single-threaded,
  TSan, WASM compile, Windows/macOS/musl cross-target compiles, sync/2D/
  irregular/NUMA smoke checks.
- `checks.log` in this directory records the final run.

## Reproduction

```sh
python3 scripts/perf_gate.py --baseline /path/to/2a11f8b \
  --cpus 24-31 --rounds 5 --output /tmp/parz-e
python3 scripts/perf_gate.py --baseline /path/to/2a11f8b \
  --cpus 0,2,4,6,8,10,12,14 --rounds 5 --output /tmp/parz-p
python3 scripts/perf_gate.py --first-call-only --only first-scan \
  --baseline /path/to/2a11f8b --cpus 24-31 --rounds 7 \
  --idle-ms 100 --output /tmp/parz-cold
python3 scripts/idle_profile.py --baseline /path/to/2a11f8b \
  --candidate . --cpus 24-31 --rounds 3 --adaptive \
  --output /tmp/parz-idle-adaptive
python3 scripts/sync_gate.py --baseline /path/to/2a11f8b \
  --rounds 7 --output /tmp/parz-sync
```

## Measurement tools added

- `zig build bench-wake-latency -- <lanes> <caller_cpu> <idle_ms> <rounds>`:
  kickstart-to-handler-entry delay for each background lane.
- `zig build bench-cold-phases -- <kind> <count> <lanes> <caller_cpu>
  <idle_ms> <rounds>`: splits a cold flat fold into caller claim, dispatch
  and release.
- `perf_gate.py --statistic min|median` and `--negative-control`.
- `idle_profile.py --adaptive`.
