import Foundation
import SwiftUI
import FormCoachCore

final class PoseDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [PoseObservation] = []
    private var recording = false
    func start() { lock.lock(); defer { lock.unlock() }; frames = []; recording = true }
    func append(_ frame: PoseObservation) {
        lock.lock(); defer { lock.unlock() }
        if recording, frames.count < 3_600 { frames.append(frame) }
    }
    func finish() throws -> Data {
        lock.lock(); let value = frames; recording = false; frames = []; lock.unlock()
        let first = value.first?.timestampMs ?? 0
        let relative = value.map { PoseObservation(timestampMs: $0.timestampMs - first, landmarks: $0.landmarks, inferenceMs: $0.inferenceMs, engineVersion: $0.engineVersion, imageWidth: $0.imageWidth, imageHeight: $0.imageHeight, detectedPersonCount: $0.detectedPersonCount) }
        return try JSONEncoder().encode(PoseReplayFile(version: 1, frames: relative))
    }
}

struct PoseSkeletonOverlay: View {
    let observation: PoseObservation
    var fill = true
    private let bones: [(LandmarkID, LandmarkID)] = [
        (.leftShoulder,.rightShoulder), (.leftShoulder,.leftElbow), (.leftElbow,.leftWrist),
        (.rightShoulder,.rightElbow), (.rightElbow,.rightWrist),
        (.leftShoulder,.leftHip), (.rightShoulder,.rightHip), (.leftHip,.rightHip),
        (.leftHip,.leftKnee), (.leftKnee,.leftAnkle), (.rightHip,.rightKnee), (.rightKnee,.rightAnkle),
        (.leftAnkle,.leftHeel), (.leftHeel,.leftFootIndex), (.rightAnkle,.rightHeel), (.rightHeel,.rightFootIndex)
    ]
    var body: some View {
        Canvas { context, size in
            func position(_ point: Landmark) -> CGPoint? {
                guard let mapped = PosePreviewMapping.point(point, imageWidth: observation.imageWidth, imageHeight: observation.imageHeight, viewWidth: size.width, viewHeight: size.height, fill: fill) else { return nil }
                return CGPoint(x: mapped.x, y: mapped.y)
            }
            for (a,b) in bones {
                guard let first = observation.landmarks[a], let last = observation.landmarks[b], first.quality >= 0.15, last.quality >= 0.15,
                      let p = position(first), let q = position(last) else { continue }
                var path = Path(); path.move(to: p); path.addLine(to: q)
                let reliable = min(first.quality,last.quality) >= 0.65
                context.stroke(path, with: .color(reliable ? .green : .orange), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: reliable ? [] : [5,3]))
            }
            for point in observation.landmarks.values where point.quality >= 0.15 {
                guard let p = position(point) else { continue }
                context.fill(Path(ellipseIn: CGRect(x: p.x-3.5,y:p.y-3.5,width:7,height:7)), with: .color(point.quality >= 0.65 ? .green : .orange))
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PoseDiagnosticsScreen: View {
    @EnvironmentObject private var flow: P0FlowModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var camera: CameraService
    var body: some View {
        NavigationStack {
            Form {
                Section("识别引擎") {
                    Picker("当前模型", selection: Binding(get: { camera.engineChoice }, set: { flow.selectPoseEngine($0) })) {
                        ForEach(PoseEngineChoice.allCases.filter(\.isAvailable)) { Text($0.title).tag($0) }
                    }.disabled(flow.hasActiveGroup || camera.isRecordingDiagnostic)
                    if flow.hasActiveGroup { Text("先结束当前组，再切换模型；切换后重新站稳。").font(.caption) }
                    Toggle("显示人体骨架", isOn: $flow.showsSkeleton)
                    Text("绿色表示较强关键点，橙色表示证据较弱；骨架用于检查识别位置，不代表动作合格。").font(.caption)
                }
                Section("当前画面") {
                    Text(flow.trackingMessage)
                    LabeledContent("判断原因", value: flow.poseFailure.rawValue)
                    LabeledContent("有效输入", value: String(format: "%.1f 帧/秒", camera.analyzedFPS))
                    LabeledContent("最大采样间隔", value: "\(camera.maximumFrameGapMs) ms")
                    if let pose = flow.latestPose {
                        LabeledContent("检出人数", value: pose.detectedPersonCount.map(String.init) ?? "未知")
                        LabeledContent("图像尺寸", value: "\(Int(pose.imageWidth)) × \(Int(pose.imageHeight))")
                        LabeledContent("单帧推理", value: String(format: "%.1f ms", pose.inferenceMs))
                        ForEach([LandmarkID.leftShoulder,.rightShoulder,.leftHip,.rightHip,.leftKnee,.rightKnee,.leftAnkle,.rightAnkle], id: \.self) { id in
                            LabeledContent(id.displayName, value: pose.landmarks[id].map { String(format: "%.2f",$0.quality) } ?? "未检出")
                        }
                    }
                    if let error = camera.inferenceError { Text(error).foregroundStyle(.red) }
                }
                Section("采集实际拍屏输入") {
                    Text("固定 iPhone，先保持人物站立，再播放动作。录制 20 秒相机视频和关键点日志，仅保存在本机，不录音。结束后可用同一录像比较两个模型。").font(.caption)
                    if camera.isRecordingDiagnostic {
                        Button("停止并保存录像", action: camera.stopDiagnosticRecording)
                    } else {
                        Button("录制 20 秒对照视频") { camera.recordDiagnostic() }
                    }
                    if let error = camera.recordingError { Text(error).foregroundStyle(.red) }
                    if let url = camera.diagnosticVideoURL {
                        ShareLink("导出最近一次实际录像", item: url)
                        Button("对这段录像进行双模型对比") { dismiss(); flow.showsReplay = true }
                    }
                    if let url = camera.diagnosticTraceURL { ShareLink("导出关键点日志", item: url) }
                }
            }
            .navigationTitle("识别诊断").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: dismiss.callAsFunction) } }
        }
    }
}
