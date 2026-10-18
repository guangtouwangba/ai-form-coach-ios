#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${COACH_POSE_PYTHON:?Set COACH_POSE_PYTHON to Python with the verified MediaPipe and OpenCV environment}"
coach_quality_output="${1:-Docs/Testing/Squat-Coaching-2026-10-16/results}"
mkdir -p "$coach_quality_output"
swift test
for coach_quality_case in standing-then-five-squats standing-five-rotated-metadata negative-frontal-moving-5319965 negative-cropped-4820063; do
  coach_quality_expected=0
  if [[ "$coach_quality_case" == standing-* ]]; then coach_quality_expected=5; fi
  "$COACH_POSE_PYTHON" Scripts/export-mediapipe-replay.py \
    "Docs/Testing/RealSquat-2026-10-15/media/$coach_quality_case.mp4" \
    "$coach_quality_output/$coach_quality_case-mediapipe.json"
  bash Scripts/replay-video.sh "$coach_quality_output/$coach_quality_case-mediapipe.json" \
    "$coach_quality_expected" "$coach_quality_output/$coach_quality_case-report.json" 2000
done
"$COACH_POSE_PYTHON" - "$coach_quality_output" <<'PY'
from pathlib import Path
import json,sys
root=Path(sys.argv[1]); rows=[]
for p in sorted(root.glob('*-report.json')):
    value=json.loads(p.read_text()); expected=value['expected']
    attempts=value['summary'].get('squatAnalysis',{}).get('attempts',[])
    assert value['actual']==expected, p
    assert len(attempts)==expected, (p,'attempt count',len(attempts))
    assert [a.get('countedRepID') for a in attempts]==list(range(1,expected+1)),p
    for attempt in attempts:
        assert attempt['endReason']=='returnedToStart',p
        assert any(a['item']=='rangeOfMotion' and a['status']=='notConfigured' for a in attempt['assessments']),p
        assert any(a['item']=='descentTempo' and a['status']=='outsideTarget' for a in attempt['assessments']),p
    rows.append(dict(file=p.name,count=expected,attempts=len(attempts),pass_=True))
(root/'mac-regression-summary.json').write_text(json.dumps(rows,indent=2))
print(json.dumps(rows,indent=2))
PY
