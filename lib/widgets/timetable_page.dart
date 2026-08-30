/// 课程表模式（参考超级课程表 UI）：周视图网格 + JSON 导入
///
/// - 课程块的显示时间完全由导入 JSON 的 `periods`（一天的节次时间分布）决定，非固定
/// - 周次由 `startDate`（第 1 周周一）推算，可切换查看任意周，支持"切回本周"
/// - 独立模式：与英语学习模式通过顶部导航胶囊互相切换
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state.dart';
import '../theme_colors.dart' show AppColors;
import '../timetable_models.dart';
import 'timetable_settings_dialog.dart';
import 'timetable_format_doc.dart';
import 'edit_timetable_dialog.dart';

/// 课程块调色板：(主色, 浅色底) —— 经典浅色主题下参考超级课程表的马卡龙色块；
/// 深色模式自动派生：底 = 主色半透明，文字 = 主色提亮
const List<(Color, Color)> _kCoursePalette = [
  (Color(0xFF5B6BD6), Color(0xFFE3E8FC)), // 蓝
  (Color(0xFF8B5CD6), Color(0xFFEFE6FC)), // 紫
  (Color(0xFF1E9E6E), Color(0xFFDEF4EA)), // 绿
  (Color(0xFFD9862B), Color(0xFFFCEFE0)), // 橙
  (Color(0xFFD65B8A), Color(0xFFFBE4EE)), // 粉
  (Color(0xFF2B8FB8), Color(0xFFE0F2FA)), // 青
];

class TimetablePage extends StatefulWidget {
  final AppState state;
  const TimetablePage({super.key, required this.state});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  late int _week;
  bool _importing = false;

  /// 跟随系统周次：进入页面自动跳到当前周；用户手动切换周次后停止跟随，
  /// 点"切回本周"恢复跟随（定时器跨周/跨天时自动跳回）
  bool _followSystem = true;

  /// 每 30 秒刷新：当前上课节次/下一节课高亮、"今天"列与表头、跨天跨周跟随
  Timer? _ticker;

  /// 上次调度课程提醒的日期：跨天后需重新调度（通知是按"当天具体时刻"调度的）
  DateTime? _lastReminderDay;

  AppState get s => widget.state;
  TimetableData? get _data => s.timetable;
  bool get _dark => s.darkMode;

  @override
  void initState() {
    super.initState();
    final d = _data;
    _week = d == null ? 1 : d.weekOf(DateTime.now());
    // 定时刷新：30s 粒度足够响应"上课中/下一节"状态切换
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _onTick());
    // 打开课程表页时（重新）调度今天的系统通知提醒。
    // 调度动作只在 App 前台发生，之后由操作系统在指定时刻弹出（App 后台/被杀也能弹）
    if (d != null) unawaited(s.scheduleClassReminders());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 系统时间联动：跨天更新"今天"标记；若在跟随状态且系统周次已变化（跨周），自动跳转
  void _onTick() {
    if (!mounted) return;
    final d = _data;
    if (d == null) return;
    final sysWeek = d.weekOf(_today);
    if (_followSystem && _week != sysWeek) {
      setState(() => _week = sysWeek);
      // 跨周（必然已跨天）→ 重新调度课程提醒
      unawaited(s.scheduleClassReminders());
    } else {
      // 刷新"今天"列高亮 / 当前节次标记
      setState(() {});
    }
    // 跨天但同周（周一→周二…）也要重调度：通知按"当天具体时刻"调度，
    // 昨天调度的时刻在今天已失效，必须按今天课表重新下发
    final today = _today;
    if (_lastReminderDay == null) {
      _lastReminderDay = today;
    } else if (_lastReminderDay != today) {
      _lastReminderDay = today;
      unawaited(s.scheduleClassReminders());
    }
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// "HH:mm" → 当天分钟数
  static int _hm(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  // ===== 顶栏 =====
  Widget _buildHeader(AppColors c) {
    final d = _data;
    final isCurrentWeek = d != null && _week == d.weekOf(_today);
    // 手机端紧凑布局：收窄内边距、缩小周次字号、"切回本周"图标化
    final compact = MediaQuery.of(context).size.width < 700;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 10 : 20, compact ? 10 : 14, compact ? 6 : 20, 0),
      child: Row(children: [
        // 学期名（如有）+ 周次选择（仅在已导入时显示）
        if (d != null) ...[
          // 第 X 周 下拉选择
          PopupMenuButton<int>(
            initialValue: _week,
            onSelected: (w) => setState(() {
              _week = w;
              _followSystem = false; // 用户手动选择周次 → 停止自动跟随
            }),
            color: _dark ? c.card : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border)),
            itemBuilder: (ctx) => [
              for (var w = 1; w <= d.totalWeeks; w++)
                PopupMenuItem(
                  value: w,
                  height: 38,
                  child: Text('第 $w 周${w == d.weekOf(_today) ? '（本周）' : ''}',
                      style: TextStyle(fontSize: 13, color: w == _week ? c.primary : c.text)),
                ),
            ],
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 5 : 6),
              decoration: BoxDecoration(color: c.inputFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('第$_week周',
                    style: TextStyle(
                        fontSize: compact ? 14.5 : 17,
                        fontWeight: FontWeight.w700,
                        color: c.primary,
                        fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, size: compact ? 16 : 18, color: c.primary),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(d.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
          ),
          // 编辑按钮：直接打开课程表编辑对话框（学期名/日期/节次/课程全部可改）
          IconButton(
            tooltip: '编辑课程表',
            icon: Icon(Icons.edit_outlined, size: 18, color: c.textSecondary),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditTimetableDialog(state: s),
            ),
          ),
        ],
        const Spacer(),
        if (d != null && !isCurrentWeek)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: compact
                ? IconButton(
                    onPressed: () => setState(() {
                      _week = d.weekOf(_today);
                      _followSystem = true; // 回到系统周次 → 恢复自动跟随
                    }),
                    icon: const Icon(Icons.today_outlined, size: 18, color: Color(0xFFE8724A)),
                    tooltip: '切回本周',
                  )
                : TextButton.icon(
                    onPressed: () => setState(() {
                      _week = d.weekOf(_today);
                      _followSystem = true;
                    }),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: const Color(0xFFE8724A),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    label: const Text('切回本周', style: TextStyle(fontSize: 12.5)),
                  ),
          ),
        // 右上角：+ 号菜单（导入 / 导出 / 格式说明）
        _iconMenuButton(
          c,
          icon: Icons.add_rounded,
          tooltip: '导入 / 导出',
          items: [
            PopupMenuItem(
              value: 'import',
              child: Row(children: [
                Icon(Icons.upload_file_outlined, size: 16, color: c.textSecondary),
                const SizedBox(width: 8),
                Text(d == null ? '导入课表' : '重新导入课表', style: TextStyle(fontSize: 13, color: c.text)),
              ]),
            ),
            if (d != null)
              PopupMenuItem(
                value: 'export',
                child: Row(children: [
                  Icon(Icons.save_alt_outlined, size: 16, color: c.textSecondary),
                  const SizedBox(width: 8),
                  const Text('导出课表', style: TextStyle(fontSize: 13)),
                ]),
              ),
            PopupMenuItem(
              value: 'format',
              child: Row(children: [
                Icon(Icons.description_outlined, size: 16, color: c.textSecondary),
                const SizedBox(width: 8),
                const Text('查看 JSON 格式', style: TextStyle(fontSize: 13)),
              ]),
            ),
          ],
          onSelected: (v) {
            switch (v) {
              case 'import':
                _importJson();
                break;
              case 'export':
                _exportJson();
                break;
              case 'format':
                _showFormatHelp(c);
                break;
            }
          },
        ),
        const SizedBox(width: 6),
        // 右上角：三点按钮直接打开独立设置（不再弹 PopupMenu 中转，用户反馈点击直达更顺手）
        IconButton(
          tooltip: '设置',
          icon: Icon(Icons.more_horiz_rounded, size: 22, color: c.textSecondary),
          onPressed: () => showDialog(
            context: context,
            builder: (ctx) => TimetableSettingsDialog(state: s),
          ),
        ),
      ]),
    );
  }

  Widget _iconMenuButton(AppColors c, {
    required IconData icon,
    required String tooltip,
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      icon: Icon(icon, size: 22, color: c.textSecondary),
      color: _dark ? c.card : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border)),
      position: PopupMenuPosition.under,
      itemBuilder: (_) => items,
      onSelected: onSelected,
    );
  }

  // ===== 星期表头 =====
  Widget _buildDayHeader(AppColors c, double colW, double timeColW) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final d = _data!;
    final month = d.dateOf(_week, 1).month;
    return SizedBox(
      width: timeColW + colW * 7,
      child: Row(children: [
        SizedBox(
          width: timeColW,
          child: Center(
            child: Text('$month月',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
        for (var day = 1; day <= 7; day++)
          SizedBox(
            width: colW,
            child: Builder(builder: (ctx) {
              final isToday = d.dateOf(_week, day) == _today;
              return Column(children: [
                Text(labels[day - 1],
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isToday ? c.primary : c.textSecondary)),
                const SizedBox(height: 2),
                Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                  Text('${d.dateOf(_week, day).day}',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                          color: isToday ? c.primary : c.text,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  if (isToday)
                    Positioned(
                      bottom: -6,
                      child: Container(width: 18, height: 3, decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(2))),
                    ),
                ]),
                const SizedBox(height: 8),
              ]);
            }),
          ),
      ]),
    );
  }

  // ===== 时间轴列（固定 1..rows 节序号；时间按 JSON periods 显示，未定义则留空） =====
  Widget _buildTimeColumn(AppColors c, double rowH, double timeColW, int rows) {
    final d = _data!;
    final curIdx = _currentPeriodIndex(d, DateTime.now());
    return SizedBox(
      width: timeColW,
      child: Column(children: [
        for (var i = 1; i <= rows; i++)
          Builder(builder: (ctx) {
            final p = d.periodAt(i);
            final isNow = p != null && p.index == curIdx;
            return SizedBox(
              height: rowH,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  // 当前节次：绿点标记
                  if (isNow) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: Color(0xFF1E9E56), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 3),
                  ],
                  Text('$i',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: isNow ? FontWeight.w800 : FontWeight.w600,
                          color: isNow ? const Color(0xFF1E9E56) : c.text,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
                if (p != null) ...[
                  const SizedBox(height: 3),
                  Text(p.start, style: TextStyle(fontSize: 9, color: c.textTertiary, height: 1.15, fontFeatures: const [FontFeature.tabularFigures()])),
                  Text(p.end, style: TextStyle(fontSize: 9, color: c.textTertiary, height: 1.15, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ]),
            );
          }),
      ]),
    );
  }

  /// 当前时间落在哪个节次区间内（[start, end)）；不在任何区间返回 null
  static int? _currentPeriodIndex(TimetableData d, DateTime now) {
    final hm = now.hour * 60 + now.minute;
    for (final p in d.periods) {
      if (hm >= _hm(p.start) && hm < _hm(p.end)) return p.index;
    }
    return null;
  }

  /// 单日课程时间状态：今天列中"第一门还没结束的课"为 上课中(绿)/下一节(红)，其余无标记
  _CourseStatus _statusOf(TimetableCourse course, TimetableCourse? upcoming, int hm, TimetableData d) {
    if (upcoming == null || !identical(upcoming, course)) return _CourseStatus.none;
    final sp = d.periodAt(course.startPeriod);
    if (sp == null) return _CourseStatus.none;
    return hm >= _hm(sp.start) ? _CourseStatus.current : _CourseStatus.next;
  }

  // ===== 单日列：背景节次槽 + 跨节次课程块 =====
  Widget _buildDayColumn(AppColors c, int day, double colW, double rowH, int rows) {
    final d = _data!;
    final courses = d.coursesFor(day, _week);
    // 时间状态：仅"今天"列参与高亮。第一门还没结束的课 = 上课中(绿) 或 下一节(红)
    final now = DateTime.now();
    final hm = now.hour * 60 + now.minute;
    final isTodayCol = d.dateOf(_week, day) == _today;
    TimetableCourse? upcoming;
    if (isTodayCol) {
      for (final c in courses) {
        final ep = d.periodAt(c.endPeriod);
        if (ep != null && hm < _hm(ep.end)) {
          upcoming = c;
          break;
        }
      }
    }
    // 简单车道分配：同一天内节次重叠的课程横向分列，宽度均分
    final lanes = <List<TimetableCourse>>[];
    for (final c in courses) {
      var placed = false;
      for (final lane in lanes) {
        if (lane.every((o) => c.endPeriod < o.startPeriod || c.startPeriod > o.endPeriod)) {
          lane.add(c);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.add([c]);
    }
    final laneCount = lanes.isEmpty ? 1 : lanes.length;
    final laneOf = <TimetableCourse, int>{};
    for (var i = 0; i < lanes.length; i++) {
      for (final c in lanes[i]) {
        laneOf[c] = i;
      }
    }

    return SizedBox(
      width: colW,
      child: Stack(children: [
        // 背景节次槽 + 分隔线（固定 rows 行，与时间轴一一对应）
        Column(children: [
          for (var i = 0; i < rows; i++)
            Container(
              height: rowH,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.divider, width: 0.8))),
            ),
        ]),
        // 今日列底色已移除——之前给今天列加 primary 淡底色，与未定义节次白色槽对比明显
        // 且有课块时底色透到课块下方也违和。改为仅靠表头下划线 + 周次选择器"本周"标记。
        // 课程块：节次序号直接映射为行槽（1 节 = 第 1 行），超出 rows 的夹边
        for (final course in courses)
          Positioned(
            top: (course.startPeriod.clamp(1, rows) - 1) * rowH + 1.5,
            height: ((course.endPeriod.clamp(1, rows) - course.startPeriod.clamp(1, rows)) + 1) * rowH - 3,
            left: 1.5 + (colW - 3) * laneOf[course]! / laneCount,
            width: (colW - 3) / laneCount - 1.5,
            child: _CourseBlock(
              course: course,
              data: d,
              dark: _dark,
              highlight: _statusOf(course, upcoming, hm, d),
              onTap: () => _showCourseDetail(c, course),
            ),
          ),
      ]),
    );
  }

  // ===== 网格主体 =====
  /// 表头与正文共用同一个 SizedBox(width: gridW) 容器——二者列宽/起点完全一致（修复错位）。
  /// 左侧固定显示 1..20 节序号（JSON 定义了时间就显示，没定义就只显示数字）。
  Widget _buildGrid(AppColors c) {
    final d = _data!;
    final compact = MediaQuery.of(context).size.width < 700;
    final rowH = compact ? 62.0 : 88.0;
    final timeColW = compact ? 40.0 : _kTimeColW;
    final minColW = compact ? 46.0 : 72.0;
    final maxColW = compact ? 110.0 : 150.0;
    // 行数 = max(20, JSON 最大节次)：默认固定 20 节，JSON 超出时跟随
    final rows = d.maxPeriodIndex > _kMaxPeriodRows ? d.maxPeriodIndex : _kMaxPeriodRows;

    return Expanded(
      child: LayoutBuilder(builder: (context, box) {
        final availW = box.maxWidth;
        final fitCols = (availW - timeColW) / 7;
        final colW = fitCols.clamp(minColW, maxColW);
        final gridW = timeColW + colW * 7;
        final needHScroll = gridW > availW + 0.5;

        // 表头 + 正文同宽同源，彻底对齐
        Widget inner = SizedBox(
          width: gridW,
          child: Column(children: [
            _buildDayHeader(c, colW, timeColW),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                child: SizedBox(
                  height: rows * rowH,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _buildTimeColumn(c, rowH, timeColW, rows),
                    for (var day = 1; day <= 7; day++) _buildDayColumn(c, day, colW, rowH, rows),
                  ]),
                ),
              ),
            ),
          ]),
        );

        // 窄屏横向滚动；无论是否滚动都顶左对齐（避免 Column 默认居中造成表头/正文错位）
        if (needHScroll) {
          inner = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: inner,
          );
        }
        return Align(alignment: Alignment.topLeft, child: inner);
      }),
    );
  }

  // ===== 空状态（未导入） =====
  Widget _buildEmpty(AppColors c) {
    return Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.calendar_month_rounded, size: 44, color: c.primary.withValues(alpha: 0.7)),
              const SizedBox(height: 14),
              Text('还没有课程表', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 8),
              Text('导入 JSON 文件即可开始使用。课程时间由文件中的\n"periods"（一天节次时间分布）决定，支持任意作息安排。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textTertiary, height: 1.6)),
              const SizedBox(height: 20),
              Row(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  onPressed: _importing ? null : _importJson,
                  icon: const Icon(Icons.upload_file_outlined, size: 17),
                  label: Text(_importing ? '导入中…' : '选择 JSON 文件'),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _showFormatHelp(c),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('查看格式与示例'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textSecondary,
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ===== 导入 =====
  Future<void> _importJson() async {
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      String raw;
      final f = result.files.single;
      if (f.bytes != null && f.bytes!.isNotEmpty) {
        raw = utf8.decode(f.bytes!, allowMalformed: true);
      } else if (f.path != null) {
        raw = utf8.decode(await File(f.path!).readAsBytes(), allowMalformed: true);
      } else {
        throw const TimetableFormatException('无法读取所选文件');
      }
      final data = TimetableData.parse(raw);
      if (!mounted) return;
      setState(() {
        s.setTimetable(data);
        _week = data.weekOf(_today);
      });
    } on TimetableFormatException catch (e) {
      if (!mounted) return;
      _showImportError(e.message);
    } catch (e) {
      if (!mounted) return;
      _showImportError('导入失败：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ===== 导出 =====
  Future<void> _exportJson() async {
    final d = _data;
    if (d == null) return;
    final c = AppColors.of(context);
    try {
      final suggested = '${d.name.replaceAll(RegExp(r'\s+'), '_')}.json';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出课表',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null) return;
      // 缩进 2 便于人工查阅
      final raw = const JsonEncoder.withIndent('  ').convert(d.toJson());
      await File(path).writeAsString(raw, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('已导出到：$path', style: TextStyle(fontSize: 13, color: c.text)),
        backgroundColor: c.card,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
      ));
    } catch (e) {
      if (!mounted) return;
      _showImportError('导出失败：$e');
    }
  }

  void _showImportError(String message) {
    final c = AppColors.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dark ? c.card : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
        title: Row(children: [
          Icon(Icons.error_outline_rounded, size: 20, color: c.scoreLow),
          const SizedBox(width: 8),
          Text('导入失败', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
        ]),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(message, style: TextStyle(fontSize: 13, color: c.text, height: 1.6)),
            const SizedBox(height: 10),
            Text('可点击"格式说明"查看 JSON 模板。', style: TextStyle(fontSize: 12, color: c.textTertiary)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('知道了', style: TextStyle(color: c.primary))),
        ],
      ),
    );
  }

  // ===== 格式说明 =====（弹窗已抽到 timetable_format_doc.dart，可被 EditTimetableDialog 等复用）
  void _showFormatHelp(AppColors c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => const TimetableFormatDocDialog(),
    );
  }

  // ===== 课程详情 =====
  void _showCourseDetail(AppColors c, TimetableCourse course) {
    final d = _data!;
    final sp = d.periodAt(course.startPeriod);
    final ep = d.periodAt(course.endPeriod);
    final time = sp != null && ep != null ? '${sp.start} ~ ${ep.end}' : '（节次时间未定义）';
    final weeksText = course.weeks == null
        ? '每周'
        : '第 ${TimetableData.weeksToSpec(course.weeks!)} 周';
    final dayLabel = '周${['一', '二', '三', '四', '五', '六', '日'][course.day - 1]}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _dark ? c.card : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
        title: Text(course.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _detailRow(c, '时间', '$dayLabel · $time'),
            _detailRow(c, '节次', '${course.startPeriod} ~ ${course.endPeriod} 节'),
            if (course.room.isNotEmpty) _detailRow(c, '地点', course.room),
            if (course.teacher.isNotEmpty) _detailRow(c, '教师', course.teacher),
            _detailRow(c, '周次', weeksText),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('关闭', style: TextStyle(color: c.primary))),
        ],
      ),
    );
  }

  Widget _detailRow(AppColors c, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 40, child: Text(label, style: TextStyle(fontSize: 12.5, color: c.textTertiary))),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: c.text, height: 1.5))),
      ]),
    );
  }

  static const double _kTimeColW = 56;

  /// 网格默认固定行数：左侧始终显示 1..20 节序号（超级课程表风格），
  /// 时间文字仅当 JSON periods 定义了该节才显示；JSON 超过 20 节时行数跟随
  static const int _kMaxPeriodRows = 20;

  late final ScrollController _scrollCtrl = ScrollController();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final d = _data;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        // 撑满宽度：避免桌面端 _buildGrid 内部 LayoutBuilder 拿到松约束导致列宽按子 intrinsic
        // 算、gridW 居中后两侧大块空白（截图红色箭头所指）
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        _buildHeader(c),
        const SizedBox(height: 10),
        if (d == null)
          _buildEmpty(c)
        else ...[
          Divider(height: 1, color: c.divider),
          // _buildGrid 内部自含 Expanded + LayoutBuilder（真实剩余宽度定列宽）
          _buildGrid(c),
        ],
      ]),
    );
  }
}

/// 课程块时间状态：无标记 / 上课中（绿）/ 下一节（红）
enum _CourseStatus { none, current, next }

/// 课程块：浅色马卡龙底 + 主色文字（深色模式自动派生半透明底 + 提亮文字）；
/// highlight 非 none 时整块切换为 绿（上课中）/ 红（下一节） 信号色
class _CourseBlock extends StatelessWidget {
  final TimetableCourse course;
  final TimetableData data;
  final bool dark;
  final _CourseStatus highlight;
  final VoidCallback onTap;
  const _CourseBlock({
    required this.course,
    required this.data,
    required this.dark,
    required this.onTap,
    this.highlight = _CourseStatus.none,
  });

  @override
  Widget build(BuildContext context) {
    final (main, soft) = _kCoursePalette[course.colorIndex % _kCoursePalette.length];
    final isCurrent = highlight == _CourseStatus.current;
    final isNext = highlight == _CourseStatus.next;
    // 信号色：上课中=绿 / 下一节=红
    final Color hc = isCurrent ? const Color(0xFF1E9E56) : const Color(0xFFE5484D);
    final bg = isCurrent || isNext
        ? (dark ? hc.withValues(alpha: 0.28) : hc.withValues(alpha: 0.12))
        : (dark ? main.withValues(alpha: 0.24) : soft);
    final fg = isCurrent || isNext
        ? (dark ? Color.lerp(hc, Colors.white, 0.55)! : hc)
        : (dark ? Color.lerp(main, Colors.white, 0.62)! : main);
    final borderCol = isCurrent || isNext ? hc : fg.withValues(alpha: 0.55);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderCol.withValues(alpha: 0.55), width: 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 时间状态标记：上课中 / 下一节
            if (isCurrent || isNext)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: hc, shape: BoxShape.circle)),
                  const SizedBox(width: 3),
                  Text(isCurrent ? '上课中' : '下一节',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: hc, height: 1)),
                ]),
              ),
            Text(course.name,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg, height: 1.35)),
            if (course.room.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(course.room,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.85), height: 1.3)),
              ),
          ]),
        ),
      ),
    );
  }
}
