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
- `CancelToken` with cooperative cancellation checked at chunk boundaries and
  every 4096 items inside a chunk.
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

## Scheduling model

- Each worker owns a truly local intrusive job list. `fork` is three local
  stores; it takes no lock and performs no atomic operation.
- Work leaves the local list only when:
  - a heartbeat fires (default every 10 µs), or
  - a flat loop calls `kickstart` explicitly.
- The heartbeat only sets a flag; the owning worker checks it at the next
  `Task.call`, so the call hot path stays a single atomic load.
- Tiny workloads finish before any sharing, so they stay at serial cost.
- Flat loops share the whole chunk list up front and fall back to serial below
  `serial_threshold` items (default 4096) or when there are fewer chunks than
  lanes. This keeps small loops at serial cost and lets large loops pull work
  dynamically.
- A worker never executes user code while the pool mutex is held.
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

// Cooperative cancellation. The flat APIs check the token at chunk
// boundaries and every 4096 items.
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
            var future = parz.Future(void, *const Node, anyerror!i64){};
            future.fork(task, sum, right);
            result += try task.call(anyerror!i64, sum, left);
            result += if (future.join(task)) |value|
                try value
            else
                try task.call(anyerror!i64, sum, right);
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

Correctness rules:

- A `Future` is single-use. Reinitialize it with `.{}` before forking again;
  `join`/`tryJoin` intentionally leave the embedded job unlinked without
  resetting it so the local join path stays cheap.
- A `Future` must be joined by the same task that forked it. It lives on that
  task's stack and its job is linked into that task's local list.
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

## Building and testing

```sh
zig build test                       # Debug
zig build test -Doptimize=ReleaseSafe
zig build bench-tree-sum -- 1000000
zig build bench-parallel-for -- 16000000
zig build bench-compute -- 1000000
zig build bench-compute -- 1000000 pin   # exercise pin_workers
zig build bench-micro
zig build bench-2d                   # 2D grid fill
zig build bench-sync                 # sync primitive throughput
zig build bench                      # all benchmarks

# Cross-library comparison (needs a spice checkout, Cargo, and GCC/OpenMP).
zig build bench-compare -Doptimize=ReleaseFast
SPICE_DIR=/tmp/spice python3 bench/compare/run_compare.py --rounds 5 --lanes 32

# WASM compile-only check. The std.Io blocking primitives need atomics.
zig test src/root.zig -target wasm32-wasi -mcpu=generic+atomics \
    -OReleaseSafe --test-no-exec

# ThreadSanitizer validation for scheduler/sync changes.
zig test src/root.zig -fsanitize-thread -OReleaseSafe

# Run all core gates (add --compare for the cross-library gate).
scripts/check.sh
scripts/check.sh --compare
```

See `bench/compare/README.md` for the comparison methodology and fairness
notes.

Benchmarks print `serial_ns`, `parallel_ns`, and `speedup`; they verify the
checksum before reporting.

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

Small trees stay close to serial cost; medium trees break even or improve;
flat scans saturate memory bandwidth; CPU-bound work scales near linearly.
Treat these as indicative, not as a fixed gate.

Sync primitives have a separate throughput smoke benchmark
(`zig build bench-sync`). On the same loaded 32-thread host, 1M operations
give roughly 0.3 Gops/s for SPSC, 11–17 Mops/s for the Treiber stack,
21–25 Mops/s for MPSC with one producer, 22–30 Mops/s for the sharded MPSC
with four producers, and 7–8 Mops/s for the global MPSC with four producers
or the blocking queue. These are indicative throughput numbers, not
competitive gates.

## Known limits / next steps

- No built-in NUMA-aware allocator. `Options.numa_node` and
  `Options.auto_numa` set the worker thread's `MPOL_PREFERRED` policy;
  pool metadata uses the allocator passed to `Pool.init`, so pass a
  NUMA-aware allocator if metadata placement matters. The caller thread is
  not affected.
- No work stealing: idle workers consume shared jobs; they do not steal from
  another worker's local list. This is intentional and matches Spice.
- `deinit` requires all caller slots to be released and no flat-parallel call
  to be active.

## License

The scheduler core is derived from judofyr/spice, distributed under the
BSD Zero Clause License (0BSD), Copyright (c) 2024 Magnus Holm. See
`LICENSE.txt`.
