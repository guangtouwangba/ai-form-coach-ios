#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build >/dev/null
replay_build_path="$(swift build --show-bin-path)"
replay_binary="${TMPDIR:-/tmp}/form-coach-replay-${UID}"
# Compile the exact same decoder and Vision adapter as the iOS App. Core
# object files come from SwiftPM; no duplicate implementation or fake poses.
swiftc -parse-as-library -I "$replay_build_path/Modules" \
  "$replay_build_path/FormCoachCore.build/"*.o \
  App/PoseAdapters.swift App/VideoReplayAnalyzer.swift Scripts/ReplayCLI.swift \
  -o "$replay_binary"
exec "$replay_binary" "$@"
