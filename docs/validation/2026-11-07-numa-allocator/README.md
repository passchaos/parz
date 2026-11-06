The optional `NumaAllocator` now implements standard Zig allocation interfaces using Linux VMA policy and a portable allocator fallback. It is independent of the scheduler and synchronization modules. Pass its allocator to `Pool.init` or use it as the backing allocator for a per-worker arena.

Implementation: `2509bf74e5d5a4c8b788ae89a05bb73dfbf11ff1`. Exact source hashes, Zig version, and host topology are in [environment.json](environment.json).

Policies are `local`, `preferred`, `bind`, and `interleave`. Node masks are copied at initialization and support every `u16` node ID, including masks spanning multiple machine words. All allocations, resize/remap operations, and frees use a consistent backend: Linux page mappings or the supplied non-Linux fallback. A failed Linux policy request keeps that page-allocation provenance in best-effort mode, or frees the mapping and returns allocation failure in required mode. `stats()` reports accepted policies, fallback allocations, policy failures, last errno, and live allocations.

Alignment and allocation arithmetic are checked before invoking the page allocator. Failed reallocations preserve the original memory. Linux resizing/remapping delegates to the page allocator and retains the VMA policy; rebinding after a successful relocation would be unsafe because a policy failure could not restore the old pointer.

The source basis is Linux's [VMA memory policy documentation](https://docs.kernel.org/6.5/admin-guide/mm/numa_memory_policy.html) and [mbind interface](https://manpages.ubuntu.com/manpages/noble/man2/mbind.2.html). Actual policy preservation is also checked with `get_mempolicy` after anonymous mapping growth and shrink, with contents verified at each step.

`scripts/check.sh` completed successfully. Debug and ReleaseSafe unit/integration tests, native single-threaded fallback, TSan, WASM/WASI, Windows GNU, aarch64 macOS, and x86_64 musl Linux test-instance compilation passed. The library has 61 unit tests and three integration tests. [gates.log](gates.log) retains the final serial/TSan and smoke evidence.

Integration tests repeat 0–3 background workers and ordered folds while per-worker arenas allocate through the wrapper. After `Pool.deinit`, the allocator reports zero live mappings. Tests cover invalid node sets, init-time allocation failure, over-page alignment, unsuccessful oversized reallocations, every policy, and required-policy behavior.

| Runtime check | Result |
|---|---|
| [preferred/node 0](preferred.log) | Native policy accepted; applied=1, fallback=0, errno=0, live=0; checksum=499999500000 |
| [required preferred/node 0](required.log) | Policy accepted and checksum verified |
| [VMA grow/shrink](vma-policy.log) | `get_mempolicy` confirmed local policy after each remap; contents preserved |
| [required node 65535](invalid-required.log) | Allocation failed with errno 22; failures=1, live=0 |
| [best-effort node 65535](invalid-fallback.log) | fallback=1, errno=22, live=0; checksum=499999500000 |

```sh
zig build check-numa -Doptimize=ReleaseSafe -- preferred 0
zig build check-numa -Doptimize=ReleaseSafe -- preferred 65535 require
zig build check-numa -Doptimize=ReleaseSafe -- preferred 65535
```

The unavailable high-node checks validate failure/fallback, rather than claiming that the host supports node 65535. The host topology is a single NUMA node. These checks establish allocator contracts and native policy configuration; they do not establish cross-node placement or a NUMA throughput gain. No benchmark speedup claim is made for this allocator.

The overall goal remains active: strict small-input parity remains unachieved, and multi-node performance evidence is still missing.

The strict 1000-node performance gate still fails in the current tree harness: `serial_ns=2112`, `parallel_ns=4402`, `speedup=0.480`. [strict-parity.log](strict-parity.log) records that checksum-verified result; no small-input performance gain is claimed by this optional allocator change.
