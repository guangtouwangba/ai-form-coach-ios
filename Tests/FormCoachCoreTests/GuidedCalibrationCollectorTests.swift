import XCTest
@testable import FormCoachCore

final class GuidedCalibrationCollectorTests: XCTestCase {
    func testThreeObservedRepetitionsProducePersonalProfile() {
        var collector = GuidedCalibrationCollector()
        var updates: [CalibrationUpdate] = []
        for start in [0, 2_200, 4_400] {
            for pose in FixtureFactory.validRep(start: start) {
                if let update = collector.ingest(pose) { updates.append(update) }
            }
        }

        XCTAssertEqual(updates.map(\.completedRepCount), [1, 2, 3])
        XCTAssertNotNil(updates.last?.profile)
        XCTAssertEqual(updates.last?.profile?.topHipY ?? 0, 0.70, accuracy: 0.001)
    }

    func testLowQualityFramesCannotAdvanceCalibration() {
        var collector = GuidedCalibrationCollector()
        var updates: [CalibrationUpdate] = []
        for start in [0, 2_200, 4_400] {
            for pose in FixtureFactory.validRep(start: start, quality: 0.4) {
                if let update = collector.ingest(pose) { updates.append(update) }
            }
        }
        XCTAssertTrue(updates.isEmpty)
    }
}
