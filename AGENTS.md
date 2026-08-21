# AGENTS.md

SmartEnglish Desktop 是一个 Flutter（Windows / Android）桌面与移动英语学习应用：AI 智能出题、对话助手、词汇剖析、模拟考试、游戏化工具（贪吃蛇 / 转盘 / 骰子）。Dart 负责 UI 与状态，性能敏感的逻辑（贪吃蛇）走 `native/` 下的 C/C++ 并通过 `dart:ffi` 每帧驱动。

本文件为本仓库的 agent（编码助手）约定。配套的 agent 技能在 `.agents/skills/`：

- `code-review` —— 评审 PR 时的重点清单（正确性、生命周期、安全、消费方适配）。
- `pre-push-checks` —— 推送前只跑最小相关检查，而非整套仓库校验。
- `find-simplifications` —— 寻找可简化/去重的候选，须有调用方证据。

## Commands

```sh
flutter pub get            # 安装依赖
flutter analyze            # 静态分析（pre-push 钩子也会跑增量版本）
flutter test               # 单元测试 / widget 测试
flutter build windows      # Windows 桌面构建（release）
flutter build apk          # Android 构建
```

## Repository layout

```
lib/            Dart UI 与状态：main.dart（入口/对话面板）、state.dart（AppState）、
                services/（api_service、storage、chat_capabilities、snake_logic FFI 绑定）、
                widgets/（各功能页与设置弹窗）、models.dart、grammar_store.dart
native/         C/C++ 性能逻辑（如 snake_logic），通过 dart:ffi 暴露
assets/         ai-icons/*.svg 模型头像、字体、图片等资源（pubspec 已声明）
.agents/skills/ 本仓库 agent 编码技能（见上）
```

## Conventions

- **状态集中**：可变应用状态在 `AppState`（`state.dart`），持久化走 `Storage`（`services/storage.dart`，基于 `shared_preferences`）。新增持久字段同步更新 `Storage` 与默认值。
- **UI 局部重建**：流式输出、棋盘动画等高频区域用 `ListenableBuilder` / `RepaintBoundary` 隔离重绘，避免整树 `setState`。动画与订阅（`Ticker` / `AnimationController` / `StreamSubscription` / `Timer`）必须在 `dispose()` 释放。
- **FFI 结构体稳定**：Dart 侧 `SnakeSnapshot` 等结构体字段顺序/布局必须与 `native/` 的 C 结构严格一致；**只改渲染/输入逻辑、不改字段布局时，旧 DLL 二进制兼容，无需重新构建 native**。改字段布局必须重建 native 并同步。
- **模型头像**：所有 `assets/ai-icons/*.svg` 为 `currentColor` 单色图标，运行时按品牌色染色。新增模型在 `main.dart` 的 `_getAiIconAsset(modelName)` 增加关键字映射即可。
- **显式 > 隐式**：跨边界（解析、持久化、FFI、平台通道）才做校验与默认值；同进程已类型化的调用不必加防御性 fallback。
- **注释讲契约**：注释陈述非显然的契约（前置/后置/不变量/兼容承诺），不叙述控制流、不抄代码、不保留 review 历史。
- **不推倒重做**：改进是增量锦上添花；新增能力以 skill / Agent Note 形式补充，不重写既有约定。
- **变更须有证据**：非平凡的 UI/行为改动应附带最小测试或验证步骤；文档随代码同 diff 更新。

## Editing these instructions

本文件是 repo 根的真实文件。保持每条规则自包含，链接到高层文档（如 `.agents/skills/*` 与 `docs/`）。清晰即可，不必冗长。
