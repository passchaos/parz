# parz

`parz` is a Zig 0.16 fine-grained parallelism library for the Project-Z stack.
It combines a heartbeat/fork-join scheduler with flat parallel loop and fold
APIs, and is intended to replace the per-library `spawn → partition → join`
code that currently exists in `imx`, `iris`, `veyra`, `vort`, `spectra`,
`prism`, and `pangu`.

The scheduler core is derived from [judofyr/spice](https://github.com/judofyr/spice)
(0BSD, Copyright (c) 2024 Magnus Holm). `parz` keeps its central property:
adding parallelism to a small workload must not make it meaningfully slower.

## What is implemented

- `Pool(Ctx)` with affinity-aware worker count, bounded caller slots,
  per-worker context init/deinit, fixed execute-state pool, and deterministic
  shutdown.
- `Worker(Ctx)` with `index`, `context()`, per-worker `Task`, and a hot-path
  `tick()`.
- `Task(Ctx)` / `Future(Ctx, Input, Output)` fork/join with caller fallback:
  `join` returns `null` when no other lane picked the job up.
- `tryJoin` / `result` for large or error-union payloads without materializing
  `?Output`.
- `parallelFor`, `parallelForEach`, `parallelForRange`, `parallelFold`,
  `parallelFoldInfallible`, `parallelReduce` with deterministic chunk-index
  combination.
- Uncancelled infallible folds use plain-value chunk results and callbacks,
  reducing dispatch storage while preserving the same chunk planning.
- `CancelToken` with cooperative cancellation checked at chunk entry/exit,
  every 4096 items in index loops, and before successful completion.
- `sync` module: bounded SPSC/MPSC queues, a sharded MPSC queue with
  per-producer FIFO shards, a bounded blocking MPMC queue, a
  multi-producer/single-consumer Treiber stack, a counting semaphore, and a
  wait group.
- `parallelFor2D` for row-major grids, optional SMT-aware Linux CPU
  affinity via `Options.pin_workers` (one logical CPU per physical core),
  and optional `MPOL_PREFERRED` NUMA binding via `Options.numa_node` or
  `Options.auto_numa`.
- Serial fallback for single-threaded/WASM targets, exhausted execute states,
  and no available caller slot.
- Error propagation: the first failing chunk (by chunk index) is returned.
- Optional `NumaAllocator` with local/preferred/bind/interleave Linux VMA
  policies, policy diagnostics, and portable allocator fallback.
- Balanced contiguous flat chunks: every chunk is nonempty, chunk lengths
  differ by at most one item, and `min_chunk` is respected unless the entire
  input is smaller. Range planning supports counts up to `maxInt(usize)`.

## Scheduling model

- Each worker owns a truly local intrusive job list. `fork` appends through
  plain stores; it takes no lock and performs no atomic operation.
- Work leaves the local list only when:
  - a heartbeat fires (default every 10 µs), or
  - a flat loop calls `kickstart` explicitly.
- The heartbeat only sets a flag; the owning worker checks it at the next
  `Task.call`, so the call hot path stays a single atomic load.
- Tiny workloads usually finish before sharing and stay on the caller.
  Recursive algorithms should also stop creating `Future`s below a useful
  grain size and invoke a direct serial kernel for those subtrees: heartbeat
  pacing avoids worker wake-ups, but cannot remove local Future bookkeeping.
  The tree gate uses a 2047-node leaf bound and keeps 1000-node traversal at
  serial parity while retaining parallelism above that bound.
- Flat loops share one job per lane up front and fall back to serial below
  `serial_threshold` items (default 4096) or when there are fewer chunks than
  lanes. This keeps small loops at serial cost and lets large loops pull work
  dynamically. The caller executes its lane immediately, before waiting for
  background lanes. Dispatch storage uses a 4 KiB stack fallback buffer.
- A worker never executes user code while the pool mutex is held.
- `ParallelOptions.max_workers` caps simultaneous lanes for that call,
  including the caller. A value of 1 keeps the chunk callbacks on the caller;
  each lane claims chunks dynamically. Chunk results and errors retain
  chunk-index ordering.
- `join` returns `null` when the job is still local or was reclaimed; the
  caller then executes it. This is the same fallback that makes zero-worker
  and spawn-failure configurations safe.

## Usage

```zig
const parz = @import("parz");

var pool = try parz.Pool(void).init(allocator, io, .{
    .workers = 0,              // 0 = affinity-aware CPU count - 1
    .max_workers = 64,
    .max_callers = 4,
    .max_execute_states = 1024,
    .pin_workers = false,      // SMT-aware Linux CPU affinity for workers
    .numa_node = null,         // Linux MPOL_PREFERRED node for background workers
    .auto_numa = false,        // use the pinned CPU's node when numa_node is null
});
defer pool.deinit();
try pool.start();

// Flat parallel loop.
const Run = struct {
    fn run(_: *parz.Worker(void), rows: []Row, index: usize) anyerror!void {
        try renderRow(rows[index]);
    }
};
try parz.parallelFor(&pool, rows, rows.len, .{ .min_chunk = 1 }, Run.run);

// Deterministic fold.
const Map = struct {
    fn map(_: *parz.Worker(void), data: []const u64, index: usize) anyerror!u64 {
        return data[index];
    }
};
const Add = struct {
    fn combine(a: u64, b: u64) u64 {
        return a + b;
    }
};
const total = try parz.parallelFold(
    &pool, u64, data, data.len, .{ .min_chunk = 4096 }, 0, Map.map, Add.combine,
);

// When `map` cannot fail, the infallible variant removes the per-item error
// check from the chunk loop.
const total_infallible = try parz.parallelFoldInfallible(
    &pool, u64, data, data.len, .{ .min_chunk = 4096 }, 0, Map.map, Add.combine,
);

// Cooperative cancellation. Nonempty flat calls check chunk entry/exit and
// successful completion; index loops also check every 4096 items.
var token = parz.CancelToken{};
try parz.parallelFor(
    &pool, rows, rows.len, .{ .min_chunk = 1, .cancel = &token }, Run.run,
);
```

Recursive fork/join:

```zig
fn sum(task: *parz.Task(void), node: *const Node) anyerror!i64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future: parz.Future(void, *const Node, anyerror!i64) = undefined;
            future.initFork(task, sum, right);
            const left_value = task.call(anyerror!i64, sum, left);
            const right_value = future.joinOrCall(task, sum);
            // Join both branches before propagating either error.
            result += try left_value;
            result += try right_value;
            return result;
        }
        result += try task.call(anyerror!i64, sum, left);
    }
    if (node.right) |right| result += try task.call(anyerror!i64, sum, right);
    return result;
}
```

`Task.call` must be used for recursive calls; direct calls bypass heartbeat
checks and the caller-fallback protocol.

Use an explicit grain cutoff before the fork. The cutoff belongs in the
workload callback because only it knows whether an item represents a cheap
node visit or substantial work. Below the cutoff, call a dedicated serial
kernel directly; above it, keep recursive parallel calls on `Task.call`.
`bench/tree_sum.zig` demonstrates a depth-based cutoff without adding fields
to the node layout. This is the recursive counterpart of flat APIs'
`serial_threshold`.

For folds, `combine` needs an associative operation and a valid identity to
match serial results across different chunk configurations. Chunk-index
combination preserves order; floating-point addition can still change with
chunk boundaries because it is not associative.

Correctness rules:

- A `Future` is single-use. Reinitialize it with `.{}` before forking again;
  `join`/`tryJoin` intentionally leave the embedded job unlinked without
  resetting it so the local join path stays cheap.
- `initFork` initializes unused caller-owned storage, including `undefined`
  storage or a previously joined slot. Keep its address stable until joined;
  do not copy or return an enqueued Future by value.
- A `Future` must be joined on the worker that forked it. Nested tasks on that
  worker share its local list. Join every fork before propagating an error
  that could unwind its storage.
- `fork` must be followed by `join`/`tryJoin`/`joinOrCall`; do not drop a
  forked future.
- `Task.call` is the only legal way to invoke a recursive parallel function.
- A worker context is owned by its lane. Do not share it across lanes or keep
  pointers into it after the callback returns.
- `deinit` requires all caller slots released and no active flat call.

## Sync primitives

`parz.sync` is independent of the scheduler:

- `SpscQueue(T)` — bounded single-producer/single-consumer.
- `MpscQueue(T)` — bounded multi-producer/single-consumer FIFO.
- `ShardedMpscQueue(T, shards)` — per-producer FIFO shards; no global order.
- `BlockingQueue(T)` — bounded blocking MPMC queue using `std.Io`.
- `TreiberStack(T)` — multi-producer/single-consumer stack; nodes are caller-owned.
- `Semaphore` and `WaitGroup`.

SPSC also supports partial bulk transfer without allocating:

```zig
const pushed = queue.tryPushSlice(pending); // prefix accepted, possibly zero
const popped = queue.tryPopSlice(received); // received[0..popped] is valid
```

Keep one producer and one consumer. Slice transfers may be mixed with
`tryPush`/`tryPop`, preserve FIFO order, and publish/free a whole batch with
one release store. Input/output slices must not alias queue storage. A pop
leaves the unused output suffix untouched.

```zig
var queue = try parz.sync.BlockingQueue(Message).init(allocator, 1024);
defer queue.deinit();

try queue.put(io, message);       // waits while full
const next = try queue.get(io);   // waits while empty

var group = parz.sync.WaitGroup{};
group.add(io, workers);
// each worker:
group.done(io);
group.wait(io);
```

`MpscQueue` and `ShardedMpscQueue` are non-blocking (`tryPush`/`tryPop`);
`BlockingQueue` is the multi-consumer blocking option.

`MpscQueue` also provides `tryPushSlice` and `tryPopSlice`. For capacities of
four or more, a producer reserves an available input prefix with one CAS and
publishes each slot separately. One- and two-slot queues use scalar operations;
another producer may interleave between those scalar pushes.
The consumer copies a ready prefix, stopping at the first unpublished slot;
later producers cannot bypass an earlier reservation. Both operations return
the transferred count, support mixing with scalar operations, allocate
nothing, and transfer at most the queue capacity. Input/output must not alias
queue storage, and an unused output suffix stays untouched. FIFO follows
reservation order; individual producer sequences retain their order. A stalled
producer can temporarily prevent the consumer from reaching later ready slots.

`SpscQueue` caches the opposite endpoint's position until a possible full or
empty boundary. Producer state, consumer state, and immutable buffer metadata
occupy separate cache lines. This reduces communication between cores at the
cost of larger queue metadata: 384 bytes on x86_64 using Zig's 128-byte padding
unit. Sharded MPSC queues inherit this layout. Single-threaded use is supported;
same-thread throughput is measured separately in the SPSC benchmark.

## Per-worker context

```zig
const Ctx = struct { scratch: std.heap.ArenaAllocator };

const Hooks = struct {
    fn init(allocator: std.mem.Allocator, _: usize) !Ctx {
        return .{ .scratch = std.heap.ArenaAllocator.init(allocator) };
    }
    fn deinit(_: std.mem.Allocator, ctx: *Ctx) void {
        ctx.scratch.deinit();
    }
};

var pool = try parz.Pool(Ctx).init(allocator, io, .{
    .context_init = Hooks.init,
    .context_deinit = Hooks.deinit,
});
```

Inside a callback, `worker.context()` returns the lane's context. It is not
shared between lanes.

Serial flat fallbacks use a temporary lane whose `worker.index` matches the
index passed to `context_init`: `pool.worker_count`, outside the registered
lane range. Temporary contexts remain private to each call. Their inactive
workers keep forked work local; `kickstart` leaves it for caller execution.
Already-cancelled nonempty serial calls return before constructing a context.

Cancellation is cooperative. A cancelled flat call joins all started lane
futures before returning, so its input and scratch storage can be released
after the call unwinds. A callback error takes precedence over cancellation
observed at that callback's exit; chunk errors are selected in chunk-index
order. Cancellation from a final successful callback or ordered reduction is
observed before successful completion. Long `parallelForRange` callbacks can
check their token during their own work; empty calls retain their no-op result.

## Building and testing

```sh
zig build test                       # Debug
zig build test -Doptimize=ReleaseSafe
zig build bench-tree-sum -- 1000000
zig build bench-parallel-for -- 16000000
zig build bench-compute -- 1000000
zig build bench-compute -- 1000000 pin   # exercise pin_workers
taskset -c 24-31 zig build bench-infallible-fold -Doptimize=ReleaseFast \
    -- scan 1000003 8 31 1 64 9
zig build bench-micro
zig build bench-micro -- 1000 8       # paired callback-shape overhead
taskset -c 24-31 zig build bench-micro -Doptimize=ReleaseFast -- 1000 1 31 1024
zig build bench-irregular -- 200000 8 9 mixed
taskset -c 0,2,4,6,8,10,12,14 zig build bench-irregular \
    -Doptimize=ReleaseFast -- 200000 8 9 skewed
# Fix the caller and each background worker on distinct allowed CPUs (Linux).
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast \
    -- 1000 heartbeat gate 31
taskset -c 24-31 zig build bench-micro -Doptimize=ReleaseFast -- 1000 8 31
zig build bench-2d                   # 2D grid fill
zig build bench-sync                 # sync primitive throughput
zig build check-worker-layout        # field offsets and context alignment
zig build bench-spsc -Doptimize=ReleaseFast -- 3000000 1024 24 26 9
zig build bench-spsc-batch -Doptimize=ReleaseFast -- 3000000 1024 64 24 26 9
zig build bench-mpsc-batch -Doptimize=ReleaseFast -- 750000 1024 64 24,25,26,27 31 9
# bench-spsc arguments: items capacity producer_cpu consumer_cpu rounds (Linux)
zig build bench                      # all benchmarks

# Cross-library comparison (needs a spice checkout, Cargo, and GCC/OpenMP).
zig build bench-compare -Doptimize=ReleaseFast
SPICE_DIR=/tmp/spice python3 bench/compare/run_compare.py --rounds 5 --lanes 32

# WASM compile-only check. The std.Io blocking primitives need atomics.
zig test src/root.zig -target wasm32-wasi -mcpu=generic+atomics \
    -OReleaseSafe --test-no-exec

# ThreadSanitizer validation for scheduler/sync changes.
zig test src/root.zig -fsanitize-thread -OReleaseSafe
zig test src/root.zig -fsingle-threaded -OReleaseSafe

# Run all core gates (add --compare for the cross-library gate).
scripts/check.sh
scripts/check.sh --compare
```

The core gate compiles the unit-test instances for WASM, Windows, macOS,
and musl Linux, and executes the native single-threaded fallback tests.

See `bench/compare/README.md` for the comparison methodology and fairness
notes.

Benchmarks print `serial_ns`, `parallel_ns`, and `speedup`; they verify the
checksum before reporting.

`bench-infallible-fold` compares calls without a cancellation token against
calls with a non-cancelled token and records dispatch allocations. Arguments
are workload (`scan` or `compute`), count, lanes, caller CPU, minimum chunk,
chunks per worker, and rounds. [Pure-value fold evidence](docs/validation/2026-11-07-infallible-value-dispatch/README.md)
includes fixed-CPU comparisons and the before/after allocation-failure fixture.

`bench-mpsc-batch` compares scalar and slice transfers using fixed prebuilt
input, checks per-producer FIFO as well as the checksum, and alternates both
APIs and serial/parallel runs. Arguments are items per producer, capacity,
batch size, comma-separated producer CPUs, consumer CPU, and rounds. Each CPU
must be distinct; allocation, thread startup and affinity setup precede timing.
Measured results and correctness checks are recorded in
[the MPSC batch validation report](docs/validation/2026-11-07-mpsc-batch/README.md).

`bench-tree-sum` and `bench-irregular` warm up both paths, verify every run,
alternate which path runs first, print raw paired samples, and report the
median. The irregular benchmark accepts `[nodes] [lanes] [rounds] [profile]`;
lanes 0 selects the automatic worker count and lanes 1 exercises caller
fallback. `mixed` uses fixed pseudo-random work per node; `skewed` makes the
entire left subtree 32 times more expensive per node than the right subtree.
Use a fixed CPU set with `taskset` for comparisons.

`bench-micro` accepts an optional repetition count after the caller CPU.
The default is one. Larger counts time repeated calls and report nanoseconds
per call; every result is checked, and a compiler memory barrier prevents
read-only serial callbacks from being moved outside the repetition loop.
This diagnostic helps assess tiny callback costs alongside the single-call
tree gate. [Local-link experiments](docs/validation/2026-11-07-local-forward-links/README.md)
record the rejected scheduling changes and all raw measurements.

The explicit parity gate rejects a slowdown greater than about 11% after
checksum validation and paired measurement:

```sh
taskset -c 0,2,4,6,8,10,12,14 zig build bench-tree-sum \
    -Doptimize=ReleaseFast -- 1000 heartbeat gate
```

This strict performance gate passes with the recursive grain cutoff and is
tracked separately from `scripts/check.sh`, which verifies correctness and
target compatibility.

Indicative snapshot from a 32-thread x86-64 Linux host (31 background workers,
ReleaseFast, best of several runs, machine otherwise loaded):

| Workload | Serial | Parallel | Speedup |
|---|---|---|---|
| tree sum, 1K nodes | ~3.9 µs | ~4.0–4.2 µs | 0.9–1.0x |
| tree sum, 100K nodes | ~170 µs | ~150–180 µs | 0.9–1.4x |
| tree sum, 10M nodes | ~15.8 ms | ~3.6–3.8 ms | 4.2–4.3x |
| flat sum, 16M u64 | ~7.1 ms | ~1.5–1.8 ms | 4.0–4.7x |
| CPU-bound fold, 1M items | ~64 ms | ~3.7–4.0 ms | 15–19x |
| 2D grid fill, 4096×4096 | ~40 ms | ~2.4 ms | ~17x |

These older best-run measurements are indicative and use a different timing
method from the paired medians. Current fixed-CPU evidence is recorded in
[the boundary validation report](docs/validation/2026-11-07-boundaries/README.md).
Current fixed-CPU small-tree and large-tree results are recorded in
[the recursive grain report](docs/validation/2026-11-07-recursive-grain/README.md).
The 1000-node parity gate now passes by routing subtrees of at most 2047 nodes
through the direct serial kernel; larger trees retain heartbeat fork/join.

Sync primitives have a separate throughput smoke benchmark
(`zig build bench-sync`); its SPSC path verifies FIFO order and checksum.
`bench-spsc` pins both endpoints, checks every warmup and measured transfer,
and alternates baseline/current and serial/parallel paths. Allocation, thread
creation, and affinity setup occur before timing. It retains the SPSC
implementation from `efeb092` as a frozen baseline. Paired medians and layout
tradeoffs are recorded in
[the SPSC validation report](docs/validation/2026-11-07-cached-spsc/README.md).
`bench-spsc-batch` compares scalar and slice APIs using identical prebuilt
input and receiver buffers. Arguments are items, capacity, batch size,
producer CPU, consumer CPU, and rounds. [Batch transfer evidence](docs/validation/2026-11-07-spsc-batch/README.md)
records every payload check, capacity-one controls and publication amortization.

## Known limits / next steps

Linux worker pinning captures the allowed CPU set during `Pool.init` and
selects one allowed sibling per physical core. Automatic worker count reserves
one selected CPU for the caller; explicit counts are capped by the selected
CPU list. The caller keeps its existing affinity.

- `Options.numa_node` and `Options.auto_numa` set worker thread policy.
  `NumaAllocator` sets policy on each Linux allocation before first-touch;
  pass its allocator to `Pool.init` to cover metadata and per-worker arenas.
- No work stealing: idle workers consume shared jobs; they do not steal from
  another worker's local list. This is intentional and matches Spice.
- `deinit` requires all caller slots to be released and no flat-parallel call
  to be active.

## License

The scheduler core is derived from judofyr/spice, distributed under the
BSD Zero Clause License (0BSD), Copyright (c) 2024 Magnus Holm. See
`LICENSE.txt`.

Concurrent `SpscQueue.len()` snapshots are approximate and bounded by capacity.
`TreiberStack.len()` includes pushes that have reserved their count before
publishing their node; it is exact after operations have finished.

`bench-micro` accepts `[nodes] [lanes]`, disables heartbeat sharing, verifies
every plain/error-union result, alternates each path with serial traversal,
and reports paired medians. Lanes 1 exercises zero-background-worker fallback.
The tree and micro serial reference functions use 64-byte code alignment to
keep their instruction layout stable when scheduler code changes.

An optional third `bench-micro` argument fixes the caller CPU; `bench-tree-sum`
accepts the caller CPU after its heartbeat and gate arguments. These modes pin
background workers before pinning the caller, and reject a caller CPU outside
the allowed set or already assigned to a worker.

Nested `Task` values use their worker's current local tail. Reclaiming a shared
parent future therefore preserves access to newly forked descendant jobs.
The retained local tail also permits a local join without atomic state checks.
The regression, worker-count checks, and paired measurements are recorded in
[the owner-tail validation report](docs/validation/2026-11-07-owner-tail/README.md).
The obsolete pending-future specialization and repeated local-tail checks
have since been removed; [the join simplification report](docs/validation/2026-11-07-join-simplification/README.md)
records the aligned controls and rejected register-return experiments.
`check-worker-layout` reports the actual compiler layout for ordinary and
overaligned contexts. [Worker layout experiments](docs/validation/2026-11-07-worker-layout/README.md)
did not establish a stable padding benefit, so the compact worker layout is retained.
Three [Future storage trials](docs/validation/2026-11-07-future-storage/README.md)
emitted identical executable code; the byte-array payload remains in use.
`Future.initFork` bypasses the pending value constructor when forking
immediately. [Direct initialization evidence](docs/validation/2026-11-07-future-init/README.md)
records the removed initialization write, lifecycle checks and measured limits.
[Cold-path code layout trials](docs/validation/2026-11-07-cold-paths/README.md)
found that branch hints emitted identical code and explicit outlining regressed
the P-core large-tree control; automatic inlining is retained.

Optional NUMA-backed allocation:

```zig
var numa = try parz.NumaAllocator.init(allocator, .{
    .policy = .preferred,
    .nodes = &.{0},
    .require_policy = false,
});
defer numa.deinit();
var pool = try parz.Pool(void).init(numa.allocator(), io, .{});
defer pool.deinit();
try pool.start();
```

`local` requires an empty node list, `preferred` one node, and `bind` or
`interleave` a nonempty set. Node masks are copied during initialization and
support all `u16` IDs. The allocator instance must remain at the same address
and outlive its allocations. It uses separate anonymous page mappings on
Linux; an arena can amortize page and syscall overhead for small objects.
Other targets use the supplied fallback allocator. `require_policy = true`
rejects unsupported platforms during initialization and failed Linux policy
requests as allocation failure. `stats()` reports accepted requests, fallback
allocations, failed policy requests, and the last Linux errno. Policy acceptance
describes VMA configuration; physical placement also depends on first-touch
and the nodes permitted by the host.

```sh
zig build check-numa -- preferred 0
zig build check-numa -- preferred 65535 require
```
