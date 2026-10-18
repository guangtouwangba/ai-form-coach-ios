import AVFoundation
import Foundation
import ImageIO
import FormCoachCore

struct PoseReplayFile: Codable, Sendable {
    let version: Int
    let frames: [PoseObservation]
    var metadata: PoseReplayMetadata? = nil
}

struct PoseReplayMetadata: Codable, Sendable {
    let sourceSHA256: String
    let modelSHA256: String
    let sampleRateHz: Double
    let decodedFrames: Int
    let sampledFrames: Int
    let timestampFallbackFrames: Int
    let orientationPolicy: String
    let exporterVersion: String
}

struct ReplaySnapshot: Sendable {
    let timeMs: Int
    let progress: Double
    let count: Int
    let message: String
    let baselineReady: Bool
    var pose: PoseObservation? = nil
    var failure: PoseFailureReason = .none
}

struct PoseComparisonReport: Codable, Identifiable, Sendable {
    var id: String { engine }
    let engine: String
    let file: String
    let frames: Int
    let firstStandingMs: Int?
    let count: Int
    let inferenceP50Ms: Double
    let inferenceP95Ms: Double
    let maximumFrameGapMs: Int
    let rejectionCounts: [String: Int]
    let reps: [RepSummary]
    let engineVersion: String
    let usablePoseFrames: Int
    let squatAnalysis: SquatAnalysis?
}

struct PoseComparisonExport: Codable {
    let createdAt: Date
    let source: String
    let reports: [PoseComparisonReport]
    let errors: [String: String]
}

actor ReplayRunDiagnostics {
    private var frames = 0
    private var firstStanding: Int?
    private var timings: [Double] = []
    private var failures: [String: Int] = [:]
    private var previous: Int?
    private var maximumGap = 0
    private var engineVersion = "not-observed"
    private var usableFrames = 0
    func record(_ frame: PoseObservation, _ update: SquatUpdate) {
        frames += 1; timings.append(frame.inferenceMs)
        engineVersion = frame.engineVersion
        if SquatFeatures.assess(frame).features != nil { usableFrames += 1 }
        if update.baselineReady && firstStanding == nil { firstStanding = frame.timestampMs }
        if update.failure != .none { failures[update.failure.rawValue, default: 0] += 1 }
        if let previous { maximumGap = max(maximumGap, frame.timestampMs - previous) }
        previous = frame.timestampMs
    }
    func report(engine: String, file: String, summary: WorkoutSummary) -> PoseComparisonReport {
        let values = timings.sorted()
        func percentile(_ p: Double) -> Double { values.isEmpty ? 0 : values[Int(Double(values.count - 1) * p)] }
        return PoseComparisonReport(engine: engine, file: file, frames: frames, firstStandingMs: firstStanding, count: summary.reps.count, inferenceP50Ms: percentile(0.5), inferenceP95Ms: percentile(0.95), maximumFrameGapMs: maximumGap, rejectionCounts: failures, reps: summary.reps, engineVersion: engineVersion, usablePoseFrames: usableFrames, squatAnalysis: summary.squatAnalysis)
    }
}

enum VideoReplayAnalyzer {
    static func orientation(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let angle = atan2(transform.b, transform.a)
        let mirrored = transform.a * transform.d - transform.b * transform.c < 0
        if abs(angle - .pi / 2) < 0.1 { return mirrored ? .rightMirrored : .right }
        if abs(angle + .pi / 2) < 0.1 { return mirrored ? .leftMirrored : .left }
        if abs(angle) > 3 { return mirrored ? .downMirrored : .down }
        return mirrored ? .upMirrored : .up
    }

    static func run(url: URL, engine: PoseEngineChoice = .appleVision, target: SquatTrainingTarget = .init(), perception suppliedPerception: LivePosePerception? = nil, diagnostics: ReplayRunDiagnostics? = nil, update: @escaping @Sendable (ReplaySnapshot) async -> Void) async throws -> WorkoutSummary {
        // A separate task keeps synchronous AVAssetReader work off the UI actor.
        let task = Task.detached(priority: .userInitiated) {
            var session = SquatSession()
            session.target = target
            var lastTimeMs = 0
            if url.pathExtension.lowercased() == "json" {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 30_000_000 else { throw ReplayError.invalidFile }
                let data = try Data(contentsOf: url)
                guard data.count < 30_000_000 else { throw ReplayError.invalidFile }
                let file = try JSONDecoder().decode(PoseReplayFile.self, from: data)
                guard file.version == 1, !file.frames.isEmpty, file.frames.count < 100_000 else { throw ReplayError.invalidFile }
                var previous = -1
                for (index, frame) in file.frames.enumerated() {
                    try Task.checkCancellation()
                    guard frame.timestampMs > previous else { throw ReplayError.invalidTimestamp }
                    previous = frame.timestampMs
                    lastTimeMs = frame.timestampMs
                    let result = session.ingest(frame)
                    await diagnostics?.record(frame, result)
                    if index % 10 == 0 || index == file.frames.count - 1 {
                        await update(ReplaySnapshot(timeMs: frame.timestampMs, progress: Double(index + 1) / Double(file.frames.count), count: session.summary.reps.count, message: result.message, baselineReady: result.baselineReady, pose: frame, failure: result.failure))
                    }
                }
            } else {
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0, seconds <= 180 else { throw ReplayError.duration }
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ReplayError.invalidFile }
                let orientation = orientation(try await track.load(.preferredTransform))
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else { throw ReplayError.invalidFile }
                reader.add(output)
                guard reader.startReading() else { throw reader.error ?? ReplayError.invalidFile }
                defer { reader.cancelReading() }
                let perception = suppliedPerception ?? engine.makePerception()
                var index = 0
                while let sample = output.copyNextSampleBuffer() {
                    try Task.checkCancellation()
                    let time = Int(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) * 1000)
                    lastTimeMs = time
                    if let frame = try await perception.process(sample, orientation: orientation, timestampMs: time) {
                        let result = session.ingest(frame)
                        await diagnostics?.record(frame, result)
                        if index % 6 == 0 {
                            await update(ReplaySnapshot(timeMs: time, progress: min(1, Double(time) / (seconds * 1000)), count: session.summary.reps.count, message: result.message, baselineReady: result.baselineReady, pose: frame, failure: result.failure))
                        }
                    }
                    index += 1
                }
                if reader.status == .failed { throw reader.error ?? ReplayError.invalidFile }
            }
            session.interrupt(reason: .videoEnded)
            await update(ReplaySnapshot(timeMs: lastTimeMs, progress: 1, count: session.summary.reps.count, message: session.baseline == nil ? "未建立站立起点，请检查视频中的机位与姿势" : "分析完成", baselineReady: session.baseline != nil))
            return session.summary
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

enum ReplayError: LocalizedError {
    case invalidFile, invalidTimestamp, duration
    var errorDescription: String? {
        switch self {
        case .invalidFile: "无法读取此文件，请选择本地视频或版本 1 的关键点 JSON。"
        case .invalidTimestamp: "关键点时间戳必须严格递增。"
        case .duration: "请选择 3 分钟以内、包含开头站稳过程的视频。"
        }
    }
}
