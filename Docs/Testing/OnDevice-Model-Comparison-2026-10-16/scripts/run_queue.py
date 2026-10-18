from pathlib import Path
import subprocess,time,json,os
B=Path(__file__).resolve().parents[1];PY='/tmp/coach-alternatives-venv/bin/python';records=[]
# Invoke after other model or pose jobs have finished; jobs below run sequentially.
jobs=[('qwen35-common','mlx-community--Qwen3.5-2B-4bit'),('gemma4-common','mlx-community--gemma-4-e2b-it-4bit'),('qwen35-4b-common','mlx-community--Qwen3.5-4B-MLX-4bit')]
for name,stem in jobs:
 receipt=B/'results'/(stem+'-download.json');deadline=time.monotonic()+1800
 while not receipt.exists():
  if time.monotonic()>deadline:raise TimeoutError('Model receipt missing '+stem)
  time.sleep(1)
 model=json.loads(receipt.read_text())['directory'];cmd=['/usr/bin/time','-l',PY,str(B/'scripts/compare_vlm.py'),model,'--suite',str(B/'results/protocol-v1.json'),'--out',str(B/'results'/name)]
 print('START',name,flush=True);t=time.monotonic()
 with open('/tmp/coach-'+name+'.log','w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
 records.append({'name':name,'returncode':r.returncode,'seconds':time.monotonic()-t,'command':cmd});(B/'results/queue-receipt.json').write_text(json.dumps(records,indent=2));print('END',name,r.returncode,flush=True)
raise SystemExit(1 if any(x['returncode'] for x in records) else 0)
