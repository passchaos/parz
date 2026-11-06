SPSC endpoints now cache the opposite position and refresh it only at a possible full/empty boundary. Each endpoint occupies a complete `std.atomic.cache_line` unit, with immutable buffer metadata in a separate unit. Acquire/release publication remains per item; push/pop allocate no memory. Sharded MPSC queues inherit the SPSC layout.

The producer's cached head conservatively limits which slots it may reuse. The consumer's cached tail covers values published before its last acquire. A boundary refresh acquires newly released slots or values. Wrapping subtraction on the producer and equality on the consumer preserve the same rules when integer positions wrap. Observers still acquire the head before the tail and clamp length to capacity; they never read either endpoint's plain cached position.

The frozen baseline in [spsc_baseline.zig](../../../bench/spsc_baseline.zig) is copied from `efeb092d467b2e997257cf72c18f91d6101d5c33` before changing queue layout. The exact baseline commit and implementation/benchmark source hashes are recorded in [environment.json](environment.json).

`bench-spsc` creates and pins the producer before starting the clock. The consumer is also pinned. Queue allocation, affinity setup and thread creation are outside the timed region. It checks every received value against the expected FIFO sequence, sums every payload, joins the producer, and checks that the final length is zero. Every warmup and measured invocation performs these checks. Each round reverses the order of baseline/current and serial/parallel paths; all raw samples are retained and summaries use medians.

The serial path fills and drains capacity-sized batches on one thread. The parallel path transfers the same sequence between two threads with non-blocking per-item operations. The `implementation` rows report `serial_ns`, `parallel_ns` and their ratio. The separate `comparison` row divides the baseline's parallel time by the current parallel time.

Final measurements use an i9-13900K with producer CPU 24 and consumer CPU 26, two distinct E cores sharing L2. Zig is 0.16.0, optimization is ReleaseFast, and each configuration has one warmup per path and nine measured rounds. The host had other active workloads, so the figures describe this fixed-input, fixed-CPU comparison. Every measured run passed order/checksum/length checks.

| Capacity | Items | Baseline serial_ns | Current serial_ns | Baseline parallel_ns | Current parallel_ns | Parallel comparison speedup |
|---|---:|---:|---:|---:|---:|---:|
| [1](capacity-1.log) | 100,000 | 373,243 | 308,572 | 19,637,364 | 19,469,999 | 1.009 |
| [8](capacity-8.log) | 3,000,000 | 4,353,114 | 4,737,333 | 67,437,107 | 58,405,371 | 1.155 |
| [1024](capacity-1024.log) | 3,000,000 | 3,979,408 | 4,484,833 | 18,051,382 | 6,938,021 | 2.602 |

The improvement has a memory and same-thread cost. Queue metadata grows from 56 to 384 bytes on x86_64, where Zig uses a 128-byte cache padding unit. Four sharded queues grow from four 128-byte padded wrappers to four 384-byte wrappers. Buffer allocation size is unchanged. In the final capacity-1024 serial measurement, the current path is 12.7% slower; capacity 1 remains dominated by handoff and shows effectively equal parallel throughput. This implementation favors the intended use between producer and consumer threads.

Two smaller layouts failed their exploratory checks: [compact cached cursors](rejected-compact-cache.log) and [aligned cursors without complete padding](rejected-partial-padding.log). Complete padding prevents read-mostly metadata from sharing an endpoint's written line. [Separation without caching](rejected-separation-only.log) also showed no convincing benefit. These exploratory binaries had variable baseline timing and are retained to explain the chosen layout. A [P-core sample on CPUs 0/2](p-core-sample.log) showed a 1.800 ratio with visibly larger timing variation; the final table uses CPUs 24/26 throughout.

```sh
zig build bench-spsc -Doptimize=ReleaseFast -- 100000 1 24 26 9
zig build bench-spsc -Doptimize=ReleaseFast -- 3000000 8 24 26 9
zig build bench-spsc -Doptimize=ReleaseFast -- 3000000 1024 24 26 9
```

Debug and ReleaseSafe each passed 62 library tests and three integration tests. [TSan](tsan.log) passed all 62 library tests. [Single-threaded mode](single-threaded.log) passed 50 tests with 12 concurrency/platform skips. WASM/WASI with atomics, x86_64 Windows GNU, aarch64 macOS and x86_64 Linux musl test instances compiled successfully. The [sync smoke benchmark](sync-smoke.log) completed and its SPSC checksum was 499999500000.

New tests seed both positions close to `usize` overflow, fill/drain complete queues, compare randomized partial operations against independent FIFO counts, and repeat threaded transfers across capacities 1, 2, 16 and 1024. Requested capacities 0 and 3 cover singleton fallback and power-of-two rounding. Existing third-party observer and sharded producer/consumer tests also pass.

The overall goal remains active. The checksum-verified [strict 1000-node tree gate](strict-parity.log) still fails with `serial_ns=2294`, `parallel_ns=4799`, `speedup=0.478`, below the required 0.9 floor. SPSC gains do not establish scheduler small-input parity or theoretical optimality.
