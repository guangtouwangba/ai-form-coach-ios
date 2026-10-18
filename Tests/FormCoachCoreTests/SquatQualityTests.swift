import XCTest
@testable import FormCoachCore

final class SquatQualityTests: XCTestCase {
    func testActualVideoBackToBackAttemptsAreNotLostAfterFirstReturn() throws {
        struct Replay: Decodable { let frames: [PoseObservation] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("Docs/Testing/Squat-Coaching-2026-10-16/results/real-mediapipe-poses.json")
        let frames = try JSONDecoder().decode(Replay.self, from: Data(contentsOf: file)).frames
        var session = SquatSession()
        for frame in frames { _ = session.ingest(frame) }
        session.interrupt(reason: .videoEnded)
        XCTAssertEqual(session.summary.reps.count, 5)
        XCTAssertEqual(session.summary.squatAnalysis?.attempts.count, 5)
        XCTAssertEqual(session.summary.squatAnalysis?.attempts.compactMap(\.countedRepID), [1, 2, 3, 4, 5])
    }
    private func session(target: SquatTrainingTarget = .init()) -> SquatSession {
        var session = SquatSession(); session.target = target
        for frame in SquatTestSequence.frames(repetitions: 0) { _ = session.ingest(frame) }
        return session
    }

    private func motion(_ session: inout SquatSession, depths: [Double], start: Int = 3100, interval: Int = 100) {
        for (i, depth) in depths.enumerated() { _ = session.ingest(SquatTestSequence.frame(timestamp: start + i * interval, depth: depth)) }
    }

    func testSmallSustainedAttemptIsRetainedWithoutChangingCounter() throws {
        var session = session()
        motion(&session, depths: [0, 0, 0, 0.05, 0.08, 0.1, 0.12, 0.14, 0.14, 0.12, 0.1, 0.05, 0, 0, 0, 0])
        XCTAssertEqual(session.summary.reps.count, 0)
        let attempt = try XCTUnwrap(session.summary.squatAnalysis?.attempts.first)
        XCTAssertNil(attempt.countedRepID)
        XCTAssertEqual(attempt.endReason, .returnedToStart)
        XCTAssertEqual(attempt.assessments.first { $0.item == .rangeOfMotion }?.status, .notConfigured)
        XCTAssertNil(attempt.recommendation, "Small observed movement is not automatically a technique fault")
    }

    func testCompleteCyclesHaveTargetsAndAlignedEvidence() throws {
        var session = SquatSession(); session.target = .init(minimumDescentMs: 2000)
        for frame in SquatTestSequence.frames() { _ = session.ingest(frame) }
        XCTAssertEqual(session.summary.reps.count, 3)
        let attempts = try XCTUnwrap(session.summary.squatAnalysis?.attempts)
        XCTAssertEqual(attempts.count, 3)
        XCTAssertEqual(attempts.compactMap(\.countedRepID), [1, 2, 3])
        for attempt in attempts {
            XCTAssertEqual(attempt.assessments.first { $0.item == .descentTempo }?.status, .outsideTarget)
            XCTAssertTrue(attempt.recommendation?.contains("所选") == true)
            XCTAssertGreaterThan(attempt.coverage.descentFrames, 1)
            XCTAssertGreaterThan(attempt.coverage.ascentFrames, 1)
            XCTAssertTrue(attempt.assessments.allSatisfy { (attempt.startMs...attempt.endMs).contains($0.evidenceMs) })
        }
    }

    func testSlowDescentMeetsSelectedTask() throws {
        var session = session(target: .init(minimumDescentMs: 1500))
        let descent = (0...20).map { Double($0) / 20 }
        let ascent = stride(from: 0.9, through: 0, by: -0.1).map { $0 }
        motion(&session, depths: [0, 0, 0] + descent + ascent + [0, 0, 0, 0])
        let attempt = try XCTUnwrap(session.summary.squatAnalysis?.attempts.first)
        XCTAssertEqual(attempt.assessments.first { $0.item == .descentTempo }?.status, .withinTarget)
    }

    func testOccludedBottomTerminatesAttemptAndNeverInventsReturnOrAdvice() throws {
        var session = session(target: .init(minimumDescentMs: 2000))
        motion(&session, depths: [0, 0, 0, 0.2, 0.4, 0.6, 0.8])
        let update = session.ingest(PoseObservation(timestampMs: 3800, landmarks: [:]))
        let attempt = try XCTUnwrap(update.attempt)
        XCTAssertEqual(attempt.endReason, .trackingLost)
        XCTAssertEqual(attempt.coverage.failure, .noPerson)
        XCTAssertTrue(attempt.assessments.allSatisfy { $0.status == .notAssessable })
        XCTAssertNil(attempt.ascentDurationMs); XCTAssertNil(attempt.recommendation)
        motion(&session, depths: [1, 0.8, 0.4, 0, 0, 0, 0], start: 3900)
        XCTAssertEqual(session.summary.reps.count, 0)
        XCTAssertEqual(session.summary.squatAnalysis?.attempts.count, 1)
    }

    func testVideoEndPauseAndCameraMoveAreDifferentFromUserFault() throws {
        for reason in [AttemptEndReason.videoEnded, .paused, .groupEnded] {
            var session = session(target: .init(minimumDescentMs: 2000))
            motion(&session, depths: [0, 0, 0, 0.2, 0.4, 0.6, 0.8])
            session.interrupt(reason: reason); session.interrupt(reason: reason)
            let attempts = try XCTUnwrap(session.summary.squatAnalysis?.attempts)
            XCTAssertEqual(attempts.count, 1)
            XCTAssertEqual(attempts[0].endReason, reason)
            XCTAssertTrue(attempts[0].assessments.allSatisfy { $0.status == .notAssessable })
        }
        var moved = session()
        motion(&moved, depths: [0, 0, 0, 0.2, 0.4, 0.6])
        let frame = SquatTestSequence.frame(timestamp: 3800, depth: 0.8)
        let update = moved.ingest(PoseObservation(timestampMs: frame.timestampMs, landmarks: frame.landmarks.mapValues { p in
            var p = p; p.x += 0.2; return p
        }, imageWidth: frame.imageWidth, imageHeight: frame.imageHeight))
        XCTAssertEqual(update.attempt?.endReason, .cameraMoved)
    }

    func testFrameGapDoesNotStitchAndReportsCause() throws {
        var session = session()
        motion(&session, depths: [0, 0, 0, 0.2, 0.4, 0.6])
        let result = session.ingest(SquatTestSequence.frame(timestamp: 4300, depth: 0.8))
        XCTAssertEqual(result.failure, .frameGap)
        XCTAssertEqual(result.attempt?.coverage.failure, .frameGap)
        XCTAssertTrue(result.attempt?.assessments.allSatisfy { $0.status == .notAssessable } == true)
    }

    func testNoiseCannotManufactureAnAttemptAndCalibrationIsNotTraining() {
        var session = session()
        motion(&session, depths: [0, 0.01, 0.02, 0.01, 0, 0.03, 0, 0, 0])
        XCTAssertTrue(session.summary.squatAnalysis?.attempts.isEmpty ?? true)
        for frame in SquatTestSequence.frames() { _ = session.ingest(frame, counting: false) }
        XCTAssertTrue(session.summary.squatAnalysis?.attempts.isEmpty ?? true)
    }

    func testDisablingCountingMidAttemptCannotStitchAcrossPause() throws {
        var session = session()
        motion(&session, depths: [0, 0, 0, 0.2, 0.4, 0.6])
        let update = session.ingest(SquatTestSequence.frame(timestamp: 3800, depth: 0.8), counting: false)
        XCTAssertEqual(update.attempt?.endReason, .paused)
        motion(&session, depths: [1, 0.8, 0.4, 0, 0, 0, 0], start: 3900)
        XCTAssertEqual(session.summary.reps.count, 0)
        XCTAssertEqual(session.summary.squatAnalysis?.attempts.count, 1)
    }

    func testLegacySummaryDecodesAndNewAnalysisRoundTrips() throws {
        let old = Data(#"{"reps":[],"suppressedIssueCount":0,"feedbackEvents":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(WorkoutSummary.self, from: old).squatAnalysis)
        var session = session()
        motion(&session, depths: [0, 0, 0, 0.2, 0.4, 0.6, 1, 1, 0.8, 0.4, 0, 0, 0, 0])
        let data = try JSONEncoder().encode(session.summary)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSummary.self, from: data), session.summary)
    }

    func testRangeNeedsExplicitNamedReferenceAndTargetFreezesPerAttempt() throws {
        var session = session(target: .init(minimumDescentMs: 2000, minimumHipDrop: 2))
        motion(&session, depths: [0, 0, 0, 0.2, 0.4, 0.6, 1])
        session.target = .init(minimumDescentMs: 200, minimumHipDrop: 2, referenceName: "test reference")
        motion(&session, depths: [1, 0.8, 0.4, 0, 0, 0, 0], start: 3800)
        let attempt = try XCTUnwrap(session.summary.squatAnalysis?.attempts.first)
        XCTAssertEqual(attempt.target.minimumDescentMs, 2000)
        XCTAssertEqual(attempt.assessments.first { $0.item == .rangeOfMotion }?.status, .notConfigured)
        XCTAssertEqual(attempt.assessments.first { $0.item == .descentTempo }?.status, .outsideTarget)
    }
}
