# Qwen3-VL-2B iPhone 预研审计

**后续实测状态：完整4-bit和BF16权重现已下载并校验，在Mac真实推理中发现动作判断未达标。见[完整实测与失败证据](../../Testing/Qwen3VL-Mac-2026-10-16/README.md)。以下保留下载前的预检记录，不能据编译通过判断模型质量。**

日期：2026-10-16。目标是提前排除可以静态核实的风险。本文明确区分：**已核实事实 / 源码推导 / 建议配置 / 仍需运行验证**。不承诺“调研后不会再有问题”。

本次没有安装或启动 iPhone App，也没有下载完整模型权重；通过 HTTP Range 只读取权重文件头来核实张量。读取了设备信息，确认当前 iPhone 15 Pro Max / iOS 27.0。编译预检为独立研究包，不修改主 App 的依赖。

## 1. 当前选型结论

- 候选保留为 **Qwen3-VL-2B-Instruct 的固定 4-bit MLX 转换版**，先做短片/少量有序图片的组后实验。
- 不把它当实时计次模型；不直接把长录像、无限对话、原始分辨率整段输入塞进手机。
- 不把“有4-bit文件”“Qwen3支持”“能编译”分别偷换成整模型4-bit、Qwen3-VL支持、iPhone推理已可用。
- 优先审计 MLX Swift LM 3.32.3 + MLX Swift 0.32.3，固定依赖锁。旧2.x和新3.x接口不同，不混抄样例。直接使用 MLXVLM，关闭需要新SDK的 FoundationModelsIntegration trait；现有 Xcode 26.6 不需要为了直连MLX先升级到27。
- 只有实际加载、预处理对齐、量化输出质量、内存/延迟和动作误报都过关，才能把候选变成推荐部署。

## 2. 已核实的模型身份与权重

来源为 Hugging Face 官方API的固定revision；完整原始元数据、配置与头信息见 [evidence](evidence)。下载大小使用十进制GB；内存计算另用GiB/MiB。

| 项目 | 核实结果 |
|---|---|
| 官方模型 | `Qwen/Qwen3-VL-2B-Instruct` |
| 官方revision | `89644892e4d85e24eaac8bacfd4f463576704203` |
| 原始权重文件 | 4,255,140,312 bytes；整个仓库约4.267GB |
| 原始张量元素数 | 2,127,532,032，约21.28亿；语言约17.21亿，视觉约4.07亿。来自原始BF16文件头的张量形状求和 |
| 候选量化仓库 | `mlx-community/Qwen3-VL-2B-Instruct-4bit`，社区转换，不是Qwen官方量化验收 |
| 量化revision | `9c4f5209e57b31f4b9dfba735de3fb983739c9cc` |
| 转换工具声明 | 模型卡注明 `mlx-vlm 0.3.4` |
| 量化方式 | affine、4 bits、group size64 |
| 量化仓库总文件 | 1,798,023,774 bytes，约1.798GB/1.675GiB |
| 权重文件 | 1,782,040,921 bytes；张量存储本体1,781,915,648 bytes |
| 视觉部分 | **315个张量仍为BF16**，813,914,112 bytes，约814MB/776.21MiB |
| 语言部分 | U32打包权重860,225,536 bytes；其余BF16张量107,776,000 bytes（包括量化辅助数据和未量化部分） |
| 完整权重预期SHA256 | 官方 `7de1838c87a5349b016c26a1c3f7d2bc400a3d485f95ef39a7059ffd734977a0`；量化 `4750d95a2162829e127a94e83ac350d498d02070aab216c4687da48804a06ffb` |

上述SHA为上游LFS元数据声明，本次没有下载全部权重，**未做完整文件哈希校验**。Range响应206，分别读取约76KB/125KB头部，没有下载4.26GB/1.78GB权重。

MLX格式的U32是打包存储，不是32-bit浮点语言模型。视觉BF16不会因为顶层写了bits=4就自动全部变成4-bit；MLX加载器按各层是否存在scales判断是否量化。后续想量化视觉塔属于另一份转换与质量验证任务。

## 3. 架构与内存下界

已核实配置：语言28层、hidden2048、attention heads16、KV heads8、head dim128、词表151936、原生max_position_embeddings262144。视觉24层、hidden1024、heads16、patch16、spatial merge2、temporal patch2、输出维度2048、DeepStack层5/11/17。2B是Dense，不是可只激活少量专家的MoE。

假设batch=1、K/V为16-bit、不量化KV，缓存开销为：

`2(K与V) × 28层 × 8个KV头 × 128维 × 2字节 = 114,688字节/token = 112KiB/token`

| 已填充总token数 | 仅KV缓存 | 权重张量+KV下界 |
|---:|---:|---:|
| 2,048 | 224MiB | 1.88GiB |
| 4,096 | 448MiB | 2.10GiB |
| 8,192 | 896MiB | 2.53GiB |
| 16,384 | 1.75GiB | 3.41GiB |
| 32,768 | 3.5GiB | 5.16GiB |
| 262,144 | 28GiB | 29.66GiB |

这不是App实测内存，也不是启动时自动分配满262K。还没计入视觉中间张量、预填充、图像解码与转换、Metal缓冲池、tokenizer、模型加载瞬时开销、AVFoundation、MediaPipe和UI。若运行时把缓存升为FP32，KV部分还会翻倍。量化权重不等于量化KV。

可重复推导：[derive_budget.py](scripts/derive_budget.py)；产物：[derived-budget.json](evidence/derived-budget.json)。不能用手机总RAM、空闲存储、Metal建议工作集中的任何一个单独保证能运行。iOS有动态进程内存限制，超限可能直接jetsam；`Memory.memoryLimit`不是向系统申请更多RAM的许可。[S5][S6]

## 4. 图片和视频输入：必须明确的预算

**已核实**：32×32像素对应一个空间合并后的视觉token；单张图片在时间patch维度会补齐，不能据temporal_patch_size=2把独立图片token数再除2。尺寸必须按当前处理器规则取整，保持全身与脚部可见。

- 512×512图片约256个视觉token；6张约1536。
- 384×672竖图约252个视觉token；6张约1512。
- 上述只是视觉token，还要加图片边界、文字、模板、时间/证据ID以及输出预算。

官方预处理配置中 `longest_edge=16777216` 指**像素面积上限**，不是宽或高的边长。HF视频处理器的同名字段则指跨帧总像素预算，和图片语义不同，禁止直接混用。[S1]

### Swift实现与官方Python不能默认等价

审查了MLX Swift LM固定tag 3.32.3及旧tag2.31.3的Qwen3VL源码：

- 3.32.3已加入图片sRGB色调处理修复及默认每图1280视觉token预算；旧2.31.3图片路径没有同样处理，且不解析新式size字段，会用自己的默认像素预算。不能仅凭老样例“可以跑”选旧版。[S3]
- 此tag还包括视觉attention逐图分段与融合SDPA修复，避免构造跨图的大型稠密mask。上游PR中的72维示例并非本2B的维度：2B视觉1024/16=64，不能照抄其他尺寸的显存实测数字作为2B结果。[S9]
- 3.32.3支持 `.processing.minPixels/maxPixels` 覆盖。手机实验仍需**显式设预算**，不能依赖桌面默认1280 token/图。
- 已检查的Swift视频路径默认2fps；累积所选帧后patchify，并非无限实时流式消费。
- Qwen3VL模型processor取出sequence.frames，没有把sequence.timestamps直接传入后续LM输入；消息生成器也只创建video占位类型。**不可据此声称完整复现官方文本时间戳对齐、帧级错误定位。**需要端到端时间标记测试或实现明确的图像ID/时间映射。
- 图片、视频、processor、tokenizer和chat template需一起固定；不能只换model.safetensors。
- 原始相机BGRA与模型RGB、方向/镜像、sRGB/线性空间、缩放与裁切都要统一。骨架叠图作为辅助，不替代原图。
- 当前AVAsset取帧路径设置 `appliesPreferredTrackTransform=true`，新路径保留actualTime；但取帧失败会跳过该帧。因此必须核对实际成功帧、原始顺序及时间，不能仅按请求帧数认定覆盖完整。HDR/广色域、HEVC/H.264、可变帧率、90°旋转metadata与自拍镜像需在本地样本里分别比对，不能把标成sRGB当成所有源文件都已正确色调映射。

对于短于0.5秒的问题，2fps采样有直接漏掉的可能；六张关键帧也只能支持对应时刻的判断。需要连续性证据的节奏和协调仍主要依靠原始时序特征，不能让模型推算未观察时段。

## 5. 本项目建议实验配置（未证明效果）

| 项目 | 初始约束 |
|---|---|
| 模型 | 固定Instruct版，区分Thinking/Embedding/Reranker；禁止自动换别的Qwen模型 |
| 任务 | 组后短片复核，优先每次独立请求；计次不等模型 |
| 输入 | 4–6张按阶段选择的原始全身帧，加明确ID/采集时间与测量；不是随机截6张 |
| 每图像素 | 先试min65536、max262144；保持比例、因子32取整。该预算仍需验证关节细节是否足够 |
| 视觉token | 每图约256、总量约1536上限，记录实际processor结果 |
| 总上下文 | 初始硬上限4096，输入与输出一起计算；不长驻积累整次历史 |
| 输出 | 初始128–192新token；可取消、有限时；超限/超时保留计次，回退模板 |
| 采样 | 第一轮temperature0/固定短格式便于回归；这是实验选择，不是官方最佳性能配置 |
| KV | 第一轮保持已知精度与短上下文；后续独立评估KV量化，不能与权重量化混称4-bit |
| 并发 | 一个在途模型任务；新请求不无限排队；MLX对象、KV和session由一个隔离执行域管理 |
| 模型加载 | 用户进入分析时后台加载；不阻塞首页/打开相机；先停止或降载相机路径再做组后分析 |
| 回退 | 模型缺失、下载失败、内存/温度压力、输出证据无效时使用已有计次和审核模板 |

不能只依赖maxKVSize轮转来实现硬上限：静默丢掉开头的目标/证据会改变问题。应在预处理后检查实际token数，显式拒绝过大输入或减少帧/像素并重新预算。

## 6. 开发、运行时与依赖

- 本机Xcode26.6 / Swift6.3.3 / iPhoneOS SDK26.5。3.32.3包要求Swift tools6.2，平台声明iOS17/macOS14；Swift Package产品 `MLXVLM` 注册 `qwen3_vl` 架构。
- MLX主要走Metal GPU，这条路线与Apple Intelligence是否开启无直接依赖。不要把“端侧”理解为已经转换Core ML、已经跑ANE，或可以套用Apple系统模型的运行指标。
- 3.x已把tokenizer/downloader解耦，实际应用还需选择并验证这些实现；只有导入MLXVLM不等于完成可推理的接入。
- 本轮固定Tokenizers实现为swift-transformers1.3.0、swift-huggingface0.9.0。Xcode编译实际遇到MLXHuggingFace宏信任门槛，研究包改用明确实现Tokenizer/TokenizerLoader协议的适配器，未关闭全局宏校验。此适配器的加载函数仅编译，未被运行。
- `MLXFoundationModels`桥接需要27 SDK；直接MLXVLM可关闭对应trait，避免把系统模型和自带模型依赖混在一起。[S2]
- 官方文档明确模拟器缺少所需Metal特性，不能在那里评价MLXArray。模拟器只做UI、状态、错误回退；真正模型开发先用Apple-silicon Mac，再验证手机。[S5]
- 历史上存在特定iPhone/系统组合乱码的问题，上游最后明确修复落在mlx-swift0.30.6。不能用旧帖“issue closed”或Mac正常替代确认固定依赖已包含修复。当前候选0.32.3是后续版本，仍需验证目标设备。[S7]
- 研究包首次编译发现本机**缺Metal Toolchain**，原样保留失败日志。本次通过Apple官方 `xcodebuild -downloadComponent MetalToolchain` 补齐17F109组件，并确认 `xcrun metal --version` 可用。未更换整套Xcode。[S8]

主App已有MediaPipe约378MB的SPM二进制下载（与最终App体积不同），加入MLX后还要测最终arm64 Release/App thinning体积，不能把依赖下载量加总当安装体积。本轮额外在临时App副本中加入研究包并保留真实loader引用：generic iOS arm64 Debug编译/共同链接通过，MediaPipe的`-all_load`没有造成此次构建的重复符号错误，MLX的default.metallib已进入App资源。未运行App，故未验证运行时资源查找、GPU竞争或推理。主项目未被加入MLX依赖。

组合编译仍报告原有CameraService/MediaPipePosePerception的Sendable捕获警告（主App目前Swift5模式）；本轮不将它们描述为已解决，也不据Debug成功保证未来Swift6迁移或Release归档成功。

## 7. 下载、离线与分发

- 首次需要取得1.8GB级模型文件；之后可纯离线推理，不需要Qwen云API。下载源是否在用户网络可达仍需检查，不静默上传相机画面作为失败回退。
- 建议App之外按需下载：显示体积、可取消/断点恢复、验证revision及**完整权重SHA**、暂存目录下载完成后原子切换；未完整文件不得加载。
- 更新时保留旧版直至新版验证；同时有旧版+暂存约3.6GB，再加Hub缓存/复制策略与余量。实际磁盘预检按具体存储实现计算，不能只预留1.8GB。
- 模型放Application Support，不用临时目录冒充长期缓存；明确备份策略、版本清理和用户删除入口。下载失败/空间不足不破坏已有训练数据。
- 权重/model metadata公开声明Apache2.0；MLX及MLX Swift LM采用MIT。分发要带适用许可、NOTICE（若上游有）、修改/转换说明。公开非商用数据集的限制仍单独存在，不能由模型Apache许可覆盖。
- 固定权重、processor、tokenizer、Swift包锁和建议规则版本；不在发布版本无条件拉main或latest。

## 8. 中文、输出可靠性与动作能力

官方多模态与中文相关基准不能证明此2B量化转换、此手机预算能可靠纠错；量化模型卡也没有本项目的动作误报指标。第一轮需验证中文指令、术语一致性、JSON/受限字段、停止token、空答案、重复输出和模型拒答。官方generation_config包含结束ID151645/151643，VL推荐temperature0.7等是通用生成建议，不能照抄其长输出限制到手机。

受限格式不保证事实。模型只能引用真实存在的finding/帧ID；校验视角、时段和覆盖率。不能把“膝部模糊”改写成“膝内扣”，也不能把角度变化归因为力量、疼痛或活动度问题。首版输出候选而非自动确诊，和教练标注比较。

## 9. 仍必须实测的项目与通过条件

| 未确定项 | 实测方式 | 不通过时处理 |
|---|---|---|
| 固定权重在Swift中真实加载 | 完整SHA后本地加载，验证所有层/形状、真实视觉输入、模型身份 | 不用假输出或静默改成文字模型 |
| 预处理与Python参考一致 | 相同原图、颜色/方向/取整/视觉token数对比；图像变化确实影响结果 | 修processor后才评动作能力 |
| 峰值内存/加载瞬时峰值 | 记录App footprint、MLX active/cache/peak和os_proc_available_memory | 降帧/像素/上下文，必要时放弃候选 |
| 并行与热稳定 | 相机+MediaPipe开启/关闭两组、连续多次分析，记录温度与采样频率 | 首版只组后、降载或卸载模型 |
| 延迟与取消 | 冷启动/热启动、视觉预填充、首token/完整输出P50/P95；返回/锁屏/取消 | 及时回退，禁止任务继续积压或卡主线程 |
| 动作质量判断 | 独立人物/源片的正反例，逐项误报/漏报/拒答/证据定位 | 不上线该项，仅保留已验证能力 |
| 量化损失 | 小批同输入对照BF16参考，不能只看文本通顺 | 更高精度、换模型或取消该能力 |
| 无网/半下载/更新失败 | 离线启动、断网、损坏文件、空间不足、旧版回滚 | 保持计次与数据可用 |
| 真机差异 | 当前iPhone及后续目标最低设备实测 | 不据一台旗舰宣称全面兼容 |

工程门槛的具体秒数/可用内存余量必须在试验前配置并记录，不捏造“iPhone每秒N token”或“最多只占NGB”。请求并发、输入token/像素上限、取消与证据校验则可以在上机前就写死并做逻辑回归。

### 验收的记录方式

每条实验至少保存：固定模型/包revision、设备与系统、构建配置、输入源及人物分组、原图尺寸/颜色/旋转、成功帧ID与actualTime、缩放后尺寸、实际视觉/文本/输出token数、冷/热加载、prefill/首token/总耗时、峰值footprint与MLX内存、温度、取消和停止原因、原始输出及校验结果。只给平均速度不能发现P95卡顿；应保存逐次结果与样本数。

回归需包含：不同人物及体型/衣着；正侧面、偏侧、正面；全身和脚被裁切；真实人和拍屏；运动模糊/暗光/遮挡/多个人；正常、浅蹲、半起身、重复抖动；图像顺序颠倒、缺帧和文字证据矛盾。按原始人物/视频隔离集合，循环同一次动作或拍同一屏不算新增独立样本。计次正确与动作纠错正确分别计分；不能以“5次计对”证明“能判断深蹲标准”。

输出先限为最多1–2个候选问题：问题枚举、证据帧ID、测量ID、拒答原因和审核过的cueID。侧视未覆盖的正面问题不生成确定结论；候选不存在、引用不存在、时段不覆盖、JSON截断、超长或空输出均走明确回退。temperature0便于回归，但不保证跨系统/硬件逐token相同；格式合法也不等于判断正确。不得让置信度自报数字冒充经标注集校准的正确率。

取消需覆盖进入后台/锁屏、返回、重复点击、模型切换和内存告警。Swift Task取消属于协作取消，不代表已提交GPU工作立刻中断；GPU结束前不销毁仍被引用的资源，不允许过期输出更新新一组训练。GPU并发、功耗和稳定性不能用编译成功代替。

## 10. 证据与复现

- [固定模型与权重头证据](evidence)；[预算脚本](scripts/derive_budget.py)。
- [独立SPM预检包](preflight/Package.swift)及[复现说明](preflight/README.md)。真实本地VLM loader接口已编译，未调用加载。
- **通过**：generic iOS库编译；Mac配置/中文分词/图文模板检查；临时App副本中的MediaPipe+MLX共同编译和链接、metallib打包。**未做**：完整权重加载、图像张量/参考预处理一致性、真实生成、运行时资源查找、Release归档和手机推理。
- [配置与tokenizer实际结果](evidence/config-tokenizer-audit.json)：测试中文23 token，无损往返；6图占位标记与1视频占位标记正确；6图文本模板在视觉展开前49 token。这个49绝不能拿来当展开后的总上下文。
- [构建审计记录](evidence/build-audit.json)含命令、日志摘要、原始临时日志SHA及范围；[组合依赖锁](evidence/combined-Package.resolved)。[失败与通过日志摘录](evidence/logs)保留Metal缺失、宏信任以及最终成功证据。工具链缺失已补齐，宏桥接已用显式协议适配替换。
- [固定版本头部重新采集脚本](scripts/refetch_pinned_headers.py)只取有界头部/配置；[临时组合副本生成脚本](scripts/prepare_combined_audit.py)不安装、不启动App。

## 原始来源

- [S1] [Qwen官方仓库：输入与像素控制](https://github.com/QwenLM/Qwen3-VL)，[技术报告](https://arxiv.org/abs/2511.21631)，[官方固定配置](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct/blob/89644892e4d85e24eaac8bacfd4f463576704203/config.json)。
- [S2] [MLX Swift LM 3.32.3 Package.swift](https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/Package.swift)。
- [S3] [Qwen3VL固定Swift实现](https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/Libraries/MLXVLM/Models/Qwen3VL.swift)，[发布修复说明](https://github.com/ml-explore/mlx-swift-lm/releases/tag/3.32.3)。
- [S4] [量化权重固定仓库](https://huggingface.co/mlx-community/Qwen3-VL-2B-Instruct-4bit/tree/9c4f5209e57b31f4b9dfba735de3fb983739c9cc)。
- [S5] [MLX官方iOS与内存说明](https://github.com/ml-explore/mlx-swift/blob/0.32.3/Source/MLX/Documentation.docc/Articles/running-on-ios.md)。
- [S6] [Apple可用进程内存](https://developer.apple.com/documentation/os/os_proc_available_memory)，[提高内存上限的适用限制](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.kernel.increased-memory-limit)。
- [S7] [官方仓库历史设备乱码问题及修复版本](https://github.com/ml-explore/mlx-swift-examples/issues/462)。
- [S8] [Apple官方Metal组件安装方式](https://developer.apple.com/documentation/Xcode/downloading-and-installing-additional-xcode-components)。
- [S9] [Qwen3VL视觉attention内存修复PR及其测量适用范围](https://github.com/ml-explore/mlx-swift-lm/pull/455)。
