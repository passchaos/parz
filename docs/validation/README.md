# Validation evidence index

Each directory is a self-contained report with a `README.md`, machine-readable
summaries where applicable, and raw logs, patches, or assembly snapshots. The
reports describe the code state and host at measurement time; re-run the
benchmarks to verify a claim on another machine.

## Scheduler and recursive fork/join

- [2026-11-11 scheduler controls](2026-11-11-scheduler-controls/README.md):
  default priority bitmap, idle metadata shortcut, optional power/fairness
  policies, E/P-core and cold/caller comparisons plus rejected candidates.

- [2026-11-11 benchmark gates](2026-11-11-benchmark-gates/README.md): paired
  primary benchmarks, symmetric 2D timing, default small-tree check and
  unchanged-core noise calibration.

| Report | Subject |
|---|---|
| [boundaries](2026-11-07-boundaries/README.md) | Balanced nonempty chunks, `min_chunk`, overflow-safe planning, saturating cancellation blocks |
| [cancellation-exit](2026-11-07-cancellation-exit/README.md) | Cancellation at the last successful callback and before successful reduction |
| [cold-paths](2026-11-07-cold-paths/README.md) | Rejected branch-hint and explicit-outlining experiments |
| [comparison-grain](2026-11-07-comparison-grain/README.md) | Cross-implementation recursive grain comparison |
| [future-init](2026-11-07-future-init/README.md) | Direct `initFork` initialization without a pending constructor |
| [future-storage](2026-11-07-future-storage/README.md) | Three storage-layout trials that emitted identical code |
| [join-simplification](2026-11-07-join-simplification/README.md) | Simplified `tryJoin`; removed pending specialization; rejected register-return experiments |
| [local-forward-links](2026-11-07-local-forward-links/README.md) | Rejected local-link assertion, alignment, and outlining experiments |
| [owner-tail](2026-11-07-owner-tail/README.md) | Nested tasks share the worker's local tail; reclaimed parents publish descendants |
| [recursive-grain](2026-11-07-recursive-grain/README.md) | 2047-node grain cutoff and small-tree parity |
| [serial-lane](2026-11-07-serial-lane/README.md) | Serial fallback context index, `kickstart`, and context destruction |
| [task-call](2026-11-07-task-call/README.md) | Rejected reuse of the calling `Task` |
| [worker-layout](2026-11-07-worker-layout/README.md) | Rejected padding experiments and the `check-worker-layout` diagnostic |
| [worker-limits](2026-11-07-worker-limits/README.md) | One future per lane and `max_workers` enforcement including the caller |

## Flat loops and folds

- [2026-11-11 flat controls](2026-11-11-flat-controls/README.md): explicit
  cost estimates, borrowed Worker contexts, reusable strict dispatch scratch,
  complete correctness gates and paired E/P-core regression controls.

| Report | Subject |
|---|---|
| [compute-grain](2026-11-07-compute-grain/README.md) | Dynamic compute grain tuning, stack-budget control, cross-library results |
| [infallible-value-dispatch](2026-11-07-infallible-value-dispatch/README.md) | Plain-value chunk results for uncancelled infallible folds |
| [range-fold](2026-11-07-range-fold/README.md) | Ordered range folds and SIMD flat reduction |
| [static-schedule](2026-11-07-static-schedule/README.md) | Opt-in contiguous static scheduling |

## Synchronization

- [2026-11-11 sync and arena](2026-11-11-sync-arena/README.md): uncounted
  stack, specialized sparse consumer sets, lazy NUMA arenas and retained
  rejection evidence for counterproductive default wake/backoff changes.

| Report | Subject |
|---|---|
| [cached-spsc](2026-11-07-cached-spsc/README.md) | Cached peer positions and cache-line-separated SPSC layout |
| [observer-accounting](2026-11-07-observer-accounting/README.md) | SPSC concurrent length observation order and capacity clamp |
| [spsc-batch](2026-11-07-spsc-batch/README.md) | SPSC slice transfers and publication amortization |
| [mpsc-batch](2026-11-07-mpsc-batch/README.md) | MPSC prefix reservation, publication, and tiny-queue fallback |
| [sharded-mpsc-batch](2026-11-07-sharded-mpsc-batch/README.md) | Sharded MPSC per-producer FIFO batch transfers |
| [blocking-batch](2026-11-07-blocking-batch/README.md) | BlockingQueue scalar vs. slice transfers, partial progress, cancellation |
| [treiber-batch](2026-11-07-treiber-batch/README.md) | TreiberStack slice publication and removal |
| [coordination-batch](2026-11-07-coordination-batch/README.md) | Batched semaphore and wait-group coordination |

## Platform and integration

| Report | Subject |
|---|---|
| [numa-allocator](2026-11-07-numa-allocator/README.md) | Linux VMA policies, fallback, required-policy failures, allocator lifetime |
| [spectra-integration-trial](2026-11-07-spectra-integration-trial/README.md) | Rejected Spectra ICC scheduler migration |
