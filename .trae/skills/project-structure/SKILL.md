---
name: project-structure
description: AFloat 项目的功能结构总览与模块地图（目录、页面、状态、服务、Agent 工具、硬约束）。当需要新增/修改功能、理解项目架构、排查问题或迭代应用自身时加载，避免在不了解结构的情况下盲目改动。
category: 开发工具
source: builtin
---

# AFloat 项目功能结构总览

> 用途：本技能是"AFloat（smartenglish）Flutter 应用"的完整功能结构说明。
> 当你要新增功能、修改现有功能、排查问题或整体迭代应用时，**先加载本技能**获取项目地图，
> 再决定改动落点。禁止在不了解结构的情况下盲目搜索与修改。

## 1. 项目概况

- **应用名**：AFloat（smartenglish）—— 智能英语学习应用
- **技术栈**：Flutter 跨平台，Windows 桌面版与 Android 移动版**共用同一套 `lib/` 代码**
- **入口**：`lib/main.dart`；全局状态在 `lib/state.dart`（AppState，全项目最核心、最大的文件）
- **版本号与依赖**：`pubspec.yaml`（当前 1.1.2+4）
- **校验命令**：`flutter analyze`（改动后必须通过）
- **核心依赖**：http / shared_preferences / window_manager（仅桌面，Android 禁用）/ flutter_tts（朗读）/ audioplayers / flutter_inappwebview（浏览器）/ file_picker / pdf / excel / flutter_local_notifications（课程提醒）

## 2. 目录结构（lib/）

### 顶层

| 文件 | 职责 |
|---|---|
| `main.dart` | 应用入口、SmartEnglishApp、桌面布局（左侧导航 + 主内容 + 右侧 AI 助手约 30% 宽）、手机底部导航、聊天 UI（`_buildChatBubble` 等）、页面导航分发 |
| `state.dart` | `AppState extends ChangeNotifier`：聊天、AI Agent 工具循环、出题、MCP、技能目录、开发者日志等全部核心逻辑 |
| `models.dart` | 通用数据模型 |
| `theme_colors.dart` / `theme_diy.dart` | 主题配色 / 用户 DIY 背景主题 |
| `timetable_models.dart` | 课表领域模型 |
| `grammar_store.dart` / `exam_real_papers.dart` | 内置语法课程 / 历年真题数据 |

### services/（服务层，每个文件一个职责域）

| 文件 | 职责 |
|---|---|
| `api_service.dart` | OpenAI 兼容 API 请求；多模态 `buildContent`（文本+图片 base64 data URL）；`noThinkingParams`/`thinkingParams` 按模型返回 |
| `agent_service.dart` | Agent 系统提示词 `buildSystemPrompt(skillCatalog:)`、Agent 工具 schema（`_agentTools`） |
| `skill_store.dart` | 技能商店注册表：`kBundledSkillFiles`（assets/skills/*.md）+ `kNativeLearningSkills`（原生学习技能）；懒加载 |
| `mcp_client.dart` | MCP stdio 客户端：`McpServerConfig`/`McpTool`/`McpStdioClient`/`McpRegistry`；JSON-RPC 2.0 |
| `storage.dart` | shared_preferences 封装，全部配置/数据的持久化 |
| `dict_service.dart` / `binary_dict.dart` | 内置词典查询（dict.bin / zsb-dict.bin / cet4-dict.bin） |
| `tts_service.dart` | 语音朗读 |
| `update_service.dart` | 在线更新：远端 update.json 清单（多源直链）+ GitHub Releases 下载 |
| `notification_service.dart` | 本地通知（课程提醒，Android 需 Boot 接收器） |
| `wechat_service.dart` | 微信绑定（weixin_clawbot，扫码后自动应答回传） |
| `multi_agent_service.dart` | 多 Agent 协作 |
| `maimemo_service.dart` | 墨墨词库 API（需 Token） |
| `knowledge_base.dart` / `chat_capabilities.dart` | 知识库 / 模型能力表（如 vision 视觉支持） |
| `snake_logic.dart` | 贪吃蛇游戏逻辑 |

### widgets/（页面与组件）

| 文件 | 职责 |
|---|---|
| `pages.dart` | 错题本、报告、单词本、记录、词典、听写等学习页 |
| `learn_page.dart` | 主页（出题入口、题长滑动条、墨墨 MOE 模式） |
| `exam_page.dart` | 做题/答题区（生成题目、词汇剖析视图） |
| `exam_preset_dialog.dart` | 出题预设对话框 |
| `timetable_page.dart` / `timetable_settings_dialog.dart` / `timetable_format_doc.dart` / `edit_timetable_dialog.dart` | 课表功能（含导入/编辑，对应 timetable-import / timetable-edit 技能） |
| `grammar_page.dart` | 语法学习页 |
| `maimemo_wordbook_page.dart` | 墨墨词库页 |
| `browser_page.dart` | 内嵌浏览器 |
| `gomoku_page.dart` / `snake_game_page.dart` / `snake_multi_page.dart` | 五子棋 / 贪吃蛇 / 多人贪吃蛇 |
| `multi_expert_page.dart` / `debate_page.dart` | 多专家团 / 辩论模式 |
| `source_viewer_page.dart` | 源码查看器 |
| `platform_select_page.dart` | 平台选择页 |
| `settings_dialog.dart` | 设置对话框（高级功能、模型配置、MCP 等入口；MCP 管理 UI 当前已按需求隐藏但代码保留） |
| `agent_rows.dart` | Agent 执行轨迹卡片（工具行、思考行、子 Agent 卡、终端块） |
| `dev_console.dart` | 开发者模式控制台浮层（DevConsoleEntry 全局叠加） |
| `update_dialog.dart` | 在线更新弹窗 |
| `markdown_renderer.dart` | Markdown 渲染（含表格） |
| `code_card.dart` / `chart_card.dart` / `model_fetch_sheet.dart` / `onboarding_page.dart` | 代码卡片 / 图表卡 / 模型拉取 / 引导页 |
| `glass_background.dart` / `aurora_backdrop.dart` / `particle_backdrop.dart` / `diy_backdrop.dart` | 毛玻璃 / 极光 / 粒子 / DIY 背景 |

## 3. 页面导航清单（main.dart 分发）

主页 LearnPage、考场/套卷 ExamPage、课表 TimetablePage、报告 ReportPage、词典 DictionaryPage、错题本 WrongBookPage、单词本 WordBookPage、记录 RecordsPage、听写 DictationPage、语法 GrammarPage、墨墨词库 MaimemoWordbookPage、浏览器 BrowserPage、贪吃蛇 SnakeGamePage、五子棋 GomokuPage、多专家团 MultiExpertPage、辩论模式 DebatePage、源码查看 SourceViewerPage、真题、平台选择。

> Agent 跳转统一用原生工具 `goto_page`（参数如 learn / exam / timetable / report / dictionary / wrong / favorite / records / dictation / grammar / maimemo / browser / game / multi_expert / debate / source）。

## 4. 核心状态 AppState（state.dart）

- 全局访问：`AppScope`（InheritedWidget）+ `AppScope.of(context)`；状态为 ChangeNotifier
- **聊天刷新**：`chatUpdateNotifier`（ValueNotifier<int>）+ `_notifyChatUpdate([force])`，默认 50ms 节流；内容落定的关键节点（发送完成、Agent 循环结束、会话切换）必须用 `force=true` 否则可能被节流吞掉
- **发送消息**：`sendChat` → `_runAgentLoop`（Agent 工具循环，最多 8 轮，`callAIWithTools`）
- **图片多模态**：仅当模型 `cfg.vision == true` 才允许发送图片（base64 经 `ApiService.buildContent`）；无视觉模型显示红色提示
- **Agent 工具**：`executeTool` 统一分发；工具结果包装为 `ToolStep` 并经 `toolExecNotifier` 上报 UI
- **MCP**：`mcpRegistry`（McpRegistry）、`parseMcpConfigs` / `addMcpServer` / `removeMcpServer`；预置模板 `mcpTemplates`（12306-mcp / mcp-deepwiki / kuaidi100-mcp / mcp-server-git / github-mcp-server）；配置持久化在 `mcpConfigJson`；**Windows 下命令必须 `npx.cmd` 形式**（Process.start 不解析无扩展名）；kuaidi100-mcp 需填 `KUAIDI100_API_KEY`（添加时会弹窗），deepwiki/12306 零配置
- **技能商店**：`skillCatalog` 只把"名称+描述"目录注入系统提示词，全文仅 skill/load_skill 命中时加载（渐进式披露）；`skillsDisabledIds` / `customSkills` 持久化
- **devMode**：设置→高级功能开关；开启后捕获所有 AI 调用（提示词/推理/输出）到 `devLog`（≤2000 条），`DevConsoleEntry` 全局右下角浮层
- **出题**：`generateQuestions`、全卷 `_requestSectionWithRetry`、词汇剖析 `requestBatch`；`max_tokens = 200000`，异常降级 8192 重试；普通对话默认 4096
- **DeepSeek V4**：控制思考必须用 `{"type":"disabled"|"enabled"}`（api_service.dart 的 noThinkingParams/thinkingParams 已处理，state.dart 的 `_noThinkingParams` 同步）；布尔 `enable_thinking` 对 V4 无效

## 5. 关键机制与约定（改动时必读）

- **新增 Agent 工具的路径**：`agent_service.dart` 加工具 schema（名称/描述/参数 JSON Schema）→ `state.dart` 的 `executeTool` 加对应分支 → 详情可参考 `_subagentTools` 白名单模式
- **新增技能资产**：写 `assets/skills/<id>.md`（YAML frontmatter：`name`/`description`/`category`/`source`，正文为完整指令）→ 在 `skill_store.dart` 的 `kBundledSkillFiles` 注册 id；原生能力则加到 `kNativeLearningSkills`
- **在线更新**：远端仓库根目录 `update.json`（多源清单见 update_service.dart）+ GitHub Releases 安装包；应用启动约 6 秒后静默检查，有新版才弹窗
- **课程提醒（Android）**：Manifest 需 `RECEIVE_BOOT_COMPLETED` 权限且注册 `ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver`（曾因漏注册导致重启丢提醒）

## 6. 硬约束（不可违反）

1. 桌面版与 Android 共用 `lib/`；若用户提到"PC 端代码不许动只能参考"，只读不改
2. 用户强调"底层代码不变只变 UI"时，只允许改动界面表现层，禁止变更数据/业务逻辑
3. Android 平台禁止引入 Windows 专用插件（如 window_manager）
4. 应用名必须是 **AFloat**（前两个字母大写）
5. 考场/套卷必须**全屏**且**隐藏左侧导航**；考场底部功能合并到右侧答题卡区域；生成全卷成功后**直接进入考场**，不弹确认框
6. 词汇剖析**只分析英文内容**；翻译题剖析**英文答案（q.english）**而非中文题干
7. 词汇剖析未配置 API 时弹窗提示「API 尚未配置，请前往设置页面中配置」
8. 构建 exe/apk **必须先按 `flutter-build` 技能弹问卷确认 Flutter SDK 路径**，确认后才能构建；不构建 debug 版本
9. 出题接口一律 200k max_tokens（普通对话不受此约束）
10. UI 审美偏好：灰色系优先（灰 > 深紫/黑）、毛玻璃效果、选中项有明显视觉反馈；AI 思考过程可折叠且**不带 emoji 前缀**；工具调用前显示扳手图标（material 图标库）

## 7. Agent 迭代自身推荐工作流

1. 收到功能需求 → **先加载本技能**，查 §2 定位模块归属
2. 页面/UI 改动 → 改 `widgets/` 对应文件；业务逻辑 → `state.dart` 或 `services/`；新能力 → 新增 `services/` 文件
3. 遵循现有模式与命名（参考同类文件写法，不要自创结构）
4. 改动后运行 `flutter analyze` 确认无新增错误
5. 需要构建 exe/apk 时严格按 `flutter-build` 技能流程（先问卷问 SDK 路径）
6. 涉及内置内容/技能时同步更新 `skill_store.dart` 注册表