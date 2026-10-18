import Foundation
import SwiftUI
import UIKit
import AVFoundation
import SwiftData
import FormCoachCore

struct V3Manifest: Decodable {
    let screens: [V3ScreenSpec]
}

struct V3ScreenCopy: Decodable, Hashable {
    let title: String
    let detail: String
}

struct V3ScreenSpec: Decodable, Hashable, Identifiable {
    let order: Int
    let stateId: String
    let name: String
    let tier: String
    let group: String
    let entryCondition: String
    let userSees: V3ScreenCopy
    let primaryAction: String?
    let secondaryAction: String?
    let nextState: String?
    let secondaryTarget: String?
    let exceptionRecovery: String
    let requiresNetwork: Bool
    let uploadedData: String
    let accessibility: String
    let layoutKind: String
    let tone: String

    var id: String { stateId }
    var isDark: Bool { tone == "dark" || layoutKind == "camera" || layoutKind == "quality" }
}

enum V3ManifestStore {
    static let p0Screens: [V3ScreenSpec] = {
        guard let url = Bundle.main.url(forResource: "DESIGN-MANIFEST-v3", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(V3Manifest.self, from: data) else {
            assertionFailure("DESIGN-MANIFEST-v3.json is missing from the application bundle")
            return []
        }
        return manifest.screens.filter { $0.tier == "P0" }.sorted { $0.order < $1.order }
    }()
}

struct LocalTrainingDraft: Codable {
    var id = UUID()
    var startedAt = Date()
    var side: String
    var goal: String
    var exerciseID: String? = nil
    var minimumDescentMs: Int? = nil
    var calibration: CalibrationProfile?
    var groups: [WorkoutSummary] = []
    var active = WorkoutSummary(reps: [], suppressedIssueCount: 0)
    var groupInProgress = false
}

enum TrainingHelp: String, Identifiable {
    case camera, calibration
    var id: String { rawValue }
}

@MainActor
final class P0FlowModel: ObservableObject {
    @Published private(set) var currentID = "P0-LAUNCH"
    @Published private(set) var routeHistory: [String] = []
    @Published var showsStateCatalog = false
    @Published var trainingSide = "右腿"
    @Published var trainingGoal = "一般检查"
    @Published var speechEnabled = UserDefaults.standard.object(forKey: "coach.speech") as? Bool ?? true {
        didSet { UserDefaults.standard.set(speechEnabled, forKey: "coach.speech"); if !speechEnabled { speech.stop() } }
    }
    @Published var completedCalibrationReps = 0
    @Published var completedTrainingReps = 0
    @Published var records: [StoredWorkoutSession] = []
    @Published var saveFailureMessage: String?
    @Published var latestCue: String?
    @Published var trackingMessage = "等待全身入镜"
    @Published var summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
    @Published var selectedRep: RepSummary?
    @Published var selectedRecord: StoredWorkoutSession?
    @Published var draft: LocalTrainingDraft?
    @Published var busy = false
    @Published var help: TrainingHelp?
    @Published var showsNewTrainingChoice = false
    @Published var showsReplay = false
    @Published var standingProgress = 0.0
    @Published var latestPose: PoseObservation?
    @Published var poseFailure: PoseFailureReason = .none
    @Published var showsSkeleton = true
    @Published var showsPoseDiagnostics = false
    @Published var squatDescentTargetMs = 0 {
        didSet {
            squatSession.target = SquatTrainingTarget(minimumDescentMs: squatDescentTargetMs > 0 ? squatDescentTargetMs : nil)
            draft?.minimumDescentMs = squatDescentTargetMs > 0 ? squatDescentTargetMs : nil
        }
    }
    private var lastSkeletonTimestamp = -1
    private var squatSession = SquatSession()
    var isSquat: Bool {
        if let selectedRecord { return selectedRecord.exerciseID == ExerciseKind.bodyweightSquat.rawValue }
        if let draft { return draft.exerciseID == ExerciseKind.bodyweightSquat.rawValue }
        return true
    }
    var exerciseTitle: String { isSquat ? "徒手深蹲" : "保加利亚分腿蹲" }
    var sessionDescription: String { isSquat ? "徒手深蹲 · 侧面计次" : "保加利亚分腿蹲 · \(trainingSide) · \(trainingGoal)" }
    func selectPoseEngine(_ choice: PoseEngineChoice) {
        guard !groupInProgress, !camera.isRecordingDiagnostic else { return }
        squatSession.reset(); standingProgress = 0; readyFrames = 0
        latestPose = nil; lastSkeletonTimestamp = -1; poseFailure = .none
        camera.selectEngine(choice)
        if needsCamera { navigate(to: "P0-CALIBRATION-READY") }
    }
    let camera = CameraService()
    private let engine = WorkoutSessionEngine()
    private let speech = SpeechService()
    private var collector = GuidedCalibrationCollector()
    private var context: ModelContext?
    private var calibration: CalibrationProfile?
    private var groupInProgress = false
    private var analysisWasUncertain = false
    private var operation: Task<Void, Never>?
    private var generation = 0
    private var mounted = false
    private var lastFrame = Date()
    private var cameraStarted = Date()
    private var readyFrames = 0
    private var lastCheckpoint = Date.distantPast
    private var deletionIsDraft = false
    private let storageURL: URL?
    private let cameraEnabled: Bool
    private let authorizationStatus: () -> AVAuthorizationStatus
    let screens: [V3ScreenSpec]
    private let byID: [String: V3ScreenSpec]
    var savedSessionCount: Int { records.count }
    var current: V3ScreenSpec? { byID[currentID] }
    var activeTraining: Bool { ["P0-TRAINING-ACTIVE", "P0-TRAINING-COACHING", "P0-TRAINING-UNCERTAIN"].contains(currentID) }
    var isCameraPaused: Bool { ["P0-EXIT-MENU", "P0-END-SET-CONFIRM", "P0-ABANDON-CONFIRM"].contains(currentID) }
    var needsCamera: Bool { activeTraining || isCameraPaused || ["P0-CALIBRATION-READY", "P0-CALIBRATION-RUNNING", "P0-CALIBRATION-SUCCESS", "P0-INTERRUPT-FOREGROUND"].contains(currentID) }
    var hasActiveGroup: Bool { groupInProgress }
    var hasCalibration: Bool { isSquat ? squatSession.baseline != nil : calibration != nil }
    var nextGroupNumber: Int { (draft?.groups.count ?? 0) + 1 }
    var deletingDraft: Bool { deletionIsDraft }
    var primaryTitle: String? {
        switch currentID {
        case "P0-HOME", "P0-HISTORY-EMPTY": "开始新训练"
        case "P0-SESSION-SETUP": "打开相机"
        case "P0-CALIBRATION-SUCCESS": "开始第 \(nextGroupNumber) 组"
        case "P0-INTERRUPT-FOREGROUND": canPerformPrimary ? (groupInProgress ? "继续本组" : (calibration == nil ? "前往校准" : "开始下一组")) : "等待画面稳定…"
        case "P0-EXIT-MENU": groupInProgress ? "继续本组" : "返回校准"
        case "P0-ABANDON-CONFIRM": "放弃本组"
        case "P0-PRIVACY-LOCAL": "返回上一页"
        case "P0-SETTINGS": "完成"
        case "P0-DELETE-CONFIRM": deletionIsDraft ? "删除草稿" : "删除训练记录"
        case "P0-HISTORY-GROUP-DETAIL": summary.reps.isEmpty ? nil : current?.primaryAction
        default: current?.primaryAction
        }
    }
    var secondaryTitle: String? {
        switch currentID {
        case "P0-HOME", "P0-SESSION-SETUP", "P0-HISTORY-EMPTY", "P0-HISTORY-SESSIONS", "P0-HISTORY-SESSION-DETAIL", "P0-PRIVACY-LOCAL": nil
        case "P0-CALIBRATION-READY": "校准与机位说明"
        case "P0-ABANDON-CONFIRM": "返回暂停菜单"
        case "P0-INTERRUPT-FOREGROUND": "机位说明"
        case "P0-PERMISSION-REQUEST": "返回训练设置"
        default: current?.secondaryAction
        }
    }
    var canPerformPrimary: Bool {
        !busy && !(currentID == "P0-CALIBRATION-RUNNING") &&
        !(currentID == "P0-INTERRUPT-FOREGROUND" && cameraEnabled && readyFrames < 5)
    }
    var groups: [WorkoutSummary] {
        if let selectedRecord, let data = selectedRecord.groupsJSON,
           let groups = try? JSONDecoder().decode([WorkoutSummary].self, from: data) { return groups }
        if let selectedRecord, let value = selectedRecord.decodedSummary() { return [value] }
        return draft?.groups ?? []
    }
    var issues: [IssueEvent] { summary.reps.flatMap(\.issues).filter { $0.disposition != .suppressed } }
    var settingsLocked: Bool { groupInProgress || !(draft?.groups.isEmpty ?? true) }
    var config: SessionConfig {
        SessionConfig(exercise: isSquat ? .bodyweightSquat : .bulgarianSplitSquat, trainingSide: trainingSide == "左腿" ? .left : .right,
                      variant: trainingGoal == "偏臀" ? .gluteBias : trainingGoal == "偏股四头肌" ? .quadBias : .general,
                      speechEnabled: true, saveVideo: false)
    }
    private var draftURL: URL {
        if let storageURL { return storageURL }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("training-draft.json")
    }

    init(screens: [V3ScreenSpec] = V3ManifestStore.p0Screens, storageURL: URL? = nil, cameraEnabled: Bool = true,
         authorizationStatus: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .video) }) {
        self.screens = screens
        self.storageURL = storageURL
        self.cameraEnabled = cameraEnabled
        self.authorizationStatus = authorizationStatus
        byID = Dictionary(uniqueKeysWithValues: screens.map { ($0.stateId, $0) })
    }

    func attach(_ context: ModelContext) {
        guard !mounted else { return }
        mounted = true
        self.context = context
        refreshRecords()
        if FileManager.default.fileExists(atPath: draftURL.path) {
            do {
                let restored = try JSONDecoder().decode(LocalTrainingDraft.self, from: Data(contentsOf: draftURL))
                // A committed session wins if the app stopped before clearing its draft.
                if !records.contains(where: { $0.id == restored.id }) { draft = restored }
            }
            catch { saveFailureMessage = "未能读取上次草稿，请保留本机数据后重试。" }
        }
        camera.observationHandler = { [weak self] observation in await self?.receive(observation) }
        if currentID == "P0-LAUNCH" { performPrimary() }
    }

    func selectTab(_ target: String) {
        routeHistory = []
        if target == "P0-HOME" { selectedRecord = nil }
        navigate(to: target, recordingHistory: false)
    }

    func beginNewTraining() {
        guard !busy else { return }
        if draft != nil { showsNewTrainingChoice = true }
        else { prepareFreshTraining() }
    }

    private func prepareFreshTraining() {
        selectedRecord = nil; selectedRep = nil; draft = nil; calibration = nil
        groupInProgress = false; analysisWasUncertain = false; completedCalibrationReps = 0; completedTrainingReps = 0
        summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
        squatSession.reset(); standingProgress = 0
        squatDescentTargetMs = 0
        trainingSide = "双腿"; trainingGoal = "完整周期计次"
        collector.reset(); routeHistory = ["P0-HOME"]
        navigate(to: "P0-SESSION-SETUP", recordingHistory: false)
    }

    func savePreviousAndBeginNew() {
        guard !busy, let draft else { return }
        showsNewTrainingChoice = false
        trainingSide = draft.side; trainingGoal = draft.goal
        generation += 1
        saveSession(archivingActiveGroup: true)
        if currentID == "P0-SAVE-SUCCESS" { prepareFreshTraining() }
    }

    private func openCamera() {
        switch authorizationStatus() {
        case .authorized: navigate(to: groupInProgress || calibration != nil ? "P0-INTERRUPT-FOREGROUND" : "P0-CALIBRATION-READY")
        case .notDetermined: navigate(to: "P0-PERMISSION-REQUEST")
        default: navigate(to: "P0-PERMISSION-DENIED")
        }
    }

    func refreshRecords() {
        guard let context else { return }
        do { records = try context.fetch(FetchDescriptor<StoredWorkoutSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])) }
        catch { saveFailureMessage = "读取训练记录失败：\(error.localizedDescription)" }
    }

    func navigate(to id: String, recordingHistory: Bool = true) {
        guard byID[id] != nil else { return }
        let wasCamera = needsCamera
        if recordingHistory, currentID != id { routeHistory.append(currentID) }
        currentID = id
        if cameraEnabled { UIApplication.shared.isIdleTimerDisabled = needsCamera }
        if wasCamera && !needsCamera { camera.stop(); speech.stop() }
        if !wasCamera && needsCamera {
            readyFrames = 0; cameraStarted = .now; lastFrame = .now
            if cameraEnabled { camera.start() }
        }
    }

    func performPrimary() {
        guard !busy else { return }
        switch currentID {
        case "P0-LAUNCH":
            navigate(to: UserDefaults.standard.bool(forKey: "coach.safety") ? "P0-HOME" : "P0-SAFETY")
        case "P0-SAFETY":
            UserDefaults.standard.set(true, forKey: "coach.safety"); selectTab("P0-HOME")
        case "P0-HOME":
            beginNewTraining()
        case "P0-EXERCISE-LIBRARY":
            selectedRecord = nil
            if draft == nil { draft = LocalTrainingDraft(side: trainingSide, goal: trainingGoal, exerciseID: ExerciseKind.bodyweightSquat.rawValue) }
            navigate(to: "P0-SESSION-SETUP")
        case "P0-SESSION-SETUP":
            if draft == nil { draft = LocalTrainingDraft(side: trainingSide, goal: trainingGoal, exerciseID: ExerciseKind.bodyweightSquat.rawValue) }
            if draft?.side != trainingSide || draft?.goal != trainingGoal { calibration = nil; draft?.calibration = nil }
            draft?.side = trainingSide; draft?.goal = trainingGoal
            draft?.minimumDescentMs = squatDescentTargetMs > 0 ? squatDescentTargetMs : nil
            checkpoint(); openCamera()
        case "P0-CAMERA-GUIDE": openCamera()
        case "P0-PERMISSION-RETURN-GRANTED": openCamera()
        case "P0-PERMISSION-REQUEST":
            Task { let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { openCamera() } else { navigate(to: "P0-PERMISSION-DENIED") } }
        case "P0-PERMISSION-DENIED", "P0-PERMISSION-RETURN-DENIED":
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case "P0-CALIBRATION-READY", "P0-CALIBRATION-INCONSISTENT":
            if isSquat { squatSession.reset(); standingProgress = 0; navigate(to: "P0-CALIBRATION-READY"); return }
            collector.reset(); completedCalibrationReps = 0; calibration = nil
            navigate(to: "P0-CALIBRATION-RUNNING")
        case "P0-CALIBRATION-RUNNING": break // Only observed complete movements advance calibration.
        case "P0-CALIBRATION-SUCCESS", "P0-NEXT-SET-READY":
            if draft?.side != trainingSide || draft?.goal != trainingGoal {
                calibration = nil; draft?.calibration = nil
                draft?.side = trainingSide; draft?.goal = trainingGoal
            }
            startGroup()
        case "P0-TRAINING-ACTIVE":
            interrupt(to: "P0-END-SET-CONFIRM")
        case "P0-TRAINING-UNCERTAIN":
            break // Resume is driven only by fresh valid observations.
        case "P0-CAMERA-IN-USE", "P0-INFERENCE-FAILED":
            navigate(to: groupInProgress ? "P0-INTERRUPT-FOREGROUND" : "P0-CALIBRATION-READY")
        case "P0-END-SET-CONFIRM": finishGroup()
        case "P0-ABANDON-KEEP-REPS": navigate(to: "P0-SESSION-GROUPS")
        case "P0-ABANDON-CONFIRM": discardCurrentGroup()
        case "P0-EXIT-MENU", "P0-INTERRUPT-FOREGROUND":
            if currentID == "P0-INTERRUPT-FOREGROUND", readyFrames < 5, cameraEnabled { return }
            if groupInProgress { resumeCurrentGroup() }
            else if !hasCalibration { navigate(to: "P0-CALIBRATION-READY") }
            else { startGroup() }
        case "P0-DRAFT-RESUME": resumeDraft()
        case "P0-SAVE-PROGRESS", "P0-SAVE-FAILED", "P0-STORAGE-FULL": saveSession()
        case "P0-SESSION-COMPLETE": openSelectedRecord()
        case "P0-DELETE-CONFIRM": deleteSelected()
        case "P0-DELETE-FAILED": navigate(to: "P0-DELETE-CONFIRM")
        case "P0-SAVE-SUCCESS": openSelectedRecord()
        case "P0-HISTORY-SESSIONS":
            if let record = records.first { openRecord(record) }
            else { navigate(to: "P0-HISTORY-EMPTY") }
        case "P0-HISTORY-SESSION-DETAIL": openGroup(0)
        case "P0-REP-DETAIL", "P0-PRIVACY-LOCAL", "P0-SETTINGS": goBack()
        case "P0-SUMMARY-CLEAN", "P0-SUMMARY-ISSUES", "P0-SESSION-GROUPS": startGroup()
        case "P0-HISTORY-GROUP-DETAIL":
            if let rep = summary.reps.first { openRep(rep) }
        case "P0-HISTORY-EMPTY": beginNewTraining()
        case "P0-DELETE-SUCCESS": selectTab(records.isEmpty ? "P0-HISTORY-EMPTY" : "P0-HISTORY-SESSIONS")
        default:
            if let next = current?.nextState { navigate(to: next) } else { navigate(to: "P0-HOME") }
        }
    }

    // Actions are keyed by screen identity. Display copy never determines routing.
    func performSecondary() {
        guard !busy else { return }
        switch currentID {
        case "P0-SAFETY", "P0-MY-LOCAL", "P0-SETTINGS": navigate(to: "P0-PRIVACY-LOCAL")
        case "P0-HOME": resumeDraft()
        case "P0-EXERCISE-LIBRARY", "P0-PERMISSION-REQUEST": goBack()
        case "P0-SESSION-SETUP": navigate(to: "P0-EXERCISE-LIBRARY")
        case "P0-CAMERA-GUIDE": help = .camera
        case "P0-CALIBRATION-READY": help = .calibration
        case "P0-CALIBRATION-RUNNING", "P0-TRAINING-ACTIVE", "A11Y-TRAINING-XXXL": interrupt(to: "P0-EXIT-MENU")
        case "P0-CALIBRATION-SUCCESS":
            squatSession.reset(); standingProgress = 0
            calibration = nil; draft?.calibration = nil; collector.reset(); completedCalibrationReps = 0
            checkpoint(); navigate(to: "P0-CALIBRATION-READY")
        case "P0-CALIBRATION-INCONSISTENT", "P0-INTERRUPT-LOCK", "P0-DEVICE-THERMAL", "P0-DEVICE-LOW-BATTERY", "P0-SAVE-FAILED", "P0-STORAGE-FULL": leaveWithDraft()
        case "P0-TRAINING-UNCERTAIN", "P0-INTERRUPT-BACKGROUND", "P0-INTERRUPT-CALL", "P0-INFERENCE-FAILED": interrupt(to: "P0-END-SET-CONFIRM")
        case "P0-EXIT-MENU": finishGroup()
        case "P0-END-SET-CONFIRM": resumeCurrentGroup()
        case "P0-ABANDON-CONFIRM": navigate(to: "P0-EXIT-MENU")
        case "P0-INTERRUPT-FOREGROUND": help = .camera
        case "P0-SUMMARY-CLEAN", "P0-SUMMARY-ISSUES", "P0-SESSION-GROUPS": saveSession()
        case "P0-NEXT-SET-READY":
            if settingsLocked { saveFailureMessage = "本次训练的腿和目标已固定。要更换设置，请先结束并保存，再开始新训练。" }
            else { navigate(to: "P0-SESSION-SETUP") }
        case "P0-DRAFT-RESUME": requestDeleteDraft()
        case "P0-HISTORY-SESSION-DETAIL": requestDeleteRecord()
        case "P0-DELETE-CONFIRM": goBack()
        case "P0-DELETE-FAILED", "P0-HISTORY-GROUP-DETAIL", "P0-ABANDON-KEEP-REPS": navigate(to: selectedRecord == nil ? "P0-SESSION-GROUPS" : "P0-HISTORY-SESSION-DETAIL")
        case "P0-REP-DETAIL":
            if let selectedRep, let index = summary.reps.firstIndex(where: { $0.id == selectedRep.id }), !summary.reps.isEmpty {
                self.selectedRep = summary.reps[(index + 1) % summary.reps.count]
            }
        case "P0-TRAINING-COACHING": speechEnabled = false; navigate(to: "P0-TRAINING-ACTIVE")
        case "P0-INTERRUPT-AUDIO", "A11Y-VOICE-OFF-TEXT": speechEnabled = true; navigate(to: "P0-TRAINING-ACTIVE")
        case "P0-QUALITY-WRONG-LEG":
            interrupt(to: "P0-EXIT-MENU")
        case let id where id.hasPrefix("P0-QUALITY-"): interrupt(to: "P0-END-SET-CONFIRM")
        case "P0-PRIVACY-LOCAL": break
        default:
            if let target = current?.secondaryTarget { navigate(to: target) }
            else { selectTab("P0-HOME") }
        }
    }

    func leaveWithDraft() {
        guard !busy else { return }
        interrupt(to: "P0-HOME")
        routeHistory = []; selectedRecord = nil
    }

    func resumeCurrentGroup() {
        navigate(to: analysisWasUncertain ? "P0-TRAINING-UNCERTAIN" : "P0-TRAINING-ACTIVE")
    }

    func requestDeleteDraft() { deletionIsDraft = true; navigate(to: "P0-DELETE-CONFIRM") }
    func requestDeleteRecord() { deletionIsDraft = false; navigate(to: "P0-DELETE-CONFIRM") }

    func discardCurrentGroup() {
        guard !busy else { return }
        if isSquat {
            squatSession.beginGroup(); groupInProgress = false; draft?.groupInProgress = false
            summary = squatSession.summary; draft?.active = summary; completedTrainingReps = 0
            checkpoint(); navigate(to: groups.isEmpty ? "P0-CALIBRATION-SUCCESS" : "P0-SESSION-GROUPS"); return
        }
        generation += 1; busy = true
        operation = Task {
            await engine.interrupt()
            groupInProgress = false; draft?.groupInProgress = false
            summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
            draft?.active = summary; completedTrainingReps = 0; latestCue = nil
            checkpoint(); busy = false
            navigate(to: groups.isEmpty ? "P0-CALIBRATION-SUCCESS" : "P0-SESSION-GROUPS")
        }
    }

    func startGroup() {
        guard draft != nil else { navigate(to: "P0-HOME"); return }
        if isSquat {
            guard squatSession.baseline != nil else { navigate(to: "P0-CALIBRATION-READY"); return }
            squatSession.beginGroup()
            groupInProgress = true; analysisWasUncertain = false; completedTrainingReps = 0; latestCue = nil
            summary = squatSession.summary; draft?.active = summary; draft?.groupInProgress = true
            checkpoint(); navigate(to: "P0-TRAINING-ACTIVE"); return
        }
        guard let calibration else { navigate(to: "P0-CALIBRATION-READY"); return }
        guard ProcessInfo.processInfo.thermalState != .critical else { navigate(to: "P0-DEVICE-THERMAL"); return }
        busy = true
        let token = generation
        operation = Task {
            await engine.start(config: config, calibration: calibration)
            guard token == generation else { return }
            groupInProgress = true; analysisWasUncertain = false; completedTrainingReps = 0; latestCue = nil
            summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
            draft?.active = summary; draft?.groupInProgress = true
            checkpoint(); busy = false; navigate(to: "P0-TRAINING-ACTIVE")
        }
    }

    func receive(_ observation: PoseObservation) async {
        guard needsCamera, !busy else { return }
        lastFrame = .now
        let token = generation
        if isSquat {
            guard !isCameraPaused else { return }
            if lastSkeletonTimestamp < 0 || observation.timestampMs < lastSkeletonTimestamp || observation.timestampMs - lastSkeletonTimestamp >= 100 {
                latestPose = observation; lastSkeletonTimestamp = observation.timestampMs
            }
            if ["P0-CALIBRATION-READY", "P0-CALIBRATION-RUNNING", "P0-CALIBRATION-SUCCESS", "P0-INTERRUPT-FOREGROUND"].contains(currentID) || activeTraining {
                let update = squatSession.ingest(observation, counting: groupInProgress && activeTraining)
                if poseFailure != update.failure { poseFailure = update.failure }
                if abs(standingProgress - update.standingProgress) >= 0.02 { standingProgress = update.standingProgress }
                if trackingMessage != update.message { trackingMessage = update.message }
                readyFrames = update.tracking ? readyFrames + 1 : 0
                if readyFrames == 5 { objectWillChange.send() }
                if update.rep != nil || update.attempt != nil {
                    summary = squatSession.summary; completedTrainingReps = summary.reps.count; draft?.active = summary
                    checkpoint()
                    if let rep = update.rep, speechEnabled { speech.speak("\(rep.id) 次") }
                }
                if activeTraining {
                    let target = update.baselineReady && update.tracking ? "P0-TRAINING-ACTIVE" : "P0-TRAINING-UNCERTAIN"
                    if currentID != target { currentID = target }
                } else if ["P0-CALIBRATION-READY", "P0-CALIBRATION-RUNNING"].contains(currentID), update.baselineReady {
                    startGroup()
                    if speechEnabled { speech.speak("已站稳，开始计次") }
                } else if currentID == "P0-CALIBRATION-SUCCESS", !update.baselineReady { navigate(to: "P0-CALIBRATION-READY") }
            }
            return
        }
        let required: [LandmarkID] = [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
        let reliable = required.allSatisfy { (observation.landmarks[$0]?.quality ?? 0) >= 0.65 }
        readyFrames = reliable ? readyFrames + 1 : 0
        trackingMessage = reliable ? "全身关键点可见" : "请保持全身入镜，增加照明"
        if currentID == "P0-CALIBRATION-RUNNING" {
            guard reliable else { collector.reset(); completedCalibrationReps = 0; return }
            if let update = collector.ingest(observation) {
                completedCalibrationReps = update.completedRepCount
                if let profile = update.profile {
                    calibration = profile; draft?.calibration = profile
                    checkpoint(); navigate(to: "P0-CALIBRATION-SUCCESS")
                } else if update.error != nil { navigate(to: "P0-CALIBRATION-INCONSISTENT") }
            }
        } else if activeTraining && groupInProgress {
            let events = await engine.ingest(observation)
            guard token == generation, activeTraining else { return }
            for event in events {
                switch event {
                case .repCompleted:
                    summary = await engine.finish()
                    completedTrainingReps = summary.reps.count
                    draft?.active = summary; checkpoint()
                case let .feedback(feedback):
                    latestCue = feedback.issue.coachCue
                    if speechEnabled { speech.speak(feedback.issue.coachCue) }
                case .analysisPaused:
                    currentID = "P0-TRAINING-UNCERTAIN"; latestCue = nil
                case .analysisResumed: currentID = "P0-TRAINING-ACTIVE"
                default: break
                }
            }
        }
    }

    func interrupt(to id: String) {
        if activeTraining { analysisWasUncertain = currentID == "P0-TRAINING-UNCERTAIN" }
        generation += 1
        if currentID == "P0-CALIBRATION-RUNNING" { collector.reset(); completedCalibrationReps = 0 }
        navigate(to: id)
        speech.stop()
        latestCue = nil
        // Permission dialogs and calibration can interrupt the preview before
        // a training group exists. There is no engine state to drain then;
        // waiting on it can leave every primary action blocked by `busy`.
        if isSquat {
            squatSession.interrupt()
            if groupInProgress { summary = squatSession.summary; draft?.active = summary }
            else { squatSession.reset(); standingProgress = 0 }
            checkpoint(); busy = false; return
        }
        guard groupInProgress else {
            checkpoint()
            busy = false
            return
        }
        busy = true
        operation = Task {
            await engine.interrupt()
            if groupInProgress {
                summary = await engine.finish()
                draft?.active = summary
            }
            checkpoint(); busy = false
        }
    }

    func finishGroup() { finishGroup(then: nil) }

    private func finishGroup(then completion: (() -> Void)?) {
        guard groupInProgress else { navigate(to: "P0-SESSION-GROUPS"); completion?(); return }
        if isSquat {
            generation += 1; camera.stop(); squatSession.interrupt(reason: .groupEnded); summary = squatSession.summary
            draft?.groups.append(summary); draft?.active = WorkoutSummary(reps: [], suppressedIssueCount: 0)
            draft?.groupInProgress = false; groupInProgress = false; selectedRep = summary.reps.first
            checkpoint(); navigate(to: "P0-SUMMARY-CLEAN"); completion?(); return
        }
        generation += 1; camera.stop(); busy = true
        operation = Task {
            await engine.interrupt()
            summary = await engine.finish()
            draft?.groups.append(summary)
            draft?.active = WorkoutSummary(reps: [], suppressedIssueCount: 0)
            draft?.groupInProgress = false; groupInProgress = false
            selectedRep = summary.reps.first
            checkpoint(); busy = false
            navigate(to: issues.isEmpty ? "P0-SUMMARY-CLEAN" : "P0-SUMMARY-ISSUES")
            completion?()
        }
    }

    func checkpoint() {
        guard let draft else { return }
        do {
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(draft).write(to: draftURL, options: .atomic)
            lastCheckpoint = .now
        } catch { saveFailureMessage = "草稿保存失败：\(error.localizedDescription)" }
    }

    func resumeDraft() {
        guard !busy else { return }
        guard let value = draft else { navigate(to: "P0-HOME"); return }
        selectedRecord = nil; trainingSide = value.side; trainingGoal = value.goal
        analysisWasUncertain = false
        calibration = value.calibration; groupInProgress = value.groupInProgress
        if isSquat {
            squatDescentTargetMs = value.minimumDescentMs ?? 0
            squatSession.reset(summary: value.active); standingProgress = 0
            summary = value.active; completedTrainingReps = value.active.reps.count
            navigate(to: groupInProgress ? "P0-TRAINING-UNCERTAIN" : "P0-CALIBRATION-READY"); return
        }
        summary = value.active; completedTrainingReps = value.active.reps.count
        busy = true
        operation = Task {
            if let calibration, groupInProgress { await engine.restore(config: config, calibration: calibration, summary: value.active) }
            busy = false; openCamera()
        }
    }

    func recalibratePreservingCompletedReps() {
        guard !busy else { return }
        let reset = { [self] in
            squatSession.reset(); standingProgress = 0
            calibration = nil; draft?.calibration = nil; collector.reset(); completedCalibrationReps = 0
            checkpoint(); navigate(to: "P0-CALIBRATION-READY")
        }
        if groupInProgress {
            finishGroup(then: reset)
        } else { reset() }
    }

    func saveSession() { saveSession(archivingActiveGroup: false) }

    private func saveSession(archivingActiveGroup: Bool) {
        guard let context, let value = draft, !groupInProgress || archivingActiveGroup else { return }
        // A reloaded draft can have an active group before the live engine is
        // restored. Archive its persisted completed reps, never just its groups.
        let savedGroups = value.groups + (archivingActiveGroup && value.groupInProgress ? [value.active] : [])
        navigate(to: "P0-SAVE-PROGRESS")
        do {
            let combined = WorkoutSummary(reps: savedGroups.flatMap(\.reps),
                                          suppressedIssueCount: savedGroups.reduce(0) { $0 + $1.suppressedIssueCount },
                                          feedbackEvents: savedGroups.flatMap(\.feedbackEvents),
                                          squatAnalysis: savedGroups.contains { $0.squatAnalysis != nil } ? SquatAnalysis(attempts: savedGroups.flatMap { $0.squatAnalysis?.attempts ?? [] }) : nil)
            let record: StoredWorkoutSession
            if let existing = records.first(where: { $0.id == value.id }) { record = existing }
            else { record = try StoredWorkoutSession(summary: combined, config: config, startedAt: value.startedAt) }
            record.id = value.id; record.endedAt = .now
            record.summaryJSON = try JSONEncoder().encode(combined)
            record.groupsJSON = try JSONEncoder().encode(savedGroups)
            record.repCount = combined.reps.count
            record.issueCount = combined.reps.flatMap(\.issues).filter { $0.disposition != .suppressed }.count
            context.insert(record); try context.save()
            selectedRecord = record
            if FileManager.default.fileExists(atPath: draftURL.path) {
                do { try FileManager.default.removeItem(at: draftURL) }
                catch { saveFailureMessage = "会话已保存，但草稿清理失败。" }
            }
            draft = nil; calibration = nil; groupInProgress = false
            refreshRecords(); navigate(to: "P0-SAVE-SUCCESS")
        } catch {
            context.rollback(); saveFailureMessage = error.localizedDescription
            navigate(to: "P0-SAVE-FAILED")
        }
    }

    func openRecord(_ record: StoredWorkoutSession) {
        routeHistory = ["P0-HISTORY-SESSIONS"]
        selectedRecord = record; summary = record.decodedSummary() ?? WorkoutSummary(reps: [], suppressedIssueCount: 0)
        navigate(to: "P0-HISTORY-SESSION-DETAIL", recordingHistory: false)
    }
    func openSelectedRecord() { if let selectedRecord { openRecord(selectedRecord) } }
    func openGroup(_ index: Int) {
        guard groups.indices.contains(index) else { return }
        summary = groups[index]; selectedRep = summary.reps.first
        navigate(to: "P0-HISTORY-GROUP-DETAIL")
    }
    func openRep(_ rep: RepSummary) { selectedRep = rep; navigate(to: "P0-REP-DETAIL") }

    func deleteSelected() {
        guard let context else { return }
        do {
            if deletionIsDraft {
                if FileManager.default.fileExists(atPath: draftURL.path) { try FileManager.default.removeItem(at: draftURL) }
                draft = nil; groupInProgress = false; calibration = nil; deletionIsDraft = false
            } else if let record = selectedRecord {
                try SessionDeletionService.delete(record, context: context); selectedRecord = nil
            } else { navigate(to: "P0-HISTORY-SESSIONS"); return }
            refreshRecords(); navigate(to: "P0-DELETE-SUCCESS")
        } catch { context.rollback(); saveFailureMessage = error.localizedDescription; navigate(to: "P0-DELETE-FAILED") }
    }

    func cameraStatusChanged(_ status: CameraService.Status) {
        guard needsCamera else { return }
        switch status {
        case .denied: interrupt(to: "P0-PERMISSION-DENIED")
        case let .unavailable(reason): interrupt(to: reason == "pose_inference_failed" ? "P0-INFERENCE-FAILED" : "P0-CAMERA-IN-USE")
        default: break
        }
    }

    func tick() {
        guard needsCamera, !busy else { return }
        if Date().timeIntervalSince(lastFrame) > 3, Date().timeIntervalSince(cameraStarted) > 3 {
            trackingMessage = "未检测到可靠人体，请调整机位"
            if activeTraining && currentID != "P0-TRAINING-UNCERTAIN" {
                generation += 1; currentID = "P0-TRAINING-UNCERTAIN"
                if isSquat {
                    squatSession.interrupt(reason: .trackingLost, failure: .frameGap)
                    summary = squatSession.summary; draft?.active = summary; checkpoint()
                } else { Task { await engine.interrupt() } }
            }
        }
        if ProcessInfo.processInfo.thermalState == .critical { interrupt(to: "P0-DEVICE-THERMAL") }
    }

    func sceneChanged(_ phase: ScenePhase) {
        if phase != .active, needsCamera { interrupt(to: "P0-INTERRUPT-BACKGROUND") }
        if phase == .active {
            if currentID == "P0-INTERRUPT-BACKGROUND" { navigate(to: "P0-INTERRUPT-FOREGROUND") }
            if currentID.contains("PERMISSION"), currentID != "P0-PERMISSION-REQUEST" {
                navigate(to: AVCaptureDevice.authorizationStatus(for: .video) == .authorized ? "P0-PERMISSION-RETURN-GRANTED" : "P0-PERMISSION-RETURN-DENIED")
            }
        }
    }
    func goBack() {
        if currentID == "P0-HISTORY-SESSION-DETAIL" { selectTab("P0-HISTORY-SESSIONS"); return }
        if currentID == "P0-HISTORY-GROUP-DETAIL" {
            routeHistory = [selectedRecord == nil ? "P0-HOME" : "P0-HISTORY-SESSIONS"]
            navigate(to: selectedRecord == nil ? "P0-SESSION-GROUPS" : "P0-HISTORY-SESSION-DETAIL", recordingHistory: false)
            return
        }
        if currentID == "P0-ABANDON-CONFIRM" { navigate(to: "P0-EXIT-MENU"); return }
        if currentID == "P0-END-SET-CONFIRM" {
            if groupInProgress { resumeCurrentGroup() } else { navigate(to: "P0-CALIBRATION-READY") }
            return
        }
        if isCameraPaused { performPrimary(); return }
        if needsCamera { interrupt(to: "P0-EXIT-MENU"); return }
        if ["P0-SAVE-SUCCESS", "P0-DELETE-SUCCESS"].contains(currentID) { selectTab("P0-HOME"); return }
        if ["P0-SUMMARY-CLEAN", "P0-SUMMARY-ISSUES"].contains(currentID) { routeHistory = ["P0-HOME"]; navigate(to: "P0-SESSION-GROUPS", recordingHistory: false); return }
        if currentID == "P0-SESSION-SETUP" { selectTab("P0-HOME"); return }
        navigate(to: routeHistory.popLast() ?? "P0-HOME", recordingHistory: false)
    }
    func resetSession() { calibration = nil; completedCalibrationReps = 0; completedTrainingReps = 0; navigate(to: "P0-SESSION-SETUP") }
}

extension IssueType {
    var coachTitle: String {
        switch self { case .torsoCollapse: "躯干稳定性不足"; case .insufficientDepth: "深度不足"; case .fastDescent: "下降过快" }
    }
    var coachCue: String {
        switch self { case .torsoCollapse: "下一次稳住躯干"; case .insufficientDepth: "保持控制，达到本次校准的动作幅度"; case .fastDescent: "下一次放慢下降速度" }
    }
}

extension V3ScreenSpec {
    var recoveryMessage: String {
        switch stateId {
        case "P0-SAFETY": "请在理解以下说明后开始训练。"
        case "P0-PERMISSION-REQUEST": "只申请摄像头权限，用于实时识别动作。"
        case "P0-PERMISSION-DENIED", "P0-PERMISSION-RETURN-DENIED": "在系统设置中允许摄像头后，再返回此 App。"
        case "P0-CAMERA-IN-USE": "确认摄像头可用后重试，也可以返回首页稍后继续。"
        case "P0-SAVE-FAILED", "P0-STORAGE-FULL": "草稿仍保留在本机；请检查存储空间后重试。"
        case "P0-DEVICE-THERMAL": "请等待手机降温后再继续。"
        default: "已完成的动作会保留；请按页面提示继续或返回首页。"
        }
    }

    var productDetail: String {
        switch stateId {
        case "P0-PERMISSION-REQUEST": return "允许使用摄像头来识别动作。画面只在本机处理，不保存训练视频。"
        case "P0-SETTINGS": return "语音设置会自动保存，文字提示始终显示。"
        case "P0-MY-LOCAL": return "查看训练记录，调整反馈方式与了解本机隐私。"
        case "P0-HOME": return "选择一个动作开始训练，或继续上次未完成的会话。"
        case "P0-DRAFT-RESUME": return "已完成的重复保存在本机。继续前请确认机位没有改变。"
        case "P0-EXERCISE-LIBRARY": return "第一版支持侧面拍摄的保加利亚分腿蹲。"
        case "P0-SESSION-SETUP", "P0-NEXT-SET-READY": return "确认训练腿与本组目标；同一会话沿用相同设置。"
        case "P0-CAMERA-IN-USE": return "相机可能被占用，或当前设备没有可用摄像头。模拟器无法代替 iPhone 拍摄训练。"
        case "P0-INTERRUPT-FOREGROUND": return "全身入镜并站回起始位置，画面稳定后点击继续；机位改变请重新校准。"
        case "P0-DELETE-CONFIRM": return "这会永久删除所选本地记录，且无法撤销。"
        case "P0-SAVE-FAILED": return "尚未确认保存成功。请重试；当前草稿仍会保留。"
        default: return userSees.detail
        }
    }

    var symbol: String {
        switch stateId {
        case "P0-LAUNCH", "P0-MODEL-LOADING": return "figure.strengthtraining.traditional"
        case let id where id.contains("PERMISSION"): return "camera.fill"
        case let id where id.contains("QUALITY"): return "viewfinder.trianglebadge.exclamationmark"
        case let id where id.contains("THERMAL"): return "thermometer.high"
        case let id where id.contains("BATTERY"): return "battery.25"
        case let id where id.contains("AUDIO"): return "speaker.slash.fill"
        case let id where id.contains("CALL"): return "phone.fill"
        case let id where id.contains("LOCK"): return "lock.fill"
        case let id where id.contains("BACKGROUND"): return "rectangle.on.rectangle.slash"
        case let id where id.contains("MODEL") || id.contains("INFERENCE"): return "cpu"
        case let id where id.contains("SAVE"): return "square.and.arrow.down"
        case let id where id.contains("DELETE"): return "trash.fill"
        case let id where id.contains("HISTORY") || id == "P0-SESSION-GROUPS": return "clock.arrow.circlepath"
        case "P0-SETTINGS": return "slider.horizontal.3"
        case "P0-PRIVACY-LOCAL", "P0-MY-LOCAL": return "hand.raised.fill"
        case let id where id.hasPrefix("A11Y-"): return "accessibility"
        default: return "checkmark.seal.fill"
        }
    }

    var semanticTone: CoachTone {
        if stateId.contains("FAILED") || stateId.contains("DENIED") || stateId.contains("ABANDON") { return .danger }
        if stateId.contains("SUCCESS") || stateId.contains("CLEAN") || stateId.contains("COMPLETE") { return .success }
        if layoutKind == "quality" || stateId.contains("LOW-BATTERY") || stateId.contains("THERMAL") { return .coaching }
        return .info
    }
}
