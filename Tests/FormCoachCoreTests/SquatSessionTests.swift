import XCTest
@testable import FormCoachCore

final class SquatSessionTests: XCTestCase {
    private func realVideoFrames(_ name: String) throws -> [PoseObservation] {
        struct Trace: Decodable { let frames: [PoseObservation] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("Docs/Testing/RealSquat-2026-10-15/results/\(name)-vision-poses.json")
        return try JSONDecoder().decode(Trace.self, from: Data(contentsOf: path)).frames
    }

    func testActualVisionStandingAndFiveCyclesAtBothResolutions() throws {
        for name in ["standing-then-five-squats", "standing-then-five-squats-hd"] {
            var session = SquatSession()
            let frames = try realVideoFrames(name)
            for frame in frames.prefix(61) { _ = session.ingest(frame) }
            XCTAssertNotNil(session.baseline, "Stable actual Vision pose must establish standing: \(name)")
            for frame in frames.dropFirst(61) { _ = session.ingest(frame) }
            XCTAssertEqual(session.summary.reps.count, 5, name)
        }
    }

    private func vision(_ frame: PoseObservation, allQuality: Double? = nil, hipOffset: Double = 0, missingAnkle: Bool = false) -> PoseObservation {
        var points = frame.landmarks
        for (id, var point) in points {
            let hip = id == .leftHip || id == .rightHip
            let quality = allQuality ?? (hip ? 0.42 : 0.8)
            point.visibility = quality; point.presence = quality
            if hip { point.x += hipOffset }
            points[id] = point
        }
        if missingAnkle { points[.rightAnkle] = nil; points[.leftAnkle] = nil }
        return PoseObservation(timestampMs: frame.timestampMs, landmarks: points, engineVersion: "apple-vision-2d-revision-1", imageWidth: frame.imageWidth, imageHeight: frame.imageHeight)
    }

    func testSupportedModerateVisionHipNeedsStableObservedSkeleton() {
        var stable = SquatSession(), jitter = SquatSession(), weak = SquatSession()
        for time in stride(from: 0, through: 3_000, by: 100) {
            let frame = SquatTestSequence.frame(timestamp: time)
            _ = stable.ingest(vision(frame))
            _ = jitter.ingest(vision(frame, hipOffset: time % 200 == 0 ? 0.04 : -0.04))
            _ = weak.ingest(vision(frame, allQuality: 0.42))
        }
        XCTAssertNotNil(stable.baseline)
        XCTAssertNil(jitter.baseline, "Confidence floor alone must not authorize a jittering joint")
        XCTAssertNil(weak.baseline, "A stationary but unsupported low-confidence skeleton is not evidence")
    }

    func testModerateVisionCountsCyclesButNotMovementOrMissingJoints() {
        var valid = SquatSession(), moving = SquatSession(), missing = SquatSession()
        for frame in SquatTestSequence.frames() {
            _ = valid.ingest(vision(frame))
            _ = missing.ingest(vision(frame, missingAnkle: true))
            _ = moving.ingest(vision(changed(frame, dx: sin(Double(frame.timestampMs) / 500) * 0.08)))
        }
        XCTAssertEqual(valid.summary.reps.count, 3)
        XCTAssertNil(moving.baseline)
        XCTAssertNil(missing.baseline)
        XCTAssertTrue(moving.summary.reps.isEmpty)
        XCTAssertTrue(missing.summary.reps.isEmpty)
    }

    func testModerateVisionOcclusionAndJointJumpCannotCompleteHalfRep() {
        for invalid in ["occlusion", "jump", "predicted"] {
            var session = SquatSession()
            for frame in SquatTestSequence.frames(repetitions: 1) {
                var pose = vision(frame)
                if frame.timestampMs == 3_800 {
                    var points = pose.landmarks
                    if invalid == "occlusion" { points[.rightHip] = nil; points[.leftHip] = nil }
                    if invalid == "jump" { points[.rightKnee]?.x += 0.2; points[.leftKnee]?.x += 0.2 }
                    if invalid == "predicted" { points[.rightHip]?.isPredicted = true; points[.leftHip]?.isPredicted = true }
                    pose = PoseObservation(timestampMs: pose.timestampMs, landmarks: points, engineVersion: pose.engineVersion, imageWidth: pose.imageWidth, imageHeight: pose.imageHeight)
                }
                _ = session.ingest(pose)
            }
            XCTAssertTrue(session.summary.reps.isEmpty, invalid)
        }
    }

    func testNonVisionModerateConfidenceDoesNotInheritVisionPolicy() {
        var detector = StaticStandingDetector()
        for time in stride(from: 0, through: 3_000, by: 100) {
            XCTAssertNil(detector.ingest(changed(SquatTestSequence.frame(timestamp: time), quality: 0.42)).baseline)
        }
    }

    private func changed(_ observation: PoseObservation, dx: Double = 0, quality: Double = 0.99) -> PoseObservation {
        PoseObservation(timestampMs: observation.timestampMs, landmarks: observation.landmarks.mapValues {
            Landmark(x: $0.x + dx, y: $0.y, visibility: quality, presence: quality)
        }, engineVersion: observation.engineVersion, imageWidth: observation.imageWidth, imageHeight: observation.imageHeight)
    }

    func testStandingRequiresElapsedTimeAndEnoughSamples() {
        var detector = StaticStandingDetector()
        for time in stride(from: 0, to: 2_000, by: 100) { XCTAssertNil(detector.ingest(SquatTestSequence.frame(timestamp: time)).baseline) }
        XCTAssertNotNil(detector.ingest(SquatTestSequence.frame(timestamp: 2_000)).baseline)
        var sparse = StaticStandingDetector()
        XCTAssertNil(sparse.ingest(SquatTestSequence.frame(timestamp: 0)).baseline)
        XCTAssertNil(sparse.ingest(SquatTestSequence.frame(timestamp: 2_000)).baseline)
    }

    func testMovingBodyAndBentKneeDoNotEstablishStanding() {
        var moving = StaticStandingDetector()
        var bent = StaticStandingDetector()
        for time in stride(from: 0, through: 5_000, by: 100) {
            XCTAssertNil(moving.ingest(changed(SquatTestSequence.frame(timestamp: time), dx: Double(time) / 100_000)).baseline)
            XCTAssertNil(bent.ingest(SquatTestSequence.frame(timestamp: time, depth: 0.7)).baseline)
        }
    }

    func testPortraitGeometryUsesEqualCoordinateUnits() throws {
        func point(_ x: Double, _ y: Double) -> Landmark { Landmark(x: x / 720, y: y / 1280) }
        let frame = PoseObservation(timestampMs: 0, landmarks: [.rightShoulder: point(100, 100), .rightHip: point(300, 300), .rightKnee: point(300, 600), .rightAnkle: point(600, 600)], imageWidth: 720, imageHeight: 1280)
        let features = try XCTUnwrap(SquatFeatures.extract(frame))
        XCTAssertEqual(features.trunkAngle, 45, accuracy: 0.001)
        XCTAssertEqual(features.kneeAngle, 90, accuracy: 0.001)
    }

    func testThreeCompleteCyclesCountExactlyThree() {
        var session = SquatSession()
        for frame in SquatTestSequence.frames() { _ = session.ingest(frame) }
        XCTAssertEqual(session.summary.reps.count, 3)
        XCTAssertTrue(session.summary.reps.allSatisfy { $0.descentDurationMs > 0 && $0.endMs > $0.startMs && $0.issues.isEmpty })
    }

    func testStationaryAndSmallMotionDoNotCount() {
        var stationary = SquatSession()
        for time in stride(from: 0, through: 10_000, by: 100) { _ = stationary.ingest(SquatTestSequence.frame(timestamp: time)) }
        XCTAssertNotNil(stationary.baseline)
        XCTAssertTrue(stationary.summary.reps.isEmpty)
        for (index, depth) in [0.0, 0, 0, 0.03, 0.08, 0.04, 0, 0, 0].enumerated() {
            _ = stationary.ingest(SquatTestSequence.frame(timestamp: 10_100 + index * 100, depth: depth))
        }
        XCTAssertTrue(stationary.summary.reps.isEmpty)
    }

    func testMissingBottomCannotBeStitchedIntoARep() {
        var session = SquatSession()
        for frame in SquatTestSequence.frames(repetitions: 0) { _ = session.ingest(frame) }
        for frame in SquatTestSequence.frames(repetitions: 1).filter({ $0.timestampMs > 3_000 }) {
            _ = session.ingest(frame.timestampMs == 3_800 ? changed(frame, quality: 0.1) : frame)
        }
        XCTAssertTrue(session.summary.reps.isEmpty)
    }

    func testMovingFeetInvalidatesBaselineWithoutLosingCompletedReps() {
        var session = SquatSession()
        for frame in SquatTestSequence.frames(repetitions: 1) { _ = session.ingest(frame) }
        XCTAssertEqual(session.summary.reps.count, 1)
        let result = session.ingest(changed(SquatTestSequence.frame(timestamp: 5_000), dx: 0.2))
        XCTAssertFalse(result.baselineReady)
        XCTAssertEqual(session.summary.reps.count, 1)
    }

    func testPauseRequiresReturningToTopAndDoesNotCountPartialMotion() {
        var session = SquatSession()
        for frame in SquatTestSequence.frames(repetitions: 0) { _ = session.ingest(frame) }
        for (index, depth) in [0.0, 0, 0, 0.3, 0.6, 1].enumerated() {
            _ = session.ingest(SquatTestSequence.frame(timestamp: 3_100 + index * 100, depth: depth))
        }
        session.interrupt()
        for (index, depth) in [1.0, 0.8, 0.4, 0, 0, 0, 0].enumerated() {
            _ = session.ingest(SquatTestSequence.frame(timestamp: 3_700 + index * 100, depth: depth))
        }
        XCTAssertTrue(session.summary.reps.isEmpty)
    }
}
