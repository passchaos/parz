# Dynamic compute grain tuning

The fixed-cost compute comparison now uses dynamic scheduling with 128 target
chunks per lane. The public library defaults remain dynamic with 16 chunks per
worker; this is workload-specific benchmark tuning, not a claim that 128 is a
general default. Dynamic scheduling is retained because it absorbs worker
wake and frequency skew that static spans cannot redistribute.

Each process ran on CPUs 24-31 with eight lanes, verified every result and
reported the best of seven paired serial/parallel repetitions. Five outer
rounds rotated 16, 32, 64 and 128 chunks-per-lane order. The table reports
medians; [`results.json`](results.json) retains every process result and
source hash.

| Target chunks/lane | Planned chunks | serial_ns | parallel_ns | speedup |
|---:|---:|---:|---:|---:|
| 16 | 128 | 109,395,569 | 14,127,912 | 7.74x |
| 32 | 256 | 109,404,227 | 13,982,691 | 7.82x |
| 64 | 512 | 109,400,486 | 13,805,931 | 7.92x |
| 128 | 976 | 109,406,288 | 13,759,221 | 7.95x |

The 128 target is capped at 976 chunks by `count / min_chunk`, so larger
values cannot add more work units for this input. Relative to 16, the selected
grain reduces parallel median time by about 2.6%. Its 7.95x measured speedup
is within roughly 0.6% of the ideal eight-lane bound.

The 976 plain `u64` results exceed the existing 4 KiB dispatch stack fallback
and use its caller-supplied allocator. An isolated 4 KiB versus 8 KiB source
comparison gave parallel medians of 13,730,397 ns and 13,767,842 ns
respectively. The larger fixed stack did not improve performance and would
charge every flat call another 4 KiB, so it was rejected; the production stack
budget and allocation-boundary tests remain unchanged.

The final three-round cross-implementation medians were:

| Workload | parz | Spice | Rayon | OpenMP |
|---|---:|---:|---:|---:|
| tree 1K | 0.002 ms / 0.99x | 0.003 ms / 0.72x | 0.013 ms / 0.14x | 0.293 ms / 0.00x |
| tree 100K | 0.103 ms / 2.14x | 0.249 ms / 0.89x | 0.172 ms / 1.11x | 0.304 ms / 0.51x |
| tree 10M | 9.503 ms / 2.62x | 10.709 ms / 2.32x | 12.875 ms / 1.84x | 10.428 ms / 2.10x |
| flat 16M | 2.289 ms / 6.33x | 4.014 ms / 3.64x | 2.550 ms / 5.23x | 3.099 ms / 4.84x |
| compute 1M | 13.764 ms / 7.95x | 14.812 ms / 7.32x | 13.779 ms / 7.91x | 13.591 ms / 7.89x |

Parz matches Rayon on absolute compute time within measurement resolution and
is about 1.3% behind OpenMP, while reporting the highest compute scaling ratio
of the four implementations. Tree and flat leadership is unchanged. This
closes the previously measured parz-versus-Rayon compute gap on this CPU set;
it does not prove global optimality across architectures or workload costs.

Reproduce the comparison with:

```sh
SPICE_DIR=/tmp/spice python3 bench/compare/run_compare.py \
  --rounds 3 --lanes 8 --cpus 24-31 --gate
```
