import Foundation
import SwiftUI
import UIKit

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

@MainActor
final class P0FlowModel: ObservableObject {
    @Published private(set) var currentID = "P0-LAUNCH"
    @Published private(set) var routeHistory: [String] = []
    @Published var showsStateCatalog = false
    @Published var trainingSide = "右腿"
    @Published var trainingGoal = "一般检查"
    @Published var speechEnabled = true
    @Published var completedCalibrationReps = 0
    @Published var completedTrainingReps = 8
    @Published var savedSessionCount = 2
    @Published var saveFailureMessage: String?

    let screens: [V3ScreenSpec]
    private let byID: [String: V3ScreenSpec]

    init(screens: [V3ScreenSpec] = V3ManifestStore.p0Screens) {
        self.screens = screens
        self.byID = Dictionary(uniqueKeysWithValues: screens.map { ($0.stateId, $0) })
        if !screens.contains(where: { $0.stateId == currentID }), let first = screens.first {
            currentID = first.stateId
        }
    }

    var current: V3ScreenSpec? { byID[currentID] }

    func navigate(to stateID: String, recordingHistory: Bool = true) {
        guard byID[stateID] != nil else { return }
        if recordingHistory, currentID != stateID { routeHistory.append(currentID) }
        currentID = stateID
    }

    func performPrimary() {
        guard let screen = current else { return }

        switch screen.stateId {
        case "P0-CALIBRATION-RUNNING":
            if completedCalibrationReps < 2 {
                completedCalibrationReps += 1
                return
            }
            completedCalibrationReps = 3
        case "P0-SAVE-PROGRESS":
            savedSessionCount += 1
        case "P0-DELETE-CONFIRM":
            savedSessionCount = max(0, savedSessionCount - 1)
        case "P0-PERMISSION-DENIED", "P0-PERMISSION-RETURN-DENIED":
            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
        default:
            break
        }

        if let next = screen.nextState, byID[next] != nil {
            navigate(to: next)
        } else {
            navigate(to: "P0-HOME")
        }
    }

    func performSecondary() {
        guard let screen = current else { return }
        if let target = screen.secondaryTarget, byID[target] != nil {
            navigate(to: target)
            return
        }

        let action = screen.secondaryAction ?? ""
        switch action {
        case let value where value.contains("隐私"):
            navigate(to: "P0-PRIVACY-LOCAL")
        case let value where value.contains("返回首页"):
            navigate(to: "P0-HOME")
        case let value where value.contains("更换动作"):
            navigate(to: "P0-EXERCISE-LIBRARY")
        case let value where value.contains("重新校准"):
            completedCalibrationReps = 0
            navigate(to: "P0-CALIBRATION-READY")
        case let value where value == "暂停" || value.contains("暂停校准"):
            navigate(to: "P0-EXIT-MENU")
        case let value where value.contains("关闭语音"):
            speechEnabled = false
            navigate(to: "P0-TRAINING-ACTIVE")
        case let value where value.contains("恢复语音") || value.contains("开启语音"):
            speechEnabled = true
            navigate(to: "P0-TRAINING-ACTIVE")
        case let value where value.contains("完成会话"):
            navigate(to: "P0-SESSION-COMPLETE")
        case let value where value.contains("再做一组"):
            navigate(to: "P0-NEXT-SET-READY")
        case let value where value.contains("修改会话设置") || value.contains("修改训练腿"):
            navigate(to: "P0-SESSION-SETUP")
        case let value where value.contains("结束本组"):
            navigate(to: "P0-END-SET-CONFIRM")
        case let value where value.contains("保存草稿") || value.contains("保留草稿") || value.contains("稍后恢复"):
            navigate(to: "P0-DRAFT-RESUME")
        case let value where value.contains("删除草稿") || value.contains("删除会话"):
            navigate(to: "P0-DELETE-CONFIRM")
        case let value where value.contains("查看已保留重复") || value.contains("下一次重复"):
            navigate(to: "P0-REP-DETAIL")
        case let value where value.contains("返回会话"):
            navigate(to: "P0-SESSION-GROUPS")
        case let value where value.contains("返回设置"):
            navigate(to: "P0-SETTINGS")
        default:
            goBack()
        }
    }

    func goBack() {
        guard let previous = routeHistory.popLast() else {
            navigate(to: "P0-HOME", recordingHistory: false)
            return
        }
        currentID = previous
    }

    func resetSession() {
        completedCalibrationReps = 0
        completedTrainingReps = 0
        navigate(to: "P0-SESSION-SETUP")
    }
}

extension V3ScreenSpec {
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
