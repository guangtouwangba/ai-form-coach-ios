# AI 动作教练视觉规范

视觉系统以暖白准备界面和深墨绿训练界面建立自然的模式切换，Coach Mint 只用于确认、选中与主操作，Coaching Amber 只用于动作建议，Safety Red 仅用于权限、硬件或不可恢复错误。

## 核心令牌

```css
:root {
  --bg: oklch(0.972 0.006 145);
  --surface: oklch(1 0 0);
  --fg: oklch(0.235 0.018 174);
  --muted: oklch(0.532 0.014 170);
  --border: oklch(0.924 0.008 150);
  --accent: oklch(0.696 0.128 174);
}
```

## 字体

- Display：SF Pro Display、PingFang SC、-apple-system
- Body：SF Pro Text、PingFang SC、-apple-system
- Mono：SF Mono、Menlo、monospace

## 视觉语言

1. 准备、设置、总结与历史使用暖白画布和低压浅色表面；相机与训练进入深墨绿沉浸界面。
2. Coach Mint 每屏最多承担一个主操作和一个明确状态，不作为装饰铺陈。
3. Coaching Amber 表达可执行建议，普通动作问题不使用红色；Safety Red 仅表达权限、设备或不可恢复风险。
4. 训练中只保留远距离可读的计次、识别状态与两项关键操作，不展示实时评分或密集角度数据。
5. 所有反馈以中性、下一次可执行的中文表达，并通过图标、文字与语音共同传达状态。
