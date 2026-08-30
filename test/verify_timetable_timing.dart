/// 验证课程表时间联动逻辑（与 timetable_page.dart 高亮算法同源，纯逻辑无 UI）
/// 运行：dart run test/verify_timetable_timing.dart
import '../lib/timetable_models.dart';

int _hm(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

/// 与页面 _statusOf 同算法：返回 0=无 / 1=上课中(绿) / 2=下一节(红)
int _statusOf(TimetableCourse course, TimetableCourse? upcoming, int hm, TimetableData d) {
  if (upcoming == null || !identical(upcoming, course)) return 0;
  final sp = d.periodAt(course.startPeriod);
  if (sp == null) return 0;
  return hm >= _hm(sp.start) ? 1 : 2;
}

/// 与页面 _currentPeriodIndex 同算法
int? _currentPeriodIndex(TimetableData d, int hm) {
  for (final p in d.periods) {
    if (hm >= _hm(p.start) && hm < _hm(p.end)) return p.index;
  }
  return null;
}

int _fail = 0;
void check(bool cond, String name) {
  if (cond) {
    print('PASS  $name');
  } else {
    print('FAIL  $name');
    _fail++;
  }
}

void main() {
  final data = TimetableData.parse('''
{
  "name": "测试学期",
  "startDate": "2026-08-31",
  "totalWeeks": 20,
  "periods": [
    {"index": 1, "start": "08:00", "end": "08:45"},
    {"index": 2, "start": "08:55", "end": "09:40"},
    {"index": 3, "start": "10:00", "end": "10:45"},
    {"index": 4, "start": "10:55", "end": "11:40"},
    {"index": 5, "start": "14:00", "end": "14:45"},
    {"index": 6, "start": "14:55", "end": "15:40"}
  ],
  "courses": [
    {"name": "高数", "day": 1, "startPeriod": 1, "endPeriod": 2, "weeks": "1-16"},
    {"name": "英语", "day": 1, "startPeriod": 3, "endPeriod": 4, "weeks": "1-16"},
    {"name": "体育", "day": 1, "startPeriod": 5, "endPeriod": 6, "weeks": "1-16"}
  ]
}
''');

  // ===== 1. copyWith：只改 startDate，其余保留 =====
  final moved = data.copyWith(startDate: DateTime(2026, 9, 7));
  check(moved.courses.length == 3, 'copyWith 保留 courses');
  check(moved.periods.length == 6, 'copyWith 保留 periods');
  check(moved.name == '测试学期', 'copyWith 保留 name');
  check(moved.startDate == DateTime(2026, 9, 7), 'copyWith 更新 startDate');
  check(moved.weekOf(DateTime(2026, 9, 7)) == 1, '改开学日期后 9-07 变第 1 周');
  check(data.weekOf(DateTime(2026, 9, 7)) == 2, '原日期下 9-07 仍是第 2 周（未串扰）');
  check(data.weekOf(DateTime(2026, 9, 14)) == 3, '原日期下 9-14 第 3 周');

  // ===== 2. 高亮判定：早上上课前 =====
  final today = data.coursesFor(1, 1); // 已按 startPeriod 排序：高数(1-2) 英语(3-4) 体育(5-6)
  // 08:10 上课中 → 高数 = 上课中(1)
  var hm = _hm('08:10');
  var cur = _currentPeriodIndex(data, hm);
  check(cur == 1, '08:10 处于第 1 节');
  var up = _firstUngoing(today, data, hm);
  check(up != null && up.name == '高数', '08:10 第一门未结束的课 = 高数');
  check(_statusOf(today[0], up, hm, data) == 1, '08:10 高数标绿（上课中）');
  check(_statusOf(today[1], up, hm, data) == 0, '08:10 英语无标记');

  // 08:50 课间 → 下一节 = 第 2 节（高数仍在 1-2 节内）
  hm = _hm('08:50');
  up = _firstUngoing(today, data, hm);
  check(up != null && up.name == '高数', '08:50 高数仍未结束');
  check(_statusOf(today[0], up, hm, data) == 1, '08:50 高数仍上课中（跨节内）');

  // 09:45 高数已下，下一节 = 英语（10:00 开始）
  hm = _hm('09:45');
  up = _firstUngoing(today, data, hm);
  check(up != null && up.name == '英语', '09:45 下一节 = 英语');
  check(_statusOf(today[1], up, hm, data) == 2, '09:45 英语标红（下一节）');
  check(_statusOf(today[0], up, hm, data) == 0, '09:45 高数无标记');

  // 10:20 英语上课中
  hm = _hm('10:20');
  cur = _currentPeriodIndex(data, hm);
  check(cur == 3, '10:20 处于第 3 节');
  up = _firstUngoing(today, data, hm);
  check(up != null && up.name == '英语', '10:20 上课中 = 英语');
  check(_statusOf(today[1], up, hm, data) == 1, '10:20 英语标绿');

  // 16:00 全天结束 → 无高亮
  hm = _hm('16:00');
  up = _firstUngoing(today, data, hm);
  check(up == null, '16:00 所有课结束 → 无高亮');

  // ===== 3. 周末 / 无课日：coursesFor 为空 =====
  check(data.coursesFor(6, 1).isEmpty, '周六无课');

  // ===== 4. 节假日时段（中午 12:00）无当前节次 =====
  check(_currentPeriodIndex(data, _hm('12:00')) == null, '12:00 不在任何节次区间');

  print(_fail == 0 ? '\n全部通过（18 项）' : '\n$_fail 项失败');
  if (_fail > 0) {
    throw Exception('存在失败项');
  }
}

/// 第一门还没结束的课（页面算法同源）
TimetableCourse? _firstUngoing(List<TimetableCourse> courses, TimetableData d, int hm) {
  for (final c in courses) {
    final ep = d.periodAt(c.endPeriod);
    if (ep != null && hm < _hm(ep.end)) return c;
  }
  return null;
}
