`Future.initFork` initializes unused caller-owned storage and appends the job directly. It accepts an undefined slot or a previously joined slot, avoiding a pending-value constructor when the caller forks immediately. The existing `.{}` / `fork` API remains available. The caller must keep the Future's address stable and join it before reuse, copying, returning its storage or unwinding its scope.

An enqueued Future cannot safely be returned by value from a constructor: the intrusive list points into the original object's address. The new operation therefore takes `*Self` and writes directly into final caller storage. It initializes the handler before the pending-state assertion can read it, copies input, then uses the existing plain-store append. Previous and next links are written before the job can be published. Input/output storage, shared execution and caller fallback remain unchanged; the operation performs no allocation or user-code execution.

```zig
var future: parz.Future(void, Input, Result) = undefined;
future.initFork(&task, run, input);
const result = future.joinOrCall(&task, run);
```

The new regression repeats undefined-slot initialization and joined-slot reuse ten times across every worker count 0–4, with either zero or 16 execution states. It checks input copying, errors from a narrow error set, all fields of a 64-byte-aligned packet result, empty input/output, and quiescent local-head/tail state. Existing pending, large-payload, ordered flat-fold and distinct-value recursive determinism tests remain enabled. The README's fallible recursive example now joins both branches before propagating either error.

[Debug](debug.log) and [ReleaseSafe](release-safe.log) each passed 64 library tests and three integration tests. [TSan](tsan.log) passed all 64 library tests. [Single-threaded mode](single-threaded.log) passed 52 tests with 12 concurrency/platform skips. WASM/WASI with atomics, Windows GNU, aarch64 macOS and x86_64 Linux musl test instances [compiled successfully](cross-targets.log).

The direct-initialization tree benchmark removes the initial eight-byte zero store at the inactive output error area. [Baseline disassembly](baseline-recursion.s) emits it at the start of the fork block; [direct disassembly](direct-recursion.s) begins with input and required job-link writes. The baseline tree `.text` hash is `abbcd0e913050ad4d7bb4dfa164b9eed5d4c66b8e2811e402e43147958bcfd54`, and direct initialization changes it to `56b5539d704c572f54857dc2855a2f7f0d3b95595b2467808cbf41728f614aee`. This reduces generated initialization work for this instantiation; it does not by itself prove a throughput gain.

The benchmark sources use `initFork` when available and a compile-time fallback to pending initialization against the exported baseline `f8b7afc`. Both traverse identical input and retain the same callback signatures. Each process warms both paths, validates every checksum independently against node count, alternates serial/parallel runs nine times and reports medians. Five outer rounds alternate baseline/candidate process order. E-core measurements fix caller 31 and workers 24–30; P-core measurements fix caller 14 and workers 0,2,4,6,8,10,12. Source/binary hashes and placement are in [environment.json](environment.json). All inner and outer samples are retained in the corresponding comparison JSON and sample logs.

| Comparison | Revision | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| Initial E-core, 1000-node tree | baseline | 1,534 | 3,211 | 0.478 |
| Initial E-core, 1000-node tree | direct | 1,499 | 3,212 | 0.467 |
| Initial E-core, 1M-node tree | baseline | 2,055,806 | 766,544 | 2.682 |
| Initial E-core, 1M-node tree | direct | 2,019,802 | 797,626 | 2.532 |
| Confirmation E-core, 1M-node tree | baseline | 2,036,028 | 854,599 | 2.382 |
| Confirmation E-core, 1M-node tree | direct | 2,040,658 | 838,525 | 2.434 |
| P-core, 1000-node tree | baseline | 2,260 | 4,289 | 0.527 |
| P-core, 1000-node tree | direct | 2,228 | 4,198 | 0.531 |
| P-core, 1M-node tree | baseline | 2,144,956 | 977,183 | 2.195 |
| P-core, 1M-node tree | direct | 2,149,722 | 957,369 | 2.245 |

Measured time changes are small and inconsistent on this loaded host. The E-core large-tree result reverses between batches. No general speedup claim is made. The useful verified result is a supported stable-address initialization path that removes an unnecessary generated store while preserving the original API and scheduler behavior.

The final [1000-node strict gate](strict-parity.log) still fails: `serial_ns=1503`, `parallel_ns=3128`, `speedup=0.480`, below 0.9. The [million-node control](large-control.log) passes with `serial_ns=1950621`, `parallel_ns=842802`, `speedup=2.314`. The overall goal remains active.
