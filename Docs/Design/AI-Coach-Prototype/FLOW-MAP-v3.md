# AI 动作教练 v3 Flow Map

## P0 端侧主流程

```mermaid
flowchart TD
  A[P0-LAUNCH 启动] --> B[P0-SAFETY 安全说明]
  B --> C[P0-HOME 产品首页]
  C --> D[P0-EXERCISE-LIBRARY 动作库]
  D --> E[P0-SESSION-SETUP 会话设置]
  E --> F[P0-CAMERA-GUIDE 侧面机位]
  F --> G{摄像头权限}
  G -->|已授权| H[P0-CALIBRATION-READY]
  G -->|拒绝| I[P0-PERMISSION-DENIED]
  I --> J{从系统设置返回}
  J -->|已授权| H
  J -->|仍拒绝| I
  H --> K[P0-CALIBRATION-RUNNING]
  K -->|一致且充分| L[P0-CALIBRATION-SUCCESS]
  K -->|差异较大| M[P0-CALIBRATION-INCONSISTENT]
  M --> K
  L --> N[P0-TRAINING-ACTIVE]
  N --> O[P0-END-SET-CONFIRM]
  O --> P{组总结}
  P -->|无成立问题| Q[P0-SUMMARY-CLEAN / 不显示下一组建议]
  P -->|有成立问题| R[P0-SUMMARY-ISSUES / 完整聚合]
  R --> S[P0-REP-DETAIL / 单次重复全部问题与证据]
```

P0 的实时计数、动作问题和可靠性判断完全在端侧完成。完整且证据充分的重复即使存在问题也计数；证据不足时显示“无法可靠判断”或保持沉默。

## 训练会话与多组流程

```mermaid
flowchart LR
  A[会话设置<br>动作／训练腿／目标] --> B[建立一次会话校准基线]
  B --> C[第 1 组训练]
  C --> D[第 1 组 Summary]
  D -->|再做一组| E[P0-NEXT-SET-READY]
  E --> F[沿用动作、训练腿、目标、校准基线]
  F --> G[第 2 组训练]
  G --> H[第 2 组 Summary]
  H -->|继续| E
  D -->|完成会话| I[P0-SESSION-COMPLETE]
  H -->|完成会话| I
  I --> J[P0-HISTORY-SESSION-DETAIL]
  J --> K[会话内多个训练组]
```

只有会话级设置发生会影响基线的变化时，产品才要求重新校准；普通“再做一组”不重复设置和校准。

## 系统异常与恢复

```mermaid
flowchart TD
  T[P0-TRAINING-ACTIVE] --> Q{画面质量}
  Q --> Q1[太近／太远／头脚出框／遮挡]
  Q --> Q2[暗光／逆光／非侧面]
  Q --> Q3[训练腿不一致／多人入镜]
  Q1 --> R[暂停判断并给出单一修复动作]
  Q2 --> R
  Q3 --> R
  R -->|重新检查通过| T

  T --> I{系统中断}
  I --> I1[后台／锁屏／来电]
  I --> I2[音频中断]
  I1 --> F[P0-INTERRUPT-FOREGROUND]
  I2 -->|等价文字继续| T
  F -->|权限、相机、主体通过| T

  T --> D{设备或模型}
  D --> D1[过热／低电量／相机占用]
  D --> D2[模型加载或推理失败]
  D1 --> X[冷却、供电、释放相机或保存草稿]
  D2 --> X
  X --> F

  T --> E[P0-EXIT-MENU]
  E -->|放弃本组| A[P0-ABANDON-CONFIRM]
  A -->|保留完成重复| G[P0-ABANDON-KEEP-REPS]
  G --> H[P0-SESSION-GROUPS]
  T -->|进程退出| S[P0-DRAFT-RESUME]
  S --> F

  H --> V{本地事务}
  V -->|保存| V1[保存中／成功／失败／空间不足]
  V -->|删除| V2[确认／成功／失败]
```

恢复原则：会话设置、会话基线和已经成立的重复事实不会因中断而被重算或静默丢弃。

## P1 Gemini 高级复盘流程

```mermaid
flowchart TD
  A[P0 组总结已保存] --> B[P1-REVIEW-ENTRY]
  B --> C[P1-CAPABILITY-PRICE]
  C --> D{StoreKit}
  D -->|购买成功／恢复成功| E[P1-CONSENT-DATA-LIST]
  D -->|取消／失败| C
  E --> F[默认：动作分析记录 + 关键动作截图]
  F -->|短视频保持关闭| G[P1-PREPARE]
  F -->|独立 opt-in| H[P1-VIDEO-OPT-IN]
  H --> G
  G --> I[P1-UPLOADING]
  I --> J[P1-QUEUED]
  J --> K[P1-ANALYZING]
  K --> L[P1-BACKGROUND-CONTINUE]
  L --> M[P1-COMPLETE]
  M --> N[P1-RESULT-LAYERED]
  N --> N1[你的训练记录]
  N --> N2[Gemini 的解读]
  N --> N3[还不能确定的地方]
  N --> N4[下一组建议，最多三条]
  N -->|看动作详情| E[P0-REP-DETAIL]
  N2 -->|与端侧冲突| O[P1-RESULT-CONFLICT 需要复核]
  O -->|看看哪里不一致| E
  N3 -->|看训练结果| N
  N --> P[P1-CLOUD-RETENTION 管理已上传内容]
  P --> Q[P1-CLOUD-DELETING]
  Q -->|成功| R[P1-CLOUD-DELETE-SUCCESS]
  Q -->|失败| S[P1-CLOUD-DELETE-FAILED]
  S --> Q

  I -.无网络／超时／服务不可用／速率限制／额度用尽.-> X[P1-RETRY 或返回训练结果]
  K -.服务异常.-> X
  X --> G
```

P1 只能在组结束后异步运行。端侧计数和客观问题是不可覆盖的事实层；Gemini 的解释、不确定内容和冲突单独呈现。
