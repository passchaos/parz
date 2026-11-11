# Parallel API

The flat APIs run direct callbacks over planned chunks. They intentionally do
not build a composable iterator. Every chunk owns a disjoint range and results
are combined in chunk-index order.

## Entry points

| API | Shape |
|---|---|
| `parallelFor(pool, shared, count, options, run)` | `run(worker, shared, index)` |
| `parallelForEach(pool, slice, options, run)` | `run(worker, slice, index)` |
| `parallelForRange(pool, shared, count, options, run)` | `run(worker, shared, chunk)` |
| `parallelFor2D(pool, shared, rows, cols, options, run)` | `run(worker, shared, row, col)` |
| `parallelFold(pool, T, shared, count, options, identity, map, combine)` | fallible `map(worker, shared, index)`, `combine(T, T) T` |
| `parallelFoldInfallible(...)` | infallible `map`, no per-item error check |
| `parallelFoldRange(...)` | fallible `map_range(worker, shared, chunk)` |
| `parallelFoldRangeInfallible(...)` | infallible range callback |
| `parallelReduce` / `parallelReduceInfallible` | aliases of the matching fold |

All APIs return `anyerror!void` or `anyerror!T` so allocation, callback, and
cancellation failures propagate to the caller.

The first argument may also be an explicitly owned `*Worker(Ctx)`. A worker
call uses that lane directly, including its context on the serial path, and
does not claim or release another caller slot. Inside a callback, pass the
current worker for nested calls. Outside callbacks, claim a caller once and
release it after all calls/futures finish; never overlap calls from different
threads on the same worker.

## Options

```zig
pub const Options = struct {
    min_chunk: usize = 1,
    max_chunks: usize = 4096,
    chunks_per_worker: usize = 16,
    schedule: Schedule = .dynamic,
    max_workers: usize = 0,
    serial_threshold: usize = 4096,
    cancel: ?*CancelToken = null,
    estimated_item_ns: usize = 0,
    min_parallel_ns: usize = 50 * std.time.ns_per_us,
    scratch: ?*parz.ParallelScratch = null,
};
```

- `min_chunk` — minimum items per chunk unless the whole input is smaller.
- `max_chunks` — hard upper bound on chunks for one call.
- `chunks_per_worker` — target chunks per available lane. More chunks improve
  dynamic load balance; static scheduling assigns them in contiguous lane
  spans. This controls granularity, not the number of jobs to wake.
- `schedule` — `.dynamic` (default) or `.static`; see below.
- `max_workers` — per-call lane cap including the caller. `0` uses all
  available lanes.
- `serial_threshold` — run serially below this item count. Set to `0` to force
  parallelism.
- `cancel` — optional cooperative cancellation token.
- `estimated_item_ns` — an explicit estimate of useful item cost; zero keeps
  existing planning. A nonzero estimate runs serially when saturating
  `count * estimated_item_ns < min_parallel_ns`. This guard is additional to
  `serial_threshold`; setting that threshold to zero still forces dispatch.
- `min_parallel_ns` — minimum estimated useful work before dispatch. Measure
  the callback to choose an estimate and budget; the library does not sample
  callbacks or infer cost from fallibility.
- `scratch` — optional strict reusable dispatch buffer; see below.

For lightweight scans, `.estimated_item_ns = 1` avoids the 4096-item wake-up
boundary on the measured host. Keep the default zero estimate for unknown
cost callbacks and tune heavy kernels independently. The item estimate is
not a platform-independent performance guarantee.

## Reusing caller context and dispatch storage

```zig
const caller = pool.claimCaller() orelse return error.NoCallerSlot;
defer pool.releaseCaller(caller);
var bytes: [8192]u8 = undefined;
var scratch = parz.ParallelScratch.init(&bytes);
var values: [8192]u64 = @splat(0);
const Increment = struct {
    fn run(_: *parz.Worker(void), data: []u64, index: usize) anyerror!void {
        data[index] += 1;
    }
};
try parz.parallelFor(caller, &values, values.len, .{
    .scratch = &scratch,
}, Increment.run);
```

All flat API shapes accept a worker. Pool calls retain independent temporary
contexts on the serial/no-slot path, including the existing fallback index.
Worker calls borrow the lane's existing context; no context constructor or
destructor is invoked for that call. A nested callback must reserve/restore
its own arena state if outer code still needs allocations in the same context.

Scratch stores ordered chunk results and lane futures, and resets after all
futures and ordered reduction finish, including errors/cancellation. There
is no heap fallback when an explicit available buffer is too small: the call
returns `OutOfMemory` before callbacks and releases a claimed caller slot.
Account for both arrays, their alignment and the larger error-union result
type when cancellation is enabled. Scratch alignment may consume a prefix.

A nested call using the active outer scratch takes its own standard 4 KiB
stack fallback, leaving outer storage intact. Independent concurrent calls
must use separate scratch objects. Scratch and its byte buffer must remain
at stable addresses until the call returns. Default calls still use the
existing bounded stack/pool-allocator policy.

## Basic loops

```zig
const Run = struct {
    fn run(_: *parz.Worker(void), rows: []Row, index: usize) anyerror!void {
        try renderRow(rows[index]);
    }
};
try parz.parallelFor(&pool, rows, rows.len, .{ .min_chunk = 1 }, Run.run);
```

`parallelFor2D` visits every cell of a row-major `rows x cols` grid exactly
once. It converts a flat chunk offset to `(row, col)` once and then advances
with increments instead of dividing per cell. Empty dimensions are a no-op;
multiplication overflow returns `error.Overflow`.

## Folds

```zig
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

`combine` needs an associative operation and a valid identity to match serial
results across different chunk configurations. Chunk-index combination
preserves order; floating-point addition can still change with chunk boundaries
because it is not associative.

When `map` cannot fail, use the infallible variant. Uncancelled infallible folds
use plain-value chunk results and callbacks, reducing dispatch storage while
preserving the same chunk planning:

```zig
const InfallibleMap = struct {
    fn map(_: *parz.Worker(void), values: []const u64, index: usize) u64 {
        return values[index];
    }
};
const total_infallible = try parz.parallelFoldInfallible(
    &pool, u64, data, data.len, .{ .min_chunk = 4096 }, 0, InfallibleMap.map, Add.combine,
);
```

## Range folds

`parallelFoldRange` and `parallelFoldRangeInfallible` invoke the callback once
per planned nonempty `Chunk`, allowing the callback to use a direct inner loop,
SIMD, or a domain-specific kernel. Fallible and infallible forms preserve
chunk-index result and error ordering.

```zig
const RangeMap = struct {
    fn map(_: *parz.Worker(void), values: []const u64, chunk: parz.Chunk) u64 {
        var subtotal: u64 = 0;
        for (values[chunk.start..chunk.end]) |value| subtotal +%= value;
        return subtotal;
    }
};
const total_by_range = try parz.parallelFoldRangeInfallible(
    &pool, u64, data, data.len,
    .{ .min_chunk = 4096, .schedule = .static }, 0,
    RangeMap.map, Add.combine,
);
```

A serial fallback invokes the range callback once for the complete input. Entry
and exit cancellation checks remain automatic; a long-running range callback
should check its token internally when lower cancellation latency is needed.

## Dynamic and static scheduling

Dynamic scheduling is the default and lets fast lanes take more chunks, which
is preferable for irregular callbacks and heterogeneous CPUs.

Static scheduling divides chunk indices into balanced contiguous spans, one per
dispatch future. A future may execute on any available worker, so static is a
partition/locality guarantee rather than worker-affinity or context-index
binding. Use it only when chunk cost is predictable; no work is redistributed
from a slow static span after execution begins.

## Recursive fork/join

`Future` is the recursive API:

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

`Task.call` must be used for recursive calls; direct calls bypass heartbeat
checks and the caller-fallback protocol.

Use an explicit grain cutoff before the fork. The cutoff belongs in the workload
callback because only it knows whether an item represents a cheap node visit or
substantial work. Below the cutoff, call a dedicated serial kernel directly;
above it, keep recursive parallel calls on `Task.call`. `bench/tree_sum.zig`
demonstrates a depth-based cutoff without adding fields to the node layout. This
is the recursive counterpart of the flat APIs' `serial_threshold`.

For large or error-union payloads, prefer the non-copying join:

```zig
if (future.tryJoin(task)) {
    const value = future.result();
    // use value
} else {
    const value = task.call(Output, work, input);
    // use value
}
```

## Cancellation

```zig
var token = parz.CancelToken{};
try parz.parallelFor(
    &pool, rows, rows.len, .{ .min_chunk = 1, .cancel = &token }, Run.run,
);
```

Cancellation is cooperative. A cancelled flat call joins all started lane
futures before returning, so its input and scratch storage can be released
after the call unwinds.

Ordering rules:

- A callback error takes precedence over cancellation observed at that
  callback's exit.
- Chunk errors are selected in chunk-index order.
- Cancellation from a final successful callback or ordered reduction is
  observed before successful completion.
- Long `parallelForRange` callbacks can check their token during their own
  work; empty calls retain their no-op result.
- A cancelled nonempty serial call returns before constructing a temporary
  context.

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

## Correctness rules

- A `Future` is single-use. Reinitialize it with `.{}` before forking again;
  `join`/`tryJoin` intentionally leave the embedded job unlinked without
  resetting it so the local join path stays cheap.
- `initFork` initializes unused caller-owned storage, including `undefined`
  storage or a previously joined slot. Keep its address stable until joined; do
  not copy or return an enqueued `Future` by value.
- A `Future` must be joined on the worker that forked it. Nested tasks on that
  worker share its local tail. Join every fork before propagating an error that
  could unwind its storage.
- `fork` must be followed by `join`/`tryJoin`/`joinOrCall`; do not drop a forked
  future.
- `Task.call` is the only legal way to invoke a recursive parallel function.
- A worker context is owned by its lane. Do not share it across lanes or keep
  pointers into it after the callback returns.
- `deinit` requires all caller slots released and no active flat call.

## Serial fallback

Flat calls run serially when:

- the input is smaller than `serial_threshold`;
- the call cannot produce at least one chunk per lane;
- no caller slot is available;
- the target is single-threaded/WASM.

The fallback is a real code path, not an error path. It uses the same callback
contract, checks cancellation, and preserves ordered errors. Every fallback
change needs a zero-worker test.

## Determinism tests

Every scheduling change needs a determinism test covering 1..N workers,
repeated runs, and identical output. `src/parallel.zig` contains the current
suite, including ordered folds, range folds, capped lanes, and cancellation
precedence.
