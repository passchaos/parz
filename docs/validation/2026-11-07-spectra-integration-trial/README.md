# Rejected Spectra ICC scheduler migration

This experiment attempted the first real Project-Z downstream migration from
per-call `std.Thread.spawn` partition/join to a reusable `parz.Pool`. The
target was Spectra's injected ICC RGB context scheduler, not Spectra's core
library: the callback already receives a validated disjoint-range job and an
explicit worker cap.

The candidate created one `Pool(void)` outside timed calls, disabled heartbeat,
reserved one caller lane, and dispatched `job.runRange` with at most four
lanes. Exact four-chunk static scheduling, 64-chunk dynamic scheduling,
caller-first span rotation and SMT-aware worker pinning were tested. The
Spectra and parz production trees were restored after rejection; no dependency
or scheduler change remains.

## Correctness

Spectra commit `a565f08` was tested against the pinned Little CMS commit
`35cef877`. The authoritative `check-sequence-threaded` gate passed with four
workers and 65,536 pixels:

```text
max_abs=0.000114545226 mean_abs=1.79004929e-06
```

The candidate selected the scheduler exactly once, produced byte-identical
output relative to Spectra's serial reference, and stayed inside the existing
LCMS differential threshold. This proves functional compatibility, but not a
performance win.

## Same-binary performance decision

To eliminate code-layout differences, a temporary single executable contained
both the original spawn/join callback and the parz callback and selected one by
argument. Processes were restricted to CPUs 24-27. Five outer rounds
alternated mode order; each process performed two warmups and the listed timed
iterations. [`results.json`](results.json) retains every elapsed value.

| Pixels/call | Timed calls | spawn/join median | parz median | parz change |
|---:|---:|---:|---:|---:|
| 65,536 | 20 | 89.925 ms | 86.648 ms | 3.64% faster |
| 262,144 | 8 | 138.222 ms | 136.472 ms | 1.27% faster |
| 524,288 | 4 | 133.645 ms | 136.170 ms | 1.89% slower |
| 1,048,576 | 4 | 264.941 ms | 272.129 ms | 2.71% slower |

The reusable pool wins when thread creation is a material fraction of each
call, but loses on long transforms. The crossover depends on transform cost,
not only pixel count, so a hardcoded size threshold would be unsound.

Further controls did not fix the large-input regression. Dynamic 64-chunk
claiming improved parz by about 0.33% over four static spans but remained
slower than spawn/join. Pinning background workers changed the median from
273.088 ms to 273.614 ms. Rotating static lane indices so the caller processed
the first span was neutral. Separate-binary results reached the same decision.

## Decision

The migration was rejected because Spectra requires performance claims to
hold for the named operation and fixed CPU evidence. Keeping both schedulers
behind a pixel threshold would preserve the direct spawn implementation,
increase dependency/API complexity, and encode a transform-specific crossover
as general policy. A future integration should target a persistent workload
whose task cost is known at the application boundary or provide an explicit
caller policy rather than guessing from item count.

This rejected result is concrete progress toward the overall goal: it proves
where parz is advantageous, rules out pinning/grain/mapping retries for this
operation, and prevents landing a downstream regression merely to claim
adoption.
