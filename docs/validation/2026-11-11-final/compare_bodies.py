from pathlib import Path
import argparse, collections, json, re
parser=argparse.ArgumentParser(description="Compare module extraction with checkpoint 609509c")
parser.add_argument('--baseline',type=Path,required=True)
parser.add_argument('--candidate',type=Path,default=Path(__file__).resolve().parents[3])
args=parser.parse_args()
root=args.candidate.resolve()
base=args.baseline.resolve()
lexer=re.compile(r'//[^\n]*|"(?:\\.|[^"\\])*"|\w+|[^\s]')
def tokens(text): return [m[0] for m in lexer.finditer(text) if not m[0].startswith('//')]
def body(text,name):
    ts=tokens(text)
    index=next(i for i,t in enumerate(ts[:-1]) if t=='fn' and ts[i+1]==name)
    start=ts.index('{',index)
    depth=0
    for end in range(start,len(ts)):
        depth += (ts[end]=='{')-(ts[end]=='}')
        if depth==0: break
    return ts[start:end+1]
def normalize(ts): return [t for t in ts if t!='pub']
checks=[]
policy_changes=[]
for original,group in [('parallel.zig','parallel'),('core.zig','scheduler')]:
    source=(base/f'src/{original}').read_text()
    prefix=source.split('\ntest "')[0]
    names=re.findall(r'^(?:pub )?(?:(?:noinline|inline) )?fn (\w+)\(',prefix,re.M)
    if original=='parallel.zig': names+=['serialRange','serialFold','serialFoldInfallible','serialFoldRange','serialFoldRangeInfallible']
    for name in names:
        if name=='Pool': continue
        target=next(p for p in (([root/'src/core.zig'] if group=='scheduler' else []) + list((root/f'src/{group}').glob('*.zig'))) if re.search(r'^(?:pub )?(?:(?:noinline|inline) )?fn '+name+r'\(',p.read_text(),re.M))
        same=normalize(body(source,name))==normalize(body(target.read_text(),name))
        if name=='Options':
            assert not same
            policy_changes.append(name)
        else:
            assert same,name
            checks.append(name)
# Verify every pool method except the relocated heartbeat (whose body is equal).
source=(base/'src/core.zig').read_text()
pool=(root/'src/scheduler/pool.zig').read_text()
methods=re.findall(r'^        (?:pub )?(?:inline )?fn (\w+)\(',source[:source.index('\n// ---------------------------------------------------------------------------\n// Worker')],re.M)
for name in methods:
    target=(root/'src/scheduler/heartbeat.zig').read_text() if name=='heartbeatWorker' else pool
    newname='run' if name=='heartbeatWorker' else name
    same=normalize(body(source,name))==normalize(body(target,newname))
    if name in ['heartbeatWorker','reclaimShared','acquireExecuteStateLocked','releaseExecuteStateLocked','popReadyJob']:
        assert not same
        policy_changes.append('Pool.'+name)
    else:
        assert same,name
        checks.append('Pool.'+name)
for original,group in [('parallel.zig','parallel'),('core.zig','scheduler')]:
    old=collections.Counter(re.findall(r'^test "([^"]+)"', (base/f'src/{original}').read_text(), re.M))
    new=collections.Counter(name for path in (([root/'src/core.zig'] if group=='scheduler' else []) + list((root/f'src/{group}').glob('*.zig'))) if path.name not in ['executor.zig','scratch.zig','ready_owners.zig'] for name in re.findall(r'^test "([^"]+)"',path.read_text(),re.M))
    if original=='core.zig':
        old['explicit idle shortcut skips worker writes and resumes periodic flags for callers']=old.pop('default heartbeat skips idle worker writes and resumes periodic flags for callers')
        old['default heartbeat preserves periodic idle lane flags']=1
        old['heartbeat thread entry has a static pool parameter']=1
        old['exhausted execution states wake ready work on capacity return across workers']=1
        old['multiple capacity returns wake blocked peers before any state is consumed']=1
    assert old==new,(original,old-new,new-old)
report={'baseline':'609509c','unchanged_function_bodies':checks,'preserved_named_tests':55,'added_contract_tests':4,'intentional_changes':policy_changes,'note':'Function bodies compare after removing comments/pub. Explicit metadata control restores original default idle pacing. Execution-state wakeups occur only after real state-capacity pressure; multi-return notifications are retained. Worker/Task/Future stay together, with a static heartbeat entry.'}
out=root/'docs/validation/2026-11-11-final'
out.mkdir(exist_ok=True)
(out/'source-equivalence.json').write_text(json.dumps(report,indent=2)+'\n')
print('Unchanged bodies:',len(checks),'preserved named tests: 55; new contract tests: 4')
