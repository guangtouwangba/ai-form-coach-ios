import Foundation

/// Targets describe a selected task, never a universal technique or safety standard.
public struct SquatTrainingTarget: Codable, Equatable, Sendable {
    public var minimumDescentMs: Int?
    public var minimumHipDrop: Double?
    public var referenceName: String?
    public init(minimumDescentMs: Int? = nil, minimumHipDrop: Double? = nil, referenceName: String? = nil) {
        self.minimumDescentMs = minimumDescentMs
        self.minimumHipDrop = minimumHipDrop
        self.referenceName = referenceName
    }
}

public enum AttemptEndReason: String, Codable, Sendable {
    case returnedToStart, trackingLost, cameraMoved, paused, videoEnded, groupEnded, timedOut
    public var title: String {
        switch self {
        case .returnedToStart: "已观察到回起"
        case .trackingLost: "跟踪中断，未判断完整动作"
        case .cameraMoved: "机位变化，本次停止评价"
        case .paused: "训练暂停，本次记录中断"
        case .videoEnded: "录像结束，未观察到完整回起"
        case .groupEnded: "本组结束，未观察到完整回起"
        case .timedOut: "动作记录超时，请回到起点"
        }
    }
}

public enum SquatQualityItem: String, Codable, CaseIterable, Sendable {
    case returnToStart, rangeOfMotion, descentTempo
    public var title: String {
        switch self { case .returnToStart: "回起记录"; case .rangeOfMotion: "动作幅度"; case .descentTempo: "下降节奏" }
    }
}
public enum SquatAssessmentStatus: String, Codable, Sendable {
    case withinTarget, outsideTarget, notAssessable, notConfigured
}
public struct SquatQualityAssessment: Codable, Equatable, Identifiable, Sendable {
    public var id: String { item.rawValue }
    public let item: SquatQualityItem
    public let status: SquatAssessmentStatus
    public let message: String
    public let evidenceMs: Int
    public let measuredValue: Double?
    public let targetValue: Double?
}
public struct SquatPhaseCoverage: Codable, Equatable, Sendable {
    public let observedFrames: Int
    public let descentFrames: Int
    public let bottomFrames: Int
    public let ascentFrames: Int
    public let maximumFrameGapMs: Int
    public let observedReturn: Bool
    public let failure: PoseFailureReason
}
public struct MovementAttempt: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let startMs: Int
    public let bottomMs: Int
    public let endMs: Int
    public let countedRepID: Int?
    public let endReason: AttemptEndReason
    /// Hip displacement divided by the standing torso length, not centimetres or a 3D joint angle.
    public let maximumHipDrop: Double
    public let minimumProjectedKneeAngle: Double
    public let descentDurationMs: Int
    public let ascentDurationMs: Int?
    public let coverage: SquatPhaseCoverage
    public let target: SquatTrainingTarget
    public let assessments: [SquatQualityAssessment]
    public let engineVersion: String
    public var recommendation: String? { assessments.first { $0.status == .outsideTarget }?.message }
}
public struct SquatAnalysis: Codable, Equatable, Sendable {
    public let algorithmVersion: String
    public var attempts: [MovementAttempt]
    public init(attempts: [MovementAttempt] = []) {
        algorithmVersion = "squat-observation-1.0"; self.attempts = attempts
    }
}

/// Independent of the full-cycle counter, so smaller movements are not discarded.
/// Any failed observation terminates the window; missing phases are never interpolated.
struct SquatAttemptTracker: Sendable {
    var target = SquatTrainingTarget()
    private var armed = false
    private var topSince: Int?
    private var candidate: [(SquatFeatures, Double)] = []
    private var frames: [(SquatFeatures, Double)] = []
    private var repID: Int?
    private var returnSince: Int?
    private var firstReturnMs: Int?
    private var activeTarget: SquatTrainingTarget?
    var isActive: Bool { !frames.isEmpty }

    mutating func ingest(_ frame: SquatFeatures, baseline: SquatBaseline, countedRepID: Int?) -> MovementAttempt? {
        let drop = (frame.hip.y - baseline.hipY) / baseline.torsoScale
        let flex = baseline.kneeAngle - frame.kneeAngle
        let atStart = drop < 0.06 && abs(flex) < 9
        if !armed {
            if atStart {
                topSince = topSince ?? frame.timestamp
                if frame.timestamp - topSince! >= 250 { armed = true }
            } else { topSince = nil }
            return nil
        }
        if frames.isEmpty {
            // Lower than the count-cycle activation, but requires sustained two-joint motion.
            guard drop > 0.045, flex > 5 else { candidate.removeAll(keepingCapacity: true); return nil }
            candidate.append((frame, drop))
            guard frame.timestamp - candidate[0].0.timestamp >= 120, candidate.count >= 2 else { return nil }
            frames = candidate; activeTarget = target; candidate.removeAll(keepingCapacity: true)
        } else { frames.append((frame, drop)) }
        if let countedRepID { repID = countedRepID }
        if atStart {
            returnSince = returnSince ?? frame.timestamp
            firstReturnMs = firstReturnMs ?? frame.timestamp
            if frame.timestamp - returnSince! >= 150 {
                let attempt = end(.returnedToStart)
                // A confirmed return already arms the next attempt. Requiring a
                // second standing window here loses back-to-back real squats.
                armed = true
                return attempt
            }
        } else { returnSince = nil; firstReturnMs = nil }
        if frame.timestamp - frames[0].0.timestamp >= 15_000 { return end(.timedOut) }
        return nil
    }

    mutating func end(_ reason: AttemptEndReason, failure: PoseFailureReason = .none) -> MovementAttempt? {
        defer {
            frames.removeAll(keepingCapacity: true); candidate.removeAll(keepingCapacity: true)
            repID = nil; returnSince = nil; firstReturnMs = nil; topSince = nil; armed = false
            activeTarget = nil
        }
        guard let first = frames.first, let last = frames.last else { return nil }
        // First deepest sample avoids including a bottom pause in descent duration.
        var bottom = first
        for sample in frames where sample.1 > bottom.1 { bottom = sample }
        let gaps = zip(frames, frames.dropFirst()).map { $1.0.timestamp - $0.0.timestamp }
        let maxGap = gaps.max() ?? 0
        let returned = reason == .returnedToStart
        let descent = max(0, bottom.0.timestamp - first.0.timestamp)
        let descentFrames = frames.filter { $0.0.timestamp <= bottom.0.timestamp }.count
        let bottomFrames = frames.filter { abs($0.1 - bottom.1) < 0.03 }.count
        let ascentFrames = frames.filter { $0.0.timestamp > bottom.0.timestamp }.count
        let eligible = returned && frames.count >= 5 && maxGap <= 200 && descent > 0 && descentFrames >= 2 && ascentFrames >= 2
        let target = activeTarget ?? self.target
        func assessment(_ item: SquatQualityItem, measured: Double?, target value: Double?, evidence: Int) -> SquatQualityAssessment {
            if !eligible {
                let detail = failure == .none ? reason.title : failure.message
                return SquatQualityAssessment(item: item, status: .notAssessable, message: "无法判断：\(returned ? "阶段采样不足" : detail)", evidenceMs: evidence, measuredValue: measured, targetValue: value)
            }
            if item == .returnToStart {
                return SquatQualityAssessment(item: item, status: .withinTarget, message: "已观察到下降并回到站立起点", evidenceMs: evidence, measuredValue: nil, targetValue: nil)
            }
            guard let value, let measured else {
                return SquatQualityAssessment(item: item, status: .notConfigured, message: item == .rangeOfMotion ? "已记录幅度；未设置参考目标，不评价深浅" : "已记录下降时长；未设置节奏目标", evidenceMs: evidence, measuredValue: measured, targetValue: nil)
            }
            let outside = measured < value
            let message: String
            if item == .descentTempo {
                message = outside ? String(format: "下降用时 %.1f 秒，短于所选 %.1f 秒目标；下一次放慢下降", measured / 1000, value / 1000) : "下降时长达到所选目标"
            } else {
                message = outside ? "幅度低于所选参考；下一次对照参考幅度练习" : "幅度达到所选参考目标"
            }
            return SquatQualityAssessment(item: item, status: outside ? .outsideTarget : .withinTarget, message: message, evidenceMs: evidence, measuredValue: measured, targetValue: value)
        }
        let descentTarget = target.minimumDescentMs.flatMap { (200...10_000).contains($0) ? Double($0) : nil }
        let rangeTarget = target.minimumHipDrop.flatMap { $0.isFinite && $0 > 0 && $0 < 3 && !(target.referenceName?.trimmingCharacters(in: .whitespaces).isEmpty ?? true) ? $0 : nil }
        return MovementAttempt(id: UUID().uuidString, startMs: first.0.timestamp, bottomMs: bottom.0.timestamp,
                               endMs: last.0.timestamp, countedRepID: repID, endReason: reason,
                               maximumHipDrop: max(0, bottom.1), minimumProjectedKneeAngle: frames.map { $0.0.kneeAngle }.min()!,
                               descentDurationMs: descent, ascentDurationMs: returned ? max(0, (firstReturnMs ?? last.0.timestamp) - bottom.0.timestamp) : nil,
                               coverage: SquatPhaseCoverage(observedFrames: frames.count, descentFrames: descentFrames, bottomFrames: bottomFrames, ascentFrames: ascentFrames, maximumFrameGapMs: maxGap, observedReturn: returned, failure: failure),
                               target: target, assessments: [assessment(.returnToStart, measured: nil, target: nil, evidence: last.0.timestamp),
                                   assessment(.rangeOfMotion, measured: bottom.1, target: rangeTarget, evidence: bottom.0.timestamp),
                                   assessment(.descentTempo, measured: Double(descent), target: descentTarget, evidence: bottom.0.timestamp)],
                               engineVersion: first.0.engineVersion)
    }
}
