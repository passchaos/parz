# Pacing depth and serial tick fast path

This report covers the 2026-11-18 follow-up optimization pass:

- gate heartbeat pacing on the owner's queued local depth, so recursive trees
  that never queue four jobs stay at serial cost;
- let a lane start its share batch on the next `Task.call` instead of waiting
  for the heartbeat wake, while the heartbeat still paces steady state;
- disable pacing entirely for pools with no background lanes, restoring the
  one-load tick fast path for single-threaded, WASM and thread-spawn-failure
  fallbacks.

The baseline is commit `93f52fa`. Both checkouts are built from the current
benchmark sources with `-OReleaseFast`, every row is checksum-verified, and
serial/parallel paths alternate.

## Environment

- Zig 0.16.0, `-OReleaseFast`.
- Intel i9-13900K, host not isolated.
- E placement: caller 31, workers 24-30. P placement: caller 14, workers
  0,2,4,6,8,10,12.
- Five alternating outer rounds for the full gate; seven to nine for focused
  confirmations.

## Results

### Tree parity scan

`tree_sum` with the benchmark's documented 2047-node serial cutoff, E cores,
seven alternating rounds. The baseline parallelizes only after the first
heartbeat; a three-level tree (10k nodes) pays the worker wake-up without
enough work to recover it. The candidate gates pacing on the local depth, so
the 10k tree stays on its local list.

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| tree-1k | 1505 | 1495 | 0.993 |
| tree-10k | 20000 | 15546 | 0.777 |
| tree-100k | 60950 | 57102 | 0.937 |
| tree-1m | 441563 | 399058 | 0.904 |

### Zero-worker tick

A pool with no background lanes previously kept pacing enabled, so every
`Task.call` took the out-of-line tick slow path and rechecked demand.
`prof_small` full-recursion tree, one lane, 2000 repetitions per sample:

| Rows | Heartbeat off | Heartbeat on | Ratio |
|---|---:|---:|---:|
| 10k nodes, before | 28183 | 54105 | 1.92 |
| 10k nodes, after | 28581 | 28246 | 0.99 |

### Full E-placement gate

Five alternating rounds, all default rows. The candidate is the final source
with the depth gate, next-tick self-share and zero-lane pacing disable. Raw
data: `perf_gate-e.json`.

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| tree-1k | 1476 | 1486 | 1.007 |
| tree-10k | 19517 | 15604 | 0.800 |
| tree-100k | 61384 | 52673 | 0.858 |
| tree-1m | 460705 | 406940 | 0.883 |
| micro-plain | 2779 | 2797 | 1.006 |
| micro-error-union | 3031 | 3030 | 1.000 |
| flat-1m | 69926 | 70003 | 1.001 |
| flat-16m | 3167137 | 3173218 | 1.002 |
| scan-1m | 69815 | 69293 | 0.993 |
| compute-1m | 14153237 | 14158096 | 1.000 |
| heavy-8192 | 124670 | 125291 | 1.005 |
| grid | 573267 | 573393 | 1.000 |
| scratch-1m | 69885 | 73197 | 1.047 |
| first-scan | 22819 | 21059 | 0.923 |
| first-heavy | 171721 | 172728 | 1.006 |

`scratch-1m` is the only row above 3%; it exercises explicit dispatch scratch
and does not touch the heartbeat path. A focused confirmation is included in
the raw data set.

### Full P-placement gate

Five alternating rounds on physical P cores. Raw data: `perf_gate-p.json`.
The P host is shared and noisier than the E-core placement; rows flagged by
the five-round run were re-measured with nine rounds.

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| tree-1k | 1478 | 1469 | 0.994 |
| tree-10k | 19292 | 20945 | 1.086 |
| tree-100k | 67696 | 59616 | 0.881 |
| tree-1m | 428419 | 356919 | 0.833 |
| micro-plain | 2552 | 2398 | 0.940 |
| micro-error-union | 2836 | 2858 | 1.008 |
| flat-1m | 46769 | 45702 | 0.977 |
| flat-16m | 1577271 | 1574353 | 0.998 |
| scan-1m | 45159 | 46348 | 1.026 |
| compute-1m | 8730529 | 9105664 | 1.043 |
| scratch-1m | 50012 | 52961 | 1.059 |

Focused nine-round confirmation for the two flagged rows:

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| tree-10k | 19031 | 17015 | 0.894 |
| scratch-1m | 48439 | 49299 | 1.018 |

The five-round P flags did not reproduce: the focused tree-10k run shows the
candidate faster, and scratch-1m returns inside the 5% allowance.

### Noise floor

`perf_gate --negative-control` builds both revisions from the baseline source
and compares them, so every ratio is host/layout noise. Five rounds, E cores:

| Row | Ratio |
|---|---:|
| tree-1k | 1.008 |
| tree-10k | 0.983 |
| tree-100k | 0.987 |
| tree-1m | 1.018 |
| micro-plain | 1.009 |

The candidate's tree ratios (0.800, 0.858, 0.883) are well outside this
±2% floor.

### Irregular trees

`irregular` with 200k nodes, 8 lanes, five inner rounds, seven process rounds:

| Profile | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| mixed | 10,361,561 | 10,840,072 | 1.046 |
| skewed | 13,189,755 | 13,252,292 | 1.005 |

### Cold first call

`perf_gate --first-call-only`, seven rounds, 1 ms idle:

| Row | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| first-scan | 18386 | 14564 | 0.792 |
| first-heavy | 138764 | 127548 | 0.919 |

## Evaluated and retained

- **Helping while waiting.** Implementing Spice's `waitForJob` helper loop
  executed only one or two shared jobs per tree round because shared lists are
  usually empty when a join waits; the gain was inside run-to-run noise.
- **Unconditional self-share.** Starting a share batch on every pacing tick
  is retained: it improves the 100k and 1M trees and costs 4.6% / 0.5% on the
  mixed and skewed irregular-tree profiles, inside the 5% allowance.
- **Idle-lane-gated self-share.** Requiring `idle_workers >= share_batch`
  before the next-tick share did not improve the large-tree rows consistently
  and added another load to the pacing path, so the simpler unconditional
  next-tick share was retained.
- **Per-lane share epoch.** Throttling self-shares to one per heartbeat period
  required a new per-worker field. Adding the field changed the hot worker
  layout and cost 6-8% on the micro fork/join benchmark, so the throttle was
  dropped.
- **Larger share batches.** A warm-burst harness measured `share_batch`
  2/4/8/16 on the final code. tree-100k prefers 4 (52.3us) over 8/16
  (54.9/55.3us), while tree-1m prefers 2 (401.6us) over 4 (420.9us); no
  single value wins both rows, so the default 4 is retained. In a warm burst
  the heartbeat's periodic flags still let a small tree share, which is cheap
  because the lanes are already awake; the depth gate only suppresses
  demand-driven wake-ups from an idle pool.

## Cross-library comparison

`scripts/check.sh --compare` runs the comparison gate against spice, Rayon and
OpenMP on the same host. Every implementation alternates serial and parallel
runs and verifies its checksum; medians over two rounds:

| Workload | parz | spice | Rayon | OpenMP |
|---|---:|---:|---:|---:|
| tree-1000 | 0.002ms / 1.00x | 0.003ms / 0.67x | 0.030ms / 0.08x | 0.460ms / 0.00x |
| tree-100000 | 0.058ms / 3.86x | 0.229ms / 0.69x | 0.293ms / 0.64x | 0.477ms / 0.26x |
| tree-10000000 | 3.434ms / 4.62x | 7.340ms / 2.24x | 4.962ms / 3.19x | 3.549ms / 3.66x |
| flat-16000000 | 1.607ms / 4.24x | 4.419ms / 1.53x | 1.883ms / 2.84x | 1.964ms / 3.58x |
| compute-1000000 | 3.449ms / 17.92x | 9.120ms / 6.78x | 3.641ms / 16.90x | 6.636ms / 9.68x |

Raw output: `cross-library.log`.

## Correctness

- `zig build test` (Debug) and `zig build test -Doptimize=ReleaseSafe`: 132
  tests each.
- `zig test src/root.zig -fsanitize-thread -OReleaseSafe`: 132 tests.
- `zig test src/root.zig -fsingle-threaded -OReleaseSafe`: 99 passed, 33
  skipped (threaded cases), 0 failed.
- WASM (`wasm32-wasi`, atomics) and Windows/macOS/musl cross-target compiles.
- `scripts/check.sh --compare`: parity gate, sync/2D/irregular/NUMA smoke
  checks and the cross-library gate all pass.
- New unit test: `pacing requires enough excess local work` verifies the depth
  threshold and that the local list is fully drained after joins.
- `checks.log` in this directory records the final run.

## Reproduction

```sh
python3 scripts/perf_gate.py --baseline /path/to/93f52fa --cpus 24-31 \
  --rounds 5 --output /tmp/parz-e
python3 scripts/perf_gate.py --baseline /path/to/93f52fa \
  --cpus 0,2,4,6,8,10,12,14 --rounds 5 --output /tmp/parz-p
python3 scripts/perf_gate.py --first-call-only --only first-scan,first-heavy \
  --baseline /path/to/93f52fa --cpus 24-31 --rounds 7 --idle-ms 1 \
  --output /tmp/parz-cold
python3 scripts/perf_gate.py --baseline /path/to/93f52fa --negative-control \
  --cpus 24-31 --rounds 5 --only tree-1k,tree-10k,tree-100k,tree-1m \
  --output /tmp/parz-negative
SPICE_DIR=/tmp/spice scripts/check.sh --compare
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- \
  10000 heartbeat measure 31
```
