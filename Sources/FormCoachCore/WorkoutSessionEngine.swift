import Foundation

public actor WorkoutSessionEngine {
    private var config: SessionConfig?
    private var calibration: CalibrationProfile?
    private var preprocessor = MotionPreprocessor()
    private var phase: ExercisePhase = .invalid
    private var reps: [RepSummary] = []
    private var suppressedIssueCount = 0
    private var activeRep: RepAccumulator?
    private var lastFeedbackByType: [IssueType: Int] = [:]
    private var paused = false

    public init() {}

    public func start(config: SessionConfig, calibration: CalibrationProfile) {
        self.config = config
        self.calibration = calibration
        phase = .ready
        reps = []
        suppressedIssueCount = 0
        activeRep = nil
        lastFeedbackByType = [:]
        paused = false
        preprocessor.reset()
    }

    public func ingest(_ observation: PoseObservation) -> [SessionEvent] {
        guard let config, let calibration else { return [.analysisPaused("session_not_started")] }
        guard let frame = preprocessor.process(observation, config: config, calibration: calibration) else {
            if !paused {
                paused = true
                phase = .invalid
                return [.analysisPaused("required_landmarks_unavailable"), .phaseChanged(.invalid)]
            }
            return []
        }

        var events: [SessionEvent] = []
        if paused {
            paused = false
            phase = .ready
            events += [.analysisResumed, .phaseChanged(.ready)]
        }

        let next = nextPhase(for: frame, calibration: calibration)
        if next != phase {
            phase = next
            events.append(.phaseChanged(next))
        }

        switch phase {
        case .descending:
            if activeRep == nil {
                activeRep = RepAccumulator(index: reps.count + 1, startMs: frame.timestampMs, initialTrunkAngle: frame.trunkAngle)
            }
            activeRep?.record(frame)
        case .bottom, .ascending:
            activeRep?.record(frame)
        case .lockout:
            guard var accumulator = activeRep else { break }
            accumulator.record(frame)
            let result = completeRep(accumulator, config: config, calibration: calibration)
            reps.append(result.rep)
            events.append(.repCompleted(result.rep))
            for issue in result.rep.issues {
                events.append(.issueDetected(issue))
            }
            if let feedback = chooseFeedback(from: result.rep.issues, at: frame.timestampMs, config: config) {
                events.append(.feedback(feedback))
            }
            activeRep = nil
        case .ready, .invalid:
            break
        }
        return events
    }

    public func finish() -> WorkoutSummary {
        WorkoutSummary(reps: reps, suppressedIssueCount: suppressedIssueCount)
    }

    private func nextPhase(for frame: MotionFrame, calibration: CalibrationProfile) -> ExercisePhase {
        let isTop = frame.hipDrop < max(0.15, calibration.targetDepth * 0.35)
        switch phase {
        case .invalid, .ready, .lockout:
            return frame.verticalVelocity < -0.06 ? .descending : .ready
        case .descending:
            // Depth is the stable phase boundary. Velocity is deliberately not
            // required here because smoothing can keep a small negative value
            // for several frames after the athlete reaches the bottom.
            if frame.hipDrop >= calibration.targetDepth * 0.80 { return .bottom }
            return .descending
        case .bottom:
            return frame.verticalVelocity > 0.04 ? .ascending : .bottom
        case .ascending:
            return isTop ? .lockout : .ascending
        }
    }

    private func completeRep(_ accumulator: RepAccumulator, config: SessionConfig, calibration: CalibrationProfile) -> (rep: RepSummary, issues: [IssueEvent]) {
        let endMs = accumulator.lastTimestampMs
        let poseConfidence = accumulator.minimumPoseQuality
        let predictedPenalty = accumulator.containsPredictedPoint ? 0.45 : 1.0
        let phaseConfidence = accumulator.sawBottom ? 1.0 : 0.6
        let baseConfidence = poseConfidence * predictedPenalty * phaseConfidence
        var issues: [IssueEvent] = []

        let allowedDelta: Double
        switch config.variant {
        case .general: allowedDelta = calibration.baselineTrunkDelta + 12
        case .gluteBias: allowedDelta = calibration.baselineTrunkDelta + 18
        case .quadBias: allowedDelta = calibration.baselineTrunkDelta + 9
        }
        if accumulator.maximumTrunkDelta > allowedDelta {
            issues.append(makeIssue(.torsoCollapse, accumulator: accumulator, confidence: baseConfidence * evidenceStrength(accumulator.maximumTrunkDelta, threshold: allowedDelta), config: config, evidence: ["trunkDelta": accumulator.maximumTrunkDelta, "allowedDelta": allowedDelta]))
        }
        if accumulator.maximumDepth < calibration.targetDepth * 0.90 {
            let ratio = accumulator.maximumDepth / max(calibration.targetDepth, 0.001)
            issues.append(makeIssue(.insufficientDepth, accumulator: accumulator, confidence: baseConfidence * min(1, max(0.75, 1 - ratio + 0.75)), config: config, evidence: ["depth": accumulator.maximumDepth, "targetDepth": calibration.targetDepth]))
        }
        if accumulator.descentDurationMs < max(350, Int(Double(calibration.targetDescentDurationMs) * 0.70)) {
            issues.append(makeIssue(.fastDescent, accumulator: accumulator, confidence: baseConfidence, config: config, evidence: ["descentDurationMs": Double(accumulator.descentDurationMs), "targetDurationMs": Double(calibration.targetDescentDurationMs)]))
        }

        suppressedIssueCount += issues.filter { $0.disposition == .suppressed }.count
        let rep = RepSummary(
            id: accumulator.index,
            startMs: accumulator.startMs,
            endMs: endMs,
            descentDurationMs: accumulator.descentDurationMs,
            maximumDepth: accumulator.maximumDepth,
            maximumTrunkDelta: accumulator.maximumTrunkDelta,
            issues: issues
        )
        return (rep, issues)
    }

    private func makeIssue(_ type: IssueType, accumulator: RepAccumulator, confidence: Double, config: SessionConfig, evidence: [String: Double]) -> IssueEvent {
        let disposition: ConfidenceDisposition
        if accumulator.containsPredictedPoint || confidence < config.summaryThreshold { disposition = .suppressed }
        else if confidence >= config.spokenThreshold { disposition = .spoken }
        else { disposition = .summaryOnly }
        return IssueEvent(
            type: type,
            repIndex: accumulator.index,
            phase: type == .fastDescent ? .descending : .bottom,
            startMs: accumulator.startMs,
            endMs: accumulator.lastTimestampMs,
            severity: confidence >= 0.95 ? 2 : 1,
            confidence: min(1, max(0, confidence)),
            disposition: disposition,
            evidence: evidence
        )
    }

    private func chooseFeedback(from issues: [IssueEvent], at timestampMs: Int, config: SessionConfig) -> FeedbackEvent? {
        guard config.speechEnabled else { return nil }
        let priority: [IssueType] = [.torsoCollapse, .insufficientDepth, .fastDescent]
        for type in priority {
            guard let issue = issues.first(where: { $0.type == type && $0.disposition == .spoken }) else { continue }
            if let last = lastFeedbackByType[type], timestampMs - last < config.feedbackCooldownMs { continue }
            lastFeedbackByType[type] = timestampMs
            return FeedbackEvent(issue: type, repIndex: issue.repIndex, timestampMs: timestampMs, cueKey: cueKey(for: type))
        }
        return nil
    }

    private func cueKey(for type: IssueType) -> String {
        switch type {
        case .torsoCollapse: return "cue.torso_stable"
        case .insufficientDepth: return "cue.go_lower"
        case .fastDescent: return "cue.control_descent"
        }
    }

    private func evidenceStrength(_ value: Double, threshold: Double) -> Double {
        min(1, max(0.80, value / max(threshold, 0.001)))
    }
}

private struct RepAccumulator: Sendable {
    let index: Int
    let startMs: Int
    let initialTrunkAngle: Double
    var lastTimestampMs: Int
    var bottomTimestampMs: Int?
    var maximumDepth = 0.0
    var maximumTrunkDelta = 0.0
    var minimumPoseQuality = 1.0
    var containsPredictedPoint = false
    var sawBottom = false

    init(index: Int, startMs: Int, initialTrunkAngle: Double) {
        self.index = index
        self.startMs = startMs
        self.initialTrunkAngle = initialTrunkAngle
        self.lastTimestampMs = startMs
    }

    mutating func record(_ frame: MotionFrame) {
        lastTimestampMs = frame.timestampMs
        maximumDepth = max(maximumDepth, frame.hipDrop)
        maximumTrunkDelta = max(maximumTrunkDelta, frame.trunkAngle - initialTrunkAngle)
        minimumPoseQuality = min(minimumPoseQuality, frame.poseQuality)
        containsPredictedPoint = containsPredictedPoint || frame.containsPredictedRequiredPoint
        if frame.hipDrop > 0.35 {
            sawBottom = true
            bottomTimestampMs = bottomTimestampMs ?? frame.timestampMs
        }
    }

    var descentDurationMs: Int { max(0, (bottomTimestampMs ?? lastTimestampMs) - startMs) }
}
