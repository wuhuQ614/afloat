/// 验证 validate_timetable 的校验算法（与 state.dart _toolValidateTimetable 同源）
/// 运行：dart run test/verify_timetable_validate.dart
import '../lib/timetable_models.dart';

int _hm(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

class CheckResult {
  final bool valid;
  final List<String> codes;
  CheckResult(this.valid, this.codes);
}

/// 校验算法（与 _toolValidateTimetable 中逐项体检部分一致）
CheckResult validate(String raw) {
  TimetableData data;
  try {
    data = TimetableData.parse(raw);
  } on TimetableFormatException catch (_) {
    return CheckResult(false, ['format_error']);
  }
  final codes = <String>[];
  if (data.courses.isEmpty) codes.add('no_courses');

  for (var i = 0; i < data.periods.length; i++) {
    final p = data.periods[i];
    if (_hm(p.start) >= _hm(p.end)) codes.add('period_reverse');
    if (i > 0) {
      final prev = data.periods[i - 1];
      if (_hm(p.start) < _hm(prev.end)) codes.add('period_overlap');
    }
  }
  final defined = data.periods.map((p) => p.index).toSet();
  for (final c in data.courses) {
    if (!defined.contains(c.startPeriod) || !defined.contains(c.endPeriod)) {
      codes.add('undefined_period');
      break;
    }
  }
  var maxWeek = 0;
  for (final c in data.courses) {
    if (c.weeks != null && c.weeks!.isNotEmpty) {
      final m = c.weeks!.reduce((a, b) => a > b ? a : b);
      if (m > maxWeek) maxWeek = m;
    }
  }
  if (maxWeek > data.totalWeeks) codes.add('weeks_overflow');

  for (var day = 1; day <= 7; day++) {
    final list = data.courses.where((c) => c.day == day).toList()
      ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final a = list[i], b = list[j];
        final overlapWeeks =
            a.weeks == null || b.weeks == null || a.weeks!.intersection(b.weeks!).isNotEmpty;
        if (overlapWeeks && a.startPeriod <= b.endPeriod && b.startPeriod <= a.endPeriod) {
          codes.add('course_conflict');
        }
      }
    }
  }
  return CheckResult(true, codes.toSet().toList());
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

String _doc(String courses, {String periods = '', int totalWeeks = 20}) {
  final p = periods.isNotEmpty
      ? periods
      : '{"index":1,"start":"08:00","end":"08:45"},{"index":2,"start":"08:55","end":"09:40"},'
          '{"index":3,"start":"10:00","end":"10:45"}';
  return '{"name":"测试学期","startDate":"2026-08-31",'
      '"totalWeeks":$totalWeeks,"periods":[$p],"courses":[$courses]}';
}

void main() {
  // 1. 正常课表：无任何问题
  var r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":2,"weeks":"1-16"}'));
  check(r.valid && r.codes.isEmpty, '正常课表：校验通过且无警告');

  // 2. 课程为空
  r = validate(_doc(''));
  check(r.valid && r.codes.contains('no_courses'), 'courses 为空 → no_courses 警告');

  // 3. 节次时间倒挂
  r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":1}',
      periods: '{"index":1,"start":"09:00","end":"08:00"}'));
  check(r.codes.contains('period_reverse'), '节次时间倒挂 → period_reverse');

  // 4. 相邻节次重叠
  r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":1}',
      periods: '{"index":1,"start":"08:00","end":"09:00"},{"index":2,"start":"08:30","end":"09:30"}'));
  check(r.codes.contains('period_overlap'), '相邻节次时间重叠 → period_overlap');

  // 5. 课程引用未定义节次
  r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":9}'));
  check(r.codes.contains('undefined_period'), '引用未定义节次 → undefined_period');

  // 6. 周次越界
  r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":2,"weeks":"1-30"}',
      totalWeeks: 20));
  check(r.codes.contains('weeks_overflow'), '周次 30 > totalWeeks 20 → weeks_overflow');

  // 7. 同天同节次冲突
  r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":2},'
      '{"name":"英语","day":1,"startPeriod":2,"endPeriod":3}'));
  check(r.codes.contains('course_conflict'), '同一天节次重叠 → course_conflict');

  // 8. 同天但周次不重叠：不算冲突
  r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":2,"weeks":"1-8"},'
      '{"name":"英语","day":1,"startPeriod":2,"endPeriod":3,"weeks":"9-16"}'));
  check(!r.codes.contains('course_conflict'), '同天但周次不重叠 → 不算冲突');

  // 9. 不同天同节次：不算冲突
  r = validate(_doc('{"name":"高数","day":1,"startPeriod":1,"endPeriod":2},'
      '{"name":"英语","day":2,"startPeriod":1,"endPeriod":2}'));
  check(!r.codes.contains('course_conflict') && r.codes.isEmpty, '不同天同节次 → 无冲突');

  // 10. 格式错误：缺 startDate → 第 1 道校验不通过
  r = validate('{"name":"x","periods":[{"index":1,"start":"08:00","end":"08:45"}],"courses":[]}');
  check(!r.valid && r.codes.contains('format_error'), '缺 startDate → valid=false（拦截）');

  // 11. 格式错误：非法 JSON
  r = validate('{not json');
  check(!r.valid, '非法 JSON → valid=false');

  print(_fail == 0 ? '\n全部通过（11 项）' : '\n$_fail 项失败');
  if (_fail > 0) throw Exception('存在失败项');
}
