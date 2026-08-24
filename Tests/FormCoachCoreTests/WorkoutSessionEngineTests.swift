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

    func testMovementBelowNinetyPercentOfCalibratedDepthDoesNotCount() async {
        let engine = WorkoutSessionEngine()
        await engine.start(config: SessionConfig(), calibration: FixtureFactory.calibration)
        let frames = [
            FixtureFactory.pose(timestamp: 0, hipY: 0.70, kneeAngle: 165),
            FixtureFactory.pose(timestamp: 250, hipY: 0.66, kneeAngle: 145),
            FixtureFactory.pose(timestamp: 500, hipY: 0.615, kneeAngle: 110),
            FixtureFactory.pose(timestamp: 750, hipY: 0.615, kneeAngle: 105),
            FixtureFactory.pose(timestamp: 1_000, hipY: 0.65, kneeAngle: 135),
            FixtureFactory.pose(timestamp: 1_300, hipY: 0.70, kneeAngle: 165)
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

    func testSpokenFeedbackPersistsTraceabilityMetadata() async {
        let engine = WorkoutSessionEngine()
        let config = SessionConfig(spokenThreshold: 0.80, ruleVersion: "test-rules-7")
        await engine.start(config: config, calibration: FixtureFactory.calibration)
        for pose in FixtureFactory.validRep(trunkAtBottom: 38) { _ = await engine.ingest(pose) }
        let feedback = await engine.finish().feedbackEvents.first
        XCTAssertEqual(feedback?.ruleVersion, "test-rules-7")
        XCTAssertEqual(feedback?.engineVersion, "fixture")
        XCTAssertEqual(feedback?.spokenThreshold, 0.80)
        XCTAssertFalse(feedback?.evidence.isEmpty ?? true)
    }
}
