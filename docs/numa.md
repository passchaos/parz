# NUMA support

Pool context constructors run before worker pinning and thread NUMA policy.
Keep lane arenas lazy: construct `std.heap.ArenaAllocator` without allocating,
then first allocate/touch scratch inside the worker callback. That work runs
after worker placement. A retained arena amortizes Linux mapping/mbind calls;
reset it only after all users of its allocations finish. Static scheduling
guarantees contiguous chunk spans, not the same worker context on every call.
Use an explicitly owned Worker when verifying lane-specific retained reuse.

`bench-numa-arena` compares per-object VMA allocations with retained arena
allocation on one fixed CPU. Its speedup is an allocation-pattern comparison,
not parallel scaling or a claim about cross-node hardware. Multi-node placement
requires execution on a multi-node host; current evidence is single-node.

`parz` exposes two independent NUMA controls:

1. `Pool` options that set the background workers' Linux memory policy.
2. `NumaAllocator`, an optional allocator that applies a VMA policy to each
   allocation before first touch.

The caller thread is not affected by either control.

## Pool worker policy

```zig
var pool = try parz.Pool(void).init(allocator, io, .{
    .pin_workers = true,
    .numa_node = 0,      // MPOL_PREFERRED node for background workers
    .auto_numa = false,  // when numa_node is null, use the pinned CPU's node
});
```

- `Options.numa_node` sets a fixed `MPOL_PREFERRED` node for background
  workers.
- `Options.auto_numa` uses the node of the CPU the worker is currently running
  on (Linux `getcpu`). Best combined with `pin_workers = true`.
- Unsupported targets and failed policy requests are no-ops for the pool.

## NumaAllocator

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

Pass its allocator to `Pool.init` to cover pool metadata and per-worker
contexts. Use an arena on top for fine-grained allocations: the allocator uses
separate anonymous page mappings on Linux, and an arena amortizes page and
syscall overhead.

### Policies

| Policy | Node list | Linux behavior |
|---|---|---|
| `.local` | Must be empty | `MPOL_LOCAL` |
| `.preferred` | Exactly one node | `MPOL_PREFERRED` |
| `.bind` | Nonempty set | `MPOL_BIND` |
| `.interleave` | Nonempty set | `MPOL_INTERLEAVE` |

Node IDs are `u16`. Node masks are copied during initialization, so the input
slice does not need to outlive `init`. Masks support all `u16` IDs.

### Fallback and failure

- Other targets use the supplied fallback allocator.
- `require_policy = false` (default): if the Linux policy request fails, the
  allocation still succeeds through the fallback path.
- `require_policy = true`: initialization fails with `UnsupportedPlatform` on
  non-Linux targets, and a failed Linux policy request is reported as
  `error.OutOfMemory` from the allocation.

Allocation provenance stays fixed for the allocator's lifetime, including when
`mbind` is unavailable. Resizing or remapping never rebinds: a failed rebind
could not restore the old pointer.

### Lifetime

- The allocator instance must remain at the same address while its interface is
  used.
- It must outlive every allocation made through it.
- `deinit` asserts that `live_allocations == 0`.

### Diagnostics

```zig
const status = numa.stats();
// status.native_supported
// status.live_allocations
// status.policy_applied
// status.policy_fallbacks
// status.policy_failures
// status.last_errno
```

Individual counters are approximate while other lanes allocate or free.
`policy_applied + policy_fallbacks` counts successful allocations.
`last_errno` is the most recently observed Linux errno, or zero if no failure
was observed. Policy acceptance describes VMA configuration; physical placement
also depends on first-touch and the nodes permitted by the host.

### Check command

```sh
zig build check-numa -- preferred 0
zig build check-numa -- preferred 65535 require
```

The check validates policy arguments, fallback behavior, allocator lifetime,
and VMA policy persistence across reallocation.

Evidence is recorded in
[the NUMA allocator report](validation/2026-11-07-numa-allocator/README.md).
