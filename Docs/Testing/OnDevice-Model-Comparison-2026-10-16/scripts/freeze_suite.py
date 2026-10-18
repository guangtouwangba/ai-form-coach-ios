#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,time
import cv2
BASE=Path(__file__).resolve().parents[1];ROOT=BASE.parents[2];OLD=ROOT/'Docs/Testing/Qwen3VL-Mac-2026-10-16/results';DATA=Path.home()/'Library/Caches/AIFormCoach/Benchmarks/OfficeSquat'
CACHE=Path.home()/'Library/Caches/AIFormCoach/Benchmarks/OnDevice-Comparison-2026-10-16';CACHE.mkdir(parents=True,exist_ok=True)
old=json.loads((OLD/'office-word-fresh-suite.json').read_text());labels=json.loads((OLD/'office-fresh-labels.json').read_text())['labels'];cases=[]
for c,l in zip(old['cases'],labels):
 c.update(expected=l['label'],split='seen-comparison',sourceSHA256=l['sha256']);cases.append(c)
newfiles=['Squat/paper_squat_tn_corr6.avi','Squat/paper_squat_tn_corr7.avi','Squat/paper_squat_tn_high4_fast.avi','Squat/paper_squat_tn_low5.avi','Squat/paper_squat_tn_low6.avi','Squat/paper_squat_tn_tilt7.avi','Squat/paper_squat_tn_tilt8.avi','Squat/paper_squat_tn_arms1_fast.avi','SquatTransSmall/paper_squat_ts_fast2.avi','SquatTransSmall/paper_squat_ts_fast3.avi']
for i,f in enumerate(newfiles):
 p=DATA/f;cap=cv2.VideoCapture(str(p));duration=cap.get(cv2.CAP_PROP_FRAME_COUNT)/cap.get(cv2.CAP_PROP_FPS);cap.release();label=p.stem.split('_')[3];label=''.join(x for x in label if not x.isdigit());label='correct' if label=='corr' else label
 c=dict(old['cases'][0]);c.update(id=f'confirmation-{i+1:02}',video=str(p),times=[round(duration*x,3) for x in [.04,.22,.40,.58,.76,.94]],expected=label,split='unused-trial-confirmation',sourceSHA256=hashlib.file_digest(p.open('rb'),'sha256').hexdigest());cases.append(c)
controls=json.loads((OLD/'observer-suite.json').read_text())['cases']
for c in controls:
 if c['id'] in ['real-cycle-warm','real-cycle-unchunked']:continue
 c['video']=str((OLD/c['video']).resolve());c.update(split='temporal-controls',maxTokens=192);cases.append(c)
# Freeze labels, prompts and sources before any candidate inference. Never change this file based on scores.
frozen={'createdUTC':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'scope':'One participant OfficeSquat primary filename labels; seen comparison vs previously unused trials, not participant holdout. high4_fast/arms1_fast have secondary fast; ts_fast have translation. Controls test visible facts only. Overall fitness correctness and clinical standards not measured.','cases':cases}
path=BASE/'results/frozen-suite.json'
if path.exists():raise SystemExit('Refusing to overwrite frozen suite')
path.write_text(json.dumps(frozen,ensure_ascii=False,indent=2)+'\n')
print('FROZEN',hashlib.sha256(path.read_bytes()).hexdigest(),len(cases),flush=True)
for c in cases:
 frames=[]
 for prefix,video,times,variant in [('R',c.get('referenceVideo'),c.get('referenceTimes',[]),None),('F',c['video'],c['times'],c.get('variant'))]:
  if not video:continue
  cap=cv2.VideoCapture(video);fps=cap.get(cv2.CAP_PROP_FPS)
  for i,t in enumerate(times):
   t=times[0] if variant=='static' else t;idx=round(t*fps);cap.set(cv2.CAP_PROP_POS_FRAMES,idx);ok,img=cap.read()
   if not ok:raise RuntimeError((video,t))
   if variant=='blank':img[:]=128
   elif variant=='crop':img=img[:img.shape[0]//2]
   file=CACHE/c['id']/f'{prefix}{i+1}.png';file.parent.mkdir(parents=True,exist_ok=True);cv2.imwrite(str(file),img)
   frames.append({'id':f'{prefix}{i+1}','requestedTime':t,'actualTime':idx/fps,'file':str(file),'sha256':hashlib.file_digest(file.open('rb'),'sha256').hexdigest()})
  cap.release()
 c['frames']=frames
(BASE/'results/prepared-suite.json').write_text(json.dumps(frozen,ensure_ascii=False,indent=2)+'\n')
print('PREPARED',len(cases),flush=True)
