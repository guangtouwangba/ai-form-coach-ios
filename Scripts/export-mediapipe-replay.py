#!/usr/bin/env python3
"""Sequential real-video MediaPipe export for the shared Swift replay core. No labels or model fitting."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import time

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

NAMES = "nose leftEyeInner leftEye leftEyeOuter rightEyeInner rightEye rightEyeOuter leftEar rightEar mouthLeft mouthRight leftShoulder rightShoulder leftElbow rightElbow leftWrist rightWrist leftPinky rightPinky leftIndex rightIndex leftThumb rightThumb leftHip rightHip leftKnee rightKnee leftAnkle rightAnkle leftHeel rightHeel leftFootIndex rightFootIndex".split()


def sha(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--hz", type=float, default=10)
    args = parser.parse_args()
    if not 5 <= args.hz <= 30:
        parser.error("--hz must be between 5 and 30")
    model = Path(__file__).resolve().parents[1] / "App/pose_landmarker_full.task"
    model_sha = sha(model)
    if model_sha != "4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad":
        raise ValueError("Pose model SHA does not match the verified App asset")
    cap = cv2.VideoCapture(str(args.video))
    if not cap.isOpened():
        raise ValueError("Video cannot be opened")
    cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    fps = cap.get(cv2.CAP_PROP_FPS)
    declared = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    options = vision.PoseLandmarkerOptions(
        base_options=python.BaseOptions(model_asset_path=str(model), delegate=python.BaseOptions.Delegate.CPU),
        running_mode=vision.RunningMode.VIDEO, num_poses=2,
        min_pose_detection_confidence=.5, min_pose_presence_confidence=.5, min_tracking_confidence=.5)
    frames, decoded, fallbacks, previous, next_sample = [], 0, 0, -1, 0
    try:
        with vision.PoseLandmarker.create_from_options(options) as detector:
            while True:
                ok, frame = cap.read()
                if not ok:
                    break
                raw_time = cap.get(cv2.CAP_PROP_POS_MSEC)
                if not math.isfinite(raw_time) or raw_time <= previous:
                    if not math.isfinite(fps) or fps <= 0:
                        raise ValueError("Video has neither usable timestamps nor FPS")
                    raw_time = decoded * 1000 / fps
                    fallbacks += 1
                decoded += 1
                if raw_time <= previous:
                    raise ValueError("Non-monotonic decoded timestamps")
                previous = raw_time
                if raw_time < next_sample:
                    continue
                timestamp = round(raw_time)
                next_sample = raw_time + 1000 / args.hz - .1
                image = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
                started = time.perf_counter()
                result = detector.detect_for_video(image, timestamp)
                elapsed = (time.perf_counter() - started) * 1000
                landmarks = {}
                if len(result.pose_landmarks) == 1:
                    for name, point in zip(NAMES, result.pose_landmarks[0]):
                        values = [point.x, point.y, point.z, point.visibility, point.presence]
                        if all(math.isfinite(x) for x in values):
                            landmarks[name] = dict(zip(["x", "y", "z", "visibility", "presence"], values), isPredicted=False)
                # Swift Codable uses an alternating array for a dictionary with enum keys.
                encoded = [value for pair in landmarks.items() for value in pair]
                frames.append(dict(timestampMs=timestamp, landmarks=encoded, inferenceMs=elapsed,
                                   engineVersion="mediapipe-full-python-" + mp.__version__ + "-" + model_sha[:12],
                                   imageWidth=frame.shape[1], imageHeight=frame.shape[0], detectedPersonCount=len(result.pose_landmarks)))
    finally:
        cap.release()
    if not frames:
        raise ValueError("No frames decoded")
    if frames[-1]["timestampMs"] > 180_000:
        raise ValueError("Use videos of 3 minutes or less")
    metadata = dict(sourceSHA256=sha(args.video), modelSHA256=model_sha, sampleRateHz=args.hz,
                    declaredFrames=declared, decodedFrames=decoded, sampledFrames=len(frames),
                    timestampFallbackFrames=fallbacks, orientationPolicy="OpenCV orientation auto; dimensions from decoded pixels",
                    exporterVersion="mediapipe-replay-1")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(dict(version=1, metadata=metadata, frames=frames), allow_nan=False))
    print(json.dumps(dict(output=str(args.output), **metadata), indent=2))


if __name__ == "__main__":
    main()
