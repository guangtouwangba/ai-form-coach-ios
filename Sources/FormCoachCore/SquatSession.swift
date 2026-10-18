import Foundation

public struct SquatFeatures: Sendable {
    public let timestamp: Int
    public let side: TrainingSide
    public let hip: Landmark
    public let ankle: Landmark
    public let shoulder: Landmark
    public let knee: Landmark
    public let thighLength: Double
    public let shinLength: Double
    public let scale: Double
    public let kneeAngle: Double
    public let trunkAngle: Double
    public let aspect: Double
    public let engineVersion: String

    public static func extract(_ observation: PoseObservation, side: TrainingSide? = nil) -> SquatFeatures? {
        assess(observation, side: side).features
    }

    public static func assess(_ observation: PoseObservation, side: TrainingSide? = nil) -> SquatFeatureAssessment {
        func rejected(_ reason: PoseFailureReason, _ joints: [LandmarkID] = []) -> SquatFeatureAssessment {
            SquatFeatureAssessment(features: nil, failure: reason, joints: joints)
        }
        if let count = observation.detectedPersonCount {
            if count == 0 { return rejected(.noPerson) }
            if count > 1 { return rejected(.multiplePeople) }
        }
        guard !observation.landmarks.isEmpty else { return rejected(.noPerson) }
        guard observation.imageWidth.isFinite, observation.imageHeight.isFinite,
              observation.imageWidth > 0, observation.imageHeight > 0 else { return rejected(.invalidGeometry) }
        let aspect = observation.imageWidth / observation.imageHeight
        let vision = observation.engineVersion.hasPrefix("apple-vision-2d-")
        func ids(_ side: TrainingSide) -> [LandmarkID] {
            side == .left ? [.leftShoulder, .leftHip, .leftKnee, .leftAnkle] : [.rightShoulder, .rightHip, .rightKnee, .rightAnkle]
        }
        let sides: [TrainingSide] = side.map { [$0] } ?? [TrainingSide.left, .right].sorted {
            ids($0).map { observation.landmarks[$0]?.quality ?? 0 }.reduce(0, +) > ids($1).map { observation.landmarks[$0]?.quality ?? 0 }.reduce(0, +)
        }
        var rejection = rejected(.missingJoints)
        for (index, selected) in sides.enumerated() {
            let keys = ids(selected)
            let missing = keys.filter { observation.landmarks[$0] == nil }
            var failure: SquatFeatureAssessment?
            if !missing.isEmpty { failure = rejected(.missingJoints, missing) }
            let raw = keys.compactMap { observation.landmarks[$0] }
            if failure == nil {
                let weak = zip(keys, raw).filter { !$0.1.quality.isFinite || $0.1.quality < (vision ? 0.3 : 0.65) || $0.1.isPredicted }.map { $0.0 }
                if !weak.isEmpty { failure = rejected(.lowConfidence, weak) }
                else if vision && (raw.filter { $0.quality >= 0.65 }.count < 2 || raw.map(\.quality).reduce(0,+) / 4 < 0.55) { failure = rejected(.lowConfidence, keys) }
                else if !raw.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0.015...0.985).contains($0.x) && (0.015...0.985).contains($0.y) }) { failure = rejected(.outOfFrame, keys) }
            }
            if let failure { if index == 0 { rejection = failure }; continue }
            let p = raw.map { Landmark(x: $0.x * aspect, y: $0.y) }
            let scale = Geometry.distance(p[0], p[1])
            let thigh = Geometry.distance(p[1], p[2]), shin = Geometry.distance(p[2], p[3])
            if scale <= 0.08 || p[3].y - p[0].y <= 0.25 { if index == 0 { rejection = rejected(.tooSmall) }; continue }
            guard thigh > 0.04, shin > 0.04, (0.4...2.5).contains(thigh / shin), (0.6...3.5).contains((thigh + shin) / scale) else {
                if index == 0 { rejection = rejected(.invalidGeometry) }; continue
            }
            let knee = Geometry.angle(p[1], p[2], p[3])
            let trunk = Geometry.trunkAngleFromVertical(hip: Landmark(x: p[1].x, y: -p[1].y), shoulder: Landmark(x: p[0].x, y: -p[0].y))
            guard knee.isFinite, trunk.isFinite else { continue }
            return SquatFeatureAssessment(features: SquatFeatures(timestamp: observation.timestampMs, side: selected, hip: p[1], ankle: p[3], shoulder: p[0], knee: p[2], thighLength: thigh, shinLength: shin, scale: scale, kneeAngle: knee, trunkAngle: trunk, aspect: aspect, engineVersion: observation.engineVersion), failure: .none, joints: [])
        }
        return rejection
    }

}

public struct SquatBaseline: Codable, Equatable, Sendable {
    public let hipY: Double
    public let torsoScale: Double
    public let kneeAngle: Double
    public let trunkAngle: Double
    public let ankleX: Double
    public let ankleY: Double
    public let aspect: Double
    public let side: TrainingSide
    public let engineVersion: String
    public var thighLength: Double? = nil
    public var shinLength: Double? = nil
}

public struct StandingUpdate: Sendable {
    public let progress: Double
    public let message: String
    public let baseline: SquatBaseline?
    public var failure: PoseFailureReason = .none
}

/// These are count-cycle heuristics, not a certified squat technique standard.
public struct StaticStandingDetector: Sendable {
    private var frames: [SquatFeatures] = []
    public init() {}
    public mutating func reset() { frames.removeAll() }

    public mutating func ingest(_ observation: PoseObservation) -> StandingUpdate {
        func waiting(_ message: String, progress: Double = 0, failure: PoseFailureReason = .none) -> StandingUpdate { StandingUpdate(progress: progress, message: message, baseline: nil, failure: failure) }
        let assessment = SquatFeatures.assess(observation, side: frames.first?.side)
        guard let frame = assessment.features else {
            reset(); return waiting(assessment.message, failure: assessment.failure)
        }
        guard frame.kneeAngle >= 150, frame.trunkAngle < 35 else {
            reset(); return waiting(PoseFailureReason.notUpright.message, failure: .notUpright)
        }
        // Reject clearly frontal views when both shoulders are confidently visible.
        if let left = observation.landmarks[.leftShoulder], let right = observation.landmarks[.rightShoulder], min(left.quality, right.quality) >= 0.65,
           abs(left.x - right.x) * frame.aspect > frame.scale * 0.65 {
            reset(); return waiting(PoseFailureReason.wrongView.message, failure: .wrongView)
        }
        var discontinuous = false
        if let previous = frames.last, frame.timestamp <= previous.timestamp || frame.timestamp - previous.timestamp > 250 || abs(frame.aspect - previous.aspect) > 0.01 || frame.engineVersion != previous.engineVersion {
            discontinuous = true
            reset()
        }
        frames.append(frame)
        while frames.count > 1, frame.timestamp - frames[1].timestamp >= 2_000 { frames.removeFirst() }
        let scale = median(frames.map(\.scale))
        let hip = Landmark(x: median(frames.map { $0.hip.x }), y: median(frames.map { $0.hip.y }))
        let ankle = Landmark(x: median(frames.map { $0.ankle.x }), y: median(frames.map { $0.ankle.y }))
        let jitter = frames.map { Geometry.distance($0.hip, hip) / scale }.sorted()
        let ankleJitter = frames.map { Geometry.distance($0.ankle, ankle) / scale }.max() ?? 0
        let drift = Geometry.distance(frames.first!.hip, frame.hip) / scale
        let spread = ((frames.map(\.scale).max() ?? scale) - (frames.map(\.scale).min() ?? scale)) / scale
        let shoulder = Landmark(x: median(frames.map { $0.shoulder.x }), y: median(frames.map { $0.shoulder.y }))
        let knee = Landmark(x: median(frames.map { $0.knee.x }), y: median(frames.map { $0.knee.y }))
        let jointJitter = frames.map { max(Geometry.distance($0.shoulder, shoulder), Geometry.distance($0.knee, knee)) / scale }.max() ?? 0
        let kneeSpread = (frames.map(\.kneeAngle).max() ?? 0) - (frames.map(\.kneeAngle).min() ?? 0)
        guard jitter[Int(Double(jitter.count - 1) * 0.90)] < 0.035, drift < 0.045, ankleJitter < 0.04, spread < 0.10,
              jointJitter < 0.05, kneeSpread < 10 else {
            frames = [frame]; return waiting(PoseFailureReason.moving.message, failure: .moving)
        }
        let elapsed = frame.timestamp - frames.first!.timestamp
        if discontinuous { return waiting(PoseFailureReason.frameGap.message, failure: .frameGap) }
        guard elapsed >= 2_000, frames.count >= 16 else { return waiting("保持站稳，正在建立起始位置", progress: min(0.99, Double(elapsed) / 2_000)) }
        var baseline = SquatBaseline(hipY: hip.y, torsoScale: scale, kneeAngle: median(frames.map(\.kneeAngle)), trunkAngle: median(frames.map(\.trunkAngle)), ankleX: ankle.x, ankleY: ankle.y, aspect: frame.aspect, side: frame.side, engineVersion: frame.engineVersion)
        baseline.thighLength = median(frames.map(\.thighLength)); baseline.shinLength = median(frames.map(\.shinLength))
        return StandingUpdate(progress: 1, message: "已站稳，可以开始", baseline: baseline)
    }
}

public struct SquatUpdate: Sendable {
    public let message: String
    public let standingProgress: Double
    public let baselineReady: Bool
    public let rep: RepSummary?
    public let tracking: Bool
    public var failure: PoseFailureReason = .none
    public var attempt: MovementAttempt? = nil
}

/// Shared by the live camera, decoded video and landmark replay.
public struct SquatSession: Sendable {
    public private(set) var baseline: SquatBaseline?
    public private(set) var summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
    private var standing = StaticStandingDetector()
    private enum Phase: Sendable { case waitingForTop, ready, descending, ascending }
    private var phase = Phase.waitingForTop
    private var previousTimestamp: Int?
    private var previousFrame: SquatFeatures?
    private var startMs = 0
    private var bottomMs = 0
    private var maximumDrop = 0.0
    private var minimumKnee = 180.0
    private var maximumTrunk = 0.0
    private var topSince: Int?
    private var attemptTracker = SquatAttemptTracker()
    public var target: SquatTrainingTarget {
        get { attemptTracker.target }
        set { attemptTracker.target = newValue }
    }
    public init() {}

    public mutating func reset(summary: WorkoutSummary = WorkoutSummary(reps: [], suppressedIssueCount: 0)) {
        let target = self.target
        self = SquatSession(); self.summary = summary; self.target = target
    }
    public mutating func beginGroup() {
        interrupt()
        summary = WorkoutSummary(reps: [], suppressedIssueCount: 0, squatAnalysis: SquatAnalysis())
    }
    public mutating func interrupt(reason: AttemptEndReason = .paused, failure: PoseFailureReason = .none) {
        record(attemptTracker.end(reason, failure: failure))
        phase = .waitingForTop; topSince = nil; previousTimestamp = nil; previousFrame = nil
        maximumDrop = 0; minimumKnee = 180
    }

    public mutating func ingest(_ observation: PoseObservation, counting: Bool = true) -> SquatUpdate {
        let previousCount = summary.squatAnalysis?.attempts.count ?? 0
        if !counting, attemptTracker.isActive { interrupt() }
        var result = ingestCount(observation, counting: counting)
        if counting, result.tracking, let baseline,
           let frame = SquatFeatures.assess(observation, side: baseline.side).features {
            record(attemptTracker.ingest(frame, baseline: baseline, countedRepID: result.rep?.id))
        }
        if (summary.squatAnalysis?.attempts.count ?? 0) > previousCount {
            result.attempt = summary.squatAnalysis?.attempts.last
        }
        return result
    }

    private mutating func record(_ attempt: MovementAttempt?) {
        guard let attempt else { return }
        if summary.squatAnalysis == nil { summary.squatAnalysis = SquatAnalysis() }
        summary.squatAnalysis?.attempts.append(attempt)
    }

    private mutating func ingestCount(_ observation: PoseObservation, counting: Bool) -> SquatUpdate {
        func update(_ message: String, _ tracking: Bool = true, rep: RepSummary? = nil, progress: Double = 1, failure: PoseFailureReason = .none) -> SquatUpdate {
            SquatUpdate(message: message, standingProgress: progress, baselineReady: baseline != nil, rep: rep, tracking: tracking, failure: failure)
        }
        guard let reference = baseline else {
            let value = standing.ingest(observation)
            if let baseline = value.baseline { self.baseline = baseline; phase = .waitingForTop }
            return update(value.message, value.progress > 0 || value.baseline != nil, progress: value.progress, failure: value.failure)
        }
        let assessment = SquatFeatures.assess(observation, side: reference.side)
        guard let frame = assessment.features else {
            interrupt(reason: .trackingLost, failure: assessment.failure); return update(assessment.message, false, failure: assessment.failure)
        }
        guard abs(frame.aspect - reference.aspect) < 0.01, frame.engineVersion == reference.engineVersion,
              abs(frame.scale / reference.torsoScale - 1) < 0.25,
              hypot(frame.ankle.x - reference.ankleX, frame.ankle.y - reference.ankleY) / reference.torsoScale < 0.22 else {
            baseline = nil; standing.reset(); interrupt(reason: .cameraMoved, failure: .cameraMoved)
            return update(PoseFailureReason.cameraMoved.message, false, progress: 0, failure: .cameraMoved)
        }
        if let previousTimestamp, observation.timestampMs <= previousTimestamp || observation.timestampMs - previousTimestamp > 250 {
            interrupt(reason: .trackingLost, failure: .frameGap)
            return update(PoseFailureReason.frameGap.message, false, failure: .frameGap)
        }
        // A stable low-confidence joint may remain usable, but a geometrically
        // impossible skeleton or abrupt joint jump never continues a partial rep.
        if let thigh = reference.thighLength, let shin = reference.shinLength,
           abs(frame.thighLength / thigh - 1) > 0.25 || abs(frame.shinLength / shin - 1) > 0.25 {
            interrupt(reason: .trackingLost, failure: .skeletonChanged); return update(PoseFailureReason.skeletonChanged.message, false, failure: .skeletonChanged)
        }
        if let previousFrame {
            let dt = Double(frame.timestamp - previousFrame.timestamp) / 1000
            let jump = zip([frame.shoulder, frame.hip, frame.knee, frame.ankle], [previousFrame.shoulder, previousFrame.hip, previousFrame.knee, previousFrame.ankle]).map { Geometry.distance($0, $1) / reference.torsoScale }.max() ?? 0
            guard dt > 0, jump <= max(0.08, dt * 6) else {
                interrupt(reason: .trackingLost, failure: .jointJump); return update(PoseFailureReason.jointJump.message, false, failure: .jointJump)
            }
        }
        previousTimestamp = observation.timestampMs
        previousFrame = frame
        guard counting else { return update("已站稳，可以开始") }
        let drop = (frame.hip.y - reference.hipY) / reference.torsoScale
        let kneeFlex = reference.kneeAngle - frame.kneeAngle
        let isTop = drop < 0.10 && abs(kneeFlex) < 12
        switch phase {
        case .waitingForTop:
            if isTop {
                topSince = topSince ?? frame.timestamp
                if frame.timestamp - topSince! >= 250 { phase = .ready }
            } else { topSince = nil }
            return update(PoseFailureReason.waitingForTop.message, failure: .waitingForTop)
        case .ready:
            if drop > 0.10 && kneeFlex > 12 {
                phase = .descending; startMs = frame.timestamp; bottomMs = frame.timestamp
                maximumDrop = drop; minimumKnee = frame.kneeAngle; maximumTrunk = frame.trunkAngle
            }
        case .descending:
            if drop >= maximumDrop { maximumDrop = drop; bottomMs = frame.timestamp }
            minimumKnee = min(minimumKnee, frame.kneeAngle)
            maximumTrunk = max(maximumTrunk, frame.trunkAngle)
            if maximumDrop >= 0.25, reference.kneeAngle - minimumKnee >= 35, drop < maximumDrop - 0.055 { phase = .ascending }
            else if isTop { phase = .ready; return update("已观察到小幅往返，本次未计入完整周期") }
        case .ascending:
            if isTop {
                phase = .waitingForTop; topSince = frame.timestamp
                guard frame.timestamp - startMs >= 500, frame.timestamp - startMs < 15_000 else { return update("本次周期时间异常，未计入") }
                let rep = RepSummary(id: summary.reps.count + 1, startMs: startMs, endMs: frame.timestamp, descentDurationMs: max(0, bottomMs - startMs), maximumDepth: maximumDrop, maximumTrunkDelta: max(0, maximumTrunk - reference.trunkAngle), issues: [], engineVersion: frame.engineVersion)
                summary = WorkoutSummary(reps: summary.reps + [rep], suppressedIssueCount: 0, squatAnalysis: summary.squatAnalysis)
                return update("已完成 \(summary.reps.count) 次", rep: rep)
            }
        }
        return update(phase == .ready ? "已准备好，开始下一次深蹲" : "正在记录本次动作")
    }
}

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted(); return sorted[sorted.count / 2]
}

/// Deterministic geometry fixture. Never represented as a real-person video.
public enum SquatTestSequence {
    public static func frame(timestamp: Int, depth: Double = 0) -> PoseObservation {
        // Isotropic image space, converted to a portrait source's normalized coordinates.
        let aspect = 720.0 / 1280
        let ankle = (0.29, 0.90)
        let hip = (0.29 + depth * 0.12, 0.46 + depth * 0.28)
        // Two fixed-length leg segments, rather than independently moving the
        // knee and stretching the synthetic shin during a squat.
        let dx = ankle.0 - hip.0, dy = ankle.1 - hip.1
        let distance = hypot(dx, dy)
        let height = sqrt(max(0, 0.22 * 0.22 - distance * distance / 4))
        let knee = ((hip.0 + ankle.0) / 2 - dy / distance * height,
                    (hip.1 + ankle.1) / 2 + dx / distance * height)
        func point(_ x: Double, _ y: Double) -> Landmark { Landmark(x: x / aspect, y: y, visibility: 0.99, presence: 0.99) }
        return PoseObservation(timestampMs: timestamp, landmarks: [
            .nose: point(hip.0 - 0.01, hip.1 - 0.30),
            .rightShoulder: point(hip.0 - 0.02, hip.1 - 0.22), .leftShoulder: point(hip.0 - 0.025, hip.1 - 0.22),
            .rightHip: point(hip.0, hip.1), .leftHip: point(hip.0 - 0.005, hip.1),
            .rightKnee: point(knee.0, knee.1), .leftKnee: point(knee.0 - 0.005, knee.1),
            .rightAnkle: point(ankle.0, ankle.1), .leftAnkle: point(ankle.0 - 0.005, ankle.1)
        ], engineVersion: "synthetic-squat-v1", imageWidth: 720, imageHeight: 1280)
    }
    public static func frames(repetitions: Int = 3) -> [PoseObservation] {
        var result = stride(from: 0, through: 3_000, by: 100).map { frame(timestamp: $0) }
        var time = 3_000
        for _ in 0..<max(0, repetitions) {
            for value in [0.0, 0, 0, 0.2, 0.4, 0.6, 0.8, 1, 1, 0.8, 0.6, 0.4, 0.2, 0, 0, 0, 0] {
                time += 100; result.append(frame(timestamp: time, depth: value))
            }
        }
        return result
    }
}
