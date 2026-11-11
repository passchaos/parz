# Optimization progress

Objective: optimize every item in the 2026-11-11 implementation audit while
preserving correctness, serial fallback and measured performance. A candidate
lands only after fixed-input, fixed-CPU alternating baseline/candidate runs;
an observed regression requires confirmation and correction or withdrawal.
Changes must preserve chunk-index output/error order, per-lane context
ownership, bounded hot-path storage, plain-store fork and callbacks outside
the pool mutex. The 1000-node tree parity floor is 0.9x.

| Item | Status | Completion evidence required |
|---|---|---|
| Paired compute/flat/2D timing and default small-tree gate | Complete | [Paired calibration and all samples](validation/2026-11-11-benchmark-gates/README.md); default gate wired into check.sh |
| Light flat-work granularity | Pending | 4095/4096/8192/64K/1M light and heavy rows; zero-worker/cancellation/order tests |
| Explicit lane context reuse | Pending | All flat API shapes, nested scratch contract, no repeated context allocation, throughput/parity |
| Explicit reusable dispatch scratch | Pending | Stack/heap boundaries, result alignment, nested calls, allocation failures, order and timing |
| Idle heartbeat parking | Pending | Idle wake/CPU counts, first-job latency, held caller, shutdown, TSan and tree controls |
| Multiple-caller owner lookup/fairness | Pending | 1/2/4/8 caller latency and throughput, ready-owner lifecycle, deterministic repeats, TSan |
| BlockingQueue batch wake strategy | Pending | Multi producer/consumer and tiny queues, cancellation, no stranded waiters, timings |
| Treiber optional count | Pending | Scalar/batch/reuse semantics, TSan, counted/uncounted timings |
| MPSC contention/backoff | Pending | Contention/tiny queue rows and repeated FIFO; retain only verified improvement |
| Sharded MPSC empty-shard polling | Pending | Sparse/dense shard rows and per-producer FIFO; retain only verified improvement |
| NUMA context locality / arena path | Pending | First-touch contract and integration checks; honest single-node limits |
| Semantic parallel/core source modules | Pending | Public API compatibility, tests beside implementations, unchanged performance |
| Final correctness/platform/performance gates and Git sync | Pending | Debug, ReleaseSafe, TSan, serial, WASM/native compile checks, paired evidence, commit/push |

The baseline is commit `04ab4e1`. Historical rejected worker padding, payload
layouts, 8 KiB fixed-stack expansion and forced outlining remain rejected
unless new evidence justifies revisiting them. Dynamic remains the default
until mixed-cost and heterogeneous CPU rows support a change. A rejected
experiment must retain its patch, input/CPU configuration and measured reason.
