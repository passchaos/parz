#!/usr/bin/env python3
"""Alternating fixed-core sync comparisons with every inner checksum verified."""
import argparse
import json
from pathlib import Path
import re
import statistics
import tempfile
from perf_gate import REPO, build, command

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, default=REPO)
    parser.add_argument('--rounds', type=int, default=5)
    parser.add_argument('--only', choices=['treiber', 'blocking', 'mpsc', 'sharded'])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.rounds < 3: parser.error('at least three outer rounds are required')
    cases = [
        ('treiber', 'treiber-scalar', 'treiber_batch.zig', ['25000','1','24,25,26,27','31','9']),
        ('treiber', 'treiber-batch', 'treiber_batch.zig', ['25000','64','24,25,26,27','31','9']),
        ('treiber', 'treiber-uncounted', 'treiber_batch.zig', ['25000','64','24,25,26,27','31','9','uncounted']),
        ('blocking', 'blocking-1', 'blocking_batch.zig', ['25000','1','1','24,25','26,27','31','9']),
        ('blocking', 'blocking-4', 'blocking_batch.zig', ['25000','4','4','24,25','26,27','31','9']),
        ('blocking', 'blocking-1024', 'blocking_batch.zig', ['25000','1024','64','24,25','26,27','31','9']),
        ('mpsc', 'mpsc-1', 'mpsc_batch.zig', ['25000','1','1','24,25,26,27','31','9']),
        ('mpsc', 'mpsc-2', 'mpsc_batch.zig', ['25000','2','2','24,25,26,27','31','9']),
        ('mpsc', 'mpsc-1024', 'mpsc_batch.zig', ['25000','1024','64','24,25,26,27','31','9']),
        ('mpsc', 'mpsc-65536', 'mpsc_batch.zig', ['25000','65536','64','24,25,26,27','31','9']),
        ('sharded', 'sharded-dense', 'sharded_mpsc_batch.zig', ['25000','64','64','24,25,26,27','31','9']),
        ('sharded', 'sharded-small-view', 'sharded_sparse.zig', ['4','100000','31']),
        ('sharded', 'sharded-sparse-view', 'sharded_sparse.zig', ['128','100000','31']),
    ]
    if args.only: cases = [case for case in cases if case[0] == args.only]
    args.output.mkdir(parents=True, exist_ok=True)
    samples=[]
    with tempfile.TemporaryDirectory(prefix='parz-sync-') as temp:
        binaries={}
        for revision, root in [('baseline', args.baseline), ('candidate', args.candidate)]:
            for source in sorted({c[2] for c in cases}):
                print(f'build {revision} {source}', flush=True)
                binary=Path(temp)/(revision+'-'+source)
                build(REPO/'bench'/source, root.resolve(), binary)
                binaries[revision,source]=binary
        for round_index in range(args.rounds):
            for _,name,source,parameters in cases:
                revisions=['baseline','candidate'] if round_index%2==0 else ['candidate','baseline']
                for revision in revisions:
                    invocation=['taskset','-c','24-31',str(binaries[revision,source]),*parameters]
                    log=command(invocation)
                    (args.output/f'{name}-{revision}-{round_index}.log').write_text(log)
                    records=[line for line in log.splitlines() if 'statistic=median' in line]
                    if not records: raise RuntimeError(log)
                    for line in records:
                        fields=dict(re.findall(r'(\w+)=(\S+)', line))
                        key=name+'-'+fields.get('implementation','lookup')
                        samples.append({'case':key,'revision':revision,'round':round_index,'command':invocation,**fields})
                    print(f'run {round_index} {name} {revision}',flush=True)
    summary=[]; failures=[]
    for case in sorted({s['case'] for s in samples}):
        row={'case':case}
        for revision in ['baseline','candidate']:
            selected=[s for s in samples if s['case']==case and s['revision']==revision]
            row[revision]={key:statistics.median(float(s[key]) for s in selected) for key in ['serial_ns','parallel_ns','speedup']}
        for key in ['serial_ns','parallel_ns']:
            ratio=row['candidate'][key]/row['baseline'][key]
            row[key+'_ratio']=ratio
            if ratio>1.05: failures.append(f'{case} {key} increased {(ratio-1)*100:.2f}%')
        summary.append(row); print(json.dumps(row),flush=True)
    (args.output/'results.json').write_text(json.dumps({'cpus':'24-31','rounds':args.rounds,'summary':summary,'samples':samples,'failures':failures},indent=2))
    if failures: raise SystemExit('\n'.join(failures))

if __name__=='__main__': main()
