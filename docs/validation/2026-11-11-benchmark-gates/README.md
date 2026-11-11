# Paired primary benchmarks and default small-tree gate

The compute, flat-fold and 2D primary benchmarks now use warm-up, alternating
serial/parallel samples, per-result checksum verification and medians.
Optional lane/caller arguments fix CPU placement. Both 2D paths time fill
plus an identical checksum traversal; the earlier asymmetric timing is gone.
The paired timing helper uses a compiler memory barrier before each sample.

`scripts/check.sh` now runs the fixed-CPU 1000-node parity floor on its default
path. `scripts/perf_gate.py` selects allowed physical cores, reserves the last
for caller, builds identical current harnesses against two core source roots,
alternates revision order and saves every sample. Regression failures must be
confirmed and investigated, rather than ignored because other rows passed.

This calibration compares the **same scheduler** (`04ab4e1`) through both
source roots. There is no scheduler optimization in these samples. Zig 0.16.0,
ReleaseFast, caller CPU 31, workers 24–30, three outer rounds. Main flat runs
use 21 inner pairs; tree/compute/2D use 9; micro uses 9 pairs of 1000 repeats.
All checksums passed and the 1000-node candidate median speedup was 0.986.

| Case | Baseline parallel_ns | Candidate parallel_ns | Ratio |
|---|---:|---:|---:|
| Micro plain | 3112 | 3115 | 1.001 |
| Micro error union | 3037 | 3040 | 1.001 |
| Compute 1M | 14177662 | 14203420 | 1.002 |
| Flat 16M | 3345767 | 3297894 | 0.986 |
| Flat 1M | 77009 | 73669 | 0.957 |
| Grid 1024² | 571419 | 570824 | 0.999 |
| Tree 1K | 1500 | 1520 | 1.013 |
| Tree 1M | 496434 | 507870 | 1.023 |

The heartbeat 100K tree was much noisier (115735 vs 73455 ns) despite unchanged
code. That difference is not an optimization gain. Subsequent scheduler trials
need at least five outer rounds and confirmation of apparent medium-tree
regressions; one favorable run cannot establish an improvement. The default
5% regression allowance is a detection threshold, not permission to knowingly
land a slowdown.

[results.json](results.json) contains every command, CPU set, harness hash,
serial_ns/parallel_ns/speedup and process median. The adjacent logs contain
all inner samples. The baseline checkout was exported to
`/tmp/parz-opt-20261111/baseline`; the runner's temporary binaries are removed
after the process completes. Reproduce with a clean `04ab4e1` source export:

```sh
python3 scripts/perf_gate.py --baseline /path/to/04ab4e1 --cpus 24-31 \
  --rounds 5 --output /tmp/parz-paired-baseline
```
