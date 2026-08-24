import Foundation
import FormCoachCore

enum FixtureFactory {
    static let calibration = CalibrationProfile(topHipY: 0.70, torsoLength: 0.25, targetDepth: 0.40, baselineTrunkDelta: 3, targetDescentDurationMs: 800)

    static func pose(timestamp: Int, hipY: Double, kneeAngle: Double, trunkLean: Double = 8, quality: Double = 0.99, predicted: Bool = false) -> PoseObservation {
        let hipImageY = 1 - hipY
        let hipX = 0.50
        let torso = 0.25
        let dx = sin(trunkLean * .pi / 180) * torso
        let dy = cos(trunkLean * .pi / 180) * torso
        let shoulderImageY = 1 - (hipY + dy)
        let knee = kneePoint(hip: (hipX, hipImageY), angle: kneeAngle)
        let point: (Double, Double) -> Landmark = { x, y in
            Landmark(x: x, y: y, visibility: quality, presence: quality, isPredicted: predicted)
        }
        return PoseObservation(timestampMs: timestamp, landmarks: [
            .leftShoulder: point(hipX - dx - 0.02, shoulderImageY),
            .rightShoulder: point(hipX - dx + 0.02, shoulderImageY),
            .leftHip: point(hipX - 0.02, hipImageY),
            .rightHip: point(hipX + 0.02, hipImageY),
            .rightKnee: point(knee.0, knee.1),
            .rightAnkle: point(0.35, 0.88),
            .leftKnee: point(0.68, 0.74),
            .leftAnkle: point(0.82, 0.68)
        ])
    }

    static func validRep(start: Int = 0, trunkAtBottom: Double = 10, quality: Double = 0.99, predicted: Bool = false) -> [PoseObservation] {
        [
            pose(timestamp: start, hipY: 0.70, kneeAngle: 165, quality: quality, predicted: predicted),
            pose(timestamp: start + 250, hipY: 0.65, kneeAngle: 145, quality: quality, predicted: predicted),
            pose(timestamp: start + 500, hipY: 0.60, kneeAngle: 125, quality: quality, predicted: predicted),
            pose(timestamp: start + 800, hipY: 0.58, kneeAngle: 100, trunkLean: trunkAtBottom, quality: quality, predicted: predicted),
            pose(timestamp: start + 950, hipY: 0.58, kneeAngle: 98, trunkLean: trunkAtBottom, quality: quality, predicted: predicted),
            pose(timestamp: start + 1_200, hipY: 0.63, kneeAngle: 125, trunkLean: 9, quality: quality, predicted: predicted),
            pose(timestamp: start + 1_500, hipY: 0.69, kneeAngle: 155, quality: quality, predicted: predicted),
            pose(timestamp: start + 1_700, hipY: 0.70, kneeAngle: 165, quality: quality, predicted: predicted)
        ]
    }

    private static func kneePoint(hip: (Double, Double), angle: Double) -> (Double, Double) {
        let flex = max(0, min(1, (170 - angle) / 80))
        return (0.46 - flex * 0.08, hip.1 + 0.18 - flex * 0.04)
    }
}
