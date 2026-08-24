#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

expected_model_sha="4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad"
actual_model_sha="$(shasum -a 256 App/pose_landmarker_full.task | awk '{print $1}')"
if [[ "$actual_model_sha" != "$expected_model_sha" ]]; then
  echo "Model checksum mismatch: $actual_model_sha" >&2
  exit 1
fi

swift test

if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild \
    -project AIFormCoach.xcodeproj \
    -target AIFormCoach \
    -sdk iphonesimulator17.5 \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    ARCHS=arm64 \
    build
fi

echo "Verification passed."
