Nonempty flat calls now observe cancellation from their last successful work
callback and from final ordered reduction. Previously the final block or
chunk could cancel its token and return successfully because no later entry
check ran. The [callback baseline](callback-before.log) demonstrates a
cancelled final callback returning `void`; the
[reduction baseline](reduction-before.log) demonstrates a successful result
with its token already cancelled. Baseline is commit `bed8caa`.

Range execution checks after a successful callback. Fallible and cancellable
infallible chunk folds check after their final block. Serial range/fold
fallbacks check after successful work too. Parallel calls check after
successful dispatch and reduction, covering cancellation during the caller's
last combine operation. Index-based loops keep their 4096-item checkpoints;
opaque range callbacks can check the token during their own work.

Callback errors propagate before the new exit check. Dispatch still joins all
lane futures and selects chunk errors by index before reaching the final
success checkpoint. An earlier chunk's error therefore wins over a later
chunk's cancellation, regardless of which finishes first. Cancellation does
not preempt user callbacks or undo work. A cancellation request racing after
the last checkpoint does not retroactively change completed work. Empty calls
retain their no-op result.

The token module documentation now states the actual lifetime contract:
started lanes are drained before return. Its old wording incorrectly said
that a cancelled call returned without waiting for already-running chunks.
Caller-owned input and scratch storage can be released after the call
unwinds, and the token can then be reset.

New tests cover final-callback cancellation in `parallelFor`,
`parallelForRange`, `parallelFor2D`, fallible fold and infallible fold across
worker counts 0–4. They exercise one dispatched chunk, threshold-based serial
fallback, and caller-slot exhaustion. Final reduction tests cover fallible
fold and the infallible reduce alias. Error tests cover cancellation and
failure in the same callback, an earlier failing chunk followed by a
cancelling chunk, and serial fallback.

The concurrent test makes chunk one cancel and finish while chunk zero is
still inside a delayed callback. It repeats both successful and failing
chunk-zero cases ten times, checks that both callbacks finished before the
call returned, verifies caller-slot release, and requires the lower-index
error when chunk zero fails after chunk one's cancellation result is ready.

The no-token infallible value path from `bed8caa` is retained. It has no added
token load or dispatch allocation. A matched benchmark uses fixed input,
caller CPU 31, workers 24–30 and nine alternating serial/parallel and token
mode measurements per process. Warmups and every timed result are verified.
Five outer rounds alternate baseline/candidate order. Both revisions use the
same benchmark source and 64-byte-aligned serial function. Table entries are
medians of process medians; speedup is the median reported ratio.

| Case | Token | Revision | serial_ns | parallel_ns | speedup | Allocations |
|---|---|---|---:|---:|---:|---:|
| Scan 4096, 8 lanes | none | baseline | 1,084 | 20,583 | 0.053 | 0 |
| Scan 4096, 8 lanes | none | exit checks | 1,074 | 20,811 | 0.052 | 0 |
| Scan 4096, 8 lanes | present | baseline | 1,087 | 20,551 | 0.052 | 1 |
| Scan 4096, 8 lanes | present | exit checks | 1,076 | 22,114 | 0.048 | 1 |
| Compute 1,000,003, 8 lanes | none | baseline | 109,311,209 | 14,115,743 | 7.744 | 0 |
| Compute 1,000,003, 8 lanes | none | exit checks | 109,323,241 | 14,108,151 | 7.749 | 0 |
| Compute 1,000,003, 8 lanes | present | baseline | 109,316,431 | 14,149,021 | 7.725 | 1 |
| Compute 1,000,003, 8 lanes | present | exit checks | 109,319,700 | 14,114,635 | 7.746 | 1 |
| Scan 4096, zero workers | none | baseline | 1,062 | 1,175 | 0.901 | 0 |
| Scan 4096, zero workers | none | exit checks | 1,064 | 1,167 | 0.908 | 0 |
| Scan 4096, zero workers | present | baseline | 1,057 | 1,916 | 0.552 | 0 |
| Scan 4096, zero workers | present | exit checks | 1,067 | 1,959 | 0.545 | 0 |

The small token-enabled forced-dispatch scan pays about 7.6% extra time in
this set for exit observations; large compute and no-token times stay close.
This is a correctness change, with no general throughput gain claimed. The
host has other active workloads. [Raw comparison](fold-comparison.json),
[samples](fold-samples.log) and [environment](environment.json) preserve the
measured scope and provenance.

[Debug](debug.log) and [ReleaseSafe](release-safe.log) each passed 79 library
tests and three integration tests. [TSan](tsan.log) passed all 79 library
tests. [Single-threaded](single-threaded.log) passed 63 with 16 skips. The
final test instances compiled for [WASM/WASI](wasm32-wasi.log),
[Windows GNU](x86_64-windows-gnu.log), [aarch64 macOS](aarch64-macos.log) and
[x86_64 Linux musl](x86_64-linux-musl.log).

The scheduler core is unchanged. The [strict 1000-node tree gate](strict-parity.log)
remains failing: `serial_ns=1647`, `parallel_ns=3519`, `speedup=0.468`.
The [million-node control](large-tree-control.log) passes with
`serial_ns=1763123`, `parallel_ns=805724`, `speedup=2.188`. The overall goal
remains active; this cancellation fix does not establish recursive small-task
parity or theoretical optimality.
