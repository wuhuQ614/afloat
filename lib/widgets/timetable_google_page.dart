/// 课程表模式 v2 —— Google Calendar 风格（按设计稿 1:1 复刻）
///
/// 设计语言与项目主色（紫）无关：本页自带一套 Google 配色（蓝 #1A73E8 /
/// 中性灰 #202124 #5F6368 #80868B / 分隔线 #E8EAED），深浅色两套变体。
///
/// 布局：
/// - 宽屏（>= 860）三栏：左导航栏 + 顶栏/副头 + 周（日/月）视图网格
/// - 窄屏：顶栏 + 日期条 + 单日时间轴 + FAB + 底部标签栏
///
/// 数据仍复用 [TimetableData]（JSON 导入的节次 + 课程），本页只改呈现与交互：
/// 课程起止时间由 periods 换算成分钟轴定位，分钟轴范围由数据实际跨度推导。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state.dart';
import '../timetable_models.dart';
import 'edit_timetable_dialog.dart';
import 'timetable_format_doc.dart';
import 'timetable_settings_dialog.dart';

// ============================================================
// 配色
// ============================================================

/// 页面配色（Google 风格）。深色变体只改底色与文字，主色蓝转为浅蓝以保证对比度。
class _G {
  final bool dark;
  const _G(this.dark);

  Color get pageBg => dark ? const Color(0xFF1B1B1F) : const Color(0xFFF6F8FC);
  Color get surface => dark ? const Color(0xFF232329) : Colors.white;
  Color get surfaceAlt => dark ? const Color(0xFF1F1F24) : Colors.white;
  Color get track => dark ? const Color(0xFF2C2C33) : const Color(0xFFF1F3F4);
  Color get hover => dark ? const Color(0xFF2E2E36) : const Color(0xFFF1F3F4);

  Color get text => dark ? const Color(0xFFE8EAED) : const Color(0xFF202124);
  Color get text2 => dark ? const Color(0xFFB0B3B8) : const Color(0xFF5F6368);
  Color get text3 => dark ? const Color(0xFF8A8D93) : const Color(0xFF80868B);

  Color get line => dark ? const Color(0xFF34343C) : const Color(0xFFE8EAED);
  Color get lineStrong => dark ? const Color(0xFF40404A) : const Color(0xFFDADCE0);

  /// 主色：Google 蓝（取自设计稿 FAB / 选中标签实测值 #3D79F5）
  Color get blue => dark ? const Color(0xFF8AB4F8) : const Color(0xFF3D79F5);
  Color get blueSoft => dark ? const Color(0xFF1F3A5F) : const Color(0xFFE8F0FE);
  Color get onBlue => dark ? const Color(0xFF12203A) : Colors.white;

  Color get shadow => dark ? const Color(0x4D000000) : const Color(0x14000000);
  Color get shadowSoft => dark ? const Color(0x33000000) : const Color(0x0F000000);

  /// 图例圆点用色
  Color get dotGreen => dark ? const Color(0xFF81C995) : const Color(0xFF34A853);
  Color get dotAmber => dark ? const Color(0xFFFDD663) : const Color(0xFFFBBC04);
  Color get dotPurple => dark ? const Color(0xFFC58AF9) : const Color(0xFFA142F4);

  /// 危险操作用色（清除课表），Google 红
  Color get red => dark ? const Color(0xFFF28B82) : const Color(0xFFD93025);
}

/// 课程调色板三元组：浅底 / 圆点与色条 / 文字
class _EvColor {
  final Color fill;
  final Color accent;
  final Color ink;
  const _EvColor(this.fill, this.accent, this.ink);

  /// 深色模式派生：底 = 强调色低透明，文字 = 强调色向白提亮
  _EvColor darkVariant() => _EvColor(
        accent.withValues(alpha: 0.16),
        accent,
        Color.lerp(accent, Colors.white, 0.60)!,
      );
}

/// 课程调色板。前五组（蓝/薄荷/薰衣草/杏/粉）的填充与文字色**直接从设计稿取样**：
/// 填充离白的距离只有 40~45/255（此前用的 #D3E3FD 是 74，饱和过头显廉价）；
/// 文字色取卡内最暗像素均值（#2C49B9 / #1D683E / #5348B7 / #A36931 / #9B515A）。
/// 后五组按同一明度推导，保证整套观感一致。
const List<_EvColor> _kEventPalette = [
  _EvColor(Color(0xFFE5F0FE), Color(0xFF4285F5), Color(0xFF3358BE)), // 蓝
  _EvColor(Color(0xFFDCF6F0), Color(0xFF2BA88C), Color(0xFF1F7A50)), // 薄荷
  _EvColor(Color(0xFFECEAFD), Color(0xFF7C6FD8), Color(0xFF5B50BC)), // 薰衣草
  _EvColor(Color(0xFFFDF0DB), Color(0xFFE8A04C), Color(0xFFA56A28)), // 杏
  _EvColor(Color(0xFFFDE6EA), Color(0xFFE07C8C), Color(0xFFA05560)), // 粉
  _EvColor(Color(0xFFE1F3F8), Color(0xFF38A3C6), Color(0xFF1F6E88)), // 青
  _EvColor(Color(0xFFEBF2DD), Color(0xFF86AB4A), Color(0xFF5A7330)), // 苔绿
  _EvColor(Color(0xFFE6EDF7), Color(0xFF6F8EC7), Color(0xFF465E8C)), // 石板
  _EvColor(Color(0xFFFDEAE3), Color(0xFFE28468), Color(0xFFA05238)), // 珊瑚
  _EvColor(Color(0xFFEFEAF6), Color(0xFF9B8CC0), Color(0xFF6B5D92)), // 灰紫
];

// ============================================================
// 时间工具
// ============================================================

/// "HH:mm" → 当天分钟数
int _toMin(String t) {
  final p = t.split(':');
  if (p.length < 2) return 0;
  final h = int.tryParse(p[0]) ?? 0;
  final m = int.tryParse(p[1]) ?? 0;
  return h * 60 + m;
}

String _fmtMin(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

const List<String> _kWeekdayCn = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// 视图粒度
enum _CalView { day, week, month }

// ============================================================
// 页面
// ============================================================

class TimetableGooglePage extends StatefulWidget {
  final AppState state;
  const TimetableGooglePage({super.key, required this.state});

  @override
  State<TimetableGooglePage> createState() => _TimetableGooglePageState();
}

class _TimetableGooglePageState extends State<TimetableGooglePage>
    with TickerProviderStateMixin {
  AppState get s => widget.state;
  TimetableData? get _data => s.timetable;
  bool get _dark => s.darkMode;
  _G get g => _G(_dark);

  static const double _hourH = 56; // 桌面每小时高度
  static const double _hourHMobile = 66; // 窄屏每小时高度
  static const double _gutterW = 62; // 左侧时间轴宽度
  static const double _padTop = 14; // 网格顶部留白（避免 08:00 标签被裁）

  _CalView _view = _CalView.week;
  int _navIndex = 0; // 0 课程表 1 任务 2 笔记 3 设置
  DateTime _cursor = DateTime.now();
  bool _followSystem = true; // 跟随系统时间自动跳到今天
  bool _promoOpen = true; // 左栏推广卡
  String _query = '';

  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  Timer? _ticker;
  DateTime? _lastReminderDay;

  /// 课块入场动画：一次性播放，按索引错峰淡入 + 上浮（复刻设计稿的轻量动效）
  late final AnimationController _intro;

  /// 设置面板抽拉动画（0 = 收起，1 = 完全展开）
  late final AnimationController _drawerAnim;

  @override
  void initState() {
    super.initState();
    final d = _data;
    _cursor = _today;
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 620))
      ..forward();
    _drawerAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    if (d != null) unawaited(s.scheduleClassReminders());
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _onTick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _intro.dispose();
    _drawerAnim.dispose();
    super.dispose();
  }

  void _openDrawer() => _drawerAnim.forward();

  void _closeDrawer() => _drawerAnim.reverse();

  /// 触发一次入场动画（切视图 / 换周 / 切日时重放，让内容切换有过渡感）
  void _replayIntro() {
    if (_intro.isAnimating) _intro.stop();
    _intro.forward(from: 0);
  }

  /// 第 [i] 个课块在当前动画帧的进度（0~1），错峰 60ms、单块 420ms
  double _stagger(int i) {
    final v = _intro.value;
    final t = ((v - i * 0.055) / 0.42).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  /// 30 秒粒度：刷新"正在进行"指示线；跟随状态下跨天自动跳回今天（并重排提醒）
  void _onTick() {
    if (!mounted) return;
    final today = _today;
    if (_followSystem && today != _cursorDay) {
      setState(() => _cursor = today);
    } else {
      setState(() {});
    }
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

  DateTime get _cursorDay => DateTime(_cursor.year, _cursor.month, _cursor.day);

  /// 视图锚点所在周的周一
  DateTime get _weekStart {
    final c = _cursorDay;
    return c.subtract(Duration(days: c.weekday - 1));
  }

  /// 当前显示周期的标题（复刻设计稿的 "August 2025"）
  String get _periodLabel {
    final c = _cursorDay;
    if (_view == _CalView.day) {
      return '${c.year}年${c.month}月${c.day}日 ${_kWeekdayCn[c.weekday - 1]}';
    }
    return '${c.year}年${c.month}月';
  }

  /// 显示的周次（仅周视图；无数据返回 null）
  int? get _weekNo {
    final d = _data;
    if (d == null) return null;
    return d.weekOf(_weekStart);
  }

  /// 是否正在看本周 / 今天
  bool get _isCurrent {
    if (_view == _CalView.month) {
      final n = _today;
      return _cursor.year == n.year && _cursor.month == n.month;
    }
    if (_view == _CalView.day) return _cursorDay == _today;
    return _weekStart == _today.subtract(Duration(days: _today.weekday - 1));
  }

  // ---------- 导航 ----------

  void _shift(int dir) {
    setState(() {
      _followSystem = false;
      switch (_view) {
        case _CalView.day:
          _cursor = _cursorDay.add(Duration(days: dir));
          break;
        case _CalView.week:
          _cursor = _cursorDay.add(Duration(days: 7 * dir));
          break;
        case _CalView.month:
          _cursor = DateTime(_cursor.year, _cursor.month + dir, 1);
          break;
      }
    });
    _replayIntro();
  }

  void _goToday() {
    setState(() {
      _cursor = _today;
      _followSystem = true;
    });
    _replayIntro();
  }

  void _setView(_CalView v) {
    if (_view == v) return;
    setState(() => _view = v);
    _replayIntro();
  }

  // ---------- 数据换算 ----------

  /// 课程名 → 调色板下标：按首次出现顺序分配，保证同一门课跨天同色
  Map<String, int> get _paletteOf {
    final d = _data;
    final m = <String, int>{};
    if (d == null) return m;
    var i = 0;
    for (final c in d.courses) {
      if (!m.containsKey(c.name)) {
        m[c.name] = i % _kEventPalette.length;
        i++;
      }
    }
    return m;
  }

  _EvColor _colorOf(String name) {
    final i = _paletteOf[name] ?? 0;
    final base = _kEventPalette[i];
    return _dark ? base.darkVariant() : base;
  }

  /// 分钟轴范围：由 periods 的实际跨度推导；无数据回落到 08:00–22:00
  (int, int) get _gridRange {
    final d = _data;
    if (d == null || d.periods.isEmpty) return (8 * 60, 22 * 60);
    var lo = 24 * 60;
    var hi = 0;
    for (final p in d.periods) {
      lo = math.min(lo, _toMin(p.start));
      hi = math.max(hi, _toMin(p.end));
    }
    if (hi <= lo) return (8 * 60, 22 * 60);
    return ((lo ~/ 60) * 60, ((hi + 59) ~/ 60) * 60);
  }

  /// 网格列对应的日期
  List<DateTime> get _visibleDays {
    if (_view == _CalView.day) return [_cursorDay];
    final d = _data;
    // 设计稿是 5 列（工作日）；若课表里存在周末课程才扩展到 7 列
    var n = 5;
    if (d != null && d.courses.any((c) => c.day >= 6)) n = 7;
    final start = _weekStart;
    return [for (var i = 0; i < n; i++) start.add(Duration(days: i))];
  }

  /// 某天的课程（含时间换算），按开始时间升序
  List<({TimetableCourse course, int start, int end})> _eventsOn(DateTime date) {
    final d = _data;
    if (d == null) return const [];
    final week = d.weekOf(date);
    final out = <({TimetableCourse course, int start, int end})>[];
    for (final c in d.coursesFor(date.weekday, week)) {
      final sp = d.periodAt(c.startPeriod);
      final ep = d.periodAt(c.endPeriod);
      if (sp == null || ep == null) continue;
      final st = _toMin(sp.start);
      var en = _toMin(ep.end);
      if (en <= st) en = st + 30;
      out.add((course: c, start: st, end: en));
    }
    return out;
  }

  /// 搜索命中：课程名 / 教室 / 教师任一包含关键词
  bool _matches(TimetableCourse c) {
    final q = _query.trim();
    if (q.isEmpty) return true;
    final t = q.toLowerCase();
    return c.name.toLowerCase().contains(t) ||
        c.room.toLowerCase().contains(t) ||
        c.teacher.toLowerCase().contains(t);
  }

  // ---------- 弹窗 ----------

  void _showCourseDetail(TimetableCourse course, {DateTime? date}) {
    final d = _data;
    if (d == null) return;
    final gc = g;
    final ev = _colorOf(course.name);
    final sp = d.periodAt(course.startPeriod);
    final ep = d.periodAt(course.endPeriod);
    final time = (sp != null && ep != null) ? '${sp.start} – ${ep.end}' : '节次时间未定义';
    final weeks = course.weeks == null ? '每周' : '第 ${TimetableData.weeksToSpec(course.weeks!)} 周';
    final dayLabel = date != null
        ? '${date.month}月${date.day}日 ${_kWeekdayCn[date.weekday - 1]}'
        : _kWeekdayCn[course.day - 1];

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => Dialog(
        backgroundColor: gc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部色条呼应事件卡
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: ev.accent,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.name,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: gc.text)),
                    const SizedBox(height: 12),
                    _detailRow(gc, Icons.schedule_rounded, '$dayLabel · $time'),
                    if (course.room.isNotEmpty)
                      _detailRow(gc, Icons.place_outlined, course.room),
                    if (course.teacher.isNotEmpty)
                      _detailRow(gc, Icons.person_outline_rounded, course.teacher),
                    _detailRow(gc, Icons.date_range_outlined,
                        '$weeks · 第 ${course.startPeriod}–${course.endPeriod} 节'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openEdit();
                      },
                      child: Text('编辑课表', style: TextStyle(color: gc.text2, fontSize: 13.5)),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: gc.blue,
                        foregroundColor: gc.onBlue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
                      child: const Text('知道了', style: TextStyle(fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(_G gc, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: gc.text3),
        const SizedBox(width: 11),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13.5, color: gc.text2, height: 1.45)),
        ),
      ]),
    );
  }

  void _openEdit() {
    showDialog<void>(
      context: context,
      builder: (_) => EditTimetableDialog(state: s),
    );
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => TimetableSettingsDialog(state: s),
    );
  }

  void _openFormatDoc() {
    showDialog<void>(context: context, builder: (_) => const TimetableFormatDocDialog());
  }

  /// 导入 / 导出 / 编辑 / 格式说明 的统一下拉（窄屏 FAB、宽屏头像与「添加」共用）
  /// [anchor] 传触发点的 context，让菜单贴着按钮弹出；不传则贴页面右上角
  Future<void> _showActions({BuildContext? anchor}) async {
    final gc = g;
    final d = _data;
    final src = (anchor ?? context).findRenderObject();
    final box = src is RenderBox ? src : null;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final res = await showMenu<String>(
      context: context,
      color: gc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        origin.dx + box.size.width - 230,
        origin.dy + 52,
        overlay.size.width - (origin.dx + box.size.width),
        overlay.size.height - origin.dy,
      ),
      items: [
        _menuItem('import', Icons.file_download_outlined, d == null ? '导入课表' : '重新导入课表', gc),
        if (d != null) _menuItem('export', Icons.file_upload_outlined, '导出课表', gc),
        _menuItem('edit', Icons.edit_outlined, '编辑课程表', gc),
        _menuItem('format', Icons.description_outlined, '查看 JSON 格式', gc),
        _menuItem('settings', Icons.tune_rounded, '课程表设置', gc),
      ],
    );
    if (!mounted || res == null) return;
    switch (res) {
      case 'import':
        await _importJson();
        break;
      case 'export':
        await _exportJson();
        break;
      case 'edit':
        _openEdit();
        break;
      case 'format':
        _openFormatDoc();
        break;
      case 'settings':
        _openSettings();
        break;
    }
  }

  PopupMenuItem<String> _menuItem(String v, IconData icon, String label, _G gc) {
    return PopupMenuItem<String>(
      value: v,
      height: 42,
      child: Row(children: [
        Icon(icon, size: 17, color: gc.text2),
        const SizedBox(width: 11),
        Text(label, style: TextStyle(fontSize: 13.5, color: gc.text)),
      ]),
    );
  }

  // ---------- 导入 / 导出 ----------

  Future<void> _importJson() async {
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
        _cursor = _today;
        _followSystem = true;
      });
      unawaited(s.scheduleClassReminders());
      if (mounted) {
        _toast('已导入「${data.name}」，共 ${data.courses.length} 门课');
      }
    } on TimetableFormatException catch (e) {
      if (mounted) _showError('导入失败', e.message);
    } catch (e) {
      if (mounted) _showError('导入失败', '导入失败：$e');
    } finally {
      // 释放 focus，避免下拉残留
      if (mounted) FocusScope.of(context).unfocus();
    }
  }

  Future<void> _exportJson() async {
    final d = _data;
    if (d == null) return;
    try {
      final suggested = '${d.name.replaceAll(RegExp(r'\s+'), '_')}.json';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出课表',
        fileName: suggested,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null) return;
      final raw = const JsonEncoder.withIndent('  ').convert(d.toJson());
      await File(path).writeAsString(raw, flush: true);
      if (!mounted) return;
      _toast('已导出到：$path');
    } catch (e) {
      if (mounted) _showError('导出失败', '导出失败：$e');
    }
  }

  void _toast(String text) {
    final gc = g;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: TextStyle(fontSize: 13, color: gc.text)),
      backgroundColor: gc.surface,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String title, String message) {
    final gc = g;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: gc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: gc.text)),
        content: SizedBox(
          width: 360,
          child: Text(message, style: TextStyle(fontSize: 13, color: gc.text2, height: 1.6)),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openFormatDoc();
            },
            child: Text('格式说明', style: TextStyle(color: gc.text2, fontSize: 13.5)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: gc.blue,
              foregroundColor: gc.onBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text('知道了', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
    );
  }

  // ---------- 左侧导航 ----------

  void _onNav(int i) {
    if (i == 3) {
      // 设置：改为抽拉式设置面板（功能与原课程表设置对话框一致）
      setState(() => _navIndex = 0);
      _openDrawer();
      return;
    }
    setState(() => _navIndex = i);
  }

  Widget _buildSidebar(_G gc) {
    return Container(
      width: 232,
      color: gc.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: gc.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.calendar_month_rounded, size: 17, color: gc.onBlue),
              ),
              const SizedBox(width: 11),
              Text('课程表',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: gc.text)),
            ]),
          ),
          _navItem(gc, 0, Icons.calendar_today_rounded, '课程表'),
          _navItem(gc, 1, Icons.check_box_outlined, '任务'),
          _navItem(gc, 2, Icons.sticky_note_2_outlined, '笔记'),
          _navItem(gc, 3, Icons.settings_outlined, '设置'),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text('我的日历',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.6,
                    color: gc.text3)),
          ),
          const SizedBox(height: 10),
          _legendRow(gc, gc.blue, '课程'),
          _legendRow(gc, gc.dotGreen, '个人'),
          _legendRow(gc, gc.dotAmber, '工作'),
          _legendRow(gc, gc.dotPurple, '假期'),
          const Spacer(),
          if (_promoOpen) _promoCard(gc),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _navItem(_G gc, int i, IconData icon, String label) {
    final active = _navIndex == i;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _onNav(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: active ? gc.blueSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(children: [
              Icon(icon, size: 18, color: active ? gc.blue : gc.text2),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? gc.blue : gc.text,
                  )),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _legendRow(_G gc, Color color, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 5, 22, 5),
      child: Row(children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 13),
        Text(label, style: TextStyle(fontSize: 13, color: gc.text2)),
      ]),
    );
  }

  Widget _promoCard(_G gc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
        decoration: BoxDecoration(
          color: gc.track,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const _GoogleMark(size: 18),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _promoOpen = false),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(Icons.close_rounded, size: 15, color: gc.text3),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text('保持井然有序，\n更高效',
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.4, color: gc.text)),
          const SizedBox(height: 6),
          Text('跨设备同步你的日历',
              style: TextStyle(fontSize: 12, height: 1.5, color: gc.text2)),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _openFormatDoc,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('了解更多',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: gc.blue)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, size: 14, color: gc.blue),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ---------- 顶栏 ----------

  Widget _iconButton(_G gc, IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, size: 20, color: gc.text2),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(_G gc) {
    return SizedBox(
      height: 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: gc.track,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(children: [
                  const SizedBox(width: 16),
                  Icon(Icons.search_rounded, size: 19, color: gc.text2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(fontSize: 13.5, color: gc.text),
                      cursorColor: gc.blue,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索课程、教室或教师…',
                        hintStyle: TextStyle(fontSize: 13.5, color: gc.text3),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded, size: 16, color: gc.text3),
                      ),
                    ),
                  const SizedBox(width: 10),
                ]),
              ),
            ),
          ),
          const Spacer(),
          _iconButton(gc, Icons.today_outlined, '回到今天', _goToday),
          _iconButton(gc, Icons.notifications_none_rounded, '课程提醒',
              () => unawaited(s.scheduleClassReminders())),
          const SizedBox(width: 8),
          _avatar(gc),
        ]),
      ),
    );
  }

  Widget _avatar(_G gc) {
    return Tooltip(
      message: '课表信息',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _showActions,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: gc.blueSoft,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text('课',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: gc.blue)),
          ),
        ),
      ),
    );
  }

  // ---------- 副头（年月 + 日/周/月） ----------

  Widget _buildSubHeader(_G gc) {
    final week = _weekNo;
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(children: [
          Icon(Icons.person_outline_rounded, size: 20, color: gc.text2),
          const SizedBox(width: 11),
          Text(_periodLabel,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: gc.text)),
          if (week != null && _view != _CalView.month) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: gc.track,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('第 $week 周',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: gc.text2)),
            ),
          ],
          const SizedBox(width: 6),
          _chevron(gc, Icons.chevron_left_rounded, () => _shift(-1)),
          _chevron(gc, Icons.chevron_right_rounded, () => _shift(1)),
          if (!_isCurrent)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: TextButton(
                onPressed: _goToday,
                style: TextButton.styleFrom(
                  foregroundColor: gc.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(color: gc.lineStrong)),
                ),
                child: const Text('今天', style: TextStyle(fontSize: 12.5)),
              ),
            ),
          const Spacer(),
          _SegmentedButton(
            gc: gc,
            value: _view,
            onChanged: _setView,
          ),
          const SizedBox(width: 10),
          _iconButton(gc, Icons.calendar_month_outlined, '选择月份',
              () => _setView(_CalView.month)),
          _iconButton(gc, Icons.add_rounded, '导入 / 导出', _showActions),
        ]),
      ),
    );
  }

  Widget _chevron(_G gc, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 22, color: gc.text2),
        ),
      ),
    );
  }

  // ---------- 主体分发 ----------

  Widget _buildCalendarBody(_G gc, {bool singleDay = false}) {
    if (_navIndex == 1) return _buildTasks(gc);
    if (_navIndex == 2) return _buildNotes(gc);
    if (_data == null) return _buildEmpty(gc);
    if (!singleDay && _view == _CalView.month) return _buildMonthView(gc);
    return _buildGrid(gc,
        forceDays: singleDay ? [_cursorDay] : null,
        hourH: singleDay ? _hourHMobile : _hourH,
        mobile: singleDay);
  }

  // ---------- 周 / 日 网格 ----------

  Widget _buildGrid(_G gc,
      {List<DateTime>? forceDays, double hourH = _hourH, bool mobile = false}) {
    final days = forceDays ?? _visibleDays;
    final (lo, hi) = _gridRange;
    final hours = ((hi - lo) / 60).round();
    final totalH = hours * hourH;
    final dayCount = days.length;

    return LayoutBuilder(builder: (ctx, cst) {
      const gutter = _gutterW;
      final colW = (cst.maxWidth - gutter) / dayCount;
      return Column(children: [
        // 表头：窄屏用左对齐文字标题（对齐设计稿的 "Wed, Aug 27"），宽屏用「星期 + 日期胶囊」
        if (mobile)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: Row(children: [
              Text(
                '${_kWeekdayCn[days.first.weekday - 1]} ${days.first.month}月${days.first.day}日',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: gc.text),
              ),
              const Spacer(),
              if (_weekNo != null)
                Text('第 $_weekNo 周',
                    style: TextStyle(fontSize: 12, color: gc.text3)),
            ]),
          )
        else
          SizedBox(
            height: 70,
            child: Row(children: [
              const SizedBox(width: gutter),
              for (final day in days)
                SizedBox(width: colW, child: _dayHeaderCell(gc, day, colW)),
            ]),
          ),
        Container(height: 1, color: gc.line),
        Expanded(
          child: AnimatedBuilder(
            animation: _intro,
            builder: (ctx, _) => SingleChildScrollView(
              controller: _scroll,
              child: SizedBox(
                height: _padTop + totalH + 24,
                child: Stack(children: [
                  // 列分隔线
                  Positioned(
                    left: gutter,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: Row(children: [
                      for (var i = 0; i < dayCount; i++)
                        Container(
                          width: colW,
                          decoration: BoxDecoration(
                            border: Border(
                              left: i == 0
                                  ? BorderSide.none
                                  : BorderSide(color: gc.line, width: 1),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  // 小时线 + 时间标签
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _padTop,
                    child: Column(children: [
                      for (var h = 0; h < hours; h++)
                        SizedBox(
                          height: hourH,
                          child: Row(children: [
                            SizedBox(
                              width: gutter,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: Transform.translate(
                                    offset: const Offset(0, -6),
                                    child: Text(
                                      _fmtMin(lo + h * 60),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: gc.text3,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: Container(height: 1, color: gc.line),
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                  // 各日课块
                  for (var i = 0; i < dayCount; i++)
                    Positioned(
                      left: gutter + i * colW,
                      top: _padTop,
                      width: colW,
                      height: totalH,
                      child: _dayColumn(gc, days[i], lo, hi, hourH, colW, mobile),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  Widget _dayHeaderCell(_G gc, DateTime day, double colW) {
    final active = day == _cursorDay;
    final isToday = day == _today && _isCurrent;
    return InkWell(
      onTap: () {
        setState(() {
          _cursor = day;
          _followSystem = false;
        });
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _kWeekdayCn[day.weekday - 1],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: active ? gc.blue : gc.text2,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
            decoration: BoxDecoration(
              color: active ? gc.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${day.month}.${day.day}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: active ? gc.onBlue : gc.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          if (isToday && !active)
            Text('今天', style: TextStyle(fontSize: 10, color: gc.blue)),
        ],
      ),
    );
  }

  Widget _dayColumn(_G gc, DateTime date, int lo, int hi, double hourH, double colW,
      bool mobile) {
    final totalH = ((hi - lo) / 60).round() * hourH;
    final evs = _eventsOn(date).where((e) => _matches(e.course)).toList();
    final showNow = _isCurrent && date == _today;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final nowTop = (nowMin - lo) / 60 * hourH;

    // 车道分配：同一天内时间重叠的课块横向均分
    final lanes = <List<int>>[];
    for (var i = 0; i < evs.length; i++) {
      var placed = false;
      for (final lane in lanes) {
        if (lane.every((j) => evs[i].start >= evs[j].end || evs[i].end <= evs[j].start)) {
          lane.add(i);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.add([i]);
    }
    final laneOf = <int, int>{};
    for (var l = 0; l < lanes.length; l++) {
      for (final j in lanes[l]) {
        laneOf[j] = l;
      }
    }
    final laneCount = lanes.isEmpty ? 1 : lanes.length;

    return Stack(clipBehavior: Clip.none, children: [
      for (var i = 0; i < evs.length; i++)
        () {
          final e = evs[i];
          final l = laneOf[i] ?? 0;
          final availW = colW - 8;
          final laneW = availW / laneCount;
          final w = laneW - (laneCount > 1 ? 4 : 0);
          final left = 4 + l * laneW;
          final top = (e.start - lo) / 60 * hourH;
          final h = ((e.end - e.start) / 60 * hourH) - 2;
          final t = _stagger(i);
          return Positioned(
            left: left,
            top: top + (1 - t) * 10,
            width: w,
            height: h,
            child: Opacity(
              opacity: t,
              child: mobile
                  ? _mobileEventCard(gc, e.course, e.start, e.end,
                      onTap: () => _showCourseDetail(e.course, date: date))
                  : _eventChip(gc, e.course, e.start, e.end, h,
                      onTap: () => _showCourseDetail(e.course, date: date)),
            ),
          );
        }(),
      // 当前时间指示
      if (showNow && nowTop >= 0 && nowTop <= totalH)
        Positioned(
          left: 0,
          right: 0,
          top: nowTop,
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: gc.blue, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 2, color: gc.blue)),
          ]),
        ),
    ]);
  }

  Widget _eventChip(_G gc, TimetableCourse course, int st, int en, double h,
      {required VoidCallback onTap}) {
    final ev = _colorOf(course.name);
    final showTime = h >= 36;
    final place = course.room.isNotEmpty ? course.room : course.teacher;
    final showPlace = h >= 58 && place.isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ev.fill,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // 色条：实测参考图只有 2px，且是强调色 55% 透明叠在填充上（不是实色）
            Container(
              width: 2,
              color: Color.alphaBlend(ev.accent.withValues(alpha: 0.55), ev.fill),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 6, 7, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: ev.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          course.name,
                          maxLines: showTime ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: ev.ink,
                          ),
                        ),
                      ),
                    ]),
                    if (showTime) ...[
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.only(left: 11),
                        child: Text(
                          '${_fmtMin(st)} – ${_fmtMin(en)}',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: ev.ink.withValues(alpha: 0.72),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                    if (showPlace) ...[
                      const SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 11),
                        child: Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.2,
                            color: ev.ink.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// 窄屏课程卡：左侧色条 + 标题/时间/地点 + 右侧「›」。
  /// 行距按参考图放宽（标题→时间 6px、时间→地点 4px），对应"文字排版很均匀"的要求
  Widget _mobileEventCard(_G gc, TimetableCourse course, int st, int en,
      {required VoidCallback onTap}) {
    final ev = _colorOf(course.name);
    final place = course.room.isNotEmpty ? course.room : course.teacher;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ev.fill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 2,
              color: Color.alphaBlend(ev.accent.withValues(alpha: 0.55), ev.fill),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration:
                            BoxDecoration(color: ev.accent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          course.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: ev.ink,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        '${_fmtMin(st)} – ${_fmtMin(en)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: ev.ink.withValues(alpha: 0.70),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text(
                          place,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: ev.ink.withValues(alpha: 0.70),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(Icons.chevron_right_rounded,
                    size: 19, color: ev.ink.withValues(alpha: 0.5)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---------- 月视图 ----------

  Widget _buildMonthView(_G gc) {
    final first = DateTime(_cursor.year, _cursor.month, 1);
    final gridStart = first.subtract(Duration(days: first.weekday - 1));
    const rows = 6;
    final today = _today;

    return LayoutBuilder(builder: (ctx, cst) {
      final cellW = cst.maxWidth / 7;
      final cellH = cst.maxHeight / (rows + 1);
      return Column(children: [
        // 星期表头
        SizedBox(
          height: cellH * 0.62,
          child: Row(children: [
            for (var i = 0; i < 7; i++)
              SizedBox(
                width: cellW,
                child: Center(
                  child: Text(_kWeekdayCn[i],
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: gc.text2)),
                ),
              ),
          ]),
        ),
        Container(height: 1, color: gc.line),
        for (var r = 0; r < rows; r++)
          SizedBox(
            height: cellH,
            child: Row(children: [
              for (var c = 0; c < 7; c++)
                _monthCell(gc, gridStart.add(Duration(days: r * 7 + c)), cellW, today),
            ]),
          ),
      ]);
    });
  }

  Widget _monthCell(_G gc, DateTime day, double w, DateTime today) {
    final inMonth = day.month == _cursor.month;
    final isToday = day == today;
    final isCursor = day == _cursorDay;
    final evs = _eventsOn(day).where((e) => _matches(e.course)).toList();
    return InkWell(
      onTap: () {
        setState(() {
          _cursor = day;
          _followSystem = false;
          _view = _CalView.day;
        });
        _replayIntro();
      },
      child: Container(
        width: w,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: gc.line, width: 1),
            bottom: BorderSide(color: gc.line, width: 1),
          ),
          color: isCursor && !isToday ? gc.blueSoft.withValues(alpha: 0.45) : null,
        ),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isToday ? gc.blue : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
                  color: isToday
                      ? gc.onBlue
                      : (inMonth ? gc.text : gc.text3.withValues(alpha: 0.7)),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          for (final e in evs.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: inMonth ? _colorOf(e.course.name).fill : gc.track,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(children: [
                  Container(width: 2.5, height: 15, color: _colorOf(e.course.name).accent),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      e.course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.4,
                        color: inMonth ? _colorOf(e.course.name).ink : gc.text3,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                ]),
              ),
            ),
          if (evs.length > 3)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('+${evs.length - 3}',
                  style: TextStyle(fontSize: 10, color: gc.text3)),
            ),
        ]),
      ),
    );
  }

  // ---------- 任务 / 笔记 / 空态 ----------

  Widget _buildTasks(_G gc) => _placeholder(gc, '任务', '刷课与作业待办会显示在这里');

  Widget _buildNotes(_G gc) => _placeholder(gc, '笔记', '课堂笔记会显示在这里');

  Widget _placeholder(_G gc, String title, String sub) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: gc.text)),
          const SizedBox(height: 8),
          Text(sub, style: TextStyle(fontSize: 13, color: gc.text3)),
        ],
      ),
    );
  }

  Widget _buildEmpty(_G gc) {
    return Center(
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(30, 34, 30, 30),
        decoration: BoxDecoration(
          color: gc.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: gc.line),
          boxShadow: [BoxShadow(color: gc.shadowSoft, blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Column(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: gc.blueSoft, borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.calendar_month_rounded, size: 28, color: gc.blue),
          ),
          const SizedBox(height: 18),
          Text('还没有课程表',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: gc.text)),
          const SizedBox(height: 8),
          Text('导入 JSON 课表文件即可按周查看课程安排',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.6, color: gc.text2)),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _importJson,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('导入课表', style: TextStyle(fontSize: 13.5)),
            style: FilledButton.styleFrom(
              backgroundColor: gc.blue,
              foregroundColor: gc.onBlue,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _openFormatDoc,
            child: Text('查看 JSON 格式',
                style: TextStyle(fontSize: 12.5, color: gc.text2)),
          ),
        ]),
      ),
    );
  }

  // ---------- 窄屏 ----------

  Widget _buildMobile(_G gc) {
    return Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _mobileHeader(gc),
        if (_navIndex == 0) _mobileDateStrip(gc),
        Expanded(child: _buildCalendarBody(gc, singleDay: true)),
        _mobileTabBar(gc),
      ]),
      if (_navIndex == 0 && _data != null)
        Positioned(
          right: 18,
          bottom: 84,
          child: Builder(
            builder: (ctx) => _mobileFab(gc, () => _showActions(anchor: ctx)),
          ),
        ),
    ]);
  }

  Widget _mobileHeader(_G gc) {
    // 搜索图标与头像已按反馈移除（搜索框是宽屏专有组件，窄屏点它也无处可去）
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 6),
      child: Row(children: [
        _iconButton(gc, Icons.menu_rounded, '课程表设置', _openDrawer),
        const SizedBox(width: 2),
        Text('课程表',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: gc.text)),
      ]),
    );
  }

  Widget _mobileDateStrip(_G gc) {
    final days = _visibleDays;
    return SizedBox(
      height: 62,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          for (final day in days)
            Expanded(child: _mobileDayCell(gc, day)),
        ]),
      ),
    );
  }

  Widget _mobileDayCell(_G gc, DateTime day) {
    final active = day == _cursorDay;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() {
          _cursor = day;
          _followSystem = false;
        });
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_kWeekdayCn[day.weekday - 1],
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: active ? gc.blue : gc.text3)),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: active ? gc.blue : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${day.month}.${day.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? gc.onBlue : gc.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileFab(_G gc, VoidCallback onTap) {
    return _PressScale(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: gc.blue,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: gc.blue.withValues(alpha: 0.32), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Icon(Icons.add_rounded, size: 27, color: gc.onBlue),
      ),
    );
  }

  Widget _mobileTabBar(_G gc) {
    const items = [
      (Icons.calendar_today_rounded, '课程表'),
      (Icons.check_box_outlined, '任务'),
      (Icons.sticky_note_2_outlined, '笔记'),
      (Icons.person_outline_rounded, '我的'),
    ];
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: gc.surface,
        border: Border(top: BorderSide(color: gc.line, width: 1)),
      ),
      child: Row(children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: InkWell(
              onTap: () => _onNav(i == 3 ? 3 : i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(items[i].$1,
                      size: 20, color: _navIndex == i ? gc.blue : gc.text3),
                  const SizedBox(height: 4),
                  Text(items[i].$2,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: _navIndex == i ? FontWeight.w600 : FontWeight.w400,
                        color: _navIndex == i ? gc.blue : gc.text3,
                      )),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  // ---------- 装配 ----------

  @override
  Widget build(BuildContext context) {
    final gc = g;
    return Scaffold(
      backgroundColor: gc.pageBg,
      body: Stack(children: [
        LayoutBuilder(builder: (ctx, cst) {
          final wide = cst.maxWidth >= 860;
          return wide ? _buildDesktop(gc) : _buildMobile(gc);
        }),
        _buildDrawerOverlay(gc),
      ]),
    );
  }

  /// 抽拉式设置面板：从左滑入 + 右侧遮罩渐显
  Widget _buildDrawerOverlay(_G gc) {
    return AnimatedBuilder(
      animation: _drawerAnim,
      builder: (ctx, _) {
        final v = _drawerAnim.value;
        if (v == 0) return const SizedBox.shrink();
        final t = Curves.easeOutCubic.transform(v);
        final w = math.min(330.0, MediaQuery.of(context).size.width * 0.88);
        return Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: v < 0.02,
              child: GestureDetector(
                onTap: _closeDrawer,
                child: Container(color: Colors.black.withValues(alpha: 0.32 * t)),
              ),
            ),
          ),
          Positioned(
            left: -w * (1 - t),
            top: 0,
            bottom: 0,
            width: w,
            child: _SettingsDrawer(
              gc: gc,
              state: s,
              onClose: _closeDrawer,
              onEdit: () {
                _closeDrawer();
                _openEdit();
              },
              onImport: () async {
                _closeDrawer();
                await _importJson();
              },
              onExport: () async {
                _closeDrawer();
                await _exportJson();
              },
              onFormatDoc: () {
                _closeDrawer();
                _openFormatDoc();
              },
              onClear: () => _clearTimetable(gc),
            ),
          ),
        ]);
      },
    );
  }

  /// 清除课表：先确认再置空（与原设置对话框语义一致，仅配色换成 Google 红）
  Future<void> _clearTimetable(_G gc) async {
    _closeDrawer();
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (ctx) => AlertDialog(
        backgroundColor: gc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('确认清除',
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: gc.text)),
        content: Text('将删除当前课程表数据（学期名/节次时间/课程）。此操作不可撤销。',
            style: TextStyle(fontSize: 13, color: gc.text2, height: 1.6)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消', style: TextStyle(color: gc.text2))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('清除',
                  style: TextStyle(color: gc.red, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok == true) {
      s.setTimetable(null);
      if (mounted) setState(() => _cursor = _today);
    }
  }

  Widget _buildDesktop(_G gc) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildSidebar(gc),
      Container(width: 1, color: gc.line),
      Expanded(
        child: Column(children: [
          _buildTopBar(gc),
          if (_navIndex == 0) _buildSubHeader(gc),
          Expanded(child: _buildCalendarBody(gc)),
        ]),
      ),
    ]);
  }
}

// ============================================================
// 复用小组件
// ============================================================

/// 日 / 周 / 月 分段控件：白色胶囊随选中项滑动（对应设计稿的 segmented control）
class _SegmentedButton extends StatelessWidget {
  final _G gc;
  final _CalView value;
  final ValueChanged<_CalView> onChanged;
  const _SegmentedButton({
    required this.gc,
    required this.value,
    required this.onChanged,
  });

  static const double _segW = 58;
  static const double _h = 38;
  static const double _pad = 3;

  @override
  Widget build(BuildContext context) {
    const labels = ['日', '周', '月'];
    final idx = value.index;
    return Container(
      height: _h,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: gc.track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(
        width: _segW * 3,
        child: Stack(children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            alignment: switch (idx) {
              0 => Alignment.centerLeft,
              1 => Alignment.center,
              _ => Alignment.centerRight,
            },
            child: Container(
              width: _segW,
              height: _h - _pad * 2,
              decoration: BoxDecoration(
                color: gc.surface,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(color: gc.shadow, blurRadius: 4, offset: const Offset(0, 1)),
                ],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < 3; i++)
              SizedBox(
                width: _segW,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onChanged(_CalView.values[i]),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: i == idx ? FontWeight.w600 : FontWeight.w500,
                        color: i == idx ? gc.text : gc.text2,
                      ),
                      child: Text(labels[i]),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// 四色 Google 标记（左栏推广卡用）
class _GoogleMark extends StatelessWidget {
  final double size;
  const _GoogleMark({this.size = 18});

  @override
  Widget build(BuildContext context) {
    final h = size / 2;
    return SizedBox(
      width: size,
      height: size,
      child: Column(children: [
        Row(children: [
          _sq(const Color(0xFF4285F4), h),
          _sq(const Color(0xFFEA4335), h),
        ]),
        Row(children: [
          _sq(const Color(0xFF34A853), h),
          _sq(const Color(0xFFFBBC04), h),
        ]),
      ]),
    );
  }

  Widget _sq(Color c, double h) => Container(width: h, height: h, color: c);
}

/// 按下缩放：FAB 等强调按钮的触感反馈
class _PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  const _PressScale({required this.child, required this.onTap});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scale = _down ? 0.92 : (_hover ? 1.05 : 1.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// 课程表设置抽拉面板：从左滑入。
/// 功能与原「课程表设置」对话框完全一致（开学日期 / 导入 / 导出 / 清除 / 编辑 /
/// 格式说明 / 应用模式切换），UI 按 Google 风格重排为分区卡片。
class _SettingsDrawer extends StatelessWidget {
  final _G gc;
  final AppState state;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final Future<void> Function() onImport;
  final Future<void> Function() onExport;
  final VoidCallback onFormatDoc;
  final VoidCallback onClear;

  const _SettingsDrawer({
    required this.gc,
    required this.state,
    required this.onClose,
    required this.onEdit,
    required this.onImport,
    required this.onExport,
    required this.onFormatDoc,
    required this.onClear,
  });

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final gc = this.gc;
    return Material(
      color: gc.surface,
      child: Container(
        decoration: BoxDecoration(
          color: gc.surface,
          boxShadow: [
            BoxShadow(color: gc.shadow, blurRadius: 24, offset: const Offset(6, 0)),
          ],
        ),
        child: SafeArea(
          right: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(children: [
                Icon(Icons.tune_rounded, size: 19, color: gc.text2),
                const SizedBox(width: 10),
                Text('课程表设置',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: gc.text)),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onClose,
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.close_rounded, size: 20, color: gc.text3),
                  ),
                ),
              ]),
            ),
            Container(height: 1, color: gc.line),
            Expanded(
              child: ListenableBuilder(
                listenable: state,
                builder: (ctx, _) {
                  final tt = state.timetable;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section(gc, '学期设置'),
                        const SizedBox(height: 10),
                        _card(gc, [
                          _row(
                            gc,
                            icon: Icons.event_available_outlined,
                            title: '开学日期（第 1 周周一）',
                            sub: tt == null ? '导入课表后可修改' : '周次与「今天」按此日期推算，修改后立即生效',
                            value: tt == null ? null : _fmt(tt.startDate),
                            onTap: tt == null ? null : () => _pickStart(context),
                          ),
                        ]),
                        const SizedBox(height: 22),
                        _section(gc, '数据管理'),
                        const SizedBox(height: 10),
                        _card(gc, [
                          _row(gc,
                              icon: Icons.upload_file_outlined,
                              title: '导入课表',
                              sub: '从 JSON 文件加载，导入后立即生效',
                              onTap: onImport),
                          _divider(gc),
                          _row(gc,
                              icon: Icons.save_alt_outlined,
                              title: '导出课表',
                              sub: tt == null ? '当前未导入课表' : '保存为 JSON 文件，可备份或换设备',
                              onTap: tt == null ? null : onExport),
                          _divider(gc),
                          _row(gc,
                              icon: Icons.delete_outline_rounded,
                              title: '清除课表',
                              sub: tt == null ? '当前未导入课表' : '删除数据，回到空白初始表',
                              onTap: tt == null ? null : onClear,
                              danger: true),
                        ]),
                        const SizedBox(height: 22),
                        _section(gc, '编辑与说明'),
                        const SizedBox(height: 10),
                        _card(gc, [
                          _row(gc,
                              icon: Icons.edit_outlined,
                              title: '编辑课程表',
                              sub: tt == null ? '当前未导入课表' : '学期名 / 节次时间 / 课程明细',
                              onTap: tt == null ? null : onEdit),
                          _divider(gc),
                          _row(gc,
                              icon: Icons.description_outlined,
                              title: '查看 JSON 格式',
                              sub: '导入文件的字段说明与示例',
                              onTap: onFormatDoc),
                        ]),
                        const SizedBox(height: 22),
                        _section(gc, '应用模式'),
                        const SizedBox(height: 10),
                        _modeToggle(gc),
                      ],
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickStart(BuildContext context) async {
    final t = state.timetable;
    if (t == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: t.startDate,
      firstDate: DateTime(t.startDate.year - 1, 1, 1),
      lastDate: DateTime(t.startDate.year + 2, 12, 31),
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null && state.timetable != null) {
      state.setTimetable(state.timetable!.copyWith(startDate: picked));
    }
  }

  Widget _section(_G gc, String t) => Text(t,
      style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.6,
          color: gc.text3));

  Widget _card(_G gc, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: gc.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: gc.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _divider(_G gc) =>
      Container(height: 1, color: gc.line, margin: const EdgeInsets.only(left: 48));

  Widget _row(
    _G gc, {
    required IconData icon,
    required String title,
    required String sub,
    String? value,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final disabled = onTap == null;
    final fg = disabled ? gc.text3 : (danger ? gc.red : gc.text);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 19, color: disabled ? gc.text3 : (danger ? gc.red : gc.text2)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w500, color: fg)),
                  const SizedBox(height: 3),
                  Text(sub,
                      style:
                          TextStyle(fontSize: 11.5, height: 1.35, color: gc.text3)),
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: gc.blue,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(width: 4),
              Icon(Icons.edit_calendar_outlined, size: 15, color: gc.text3),
            ] else ...[
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: disabled ? gc.track : gc.lineStrong),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _modeToggle(_G gc) {
    final isTimetable = state.appMode == 'timetable';
    return Row(children: [
      Expanded(
        child: _modeSeg(gc, Icons.calendar_month_rounded, '课程表', isTimetable, () {
          if (!isTimetable) {
            if (state.uiMode.isEmpty) state.setUiMode('desktop');
            state.setAppMode('timetable');
          }
        }),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _modeSeg(gc, Icons.school_outlined, '学习模式', !isTimetable, () {
          if (isTimetable) {
            if (state.uiMode.isEmpty) state.setUiMode('desktop');
            state.setAppMode('english');
          }
        }),
      ),
    ]);
  }

  Widget _modeSeg(
      _G gc, IconData icon, String label, bool selected, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 62,
          decoration: BoxDecoration(
            color: selected ? gc.blueSoft : gc.track,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? gc.blue.withValues(alpha: 0.5) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 19, color: selected ? gc.blue : gc.text3),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? gc.blue : gc.text2,
                )),
          ]),
        ),
      ),
    );
  }
}
