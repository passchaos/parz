# Cross-implementation recursive grain comparison

The formal `compare-parz tree` workload now uses the same remaining-depth
grain rule as `bench-tree-sum`: subtrees containing at most 2047 nodes run
through the direct serial kernel, while larger subtrees retain heartbeat
fork/join. The pointer-based error-union and flattened uncut variants remain
available as diagnostics. The library scheduler and public API are unchanged.

Baseline is commit `376eaef`; its comparison tree still created a `Future` at
almost every internal node. Baseline and candidate processes were alternated
over five outer rounds on CPUs 24-31 with eight lanes. Each process checks all
results and reports the best of nine paired serial/parallel repetitions. The
table uses medians of those five process results and median reported speedup.
[`results.json`](results.json) retains every process result and source hashes.

| Input | Revision | serial_ns | parallel_ns | speedup | Parallel change |
|---:|---|---:|---:|---:|---:|
| 1,000 | per-node Future | 1,412 | 2,935 | 0.49 | — |
| 1,000 | 2047-node leaves | 1,414 | 1,446 | 0.98 | -50.7% |
| 100,000 | per-node Future | 165,648 | 115,037 | 1.43 | — |
| 100,000 | 2047-node leaves | 156,334 | 78,689 | 2.04 | -31.6% |
| 10,000,000 | per-node Future | 22,573,944 | 11,198,985 | 2.01 | — |
| 10,000,000 | 2047-node leaves | 22,969,393 | 9,533,978 | 2.38 | -14.9% |

The comparison runner now reports outer medians instead of selecting the
single fastest outer process. Its conservative gate also scales broad and
compute floors below the historical 32-lane ceiling; an explicit eight-lane
run no longer demands an impossible 10x compute speedup. Invalid zero rounds
or lanes are rejected. The infallible compute workload now honors the same
CLI `min_chunk` and `chunks_per_worker` controls as the fallible workload.

The final three-round interleaved comparison used the same CPU set, eight
lanes, Zig 0.16.0, Spice `39186ac`, the installed Rayon release build and GCC
OpenMP. Values are outer medians; every underlying process validated its
checksum.

| Workload | parz | Spice | Rayon | OpenMP |
|---|---:|---:|---:|---:|
| tree 1K | 0.001 ms / 0.98x | 0.003 ms / 0.73x | 0.014 ms / 0.13x | 0.288 ms / 0.01x |
| tree 100K | 0.086 ms / 1.82x | 0.249 ms / 0.88x | 0.179 ms / 1.09x | 0.307 ms / 0.52x |
| tree 10M | 9.449 ms / 2.38x | 11.419 ms / 2.28x | 13.072 ms / 1.85x | 10.875 ms / 2.08x |
| flat 16M | 3.335 ms / 4.50x | 4.224 ms / 3.45x | 2.778 ms / 5.04x | 4.848 ms / 2.81x |
| compute 1M | 14.660 ms / 7.47x | 15.297 ms / 7.09x | 13.809 ms / 7.90x | 13.941 ms / 7.70x |

Parz is the fastest measured tree implementation at every tested size and
passes the eight-lane regression gate. Rayon remains faster on this flat and
compute input, so no global optimality claim is made.

Two follow-up tuning experiments were rejected. Reducing uniform fold chunks
to one per lane made cold worker imbalance much worse; the existing dynamic
default remained the most robust setting. Pinning the seven background workers
improved flat median time by about 4.2%, but regressed the 10M tree by about
0.6% and left compute unchanged. Worker pinning therefore remains explicit
rather than becoming a comparison default.

Reproduce the final gate with:

```sh
SPICE_DIR=/tmp/spice python3 bench/compare/run_compare.py \
  --rounds 3 --lanes 8 --cpus 24-31 --gate
```
