import SwiftUI

// MARK: - Foundations

enum CoachColor {
    static let canvas = Color(red: 0.965, green: 0.976, blue: 0.961)
    static let surface = Color.white
    static let textPrimary = Color(red: 0.105, green: 0.155, blue: 0.145)
    static let textSecondary = Color(red: 0.395, green: 0.445, blue: 0.430)
    static let border = Color(red: 0.902, green: 0.922, blue: 0.904)

    static let mint = Color(red: 0.075, green: 0.690, blue: 0.525)
    static let mintDark = Color(red: 0.035, green: 0.430, blue: 0.335)
    static let mintSoft = Color(red: 0.895, green: 0.970, blue: 0.935)

    static let trainingCanvas = Color(red: 0.025, green: 0.115, blue: 0.100)
    static let trainingSurface = Color(red: 0.055, green: 0.185, blue: 0.160)
    static let onTraining = Color(red: 0.955, green: 0.980, blue: 0.965)
    static let onTrainingMuted = Color(red: 0.690, green: 0.770, blue: 0.740)

    static let amber = Color(red: 0.900, green: 0.620, blue: 0.145)
    static let amberSoft = Color(red: 1.000, green: 0.955, blue: 0.835)
    static let danger = Color(red: 0.825, green: 0.225, blue: 0.155)
    static let dangerSoft = Color(red: 1.000, green: 0.920, blue: 0.900)
    static let info = Color(red: 0.185, green: 0.475, blue: 0.775)
    static let infoSoft = Color(red: 0.900, green: 0.945, blue: 1.000)
}

enum CoachSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

enum CoachRadius {
    static let small: CGFloat = 10
    static let medium: CGFloat = 14
    static let large: CGFloat = 18
    static let extraLarge: CGFloat = 24
    static let capsule: CGFloat = 999
}

enum CoachLayout {
    static let screenHorizontalPadding: CGFloat = 20
    static let compactControlHeight: CGFloat = 44
    static let controlHeight: CGFloat = 52
    static let prominentControlHeight: CGFloat = 58
    static let iconControlSize: CGFloat = 44
    static let readableContentWidth: CGFloat = 560
}

enum CoachTypography {
    static let display = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let title = Font.system(.title2, design: .rounded, weight: .bold)
    static let section = Font.system(.headline, design: .rounded, weight: .semibold)
    static let body = Font.system(.body, design: .default, weight: .regular)
    static let bodyStrong = Font.system(.body, design: .default, weight: .semibold)
    static let label = Font.system(.subheadline, design: .default, weight: .semibold)
    static let caption = Font.system(.caption, design: .default, weight: .regular)
    static let captionStrong = Font.system(.caption, design: .default, weight: .semibold)
    static let metric = Font.system(size: 42, weight: .bold, design: .rounded)
    static let repCounter = Font.system(size: 76, weight: .bold, design: .rounded)
    static let mono = Font.system(.caption, design: .monospaced, weight: .medium)
}

enum CoachMotion {
    static let quick = 0.16
    static let standard = 0.24
    static let deliberate = 0.36

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: standard)
    }
}

private struct CoachSurfaceShadow: ViewModifier {
    let elevated: Bool

    func body(content: Content) -> some View {
        content.shadow(
            color: CoachColor.trainingCanvas.opacity(elevated ? 0.12 : 0.06),
            radius: elevated ? 22 : 10,
            x: 0,
            y: elevated ? 12 : 5
        )
    }
}

extension View {
    func coachSurfaceShadow(elevated: Bool = false) -> some View {
        modifier(CoachSurfaceShadow(elevated: elevated))
    }
}

// MARK: - Semantic status

enum CoachTone {
    case neutral
    case success
    case coaching
    case danger
    case info

    var foreground: Color {
        switch self {
        case .neutral: CoachColor.textSecondary
        case .success: CoachColor.mintDark
        case .coaching: Color(red: 0.48, green: 0.30, blue: 0.02)
        case .danger: CoachColor.danger
        case .info: CoachColor.info
        }
    }

    var background: Color {
        switch self {
        case .neutral: CoachColor.border.opacity(0.55)
        case .success: CoachColor.mintSoft
        case .coaching: CoachColor.amberSoft
        case .danger: CoachColor.dangerSoft
        case .info: CoachColor.infoSoft
        }
    }

    var systemImage: String {
        switch self {
        case .neutral: "minus.circle.fill"
        case .success: "checkmark.circle.fill"
        case .coaching: "exclamationmark.triangle.fill"
        case .danger: "exclamationmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }
}

struct CoachStatusBadge: View {
    let title: String
    var tone: CoachTone = .neutral

    var body: some View {
        Label(title, systemImage: tone.systemImage)
            .font(CoachTypography.captionStrong)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, CoachSpacing.sm)
            .padding(.vertical, CoachSpacing.xs)
            .background(tone.background, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Buttons

enum CoachButtonKind {
    case primary
    case secondary
    case coaching
    case destructive
    case ghost
}

struct CoachButtonStyle: ButtonStyle {
    let kind: CoachButtonKind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CoachTypography.bodyStrong)
            .frame(maxWidth: .infinity)
            .frame(minHeight: CoachLayout.controlHeight)
            .padding(.horizontal, CoachSpacing.md)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: CoachRadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CoachRadius.medium, style: .continuous)
                    .stroke(border, lineWidth: kind == .primary ? 0 : 1)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.42)
            .animation(CoachMotion.animation(reduceMotion: reduceMotion), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary, .ghost: CoachColor.textPrimary
        case .coaching: CoachColor.textPrimary
        case .destructive: CoachColor.danger
        }
    }

    private var background: Color {
        switch kind {
        case .primary: CoachColor.mintDark
        case .secondary: CoachColor.surface
        case .coaching: CoachColor.amber
        case .destructive: CoachColor.dangerSoft
        case .ghost: .clear
        }
    }

    private var border: Color {
        switch kind {
        case .primary: .clear
        case .secondary, .ghost: CoachColor.border
        case .coaching: CoachColor.amber
        case .destructive: CoachColor.danger.opacity(0.45)
        }
    }
}

struct CoachButton: View {
    let title: String
    var systemImage: String?
    var kind: CoachButtonKind = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(CoachButtonStyle(kind: kind))
    }
}

struct CoachIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var foreground: Color = CoachColor.textPrimary
    var background: Color = CoachColor.surface.opacity(0.86)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: CoachLayout.iconControlSize, height: CoachLayout.iconControlSize)
                .foregroundStyle(foreground)
                .background(background, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Surfaces and rows

struct CoachCard<Content: View>: View {
    var padding: CGFloat = CoachSpacing.md
    var elevated = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(CoachColor.surface, in: RoundedRectangle(cornerRadius: CoachRadius.large, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CoachRadius.large, style: .continuous)
                    .stroke(CoachColor.border, lineWidth: 1)
            }
            .coachSurfaceShadow(elevated: elevated)
    }
}

struct CoachSectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
            Text(title).font(CoachTypography.section).foregroundStyle(CoachColor.textPrimary)
            if let detail {
                Text(detail).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct CoachListRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: CoachSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CoachColor.mintDark)
                .frame(width: 36, height: 36)
                .background(CoachColor.mintSoft, in: RoundedRectangle(cornerRadius: CoachRadius.small))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CoachSpacing.xxxs) {
                Text(title).font(CoachTypography.bodyStrong).foregroundStyle(CoachColor.textPrimary)
                if let detail {
                    Text(detail).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                }
            }
            Spacer(minLength: CoachSpacing.sm)
            trailing
        }
        .padding(.vertical, CoachSpacing.xs)
        .contentShape(Rectangle())
    }
}

extension CoachListRow where Trailing == Image {
    init(systemImage: String, title: String, detail: String? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.trailing = Image(systemName: "chevron.right")
    }
}

struct CoachChecklistRow: View {
    let title: String
    let detail: String
    var isComplete = true

    var body: some View {
        CoachCard {
            HStack(spacing: CoachSpacing.sm) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isComplete ? CoachColor.mintDark : CoachColor.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                    Text(title).font(CoachTypography.bodyStrong)
                    Text(detail).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isComplete ? "已满足" : "待完成")
    }
}

struct CoachBanner: View {
    let title: String
    let message: String
    var tone: CoachTone = .info

    var body: some View {
        HStack(alignment: .top, spacing: CoachSpacing.sm) {
            Image(systemName: tone.systemImage)
                .font(.title3)
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CoachSpacing.xxs) {
                Text(title).font(CoachTypography.bodyStrong)
                Text(message).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary)
            }
            Spacer()
        }
        .padding(CoachSpacing.md)
        .background(tone.background, in: RoundedRectangle(cornerRadius: CoachRadius.medium, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Training and result components

struct CoachMetric: View {
    let value: String
    let label: String
    var tone: CoachTone = .neutral

    var body: some View {
        VStack(spacing: CoachSpacing.xxs) {
            Text(value)
                .font(CoachTypography.title)
                .foregroundStyle(tone == .neutral ? CoachColor.textPrimary : tone.foreground)
                .monospacedDigit()
            Text(label)
                .font(CoachTypography.caption)
                .foregroundStyle(CoachColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct CoachMetricRow: View {
    struct Item: Identifiable {
        let id = UUID()
        let value: String
        let label: String
        var tone: CoachTone = .neutral
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                CoachMetric(value: item.value, label: item.label, tone: item.tone)
                if index < items.count - 1 {
                    Divider().frame(height: 42)
                }
            }
        }
        .padding(.vertical, CoachSpacing.sm)
    }
}

struct CoachLiveCue: View {
    let message: String
    var isSpoken = true

    var body: some View {
        HStack(alignment: .top, spacing: CoachSpacing.sm) {
            Image(systemName: isSpoken ? "speaker.wave.2.fill" : "text.bubble.fill")
                .font(.title3)
                .accessibilityHidden(true)
            Text(message)
                .font(CoachTypography.bodyStrong)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(CoachColor.textPrimary)
        .padding(CoachSpacing.md)
        .background(CoachColor.amber, in: RoundedRectangle(cornerRadius: CoachRadius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CoachRadius.large, style: .continuous)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前训练提示，\(message)")
    }
}

struct CoachEvidenceRow: View {
    let label: String
    let value: String
    var tone: CoachTone = .neutral

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CoachSpacing.sm) {
            Text(label).font(CoachTypography.captionStrong).foregroundStyle(CoachColor.textSecondary)
            Spacer()
            Text(value)
                .font(CoachTypography.mono)
                .foregroundStyle(tone == .neutral ? CoachColor.textPrimary : tone.foreground)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

struct CoachProgressRing: View {
    let value: Double
    let label: String
    var detail: String?
    var tone: CoachTone = .success

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tone.foreground, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: CoachSpacing.xxs) {
                Text(label).font(CoachTypography.metric).monospacedDigit()
                if let detail { Text(detail).font(CoachTypography.caption) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("完成百分之 \(Int(value * 100))")
    }
}

struct CoachStepRow: View {
    enum State { case pending, active, complete, failed }
    let title: String
    var detail: String?
    let state: State

    var body: some View {
        HStack(spacing: CoachSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CoachSpacing.xxxs) {
                Text(title).font(CoachTypography.bodyStrong)
                if let detail { Text(detail).font(CoachTypography.caption).foregroundStyle(CoachColor.textSecondary) }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityState)
    }

    private var icon: String {
        switch state {
        case .pending: "circle"
        case .active: "circle.dotted.circle"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .pending: CoachColor.textSecondary
        case .active, .complete: CoachColor.mintDark
        case .failed: CoachColor.danger
        }
    }

    private var accessibilityState: String {
        switch state {
        case .pending: "等待中"
        case .active: "进行中"
        case .complete: "已完成"
        case .failed: "失败"
        }
    }
}

struct CoachEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: CoachSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(CoachColor.mintDark)
                .accessibilityHidden(true)
            Text(title).font(CoachTypography.title).multilineTextAlignment(.center)
            Text(message)
                .font(CoachTypography.body)
                .foregroundStyle(CoachColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CoachSpacing.xxxl)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Page scaffolds

struct CoachScreen<Content: View>: View {
    var scrolls = true
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            CoachColor.canvas.ignoresSafeArea()
            if scrolls {
                ScrollView {
                    content
                        .frame(maxWidth: CoachLayout.readableContentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, CoachLayout.screenHorizontalPadding)
                        .padding(.vertical, CoachSpacing.lg)
                }
            } else {
                content
                    .frame(maxWidth: CoachLayout.readableContentWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, CoachLayout.screenHorizontalPadding)
                    .padding(.vertical, CoachSpacing.lg)
            }
        }
        .foregroundStyle(CoachColor.textPrimary)
    }
}

struct CoachNavigationScaffold<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) where Trailing == EmptyView {
        self.title = title
        self.trailing = EmptyView()
        self.content = content()
    }

    init(title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { trailing }
                }
                .toolbarBackground(CoachColor.canvas.opacity(0.96), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
        .tint(CoachColor.mintDark)
    }
}

struct CoachTrainingBackground: View {
    var body: some View {
        LinearGradient(
            colors: [CoachColor.trainingSurface, CoachColor.trainingCanvas],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#if DEBUG
struct CoachDesignSystemCatalog: View {
    var body: some View {
        CoachNavigationScaffold(title: "Design System") {
            CoachScreen {
                VStack(alignment: .leading, spacing: CoachSpacing.xxl) {
                    catalogSection("按钮", detail: "主操作、次操作、训练建议和破坏性操作") {
                        CoachButton(title: "开始训练", systemImage: "figure.strengthtraining.traditional", action: {})
                        CoachButton(title: "稍后再说", kind: .secondary, action: {})
                        CoachButton(title: "应用到下一组", kind: .coaching, action: {})
                        CoachButton(title: "删除训练记录", systemImage: "trash", kind: .destructive, action: {})
                    }

                    catalogSection("状态", detail: "图标和文字始终与颜色同时出现") {
                        FlowLayout(spacing: CoachSpacing.xs) {
                            CoachStatusBadge(title: "识别中", tone: .success)
                            CoachStatusBadge(title: "需要调整", tone: .coaching)
                            CoachStatusBadge(title: "无法判断", tone: .neutral)
                            CoachStatusBadge(title: "设备异常", tone: .danger)
                        }
                        CoachBanner(title: "画面证据不足", message: "调整机位后再继续，本组已经完成的重复会保留。", tone: .coaching)
                    }

                    catalogSection("训练事实", detail: "计数事实与 AI 解释保持分层") {
                        CoachCard {
                            CoachMetricRow(items: [
                                .init(value: "8", label: "计数重复"),
                                .init(value: "6", label: "稳定", tone: .success),
                                .init(value: "2", label: "问题", tone: .coaching),
                                .init(value: "1", label: "未计数")
                            ])
                        }
                        CoachLiveCue(message: "下一次稳住躯干", isSpoken: true)
                    }

                    catalogSection("流程与恢复", detail: "加载、成功和失败必须有可恢复路径") {
                        CoachCard {
                            VStack(spacing: CoachSpacing.md) {
                                CoachStepRow(title: "准备训练证据", detail: "仅在本机生成", state: .complete)
                                CoachStepRow(title: "生成组后复盘", detail: "可离开此页面", state: .active)
                                CoachStepRow(title: "完成后通知", state: .pending)
                            }
                        }
                        CoachProgressRing(value: 2.0 / 3.0, label: "2 / 3", detail: "校准动作")
                            .frame(width: 180, height: 180)
                            .foregroundStyle(CoachColor.textPrimary)
                    }

                    catalogSection("空状态", detail: "不伪造内容，直接说明下一步") {
                        CoachCard {
                            CoachEmptyState(systemImage: "clock.arrow.circlepath", title: "还没有训练会话", message: "完成并保存第一组训练后，会话会出现在这里。")
                        }
                    }
                }
            }
        }
    }

    private func catalogSection<Content: View>(
        _ title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: CoachSpacing.sm) {
            CoachSectionHeader(title: title, detail: detail)
            content()
        }
    }
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("AI Coach Design System") {
    CoachDesignSystemCatalog()
}
#endif
