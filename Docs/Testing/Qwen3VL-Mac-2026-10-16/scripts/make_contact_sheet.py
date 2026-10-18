#!/usr/bin/env python3
from pathlib import Path
import json
from PIL import Image,ImageOps,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
results=ROOT/'results/performance-monotonic'
rows=[('perf-01','Real cycle: standing -> bottom -> standing'),('standing-static','Static control: identical standing images'),('blank-control','Blank control: no person'),('ascent-omitted','Incomplete cycle: ascent is absent')]
font=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',18)
canvas=Image.new('RGB',(1000,1120),'#f2f4f7');draw=ImageDraw.Draw(canvas)
for row,(name,title) in enumerate(rows):
 d=json.loads((results/(name+'.json')).read_text());y=row*280
 draw.text((20,y+10),title,font=font,fill='#142232')
 for col,index in enumerate([0,3,5]):
  f=d['frames'][index];image=Image.open(f['file']).convert('RGB')
  thumb=ImageOps.contain(image,(220,210));x=20+col*240
  canvas.paste(thumb,(x,y+40));draw.text((x,y+252),f"{f['id']} / {f['actualTime']:.2f}s",font=font,fill='#344354')
 raw=d['rawOutput'].strip()
 if raw.startswith('```json\n') and raw.endswith('\n```'):raw=raw[8:-4]
 obj=json.loads(raw)
 for i,line in enumerate([f"motion: {obj['motion']}",f"lowest: {obj['lowest_frame']}",f"returned: {obj['returned']}",f"knee_in: {obj['knee_in']}",f"gate: {'candidate' if d['observationGate']['acceptedAsObservation'] else 'rejected'}"]):
  draw.text((752,y+55+i*30),line,font=font,fill='#226b44' if row==0 else '#a33232')
canvas.save(ROOT/'failure-contact-sheet.jpg',quality=90)
print(ROOT/'failure-contact-sheet.jpg')
