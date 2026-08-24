import XCTest
@testable import FormCoachCore

final class CalibrationTests: XCTestCase {
    func testBuildUsesMedianOfThreeGuidedRepetitions() throws {
        let profile = try CalibrationProfile.build(topHipY: 0.7, torsoLength: 0.25, samples: [
            .init(depth: 0.41, earlyDescentTrunkAngle: 9, bottomTrunkAngle: 13, descentDurationMs: 850),
            .init(depth: 0.39, earlyDescentTrunkAngle: 8, bottomTrunkAngle: 11, descentDurationMs: 800),
            .init(depth: 0.40, earlyDescentTrunkAngle: 8, bottomTrunkAngle: 13, descentDurationMs: 820)
        ])
        XCTAssertEqual(profile.targetDepth, 0.40, accuracy: 0.001)
        XCTAssertEqual(profile.baselineTrunkDelta, 4, accuracy: 0.001)
        XCTAssertEqual(profile.targetDescentDurationMs, 820)
    }

    func testBuildRejectsInconsistentRepetitions() {
        XCTAssertThrowsError(try CalibrationProfile.build(topHipY: 0.7, torsoLength: 0.25, samples: [
            .init(depth: 0.20, earlyDescentTrunkAngle: 8, bottomTrunkAngle: 10, descentDurationMs: 800),
            .init(depth: 0.40, earlyDescentTrunkAngle: 8, bottomTrunkAngle: 10, descentDurationMs: 800),
            .init(depth: 0.50, earlyDescentTrunkAngle: 8, bottomTrunkAngle: 10, descentDurationMs: 800)
        ]))
    }
}
