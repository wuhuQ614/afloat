/// 课程表编辑对话框
/// 可编辑：学期名、开学日期、总周数、节次时间分布、课程列表（增/删/改）
/// 保存时构造新 TimetableData 并 setTimetable，校验失败给具体提示
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state.dart';
import '../theme_colors.dart' show AppColors;
import '../timetable_models.dart';
import 'timetable_format_doc.dart';

class EditTimetableDialog extends StatefulWidget {
  final AppState state;
  const EditTimetableDialog({super.key, required this.state});

  @override
  State<EditTimetableDialog> createState() => _EditTimetableDialogState();
}

class _EditTimetableDialogState extends State<EditTimetableDialog> {
  late TextEditingController _nameCtrl;
  late DateTime _startDate;
  late int _totalWeeks;
  late List<_PeriodRow> _periods;
  late List<_CourseRow> _courses;

  @override
  void initState() {
    super.initState();
    final d = widget.state.timetable!;
    _nameCtrl = TextEditingController(text: d.name);
    _startDate = d.startDate;
    _totalWeeks = d.totalWeeks;
    _periods = d.periods
        .map((p) => _PeriodRow(
              index: TextEditingController(text: '${p.index}'),
              start: TextEditingController(text: p.start),
              end: TextEditingController(text: p.end),
            ))
        .toList();
    _courses = d.courses
        .map((c) => _CourseRow(
              name: TextEditingController(text: c.name),
              teacher: TextEditingController(text: c.teacher),
              room: TextEditingController(text: c.room),
              day: TextEditingController(text: '${c.day}'),
              startPeriod: TextEditingController(text: '${c.startPeriod}'),
              endPeriod: TextEditingController(text: '${c.endPeriod}'),
              weeks: TextEditingController(
                  text: c.weeks == null ? '' : TimetableData.weeksToSpec(c.weeks!)),
              colorIndex: c.colorIndex,
            ))
        .toList();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final p in _periods) {
      p.index.dispose();
      p.start.dispose();
      p.end.dispose();
    }
    for (final c in _courses) {
      c.name.dispose();
      c.teacher.dispose();
      c.room.dispose();
      c.day.dispose();
      c.startPeriod.dispose();
      c.endPeriod.dispose();
      c.weeks.dispose();
    }
    super.dispose();
  }

  void _addPeriod() {
    final nextIdx = _periods.isEmpty
        ? 1
        : (_periods
                .map((p) => int.tryParse(p.index.text.trim()) ?? 0)
                .reduce((a, b) => a > b ? a : b) +
            1);
    setState(() {
      _periods.add(_PeriodRow(
        index: TextEditingController(text: '$nextIdx'),
        start: TextEditingController(text: '08:00'),
        end: TextEditingController(text: '08:45'),
      ));
    });
  }

  void _removePeriod(int i) {
    setState(() {
      final p = _periods.removeAt(i);
      p.index.dispose();
      p.start.dispose();
      p.end.dispose();
    });
  }

  void _addCourse() {
    setState(() {
      _courses.add(_CourseRow(
        name: TextEditingController(text: '新课程'),
        teacher: TextEditingController(),
        room: TextEditingController(),
        day: TextEditingController(text: '1'),
        startPeriod: TextEditingController(text: '1'),
        endPeriod: TextEditingController(text: '1'),
        weeks: TextEditingController(text: '1-16'),
        colorIndex: _courses.length % 6,
      ));
    });
  }

  void _removeCourse(int i) {
    setState(() {
      final c = _courses.removeAt(i);
      c.name.dispose();
      c.teacher.dispose();
      c.room.dispose();
      c.day.dispose();
      c.startPeriod.dispose();
      c.endPeriod.dispose();
      c.weeks.dispose();
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('学期名不能为空');
      return;
    }
    final periodsJson = StringBuffer('[');
    for (var i = 0; i < _periods.length; i++) {
      if (i > 0) periodsJson.write(',');
      final idx = _periods[i].index.text.trim();
      final s = _periods[i].start.text.trim();
      final e = _periods[i].end.text.trim();
      periodsJson.write('{"index":$idx,"start":"$s","end":"$e"}');
    }
    periodsJson.write(']');

    final coursesJson = StringBuffer('[');
    for (var i = 0; i < _courses.length; i++) {
      if (i > 0) coursesJson.write(',');
      final c = _courses[i];
      final n = c.name.text.trim();
      final t = c.teacher.text.trim();
      final r = c.room.text.trim();
      final d = c.day.text.trim();
      final sp = c.startPeriod.text.trim();
      final ep = c.endPeriod.text.trim();
      final w = c.weeks.text.trim();
      coursesJson.write('{');
      coursesJson.write('"name":"${_esc(n)}",');
      if (t.isNotEmpty) coursesJson.write('"teacher":"${_esc(t)}",');
      if (r.isNotEmpty) coursesJson.write('"room":"${_esc(r)}",');
      coursesJson.write('"day":$d,"startPeriod":$sp,"endPeriod":$ep');
      if (w.isNotEmpty) coursesJson.write(',"weeks":"${_esc(w)}"');
      coursesJson.write('}');
    }
    coursesJson.write(']');

    final sd =
        '${_startDate.year.toString().padLeft(4, '0')}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}';
    final json = '{'
        '"name":"${_esc(name)}",'
        '"startDate":"$sd",'
        '"totalWeeks":$_totalWeeks,'
        '"periods":$periodsJson,'
        '"courses":$coursesJson'
        '}';

    try {
      final data = TimetableData.parse(json);
      widget.state.setTimetable(data);
      _toast('已保存');
      Navigator.of(context).pop(true);
    } on TimetableFormatException catch (e) {
      _toast('保存失败：${e.message}');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  static String _esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 13)),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final compact = MediaQuery.of(context).size.width < 700;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(compact ? 12 : 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 720,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Container(
          decoration: BoxDecoration(
            // 实底不透明：编辑页有大量输入框与滚动，半透明会让下层课程表页持续参与合成
            color: c.cardSolid,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(children: [
                Icon(Icons.edit_calendar_outlined, size: 18, color: c.primary),
                const SizedBox(width: 8),
                Text('编辑课程表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                const Spacer(),
                IconButton(
                  tooltip: '查看 JSON 格式',
                  icon: Icon(Icons.help_outline_rounded, size: 18, color: c.textSecondary),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const TimetableFormatDocDialog(),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: Icon(Icons.close_rounded, size: 20, color: c.textTertiary),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ]),
            ),
            Divider(height: 1, color: c.divider),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionTitle(c, '学期信息'),
                  const SizedBox(height: 8),
                  _buildSemesterBlock(c, compact),
                  const SizedBox(height: 18),
                  _sectionTitle(c, '节次时间分布（左侧 1..${_periods.length} 节课）'),
                  const SizedBox(height: 4),
                  Text('课块显示时间完全由这张表决定，JSON 里 periods[] 与此处一一对应。',
                      style: TextStyle(fontSize: 11, color: c.textTertiary, height: 1.5)),
                  const SizedBox(height: 8),
                  _buildPeriodsTable(c, compact),
                  const SizedBox(height: 18),
                  _sectionTitle(c, '课程列表（${_courses.length} 门）'),
                  const SizedBox(height: 4),
                  Text('day 1=周一 … 7=周日；weeks 留空=每周都有，写法 "1-16" 或 "1-8,10,12-16"。',
                      style: TextStyle(fontSize: 11, color: c.textTertiary, height: 1.5)),
                  const SizedBox(height: 8),
                  _buildCoursesList(c, compact),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addCourse,
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('新增课程'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.primary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ]),
              ),
            ),
            Divider(height: 1, color: c.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('取消', style: TextStyle(color: c.textTertiary)),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('保存'),
                  style: FilledButton.styleFrom(backgroundColor: c.primary, foregroundColor: Colors.white),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _sectionTitle(AppColors c, String t) =>
      Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text));

  Widget _buildSemesterBlock(AppColors c, bool compact) {
    return Column(children: [
      Row(children: [
        Expanded(
          flex: 3,
          child: _field(
            c,
            label: '学期名',
            child: TextField(
              controller: _nameCtrl,
              style: TextStyle(fontSize: 13, color: c.text),
              decoration: _decoration(c, hint: '如：2025-2026 第1学期'),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _field(
            c,
            label: '开学日期（第 1 周周一）',
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(_startDate.year - 1, 1, 1),
                  lastDate: DateTime(_startDate.year + 2, 12, 31),
                  locale: const Locale('zh', 'CN'),
                );
                if (picked != null) setState(() => _startDate = picked);
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                decoration: BoxDecoration(
                  color: c.inputFill,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_rounded, size: 14, color: c.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                      '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}'
                      '（周${['一', '二', '三', '四', '五', '六', '日'][_startDate.weekday - 1]}）',
                      style: TextStyle(fontSize: 13, color: c.text)),
                  const Spacer(),
                  Icon(Icons.arrow_drop_down_rounded, size: 18, color: c.textTertiary),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: _field(
            c,
            label: '总周数',
            child: TextField(
              controller: TextEditingController(text: '$_totalWeeks')
                ..selection = TextSelection.collapsed(offset: '$_totalWeeks'.length),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => _totalWeeks = int.tryParse(v) ?? _totalWeeks,
              style: TextStyle(fontSize: 13, color: c.text),
              decoration: _decoration(c, hint: '20'),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _field(AppColors c, {required String label, required Widget child}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w500)),
      const SizedBox(height: 4),
      child,
    ]);
  }

  InputDecoration _decoration(AppColors c, {String? hint}) => InputDecoration(
        filled: true,
        fillColor: c.inputFill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: c.textTertiary.withValues(alpha: 0.7)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.primary, width: 1.4)),
      );

  Widget _buildPeriodsTable(AppColors c, bool compact) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        for (var i = 0; i < _periods.length; i++) _periodRow(c, i, compact),
        InkWell(
          onTap: _addPeriod,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_rounded, size: 14, color: c.primary),
              const SizedBox(width: 4),
              Text('添加节次', style: TextStyle(fontSize: 12, color: c.primary, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _periodRow(AppColors c, int i, bool compact) {
    final p = _periods[i];
    return Container(
      decoration: BoxDecoration(
          border: i < _periods.length - 1 ? Border(bottom: BorderSide(color: c.divider, width: 0.6)) : null),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(children: [
        SizedBox(
          width: 40,
          child: TextField(
            controller: p.index,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(fontSize: 12.5, color: c.text, fontWeight: FontWeight.w600),
            decoration: _decoration(c).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
          ),
        ),
        const SizedBox(width: 6),
        const Text('节', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: p.start,
            style: TextStyle(fontSize: 12.5, color: c.text),
            decoration: _decoration(c, hint: '08:00')
                .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('~', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))),
        Expanded(
          child: TextField(
            controller: p.end,
            style: TextStyle(fontSize: 12.5, color: c.text),
            decoration: _decoration(c, hint: '08:45')
                .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          ),
        ),
        IconButton(
          tooltip: '删除',
          onPressed: _periods.length > 1 ? () => _removePeriod(i) : null,
          icon: Icon(Icons.close_rounded,
              size: 15, color: _periods.length > 1 ? c.textTertiary : c.textTertiary.withValues(alpha: 0.3)),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ]),
    );
  }

  Widget _buildCoursesList(AppColors c, bool compact) {
    if (_courses.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(border: Border.all(color: c.border), borderRadius: BorderRadius.circular(8)),
        child: Text('暂无课程，点下方"新增课程"添加。', style: TextStyle(fontSize: 12, color: c.textTertiary)),
      );
    }
    return Column(children: [
      for (var i = 0; i < _courses.length; i++) _courseRow(c, i, compact),
    ]);
  }

  Widget _courseRow(AppColors c, int i, bool compact) {
    final cRow = _courses[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.inputFill,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 8,
            height: 22,
            decoration: BoxDecoration(
              color: Color(_paletteColor(cRow.colorIndex)),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: cRow.name,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
              decoration: _decoration(c, hint: '课程名')
                  .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '删除',
            onPressed: () => _removeCourse(i),
            icon: Icon(Icons.delete_outline_rounded, size: 16, color: c.textTertiary),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextField(
              controller: cRow.teacher,
              style: TextStyle(fontSize: 12, color: c.text),
              decoration: _decoration(c, hint: '教师（可选）')
                  .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: cRow.room,
              style: TextStyle(fontSize: 12, color: c.text),
              decoration: _decoration(c, hint: '地点（可选）')
                  .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          SizedBox(
            width: 52,
            child: TextField(
              controller: cRow.day,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(fontSize: 12, color: c.text),
              decoration: _decoration(c, hint: '1-7')
                  .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
            ),
          ),
          const SizedBox(width: 4),
          Text('日', style: TextStyle(fontSize: 11, color: c.textTertiary)),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: TextField(
              controller: cRow.startPeriod,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(fontSize: 12, color: c.text),
              decoration: _decoration(c).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: Text('~', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))),
          SizedBox(
            width: 40,
            child: TextField(
              controller: cRow.endPeriod,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: TextStyle(fontSize: 12, color: c.text),
              decoration: _decoration(c).copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
            ),
          ),
          const SizedBox(width: 4),
          Text('节', style: TextStyle(fontSize: 11, color: c.textTertiary)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: cRow.weeks,
              style: TextStyle(fontSize: 12, color: c.text),
              decoration: _decoration(c, hint: '1-16（可留空）')
                  .copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            ),
          ),
        ]),
      ]),
    );
  }

  static const List<int> _palette = [
    0xFF5B6BD6, 0xFF8B5CD6, 0xFF1E9E6E, 0xFFD9862B, 0xFFD65B8A, 0xFF2B8FB8,
  ];
  int _paletteColor(int i) => _palette[i % _palette.length];
}

class _PeriodRow {
  final TextEditingController index;
  final TextEditingController start;
  final TextEditingController end;
  _PeriodRow({required this.index, required this.start, required this.end});
}

class _CourseRow {
  final TextEditingController name;
  final TextEditingController teacher;
  final TextEditingController room;
  final TextEditingController day;
  final TextEditingController startPeriod;
  final TextEditingController endPeriod;
  final TextEditingController weeks;
  final int colorIndex;
  _CourseRow({
    required this.name,
    required this.teacher,
    required this.room,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    required this.colorIndex,
  });
}
