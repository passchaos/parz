`Future.tryJoin` now handles the owner-local tail once, then checks the handler before reading any pending predecessor. Every future uses `Job.pending()`; the old error-union/small-input specialization is unnecessary after the owner-tail change. Non-tail local jobs use removal directly. Only the owner can change `local_tail`, and no user callback or wait occurs between the first tail comparison and these local branches, so repeating the comparison cannot change the result.

Fork remains a plain-store append. Local-tail join preserves caller execution; non-tail and shared jobs retain their acquire/tag/reclaim/wait behavior. The input/output buffer layout, result representation and user callback signatures are unchanged. Existing pending-future and error-fallback tests cover 0–4 workers, and the distinct-value recursive integration repeats every worker count 0–4.

The tree and micro serial references now have 64-byte code alignment. In the initial ABI experiment, an unchanged serial function had identical relative instructions but moved from address `0x1083cc0` to `0x1083bb0`; its measured median changed from about 1.5 us to about 2.2 us. This made the apparent serial/parallel ratio misleading even though parallel time did not improve. Fixed alignment controls this source of code-layout variation. Both final variants' serial functions are aligned and have the same machine-code SHA-256 in both benchmarks: `0591c06c5928a5fb5b17e6cb81367c4d050142039c09c0856135fb7d1689f251`. Disassembly and addresses are recorded in [environment.json](environment.json) and the serial `.s` files beside it.

The baseline is committed `4837ba2`, exported without implementation edits. Baseline and candidate use the same updated benchmark sources. Measurements fix the allowed CPU set to `24-31`, pin caller CPU 31 and background workers to CPUs 24–30 on an i9-13900K. Each process checks warmups and every timed checksum, alternates serial/parallel paths nine times, and reports medians. Five outer rounds alternate baseline/candidate process order. [before-after.json](before-after.json) contains every process median; [paired-samples.log](paired-samples.log) contains inner samples and placement records. The table gives medians of the five process medians.

| Workload | Revision | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| Local plain callback, 1000 nodes | baseline | 1,536 | 3,285 | 0.468 |
| Local plain callback, 1000 nodes | current | 1,516 | 3,362 | 0.451 |
| Local error-union callback, 1000 nodes | baseline | 1,502 | 3,302 | 0.455 |
| Local error-union callback, 1000 nodes | current | 1,494 | 3,166 | 0.472 |
| Heartbeat tree, 1000 nodes, 8 lanes | baseline | 1,479 | 3,272 | 0.452 |
| Heartbeat tree, 1000 nodes, 8 lanes | current | 1,486 | 3,174 | 0.468 |
| Heartbeat tree, 100,000 nodes, 8 lanes | baseline | 162,179 | 139,829 | 1.160 |
| Heartbeat tree, 100,000 nodes, 8 lanes | current | 161,880 | 136,024 | 1.190 |
| Heartbeat tree, 1,000,000 nodes, 8 lanes | baseline | 1,784,624 | 794,394 | 2.247 |
| Heartbeat tree, 1,000,000 nodes, 8 lanes | current | 1,758,076 | 753,881 | 2.332 |

The small error-union parallel times are about 3–4% lower and the million-node parallel time is about 5% lower in this set. Plain local time varies slightly in the other direction. These modest changes on a loaded host do not establish a general throughput gain or theoretical optimality. [pending-cleanup.json](pending-cleanup.json) isolates removal of the old pending specialization before removing the repeated comparisons; it showed no convincing independent timing gain.

Two register-return prototypes were rejected. Both copied a small error-union payload into a word plus an error code, force-inlined the callback, and returned the carrier through a non-inlined native adapter. The SysV variant reduced local stack reservation from 104 to 88 bytes, but did not reduce local error-union time; small heartbeat-tree time was 3422 ns versus 3196 ns and million-node time was 841012 ns versus 771125 ns. The regcall variant was materially slower. The experimental adapters are absent from the implementation. Exact rejected patches and raw evidence are retained in [SysV patch](rejected-sysv.patch), [SysV results](sysv-experiment.json), [regcall patch](rejected-regcall.patch), and [regcall results](regcall-experiment.json), with the corresponding sample logs.

```sh
taskset -c 24-31 zig build bench-micro -Doptimize=ReleaseFast -- 1000 1 31
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000 heartbeat gate 31
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000000 heartbeat gate 31
```

Debug and ReleaseSafe each passed 63 library tests and three integration tests. [ReleaseSafe](release-safe.log), [TSan](tsan.log) and [single-threaded](single-threaded.log) evidence is retained; TSan passed 63 tests and single-threaded mode passed 51 with 12 concurrency/platform skips. WASM/WASI with atomics, Windows GNU, aarch64 macOS and x86_64 Linux musl test instances [compiled successfully](cross-targets.log).

The final aligned [1000-node strict parity gate](strict-parity.log) remains failing: `serial_ns=1497`, `parallel_ns=3146`, `speedup=0.476`, below 0.9. The [million-node control](large-control.log) passes with `serial_ns=1742948`, `parallel_ns=757241`, `speedup=2.302`. The overall goal remains active.
