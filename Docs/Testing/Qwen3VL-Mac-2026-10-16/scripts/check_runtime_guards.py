#!/usr/bin/env python3
"""Exercise real executable budget/error exits without loading model weights."""
from pathlib import Path
import json,tempfile,subprocess
ROOT=Path(__file__).resolve().parents[4]
exe=Path('/tmp/coach-qwen-preflight-build/Build/Products/Release/CoachVideoBenchmark')
cases=[('too-many-frames',{'times':[0]*13}),('too-many-pixels',{'maxPixels':16777216}),('too-many-tokens',{'maxTokens':10000}),('invalid-variant',{'variant':'copr'})]
rows=[]
with tempfile.TemporaryDirectory(prefix='coach-qwen-budget-') as tmp:
 base=Path(tmp)
 for name,change in cases:
  item={'id':name,'video':'unused.mp4','times':[0],'prompt':'test'};item.update(change)
  suite=base/(name+'.json');suite.write_text(json.dumps({'cases':[item]}))
  result=subprocess.run([str(exe),str(base/'not-a-model'),str(suite),str(base/name)],capture_output=True,text=True)
  assert result.returncode==1,(name,result.returncode,result.stderr)
  assert 'Unsafe input budget or unsupported variant' in result.stderr
  assert 'Loading local verified' not in result.stderr
  rows.append({'id':name,'exitCode':result.returncode,'failedBeforeModelLoad':True,'stderr':result.stderr.strip()})
 suite=base/'empty.json';suite.write_text('{"cases":[]}')
 result=subprocess.run([str(exe),str(base/'not-a-model'),str(suite),str(base/'empty')],capture_output=True,text=True)
 assert result.returncode==1 and 'Empty suite' in result.stderr
 rows.append({'id':'empty-suite','exitCode':result.returncode,'failedBeforeModelLoad':True})
out=ROOT/'Docs/Testing/Qwen3VL-Mac-2026-10-16/results/runtime-guard-regression.json'
out.write_text(json.dumps({'checks':rows,'allPassed':True},indent=2)+'\n')
print('PASS 5 actual executable guards; all rejected before loading weights.')
