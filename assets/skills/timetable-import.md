---
name: timetable-import
description: 把用户的课表文本或图片信息转成课程表 JSON 并调用 import_timetable 工具导入到应用。仅在学习模式（Agent 工具循环中）使用，导入成功会自动切换到课程表模式。
category: 课程表
source: AFloat/timetable-import
---

# Timetable Import（课程表 JSON 导入）

帮助用户把自然语言或图片里的课表信息，转成 AFloat 课程表模式的 JSON 格式并导入。导入后整个应用会切到课程表模式，周视图立即按新数据显示。

## When to Use

- 用户说"导入我的课表"/"这是我的课表"/"帮我把课表导入进去"等
- 用户贴了一张课表图片或一段课表文字描述（"周一第 1-2 节高数，周三第 3-4 节线代，王老师，地点教 305"）
- 用户想替换现有课表
- 用户说"把课表改成…"并提供新内容

**不要**用于：纯查询当前课表（用 `get_timetable_summary` 工具）；本技能只做"识别用户输入 → 构造 JSON → 调工具"。

## 工具

| 名称 | 用途 |
|---|---|
| `get_timetable_summary` | 查询当前是否已导入课表、已导入则返回摘要（学期名/总周数/课程数等）。在导入前先调一次，确认是否覆盖。 |
| `validate_timetable` | **第 1 道校验**：干跑校验 JSON（不写入、不切模式），返回 `checks` 各项 pass/warn + 统计 + `issues` 问题清单。 |
| `import_timetable` | 把 JSON 文本解析并写入课表。导入成功后会自动切到课程表模式。 |

工具仅在**学习模式**下可用（课程表模式下没有 Agent 工具循环）。

## 关键调用约定

**直接调工具循环里的工具，**不要**用 `run_code` 串起来**：`run_code` 的代码解析器只识别
"单条 `await tools.xxx({...})` + `return`"的极简形式，把多步流程塞进 `run_code` 会被拒
（返回 `reason: "no_tool_calls_parsed"`）。本技能的工作流请按步骤**直接**调用对应工具
（`get_timetable_summary` / `ask_user_question` / `validate_timetable` / `import_timetable`），
由 Agent 工具循环天然串联。

## 工作流程（两道校验，缺一不可）

1. **查询现状**：先调一次 `get_timetable_summary`。如果已导入，告诉用户当前课表名 + 课程数，让其确认是否覆盖。
2. **收集学期信息**：用 `ask_user_question` 工具向用户要以下信息（如果用户消息里没给）：
   - **学期名**（如 "2025-2026 第1学期"）— 可省，缺省用 "我的课程表"
   - **第 1 周周一的日期**（如 "2025-09-01"）— **必填**，周次推算依赖它
   - **一天的节次时间分布**（每节课的起止时间）— **必填**，课程块的显示时间完全由它决定
   - **课程列表**（每门：课程名、地点、教师、星期几、当日第几节~第几节、上课周次范围）— 可空数组
3. **构造 JSON**：按下方 schema 严格输出 `json_text` 字符串（第 4 步校验用的内容必须与此完全一致）。
4. **第 1 道校验（机器校验）**：调 `validate_timetable`，检查返回：
   - `checks` 中是否有 `fail` → 按 `issues[].message` 修正 JSON 后**重新校验**，不得跳过；
   - 有 `warn` 时逐条判断是否合理（节次重叠、周次越界、课程节次未定义、同天冲突等），能修就修，确认是用户课表本身如此则保留；
   - 记录返回的 `courseCount / periodCount / coursesPerDay / maxWeekUsed / startWeekday`，供第 2 道校验比对。
5. **第 2 道校验（逐条对照复核）**：把生成的 `courses` **逐条**与用户原始课表（文字/图片）核对，必须全部一致才算通过：
   - **课程总数**是否与源课表一致（用 `coursesPerDay` 按星期核对每日门数）；
   - 每门课的 **课程名 / 星期几 / 第几节~第几节 / 周次范围 / 地点 / 教师** 是否与源一一对应，有没有串行、漏课、多课；
   - `periods` 的节次时间是否与用户给的作息表一致；
   - **发现任何不一致 → 修正 JSON 后从步骤 4 重新走一遍两道校验**，不得直接导入。
6. **导入**：两道校验都通过后，才调 `import_timetable`，把与校验时**完全相同**的 JSON 原文作为 `json_text` 传入。
7. **向用户报告**：用工具返回的 `ok / name / totalWeeks / courseCount / firstDay` 字段，告知"已导入《...》（N 门课 / M 周）"，并说明应用已切到课程表模式；同时简述两道校验的结论（如有保留的警告，也要一并告知）。

## JSON Schema（严格遵守）

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

### 字段说明

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | 缺省 `我的课程表` | 学期名，只用于显示 |
| `startDate` | **必填** | 第 1 周周一的日期，格式 `yyyy-MM-dd`。错误格式/缺此字段都会被拒绝 |
| `totalWeeks` | 缺省自动 | 学期总周数。如果给了 `weeks` 字段，会从课程最大周次推算，可省略 |
| `periods` | **必填** | 一天的节次时间分布。每个含 `index`（正整数节次序号）/ `start` / `end`（`HH:mm`）。课程块上显示的时间完全由这组数据决定 |
| `courses` | 必填（可空数组） | 课程列表，每门课一次排课 |

### 课程字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | **必填** | 课程名 |
| `day` | **必填** | 1=周一，2=周二，…，7=周日 |
| `startPeriod` | **必填** | 当日第几节开始（对应 `periods[].index`） |
| `endPeriod` | **必填** | 当日第几节结束（含） |
| `teacher` | 可选 | 教师姓名 |
| `room` | 可选 | 教室/地点 |
| `weeks` | 可选 | 上课周次。`"1-16"` / `"1-8,10,12-16"` / `"all"` / `[1,2,3]` / 缺省=每周都有 |

## 常见错误（用户消息里的典型坑）

- 缺 `startDate` → "缺少 startDate（第 1 周周一的日期）——周次推算依赖它"
- 缺 `periods` 或 `periods: []` → "缺少 periods（一天的节次时间分布）"
- `day` 越界（不是 1~7 的整数）→ 格式错误
- 时间不是 `HH:mm` 格式（"8:30" 没前导 0 也算合法，但 "8-30" 不算）
- `weeks` 写 "单周" / "双周"（不识别）→ 退化为全周

## 模板（最简可工作版）

```json
{
  "name": "2025-2026 第1学期",
  "startDate": "2025-09-01",
  "periods": [
    {"index": 1, "start": "08:00", "end": "08:45"},
    {"index": 2, "start": "08:55", "end": "09:40"},
    {"index": 3, "start": "10:00", "end": "10:45"},
    {"index": 4, "start": "10:55", "end": "11:40"},
    {"index": 5, "start": "14:00", "end": "14:45"},
    {"index": 6, "start": "14:55", "end": "15:40"},
    {"index": 7, "start": "15:50", "end": "16:35"},
    {"index": 8, "start": "16:45", "end": "17:30"}
  ],
  "courses": [
    {"name": "高数", "day": 1, "startPeriod": 1, "endPeriod": 2, "weeks": "1-16"},
    {"name": "英语", "day": 3, "startPeriod": 3, "endPeriod": 4, "weeks": "1-16"}
  ]
}
```

## 调用示例（两道校验）

```python
# 1. 导入前先查现状
result = await tools.get_timetable_summary({})

# 2. 第 1 道校验：干跑校验（不写入）
check = await tools.validate_timetable({"json_text": json_text})
info = json.loads(check.content)
if not info["valid"]:
    for it in info["issues"]:
        if it["level"] == "error":
            # 修正 json_text 后重新校验，不得跳过
            ...
else:
    # 记录统计：courseCount / periodCount / coursesPerDay / maxWeekUsed
    print(info["courseCount"], info["coursesPerDay"])

# 3. 第 2 道校验（在模型内部完成，无工具调用）：
#    逐条把 json_text 里的 courses 与用户原始课表核对
#    课程名/星期/节次/周次/地点/教师 全部一致才继续；不一致则修正后回到步骤 2

# 4. 两道都通过后导入（json_text 必须与校验时完全相同）
result = await tools.import_timetable({"json_text": json_text})

# 5. 根据返回判断
if result.ok:
    info = json.loads(result.content)
    print(f"已导入《{info['name']}》{info['courseCount']}门课/{info['totalWeeks']}周")
else:
    print(f"失败：{result.actionLabel}")
```

## 工具返回结构

`validate_timetable` 成功（含警告也算 valid=true，除非有 error 级问题）：
```json
{
  "ok": true,
  "valid": true,
  "checks": {
    "json_parse": "pass",
    "required_fields": "pass",
    "periods_time": "pass",
    "periods_defined": "pass",
    "weeks_range": "pass",
    "conflicts": "warn"
  },
  "name": "2025-2026 第1学期",
  "startDate": "2025-09-01",
  "startWeekday": "周一",
  "firstWeekMonday": "2025-09-01",
  "totalWeeks": 16,
  "periodCount": 8,
  "courseCount": 12,
  "maxWeekUsed": 16,
  "coursesPerDay": {"一": 3, "二": 2, "三": 3, "四": 2, "五": 2, "六": 0, "日": 0},
  "issues": [
    {"level": "warn", "code": "course_conflict", "message": "周三：高等数学 与 线性代数 节次重叠"}
  ],
  "next": "第 1 道校验已完成。请再做第 2 道校验：逐条对照用户原始课表核对…"
}
```

`import_timetable` 成功：
```json
{"ok": true, "name": "2025-2026 第1学期", "totalWeeks": 16, "periodCount": 8, "courseCount": 12, "firstDay": "2025-09-01", "startDate": "2025-09-01"}
```

失败：
```json
{"ok": false, "reason": "format_error", "message": "缺 periods"}
```

`actionLabel` 是给用户看的简短中文提示，Agent 回复时直接复用即可。
