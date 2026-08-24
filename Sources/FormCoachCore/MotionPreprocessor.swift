import Foundation

public struct MotionPreprocessor: Sendable {
    private var previousHipY: Double?
    private var previousTimestampMs: Int?
    private var smoothedHipY: Double?
    private var smoothedTrunkAngle: Double?
    private let alpha: Double

    public init(alpha: Double = 0.42) { self.alpha = alpha }

    public mutating func process(
        _ observation: PoseObservation,
        config: SessionConfig,
        calibration: CalibrationProfile
    ) -> MotionFrame? {
        let required = requiredLandmarks(for: config.trainingSide)
        guard required.allSatisfy({ observation.landmarks[$0] != nil }) else { return nil }
        let points = required.compactMap { observation.landmarks[$0] }
        let quality = points.map(\.quality).min() ?? 0
        guard quality >= config.minimumLandmarkQuality else { return nil }

        guard
            let leftShoulder = observation.landmarks[.leftShoulder],
            let rightShoulder = observation.landmarks[.rightShoulder],
            let leftHip = observation.landmarks[.leftHip],
            let rightHip = observation.landmarks[.rightHip]
        else { return nil }

        let shoulder = Geometry.midpoint(leftShoulder, rightShoulder)
        let hip = Geometry.midpoint(leftHip, rightHip)
        let kneeID: LandmarkID = config.trainingSide == .left ? .leftKnee : .rightKnee
        let ankleID: LandmarkID = config.trainingSide == .left ? .leftAnkle : .rightAnkle
        let hipID: LandmarkID = config.trainingSide == .left ? .leftHip : .rightHip
        guard let frontHip = observation.landmarks[hipID], let knee = observation.landmarks[kneeID], let ankle = observation.landmarks[ankleID] else { return nil }

        let canonicalHipY = 1 - hip.y
        let rawTrunk = Geometry.trunkAngleFromVertical(hip: Landmark(x: hip.x, y: 1 - hip.y), shoulder: Landmark(x: shoulder.x, y: 1 - shoulder.y))
        let filteredHipY = smooth(canonicalHipY, previous: smoothedHipY)
        let filteredTrunk = smooth(rawTrunk, previous: smoothedTrunkAngle)
        let velocity: Double
        if let previousHipY, let previousTimestampMs, observation.timestampMs > previousTimestampMs {
            velocity = (filteredHipY - previousHipY) / (Double(observation.timestampMs - previousTimestampMs) / 1_000)
        } else {
            velocity = 0
        }
        self.previousHipY = filteredHipY
        self.previousTimestampMs = observation.timestampMs
        self.smoothedHipY = filteredHipY
        self.smoothedTrunkAngle = filteredTrunk

        return MotionFrame(
            timestampMs: observation.timestampMs,
            hipY: filteredHipY,
            hipDrop: max(0, (calibration.topHipY - filteredHipY) / calibration.torsoLength),
            verticalVelocity: velocity / calibration.torsoLength,
            frontKneeAngle: Geometry.angle(frontHip, knee, ankle),
            trunkAngle: filteredTrunk,
            poseQuality: quality,
            containsPredictedRequiredPoint: points.contains(where: \.isPredicted)
        )
    }

    public mutating func reset() {
        previousHipY = nil
        previousTimestampMs = nil
        smoothedHipY = nil
        smoothedTrunkAngle = nil
    }

    private func smooth(_ value: Double, previous: Double?) -> Double {
        guard let previous else { return value }
        return alpha * value + (1 - alpha) * previous
    }

    private func requiredLandmarks(for side: TrainingSide) -> [LandmarkID] {
        let front: [LandmarkID] = side == .left ? [.leftHip, .leftKnee, .leftAnkle] : [.rightHip, .rightKnee, .rightAnkle]
        return [.leftShoulder, .rightShoulder, .leftHip, .rightHip] + front
    }
}
