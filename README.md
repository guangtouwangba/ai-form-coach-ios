# AI 动作教练 iOS P0

一个隐私优先、端侧运行的动作辅助原型。当前主流程为徒手深蹲：手机侧面拍摄，自动检测站稳、建立静态基线，再识别完整次数。保留旧版分腿蹲历史与核心实现。

> Status: experimental open-source prototype. It has not completed real-device,
> coach-labelled accuracy or App Store release gates.

## 当前能力

- iOS 17 SwiftUI 流程：首页、训练配置、机位引导、自动站稳、实时训练、组后总结、历史和个人中心。
- 实时后置摄像头预览与 latest-frame 丢帧策略；推理落后时不积压旧帧。
- 默认 MediaPipe Pose Landmarker Full，官方 Swift Package 1.1.1 固定提交；Apple Vision 可在诊断页切换对照。
- 显示真实关键点骨架，分别报告无人、多人、弱关节、出画、人物过小、晃动、帧中断等原因。
- 个体尺度归一化、低通滤波、阶段状态机、完整计次、躯干稳定/深度/下降速度规则。
- 置信度门控、单次只说一个最高优先级问题、同类提示冷却、低质量画面暂停分析。
- V3 页面已连接相机、三次真实动作校准、计数、多个问题总结、行动建议和逐次证据，不再用示例次数驱动训练。
- SwiftData 多组会话、本地历史与显式删除；每次完整重复保存结构化草稿，可重启后恢复。默认不录像；显式诊断录像保存在本机，可通过“文件”管理。
- 导入本地录像、逐帧运行真实模型、比较两个引擎的站稳时间与计次、导出诊断报告。
- 切后台、画面质量不足和主动暂停会丢弃半次动作，保留已完成重复；语音关闭仍显示文字提示。

## 快速验证

```bash
./Scripts/verify.sh
```

在 Xcode 中打开 `AIFormCoach.xcodeproj`，选择 `AIFormCoach-Integration` scheme。真机相机、语音和性能验收需要一台 iOS 17+ iPhone，并在 Signing & Capabilities 中选择自己的 Team。

运行核心测试、模拟器构建和 App 集成测试：

```bash
COACH_TEST_SIMULATOR=<你的模拟器UUID> ./Scripts/verify.sh
```

集成测试使用独立临时数据库与合成姿态输入，不访问真实相机，不改已有训练记录。它验证程序流程，不代表实际识别准确率。

MediaPipe 已通过 Xcode 的官方 Swift Package 接入，无需 CocoaPods 或额外编译开关。打开 `AIFormCoach.xcodeproj` 后由 Xcode 解析固定依赖；首次下载体积较大。不要重复添加同名 Pod。当前验证工具链为 Xcode 26.6 / iOS 26.5 Simulator。

真实视频回归与双模型对照说明见 [MediaPipe 验证记录](Docs/Testing/MediaPipe-2026-10-15/README.md)。Mac 可运行共享 Apple Vision 解码器：

```bash
./Scripts/replay-video.sh <本地视频路径> <预期次数> [结果.json]
```

## 重要边界

这不是医疗诊断或专业教练替代品。当前训练主流程只覆盖侧面机位下的徒手深蹲；卧推、3D 几何、多机位和经过教练标注的准确率验证不在 P0 内。

诊断原因描述的是模型与几何检查结果，不能仅凭弱关键点断言是光线、对焦或遮挡造成。Gemini、账号、云同步和订阅未启用。当前属于可开始真机试用的集成版本，尚不具备正式发布验收证据。

本轮集成范围与真机检查表见 [集成验收记录](Docs/INTEGRATION-STATUS.md)。

详见 [实现与测试计划](Docs/IMPLEMENTATION_AND_TEST_PLAN.md) 和 [依赖审计](Docs/DEPENDENCY_AUDIT.md)。

## 后续功能提案

- [手机摄像头杠铃测速与 VBT 分析](Docs/Proposals/BARBELL_VBT.md)：通过实际杠铃片直径标定、视频追踪和时间戳计算杠铃速度，规划逐次分析、速度损失和训练对比。当前仅为功能构思，未实现、未验证精度，不属于现有 P0 能力。

## 开源协作

项目代码采用 [MIT License](LICENSE)。随仓库分发的 MediaPipe 模型保留其
上游许可证，详见 [第三方声明](THIRD_PARTY_NOTICES.md)。提交改进前请阅读
[贡献指南](CONTRIBUTING.md) 与 [安全策略](SECURITY.md)。
