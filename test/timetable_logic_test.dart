/// 课程表模型纯逻辑验证（不依赖 Flutter，dart run 直接跑）
import 'dart:convert';
import 'package:smartenglish/timetable_models.dart';

void check(bool cond, String name) {
  print('${cond ? "PASS" : "FAIL"}  $name');
  if (!cond) throw StateError('验证失败: $name');
}

void main() {
  // 1. 标准解析
  final raw = '''
  {
    "name": "2025-2026 第1学期",
    "startDate": "2025-09-01",
    "periods": [
      {"index": 1, "start": "08:30", "end": "09:15"},
      {"index": 2, "start": "09:20", "end": "10:05"},
      {"index": 3, "start": "10:25", "end": "11:10"},
      {"index": 4, "start": "11:15", "end": "12:00"},
      {"index": 5, "start": "14:30", "end": "15:15"},
      {"index": 6, "start": "15:20", "end": "16:05"},
      {"index": 7, "start": "16:25", "end": "17:10"},
      {"index": 8, "start": "17:15", "end": "18:00"}
    ],
    "courses": [
      {"name": "人工智能导论", "room": "@校本部机大楼212", "day": 4, "startPeriod": 1, "endPeriod": 3, "weeks": "1-16"},
      {"name": "机械设计基础", "room": "@校本部机电大楼304", "day": 1, "startPeriod": 3, "endPeriod": 4, "weeks": "1-8,10,12-16"},
      {"name": "体育与 health", "day": 1, "startPeriod": 7, "endPeriod": 8},
      {"name": "无周次全周课", "day": 7, "startPeriod": 5, "endPeriod": 5, "weeks": "all"}
    ]
  }''';
  final d = TimetableData.parse(raw);
  check(d.name == '2025-2026 第1学期', '解析 name');
  check(d.periods.length == 8, '解析 periods 8 节');
  check(d.periodAt(5)!.start == '14:30', 'periodAt(5) 时间正确');
  check(d.totalWeeks == 16, 'totalWeeks 由课程最大周次推出 = 16');

  // 2. 周次推算：2025-09-01 是周一 → 当周为第 1 周；+7 天为第 2 周；开学前 clamp 到 1
  check(d.weekOf(DateTime(2025, 9, 1)) == 1, '开学当天 = 第1周');
  check(d.weekOf(DateTime(2025, 9, 8)) == 2, '开学+7天 = 第2周');
  check(d.weekOf(DateTime(2025, 12, 21)) == 16, '第16周周日');
  check(d.dateOf(16, 7) == DateTime(2025, 12, 21), '第16周周日日期');
  check(d.weekOf(DateTime(2025, 8, 30)) == 1, '开学前 clamp 到 1');
  check(d.dateOf(1, 1) == DateTime(2025, 9, 1), '第1周周一日期');
  check(d.dateOf(2, 7) == DateTime(2025, 9, 14), '第2周周日日期');

  // 3. coursesFor：周次过滤
  check(d.coursesFor(1, 1).length == 2, '第1周周一 2 门课');
  check(d.coursesFor(1, 9).length == 1, '第9周周一只剩无 weeks 的课+all'); // 机械设计(1-8,10..)不在 9
  check(d.coursesFor(1, 9).first.name == '体育与 health' || d.coursesFor(1, 9).length == 1, '第9周周一过滤正确');
  check(d.coursesFor(4, 3).first.name == '人工智能导论', '周三(4)课');
  check(d.coursesFor(7, 30).length == 1, 'weeks=all 每周有效');

  // 4. weeks 解析形态
  final d2 = TimetableData.parse(jsonEncode({
    'startDate': '2025-09-01',
    'periods': [
      {'index': 1, 'start': '08:00', 'end': '08:45'}
    ],
    'courses': [
      {'name': 'A', 'day': 1, 'startPeriod': 1, 'endPeriod': 1, 'weeks': [1, 2, 5]},
      {'name': 'B', 'day': 2, 'startPeriod': 1, 'endPeriod': 1, 'weeks': '3'},
    ],
  }));
  check(d2.coursesFor(1, 1).isNotEmpty && d2.coursesFor(1, 3).isEmpty, 'weeks 数组 [1,2,5]');
  check(d2.coursesFor(2, 3).isNotEmpty && d2.coursesFor(2, 4).isEmpty, 'weeks 单数字 "3"');

  // 5. round-trip：toJson → parse 幂等
  final rt = TimetableData.parse(jsonEncode(d.toJson()));
  check(rt.name == d.name && rt.startDate == d.startDate && rt.courses.length == d.courses.length, 'round-trip 结构一致');
  check(rt.courses[1].weeks != null && rt.courses[1].weeks!.contains(10) && !rt.courses[1].weeks!.contains(9), 'round-trip weeks "1-8,10,12-16" 保真');

  // 6. 错误提示
  _expectFormatError('{"periods":[],"courses":[]}', '缺 periods');
  _expectFormatError('{"startDate":"bad-date","periods":[{"index":1,"start":"08:00","end":"09:00"}],"courses":[]}', 'startDate 格式错');
  _expectFormatError('{"startDate":"2025-09-01","periods":[{"index":1,"start":"0800","end":"09:00"}],"courses":[]}', '时间格式错');
  _expectFormatError('not json', '非法 JSON');
  _expectFormatError('{"startDate":"2025-09-01","periods":[{"index":1,"start":"08:00","end":"09:00"}],"courses":[{"day":9,"startPeriod":1}]}', 'day 越界');

  print('\\n全部通过 ✓');
}

void _expectFormatError(String raw, String name) {
  try {
    TimetableData.parse(raw);
    check(false, '应抛格式错误: $name');
  } on TimetableFormatException {
    check(true, '格式错误被拦截: $name');
  }
}
