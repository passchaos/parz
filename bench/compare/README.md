# parz comparison benchmark

This directory contains a reproducible comparison between `parz`, [spice],
[Rayon], and an OpenMP C baseline.

The harness is deliberately separate from `zig build bench`: it needs an
external spice checkout, Cargo/Rayon, and a GCC with OpenMP.

## Workloads

| Name | Input | What it measures |
|---|---|---|
| tree | 1K / 100K / 10M nodes | fork/join scheduling and caller fallback |
| flat | 16M `u64` values | memory-bandwidth-bound parallel sum |
| compute | 1M items, 64-round LCG | CPU-bound fold |

Each benchmark alternates a serial run and a parallel run, verifies the
checksum, and reports `serial_ns`, `parallel_ns`, and `speedup`. The runner
interleaves the four implementations across rounds and reports the best
parallel time per cell.

## Dependencies

- Zig 0.16
- Rust and Cargo (for Rayon)
- GCC with OpenMP (`-fopenmp`)
- A [spice] checkout (optional; clone it yourself, for example
  `git clone https://github.com/judofyr/spice /tmp/spice`)

## Run

```sh
SPICE_DIR=/tmp/spice python3 bench/compare/run_compare.py --rounds 5 --lanes 32
```

Useful options:

```sh
--cpus 0-15          # pin the whole process with taskset
--no-build           # reuse the already-built binaries
--json results.json  # save raw samples
--gate               # fail on catastrophic parz regressions
```

The runner builds:

- `zig build bench-compare -Doptimize=ReleaseFast [-Dspice-dir=...]`
- `cargo build --release` in `bench/compare/rayon-bench`
- `gcc -O3 -march=native -fno-tree-vectorize -fopenmp omp_bench.c`

If `cargo`, `gcc`, or the spice checkout is missing, that implementation is
skipped with a warning.

## Fairness notes

- Spice has no flat-loop API. Its `flat` and `compute` numbers use a recursive
  range fork/join with 4096/1024-element leaves; treat them as an adaptation,
  not a native spice feature.
- OpenMP's tree uses `#pragma omp task` with a depth cutoff of 8. Its flat and
  compute loops use `parallel for reduction(static)`.
- GCC is compiled with `-fno-tree-vectorize` for the compute workload so its
  serial baseline stays scalar like Zig/Rust. Without that flag GCC can
  vectorize independent LCG iterations.
- Absolute numbers are sensitive to CPU topology (P/E cores), frequency
  scaling, and other load on the machine. Use `--cpus` and an otherwise idle
  host for publishable numbers.
- The checksum gate is part of every process: a mismatch exits non-zero and the
  runner stops.

[spice]: https://github.com/judofyr/spice
[Rayon]: https://github.com/rayon-rs/rayon

The parz executable accepts a per-call lane cap after its tuning arguments.
The cap includes the caller; 0 keeps all pool lanes available:

```sh
taskset -c 0,2,4,6,8,10,12,14 zig-out/bin/compare-parz \
    compute 1000000 8 1024 16 heartbeat 10000 2
```

Every measured parz checksum is validated, including samples that are not
selected as the best time.
