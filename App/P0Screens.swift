import SwiftUI

struct P0FlowRootView: View {
    @StateObject private var flow = P0FlowModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let screen = flow.current {
                V3ScreenRouter(screen: screen)
                    .id(screen.stateId)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
                    .preferredColorScheme(screen.isDark ? .dark : .light)
            } else {
                ContentUnavailableView("无法读取页面清单", systemImage: "doc.badge.exclamationmark")
            }
        }
        .environmentObject(flow)
        .animation(CoachMotion.animation(reduceMotion: reduceMotion), value: flow.currentID)
        .sheet(isPresented: $flow.showsStateCatalog) {
            P0StateCatalogView()
                .environmentObject(flow)
        }
    }
}

private struct V3ScreenRouter: View {
    let screen: V3ScreenSpec

    @ViewBuilder
    var body: some View {
        switch screen.layoutKind {
        case "launch": V3LaunchScreen(screen: screen)
        case "home": V3HomeScreen(screen: screen)
        case "select": V3ExerciseLibraryScreen(screen: screen)
        case "setup": V3SetupScreen(screen: screen)
        case "camera-guide": V3CameraGuideScreen(screen: screen)
        case "camera": V3CameraScreen(screen: screen)
        case "quality": V3QualityScreen(screen: screen)
        case "sheet": V3SheetStateScreen(screen: screen)
        case "summary": V3SummaryScreen(screen: screen)
        case "detail": V3DetailScreen(screen: screen)
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
        }
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
                    V3ActionStack(screen: screen)
                }
            }
            .navigationTitle(screen.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsBack && screen.stateId != "P0-HOME" {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: flow.goBack) { Image(systemName: "chevron.left") }
                            .accessibilityLabel("返回")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { flow.showsStateCatalog = true } label: { Image(systemName: "square.grid.2x2") }
                        .accessibilityLabel("页面状态目录")
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
            Text(screen.userSees.detail)
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
            if let primary = screen.primaryAction {
                CoachButton(
                    title: primary,
                    systemImage: primarySymbol,
                    kind: destructivePrimary ? .destructive : (dark ? .coaching : .primary),
                    action: flow.performPrimary
                )
            }
            if let secondary = screen.secondaryAction {
                CoachButton(
                    title: secondary,
                    kind: secondary.contains("删除") ? .destructive : .secondary,
                    action: flow.performSecondary
                )
            }
        }
        .frame(maxWidth: .infinity)
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
        Button { flow.navigate(to: target) } label: {
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
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 76, weight: .semibold))
                    .foregroundStyle(CoachColor.mint)
                    .padding(28)
                    .background(CoachColor.trainingSurface, in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
                Text(screen.userSees.title).font(CoachTypography.display)
                Text(screen.userSees.detail)
                    .font(CoachTypography.body)
                    .foregroundStyle(CoachColor.onTrainingMuted)
                    .multilineTextAlignment(.center)
                ProgressView().tint(CoachColor.mint)
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
                    if screen.stateId == "P0-DRAFT-RESUME" {
                        draftContent
                    } else {
                        VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                        V3PageHeading(screen: screen, eyebrow: "PRIVATE · ON DEVICE")
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [CoachColor.trainingSurface, CoachColor.mintDark], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 132, weight: .medium))
                                .foregroundStyle(.white.opacity(0.18))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding()
                            VStack(alignment: .leading, spacing: CoachSpacing.xs) {
                                CoachStatusBadge(title: "端侧识别就绪", tone: .success)
                                Text("保加利亚分腿蹲").font(CoachTypography.title)
                                Text("纯侧面 · 单人 · 视频不保存").font(CoachTypography.caption)
                            }
                            .foregroundStyle(.white)
                            .padding(CoachSpacing.lg)
                        }
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: CoachRadius.extraLarge))

                        V3ActionStack(screen: screen)

                        CoachSectionHeader(title: "本机状态", detail: "数据不会自动上传")
                        CoachCard {
                            VStack(spacing: CoachSpacing.sm) {
                                Button { flow.navigate(to: "P0-DRAFT-RESUME") } label: {
                                    CoachListRow(systemImage: "arrow.uturn.forward", title: "恢复上次训练草稿", detail: "已保留完成的重复")
                                }.buttonStyle(.plain)
                                Divider()
                                Button { flow.navigate(to: flow.savedSessionCount == 0 ? "P0-HISTORY-EMPTY" : "P0-HISTORY-SESSIONS") } label: {
                                    CoachListRow(systemImage: "clock", title: "最近训练", detail: "\(flow.savedSessionCount) 个本地会话")
                                }.buttonStyle(.plain)
                            }
                        }
                        }
                    }
                }
                V3TabBar()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { flow.showsStateCatalog = true } label: { Image(systemName: "square.grid.2x2") }
                }
            }
        }
        .tint(CoachColor.mintDark)
    }

    private var draftContent: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.xl) {
            V3PageHeading(screen: screen, eyebrow: "未完成草稿")
            CoachCard(elevated: true) {
                VStack(alignment: .leading, spacing: CoachSpacing.md) {
                    HStack {
                        CoachStatusBadge(title: "等待恢复", tone: .coaching)
                        Spacer()
                        Text("今天 20:18").font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                    }
                    Text("保加利亚分腿蹲").font(CoachTypography.title)
                    CoachEvidenceRow(label: "训练腿", value: flow.trainingSide)
                    CoachEvidenceRow(label: "训练目标", value: flow.trainingGoal)
                    CoachEvidenceRow(label: "已完成", value: "1 组 · 8 次")
                    CoachEvidenceRow(label: "校准基线", value: "可继续复用", tone: .success)
                }
            }
            CoachBanner(title: "不会自动打开摄像头", message: "恢复前会重新检查权限、机位和画面质量。", tone: .info)
            V3ActionStack(screen: screen)
        }
    }
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
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 86, weight: .medium)).foregroundStyle(CoachColor.mintDark)
                    }.frame(height: 220)
                    Text("保加利亚分腿蹲").font(CoachTypography.title)
                    Text("当前版本唯一开放动作 · 侧面识别").font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                    CoachStatusBadge(title: "可以训练", tone: .success)
                }
            }
            CoachBanner(title: "为什么只有一个动作？", message: "MVP 先把一个动作的校准、识别、反馈与总结做可靠，再扩展动作库。", tone: .info)
        }
    }
}

private struct V3SetupScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        V3LightPage(screen: screen) {
            V3PageHeading(screen: screen, eyebrow: screen.stateId == "P0-NEXT-SET-READY" ? "下一组" : "训练设置")
            CoachSectionHeader(title: "训练腿", detail: "训练过程中不会自动猜测或切换")
            Picker("训练腿", selection: $flow.trainingSide) {
                Text("左腿").tag("左腿")
                Text("右腿").tag("右腿")
            }.pickerStyle(.segmented)
            CoachSectionHeader(title: "本组目标")
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
                    }.buttonStyle(.plain)
                }
            }
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

    var body: some View {
        V3LightPage(screen: screen) {
            V3PageHeading(screen: screen, eyebrow: "机位检查")
            ZStack {
                RoundedRectangle(cornerRadius: CoachRadius.extraLarge).fill(CoachColor.mintSoft)
                HStack(spacing: CoachSpacing.xxl) {
                    VStack { Image(systemName: "iphone").font(.system(size: 58)); Text("髋部高度").font(CoachTypography.caption) }
                    Image(systemName: "arrow.right").font(.title).foregroundStyle(CoachColor.mintDark)
                    Image(systemName: "figure.stand").font(.system(size: 132)).foregroundStyle(CoachColor.mintDark)
                }
            }.frame(height: 300)
            CoachChecklistRow(title: "保持全身可见", detail: "头、双脚和训练凳都要完整入镜")
            CoachChecklistRow(title: "手机与髋部齐平", detail: "距离约 2.5–4 米，保持纯侧面")
            CoachChecklistRow(title: "远离运动路径", detail: "不要把手机放在器械或行走路线内")
        }
    }
}

// MARK: - Camera, calibration and training

private struct V3CameraStage: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.15), CoachColor.trainingCanvas], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "figure.stand")
                    .font(.system(size: 210, weight: .ultraLight))
                    .foregroundStyle(CoachColor.onTraining.opacity(0.3))
                Spacer()
            }
            RoundedRectangle(cornerRadius: CoachRadius.extraLarge)
                .stroke(CoachColor.mint.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                .padding(.horizontal, 46).padding(.vertical, 118)
        }
    }
}

private struct V3CameraScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        ZStack {
            CoachTrainingBackground()
            V3CameraStage().opacity(0.9)
            VStack(spacing: CoachSpacing.md) {
                HStack {
                    CoachIconButton(systemImage: "xmark", accessibilityLabel: "退出", foreground: .white, background: .black.opacity(0.25), action: flow.goBack)
                    Spacer()
                    CoachStatusBadge(title: cameraStatus, tone: screen.semanticTone)
                    Spacer()
                    CoachIconButton(systemImage: flow.speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", accessibilityLabel: "切换语音", foreground: .white, background: .black.opacity(0.25)) { flow.speechEnabled.toggle() }
                }
                .padding(.horizontal, CoachSpacing.lg)
                .padding(.top, CoachSpacing.sm)

                if screen.stateId.contains("CALIBRATION") {
                    Spacer()
                    CoachProgressRing(
                        value: progress,
                        label: "\(flow.completedCalibrationReps) / 3",
                        detail: "校准动作",
                        tone: screen.stateId.contains("INCONSISTENT") ? .coaching : .success
                    )
                    .frame(width: 178, height: 178)
                    .foregroundStyle(.white)
                    Spacer()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: CoachSpacing.xs) {
                        Text("\(flow.completedTrainingReps)").font(CoachTypography.repCounter).monospacedDigit()
                        Text("次").font(CoachTypography.bodyStrong)
                        Spacer()
                    }.padding(.horizontal, CoachSpacing.xl).foregroundStyle(.white)
                    Spacer()
                    if screen.stateId == "P0-TRAINING-COACHING" {
                        CoachLiveCue(message: "下一次稳住躯干", isSpoken: flow.speechEnabled)
                    } else if screen.stateId == "A11Y-VOICE-OFF-TEXT" {
                        CoachLiveCue(message: "下一次稳住躯干", isSpoken: false)
                    } else if screen.stateId == "P0-TRAINING-UNCERTAIN" {
                        CoachBanner(title: "暂时无法可靠判断", message: "计数已暂停。调整机位后会自动继续，已完成的重复不会丢失。", tone: .coaching)
                    }
                }

                VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                    Text(screen.userSees.title).font(CoachTypography.title)
                    Text(screen.userSees.detail).font(CoachTypography.body).foregroundStyle(CoachColor.onTrainingMuted)
                    V3ActionStack(screen: screen, dark: true)
                }
                .padding(CoachSpacing.lg)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
                .padding(.horizontal, CoachSpacing.md).padding(.bottom, CoachSpacing.sm)
            }
            .foregroundStyle(CoachColor.onTraining)
        }
        .dynamicTypeSize(screen.stateId.contains("XXXL") ? .accessibility3 : .large)
    }

    private var progress: Double {
        if screen.stateId == "P0-CALIBRATION-SUCCESS" { return 1 }
        return Double(flow.completedCalibrationReps) / 3
    }

    private var cameraStatus: String {
        if screen.stateId == "P0-TRAINING-COACHING" { return "正在提示" }
        if screen.stateId == "P0-TRAINING-UNCERTAIN" { return "判断暂停" }
        if screen.stateId == "P0-CALIBRATION-SUCCESS" { return "校准完成" }
        return screen.stateId.contains("CALIBRATION") ? "建立基线" : "实时识别"
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
            V3PageHeading(screen: screen, eyebrow: screen.group)
            CoachBanner(title: statusTitle, message: screen.exceptionRecovery, tone: screen.semanticTone)
            if screen.stateId == "P0-SAFETY" {
                CoachCard {
                    VStack(spacing: CoachSpacing.md) {
                        safetyRow("不是医疗诊断或专业教练替代品")
                        safetyRow("出现疼痛、眩晕或不适请立即停止")
                        safetyRow("训练视频默认仅在本机处理且不保存")
                        safetyRow("手机必须远离器械和行走路径")
                    }
                }
            } else {
                V3StateMeta(screen: screen)
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
                    CoachIconButton(systemImage: "square.grid.2x2", accessibilityLabel: "页面状态目录", foreground: .white, background: .black.opacity(0.22)) { flow.showsStateCatalog = true }
                }
                Spacer()
                Image(systemName: screen.symbol)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(screen.semanticTone == .danger ? CoachColor.danger : CoachColor.amber)
                    .frame(width: 96, height: 96)
                    .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: CoachRadius.extraLarge))
                V3PageHeading(screen: screen, eyebrow: screen.group, dark: true)
                CoachBanner(title: "已完成的重复会保留", message: screen.exceptionRecovery, tone: screen.semanticTone)
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

    var body: some View {
        ZStack(alignment: .bottom) {
            CoachTrainingBackground()
            V3CameraStage().opacity(0.22)
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(alignment: .leading, spacing: CoachSpacing.lg) {
                Capsule().fill(CoachColor.border).frame(width: 42, height: 5).frame(maxWidth: .infinity)
                Image(systemName: screen.symbol).font(.title).foregroundStyle(screen.semanticTone.foreground)
                V3PageHeading(screen: screen)
                CoachBanner(title: "已完成的重复不会自动丢失", message: screen.exceptionRecovery, tone: screen.semanticTone)
                V3ActionStack(screen: screen)
            }
            .padding(CoachSpacing.xl)
            .background(CoachColor.canvas, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
        }
    }
}

// MARK: - Summaries, detail and local data

private struct V3SummaryScreen: View {
    let screen: V3ScreenSpec

    var body: some View {
        V3LightPage(screen: screen) {
            VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                CoachStatusBadge(title: summaryStatus, tone: screen.semanticTone)
                V3PageHeading(screen: screen, eyebrow: "本机总结")
            }
            CoachCard(elevated: true) {
                CoachMetricRow(items: [
                    .init(value: "8", label: "有效重复"),
                    .init(value: screen.stateId.contains("CLEAN") ? "8" : "6", label: "稳定", tone: .success),
                    .init(value: screen.stateId.contains("CLEAN") ? "0" : "2", label: "有问题", tone: .coaching)
                ])
            }
            if screen.stateId.contains("ISSUES") || screen.stateId.contains("KEEP-REPS") || screen.stateId.contains("GROUP-DETAIL") {
                CoachCard {
                    VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                        Text("最值得先处理").font(CoachTypography.captionStrong).foregroundStyle(CoachColor.textSecondary)
                        Label("躯干稳定性不足", systemImage: "exclamationmark.triangle.fill")
                            .font(CoachTypography.title).foregroundStyle(CoachColor.amber)
                        Text("第 4、7 次重复达到成立阈值。下一组先保持较小幅度和稳定节奏。")
                            .font(CoachTypography.body).foregroundStyle(CoachColor.textSecondary)
                    }
                }
            } else {
                CoachBanner(title: "动作整体稳定", message: "没有发现达到成立阈值的问题。继续保持当前节奏。", tone: .success)
            }
            CoachSectionHeader(title: "下一步", detail: "最多三条、可以立刻执行")
            CoachChecklistRow(title: "稳住躯干", detail: "下降阶段让肩髋相对关系更稳定")
            CoachChecklistRow(title: "保持节奏", detail: "不要为了追求次数加快下降")
        }
    }

    private var summaryStatus: String {
        if screen.stateId.contains("SUCCESS") || screen.stateId.contains("COMPLETE") { return "已完成" }
        if screen.stateId.contains("CLEAN") { return "本组稳定" }
        return "需要关注"
    }
}

private struct V3DetailScreen: View {
    let screen: V3ScreenSpec

    var body: some View {
        V3LightPage(screen: screen) {
            V3PageHeading(screen: screen, eyebrow: screen.stateId == "P0-PRIVACY-LOCAL" ? "隐私" : "证据")
            if screen.stateId == "P0-PRIVACY-LOCAL" {
                CoachCard(elevated: true) {
                    VStack(spacing: CoachSpacing.md) {
                        privacyRow("摄像头画面", "仅用于实时端侧分析", "不保存")
                        Divider()
                        privacyRow("结构化训练记录", "重复、问题、提示与证据", "本机保存")
                        Divider()
                        privacyRow("网络上传", "核心训练不依赖网络", "无")
                    }
                }
            } else {
                CoachCard(elevated: true) {
                    VStack(alignment: .leading, spacing: CoachSpacing.md) {
                        HStack { Text("第 4 次重复").font(CoachTypography.title); Spacer(); CoachStatusBadge(title: "问题成立", tone: .coaching) }
                        CoachEvidenceRow(label: "问题", value: "躯干稳定性不足", tone: .coaching)
                        CoachEvidenceRow(label: "阶段", value: "下降末段")
                        CoachEvidenceRow(label: "置信度", value: "91%", tone: .coaching)
                        CoachEvidenceRow(label: "躯干变化", value: "+18.4°")
                        CoachEvidenceRow(label: "规则版本", value: "bss-0.1.0")
                    }
                }
                CoachBanner(title: "证据可以追溯", message: "只展示达到成立阈值的问题；不确定帧不会写成动作错误。", tone: .info)
            }
        }
    }

    private func privacyRow(_ title: String, _ detail: String, _ status: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                Text(title).font(CoachTypography.bodyStrong)
                Text(detail).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
            }
            Spacer()
            CoachStatusBadge(title: status, tone: status == "无" || status == "不保存" ? .success : .neutral)
        }
    }
}

private struct V3HistoryScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CoachScreen {
                    VStack(alignment: .leading, spacing: CoachSpacing.xl) {
                        V3PageHeading(screen: screen, eyebrow: "仅保存在本机")
                        if screen.stateId == "P0-HISTORY-EMPTY" || flow.savedSessionCount == 0 {
                            CoachCard { CoachEmptyState(systemImage: "clock", title: "还没有训练会话", message: "完成并保存第一组训练后，会话会出现在这里。") }
                        } else if screen.stateId == "P0-SESSION-GROUPS" {
                            currentSessionGroups
                        } else if screen.stateId.contains("DETAIL") {
                            sessionDetail
                        } else {
                            ForEach(0..<flow.savedSessionCount, id: \.self) { index in
                                Button { flow.navigate(to: "P0-HISTORY-SESSION-DETAIL") } label: {
                                    CoachCard {
                                        CoachListRow(
                                            systemImage: "figure.strengthtraining.traditional",
                                            title: "保加利亚分腿蹲",
                                            detail: index == 0 ? "今天 20:18 · 2 组 · 16 次" : "8 月 30 日 · 1 组 · 8 次"
                                        )
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                        V3ActionStack(screen: screen)
                    }
                }
                if isTopLevel { V3TabBar() }
            }
            .navigationTitle("训练历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isTopLevel {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: flow.goBack) { Image(systemName: "chevron.left") }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { flow.showsStateCatalog = true } label: { Image(systemName: "square.grid.2x2") }
                }
            }
        }.tint(CoachColor.mintDark)
    }

    private var isTopLevel: Bool {
        screen.stateId == "P0-HISTORY-EMPTY" || screen.stateId == "P0-HISTORY-SESSIONS"
    }

    private var sessionDetail: some View {
        VStack(spacing: CoachSpacing.md) {
            CoachCard(elevated: true) {
                CoachMetricRow(items: [
                    .init(value: "2", label: "训练组"),
                    .init(value: "16", label: "有效重复"),
                    .init(value: "3", label: "成立问题", tone: .coaching)
                ])
            }
            Button { flow.navigate(to: "P0-HISTORY-GROUP-DETAIL") } label: {
                CoachCard { CoachListRow(systemImage: "1.circle.fill", title: "第 1 组", detail: "8 次 · 躯干稳定性 2 次") }
            }.buttonStyle(.plain)
            Button { flow.navigate(to: "P0-HISTORY-GROUP-DETAIL") } label: {
                CoachCard { CoachListRow(systemImage: "2.circle.fill", title: "第 2 组", detail: "8 次 · 深度不足 1 次") }
            }.buttonStyle(.plain)
        }
    }

    private var currentSessionGroups: some View {
        VStack(spacing: CoachSpacing.md) {
            CoachCard {
                VStack(alignment: .leading, spacing: CoachSpacing.sm) {
                    Text("会话设置").font(CoachTypography.section)
                    CoachEvidenceRow(label: "动作", value: "保加利亚分腿蹲")
                    CoachEvidenceRow(label: "训练腿", value: flow.trainingSide)
                    CoachEvidenceRow(label: "训练目标", value: flow.trainingGoal)
                    CoachEvidenceRow(label: "校准基线", value: "已建立", tone: .success)
                }
            }
            CoachCard { CoachListRow(systemImage: "1.circle.fill", title: "第 1 组 · 已完成", detail: "8 次 · 2 个成立问题") }
            CoachCard { CoachListRow(systemImage: "2.circle", title: "第 2 组 · 待开始", detail: "沿用当前会话设置") }
        }
    }
}

private struct V3SettingsScreen: View {
    let screen: V3ScreenSpec
    @EnvironmentObject private var flow: P0FlowModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        V3PageHeading(screen: screen, eyebrow: "LOCAL FIRST")
                    }.listRowBackground(Color.clear)
                    if screen.stateId == "P0-MY-LOCAL" {
                        Section("本机内容") {
                            Button { flow.navigate(to: "P0-HISTORY-SESSIONS") } label: {
                                CoachListRow(systemImage: "clock", title: "训练历史", detail: "\(flow.savedSessionCount) 个本地会话")
                            }
                            Button { flow.navigate(to: "P0-SETTINGS") } label: {
                                CoachListRow(systemImage: "slider.horizontal.3", title: "训练设置", detail: "语音、文字与动态效果")
                            }
                            Button { flow.navigate(to: "P0-PRIVACY-LOCAL") } label: {
                                CoachListRow(systemImage: "hand.raised.fill", title: "本地隐私", detail: "画面如何处理和保存")
                            }
                        }
                        Section("产品边界") {
                            Label("没有账号", systemImage: "person.crop.circle.badge.xmark")
                            Label("没有云同步", systemImage: "icloud.slash")
                            Label("没有订阅", systemImage: "creditcard.trianglebadge.exclamationmark")
                        }
                    } else {
                        Section("训练反馈") {
                            Toggle("语音提示", isOn: $flow.speechEnabled)
                            LabeledContent("等价文字", value: "始终显示")
                            LabeledContent("减少动态效果", value: "跟随系统")
                            LabeledContent("默认训练腿", value: flow.trainingSide)
                        }
                        Section("隐私与数据") {
                            Button("本地隐私说明") { flow.navigate(to: "P0-PRIVACY-LOCAL") }
                            LabeledContent("本地会话", value: "\(flow.savedSessionCount)")
                            LabeledContent("视频保存", value: "关闭")
                        }
                        Section("关于") {
                            LabeledContent("规则版本", value: "bss-0.1.0")
                            Text("一般训练辅助，不替代医疗建议或专业教练。")
                        }
                    }
                    Section {
                        V3ActionStack(screen: screen)
                    }.listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(CoachColor.canvas)
                V3TabBar()
            }
            .navigationTitle(screen.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { flow.showsStateCatalog = true } label: { Image(systemName: "square.grid.2x2") }
                }
            }
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
