#!/usr/bin/env python3
"""Compare actual normalized patch tensors, not only model prose."""
from pathlib import Path
import sys,json
import numpy as np
from transformers import AutoProcessor
from mlx_vlm.utils import prepare_inputs
modeldir,resultdir,outpath=sys.argv[1:]
processor=AutoProcessor.from_pretrained(modeldir,use_fast=True,local_files_only=True)
processor.image_processor.min_pixels=65536
processor.image_processor.max_pixels=262144
processor.image_processor.size={'shortest_edge':65536,'longest_edge':262144}
results=[]
for name in ['caption-real','caption-blank','colorchart']:
 d=json.loads((Path(resultdir)/(name+'.json')).read_text())
 f=d['frames'][0]
 messages=[{'role':'user','content':[{'type':'image'},{'type':'text','text':d['prompt']}]}]
 prompt=processor.apply_chat_template(messages,tokenize=False,add_generation_prompt=True)
 prepared=prepare_inputs(processor,images=[f['file']],prompts=prompt,image_token_index=151655)
 reference=np.asarray(prepared['pixel_values']).astype(np.float32)
 actual=np.load(d['preparedTensorPath']).astype(np.float32)
 record={'case':name,'swiftShape':list(actual.shape),'pythonShape':list(reference.shape),'swiftGrid':d['visualGridTHW'],'pythonGrid':prepared['image_grid_thw'].tolist()}
 if actual.shape==reference.shape:
  delta=np.abs(actual-reference)
  record.update(meanAbsoluteError=float(delta.mean()),p99AbsoluteError=float(np.quantile(delta,.99)),maxAbsoluteError=float(delta.max()),swiftMean=float(actual.mean()),pythonMean=float(reference.mean()),sameLayout=True)
 else:record['sameLayout']=False
 results.append(record)
Path(outpath).write_text(json.dumps({'scope':'Swift actual AVAsset/CIImage patches vs Python HF fast processor of the saved sRGB PNG; bicubic implementations can differ. Not assumed bit identical.','results':results},indent=2)+'\n')
print(json.dumps(results,indent=2))
