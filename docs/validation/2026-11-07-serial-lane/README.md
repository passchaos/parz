Serial flat fallbacks now use the index supplied to their context constructor,
skip temporary context construction when already cancelled, and keep inactive
workers' forked jobs local when `kickstart` is requested. These changes repair
three verified fallback boundary problems. Baseline is commit `bfb3596`.

Temporary contexts are constructed with `pool.worker_count`, but the worker
passed to callbacks previously had index zero. The
[index regression](index-before.log) failed with `expected 1, found 0` even
with zero background workers. Serial range, fallible fold and infallible fold
now set that worker index to `pool.worker_count`. This is outside the
registered lane range and is reserved for temporary contexts; separate
temporary calls still own distinct context objects. Tests cover worker counts
0–4, threshold fallback and caller-slot exhaustion.

Previously an already-cancelled serial call could construct a context and
return its constructor error before checking the token. The
[cancel regression](cancel-before.log) observed
`UnexpectedContextConstruction` instead of `Cancelled`. Each serial helper
now checks cancellation before context construction. Checks after construction
or at block entry remain, so cancellation raised by a successful constructor
is still observed before work. A pre-cancelled call does not construct or
destroy a temporary context.

An inactive temporary worker is not registered in the pool and its shared
tail is not initialized for publication. The independent
[kickstart fixture](serial-kick-fixture.zig) [crashed before the fix](kick-before.log)
inside `Job.pushShared`. Sharing now checks `owner.active` under the pool
mutex before accessing local/shared links. An inactive worker therefore keeps
the jobs local and preserves the `join` caller fallback. The
[same fixture passes after the fix](kick-after.log). The implementation test
repeats fork, kickstart, ordered joins and quiescence checks ten times for
worker counts 0–4 and both serial fallback modes. Registered active workers
retain the existing heartbeat and explicit kickstart behavior.

The [cancelled-context benchmark](cancelled-context-bench.zig) gives the
context constructor an explicit 64 KiB allocation and initialization. Input
count is 64, the token is already cancelled, and the pool has zero background
workers. Both paths return a verified zero result for cancellation. The serial
reference checks the token directly; the API path invokes the actual
`parallelForRange` serial fallback. Both are measured in 1024-call batches,
with memory compiler barriers preventing work from leaving the loops. A
counting allocator records context allocations and bytes; setup is excluded.

Every process warms both paths and verifies every result, alternates
serial/parallel order over nine measurements, and reports medians. Five
outer rounds alternate baseline/candidate process order. The caller is pinned
to CPU 31. [Environment](environment.json) records Zig 0.16.0, hashes and
placement. [Samples](cancelled-context-batch-samples.log) and
[comparison](cancelled-context-batch-comparison.json) retain all observations.
The table gives medians of process medians and times for a batch of 1024 calls.

| Revision | serial_ns | parallel_ns | speedup | API calls including warmup | Context allocations | Allocated bytes |
|---|---:|---:|---:|---:|---:|---:|
| baseline | 817 | 29,087,317 | 0.000 | 10,240 | 10,240 | 671,088,640 |
| serial lane fix | 543 | 802 | 0.677 | 10,240 | 0 | 0 |

The large difference comes from skipping the explicit context allocation and
initialization. It is evidence for this already-cancelled workload, not a
general scheduler speedup. An earlier per-call timing diagnostic rounded the
sub-nanosecond reference and fixed API observations to integer zero; those
[initial samples](cancelled-context-samples.log) and
[results](cancelled-context-comparison.json) are retained, and batch timing is
used for the table above.

Normal callback errors, temporary context mutation/destruction and active
worker scheduling retain their previous behavior. The full unit suite includes
the mutated-context lifetime test, cancellation/error-order tests, ordered
folds and recursive determinism. The fixed
[fold control](fold-control.log) completes with verified checksum and keeps
zero dispatch allocations for the uncancelled infallible path.
