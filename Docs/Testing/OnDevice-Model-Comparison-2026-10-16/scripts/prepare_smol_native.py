"""Official Transformers video processor, exact saved frames and true source timestamps."""
from pathlib import Path
import json,numpy as np,cv2
from PIL import Image
from transformers import AutoProcessor
from transformers.video_utils import VideoMetadata
B=Path(__file__).resolve().parents[1];s=json.loads((B/'results/protocol-v1.json').read_text());model=json.loads((B/'results/HuggingFaceTB--SmolVLM2-500M-Video-Instruct-mlx-download.json').read_text())['directory'];processor=AutoProcessor.from_pretrained(model,local_files_only=True,use_fast=True)
cache=Path.home()/'Library/Caches/AIFormCoach/Benchmarks/OnDevice-Comparison-2026-10-16/smol-native';cache.mkdir(parents=True,exist_ok=True);rows=[]
for c in s['cases']:
 videos=[];meta=[];content=[]
 for prefix in ['R','F']:
  frames=[f for f in c['frames'] if f['id'].startswith(prefix)]
  if not frames:continue
  video=c.get('referenceVideo') if prefix=='R' else c['video'];cap=cv2.VideoCapture(video);fps=cap.get(cv2.CAP_PROP_FPS);total=int(cap.get(cv2.CAP_PROP_FRAME_COUNT));cap.release()
  videos.append(np.stack([np.asarray(Image.open(f['file']).convert('RGB')) for f in frames]));meta.append(VideoMetadata(total_num_frames=total,fps=fps,duration=total/fps,frames_indices=[round(f['actualTime']*fps) for f in frames]))
  content.extend([{'type':'text','text':f'This video contains the ordered frames {prefix}1 through {prefix}6. '},{'type':'video'}])
 content.append({'type':'text','text':c['prompt']});messages=[{'role':'system','content':[{'type':'text','text':c['systemPrompt']}]},{'role':'user','content':content}]
 prompt=processor.apply_chat_template(messages,tokenize=False,add_generation_prompt=True)
 inputs=processor(text=prompt,videos=[videos],video_metadata=meta,do_sample_frames=False,return_tensors='pt')
 file=cache/(c['id']+'.npz');np.savez(file,**{k:v.detach().cpu().numpy() for k,v in inputs.items() if hasattr(v,'detach')})
 row={'id':c['id'],'inputs':str(file),'prompt':prompt,'decodedPrompt':processor.tokenizer.decode(inputs['input_ids'][0],skip_special_tokens=False),'shapes':{k:list(v.shape) for k,v in inputs.items() if hasattr(v,'shape')},'metadata':[{'fps':v.fps,'indices':v.frames_indices,'duration':v.duration} for v in meta],'maxTokens':c.get('maxTokens',192),'split':c['split']};rows.append(row);print(c['id'],row['shapes'],flush=True)
(B/'results/smol-native-inputs.json').write_text(json.dumps({'processor':'Official Transformers 4.57.1 SmolVLM video processor; no resampling, exact same frames. Not native MLX-VLM video fallback.','cases':rows},indent=2))
