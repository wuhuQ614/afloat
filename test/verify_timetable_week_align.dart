/// 验证 weekOf/dateOf 对齐"周次首日=周一"：startDate 任意星期，
/// day 1..7 始终对应周一..周日，与表头一/二/…/日严格对齐
/// 运行：dart run test/verify_timetable_week_align.dart
import '../lib/timetable_models.dart';

int _fail = 0;
void check(bool cond, String name) {
  if (cond) {
    print('PASS  $name');
  } else {
    print('FAIL  $name');
    _fail++;
  }
}

TimetableData _parse(String startDate) {
  return TimetableData.parse('''
{
  "name": "对齐测试",
  "startDate": "$startDate",
  "totalWeeks": 20,
  "periods": [
    {"index": 1, "start": "08:00", "end": "08:45"},
    {"index": 2, "start": "08:55", "end": "09:40"}
  ],
  "courses": []
}
''');
}

void main() {
  // ===== 场景 A：startDate = 2026-08-31（周一）—— 经典情况 =====
  final a = _parse('2026-08-31');
  // weekday: 周一=1, 周日=7
  check(a.dateOf(1, 1).weekday == 1 && a.dateOf(1, 1) == DateTime(2026, 8, 31), 'A.startDate=周一: week1/day1=周一(8-31)');
  check(a.dateOf(1, 7) == DateTime(2026, 9, 6), 'A.startDate=周一: week1/day7=周日(9-6)');
  check(a.dateOf(2, 1) == DateTime(2026, 9, 7), 'A.startDate=周一: week2/day1=下周一(9-7)');
  check(a.weekOf(DateTime(2026, 8, 31)) == 1, 'A.开学日=第 1 周');
  check(a.weekOf(DateTime(2026, 9, 5)) == 1, 'A.周六(9-5)=第 1 周内');
  check(a.weekOf(DateTime(2026, 9, 7)) == 2, 'A.下周一(9-7)=第 2 周');

  // ===== 场景 B：startDate = 2026-08-30（周日，开学日=周日）=====
  // 这是用户截图场景：开学日是周日，day=7(日) 列才应该是 8-30
  final b = _parse('2026-08-30');
  check(b.startDate.weekday == 7, 'B.startDate 本身是周日');
  check(b.dateOf(1, 1).weekday == 1, 'B.week1/day1 必须是周一（与表头"一"对齐）');
  check(b.dateOf(1, 1) == DateTime(2026, 8, 24), 'B.week1/day1=周一(8-24)');
  check(b.dateOf(1, 7) == DateTime(2026, 8, 30), 'B.week1/day7=周日(8-30)——这才是开学日');
  check(b.weekOf(DateTime(2026, 8, 30)) == 1, 'B.开学日周日(8-30)=第 1 周');
  check(b.weekOf(DateTime(2026, 8, 24)) == 1, 'B.周一(8-24)同周=第 1 周');
  check(b.weekOf(DateTime(2026, 8, 31)) == 2, 'B.下周一(8-31)=第 2 周');

  // ===== 场景 C：startDate = 2026-09-02（周三，开学日=周三）=====
  final c = _parse('2026-09-02');
  check(c.startDate.weekday == 3, 'C.startDate 本身是周三');
  check(c.dateOf(1, 1).weekday == 1, 'C.week1/day1 必须是周一');
  check(c.dateOf(1, 1) == DateTime(2026, 8, 31), 'C.week1/day1=周一(8-31)');
  check(c.dateOf(1, 3) == DateTime(2026, 9, 2), 'C.week1/day3=周三(9-2)——开学日');
  check(c.dateOf(1, 7) == DateTime(2026, 9, 6), 'C.week1/day7=周日(9-6)');
  check(c.weekOf(DateTime(2026, 9, 2)) == 1, 'C.开学日周三(9-2)=第 1 周');
  check(c.weekOf(DateTime(2026, 8, 31)) == 1, 'C.周一(8-31)同周=第 1 周');
  check(c.weekOf(DateTime(2026, 9, 7)) == 2, 'C.下周一(9-7)=第 2 周');

  // ===== 场景 D：跨学期边界（学期外）=====
  // 总周数 20，开学前/学期末应 clamp
  check(a.weekOf(DateTime(2026, 7, 1)) == 1, 'A.开学前 clamp 到第 1 周');
  // 学期末：20*7=140 天后 = 2027-01-18(周一)
  check(a.weekOf(DateTime(2027, 1, 18)) == 20, 'A.学期末周一=第 20 周');
  check(a.weekOf(DateTime(2027, 1, 25)) == 20, 'A.学期末之后 clamp 到第 20 周');

  print(_fail == 0 ? '\n全部通过（20 项）' : '\n$_fail 项失败');
  if (_fail > 0) throw Exception('存在失败项');
}
