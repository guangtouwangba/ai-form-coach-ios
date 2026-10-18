from pathlib import Path
import json
B=Path(__file__).resolve().parents[1];scores=json.loads((B/'results/comparison-score.json').read_text());perf=json.loads((B/'results/performance-summary.json').read_text());pose=json.loads((B/'results/pose-baseline/score.json').read_text());six=json.loads((B/'results/pose-six-frames/score.json').read_text())
names={'qwen3vl':'Qwen3-VL-2B 4-bit（旧模型重跑）','qwen35':'Qwen3.5-2B 4-bit','qwen35-4b':'Qwen3.5-4B 4-bit','gemma4':'Gemma 4 E2B IT 4-bit','smolvlm':'SmolVLM2-500M BF16'}
lines=[]
for key in names:
 r=scores[key+'-common'];a=r['statistics']['seen-comparison'];b=r['statistics']['unused-trial-confirmation'];lines.append(f"| {names[key]} | {a['correct']}/{a['n']} | {b['correct']}/{b['n']} | {r['controlsPassed']}/{r['controlsN']} | {b['abstentions']} 拒答 / {b['invalid']} 无效 |")
quality='\n'.join(lines);lines=[]
for key in ['qwen35','qwen35-4b','gemma4']:
 r=scores[key+'-recommended'];a=r['statistics']['seen-comparison'];b=r['statistics']['unused-trial-confirmation'];lines.append(f"| {names[key]} | {a['correct']}/{a['n']} | {b['correct']}/{b['n']} | {r['controlsPassed']}/{r['controlsN']} |")
sampling='\n'.join(lines);lines=[]
for tag,group in [('10Hz 骨架主基线：最近质心',pose['nearest-centroid']),('10Hz 骨架辅助对照：逻辑回归 C=1',pose['logistic-C1']),('相同六帧诊断：最近质心',six['nearest-centroid']),('相同六帧诊断：逻辑回归 C=1',six['logistic-C1'])]:
 counts=[]
 for split in ['seen-comparison','unused-trial-confirmation']:
  rows=[r for r in group['rows'] if r['split']==split];counts.append(f"{sum(r['correct'] for r in rows)}/{len(rows)}")
 lines.append(f"| {tag} | {' | '.join(counts)} |")
pose_table='\n'.join(lines);lines=[]
for r in perf['models']:
 lines.append(f"| {names[r['model']]} | {r['generateP50Seconds']:.2f} / {r['generateMaxSeconds']:.2f} 秒 | {r['preprocessedTotalP50Seconds']:.2f} 秒 | {r['wholeProcessPeakFootprintBytes']/2**30:.2f} GiB | {r['inputTokens'][0]} / {r['outputTokens'][0]} |")
perf_table='\n'.join(lines);receipts=[]
for p in sorted((B/'results').glob('*-download.json')):
 r=json.loads(p.read_text());weight=sum(f['bytes'] for f in r['files'] if f['file'].endswith('.safetensors'));receipts.append(f"| [{r['repo']}](https://huggingface.co/{r['repo']}/tree/{r['revision']}) | {weight:,}（{weight/1e9:.3f} GB） | `{r['revision'][:12]}` | [完整 SHA 回执](results/{p.name}) |")
model_table='\n'.join(receipts)
report=f'''# 端侧动作判错模型：Mac 同批真实视频对比

2026-10-16。**新增四套完整模型已下载并校验上游 SHA，五套 VLM 已在真实 Mac Metal GPU 上运行。当前更值得继续的是 MediaPipe + 专用小分类器；本轮没有一套通用 VLM 通过自动纠错验收。未安装或启动 iPhone App，实验没有接进主 App。**

[打开逐帧证据查看器](review.html)：可切换片段、模型、采样模式，查看真实参考帧、待评帧、原始回答和骨架反馈草稿。[全部机器评分](results/comparison-score.json)。

## 判错与看懂动作分开验收

Qwen3.5-4B 在五个基础事实检查中 **5/5** 通过，覆盖完整回起、静止、空白、上半身裁切和只下降未回起。但它对十段留出试次的具体偏差只有 **1/10** 命中，集中输出 high。可以观察到基本时序，不等于能可靠地知道哪里做错。

骨架小分类器在相同十段试次中，主基线为 **6/10**，事先固定的辅助逻辑回归为 **8/10**。辅助模型还有一段速度问题漏判成与示范相符、一段因所需特征覆盖率约 70% 拒答，不能称为“80% 全人群准确率”或已可发布。

## 数据、分组和评分边界

- 同批 12 段：上一轮已测过的 OfficeSquat 试次，用来直接比较新旧模型；不再称为未见样本。
- 新留出 10 段：此前未测过的试次，在本轮任何候选推理前固定文件、主标签、SHA、时间和提示；未用于小分类器拟合。各模型沿用同一清单，未依据结果修改提示。[初始冻结](results/frozen-suite.json)、[实际输入与最终英文协议](results/protocol-v1.json)。
- 五个事实控制：源自已保存的 Pexels 侧面深蹲，含完整动作、静止重复帧、灰色空白、裁切及截掉回起。它们测试可见事实和拒答，不作为动作规范的专家标签。
- OfficeSquat 是同一参与者的特定举臂蹲练习，主标签为 correct / high / low / tilt / arms / fast；论文描述 60 段，本地原始 ZIP 实有 62 段。没有把这套协议的“正确”当作通用徒手深蹲标准。[作者论文与数据出处](https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2022.669719/full)。ZIP 哈希和原始来源沿用[既有数据回执](../Qwen3VL-Mac-2026-10-16/results/office-source.json)。
- 新留出 high4_fast、arms1_fast 等含次级 fast 标签；主标签命中与“主或次标签命中”分别记录。表内主标签一致数不把拒答或格式无效剔除分母。correct 表示匹配参考，不是对安全或所有动作维度的认证。
- 全部 VLM 采用英文提示；SmolVLM2 官方主要语言为英文，避免中文能力成为额外混杂因素。[官方模型卡](https://huggingface.co/HuggingFaceTB/SmolVLM2-500M-Video-Instruct)。

## 五套 VLM 的实际结果

分类输入是六张正确参考 R + 六张待评 F，有帧序和真实采样时间；事实控制为六张 F。统一采用短标签或五字段观察任务，temperature=0、关闭 thinking、分类最多 16 新 token、观察最多 192，输入加输出上限 8192。分别记录处理后的张量形状和真实 token 数，没有把模型的图片 token ID 混用。

| 模型 | 同批 12 段主标签命中 | 留出 10 段主标签命中 | 五个事实检查严格通过 | 留出集拒答 / 无效 |
|---|---:|---:|---:|---:|
{quality}

- Qwen3.5-2B：主要选择 uncertain，不能把低误报解读为已能纠错；未回起片段仍出现 returned=yes。
- Qwen3.5-4B：五个事实检查均通过；具体偏差集中判成 high，对本来匹配示范的两段也报错。
- Gemma 4：具体偏差主要判成 correct；空白画面声称有人深蹲、缺少回起仍说已回起。
- SmolVLM2-500M：多图模式大量输出 R；改用官方 Transformers 视频处理器后大量输出 correct = matches R，仍不满足分类协议，也不能据此可靠区分偏差。单图空白诊断亦发生人物幻觉。[原生视频格式输入](results/smol-native-inputs.json)、[全部原始输出](results/smolvlm-native)。

旧 Qwen3-VL 的同批结果本轮是 1/12。为公平比较，新旧模型都在同一 Python 运行环境和同一保存 PNG 上重新推理；上轮 Swift 的 3/12 使用不同取帧和处理路径，不能与本表混当同一轮实验。

严格事实检查同时包含语义、字段和类型。例如静止时 returned=no 可没有编造运动，但不满足本轮要求的 uncertain，属于严格协议失败；字符串 "null" 也不等同 JSON null。通过数不能独自代替对原始错误的检查，查看器保留完整回答。

### 官方推荐采样参数补测

没有仅凭 greedy 结果否定模型。Qwen3.5 使用 temperature=.7、top_p=.8、top_k=20、presence_penalty=1.5；Gemma 4 使用 temperature=1、top_p=.95、top_k=64。均关闭 thinking、固定随机种子 17；这是单次采样诊断，不是种子稳定性证明，也没有挑选较好的随机结果覆盖主实验。[Qwen 参数出处](https://huggingface.co/Qwen/Qwen3.5-2B)、[Gemma 参数出处](https://huggingface.co/google/gemma-4-E2B-it)。

| 推荐采样模式 | 同批命中 | 留出命中 | 事实严格通过 |
|---|---:|---:|---:|
{sampling}

参数切换没有解决具体偏差判断；4B 在该模式还出现把错误片段判断为 correct 的情况。更长 thinking、微调后能力、原始 BF16 候选和其他输入分辨率未被本轮穷尽，不将本结果外推为所有 VLM 都不能做此任务。

## 更贴近端侧的专用方案

用主 App 相同 SHA 的 **MediaPipe Full 资产 {perf['pose']['modelBytes']:,} 字节**，在 Mac CPU 上真实提取骨架。18 段训练试次，每类三段；测试为前述 12 + 10 段，训练归一化只拟合训练集。每帧计算 14 个投影几何量，包括膝/髋角、手腕和肘相对肩高、左右高度差、躯干与腿长归一化位置；加分位数、实际活动时长和角速度共 44 维。最近质心及 C=1、class_weight=balanced 的逻辑回归预先固定，没有根据留出结果搜索超参数。

| 固定分类器及输入 | 同批 12 段 | 留出 10 段 |
|---|---:|---:|
{pose_table}

**公平性限制：VLM 是一段正确参考下的零样本分类，小分类器使用了 18 段有标签训练数据。主骨架方案还以 10Hz 看到更多帧。它们是在比较可落地的整条方案，分数不能当作同条件的基础模型排名。** 因此又给骨架分类器与 VLM 完全相同的六张 F 图作预算诊断；两种固定分类器均为 7/10，速度问题仍是主要遗漏。六帧诊断不是额外的人物留出实验。

10Hz 辅助逻辑回归的十段留出细分：correct 2/2、high 1/1、low 1/2（另 1 段拒答）、tilt 2/2、arms 1/1、fast 1/2。已经识别到特定示范下的可见差异；本轮没有训练足跟离地、腰背形态、侧面膝内扣等标签，不输出这些结论。正面投影膝角也不等于真实 3D 屈膝角。

两个小分类器已导出可移植 JSON，分别 **{perf['pose']['centroidHeadBytes']:,} / {perf['pose']['logisticHeadBytes']:,} 字节**；辅助分类器导出后的矩阵推理与原始结果逐例核对，22/22 一致。[质心模型](results/pose-baseline/tiny-head.json)、[逻辑回归模型](results/pose-baseline/tiny-logistic-head.json)、[训练与评估协议](results/pose-baseline/frozen-protocol.json)、[具体草稿与测量](results/pose-baseline/review-drafts.json)。

草稿包含候选问题、所需特征覆盖率、关节测量与参考值、调整文本和具体拒答原因。建议仅针对 OfficeSquat 本次示范，例如手臂高度较低；不能把双臂必须抬平套用到一般深蹲。所有候选均 reviewRequired=true、eligibleForAutomaticCoaching=false。覆盖率较低会拒答；集中发生在最低点的短时丢点、机位变化、身体比例和连续视频分段仍需更严格验证。

## Mac 内存与耗时

实时核对设备为 **Apple M5 Pro / 48GiB / macOS 26.5.1**。新环境 MLX-VLM 0.6.0、MLX/Metal 0.32.4、MLX-LM 0.32.1、Transformers 5.20.0；骨架为 MediaPipe 1.1.1、scikit-learn 1.9.1。[依赖冻结](evidence/python-packages.txt)、[设备记录](evidence/environment.json)。

下表各模型重新加载后重复同一组六张真实图六次，剔除第一次，报告余下五次暖请求；输入文件和 shader 缓存已热，GPU 推理顺序执行。相机没有同时运行。PNG 已提取，合计包含读图与预处理，不含视频解码、相机或 UI。每模型处理器不同，Qwen 图片像素预算 65536–131072、Gemma 140 soft-token 预算、Smol 不切图；真实 token 数及张量形状均在回执里。

| 模型 | 推理 P50 / 最大 | 读图预处理及推理合计 P50 | 整进程峰值 footprint | 输入 / 输出 token |
|---|---:|---:|---:|---:|
{perf_table}

耗时含视觉编码、prefill 与输出；输出长度不同，不能只按耗时排能力。内存列为 time -l 进程级 peak memory footprint，另有每 50ms 采样、RSS 和 MLX peak 保留，几种内存口径不混用。五个重复是性能样本，不是五个独立动作样本。[逐次数据与统计](results/performance-summary.json)。

骨架主实验共处理 **{perf['pose']['clips']} 段 / {perf['pose']['sampledFrames']} 个采样帧**；每段单帧推理 P50 的中位数为 **{perf['pose']['perClipInferenceMedianP50Seconds']*1000:.2f}ms**（CPU），小分类器矩阵推理 P50 **{perf['pose']['classifierOnlyP50Seconds']*1e6:.1f}μs**，整个 CPU 实验进程峰值 footprint **{perf['pose']['wholeProcessPeakFootprintBytes']/2**30:.2f}GiB**。前者不是相机整条链路延迟；VLM 与骨架也不是相同计算任务。**这些数字均不是 iPhone 的内存、时延或发热结论。**

## 实际发现并修复的问题

1. **Gemma 4 共享 KV 接入错误**：MLX-VLM 0.6.0 为最后 20 个共享层创建了不存在的 K/V 投影和 K norm，严格加载报缺 60 个参数。按共享层架构省略这些未使用模块，保留 strict=True，没有随机补权重或忽略缺失。补丁与上游 Swift 3.32.3 的实现一致。[补丁](evidence/gemma4-shared-kv.patch)、[原始与修复源码 SHA](evidence/gemma4-runtime-patch.json)、[上游实现](https://github.com/ml-explore/mlx-swift-lm/blob/3.32.3/Libraries/MLXVLM/Models/Gemma4.swift)。初始失败及修复后的成功记录都保留。
2. **独立路径检查 Gemma 误判**：用现有 Release Swift/MLX 运行相同视频、时间和 140 token 预算的七个诊断，模型权重及 tokenizer 通过符号链接保持原文件；处理配置是单独派生文件。Swift 亦将空白说成有人深蹲、将未回起说成已回起。旧 CLI 的启动日志固定写 Qwen3-VL，但实际目录配置为 model_type=gemma4，environment 记录实际模型路径；加载器按配置分派。两条路径共享 MLX 底层，且重取帧与缩放不保证位级相同；这不是独立硬件或原始 BF16 验证。[Swift 原始结果](results/gemma4-swift-diagnostic)、[派生配置来源](evidence/swift-gemma-shadow.json)。
3. **AVI 头部帧数大于实际可解码帧数**：训练 low3 声称 108 帧，顺序实际可读 105 帧，按声明末尾随机寻帧会失败。骨架入口改为顺序解码，以实际解码帧和时间计算特征；40 段中记录到 {perf['pose']['declaredDecodeMismatchClips']} 段有此差异，未通过减少识别阈值绕开。VLM 的六帧输入全部实际读取成功，文件和帧 SHA 固定。全部差异与原始记录保留。
4. **输出资格与错误计分分离**：模型运行成功不等于判错通过；拒答、类型错误、无效标签和危险事实全部留在评分和原始回答中。骨架结果不回写训练总结、计次或主 App，建议未自动发布。

## 模型文件与复现

新下载权重共约 9.322 GB（十进制），均保存在 Library/Application Support/AIFormCoach/Models，数据、帧和大张量在 Library/Caches/AIFormCoach/Benchmarks。权重没有加入仓库。[完整张量存储审计](evidence/tensor-storage-audit.json)确认四套均包含实际视觉权重；Smol 本地文件全部为 BF16。

| 固定模型 | 完整权重字节数 | 固定修订 | 校验 |
|---|---:|---|---|
{model_table}

Gemma E2B 的 E 表示有效参数规模，官方列出含嵌入约 5.1B，不能把 E2B 当成只有 2GB 文件。[官方参数表](https://huggingface.co/google/gemma-4-E2B-it)。所选固定社区卡仍标 gemma 许可，当前官方卡标 Apache 2.0，差异如实留在原始 metadata；本轮只作本地研究，未分发模型或数据。

本地重跑示例（Python 3.12，所列路径是本次隔离环境）：

```sh
uv venv --python 3.12 /tmp/coach-alternatives-venv
uv pip install --python /tmp/coach-alternatives-venv/bin/python -r evidence/python-packages.txt
python3 scripts/download_candidates.py
python3 scripts/download_candidates.py mlx-community/Qwen3.5-4B-MLX-4bit
python3 scripts/patch_gemma_runtime.py
/tmp/coach-alternatives-venv/bin/python scripts/compare_vlm.py \\
  '/Users/kids/Library/Application Support/AIFormCoach/Models/Qwen3.5-4B-MLX-4bit/32f3e8ecf65426fc3306969496342d504bfa13f3' \\
  --suite results/protocol-v1.json --out /tmp/coach-qwen35-repeat
/tmp/coach-alternatives-venv/bin/python scripts/pose_baseline.py
/tmp/coach-alternatives-venv/bin/python scripts/pose_six_frames.py
```

命令从本报告目录执行；download_candidates 优先读取已保存 metadata 固定修订，不默认跟随 latest。既有 Qwen3-VL 对照权重及素材的恢复见[上一轮报告](../Qwen3VL-Mac-2026-10-16/README.md)。原生 Smol 预处理另用已有 Transformers 4.57.1 / Torch 2.9 CPU 环境，依赖见[快照](evidence/native-processor-python-packages.txt)。调度脚本需依次运行，避免同时进行模型或骨架推理。

[执行与源码校验清单](results/execution-manifest.json)记录原始日志、已解决的初始失败、命令和源码 SHA。没有进行 iPhone 安装、启动、签名或真机测试；没有提交或推送代码。

## 本轮选型判断及尚缺的证据

**继续做 MediaPipe + 本动作专用判错头，先输出少数可观测的问题及明确原因。** 当前已跑通几何特征 + 最近质心/逻辑回归，时序神经网络仍需训练与比较。后续可在多人、不同机位的侧面徒手深蹲数据上比较时序小模型，并由教练明确错误标签和目标；当前单人举臂协议的权重不能直接变成主 App 的通用教练。

计次与完整动作分段继续由已有姿态时序引擎承担。判错头对分段后的动作评价，低置信、机位不支持、关键阶段丢点时给出不可判断原因；调整文本依据确认的测量或标签生成，语言模型若参与，只解释已确认事实。当前实现的反馈草稿保持人工审核，未证明能在连续相机输入中稳定纠错。

仍待验证：人物分离的专家标注集、动作周期和关键阶段覆盖、真实手机拍屏域、不同衣着/遮挡/光线，以及 iPhone 相机并行时内存、耗时和发热。用户通知后才恢复手机安装相关工作。

作者的 Fitness-AQA 确实面向健身动作质量，但公开仓库当前审查没有现成可直接运行的健身分类 checkpoint，Code_Release 仍写 Work in Progress，数据申请说明限非商用；未提交对外申请，未声称已测这套模型。[作者仓库](https://github.com/ParitoshParmar/Fitness-AQA)。近期 FitAQA 预印本也区分视觉证据、动作判断与错误时段定位；这里仅借鉴评估思路，未把其尚未获取的数据当作实测样本。[论文](https://arxiv.org/html/2608.08736v1)。完整出处见[来源记录](evidence/sources.json)。
'''
(B/'README.md').write_text(report);print('Report written')
