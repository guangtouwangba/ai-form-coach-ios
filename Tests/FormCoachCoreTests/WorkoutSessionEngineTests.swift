import XCTest
@testable import FormCoachCore

final class WorkoutSessionEngineTests: XCTestCase {
    func testCompleteSequenceCountsExactlyOneRep() async {
        let engine = WorkoutSessionEngine()
        await engine.start(config: SessionConfig(), calibration: FixtureFactory.calibration)
        var events: [SessionEvent] = []
        for pose in FixtureFactory.validRep() { events += await engine.ingest(pose) }
        let summary = await engine.finish()
        XCTAssertEqual(summary.effectiveRepCount, 1)
        XCTAssertEqual(events.filter { if case .repCompleted = $0 { return true }; return false }.count, 1)
    }

    func testPartialMovementDoesNotCount() async {
        let engine = WorkoutSessionEngine()
        await engine.start(config: SessionConfig(), calibration: FixtureFactory.calibration)
        let frames = [
            FixtureFactory.pose(timestamp: 0, hipY: 0.70, kneeAngle: 165),
            FixtureFactory.pose(timestamp: 300, hipY: 0.67, kneeAngle: 150),
            FixtureFactory.pose(timestamp: 600, hipY: 0.69, kneeAngle: 160)
        ]
        for pose in frames { _ = await engine.ingest(pose) }
        let summary = await engine.finish()
        XCTAssertEqual(summary.effectiveRepCount, 0)
    }

    func testLowConfidenceIssueNeverProducesFeedback() async {
        let engine = WorkoutSessionEngine()
        await engine.start(config: SessionConfig(minimumLandmarkQuality: 0.5), calibration: FixtureFactory.calibration)
        var feedback: [FeedbackEvent] = []
        for pose in FixtureFactory.validRep(trunkAtBottom: 35, quality: 0.75) {
            for event in await engine.ingest(pose) {
                if case let .feedback(value) = event { feedback.append(value) }
            }
        }
        XCTAssertTrue(feedback.isEmpty)
        let issues = await engine.finish().reps.flatMap(\.issues)
        XCTAssertTrue(issues.allSatisfy { $0.disposition != .spoken })
    }

    func testPredictedRequiredPointSuppressesIssue() async {
        let engine = WorkoutSessionEngine()
        await engine.start(config: SessionConfig(minimumLandmarkQuality: 0.5), calibration: FixtureFactory.calibration)
        for pose in FixtureFactory.validRep(trunkAtBottom: 35, predicted: true) { _ = await engine.ingest(pose) }
        let issues = await engine.finish().reps.flatMap(\.issues)
        XCTAssertFalse(issues.isEmpty)
        XCTAssertTrue(issues.allSatisfy { $0.disposition == .suppressed })
    }

    func testFeedbackCooldownPreventsRepeatedCue() async {
        let engine = WorkoutSessionEngine()
        await engine.start(config: SessionConfig(feedbackCooldownMs: 5_000), calibration: FixtureFactory.calibration)
        var cues: [FeedbackEvent] = []
        for pose in FixtureFactory.validRep(start: 0, trunkAtBottom: 38) + FixtureFactory.validRep(start: 2_000, trunkAtBottom: 38) {
            for event in await engine.ingest(pose) {
                if case let .feedback(value) = event { cues.append(value) }
            }
        }
        XCTAssertLessThanOrEqual(cues.count, 1)
    }
}
