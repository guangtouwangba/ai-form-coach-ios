#!/usr/bin/env python3
"""Differential probe: same pinned MLX weights, actual Swift-extracted PNGs and prompts."""
from pathlib import Path
import sys,json,time,dataclasses
import mlx.core as mx
from mlx_vlm import load,generate
from mlx_vlm.utils import prepare_inputs
modeldir,suitepath,swiftresults,outpath=sys.argv[1:]
suite=json.loads(Path(suitepath).read_text())
out=Path(outpath);out.mkdir(parents=True,exist_ok=True)
mx.set_cache_limit(128*1024*1024)
t0=time.monotonic()
model,processor=load(modeldir,use_fast=True,local_files_only=True)
print('Loaded Python reference',time.monotonic()-t0,flush=True)
for item in suite['cases']:
    captured=json.loads((Path(swiftresults)/(item['id']+'.json')).read_text())
    frames=captured['frames']
    content=[];images=[]
    for f in frames:
        content.extend([{'type':'text','text':f"[{f['id']} t={f['actualTime']:.3f}s]"},{'type':'image'}])
        images.append(f['file'])
    content.append({'type':'text','text':item['prompt']})
    messages=[{'role':'system','content':item.get('systemPrompt','You are a helpful assistant.')},{'role':'user','content':content}]
    prompt=processor.apply_chat_template(messages,tokenize=False,add_generation_prompt=True)
    budget=item.get('maxPixels',262144)
    processor.image_processor.min_pixels=65536
    processor.image_processor.max_pixels=budget
    processor.image_processor.size={'shortest_edge':65536,'longest_edge':budget}
    prepared=prepare_inputs(processor,images=images,prompts=prompt,image_token_index=151655)
    shapes={k:list(v.shape) for k,v in prepared.items() if hasattr(v,'shape')}
    grids=prepared['image_grid_thw'].tolist() if 'image_grid_thw' in prepared else None
    mx.reset_peak_memory()
    start=time.monotonic()
    result=generate(model,processor,prompt,image=images,max_tokens=item.get('maxTokens',192),temperature=0,verbose=False)
    seconds=time.monotonic()-start
    data={'id':item['id'],'text':result.text,'seconds':seconds,'mlxPeakBytes':mx.get_peak_memory(),'inputShapes':shapes,'imageGridTHW':grids,'promptTail':prompt[-280:],'promptTokens':result.prompt_tokens,'outputTokens':result.generation_tokens,'scope':'Python MLX-VLM 0.3.4 using identical saved PNG files and pinned quantized weights; not phone timing'}
    (out/(item['id']+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    print(item['id'],seconds,result.text,flush=True)
