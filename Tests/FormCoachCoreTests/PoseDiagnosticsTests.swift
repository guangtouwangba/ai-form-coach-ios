import XCTest
@testable import FormCoachCore

final class PoseDiagnosticsTests: XCTestCase {
    private func modified(count: Int? = 1, transform: (Landmark) -> Landmark = { $0 }) -> PoseObservation {
        let frame = SquatTestSequence.frame(timestamp: 0)
        return PoseObservation(timestampMs: 0, landmarks: frame.landmarks.mapValues(transform), engineVersion: frame.engineVersion, imageWidth: frame.imageWidth, imageHeight: frame.imageHeight, detectedPersonCount: count)
    }

    func testDetectionCountIsNotConfusedWithPointConfidence() {
        XCTAssertEqual(SquatFeatures.assess(modified(count: 0)).failure, .noPerson)
        XCTAssertEqual(SquatFeatures.assess(modified(count: 2)).failure, .multiplePeople)
        XCTAssertEqual(SquatFeatures.assess(modified { Landmark(x: $0.x, y: $0.y, visibility: 0.1, presence: 0.1) }).failure, .lowConfidence)
    }

    func testSmallPersonAndOutOfFrameHaveDifferentReasons() {
        XCTAssertEqual(SquatFeatures.assess(modified { Landmark(x: 0.5 + ($0.x-0.5)*0.3, y: 0.5 + ($0.y-0.5)*0.3) }).failure, .tooSmall)
        XCTAssertEqual(SquatFeatures.assess(modified { Landmark(x: $0.x+1, y: $0.y) }).failure, .outOfFrame)
        let frame = PoseObservation(timestampMs: 0, landmarks: [.nose: Landmark(x: 0.5,y: 0.1)], detectedPersonCount: 1)
        XCTAssertEqual(SquatFeatures.assess(frame).failure, .missingJoints)
        XCTAssertFalse(SquatFeatures.assess(frame).joints.isEmpty)
    }

    func testFrameGapExplainsWhyStandingRestarts() {
        var detector = StaticStandingDetector()
        _ = detector.ingest(SquatTestSequence.frame(timestamp: 0))
        let result = detector.ingest(SquatTestSequence.frame(timestamp: 500))
        XCTAssertEqual(result.failure, .frameGap)
        XCTAssertNil(result.baseline)
    }

    func testAspectFillMatchesPortraitCameraPreviewCrop() throws {
        let center = try XCTUnwrap(PosePreviewMapping.point(Landmark(x:0.5,y:0.5), imageWidth:720,imageHeight:1280,viewWidth:390,viewHeight:844))
        XCTAssertEqual(center.x,195,accuracy:0.001); XCTAssertEqual(center.y,422,accuracy:0.001)
        let edge = try XCTUnwrap(PosePreviewMapping.point(Landmark(x:0,y:0), imageWidth:720,imageHeight:1280,viewWidth:390,viewHeight:844))
        XCTAssertLessThan(edge.x,0); XCTAssertEqual(edge.y,0,accuracy:0.001)
        let fit = try XCTUnwrap(PosePreviewMapping.point(Landmark(x:0,y:0), imageWidth:720,imageHeight:1280,viewWidth:390,viewHeight:844,fill:false))
        XCTAssertEqual(fit.x,0,accuracy:0.001); XCTAssertGreaterThan(fit.y,0)
    }
}
