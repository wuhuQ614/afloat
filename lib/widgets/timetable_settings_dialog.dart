/// 课程表模式独立的设置对话框（不依赖学习模式 SettingsDialog）
/// 由课程表页右上角"三点"菜单触发
library;

import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../state.dart';
import '../theme_colors.dart' show AppColors;
import '../timetable_models.dart';

class TimetableSettingsDialog extends StatelessWidget {
  final AppState state;
  const TimetableSettingsDialog({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dark = c.isLight ? false : true;
    // ListenableBuilder：开学日期修改（setTimetable → notifyListeners）后立即刷新显示
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            // 实底不透明：Dialog 用半透明 card 会让下层课程表页（毛玻璃背景 + 粒子动效）
            // 持续参与合成，滚动/输入时开销明显
            color: c.cardSolid,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.4 : 0.12), blurRadius: 24, offset: const Offset(0, 8))],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // 顶栏
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 12),
              child: Row(children: [
                Icon(Icons.settings_outlined, size: 18, color: c.textSecondary),
                const SizedBox(width: 8),
                Text('课程表设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, size: 20, color: c.textTertiary),
                  tooltip: '关闭',
                ),
              ]),
            ),
            Divider(height: 1, color: c.divider),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _sectionTitle(c, '学期设置'),
                  const SizedBox(height: 10),
                  if (state.timetable != null)
                    _DateRow(
                      icon: Icons.event_available_outlined,
                      title: '开学日期（第 1 周周一）',
                      subtitle: '周次与"今天"定位按此日期推算，修改后立即生效',
                      value: _fmtDate(state.timetable!.startDate),
                      c: c,
                      onTap: () async {
                        final t = state.timetable!;
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
                      },
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.inputFill,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(children: [
                        Icon(Icons.event_available_outlined, size: 18, color: c.textTertiary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('导入课表后可在此修改开学日期（第 1 周周一）',
                              style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 22),
                  _sectionTitle(c, '数据管理'),
                  const SizedBox(height: 10),
                  _ActionRow(
                    icon: Icons.upload_file_outlined,
                    title: '导入课表',
                    subtitle: '从 JSON 文件加载，导入后立即生效',
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _doImport(context, state);
                    },
                    c: c,
                  ),
                  const SizedBox(height: 8),
                  _ActionRow(
                    icon: Icons.save_alt_outlined,
                    title: '导出课表',
                    subtitle: state.timetable == null ? '当前未导入课表' : '保存为 JSON 文件，可备份或换设备',
                    onTap: state.timetable == null ? null : () async {
                      Navigator.of(context).pop();
                      await _doExport(context, state);
                    },
                    c: c,
                  ),
                  const SizedBox(height: 8),
                  _ActionRow(
                    icon: Icons.delete_outline_rounded,
                    title: '清除课表',
                    subtitle: '删除当前课表数据，回到空白初始表',
                    destructive: true,
                    onTap: state.timetable == null ? null : () async {
                      Navigator.of(context).pop();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: c.cardSolid,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
                          title: Text('确认清除', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                          content: Text('将删除当前课程表数据（学期名/节次时间/课程）。此操作不可撤销。', style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.6)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('取消', style: TextStyle(color: c.textTertiary))),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text('清除', style: TextStyle(color: c.scoreLow, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) state.setTimetable(null);
                    },
                    c: c,
                  ),
                  const SizedBox(height: 22),
                  // 课程提醒：手机端默认开启、无 UI 开关（用户要求），桌面端自动无行为
                  const SizedBox(height: 10),
                  // "应用模式"段移到这里：放设置最下方（辅助设置，不影响主要操作）
                  _sectionTitle(c, '应用模式'),
                  const SizedBox(height: 10),
                  _ModeToggle(state: state),
                ]),
              ),
            ),
          ]),
        ),
      ),
      ),
    );
  }

  Widget _sectionTitle(AppColors c, String t) => Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text, letterSpacing: 0.2));

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<void> _doImport(BuildContext context, AppState s) async {
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
      s.setTimetable(data);
      if (!context.mounted) return;
      _toast(context, '已导入《${data.name}》（${data.courses.length} 门课）');
    } on TimetableFormatException catch (e) {
      if (!context.mounted) return;
      _toast(context, '解析失败：${e.message}', error: true);
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, '导入失败：$e', error: true);
    }
  }

  static Future<void> _doExport(BuildContext context, AppState s) async {
    final d = s.timetable;
    if (d == null) return;
    final suggested = '${d.name.replaceAll(RegExp(r'\s+'), '_')}.json';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出课表',
      fileName: suggested,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    try {
      // 简单 JSON 美化（缩进 2）便于人工阅读
      final raw = const JsonEncoder.withIndent('  ').convert(d.toJson());
      await File(path).writeAsString(raw, flush: true);
      if (!context.mounted) return;
      _toast(context, '已导出到：$path');
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, '导出失败：$e', error: true);
    }
  }

  static void _toast(BuildContext context, String msg, {bool error = false}) {
    final c = AppColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(fontSize: 13, color: error ? Colors.white : c.text)),
        backgroundColor: error ? c.scoreLow : c.cardSolid,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

/// 模式切换：课程表 / 学习模式（点击即切）
class _ModeToggle extends StatelessWidget {
  final AppState state;
  const _ModeToggle({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isTimetable = state.appMode == 'timetable';
    Widget seg(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: selected ? c.primaryBg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? c.primary.withValues(alpha: 0.4) : c.border, width: selected ? 1.4 : 1),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: selected ? c.primary : c.textTertiary),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? c.primary : c.textSecondary)),
            ]),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        seg('课程表', Icons.calendar_month_outlined, isTimetable, () {
          if (!isTimetable) {
            if (state.uiMode.isEmpty) state.setUiMode('desktop');
            state.setAppMode('timetable');
          }
        }),
        const SizedBox(width: 4),
        seg('学习模式', Icons.school_outlined, !isTimetable, () {
          if (isTimetable) {
            if (state.uiMode.isEmpty) state.setUiMode('desktop');
            state.setAppMode('english');
          }
        }),
      ]),
    );
  }
}

/// 带值的设置行（右侧显示当前值，点击弹出选择器）
class _DateRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onTap;
  final AppColors c;
  const _DateRow({required this.icon, required this.title, required this.subtitle, required this.value, required this.onTap, required this.c});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.inputFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: c.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: c.textTertiary)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primary, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 2),
            Icon(Icons.edit_calendar_outlined, size: 16, color: c.textTertiary),
          ]),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final AppColors c;
  const _ActionRow({required this.icon, required this.title, required this.subtitle, required this.onTap, required this.c, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final color = disabled
        ? c.textTertiary
        : destructive
            ? c.scoreLow
            : c.text;
    final subColor = disabled ? c.textTertiary : c.textTertiary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: c.inputFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: color)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: subColor)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ]),
        ),
      ),
    );
  }
}
