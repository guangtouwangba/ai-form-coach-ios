"""Budget diagnostic: pose classifiers get the exact six F frames used by VLM.
Same 18-trial supervised training and fixed heads; not a zero-shot model ranking.
"""
from pathlib import Path
import json,ast,math,time,os
import numpy as np,cv2,mediapipe as mp
from PIL import Image
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import NearestCentroid
from sklearn.linear_model import LogisticRegression
B=Path(__file__).resolve().parents[1];ROOT=B.parents[2];old=B/'results/pose-baseline';protocol=json.loads((old/'frozen-protocol.json').read_text());OUT=B/'results/pose-six-frames';OUT.mkdir(exist_ok=True)
# Reuse the exact geometry functions without executing the training entry point.
source=(B/'scripts/pose_baseline.py').read_text();tree=ast.parse(source);nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['point','angle','features']];exec(compile(ast.Module(body=nodes,type_ignores=[]),'pose_geometry','exec'),globals())
rows=[];suite=json.loads((B/'results/protocol-v1.json').read_text());test={c['id']:c for c in suite['cases']};cache=Path.home()/'Library/Caches/AIFormCoach/Benchmarks/OnDevice-Comparison-2026-10-16/pose-six-training';cache.mkdir(exist_ok=True)
for c in protocol['training']+protocol['evaluation']:
 frames=[]
 if c['split']=='train':
  cap=cv2.VideoCapture(c['video']);fps=cap.get(cv2.CAP_PROP_FPS);n=cap.get(cv2.CAP_PROP_FRAME_COUNT)
  for i,x in enumerate([.04,.22,.40,.58,.76,.94]):
   idx=round(round(n/fps*x,3)*fps);cap.set(cv2.CAP_PROP_POS_FRAMES,idx);ok,im=cap.read()
   if not ok:raise RuntimeError('Training frame decode failed '+c['id'])
   file=cache/(c['id']+f'-{i}.png');cv2.imwrite(str(file),im);frames.append({'file':str(file),'actualTime':idx/fps})
  cap.release()
 else:frames=[f for f in test[c['id']]['frames'] if f['id'].startswith('F')]
 opts=vision.PoseLandmarkerOptions(base_options=python.BaseOptions(model_asset_path=str(ROOT/'App/pose_landmarker_full.task'),delegate=python.BaseOptions.Delegate.CPU),running_mode=vision.RunningMode.VIDEO,num_poses=2,min_pose_detection_confidence=.5,min_pose_presence_confidence=.5,min_tracking_confidence=.5)
 seq=[];times=[]
 with vision.PoseLandmarker.create_from_options(opts) as detector:
  for f in frames:
   im=np.asarray(Image.open(f['file']).convert('RGB'));h,w=im.shape[:2];r=detector.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB,data=im),round(f['actualTime']*1000));v=features(r.pose_landmarks[0],w,h) if len(r.pose_landmarks)==1 else None;seq.append(v if v is not None else [np.nan]*14);times.append(f['actualTime'])
 arr=np.array(seq);coverage=float(np.min(np.isfinite(arr).mean(axis=0)));summ=[]
 for i in range(14):summ.extend(np.nanquantile(arr[:,i],[.1,.5,.9]).tolist() if np.isfinite(arr[:,i]).any() else [0,0,0])
 knee=np.nanmean(arr[:,:2],axis=1);good=np.isfinite(knee)
 if good.sum()>=3:
  knee=np.interp(times,np.array(times)[good],knee[good]);active=np.where(knee<np.quantile(knee,.95)-10)[0];duration=times[active[-1]]-times[active[0]] if len(active)>1 else 0;speed=float(np.quantile(np.abs(np.diff(knee)/np.diff(times)),.9))
 else:duration=0;speed=0
 summ.extend([duration,speed]);row={'id':c['id'],'split':c['split'],'expected':c['expected'],'features':summ,'coverage':coverage,'frames':frames};rows.append(row);(OUT/(c['id']+'.json')).write_text(json.dumps(row,indent=2));print(c['id'],coverage,flush=True)
tr=[r for r in rows if r['split']=='train'];ev=[r for r in rows if r['split']!='train'];scores={}
for name,head in [('nearest-centroid',NearestCentroid()),('logistic-C1',LogisticRegression(C=1,class_weight='balanced',max_iter=1000,random_state=0))]:
 pipe=make_pipeline(StandardScaler(),head);pipe.fit([r['features'] for r in tr],[r['expected'] for r in tr]);pred=pipe.predict([r['features'] for r in ev]);scored=[]
 for r,label in zip(ev,pred):
  label=str(label) if r['coverage']>=.8 else 'uncertain';scored.append({'id':r['id'],'split':r['split'],'expected':r['expected'],'predicted':label,'correct':label==r['expected'],'coverage':r['coverage']})
 scores[name]={'rows':scored,'eligibleForAutomaticCoaching':False}
(OUT/'score.json').write_text(json.dumps(scores,indent=2));print({k:sum(r['correct'] for r in v['rows']) for k,v in scores.items()})
