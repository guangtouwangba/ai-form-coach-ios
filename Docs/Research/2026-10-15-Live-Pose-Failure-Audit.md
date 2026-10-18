# 拍屏实时识别失败：当前实现审计

2026-10-15。用户反馈修复后实际拍屏仍持续显示关键点不足或未找到人；尚未完成站稳，不能将其归为完整动作计次漏计。当前未取得这次失败输入的关键点/原始画面，所以不能确定是姿态模型没有检出，还是质量与取景规则拒绝。

## 已核实的当前实现

后置广角相机，720p 采集、竖屏方向设置 → Apple Vision `VNDetectHumanBodyPoseRequest` revision 1 → 从结果提取 9 个点 → `SquatFeatures` 的置信度及几何门槛 → `StaticStandingDetector` 连续约 2 秒站稳 → `SquatSession` 根据髋下降、膝屈曲、回升及回到起点计次。检测是端侧机器学习模型；站稳和计次是手写规则，尚无专门训练的动作时序模型。

`CameraService` 实际走 `AppleVisionPosePerception`。工程有 `pose_landmarker_full.task` 资源和条件编译适配器，但没有启用 `MEDIAPIPE_ENABLED`，也没有引入 MediaPipeTasksVision 运行时依赖，因此不能把已有模型文件算作已接入 MediaPipe。

## 对这次失败的相关发现

- Vision 结果数不是 1 时统一输出空关键点，无法从上层区分无人、多人和误检。
- 特征提取将点缺失、置信度不足、出框、人物比例过小、几何不合理统一变成 nil，上层只有泛化提示。当前还要求躯干长度大于图像高度的 8%、同侧肩到踝的纵向距离大于 25%；这些是工程门槛，不是适用于所有拍屏场景的已标定标准。
- 模型直接处理整帧；当前没有目标人物 ROI 裁切/放大，也没有显示骨架和采集图像到 aspect-fill 预览的坐标变换。
- 实时输入是单帧 Vision 请求；后处理有稳定性窗口，但没有显式关键点时间滤波。短时证据不足会清空站稳窗口；帧间隔超过 250ms 也会重置。离线视频顺序处理保留全部源时间帧，不能覆盖实时采样和丢帧问题。
- 前轮正例开头 3 秒是冻结帧，同一动作循环 5 次。这能证明固定输入回归通过，不能证明重新拍屏后的点抖动、取景占比和真人站立均可用。测试数量也不能代替该场景的实际验收。

以上是代码事实或验证边界，不是已确定的本次根因。不能仅凭“原片动作标准”断定模型应能稳定识别重拍画面，也不能把失败直接归咎于用户拍摄；产品应明确指出缺失证据。

## 建议方案

先补齐输入证据：骨架叠加、检测人数、目标占比、每个必要点的置信度、有效输入频率/最大间隔、站稳拒绝原因。将实际失败的手机输入留为固定回归，与原片分开保存，禁止再用原片通过代替拍屏通过。

MediaPipe Pose Landmarker Full 是优先对照候选。它有 iOS 实时流接口、33 点、归一化坐标和 world landmarks，视频/实时模式支持跟踪。官方资料不证明它在本项目条件下必然优于 Apple Vision。用同一批手机实际输入比较关键点可用率、抖动、推理耗时、站稳成功率、计数误差，结果决定默认引擎。

接入前必须修现有备用适配器的这些问题：

1. 返回真实方向校正后的图像宽高，不能沿用 `PoseObservation` 默认的 1×1，否则恢复宽高比几何错误。
2. 初始化失败应可恢复，不使用 `try!`；实时任务必须处理取消、丢帧及回调生命周期。
3. `numPoses=1` 不能证明画面只有一个人；另行设计多目标发现及目标身份保持。
4. 现场相机、导入视频和本地验证应显式选择同一模型版本及各自正确的运行模式。仅切换 CameraService 而回放仍默认 Vision 不是同模型验证。
5. 模型的 confidence/visibility/presence 不混用，重新定义模型各自的可用性策略；输出关键点数量更多不等于站稳或计次自然正确。

本次仅审计和方案判断，没有更换生产模型，也没有宣称拍屏问题已解决。

来源：[Apple 姿态检测](https://developer.apple.com/documentation/vision/detecting-human-body-poses-in-images)、[MediaPipe 模型说明](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker)、[iOS 官方运行模式与输出](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios)。
