from pathlib import Path
import ast,json,hashlib,re,subprocess,datetime,shutil
B=Path(__file__).resolve().parents[1];R=B/'results';checks=[]
for p in B.rglob('*.json'):json.loads(p.read_text())
checks.append('All JSON parses')
for p in (B/'scripts').glob('*.py'):ast.parse(p.read_text())
checks.append('All Python scripts parse')
suite=json.loads((R/'protocol-v1.json').read_text());assert len(suite['cases'])==27
assert {s:sum(c['split']==s for c in suite['cases']) for s in ['seen-comparison','unused-trial-confirmation','temporal-controls']}=={'seen-comparison':12,'unused-trial-confirmation':10,'temporal-controls':5}
checks.append('Frozen 12 + 10 + 5 denominators')
assert hashlib.sha256((R/'frozen-suite.json').read_bytes()).hexdigest()=='822f06479ed374730707c67c263ef1af05e3853573e64e8eb136605e4637af47'
checks.append('Initial frozen suite unchanged')
unique={f['file']:f['sha256'] for c in suite['cases'] for f in c['frames']}
for path,digest in unique.items():assert hashlib.file_digest(Path(path).open('rb'),'sha256').hexdigest()==digest,path
checks.append(f'{len(unique)} source frame files match frozen SHA')
models=['qwen3vl','qwen35','qwen35-4b','gemma4','smolvlm'];inferences=0
for model in models:
 for c in suite['cases']:
  r=json.loads((R/(model+'-common')/(c['id']+'.json')).read_text());assert r['success'],(model,c['id']);inferences+=1
 for i in range(1,7):assert json.loads((R/(model+'-perf')/f'real-cycle-repeat{i}.json').read_text())['success'];inferences+=1
for model in ['qwen35','qwen35-4b','gemma4']:
 for c in suite['cases']:assert json.loads((R/(model+'-recommended')/(c['id']+'.json')).read_text())['success'];inferences+=1
 for c in json.loads((R/'diagnostic-suite.json').read_text())['cases']:assert json.loads((R/(model+'-diagnostic')/(c['id']+'.json')).read_text())['success'];inferences+=1
for c in json.loads((R/'diagnostic-suite.json').read_text())['cases']:assert json.loads((R/'smolvlm-diagnostic'/(c['id']+'.json')).read_text())['success'];inferences+=1
for c in suite['cases']:assert json.loads((R/'smolvlm-native'/(c['id']+'.json')).read_text())['success'];inferences+=1
for c in json.loads((R/'swift-gemma-diagnostic-suite.json').read_text())['cases']:assert json.loads((R/'gemma4-swift-diagnostic'/(c['id']+'.json')).read_text())['success'];inferences+=1
checks.append(f'{inferences} successful actual VLM inference records; quality graded separately')
for folder in ['pose-baseline','pose-six-frames']:
 score=json.loads((R/folder/'score.json').read_text())
 for k,v in score.items():assert len(v['rows'])==22 and not v['eligibleForAutomaticCoaching']
checks.append('Two fixed pose heads / two frame budgets have all 22 evaluation rows')
drafts=json.loads((R/'pose-baseline/review-drafts.json').read_text());assert drafts['exportParityCases']==22;assert all(x['reviewRequired'] and not x['eligibleForAutomaticCoaching'] for x in drafts['drafts'])
checks.append('22 exported classifier parity checks and research-only drafts')
patch=json.loads((B/'evidence/gemma4-runtime-patch.json').read_text());actual=Path('/tmp/coach-alternatives-venv/lib/python3.12/site-packages/mlx_vlm/models/gemma4/language.py');assert hashlib.file_digest(actual.open('rb'),'sha256').hexdigest()==patch['patchedSHA256']
checks.append('Strict Gemma shared-KV patch source hash matches')
for p in R.glob('*-download.json'):
 receipt=json.loads(p.read_text());assert receipt['completeWeightsVerified']
 for f in receipt['files']:assert (Path(receipt['directory'])/f['file']).stat().st_size==f['bytes']
checks.append('Four complete model receipts and file sizes present; upstream full hashes verified during download')
text=(B/'README.md').read_text()
for target in re.findall(r'\]\(([^)]+)\)',text):
 if '://' not in target and target!='results/execution-manifest.json':assert (B/target).exists(),target
checks.append('README local links resolve')
html=(B/'review.html').read_text();js=re.search(r'<script>(.*)</script>',html,re.S)[1];Path('/tmp/coach-model-review.js').write_text(js);subprocess.run(['node','--check','/tmp/coach-model-review.js'],check=True)
checks.append('Offline viewer JavaScript syntax valid')
logs=B/'evidence/logs';logs.mkdir(exist_ok=True)
for p in Path('/tmp').glob('coach-*.log'):
 if p.name.startswith(('coach-model-','coach-qwen35','coach-qwen3vl-common','coach-qwen3vl-perf','coach-gemma4','coach-smol','coach-pose-','coach-post-checks')):
  shutil.copy2(p,logs/p.name)
files={str(p.relative_to(B)):{'bytes':p.stat().st_size,'sha256':hashlib.file_digest(p.open('rb'),'sha256').hexdigest()} for p in B.rglob('*') if p.is_file() and p.name!='execution-manifest.json'}
manifest={'createdUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scope':'Mac-only actual model research. No iPhone install, launch, signing, commit or push. No main App source modifications this turn.','checks':checks,'allArtifactChecksPassed':True,'qualityAcceptance':'VLM automatic coaching: FAIL. Pose research signal only; no automatic coaching.','resolvedInitialFailures':['Gemma strict loading missing 60 shared-KV parameters repaired and rerun; initial queue receipt retains returncode1','AVI header framecount seeking failure repaired using sequential decoding; initial failure logs retained','Missing num2words for official Smol CPU processor installed; return_tensors changed to pt as required, then converted to np for MLX.'], 'measurementNotes':'Early common runs preceded additions of optional recommended sampling and release of prior tensor references; primary greedy inputs were unchanged. Final performance uses the same final benchmark code. Scheduler scripts had transient session PID barriers removed after completion; persisted subprocess command receipts remain actual.','files':files}
(R/'execution-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');assert (R/'execution-manifest.json').exists()
print('\n'.join(checks))
