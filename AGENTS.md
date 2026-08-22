# AGENTS.md

SmartEnglish Desktop 是一个 Flutter（Windows / Android）桌面与移动英语学习应用：AI 智能出题、对话助手（Agent 工具循环 / 技能商店 / MCP / 子 Agent）、词汇剖析、模拟考试、游戏（贪吃蛇单机·双人·多人联机 + 五子棋）。Dart 负责 UI 与状态，性能敏感的逻辑（贪吃蛇）走 `native/` 下的 C/C++ 并通过 `dart:ffi` 每帧驱动。

本文件为本仓库的 agent（编码助手）约定。配套的 agent 技能在 `.agents/skills/`：

- `code-review` —— 评审 PR 时的重点清单（正确性、生命周期、安全、消费方适配）。
- `pre-push-checks` —— 推送前只跑最小相关检查，而非整套仓库校验。
- `find-simplifications` —— 寻找可简化/去重的候选，须有调用方证据。

## Commands

```sh
flutter pub get            # 安装依赖
flutter analyze            # 静态分析（本仓库未安装 git hooks，本地检查即唯一门禁）
flutter test               # 单元测试 / widget 测试
flutter build windows      # Windows 桌面构建（release）
flutter build apk          # Android 构建
```

## Repository layout

```
lib/            Dart UI 与状态：main.dart（入口/对话面板）、state.dart（AppState，含 Agent
                工具循环）、models.dart、grammar_store.dart、theme_colors.dart、
                services/（api_service AI 调用、storage 持久化、chat_capabilities 模型能力表、
                agent_service 系统提示词与工具定义、skill_store 技能商店、mcp_client MCP
                stdio 客户端、dict_service/binary_dict 词典、maimemo_service 墨墨同步、
                tts_service 朗读、snake_logic FFI 绑定）、
                widgets/（答题 pages、考场 exam_page、学习 learn_page、语法 grammar_page、
                查词/生词/默写、贪吃蛇 snake_game/snake_pvp/snake_multi、五子棋 gomoku_page、
                设置 settings_dialog、开屏引导 onboarding_page、Agent 卡片 agent_rows、
                开发者控制台 dev_console、浏览器 browser_page 等）
native/         C/C++ 性能逻辑（snake_logic），通过 dart:ffi 暴露
assets/         ai-icons/*.svg 模型头像、icons/、skills/（内置技能商店）、sources/（源码
                查看器素材）、dict.bin/zsb-dict.bin 词典、questions.json、
                grammar_course.json（pubspec 已声明；无自定义字体，全部走系统字体）
.agents/skills/ 本仓库 agent 编码技能（见上）
.dsh/skills/    运行时用户自定义技能（.md，YAML frontmatter，应用内可发现/加载）
installer/      Windows 安装包（Inno Setup，afloat_setup.iss）
tool/           维护脚本（migrate_dict.dart、check_grammar_course.ps1）
deepseek-harness/  独立的 TS/Node 参考工程（仿 deepseek 官方 harness 的完整仓库，仅作
                设计参考，不参与 Flutter 构建与产物）
racing-game/    网页小游戏原型（独立 HTML/TS，非 Flutter 产物）
snake-game/     网页贪吃蛇原型（独立 TS，非 Flutter 产物）
config.yaml     项目级配置
安全勘察报告.md / 功能缺陷与Agent适配性调研报告.md   治理文档（安全与缺陷勘察基线）
```

## Conventions

- **状态集中**：可变应用状态在 `AppState`（`state.dart`），持久化走 `Storage`（`services/storage.dart`，基于 `shared_preferences`）。新增持久字段同步更新 `Storage` 与默认值，并纳入 `buildBackupJson`/`importBackup` 备份键清单。
- **UI 局部重建**：流式输出、棋盘动画等高频区域用 `ListenableBuilder` / `RepaintBoundary` 隔离重绘，避免整树 `setState`。动画与订阅（`Ticker` / `AnimationController` / `StreamSubscription` / `Timer`）必须在 `dispose()` 释放，暂停/结束态要停 Ticker 防空转。
- **FFI 结构体稳定**：Dart 侧 `SnakeSnapshot` 等结构体字段顺序/布局必须与 `native/` 的 C 结构严格一致；**只改渲染/输入逻辑、不改字段布局时，旧 DLL 二进制兼容，无需重新构建 native**。改字段布局必须重建 native 并同步。
- **模型头像**：所有 `assets/ai-icons/*.svg` 为 `currentColor` 单色图标，运行时按品牌色染色。新增模型在 `main.dart` 的 `_getAiIconAsset(modelName)` 增加关键字映射即可。
- **显式 > 隐式**：跨边界（解析、持久化、FFI、平台通道）才做校验与默认值；同进程已类型化的调用不必加防御性 fallback。外部数据解析失败要留诊断路径，不许 catch 后静默吞掉。
- **注释讲契约**：注释陈述非显然的契约（前置/后置/不变量/兼容承诺），不叙述控制流、不抄代码、不保留 review 历史。
- **不推倒重做**：改进是增量锦上添花；新增能力以 skill / Agent Note 形式补充，不重写既有约定。
- **变更须有证据**：非平凡的 UI/行为改动应附带最小测试或验证步骤；文档随代码同 diff 更新。

## Editing these instructions

本文件是 repo 根的真实文件。保持每条规则自包含，链接到真实存在的文档（如 `.agents/skills/*` 与根目录治理报告）。清晰即可，不必冗长。
