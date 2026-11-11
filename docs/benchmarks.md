# Benchmarks and validation

Benchmark claims require fixed input, a fixed CPU set, and alternating
serial/parallel runs. Every benchmark verifies its checksum before reporting.
Report `serial_ns`, `parallel_ns`, and `speedup`.

## Build and test gates

```sh
zig build test                       # Debug
zig build test -Doptimize=ReleaseSafe

# Single-threaded and ThreadSanitizer validation.
zig test src/root.zig -fsingle-threaded -OReleaseSafe
zig test src/root.zig -fsanitize-thread -OReleaseSafe

# WASM compile-only check. The std.Io blocking primitives need atomics.
zig test src/root.zig -target wasm32-wasi -mcpu=generic+atomics \
    -OReleaseSafe --test-no-exec

# Cross-target compile checks.
for target in x86_64-windows-gnu aarch64-macos x86_64-linux-musl; do
    zig test src/root.zig -target "$target" -OReleaseSafe --test-no-exec \
        -femit-bin="/tmp/parz-cross-$target-test"
done

# Run all core gates (add --compare for the cross-library gate).
scripts/check.sh
scripts/check.sh --compare
```

The core gate compiles the unit-test instances for WASM, Windows, macOS, and
musl Linux, and executes the native single-threaded fallback tests.

## Primary benchmarks

```sh
zig build bench-tree-sum -- 1000000
zig build bench-parallel-for -- 16000000
zig build bench-compute -- 1000000
zig build bench-compute -- 1000000 pin   # exercise pin_workers
zig build bench-2d                       # 2D grid fill
zig build bench-sync                     # sync primitive throughput
zig build bench-micro
zig build bench-micro -- 1000 8          # paired callback-shape overhead
zig build bench-irregular -- 200000 8 9 mixed
zig build bench                          # all primary benchmarks
```

`bench-tree-sum` and `bench-irregular` warm up both paths, verify every run,
alternate which path runs first, print raw paired samples, and report the
median.

- `bench-tree-sum [nodes] [heartbeat] [gate] [caller_cpu]`
- `bench-irregular [nodes] [lanes] [rounds] [profile]`
  - lanes `0` selects the automatic worker count; lanes `1` exercises caller
    fallback.
  - `mixed` uses fixed pseudo-random work per node; `skewed` makes the entire
    left subtree 32 times more expensive per node than the right subtree.
- `bench-micro [nodes] [lanes] [caller_cpu] [repetitions]`
  - The default repetition count is one. Larger counts time repeated calls and
    report nanoseconds per call. Every result is checked, and a compiler memory
    barrier prevents read-only serial callbacks from being moved outside the
    repetition loop.
  - Lanes `1` exercises zero-background-worker fallback.
  - The tree and micro serial reference functions use 64-byte code alignment to
    keep their instruction layout stable when scheduler code changes.
  - Optional CPU arguments pin background workers before pinning the caller, and
    reject a caller CPU outside the allowed set or already assigned to a worker.

Use a fixed CPU set with `taskset` for comparisons:

```sh
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast \
    -- 1000 heartbeat gate 31
taskset -c 24-31 zig build bench-micro -Doptimize=ReleaseFast -- 1000 8 31
taskset -c 24-31 zig build bench-infallible-fold -Doptimize=ReleaseFast \
    -- scan 1000003 8 31 1 64 9
taskset -c 0,2,4,6,8,10,12,14 zig build bench-irregular \
    -Doptimize=ReleaseFast -- 200000 8 9 skewed
```

## Small-input parity gate

The explicit parity gate rejects a slowdown greater than about 11% after
checksum validation and paired measurement:

```sh
taskset -c 0,2,4,6,8,10,12,14 zig build bench-tree-sum \
    -Doptimize=ReleaseFast -- 1000 heartbeat gate
```

This strict performance gate passes with the recursive grain cutoff and is
tracked separately from `scripts/check.sh`, which verifies correctness and
target compatibility.

## Flat-loop benchmarks

`bench-infallible-fold` compares calls without a cancellation token against
calls with a non-cancelled token and records dispatch allocations. Arguments are
workload (`scan` or `compute`), count, lanes, caller CPU, minimum chunk, chunks
per worker, and rounds.

- [Pure-value fold evidence](validation/2026-11-07-infallible-value-dispatch/README.md)
  includes fixed-CPU comparisons and the before/after allocation-failure
  fixture.
- [Range-fold report](validation/2026-11-07-range-fold/README.md) records the
  fixed-CPU SIMD comparison and full fallback/cancellation validation.
- [Static scheduling report](validation/2026-11-07-static-schedule/README.md)
  records high-chunk overhead and uniform-work controls.
- [Compute grain report](validation/2026-11-07-compute-grain/README.md)
  records the grain sweep, stack-budget control, and final cross-library
  results. The fixed-cost compute comparison uses dynamic scheduling with a
  tuned 128 chunks per lane.

## Sync benchmarks

```sh
zig build bench-spsc -Doptimize=ReleaseFast -- 3000000 1024 24 26 9
zig build bench-spsc-batch -Doptimize=ReleaseFast -- 3000000 1024 64 24 26 9
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 750000 1024 64 24,25,26,27 31 9
zig build bench-sharded-mpsc-batch -Doptimize=ReleaseFast -- \
    750000 1024 64 24,25,26,27 31 9
zig build bench-blocking-batch -Doptimize=ReleaseFast -- \
    500000 1024 64 24,25 26,27 31 9
zig build bench-treiber-batch -Doptimize=ReleaseFast -- \
    250000 64 24,25,26,27 31 9
zig build bench-semaphore-batch -Doptimize=ReleaseFast -- \
    1000000 64 24 26 9
```

- `bench-spsc [items] [capacity] [producer_cpu] [consumer_cpu] [rounds]` pins
  both endpoints, checks every warmup and measured transfer, and alternates
  baseline/current and serial/parallel paths. Allocation, thread creation, and
  affinity setup occur before timing. It retains the SPSC implementation from
  `efeb092` as a frozen baseline.
- `bench-spsc-batch [items] [capacity] [batch] [producer_cpu] [consumer_cpu] [rounds]`
  compares scalar and slice APIs using identical prebuilt input and receiver
  buffers.
- `bench-mpsc-batch [items_per_producer] [capacity] [batch] [producer_cpus] [consumer_cpu] [rounds]`
  compares scalar and slice transfers using fixed prebuilt input, checks
  per-producer FIFO as well as the checksum, and alternates both APIs and
  serial/parallel runs. Each CPU must be distinct; allocation, thread startup,
  and affinity setup precede timing.
- `bench-sharded-mpsc-batch` performs the same fixed-CPU, per-producer FIFO and
  checksum validation for private SPSC shards.
- `bench-blocking-batch` compares scalar and slice operations for two producers
  and two consumers, with thread startup outside timing and every output
  checked afterward.
- `bench-treiber-batch` compares per-node CAS operations with caller-owned node
  slice publication/removal.
- `bench-semaphore-batch` compares per-permit locking with multi-permit
  coordination between fixed producer/consumer CPUs.

Evidence:

- [SPSC validation report](validation/2026-11-07-cached-spsc/README.md)
- [SPSC batch evidence](validation/2026-11-07-spsc-batch/README.md)
- [MPSC batch report](validation/2026-11-07-mpsc-batch/README.md)
- [Sharded MPSC batch report](validation/2026-11-07-sharded-mpsc-batch/README.md)
- [BlockingQueue batch report](validation/2026-11-07-blocking-batch/README.md)
- [Treiber batch report](validation/2026-11-07-treiber-batch/README.md)
- [Coordination batch report](validation/2026-11-07-coordination-batch/README.md)

`bench-sync` is a separate throughput smoke benchmark; its SPSC path verifies
FIFO order and checksum.

## Cross-library comparison

The comparison harness needs a spice checkout, Cargo, and GCC/OpenMP:

```sh
zig build bench-compare -Doptimize=ReleaseFast
SPICE_DIR=/tmp/spice python3 bench/compare/run_compare.py --rounds 5 --lanes 32
```

See `bench/compare/README.md` for the methodology and fairness notes.

## Indicative snapshot

From a 32-thread x86-64 Linux host (31 background workers, ReleaseFast, best of
several runs, machine otherwise loaded):

| Workload | Serial | Parallel | Speedup |
|---|---|---|---|
| tree sum, 1K nodes | ~3.9 µs | ~4.0–4.2 µs | 0.9–1.0x |
| tree sum, 100K nodes | ~170 µs | ~150–180 µs | 0.9–1.4x |
| tree sum, 10M nodes | ~15.8 ms | ~3.6–3.8 ms | 4.2–4.3x |
| flat sum, 16M u64 | ~7.1 ms | ~1.5–1.8 ms | 4.0–4.7x |
| CPU-bound fold, 1M items | ~64 ms | ~3.7–4.0 ms | 15–19x |
| 2D grid fill, 4096×4096 | ~40 ms | ~2.4 ms | ~17x |

These older best-run measurements are indicative and use a different timing
method from the paired medians. Current fixed-CPU evidence is recorded in:

- [Boundary validation report](validation/2026-11-07-boundaries/README.md)
- [Recursive grain report](validation/2026-11-07-recursive-grain/README.md)

The 1000-node parity gate now passes by routing subtrees of at most 2047 nodes
through the direct serial kernel; larger trees retain heartbeat fork/join.

## Evidence index

`bench-multi-caller` reports throughput and per-call p50/p95/max latency for
checked simultaneous callers. Its arguments are caller count, items/call,
calls/caller, complete physical CPU list, rounds and optional `fair` policy.
The main controller shares the last caller CPU only during untimed setup/join.

```sh
taskset -c 24-31 zig build bench-multi-caller -- 4 4096 8 24,25,26,27,28,29,30,31 9
python3 scripts/perf_gate.py --callers-only --baseline /path/to/baseline \
  --cpus 24-31 --rounds 5 --output /tmp/parz-callers
python3 scripts/perf_gate.py --first-call-only --idle-ms 100 \
  --baseline /path/to/baseline --cpus 24-31 --rounds 5 --output /tmp/parz-cold
python3 scripts/idle_profile.py --baseline /path/to/baseline --cpus 24-31 \
  --rounds 3 --output /tmp/parz-idle
```

Cold-call preparation sleeps outside both timing intervals. Idle profiling
uses per-thread context switches and scheduler CPU nanoseconds from `/proc`;
`--parking` measures the explicit parking policy rather than the default.
Automatic parking and unconditional owner fairness are not enabled by default
when their latency/throughput comparisons show regressions.

Primary compute, flat-fold and 2D benchmarks warm both paths, alternate them,
verify every checksum and report medians. Both 2D paths include the fill and
the same post-fill checksum traversal. Optional arguments fix lane count,
caller CPU and sample count:

```sh
taskset -c 24-31 zig build bench-parallel-for -- 1000003 8 31 21
taskset -c 24-31 zig build bench-compute -- 1000000 pin 8 31 9
taskset -c 24-31 zig build bench-2d -- 1024 1024 8 31 9
python3 scripts/perf_gate.py --baseline /path/to/baseline --cpus 24-31 \
  --rounds 5 --output /tmp/parz-regression
```

The regression runner compiles identical current benchmark sources against
both core checkouts, alternates process order and saves every inner sample.
It rejects a median parallel-time increase above the requested allowance
(5% default, accounting for noisy hosts) and always enforces 0.9x small-tree
parity. A failed row requires investigation and a repeated comparison; a
passing row only supports the inputs and CPU placement measured. Set
`PARZ_BENCH_CPUS` to fix the default check script's CPU set; otherwise it
selects up to eight allowed physical cores and reserves the last for caller.

`bench-flat-dispatch` measures the opt-in cost guard, borrowed worker context
and strict scratch against the old core with the same harness. Arguments are
`kind count lanes caller_cpu chunks_per_worker rounds repetitions`, where
kind is `scan`, `cheap`, `compute`, `context`, or `scratch`:

```sh
taskset -c 24-31 zig build bench-flat-dispatch -- cheap 4096 8 31 16 21
taskset -c 24-31 zig build bench-flat-dispatch -- context 16 8 31 16 21 1000
taskset -c 24-31 zig build bench-flat-dispatch -- scratch 1000003 8 31 64 21
python3 scripts/perf_gate.py --flat-only --baseline /path/to/baseline \
  --cpus 24-31 --rounds 7 --output /tmp/parz-flat-controls
```

Allocation counts exclude input/pool initialization. The synthetic context
constructor allocates 64 KiB; its map only scans data. Repeated context samples
amortize clock reads. This measures context construction overhead rather than
application scratch processing.

All fixed-CPU reports and raw logs are indexed in
[the validation index](validation/README.md).
