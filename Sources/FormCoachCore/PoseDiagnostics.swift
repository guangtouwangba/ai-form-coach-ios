import Foundation

public enum PoseFailureReason: String, Codable, Sendable {
    case none, noPerson, multiplePeople, missingJoints, lowConfidence, outOfFrame
    case tooSmall, invalidGeometry, notUpright, wrongView, moving, frameGap
    case cameraMoved, skeletonChanged, jointJump, waitingForTop

    public var message: String {
        switch self {
        case .none: "关键点可用"
        case .noPerson: "未检测到人体，请让一个人全身入镜"
        case .multiplePeople: "检测到多个人体，请只保留训练者入镜"
        case .missingJoints: "肩、髋、膝或踝未检出，请露出全身并调整机位"
        case .lowConfidence: "身体关键点不够清楚，请靠近一些或改善光线"
        case .outOfFrame: "身体关键点接近画面边缘，请调整取景"
        case .tooSmall: "人物在画面中过小，请靠近或只对准视频中的人物"
        case .invalidGeometry: "身体关键点位置不合理，请调整机位并保持侧拍"
        case .notUpright: "请先自然站直，再开始深蹲"
        case .wrongView: "请将手机放在身体侧面"
        case .moving: "画面或身体仍在移动，请固定手机并保持站稳"
        case .frameGap: "有效画面不连续，请保持手机稳定并等待重新检测"
        case .cameraMoved: "机位或脚的位置已变化，请重新站稳"
        case .skeletonChanged: "身体关键点不连续，请回到站立起点"
        case .jointJump: "身体关键点跳变，请回到站立起点"
        case .waitingForTop: "回到站立起点后开始计次"
        }
    }
}

public struct SquatFeatureAssessment: Sendable {
    public let features: SquatFeatures?
    public let failure: PoseFailureReason
    public let joints: [LandmarkID]
    public var message: String {
        let names = joints.prefix(4).map(\.displayName).joined(separator: "、")
        guard !names.isEmpty else { return failure.message }
        switch failure {
        case .missingJoints: return "未检出\(names)，请露出这些部位并调整机位"
        case .lowConfidence: return "\(names)证据不足，请靠近一些或改善光线"
        case .outOfFrame: return "\(names)接近画面边缘，请调整取景"
        default: return failure.message
        }
    }
}

public extension LandmarkID {
    var displayName: String {
        switch self {
        case .leftShoulder: "左肩"
        case .rightShoulder: "右肩"
        case .leftHip: "左髋"
        case .rightHip: "右髋"
        case .leftKnee: "左膝"
        case .rightKnee: "右膝"
        case .leftAnkle: "左踝"
        case .rightAnkle: "右踝"
        default: rawValue
        }
    }
}

public enum PosePreviewMapping {
    /// Same transform as AVCaptureVideoPreviewLayer.resizeAspectFill. Coordinates
    /// are already orientation-corrected and use a top-left origin.
    public static func point(_ point: Landmark, imageWidth: Double, imageHeight: Double,
                             viewWidth: Double, viewHeight: Double, fill: Bool = true) -> (x: Double, y: Double)? {
        guard imageWidth > 0, imageHeight > 0, viewWidth > 0, viewHeight > 0,
              [point.x, point.y, imageWidth, imageHeight, viewWidth, viewHeight].allSatisfy(\.isFinite) else { return nil }
        let scale = fill ? max(viewWidth / imageWidth, viewHeight / imageHeight) : min(viewWidth / imageWidth, viewHeight / imageHeight)
        return (point.x * imageWidth * scale + (viewWidth - imageWidth * scale) / 2,
                point.y * imageHeight * scale + (viewHeight - imageHeight * scale) / 2)
    }
}
