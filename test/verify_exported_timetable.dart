/// 验证导出的课表 JSON 能被 TimetableData.parse 正确解析
import 'dart:convert';
import 'dart:io';
import 'package:smartenglish/timetable_models.dart';

void check(bool cond, String name) {
  print('${cond ? "PASS" : "FAIL"}  $name');
  if (!cond) throw StateError('验证失败: $name');
}

void main(List<String> args) {
  final raw = File(args.first).readAsStringSync();
  final d = TimetableData.parse(raw);
  print('学期: ${d.name}');
  print('开学(第1周周一): ${d.startDate}');
  print('总周数: ${d.totalWeeks}  节次数: ${d.periods.length}  课程条目: ${d.courses.length}');
  for (var day = 1; day <= 5; day++) {
    final cs = d.coursesFor(day, 1);
    print('周$day 第1周 ${cs.length} 门: ${cs.map((c) => c.name).toSet().toList()}');
  }
  // 本周(第1周)每天课块数
  var blocks = 0;
  for (var day = 1; day <= 7; day++) {
    blocks += d.coursesFor(day, 1).length;
  }
  check(d.periods.length == 10, '10 节次时间');
  check(d.courses.length == 32, '32 条排课');
  check(d.weekOf(DateTime(2026, 8, 31)) == 1, '2026-08-31 = 第1周');
  check(d.weekOf(DateTime(2026, 10, 11)) == 6, '2026-10-11 = 第6周');
  check(blocks > 0, '第1周有课块');
  // 无周次冲突抽查：周一 7-8 三门课周次两两不重叠
  final m78 = d.coursesFor(1, 1).where((c) => c.startPeriod <= 8 && c.endPeriod >= 7).toList();
  check(m78.length == 1 && m78.first.name.contains('体育'), '第1周周一7-8只有体育');
  final m78w10 = d.coursesFor(1, 10).where((c) => c.startPeriod <= 8 && c.endPeriod >= 7).toList();
  check(m78w10.length == 1 && m78w10.first.name.contains('人工智能'), '第10周周一7-8只有人工智能导论');
  print('\\n课表 JSON 验证全部通过 ✓');
}
