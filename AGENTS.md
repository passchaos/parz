# AGENTS.md

## Project Mission

`parz` is the shared fine-grained parallelism library for the Project-Z stack.
Its job is to replace per-library `std.Thread.spawn → partition → join` code in
`imx`, `iris`, `veyra`, `vort`, `spectra`, `prism`, and `pangu`, and to give
`zui`, `horizon`, and `netz` a reusable bounded queue layer.

The scheduler core is derived from judofyr/spice (0BSD). Preserve the property
that made it worth adopting: **adding parallelism to a small workload must not
make it meaningfully slower**. Do not turn `parz` into a composable Rayon-style
iterator algebra; `imx` already chose direct callbacks for a reason.

## Boundaries

- Core depends only on `std` (Zig 0.16).
- Do not depend on `zio`, `iris`, `imx`, or any other sibling library.
- Keep the scheduler and the future `sync` module independent. The scheduler's
  local job list is not a general-purpose MPSC queue.
- Single-threaded and WASM targets must compile and fall back to serial.
- No hidden allocations in hot paths. Fork/join uses caller stack storage;
  flat loops use a bounded stack fallback allocator.
- Never execute user code while holding the pool mutex.

## Design invariants

- `fork` only appends to the owner's local list with plain stores: no
  atomics, no locks.
- Work leaves a local list only through heartbeat or explicit `kickstart`.
- `join` returning `null` means "caller must run it"; every code path must
  preserve that fallback.
- Results are combined in chunk-index order so output does not depend on
  scheduling.
- Error selection is by chunk index, not by completion order.
- Per-worker context is owned by the lane and must not be shared.
- `deinit` requires all caller slots released and no active flat call.

## Testing

- Unit tests live beside the implementation.
- Every scheduling change needs a determinism test (1..N workers, repeated
  runs, identical output).
- Every fallback change needs a zero-worker test.
- Validate with `zig build test` and `zig build test -Doptimize=ReleaseSafe`.
- Benchmark claims require fixed input, fixed CPU, and alternating serial /
  parallel runs. Report `serial_ns`, `parallel_ns`, and `speedup`, and always
  verify the checksum first.
- Small-input parity is a gate, not a nice-to-have: a 1000-node tree must not
  regress into a large slowdown.

## Current scope

Implemented: `Pool`, `Worker`, `Task`, `Future`, `parallelFor`,
`parallelForEach`, `parallelForRange`, `parallelFold`, `parallelReduce`,
per-worker context, error propagation, caller fallback, heartbeat pacing.

Not implemented yet: cancellation tokens, `sync` module (bounded MPSC/SPSC,
Treiber stack, semaphore, wait group), `parallelFor2D`/collapse, NUMA pinning.
