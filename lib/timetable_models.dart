/// 课程表模式数据模型：JSON 导入 → TimetableData
///
/// 导入格式约定（参考超级课程表：课程时间由导入的节次时间分布决定，非固定）：
/// ```json
/// {
///   "name": "2025-2026 第1学期",
///   "startDate": "2025-09-01",              // 第1周周一的日期（用于推算当前周次）
///   "totalWeeks": 20,                        // 可选，学期总周数（默认取课程最大周次，至少 20）
///   "periods": [                             // 一天的节次时间分布（每一天共用，必填）
///     {"index": 1, "start": "08:30", "end": "09:15"},
///     {"index": 2, "start": "09:20", "end": "10:05"}
///   ],
///   "courses": [
///     {
///       "name": "机械设计基础",              // 必填
///       "teacher": "张三",                   // 可选
///       "room": "@校本部机电大楼304",         // 可选
///       "day": 1,                            // 1=周一 … 7=周日，必填
///       "startPeriod": 3,                    // 起始节次（对应 periods[].index），必填
///       "endPeriod": 4,                      // 结束节次（含），必填
///       "weeks": "1-16"                      // 可选："1-16" | "1-8,10,12-16" | "all" | [1,2,3]；缺省=每周都有
///     }
///   ]
/// }
/// ```
library;

import 'dart:convert';

/// 一节课的时间分布（节次）
class TimetablePeriod {
  final int index; // 节次序号（1 起）
  final String start; // HH:mm
  final String end; // HH:mm
  const TimetablePeriod({required this.index, required this.start, required this.end});

  factory TimetablePeriod.fromJson(Map<String, dynamic> j) {
    final idx = j['index'];
    final s = (j['start'] ?? '').toString().trim();
    final e = (j['end'] ?? '').toString().trim();
    if (idx is! int || idx < 1) throw const TimetableFormatException('periods[].index 必须是正整数节次序号');
    if (!_timeExp.hasMatch(s) || !_timeExp.hasMatch(e)) {
      throw const TimetableFormatException('periods[].start/end 必须是 HH:mm 格式（如 08:30）');
    }
    return TimetablePeriod(index: idx, start: s, end: e);
  }

  static final RegExp _timeExp = RegExp(r'^\d{1,2}:\d{2}$');
}

/// 一门课的一次排课（星期几 + 起止节次 + 周次范围）
class TimetableCourse {
  final String name;
  final String teacher;
  final String room;
  final int day; // 1=周一 … 7=周日
  final int startPeriod;
  final int endPeriod;
  final Set<int>? weeks; // null = 每周都有
  final int colorIndex; // 调色板索引（JSON color 缺省时按出现顺序分配）

  const TimetableCourse({
    required this.name,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    this.teacher = '',
    this.room = '',
    this.weeks,
    this.colorIndex = 0,
  });

  bool activeInWeek(int week) => weeks == null || weeks!.contains(week);

  factory TimetableCourse.fromJson(Map<String, dynamic> j, int colorIndex) {
    final name = (j['name'] ?? '').toString().trim();
    if (name.isEmpty) throw const TimetableFormatException('courses[].name 不能为空');
    final day = j['day'];
    if (day is! int || day < 1 || day > 7) {
      throw const TimetableFormatException('courses[].day 必须是 1~7（1=周一 … 7=周日）');
    }
    final sp = j['startPeriod'] ?? j['start'] ?? j['sectionStart'];
    final ep = j['endPeriod'] ?? j['end'] ?? j['sectionEnd'] ?? sp;
    if (sp is! int || sp < 1 || (ep is! int) || ep < sp) {
      throw const TimetableFormatException('courses[].startPeriod/endPeriod 必须是整数节次，且 startPeriod ≤ endPeriod');
    }
    return TimetableCourse(
      name: name,
      teacher: (j['teacher'] ?? '').toString().trim(),
      room: (j['room'] ?? j['location'] ?? '').toString().trim(),
      day: day,
      startPeriod: sp,
      endPeriod: ep,
      weeks: _parseWeeks(j['weeks']),
      colorIndex: colorIndex,
    );
  }

  /// weeks 字段宽容解析："1-16" | "1-8,10,12-16" | "all" | [1,2,3] | 缺省
  static Set<int>? _parseWeeks(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      final s = <int>{};
      for (final v in raw) {
        if (v is int && v > 0) s.add(v);
      }
      return s.isEmpty ? null : s;
    }
    final str = raw.toString().trim();
    if (str.isEmpty || str == 'all' || str == '全部' || str == 'allWeeks') return null;
    final s = <int>{};
    for (final part in str.split(RegExp('[,，;；]'))) {
      final p = part.trim();
      if (p.isEmpty) continue;
      final range = RegExp(r'^(\d+)\s*[-–—~]\s*(\d+)$').firstMatch(p);
      if (range != null) {
        final a = int.parse(range.group(1)!);
        final b = int.parse(range.group(2)!);
        for (var i = a; i <= b && i - a < 200; i++) {
          if (i > 0) s.add(i);
        }
      } else if (RegExp(r'^\d+$').hasMatch(p)) {
        s.add(int.parse(p));
      } else if (p.contains('单') || p.contains('双')) {
        // "单周"/"双周"：交给上层按起始日期奇偶推算没有依据，此处按全周显示
        return null;
      }
    }
    return s.isEmpty ? null : s;
  }
}

/// JSON 解析失败（带用户可读信息）
class TimetableFormatException implements Exception {
  final String message;
  const TimetableFormatException(this.message);
  @override
  String toString() => message;
}

/// 一份完整的课程表
class TimetableData {
  final String name;
  final DateTime startDate; // 第 1 周周一
  final int totalWeeks;
  final List<TimetablePeriod> periods; // 按 index 升序
  final List<TimetableCourse> courses;

  const TimetableData({
    required this.name,
    required this.startDate,
    required this.totalWeeks,
    required this.periods,
    required this.courses,
  });

  /// 仅改部分字段（开学日期设置等场景；periods/courses 保持不变）
  TimetableData copyWith({String? name, DateTime? startDate, int? totalWeeks}) => TimetableData(
        name: name ?? this.name,
        startDate: startDate ?? this.startDate,
        totalWeeks: totalWeeks ?? this.totalWeeks,
        periods: periods,
        courses: courses,
      );

  /// 节次总数（用于网格行数）
  int get periodCount => periods.isEmpty ? 12 : periods.length;

  /// 最大节次序号（periods 不连续时网格仍按序号定位）
  int get maxPeriodIndex =>
      periods.isEmpty ? 12 : periods.map((p) => p.index).reduce((a, b) => a > b ? a : b);

  TimetablePeriod? periodAt(int index) {
    for (final p in periods) {
      if (p.index == index) return p;
    }
    return null;
  }

  /// 指定星期（1~7）+ 周次下有效的课程
  List<TimetableCourse> coursesFor(int day, int week) =>
      courses.where((c) => c.day == day && c.activeInWeek(week)).toList()
        ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));

  /// 今天是第几周（1 起；开学前/学期外返回 clamp 后的边界值）
  /// startDate 可以是任意星期——weekOf 按"第 1 周周一开始日"对齐：先找 startDate 所在周的周一
  /// 作为学期起点，再算 today 所在周与之相差几周
  int weekOf(DateTime today) {
    final d = DateTime(today.year, today.month, today.day);
    final startOfStartWeek = _weekStart;
    final startOfTodayWeek = d.subtract(Duration(days: d.weekday - 1));
    final diff = startOfTodayWeek.difference(startOfStartWeek).inDays;
    final w = (diff / 7).floor() + 1;
    return w.clamp(1, totalWeeks);
  }

  /// 第 [week] 周星期 [day]（1~7 固定对应周一~周日）的日期。
  /// 与 startDate 实际是星期几无关——day=1 始终是该周周一、day=7 始终是周日，
  /// 保证日期与"一/二/…/日"表头严格对齐
  DateTime dateOf(int week, int day) =>
      _weekStart.add(Duration(days: (week - 1) * 7 + (day - 1)));

  /// startDate 所在周的周一（学期时间轴锚点）
  DateTime get _weekStart =>
      DateTime(startDate.year, startDate.month, startDate.day)
          .subtract(Duration(days: startDate.weekday - 1));

  /// 序列化（持久化到 Storage 用；weeks 还原成 "a-b,c" 紧凑区间串）
  Map<String, dynamic> toJson() => {
        'name': name,
        'startDate': '${startDate.year.toString().padLeft(4, '0')}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
        'totalWeeks': totalWeeks,
        'periods': [
          for (final p in periods) {'index': p.index, 'start': p.start, 'end': p.end},
        ],
        'courses': [
          for (final c in courses) {
            'name': c.name,
            if (c.teacher.isNotEmpty) 'teacher': c.teacher,
            if (c.room.isNotEmpty) 'room': c.room,
            'day': c.day,
            'startPeriod': c.startPeriod,
            'endPeriod': c.endPeriod,
            if (c.weeks != null) 'weeks': weeksToSpec(c.weeks!),
          },
        ],
      };

  /// 把周次集合压缩为 "1-8,10,12-16" 形式
  static String weeksToSpec(Set<int> weeks) {
    final s = weeks.toList()..sort();
    final parts = <String>[];
    var i = 0;
    while (i < s.length) {
      var j = i;
      while (j + 1 < s.length && s[j + 1] == s[j] + 1) {
        j++;
      }
      parts.add(i == j ? '${s[i]}' : '${s[i]}-${s[j]}');
      i = j + 1;
    }
    return parts.join(',');
  }

  // ===== 解析 =====

  /// 解析 JSON 字符串，失败抛 TimetableFormatException
  factory TimetableData.parse(String raw) {
    dynamic root;
    try {
      root = jsonDecode(raw);
    } catch (_) {
      throw const TimetableFormatException('不是合法的 JSON 文本');
    }
    if (root is! Map<String, dynamic>) {
      throw const TimetableFormatException('JSON 根节点必须是对象 {…}');
    }
    final name = (root['name'] ?? root['term'] ?? '我的课程表').toString().trim();
    final startRaw = (root['startDate'] ?? root['start'] ?? '').toString().trim();
    if (startRaw.isEmpty) {
      throw const TimetableFormatException('缺少 startDate（第 1 周周一的日期，如 "2025-09-01"）——周次推算依赖它');
    }
    final startDate = DateTime.tryParse(startRaw.replaceAll('/', '-'));
    if (startDate == null) {
      throw const TimetableFormatException('startDate 无法解析，格式应为 yyyy-MM-dd（如 "2025-09-01"）');
    }
    // 节次时间分布（必填——课程块的显示时间完全由它决定）
    final periodsRaw = root['periods'] ?? root['sections'] ?? root['times'];
    if (periodsRaw is! List || periodsRaw.isEmpty) {
      throw const TimetableFormatException('缺少 periods（一天的节次时间分布，如 [{"index":1,"start":"08:30","end":"09:15"},…]）');
    }
    final periods = <TimetablePeriod>[];
    for (final p in periodsRaw) {
      if (p is! Map<String, dynamic>) throw const TimetableFormatException('periods[] 的每一项都必须是对象 {index, start, end}');
      periods.add(TimetablePeriod.fromJson(p));
    }
    periods.sort((a, b) => a.index.compareTo(b.index));
    // 课程
    final coursesRaw = root['courses'] ?? root['classes'] ?? root['lessons'];
    if (coursesRaw is! List) {
      throw const TimetableFormatException('缺少 courses（课程列表，可为空数组 []）');
    }
    final courses = <TimetableCourse>[];
    for (var i = 0; i < coursesRaw.length; i++) {
      final c = coursesRaw[i];
      if (c is! Map<String, dynamic>) throw TimetableFormatException('courses[$i] 必须是对象');
      courses.add(TimetableCourse.fromJson(c, i));
    }
    // 总周数：显式指定 > 课程最大周次 > 默认 20
    var totalWeeks = 20;
    if (root['totalWeeks'] is int && root['totalWeeks'] > 0) {
      totalWeeks = root['totalWeeks'];
    } else {
      var mx = 0;
      for (final c in courses) {
        if (c.weeks != null) mx = mx > c.weeks!.reduce((a, b) => a > b ? a : b) ? mx : c.weeks!.reduce((a, b) => a > b ? a : b);
      }
      if (mx > 0) totalWeeks = mx;
    }
    return TimetableData(
      name: name,
      startDate: DateTime(startDate.year, startDate.month, startDate.day),
      totalWeeks: totalWeeks,
      periods: periods,
      courses: courses,
    );
  }
}
