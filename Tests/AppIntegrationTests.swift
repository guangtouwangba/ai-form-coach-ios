import XCTest
import SwiftData
import FormCoachCore
@testable import AIFormCoach

@MainActor
final class AppIntegrationTests: XCTestCase {
    private var directory: URL!
    private var container: ModelContainer!
    private var draftURL: URL { directory.appendingPathComponent("draft.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("coach-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        container = try ModelContainer(for: StoredWorkoutSession.self, configurations:
            ModelConfiguration(url: directory.appendingPathComponent("store.sqlite")))
    }

    override func tearDownWithError() throws {
        container = nil
        try FileManager.default.removeItem(at: directory)
    }

    private func model() -> P0FlowModel {
        let model = P0FlowModel(storageURL: draftURL, cameraEnabled: false)
        model.attach(ModelContext(container))
        return model
    }

    private func settle(_ model: P0FlowModel) async {
        let deadline = Date().addingTimeInterval(5)
        while model.busy && Date() < deadline { await Task.yield() }
        XCTAssertFalse(model.busy, "Asynchronous flow did not settle")
    }

    func testLiveInputToTwoGroupsSaveReloadAndDelete() async throws {
        let flow = model()
        // Only sensor input is synthetic; use the same model, engine and disk stores as the app.
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查", calibration: FixtureFactory.calibration)
        flow.resumeDraft()
        await settle(flow)
        flow.startGroup()
        await settle(flow)
        for pose in FixtureFactory.validRep(trunkAtBottom: 38) { await flow.receive(pose) }
        XCTAssertEqual(flow.completedTrainingReps, 1)
        flow.finishGroup()
        await settle(flow)
        XCTAssertEqual(flow.groups.count, 1)
        XCTAssertFalse(flow.issues.isEmpty)
        flow.startGroup()
        await settle(flow)
        for pose in FixtureFactory.validRep(start: 5000) { await flow.receive(pose) }
        flow.finishGroup()
        await settle(flow)
        XCTAssertEqual(flow.groups.count, 2)
        flow.saveSession()
        XCTAssertEqual(flow.currentID, "P0-SAVE-SUCCESS")
        XCTAssertNil(flow.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draftURL.path))

        let reopened = model()
        XCTAssertEqual(reopened.records.count, 1)
        let record = try XCTUnwrap(reopened.records.first)
        XCTAssertEqual(record.repCount, 2)
        reopened.openRecord(record)
        XCTAssertEqual(reopened.groups.count, 2)
        reopened.openGroup(0)
        XCTAssertEqual(reopened.summary.reps.count, 1)
        reopened.openRep(try XCTUnwrap(reopened.summary.reps.first))
        XCTAssertFalse(reopened.selectedRep?.issues.isEmpty ?? true)
        reopened.openRecord(record)
        reopened.performSecondary()
        XCTAssertEqual(reopened.currentID, "P0-DELETE-CONFIRM")
        reopened.performPrimary()
        XCTAssertEqual(reopened.currentID, "P0-DELETE-SUCCESS")
        XCTAssertTrue(model().records.isEmpty)
    }

    func testDraftReloadRestoresCompletedRepsWithoutCountingPartialRep() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查", calibration: FixtureFactory.calibration)
        flow.resumeDraft()
        await settle(flow)
        flow.startGroup()
        await settle(flow)
        for pose in FixtureFactory.validRep() { await flow.receive(pose) }
        for pose in FixtureFactory.validRep(start: 3000).prefix(5) { await flow.receive(pose) }
        flow.interrupt(to: "P0-HOME")
        await settle(flow)
        let reopened = model()
        XCTAssertEqual(reopened.draft?.active.reps.count, 1)
        reopened.resumeDraft()
        await settle(reopened)
        reopened.performPrimary()
        for pose in FixtureFactory.validRep(start: 3000).suffix(3) { await reopened.receive(pose) }
        XCTAssertEqual(reopened.completedTrainingReps, 1)
        for pose in FixtureFactory.validRep(start: 6000) { await reopened.receive(pose) }
        XCTAssertEqual(reopened.completedTrainingReps, 2)
    }

    func testDraftWriteFailureRetainsDraftAndDoesNotClaimSuccess() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查")
        flow.checkpoint()
        // A file at the parent path makes subsequent atomic draft writes fail.
        try FileManager.default.removeItem(at: draftURL)
        try FileManager.default.createDirectory(at: draftURL, withIntermediateDirectories: false)
        flow.checkpoint()
        XCTAssertNotNil(flow.saveFailureMessage)
        XCTAssertNotNil(flow.draft)
        XCTAssertNotEqual(flow.currentID, "P0-SAVE-SUCCESS")
    }

    func testCalibrationProgressRequiresThreeObservedMovements() async throws {
        let flow = model()
        flow.navigate(to: "P0-EXERCISE-LIBRARY")
        flow.performPrimary()
        flow.navigate(to: "P0-CALIBRATION-READY")
        flow.performPrimary()
        flow.performPrimary()
        XCTAssertEqual(flow.completedCalibrationReps, 0)
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-RUNNING")
        for start in [0, 3000, 6000] {
            for pose in FixtureFactory.validRep(start: start) { await flow.receive(pose) }
        }
        XCTAssertEqual(flow.completedCalibrationReps, 3)
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-SUCCESS")
        XCTAssertNotNil(flow.draft?.calibration)
        flow.performPrimary()
        await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-TRAINING-ACTIVE")
        for pose in FixtureFactory.validRep(start: 9000) { await flow.receive(pose) }
        XCTAssertEqual(flow.completedTrainingReps, 1)
    }
}
