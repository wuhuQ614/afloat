// 课程提醒调度逻辑验证（可独立运行，不需要 Flutter 运行环境）
//
// 验证 state.dart `scheduleClassReminders()` 的核心算法：
//   1. 提醒时刻 = 当前课程结束时刻 - 5 分钟
//   2. 通知标题/正文取自"下一节课"（名称 / 开始时间 / 教室）
//   3. 当天最后一节课不提醒（没有"下一节课"）
//   4. 通知 id 稳定唯一（同课同天 → 同 id，重复调度只覆盖不堆积）
//   5. 已过去的时刻不会被调度
//
// 运行：dart run test/verify_class_reminder.dart

import '../lib/timetable_models.dart';

int _hm(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String _pad(int n) => n.toString().padLeft(2, '0');

String _fmt(DateTime d) => '${_pad(d.hour)}:${_pad(d.minute)}';

/// 复刻 state.dart 的调度算法，产出可读的提醒计划
class ReminderPlan {
  final DateTime remindAt;
  final String title;
  final String body;
  final int id;
  ReminderPlan(this.remindAt, this.title, this.body, this.id);
  @override
  String toString() => '${_fmt(remindAt)} | $title | $body';
}

List<ReminderPlan> buildPlans(
  TimetableData d,
  int day,
  int week,
  DateTime now, {
  int minutesBefore = 5,
}) {
  final midnight = DateTime(now.year, now.month, now.day);
  final courses = d.coursesFor(day, week); // 已按 startPeriod 升序
  final out = <ReminderPlan>[];

  // 最后一节课没有"下一节课"，故只遍历到 length - 1
  for (var i = 0; i < courses.length - 1; i++) {
    final cur = courses[i];
    final next = courses[i + 1];
    final endPeriod = d.periodAt(cur.endPeriod);
    if (endPeriod == null) continue;

    final endAt = midnight.add(Duration(minutes: _hm(endPeriod.end)));
    final remindAt = endAt.subtract(Duration(minutes: minutesBefore));

    // 与 NotificationService.schedule 一致：过去的时间点不调度
    if (!remindAt.isAfter(now)) continue;

    final nextPeriod = d.periodAt(next.startPeriod);
    final parts = <String>[
      if (nextPeriod != null) '${nextPeriod.start} 开始',
      if (next.room.isNotEmpty) next.room,
    ];
    out.add(ReminderPlan(
      remindAt,
      '下节课：${next.name}',
      parts.join(' · '),
      50000 + day * 100 + cur.startPeriod, // NotificationService.idFor
    ));
  }
  return out;
}

int _pass = 0;
int _fail = 0;

void check(String label, Object? actual, Object? expected) {
  if (actual == expected) {
    _pass++;
  } else {
    _fail++;
    print('  [FAIL] $label\n         期望: $expected\n         实际: $actual');
  }
}

void main() {
  // 构造课表：开学日设为"本周一"→ 第 1 周；周一（day=1）排 3 节课
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: now.weekday - 1));
  final start =
      '${monday.year}-${_pad(monday.month)}-${_pad(monday.day)}';

  const json = '''
{
  "name": "验证学期",
  "startDate": "@START@",
  "totalWeeks": 20,
  "periods": [
    {"index": 1, "start": "08:00", "end": "08:45"},
    {"index": 2, "start": "08:55", "end": "09:40"},
    {"index": 3, "start": "10:00", "end": "10:45"}
  ],
  "courses": [
    {"name": "高等数学", "room": "教三301", "day": 1, "startPeriod": 1, "endPeriod": 1},
    {"name": "大学英语", "room": "教五102", "day": 1, "startPeriod": 2, "endPeriod": 2},
    {"name": "体育",     "room": "操场",   "day": 1, "startPeriod": 3, "endPeriod": 3}
  ]
}
''';

  final d = TimetableData.parse(json.replaceAll('@START@', start));

  print('=== 课程提醒调度逻辑验证 ===\n');
  print('课表：${d.name}｜${d.courses.length} 门课｜${d.periods.length} 节次');
  print('第 1 周周一课程：${d.coursesFor(1, 1).map((c) => c.name).join(' → ')}\n');

  // ---- 1. 提醒时刻 = 课程结束前 5 分钟 ----
  // 固定在"周一清晨 06:00"计算：此时 3 节课的提醒时刻都还没到，应全部参与调度
  final early = DateTime(monday.year, monday.month, monday.day, 6, 0);
  final plans = buildPlans(d, 1, 1, early);

  print('--- 用例 1：周一 06:00 计算（3 节课均未到提醒时刻）---');
  for (final p in plans) {
    print('  $p');
  }
  // 第1节 08:00-08:45 → 08:40 提醒「大学英语 08:55 开始」
  // 第2节 08:55-09:40 → 09:35 提醒「体育 10:00 开始」
  // 第3节是最后一节 → 不提醒
  check('提醒条数（最后一节不提醒）', plans.length, 2);
  check('第1条提醒时刻', _fmt(plans[0].remindAt), '08:40');
  check('第1条标题（下一节课名）', plans[0].title, '下节课：大学英语');
  check('第1条正文（时间·教室）', plans[0].body, '08:55 开始 · 教五102');
  check('第2条提醒时刻', _fmt(plans[1].remindAt), '09:35');
  check('第2条标题', plans[1].title, '下节课：体育');
  check('第2条正文', plans[1].body, '10:00 开始 · 操场');

  // ---- 2. 通知 id 稳定唯一 ----
  print('\n--- 用例 2：通知 id 稳定唯一 ---');
  final ids = plans.map((p) => p.id).toSet();
  check('id 无重复', ids.length, plans.length);
  // 周一(1) 第1节 → 50000 + 1*100 + 1 = 50101
  check('第1条 id', plans[0].id, 50101);
  check('第2条 id', plans[1].id, 50102);
  // 同一门课重复调度应得到相同 id（覆盖而非堆积）
  final again = buildPlans(d, 1, 1, early);
  check('重复调度 id 不变（只覆盖不堆积）', again.first.id, plans.first.id);

  // ---- 3. 已过去的时刻不再调度 ----
  print('\n--- 用例 3：已过去的提醒时刻不调度 ---');
  // 周一 10:00：第1节(08:40)、第2节(09:35) 的提醒时刻都已过去，应全部跳过
  final late = DateTime(monday.year, monday.month, monday.day, 10, 0);
  final lateP = buildPlans(d, 1, 1, late);
  print('  10:00 时剩余提醒：${lateP.isEmpty ? '（无，符合预期）' : lateP}');
  check('过期提醒被跳过', lateP.length, 0);

  // 周一 09:00：第1节(08:40)已过，第2节(09:35)未到 → 只剩 1 条
  final mid = DateTime(monday.year, monday.month, monday.day, 9, 0);
  final midP = buildPlans(d, 1, 1, mid);
  print('  09:00 时剩余提醒：${midP.map((p) => p.toString()).join(' ; ')}');
  check('部分过期时只保留未到的提醒', midP.length, 1);
  check('剩余的是第2节的提醒', midP.first.title, '下节课：体育');

  // ---- 4. 无下一节课时不产生提醒 ----
  print('\n--- 用例 4：当天只有 1 节课时不提醒 ---');
  const oneJson = '''
{
  "name": "单节课",
  "startDate": "@START@",
  "periods": [{"index": 1, "start": "08:00", "end": "08:45"}],
  "courses": [
    {"name": "自习", "room": "", "day": 2, "startPeriod": 1, "endPeriod": 1}
  ]
}
''';
  final d2 = TimetableData.parse(oneJson.replaceAll('@START@', start));
  check('单节课当天无提醒', buildPlans(d2, 2, 1, early).length, 0);

  // ---- 5. 周次过滤：不在本周的课程不参与 ----
  print('\n--- 用例 5：周次范围外不提醒 ---');
  const weekJson = '''
{
  "name": "单双周",
  "startDate": "@START@",
  "periods": [
    {"index": 1, "start": "08:00", "end": "08:45"},
    {"index": 2, "start": "08:55", "end": "09:40"}
  ],
  "courses": [
    {"name": "仅第2周A", "room": "", "day": 3, "startPeriod": 1, "endPeriod": 1, "weeks": "2"},
    {"name": "仅第2周B", "room": "", "day": 3, "startPeriod": 2, "endPeriod": 2, "weeks": "2"}
  ]
}
''';
  final d3 = TimetableData.parse(weekJson.replaceAll('@START@', start));
  check('第1周不提醒第2周的课', buildPlans(d3, 3, 1, early).length, 0);
  check('第2周正常提醒', buildPlans(d3, 3, 2, early).length, 1);

  print('\n=== 结果：$_pass 通过 / $_fail 失败 ===');
  if (_fail > 0) {
    throw StateError('存在失败的断言');
  }
}
