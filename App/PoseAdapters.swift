import AVFoundation
import Foundation
import ImageIO
import Vision
import FormCoachCore

protocol LivePosePerception: AnyObject {
    var engineVersion: String { get }
    func process(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, timestampMs: Int) async throws -> PoseObservation?
}

final class SendableSampleBuffer: @unchecked Sendable {
    let value: CMSampleBuffer
    init(_ value: CMSampleBuffer) { self.value = value }
}

final class AppleVisionPosePerception: LivePosePerception {
    let engineVersion = "apple-vision-2d-revision-1"

    func process(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, timestampMs: Int) async throws -> PoseObservation? {
        let buffer = SendableSampleBuffer(sampleBuffer)
        let task = Task.detached(priority: .userInitiated) { () throws -> PoseObservation? in
            let started = ContinuousClock.now
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cmSampleBuffer: buffer.value, orientation: orientation)
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let map: [(LandmarkID, VNHumanBodyPoseObservation.JointName)] = [
                (.nose, .nose), (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
                (.leftHip, .leftHip), (.rightHip, .rightHip), (.leftKnee, .leftKnee),
                (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
            ]
            let points = try observation.recognizedPoints(.all)
            var landmarks: [LandmarkID: Landmark] = [:]
            for (id, joint) in map {
                guard let value = points[joint], value.confidence > 0 else { continue }
                // Vision uses a lower-left origin while MediaPipe and the core
                // contract use image coordinates with a top-left origin.
                landmarks[id] = Landmark(x: value.location.x, y: 1 - value.location.y, visibility: Double(value.confidence), presence: Double(value.confidence))
            }
            let elapsed = ContinuousClock.now - started
            return PoseObservation(timestampMs: timestampMs, landmarks: landmarks, inferenceMs: elapsed.milliseconds, engineVersion: self.engineVersion)
        }
        return try await task.value
    }
}

#if MEDIAPIPE_ENABLED && canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
import UIKit

final class MediaPipePosePerception: NSObject, LivePosePerception, PoseLandmarkerLiveStreamDelegate {
    let engineVersion = "mediapipe-pose-full-1"
    private var continuations: [Int: CheckedContinuation<PoseObservation?, Error>] = [:]
    private let lock = NSLock()
    private lazy var landmarker: PoseLandmarker = {
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.5
        options.minPosePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        options.outputSegmentationMasks = false
        options.poseLandmarkerLiveStreamDelegate = self
        return try! PoseLandmarker(options: options)
    }()

    func process(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, timestampMs: Int) async throws -> PoseObservation? {
        let image = try MPImage(sampleBuffer: sampleBuffer, orientation: UIImage.Orientation(orientation))
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock(); continuations[timestampMs] = continuation; lock.unlock()
            do { try landmarker.detectAsync(image: image, timestampInMilliseconds: timestampMs) }
            catch {
                lock.lock(); continuations.removeValue(forKey: timestampMs); lock.unlock()
                continuation.resume(throwing: error)
            }
        }
    }

    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        lock.lock(); let continuation = continuations.removeValue(forKey: timestampInMilliseconds); lock.unlock()
        guard let continuation else { return }
        if let error { continuation.resume(throwing: error); return }
        guard let pose = result?.landmarks.first else { continuation.resume(returning: nil); return }
        let ids: [Int: LandmarkID] = [0:.nose, 11:.leftShoulder, 12:.rightShoulder, 23:.leftHip, 24:.rightHip, 25:.leftKnee, 26:.rightKnee, 27:.leftAnkle, 28:.rightAnkle, 29:.leftHeel, 30:.rightHeel, 31:.leftFootIndex, 32:.rightFootIndex]
        var landmarks: [LandmarkID: Landmark] = [:]
        for (index, id) in ids where index < pose.count {
            let point = pose[index]
            landmarks[id] = Landmark(x: Double(point.x), y: Double(point.y), z: Double(point.z), visibility: point.visibility?.doubleValue ?? 0, presence: point.presence?.doubleValue ?? 0)
        }
        continuation.resume(returning: PoseObservation(timestampMs: timestampInMilliseconds, landmarks: landmarks, engineVersion: engineVersion))
    }
}

private extension UIImage.Orientation {
    init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
#endif

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
