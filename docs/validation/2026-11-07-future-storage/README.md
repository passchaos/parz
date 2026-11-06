The production scheduler and Future implementation remain identical to committed `d3d41bb`. Three storage experiments emitted exactly the same `.text` section as the baseline tree executable and were rejected. Their timing differences therefore do not establish an implementation speedup.

The baseline allocates one byte array sized to the larger of Input and Output and aligned to the larger type alignment. The experiments used overlapping extern-union byte views, explicitly marked the inactive output tail undefined after setting input, or used a `u128` carrier for 16-byte payloads. Every experimental implementation passed the existing Debug suite of 63 library tests and three integration tests. Their source patches are retained in [union](rejected-union.patch), [undefined tail](rejected-undefined-tail.patch), and [scalar](rejected-scalar.patch).

The tree benchmark's error-union future has an 8-byte input and a 16-byte output. Before each fork, LLVM emits a zero store at offset 32 of the 40-byte Future, followed by the input store at offset 24. The optimized [IR excerpt](initialization-ir.ll) maps that zero store to `bench/tree_sum.zig:23`, the Future variable initializer. Neither the union views nor explicit undefined tail removed it. [Baseline](baseline-recursion.s), [union](union-recursion.s), [undefined-tail](undefined-tail-recursion.s), and [scalar](scalar-recursion.s) disassemblies retain the same writes.

All four tree executables have the same `.text` SHA-256: `abbcd0e913050ad4d7bb4dfa164b9eed5d4c66b8e2811e402e43147958bcfd54`. Debug data and full binary hashes differ; [environment.json](environment.json) records both the executable-code and binary hashes, source hashes, baseline commit and compiler version. This establishes code identity for this instantiated benchmark, rather than all possible Future types or targets.

Measurements used fixed input, caller CPU 31 and workers 24–30 on the allowed set `24-31`. Each process checks every warmup and measured checksum, alternates serial/parallel paths nine times and reports medians. Five outer rounds alternate the baseline and candidate process order. The serial reference retains 64-byte code alignment. Process medians and all inner samples are retained in each `*-comparison.json` and `*-samples.log` file.

| Million-node tree comparison | serial_ns | parallel_ns | speedup |
|---|---:|---:|---:|
| Union trial baseline | 1,954,182 | 773,764 | 2.526 |
| Union trial candidate | 1,937,021 | 778,041 | 2.490 |
| Undefined-tail trial baseline | 2,001,682 | 837,166 | 2.391 |
| Undefined-tail trial candidate | 1,979,903 | 814,154 | 2.432 |
| Scalar trial baseline | 2,037,193 | 842,190 | 2.419 |
| Scalar trial candidate | 2,020,585 | 824,208 | 2.452 |

The last two cells appear faster despite identical executable code. This is measurement variation on the loaded host, not a storage optimization. The full comparisons also include 1000-node plain/error-union local traversal and 1000/100,000-node heartbeat trees; none provides evidence of a code-generation benefit.

After the experiments, the scheduler source was restored byte-for-byte to the baseline. No storage, ABI, scheduling or concurrency change remains. The existing [strict parity evidence](../2026-11-07-join-simplification/strict-parity.log) still describes the unchanged implementation: `serial_ns=1497`, `parallel_ns=3146`, `speedup=0.476`, below the 0.9 floor. The goal remains active. Subsequent work should target actual instructions and frame costs rather than retrying these equivalent storage representations.
