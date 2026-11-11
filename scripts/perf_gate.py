#!/usr/bin/env python3
"""Fixed-CPU paired performance gate; build identical harnesses for both cores."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]


def cpu_list(text):
    result = []
    for group in text.split(','):
        bounds = group.split('-')
        first = int(bounds[0])
        last = int(bounds[-1])
        if first > last:
            raise ValueError('descending CPU range')
        result.extend(range(first, last + 1))
    return result


def placement(requested):
    allowed = os.sched_getaffinity(0)
    selected = []
    for cpu in sorted(allowed):
        siblings = Path(f'/sys/devices/system/cpu/cpu{cpu}/topology/thread_siblings_list')
        group = set(cpu_list(siblings.read_text().strip())) if siblings.exists() else {cpu}
        if not group.intersection(selected):
            selected.append(cpu)
    if requested:
        cpus = cpu_list(requested)
        if not cpus or len(set(cpus)) != len(cpus) or not set(cpus).issubset(allowed):
            raise ValueError('CPU set must be unique and inside the allowed affinity')
        if not set(cpus).issubset(selected):
            raise ValueError('select the first allowed logical CPU per physical core')
        return cpus
    return selected[-8:]


def command(args, cwd=None):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f'{args!r}\n{result.stdout}\n{result.stderr}')
    return result.stdout + result.stderr


def build(source, core, binary):
    return command(['zig', 'build-exe', '--dep', 'parz', '-OReleaseFast',
                    f'-Mroot={source}', '-OReleaseFast', f'-Mparz={core / "src/root.zig"}',
                    f'-femit-bin={binary}'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, help='source checkout for old core')
    parser.add_argument('--candidate', type=Path, default=REPO)
    parser.add_argument('--cpus', default=os.environ.get('PARZ_BENCH_CPUS'))
    parser.add_argument('--rounds', type=int, default=5, help='alternating process rounds')
    parser.add_argument('--parity-only', action='store_true')
    parser.add_argument('--flat-only', action='store_true')
    parser.add_argument('--max-regression', type=float, default=0.05)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 3 or not 0 <= args.max_regression <= 0.1:
        parser.error('at least 3 rounds and a regression allowance in [0, 0.1] are required')
    cpus = placement(args.cpus)
    cpu_arg = ','.join(map(str, cpus))
    lanes, caller = str(len(cpus)), str(cpus[-1])
    cases = [('tree-1k', 'tree_sum.zig', ['1000', 'heartbeat', 'measure', caller])]
    if args.flat_only:
        cases = []
    if args.flat_only or not args.parity_only:
        for count in (4095, 4096, 8192, 65536, 1000003):
            cases.append((f'cheap-{count}', 'flat_dispatch.zig', ['cheap', str(count), lanes, caller, '16', '21']))
        cases.extend([
            ('scan-1m', 'flat_dispatch.zig', ['scan', '1000003', lanes, caller, '16', '21']),
            ('scratch-1m', 'flat_dispatch.zig', ['scratch', '1000003', lanes, caller, '64', '21']),
            ('context-16', 'flat_dispatch.zig', ['context', '16', lanes, caller, '16', '21', '1000']),
            ('heavy-8192', 'flat_dispatch.zig', ['compute', '8192', lanes, caller, '16', '21']),
        ])
    if not args.parity_only and not args.flat_only:
        cases.extend([
            ('tree-100k', 'tree_sum.zig', ['100000', 'heartbeat', 'measure', caller]),
            ('tree-1m', 'tree_sum.zig', ['1000000', 'heartbeat', 'measure', caller]),
            ('micro', 'micro.zig', ['1000', lanes, caller, '1000']),
            ('flat-1m', 'parallel_for.zig', ['1000003', lanes, caller, '21']),
            ('flat-16m', 'parallel_for.zig', ['16000003', lanes, caller, '9']),
            ('compute-1m', 'compute.zig', ['1000000', 'pin', lanes, caller, '9']),
            ('grid', 'parallel_for_2d.zig', ['1024', '1024', lanes, caller, '9']),
        ])
    args.output.mkdir(parents=True, exist_ok=True)
    sources = {'candidate': args.candidate.resolve()}
    if args.baseline:
        sources['baseline'] = args.baseline.resolve()
    samples = []
    with tempfile.TemporaryDirectory(prefix='parz-perf-') as temp:
        binaries = {}
        for revision, core in sources.items():
            for source in sorted({case[1] for case in cases}):
                binary = Path(temp) / f'{revision}-{source}'
                print(f'build {revision} {source}', flush=True)
                build(REPO / 'bench' / source, core, binary)
                binaries[revision, source] = binary
        for round_index in range(args.rounds):
            revisions = list(sources)
            if round_index % 2:
                revisions.reverse()
            for name, source, parameters in cases:
                for revision in revisions:
                    invocation = ['taskset', '-c', cpu_arg, str(binaries[revision, source]), *parameters]
                    log = command(invocation)
                    (args.output / f'{name}-{revision}-{round_index}.log').write_text(log)
                    records = [line for line in log.splitlines() if 'statistic=median' in line]
                    if not records:
                        raise RuntimeError(f'no paired statistics for {name}: {log}')
                    for line in records:
                        fields = dict(re.findall(r'(\w+)=(\S+)', line))
                        suffix = fields.get('callback', '')
                        key = name + (f'-{suffix}' if suffix else '')
                        samples.append({'case': key, 'revision': revision, 'round': round_index,
                                        'command': invocation, **fields})
                    print(f'run {round_index} {name} {revision}', flush=True)
    summaries, failures = [], []
    for case in sorted({sample['case'] for sample in samples}):
        row = {'case': case}
        for revision in sources:
            selected = [s for s in samples if s['case'] == case and s['revision'] == revision]
            row[revision] = {key: statistics.median(float(s[key]) for s in selected)
                             for key in ('serial_ns', 'parallel_ns', 'speedup')}
        if case == 'tree-1k' and row['candidate']['speedup'] < 0.9:
            failures.append(f'{case}: parity below 0.9')
        if 'baseline' in row:
            ratio = row['candidate']['parallel_ns'] / row['baseline']['parallel_ns']
            row['parallel_ratio'] = ratio
            if ratio > 1 + args.max_regression:
                failures.append(f'{case}: parallel time increased by {(ratio - 1) * 100:.2f}%')
        summaries.append(row)
        print(json.dumps(row), flush=True)
    metadata = {'cpus': cpus, 'caller_cpu': int(caller), 'rounds': args.rounds,
                'zig': command(['zig', 'version']).strip(),
                'max_regression': args.max_regression,
                'harness_hashes': {source: hashlib.sha256((REPO / 'bench' / source).read_bytes()).hexdigest()
                                  for source in {case[1] for case in cases}},
                'source_roots': {name: str(path) for name, path in sources.items()}}
    (args.output / 'results.json').write_text(json.dumps({'environment': metadata, 'summary': summaries,
                                                       'samples': samples, 'failures': failures}, indent=2))
    if failures:
        raise SystemExit('\n'.join(failures))


if __name__ == '__main__':
    main()
