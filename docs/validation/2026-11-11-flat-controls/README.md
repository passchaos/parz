# Flat cost guard, borrowed worker context and explicit dispatch scratch

Flat APIs now accept a Pool or an explicitly owned Worker. Worker calls use
their current context even when serial and never claim/release another caller
slot. Pool fallback context/index semantics are preserved. An optional item
cost estimate adds a saturating minimum-work guard; zero preserves defaults,
and serial_threshold=0 still forces dispatch. ParallelScratch provides strict
caller-owned reusable result/Future storage, returns OOM before callbacks when
too small, and protects active outer storage by using the existing bounded
stack fallback for nested calls. Public rules are in
[parallel-api.md](../../parallel-api.md).

The scheduler core, chunk plans, result/error ordering and dynamic default
are unchanged. The new executor/scratch modules keep ownership code and its
tests together; the remaining parallel/core structure work is still pending.

Validation:

- [Debug](debug.log) and [ReleaseSafe](release-safe.log): 103 library plus
  3 integration tests, all passed.
- [TSan](tsan.log): 103 passed, including concurrent nested use of outer
  scratch, cancellation drain and borrowed-worker nesting.
- [Single threaded](serial.log): 81 passed, 22 skipped, zero failed.
- [WASM with atomics](wasm.log): compile passed; the successful command emits
  no output, so the log is empty.
- Tests cover all ten flat entry points, zero–four background workers,
  repeated dynamic/static scheduling, retained parent futures, explicit-worker
  OOM ownership, context allocation prohibition after startup, 128-byte-aligned
  noncommutative fold results, strict result/Future allocation failures,
  callback errors, cancellation and reset after draining.

Each benchmark uses the same current harness with baseline core `04ab4e1` and
candidate core, Zig 0.16.0 ReleaseFast. E-core placement is caller 31/workers
24–30; P-core placement is caller 14/workers 0,2,4,6,8,10,12. Both paths warm
up and every result is checked. There are 21 alternating inner pairs for flat
rows (1000 repeats per pair for context); outer revision order alternates.
Main controls use 9 pairs for tree/compute/2D. Machine load is not isolated.

Representative E-core five-round controls:

| Row | Baseline parallel_ns | Candidate parallel_ns | Candidate serial_ns | Candidate speedup |
|---|---:|---:|---:|---:|
| Cheap 4095 | 1102 | 1107 | 1095 | 0.990 |
| Cheap 4096 | 14802 | 1107 | 1095 | 0.989 |
| Cheap 8192 | 15208 | 2171 | 2161 | 0.995 |
| Cheap 65536 | 15696 | 15524 | 17059 | 1.098 |
| Context 16 | 1733 | 7 | 3 | 0.429 |
| Scratch 1M | 78097 | 77483 | 329883 | 4.256 |
| Compute 1M | 14168890 | 14206743 | 108865486 | 7.663 |
| Flat 16M | 3166981 | 3176284 | 15369490 | 4.817 |
| Tree 1K | 1487 | 1497 | 1461 | 0.975 |

The cost guard restores cheap 4096/8192 scans to serial parity without forcing
unknown or heavy callbacks to use that estimate. The context fixture allocates
64 KiB in its constructor and only scans 16 values: per-call context allocation
falls from one to zero. Its nanosecond kernel times describe this synthetic
case, not a promised application-wide acceleration. For 512 u64 chunks,
explicit scratch removes the measured 256-byte heap allocation; no general
throughput gain is claimed for scratch.

The first five-round scan row was 3.17% slower. A seven-round confirmation
measured baseline/candidate 71901/71974 ns (+0.10%); the later main control was
+2.17%, while P-core scan was -2.34%. These changes do not show a stable
regression or gain. All main five-round control rows remain within the 5%
detection threshold, and the 1000-node floor passes. Subsequent final gates
must still cover the complete scheduler/sync/structure changes; this report
only verifies the flat checkpoint.

P-core five-round rows retain the cheap-work improvements: 4096 at
14578→1092 ns and 8192 at 14313→2148 ns. Scratch records zero allocation and
context construction records zero allocation on both CPU sets. Some unchanged
large rows vary by roughly 1–3%, consistent with the earlier same-core noise
calibration; those changes are not counted as improvements.

The [initial results](initial-results.json), [seven-round confirmation](confirmation/results.json),
[complete controls](controls/results.json), and [P-core results](p-core/results.json)
retain serial_ns, parallel_ns, speedup, harness hashes, commands and process
medians. Each dataset directory contains all inner raw logs, including its
allocation counters. Reproduce against a clean `04ab4e1` source export:

```sh
python3 scripts/perf_gate.py --baseline /path/to/04ab4e1 --cpus 24-31 \
  --rounds 5 --output /tmp/parz-flat-main-controls
python3 scripts/perf_gate.py --flat-only --baseline /path/to/04ab4e1 \
  --cpus 24-31 --rounds 7 --output /tmp/parz-flat-confirmation
python3 scripts/perf_gate.py --flat-only --baseline /path/to/04ab4e1 \
  --cpus 0,2,4,6,8,10,12,14 --rounds 5 --output /tmp/parz-flat-p-core
```
