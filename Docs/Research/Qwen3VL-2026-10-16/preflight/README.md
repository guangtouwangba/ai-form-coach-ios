# Isolated compatibility audit

This package does not modify the app or install anything on a phone. Pin versions
with Package.resolved. Disable the optional Foundation Models trait because the
current SDK is 26.5. Use an explicit tokenizer protocol adapter rather than
changing Xcode's global macro trust settings.

From this directory:

```sh
xcodebuild -scheme CoachQwenPreflight -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/coach-qwen-preflight-build -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -scheme CoachConfigAudit -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/coach-qwen-preflight-build -jobs 4 \
  CODE_SIGNING_ALLOWED=NO build

/tmp/coach-qwen-preflight-build/Build/Products/Debug/CoachConfigAudit \
  /tmp/coach-qwen-tokenizer
```

The tokenizer folder must contain the **same fixed model revision's** config.json,
preprocessor_config.json, tokenizer_config.json, tokenizer.json and chat template.
This run used 9c4f5209e57b31f4b9dfba735de3fb983739c9cc. Archived tokenizer SHA256 and
configuration results are in ../evidence. The full 11.4MB tokenizer is in /tmp,
not duplicated into the project; model weights were never downloaded.

The executable checks real Qwen configuration decoding, Chinese text round-trip,
and image/video special markers. It never calls loadLocalWeights. The separate CoachVideoBenchmark executable now calls the real loader and evaluates
weights in the authorized Mac experiment. See ../../../Testing/Qwen3VL-Mac-2026-10-16/README.md
(relative source path: Docs/Testing/Qwen3VL-Mac-2026-10-16/README.md). The
configuration-only executable remains a CPU tokenization check.

../scripts/prepare_combined_audit.py copies the app into a fresh temporary folder,
adds this package and retains a loader reference to check the link. It prints the
folder path. Build scheme AIFormCoach-Integration there with the same generic iOS destination and
CODE_SIGNING_ALLOWED=NO. Never install or launch this audit app. The repository's
main app project stays unchanged. Dependency revisions and the resulting build
status are recorded in ../evidence/build-audit.json.

Actual MLXArray evaluation is not supported in iOS Simulator. The Mac executable
uses CPU tokenization and JSON decoding only; simulator UI and phone inference
acceptance are separate work.
