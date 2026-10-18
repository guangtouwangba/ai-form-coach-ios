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
            guard let format = CMSampleBufferGetFormatDescription(buffer.value) else { return nil }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            let swapped = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
            let width = Double(swapped ? dimensions.height : dimensions.width)
            let height = Double(swapped ? dimensions.width : dimensions.height)
            let request = VNDetectHumanBodyPoseRequest()
            request.revision = VNDetectHumanBodyPoseRequestRevision1

            let handler = VNImageRequestHandler(cmSampleBuffer: buffer.value, orientation: orientation)
            do { try handler.perform([request]) }
            catch {
                #if targetEnvironment(simulator)
                throw NSError(domain: "CoachSimulatorVision", code: 1, userInfo: [NSLocalizedDescriptionKey: "当前模拟器无法启动人体姿态识别。可运行内置关键点测试；真人录像请在 iPhone 上分析。", NSUnderlyingErrorKey: error])
                #else
                throw error
                #endif
            }
            // Do not silently pick one person when someone else enters the frame.
            guard let results = request.results, results.count == 1, let observation = results.first else {
                return PoseObservation(timestampMs: timestampMs, landmarks: [:], engineVersion: self.engineVersion, imageWidth: width, imageHeight: height, detectedPersonCount: request.results?.count ?? 0)
            }
            let map: [(LandmarkID, VNHumanBodyPoseObservation.JointName)] = [
                (.nose, .nose), (.leftEye, .leftEye), (.rightEye, .rightEye), (.leftEar, .leftEar), (.rightEar, .rightEar),
                (.leftElbow, .leftElbow), (.rightElbow, .rightElbow), (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
                (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
                (.leftHip, .leftHip), (.rightHip, .rightHip), (.leftKnee, .leftKnee),
                (.rightKnee, .rightKnee), (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
            ]
            let points = try observation.recognizedPoints(.all)
            var landmarks: [LandmarkID: FormCoachCore.Landmark] = [:]
            for (id, joint) in map {
                guard let value = points[joint], value.confidence > 0 else { continue }
                // Vision uses a lower-left origin while MediaPipe and the core
                // contract use image coordinates with a top-left origin.
                landmarks[id] = FormCoachCore.Landmark(x: value.location.x, y: 1 - value.location.y, visibility: Double(value.confidence), presence: Double(value.confidence))
            }
            let elapsed = ContinuousClock.now - started
            return PoseObservation(timestampMs: timestampMs, landmarks: landmarks, inferenceMs: elapsed.milliseconds, engineVersion: self.engineVersion, imageWidth: width, imageHeight: height, detectedPersonCount: 1)
        }
        return try await task.value
    }
}

enum PoseEngineChoice: String, CaseIterable, Codable, Identifiable {
    case mediaPipe, appleVision
    var id: String { rawValue }
    var title: String { self == .mediaPipe ? "MediaPipe Full" : "Apple Vision" }
    var isAvailable: Bool {
        if self == .appleVision { return true }
        #if canImport(MediaPipeTasksVision) && os(iOS)
        return true
        #else
        return false
        #endif
    }
    static var recommended: Self { Self.mediaPipe.isAvailable ? .mediaPipe : .appleVision }
    func makePerception() -> LivePosePerception {
        if self == .appleVision { return AppleVisionPosePerception() }
        #if canImport(MediaPipeTasksVision) && os(iOS)
        return MediaPipePosePerception()
        #else
        return UnavailablePosePerception()
        #endif
    }
}

private final class UnavailablePosePerception: LivePosePerception {
    let engineVersion = "mediapipe-unavailable"
    func process(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, timestampMs: Int) async throws -> PoseObservation? {
        throw NSError(domain: "CoachPose", code: 1, userInfo: [NSLocalizedDescriptionKey: "此运行环境未链接 MediaPipe iOS 运行库，请选择 Apple Vision。"])
    }
}

#if canImport(MediaPipeTasksVision) && os(iOS)
import MediaPipeTasksVision
import CoreImage

/// Sequential timestamped video mode also serves the live camera. It retains
/// MediaPipe tracking without an async callback that can silently drop requests.
/// CameraService supplies at most one frame at a time; blocking work stays here.
final class MediaPipePosePerception: LivePosePerception {
    let engineVersion = "mediapipe-pose-full-1.1.1"
    private let queue = DispatchQueue(label: "coach.pose.mediapipe", qos: .userInitiated)
    private var landmarker: PoseLandmarker?
    private var previousTimestamp = -1
    private lazy var imageContext = CIContext(options: [.cacheIntermediates: false])

    func process(_ sampleBuffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, timestampMs: Int) async throws -> PoseObservation? {
        let buffer = SendableSampleBuffer(sampleBuffer)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let started = ContinuousClock.now
                    if landmarker == nil || timestampMs <= previousTimestamp {
                        guard let path = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") else {
                            throw NSError(domain: "CoachPose", code: 2, userInfo: [NSLocalizedDescriptionKey: "MediaPipe 模型文件缺失，请重新安装完整版本。"])
                        }
                        let options = PoseLandmarkerOptions()
                        options.baseOptions.modelAssetPath = path
                        options.runningMode = .video
                        options.numPoses = 2
                        options.minPoseDetectionConfidence = 0.5
                        options.minPosePresenceConfidence = 0.5
                        options.minTrackingConfidence = 0.5
                        landmarker = try PoseLandmarker(options: options)
                    }
                    guard let format = CMSampleBufferGetFormatDescription(buffer.value), let landmarker else {
                        throw NSError(domain: "CoachPose", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法读取相机帧格式。"])
                    }
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format)
                    let swapped = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
                    let width = Double(swapped ? dimensions.height : dimensions.width)
                    let height = Double(swapped ? dimensions.width : dimensions.height)
                    let image: MPImage
                    if orientation == .up {
                        image = try MPImage(sampleBuffer: buffer.value)
                    } else {
                        // MediaPipe rotates the inference ROI but projects its
                        // output back into the original image coordinates.
                        // Normalize pixels first so every engine emits the
                        // same upright, top-left coordinate contract. This
                        // also handles mirrored source videos explicitly.
                        guard let source = CMSampleBufferGetImageBuffer(buffer.value) else {
                            throw NSError(domain: "CoachPose", code: 4, userInfo: [NSLocalizedDescriptionKey: "无法读取视频像素。"])
                        }
                        let oriented = CIImage(cvPixelBuffer: source).oriented(orientation)
                        var pixel: CVPixelBuffer?
                        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(width), Int(height), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
                        guard status == kCVReturnSuccess, let pixel else {
                            throw NSError(domain: "CoachPose", code: 5, userInfo: [NSLocalizedDescriptionKey: "无法准备方向校正后的视频帧。"])
                        }
                        let upright = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
                        imageContext.render(upright, to: pixel)
                        image = try MPImage(pixelBuffer: pixel)
                    }
                    let result = try landmarker.detect(videoFrame: image, timestampInMilliseconds: timestampMs)
                    previousTimestamp = timestampMs
                    let ids: [LandmarkID] = [.nose, .leftEyeInner, .leftEye, .leftEyeOuter, .rightEyeInner, .rightEye, .rightEyeOuter, .leftEar, .rightEar, .mouthLeft, .mouthRight, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftPinky, .rightPinky, .leftIndex, .rightIndex, .leftThumb, .rightThumb, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .leftHeel, .rightHeel, .leftFootIndex, .rightFootIndex]
                    var landmarks: [LandmarkID: FormCoachCore.Landmark] = [:]
                    if result.landmarks.count == 1, let pose = result.landmarks.first {
                        for (index, id) in ids.enumerated() where index < pose.count {
                            let point = pose[index]
                            landmarks[id] = FormCoachCore.Landmark(x: Double(point.x), y: Double(point.y), z: Double(point.z), visibility: point.visibility?.doubleValue ?? 0, presence: point.presence?.doubleValue ?? 0)
                        }
                    }
                    continuation.resume(returning: PoseObservation(timestampMs: timestampMs, landmarks: landmarks, inferenceMs: (ContinuousClock.now - started).milliseconds, engineVersion: engineVersion, imageWidth: width, imageHeight: height, detectedPersonCount: result.landmarks.count))
                } catch { continuation.resume(throwing: error) }
            }
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
