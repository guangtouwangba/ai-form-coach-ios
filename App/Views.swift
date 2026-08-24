import SwiftUI
import SwiftData
import FormCoachCore

private let mint = Color(red: 0.05, green: 0.72, blue: 0.65)
private let amber = Color(red: 0.96, green: 0.63, blue: 0.10)

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Group {
            switch model.step {
            case .onboarding: SafetyView()
            case .selection: ExerciseSelectionView()
            case .configuration: ConfigurationView()
            case .positioning: PositioningView()
            case .calibration: CalibrationView()
            case .live: LiveWorkoutView()
            case .summary: SummaryView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .animation(.easeInOut(duration: 0.24), value: model.step)
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
        NavigationScaffold(title: "AI 动作教练", trailing: { Button { model.openSettings() } label: { Image(systemName: "gearshape") } }) {
            VStack(spacing: 16) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [Color(red:0.05,green:0.23,blue:0.21), mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "figure.strengthtraining.traditional").font(.system(size: 120)).foregroundStyle(.white.opacity(0.34)).frame(maxWidth: .infinity, alignment: .trailing).padding()
                    VStack(alignment: .leading, spacing: 8) { Text("保加利亚分腿蹲").font(.title2.bold()); Text("侧面拍摄 · 实时语音纠正").font(.subheadline); Label("AI 本地识别 · 隐私保护", systemImage: "lock.shield") .font(.caption).padding(.top, 120) }.foregroundStyle(.white).padding(22)
                }.frame(height: 330).clipShape(RoundedRectangle(cornerRadius: 24))
                HStack { Benefit(icon:"speaker.wave.2", text:"实时纠正"); Benefit(icon:"number", text:"自动计次"); Benefit(icon:"shield", text:"安全优先") }
                PrimaryButton("开始训练", action: model.selectExercise)
                Button("查看历史记录", action: model.openHistory).foregroundStyle(.secondary)
            }.padding()
        }
    }
}

struct ConfigurationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        NavigationScaffold(title: "训练设置") {
            VStack(alignment: .leading, spacing: 24) {
                Text("训练腿").font(.headline)
                Picker("训练腿", selection: $model.trainingSide) { Text("左腿").tag(TrainingSide.left); Text("右腿").tag(TrainingSide.right) }.pickerStyle(.segmented)
                Text("训练目标").font(.headline)
                ForEach(ExerciseVariant.allCases, id: \.self) { variant in
                    Button { model.variant = variant } label: {
                        HStack { VStack(alignment:.leading) { Text(variant.title).font(.headline); Text(variant.detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: model.variant == variant ? "checkmark.circle.fill" : "circle").foregroundStyle(mint) }
                        .padding().background(.background).clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius:16).stroke(model.variant == variant ? mint : .gray.opacity(0.2)))
                    }.buttonStyle(.plain)
                }
                Spacer(); PrimaryButton("继续", action: model.confirmConfiguration)
            }.padding()
        }
    }
}

struct PositioningView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        NavigationScaffold(title: "把手机放在侧面") {
            VStack(spacing: 20) {
                ZStack { RoundedRectangle(cornerRadius:24).fill(Color.gray.opacity(0.08)); HStack(spacing:36) { Image(systemName:"iphone").font(.system(size:50)); Image(systemName:"arrow.right").foregroundStyle(mint); Image(systemName:"figure.stand").font(.system(size:120)) } }.frame(height:310)
                ChecklistRow(title:"保持全身可见", detail:"头、双脚和训练凳都要完整入镜")
                ChecklistRow(title:"手机与髋部齐平", detail:"距离约 2.5–4 米，保持纯侧面")
                ChecklistRow(title:"远离运动路径", detail:"不要把手机放在器械或行走路线内")
                Spacer(); PrimaryButton("检查机位", action:model.beginPositioning)
            }.padding()
        }
    }
}

struct CalibrationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing:24) {
                Text("建立你的动作基线").font(.title2.bold())
                Text("先保持起始姿势，再完成 3 次轻负重动作。校准动作不会被评价。") .multilineTextAlignment(.center).foregroundStyle(.secondary)
                ZStack { Circle().stroke(.white.opacity(0.15), lineWidth:12); Circle().trim(from:0,to:Double(model.calibrationProgress)/3).stroke(mint,style:StrokeStyle(lineWidth:12,lineCap:.round)).rotationEffect(.degrees(-90)); Text("\(model.calibrationProgress) / 3").font(.system(size:40,weight:.bold)) }.frame(width:190,height:190)
                if model.calibrationProgress == 0 { PrimaryButton("开始校准", action:model.runGuidedCalibration) } else { Text(model.calibrationProgress == 3 ? "校准完成" : "动作保持稳定").foregroundStyle(mint).font(.headline) }
            }.foregroundStyle(.white).padding(30)
        }
    }
}

struct LiveWorkoutView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var camera = CameraService()
    var body: some View {
        ZStack {
            LinearGradient(colors:[.black,Color(red:0.04,green:0.11,blue:0.10)],startPoint:.top,endPoint:.bottom).ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea()
            PoseSilhouette().stroke(mint.opacity(0.85), style:StrokeStyle(lineWidth:5,lineCap:.round,lineJoin:.round)).frame(width:270,height:440).offset(y:20)
            VStack {
                HStack { Button { model.finishWorkout() } label:{ Image(systemName:"xmark") }; Spacer(); Text("保加利亚分腿蹲").font(.caption.bold()).padding(.horizontal,14).padding(.vertical,9).background(.ultraThinMaterial,in:Capsule()); Spacer(); Button { model.speechEnabled.toggle() } label:{ Image(systemName:model.speechEnabled ? "speaker.wave.2" : "speaker.slash") } }.font(.title3)
                HStack(alignment:.firstTextBaseline) { Text("\(model.repCount)").font(.system(size:76,weight:.bold)); Text("次"); Spacer() }.padding(.top,24)
                Spacer()
                if let cue=model.latestCue { Label(cue,systemImage:"speaker.wave.2.fill").font(.headline).padding().frame(maxWidth:.infinity).background(.black.opacity(0.55),in:Capsule()).overlay(Capsule().stroke(amber)) }
                HStack { Button { model.liveStatus = .paused("manual") } label:{ Image(systemName:"pause.fill").frame(width:54,height:54).background(.ultraThinMaterial,in:Circle()) }; Spacer(); Button("结束训练",action:model.finishWorkout).foregroundStyle(amber).font(.headline).padding() }
            }.padding().foregroundStyle(.white)
        }
        .onAppear {
            camera.observationHandler = { observation in model.receive(observation) }
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
        NavigationScaffold(title: "本组总结") {
            ScrollView { VStack(spacing:16) {
                Text("完成 \(model.summary.effectiveRepCount) 次有效动作").font(.title2.bold()).padding(.top)
                VStack(alignment:.leading,spacing:8) { Text("核心问题").font(.caption).foregroundStyle(.secondary); Text(issues.isEmpty ? "本组动作稳定" : "躯干前倾 \(issues.filter{$0.type == .torsoCollapse}.count) 次").font(.title3.bold()).foregroundStyle(issues.isEmpty ? mint : amber); Text(issues.isEmpty ? "继续保持当前节奏。" : "下一组先减小幅度，保持躯干稳定。").font(.subheadline) }.frame(maxWidth:.infinity,alignment:.leading).padding().background(.background,in:RoundedRectangle(cornerRadius:18)).shadow(color:.black.opacity(0.06),radius:12)
                VStack(spacing:8) { ForEach(model.summary.reps) { rep in Button { model.showRep(rep) } label:{ HStack { Text("第 \(rep.id) 次"); Spacer(); Text(rep.issues.isEmpty ? "稳定" : rep.issues.first!.type.title).foregroundStyle(rep.issues.isEmpty ? mint : amber); Image(systemName:"chevron.right") }.padding().background(Color.gray.opacity(0.07),in:RoundedRectangle(cornerRadius:13)) }.buttonStyle(.plain) } }
                if let selected=model.selectedRep { ProblemEvidenceView(rep:selected) }
                PrimaryButton("保存本次摘要") { do { context.insert(try StoredWorkoutSession(summary:model.summary,config:SessionConfig(trainingSide:model.trainingSide,variant:model.variant,speechEnabled:model.speechEnabled,saveVideo:false))); try context.save(); saveMessage="已保存到本机" } catch { saveMessage="保存失败，请重试" } }
                Button("再做一组",action:model.resetWorkout).buttonStyle(.bordered).tint(mint)
                if let saveMessage { Text(saveMessage).font(.caption).foregroundStyle(.secondary) }
            }.padding() }
        }
    }
}

struct ProblemEvidenceView: View {
    let rep:RepSummary
    var body:some View { VStack(alignment:.leading,spacing:10) { Text("第 \(rep.id) 次 · 问题证据").font(.headline); if let issue=rep.issues.first { Text(issue.type.title).foregroundStyle(amber); Text("置信度 \(Int(issue.confidence*100))% · \(issue.phase.rawValue)").font(.caption).foregroundStyle(.secondary); ForEach(issue.evidence.sorted(by:{$0.key<$1.key}),id:\.key){Text("\($0.key)：\(String(format:"%.2f",$0.value))").font(.caption.monospaced())} } }.frame(maxWidth:.infinity,alignment:.leading).padding().background(Color.black.opacity(0.92),in:RoundedRectangle(cornerRadius:18)).foregroundStyle(.white) }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.modelContext) private var context
    @Query(sort: \StoredWorkoutSession.startedAt, order: .reverse) private var sessions: [StoredWorkoutSession]

    var body: some View {
        NavigationScaffold(title: "训练历史", trailing: { Button("完成", action: model.goHome) }) {
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
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationScaffold(title: "设置", trailing: { Button("完成", action: model.goHome) }) {
            Form {
                Section("训练反馈") {
                    Toggle("语音提示", isOn: $model.speechEnabled)
                }
                Section("隐私") {
                    Toggle("保存训练视频", isOn: $model.saveVideo)
                    Text("默认关闭。视频只保存在本机应用容器中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("关于") {
                    LabeledContent("规则版本", value: "bss-0.1.0")
                    Text("仅提供一般训练辅助，不替代医疗建议或专业教练。")
                }
            }
        }
    }
}

struct NavigationScaffold<Content: View>: View {
    let title: String
    let trailing: AnyView
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = AnyView(EmptyView())
        self.content = content()
    }

    init<Trailing: View>(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { trailing } }
        }
    }
}
struct OnboardingPage:View{let icon:String;let title:String;let items:[String];let actionTitle:String;let action:()->Void;var body:some View{VStack(alignment:.leading,spacing:24){Spacer();Image(systemName:icon).font(.system(size:70)).foregroundStyle(mint);Text(title).font(.largeTitle.bold());ForEach(items,id:\.self){Label($0,systemImage:"checkmark.circle.fill").font(.body).foregroundStyle(.primary).labelStyle(.titleAndIcon)};Spacer();PrimaryButton(actionTitle,action:action)}.padding(28)}}
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: [mint, Color(red: 0, green: 0.82, blue: 0.72)], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16)
                )
        }
        .buttonStyle(.plain)
    }
}
struct Benefit:View{let icon:String;let text:String;var body:some View{VStack{Image(systemName:icon).font(.title3).foregroundStyle(mint);Text(text).font(.caption2)}.frame(maxWidth:.infinity).padding(.vertical,14).background(.background,in:RoundedRectangle(cornerRadius:16)).shadow(color:.black.opacity(0.05),radius:8)}}
struct ChecklistRow:View{let title:String;let detail:String;var body:some View{HStack{Image(systemName:"checkmark.circle.fill").foregroundStyle(mint).font(.title2);VStack(alignment:.leading){Text(title).font(.headline);Text(detail).font(.caption).foregroundStyle(.secondary)};Spacer()}.padding().background(.background,in:RoundedRectangle(cornerRadius:16)).shadow(color:.black.opacity(0.05),radius:8)}}
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
