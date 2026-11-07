# Recursive grain cutoff

The tree benchmark now stops constructing `Future`s once a subtree has at
most 2047 nodes and calls the same direct serial traversal used by the
reference path. Work above the cutoff retains the existing
heartbeat/fork/join scheduler, plain-store local forks, caller fallback and
error-union result handling. The node layout is unchanged; a `Work` value
carries the remaining tree depth. Saturating depth calculation also handles
arbitrary nonzero `usize` input counts without overflow.

This closes the strict small-input gate without sacrificing large-tree
throughput. The previous callback created a `Future` for almost every internal
node even when no heartbeat arrived, so the 1000-node traversal paid local
list, recursive error-union and join bookkeeping without executing in
parallel. The cutoff sends that whole input through the serial kernel. On a
million-node tree, it also removes bookkeeping from the leaf 2047-node
subtrees while leaving hundreds of subtrees available to seven background
workers.

An earlier prototype tried to expose the heartbeat as a `shouldFork` hint and
skip heartbeats when the local list was empty. Even with heartbeat disabled,
the outlined no-Future path measured `serial_ns=1514`,
`parallel_ns=2807`, `speedup=0.539` for 1000 nodes. The remaining recursive
error-union frame was too expensive, so all scheduler/API changes from that
prototype were removed. The retained change is workload grain selection, not
a new scheduler state or semantic branch.

## Alternating comparison

Baseline is `bfb3596479c797ccb358d75074d7a94e2975b7ae`. The candidate includes
the grain-cutoff benchmark plus the independent serial-lane fixes documented
next door; those core changes only guard inactive temporary workers and do not
affect this registered active caller. Baseline and candidate processes were
alternated over five outer rounds. Each process alternates serial and parallel
paths for nine inner measurements, checks warmups and every timed checksum,
and reports medians.

The process is restricted to CPUs 24-31 on an i9-13900K. The caller is pinned
to CPU 31 and the seven background workers to CPUs 24-30. Zig is 0.16.0.
[`comparison.json`](comparison.json) retains every process median and source
hashes. The table reports medians of the five process medians; speedup is the
median of each process's reported ratio.

| Input | Revision | serial_ns | parallel_ns | speedup | Gate |
|---:|---|---:|---:|---:|---|
| 1,000 | baseline | 1,484 | 3,172 | 0.473 | FAIL |
| 1,000 | 2047-node leaves | 1,488 | 1,515 | 0.980 | PASS |
| 1,000,000 | baseline | 1,725,858 | 806,036 | 2.239 | PASS |
| 1,000,000 | 2047-node leaves | 1,733,944 | 503,894 | 3.501 | PASS |

The candidate reduces the million-node parallel median by 37.5% in this
comparison and raises its measured speedup by 56.4%. The 1000-node parallel
median falls by 52.2%, bringing the strict `speedup >= 0.9` gate from failure
to a 0.980 pass. These are results for the fixed tree, CPU placement and host;
applications should choose grain size from their own per-item cost.

Reproduce the strict gate and large control with:

```sh
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000 heartbeat gate 31
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000000 heartbeat gate 31
```

This resolves the named small-tree parity gate. It does not by itself prove
global theoretical optimality across all recursive workloads, architectures,
worker counts or sibling-library integrations, so the broader optimization
goal remains active.
