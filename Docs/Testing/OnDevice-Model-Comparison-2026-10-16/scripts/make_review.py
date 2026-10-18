"""Self-contained local viewer for measured outputs, with original evidence thumbnails."""
from pathlib import Path
import json,base64,io
from PIL import Image
B=Path(__file__).resolve().parents[1];s=json.loads((B/'results/protocol-v1.json').read_text());models=['qwen3vl-common','qwen35-common','qwen35-4b-common','gemma4-common','smolvlm-common','smolvlm-native','qwen35-recommended','qwen35-4b-recommended','gemma4-recommended'];images={};cases=[];drafts={x['id']:x for x in json.loads((B/'results/pose-baseline/review-drafts.json').read_text())['drafts']}
for c in s['cases']:
 frames=[]
 for f in c['frames']:
  key=f['sha256']
  if key not in images:
   im=Image.open(f['file']).convert('RGB');im.thumbnail((224,260));buf=io.BytesIO();im.save(buf,format='JPEG',quality=70);images[key]='data:image/jpeg;base64,'+base64.b64encode(buf.getvalue()).decode()
  frames.append({'id':f['id'],'time':f['actualTime'],'image':key})
 results={}
 for m in models:
  p=B/'results'/m/(c['id']+'.json')
  if p.exists():
   r=json.loads(p.read_text());results[m]={'output':r.get('rawOutput',r.get('error','')),'seconds':r.get('generateSeconds'),'success':r.get('success')}
 cases.append({'id':c['id'],'split':c['split'],'expected':c.get('expected','按可见事实检查，非动作质量标签'),'frames':frames,'results':results,'pose':drafts.get(c['id'])})
data=json.dumps({'cases':cases,'images':images,'models':models},ensure_ascii=False).replace('<','\\u003c')
html='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>动作判错 · Mac 实测证据</title><style>
*{box-sizing:border-box}body{margin:0;background:#f6f7f9;color:#18232e;font:15px/1.6 -apple-system,BlinkMacSystemFont, sans-serif}main{max-width:1180px;margin:auto;padding:36px 24px}h1{font-size:30px;margin:4px 0 12px}h2{font-size:19px}.note{color:#536171;max-width:900px}select{font:inherit;max-width:100%;padding:10px 14px;background:white;border:1px solid #bcc5ce;border-radius:8px}nav{display:flex;gap:18px;flex-wrap:wrap;margin:28px 0}section{background:white;border:1px solid #dee3e9;border-radius:12px;padding:20px;margin:18px 0}.frames{display:grid;grid-template-columns:repeat(6,minmax(0,1fr));gap:12px}.frame img{display:block;max-width:100%;height:175px;object-fit:contain;background:#f2f3f5;margin:auto}.frame small{display:block;text-align:center;color:#586677;margin-top:7px}pre{white-space:pre-wrap;word-break:break-word;font:14px/1.7 ui-monospace,monospace;margin:8px 0}#truth{font-weight:600}.badge{display:inline-block;font-size:12px;padding:4px 10px;border-radius:20px;background:#e8eef5;color:#345273}.sub{color:#667482;font-size:13px}.warn{background:#fff4dd;color:#825211;padding:12px;border-radius:8px}details{margin-top:12px}button{cursor:pointer}a{color:#225e94}@media(max-width:700px){main{padding:22px 14px}.frames{grid-template-columns:repeat(3,minmax(0,1fr))}.frame img{height:145px}section{padding:14px}h1{font-size:25px}}
</style><main><span class="badge">仅 Mac 研究验证 · 自动建议未启用</span><h1>先看证据，再看模型结论</h1><p class="note">用同一批真实视频比较模型判断。OfficeSquat 的标签来自作者文件名，描述特定的举臂深蹲示范；本轮主要为同一参与者，不能换算成全人群健身准确率。12 段同批对比 + 10 段此前未测的试次 + 5 个事实反例。</p><nav><label>选择片段<br><select id="case"></select></label><label>选择模型 / 运行模式<br><select id="model"></select></label></nav><p id="truth"></p><p class="sub" id="split"></p><section id="reference"><h2>参考动作 R</h2><div class="frames" id="rframes"></div></section><section><h2>待评片段 F · 按时间顺序</h2><div class="frames" id="fframes"></div></section><section><h2>模型原始回答</h2><p class="sub" id="time"></p><pre id="answer"></pre></section><section id="pose"><h2>骨架小分类器 · 待审核候选</h2><p id="pose-answer"></p><div class="warn">下列文本只作研究审核，不会发送给 App 用户。分类与骨架估计都仍有误差。</div><details><summary>展开关节测量及反馈草稿</summary><pre id="pose-data"></pre></details></section><p class="sub">保留拒答、无效格式和误判。完整口径、性能、源码与模型文件校验见同目录 README.md。</p></main><script>const DATA=__DATA__;
const sel=document.querySelector('#case'),model=document.querySelector('#model');
for(const c of DATA.cases){let o=document.createElement('option');o.value=c.id;o.textContent=c.id+' · '+c.expected;sel.append(o)}
for(const m of DATA.models){if(DATA.cases.some(c=>c.results[m])){let o=document.createElement('option');o.value=m;o.textContent=m;model.append(o)}}
function frames(c,prefix,id){let parent=document.getElementById(id);parent.replaceChildren();for(const f of c.frames.filter(f=>f.id.startsWith(prefix))){let div=document.createElement('div');div.className='frame';let im=document.createElement('img');im.src=DATA.images[f.image];im.alt=f.id;div.append(im);let text=document.createElement('small');text.textContent=f.id+' · '+f.time.toFixed(2)+' s';div.append(text);parent.append(div)}}
function render(){const c=DATA.cases.find(c=>c.id===sel.value),r=c.results[model.value];document.querySelector('#truth').textContent='作者主标签 / 对照目标：'+c.expected;document.querySelector('#split').textContent=c.split;frames(c,'R','rframes');frames(c,'F','fframes');document.querySelector('#reference').hidden=!c.frames.some(f=>f.id.startsWith('R'));document.querySelector('#answer').textContent=r?r.output:'该模式未运行此片段。';document.querySelector('#time').textContent=r&&r.seconds?'本次模型推理 '+r.seconds.toFixed(2)+' 秒（不等同手机性能）':'';document.querySelector('#pose').hidden=!c.pose;if(c.pose){document.querySelector('#pose-answer').textContent='候选：'+c.pose.candidateIssue+' · 关键点可用率 '+Math.round(c.pose.jointCoverage*100)+'%';document.querySelector('#pose-data').textContent=JSON.stringify(c.pose,null,2)}}
sel.value='ascent-omitted';model.value='gemma4-common';sel.addEventListener('change',render);model.addEventListener('change',render);render();
</script></html>'''
(B/'review.html').write_text(html.replace('__DATA__',data));print('Created self-contained review:',len(images),'evidence frames')
