# parz

`parz` is a Zig 0.16 fine-grained parallelism library for the Project-Z stack.
It combines a heartbeat/fork-join scheduler with flat parallel loop and fold
APIs, plus a standalone bounded-queue module. It replaces the per-library
`spawn → partition → join` code in `imx`, `iris`, `veyra`, `vort`, `spectra`,
`prism`, and `pangu`, and gives `zui`, `horizon`, and `netz` a reusable
bounded queue layer.

The scheduler core is derived from [judofyr/spice](https://github.com/judofyr/spice)
(0BSD, Copyright (c) 2024 Magnus Holm). `parz` keeps its central property:
**adding parallelism to a small workload must not make it meaningfully
slower.**

## Design at a glance

- **Local-first scheduling.** Each worker owns an intrusive job list. `fork`
  appends with plain stores — no atomics and no lock. Work leaves the list only
  through a heartbeat or an explicit `kickstart`.
- **Caller fallback is the safety net.** `join` returns `null` when no other
  lane picked the job up; the caller then runs it. Zero-worker, single-threaded,
  WASM, and spawn-failure configurations all use the same path.
- **Determinism by construction.** Flat results and errors are combined in
  chunk-index order, never completion order.
- **No hidden allocation on hot paths.** Fork/join uses caller stack storage;
  flat loops use a 4 KiB stack fallback allocator.
- **Scheduler and sync stay independent.** The local job list is not a
  general-purpose MPSC queue.

See [docs/architecture.md](docs/architecture.md) for the full model and
[docs/parallel-api.md](docs/parallel-api.md) for API semantics.

## What is implemented

**Scheduler**

- `Pool(Ctx)` with affinity-aware worker count, bounded caller slots,
  per-worker context init/deinit, a fixed execute-state pool, and deterministic
  shutdown.
- `Worker(Ctx)` with `index`, `context()`, per-worker `Task`, and a hot-path
  `tick()`.
- `Task(Ctx)` / `Future(Ctx, Input, Output)` fork/join with caller fallback.
- `tryJoin` / `result` for large or error-union payloads without materializing
  `?Output`.
- Optional SMT-aware Linux CPU affinity (`Options.pin_workers`) and optional
  NUMA placement (`Options.numa_node`, `Options.auto_numa`).

**Flat parallelism**

- `parallelFor`, `parallelForEach`, `parallelForRange`, `parallelFor2D`,
  `parallelFold`, `parallelFoldInfallible`, `parallelFoldRange`,
  `parallelFoldRangeInfallible`, `parallelReduce`, and
  `parallelReduceInfallible`.
- Balanced contiguous chunks: every chunk is nonempty, chunk lengths differ by
  at most one item, and `min_chunk` is respected unless the whole input is
  smaller.
- Dynamic chunk claiming by default; opt-in contiguous static scheduling for
  predictable work.
- Cooperative `CancelToken` checked at chunk entry/exit, every 4096 items in
  index loops, and before successful completion.
- Deterministic error selection by chunk index.
- Explicit item-cost hints for cheap workloads, worker-based calls that reuse
  lane context, and optional caller-owned `ParallelScratch` dispatch storage.

**Synchronization (`parz.sync`)**

- `SpscQueue(T)` — bounded single-producer/single-consumer queue.
- `MpscQueue(T)` — bounded multi-producer/single-consumer FIFO.
- `ShardedMpscQueue(T, shards)` — per-producer FIFO shards.
- `BlockingQueue(T)` — bounded blocking MPMC queue using `std.Io`.
- `TreiberStack(T)` — multi-producer/single-consumer stack.
- `Semaphore` and `WaitGroup`.
- Partial batch transfer APIs for every container and for coordination
  primitives; all transfers are bounded and allocate nothing.

**Platform**

- Serial fallback for single-threaded/WASM targets.
- Optional `NumaAllocator` with Linux VMA policies and portable fallback.

## Quick start

```zig
const std = @import("std");
const parz = @import("parz");

var pool = try parz.Pool(void).init(allocator, io, .{
    .workers = 0,              // 0 = affinity-aware CPU count - 1
    .max_workers = 64,
    .max_callers = 4,
    .max_execute_states = 1024,
    .pin_workers = false,      // SMT-aware Linux CPU affinity
    .numa_node = null,         // MPOL_PREFERRED node for background workers
    .auto_numa = false,        // use the pinned CPU's node when numa_node is null
});
defer pool.deinit();
try pool.start();

// Flat parallel loop.
const Render = struct {
    fn run(_: *parz.Worker(void), rows: []Row, index: usize) anyerror!void {
        try renderRow(rows[index]);
    }
};
try parz.parallelFor(&pool, rows, rows.len, .{ .min_chunk = 1 }, Render.run);

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

Use an explicit grain cutoff before forking: below the cutoff, call a
dedicated serial kernel directly; above it, keep recursive parallel calls on
`Task.call`. `bench/tree_sum.zig` demonstrates a depth-based cutoff without
changing the node layout. This is the recursive counterpart of the flat APIs'
`serial_threshold`.

Bounded queues:

```zig
var queue = try parz.sync.BlockingQueue(Message).init(allocator, 1024);
defer queue.deinit();

try queue.put(io, message);       // waits while full
const next = try queue.get(io);   // waits while empty

const written = try queue.putSlice(io, pending); // explicit partial progress
const read = try queue.getSlice(io, received);
```

See [docs/sync.md](docs/sync.md) for every primitive and its batch semantics.

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
shared between lanes; do not keep pointers into it after the callback returns.
Serial fallbacks use a temporary lane whose index is `pool.worker_count`.

## Build and test

```sh
zig build test
zig build test -Doptimize=ReleaseSafe

# ThreadSanitizer and single-threaded fallback.
zig test src/root.zig -fsanitize-thread -OReleaseSafe
zig test src/root.zig -fsingle-threaded -OReleaseSafe

# WASM compile-only check (blocking primitives need atomics).
zig test src/root.zig -target wasm32-wasi -mcpu=generic+atomics \
    -OReleaseSafe --test-no-exec

# All core gates, including cross-target compile checks.
scripts/check.sh
```

Benchmarks print `serial_ns`, `parallel_ns`, and `speedup`, and verify the
checksum before reporting. Common commands:

```sh
zig build bench-tree-sum -- 1000000
zig build bench-parallel-for -- 16000000
zig build bench-compute -- 1000000
zig build bench-2d
zig build bench-sync
zig build bench-spsc -Doptimize=ReleaseFast -- 3000000 1024 24 26 9
zig build bench                          # all primary benchmarks
```

The explicit small-input parity gate uses a fixed CPU set:

```sh
taskset -c 0,2,4,6,8,10,12,14 zig build bench-tree-sum \
    -Doptimize=ReleaseFast -- 1000 heartbeat gate
```

See [docs/benchmarks.md](docs/benchmarks.md) for argument meanings, fixed-CPU
methodology, the comparison harness, and the indicative performance snapshot.
Validation evidence is indexed in
[docs/validation/README.md](docs/validation/README.md).

## Documentation

| Document | Contents |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Scheduling model, fork/join protocol, invariants, known limits |
| [docs/parallel-api.md](docs/parallel-api.md) | Flat loop/fold semantics, cancellation, context, correctness rules |
| [docs/sync.md](docs/sync.md) | Queue, stack, semaphore, and wait-group semantics |
| [docs/benchmarks.md](docs/benchmarks.md) | Benchmark commands, methodology, and performance evidence |
| [docs/numa.md](docs/numa.md) | `NumaAllocator` policies, lifetime, and diagnostics |
| [docs/validation/README.md](docs/validation/README.md) | Index of fixed-CPU validation reports and raw logs |

## Known limits

- No work stealing: idle workers consume shared jobs; they do not steal from
  another worker's local list. This is intentional and matches Spice.
- A `Future` is single-use, must stay at a stable address while enqueued, and
  must be joined on the worker that forked it.
- `deinit` requires all caller slots released and no active flat call.
- Linux worker pinning captures the allowed CPU set during `Pool.init`; the
  caller keeps its existing affinity.
- `ParallelOptions.schedule = .static` is a partition/locality guarantee, not
  worker affinity. Use it only when chunk cost is predictable.

## License

The scheduler core is derived from judofyr/spice, distributed under the BSD
Zero Clause License (0BSD), Copyright (c) 2024 Magnus Holm. See `LICENSE.txt`.
