# AI 动作教练设计文稿索引

最后整理：2026-08-31  
当前版本：v3 Production

## 从这里开始

1. 用 `ai-action-coach-prototype-v3.html` 浏览全部页面和组件。
2. 用 `FLOW-MAP-v3.md` 理解 P0 主流程、异常恢复与 P1 异步流程。
3. 用 `SCREEN-STATE-MATRIX.md` 查某个页面的进入条件、操作、下一状态、恢复、网络、上传与无障碍要求。
4. 工程实现读取 `DESIGN-MANIFEST-v3.json`，并遵守 `DESIGN-HANDOFF.md`。
5. 产品定稿查看 `DESIGN-AUDIT-v3.md` 中仍待决定的五项问题。

## 当前真相文件

| 文件 | 用途 | 使用者 |
| --- | --- | --- |
| `ai-action-coach-prototype-v3.html` | 98 个页面/状态与 27 个组件的可交互总画板 | 产品、设计、开发 |
| `DESIGN-MANIFEST-v3.json` | 状态、跳转、边界与组件的机器可读清单 | 开发、测试、AI 编码工具 |
| `SCREEN-STATE-MATRIX.md` | 每个状态的完整行为契约 | 产品、开发、测试 |
| `FLOW-MAP-v3.md` | 用户主流程、异常恢复、Gemini 异步流程 | 产品、开发 |
| `DESIGN-HANDOFF.md` | 实现约束、优先级与验收门槛 | 开发、测试 |
| `DESIGN-SYSTEM.md` | SwiftUI 令牌、组件、语义和使用规则 | 设计、开发、测试 |
| `DESIGN-AUDIT-v3.md` | 完整性结论、已覆盖范围、待定问题 | 产品负责人 |
| `V2-TO-V3-CHANGELOG.md` | 33 张 v2 画板到 v3 状态的映射 | 设计、产品 |
| `brand-spec.md` | 品牌基础说明 | 设计、开发 |

## 视觉参考资产

- `assets/bulgarian-split-squat-hero.png`：动作选择/介绍视觉。
- `assets/bulgarian-split-squat-camera.png`：实时相机背景参考。
- `assets/accessibility-high-fidelity-concept.png`：无障碍方向。
- `assets/system-device-high-fidelity-concept.png`：系统与设备异常方向。
- `assets/local-data-recovery-high-fidelity-concept.png`：本地保存、草稿和删除方向。
- `assets/gemini-review-high-fidelity-concept.png`：高级复盘、购买、上传同意与异步任务方向。
- `assets/gemini-results-delete-high-fidelity-concept.png`：结果分层、冲突、不确定与云端删除方向。

概念图仅控制视觉方向；页面名称、导航、数字、上传范围和行为以 v3 manifest 与状态矩阵为准。

## 历史文件

- `ai-action-coach-prototype-v2.html`：33 画板旧版原型。
- `review-gallery.html` 与 `review-screenshots/`：v2 逐页截图总览。
- `ai-action-coach-prototype.html`：更早版本原型。
- `DESIGN-MANIFEST.json`：旧导出工具兼容索引；不要用它生成当前页面。
- `DESIGN-GAPS-AND-V3-PROMPT.md`：生成 v3 前的缺口分析和设计 Prompt，作为需求来源留档。

## 原始归档

合并前收到的原压缩包保存在上一级目录：`../AI-Coach-Prototype-v3.zip`。旧归档也保留在项目中，便于校验来源和回滚。
