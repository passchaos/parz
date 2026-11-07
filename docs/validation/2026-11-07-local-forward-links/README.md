The scheduler implementation was restored after local assertion, alignment
and deferred-forward-link experiments failed to improve performance
consistently across E and P cores. The retained changes are an optional
repeated-call microbenchmark and a nested `Worker.begin` regression test.
The overall optimization goal remains active.

The baseline is exported commit `d2e1212`, using Zig 0.16.0. E-core cases fix
caller 31 and workers 24–30; P-core cases fix caller 14 and workers
0, 2, 4, 6, 8, 10, 12. Local micro cases use one lane with heartbeat disabled.
Each process checks warmups and every timed checksum, alternates
serial/parallel runs nine times and reports medians. Five outer rounds
alternate revision order. Source and binary hashes are retained in
[environment.json](environment.json). The host has other active workloads;
the recorded outcomes are bounded to these inputs and CPU placements.

The first candidate snapshots the tail before append and checks local-tail
invariants with plain loads. Its error-union disassembly removes one tail
reload and two acquire loads from assertion evaluation; the stack reservation
remains 104 bytes. The old `std.debug.assert(state() == .queued_local)` can
retain atomic loads in ReleaseFast even when the assertion check disappears.
The [baseline](baseline-recursion.s) and [candidate](local-recursion.s)
disassemblies establish that instruction difference. Fewer instructions did
not establish a stable execution-time benefit.

The candidates were separated into [tail snapshot](snapshot.patch) and
[plain local assertions](checks.patch). Single-call plain micro results looked
better, but repeated calls exposed an E-core regression. For plain local
1000-node callbacks, the [isolated single-call E-core comparison](isolated-E-comparison.json)
gave `parallel_ns=3352` for baseline and `2906` for local assertions. In the
[repeated comparison](repeated-E-comparison.json), baseline was `2796 ns` and
the candidate `3109 ns` per call. Their plain recursive function starts moved
from offset 32 to offset 16 within a 64-byte line. These results do not support
promoting the initial single-call gain as a portable optimization.

The repeated diagnostic times 1024 calls between clock reads, checks each
result independently, and uses `std.mem.doNotOptimizeAway(context)` with a
pointer context and its memory clobber to prevent read-only serial work from
being hoisted out of the loop. Reported times are per call. It uses the same
tree and actual public call/fork/join APIs. The default repetition count is
one and delegates to the original `timing.paired` implementation. The
single-call strict tree gate is kept separately.

Alignment-only and alignment/assertion controls are retained in
[E-core](alignment-E-comparison.json) and [P-core](alignment-P-comparison.json)
results, with corresponding patches. Code placement explained part of the
plain callback variation, but those controls did not provide consistent
large-tree gains.

The deferred-link candidate maintains an owner-only backward chain and uses
a non-executing dirty marker on its local tail. Fork avoids updating the prior
tail's forward link. Sharing and non-tail joins build forward links once;
prepared non-tail removals preserve those links. Sharing still retains the
owner's tail and publishes through the existing shared list. An initialization
flag keeps nested `begin` calls from resetting a nonempty backward chain.
The mixed-list and nested-begin test instances passed all 76 Debug tests
including three integration tests. This is functional evidence for the
experiment, rather than a claim that it passed all concurrency/platform gates.

Both conditional empty-head cleanup and unconditional dirty marking were
measured. The latter uses constant-time local tail removal and treats the
dirty local tail as having no materialized forward successor. A further
candidate outlines forward preparation and fixes callback alignment to 64
bytes. Its [E-core](outlined-E-comparison.json) and
[P-core](outlined-P-comparison.json) results include:

| Case | Revision | serial_ns | parallel_ns | speedup |
|---|---|---:|---:|---:|
| E, repeated plain 1000-node local call | baseline | 1,375 | 2,864 | 0.480 |
| E, repeated plain 1000-node local call | deferred + outlined + aligned | 1,394 | 3,119 | 0.438 |
| E, 1M-node heartbeat tree | baseline | 1,851,249 | 776,112 | 2.370 |
| E, 1M-node heartbeat tree | deferred + outlined + aligned | 1,852,383 | 730,857 | 2.468 |
| P, repeated plain 1000-node local call | baseline | 1,958 | 3,835 | 0.509 |
| P, repeated plain 1000-node local call | deferred + outlined + aligned | 1,925 | 3,390 | 0.567 |
| P, 1M-node heartbeat tree | baseline | 2,057,202 | 849,243 | 2.432 |
| P, 1M-node heartbeat tree | deferred + outlined + aligned | 2,026,260 | 785,163 | 2.572 |

Columns are medians of process medians; speedup is the median reported ratio.
The million-node parallel time improved about 6–8% in these last batches,
while repeated E-core plain callbacks regressed about 9%. Earlier deferred
variants also regressed on small or medium inputs. The small-workload mission
does not support applying those mixed outcomes to the general scheduler.
All source trials are retained as patches; all process medians and inner
samples are retained in the comparison JSON and sample logs. No alignment,
dirty marker, local-list protocol or assertion change remains in production.

The retained regression repeats nested `Worker.begin` with outstanding parent
and child futures ten times across worker counts 0–4. It covers registered
caller lanes and temporary unregistered serial workers, checks distinct
values, and confirms quiescent local head/tail state afterward. It passes
against the restored implementation and protects the public nested-begin
behavior needed by later scheduler work.

```sh
taskset -c 24-31 zig build bench-micro -Doptimize=ReleaseFast -- 1000 1 31 1024
taskset -c 0,2,4,6,8,10,12,14 zig build bench-micro -Doptimize=ReleaseFast -- 1000 1 14 1024
taskset -c 24-31 zig build bench-tree-sum -Doptimize=ReleaseFast -- 1000 heartbeat gate 31
```

The final retained changes passed [Debug](debug.log) and
[ReleaseSafe](release-safe.log), each with 72 library tests and three
integration tests. [TSan](tsan.log) passed all 72 library tests.
[Single-threaded mode](single-threaded.log) passed 58 with 14 skips. Test
instances compiled for [WASM/WASI with atomics](wasm32-wasi.log),
[Windows GNU](x86_64-windows-gnu.log), [aarch64 macOS](aarch64-macos.log) and
[x86_64 Linux musl](x86_64-linux-musl.log).

Both [default single-call](single-smoke.log) and
[1024-repetition](repeated-smoke.log) micro modes verified every result and
completed. The final [strict 1000-node gate](strict-parity.log) remains
failing: `serial_ns=1526`, `parallel_ns=3354`, `speedup=0.455`. The
[million-node control](large-control.log) passes with `serial_ns=1837463`,
`parallel_ns=786764`, `speedup=2.335`. The retained benchmark/test work does
not establish scheduler small-input parity or theoretical optimality.
