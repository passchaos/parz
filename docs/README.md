# parz documentation

Start with the [README](../README.md) for the overview and quick start.

## Guides

| Document | Contents |
|---|---|
| [architecture.md](architecture.md) | Scheduler model, fork/join protocol, caller slots, execute states, flat dispatch, invariants, limits |
| [parallel-api.md](parallel-api.md) | Flat loop/fold/range APIs, options, cancellation, per-worker context, correctness rules |
| [sync.md](sync.md) | SPSC/MPSC/sharded/blocking queues, Treiber stack, semaphore, wait group, batch semantics |
| [benchmarks.md](benchmarks.md) | Build/test gates, benchmark arguments, fixed-CPU methodology, parity gate, performance snapshot |
| [numa.md](numa.md) | Worker NUMA policy, `NumaAllocator` policies, lifetime, diagnostics |
| [OPTIMIZATION_BACKLOG.md](OPTIMIZATION_BACKLOG.md) | Current optimization work, required gates and evidence |

## Validation evidence

Fixed-CPU benchmark reports and raw logs live under `docs/validation/`. Each
report directory contains:

- `README.md` — claim, method, fixed CPU set, before/after comparison, and
  rejected alternatives;
- `results.json` or `*-comparison.json` — machine-readable summaries;
- raw logs, patches, and assembly snapshots where relevant.

The full index is in [validation/README.md](validation/README.md).

Validation reports are historical evidence. They describe the code state and
host at the time of measurement; use the current tests and benchmarks to
re-verify a claim on another machine.
