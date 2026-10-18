# Third-party notices

## MediaPipe Pose Landmarker

This repository includes `App/pose_landmarker_full.task`, the Pose Landmarker
Full model bundle published by Google MediaPipe. The model is distributed under
the [Apache License 2.0](LICENSES/Apache-2.0.txt) according to its model card.

- Model documentation: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker
- Model card: https://developers.google.com/static/ml-kit/images/vision/pose-detection/pose_model_card.pdf
- MediaPipe source and license: https://github.com/google-ai-edge/mediapipe
- Bundled model SHA-256: `4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad`

MediaPipe and the model remain subject to their respective upstream terms and
licenses. They are not relicensed by this repository's MIT License.

## MediaPipe Tasks runtime

The iOS application also links Google's official `MediaPipeTasksVision` Swift
Package, version 1.1.1, pinned to source revision
`7dd8fe00c17e7732818ea1406c4fb64beb237e6c`. Its runtime and bundled dependencies
remain covered by the upstream licenses and notices distributed with that
package. Source: https://github.com/google-ai-edge/mediapipe

## Apple frameworks

The application uses Apple Vision, AVFoundation, AVFAudio, SwiftUI and
SwiftData. Their use and redistribution are governed by Apple's SDK and
developer agreements; those frameworks are not included in this repository.
