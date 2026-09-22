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
    var calibration: CalibrationProfile?
    var groups: [WorkoutSummary] = []
    var active = WorkoutSummary(reps: [], suppressedIssueCount: 0)
    var groupInProgress = false
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
    let camera = CameraService()
    private let engine = WorkoutSessionEngine()
    private let speech = SpeechService()
    private var collector = GuidedCalibrationCollector()
    private var context: ModelContext?
    private var calibration: CalibrationProfile?
    private var groupInProgress = false
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
    let screens: [V3ScreenSpec]
    private let byID: [String: V3ScreenSpec]
    var savedSessionCount: Int { records.count }
    var current: V3ScreenSpec? { byID[currentID] }
    var activeTraining: Bool { ["P0-TRAINING-ACTIVE", "P0-TRAINING-COACHING", "P0-TRAINING-UNCERTAIN"].contains(currentID) }
    var needsCamera: Bool { activeTraining || ["P0-CALIBRATION-READY", "P0-CALIBRATION-RUNNING", "P0-INTERRUPT-FOREGROUND"].contains(currentID) }
    var groups: [WorkoutSummary] {
        if let selectedRecord, let data = selectedRecord.groupsJSON,
           let groups = try? JSONDecoder().decode([WorkoutSummary].self, from: data) { return groups }
        if let selectedRecord, let value = selectedRecord.decodedSummary() { return [value] }
        return draft?.groups ?? []
    }
    var issues: [IssueEvent] { summary.reps.flatMap(\.issues).filter { $0.disposition != .suppressed } }
    var settingsLocked: Bool { groupInProgress || !(draft?.groups.isEmpty ?? true) }
    var config: SessionConfig {
        SessionConfig(trainingSide: trainingSide == "左腿" ? .left : .right,
                      variant: trainingGoal == "偏臀" ? .gluteBias : trainingGoal == "偏股四头肌" ? .quadBias : .general,
                      speechEnabled: true, saveVideo: false)
    }
    private var draftURL: URL {
        if let storageURL { return storageURL }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("training-draft.json")
    }

    init(screens: [V3ScreenSpec] = V3ManifestStore.p0Screens, storageURL: URL? = nil, cameraEnabled: Bool = true) {
        self.screens = screens
        self.storageURL = storageURL
        self.cameraEnabled = cameraEnabled
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
            UserDefaults.standard.set(true, forKey: "coach.safety"); navigate(to: "P0-HOME")
        case "P0-HOME":
            selectedRecord = nil
            navigate(to: draft == nil ? "P0-EXERCISE-LIBRARY" : "P0-DRAFT-RESUME")
        case "P0-EXERCISE-LIBRARY":
            selectedRecord = nil
            if draft == nil { draft = LocalTrainingDraft(side: trainingSide, goal: trainingGoal) }
            navigate(to: "P0-SESSION-SETUP")
        case "P0-SESSION-SETUP":
            if draft?.side != trainingSide || draft?.goal != trainingGoal { calibration = nil; draft?.calibration = nil }
            draft?.side = trainingSide; draft?.goal = trainingGoal
            checkpoint(); navigate(to: "P0-CAMERA-GUIDE")
        case "P0-PERMISSION-REQUEST":
            Task { let granted = await AVCaptureDevice.requestAccess(for: .video)
                navigate(to: granted ? "P0-CALIBRATION-READY" : "P0-PERMISSION-DENIED") }
        case "P0-PERMISSION-DENIED", "P0-PERMISSION-RETURN-DENIED":
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case "P0-CALIBRATION-READY", "P0-CALIBRATION-INCONSISTENT":
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
        case "P0-END-SET-CONFIRM", "P0-ABANDON-KEEP-REPS":
            finishGroup()
        case "P0-ABANDON-CONFIRM":
            finishGroup()
        case "P0-EXIT-MENU", "P0-INTERRUPT-FOREGROUND":
            if currentID == "P0-INTERRUPT-FOREGROUND", readyFrames < 5, cameraEnabled { return }
            if groupInProgress { navigate(to: "P0-TRAINING-ACTIVE") }
            else { navigate(to: calibration == nil ? "P0-CALIBRATION-READY" : "P0-NEXT-SET-READY") }
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
        case "P0-REP-DETAIL": goBack()
        case "P0-SUMMARY-ISSUES", "P0-HISTORY-GROUP-DETAIL":
            if let rep = summary.reps.first { openRep(rep) }
        default:
            if let next = current?.nextState { navigate(to: next) } else { navigate(to: "P0-HOME") }
        }
    }

    func performSecondary() {
        guard !busy, let screen = current else { return }
        let action = screen.secondaryAction ?? ""
        if currentID == "P0-HOME" { navigate(to: draft == nil ? "P0-HOME" : "P0-DRAFT-RESUME"); return }
        if action.contains("完成会话") { saveSession(); return }
        if action.contains("删除草稿") { deletionIsDraft = true; navigate(to: "P0-DELETE-CONFIRM"); return }
        if action.contains("删除会话") { deletionIsDraft = false; navigate(to: "P0-DELETE-CONFIRM"); return }
        if action == "删除本组" {
            groupInProgress = false; draft?.groupInProgress = false
            draft?.active = WorkoutSummary(reps: [], suppressedIssueCount: 0)
            checkpoint(); navigate(to: "P0-SESSION-GROUPS"); return
        }
        if action.contains("暂停") { interrupt(to: "P0-EXIT-MENU"); return }
        if action.contains("结束本组") { interrupt(to: "P0-END-SET-CONFIRM"); return }
        if action.contains("放弃本组") { interrupt(to: "P0-ABANDON-CONFIRM"); return }
        if action.contains("草稿") || action.contains("稍后恢复") {
            checkpoint(); interrupt(to: "P0-HOME"); return
        }
        if action.contains("重新校准") {
            calibration = nil; collector.reset(); completedCalibrationReps = 0
            navigate(to: "P0-CALIBRATION-READY"); return
        }
        if action.contains("修改会话设置"), settingsLocked {
            saveFailureMessage = "当前会话的训练腿和目标已固定。请先保存会话，再开始不同设置的训练。"
            return
        }
        if action.contains("语音") {
            speechEnabled = !action.contains("关闭"); navigate(to: "P0-TRAINING-ACTIVE"); return
        }
        if action.contains("下一次重复"), let selectedRep,
           let index = summary.reps.firstIndex(where: { $0.id == selectedRep.id }), !summary.reps.isEmpty {
            self.selectedRep = summary.reps[(index + 1) % summary.reps.count]; return
        }
        if action.contains("隐私") { navigate(to: "P0-PRIVACY-LOCAL"); return }
        if let target = screen.secondaryTarget { navigate(to: target); return }
        if action.contains("继续训练") { navigate(to: "P0-TRAINING-ACTIVE"); return }
        if action.contains("返回首页") { navigate(to: "P0-HOME"); return }
        if action.contains("修改") || action.contains("更换动作") { navigate(to: "P0-SESSION-SETUP"); return }
        if action.contains("返回会话") { navigate(to: selectedRecord == nil ? "P0-SESSION-GROUPS" : "P0-HISTORY-SESSION-DETAIL"); return }
        goBack()
    }

    func startGroup() {
        guard draft != nil else { navigate(to: "P0-HOME"); return }
        guard let calibration else { navigate(to: "P0-CALIBRATION-READY"); return }
        guard ProcessInfo.processInfo.thermalState != .critical else { navigate(to: "P0-DEVICE-THERMAL"); return }
        busy = true
        let token = generation
        operation = Task {
            await engine.start(config: config, calibration: calibration)
            guard token == generation else { return }
            groupInProgress = true; completedTrainingReps = 0; latestCue = nil
            summary = WorkoutSummary(reps: [], suppressedIssueCount: 0)
            draft?.active = summary; draft?.groupInProgress = true
            checkpoint(); busy = false; navigate(to: "P0-TRAINING-ACTIVE")
        }
    }

    func receive(_ observation: PoseObservation) async {
        guard needsCamera, !busy else { return }
        lastFrame = .now
        let token = generation
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
        generation += 1
        if currentID == "P0-CALIBRATION-RUNNING" { collector.reset(); completedCalibrationReps = 0 }
        navigate(to: id)
        speech.stop()
        latestCue = nil
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

    func finishGroup() {
        guard groupInProgress else { navigate(to: "P0-SESSION-GROUPS"); return }
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
        guard let value = draft else { navigate(to: "P0-HOME"); return }
        selectedRecord = nil; trainingSide = value.side; trainingGoal = value.goal
        calibration = value.calibration; groupInProgress = value.groupInProgress
        summary = value.active; completedTrainingReps = value.active.reps.count
        busy = true
        operation = Task {
            if let calibration, groupInProgress { await engine.restore(config: config, calibration: calibration, summary: value.active) }
            busy = false; navigate(to: "P0-INTERRUPT-FOREGROUND")
        }
    }

    func saveSession() {
        guard let context, let value = draft, !groupInProgress else { return }
        navigate(to: "P0-SAVE-PROGRESS")
        do {
            let combined = WorkoutSummary(reps: value.groups.flatMap(\.reps),
                                          suppressedIssueCount: value.groups.reduce(0) { $0 + $1.suppressedIssueCount },
                                          feedbackEvents: value.groups.flatMap(\.feedbackEvents))
            let record: StoredWorkoutSession
            if let existing = records.first(where: { $0.id == value.id }) { record = existing }
            else { record = try StoredWorkoutSession(summary: combined, config: config, startedAt: value.startedAt) }
            record.id = value.id; record.endedAt = .now
            record.summaryJSON = try JSONEncoder().encode(combined)
            record.groupsJSON = try JSONEncoder().encode(value.groups)
            record.repCount = combined.reps.count
            record.issueCount = combined.reps.flatMap(\.issues).filter { $0.disposition != .suppressed }.count
            context.insert(record); try context.save()
            selectedRecord = record
            if FileManager.default.fileExists(atPath: draftURL.path) {
                do { try FileManager.default.removeItem(at: draftURL) }
                catch { saveFailureMessage = "会话已保存，但草稿清理失败。" }
            }
            draft = nil; calibration = nil; refreshRecords(); navigate(to: "P0-SAVE-SUCCESS")
        } catch {
            context.rollback(); saveFailureMessage = error.localizedDescription
            navigate(to: "P0-SAVE-FAILED")
        }
    }

    func openRecord(_ record: StoredWorkoutSession) {
        selectedRecord = record; summary = record.decodedSummary() ?? WorkoutSummary(reps: [], suppressedIssueCount: 0)
        navigate(to: "P0-HISTORY-SESSION-DETAIL")
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
                Task { await engine.interrupt() }
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
        if needsCamera { interrupt(to: "P0-EXIT-MENU"); return }
        if ["P0-SAVE-SUCCESS", "P0-DELETE-SUCCESS"].contains(currentID) { routeHistory = []; navigate(to: "P0-HOME"); return }
        if ["P0-SUMMARY-CLEAN", "P0-SUMMARY-ISSUES"].contains(currentID) { navigate(to: "P0-SESSION-GROUPS"); return }
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
    var productDetail: String {
        switch stateId {
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
