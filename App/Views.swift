import SwiftUI
import SwiftData
import FormCoachCore

struct RootView: View {
    var body: some View {
        P0FlowRootView()
    }
}

struct SafetyView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        OnboardingPage(icon: "figure.strengthtraining.traditional", title: "训练前请先了解", items: [
            "这不是医疗诊断或专业教练替代品。",
            "出现疼痛、眩晕或不适请立即停止。",
            "视频默认在本机处理，而且默认不保存。",
            "手机必须放在器械和行走路径之外。"
        ], actionTitle: "我已了解，开始设置", action: model.acknowledgeSafety)
    }
}

struct ExerciseSelectionView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        CoachNavigationScaffold(title: "AI 动作教练", trailing: { Button { model.openSettings() } label: { Image(systemName: "gearshape") } }) {
            CoachScreen {
              VStack(spacing: CoachSpacing.md) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [CoachColor.trainingSurface, CoachColor.mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 120)).foregroundStyle(.white.opacity(0.34)).frame(maxWidth: .infinity, alignment: .trailing).padding()
                    VStack(alignment: .leading, spacing: 8) { Text("保加利亚分腿蹲").font(.title2.bold()); Text("侧面拍摄 · 实时语音纠正").font(.subheadline); Label("AI 本地识别 · 隐私保护", systemImage: "lock.shield") .font(.caption).padding(.top, 120) }.foregroundStyle(.white).padding(22)
                }.frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 24))
                HStack { Benefit(icon:"speaker.wave.2", text:"实时纠正"); Benefit(icon:"number", text:"自动计次"); Benefit(icon:"shield", text:"安全优先") }
                CoachButton(title: "开始训练", systemImage: "figure.strengthtraining.traditional", action: model.selectExercise)
                Button("查看历史记录", action: model.openHistory).foregroundStyle(.secondary)
              }
            }
        }
    }
}

struct ConfigurationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        CoachNavigationScaffold(title: "训练设置") {
          CoachScreen(scrolls: false) {
            VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                Text("训练腿").font(.headline)
                Picker("训练腿", selection: $model.trainingSide) { Text("左腿").tag(TrainingSide.left); Text("右腿").tag(TrainingSide.right) }.pickerStyle(.segmented)
                Text("训练目标").font(.headline)
                ForEach(ExerciseVariant.allCases, id: \.self) { variant in
                    Button { model.variant = variant } label: {
                        HStack { VStack(alignment:.leading) { Text(variant.title).font(CoachTypography.section); Text(variant.detail).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary) }; Spacer(); Image(systemName: model.variant == variant ? "checkmark.circle.fill" : "circle").foregroundStyle(CoachColor.mintDark) }
                        .padding().background(CoachColor.surface).clipShape(RoundedRectangle(cornerRadius: CoachRadius.medium)).overlay(RoundedRectangle(cornerRadius: CoachRadius.medium).stroke(model.variant == variant ? CoachColor.mintDark : CoachColor.border))
                    }.buttonStyle(.plain)
                }
                Spacer(); CoachButton(title: "继续", action: model.confirmConfiguration)
            }
          }
        }
    }
}

struct PositioningView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        CoachNavigationScaffold(title: "把手机放在侧面") {
          CoachScreen {
            VStack(spacing: CoachSpacing.lg) {
                ZStack { RoundedRectangle(cornerRadius: CoachRadius.extraLarge).fill(CoachColor.mintSoft); HStack(spacing:36) { Image(systemName:"iphone").font(.system(size:50)); Image(systemName:"arrow.right").foregroundStyle(CoachColor.mintDark); Image(systemName:"figure.stand").font(.system(size:120)) } }.frame(height:310)
                CoachChecklistRow(title:"保持全身可见", detail:"头、双脚和训练凳都要完整入镜")
                CoachChecklistRow(title:"手机与髋部齐平", detail:"距离约 2.5–4 米，保持纯侧面")
                CoachChecklistRow(title:"远离运动路径", detail:"不要把手机放在器械或行走路线内")
                Spacer(); CoachButton(title: "检查机位", systemImage: "camera.viewfinder", action:model.beginPositioning)
            }
          }
        }
    }
}

struct CalibrationView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var camera = CameraService()
    var body: some View {
        ZStack {
            CoachTrainingBackground()
            CameraPreview(session: camera.session).ignoresSafeArea().opacity(0.48)
            VStack(spacing:24) {
                Text("建立你的动作基线").font(.title2.bold())
                Text(model.calibrationMessage).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.8))
                CoachProgressRing(value: Double(model.calibrationProgress) / 3, label: "\(model.calibrationProgress) / 3", detail: "校准动作").frame(width:190,height:190)
                Text("关键点不足时不会记录；三次动作不一致会自动要求重试。")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }.foregroundStyle(.white).padding(30)
        }
        .onAppear {
            camera.observationHandler = { observation in model.receiveCalibration(observation) }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }
}

struct LiveWorkoutView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var camera = CameraService()
    var body: some View {
        ZStack {
            CoachTrainingBackground()
            CameraPreview(session: camera.session).ignoresSafeArea()
            PoseSilhouette().stroke(CoachColor.mint.opacity(0.85), style:StrokeStyle(lineWidth:5,lineCap:.round,lineJoin:.round)).frame(width:270,height:440).offset(y:20)
            if camera.status == .denied {
                ContentUnavailableView("无法使用摄像头", systemImage: "camera.fill", description: Text("请在系统设置中允许摄像头权限后重试。"))
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 20))
            }
            VStack {
                HStack { Button { model.finishWorkout() } label:{ Image(systemName:"xmark") }; Spacer(); Text("保加利亚分腿蹲").font(.caption.bold()).padding(.horizontal,14).padding(.vertical,9).background(.ultraThinMaterial,in:Capsule()); Spacer(); Button { model.speechEnabled.toggle() } label:{ Image(systemName:model.speechEnabled ? "speaker.wave.2" : "speaker.slash") } }.font(.title3)
                HStack(alignment:.firstTextBaseline) { Text("\(model.repCount)").font(.system(size:76,weight:.bold)); Text("次"); Spacer() }.padding(.top,24)
                Spacer()
                if let cue=model.latestCue { CoachLiveCue(message: cue, isSpoken: model.speechEnabled) }
                HStack { Button(action:model.toggleAnalysisPause) { Image(systemName:model.isAnalysisPaused ? "play.fill" : "pause.fill").frame(width:54,height:54).background(.ultraThinMaterial,in:Circle()) }; Spacer(); Button("结束训练",action:model.finishWorkout).foregroundStyle(CoachColor.amber).font(CoachTypography.bodyStrong).padding() }
            }.padding().foregroundStyle(.white)
        }
        .onAppear {
            camera.observationHandler = { observation in await model.receive(observation) }
            camera.start()
        }
        .onDisappear { camera.stop() }
    }
}

struct SummaryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @State private var saveMessage: String?
    private var issues:[IssueEvent] { model.summary.reps.flatMap(\.issues).filter{$0.disposition != .suppressed} }
    var body: some View {
        CoachNavigationScaffold(title: "本组总结") {
          CoachScreen { VStack(spacing:CoachSpacing.md) {
                Text("完成 \(model.summary.effectiveRepCount) 次有效动作").font(.title2.bold()).padding(.top)
                CoachCard(elevated: true) { VStack(alignment:.leading,spacing:CoachSpacing.xs) { Text("核心问题").font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary); Text(issues.isEmpty ? "本组动作稳定" : "躯干前倾 \(issues.filter{$0.type == .torsoCollapse}.count) 次").font(CoachTypography.title).foregroundStyle(issues.isEmpty ? CoachColor.mintDark : CoachColor.amber); Text(issues.isEmpty ? "继续保持当前节奏。" : "下一组先减小幅度，保持躯干稳定。").font(CoachTypography.body) } }
                VStack(spacing:8) { ForEach(model.summary.reps) { rep in Button { model.showRep(rep) } label:{ CoachCard { HStack { Text("第 \(rep.id) 次"); Spacer(); Text(rep.issues.isEmpty ? "稳定" : rep.issues.first!.type.title).foregroundStyle(rep.issues.isEmpty ? CoachColor.mintDark : CoachColor.amber); Image(systemName:"chevron.right") } } }.buttonStyle(.plain) } }
                if let selected=model.selectedRep { ProblemEvidenceView(rep:selected) }
                CoachButton(title: "保存本次摘要", systemImage: "square.and.arrow.down") { do { context.insert(try StoredWorkoutSession(summary:model.summary,config:SessionConfig(trainingSide:model.trainingSide,variant:model.variant,speechEnabled:model.speechEnabled,saveVideo:false))); try context.save(); saveMessage="已保存到本机" } catch { saveMessage="保存失败，请重试" } }
                CoachButton(title: "再做一组", kind: .secondary, action:model.resetWorkout)
                if let saveMessage { Text(saveMessage).font(.caption).foregroundStyle(.secondary) }
          } }
        }
    }
}

struct ProblemEvidenceView: View {
    let rep:RepSummary
    var body:some View { VStack(alignment:.leading,spacing:10) { Text("第 \(rep.id) 次 · 问题证据").font(CoachTypography.section); if let issue=rep.issues.first { Text(issue.type.title).foregroundStyle(CoachColor.amber); Text("置信度 \(Int(issue.confidence*100))% · \(issue.phase.rawValue)").font(CoachTypography.caption).foregroundStyle(CoachColor.onTrainingMuted); ForEach(issue.evidence.sorted(by:{$0.key<$1.key}),id:\.key){CoachEvidenceRow(label:$0.key,value:String(format:"%.2f",$0.value),tone:.coaching)} } }.frame(maxWidth:.infinity,alignment:.leading).padding().background(CoachColor.trainingCanvas,in:RoundedRectangle(cornerRadius:CoachRadius.large)).foregroundStyle(CoachColor.onTraining) }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredWorkoutSession.startedAt, order: .reverse) private var sessions: [StoredWorkoutSession]

    var body: some View {
        CoachNavigationScaffold(title: "训练历史", trailing: { Button("完成", action: model.goHome) }) {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView("还没有训练记录", systemImage: "clock", description: Text("完成训练后可主动保存摘要。"))
                }
                ForEach(sessions) { session in
                    VStack(alignment: .leading) {
                        Text("保加利亚分腿蹲").font(.headline)
                        Text("\(session.repCount) 次 · \(session.issueCount) 个提示 · \(session.startedAt.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        try? SessionDeletionService.delete(sessions[index], context: context)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CoachColor.canvas)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        CoachNavigationScaffold(title: "设置", trailing: { Button("完成", action: model.goHome) }) {
            Form {
                Section("训练反馈") {
                    Toggle("语音提示", isOn: $model.speechEnabled)
                }
                Section("隐私") { Text("训练画面只用于实时本机分析，本版本不会保存视频。") }
                Section("关于") {
                    LabeledContent("规则版本", value: "bss-0.1.0")
                    Text("仅提供一般训练辅助，不替代医疗建议或专业教练。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CoachColor.canvas)
        }
    }
}

struct OnboardingPage: View {
    let icon: String
    let title: String
    let items: [String]
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        CoachScreen(scrolls: false) {
            VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(CoachColor.mintDark)
                    .accessibilityHidden(true)
                Text(title).font(CoachTypography.display)
                CoachCard {
                    VStack(alignment: .leading, spacing: CoachSpacing.md) {
                        ForEach(items, id: \.self) {
                            Label($0, systemImage: "checkmark.circle.fill")
                                .font(CoachTypography.body)
                                .foregroundStyle(CoachColor.textPrimary)
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
                Spacer()
                CoachButton(title: actionTitle, action: action)
            }
        }
    }
}

struct Benefit: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: CoachSpacing.xs) {
            Image(systemName: icon).font(.title3).foregroundStyle(CoachColor.mintDark)
            Text(text).font(CoachTypography.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CoachSpacing.sm)
        .background(CoachColor.surface, in: RoundedRectangle(cornerRadius: CoachRadius.medium))
        .overlay { RoundedRectangle(cornerRadius: CoachRadius.medium).stroke(CoachColor.border) }
    }
}
struct PoseSilhouette:Shape{func path(in r:CGRect)->Path{var p=Path();p.addEllipse(in:CGRect(x:r.midX-22,y:r.minY,width:44,height:44));p.move(to:CGPoint(x:r.midX,y:r.minY+45));p.addLine(to:CGPoint(x:r.midX+8,y:r.minY+180));p.addLine(to:CGPoint(x:r.midX-55,y:r.minY+280));p.addLine(to:CGPoint(x:r.midX-96,y:r.maxY));p.move(to:CGPoint(x:r.midX+8,y:r.minY+180));p.addLine(to:CGPoint(x:r.midX+86,y:r.minY+300));p.addLine(to:CGPoint(x:r.maxX,y:r.minY+340));p.move(to:CGPoint(x:r.midX,y:r.minY+90));p.addLine(to:CGPoint(x:r.midX-45,y:r.minY+190));return p}}

private extension ExerciseVariant {
    var title: String {
        switch self {
        case .general: "一般检查"
        case .gluteBias: "偏臀"
        case .quadBias: "偏股四头肌"
        }
    }

    var detail: String {
        switch self {
        case .general: "平衡观察深度、节奏与躯干稳定"
        case .gluteBias: "允许更大的合理髋主导前倾"
        case .quadBias: "更关注相对直立的躯干控制"
        }
    }
}

private extension IssueType {
    var title: String {
        switch self {
        case .torsoCollapse: "躯干角度不稳定"
        case .insufficientDepth: "深度不足"
        case .fastDescent: "下降过快"
        }
    }
}
