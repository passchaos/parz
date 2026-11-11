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
| Light flat-work granularity | Complete | [Cost guard with E/P-core rows and unknown/heavy controls](validation/2026-11-11-flat-controls/README.md); defaults preserved |
| Explicit lane context reuse | Complete | All ten API shapes, nested parent futures, zero-worker/error/cancel coverage, zero repeated context allocations |
| Explicit reusable dispatch scratch | Complete | Aligned noncommutative results, strict two-stage OOM, nested/cancel drain tests and zero measured dispatch allocations |
| Idle heartbeat parking | Complete | [Default idle shortcut and explicit parking evidence](validation/2026-11-11-scheduler-controls/README.md); automatic parking rejected to preserve cold latency |
| Multiple-caller owner lookup/fairness | Complete | Default priority bitmap, optional round robin, 1/2/4/8 caller controls and deterministic/state-exhaustion contracts |
| BlockingQueue batch wake strategy | Complete | [Trial evidence](validation/2026-11-11-sync-arena/README.md): waiter tracking withdrawn for repeated small slowdowns; original hot path retained, cancellation/no-stranding coverage added |
| Treiber optional count | Complete | Uncounted variant verified with mixed scalar/batch/reuse/TSan; default counted retry preserved after regression trial |
| MPSC contention/backoff | Complete | Unconditional and batch-only pause trials withdrawn; bounded batch/CAS protocol preserved with all evidence |
| Sharded MPSC empty-shard polling | Complete | Compile-time known-producer view eliminates unused-shard scans; default dense path preserved and FIFO checked |
| NUMA context locality / arena path | Complete | Lazy first-touch and owned-lane capacity reuse integration; measured VMA/arena comparison with explicit single-node scope |
| Semantic parallel/core source modules | Pending | Public API compatibility, tests beside implementations, unchanged performance |
| Final correctness/platform/performance gates and Git sync | Pending | Debug, ReleaseSafe, TSan, serial, WASM/native compile checks, paired evidence, commit/push |

The baseline is commit `04ab4e1`. Historical rejected worker padding, payload
layouts, 8 KiB fixed-stack expansion and forced outlining remain rejected
unless new evidence justifies revisiting them. Dynamic remains the default
until mixed-cost and heterogeneous CPU rows support a change. A rejected
experiment must retain its patch, input/CPU configuration and measured reason.
