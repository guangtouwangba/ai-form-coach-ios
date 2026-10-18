from pathlib import Path
import json
B=Path(__file__).resolve().parents[1];s=json.loads((B/'results/protocol-v1.json').read_text());cases=[]
for id,idx in [('real-cycle',0),('real-cycle',3),('blank-control',0)]:
 c=next(c for c in s['cases'] if c['id']==id).copy();c['id']=f'caption-{id}-{idx}';c['frames']=[c['frames'][idx]];c['split']='diagnostic';c['prompt']='Describe only the visible person and the positions of their legs in one short English sentence. If there is no person, say no person.';c['systemPrompt']='Describe the image accurately.';c['maxTokens']=64;cases.append(c)
c=next(c for c in s['cases'] if c['id']=='ascent-omitted').copy();c['id']='simple-incomplete';c['split']='diagnostic';c['prompt']='These images are in time order. Is the person standing upright in the LAST image? Answer only yes, no, or uncertain.';c['systemPrompt']='Look at the final image. Do not infer any later movement.';c['maxTokens']=16;cases.append(c)
(B/'results/diagnostic-suite.json').write_text(json.dumps({'scope':'Simple image/phase diagnostic, separate from frozen comparison. Not a new blind test.','cases':cases},indent=2))
