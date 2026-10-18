#!/usr/bin/env python3
"""Research-only MediaPipe Full + tiny supervised pose head; no fixture filenames in predictors."""
from pathlib import Path
import json,time,hashlib,math,resource
import numpy as np
import cv2,mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import NearestCentroid
from sklearn.linear_model import LogisticRegression
BASE=Path(__file__).resolve().parents[1];ROOT=BASE.parents[2];OLD=ROOT/'Docs/Testing/Qwen3VL-Mac-2026-10-16/results';DATA=Path.home()/'Library/Caches/AIFormCoach/Benchmarks/OfficeSquat';OUT=BASE/'results/pose-baseline';OUT.mkdir(parents=True,exist_ok=True)
SUITE=json.loads((BASE/'results/protocol-v1.json').read_text());train=json.loads((OLD/'office-labels-frozen.json').read_text())['labels']
manifest={'training':[{'id':'train-'+l['id'],'video':str(DATA/'Squat'/l['file']),'expected':l['label'],'split':'train','sha256':l['sha256']} for l in train],'evaluation':[c for c in SUITE['cases'] if c['split']!='temporal-controls'],'modelSHA256':hashlib.file_digest((ROOT/'App/pose_landmarker_full.task').open('rb'),'sha256').hexdigest(),'policy':'Fixed before baseline inference: MediaPipe Full CPU, 10 Hz, confidence >=.5, 14 pose features x 3 quantiles plus active seconds and peak angular speed; StandardScaler + nearest centroid (no hyperparameter search), plus C=1 balanced logistic diagnostic. 18 training trials only; same subject. No filename/duration metadata passed to classifier. New VLM results not used to tune features. No automatic coaching.'}
manifestpath=OUT/'frozen-protocol.json'
if manifestpath.exists():
 assert json.loads(manifestpath.read_text())==manifest,'Frozen protocol changed'
else:manifestpath.write_text(json.dumps(manifest,indent=2))
opts=lambda:vision.PoseLandmarkerOptions(base_options=python.BaseOptions(model_asset_path=str(ROOT/'App/pose_landmarker_full.task'),delegate=python.BaseOptions.Delegate.CPU),running_mode=vision.RunningMode.VIDEO,num_poses=2,min_pose_detection_confidence=.5,min_pose_presence_confidence=.5,min_tracking_confidence=.5)

def point(lm,i,w,h):
 p=lm[i]
 if min(p.visibility,p.presence)<.5:return np.array([np.nan,np.nan])
 return np.array([p.x*w,p.y*h])
def angle(a,b,c):
 x=a-b;y=c-b;d=np.linalg.norm(x)*np.linalg.norm(y)
 return math.degrees(math.acos(float(np.clip(np.dot(x,y)/d,-1,1)))) if d>1e-8 else np.nan

def features(landmarks,w,h):
 p={i:point(landmarks,i,w,h) for i in range(11,33)}
 hip=(p[23]+p[24])/2;shoulder=(p[11]+p[12])/2;ankle=(p[27]+p[28])/2
 leg=(np.linalg.norm(p[23]-p[25])+np.linalg.norm(p[25]-p[27])+np.linalg.norm(p[24]-p[26])+np.linalg.norm(p[26]-p[28]))/2
 if not np.isfinite(leg) or leg<10:return None
 v=[angle(p[23],p[25],p[27]),angle(p[24],p[26],p[28]),angle(p[11],p[23],p[25]),angle(p[12],p[24],p[26])]
 v += [(p[i][1]-p[j][1])/leg for i,j in [(13,11),(14,12),(15,11),(16,12),(11,12),(23,24)]]
 v += [(ankle[1]-hip[1])/leg,(hip[1]-shoulder[1])/leg,(p[25][0]-p[27][0])/leg,(p[26][0]-p[28][0])/leg]
 return v
records=[]
for c in manifest['training']+manifest['evaluation']:
 cap=cv2.VideoCapture(c['video']);fps=cap.get(cv2.CAP_PROP_FPS);n=int(cap.get(cv2.CAP_PROP_FRAME_COUNT));duration=n/fps;sequence=[];times=[];infer=[];miss=0;start=time.monotonic()
 with vision.PoseLandmarker.create_from_options(opts()) as detector:
  decoded=0;sample_index=0
  while True:
   ok,img=cap.read()
   if not ok:break
   frame_index=decoded;decoded+=1
   if frame_index<round(sample_index*fps/10):continue
   sample_index+=1;actual=frame_index/fps
   h,w=img.shape[:2];s=time.monotonic();r=detector.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB,data=cv2.cvtColor(img,cv2.COLOR_BGR2RGB)),round(actual*1000));infer.append(time.monotonic()-s)
   feat=features(r.pose_landmarks[0],w,h) if len(r.pose_landmarks)==1 else None
   if feat is None:feat=[np.nan]*14;miss+=1
   sequence.append(feat);times.append(float(actual))
 cap.release();arr=np.array(sequence);valid=np.isfinite(arr).mean(axis=0);coverage=float(np.min(valid));summ=[]
 for k in range(14):
  col=arr[:,k];good=np.isfinite(col)
  if not good.any():summ.extend([0,0,0])
  else:summ.extend(np.nanquantile(col,[.1,.5,.9]).tolist())
 knee=np.nanmean(arr[:,:2],axis=1);good=np.isfinite(knee)
 if good.sum()>=3:
  knee=np.interp(times,np.array(times)[good],knee[good]);standing=float(np.quantile(knee,.95));active=np.where(knee<standing-10)[0];active_seconds=(times[active[-1]]-times[active[0]]) if len(active)>1 else 0;speed=float(np.quantile(np.abs(np.diff(knee)/np.diff(times)),.9))
 else:active_seconds=0;speed=0
 summ.extend([active_seconds,speed]);record={'id':c['id'],'expected':c['expected'],'split':c['split'],'features':summ,'coverage':coverage,'missingFrames':miss,'declaredSourceFrames':n,'decodedSourceFrames':decoded,'sampledFrames':len(times),'activeSeconds':active_seconds,'inferenceP50Seconds':float(np.median(infer)),'inferenceP95Seconds':float(np.quantile(infer,.95)),'wallSeconds':time.monotonic()-start,'times':times,'sequence':np.where(np.isfinite(arr),arr,0).tolist(),'validity':np.isfinite(arr).tolist()};records.append(record)
 (OUT/(c['id']+'.json')).write_text(json.dumps(record,indent=2));print(c['id'],'coverage',round(coverage,2),'inference ms',round(np.median(infer)*1000,1),flush=True)
# Train only after extraction is complete. No validation labels influence fitting.
tr=[r for r in records if r['split']=='train'];ev=[r for r in records if r['split']!='train'];X=np.array([r['features'] for r in tr]);y=np.array([r['expected'] for r in tr]);tests=np.array([r['features'] for r in ev])
results={}
for name,head in [('nearest-centroid',NearestCentroid()),('logistic-C1',LogisticRegression(C=1,class_weight='balanced',max_iter=1000,random_state=0))]:
 pipe=make_pipeline(StandardScaler(),head);pipe.fit(X,y);pred=pipe.predict(tests);rows=[]
 for r,label in zip(ev,pred):
  predlabel=str(label) if r['coverage']>=.8 else 'uncertain';rows.append({'id':r['id'],'split':r['split'],'expected':r['expected'],'predicted':predlabel,'correct':predlabel==r['expected'],'coverage':r['coverage']})
 results[name]={'rows':rows,'trainingN':len(tr),'eligibleForAutomaticCoaching':False}
 if name=='nearest-centroid':
  scaler=pipe.steps[0][1];est=pipe.steps[1][1];model={'classes':est.classes_.tolist(),'centroids':est.centroids_.tolist(),'mean':scaler.mean_.tolist(),'scale':scaler.scale_.tolist(),'featureCount':len(summ),'scope':'Research same-participant prototype only; no automatic advice or app integration'};(OUT/'tiny-head.json').write_text(json.dumps(model,indent=2))
(OUT/'score.json').write_text(json.dumps(results,indent=2));print(json.dumps({k:[sum(x['correct'] for x in v['rows']),len(v['rows'])] for k,v in results.items()}),flush=True)
