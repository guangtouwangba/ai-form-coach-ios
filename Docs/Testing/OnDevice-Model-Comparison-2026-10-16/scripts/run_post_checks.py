from pathlib import Path
import os,time,json,subprocess
B=Path(__file__).resolve().parents[1];PY='/tmp/coach-alternatives-venv/bin/python';records=[]
# Invoke after other model or pose jobs have finished; jobs below run sequentially.
old=Path('/Users/kids/Library/Application Support/AIFormCoach/Models/Qwen3-VL-2B-Instruct-4bit/9c4f5209e57b31f4b9dfba735de3fb983739c9cc')
models=[('qwen3vl',str(old)),('qwen35','mlx-community--Qwen3.5-2B-4bit'),('qwen35-4b','mlx-community--Qwen3.5-4B-MLX-4bit'),('gemma4','mlx-community--gemma-4-e2b-it-4bit'),('smolvlm','HuggingFaceTB--SmolVLM2-500M-Video-Instruct-mlx')]
for name,stem in models:
 model=stem if stem.startswith('/') else json.loads((B/'results'/(stem+'-download.json')).read_text())['directory']
 jobs=[('perf',B/'results/protocol-v1.json',['--ids','real-cycle','--repeat','6'])]
 if name not in ['qwen3vl','smolvlm']:jobs += [('diagnostic',B/'results/diagnostic-suite.json',[]),('recommended',B/'results/protocol-v1.json',['--sampling','recommended','--seed','17'])]
 for suffix,suite,extra in jobs:
  label=name+'-'+suffix;cmd=['/usr/bin/time','-l',PY,str(B/'scripts/compare_vlm.py'),model,'--suite',str(suite),'--out',str(B/'results'/label),*extra];print('START',label,flush=True);t=time.monotonic()
  with open('/tmp/coach-'+label+'.log','w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
  records.append({'name':label,'returncode':r.returncode,'seconds':time.monotonic()-t,'command':cmd});(B/'results/post-checks-receipt.json').write_text(json.dumps(records,indent=2));print('END',label,r.returncode,flush=True)
raise SystemExit(1 if any(x['returncode'] for x in records) else 0)
