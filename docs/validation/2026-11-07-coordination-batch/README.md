# Batched semaphore and wait-group coordination

`Semaphore` now provides `init(permits)`, `postMany`, `waitMany`, and
`waitManyUncancelable`. Multi-permit operations update the count under one
mutex acquisition. Zero requests return immediately and one-permit requests
inline the scalar path.

Waiters requesting more than one permit are counted while holding the same
mutex. Whenever permits remain and a wide waiter exists, the wrapper
broadcasts; otherwise it preserves the scalar signal chain used by
`std.Io.Semaphore`. This prevents an ineligible large waiter from consuming
the only signal while a smaller request could proceed. Cancellation removes a
registered wide waiter after the condition wait reacquires the mutex.

`WaitGroup.doneMany(n)` completes several members with one lock and broadcasts
when the count reaches zero. `waitCancelable` adds the cancelable counterpart
to the existing uncancelable `wait`; zero completion is a no-op and scalar
`done` remains an inline one-member wrapper.

Tests cover initial permits, zero/scalar/batch operations, four scalar waiters
released by one batch, a four-permit waiter, mixed one/four-permit waiters that
must not strand an available permit, two cancelable WaitGroup waiters, partial
`doneMany` calls and zero completion. All concurrency paths pass TSan.

## Fixed-CPU semaphore benchmark

One producer is pinned to CPU 24 and one consumer to CPU 26. Thread startup and
affinity are excluded. Scalar paths transfer one million permits one at a
time; batch paths use identical totals and explicit batch sizes. The final
permit count is checked after every warmup and measurement. Nine samples
alternate scalar/batch and serial/parallel order. [`results.json`](results.json)
retains raw observations and source hashes.

| Case | API | serial_ns | parallel_ns | speedup | Scalar/batch parallel ratio |
|---|---|---:|---:|---:|---:|
| 1M permits, batch 64 | scalar | 24,886,641 | 77,753,569 | 0.320 | — |
| Same | batch | 482,514 | 1,456,733 | 0.331 | 53.375x |
| 1M permits, batch 256 | scalar | 24,944,657 | 82,030,182 | 0.304 | — |
| Same | batch | 121,283 | 477,237 | 0.254 | 171.886x |
| 100K permits, batch 1 | scalar | 2,519,220 | 8,894,621 | 0.283 | — |
| Same | batch | 2,536,657 | 8,937,130 | 0.284 | 0.995x |

Batch 64 removes 98.1% of parallel coordination time; batch 256 removes
99.4%. The one-permit wrapper stays within about 0.5% of scalar, satisfying
the small-operation parity gate.

```sh
zig build bench-semaphore-batch -Doptimize=ReleaseFast -- \
  1000000 64 24 26 9
```

## Verification

- Debug and ReleaseSafe: 94 library tests plus three integration tests passed.
- ThreadSanitizer: all 94 library tests passed.
- Single-threaded ReleaseSafe: 72 passed and 22 thread/platform tests skipped.
- Test instances compiled for WASM/WASI atomics, Windows GNU, aarch64 macOS,
  and x86_64 musl Linux.
- The final ReleaseFast benchmark and smoke completed with zero remaining
  permits.

The wrapper intentionally relies on the Zig 0.16 `std.Io.Semaphore` mutex,
condition and permit fields. These results cover that implementation and one
topology; they do not imply the same ratios for kernel-backed semaphores.
