#!/usr/bin/env python3
"""Build and run the parz / spice / Rayon / OpenMP comparison.

The benchmark processes alternate serial and parallel runs internally and
verify their checksum before printing. This runner interleaves the four
implementations across rounds and reports the best parallel time per cell.
"""

import argparse
import os
import re
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COMPARE = ROOT / "bench" / "compare"
PATTERN = re.compile(r"serial_ns=\s*(\d+)\s+parallel_ns=\s*(\d+)\s+speedup=\s*([\d.]+)")

WORKLOADS = [
    ("tree", 1_000),
    ("tree", 100_000),
    ("tree", 10_000_000),
    ("flat", 16_000_000),
    ("compute", 1_000_000),
]


def run(cmd, cwd=ROOT, check=True):
    print("+", " ".join(str(c) for c in cmd), flush=True)
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if check and result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    return result


def build(args):
    zig_cmd = ["zig", "build", "bench-compare", "-Doptimize=ReleaseFast"]
    spice_dir = os.environ.get("SPICE_DIR")
    if spice_dir:
        zig_cmd.append(f"-Dspice-dir={spice_dir}")
    run(zig_cmd)

    if shutil.which("cargo"):
        result = run(["cargo", "build", "--release"], cwd=COMPARE / "rayon-bench", check=False)
        if result.returncode != 0:
            print("cargo build failed; skipping Rayon", file=sys.stderr)
    else:
        print("cargo not found; skipping Rayon", file=sys.stderr)

    if shutil.which("gcc"):
        result = run([
            "gcc", "-O3", "-march=native", "-fno-tree-vectorize", "-fopenmp",
            "-o", str(COMPARE / "omp_bench"), str(COMPARE / "omp_bench.c"),
        ], check=False)
        if result.returncode != 0:
            print("gcc build failed; skipping OpenMP", file=sys.stderr)
    else:
        print("gcc not found; skipping OpenMP", file=sys.stderr)


def discover_impls(args):
    impls = {
        "parz": {
            "path": ROOT / "zig-out" / "bin" / "compare-parz",
            "compute_workload": "compute-inf",
        },
    }
    spice = ROOT / "zig-out" / "bin" / "compare-spice"
    if spice.exists():
        impls["spice"] = {"path": spice, "compute_workload": "compute"}
    rayon = COMPARE / "rayon-bench" / "target" / "release" / "rayon-bench"
    if rayon.exists():
        impls["rayon"] = {"path": rayon, "compute_workload": "compute"}
    omp = COMPARE / "omp_bench"
    if omp.exists():
        impls["openmp"] = {"path": omp, "compute_workload": "compute"}
    return impls


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rounds", type=int, default=5)
    parser.add_argument("--lanes", type=int, default=os.cpu_count() or 1)
    parser.add_argument("--cpus", help="taskset CPU list, e.g. 0-15")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--json", type=Path, help="write raw results as JSON")
    parser.add_argument(
        "--gate",
        action="store_true",
        help="fail if parz speedups fall below conservative smoke thresholds",
    )
    args = parser.parse_args()

    if not args.no_build:
        build(args)

    impls = discover_impls(args)
    if "parz" not in impls or not impls["parz"]["path"].exists():
        raise SystemExit("compare-parz was not built; run zig build bench-compare")

    data = {name: {} for name in impls}
    for round_index in range(args.rounds):
        order = list(impls)
        order = order[round_index % len(order):] + order[:round_index % len(order)]
        for workload, count in WORKLOADS:
            for name in order:
                info = impls[name]
                actual = info["compute_workload"] if workload == "compute" else workload
                cmd = [str(info["path"]), actual, str(count), str(args.lanes)]
                if args.cpus:
                    cmd = ["taskset", "-c", args.cpus] + cmd
                result = run(cmd, check=False)
                output = result.stdout + result.stderr
                if result.returncode != 0:
                    print(f"FAIL {name} {workload}-{count}: {output.strip()}", file=sys.stderr)
                    raise SystemExit(result.returncode)
                match = PATTERN.search(output)
                if not match:
                    print(f"PARSE FAIL {name} {workload}-{count}: {output.strip()}", file=sys.stderr)
                    raise SystemExit(1)
                serial, parallel = int(match.group(1)), int(match.group(2))
                key = f"{workload}-{count}"
                data[name].setdefault(key, []).append((serial, parallel))
                print(
                    f"r{round_index + 1:02d} {name:6s} {key:16s} "
                    f"serial={serial:>10d} parallel={parallel:>10d} "
                    f"speedup={match.group(3)}",
                    flush=True,
                )

    print("\n=== best (min) parallel time per implementation ===")
    header = f"{'workload':16s}"
    for name in impls:
        header += f" {name:>18s}"
    print(header)
    for workload, count in WORKLOADS:
        key = f"{workload}-{count}"
        line = f"{key:16s}"
        for name in impls:
            runs = data[name].get(key, [])
            if not runs:
                line += f" {'-':>18s}"
                continue
            serial, parallel = min(runs, key=lambda item: item[1])
            line += f" {parallel / 1e6:10.3f}ms/{serial / parallel:5.2f}x"
        print(line)

    if args.gate:
        # Conservative smoke floors, not competitive targets. They are meant
        # to catch catastrophic regressions on a loaded development host.
        gates = {
            "tree-1000": 0.30,
            "tree-100000": 0.80,
            "tree-10000000": 2.50,
            "flat-16000000": 2.50,
            "compute-1000000": 10.0,
        }
        failures = []
        for key, minimum in gates.items():
            runs = data["parz"].get(key, [])
            if not runs:
                failures.append(f"{key}: missing")
                continue
            serial, parallel = min(runs, key=lambda item: item[1])
            speedup = serial / parallel
            if speedup < minimum:
                failures.append(f"{key}: {speedup:.2f}x < {minimum:.2f}x")
        if failures:
            print("gate failed:", "; ".join(failures), file=sys.stderr)
            raise SystemExit(1)
        print("gate passed")

    if args.json:
        import json
        args.json.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
