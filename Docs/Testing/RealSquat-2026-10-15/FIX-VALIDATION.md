# 站稳检测修复与本地优先验证

2026-10-15。修复前，同一段真实 Vision 输出在本地稳定复现“无法建立站稳、预期 5 次实际 0 次”。回归命令为：

```sh
swift test --filter SquatSessionTests/testActualVisionStandingAndFiveCyclesAtBothResolutions
```

修复前两种分辨率均失败，日志 `/tmp/coach-standing-red.log`；修复后通过。原始失败报告仍在 `results/`，修复结果在 `results-fixed/`，未覆盖失败证据。

## 根因与修改

原实现把 Apple Vision 的 confidence 和另一类模型的 visibility/presence 用相同的单点 0.65 门槛处理。侧面可连续跟踪的髋点置信度约 0.44–0.47，导致每一帧都在静态窗口之前被拒绝；提示却把低置信度混同为未入镜。Apple 对 confidence 的定义见 [VNRecognizedPoint](https://developer.apple.com/documentation/vision/vnrecognizedpoint)。

新规则分两层，不依赖视频名称、人物、分辨率或预期次数：

- Vision 专用候选帧证据：各点至少 0.30、四点均值至少 0.55、至少两个观察点达到 0.65；不接受预测点、缺失点、非有限坐标或出画。其他引擎保留原来的 0.65 策略。这些数值是研发启发式门槛，不是 Apple 推荐阈值或已标定的正确概率。
- 候选帧不会立即授权计次。还须满足合理腿段比例与全身几何，连续约 2 秒稳定站直，肩、髋、膝、踝稳定、膝角稳定且有足够实际时间样本。完成站稳后冻结所选侧、起始位置和腿段长度。训练中检查腿段长度偏差及相邻关键点速度，突跳或遮挡放弃半次；机位变化重新站稳，已完成次数保留。

这不是把所有模型、所有点统一降到更低置信度。单点证据成为候选条件，完整骨架、多个强观察点及时间连续性一起决定是否可用。置信度全部偏低或低置信度点位置不稳定时，即使画面静止也不会放行。

合成几何原本分别移动髋和膝，导致测试过程中腿段长度不合理地变化。新骨架校验暴露了这个夹具缺陷；夹具改为由等长腿段几何求膝位置，没有为旧夹具放宽人体比例保护。

提示区分未找到单人全身、关键点证据不足、身体移动、骨架跳变等原因；证据不足时建议改善光线/机位，不再一律声称身体没入镜。

## 本地优先：同一视频代码，无手机依赖

`App/VideoReplayAnalyzer.swift` 从 UI 服务文件中分离，算法没有复制一套。Mac CLI 和 iPhone 编译相同的解码器、`AppleVisionPosePerception` 与 `SquatSession`。

```sh
# 27 项核心测试，包含 iPhone 已捕获的真实 Vision 数据和保护性反例
swift test

# Mac 直接解码真实视频、执行 Vision，再计算完整周期
bash Scripts/replay-video.sh \
  Docs/Testing/RealSquat-2026-10-15/media/standing-then-five-squats-hd.mp4 \
  5 /tmp/squat-replay-result.json
```

CLI 返回非零退出码表示次数与人工预期不符或分析失败。JSON 记录首次站稳时间、逐次起止点及过程状态。命令无需网络、无需安装手机；它验证离线分析链，不能代表实时相机性能或所有拍摄条件。

## 实际结果

| 输入 | Mac 真实 Vision | iPhone 真实 Vision / App 导入模型 |
| --- | --- | --- |
| 原片，无足够站立阶段 | 不建立基线、0 次 | 不建立基线、0 次 |
| 540×960，开头站立 3 秒及 5 个循环 | 第 2000ms 建立基线，5 次 | 第 2000ms 建立基线，5 次 |
| 1080×1920，同上 | 第 2000ms 建立基线，5 次 | 第 2000ms 建立基线，5 次 |
| 独立人物正面/机位移动片 5319965，前 6 秒 | 不建立基线、0 次 | 本轮未重复手机验证 |
| 独立人物半身裁切片 4820063 | 不建立基线、0 次 | 本轮未重复手机验证 |

独立反例来源为 [cottonbro studio / 5319965](https://www.pexels.com/video/a-man-doing-squats-5319965/) 和 [Jaza Mirza / 4820063](https://www.pexels.com/video/a-man-doing-squats-4820063/)，均适用 [Pexels License](https://www.pexels.com/license/)。下载来源及处理方式随本目录归档。选择依据是人工查看画面，不依据算法是否通过来挑选。

自动验证：27 项核心测试通过；模拟器集成 17 通过、5 条件跳过、0 失败；iPhone 本轮选择的 6 项集成全部通过，包括三段输入的真实视频回放与 App 导入方法、自动站稳计次保存、相机首帧/退出/恢复/进入训练连续性。模拟器首次构建因未限制架构而找不到 x86_64 的核心模块，改为现有 arm64 配置重跑通过。真实视频的正常版本安装在以上验证之后进行。

测试包：`/tmp/coach-standing-fixed-device.xcresult`。模拟器日志 `/tmp/coach-standing-simulator-final.log`。手机测试没有替代真人实际运动验收；正例仍来自同一真人动作循环五遍，两个分辨率也不是独立动作样本，因此目前只能证明本轮缺陷已修复及这些反例受保护，不能宣称通用准确率。

后续应继续冻结不同人物、衣着、机位、速度和真实站立抖动的独立样本；每新增样本先人工标注，再运行本地回放，最后验证手机实时输入。
