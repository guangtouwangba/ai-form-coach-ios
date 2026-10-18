from pathlib import Path
import json,re,statistics
B=Path(__file__).resolve().parents[1];suite=json.loads((B/'results/protocol-v1.json').read_text());sums={}
def parse_json(s):
 s=s.strip()
 if s.startswith('```') and s.endswith('```'):s=re.sub(r'^```(?:json)?\s*','',s)[:-3].strip()
 try:return json.loads(s)
 except:return None
def control(c,r):
 p=parse_json(r.get('rawOutput',''));checks={}
 if not isinstance(p,dict):return {'allPass':False,'schemaValid':False,'reason':'not a complete JSON object'}
 keys=['motion','lowest_frame','returned','knee_in','explanation'];checks['schemaValid']=set(p)==set(keys) and p.get('motion') in ['squat','static','unknown'] and p.get('returned') in ['yes','no','uncertain'] and p.get('knee_in') in ['yes','no','uncertain'] and (p.get('lowest_frame') is None or p.get('lowest_frame') in [f'F{i}' for i in range(1,7)]) and isinstance(p.get('explanation'),str)
 checks['sideKneeAbstention']=p.get('knee_in')=='uncertain'
 id=c['id']
 if id=='real-cycle':checks.update(motion=p.get('motion')=='squat',returnObserved=p.get('returned')=='yes',lowest=p.get('lowest_frame') in ['F3','F4','F5'])
 elif id=='standing-static':checks.update(motion=p.get('motion')=='static',returnObserved=p.get('returned')=='uncertain',lowest=p.get('lowest_frame') is None)
 elif id=='blank-control':checks.update(motion=p.get('motion')=='unknown',returnObserved=p.get('returned')=='uncertain',lowest=p.get('lowest_frame') is None)
 elif id=='cropped-control':checks.update(returnObserved=p.get('returned')=='uncertain',lowest=p.get('lowest_frame') is None)
 elif id=='ascent-omitted':checks.update(motion=p.get('motion')=='squat',returnObserved=p.get('returned')=='no',lowest=p.get('lowest_frame') in ['F5','F6'])
 checks['allPass']=all(checks.values());return checks
for folder in ['qwen3vl-common','qwen35-common','gemma4-common','smolvlm-common','smolvlm-native','qwen35-4b-common','qwen35-recommended','qwen35-4b-recommended','gemma4-recommended']:
 d=B/'results'/folder
 if not d.exists():continue
 rows=[];controls=[];perf=[]
 for c in suite['cases']:
  p=d/(c['id']+'.json')
  if not p.exists():continue
  r=json.loads(p.read_text());perf.append(r)
  if c['split']=='temporal-controls':controls.append({'id':c['id'],'rawOutput':r.get('rawOutput'),'checks':control(c,r)});continue
  raw=r.get('rawOutput','');pred=raw.strip().lower();pred=pred if pred in ['correct','high','low','tilt','arms','fast','uncertain'] else 'invalid';secondary='fast' if '_fast.avi' in c['video'] and c['expected']!='fast' else None
  rows.append({'id':c['id'],'split':c['split'],'expected':c['expected'],'predicted':pred,'correct':pred==c['expected'],'primaryOrSecondaryCorrect':pred in [c['expected'],secondary],'secondary':secondary,'falseTargetMatch':c['expected']!='correct' and pred=='correct','rawOutput':raw})
 summary={'rows':rows,'controls':controls,'eligibleForAutomaticCoaching':False,'statistics':{}}
 for split in ['seen-comparison','unused-trial-confirmation']:
  sub=[r for r in rows if r['split']==split];summary['statistics'][split]={'correct':sum(r['correct'] for r in sub),'n':len(sub),'primaryOrSecondaryCorrect':sum(r['primaryOrSecondaryCorrect'] for r in sub),'falseTargetMatch':sum(r['falseTargetMatch'] for r in sub),'invalid':sum(r['predicted']=='invalid' for r in sub),'abstentions':sum(r['predicted']=='uncertain' for r in sub)}
 good=[r for r in perf if r.get('success')];summary['performanceMixedTasks']={'n':len(good),'generateP50Seconds':statistics.median(r['generateSeconds'] for r in good),'maxFootprintBytes':max(r.get('peakFootprintBytes',0) for r in good),'scope':'Mixed 12-image label and 6-image JSON cases, not matched output lengths; separate repeated performance is preferred.'}
 (d/'score.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n');sums[folder]={'statistics':summary['statistics'],'controlsPassed':sum(x['checks']['allPass'] for x in controls),'controlsN':len(controls)}
(B/'results/comparison-score.json').write_text(json.dumps(sums,indent=2)+'\n');print(json.dumps(sums,indent=2))
