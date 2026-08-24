# 本地依赖审计（2026-08-24）

## 检测结果

| 项目 | 本机结果 | P0 影响 |
|---|---|---|
| macOS | 14.2.1，Apple M2，24 GB | 可进行本地原型开发 |
| Xcode | 15.4 | 可编译 iOS 17.5；不能作为 2026 App Store 最终提交工具链 |
| Swift | 5.10 | Core package 与单元测试可用 |
| iOS SDK | 17.5 | target-level 模拟器编译可用 |
| 模拟器 runtime | 17.4 已登记，但 scheme 无合格 destination | 当前机器不能执行 App/UI 测试 |
| 真机 | 未连接 | 相机、TTS、功耗与端到端延迟尚不能本机验收 |
| 签名 | 无证书、无开发账号 | 不能安装到真机或归档分发 |
| CocoaPods | 1.15.2 | 需设置 UTF-8 locale |
| MediaPipeTasksVision | 1.0.0 | pod 可下载，但二进制引用 Xcode 15.4 SDK 不具备的 Metal 符号 |

## 已验证的兼容策略

默认构建使用 Apple Vision 2D 后备适配器，因此 Xcode 15.4 target build 成功。MediaPipe 是明确的 opt-in：升级到 Xcode 26 后执行 `ENABLE_MEDIAPIPE=1 pod install`，并添加 `MEDIAPIPE_ENABLED` 编译条件。

模型文件 `App/pose_landmarker_full.task` 的固定 SHA-256：

```
4eaa5eb7a98365221087693fcc286334cf0858e2eb6e15b506aa4a7ecdcec4ad
```

## 发布前必须补齐

1. macOS 15.6+、Xcode 26+ 与对应 iOS Simulator runtime。
2. Apple Developer Program 团队、唯一 bundle identifier 和签名配置。
3. 至少两档真机：目标最低性能设备与一台当前主流设备。
4. MediaPipe 构建、真机 Metal 路径和模型许可证复核。
5. App Store Connect 隐私问卷、隐私政策 URL、支持 URL、截图与年龄分级。
6. 生成最终 App Icon，并在 Xcode 26 构建中重新启用 asset catalog 的 AppIcon 编译设置。
