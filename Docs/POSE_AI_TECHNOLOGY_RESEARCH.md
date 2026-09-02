# AI 动作教练：姿态 AI 技术选型与落地研究

> 日期：2026-08-30  
> 范围：iOS、隐私优先、完全端侧、单人纯侧面机位、保加利亚分腿蹲  
> 状态：技术研究与决策输入，不是已验证的准确率声明

## 1. 结论先行

本产品不应把“换一个更强的姿态模型”误当成“动作纠正就准确了”。它其实包含两个独立问题：

1. **姿态估计准确性**：每一帧的肩、髋、膝、踝在哪里，坐标和可见性有多可靠。
2. **教练判断准确性**：一整次动作是否完整，是否存在躯干不稳定、深度不足、下降过快，以及应该给什么建议。

姿态模型只直接解决第一层。第二层还需要动作分段、个人校准、时序建模、教练标注数据、置信度校准和产品级安全闸门。动作识别研究也明确指出，“做了什么”和“做得怎么样”不是同一个任务，普通动作识别表征不足以直接承担动作质量评估（AQA）任务。[Parmar 与 Morris，CVPR 2019](https://openaccess.thecvf.com/content_CVPR_2019/html/Parmar_What_and_How_Well_You_Performed_A_Multitask_Learning_Approach_CVPR_2019_paper.html)

推荐目标架构是**神经感知 + 确定性状态机 + 端侧时序质量模型 + 规则/置信度闸门**的混合方案：

```text
AVCaptureSession
  → Pose Adapter（Vision 2D 为稳定基线；MediaPipe 为受控候选）
  → 统一 LandmarkContract + 画面质量闸门
  → 平滑、尺度归一化、角度/位移/速度特征
  → 确定性阶段状态机与完整计次
  → 单次重复的端侧多标签时序质量模型（Core ML）
  → 规则复核 + 置信度校准 + abstain（不判断）
  → 实时最多一个提示
  → 组后完整 Summary + 1–3 项 Action List
```

近期不建议：用云端视频语言模型替代实时判定；直接把 Create ML 的动作分类器当作多问题质量模型；在没有教练标注、人物隔离测试集和真机性能数据时宣布“AI 能准确纠正动作”。

## 2. 当前仓库基线如何接入目标架构

仓库已经具备正确的分层雏形，不需要推翻重来：

- `App/PoseAdapters.swift` 通过 `LivePosePerception` 隔离感知层。
- 默认 `AppleVisionPosePerception` 使用 `VNDetectHumanBodyPoseRequest`，版本标识为 `apple-vision-2d-revision-1`，向统一领域模型映射 9 个点：鼻、双肩、双髋、双膝、双踝。
- 可选 `MediaPipePosePerception` 使用 Pose Landmarker live-stream，配置单人、0.5 detection/presence/tracking 阈值；当前映射额外包含脚跟和足尖，但只使用 `result.landmarks` 的图像坐标，没有使用 `worldLandmarks`。
- `Sources/FormCoachCore/MotionPreprocessor.swift` 已承担平滑、人体尺度归一化和派生运动特征。
- `WorkoutSessionEngine` 已有阶段状态机、完整计次、三类阈值规则、低质量暂停、问题置信度、抑制策略、实时提示优先级和冷却。
- `PoseObservation`、`RepSummary`、`IssueEvent` 和 `FeedbackEvent` 已记录时间戳、引擎/规则版本与结构化证据，适合继续作为可解释性审计层。

因此新增 AI 的合理接缝是：在一次重复完成、`RepAccumulator` 已得到规范化时序之后，加入 `RepQualityModel` 协议；模型返回每类问题的概率与可选证据，再由现有策略层决定记录、抑制或播报。**计次、相机质量、隐私和提示节流不应交给黑盒模型。**

当前已知工程约束：仓库的 `MediaPipeTasksVision` 锁定为 1.0.0；本地审计显示它在现有 Xcode 15.4 工具链下因 Metal 符号不兼容而保持 opt-in。这个结果是仓库本地证据，不代表所有 MediaPipe/iOS 组合都不兼容；升级工具链后仍须真机复验。

## 3. 姿态估计候选

### 3.1 Apple Vision 2D Body Pose

**输出与时序**

- `VNDetectHumanBodyPoseRequest` 从 iOS 14 / macOS 11 起提供，最多返回 19 个二维身体点，包括脸部、上肢、髋、膝、踝、颈和 root；每点包含归一化 `x/y` 和 confidence，坐标原点在左下。[Apple：Detecting Human Body Poses in Images](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images)
- 请求是逐图像的；API 本身不是动作质量或时序分类器，跟踪、平滑和阶段序列需由应用实现。[VNDetectHumanBodyPoseRequest](https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest)

**iOS、延迟、隐私与工具链**

- 系统 Vision 框架直接接收相机帧，不需要随 App 分发额外姿态模型或第三方运行时。
- 推理可完全在设备上执行，因而可维持“画面不离开设备”的边界。具体延迟、帧率、发热并无一个可跨设备套用的官方数值，必须在目标 iPhone 上测量。
- Apple 建议主体高度至少占画面三分之一、关键身体区域尽量完整入镜；宽松衣物和密集人群会降低检测准确性。[Apple：提高人体姿态检测准确性](https://developer.apple.com/documentation/Vision/detecting-human-body-poses-in-images)

**优点**

- iOS 原生依赖最少，当前仓库已经编译通过，是可靠基线和降级路径。
- 19 点足以支撑侧面分腿蹲的髋部位移、膝角、躯干角与节奏特征。
- 版本可通过 Vision request revision 显式记录，便于回归测试。

**限制与适配度**

- 只有 2D 坐标，离平面运动、机位偏转和前后腿遮挡容易投影成错误角度。
- 不提供脚跟/足尖，不能直接判断足部方向或脚掌细节。
- 适配度：**当前 P0 首选姿态基线**；不能单独证明教练判断准确。

### 3.2 Apple Vision 3D Body Pose

**输出与时序**

- `VNDetectHumanBodyPose3DRequest` 从 iOS 17 / macOS 14 起提供 17 个三维关节；位置以米表示、以双髋中点 root 为原点，并带父关节关系。[Apple：Identifying 3D Human Body Poses in Images](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images)
- 请求只返回画面中最显著的一人；要么返回全部 17 点，要么没有结果。没有深度数据也能运行，但 Apple 明确说明提供 depth 会提高准确性。[同一官方文档](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images)
- 有足够深度元数据时可估计 body height；官方说明准确的实测身高依赖配置 LiDAR 相机，否则可能返回 1.8m 参考高度。[同一官方文档](https://developer.apple.com/documentation/vision/identifying-3d-human-body-poses-in-images)

**优点**

- 能显式观察离相机方向的变化，理论上比纯 2D 更有能力识别机位偏转和关节前后关系。
- 单人输出符合本产品的单人边界，系统框架仍可保持端侧。

**限制与适配度**

- 17 点仍无 MediaPipe 那样的脚部细粒度；没有深度输入时的 3D 是估计结果，不等于真实测量。
- 设备与相机能力差异会造成两种数据质量路径；如果把它作为唯一输入，会扩大测试矩阵。
- 需要单独验证 live camera 帧处理吞吐和各目标机型可用性，不能从静态图片 API 说明推断实时性能。
- 适配度：**有价值的实验分支，不是第一阶段默认方案**。建议做 2D/3D 同帧对照采集，验证它是否真实降低侧视角误报，再决定是否进入产品路径。

### 3.3 MediaPipe Pose Landmarker

**输出与时序**

- iOS Pose Landmarker 输出每人 33 个图像 landmarks，以及 33 个 world landmarks；图像坐标含归一化 `x/y`、相对髋中点的 `z`、visibility/presence，world coordinates 以米为单位、髋中点为原点。[Google：Pose Landmarker iOS 输出](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios#handle_and_display_results)
- 支持 image、video、live-stream 三种模式；live-stream 异步回调，并在任务忙时忽略新帧。video/live-stream 使用 tracking 以减少每帧重新检测，从而帮助降低延迟。[Google：Pose Landmarker iOS 指南](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios)
- 可设置检测数量、检测/存在/跟踪阈值并可选输出分割 mask。[Google：配置项](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios#configuration_options)

**iOS、隐私、工具链与许可证**

- 官方 iOS 集成使用 `MediaPipeTasksVision` CocoaPod，支持 Swift/Objective-C；模型 `.task` 文件需加入 App bundle。[Google：iOS setup](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/ios#setup)
- MediaPipe 官方仓库说明 Tasks 输入处理发生在设备上、不会把输入发送到 Google；同一说明也称 Tasks 会发送性能和使用指标，因此发布前必须核对实际 SDK 版本、网络行为、用户同意与隐私申报，而不能把“输入不上云”简化成“完全没有网络遥测”。[MediaPipe 官方仓库隐私说明](https://github.com/google-ai-edge/mediapipe#privacy-notice)
- MediaPipe 源码和官方示例采用 Apache-2.0。[MediaPipe LICENSE](https://github.com/google-ai-edge/mediapipe/blob/master/LICENSE) 但具体 `.task` 模型资产的再分发条款必须对所锁定模型单独复核；不能仅凭 SDK 源码许可证推定模型权重许可证。

**优点**

- 脚跟和足尖、visibility/presence、world landmarks 对分腿蹲细节和遮挡质量判断更有潜力。
- live-stream 的异步和忙时丢帧语义与当前项目的 latest-frame 策略一致。
- 跨平台 landmark schema 有利于未来复用训练数据。

**限制与适配度**

- CocoaPods、二进制 SDK、模型资产和许可证增加供应链与发布审计成本。
- world landmarks 仍由单目模型估计，必须用本产品数据实证验证，不能因为单位是“米”就当成测量级 3D。
- 当前 adapter 只消费图像 landmarks，尚未利用 world landmarks；因此现有 MediaPipe 路径的实际价值主要是更多关节点与另一套误差分布。
- 适配度：**首要对照候选**。升级工具链后应与 Vision 2D 在同一真机、同一人物隔离数据集上做误差、覆盖率、延迟、发热和最终 coaching 指标对比。

### 3.4 MoveNet + TensorFlow Lite / LiteRT

**输出、iOS 与许可证**

- MoveNet single-pose Lightning/Thunder 输出 17 个人体关键点。[TensorFlow Hub 官方教程](https://www.tensorflow.org/hub/tutorials/movenet)
- TensorFlow 官方仓库有持续相机输入的 iOS 示例，包含 PoseNet、MoveNet Lightning 和 Thunder；示例说明画面用后立即丢弃，要求 iOS 12.4+、Xcode 12.5+，通过 CocoaPods 集成。[TensorFlow 官方 iOS 示例](https://github.com/tensorflow/examples/tree/master/lite/examples/pose_estimation/ios)
- TensorFlow examples 代码采用 Apache-2.0。[tensorflow/examples LICENSE](https://github.com/tensorflow/examples/blob/master/LICENSE) 与 MediaPipe 一样，计划分发具体模型文件时仍须保留模型卡/下载页所载条款并单独法务核验。

**优点**

- Lightning/Thunder 提供速度与精度档位，且有第一方 iOS 示例，适合建立第三条姿态基准以验证结论是否依赖某一家引擎。
- 完全端侧路径可实现隐私目标。

**限制与适配度**

- 只有 17 个 2D 点，不提供 MediaPipe 的脚部细粒度或同等 world-landmark 输出。
- 引入第二个非 Apple 推理运行时，但产品当前已经有 Vision 和 MediaPipe 两条路径，第三条生产依赖会增加维护成本。
- 官方 iOS 示例证明“能集成”，不证明它在本 App、当前设备和侧面分腿蹲上优于已有候选。
- 适配度：**离线 benchmark 候选，暂不进入生产依赖**。只有在它对最终教练指标或低端设备延迟显著胜出时才升级为生产方案。

### 3.5 姿态引擎选择矩阵

| 候选 | 输出 | 原生时序 | iOS 集成 | 产品定位 |
|---|---|---|---|---|
| Vision 2D | 最多 19 个 2D 点 + confidence | 无，应用自建 | 系统框架 | 默认基线/后备 |
| Vision 3D | 17 个 3D 点、米制 root-relative；可利用 depth | 无，应用自建 | iOS 17+ 系统框架 | 实验分支 |
| MediaPipe Pose | 33 个图像点 + 33 个 world 点，可选 mask | video/live tracking | CocoaPods + `.task` | 第一对照候选 |
| MoveNet | 17 个 2D 点 | 模型逐帧，应用自建 | TFLite/LiteRT 官方示例 | 离线 benchmark |

最终选择不能按“点越多越好”决定，应以本产品最终指标为准：关键点覆盖、动作分段/计次、三类问题 precision/recall、错误提示率、端到端提示延迟、功耗与热稳定。

## 4. 动作质量与时序模型候选

### 4.1 规则-only 基线（当前方案）

**机制**：平滑后的关键点 → 人体尺度归一化 → 阶段状态机 → 每次重复的深度、躯干变化、下降时长 → 个体校准阈值。

**优点**：无需训练数据、确定性、容易复现和解释；能明确区分“没有足够证据”和“检测到问题”；适合建立数据管线、标注工具和安全后备。

**限制**：难以覆盖身体比例、机位偏差、遮挡、动作风格和多个特征共同出现的复杂边界；三次个人校准也不能把错误动作变成正确标准。

**定位**：必须保留为 baseline、解释层和 fallback；不应作为公开准确纠正能力的唯一证据。

### 4.2 Create ML `MLActionClassifier`

- Create ML 使用 Vision 在视频帧中提取人体 landmarks，再从 landmark 序列学习动作模式；导出 Core ML 模型后可分析相机实时帧。[Apple：Creating an Action Classifier Model](https://developer.apple.com/documentation/createml/creating-an-action-classifier-model)
- 官方要求训练帧率与目标 App 帧率匹配；prediction window = frame rate × action duration。Apple 建议每个动作类别至少收集 50 个示例，并建立相关但不属于目标动作的 negative class。[同一官方文档](https://developer.apple.com/documentation/createml/creating-an-action-classifier-model)
- 数据源可直接使用视频与时间段 annotation，也可使用已提取的 keypoint DataFrame；模型输出带 label、confidence 和 frame range。[MLActionClassifier.DataSource](https://developer.apple.com/documentation/createml/mlactionclassifier/datasource)、[Prediction](https://developer.apple.com/documentation/createml/mlactionclassifier/prediction)

**优点**：Apple 全栈工具链、训练门槛低、Core ML 部署自然，很适合快速回答“时序模型是否比规则更好”。

**限制**：它的核心抽象是动作**分类**。本产品一次重复可能同时有多个问题，需要多标签输出、按阶段证据和 abstain；直接把组合标签做成类别会发生类别组合爆炸。其 Vision 特征提取还会把姿态前端绑定到 Apple schema，与 MediaPipe 统一输入目标冲突。

**定位**：**快速 PoC/对照组**，不是最终多标签质量模型的默认选择。可以先训练“稳定 / 躯干 / 深度 / 速度 / negative”单标签版本，测出数据上限和实时窗口成本。

### 4.3 自定义端侧时序模型 + Core ML

Core ML 可在设备上使用 CPU、GPU 和 Neural Engine，完全本地运行不需要网络；Apple 也支持用 coremltools 把 TensorFlow 或 PyTorch 模型转换成 Core ML。[Core ML 官方说明](https://developer.apple.com/documentation/CoreML)、[coremltools Unified Conversion API](https://apple.github.io/coremltools/docs/source/coremltools.converters.convert.html)

工具链约束必须固定：coremltools 的 `mlprogram` 是推荐格式，部署下限为 iOS 15；转换支持 TensorFlow 与 PyTorch/TorchScript/ExportedProgram，但具体算子、精度和 state 支持随 coremltools 与最低 deployment target 变化，必须用锁定版本进行数值一致性和真机性能测试。[Core ML Tools：Source and Conversion Formats](https://apple.github.io/coremltools/docs-guides/source/target-conversion-formats.html)

候选架构：

1. **小型 TCN（优先）**：固定长度的关键点/角度序列经过一维时间卷积，输出三类独立 sigmoid 概率与可选阶段概率。TCN 已被原始研究用于细粒度动作分段，也被用于 3D skeleton 时序建模。[Lea 等，TCN for Action Segmentation](https://arxiv.org/abs/1611.05267)、[Kim 与 Reiter，Interpretable 3D Human Action Analysis with TCN](https://arxiv.org/abs/1704.04516) 对本产品的工程优势是小、并行、固定延迟、容易量化；但“优于其他架构”仍需本数据验证。
2. **LSTM/GRU**：适合可变时长序列和在线 hidden state；对小数据可能是实用基线。但串行计算、状态复位、丢帧和模型转换会增加实时一致性风险。先作为离线对照，不作为首个生产模型。
3. **Skeleton GCN / ST-GCN**：把关节作为节点、骨连接与跨帧连接作为边，天然编码人体拓扑。ST-GCN 原始工作从 2D/3D skeleton 学习空间与时间模式；Joint Relation Graphs 又直接证明关节关系建模可用于 action assessment。[Yan 等，ST-GCN](https://ojs.aaai.org/index.php/AAAI/article/download/12328/12187)、[Pan 等，ICCV 2019](https://openaccess.thecvf.com/content_ICCV_2019/html/Pan_Action_Assessment_by_Joint_Relation_Graphs_ICCV_2019_paper.html) 优点是拓扑归纳偏置强；缺点是开发、转换与端侧优化复杂度高，数据量小的时候未必胜过 TCN。
4. **Transformer**：适合长程依赖和多阶段关系；已有 skeleton Transformer 用于动作识别，也有细粒度 AQA 研究强调阶段级时空解析。[3Mformer，CVPR 2023](https://openaccess.thecvf.com/content/CVPR2023/papers/Wang_3Mformer_Multi-Order_Multi-Mode_Transformer_for_Skeletal_Action_Recognition_CVPR_2023_paper.pdf)、[FineParser，CVPR 2024](https://openaccess.thecvf.com/content/CVPR2024/html/Xu_FineParser_A_Fine-grained_Spatio-temporal_Action_Parser_for_Human-centric_Action_Quality_CVPR_2024_paper.html) 但对单个约 1–3 秒的分腿蹲、三类标签和早期小数据集，复杂度和过拟合风险通常不划算；列为数据规模扩大后的研究候选。

**推荐的第一版自定义模型接口**

```text
输入：[T, J, F]
  T = 固定采样后的完整重复窗口
  J = 统一 landmark 子集
  F = x/y(/z)、visibility、presence、速度、角度、相对校准偏差、mask

输出：
  phase probabilities [T, 5]（可选，用于辅助训练）
  issue probabilities [3]（多标签 sigmoid）
  data-quality / out-of-distribution score [1]
```

模型不直接生成自然语言。提示文案、优先级、冷却和 Action List 继续由可版本化策略产生。

### 4.4 云端视频语言模型（VLM）

云端 VLM 可以在未来用于**用户显式同意的组后视频复盘、教练辅助标注或研究**，但不应成为当前实时判断核心：它要求传输图像/视频，破坏默认端侧边界；网络延迟、成本和模型版本变化降低可复现性；输出也不天然提供可校准的逐问题概率和确定性阈值。

更关键的是，2026 年一项针对多种活动与模型的原始实证研究报告：所测 VLM 在 AQA baseline 中仅略高于随机水平，加入 skeleton、grounding、推理结构或 in-context learning 也没有一致有效。[CVPR 2026 Workshop：Can Vision Language Models Judge Action Quality?](https://openaccess.thecvf.com/content/CVPR2026W/SAUAFG/html/Monte_e_Freitas_Can_Vision_Language_Models_Judge_Action_Quality_An_Empirical_Evaluation_CVPRW_2026_paper.html)

结论：**当前不接云端 VLM 到实时训练链路**。若未来研究，必须是独立、显式 opt-in 的产品能力，另做隐私、成本和准确率决策。

## 5. 推荐实施路径

### 阶段 0：冻结并测量规则基线

- 保持 Vision 2D + 现有规则作为 control。
- 固定 camera preset、目标分析 FPS、画面方向、关键点 schema、规则版本和测试机型。
- 为每帧记录非图像调试数据：时间戳、关键点/质量、派生指标、阶段、是否丢帧、推理耗时；开发数据必须取得明确同意，并与生产“默认不保存画面”分开。
- 先补齐组后 Summary + 1–3 项 Action List 的确定性聚合规范。

### 阶段 1：姿态引擎 bake-off

- 同一批已同意的教练标注视频，离线跑 Vision 2D、Vision 3D、MediaPipe、MoveNet。
- 统一映射到 `LandmarkContract`；不要让不同引擎各自使用不同问题规则。
- 同时报告关键点指标和最终 coaching 指标，不能只比较模型宣传的通用 benchmark。
- 真机比较端到端 p50/p95 推理、有效分析 FPS、丢帧率、15 分钟热降频、峰值内存与电量。
- 仅当候选在预注册指标上显著胜出，才改变默认 adapter；Vision 2D 仍保留可诊断后备。

### 阶段 2：Create ML 快速时序 PoC

- 用相同人物隔离 split 训练 `MLActionClassifier` 单标签对照。
- 目的不是直接发布，而是验证“时序学习是否在本数据上超过规则”，以及测试窗口长度、帧率、端侧延迟和数据量级。
- 如果不能稳定超过规则或只在随机视频切分上提升，停止模型扩张，先修数据和标签。

### 阶段 3：自定义多标签 TCN

- 输入统一关键点序列和派生特征；同时训练三类问题，加入 `clean/none`、低质量和不确定样本。
- 以规则输出作为附加特征或复核，而不是训练真值。
- 经 coremltools 转换后做 Python ↔ Core ML 数值一致性测试；固定工具链、最低 iOS、量化精度、模型 SHA-256 和训练数据版本。
- 采用 shadow mode：模型只记录不提示，对比教练真值和现有规则。
- 达到发布闸门后再逐类启用，允许某一问题由模型、另一问题继续由规则判断。

### 阶段 4：扩大动作或升级架构

- 数据足够后再比较 LSTM、GCN、Transformer；每次只改变一个变量并保留规则、Create ML、TCN 基线。
- 新动作必须拥有独立动作定义、阶段、标签手册、数据覆盖和发布闸门，不能默认继承分腿蹲模型。

## 6. 数据与标注方案

### 6.1 标注单位

每条训练样本以**一次完整重复**为主单位，同时保留会话和训练组层级：

- subject ID（去标识化）、session ID、set ID、rep ID；
- 训练腿、训练目标、机位、设备、光照、衣着/遮挡类别；
- 起始、下降、底部、上升、锁定的时间边界；
- 完整/未完成、是否可判定；
- 多标签：躯干不稳定、深度不足、下降过快；
- 每个问题的严重度和发生阶段；
- 教练备注与分歧处理结果；
- 姿态引擎/模型/规则版本。

### 6.2 标签不是规则输出

- 由至少两名合格教练独立标注；不一致样本进入第三方复核或 consensus session。
- 在标注指南中给每类问题写清可观察定义、边界样例、不可判定条件和训练目标差异。
- 记录 inter-rater agreement；标签本身分歧大时，模型上限受标签定义限制，应先修定义而不是调模型。
- 不把三次用户校准动作自动标成“正确”；校准只是个体参考。

### 6.3 覆盖与困难负样本

- 覆盖不同身高、身体比例、肤色、体型、训练经验、左右腿、衣着、背景、光照、拍摄距离、iPhone 型号和轻微机位偏差。
- 每类问题要有单独出现和组合出现样本；另收稳定动作、动作未完成、走入/走出画面、遮挡、多人、坐下/弯腰等 negative/OOD。
- Apple 的训练建议强调单人、全身、固定相机、充足光照、衣着与背景对比，并要求相关 negative class；这些是采集起点，但产品测试还要故意包含不理想场景来验证 abstain。[Apple：Gathering Training Videos](https://developer.apple.com/documentation/createml/recording-or-choosing-training-videos)

### 6.4 人物隔离切分

- 训练、验证、测试必须按 `subject ID` 完全隔离；同一个人的任何视频不能跨 split。
- 另设冻结的 release test、困难场景 test 和设备性能 test；release test 不参与阈值调参。
- 随机按重复/视频切分会把个人姿态、衣服、背景泄漏到测试集，得出的准确率不代表新用户泛化。

## 7. 评估指标与建议发布闸门

以下数值是本项目建议的预注册门槛，不是外部来源或当前已达成结果。正式采集前应由产品、教练和工程共同批准。

### 7.1 姿态层

- 必需关节点可用率（肩/髋/膝/踝）；按人物与场景分组。
- 在人工点标子集上的 PCK / normalized joint error。
- 短时抖动、遮挡后恢复时间、左右腿身份交换率。
- 姿态引擎不应只凭通用 benchmark 入选；必须改善最终动作指标或性能预算。

### 7.2 计次与阶段层

- 完整重复计数 precision ≥ 0.98、recall ≥ 0.97。
- 未完成动作误计率 ≤ 1%。
- 阶段边界 median absolute error 建议 ≤ 150 ms，p95 ≤ 300 ms。
- 低质量/OOD 画面应优先 abstain，而不是猜测。

### 7.3 每类问题层

- 每类分别报告 precision、recall、F1、PR-AUC、校准误差；不得只报总 accuracy。
- 实时播报路径以 precision 优先：建议每类 precision ≥ 0.95，且 95% 置信区间下界 ≥ 0.90。
- summary-only 可采用较低阈值，但仍建议 precision ≥ 0.90。
- 稳定重复的任意错误播报率 ≤ 5%；每组错误播报中位数应为 0。
- 同时报告不同性别、体型、肤色、设备、衣着、光照、左右腿等切片；任何关键切片不能被整体均值掩盖。

### 7.4 端侧产品层

- 从重复完成到提示决策 p95 ≤ 300 ms；语音开始可另设预算。
- 目标设备持续 15 分钟训练无崩溃、无不可恢复相机积压。
- 实际分析 FPS、p50/p95 推理时延、丢帧率、内存、温升/热状态、电量全部按设备记录。
- 无网络条件下完整训练闭环可用；默认不保存视频或帧。
- 模型不确定、关键点缺失、多人、方向错误时，暂停/不提示的行为通过验收。

### 7.5 相对发布条件

新模型除绝对门槛外，还必须在**同一冻结人物隔离测试集**上：

- 三类问题的宏平均 F1 与错误播报率均优于规则 baseline；
- 不降低计次门槛；
- 不突破目标设备时延、功耗和热预算；
- 经教练盲评确认 Action List 更可信或至少不劣；
- 所有模型、数据、阈值、引擎版本和许可证可追溯。

若只提高 recall 却显著增加误提示，不进入实时播报；可先进入 summary-only 或继续 shadow mode。

## 8. 风险与控制

| 风险 | 后果 | 控制 |
|---|---|---|
| 2D 投影与机位偏转 | 角度/深度假异常 | 机位闸门、数据增强、3D 对照、abstain |
| 校准动作本身有问题 | 个体基线污染 | 校准只做参考；通用边界与质量检查独立 |
| 姿态 confidence 被误当 coaching confidence | 误报自信 | 单独训练/校准问题概率；分层记录置信度 |
| 小数据或同人泄漏 | 离线高分、真实失效 | subject-disjoint split、冻结测试集 |
| 标签主观或教练不一致 | 模型上限不清 | 双人标注、裁决、agreement 报告 |
| 多问题组合稀疏 | 漏掉共现模式 | 多标签建模、组合覆盖、逐类阈值 |
| 模型转换数值漂移 | Python 好、iPhone 差 | 转换一致性测试、锁版本、真机 golden set |
| 热降频与帧率变化 | 时序特征漂移 | 时间戳特征、重采样、持续负载测试 |
| 第三方 SDK/模型条款不清 | 发布/合规阻塞 | SDK 与模型资产分别核验许可证和遥测 |
| 黑盒解释不可信 | 用户无法理解提示 | 保存结构化指标；模型只给概率，策略给文案 |
| 数据采集破坏隐私承诺 | 信任与合规风险 | 生产默认不保存；研究采集独立同意、最小化与删除策略 |

## 9. 需要继续决策的问题

1. 最低支持设备和最低 iOS 是否保持 iOS 17；是否覆盖无 LiDAR 设备作为主路径。
2. 目标分析帧率、单次重复最大时长和提示延迟预算。
3. MediaPipe 的固定 SDK/模型版本、模型资产许可证与遥测处理是否满足发布要求。
4. 训练数据是否允许保存原视频；若允许，保存位置、加密、访问控制、保留期和撤回流程。
5. 谁具备“合格教练”标注资格；三类问题的操作性定义、严重度和不可判定规则。
6. 每类问题的实时提示阈值、summary-only 阈值和允许的错误成本。
7. Vision 2D 与 MediaPipe 是单一路径择优，还是设备/场景路由；路由会不会让模型输入分布碎片化。
8. 自定义模型是否只输入统一 skeleton，还是加入规则派生特征和个人校准偏差。
9. 是否需要把动作阶段作为辅助学习目标；是否保留确定性状态机为最终计次权威。
10. 公开发布前所需样本人数、每类样本数与关键切片最低样本量。

## 10. 建议形成的技术决定

建议下一份 ADR 固化以下方向：

> AI 动作教练采用混合架构。Apple Vision 2D 和当前规则引擎作为可解释基线与后备；MediaPipe、Vision 3D、MoveNet 必须在统一人物隔离数据集和目标真机上比较后才能替换默认姿态引擎。公开发布前新增端侧多标签时序质量模型，首选小型 TCN，经 Core ML 部署；确定性阶段/计次、画面质量、提示策略和隐私闸门继续由规则层掌握。云端视频语言模型不进入第一版实时链路。

这项决定仍需在教练标签规范、数据采集授权、设备范围和 release gates 获得确认后，才能从“研究建议”升级为正式 ADR。
