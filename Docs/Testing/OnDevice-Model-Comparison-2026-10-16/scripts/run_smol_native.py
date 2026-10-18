from pathlib import Path
import json,numpy as np,time,resource,dataclasses
import mlx.core as mx
from mlx_vlm import load,generate
B=Path(__file__).resolve().parents[1];receipt=json.loads((B/'results/HuggingFaceTB--SmolVLM2-500M-Video-Instruct-mlx-download.json').read_text());s=json.loads((B/'results/smol-native-inputs.json').read_text());out=B/'results/smolvlm-native';out.mkdir(parents=True,exist_ok=True);mx.set_cache_limit(128*1024**2);m,p=load(receipt['directory'],use_fast=True,local_files_only=True);failed=0
(out/'environment.json').write_text(json.dumps({'modelDirectory':receipt['directory'],'processor':s['processor'],'runtime':'MLX-VLM 0.6.0 inference, official Transformers 4.57.1 CPU video preprocessing','scope':'Same saved frames; native video-format diagnostic, not an additional independent test set. Two six-frame clips flatten into a single twelve-image sequence for one prompt.','eligibleForAutomaticCoaching':False},indent=2))
for c in s['cases']:
 try:
  arrays=dict(np.load(c['inputs']));original={k:list(v.shape) for k,v in arrays.items()}
  # HF returns a clip axis; batch has one prompt containing every clip in order.
  for k in ['pixel_values','pixel_attention_mask']:
   if k in arrays and arrays[k].shape[0]>1:arrays[k]=arrays[k].reshape((1,-1)+arrays[k].shape[2:])
  inputs={k:mx.array(v) for k,v in arrays.items()};inputs['mask']=inputs.pop('attention_mask',None);mx.reset_peak_memory();t=time.monotonic();r=generate(m,p,c['prompt'],max_tokens=c['maxTokens'],temperature=0,verbose=False,**inputs);mx.synchronize()
  result={'id':c['id'],'success':True,'split':c['split'],'rawOutput':r.text,'finishReason':r.finish_reason,'generateSeconds':time.monotonic()-t,'mlxPeakBytes':mx.get_peak_memory(),'peakRSSBytes':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,'originalShapes':original,'actualShapes':{k:list(v.shape) for k,v in inputs.items() if hasattr(v,'shape')},'promptTokens':r.prompt_tokens,'outputTokens':r.generation_tokens};(out/(c['id']+'.json')).write_text(json.dumps(result,indent=2));print(c['id'],repr(r.text),flush=True);mx.clear_cache()
 except Exception as e:failed+=1;(out/(c['id']+'.json')).write_text(json.dumps({'id':c['id'],'success':False,'error':repr(e)},indent=2));print('ERROR',c['id'],repr(e),flush=True)
raise SystemExit(1 if failed else 0)
