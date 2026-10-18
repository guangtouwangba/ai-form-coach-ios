#!/usr/bin/env python3
"""Download pinned complete models outside repository, checking upstream LFS hashes."""
from pathlib import Path
import urllib.request,json,hashlib,subprocess,concurrent.futures,time,sys
BASE=Path(__file__).resolve().parents[1]
REPOS=['mlx-community/Qwen3.5-2B-4bit','mlx-community/gemma-4-e2b-it-4bit','HuggingFaceTB/SmolVLM2-500M-Video-Instruct-mlx']
def one(repo):
 stem=repo.replace('/','--');metadata=BASE/'evidence'/f'{stem}-metadata.json'
 m=json.loads(metadata.read_text()) if metadata.exists() else json.load(urllib.request.urlopen('https://huggingface.co/api/models/'+repo+'?blobs=true',timeout=60))
 rev=m['sha'];metadata.write_text(json.dumps(m,indent=2))
 dest=Path.home()/'Library/Application Support/AIFormCoach/Models'/repo.split('/')[-1]/rev;dest.mkdir(parents=True,exist_ok=True)
 receipts=[]
 for item in m['siblings']:
  name=item['rfilename']
  if name.startswith('.') or name.endswith('.gitattributes'):continue
  target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);expected=item.get('lfs',{}).get('sha256')
  def valid(p):return p.exists() and p.stat().st_size==item['size'] and (not expected or hashlib.file_digest(p.open('rb'),'sha256').hexdigest()==expected)
  if not valid(target):
   part=target.with_suffix(target.suffix+'.part');url=f'https://huggingface.co/{repo}/resolve/{rev}/{name}?download=true'
   subprocess.run(['curl','-sS','--fail','-L','--retry','3','--connect-timeout','30','-C','-','-o',str(part),url],check=True)
   if not valid(part):raise RuntimeError(f'Integrity failure {repo}/{name}')
   part.replace(target)
  record={'file':name,'bytes':target.stat().st_size,'sha256':hashlib.file_digest(target.open('rb'),'sha256').hexdigest(),'upstreamSHA256':expected};receipts.append(record)
  if not name.endswith('.safetensors') and target.stat().st_size<200_000:(BASE/'evidence'/f'{stem}-{name.replace("/","_")}').write_bytes(target.read_bytes())
  print(json.dumps({'repo':repo,'verified':name,'bytes':record['bytes']}),flush=True)
 receipt={'repo':repo,'revision':rev,'directory':str(dest),'files':receipts,'completeWeightsVerified':True}
 (BASE/'results'/f'{stem}-download.json').write_text(json.dumps(receipt,indent=2))
 print('COMPLETE '+repo,flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:list(ex.map(one,sys.argv[1:] or REPOS))
