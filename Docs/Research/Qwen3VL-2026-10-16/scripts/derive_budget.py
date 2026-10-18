#!/usr/bin/env python3
"""Derive lower bounds from archived public metadata; never performs inference."""
import json, math
from pathlib import Path
root=Path(__file__).resolve().parents[1]
evidence=root/'evidence'
name='mlx-community--Qwen3-VL-2B-Instruct-4bit'
config=json.loads((evidence/f'{name}--config.json').read_text())
meta=json.loads((evidence/f'{name}--metadata.json').read_text())
header=json.loads((evidence/f'{name}--safetensors-header.json').read_text())
raw=json.loads((evidence/'Qwen--Qwen3-VL-2B-Instruct--safetensors-header.json').read_text())
vision={k:v for k,v in header.items() if k.startswith('vision_tower.')}
assert vision and all(v['dtype']=='BF16' for v in vision.values())
weight_bytes=sum(v['data_offsets'][1]-v['data_offsets'][0] for k,v in header.items() if k!='__metadata__')
vision_bytes=sum(v['data_offsets'][1]-v['data_offsets'][0] for v in vision.values())
text=config['text_config']; per_token=2*text['num_hidden_layers']*text['num_key_value_heads']*text['head_dim']*2
result={
 'assumptions':['Batch 1; full unquantized 16-bit K/V; actual dtype/capacity must be observed at runtime.', 'Weights + KV are a lower bound, excluding all vision activations, prefill, Metal caches, decoder/camera, UI and operating-system accounting.'],
 'original_tensor_parameters':sum(math.prod(v['shape']) for k,v in raw.items() if k!='__metadata__'),
 'repo_bytes':sum(v.get('size',0) for v in meta['siblings']),
 'tensor_storage_bytes':weight_bytes,'vision_bf16_bytes':vision_bytes,
 'kv_bytes_per_token':per_token,
 'kv_examples':[{'tokens':n,'kv_mib':per_token*n/2**20,'weights_plus_kv_gib_lower_bound':(weight_bytes+per_token*n)/2**30} for n in [2048,4096,8192,16384,32768,262144]],
 'image_examples':[{'height':h,'width':w,'per_image_visual_tokens_after_spatial_merge':h*w//1024,'six_image_visual_tokens':h*w//1024*6} for h,w in [(512,512),(672,384),(1280,736)]],
 'patch_factor':config['vision_config']['patch_size']*config['vision_config']['spatial_merge_size'],
 'temporal_patch_size':config['vision_config']['temporal_patch_size']
}
assert result['patch_factor']==32 and result['original_tensor_parameters']==2127532032
(evidence/'derived-budget.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
