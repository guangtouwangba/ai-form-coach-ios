#!/usr/bin/env python3
"""Real sequential MLX inference; no labels enter prompts. Mac only."""
from pathlib import Path
import argparse,json,time,threading,ctypes,struct,resource,dataclasses,platform,hashlib,traceback
import mlx.core as mx
from mlx_vlm import load,generate
from mlx_vlm.utils import prepare_inputs
p=argparse.ArgumentParser();p.add_argument('model');p.add_argument('--suite',required=True);p.add_argument('--out',required=True);p.add_argument('--split');p.add_argument('--ids');p.add_argument('--repeat',type=int,default=1);p.add_argument('--sampling',choices=['greedy','recommended'],default='greedy');p.add_argument('--seed',type=int,default=17);a=p.parse_args()
out=Path(a.out);out.mkdir(parents=True,exist_ok=True);suite=json.loads(Path(a.suite).read_text());cases=suite['cases']
if a.split:cases=[c for c in cases if c['split']==a.split]
if a.ids:cases=[c for c in cases if c['id'] in a.ids.split(',')]
assert cases and a.repeat>=1
for c in cases:assert len(c['frames'])<=12 and 0<c.get('maxTokens',192)<=192
lib=ctypes.CDLL('/usr/lib/libSystem.B.dylib');lib.mach_task_self.restype=ctypes.c_uint

def footprint():
 b=(ctypes.c_uint*1024)();n=ctypes.c_uint(1024);status=lib.task_info(lib.mach_task_self(),22,b,ctypes.byref(n))
 return struct.unpack_from('Q',bytes(b),144)[0] if status==0 and n.value>=38 else 0
class Sampler:
 def __init__(self):self.peak=0;self.stopped=False;self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start()
 def run(self):
  while not self.stopped:self.peak=max(self.peak,footprint());time.sleep(.05)
 def reset(self):self.peak=footprint()
sampler=Sampler();mx.set_cache_limit(128*1024**2);start=time.monotonic();model,processor=load(a.model,use_fast=True,local_files_only=True);mx.synchronize();config=json.loads((Path(a.model)/'config.json').read_text());kind=config['model_type']
load_seconds=time.monotonic()-start
mx.random.seed(a.seed)
sampling={'temperature':0}
if a.sampling=='recommended':
 sampling=({'temperature':.7,'top_p':.8,'top_k':20,'presence_penalty':1.5} if kind.startswith('qwen') else {'temperature':1.,'top_p':.95,'top_k':64})
ip=processor.image_processor
if kind in ['qwen3_vl','qwen3_5']:
 ip.min_pixels=65536;ip.max_pixels=131072;ip.size={'shortest_edge':65536,'longest_edge':131072}
elif kind=='gemma4':ip.max_soft_tokens=140
elif kind=='smolvlm':ip.do_image_splitting=False
else:raise RuntimeError('Unaudited model family '+kind)
env={'modelDirectory':a.model,'modelType':kind,'loadSeconds':load_seconds,'loadPeakFootprintBytes':sampler.peak,'os':platform.platform(),'scope':'Real macOS Metal GPU, sequential inference. File/Metal caches may be warm; no camera or iPhone.','suiteSHA256':hashlib.sha256(Path(a.suite).read_bytes()).hexdigest(),'mlxCacheBytes':128*1024**2,'runtime':'mlx-vlm 0.6.0','thinking':False,'sampling':sampling,'seed':a.seed,'processorPolicy':{'qwenPixels':[65536,131072],'gemmaSoftTokens':140,'smolImageSplitting':False}}
(out/'environment.json').write_text(json.dumps(env,indent=2));print('LOADED',kind,load_seconds,flush=True);failures=0
for c in cases:
 for rep in range(a.repeat):
  cid=c['id']+(f'-repeat{rep+1}' if a.repeat>1 else '');target=out/(cid+'.json');sampler.reset();mx.reset_peak_memory();t0=time.monotonic()
  try:
   images=[];content=[]
   for f in c['frames']:
    content.extend([{'type':'text','text':f"[{f['id']} t={f['actualTime']:.3f}s]"},{'type':'image'}]);images.append(f['file'])
   content.append({'type':'text','text':c['prompt']});messages=[{'role':'system','content':c.get('systemPrompt','Report only visible evidence.')},{'role':'user','content':content}]
   prompt=processor.apply_chat_template(messages,tokenize=False,add_generation_prompt=True,enable_thinking=False)
   prep0=time.monotonic();inputs=prepare_inputs(processor,images=images,prompts=prompt,image_token_index=config.get('image_token_index',config.get('image_token_id')),add_special_tokens=False)
   mx.eval(*[v for v in inputs.values() if isinstance(v,mx.array)]);mx.synchronize();prepsec=time.monotonic()-prep0
   shapes={k:list(v.shape) for k,v in inputs.items() if hasattr(v,'shape')};n=int(inputs['input_ids'].shape[-1]);assert n+c.get('maxTokens',192)<=8192,(n,'Context limit')
   kwargs=dict(inputs);kwargs['mask']=kwargs.pop('attention_mask',None);gen0=time.monotonic()
   r=generate(model,processor,prompt,max_tokens=c.get('maxTokens',192),verbose=False,**sampling,**kwargs);mx.synchronize();gensec=time.monotonic()-gen0
   result={'id':cid,'caseID':c['id'],'split':c['split'],'success':True,'rawOutput':r.text,'finishReason':r.finish_reason,'generateSeconds':gensec,'prepareSeconds':prepsec,'totalSeconds':time.monotonic()-t0,'peakFootprintBytes':sampler.peak,'endFootprintBytes':footprint(),'peakRSSBytes':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,'mlxPeakBytes':mx.get_peak_memory(),'promptTokens':r.prompt_tokens,'outputTokens':r.generation_tokens,'inputShapes':shapes,'promptTail':prompt[-280:],'frames':c['frames'],'sampling':sampling,'seed':a.seed,'maxTokens':c.get('maxTokens',192)}
   target.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(cid,round(gensec,3),repr(r.text),flush=True)
  except Exception as e:
   failures+=1;target.write_text(json.dumps({'id':cid,'success':False,'error':repr(e),'traceback':traceback.format_exc()},indent=2));print('FAILED',cid,traceback.format_exc(),flush=True)
  inputs=None;kwargs=None;r=None;mx.clear_cache()
sampler.stopped=True
raise SystemExit(1 if failures else 0)
