#!/usr/bin/env python3
"""Compare idle heartbeat CPU and context switches without timed user work."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
from perf_gate import REPO, build, placement


def snapshot(pid):
    result = {}
    for task in Path(f'/proc/{pid}/task').iterdir():
        status = dict(line.split(':', 1) for line in (task / 'status').read_text().splitlines() if ':' in line)
        stat = (task / 'stat').read_text().rsplit(')', 1)[1].split()
        result[task.name] = {
            'voluntary': int(status['voluntary_ctxt_switches']),
            'involuntary': int(status['nonvoluntary_ctxt_switches']),
            'cpu_ticks': int(stat[11]) + int(stat[12]),
            'cpu_ns': int((task / 'schedstat').read_text().split()[0]),
        }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, default=REPO)
    parser.add_argument('--cpus', default=os.environ.get('PARZ_BENCH_CPUS'))
    parser.add_argument('--rounds', type=int, default=3)
    parser.add_argument('--parking', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 3:
        parser.error('at least three alternating process rounds are required')
    cpus = placement(args.cpus)
    args.output.mkdir(parents=True, exist_ok=True)
    rows = []
    with tempfile.TemporaryDirectory(prefix='parz-idle-') as temp:
        binaries = {}
        for revision, root in [('baseline', args.baseline), ('candidate', args.candidate)]:
            binary = Path(temp) / revision
            print('build ' + revision, flush=True)
            build(REPO / 'bench/pool_idle.zig', root.resolve(), binary)
            binaries[revision] = binary
        for round_index in range(args.rounds):
            for mode in ('idle', 'held', 'flat-held'):
                revisions = ['baseline', 'candidate']
                if round_index % 2:
                    revisions.reverse()
                for revision in revisions:
                    cmd = ['taskset', '-c', ','.join(map(str, cpus)), str(binaries[revision]),
                           str(len(cpus)), str(cpus[-1]), mode, 'park' if args.parking else 'periodic']
                    process = subprocess.Popen(cmd, stderr=subprocess.PIPE, text=True)
                    try:
                        ready = process.stderr.readline()
                        if not ready.startswith('ready '):
                            raise RuntimeError(ready + process.stderr.read())
                        before = snapshot(process.pid)
                        start = time.monotonic()
                        time.sleep(2)
                        after = snapshot(process.pid)
                        elapsed = time.monotonic() - start
                        rest = process.communicate(timeout=5)[1]
                        if process.returncode:
                            raise RuntimeError(rest)
                    finally:
                        if process.poll() is None:
                            process.kill()
                            process.wait()
                    deltas = {tid: {key: value - before[tid][key] for key, value in counters.items()}
                              for tid, counters in after.items() if tid in before}
                    row = {'revision': revision, 'held': mode != 'idle', 'mode': mode, 'round': round_index, 'command': cmd,
                           'ready': ready.strip(), 'elapsed_s': elapsed, 'threads': deltas,
                           'voluntary_per_second': sum(t['voluntary'] for t in deltas.values()) / elapsed,
                           'cpu_seconds': sum(t['cpu_ticks'] for t in deltas.values()) / os.sysconf('SC_CLK_TCK'),
                           'cpu_ns': sum(t['cpu_ns'] for t in deltas.values())}
                    rows.append(row)
                    print(json.dumps(row), flush=True)
    (args.output / 'results.json').write_text(json.dumps({'cpus': cpus, 'parking': args.parking, 'samples': rows}, indent=2))
    idle = [row for row in rows if row['revision'] == 'candidate' and not row['held']]
    if args.parking and any(row['voluntary_per_second'] > 2 for row in idle):
        raise SystemExit('idle heartbeat did not remain parked')


if __name__ == '__main__':
    main()
