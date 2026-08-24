import Foundation

public struct CalibrationUpdate: Equatable, Sendable {
    public let completedRepCount: Int
    public let profile: CalibrationProfile?
    public let error: CalibrationError?
}

public struct GuidedCalibrationCollector: Sendable {
    private enum Phase: Sendable { case ready, descending, ascending }

    private var phase: Phase = .ready
    private var samples: [CalibrationRepSample] = []
    private var topHipY: Double?
    private var torsoLengths: [Double] = []
    private var previousHipY: Double?
    private var previousTimestampMs: Int?
    private var repStartMs = 0
    private var bottomTimestampMs = 0
    private var maximumDepth = 0.0
    private var earlyTrunkAngle = 0.0
    private var bottomTrunkAngle = 0.0

    public init() {}

    public mutating func reset() {
        self = GuidedCalibrationCollector()
    }

    public mutating func ingest(_ observation: PoseObservation, minimumQuality: Double = 0.65) -> CalibrationUpdate? {
        guard
            let leftShoulder = observation.landmarks[.leftShoulder],
            let rightShoulder = observation.landmarks[.rightShoulder],
            let leftHip = observation.landmarks[.leftHip],
            let rightHip = observation.landmarks[.rightHip]
        else { return nil }

        let required = [leftShoulder, rightShoulder, leftHip, rightHip]
        guard required.allSatisfy({ $0.quality >= minimumQuality && !$0.isPredicted }) else { return nil }

        let shoulder = Geometry.midpoint(leftShoulder, rightShoulder)
        let hip = Geometry.midpoint(leftHip, rightHip)
        let canonicalHipY = 1 - hip.y
        let canonicalShoulder = Landmark(x: shoulder.x, y: 1 - shoulder.y)
        let canonicalHip = Landmark(x: hip.x, y: canonicalHipY)
        let torsoLength = hypot(canonicalShoulder.x - canonicalHip.x, canonicalShoulder.y - canonicalHip.y)
        guard torsoLength > 0.08 else { return nil }

        let trunkAngle = Geometry.trunkAngleFromVertical(hip: canonicalHip, shoulder: canonicalShoulder)
        let velocity: Double
        if let previousHipY, let previousTimestampMs, observation.timestampMs > previousTimestampMs {
            velocity = (canonicalHipY - previousHipY) / (Double(observation.timestampMs - previousTimestampMs) / 1_000) / torsoLength
        } else {
            velocity = 0
        }
        previousHipY = canonicalHipY
        previousTimestampMs = observation.timestampMs

        if phase == .ready {
            topHipY = max(topHipY ?? canonicalHipY, canonicalHipY)
            torsoLengths.append(torsoLength)
            if torsoLengths.count > 45 { torsoLengths.removeFirst() }
        }
        guard let topHipY else { return nil }
        let depth = max(0, (topHipY - canonicalHipY) / median(torsoLengths))

        switch phase {
        case .ready:
            if velocity < -0.08 && depth > 0.08 {
                phase = .descending
                repStartMs = observation.timestampMs
                bottomTimestampMs = observation.timestampMs
                maximumDepth = depth
                earlyTrunkAngle = trunkAngle
                bottomTrunkAngle = trunkAngle
            }
        case .descending:
            if depth > maximumDepth {
                maximumDepth = depth
                bottomTimestampMs = observation.timestampMs
                bottomTrunkAngle = trunkAngle
            }
            if velocity > 0.06 && maximumDepth >= 0.25 { phase = .ascending }
        case .ascending:
            if depth < 0.10 {
                samples.append(CalibrationRepSample(
                    depth: maximumDepth,
                    earlyDescentTrunkAngle: earlyTrunkAngle,
                    bottomTrunkAngle: bottomTrunkAngle,
                    descentDurationMs: max(1, bottomTimestampMs - repStartMs)
                ))
                phase = .ready
                let count = samples.count
                guard count == 3 else { return CalibrationUpdate(completedRepCount: count, profile: nil, error: nil) }
                do {
                    let profile = try CalibrationProfile.build(topHipY: topHipY, torsoLength: median(torsoLengths), samples: samples)
                    return CalibrationUpdate(completedRepCount: count, profile: profile, error: nil)
                } catch let error as CalibrationError {
                    samples.removeAll()
                    return CalibrationUpdate(completedRepCount: 0, profile: nil, error: error)
                } catch {
                    samples.removeAll()
                    return CalibrationUpdate(completedRepCount: 0, profile: nil, error: .inconsistentRepetitions)
                }
            }
        }
        return nil
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 1 }
        return sorted[sorted.count / 2]
    }
}
