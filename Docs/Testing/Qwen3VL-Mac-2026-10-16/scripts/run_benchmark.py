#!/usr/bin/env python3
"""Rebuild/run the pinned Mac benchmark. Never installs or launches a phone app."""
from pathlib import Path
import argparse,json,subprocess
ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser()
p.add_argument('--bf16',action='store_true');p.add_argument('--skip-build',action='store_true')
p.add_argument('--suite',type=Path,default=HERE/'results/performance-final-suite.json')
p.add_argument('--out',type=Path,required=True)
a=p.parse_args()
receipt=HERE/'results'/('download-receipt-bf16.json' if a.bf16 else 'download-receipt.json')
# Revalidate current local files, even if a historical receipt exists.
subprocess.run(['python3',str(HERE/'scripts/download_model.py')]+(['--bf16'] if a.bf16 else []),check=True)
model=json.loads(receipt.read_text())
assert model['completeWeightsVerified']
preflight=ROOT/'Docs/Research/Qwen3VL-2026-10-16/preflight'
build=Path('/tmp/coach-qwen-preflight-build')
if not a.skip_build:
 subprocess.run(['xcodebuild','-scheme','CoachVideoBenchmark','-configuration','Release','-destination','platform=macOS,arch=arm64','-derivedDataPath',str(build),'-jobs','4','CODE_SIGNING_ALLOWED=NO','build'],cwd=preflight,check=True)
subprocess.run(['/usr/bin/time','-l',str(build/'Build/Products/Release/CoachVideoBenchmark'),model['directory'],str(a.suite.resolve()),str(a.out.resolve())],cwd=ROOT,check=True)
