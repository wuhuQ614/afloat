---
name: timetable-edit
description: 修改当前课程表的任何信息——增删课程、改课程名/教室/教师/节次/周次、调整作息时间（节次时间分布）、改学期名/开学日期/总周数。当用户说"把课表改成…/加一门课/删掉高数/换到周三/改到第3-4节/换教室/调作息/改学期名"等修改意图时加载。
category: 课程表
source: AFloat/timetable-edit
---

# Timetable Edit（课程表修改）

在**当前已导入的课表**基础上修改任意信息。与 `timetable-import`（从无到有导入 / 整体替换）不同，本技能只做"读现状 → 按用户要求最小改动 → 校验 → 写回"。

## When to Use

- 用户要求改课表里的**任何一项**：加课、删课、改课程名、换教室、换教师、调整某门课的星期/节次/周次
- 用户要求调整**作息时间**（一天的节次时间分布，如"上午第一节改到 8:00 开始"）
- 用户要求改**学期信息**（学期名、开学日期、总周数）
- 用户说"把课程表里的 X 改成 Y"、"帮我加一门课"、"把周一的课删了"、"高数换成线代"等

**不要**用于：
- 纯查询当前课表 → 用 `get_timetable_summary`（摘要）或 `get_timetable_full`（完整 JSON），不写回
- 从无到有导入新课表 / 整体换一版全新课表 → 用 `timetable-import` 技能

## 工具

| 名称 | 用途 |
|---|---|
| `get_timetable_full` | **必先调用**：读当前课表完整 JSON（`json` 字段与 import_timetable 输入 schema 一致），在其基础上修改 |
| `get_timetable_summary` | 可选：先看摘要（学期名/课数），确认导入状态 |
| `validate_timetable` | **第 1 道校验**：干跑校验修改后的 JSON（不写入、不切模式），返回 checks + issues |
| `import_timetable` | 把修改后的 JSON 写回课表。成功后自动切到课程表模式 |

工具仅在**学习模式**下可用（课程表模式下没有 Agent 工具循环）。

## 关键调用约定

**直接调工具循环里的工具，**不要**用 `run_code` 串起来**：
- `run_code` 的代码解析器只识别"单条 `await tools.xxx({...})` + `return`"的极简形式，
  把"读全量→改 JSON→再校验"塞进 `run_code` 会被拒（返回 `reason: "no_tool_calls_parsed"`）。
- 正确做法：每一步直接调用对应工具（`get_timetable_full` → 自己改字段 → `validate_timetable` →
  `import_timetable`），由 Agent 工具循环天然串联多轮。

## 工作流程（必须先读现状，再做最小修改）

1. **读现状**：调用 `get_timetable_full`。
   - 返回 `imported:false` → 告诉用户当前还没导入课表，询问是否要导入（转 `timetable-import` 技能）后结束；
   - 返回 `imported:true` → 取出 `json`，这就是修改的**唯一底稿**。
2. **映射修改**：把用户的每一条要求翻译成对底稿字段的改动（见下方"修改映射表"）。**最小改动原则**：用户没提到的字段一律原样保留，绝不重写整张课表（防止漏课、手滑改错）。
3. **构造新 JSON**：输出修改后的完整 JSON 文本（`json_text`），内容 = 底稿 + 本次修改。
4. **第 1 道校验**：调 `validate_timetable`。有 `fail`/error → 按 `issues[].message` 修正后**重新校验**；有 `warn` → 逐条判断：节次重叠/周次越界/引用未定义节次等，能修就修，确实是用户课表如此则保留。
5. **第 2 道校验（对照复核）**：把修改后的 `courses` 与「底稿 + 用户要求」逐条比对：
   - **被修改的课程**：确认改成了用户要求的样子（课程名/星期/节次/周次/地点/教师）；
   - **其余所有课程**：必须与底稿**完全一致**（门数、顺序、每门字段都不得变）；
   - `periods` / `name` / `startDate` / `totalWeeks` 未被要求改动的部分同样保持不变。
   - 任何不一致 → 修正后从步骤 4 重来。
6. **写回**：两道校验都通过后调 `import_timetable`，`json_text` 传**与校验时完全相同**的修改后 JSON。
7. **报告**：告诉用户改了什么（按条目列清楚）、导入成功会自动切到课程表模式；如有保留的警告一并说明。

## 修改映射表（用户要求 → JSON 字段）

| 用户要求 | 改哪里 |
|---|---|
| 加一门课 | `courses` 数组新增一项（name/day/startPeriod/endPeriod 必填，teacher/room/weeks 可选） |
| 删一门课 | `courses` 数组移除对应项（按 name+day 定位，注意同名的多门课要按星期/节次区分） |
| 改课程名 | 该项的 `name` |
| 换教室 / 换教师 | 该项的 `room` / `teacher` |
| 改到星期 X | 该项的 `day`（1=周一 … 7=周日） |
| 改节次（第几节~第几节） | 该项的 `startPeriod` / `endPeriod`（必须对应 `periods[].index`） |
| 改上课周次 | 该项的 `weeks`：`"1-16"` / `"1-8,10,12-16"` / `"all"` / `[1,2,3]`，缺省=全周 |
| 调整作息时间（某节课开始/结束时间） | `periods` 数组里对应 `index` 的 `start` / `end`（`HH:mm`）——注意这会改变所有引用该节次的课程的显示时间 |
| 加一节 / 删一节作息 | `periods` 数组增/减项（`index` 为正整数，保持升序）；同时检查引用这些节次的课程是否受影响 |
| 改学期名 | 顶层 `name` |
| 改开学日期 | 顶层 `startDate`（`yyyy-MM-dd`，第 1 周周一；周次推算依赖它） |
| 改总周数 | 顶层 `totalWeeks`（注意检查是否有课程周次超出新总周数） |

## JSON Schema（与 timetable-import 完全一致）

```json
{
  "name": "2025-2026 第1学期",
  "startDate": "2025-09-01",
  "totalWeeks": 16,
  "periods": [
    {"index": 1, "start": "08:30", "end": "09:15"},
    {"index": 2, "start": "09:20", "end": "10:05"}
  ],
  "courses": [
    {
      "name": "高等数学",
      "teacher": "王老师",
      "room": "教305",
      "day": 1,
      "startPeriod": 1,
      "endPeriod": 2,
      "weeks": "1-16"
    }
  ]
}
```

字段规则：`name` 缺省 `我的课程表`；`startDate` 必填（`yyyy-MM-dd`）；`totalWeeks` 可省略（从课程最大周次推算）；`periods` 必填（含 `index`/`start`/`end`，课程显示时间完全由它决定）；`courses` 必填（可空数组）。课程里 `name`/`day`/`startPeriod`/`endPeriod` 必填，`teacher`/`room`/`weeks` 可选。

## 常见错误（修改时特别容易踩的坑）

- **重写整表导致漏课**：永远从 `get_timetable_full` 返回的 `json` 改起，不要凭记忆/摘要手写全表（摘要最多只有 5 条示例课，不够当底稿）
- 新课程的 `startPeriod`/`endPeriod` 引用了一个 `periods` 中不存在的节次 → 校验会报"未定义节次"
- 作息时间 `end ≤ start`（倒挂）或与相邻节次重叠 → 校验 warn
- 同名多门课删课时只删了其中一节 → 用 `day`/`startPeriod` 精确锁定
- 改 `startDate` 或 `totalWeeks` 后不检查周次是否越界 → 校验 warn"周次超出 totalWeeks"

## 调用示例（修改一门课的教室）

```python
# 1. 读当前完整课表
r = await tools.get_timetable_full({})
info = json.loads(r.content)
if not info["imported"]:
    print("尚未导入课表，需要先导入")
    return
t = info["json"]  # 底稿：完整课表对象

# 2. 最小修改：只改用户要求的那门课
for c in t["courses"]:
    if c["name"] == "高等数学" and c["day"] == 1:
        c["room"] = "教305"
        break
json_text = json.dumps(t, ensure_ascii=False)

# 3. 第 1 道校验
check = await tools.validate_timetable({"json_text": json_text})
v = json.loads(check.content)
if not v["valid"]:
    # 修正后重新校验，不得跳过
    ...

# 4. 第 2 道校验（模型内部完成）：其余课程与底稿逐条一致、被改的课确实改到位

# 5. 写回
result = await tools.import_timetable({"json_text": json_text})
if result.ok:
    print("已更新《%s》" % json.loads(result.content)["name"])
```

## 工具返回结构

`get_timetable_full` 成功：
```json
{"ok": true, "imported": true, "json": {"name": "…", "startDate": "2025-09-01", "totalWeeks": 16, "periods": [...], "courses": [...]}}
```
未导入：`{"ok": true, "imported": false}`

`validate_timetable` / `import_timetable` 的返回结构见 `timetable-import` 技能（两技能共用同一套工具与 schema）。
