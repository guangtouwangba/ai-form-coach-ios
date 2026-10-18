#!/usr/bin/env python3
"""Independent official Transformers/PyTorch MPS backend; local weights and frames only."""
from pathlib import Path
import sys,json,time,resource
from PIL import Image
import torch
from transformers import AutoProcessor,Qwen3VLForConditionalGeneration
modeldir,suitepath,swiftresults,outpath=sys.argv[1:]
out=Path(outpath);out.mkdir(parents=True,exist_ok=True)
torch.set_num_threads(6)
assert torch.backends.mps.is_available(),'MPS backend unavailable'
t0=time.monotonic()
model=Qwen3VLForConditionalGeneration.from_pretrained(modeldir,dtype=torch.bfloat16,attn_implementation='sdpa',local_files_only=True).eval().to('mps')
processor=AutoProcessor.from_pretrained(modeldir,use_fast=True,local_files_only=True)
torch.mps.synchronize()
print('Loaded official PyTorch MPS BF16',time.monotonic()-t0,flush=True)
for item in json.loads(Path(suitepath).read_text())['cases']:
    captured=json.loads((Path(swiftresults)/(item['id']+'.json')).read_text())
    content=[];images=[]
    for f in captured['frames']:
        content.extend([{'type':'text','text':f"[{f['id']} t={f['actualTime']:.3f}s]"},{'type':'image'}])
        images.append(Image.open(f['file']).convert('RGB'))
    content.append({'type':'text','text':item['prompt']})
    messages=[{'role':'system','content':item.get('systemPrompt','You are a helpful assistant.')},{'role':'user','content':content}]
    processor.image_processor.min_pixels=65536
    processor.image_processor.max_pixels=item.get('maxPixels',262144)
    processor.image_processor.size={'shortest_edge':65536,'longest_edge':item.get('maxPixels',262144)}
    text=processor.apply_chat_template(messages,tokenize=False,add_generation_prompt=True)
    inputs=processor(text=[text],images=images,return_tensors='pt').to('mps')
    n=inputs['input_ids'].shape[1]
    start=time.monotonic()
    with torch.inference_mode():
        tokens=model.generate(**inputs,max_new_tokens=item.get('maxTokens',192),do_sample=False)
    torch.mps.synchronize()
    answer=processor.batch_decode(tokens[:,n:],skip_special_tokens=True)[0]
    result={'id':item['id'],'text':answer,'seconds':time.monotonic()-start,'inputTokens':n,'outputTokens':tokens.shape[1]-n,'pixelShape':list(inputs['pixel_values'].shape),'imageGridTHW':inputs['image_grid_thw'].tolist(),'dtype':'bfloat16','backend':'official Transformers 4.57.1 / PyTorch 2.9.0 / MPS','driverAllocatedBytes':torch.mps.driver_allocated_memory(),'currentAllocatedBytes':torch.mps.current_allocated_memory(),'maxRSSBytes':resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}
    (out/(item['id']+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(item['id'],result['seconds'],answer,flush=True)
    del inputs,tokens
