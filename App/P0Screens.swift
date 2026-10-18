import SwiftUI
import SwiftData
import FormCoachCore
import AVFoundation
import AVKit
import UniformTypeIdentifiers

struct P0FlowRootView: View {
    @StateObject private var flow: P0FlowModel
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor init(flow: P0FlowModel? = nil) {
        _flow = StateObject(wrappedValue: flow ?? P0FlowModel())
    }

    var body: some View {
        Group {
            if let screen = flow.current {
                V3ScreenRouter(screen: screen)
                    // Calibration and training change the overlay, not the
                    // underlying camera. Replacing it here causes black frames.
                    .id(flow.needsCamera ? "P0-LIVE-CAMERA" : screen.stateId)
                    .transition(reduceMotion || flow.needsCamera ? .identity : .opacity.combined(with: .move(edge: .trailing)))
                    .preferredColorScheme(screen.isDark ? .dark : .light)
            } else {
                ContentUnavailableView("无法读取页面清单", systemImage: "doc.badge.exclamationmark")
            }
        }
        .environmentObject(flow)
        .task { flow.attach(context) }
        .alert("本机存储提示", isPresented: Binding(get: { flow.saveFailureMessage != nil }, set: { if !$0 { flow.saveFailureMessage = nil } })) {
            Button("知道了") { flow.saveFailureMessage = nil }
        } message: { Text(flow.saveFailureMessage ?? "") }
        .onChange(of: scenePhase) { _, phase in flow.sceneChanged(phase) }
        .onReceive(flow.camera.$status) { flow.cameraStatusChanged($0) }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in flow.tick() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification)) { _ in
            if flow.needsCamera { flow.interrupt(to: "P0-CAMERA-IN-USE") }
        }
        // Live overlays update in place. Implicit insertion/opacity animations
        // can hide unchanged controls when tracking changes state.
        .animation(flow.needsCamera ? nil : CoachMotion.animation(reduceMotion: reduceMotion), value: flow.currentID)
        .sheet(isPresented: $flow.showsReplay) { SquatReplayScreen().environmentObject(flow) }
        .sheet(isPresented: $flow.showsPoseDiagnostics) { PoseDiagnosticsScreen(camera: flow.camera).environmentObject(flow) }
        .sheet(item: $flow.help) { TrainingHelpSheet(topic: $0) }
        .alert("有一份未完成的训练", isPresented: $flow.showsNewTrainingChoice) {
            Button("保存上次训练并新建", action: flow.savePreviousAndBeginNew)
            Button("继续上次训练") { flow.resumeDraft() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("已完成的动作会先保存到训练历史，再开始新训练。未完成的动作不会补计。")
        }
        .sheet(isPresented: $flow.showsStateCatalog) {
            P0StateCatalogView()
                .environmentObject(flow)
        }
    }
}

private struct V3ScreenRouter: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    @ViewBuilder
    var body: some View {
        if flow.needsCamera { V3CameraScreen(screen: screen) }
        else { switch screen.layoutKind {
        case "launch": V3LaunchScreen(screen: screen)
        case "home": V3HomeScreen(screen: screen)
        case "select": V3ExerciseLibraryScreen(screen: screen)
        case "setup": V3SetupScreen(screen: screen)
        case "camera-guide": V3CameraGuideScreen(screen: screen)
        case "camera": V3CameraScreen(screen: screen)
        case "quality": V3QualityScreen(screen: screen)
        case "sheet": V3SheetStateScreen(screen: screen)
        case "summary": V3SummaryScreen(screen: screen)
        case "detail":
            if screen.stateId == "P0-PRIVACY-LOCAL" { CoachPrivacyScreen() }
            else { V3DetailScreen(screen: screen) }
        case "history": V3HistoryScreen(screen: screen)
        case "settings": V3SettingsScreen(screen: screen)
        case "loading": V3LoadingScreen(screen: screen)
        case "a11y": V3AccessibilityScreen(screen: screen)
        case "notice": V3NoticeScreen(screen: screen)
        case "system":
            if screen.isDark {
                V3DarkSystemScreen(screen: screen)
            } else {
                V3NoticeScreen(screen: screen)
            }
        default: V3NoticeScreen(screen: screen)
        } }
    }
}

// MARK: - Shared page pieces

private struct V3LightPage<Content: View>: View {
    let screen: V3ScreenSpec
    var showsBack = true
    @ViewBuilder let content: Content
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        NavigationStack {
            CoachScreen {
                VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                    content
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if ["P0-HISTORY-EMPTY", "P0-HISTORY-SESSIONS"].contains(screen.stateId) {
                    V3TabBar()
                } else {
                VStack(spacing: CoachSpacing.sm) {
                    if ["P0-SUMMARY-CLEAN", "P0-SUMMARY-ISSUES", "P0-HISTORY-GROUP-DETAIL", "P0-SESSION-GROUPS"].contains(screen.stateId), flow.selectedRecord == nil {
                        CoachButton(title: "再做一组", action: flow.startGroup)
                        CoachButton(title: "结束训练并保存", kind: .secondary, action: flow.saveSession)
                    } else if screen.stateId != "P0-HISTORY-SESSION-DETAIL" {
                        V3ActionStack(screen: screen)
                    }
                }
                .disabled(flow.busy)
                .padding(.horizontal, CoachSpacing.lg).padding(.vertical, CoachSpacing.sm)
                .frame(maxWidth: .infinity).background(CoachColor.canvas)
                .overlay(alignment: .top) { Rectangle().fill(CoachColor.border).frame(height: 1) }
                }
            }
            .navigationTitle(screen.displayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsBack && !["P0-HOME", "P0-HISTORY-EMPTY", "P0-HISTORY-SESSIONS"].contains(screen.stateId) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: flow.goBack) { Image(systemName: "chevron.left") }
                            .accessibilityLabel("返回")
                    }
                }
            }
            .toolbarBackground(CoachColor.canvas.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(CoachColor.mintDark)
    }
}

private struct V3PageHeading: View {
    let screen: V3ScreenSpec
    var eyebrow: String? = nil
    var dark = false

    var body: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.sm) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(CoachTypography.captionStrong)
                    .tracking(1.1)
                    .foregroundStyle(dark ? CoachColor.mint : CoachColor.mintDark)
            }
            Text(screen.userSees.title)
                .font(CoachTypography.display)
                .foregroundStyle(dark ? CoachColor.onTraining : CoachColor.textPrimary)
            Text(screen.productDetail)
                .font(CoachTypography.body)
                .foregroundStyle(dark ? CoachColor.onTrainingMuted : CoachColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct V3ActionStack: View {
    let screen: V3ScreenSpec
    var dark = false
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        VStack(spacing: CoachSpacing.sm) {
            if let primary = flow.primaryTitle {
                CoachButton(
                    title: primary,
                    systemImage: primarySymbol,
                    kind: destructivePrimary ? .destructive : (dark ? .coaching : .primary),
                    action: flow.performPrimary
                )
                .disabled(!flow.canPerformPrimary)
            }
            if let secondary = flow.secondaryTitle {
                CoachButton(
                    title: secondary,
                    kind: secondary.contains("删除") ? .destructive : .secondary,
                    action: flow.performSecondary
                )
            }
        }
        .frame(maxWidth: .infinity)
        .disabled(flow.busy)
    }

    private var destructivePrimary: Bool {
        screen.primaryAction?.contains("删除") == true
    }

    private var primarySymbol: String? {
        if destructivePrimary { return "trash" }
        if screen.primaryAction?.contains("设置") == true { return "gearshape" }
        if screen.primaryAction?.contains("重试") == true { return "arrow.clockwise" }
        if screen.primaryAction?.contains("保存") == true { return "square.and.arrow.down" }
        return nil
    }
}

private struct V3StateMeta: View {
    let screen: V3ScreenSpec

    var body: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                Label(screen.entryCondition, systemImage: "arrow.turn.down.right")
                Label(screen.exceptionRecovery, systemImage: "lifepreserver")
                Label(screen.accessibility, systemImage: "accessibility")
            }
            .font(CoachTypography.caption)
            .foregroundStyle(CoachColor.textSecondary)
        }
    }
}

private struct V3TabBar: View {
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        HStack {
            tab("figure.run", "训练", "P0-HOME")
            tab("clock", "历史", flow.savedSessionCount == 0 ? "P0-HISTORY-EMPTY" : "P0-HISTORY-SESSIONS")
            tab("person.crop.circle", "我的", "P0-MY-LOCAL")
        }
        .padding(.horizontal, CoachSpacing.md)
        .padding(.top, CoachSpacing.xs)
        .background(.ultraThinMaterial)
    }

    private func tab(_ icon: String, _ title: String, _ target: String) -> some View {
        Button { flow.selectTab(target) } label: {
            VStack(spacing: CoachSpacing.xxs) {
                Image(systemName: icon).font(.headline)
                Text(title).font(CoachTypography.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(flow.currentID == target ? CoachColor.mintDark : CoachColor.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Entry and setup

private struct V3LaunchScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        ZStack {
            CoachTrainingBackground()
            VStack(spacing: CoachSpacing.xl) {
                Spacer()
                CoachSquatIcon(tint: CoachColor.mint)
                    .frame(width: 76, height: 76)
                    .padding(28)
                    .background(CoachColor.trainingSurface, in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
                Text(screen.userSees.title).font(CoachTypography.display)
                Text("离线动作辅助 · 默认不录像")
                    .font(CoachTypography.body)
                    .foregroundStyle(CoachColor.onTrainingMuted)
                    .multilineTextAlignment(.center)
                Text("实验版本 · 不替代专业教练").font(CoachTypography.caption)
                Spacer()
                CoachButton(title: screen.primaryAction ?? "继续", kind: .coaching, action: flow.performPrimary)
            }
            .foregroundStyle(CoachColor.onTraining)
            .padding(CoachSpacing.xl)
        }
    }
}

private struct V3HomeScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CoachScreen {
                    VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("训练").font(CoachTypography.display)
                            Spacer()
                            Label("仅在本机", systemImage: "lock.shield")
                                .font(CoachTypography.captionStrong).foregroundStyle(CoachColor.textSecondary)
                        }
                        if let draft = flow.draft { resumeCard(draft) }
                        newTrainingCard
                        Button { flow.help = .camera } label: {
                            HStack(alignment: .top, spacing: CoachSpacing.sm) {
                                Image(systemName: "iphone").font(.title2).foregroundStyle(CoachColor.mintDark)
                                VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                                    Text("开始前，摆好手机").font(CoachTypography.bodyStrong)
                                    Text("固定在纯侧面，让头部和双脚完整入镜。")
                                        .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.bold()).padding(.top, 6)
                            }.padding(.vertical, CoachSpacing.xs).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("机位说明：如何摆放手机")
                        VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                            HStack {
                                Text("最近训练").font(CoachTypography.section)
                                Spacer()
                                Button("全部") { openHistory() }.font(CoachTypography.label).frame(minWidth: 44, minHeight: 44)
                            }
                            if let record = flow.records.first {
                                Button { flow.openRecord(record) } label: {
                                    CoachCard {
                                        CoachExerciseRow(exerciseID: record.exerciseID, detail: "\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.repCount) 次")
                                    }
                                }.buttonStyle(.plain)
                            } else {
                                Text("完成并保存后，训练记录会出现在这里。")
                                    .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                            }
                        }
                        Text("画面在本机实时处理，默认不录像。训练辅助不替代专业指导。")
                            .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                    }.disabled(flow.busy)
                }
                V3TabBar()
            }
            .toolbar(.hidden, for: .navigationBar)
        }.tint(CoachColor.mintDark)
    }

    private var newTrainingCard: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.lg) {
            HStack(alignment: .center, spacing: CoachSpacing.sm) {
                VStack(alignment: .leading, spacing: CoachSpacing.xs) {
                    Text(flow.draft == nil ? "今天练这个" : "开始另一场训练")
                        .font(CoachTypography.captionStrong).opacity(0.75)
                    Text("徒手深蹲").font(CoachTypography.title)
                }
                Spacer(minLength: 0)
                CoachSquatIcon(tint: flow.draft == nil ? CoachColor.onTraining : CoachColor.mintDark)
                    .frame(width: 40, height: 40)
            }
            HStack(spacing: CoachSpacing.sm) {
                Label("单人侧面", systemImage: "viewfinder")
                Label("自动站稳检测", systemImage: "checkmark.circle")
            }.font(CoachTypography.captionStrong)
            if flow.draft == nil {
                Text("侧面站稳后开始，记录每一次完整起落。")
                    .font(CoachTypography.body).foregroundStyle(CoachColor.onTrainingMuted)
            }
            CoachButton(title: "开始新训练", systemImage: "plus", kind: flow.draft == nil ? .coaching : .secondary, action: flow.beginNewTraining)
        }
        .padding(CoachSpacing.lg)
        .foregroundStyle(flow.draft == nil ? CoachColor.onTraining : CoachColor.textPrimary)
        .background(flow.draft == nil ? CoachColor.trainingSurface : CoachColor.surface,
                    in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
        .overlay { RoundedRectangle(cornerRadius: CoachRadius.extraLarge).stroke(CoachColor.border.opacity(flow.draft == nil ? 0 : 1)) }
    }

    private func resumeCard(_ draft: LocalTrainingDraft) -> some View {
        VStack(alignment: .leading, spacing: CoachSpacing.md) {
            HStack {
                Text("这次训练还没结束").font(CoachTypography.title)
                Spacer(minLength: 0)
                Image(systemName: "arrow.uturn.forward.circle.fill").font(.title2).foregroundStyle(CoachColor.mint)
            }
            Text("\(draft.exerciseID == "bodyweight_squat" ? "徒手深蹲" : "保加利亚分腿蹲") · \(draft.startedAt.formatted(date: .omitted, time: .shortened))")
                .font(CoachTypography.caption).foregroundStyle(CoachColor.onTrainingMuted)
            HStack(spacing: CoachSpacing.xl) {
                draftMetric("\(draft.active.reps.count)", "次 · 当前组保留")
                draftMetric("\(draft.groups.count)", "组 · 已完成")
            }.padding(.vertical, CoachSpacing.xs)
            CoachButton(title: "继续上次训练", systemImage: "play.fill", kind: .coaching, action: flow.resumeDraft)
        }
        .padding(CoachSpacing.lg).foregroundStyle(CoachColor.onTraining)
        .background(CoachColor.trainingSurface, in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
    }

    private func draftMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
            Text(value).font(CoachTypography.title).monospacedDigit()
            Text(label).font(CoachTypography.caption).foregroundStyle(CoachColor.onTrainingMuted)
        }.accessibilityElement(children: .combine)
    }

    private func openHistory() { flow.selectTab(flow.records.isEmpty ? "P0-HISTORY-EMPTY" : "P0-HISTORY-SESSIONS") }
}

private struct V3ExerciseLibraryScreen: View {
    let screen: V3ScreenSpec

    var body: some View {
        V3LightPage(screen: screen) {
            V3PageHeading(screen: screen, eyebrow: "动作库")
            CoachCard(elevated: true) {
                VStack(alignment: .leading, spacing: CoachSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: CoachRadius.medium).fill(CoachColor.mintSoft)
                        CoachSquatIcon().frame(width: 86, height: 86)
                    }.frame(height: 220)
                    Text("徒手深蹲").font(CoachTypography.title)
                    Text("当前版本唯一开放动作 · 侧面识别").font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                    CoachStatusBadge(title: "可以训练", tone: .success)
                }
            }
            CoachBanner(title: "为什么只有一个动作？", message: "当前优先验证徒手深蹲计次；旧的分腿蹲训练记录仍可查看。", tone: .info)
        }
    }
}

private struct V3SetupScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        V3LightPage(screen: screen) {
            Text("本次训练").font(CoachTypography.display)
            HStack(spacing: CoachSpacing.sm) {
                CoachSquatIcon().frame(width: 28, height: 28)
                Text("徒手深蹲").font(CoachTypography.title)
            }
            if flow.isSquat {
                CoachCard {
                    VStack(alignment: .leading, spacing: CoachSpacing.md) {
                        Label("手机固定在身体侧面", systemImage: "iphone")
                        Label("自然站稳约 2 秒，自动开始计次", systemImage: "figure.stand")
                        Label("开始后完成下蹲与站起，再计为一次", systemImage: "number")
                    }.font(CoachTypography.body)
                }
                SquatTempoPicker(selection: $flow.squatDescentTargetMs).disabled(flow.settingsLocked)
                Text("记录每次动作的幅度与时长。节奏只与本次所选目标比较，不对整体姿势打分。无需器械。")
                    .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
            } else {
            CoachSectionHeader(title: "训练腿", detail: "训练过程中不会自动猜测或切换")
            Picker("训练腿", selection: $flow.trainingSide) {
                Text("左腿").tag("左腿")
                Text("右腿").tag("右腿")
            }.pickerStyle(.segmented).disabled(flow.settingsLocked)
            CoachSectionHeader(title: "训练目标")
            VStack(spacing: CoachSpacing.sm) {
                ForEach(["一般检查", "偏臀", "偏股四头肌"], id: \.self) { goal in
                    Button { flow.trainingGoal = goal } label: {
                        CoachCard {
                            HStack {
                                VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                                    Text(goal).font(CoachTypography.bodyStrong)
                                    Text(goalDetail(goal)).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: flow.trainingGoal == goal ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(CoachColor.mintDark)
                            }
                        }
                    }.buttonStyle(.plain).disabled(flow.settingsLocked)
                }
            }
            }
            Button("如何摆放手机？") { flow.help = .camera }
                .font(CoachTypography.bodyStrong).padding(.vertical, CoachSpacing.sm)
        }
    }

    private func goalDetail(_ goal: String) -> String {
        switch goal {
        case "偏臀": "允许更大的合理髋主导前倾"
        case "偏股四头肌": "更关注相对直立的躯干控制"
        default: "平衡观察深度、节奏与躯干稳定"
        }
    }
}

private struct V3CameraGuideScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        V3LightPage(screen: screen) {
            V3PageHeading(screen: screen, eyebrow: "机位检查")
            ZStack {
                RoundedRectangle(cornerRadius: CoachRadius.extraLarge).fill(CoachColor.mintSoft)
                HStack(spacing: CoachSpacing.xxl) {
                    VStack { Image(systemName: "iphone").font(.system(size: 58)); Text("髋部高度").font(CoachTypography.caption) }
                    Image(systemName: "arrow.right").font(.title).foregroundStyle(CoachColor.mintDark)
                    CoachSquatIcon().frame(width: 80, height: 80)
                }
            }.frame(height: 300)
            CoachChecklistRow(title: "保持全身可见", detail: "头部和双脚都要完整入镜", isComplete: false)
            CoachChecklistRow(title: "手机与髋部齐平", detail: "距离约 2.5–4 米，保持纯侧面", isComplete: false)
            CoachChecklistRow(title: "远离运动路径", detail: "不要把手机放在器械或行走路线内", isComplete: false)
        }
    }
}

// MARK: - Camera, calibration and training

private struct TrainingHelpSheet: View {
    let topic: TrainingHelp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CoachScreen {
                VStack(alignment: .leading, spacing: CoachSpacing.lg) {
                    HStack(spacing: CoachSpacing.sm) {
                        CoachSquatIcon().frame(width: 32, height: 32)
                        Text(topic == .camera ? "把手机放在身体侧面" : "自动建立站立起点").font(CoachTypography.title)
                    }
                    Text(topic == .camera ? "侧面画面用于观察下降深度、节奏和躯干变化。斜前方或正面会影响判断。" : "打开相机后自然站稳约两秒，系统会自动记录起始位置。听到“开始计次”后即可下蹲。")
                    Label("手机与髋部大致齐平，固定在身体纯侧面。", systemImage: "iphone")
                    Label("让头部和双脚完整入镜；保持只有一人。", systemImage: "viewfinder")
                    Label("手机远离器械与行走路径，保证照明充足。", systemImage: "lightbulb")
                    if topic == .camera {
                        Text("摆好机位后，自然站稳").font(CoachTypography.section)
                        Text("保持自然站立，系统自动建立起点；听到开始计次后即可下蹲。移动手机或改变脚的位置后，需要重新站稳。")
                    }
                    if topic == .calibration {
                        Text("肩、髋、膝、踝需要可见。遮挡时不会补计动作；恢复后先回到站立起点。站稳检测不代表动作合格认证。")
                    }
                }.font(CoachTypography.body).foregroundStyle(CoachColor.textPrimary)
            }
            .navigationTitle(topic == .camera ? "机位说明" : "校准说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(CoachColor.mintDark).preferredColorScheme(.light)
    }
}

private struct V3PausedControls: View {
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: CoachSpacing.md) {
                    if flow.currentID == "P0-ABANDON-CONFIRM" {
                        Text("放弃当前这一组？").font(CoachTypography.title)
                        Text("当前组的 \(flow.completedTrainingReps) 次记录将被删除；之前完成的组会保留。此操作无法撤销。")
                        CoachButton(title: "放弃本组", kind: .destructive, action: flow.discardCurrentGroup)
                        CoachButton(title: "返回暂停菜单", kind: .secondary) { flow.navigate(to: "P0-EXIT-MENU") }
                    } else if flow.currentID == "P0-END-SET-CONFIRM", flow.hasActiveGroup {
                        Text("结束本组？").font(CoachTypography.title)
                        Text("保留已完成的 \(flow.completedTrainingReps) 次动作，进入本组总结。")
                        CoachButton(title: "结束本组", action: flow.finishGroup)
                        CoachButton(title: "继续本组", kind: .secondary, action: flow.resumeCurrentGroup)
                    } else {
                        Text(flow.hasActiveGroup ? "训练已暂停" : "校准已暂停").font(CoachTypography.title)
                        Text(flow.hasActiveGroup ? "第 \(flow.nextGroupNumber) 组已保留 \(flow.completedTrainingReps) 次。" : "返回后可以继续准备；未完成的校准需要重新开始。")
                        CoachButton(title: flow.hasActiveGroup ? "继续本组" : "返回校准", action: flow.performPrimary)
                        if flow.hasActiveGroup {
                            CoachButton(title: "结束本组，查看总结", kind: .secondary, action: flow.finishGroup)
                        }
                        CoachButton(title: "稍后继续，返回首页", kind: .secondary, action: flow.leaveWithDraft)
                        if flow.hasActiveGroup {
                            Button("放弃当前组…") { flow.navigate(to: "P0-ABANDON-CONFIRM") }
                                .foregroundStyle(CoachColor.danger).frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            Button("返回训练设置") { flow.navigate(to: "P0-SESSION-SETUP") }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
                .font(CoachTypography.body).foregroundStyle(CoachColor.textPrimary)
                .padding(CoachSpacing.lg).background(CoachColor.canvas, in: RoundedRectangle(cornerRadius: 24))
                .padding(CoachSpacing.lg)
                .disabled(flow.busy)
            }.frame(maxHeight: .infinity, alignment: .center)
            .defaultScrollAnchor(.center)
        }
    }
}

private struct V3CameraStage: View {
    @EnvironmentObject private var flow: P0FlowModel
    var body: some View {
        ZStack {
            Color.black
            CameraPreview(camera: flow.camera)
            if flow.showsSkeleton, let pose = flow.latestPose, !flow.isCameraPaused {
                PoseSkeletonOverlay(observation: pose)
            }
        }.ignoresSafeArea()
    }
}

private struct V3CameraScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel
    @ScaledMetric(relativeTo: .largeTitle) private var counterSize = 64

    var body: some View {
        ZStack {
            V3CameraStage()
            LinearGradient(stops: [.init(color: .black.opacity(0.72), location: 0),
                                   .init(color: .clear, location: 0.30),
                                   .init(color: .clear, location: 0.55),
                                   .init(color: .black.opacity(0.82), location: 1)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                .allowsHitTesting(false)
            if !flow.isCameraPaused {
            VStack(spacing: 0) {
                HStack(spacing: CoachSpacing.sm) {
                    CoachIconButton(systemImage: "xmark", accessibilityLabel: "暂停并查看离开选项", foreground: .white, background: .black.opacity(0.3), action: flow.goBack)
                    Spacer(minLength: 0)
                    VStack(spacing: CoachSpacing.xxs) {
                        Text(cameraStatus).font(CoachTypography.bodyStrong)
                        Text(flow.sessionDescription).font(CoachTypography.caption).foregroundStyle(CoachColor.onTrainingMuted)
                    }.accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    CoachIconButton(systemImage: flow.speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", accessibilityLabel: "切换语音", foreground: .white, background: .black.opacity(0.3)) { flow.speechEnabled.toggle() }
                }
                .padding(.horizontal, CoachSpacing.lg).padding(.top, CoachSpacing.xs)
                HStack {
                    VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                        Text(counterLabel).font(CoachTypography.captionStrong).foregroundStyle(CoachColor.onTrainingMuted)
                        HStack(alignment: .firstTextBaseline, spacing: CoachSpacing.xs) {
                            Text(counterValue).font(.system(size: counterSize, weight: .bold, design: .rounded)).monospacedDigit()
                            Text(isCalibration ? (flow.isSquat ? "%" : "/ 3") : (isReviewWithoutGroup ? "组" : "次")).font(CoachTypography.title).foregroundStyle(CoachColor.onTrainingMuted)
                        }
                    }
                    .padding(CoachSpacing.md).background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: CoachRadius.large))
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                }.padding(.horizontal, CoachSpacing.lg).padding(.top, CoachSpacing.lg)
                Spacer(minLength: CoachSpacing.lg)
                cameraDock
            }
            .foregroundStyle(.white)
            .id(screen.stateId)
            } else { V3PausedControls() }
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private var cameraDock: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.md) {
            Label(flow.trackingMessage, systemImage: "viewfinder")
                .font(CoachTypography.captionStrong).foregroundStyle(CoachColor.onTrainingMuted)
            HStack {
                Text(flow.camera.engineChoice.title).font(CoachTypography.caption)
                Spacer()
                Button("识别诊断") { flow.showsPoseDiagnostics = true }.font(CoachTypography.captionStrong)
            }.foregroundStyle(CoachColor.onTrainingMuted)
            VStack(alignment: .leading, spacing: CoachSpacing.xs) {
                Text(instructionTitle).font(CoachTypography.title)
                    .foregroundStyle(flow.latestCue != nil || screen.stateId == "P0-TRAINING-UNCERTAIN" ? CoachColor.amber : .white)
                    .accessibilityLabel(flow.latestCue == nil ? instructionTitle : "当前训练提示，\(instructionTitle)")
                if let detail = instructionDetail {
                    Text(detail).font(CoachTypography.caption).foregroundStyle(CoachColor.onTrainingMuted)
                }
            }
            cameraActions
        }
        .padding(CoachSpacing.lg)
        .frame(maxWidth: CoachLayout.readableContentWidth)
        .background(CoachColor.trainingCanvas.opacity(0.94), in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
        .overlay { RoundedRectangle(cornerRadius: CoachRadius.extraLarge).stroke(.white.opacity(0.12)) }
        .padding(.horizontal, CoachSpacing.sm).padding(.bottom, CoachSpacing.xs)
    }

    @ViewBuilder private var cameraActions: some View {
        if flow.isSquat && ["P0-CALIBRATION-READY", "P0-CALIBRATION-RUNNING"].contains(screen.stateId) {
            ProgressView(value: flow.standingProgress).tint(CoachColor.mint)
            cameraLink("站稳检测与机位说明") { flow.help = .calibration }
        } else if flow.activeTraining {
            if screen.stateId == "P0-TRAINING-UNCERTAIN" {
                HStack {
                    Image(systemName: "pause.circle.fill")
                    Text("画面恢复稳定后自动继续").font(CoachTypography.captionStrong)
                }.foregroundStyle(CoachColor.amber)
            }
            HStack(spacing: CoachSpacing.sm) {
                CoachButton(title: "结束本组", kind: .coaching) { flow.interrupt(to: "P0-END-SET-CONFIRM") }
                CoachButton(title: "暂停", systemImage: "pause.fill", kind: .trainingSecondary) { flow.interrupt(to: "P0-EXIT-MENU") }
            }.disabled(flow.busy)
        } else {
            if screen.stateId == "P0-CALIBRATION-RUNNING" {
                CoachButton(title: "暂停校准", systemImage: "pause.fill", kind: .trainingSecondary, action: flow.performSecondary)
            } else {
                CoachButton(title: flow.primaryTitle ?? "继续", kind: .coaching, action: flow.performPrimary)
                    .disabled(!flow.canPerformPrimary)
                if screen.stateId == "P0-INTERRUPT-FOREGROUND" {
                    HStack {
                        cameraLink("机位说明") { flow.help = .camera }
                        cameraLink("机位已变，重新校准") { flow.recalibratePreservingCompletedReps() }
                    }
                } else if let title = flow.secondaryTitle {
                    cameraLink(title, action: flow.performSecondary)
                }
            }
        }
    }

    private func cameraLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(CoachTypography.captionStrong)
            .foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 44)
            .disabled(flow.busy)
    }

    private var isCalibration: Bool { screen.stateId.contains("CALIBRATION") }
    private var isReviewWithoutGroup: Bool { screen.stateId == "P0-INTERRUPT-FOREGROUND" && !flow.hasActiveGroup }
    private var counterValue: String {
        if flow.isSquat && isCalibration { return "\(Int(flow.standingProgress * 100))" }
 return isCalibration ? "\(flow.completedCalibrationReps)" : (isReviewWithoutGroup ? "\(flow.groups.count)" : "\(flow.completedTrainingReps)") }
    private var counterLabel: String {
        if flow.isSquat && isCalibration { return "站稳检测" }
 return isCalibration ? "校准动作" : (isReviewWithoutGroup ? "已经完成" : "本组已完成") }
    private var instructionTitle: String {
        if flow.isSquat && isCalibration { return screen.stateId == "P0-CALIBRATION-SUCCESS" ? "已站稳，准备开始" : "自然站立，保持稳定" }

        return switch screen.stateId {
        case "P0-CALIBRATION-READY": "先做三次正常动作"
        case "P0-CALIBRATION-RUNNING": "按平时节奏，完成动作"
        case "P0-CALIBRATION-SUCCESS": "校准完成，准备开始"
        case "P0-INTERRUPT-FOREGROUND": "确认机位后继续"
        case "P0-TRAINING-UNCERTAIN": "请调整机位与照明"
        default: flow.latestCue ?? "保持控制，完成这一组"
        }
    }
    private var instructionDetail: String? {
        if flow.isSquat {
            if flow.squatDescentTargetMs > 0 {
                return "本次目标：下降至少 \(flow.squatDescentTargetMs / 1000) 秒。组后查看节奏与动作记录。"
            }
            return "组后查看幅度、时长与每次尝试；未观察完整的周期不补计。"
        }

        return switch screen.stateId {
        case "P0-CALIBRATION-READY": "先建立本次训练的动作幅度基线。"
        case "P0-CALIBRATION-RUNNING": "仅完整且证据充分的动作计入三次校准。"
        case "P0-CALIBRATION-SUCCESS": "后续各组会沿用本次基线。"
        case "P0-INTERRUPT-FOREGROUND": "机位改变时请重新校准，已完成次数会保留。"
        case "P0-TRAINING-UNCERTAIN": "当前暂停判断，已完成次数会保留。"
        default: flow.latestCue == nil ? "只记录完整动作，休息时可随时暂停。" : "下一次动作留意这条提示。"
        }
    }
    private var cameraStatus: String {
        if flow.isSquat && isCalibration { return screen.stateId == "P0-CALIBRATION-SUCCESS" ? "起点已建立" : "自动站稳检测" }

        return switch screen.stateId {
        case "P0-INTERRUPT-FOREGROUND": "复核机位"
        case "P0-CALIBRATION-READY": "校准准备"
        case "P0-CALIBRATION-RUNNING": "正在校准"
        case "P0-CALIBRATION-SUCCESS": "基线已建立"
        case "P0-TRAINING-UNCERTAIN": "判断已暂停"
        default: "第 \(flow.nextGroupNumber) 组 · 训练中"
        }
    }
}

private struct V3QualityScreen: View {
    let screen: V3ScreenSpec

    var body: some View {
        ZStack {
            CoachTrainingBackground()
            V3CameraStage().opacity(0.55)
            VStack {
                HStack {
                    CoachStatusBadge(title: "画面需要调整", tone: .coaching)
                    Spacer()
                }.padding()
                Spacer()
                VStack(alignment: .leading, spacing: CoachSpacing.md) {
                    Label(screen.userSees.title, systemImage: screen.symbol)
                        .font(CoachTypography.title)
                        .foregroundStyle(CoachColor.amber)
                    Text(screen.userSees.detail).font(CoachTypography.body).foregroundStyle(CoachColor.onTrainingMuted)
                    qualityDiagram
                    V3ActionStack(screen: screen, dark: true)
                }
                .padding(CoachSpacing.lg)
                .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
                .padding(CoachSpacing.md)
            }
        }
    }

    private var qualityDiagram: some View {
        HStack(spacing: CoachSpacing.sm) {
            Image(systemName: issueIcon).font(.title2).foregroundStyle(CoachColor.amber)
            VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                Text(adjustmentTitle).font(CoachTypography.bodyStrong).foregroundStyle(.white)
                Text("判断暂停，不计入错误；画面恢复稳定后自动继续。")
                    .font(CoachTypography.caption).foregroundStyle(CoachColor.onTrainingMuted)
            }
        }
        .padding(CoachSpacing.md)
        .background(CoachColor.trainingSurface, in: RoundedRectangle(cornerRadius: CoachRadius.medium))
    }

    private var issueIcon: String {
        switch screen.stateId {
        case "P0-QUALITY-TOO-NEAR": "arrow.down.right.and.arrow.up.left"
        case "P0-QUALITY-TOO-FAR": "arrow.up.left.and.arrow.down.right"
        case "P0-QUALITY-DARK": "sun.min.fill"
        case "P0-QUALITY-BACKLIGHT": "sun.max.trianglebadge.exclamationmark"
        case "P0-QUALITY-MULTI-PERSON": "person.2.slash"
        case "P0-QUALITY-NOT-SIDE": "rotate.3d"
        default: "viewfinder"
        }
    }

    private var adjustmentTitle: String {
        switch screen.stateId {
        case "P0-QUALITY-TOO-NEAR": "手机向后移动"
        case "P0-QUALITY-TOO-FAR": "手机向前移动"
        case "P0-QUALITY-OUT-OF-FRAME": "让头和双脚完整入镜"
        case "P0-QUALITY-OCCLUDED": "移开遮挡物"
        case "P0-QUALITY-DARK": "增加正面照明"
        case "P0-QUALITY-BACKLIGHT": "避开身后的强光"
        case "P0-QUALITY-NOT-SIDE": "转为纯侧面站位"
        case "P0-QUALITY-WRONG-LEG": "确认当前训练腿"
        case "P0-QUALITY-MULTI-PERSON": "只保留训练者入镜"
        default: "调整拍摄环境"
        }
    }
}

// MARK: - Notices, interruptions and modal states

private struct V3NoticeScreen: View {
    let screen: V3ScreenSpec

    var body: some View {
        V3LightPage(screen: screen, showsBack: screen.stateId != "P0-SAFETY") {
            Spacer(minLength: CoachSpacing.xl)
            Image(systemName: screen.symbol)
                .font(.system(size: 58, weight: .semibold))
                .foregroundStyle(screen.semanticTone.foreground)
                .frame(width: 104, height: 104)
                .background(screen.semanticTone.background, in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
                .accessibilityHidden(true)
            V3PageHeading(screen: screen)
            CoachBanner(title: statusTitle, message: screen.recoveryMessage, tone: screen.semanticTone)
            if screen.stateId == "P0-SAFETY" {
                CoachCard {
                    VStack(spacing: CoachSpacing.md) {
                        safetyRow("不是医疗诊断或专业教练替代品")
                        safetyRow("出现疼痛、眩晕或不适请立即停止")
                        safetyRow("训练视频默认仅在本机处理且不保存")
                        safetyRow("手机必须远离器械和行走路径")
                    }
                }
            }
            Spacer(minLength: CoachSpacing.lg)
        }
    }

    private var statusTitle: String {
        switch screen.semanticTone {
        case .danger: "需要处理"
        case .coaching: "训练已安全暂停"
        case .success: "状态已恢复"
        default: "当前状态"
        }
    }

    private func safetyRow(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill")
            .font(CoachTypography.body)
            .foregroundStyle(CoachColor.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct V3DarkSystemScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        ZStack {
            CoachTrainingBackground()
            V3CameraStage().opacity(0.18)
            VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                HStack {
                    CoachIconButton(systemImage: "chevron.left", accessibilityLabel: "返回", foreground: .white, background: .black.opacity(0.22), action: flow.goBack)
                    Spacer()
                    Text("训练已安全暂停").font(CoachTypography.captionStrong).foregroundStyle(CoachColor.onTrainingMuted)
                    Spacer()
                    EmptyView()
                }
                Spacer()
                Image(systemName: screen.symbol)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(screen.semanticTone == .danger ? CoachColor.danger : CoachColor.amber)
                    .frame(width: 96, height: 96)
                    .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
                V3PageHeading(screen: screen, dark: true)
                if screen.stateId == "P0-INTERRUPT-FOREGROUND" {
                    Text(flow.trackingMessage).font(CoachTypography.bodyStrong)
                }
                CoachBanner(title: "已完成的重复会保留", message: screen.recoveryMessage, tone: screen.semanticTone)
                V3ActionStack(screen: screen, dark: true)
            }
            .padding(CoachSpacing.lg)
            .foregroundStyle(CoachColor.onTraining)
        }
    }
}

private struct V3LoadingScreen: View {
    let screen: V3ScreenSpec

    var body: some View {
        V3LightPage(screen: screen) {
            Spacer(minLength: 80)
            ProgressView().controlSize(.large).tint(CoachColor.mintDark)
                .frame(maxWidth: .infinity)
            V3PageHeading(screen: screen, eyebrow: "仅在本机")
            CoachCard {
                VStack(spacing: CoachSpacing.md) {
                    CoachStepRow(title: "整理训练事实", detail: "重复、问题与证据", state: .complete)
                    CoachStepRow(title: screen.userSees.title, detail: "请保持 App 在前台", state: .active)
                    CoachStepRow(title: "完成", state: .pending)
                }
            }
        }
    }
}

private struct V3SheetStateScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        ZStack(alignment: .bottom) {
            CoachTrainingBackground()
            V3CameraStage().opacity(0.22)
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(alignment: .leading, spacing: CoachSpacing.lg) {
                Image(systemName: screen.symbol).font(.title).foregroundStyle(screen.semanticTone.foreground)
                Text(flow.deletingDraft ? "删除训练草稿？" : "删除这次训练？").font(CoachTypography.display)
                Text(flow.deletingDraft ? "将删除这份未完成训练的草稿，不影响已保存的训练。此操作无法撤销。" : "将删除这次训练的全部组和动作记录。此操作无法撤销。")
                    .font(CoachTypography.body).foregroundStyle(CoachColor.textSecondary)
                V3ActionStack(screen: screen)
            }
            .disabled(flow.busy)
            .padding(CoachSpacing.xl)
            .background(CoachColor.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        }
    }
}

// MARK: - Summaries, detail and local data

private struct V3SummaryScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel
    @State private var showsRepEvidence = false
    @State private var showsIssueDetails = false
    private var order: [IssueType] { [.torsoCollapse, .insufficientDepth, .fastDescent] }
    private var types: [IssueType] {
        order.filter { count($0) > 0 }.sorted {
            count($0) == count($1) ? order.firstIndex(of: $0)! < order.firstIndex(of: $1)! : count($0) > count($1)
        }
    }
    private var repsWithCues: Int { flow.summary.reps.filter { $0.issues.contains { $0.disposition != .suppressed } }.count }
    private var groupNumber: Int? { flow.groups.firstIndex(of: flow.summary).map { $0 + 1 } }
    private var isCompletion: Bool { ["P0-SAVE-SUCCESS", "P0-DELETE-SUCCESS", "P0-SESSION-COMPLETE"].contains(screen.stateId) }

    var body: some View {
        V3LightPage(screen: screen) {
            if isCompletion { completionContent }
            else {
                VStack(alignment: .leading, spacing: CoachSpacing.xs) {
                    Text(groupNumber.map { "第 \($0) 组已结束" } ?? "本组已结束").font(CoachTypography.title)
                    Text(trainingContext).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                }
                CoachCard(padding: CoachSpacing.lg) {
                    HStack(spacing: CoachSpacing.lg) {
                        summaryMetric("\(flow.summary.reps.count)", "次完整动作", tone: CoachColor.textPrimary)
                        if !flow.isSquat {
                            Divider().frame(height: 68)
                            summaryMetric("\(repsWithCues)", "次动作带提示", tone: repsWithCues > 0 ? CoachTone.coaching.foreground : CoachColor.textPrimary)
                        }
                    }
                }
                if flow.summary.reps.isEmpty {
                    if let analysis = flow.summary.squatAnalysis, !analysis.attempts.isEmpty {
                        CoachBanner(title: "本组未计入完整周期", message: "已保留 \(analysis.attempts.count) 次动作尝试。展开下方记录，查看回起情况与中断原因。", tone: .info)
                    } else {
                        CoachBanner(title: "还没有完整动作记录", message: "检查机位与照明，再尝试一次完整动作。没有足够证据时，不生成动作结论。", tone: .info)
                    }
                } else if flow.isSquat {
                    CoachBanner(title: "本组动作已记录", message: "幅度与时长分别记录；有节奏目标时才生成对应提示。未提示不代表整体动作标准。", tone: .info)
                } else if let first = types.first {
                    VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                        Label("下一组先关注", systemImage: "scope").font(CoachTypography.captionStrong).foregroundStyle(CoachTone.coaching.foreground)
                        Text(first.coachCue).font(CoachTypography.title)
                        Text("\(first.coachTitle) · 本组有 \(count(first)) 条提示")
                            .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(CoachSpacing.lg)
                    .background(CoachColor.amberSoft, in: RoundedRectangle(cornerRadius: CoachRadius.large))
                } else {
                    CoachBanner(title: "没有达到阈值的问题提示", message: "未提示不代表动作一定正确；继续保持控制，留意身体感受。", tone: .info)
                }
                if flow.isSquat, let analysis = flow.summary.squatAnalysis {
                    SquatAnalysisSection(analysis: analysis)
                }
                if !types.isEmpty {
                    DisclosureGroup(isExpanded: $showsIssueDetails) {
                        VStack(spacing: CoachSpacing.md) {
                            ForEach(types, id: \.rawValue) { type in
                                HStack(alignment: .top, spacing: CoachSpacing.md) {
                                    VStack(alignment: .leading, spacing: CoachSpacing.xs) {
                                        Text(type.coachTitle).font(CoachTypography.bodyStrong)
                                        Text(type.coachCue).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    Text("\(count(type)) 条").font(CoachTypography.label).foregroundStyle(CoachTone.coaching.foreground)
                                }.padding(.top, CoachSpacing.sm)
                            }
                        }
                    } label: {
                        Text("查看全部提示（\(flow.issues.count) 条）").font(CoachTypography.bodyStrong)
                    }.tint(CoachColor.mintDark).padding(CoachSpacing.md).background(CoachColor.surface, in: RoundedRectangle(cornerRadius: CoachRadius.large))
                }
                if !flow.summary.reps.isEmpty {
                    DisclosureGroup(isExpanded: $showsRepEvidence) {
                        VStack(spacing: 0) {
                            ForEach(flow.summary.reps, id: \.id) { rep in
                                let cueCount = rep.issues.filter { $0.disposition != .suppressed }.count
                                Button { flow.openRep(rep) } label: {
                                    HStack(spacing: CoachSpacing.sm) {
                                        Text("第 \(rep.id) 次").font(CoachTypography.bodyStrong)
                                        Spacer()
                                        Text(flow.isSquat ? "查看周期时间" : (cueCount == 0 ? "无提示记录" : "\(cueCount) 条提示"))
                                            .font(CoachTypography.caption).foregroundStyle(cueCount == 0 ? CoachColor.textSecondary : CoachTone.coaching.foreground)
                                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(CoachColor.textSecondary)
                                    }.frame(minHeight: 52).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("第 \(rep.id) 次，\(cueCount) 条提示")
                                if rep.id != flow.summary.reps.last?.id { Divider() }
                            }
                        }.padding(.top, CoachSpacing.xs)
                    } label: {
                        Text("逐次记录与证据（\(flow.summary.reps.count) 次）").font(CoachTypography.bodyStrong)
                    }.tint(CoachColor.mintDark).padding(CoachSpacing.md).background(CoachColor.surface, in: RoundedRectangle(cornerRadius: CoachRadius.large))
                }
                if flow.selectedRecord == nil {
                    Button { flow.navigate(to: "P0-SESSION-GROUPS") } label: {
                        HStack {
                            Label("查看本次训练的所有组", systemImage: "list.number")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }.font(CoachTypography.label).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(CoachColor.mintDark)
                }
                Text(flow.isSquat ? "未完整观察到的周期不补计；计次结果不代表动作质量评分。" : "完整动作数与问题提示分别统计；未完成的尝试不补计。提示用于训练参考，不是动作合格评分。")
                    .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
            }
        }
    }

    private func count(_ type: IssueType) -> Int { flow.issues.filter { $0.type == type }.count }
    private func summaryMetric(_ value: String, _ title: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
            Text(value).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(tone)
            Text(title).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
    private var trainingContext: String {
        guard let record = flow.selectedRecord else { return flow.sessionDescription }
        if record.exerciseID == "bodyweight_squat" { return "徒手深蹲 · 完整周期计次" }
        let side = record.trainingSide == "left" ? "左腿" : "右腿"
        let goal = record.variant == "gluteBias" ? "偏臀" : (record.variant == "quadBias" ? "偏股四头肌" : "一般检查")
        return "保加利亚分腿蹲 · \(side) · \(goal)"
    }
    private var completionContent: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.xl) {
            Image(systemName: screen.stateId == "P0-DELETE-SUCCESS" ? "trash.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 52)).foregroundStyle(CoachColor.mintDark).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                Text(screen.stateId == "P0-DELETE-SUCCESS" ? "训练记录已删除" : "本次训练已保存").font(CoachTypography.title)
                Text(screen.stateId == "P0-DELETE-SUCCESS" ? "记录已从本机移除，无法撤销。" : "记录保存在本机，可以随时从训练历史查看。")
                    .font(CoachTypography.body).foregroundStyle(CoachColor.textSecondary)
            }
            if screen.stateId != "P0-DELETE-SUCCESS", let record = flow.selectedRecord {
                CoachCard {
                    CoachEvidenceRow(label: "本次完成", value: "\(flow.groups.count) 组 · \(record.repCount) 次动作")
                }
            }
        }.padding(.top, CoachSpacing.lg)
    }
}

private struct V3DetailScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel
    var body: some View {
        V3LightPage(screen: screen) {
            if let rep = flow.selectedRep {
                Text("第 \(rep.id) 次重复").font(CoachTypography.display)
                CoachEvidenceRow(label: "下降时长", value: "\(rep.descentDurationMs) ms")
                CoachEvidenceRow(label: "识别引擎", value: rep.engineVersion)
                ForEach(rep.issues.filter { $0.disposition != .suppressed }) { issue in
                    CoachCard {
                        VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                            Text(issue.type.coachTitle).font(CoachTypography.section)
                            CoachEvidenceRow(label: "置信度（不是准确率）", value: String(format: "%.0f%%", issue.confidence * 100))
                            CoachEvidenceRow(label: "阶段", value: issue.phase.rawValue)
                            ForEach(issue.evidence.keys.sorted(), id: \.self) { key in
                                CoachEvidenceRow(label: key, value: String(format: "%.3f", issue.evidence[key] ?? 0))
                            }
                            Text(issue.type.coachCue).font(CoachTypography.body)
                        }
                    }
                }
                CoachBanner(title: "只展示达到阈值的问题", message: "未展示的问题可能因证据不足被抑制，不代表动作一定正确。", tone: .info)
            } else {
                CoachEmptyState(systemImage: "doc.text", title: "没有重复证据", message: "完成训练后选择具体重复查看。")
            }
        }
    }
}

private struct V3HistoryScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel
    private var listing: Bool { ["P0-HISTORY-EMPTY", "P0-HISTORY-SESSIONS"].contains(screen.stateId) }
    var body: some View {
        V3LightPage(screen: screen) {
            HStack {
                Text(listing ? "训练历史" : "本次训练的各组").font(CoachTypography.display)
                Spacer()
                if !listing, flow.selectedRecord != nil {
                    Menu {
                        Button("删除训练记录", role: .destructive, action: flow.requestDeleteRecord)
                    } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44) }
                    .accessibilityLabel("更多操作")
                }
            }
            if listing {
                if flow.records.isEmpty {
                    CoachEmptyState(systemImage: "clock", title: "还没有训练会话", message: "完成并保存训练后，会话会出现在这里。")
                }
                ForEach(flow.records, id: \.id) { record in
                    Button { flow.openRecord(record) } label: {
                        CoachCard { CoachExerciseRow(exerciseID: record.exerciseID, detail: "\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(record.repCount) 次") }
                    }.buttonStyle(.plain)
                }
                if flow.records.isEmpty { CoachButton(title: "开始新训练", action: flow.beginNewTraining) }
            } else {
                ForEach(Array(flow.groups.enumerated()), id: \.offset) { index, group in
                    Button { flow.openGroup(index) } label: {
                        CoachCard { CoachListRow(systemImage: "list.number", title: "第 \(index + 1) 组",
                            detail: flow.isSquat ? "\(group.reps.count) 次完整周期 · \(group.squatAnalysis.map { "\($0.attempts.count) 次尝试" } ?? "未评价")" : "\(group.reps.count) 次 · \(group.reps.flatMap(\.issues).filter { $0.disposition != .suppressed }.count) 条问题") }
                    }.buttonStyle(.plain)
                }
                if flow.groups.isEmpty { Text("还没有完成的训练组") }
            }
        }
    }
}

private struct V3SettingsScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel
    @State private var showsAbout = false

    var body: some View {
        if screen.stateId == "P0-MY-LOCAL" { profile }
        else { feedbackSettings }
    }

    private var profile: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CoachScreen {
                    VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                        Text("我的").font(CoachTypography.display)
                        trainingOverview
                        VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                            Text("训练偏好").font(CoachTypography.section)
                            CoachCard(padding: 0) {
                                VStack(spacing: 0) {
                                    profileRow("语音与提示", icon: "speaker.wave.2", detail: flow.speechEnabled ? "语音提示已开启" : "语音提示已关闭") {
                                        flow.navigate(to: "P0-SETTINGS")
                                    }
                                    rowDivider
                                    profileRow("录像回放测试", icon: "play.rectangle", detail: "导入本地视频，对照计次结果") { flow.showsReplay = true }
                                    rowDivider
                                    profileRow("机位与校准", icon: "iphone", detail: "了解拍摄位置与校准方法") { flow.help = .camera }
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                            Text("数据与应用").font(CoachTypography.section)
                            CoachCard(padding: 0) {
                                VStack(spacing: 0) {
                                    profileRow("隐私与训练数据", icon: "hand.raised", detail: "查看画面处理与记录保存方式") {
                                        flow.navigate(to: "P0-PRIVACY-LOCAL")
                                    }
                                    rowDivider
                                    profileRow("关于 AI 动作教练", icon: "info.circle") { showsAbout = true }
                                }
                            }
                        }
                        Label("训练记录保存在当前设备", systemImage: "lock.shield")
                            .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                    }
                }
                V3TabBar()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsAbout) { CoachAboutSheet() }
        }.tint(CoachColor.mintDark)
    }

    private var trainingOverview: some View {
        CoachCard {
            VStack(alignment: .leading, spacing: CoachSpacing.md) {
                HStack {
                    Text("训练积累").font(CoachTypography.bodyStrong)
                    Spacer()
                    Button { openHistory() } label: {
                        HStack(spacing: CoachSpacing.xxs) {
                            Text("查看记录")
                            Image(systemName: "chevron.right").font(.caption.bold())
                        }.font(CoachTypography.captionStrong).frame(minHeight: 44)
                    }.accessibilityLabel("查看训练历史")
                }
                HStack(spacing: CoachSpacing.xl) {
                    profileMetric(flow.savedSessionCount, label: "次已保存训练")
                    Rectangle().fill(CoachColor.border).frame(width: 1, height: 36).accessibilityHidden(true)
                    profileMetric(flow.records.reduce(0) { $0 + $1.repCount }, label: "次完整动作")
                }
                Text(flow.records.first.map { "最近训练：\($0.startedAt.formatted(date: .abbreviated, time: .omitted))" }
                     ?? "完成并保存训练后，在这里查看你的积累。")
                    .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
            }
        }
    }

    private func profileMetric(_ value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
            Text(value, format: .number).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
            Text(label).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 60).padding(.trailing, CoachSpacing.md)
    }

    private func profileRow(_ title: String, icon: String, detail: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CoachSpacing.sm) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(CoachColor.mintDark).frame(width: 32, height: 32)
                    .background(CoachColor.mintSoft, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                    Text(title).font(CoachTypography.bodyStrong)
                    if let detail { Text(detail).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary) }
                }
                Spacer(minLength: CoachSpacing.xs)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(CoachColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(CoachColor.textPrimary)
            .padding(.horizontal, CoachSpacing.md).padding(.vertical, CoachSpacing.sm)
            .frame(minHeight: 56).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var feedbackSettings: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("语音提示", isOn: $flow.speechEnabled)
                } header: { Text("训练反馈") } footer: {
                    Text("动作提示通过语音播报。修改会自动保存；关闭语音后，画面上的文字提示仍会显示。")
                }
                Section {
                    LabeledContent("文字提示", value: "始终显示")
                    LabeledContent("动态效果", value: "跟随系统")
                } header: { Text("显示方式") } footer: {
                    Text("动态效果遵循 iPhone 的“减少动态效果”设置。徒手深蹲使用双脚支撑，站稳检测自动完成。")
                }
            }
            .scrollContentBackground(.hidden).background(CoachColor.canvas)
            .navigationTitle("语音与提示").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(action: flow.goBack) { Image(systemName: "chevron.left") }.accessibilityLabel("返回")
            } }
        }.tint(CoachColor.mintDark)
    }

    private func openHistory() {
        flow.selectTab(flow.records.isEmpty ? "P0-HISTORY-EMPTY" : "P0-HISTORY-SESSIONS")
    }
}

private struct CoachAboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "开发版"
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: CoachSpacing.sm) {
                        CoachSquatIcon().frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                            Text("AI 动作教练").font(CoachTypography.section)
                            Text("徒手深蹲训练辅助").font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                        }
                    }.padding(.vertical, CoachSpacing.xs)
                    LabeledContent("版本", value: version)
                }
                Section("关于训练提示") {
                    Text("通过侧面画面自动检测站稳并记录徒手深蹲完整周期，支持本地录像回放测试。")
                    Text("识别结果用于训练参考，不代表动作合格认证，也不替代专业教练或医疗建议。")
                }
            }
            .scrollContentBackground(.hidden).background(CoachColor.canvas)
            .navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.tint(CoachColor.mintDark)
    }
}

private struct CoachPrivacyScreen: View {
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("画面在本机实时处理", systemImage: "lock.shield")
                        .foregroundStyle(CoachColor.mintDark)
                    Text("摄像头画面在本机用于实时动作分析，默认不录像、不上传画面。")
                }
                Section("训练记录") {
                    LabeledContent("已保存训练", value: "\(flow.savedSessionCount) 次")
                    LabeledContent("保存内容", value: "动作次数与提示记录")
                    LabeledContent("存储位置", value: "当前设备")
                    Button {
                        flow.selectTab(flow.records.isEmpty ? "P0-HISTORY-EMPTY" : "P0-HISTORY-SESSIONS")
                    } label: {
                        HStack { Text("管理训练记录"); Spacer(); Image(systemName: "chevron.right").font(.caption.bold()) }
                    }
                }
                Section {
                    Text("在训练历史中打开一条记录，通过右上角的更多操作删除。删除前会再次确认。")
                    Text("录像回放处理主动导入的文件，不写入训练历史；关闭后清理导入副本。识别诊断中主动录制的视频、关键点日志和对比报告会保留在本机，可在“文件 → 我的 iPhone → AI 动作教练 → PoseDiagnostics”中管理或删除。")
                    Text("当前版本不提供账号或跨设备同步。")
                } header: { Text("记录管理") }
            }
            .scrollContentBackground(.hidden).background(CoachColor.canvas)
            .navigationTitle("隐私与训练数据").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) {
                Button(action: flow.goBack) { Image(systemName: "chevron.left") }.accessibilityLabel("返回")
            } }
        }.tint(CoachColor.mintDark)
    }
}

// MARK: - Accessibility states

private struct V3AccessibilityScreen: View {
    let screen: V3ScreenSpec

    var body: some View {
        V3LightPage(screen: screen) {
            V3PageHeading(screen: screen, eyebrow: "无障碍状态")
            CoachBanner(title: accessibilityLabel, message: screen.accessibility, tone: .info)
            Group {
                if screen.stateId.contains("SUMMARY") {
                    CoachCard {
                        VStack(alignment: .leading, spacing: CoachSpacing.md) {
                            Text("本组总结").font(.largeTitle.bold())
                            Text("完成 8 次有效动作").font(.title2)
                            Label("下一组稳住躯干", systemImage: "exclamationmark.triangle.fill").font(.title3.bold())
                        }
                    }
                } else if screen.stateId.contains("HOME") {
                    CoachCard {
                        VStack(alignment: .leading, spacing: CoachSpacing.md) {
                            Text("开始或继续训练会话").font(.largeTitle.bold())
                            Text("所有内容可随辅助字号换行，不横向滚动。")
                            CoachButton(title: "选择训练动作", action: {})
                        }
                    }
                } else {
                    CoachCard {
                        VStack(alignment: .leading, spacing: CoachSpacing.md) {
                            Label("正在识别", systemImage: "viewfinder.circle.fill").font(.title2.bold())
                            Text("状态由图标、标题和文字共同表达。语音关闭时仍显示等价文字提示。")
                                .font(.title3)
                            CoachStatusBadge(title: "计数已暂停", tone: .coaching)
                        }
                    }
                }
            }
            .dynamicTypeSize(.accessibility3)
            V3StateMeta(screen: screen)
        }
    }

    private var accessibilityLabel: String {
        if screen.stateId.contains("VOICEOVER") { return "VoiceOver 阅读顺序" }
        if screen.stateId.contains("REDUCE-MOTION") { return "减少动态效果" }
        if screen.stateId.contains("NONCOLOR") { return "不只依赖颜色" }
        if screen.stateId.contains("VOICE-OFF") { return "等价文字提示" }
        return "最大辅助字号"
    }
}

// MARK: - State catalog

private struct P0StateCatalogView: View {
    @EnvironmentObject private var flow: P0FlowModel
    @Environment(\.dismiss) private var dismiss

    private var grouped: [(String, [V3ScreenSpec])] {
        Dictionary(grouping: flow.screens, by: \.group)
            .sorted { ($0.value.first?.order ?? 0) < ($1.value.first?.order ?? 0) }
            .map { ($0.key, $0.value.sorted { $0.order < $1.order }) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("这里收录 V3 的全部 P0 页面状态。选择任意状态可直接检查页面和恢复动作。")
                        .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                }
                ForEach(grouped, id: \.0) { group, screens in
                    Section(group) {
                        ForEach(screens) { screen in
                            Button {
                                flow.navigate(to: screen.stateId)
                                dismiss()
                            } label: {
                                HStack(spacing: CoachSpacing.sm) {
                                    Image(systemName: screen.symbol).foregroundStyle(CoachColor.mintDark).frame(width: 24)
                                    VStack(alignment: .leading, spacing: CoachSpacing.xxxs) {
                                        Text(screen.name).foregroundStyle(CoachColor.textPrimary)
                                        Text(screen.stateId).font(CoachTypography.mono).foregroundStyle(CoachColor.textSecondary)
                                    }
                                    Spacer()
                                    if flow.currentID == screen.stateId { Image(systemName: "checkmark.circle.fill").foregroundStyle(CoachColor.mintDark) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("P0 页面 · \(flow.screens.count)")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: dismiss.callAsFunction) } }
        }
    }
}

private extension V3ScreenSpec {
    var displayTitle: String {
        switch stateId {
        case "P0-SUMMARY-CLEAN", "P0-SUMMARY-ISSUES", "P0-HISTORY-GROUP-DETAIL": "训练总结"
        case "P0-SESSION-SETUP": "本次设置"
        case "P0-SAVE-SUCCESS", "P0-SESSION-COMPLETE": "保存完成"
        case "P0-HISTORY-SESSIONS", "P0-HISTORY-EMPTY": "训练历史"
        case "P0-HISTORY-SESSION-DETAIL", "P0-SESSION-GROUPS": "本次训练"
        case "P0-REP-DETAIL": "动作记录"
        case "P0-MY-LOCAL": "我的"
        default: name
        }
    }
}

struct SquatTempoPicker: View {
    @Binding var selection: Int
    var body: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.xs) {
            Picker("下降节奏目标", selection: $selection) {
                Text("不设目标，只记录").tag(0)
                Text("下降至少 1 秒").tag(1000)
                Text("下降至少 2 秒").tag(2000)
                Text("下降至少 3 秒").tag(3000)
            }.tint(CoachColor.mintDark)
            Text("这是你选择的练习目标，不是所有深蹲的统一标准。")
                .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
        }
    }
}

struct SquatAnalysisSection: View {
    let analysis: SquatAnalysis
    var seek: ((Int) -> Void)? = nil
    @State private var expanded = false
    private var observed: Int { analysis.attempts.filter { $0.endReason == .returnedToStart }.count }
    private var cues: [MovementAttempt] { analysis.attempts.filter { $0.recommendation != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.md) {
            CoachSectionHeader(title: "动作观察", detail: "\(analysis.attempts.count) 次尝试 · \(observed) 次观察到回起")
            if let first = cues.first, let cue = first.recommendation {
                CoachBanner(title: "下一次先关注", message: cue, tone: .coaching)
            } else {
                Text(analysis.attempts.isEmpty ? "尚无可评价的动作尝试。" : "未生成调整提示；请查看各项是否有目标、是否看得清，不代表整体动作标准。")
                    .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
            }
            DisclosureGroup(isExpanded: $expanded) {
                ForEach(Array(analysis.attempts.enumerated()), id: \.element.id) { index, attempt in
                    CoachCard {
                        VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                            Text("尝试 \(index + 1) · \(attempt.countedRepID.map { "计为第 \($0) 次" } ?? "未计入完整周期")")
                                .font(CoachTypography.bodyStrong)
                            Text(attempt.endReason.title).font(CoachTypography.captionStrong)
                            Text(String(format: "%.1f–%.1f 秒 · 下降约 %.1f 秒", Double(attempt.startMs) / 1000, Double(attempt.endMs) / 1000, Double(attempt.descentDurationMs) / 1000))
                                .font(CoachTypography.caption).monospacedDigit()
                            Text(String(format: "髋部下降 / 站立躯干长：%.2f", attempt.maximumHipDrop))
                                .font(CoachTypography.caption)
                            ForEach(attempt.assessments) { assessment in
                                Text("\(assessment.item.title)：\(assessment.message)")
                                    .font(CoachTypography.caption)
                                    .foregroundStyle(assessment.status == .outsideTarget ? CoachTone.coaching.foreground : CoachColor.textSecondary)
                            }
                            if let seek {
                                Button("定位最低点 · \(Double(attempt.bottomMs) / 1000, specifier: "%.1f") 秒") { seek(attempt.bottomMs) }
                                    .frame(minHeight: 44).font(CoachTypography.label)
                            } else {
                                Text("证据时间：\(Double(attempt.bottomMs) / 1000, specifier: "%.1f") 秒 · 未提供视频回看")
                                    .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                            }
                        }
                    }
                }
            } label: { Text("查看每次尝试与判断依据").font(CoachTypography.bodyStrong) }
                .tint(CoachColor.mintDark)
        }
    }
}

private struct SquatReplayScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var flow: P0FlowModel
    @StateObject private var model = SquatReplayModel()
    @State private var choosingFile = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            CoachScreen {
                VStack(alignment: .leading, spacing: CoachSpacing.lg) {
                    Text("用同一套逻辑检查录像计次").font(CoachTypography.title)
                    Text("选择开头自然站稳约两秒、从侧面拍摄的徒手深蹲录像。支持 3 分钟以内的本地视频，也可导入关键点 JSON。")
                        .font(CoachTypography.body).foregroundStyle(CoachColor.textSecondary)
                    Picker("识别模型", selection: $model.engineChoice) {
                        ForEach(PoseEngineChoice.allCases.filter(\.isAvailable)) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.running)
                    SquatTempoPicker(selection: $model.descentTargetMs).disabled(model.running)
                    if let player = model.player {
                        VideoPlayer(player: player).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: CoachRadius.medium)).id("replay-video")
                        if let time = model.evidenceTimeMs {
                            Text("证据定位：\(Double(time) / 1000, specifier: "%.1f") 秒").font(CoachTypography.captionStrong)
                        }
                    }
                    CoachButton(title: "导入本地录像或关键点", systemImage: "square.and.arrow.down") { choosingFile = true }
                        .disabled(model.running)
                    CoachButton(title: "运行内置测试（预期 3 次）", kind: .secondary, action: model.sample).disabled(model.running)
                    Text("内置测试是合成关键点，用于验证计次流程，不代表真人录像识别效果。")
                        .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                    Text(model.sourceName).font(CoachTypography.captionStrong)
                    if let engine = model.comparingEngine { Text("正在比较：\(engine)").font(CoachTypography.caption) }
                    if let value = model.snapshot {
                        CoachCard {
                            VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                                ProgressView(value: value.progress)
                                Text("\(value.count) 次完整周期").font(CoachTypography.title).monospacedDigit()
                                Text(value.message).font(CoachTypography.body)
                                Text(value.baselineReady ? "站立起点已建立" : "尚未建立站立起点").font(CoachTypography.caption)
                            }
                        }
                    }
                    if let error = model.error { CoachBanner(title: "未能完成分析", message: error, tone: .danger) }
                    if let result = model.summary {
                        if let analysis = result.squatAnalysis {
                            SquatAnalysisSection(analysis: analysis, seek: model.player == nil ? nil : { time in
                                model.seekEvidence(time)
                                withAnimation { scroll.scrollTo("replay-video", anchor: .top) }
                            })
                        }
                        Button("重新分析此文件", action: model.repeatAnalysis).frame(minHeight: 44)
                            .disabled(model.running)
                        if model.player != nil {
                            CoachButton(title: "用同一录像比较两个模型", kind: .secondary, action: model.compareEngines).disabled(model.running)
                        }
                        if result.reps.isEmpty { Text("没有观察到完整周期。请检查开头是否站稳、身体是否完整可见，以及视频是否适合侧面分析。").font(CoachTypography.caption) }
                        ForEach(result.reps) { rep in
                            Text("第 \(rep.id) 次 · \(Double(rep.startMs) / 1000, specifier: "%.1f")–\(Double(rep.endMs) / 1000, specifier: "%.1f") 秒")
                                .font(CoachTypography.body).monospacedDigit()
                        }
                    }
                    if !model.comparisonReports.isEmpty || !model.comparisonErrors.isEmpty {
                        ForEach(model.comparisonReports) { report in
                            CoachCard {
                                VStack(alignment: .leading, spacing: CoachSpacing.xs) {
                                    Text(report.engine).font(CoachTypography.bodyStrong)
                                    Text("\(report.count) 次 · \(report.frames) 帧").font(CoachTypography.title)
                                    Text("可用姿态：\(report.usablePoseFrames) / \(report.frames) 帧").font(CoachTypography.caption)
                                    Text(report.firstStandingMs.map { String(format: "首次站稳：%.1f 秒",Double($0)/1000) } ?? "未完成站稳")
                                    Text(String(format: "推理中位数 %.1f ms · P95 %.1f ms", report.inferenceP50Ms, report.inferenceP95Ms)).font(CoachTypography.caption)
                                    if let top = report.rejectionCounts.filter({ $0.key != "waitingForTop" }).max(by: { $0.value < $1.value }), let reason = PoseFailureReason(rawValue: top.key) {
                                        Text("主要中断：\(reason.message)").font(CoachTypography.caption)
                                    }
                                }
                            }
                        }
                        ForEach(model.comparisonErrors.keys.sorted(), id: \.self) { name in
                            CoachBanner(title: "\(name) 未完成对比", message: model.comparisonErrors[name] ?? "", tone: .danger)
                        }
                        Button("再次对比同一录像", action: model.compareEngines).disabled(model.running)
                        if let url = model.comparisonExportURL { ShareLink("导出本机对比报告", item: url) }
                    }
                    Text("仅在本机处理；回放不计入训练历史。关闭后清理导入副本；主动录制的诊断视频和对比报告保留在本机文件中。")
                        .font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                }
            }
            .navigationTitle("录像回放测试").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { model.cancel(); dismiss() } } }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.movie, .json]) { result in
                switch result {
                case let .success(url): model.importFile(url)
                case let .failure(error): model.error = error.localizedDescription
                }
            }
            .onDisappear { model.cancel() }
            .onAppear {
                if model.sourceName == "尚未选择录像", let url = flow.camera.diagnosticVideoURL { model.importFile(url) }
            }
            }
        }.tint(CoachColor.mintDark).preferredColorScheme(.light)
    }
}
