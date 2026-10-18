#!/usr/bin/env python3
"""Re-fetch pinned public configs and bounded tensor headers using archived metadata.
No model payload or full weight file is downloaded.
"""
import urllib.request,json,struct,math,collections,concurrent.futures
from pathlib import Path
root=Path(__file__).resolve().parents[1]/'evidence'
PINS={'Qwen/Qwen3-VL-2B-Instruct':'89644892e4d85e24eaac8bacfd4f463576704203','mlx-community/Qwen3-VL-2B-Instruct-4bit':'9c4f5209e57b31f4b9dfba735de3fb983739c9cc'}
def fetch(url):
 req=urllib.request.Request(url,headers={'User-Agent':'FormCoachResearch/1.0'})
 with urllib.request.urlopen(req,timeout=45) as r:return r.read()
def one(repo):
 data=json.loads((root/f"{repo.replace('/','--')}--metadata.json").read_text())
 assert data['sha']==PINS[repo], 'Archived revision differs from audit pin'
 tag=repo.replace('/','--');(root/f'{tag}--metadata.json').write_text(json.dumps(data,indent=2))
 sha=data['sha'];files=data['siblings']
 for name in ['config.json','preprocessor_config.json','video_preprocessor_config.json','generation_config.json','README.md','chat_template.jinja','chat_template.json','LICENSE']:
  if any(x['rfilename']==name for x in files):
   (root/f'{tag}--{name}').write_bytes(fetch(f'https://huggingface.co/{repo}/raw/{sha}/{name}'))
 weights=[x for x in files if x['rfilename'].endswith('.safetensors')]
 print(json.dumps({'repo':repo,'revision':sha,'totalBytes':sum(x.get('size',0) for x in files),'weights':weights},ensure_ascii=False),flush=True)
 if weights:
  name=weights[0]['rfilename'];url=f'https://huggingface.co/{repo}/resolve/{sha}/{name}'
  def prefix(n):
   req=urllib.request.Request(url,headers={'Range':f'bytes=0-{n-1}','User-Agent':'FormCoachResearch/1.0'})
   with urllib.request.urlopen(req,timeout=50) as r:
    data=r.read(n)
    assert r.status==206 and r.headers.get('Content-Range','').startswith('bytes 0-'), 'Server did not honor bounded Range'
    return data, r.status, r.headers.get('Content-Range')
  b,status,contentrange=prefix(8);length=struct.unpack('<Q',b)[0]
  if not 0<length<10_000_000:raise ValueError('Invalid bounded header length')
  b,status,contentrange=prefix(length+8)
  header=json.loads(b[8:]);(root/f'{tag}--safetensors-header.json').write_text(json.dumps(header,indent=2))
  stats=collections.defaultdict(lambda:{'tensors':0,'elements':0,'bytes':0})
  for key,v in header.items():
   if key=='__metadata__':continue
   section='vision' if any(x in key for x in ['visual.','vision_tower.','vision_model.']) else 'language'
   item=stats[(section,v['dtype'])];item['tensors']+=1;item['elements']+=math.prod(v['shape']);item['bytes']+=v['data_offsets'][1]-v['data_offsets'][0]
  summary={'repo':repo,'revision':sha,'headerOnly':True,'headerBytes':length,'httpStatus':status,'contentRange':contentrange,'stats':[{ 'section':a,'dtype':b,**v} for (a,b),v in stats.items()]}
  (root/f'{tag}--tensor-summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
 for result in ex.map(one,['Qwen/Qwen3-VL-2B-Instruct','mlx-community/Qwen3-VL-2B-Instruct-4bit']):pass
