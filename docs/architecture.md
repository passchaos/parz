# Architecture

`parz` has two independent layers:

- the scheduler and flat-parallel APIs (`core.zig`, `job.zig`, `parallel.zig`,
  `cancel.zig`, `affinity.zig`);
- the standalone synchronization module (`sync/`).

`numa.zig` is an optional allocator and is independent of both.

## Scheduler lineage

The scheduler core is derived from [judofyr/spice](https://github.com/judofyr/spice)
(0BSD, Copyright (c) 2024 Magnus Holm). The project-specific additions are the
flat loop/fold APIs, deterministic ordered combination, per-worker context,
bounded execute states, caller-slot accounting, cancellation, Linux affinity,
and the synchronization module.

The property worth preserving from Spice is simple: adding parallelism to a
small workload must not make it meaningfully slower. That is why the scheduler
does not adopt a composable Rayon-style iterator algebra and why flat APIs take
direct callbacks.

## Source layout

| File | Responsibility |
|---|---|
| `src/root.zig` | Public surface and module re-exports |
| `src/core.zig` | `Pool`, `Worker`, `Task`, `Future`, caller slots, execute states |
| `src/job.zig` | Intrusive local/shared job list and tagged job state |
| `src/parallel.zig` | Flat loop/fold planning, dispatch, serial fallbacks |
| `src/cancel.zig` | `CancelToken` |
| `src/affinity.zig` | Linux CPU pinning and NUMA placement helpers |
| `src/sync.zig` | Re-exports for the standalone sync module |
| `src/sync/*.zig` | Queue, stack, semaphore, and wait-group implementations |
| `src/numa.zig` | Optional NUMA-aware allocator |

## Local-first scheduling

Each worker owns a truly local intrusive job list:

- `fork` appends to the owner's local list with plain stores: no atomics, no
  locks, no allocation.
- Work leaves the local list only through:
  - a heartbeat firing, or
  - an explicit `kickstart` from a flat loop.
- The heartbeat only sets a per-worker flag. The owner checks that flag at the
  next `Task.call`, so the call hot path is a single atomic load.
- A heartbeat shares at most a few jobs and retains the owner's local tail, so
  the owner always keeps work to run even if every idle worker picks something
  up.
- Idle workers consume jobs from shared lists. They do not steal from another
  worker's local list. Work stealing is intentionally out of scope.

Tiny workloads usually finish before the first heartbeat and stay on the
caller. Recursive algorithms should also stop creating `Future`s below a useful
grain size and call a serial kernel directly for those subtrees. Heartbeat
pacing avoids worker wake-ups, but it cannot remove local Future bookkeeping.
The tree gate uses a 2047-node leaf bound and keeps 1000-node traversal at
serial parity while retaining parallelism above that bound.

## Fork/join protocol

`Future(Ctx, Input, Output)` embeds a `Job` and a payload buffer. The input and
output never coexist: the input is consumed before a background handler writes
the output, and local execution copies the input before overwriting it.

`join` has one mandatory fallback:

- `tryJoin` returns `true` when another lane executed the job and `result()` is
  valid.
- `tryJoin` returns `false` when the job is still local, pending, or was
  reclaimed. The caller must then execute it.
- `join` materializes this as `?Output`: `null` means "caller must run it".
- `joinOrCall` packages the common case.

Every code path must preserve the fallback. It is what makes zero-worker,
single-threaded, WASM, exhausted-execute-state, and spawn-failure
configurations safe.

Additional rules:

- A `Future` is single-use. Reinitialize it with `.{}` before forking again;
  `join`/`tryJoin` intentionally leave the embedded job unlinked without
  resetting it so the local join path stays cheap.
- `initFork` initializes unused caller-owned storage, including `undefined`
  storage or a previously joined slot. Keep its address stable until joined; do
  not copy or return an enqueued `Future` by value.
- A `Future` must be joined on the worker that forked it. Nested tasks on that
  worker share its local tail. Join every fork before propagating an error that
  could unwind its storage.
- `fork` must be followed by `join`/`tryJoin`/`joinOrCall`; do not drop a
  forked future.
- `Task.call` is the only legal way to invoke a recursive parallel function;
  direct calls bypass heartbeat checks and the caller-fallback protocol.

Nested `Task` values use their worker's current local tail. Reclaiming a shared
parent future therefore preserves access to newly forked descendant jobs. The
retained local tail also permits a local join without atomic state checks.
See [the owner-tail validation report](validation/2026-11-07-owner-tail/README.md).

## Caller slots and worker lifecycle

- Background workers are registered during `start`. Caller threads claim one of
  a fixed number of caller slots; a caller with no slot runs the serial
  fallback instead.
- The caller executes its own flat lane immediately before waiting for
  background lanes.
- `Pool.parallelWorkerCount()` is `spawned_background + 1` and is the lane
  budget used by flat planning.
- `deinit` requires all caller slots released and no active flat call.
- A worker never executes user code while the pool mutex is held. The mutex
  protects shared lists and execute-state allocation only.

## Execute states

Out-of-line execution needs a small state object to carry the completion event.
`max_execute_states` bounds these objects. When the pool is exhausted:

- work is not handed to another lane;
- it stays local;
- `join` returns `false` and the caller executes it.

This keeps the fallback total without allocating in the hot path.

## Flat call model

A flat call (`parallelFor`, `parallelForRange`, folds) does the following:

1. Return immediately for empty input.
2. Decide whether to run serially (item threshold, optional estimated-work
   guard, or fewer planned chunks than lanes). Pool calls construct a temporary
   context; explicit Worker calls borrow that lane's existing context.
3. Use the supplied worker or claim a caller slot. If none is available, run
   the serial path. Borrowed workers are never released by the flat call.
4. Plan balanced contiguous chunks and lanes.
5. Dispatch one future per lane, then join every lane before ordered
   reduction.
6. Check cancellation before successful completion.

Dispatch storage uses a 4 KiB stack fallback buffer; overflow goes to the
pool's allocator. Optional caller-owned `ParallelScratch` provides strict
reusable storage for results/futures; nested use takes a separate bounded
stack fallback. No per-item allocation occurs. See the
[parallel API guide](parallel-api.md) for capacity and ownership rules.

### Chunk planning

`min_chunk`, `max_chunks`, and `chunks_per_worker` determine the chunk count.
Chunks are contiguous, nonempty, balanced (lengths differ by at most one), and
respect `min_chunk` unless the whole input is smaller. Range planning supports
counts up to `maxInt(usize)` without overflowing `index * size` intermediates.

### Dynamic and static lanes

- **Dynamic** is the default. Lanes claim disjoint chunk indices from a shared
  atomic cursor, so fast lanes take more work. This is preferable for irregular
  callbacks and heterogeneous CPUs.
- **Static** assigns each dispatch lane one contiguous span of chunk indices.
  It removes cursor contention and improves locality for uniform work. A
  future may execute on any available worker, so static is a
  partition/locality guarantee, not worker-affinity or context-index binding.
  No work is redistributed from a slow static span after execution begins.

### Determinism

Results are stored by chunk index. Ordered combination happens after all lanes
join, so output does not depend on which worker ran which chunk. Errors are
selected by chunk index, not completion order. Floating-point addition can
still change with chunk boundaries because it is not associative.

### `max_workers`

`ParallelOptions.max_workers` caps simultaneous lanes for that call, including
the caller. A value of 1 keeps chunk callbacks on the caller. Each lane still
claims chunks dynamically unless static scheduling is selected. Chunk results
and errors retain chunk-index ordering.

## Cancellation

Cancellation is cooperative and uses a single atomic flag. Nonempty flat calls
check it at chunk entry/exit, every 4096 items in index loops, and before
successful completion. A cancelled call joins all started lane futures before
returning, so caller-owned input and scratch storage can be released after the
call unwinds.

A callback error takes precedence over cancellation observed at that callback's
exit; chunk errors are selected in chunk-index order. Cancellation from a final
successful callback or ordered reduction is observed before successful
completion. Long range callbacks can check their token during their own work.
See [docs/parallel-api.md](parallel-api.md) for the full ordering rules.

## Design invariants

- `fork` only appends to the owner's local list with plain stores: no atomics,
  no locks.
- Work leaves a local list only through heartbeat or explicit `kickstart`.
- `join` returning `null` means "caller must run it"; every code path preserves
  that fallback.
- Results are combined in chunk-index order so output does not depend on
  scheduling.
- Error selection is by chunk index, not completion order.
- Per-worker context is owned by the lane and must not be shared.
- `deinit` requires all caller slots released and no active flat call.
- Core depends only on `std`; the scheduler and `sync` remain independent.
- Single-threaded and WASM targets compile and fall back to serial.
- No hidden allocations in hot paths.

## Implementation notes

The current implementation keeps several deliberately conservative choices.
Each was checked against fixed-CPU measurements and the alternatives were
rejected:

- **Compact worker layout.** Padding experiments did not establish a stable
  benefit. `zig build check-worker-layout` reports actual field offsets, worker
  size, and worker/context alignment for future layout work. See
  [worker layout](validation/2026-11-07-worker-layout/README.md).
- **Byte-array `Future` payload.** Three storage trials emitted identical
  executable code, so the byte-array payload remains. See
  [Future storage](validation/2026-11-07-future-storage/README.md).
- **Direct `initFork` initialization.** `initFork` bypasses the pending-value
  constructor when forking immediately. See
  [direct initialization evidence](validation/2026-11-07-future-init/README.md).
- **Automatic inlining for cold paths.** Branch hints emitted identical code and
  explicit outlining regressed the P-core large-tree control. See
  [cold-path layout trials](validation/2026-11-07-cold-paths/README.md).
- **Simplified local join.** The obsolete pending-future specialization and
  repeated local-tail checks were removed. See
  [join simplification](validation/2026-11-07-join-simplification/README.md).
- **Owner local tail.** Nested `Task` values use their worker's current local
  tail, so reclaiming a shared parent future preserves descendant forks. See
  [owner-tail validation](validation/2026-11-07-owner-tail/README.md).

## Known limits

- No work stealing.
- Linux worker pinning captures the allowed CPU set during `Pool.init` and
  selects one allowed sibling per physical core. Automatic worker count
  reserves one selected CPU for the caller; explicit counts are capped by the
  selected CPU list. The caller keeps its existing affinity.
- `Options.numa_node` and `Options.auto_numa` set the background workers' thread
  policy. `NumaAllocator` sets policy on each Linux allocation before first
  touch; pass its allocator to `Pool.init` to cover metadata and per-worker
  arenas.
- `deinit` requires all caller slots to be released and no flat-parallel call
  to be active.
