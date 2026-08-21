# 计划：完善调试三件事 + 实现 highlight 源码查看

## 概述

继续推进 AI 助手调试遗留的三件事，并新增 highlight 源码查看功能：

1. **输出上限联动上下文窗口** —— 200k 上下文 → 16k 输出；1000k 上下文 → 128k 输出
2. **修复模型选择弹窗** —— 选中特效不改变 + 响应迟缓
3. **贪吃蛇帧率优化** —— 底层代码层面提升
4. **新增 highlight 源码查看功能** —— 在更多功能中可查看项目源码（带语法高亮 + 行号）

---

## 当前状态分析（Phase 1 已确认）

### 任务 1：输出上限
- `lib/state.dart:4578` 已按 `chatThinking` 区分：思考 32768 / 不思考 16384
- 用户要求按 **contextLength** 区分：
  - 200k → 16k
  - 1000k → 128k
- `effectiveContextWindow`（`lib/state.dart:5732-5736`）已能根据 `chatThinking` 返回 200K 或 1000K
- 需要做：把 `maxTokens` 改为按 effective context 动态计算

### 任务 2：模型选择弹窗（已发现 12 个问题点，关键问题如下）
| 位置 | 问题 | 原因 |
|------|------|------|
| `lib/main.dart:2483` | `initialIdx = s.useAutoModel ? -1 : -1` | 写错，初始高亮计算逻辑全是 -1 |
| `lib/main.dart:2482-2493` | 用 `s.apiConfig` 匹配而非 `s.effectiveChatConfig` | 开了"独立配置"时高亮错位 |
| `lib/main.dart:2481` | 列表用 `s.apiProfiles`（全局） | 看不到 chat 专用配置 |
| `lib/main.dart:2654-2658` | model row 写入全局 `saveApiProfiles` | 改的是 apiConfig，破坏"对话助手模型选择器"语义 |
| `lib/main.dart:2742-2855` | 三处 StatefulBuilder 内 `var selectedIdx` | setState 后变量被重置，导致选中态视觉上"没变" |
| `lib/main.dart:3072-3079` | 底部按钮读 `effectiveChatConfig.model` | 与弹窗写入不匹配，造成"没生效"假象 |

### 任务 3：贪吃蛇帧率
- `lib/widgets/snake_game_page.dart` 已用 `Ticker` 跟随屏幕刷新率
- `_frameSignal` 驱动棋盘重建 + `RepaintBoundary` 包裹（行 366、381）
- `_SnakePainter.shouldRepaint` 返回 `true`（行 595）—— **每帧强制重绘**，是潜在瓶颈
- 食物脉动用 `math.sin(_pulseTime / 180000 * math.pi)`（行 360-362）—— `pulse` 本身在 ValueListenableBuilder 中参与构建
- C++ 端：每帧 `advance(dt)` 拷贝坐标到 4 个 int 数组（`syncRenderArrays` 行 41-47、49-62）
- 优化方向：
  1. 让 `_SnakePainter.shouldRepaint` 智能判断（点 / 食物 / 颜色变化才返回 true）
  2. 食物脉动用 `AnimationController` 驱动并放在 `RepaintBoundary` 内（已部分做到）
  3. 蛇身点列表加缓存（仅 snakeLen 或 point 变化时重建）
  4. C++ `syncRenderArrays` 用 `memcpy` 替代逐元素赋值

### 任务 4：highlight 源码查看
- 当前依赖（`pubspec.yaml:9-22`）：无任何代码高亮包
- assets 结构：`assets/ai-icons/`、`assets/icons/model_settings.png`、词典等
- 更多功能入口：`lib/main.dart:1146-1147` 走 `_MoreSelectPage`
- 路由索引：蛇 `case 20`、五子棋 `case 23`、墨墨 `case 18`、浏览器 `case 19`
- 需要新增：`case XX` → `SourceViewerPage`

---

## 计划改动

### A. 修复模型选择弹窗（高优先级）

**文件：** `lib/main.dart`

1. **A1 修复 `initialIdx` 计算**（`lib/main.dart:2482-2493`）
   - 改为基于 `s.effectiveChatConfig` 而非 `s.apiConfig`
   - `useAutoModel` 为 true 时返回 -1；否则在 `effectiveChatConfig` 匹配 profile
   - 当 `chatApiIndependent` 开启时，从 `chatProfiles` 匹配；未开启时从 `apiProfiles` 匹配

2. **A2 修复 StatefulBuilder 状态**（`lib/main.dart:2742-2855` 三处）
   - 把 `selectedIdx` / `maxMode` 提升为**外层 closure 变量**（在 `_showChatModelSelector` 函数顶部用 `int selectedIdx` 声明），通过 `setState` 修改
   - 避免每次 build 重新初始化导致视觉"无变化"
   - 关闭弹窗时（即时提交式设计，状态变量不需重置）

3. **A3 修复 model row onTap 写入路径**（`lib/main.dart:2654-2658`）
   - 根据 `chatApiIndependent` 走不同写入：
     - 开启：调 `s.saveChatProfiles(s.chatProfiles, i)`
     - 关闭：调 `s.saveApiProfiles(s.apiProfiles, i)`（原行为）
   - Auto 行同理（`enableAutoModel` 需独立处理：始终作用于全局 useAutoModel，不影响 chatApiIndependent）

4. **A4 列表源选择**（`lib/main.dart:2481`）
   - `final profiles = s.chatApiIndependent ? s.chatProfiles : s.apiProfiles;`

5. **A5 底部按钮显示来源标注**（`lib/main.dart:3072-3079`）
   - 当 `chatApiIndependent` 为 true 时，在 modelLabel 旁加一个"独立"小标识

### B. 输出上限联动上下文窗口（中优先级）

**文件：** `lib/state.dart`、`lib/services/api_service.dart`

1. **B1 新增 helper 计算**
   - 在 `lib/state.dart` 中新增：
     ```dart
     int get effectiveOutputLimit {
       final ctx = effectiveContextWindow;
       if (ctx >= 1000000) return 128000;  // 1M 上下文 → 128K 输出
       if (ctx >= 500000) return 64000;    // 500K 中间档
       return 16000;                       // 默认 200K 上下文 → 16K 输出
     }
     ```

2. **B2 替换 `lib/state.dart:4578` 的硬编码**
   - 改为 `maxTokens: chatThinking ? (effectiveContextWindow >= 1000000 ? 128000 : 32768) : effectiveOutputLimit`
   - 或更简洁：`maxTokens: chatThinking ? min(32768, effectiveContextWindow ~/ 8) : effectiveOutputLimit`

### C. 贪吃蛇帧率优化（中优先级）

**文件：** `lib/widgets/snake_game_page.dart`、`native/snake_logic/snake_logic.cpp`

1. **C1 `_SnakePainter.shouldRepaint` 优化**（`lib/widgets/snake_game_page.dart:594-595`）
   - 当前：`return true;`
   - 改为：比较 `points`、`cw`、`ch`、`isLight`，任一不同才返回 true（避免 Theme 等无关变化触发重绘）

2. **C2 蛇身点列表缓存**
   - 在 `_SnakePainter` 中持有 `List<Offset>? _cachedPoints`
   - `paint` 中若 `points.length == _cachedPoints.length` 且 `cw/ch/isLight` 未变，直接复用上次 path
   - 或在 `_build` 中根据 `snakeLen` 变化才 `new` 一次 `_SnakePainter` 实例

3. **C3 食物脉动优化**
   - 当前的脉动计算在 `ValueListenableBuilder` 内参与 build（`lib/widgets/snake_game_page.dart:355-363`）
   - 把 `pulse` 提取为 `ValueListenable<double>` 驱动，让 `_FoodDot` 自己监听（已部分做到），但 `pulse` 仍参与 build
   - 改为：`_FoodDot` 内部持有 `AnimationController` 或自驱 `Ticker`，不依赖外层 `pulse` 值

4. **C4 C++ `syncRenderArrays` 用 memcpy**
   - `native/snake_logic/snake_logic.cpp:41-47` 和 `49-62` 用 `std::memcpy` 替代 for 循环赋值

### D. highlight 源码查看功能（新增，中优先级）

**新文件：** `lib/widgets/source_viewer_page.dart`

1. **D1 添加依赖** `pubspec.yaml:9-22`
   - 添加 `highlight: ^0.7.0`（纯 Dart，无 WebView 依赖）
   - 体积增量：~1-2 MB

2. **D2 源码查看页面骨架**
   - 顶部：返回按钮 + 标题 + 语言下拉（dart / yaml / json / cpp / text）
   - 中部：可滚动 `ListView.builder`，每行 = 行号 + 语法高亮代码
   - 配色：跟随 `c.isLight` 切换主题（深色/亮色）
   - 使用 `highlight.parse(code, language: 'dart')` 拿到 `Node` 树，递归渲染 `RichText`

3. **D3 源码加载策略**
   - 优先级 1：打包部分精选文件到 assets（`assets/sources/`）
     - `state.dart`、`api_service.dart`、`main.dart` 的关键片段
     - `snake_logic.h/cpp`
   - 优先级 2：UI 上提供"选择文件"按钮调 `file_picker` 选本机文件
   - 不在生产环境直接读应用包内（Flutter 桌面 AOT 编译后源码不可读）

4. **D4 路由接入** `lib/main.dart:1140-1141` 之后
   - 新增 `case 21: return const _PageScaffold(title: '源码查看', child: SourceViewerPage());`
   - 在"更多功能"页（`lib/widgets/...`）添加入口卡片
   - 入口图标：`Icons.code_rounded` 或 `Icons.data_object_rounded`

5. **D5 语法高亮主题**
   - 浅色：`github` 风格
   - 深色：`monokai-sublime` 风格
   - 行号列固定宽度，右对齐，灰色

---

## 假设与决策

- 假设 1：用户接受用 `highlight` 纯 Dart 包，不走 WebView（体积最优）
- 假设 2：弹窗即时提交设计保留不变（用户已熟悉"点哪行就生效"）
- 假设 3：贪吃蛇帧率优化不引入新依赖（仅修改现有 Dart + C++ 代码）
- 假设 4：源码查看初期只展示项目精选文件，未来可扩展为本地文件浏览器

## 验证步骤

1. **弹窗测试**：
   - 开启"独立配置"，加 chat 专用模型，关闭独立配置 → 弹窗列表切换正确
   - 在弹窗内点不同行 → 底部按钮立即同步更新
   - 切换 Auto → 弹窗高亮回到 Auto 行

2. **输出上限测试**：
   - 1000k 上下文模型发长文本 → 输出预算 128k
   - 200k 上下文模型发长文本 → 输出预算 16k
   - 16k 不够时自动降级（保留 8192 fallback）

3. **贪吃蛇测试**：
   - 120Hz 屏幕 FPS ≥ 110
   - 60Hz 屏幕 FPS ≥ 55
   - 蛇身长 50+ 时帧率不掉

4. **源码查看测试**：
   - 打开源码查看页 → 看到精选文件列表
   - 选 dart 文件 → 看到语法高亮 + 行号
   - 切换深色模式 → 主题跟随
   - 搜索"ApiConfig" → 关键字高亮（可选增强）

## 风险点

- 弹窗改造会改变"对话助手选模型影响全局"的行为，可能与用户预期不符 → 与用户对齐
- C++ 端 memcpy 改造需要重新编译 .so / .dll，CI 流程需同步
- highlight 包在 Android Release 模式下的 R8/Proguard 兼容性需验证
