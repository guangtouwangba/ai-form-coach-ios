#!/usr/bin/env python3
"""Download the complete pinned MLX model; verify size and upstream LFS SHA256."""
from pathlib import Path
import concurrent.futures,hashlib,json,subprocess,time,argparse
ROOT=Path(__file__).resolve().parents[4]
EVIDENCE=ROOT/'Docs/Research/Qwen3VL-2026-10-16/evidence'
parser=argparse.ArgumentParser();parser.add_argument('--bf16',action='store_true');args=parser.parse_args()
REPO='Qwen/Qwen3-VL-2B-Instruct' if args.bf16 else 'mlx-community/Qwen3-VL-2B-Instruct-4bit'
META=json.loads((EVIDENCE/(REPO.replace('/','--')+'--metadata.json')).read_text())
REV='89644892e4d85e24eaac8bacfd4f463576704203' if args.bf16 else '9c4f5209e57b31f4b9dfba735de3fb983739c9cc'
assert META['sha']==REV
DEST=Path.home()/'Library/Application Support/AIFormCoach/Models'/('Qwen3-VL-2B-Instruct-BF16' if args.bf16 else 'Qwen3-VL-2B-Instruct-4bit')/REV
DEST.mkdir(parents=True,exist_ok=True)

def one(item):
    name=item['rfilename']
    if name.startswith('.') or name.endswith('.gitattributes'):return None
    target=DEST/name;target.parent.mkdir(parents=True,exist_ok=True)
    expected=item.get('lfs',{}).get('sha256')
    def valid(path):
        return path.exists() and path.stat().st_size==item['size'] and (not expected or hashlib.file_digest(path.open('rb'),'sha256').hexdigest()==expected)
    start=time.monotonic()
    if not valid(target):
        part=target.with_suffix(target.suffix+'.part')
        url=f'https://huggingface.co/{REPO}/resolve/{REV}/{name}?download=true'
        subprocess.run(['curl','--fail','--location','--retry','3','--connect-timeout','30','--continue-at','-','--output',str(part),url],check=True)
        if not valid(part):raise RuntimeError(f'Integrity mismatch: {name}')
        part.replace(target)
    digest=hashlib.file_digest(target.open('rb'),'sha256').hexdigest()
    print(json.dumps({'file':name,'bytes':target.stat().st_size,'sha256':digest,'seconds':time.monotonic()-start}),flush=True)
    return {'file':name,'bytes':target.stat().st_size,'sha256':digest,'upstreamExpectedSHA256':expected}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
    files=[x for x in ex.map(one,META['siblings']) if x]
receipt={'repo':META['id'],'revision':REV,'directory':str(DEST),'files':files,'completeWeightsVerified':True}
out=ROOT/'Docs/Testing/Qwen3VL-Mac-2026-10-16/results'/('download-receipt-bf16.json' if args.bf16 else 'download-receipt.json')
out.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n')
print('COMPLETE '+str(DEST),flush=True)
