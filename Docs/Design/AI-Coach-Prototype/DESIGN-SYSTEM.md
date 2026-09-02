# AI 动作教练 SwiftUI Design System

版本：v3.0  
实现文件：`App/DesignSystem.swift`  
设计来源：`brand-spec.md`、`ai-action-coach-prototype-v3.html`

## 1. 设计原则

1. 准备和回顾使用暖白画布；相机、校准和实时训练使用深墨绿沉浸画布。
2. Mint 表示确认、选中、可靠识别和唯一主操作，不作大面积装饰。
3. Amber 表示能够在下一次动作中执行的训练建议，不把普通动作问题画成危险警报。
4. Red 只用于权限、设备、数据删除或不可恢复风险。
5. 颜色从不单独传达状态，必须同时提供图标、标题和可访问名称。
6. 训练中优先远距离可读：计数、识别状态、当前唯一提示、暂停和结束。
7. 端侧事实、AI 解释、不确定内容与下一组建议必须保持独立层级。

## 2. Foundation Tokens

### 颜色

| SwiftUI Token | 角色 |
| --- | --- |
| `CoachColor.canvas` | 准备、设置、总结、历史的暖白背景 |
| `CoachColor.surface` | 卡片和控件表面 |
| `CoachColor.textPrimary` | 主文字 |
| `CoachColor.textSecondary` | 说明、时间和辅助信息 |
| `CoachColor.border` | 卡片与控件边界 |
| `CoachColor.mint` / `mintDark` / `mintSoft` | 主操作、成功和选中 |
| `CoachColor.trainingCanvas` / `trainingSurface` | 相机与训练背景 |
| `CoachColor.onTraining` / `onTrainingMuted` | 深色训练界面文字 |
| `CoachColor.amber` / `amberSoft` | 动作建议和注意状态 |
| `CoachColor.danger` / `dangerSoft` | 设备、权限、删除和不可恢复错误 |
| `CoachColor.info` / `infoSoft` | 中性说明 |

### 间距

`CoachSpacing` 使用 2、4、8、12、16、20、24、32、40 pt 的离散尺度。页面水平边距统一使用 `CoachLayout.screenHorizontalPadding`，不能在页面中随意新建接近值。

### 圆角与尺寸

- 小控件：`CoachRadius.small`（10 pt）。
- 常规按钮：`CoachRadius.medium`（14 pt）。
- 卡片：`CoachRadius.large`（18 pt）。
- 大型视觉容器：`CoachRadius.extraLarge`（24 pt）。
- 常规按钮最小高度：52 pt；图标触控区域：44×44 pt。

### 字体

全部通过 `CoachTypography` 使用系统 Dynamic Type。Display/Title 使用 Rounded 系统设计增强识别，正文保持默认系统字体，证据数字使用等宽字体。禁止用固定字号替代正文样式；远距离训练计数是唯一允许的大型固定展示字号。

### 动效

页面切换使用 `CoachMotion.standard`（0.24 秒）。`RootView` 已跟随 Reduce Motion；新增动画必须同样读取 `accessibilityReduceMotion`，开启时取消位移、缩放和循环装饰动画。

## 3. 语义状态

`CoachTone` 是状态颜色唯一入口：

- `.neutral`：等待、未计数、无法判断。
- `.success`：可靠识别、完成、保存成功。
- `.coaching`：动作建议、需要调整。
- `.danger`：权限、设备、删除或不可恢复错误。
- `.info`：解释性信息。

业务代码不应直接用颜色判断状态。

## 4. 组件目录

### 页面骨架

- `CoachScreen`：暖白页面、统一边距、可读宽度和可选滚动。
- `CoachNavigationScaffold`：统一导航标题、toolbar 背景与 tint。
- `CoachTrainingBackground`：相机、校准和实时训练背景。

### 操作

- `CoachButton`：primary、secondary、coaching、destructive、ghost 五种语义。
- `CoachIconButton`：保证 44 pt 触控区域和强制可访问名称。

每个页面最多一个 `.primary`。删除不能使用 primary；训练建议不能使用 danger。

### 内容与状态

- `CoachCard`：标准内容表面和可选提升阴影。
- `CoachSectionHeader`：分区标题和说明。
- `CoachListRow`：带图标、标题、说明和尾部内容的列表行。
- `CoachChecklistRow`：机位、安全和准备条件。
- `CoachStatusBadge`：紧凑识别/任务状态。
- `CoachBanner`：页面内说明、建议与错误。
- `CoachEmptyState`：历史空态或没有可显示内容。

### 训练与结果

- `CoachMetric` / `CoachMetricRow`：计数、稳定、问题、未计数四类事实。
- `CoachLiveCue`：训练中的唯一当前提示，包含语音或文字语义。
- `CoachEvidenceRow`：证据名称与等宽值。
- `CoachProgressRing`：校准等有限进度。
- `CoachStepRow`：准备、上传、分析、删除等异步步骤。

## 5. 页面映射

| v3 页面类型 | 应使用的基础组件 |
| --- | --- |
| 安全说明、首页、设置 | `CoachScreen`、`CoachCard`、`CoachButton` |
| 机位与校准 | `CoachChecklistRow`、`CoachProgressRing`、`CoachTrainingBackground` |
| 实时训练 | `CoachTrainingBackground`、`CoachStatusBadge`、`CoachLiveCue`、`CoachIconButton` |
| 组总结 | `CoachMetricRow`、`CoachCard`、`CoachEvidenceRow` |
| 空态与恢复 | `CoachEmptyState`、`CoachBanner`、`CoachStepRow` |
| Gemini 组后复盘 | 复用以上组件；不得另建一套视觉语言 |

## 6. 无障碍契约

- 所有触控目标至少 44×44 pt。
- 最大辅助字号下卡片允许增高，页面允许滚动，不截断主要信息。
- 图标按钮必须传入具体的 `accessibilityLabel`。
- 状态组件默认组合图标、标题和说明，避免 VoiceOver 重复朗读。
- 实时提示变化应由页面接入适当的 VoiceOver announcement；语音关闭时 `CoachLiveCue` 仍显示等价文字。
- 成功、警告、错误、无法判断必须同时使用图标和文字。

## 7. 开发规则

1. 页面不得新增局部品牌色、间距、圆角或阴影常量；缺少语义时先扩展 token。
2. 页面使用组件语义，不用颜色编码业务判断。
3. 不为 P1 复制组件；在同一 Design System 上扩展任务状态与数据分层。
4. 每新增一种公共组件，必须加入 `CoachDesignSystemCatalog` 的 Xcode Preview。
5. 修改 token 后，至少检查 360×800、390×844、430×932 和最大 Dynamic Type。

## 8. Xcode 预览

打开 `App/DesignSystem.swift`，选择 `AI Coach Design System` Preview，可集中检查按钮、状态、训练事实、提示、恢复步骤、进度和空状态。

