import Foundation

public enum LandmarkID: String, Codable, CaseIterable, Sendable {
    case nose
    case leftShoulder, rightShoulder
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
    case leftHeel, rightHeel
    case leftFootIndex, rightFootIndex
}

public struct Landmark: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double
    public var visibility: Double
    public var presence: Double
    public var isPredicted: Bool

    public init(
        x: Double,
        y: Double,
        z: Double = 0,
        visibility: Double = 1,
        presence: Double = 1,
        isPredicted: Bool = false
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.visibility = visibility
        self.presence = presence
        self.isPredicted = isPredicted
    }

    public var quality: Double { min(visibility, presence) }
}

public struct PoseObservation: Codable, Equatable, Sendable {
    public let timestampMs: Int
    public let landmarks: [LandmarkID: Landmark]
    public let inferenceMs: Double
    public let engineVersion: String

    public init(timestampMs: Int, landmarks: [LandmarkID: Landmark], inferenceMs: Double = 0, engineVersion: String = "fixture") {
        self.timestampMs = timestampMs
        self.landmarks = landmarks
        self.inferenceMs = inferenceMs
        self.engineVersion = engineVersion
    }
}

public enum TrainingSide: String, Codable, CaseIterable, Sendable { case left, right }
public enum ExerciseVariant: String, Codable, CaseIterable, Sendable { case general, gluteBias, quadBias }
public enum ExercisePhase: String, Codable, Sendable { case ready, descending, bottom, ascending, lockout, invalid }
public enum IssueType: String, Codable, CaseIterable, Sendable { case torsoCollapse, insufficientDepth, fastDescent }
public enum ConfidenceDisposition: String, Codable, Sendable { case spoken, summaryOnly, suppressed }

public struct SessionConfig: Codable, Equatable, Sendable {
    public var trainingSide: TrainingSide
    public var variant: ExerciseVariant
    public var speechEnabled: Bool
    public var saveVideo: Bool
    public var minimumLandmarkQuality: Double
    public var spokenThreshold: Double
    public var summaryThreshold: Double
    public var feedbackCooldownMs: Int
    public var ruleVersion: String

    public init(
        trainingSide: TrainingSide = .right,
        variant: ExerciseVariant = .general,
        speechEnabled: Bool = true,
        saveVideo: Bool = false,
        minimumLandmarkQuality: Double = 0.65,
        spokenThreshold: Double = 0.90,
        summaryThreshold: Double = 0.70,
        feedbackCooldownMs: Int = 3_000,
        ruleVersion: String = "bss-0.1.0"
    ) {
        self.trainingSide = trainingSide
        self.variant = variant
        self.speechEnabled = speechEnabled
        self.saveVideo = saveVideo
        self.minimumLandmarkQuality = minimumLandmarkQuality
        self.spokenThreshold = spokenThreshold
        self.summaryThreshold = summaryThreshold
        self.feedbackCooldownMs = feedbackCooldownMs
        self.ruleVersion = ruleVersion
    }
}

public struct CalibrationRepSample: Codable, Equatable, Sendable {
    public let depth: Double
    public let earlyDescentTrunkAngle: Double
    public let bottomTrunkAngle: Double
    public let descentDurationMs: Int

    public init(depth: Double, earlyDescentTrunkAngle: Double, bottomTrunkAngle: Double, descentDurationMs: Int) {
        self.depth = depth
        self.earlyDescentTrunkAngle = earlyDescentTrunkAngle
        self.bottomTrunkAngle = bottomTrunkAngle
        self.descentDurationMs = descentDurationMs
    }
}

public struct CalibrationProfile: Codable, Equatable, Sendable {
    public let topHipY: Double
    public let torsoLength: Double
    public let targetDepth: Double
    public let baselineTrunkDelta: Double
    public let targetDescentDurationMs: Int

    public init(topHipY: Double, torsoLength: Double, targetDepth: Double, baselineTrunkDelta: Double, targetDescentDurationMs: Int) {
        self.topHipY = topHipY
        self.torsoLength = torsoLength
        self.targetDepth = targetDepth
        self.baselineTrunkDelta = baselineTrunkDelta
        self.targetDescentDurationMs = targetDescentDurationMs
    }

    public static func build(topHipY: Double, torsoLength: Double, samples: [CalibrationRepSample]) throws -> CalibrationProfile {
        guard samples.count == 3, torsoLength > 0 else { throw CalibrationError.invalidSampleCount }
        let depths = samples.map(\.depth).sorted()
        guard depths[0] > 0, depths[2] / depths[0] < 1.35 else { throw CalibrationError.inconsistentRepetitions }
        let deltas = samples.map { max(0, $0.bottomTrunkAngle - $0.earlyDescentTrunkAngle) }.sorted()
        let durations = samples.map(\.descentDurationMs).sorted()
        return CalibrationProfile(
            topHipY: topHipY,
            torsoLength: torsoLength,
            targetDepth: depths[1],
            baselineTrunkDelta: deltas[1],
            targetDescentDurationMs: durations[1]
        )
    }
}

public enum CalibrationError: Error, Equatable { case invalidSampleCount, inconsistentRepetitions }

public struct MotionFrame: Codable, Equatable, Sendable {
    public let timestampMs: Int
    public let hipY: Double
    public let hipDrop: Double
    public let verticalVelocity: Double
    public let frontKneeAngle: Double
    public let trunkAngle: Double
    public let poseQuality: Double
    public let containsPredictedRequiredPoint: Bool
    public let engineVersion: String
}

public struct RepSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let startMs: Int
    public let endMs: Int
    public let descentDurationMs: Int
    public let maximumDepth: Double
    public let maximumTrunkDelta: Double
    public let issues: [IssueEvent]
    public let engineVersion: String
}

public struct IssueEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(repIndex)-\(type.rawValue)-\(startMs)" }
    public let type: IssueType
    public let repIndex: Int
    public let phase: ExercisePhase
    public let startMs: Int
    public let endMs: Int
    public let severity: Int
    public let confidence: Double
    public let disposition: ConfidenceDisposition
    public let evidence: [String: Double]
}

public struct FeedbackEvent: Codable, Equatable, Sendable {
    public let issue: IssueType
    public let repIndex: Int
    public let timestampMs: Int
    public let cueKey: String
    public let phase: ExercisePhase
    public let confidence: Double
    public let spokenThreshold: Double
    public let evidence: [String: Double]
    public let engineVersion: String
    public let ruleVersion: String
}

public enum SessionEvent: Equatable, Sendable {
    case phaseChanged(ExercisePhase)
    case repCompleted(RepSummary)
    case issueDetected(IssueEvent)
    case feedback(FeedbackEvent)
    case analysisPaused(String)
    case analysisResumed
}

public struct WorkoutSummary: Codable, Equatable, Sendable {
    public let reps: [RepSummary]
    public let suppressedIssueCount: Int
    public let feedbackEvents: [FeedbackEvent]
    public var effectiveRepCount: Int { reps.count }

    public init(reps: [RepSummary], suppressedIssueCount: Int, feedbackEvents: [FeedbackEvent] = []) {
        self.reps = reps
        self.suppressedIssueCount = suppressedIssueCount
        self.feedbackEvents = feedbackEvents
    }
}
