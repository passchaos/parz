# Sync optimization and lazy NUMA arena evidence

Retained changes are an optional uncounted Treiber stack and a compile-time
producer-set consumer view. Default counted-stack retry and default full-shard
polling remain compatible. Unconditional and batch-only MPSC pause trials were
withdrawn after inconsistent gains and regressions. Blocking waiter tracking
was also withdrawn because repeated tiny/batch rows showed small slowdowns;
the added cancellation and no-stranded-waiter tests remain.

All performance rows use the same current harness against baseline `0c8baaf`,
Zig 0.16 ReleaseFast, fixed inputs and CPUs 24–31, pre-warmed paths, alternating
serial/parallel and revision order, and every checksum verified. Producer and
consumer CPU assignments appear in every raw log. Seven-round confirmations
and all inner samples are in [treiber](treiber/results.json),
[blocking trial](blocking/results.json), and [specialized views](sharded/results.json).
Rejected proposals/results are in [rejected](rejected/); the blocking patch is
retained separately with the final evidence.

| Comparison | Baseline ns | Candidate ns | Result |
|---|---:|---:|---|
| Uncounted scalar, single lane | 2075871 | 1273613 | No count RMW |
| Uncounted scalar, concurrent | 9564706 | 5351104 | 44% lower time |
| Uncounted batch, concurrent | 327866 | 309087 | 6% lower time |
| Known 2-of-4 producer view | 370088 | 316756 | Specialized lookup faster |
| Known 2-of-128 producer view | 7108037 | 306774 | Empty-shard scans eliminated |

The view comparison is explicitly a single-consumer lookup benchmark, not a
multi-thread scaling claim. Concurrent tests independently verify per-producer
FIFO. Runtime index slices were slower for four shards, so final views use
compile-time indices and retain zero producer-side synchronization overhead.
Default dense-shard rows changed within about 2% in these samples; no dense
throughput gain is claimed.

[NUMA arena log](numa-arena.log) verifies checksum 8386560 for 4096 objects:
per-object VMA allocation 22540605 ns, retained arena 67276 ns, zero new VMA
allocations on reuse. Linux policy applied successfully in this sample.
This synthetic one-CPU allocation comparison does not establish cross-node
performance. Integration verifies empty arenas after Pool.init/start, first
allocation on executing lanes and retained reuse on an explicitly owned lane.

The [checks](checks/) were run before restoring the original blocking hot path;
the final restored-source checks are recorded alongside them. Debug currently
passes 121 tests (117 library + 4 integration). Tests cover mixed scalar/batch
LIFO, node reuse, concurrent uncounted publication/removal, empty/invalid view
sets, unselected shards, per-producer FIFO, cancelled condition registration
cleanup and multiple blocked readers/writers.

```sh
python3 scripts/sync_gate.py --baseline /path/to/0c8baaf --rounds 7 --output /tmp/sync-controls
taskset -c 24-31 zig build bench-numa-arena -- 4096 31
```
