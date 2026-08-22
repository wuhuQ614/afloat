# SmartEnglish Desktop 功能缺陷与 Agent 适配性调研报告

> 调研对象：`E:\YINGYU\YINGYU\smartenglish-desktop`
> 调研时间：2026-08-22
> 调研角色：代码调研员（仅勘察，不修复）
> 调研方式：静态阅读源码 + 交叉验证（关键发现均经二次定位核实），无运行、无动态测试
> 关联文档：安全类问题（密钥明文、Agent 注入面、安装包签名等）见同目录《安全勘察报告.md》，本报告不重复覆盖

---

## 0. 调研说明与限制

| 项 | 说明 |
|----|------|
| 覆盖范围 | `lib/` 全部 32 个 Dart 文件（约 1.4MB）、`native/snake_logic` FFI 契约、`.agents/skills/` 三份技能文档、AGENTS.md、根目录治理产物 |
| 环境限制 | 本机 Flutter SDK 安装不完整（`C:\src\flutter\bin\` 缺少 `flutter.bat`），**无法运行 `flutter analyze`**，本报告结论全部来自人工代码审读 |
| 行号时效 | 调研期间工作区存在未提交修改（`git status` 显示 `lib/state.dart`、`main.dart` 等 ~20 个文件为 M 状态），个别行号可能有 ±10 行漂移，均已按当前快照重新定位 |
| 严重度定义 | 高 = 崩溃 / 功能静默全损 / 数据失真；中 = 功能部分失效 / 泄漏 / 竞态；低 = 死代码 / 可观测性差 / 边缘兼容 |

## 1. 总览

| 模块 | 高 | 中 | 低 | 小计 |
|------|----|----|----|------|
| 状态层 / 对话链路（state / main） | 1 | 8 | 5 | 14 |
| 服务层（services/*，FFI） | 1 | 3 | 7 | 11 |
| Widgets 层（页面生命周期 / 功能联动） | 2 | 7 | 7 | 16 |
| Agent 内容适配性（文档 / 提示词 / 测试） | — | 2 | 若干 | 见 §4 |
| **合计** | **4** | **20** | **19+** | **43+** |

正面结论先行：FFI 结构体布局严格一致、SSE UTF-8 分包处理正确、Agent 循环多重封顶无死循环风险、三个贪吃蛇页单机版生命周期干净。最严重的共性问题模式是 **「catch 后静默吞掉 + 成功反馈失真」**（MCP 假连接、压缩摘要失效、备份缺键均属此类），与 AGENTS.md「显式 > 隐式」约定相悖。

---

## 2. 高严重度（建议优先修复）

### H1. 考试 AI 批改主观题分值口径与本地 150 分制不一致，交卷成绩被系统性压低
- **位置**：`lib/state.dart:7300`（prompt 写死"写作满分 20"）、`:7354`（clamp 0–20）、`:7371`/`:7380`（覆盖得分）；对照 `lib/models.dart:807-810`
- **问题**：本地判分体系中写作满分 35（`scorePerQuestion==35`）、英译汉每句 4 分（5 句满分 20）；而 AI 批改把写作 clamp 到 0–20 直接写入 `sectionScores[writing]`，英译汉按每句 0–3 合计上限仅 15。批改后 `sectionMax` 未同步更新，重算总分时主观题实得分上限（35）远低于卷面满分（55），`percentage`/`rank` 全部失真。
- **证据**：
  ```dart
  case ExamSection.writing: return 35;   // models.dart:810 本地口径
  wScore = (wRaw['score'] as num).toInt().clamp(0, 20);   // state.dart:7354 AI 口径
  ```
- **建议**：让 AI prompt 与解析和 `ExamSection.scorePerQuestion` 同口径，或融合分数时同步改写 `sectionMax`。

### H2. MCP 握手失败被静默吞掉：客户端带空工具列表"假连接"，设置保存可挂起 60 秒
- **位置**：`lib/services/mcp_client.dart:82-107`（根因在 `:154-157` 的 `_send`）
- **问题**：`_send` 在超时/写失败时不抛异常而是返回错误 map；`connect()` 不检查 `error` 键即置 `_initialized = true` 并继续。失败的 server 仍被加入 `_clients`，UI 显示"已连接 N 个 server"但所有工具不可用，全程零诊断信息。且单次 RPC 超时 60s，配置了不可达 server 时保存设置会逐 server 挂起 60 秒。
- **建议**：`connect()` 收到含 `error` 的响应即抛异常，走既有的 catch→dispose→跳过路径，并在 UI 透传失败原因。

### H3. 成绩页「去错题本复盘」按钮跳转到错误页面
- **位置**：`lib/widgets/exam_page.dart:1994,1998`
- **问题**：按钮文案是"去错题本复盘"，实际执行 `state.page = 9`（更多功能选择页），且绕过 `setPage()` 直接赋值。考试错题确实已写入错题本（`state.dart:7525` 附近），但用户点过去看不到。行内注释自相矛盾（"返回考场，但其实直接重进首页"）。
- **建议**：改为 `state.setPage(5)`（错题本页索引，见 `main.dart:1124`），删除误导注释。

### H4. 设置弹窗在 initState 中查祖先依赖，debug 构建打开设置必崩红屏
- **位置**：`lib/widgets/settings_dialog.dart:60-62`；`:1570`（对话设置弹窗同样）
- **问题**：`initState()` 内调用 `MediaQuery.of(context)` 与 `AppScope.of(context)`（内部为 `dependOnInheritedWidgetOfExactType`）。Flutter framework 在 State 处于 created 生命周期时调用此 API 会直接断言崩溃。release 构建剥离断言后功能正常——这解释了为何日常使用（release 构建）未暴露。
- **建议**：读取逻辑移入 `didChangeDependencies()`，或由调用方将 `AppState` 作为构造参数传入。

---

## 3. 中严重度

### 3.1 状态层 / 对话链路

| # | 问题 | 位置 | 要点 |
|---|------|------|------|
| M1 | `vision` 字段不持久化 | `storage.dart:63-83` | `saveApiConfig`/`loadApiConfig` 共 8 个键唯独漏掉 vision；设置里有 UI 开关（settings_dialog.dart:508），重启即丢回默认 true |
| M2 | 会话压缩摘要永远发不出去 | `state.dart:3762` vs `:2202`/`:4696` | `_toolCompactConversation` 把摘要构造成 `role:'system'` 入史，但两条发送链路都 `.where((m) => m.role != 'system')` 过滤——模型下一轮完全失忆，压缩对模型无效 |
| M3 | `ask_user_question` 全链路断裂 | `state.dart:3701-3749`；`agent_rows.dart:856-866` | 工具同步读 `chatHistory.last.askAnswers`（此刻用户必然没答，永远返回空）；UI 确认按钮只弹 SnackBar，答案没有任何回传模型的路径 |
| M4 | bash 熔断计数永不清理 | `state.dart:2070`（注释承诺"每次对话开始清零"）、`:3562-3594` | 全文件无 `.clear()`；被熔断的命令没有执行机会也就永远不会成功复位 → 连败 2 次后进程内永久封禁 |
| M5 | 桌面端模型选择浮层 pop 掉根路由 | `main.dart:2698`（浮层挂载于 `:2882` OverlayEntry） | "配置自定义模型"先 `Navigator.pop(context)` 再 showDialog；overlay 场景下弹的是 home 根路由，随后对话框盖在黑屏上 |
| M6 | `analyzeWords` 无 try/finally，剖析入口整体锁死 | `state.dart:1634-1921` | 任何一处异常跳过所有复位点后，`analyzing` 永久卡 true，后续请求被入口重入保护静默吞掉 |
| M7 | `gradeText` 竞态：旧题成绩顶掉新题 | `state.dart:1317-1344` | await 批改期间用户换题，完成后无条件 `currentQuestion = q.copyWith(...)` 写回旧题（对比：考试 AI 批改有 submittedAt 校验，此处没有） |
| M8 | `job_kill` 不终止真实进程，完成回调反向覆盖 kill 标记 | `state.dart:3940-3960`、`:3998-4010` | 后台任务用 `Process.run` 且未保留引用；kill 只改标志位，IIFE 完成后又把 stdout/stderr/finished 整体覆写 |

### 3.2 Widgets / 功能联动

| # | 问题 | 位置 | 要点 |
|---|------|------|------|
| M9 | 查词页 AI 查询 await 后无 mounted 检查 | `pages.dart:2374-2422` | 查询期间切页即抛 setState-after-dispose（同文件 `_fetchWordExtras` 有检查，属遗漏） |
| M10 | 查词页 TextEditingController 泄漏 | `pages.dart:1830` | `_DictionaryPageState` 无 dispose()，反复进出累积 |
| M11 | 生词本复习次数不持久化 | `pages.dart:1648-1650` | 「知道了」直接改内存对象，从不调 `Storage.saveWordBook`，重启丢失 |
| M12 | 默写错词收集后无任何去向 | `pages.dart:2595`、`:3493`、`:3515` | `_wrongWords` 只 add 不消费，与错题本/生词本体系完全脱节 |
| M13 | 多人/PVP 贪吃蛇暂停与结束后 Ticker 不停 | `snake_multi_page.dart:1146-1205`；`snake_pvp_page.dart:176`、`:254` | phase=2/3 后渲染循环照跑满帧空转（单机版 snake_game_page.dart:160/210 是正确示范） |
| M14 | 五子棋悔棋在人机执白开局场景死锁 | `gomoku_page.dart:131-149` | 玩家执白、盘面仅 AI 先手 1 子时悔棋：移除该子后轮到 AI 却无人调度，玩家也无法落子，永久卡死 |
| M15 | 多人蛇在 build() 中直接改业务状态 | `snake_multi_page.dart:1899` | `if (...) _phase = 1;` 无 setState，违反构建纯函数约定 |

### 3.3 服务层

| # | 问题 | 位置 | 要点 |
|---|------|------|------|
| M16 | 备份导入中途类型不符会"半导入"且返回 false | `storage.dart:563-621` | 单 try 内逐键硬转换写入，第 N 键抛 TypeError 时前 N-1 键已落盘，无回滚 |
| M17 | 备份键清单缺失约 10 个已使用键 | `storage.dart:505-560` | `customSkills`、`skillsDisabledIds`、`mcpConfigJson`、`chatSessions/Messages`、`apiQuestionMode/Speed`、`activeSkill/chatMode/activeExpert`、`chatWorkspacePath` 均不在备份内，换机静默丢数据；`themeId` 是只有 import 自己写的死键 |
| M18 | 墨墨服务硬类型转换，一个数字 id 毁掉整次同步 | `maimemo_service.dart:193-194`、`:300-301` | 与同文件 `_asInt` 宽容风格相悖；外部 API 返回数字 id 即 TypeError 中断整次解析 |

### 3.4 Agent 运行时

| # | 问题 | 位置 | 要点 |
|---|------|------|------|
| M19 | 决策表提示词指引错误 | `agent_service.dart:961` | 表中"按某技能的具体指令工作 → skill（先用 list_mcp_tools 看可选技能名…）"——`list_mcp_tools` 返回的是 MCP 工具清单而非技能商店目录，该错误指引随每轮对话注入上下文 |

---

## 4. 低严重度（简表）

### 4.1 状态层 / main

| # | 问题 | 位置 |
|---|------|------|
| L1 | `_updateFrameRate` 与注释相悖（highPerformanceMode 未参与）且 Windows 下整体 no-op | main.dart:366-372 |
| L2 | build 期间注册 postFrameCallback 无 mounted 守卫，可能访问已 dispose 的 ScrollController | main.dart:1076、1390 |
| L3 | 桌面端"API 未配置"引导气泡点击 pop 根路由（与 M5 同模式） | main.dart:1455 |
| L4 | `_toolNextQuestion` 未 await 异步 `nextQuestion()`，返回 stale 索引 | state.dart:2840 |
| L5 | `examPendingConfirm` 全仓库无置 true 路径，确认弹窗机制整套死代码 | state.dart:437 及关联链 |
| L6 | `init()` 8 秒超时放行与后台继续初始化的启动竞态（空数据闪现） | main.dart:310、state.dart:470-581 |

### 4.2 服务层

| # | 问题 | 位置 |
|---|------|------|
| L7 | SSE 结束标记不支持 `data:[DONE]`（冒号后无空格）变体 | api_service.dart:408-409 |
| L8 | 流式非 200 响应体读取超时后底层订阅未取消，连接滞留 | api_service.dart:391-394 |
| L9 | 流式 tool_calls 以 index 缺省 0 分桶，无 index 字段的兼容网关会把多个调用搅坏 | api_service.dart:436-471 |
| L10 | SkillStore.load() 提前置位 `_loaded`，窗口期目录为空注入系统提示词 | skill_store.dart:176-177 |
| L11 | McpRegistry.connectAll 进行中缓存忽略新配置 | mcp_client.dart:237-245 |
| L12 | TTS 初始化瞬时失败永久缓存为不可用，无重试 | tts_service.dart:19、60-63 |
| L13 | BinaryDict 加载失败永久禁用且吞掉原因（无日志） | binary_dict.dart:23-24、48-51 |
| L14 | 技能 frontmatter 值超 200 字符截断；资产加载失败静默吞；source 回退语义不一致 | skill_store.dart:190-238 |

### 4.3 Widgets

| # | 问题 | 位置 |
|---|------|------|
| L15 | 学习报告「查看全部」是死按钮（空 onTap 无反馈） | pages.dart:1373-1389 |
| L16 | 弹窗内临时 TextEditingController 从不释放 ×3 处 | settings_dialog.dart:969-973、1281-1284；maimemo_wordbook_page.dart:186-188 |
| L17 | GlassSelectedTile 未选中态呼吸动画仍每帧空转 | glass_background.dart:405-429 |
| L18 | 默写页空焦点监听器（函数体为空的死代码） | pages.dart:2652-2654 |
| L19 | `_buildGrammarEntry` 完整实现但零调用（死代码） | learn_page.dart:1619-1656 |
| L20 | 成绩页/确认弹窗硬编码 76 题、150 分，部分批次生成失败时口径失真 | exam_page.dart:2116、2157、2686-2692 |
| L21 | 历史考试记录全量非虚拟化渲染（SingleChildScrollView 内 for 展开） | pages.dart:1403-1422 |

---

## 5. Agent 相关内容适配性评估

### 5.1 总体判断

运行时 Agent 功能实现完整度高：三层技能体系（`.agents/skills` 协作技能 / `assets/skills` 运行时商店 / `.dsh/skills` 用户技能）、MCP stdio 客户端、子 Agent 隔离循环（`AgentSubagentCard` 有对应事件流渲染）、权限门控（`_isDangerousTool` + `chatFullAccess`）均已落地且相互接线，无 stub、无 TODO 半成品。UI 层（agent_rows.dart）消费的状态字段与 state.dart 定义一一对应，无悬空渲染路径。

**缺口集中在治理文档滞后于代码**。

### 5.2 AGENTS.md 失配点清单

| # | 失配点 | 严重度 |
|---|--------|--------|
| A1 | Repository layout 的 services 清单只列了 `api_service、storage、chat_capabilities、snake_logic` 四件，**漏掉 agent_service / skill_store / mcp_client 三大核心**及 dict_service / binary_dict / maimemo_service / tts_service | 高 |
| A2 | "游戏化工具（贪吃蛇 / 转盘 / 骰子）"描述失实——实际游戏是贪吃蛇三形态 + 五子棋，转盘/骰子并不存在于代码 | 中 |
| A3 | widgets 目录列举明显过时（漏 exam_page、learn_page、gomoku_page、onboarding_page、browser_page、maimemo_wordbook_page、source_viewer_page、dev_console 等） | 低 |
| A4 | "pre-push 钩子也会跑增量版本"——**`.git/hooks/pre-push` 实际不存在**，钩子基线是虚构的 | 高 |
| A5 | 引用的 `docs/` 目录不存在 | 中 |
| A6 | 未记载 deepseek-harness/（大型 TS/Node 仿写仓库）的渊源与定位；racing-game/、snake-game/、tool/、installer/、config.yaml、安全勘察报告.md、.dsh/ 均未提及 | 中 |
| A7 | 字体资源承诺未兑现（assets 声明与 layout 描述不一致处） | 低 |

### 5.3 .agents/skills 三份技能文档适配性

| 技能 | 结论 |
|------|------|
| code-review | 基本可用；其"Test strength"要求与实际测试覆盖（见 5.4）形成落差 |
| pre-push-checks | 引用了不存在的 pre-push 钩子作为机制基线（与 A4 同一根因），会误导 agent 认为钩子会兜底从而跳过本地校验；需落实钩子或改述 |
| find-simplifications | 悬空引用 AGENTS.md 中不存在的 urgency 语义，以及缺失的 `.agents/notes` 规则路径 |

### 5.4 测试覆盖缺口（中）

- `test/` 目录全仓仅 1 个文件、16 行纯单元测试（qTypeName/levelName 断言），文件名 `widget_test.dart` 名不副实（无任何 widget 测试）；
- Agent 循环、工具分发、MCP 帧解析、技能 frontmatter 解析、run_code 白名单等核心面 **0 测试覆盖**，与 AGENTS.md「变更须有证据」约定形成结构性落差。

### 5.5 运行时 Agent 小缺陷汇总

除 §3.4 M19（提示词错误指引）外：后台 bash 任务 stderr 在部分路径被丢弃（低）；skill_store 三处低危观察见 L14。

---

## 6. 已排查、确认无问题的点（避免重复劳动）

| 检查项 | 结论 |
|--------|------|
| FFI 结构体布局 | `snake_logic.dart:16-55` 与 `native/snake_logic.h:26-40` 字段顺序/padding/sizeof(64B) 完全一致；malloc/free 配对正确；`snakePos` 立即 sublist 拷贝规避 use-after-free |
| 流式/网络异常卡死 chatSending | 排除：streamChatWithTools/callAIResult 全面捕获不外抛 |
| SSE UTF-8 分包 | chunked decoder + MCP 字节缓冲，多字节跨 chunk 不损坏 |
| Agent 循环死循环风险 | 12 轮硬上限 + 三类重试计数器封顶 |
| MCP 工具名衔接 | 定义侧 `mcp__`+空格转下划线 ↔ 分发侧反查兜底，双向一致 |
| 单机贪吃蛇帧循环 / ExamShell 计时器 / learn_page / onboarding 生命周期 | dispose 配对完整，干净 |
| 全卷 150 分制自身一致性 | 本地判分自洽（20+40+15+10+10+20+35=150），失真仅在 H1 所述 AI 批改环节 |
| 多人蛇头对头碰撞、grammar_store AI 扩题竞态 | 逻辑正确 / 无用户可见影响 |
| test/widget_test.dart 可通过性 | 按代码审查判定确定性通过（但覆盖面见 5.4） |

---

## 7. 修复优先级路线图（供参考）

1. **立即**：H3（一行改动消除断链）、H4（移动两行代码消除 debug 必崩）→ M1/M2/M4（各一两行，恢复 vision 持久化 / 压缩有效性 / 熔断复位）
2. **短期**：H1（统一 AI 批改分值口径）、H2（MCP 失败显式化）、M3（ask_user_question 用 Completer 打通）、M16/M17（备份完整性）
3. **中期**：M5-M8、M9-M15（生命周期与竞态批量补齐）、A1-A6（AGENTS.md 与 skills 文档同步现实）、补关键路径测试（工具分发 / MCP 帧 / frontmatter 解析）
4. **随手清理**：§4 全部低危（死代码 L5/L18/L19、泄漏 L16、硬编码 L20）

---

*报告完。本次调研未修改任何业务代码；文中行号为调研快照时点数值。*
