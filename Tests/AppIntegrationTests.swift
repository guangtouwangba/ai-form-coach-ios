import XCTest
import SwiftData
import FormCoachCore
import AVFoundation
import ImageIO
import SwiftUI
import UIKit
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

    override func tearDown() async throws {
        container = nil
        // Let the hosting controller's cancelled SwiftUI tasks and autoreleased
        // contexts release their SQLite handles before deleting the test store.
        try await Task.sleep(for: .milliseconds(50))
        try FileManager.default.removeItem(at: directory)
    }

    private func model() -> P0FlowModel {
        let model = P0FlowModel(storageURL: draftURL, cameraEnabled: false, authorizationStatus: { .authorized })
        model.attach(ModelContext(container))
        return model
    }

    private func settle(_ model: P0FlowModel) async {
        let deadline = Date().addingTimeInterval(5)
        while model.busy && Date() < deadline { await Task.yield() }
        XCTAssertFalse(model.busy, "Asynchronous flow did not settle")
    }

    private func waitForAnalyzedFrames(_ camera: CameraService, count: Int = 5, after baseline: Int = 0) async {
        let deadline = Date().addingTimeInterval(10)
        while camera.processedFrameCount - baseline < count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThanOrEqual(camera.processedFrameCount - baseline, count,
                                    "Camera must keep analyzing frames, including frames with no person")
        XCTAssertEqual(camera.status, .running)
        print("Camera analyzed frames: \(camera.processedFrameCount - baseline)")
    }

    private func preview(in view: UIView) -> PreviewView? {
        if let preview = view as? PreviewView { return preview }
        return view.subviews.lazy.compactMap { self.preview(in: $0) }.first
    }

    // Opt-in manual design-review harness. The UI is operated through the
    // simulator; only sensor input is synthetic, and its database is temporary.
    func testInteractiveSimulatorDesignReview() async throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["COACH_INTERACTIVE_DESIGN_REVIEW"] == "1" else {
            throw XCTSkip("Interactive review is opt-in; not part of automated regression")
        }
        let flow = model()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let previousWindowHidden = previousWindow?.isHidden ?? false
        let previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        let window = UIWindow(windowScene: scene)
        let root = P0FlowRootView(flow: flow).modelContainer(container)
            .overlay(alignment: .topTrailing) {
                Text("模拟姿态输入")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black).padding(4)
                    .background(.yellow, in: RoundedRectangle(cornerRadius: 4))
                    .padding(.trailing, 8).padding(.top, 4)
                    .allowsHitTesting(false)
            }
        window.rootViewController = UIHostingController(rootView: root)
        // Keep UI automation from activating controls in the covered app window.
        previousWindow?.isHidden = true
        window.makeKeyAndVisible()
        UIApplication.shared.isIdleTimerDisabled = true
        let stopURL = FileManager.default.temporaryDirectory.appendingPathComponent("coach-design-review-stop")
        let scenarioURL = FileManager.default.temporaryDirectory.appendingPathComponent("coach-design-review-scenario.txt")
        if FileManager.default.fileExists(atPath: stopURL.path) { try FileManager.default.removeItem(at: stopURL) }
        if FileManager.default.fileExists(atPath: scenarioURL.path) { try FileManager.default.removeItem(at: scenarioURL) }
        defer {
            flow.camera.stop()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.isHidden = previousWindowHidden
            previousWindow?.makeKey()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
        print("INTERACTIVE_DESIGN_REVIEW_READY stop=\(stopURL.path) scenario=\(scenarioURL.path)")
        var timestamp = 0
        var repIndex = 0
        let deadline = Date().addingTimeInterval(1200)
        while Date() < deadline, !FileManager.default.fileExists(atPath: stopURL.path) {
            let scenario = (try? String(contentsOf: scenarioURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? "normal"
            if flow.isSquat {
                if scenario == "no-frames" {
                    timestamp += 100; try await Task.sleep(for: .milliseconds(100))
                } else if flow.activeTraining && scenario != "low-quality" {
                    let depths: [Double] = scenario == "small-motion"
                        ? [0, 0, 0, 0.05, 0.08, 0.1, 0.14, 0.14, 0.1, 0.05, 0, 0, 0, 0]
                        : [0.0, 0, 0, 0, 0.2, 0.4, 0.6, 0.8, 1, 1, 0.8, 0.6, 0.4, 0.2, 0, 0, 0, 0]
                    for depth in depths {
                        guard flow.activeTraining else { break }
                        await flow.receive(SquatTestSequence.frame(timestamp: timestamp, depth: depth))
                        timestamp += 100; try await Task.sleep(for: .milliseconds(100))
                    }
                } else {
                    if flow.needsCamera {
                        if scenario == "low-quality" {
                            await flow.receive(PoseObservation(timestampMs: timestamp, landmarks: [:]))
                        } else { await flow.receive(SquatTestSequence.frame(timestamp: timestamp)) }
                    }
                    timestamp += 100; try await Task.sleep(for: .milliseconds(100))
                }
                continue
            }
            if scenario == "low-quality", flow.needsCamera {
                await flow.receive(FixtureFactory.pose(timestamp: timestamp, hipY: 0.70, kneeAngle: 165, quality: 0.2))
                timestamp += 200
                try await Task.sleep(for: .milliseconds(200))
            } else if scenario == "no-frames" {
                timestamp += 200
                try await Task.sleep(for: .milliseconds(200))
            } else if flow.currentID == "P0-CALIBRATION-RUNNING" || flow.activeTraining {
                let trunk = flow.activeTraining && repIndex % 3 == 2 ? 38.0 : 10.0
                for pose in FixtureFactory.validRep(start: timestamp, trunkAtBottom: trunk) {
                    guard flow.needsCamera else { break }
                    await flow.receive(pose)
                    try await Task.sleep(for: .milliseconds(200))
                }
                timestamp += 2200
                repIndex += 1
            } else {
                if flow.needsCamera {
                    await flow.receive(FixtureFactory.pose(timestamp: timestamp, hipY: 0.70, kneeAngle: 165))
                }
                timestamp += 200
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: stopURL.path), "Interactive review reached its time limit")
        #else
        throw XCTSkip("Interactive design review is simulator-only")
        #endif
    }

    func testSquatAutomaticStandingCountsAndPersistsExerciseIdentity() async throws {
        let flow = model()
        flow.selectTab("P0-HOME"); flow.beginNewTraining(); flow.performPrimary()
        XCTAssertTrue(flow.isSquat)
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-READY")
        for time in stride(from: 0, through: 2_400, by: 100) { await flow.receive(SquatTestSequence.frame(timestamp: time)) }
        XCTAssertEqual(flow.currentID, "P0-TRAINING-ACTIVE")
        for frame in SquatTestSequence.frames(repetitions: 3) { await flow.receive(frame) }
        XCTAssertEqual(flow.completedTrainingReps, 3)
        flow.interrupt(to: "P0-EXIT-MENU")
        XCTAssertEqual(flow.completedTrainingReps, 3)
        flow.resumeCurrentGroup()
        flow.finishGroup(); flow.saveSession()
        let record = try XCTUnwrap(flow.records.first)
        XCTAssertEqual(record.exerciseID, "bodyweight_squat")
        XCTAssertEqual(record.repCount, 3)
        flow.openRecord(record)
        XCTAssertTrue(flow.isSquat)
        let reopened = model()
        XCTAssertEqual(reopened.records.first?.exerciseID, "bodyweight_squat")
    }

    func testLandmarkReplayCountsAndRejectsNonMonotonicTimestamps() async throws {
        let url = directory.appendingPathComponent("squat.json")
        try JSONEncoder().encode(PoseReplayFile(version: 1, frames: SquatTestSequence.frames())).write(to: url)
        let result = try await VideoReplayAnalyzer.run(url: url) { _ in }
        XCTAssertEqual(result.reps.count, 3)
        try JSONEncoder().encode(PoseReplayFile(version: 1, frames: [SquatTestSequence.frame(timestamp: 100), SquatTestSequence.frame(timestamp: 100)])).write(to: url)
        do { _ = try await VideoReplayAnalyzer.run(url: url) { _ in }; XCTFail("Repeated timestamps must not pass") }
        catch { XCTAssertTrue(error is ReplayError) }
    }

    func testVideoReplayDecodesActualMovieAndDoesNotCountEmptyFrames() async throws {
        let url = directory.appendingPathComponent("empty.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 240, AVVideoHeightKey: 320])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 240, kCVPixelBufferHeightKey as String: 320])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for index in 0..<40 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer), kCVReturnSuccess)
            let pixel = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 120, CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        #if targetEnvironment(simulator)
        // This simulator cannot initialize Vision body pose. Decode real movie
        // frames with a probe; the device branch exercises actual Apple Vision.
        let probe = EmptyVideoPoseProbe()
        let result = try await VideoReplayAnalyzer.run(url: url, perception: probe) { _ in }
        XCTAssertEqual(probe.frames, 40)
        #else
        let result = try await VideoReplayAnalyzer.run(url: url) { _ in }
        #endif
        XCTAssertTrue(result.reps.isEmpty)
    }

    // Opt-in external real-video validation. Files are copied into the app's
    // Documents/replay-validation folder; no network access or synthetic poses.
    func testSelectedRealSquatVideoReplay() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real video inference requires a physical iPhone")
        #else
        guard ProcessInfo.processInfo.environment["COACH_REAL_REPLAY_TEST"] == "1" else {
            throw XCTSkip("Opt-in downloaded video validation")
        }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("replay-validation")
        let cases = ProcessInfo.processInfo.environment["COACH_REAL_REPLAY_HD_ONLY"] == "1"
            ? [("standing-then-five-squats-hd", 5)]
            : [("original-6525519", 0), ("standing-then-five-squats", 5), ("standing-then-five-squats-hd", 5)]
        for (name, expected) in cases {
            let url = base.appendingPathComponent(name + ".mp4")
            let trace = RealVideoReplayTrace()
            let perception = RecordingVideoPerception()
            let result = try await VideoReplayAnalyzer.run(url: url, perception: perception) { value in await trace.append(value) }
            let snapshots = await trace.values
            let payload: [String: Any] = [
                "file": url.lastPathComponent, "expected": expected, "actual": result.reps.count,
                "decodedPoseFrames": perception.frames.count,
                "snapshots": snapshots.map { ["timeMs": $0.timeMs, "count": $0.count, "baselineReady": $0.baselineReady, "message": $0.message] as [String: Any] },
                "reps": result.reps.map { ["id": $0.id, "startMs": $0.startMs, "endMs": $0.endMs] }
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: base.appendingPathComponent(name + "-result.json"))
            try JSONEncoder().encode(PoseReplayFile(version: 1, frames: perception.frames)).write(to: base.appendingPathComponent(name + "-vision-poses.json"))
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            print("REAL_VIDEO_REPLAY \(String(decoding: data, as: UTF8.self))")
            // Exercise the same file copy, AVPlayer setup and analysis used by
            // the import button, this time with the production default adapter.
            let replay = SquatReplayModel()
            replay.importFile(url)
            let deadline = Date().addingTimeInterval(60)
            while replay.running, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            XCTAssertFalse(replay.running)
            XCTAssertNil(replay.error)
            XCTAssertEqual(replay.summary?.reps.count, result.reps.count)
            XCTAssertNotNil(replay.player)
            replay.cancel()
            XCTAssertEqual(result.reps.count, expected, "Real video count differs from the manually annotated clip")
            XCTAssertEqual(snapshots.contains(where: \.baselineReady), expected > 0)
        }
        #endif
    }

    func testMediaPipeActualVideoReplayAndModelSelection() async throws {
        guard ProcessInfo.processInfo.environment["COACH_MEDIAPIPE_VIDEO_TEST"] == "1" else { throw XCTSkip("Opt-in real MediaPipe inference") }
        XCTAssertTrue(PoseEngineChoice.mediaPipe.isAvailable, "MediaPipe must actually be linked")
        let root = try XCTUnwrap(Bundle(for: AppIntegrationTests.self).url(forResource: "media", withExtension: nil))
        let url = root.appendingPathComponent("standing-then-five-squats-hd.mp4")
        let diagnostics = ReplayRunDiagnostics()
        let trace = RealVideoReplayTrace()
        let result = try await VideoReplayAnalyzer.run(url: url, engine: .mediaPipe, target: .init(minimumDescentMs: 2000), diagnostics: diagnostics) { await trace.append($0) }
        let report = await diagnostics.report(engine: "MediaPipe Full", file: url.lastPathComponent, summary: result)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "mediapipe-real-video"; attachment.lifetime = .keepAlways; add(attachment)
        print("MEDIAPIPE_REAL_VIDEO \(String(decoding: data, as: UTF8.self))")
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("mediapipe-simulator-report.json"))
        XCTAssertEqual(report.frames, 630)
        XCTAssertNotNil(report.firstStandingMs)
        XCTAssertEqual(result.reps.count, 5)
        XCTAssertEqual(result.squatAnalysis?.attempts.count, 5)
        XCTAssertEqual(result.squatAnalysis?.attempts.compactMap(\.countedRepID), [1,2,3,4,5])
        XCTAssertTrue(result.squatAnalysis?.attempts.allSatisfy {
            $0.assessments.first(where: { $0.item == .descentTempo })?.status == .outsideTarget
        } == true, "The actual sample is faster than the explicitly selected two-second descent task; this is not a universal form verdict")
        XCTAssertTrue(result.reps.allSatisfy { $0.engineVersion.hasPrefix("mediapipe-") })
        let points = await trace.values.compactMap(\.pose).first(where: { !$0.landmarks.isEmpty })
        XCTAssertEqual(points?.landmarks.count,33)
        XCTAssertEqual(points?.imageWidth,1080)
        XCTAssertEqual(points?.imageHeight,1920)
        for (name, expected) in [("standing-then-five-squats.mp4",5), ("standing-five-rotated-metadata.mp4",5), ("negative-frontal-moving-5319965.mp4",0), ("negative-cropped-4820063.mp4",0)] {
            let diagnostics = ReplayRunDiagnostics()
            let result = try await VideoReplayAnalyzer.run(url: root.appendingPathComponent(name), engine: .mediaPipe, diagnostics: diagnostics) { _ in }
            let report = await diagnostics.report(engine: "MediaPipe Full", file: name, summary: result)
            print("MEDIAPIPE_EXTRA \(String(decoding: try encoder.encode(report), as: UTF8.self))")
            XCTAssertEqual(result.reps.count, expected, name)
            XCTAssertEqual(report.firstStandingMs != nil, expected > 0, name)
            XCTAssertEqual(result.squatAnalysis?.attempts.count ?? 0, expected, name)
        }
    }

    func testMediaPipeImportComparisonExportAndCancellation() async throws {
        guard ProcessInfo.processInfo.environment["COACH_MEDIAPIPE_VIDEO_TEST"] == "1" else { throw XCTSkip("Opt-in real video model comparison") }
        let root = try XCTUnwrap(Bundle(for: AppIntegrationTests.self).url(forResource: "media", withExtension: nil))
        let replay = SquatReplayModel()
        replay.engineChoice = .mediaPipe
        replay.importFile(root.appendingPathComponent("standing-then-five-squats.mp4")); replay.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(replay.running); XCTAssertNil(replay.summary)
        replay.importFile(root.appendingPathComponent("standing-then-five-squats.mp4"))
        let importDeadline = Date().addingTimeInterval(40)
        while replay.running, Date() < importDeadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(replay.running); XCTAssertNil(replay.error)
        XCTAssertEqual(replay.summary?.reps.count,5)
        let bottomMs = try XCTUnwrap(replay.summary?.squatAnalysis?.attempts.first?.bottomMs)
        replay.player?.play()
        replay.seekEvidence(bottomMs)
        let seekDeadline = Date().addingTimeInterval(3)
        while abs((replay.player?.currentTime().seconds ?? -1) - Double(bottomMs) / 1000) > 0.05, Date() < seekDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(replay.player?.rate,0)
        XCTAssertEqual(replay.player?.currentTime().seconds ?? -1, Double(bottomMs) / 1000, accuracy: 0.05)
        XCTAssertEqual(replay.evidenceTimeMs,bottomMs)
        replay.compareEngines()
        let deadline = Date().addingTimeInterval(60)
        while replay.running, Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(replay.running); XCTAssertNil(replay.error)
        XCTAssertEqual(replay.comparisonReports.first(where: { $0.engine == "MediaPipe Full" })?.count,5)
        let export = try XCTUnwrap(replay.comparisonExportURL)
        let bundle = try JSONDecoder().decode(PoseComparisonExport.self, from: Data(contentsOf: export))
        XCTAssertEqual(bundle.reports.count + bundle.errors.count,2)
        #if targetEnvironment(simulator)
        // A simulator may not support Vision. Its error must be explicit in
        // the export, never presented as a successful zero-count run.
        if bundle.reports.count == 1 { XCTAssertNotNil(bundle.errors["Apple Vision"]) }
        #else
        XCTAssertTrue(bundle.errors.isEmpty)
        XCTAssertEqual(bundle.reports.map(\.count),[5,5])
        #endif
        replay.cancel()
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path), "Export is intentionally retained")
    }

    func testDiagnosticTraceIsRelativeAndStopsCollecting() throws {
        let recorder = PoseDiagnosticRecorder()
        recorder.start()
        recorder.append(SquatTestSequence.frame(timestamp: 100_000))
        recorder.append(SquatTestSequence.frame(timestamp: 100_100))
        let trace = try JSONDecoder().decode(PoseReplayFile.self, from: recorder.finish())
        XCTAssertEqual(trace.frames.map(\.timestampMs), [0,100])
        XCTAssertEqual(trace.frames.first?.imageWidth,720)
        recorder.append(SquatTestSequence.frame(timestamp: 100_200))
        XCTAssertTrue(try JSONDecoder().decode(PoseReplayFile.self, from: recorder.finish()).frames.isEmpty)
    }

    func testMacMediaPipeExportAndSimulatorCoreParity() async throws {
        let bundle = Bundle(for: AppIntegrationTests.self)
        let poseURL = try XCTUnwrap(bundle.url(forResource: "real-mediapipe-poses", withExtension: "json"))
        let expectedURL = try XCTUnwrap(bundle.url(forResource: "mac-shared-core", withExtension: "json"))
        struct MacReport: Decodable { let summary: WorkoutSummary }
        let expected = try JSONDecoder().decode(MacReport.self, from: Data(contentsOf: expectedURL)).summary
        let input = try JSONDecoder().decode(PoseReplayFile.self, from: Data(contentsOf: poseURL))
        XCTAssertEqual(input.metadata?.modelSHA256, "4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad")
        let actual = try await VideoReplayAnalyzer.run(url: poseURL, target: .init(minimumDescentMs: 2000)) { _ in }
        XCTAssertEqual(actual.reps, expected.reps)
        let attempts = try XCTUnwrap(actual.squatAnalysis?.attempts)
        let reference = try XCTUnwrap(expected.squatAnalysis?.attempts)
        XCTAssertEqual(attempts.count, reference.count)
        for (a,b) in zip(attempts,reference) {
            XCTAssertEqual(a.startMs,b.startMs); XCTAssertEqual(a.bottomMs,b.bottomMs); XCTAssertEqual(a.endMs,b.endMs)
            XCTAssertEqual(a.endReason,b.endReason); XCTAssertEqual(a.countedRepID,b.countedRepID)
            XCTAssertEqual(a.maximumHipDrop,b.maximumHipDrop,accuracy: 1e-6)
            XCTAssertEqual(a.minimumProjectedKneeAngle,b.minimumProjectedKneeAngle,accuracy: 1e-6)
            XCTAssertEqual(a.coverage,b.coverage); XCTAssertEqual(a.assessments,b.assessments)
        }
    }

    func testSquatAttemptsTargetsSummarySaveAndReload() async throws {
        let flow = model()
        flow.beginNewTraining(); flow.squatDescentTargetMs = 2000; flow.performPrimary()
        for frame in SquatTestSequence.frames(repetitions: 1) { await flow.receive(frame) }
        XCTAssertEqual(flow.completedTrainingReps, 1)
        XCTAssertEqual(flow.summary.squatAnalysis?.attempts.count, 1)
        let cue = try XCTUnwrap(flow.summary.squatAnalysis?.attempts.first?.recommendation)
        XCTAssertTrue(cue.contains("所选"))
        let small: [Double] = [0, 0, 0, 0.05, 0.08, 0.1, 0.14, 0.14, 0.1, 0.05, 0, 0, 0, 0]
        for (i, depth) in small.enumerated() { await flow.receive(SquatTestSequence.frame(timestamp: 4800 + i * 100, depth: depth)) }
        XCTAssertEqual(flow.completedTrainingReps, 1)
        XCTAssertEqual(flow.summary.squatAnalysis?.attempts.count, 2, "Uncounted attempts must also update the published summary and draft")
        flow.goBack(); await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-EXIT-MENU")
        flow.performPrimary()
        flow.finishGroup()
        XCTAssertEqual(flow.currentID, "P0-SUMMARY-CLEAN")
        XCTAssertEqual(flow.summary.squatAnalysis?.attempts.count, 2)
        flow.saveSession()
        XCTAssertEqual(flow.currentID, "P0-SAVE-SUCCESS")
        let reopened = model()
        let record = try XCTUnwrap(reopened.records.first)
        let saved = try XCTUnwrap(record.decodedSummary())
        XCTAssertEqual(saved.reps.count, 1)
        XCTAssertEqual(saved.squatAnalysis?.attempts.count, 2)
        XCTAssertEqual(saved.squatAnalysis?.attempts.first?.target.minimumDescentMs, 2000)
        reopened.openRecord(record); reopened.openGroup(0)
        XCTAssertEqual(reopened.summary.squatAnalysis, saved.squatAnalysis)
        reopened.performSecondary()
        XCTAssertEqual(reopened.currentID, "P0-HISTORY-SESSION-DETAIL")
        reopened.goBack()
        XCTAssertEqual(reopened.currentID, "P0-HISTORY-SESSIONS", "Returning from the session must not cycle back into its last group")
        reopened.summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
        reopened.navigate(to: "P0-HISTORY-GROUP-DETAIL")
        XCTAssertNil(reopened.primaryTitle, "A group with no counted cycles must not offer an empty cycle detail page")
    }

    func testSquatDraftRestoresTargetAndAttemptEvidence() async throws {
        let flow = model()
        flow.beginNewTraining(); flow.squatDescentTargetMs = 3000; flow.performPrimary()
        for frame in SquatTestSequence.frames(repetitions: 1) { await flow.receive(frame) }
        flow.interrupt(to: "P0-HOME")
        let reopened = model()
        reopened.resumeDraft()
        XCTAssertEqual(reopened.squatDescentTargetMs, 3000)
        XCTAssertEqual(reopened.summary.squatAnalysis?.attempts.count, 1)
        XCTAssertEqual(reopened.completedTrainingReps, 1)
    }

    func testReplayFinalizesTruncatedAttemptWithoutGivingTechniqueAdvice() async throws {
        let url = directory.appendingPathComponent("truncated.json")
        let frames = SquatTestSequence.frames(repetitions: 1).filter { $0.timestampMs <= 3800 }
        try JSONEncoder().encode(PoseReplayFile(version: 1, frames: frames)).write(to: url)
        let summary = try await VideoReplayAnalyzer.run(url: url, target: .init(minimumDescentMs: 2000)) { _ in }
        XCTAssertEqual(summary.reps.count, 0)
        let attempt = try XCTUnwrap(summary.squatAnalysis?.attempts.first)
        XCTAssertEqual(attempt.endReason, .videoEnded)
        XCTAssertTrue(attempt.assessments.allSatisfy { $0.status == .notAssessable })
        XCTAssertNil(attempt.recommendation)
    }

    func testChangingPoseEngineResetsStandingWithoutStartingCamera() async throws {
        let saved = UserDefaults.standard.object(forKey: "coach.poseEngine")
        defer { UserDefaults.standard.set(saved, forKey: "coach.poseEngine") }
        let flow = model()
        flow.beginNewTraining(); flow.performPrimary()
        for time in stride(from: 0, through: 1_000, by: 100) { await flow.receive(SquatTestSequence.frame(timestamp: time)) }
        XCTAssertGreaterThan(flow.standingProgress,0)
        flow.selectPoseEngine(.appleVision)
        XCTAssertEqual(flow.standingProgress,0)
        XCTAssertNil(flow.latestPose)
        XCTAssertFalse(flow.hasCalibration)
    }

    func testNewTrainingDoesNotHijackOrOverwriteDraft() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "左腿", goal: "偏臀", calibration: FixtureFactory.calibration)
        flow.checkpoint()
        let original = try XCTUnwrap(flow.draft?.id)
        flow.selectTab("P0-HOME")
        flow.performPrimary()
        XCTAssertTrue(flow.showsNewTrainingChoice)
        XCTAssertEqual(flow.currentID, "P0-HOME")
        XCTAssertEqual(flow.draft?.id, original)
        flow.savePreviousAndBeginNew()
        await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-SESSION-SETUP")
        XCTAssertNil(flow.draft)
        XCTAssertEqual(flow.records.first?.id, original)
        XCTAssertEqual(flow.records.count, 1)
        flow.goBack()
        XCTAssertEqual(flow.currentID, "P0-HOME")
    }

    func testPrivacyAndHelpReturnToTheirSourceWithoutPausing() {
        let flow = model()
        flow.navigate(to: "P0-SAFETY")
        flow.performSecondary()
        XCTAssertEqual(flow.currentID, "P0-PRIVACY-LOCAL")
        flow.performPrimary()
        XCTAssertEqual(flow.currentID, "P0-SAFETY")
        flow.navigate(to: "P0-CAMERA-GUIDE")
        flow.performSecondary()
        XCTAssertEqual(flow.help, .camera)
        XCTAssertEqual(flow.currentID, "P0-CAMERA-GUIDE")
        flow.help = nil
        flow.navigate(to: "P0-CALIBRATION-READY")
        flow.performSecondary()
        XCTAssertEqual(flow.help, .calibration)
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-READY")
        flow.navigate(to: "P0-SESSION-SETUP")
        flow.performSecondary()
        XCTAssertEqual(flow.currentID, "P0-EXERCISE-LIBRARY")
    }

    func testTrainingEntryRoutesByAuthorizationAndDoesNotCreateEmptyDraftOnBack() {
        for (authorization, expected): (AVAuthorizationStatus, String) in [(.authorized, "P0-CALIBRATION-READY"), (.notDetermined, "P0-PERMISSION-REQUEST"), (.denied, "P0-PERMISSION-DENIED")] {
            let flow = P0FlowModel(storageURL: directory.appendingPathComponent(UUID().uuidString), cameraEnabled: false, authorizationStatus: { authorization })
            flow.attach(ModelContext(container))
            flow.selectTab("P0-HOME")
            flow.performPrimary()
            XCTAssertEqual(flow.currentID, "P0-SESSION-SETUP")
            XCTAssertNil(flow.draft)
            flow.goBack()
            XCTAssertEqual(flow.currentID, "P0-HOME")
            flow.performPrimary()
            flow.performPrimary()
            XCTAssertEqual(flow.currentID, expected)
            XCTAssertNotNil(flow.draft)
        }
    }

    func testPauseResumeAndReturnHomePreserveCompletedReps() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查", calibration: FixtureFactory.calibration)
        flow.resumeDraft(); await settle(flow)
        flow.startGroup(); await settle(flow)
        for pose in FixtureFactory.validRep() { await flow.receive(pose) }
        flow.performSecondary(); await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-EXIT-MENU")
        XCTAssertTrue(flow.needsCamera)
        XCTAssertEqual(flow.completedTrainingReps, 1)
        flow.performPrimary()
        XCTAssertEqual(flow.currentID, "P0-TRAINING-ACTIVE")
        flow.goBack(); await settle(flow)
        flow.leaveWithDraft(); await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-HOME")
        XCTAssertTrue(flow.routeHistory.isEmpty)
        let reopened = model()
        reopened.resumeDraft(); await settle(reopened)
        XCTAssertEqual(reopened.currentID, "P0-INTERRUPT-FOREGROUND")
        reopened.performPrimary()
        XCTAssertEqual(reopened.currentID, "P0-TRAINING-ACTIVE")
        XCTAssertEqual(reopened.completedTrainingReps, 1)
        reopened.goBack(); await settle(reopened)
        reopened.performSecondary(); await settle(reopened)
        XCTAssertEqual(reopened.groups.count, 1)
        XCTAssertTrue(["P0-SUMMARY-CLEAN", "P0-SUMMARY-ISSUES"].contains(reopened.currentID))
    }

    func testBackFromDiscardConfirmationNeverDiscardsGroup() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查", calibration: FixtureFactory.calibration)
        flow.resumeDraft(); await settle(flow)
        flow.startGroup(); await settle(flow)
        for pose in FixtureFactory.validRep() { await flow.receive(pose) }
        flow.goBack(); await settle(flow)
        flow.navigate(to: "P0-ABANDON-CONFIRM")
        flow.goBack()
        XCTAssertEqual(flow.currentID, "P0-EXIT-MENU")
        XCTAssertEqual(flow.draft?.active.reps.count, 1)
        XCTAssertTrue(flow.hasActiveGroup)
        flow.navigate(to: "P0-ABANDON-CONFIRM")
        flow.performPrimary(); await settle(flow)
        XCTAssertEqual(flow.draft?.active.reps.count, 0)
        XCTAssertFalse(flow.hasActiveGroup)
    }

    func testNewTrainingArchivesActiveRepsAndRecalibrationKeepsEarlierGroup() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查", calibration: FixtureFactory.calibration)
        let original = try XCTUnwrap(flow.draft?.id)
        flow.resumeDraft(); await settle(flow)
        flow.startGroup(); await settle(flow)
        for pose in FixtureFactory.validRep() { await flow.receive(pose) }
        flow.recalibratePreservingCompletedReps(); await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-READY")
        XCTAssertNil(flow.draft?.calibration)
        XCTAssertEqual(flow.draft?.groups.first?.reps.count, 1)
        flow.leaveWithDraft(); await settle(flow)
        flow.beginNewTraining()
        flow.savePreviousAndBeginNew(); await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-SESSION-SETUP")
        XCTAssertEqual(flow.records.first?.id, original)
        XCTAssertEqual(flow.records.first?.repCount, 1)
        XCTAssertNil(flow.draft)
    }

    func testNewTrainingFromColdDraftPreservesActiveRepsWithoutOpeningCamera() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查", calibration: FixtureFactory.calibration)
        let original = try XCTUnwrap(flow.draft?.id)
        flow.resumeDraft(); await settle(flow)
        flow.startGroup(); await settle(flow)
        for pose in FixtureFactory.validRep() { await flow.receive(pose) }
        flow.leaveWithDraft(); await settle(flow)
        let reopened = model()
        XCTAssertFalse(reopened.hasActiveGroup)
        XCTAssertEqual(reopened.draft?.active.reps.count, 1)
        reopened.beginNewTraining()
        reopened.savePreviousAndBeginNew()
        XCTAssertEqual(reopened.currentID, "P0-SESSION-SETUP")
        XCTAssertEqual(reopened.records.first?.id, original)
        XCTAssertEqual(reopened.records.first?.repCount, 1)
        XCTAssertEqual(reopened.records.first?.decodedSummary()?.reps.count, 1)
        XCTAssertNil(reopened.draft)
    }

    func testReturningFromPauseKeepsUncertainStatusUntilValidInputResumes() async throws {
        let flow = model()
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查", calibration: FixtureFactory.calibration)
        flow.resumeDraft(); await settle(flow)
        flow.startGroup(); await settle(flow)
        await flow.receive(FixtureFactory.pose(timestamp: 0, hipY: 0.7, kneeAngle: 165, quality: 0.2))
        XCTAssertEqual(flow.currentID, "P0-TRAINING-UNCERTAIN")
        flow.goBack(); await settle(flow)
        flow.performPrimary()
        XCTAssertEqual(flow.currentID, "P0-TRAINING-UNCERTAIN")
        for pose in FixtureFactory.validRep(start: 3000) { await flow.receive(pose) }
        XCTAssertEqual(flow.currentID, "P0-TRAINING-ACTIVE")
    }

    func testReplaySheetPresentsAndDismissesWithFlowEnvironment() async throws {
        let flow = model()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: P0FlowRootView(flow: flow).modelContainer(container))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(150))
        flow.showsReplay = true
        try await Task.sleep(for: .milliseconds(600))
        // Accessing the replay view's body/onAppear must resolve its flow.
        // A missing sheet environment used to crash at this exact entry point.
        XCTAssertNotNil(host.presentedViewController)
        XCTAssertNotNil(host.presentedViewController?.viewIfLoaded)
        flow.showsReplay = false
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertNil(host.presentedViewController)
    }

    func testCalibrationAndTrainingKeepTheSamePreview() async throws {
        let flow = model()
        flow.navigate(to: "P0-EXERCISE-LIBRARY")
        flow.performPrimary()
        flow.navigate(to: "P0-CALIBRATION-READY")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            P0FlowRootView(flow: flow).modelContainer(container).transaction { $0.disablesAnimations = true })
        window.makeKeyAndVisible()
        defer {
            flow.camera.stop()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(100))
        let firstPreview = try XCTUnwrap(preview(in: window))
        flow.performPrimary()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(preview(in: window) === firstPreview, "Starting calibration replaced the live preview")
        for time in stride(from: 0, through: 2_400, by: 100) { await flow.receive(SquatTestSequence.frame(timestamp: time)) }
        XCTAssertEqual(flow.currentID, "P0-TRAINING-ACTIVE")
        XCTAssertTrue(flow.needsCamera, "Calibration success must not stop the preview before training")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(preview(in: window) === firstPreview, "Calibration success replaced the live preview")
        await settle(flow)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(flow.currentID, "P0-TRAINING-ACTIVE")
        XCTAssertTrue(preview(in: window) === firstPreview, "Starting training replaced the live preview")
        flow.goBack()
        await settle(flow)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(preview(in: window) === firstPreview, "Pausing replaced the live preview")
        flow.performPrimary()
        await settle(flow)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(preview(in: window) === firstPreview, "Resuming replaced the live preview")
    }

    func testCalibrationInterruptionKeepsControlsAvailable() {
        let flow = model()
        flow.navigate(to: "P0-CALIBRATION-RUNNING")
        flow.sceneChanged(.inactive)
        XCTAssertFalse(flow.busy)
        XCTAssertEqual(flow.currentID, "P0-INTERRUPT-BACKGROUND")
        flow.sceneChanged(.active)
        flow.performPrimary()
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-READY")
        flow.performPrimary()
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-READY")
        flow.goBack()
        XCTAssertFalse(flow.busy)
        XCTAssertEqual(flow.currentID, "P0-EXIT-MENU")
    }

    func testRealCameraPreviewStartsAndDeliversFrames() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an unlocked physical iPhone with camera permission")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw XCTSkip("Grant camera permission in the app before running this test")
        }
        let camera = CameraService()
        let controller = UIHostingController(rootView: CameraPreview(camera: camera))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        camera.start()
        window.makeKeyAndVisible()
        defer {
            camera.stop()
            camera.observationHandler = nil
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        await waitForAnalyzedFrames(camera)
        XCTAssertEqual(camera.status, .running)
        #endif
    }

    func testRealCameraFlowCanExitAfterReceivingFrames() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an unlocked physical iPhone with camera permission")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw XCTSkip("Grant camera permission in the app before running this test")
        }
        let flow = P0FlowModel(storageURL: draftURL)
        flow.attach(ModelContext(container))
        flow.camera.observationHandler = { [weak flow] observation in
            await flow?.receive(observation)
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: P0FlowRootView(flow: flow).modelContainer(container))
        window.makeKeyAndVisible()
        defer {
            flow.camera.stop()
            flow.camera.observationHandler = nil
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        flow.navigate(to: "P0-CALIBRATION-READY")
        await waitForAnalyzedFrames(flow.camera)
        XCTAssertEqual(flow.currentID, "P0-CALIBRATION-READY")
        flow.goBack()
        await settle(flow)
        XCTAssertEqual(flow.currentID, "P0-EXIT-MENU")
        #endif
    }

    func testRealCameraResumeKeepsMainRunLoopResponsive() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an unlocked physical iPhone with camera permission")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw XCTSkip("Grant camera permission in the app before running this test")
        }
        let flow = P0FlowModel(storageURL: draftURL)
        flow.attach(ModelContext(container))
        flow.draft = LocalTrainingDraft(side: "双腿", goal: "完整周期计次", exerciseID: ExerciseKind.bodyweightSquat.rawValue)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: P0FlowRootView(flow: flow).modelContainer(container))
        window.makeKeyAndVisible()
        var lastTick = ProcessInfo.processInfo.systemUptime
        var longestGap: TimeInterval = 0
        let heartbeat = DispatchSource.makeTimerSource(queue: .main)
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(20))
        heartbeat.setEventHandler {
            let now = ProcessInfo.processInfo.systemUptime
            longestGap = max(longestGap, now - lastTick)
            lastTick = now
        }
        heartbeat.resume()
        defer {
            heartbeat.cancel()
            flow.camera.stop()
            flow.camera.observationHandler = nil
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        flow.resumeDraft()
        await settle(flow)
        for _ in 0..<2 {
            let baseline = flow.camera.processedFrameCount
            await waitForAnalyzedFrames(flow.camera, after: baseline)
            flow.goBack()
            await settle(flow)
            flow.performPrimary()
            await settle(flow)
        }
        try await Task.sleep(for: .milliseconds(250))
        let metric = XCTAttachment(string: "Maximum main-loop gap during camera resume: \(longestGap) seconds")
        metric.lifetime = .keepAlways
        add(metric)
        print("Camera resume maximum main-loop gap: \(longestGap) seconds")
        XCTAssertLessThan(longestGap, 0.5, "Camera transitions blocked the main run loop for \(longestGap) seconds")
        #endif
    }

    func testRealTrainingEntryKeepsPreviewAndMainRunLoopResponsive() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an unlocked physical iPhone with camera permission")
        #else
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw XCTSkip("Grant camera permission in the app before running this test")
        }
        let flow = P0FlowModel(storageURL: draftURL)
        flow.attach(ModelContext(container))
        flow.navigate(to: "P0-HOME")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: P0FlowRootView(flow: flow).modelContainer(container))
        window.makeKeyAndVisible()
        var lastTick = ProcessInfo.processInfo.systemUptime
        var longestGap: TimeInterval = 0
        let heartbeat = DispatchSource.makeTimerSource(queue: .main)
        heartbeat.schedule(deadline: .now(), repeating: .milliseconds(20))
        heartbeat.setEventHandler {
            let now = ProcessInfo.processInfo.systemUptime
            longestGap = max(longestGap, now - lastTick)
            lastTick = now
        }
        heartbeat.resume()
        defer {
            heartbeat.cancel()
            flow.camera.stop()
            flow.camera.observationHandler = nil
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
        flow.camera.observationHandler = { [weak flow] observation in
            await flow?.receive(observation)
        }
        for expected in ["P0-SESSION-SETUP", "P0-CALIBRATION-READY"] {
            flow.performPrimary()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(flow.currentID, expected)
        }
        await waitForAnalyzedFrames(flow.camera)
        let firstPreview = try XCTUnwrap(preview(in: window))
        let firstLayer = try XCTUnwrap(firstPreview.previewLayer)
        // Standing and squat motion are synthetic; preview and subsequent
        // training inference use the physical camera throughout this test.
        flow.camera.observationHandler = nil
        for time in stride(from: 0, through: 2_400, by: 100) { await flow.receive(SquatTestSequence.frame(timestamp: time)) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(flow.currentID, "P0-TRAINING-ACTIVE")
        XCTAssertEqual(flow.camera.status, .running)
        XCTAssertTrue(preview(in: window) === firstPreview)
        XCTAssertTrue(firstPreview.previewLayer === firstLayer)
        for pose in SquatTestSequence.frames(repetitions: 3) { await flow.receive(pose) }
        XCTAssertEqual(flow.completedTrainingReps, 3)
        let trainingBaseline = flow.camera.processedFrameCount
        flow.camera.observationHandler = { [weak flow] observation in
            await flow?.receive(observation)
        }
        await waitForAnalyzedFrames(flow.camera, after: trainingBaseline)
        XCTAssertTrue(flow.activeTraining)
        XCTAssertTrue(preview(in: window) === firstPreview)
        XCTAssertTrue(firstPreview.previewLayer === firstLayer)
        flow.goBack()
        await settle(flow)
        try await Task.sleep(for: .milliseconds(100))
        print("Training entry maximum main-loop gap: \(longestGap) seconds")
        XCTAssertLessThan(longestGap, 0.5, "Training entry blocked the main run loop for \(longestGap) seconds")
        #endif
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
        // A legacy BSS draft must retain its three-repetition calibration path.
        flow.draft = LocalTrainingDraft(side: "右腿", goal: "一般检查")
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

private final class EmptyVideoPoseProbe: LivePosePerception, @unchecked Sendable {
    let engineVersion = "decode-probe-no-inference"
    var frames = 0
    func process(_ buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, timestampMs: Int) async throws -> PoseObservation? {
        frames += 1
        return PoseObservation(timestampMs: timestampMs, landmarks: [:], engineVersion: engineVersion)
    }
}

private actor RealVideoReplayTrace {
    var values: [ReplaySnapshot] = []
    func append(_ value: ReplaySnapshot) { values.append(value) }
}

private final class RecordingVideoPerception: LivePosePerception, @unchecked Sendable {
    private let base = AppleVisionPosePerception()
    var engineVersion: String { base.engineVersion }
    private(set) var frames: [PoseObservation] = []
    func process(_ buffer: CMSampleBuffer, orientation: CGImagePropertyOrientation, timestampMs: Int) async throws -> PoseObservation? {
        let value = try await base.process(buffer, orientation: orientation, timestampMs: timestampMs)
        if let value { frames.append(value) }
        return value
    }
}
