# Bounded ready-owner indexing and compatible idle heartbeat

Default shared-job pickup uses an init-time priority bitmap instead of
scanning every registered worker. It retains the original worker-index order;
empty/reclaimed owners leave the bitmap and intrusive index list. Optional
`fair_shared_owners` rotates owners. Default heartbeat keeps its original
periods but skips the pool lock and idle worker writes using caller/stop
atomic snapshots. Fork and Task.call's heartbeat load remain unchanged.

Complete parking is explicitly disabled by default. Flat caller admission
does not request recursive demand in parking mode; Worker.begin requests it.
Automatic parking, heartbeat pinning and unconditional round robin were
rejected as defaults after their cold latency or throughput rows regressed.
Their patches/results are retained in [rejected](rejected/).

The baseline is the verified flat checkpoint `85bdeb6`. All comparisons use
the same current harness for both source roots, Zig 0.16.0 ReleaseFast, fixed
input and CPU placement, alternating serial/parallel and revision order, and
checksum verification for every result. E placement: caller 31, workers 24–30.
P placement: caller 14, workers 0,2,4,6,8,10,12. Default comparisons use five
outer rounds; confirmations use seven. The host is not isolated.

[E-core controls](e-core/results.json) passed every row and 1000-node parity
(0.980x). [P-core controls](p-core/results.json) passed all but an absolute
1000-node time comparison; its serial reference increased similarly while
parity stayed 0.985x. The [seven-round small-tree confirmation](p-parity-confirmation/results.json)
passed. No implementation gain is inferred from these frequency/noise shifts.

A first [100 ms cold-idle comparison](cold-initial/results.json) flagged the
scan at +8.78%; [seven-round confirmation](cold-confirmation/results.json)
measured 40651 vs baseline 43157 ns, and heavy work 154434 vs 168204 ns. The
increase did not reproduce. Both results are preserved; the gate threshold
does not authorize knowingly retaining a regression.

[Default 1/2/4/8 caller controls](callers/results.json) preserve throughput.
The earlier round-robin trial reduced four-caller p95 (493303→333676 ns) but
increased group time 2–4%, so it is an explicit fairness choice rather than a
default throughput claim. Priority bitmap contracts include word boundaries,
arbitrary reclamation, zero states and repeated deterministic workloads.

[Default idle samples](idle-default/results.json) retain about 13972 wakes/s.
Two-second median scheduler CPU time was 49138068 ns baseline and 48588242 ns
candidate; this small difference is not claimed as a stable throughput gain.
The verified mechanism is skipping idle locks/metadata stores. The explicit
[parking samples](idle-parking/results.json) show zero idle timer wakes;
their known cold-latency cost is why automatic parking is disabled.

[Checks](checks/) record Debug and ReleaseSafe 114 tests each, TSan 111 tests,
single-threaded 86 pass/25 skip, and successful WASM compile with atomics.
Tests cover held/flat callers, recursive demand activation, idle shutdown,
default idle flags, priority/round-robin selection and execution-state fallback.
Native cross-target and complete final regression gates remain part of the
overall optimization goal after the remaining sync/module changes.

```sh
python3 scripts/perf_gate.py --baseline /path/to/85bdeb6 --cpus 24-31 --rounds 5 --output /tmp/scheduler-e
python3 scripts/perf_gate.py --baseline /path/to/85bdeb6 --cpus 0,2,4,6,8,10,12,14 --rounds 5 --output /tmp/scheduler-p
python3 scripts/perf_gate.py --first-call-only --idle-ms 100 --baseline /path/to/85bdeb6 --cpus 24-31 --rounds 7 --output /tmp/scheduler-cold
python3 scripts/perf_gate.py --callers-only --baseline /path/to/85bdeb6 --cpus 24-31 --rounds 5 --output /tmp/scheduler-callers
python3 scripts/idle_profile.py --baseline /path/to/85bdeb6 --cpus 24-31 --rounds 3 --output /tmp/scheduler-idle
```
