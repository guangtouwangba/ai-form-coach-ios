#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${COACH_TEST_SIMULATOR:?Set COACH_TEST_SIMULATOR to an iOS Simulator UUID}"
coach_test_root="$(mktemp -d "${TMPDIR:-/tmp}/coach-mediapipe-regression.XXXXXX")"
coach_derived="$coach_test_root/build"
echo "Simulator-only real MediaPipe regression; artifacts: $coach_test_root"
xcodebuild -project AIFormCoach.xcodeproj -scheme AIFormCoach-Integration \
  -configuration Debug -destination "platform=iOS Simulator,id=$COACH_TEST_SIMULATOR" \
  -derivedDataPath "$coach_derived" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  build-for-testing > "$coach_test_root/build.log" 2>&1
python3 - "$coach_derived/Build/Products" <<'PY'
from pathlib import Path
import plistlib,sys
root=Path(sys.argv[1])
files=list(root.glob('AIFormCoach-Integration_*.xctestrun'))
if len(files)!=1: raise SystemExit('Expected exactly one integration test run configuration')
value=plistlib.loads(files[0].read_bytes())
value['AIFormCoachTests'].setdefault('EnvironmentVariables',{})['COACH_MEDIAPIPE_VIDEO_TEST']='1'
(root/'MediaPipe-RealVideo.xctestrun').write_bytes(plistlib.dumps(value))
PY
xcodebuild test-without-building -xctestrun "$coach_derived/Build/Products/MediaPipe-RealVideo.xctestrun" \
  -destination "platform=iOS Simulator,id=$COACH_TEST_SIMULATOR" \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 120 \
  -resultBundlePath "$coach_test_root/results.xcresult" | tee "$coach_test_root/tests.log"
