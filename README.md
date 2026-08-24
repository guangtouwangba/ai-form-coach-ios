# AI 动作教练 iOS P0

一个隐私优先、端侧运行的保加利亚分腿蹲动作辅助原型。手机侧面拍摄后，应用实时提取人体关键点、识别动作阶段和完整次数，并在高置信度问题出现时给出简短中文语音提示。

## 当前能力

- iOS 17 SwiftUI 流程：安全说明、动作配置、机位引导、三次校准引导、实时训练、组后总结、历史和设置。
- 实时后置摄像头预览与 latest-frame 丢帧策略；推理落后时不积压旧帧。
- 默认 Apple Vision 2D 姿态适配器，可在当前 Xcode 15.4 上编译。
- MediaPipe Pose Landmarker 1.0 适配器和模型已纳入源码，使用 Xcode 26 时可选择启用。
- 个体尺度归一化、低通滤波、阶段状态机、完整计次、躯干稳定/深度/下降速度规则。
- 置信度门控、单次只说一个最高优先级问题、同类提示冷却、低质量画面暂停分析。
- SwiftData 本地摘要与显式删除；视频默认不保存。

## 快速验证

```bash
./Scripts/verify.sh
```

在 Xcode 15.4 上，直接打开 `AIFormCoach.xcodeproj`。真机相机、语音和性能验收需要一台 iOS 17+ iPhone。

启用 MediaPipe（要求当前 Apple 工具链；面向 2026 App Store 发布建议 Xcode 26）：

```bash
ENABLE_MEDIAPIPE=1 LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 pod install
```

然后在 App target 的 `SWIFT_ACTIVE_COMPILATION_CONDITIONS` 添加 `MEDIAPIPE_ENABLED`，通过生成的 workspace 构建。

## 重要边界

这不是医疗诊断或专业教练替代品。当前规则只覆盖纯侧面机位下的保加利亚分腿蹲；卧推、3D 几何、多机位和经过教练标注的准确率验证不在 P0 内。

详见 [实现与测试计划](Docs/IMPLEMENTATION_AND_TEST_PLAN.md) 和 [依赖审计](Docs/DEPENDENCY_AUDIT.md)。
