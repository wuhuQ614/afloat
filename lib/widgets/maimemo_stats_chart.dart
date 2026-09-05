/// 墨墨学习情况统计卡（复刻墨墨 App 统计页「学习情况」柱状图）：
/// - 三 Tab：遗忘曲线 / 学习情况 / 记忆持久度（v1 完整实现「学习情况」）
/// - 学习情况：认知情况（今日四色堆叠）/ 复习·新学（新学+复习堆叠）
/// - 时间轴：过去 4 天 + 今天 + 未来 6 天；历史柱 = lastStudyDate 聚合，
///   未来柱 = nextStudyDate 聚合（待学），今日 = get_today_items 实时认知细分
library;

import 'package:flutter/material.dart';

import '../services/maimemo_service.dart';
import '../theme_colors.dart' show AppColors;

/// 单日统计
class _DayStat {
  final DateTime date;
  int learned = 0; // 已学词数（历史：lastStudyDate 聚合）
  int newWords = 0; // 其中新学（firstStudyDate 聚合 / 今日 is_new）
  int wellFamiliar = 0;
  int familiar = 0;
  int vague = 0;
  int forget = 0;
  final bool isFuture; // 未来列（待学）
  int due = 0; // 未来：到期待学数（nextStudyDate 聚合）

  _DayStat(this.date, {this.isFuture = false});

  int get total => isFuture ? due : learned;
}

// 图表配色（文件级，_BarPainter 与 State 共用）
const _cWellFamiliar = Color(0xFF10B981); // 熟知 绿
const _cFamiliar = Color(0xFF3B82F6); // 认识 蓝
const _cVague = Color(0xFFF59E0B); // 模糊 橙
const _cForget = Color(0xFFEF4444); // 忘记 红
const _cDue = Color(0xFFC9CDD4); // 待学 灰
const _cLearned = Color(0xFF5B7FD4); // 历史已学 蓝紫
const _cNew = Color(0xFF22C1A3); // 新学 青

class MaimemoStatsChart extends StatefulWidget {
  final String token;
  const MaimemoStatsChart({super.key, required this.token});

  @override
  State<MaimemoStatsChart> createState() => _MaimemoStatsChartState();
}

class _MaimemoStatsChartState extends State<MaimemoStatsChart> {
  bool _loading = true;
  String? _error;
  List<MaimemoStudyRecord> _records = [];
  List<MaimemoTodayWord> _todayWords = [];
  int _studyTimeSec = 0;
  int _tab = 1; // 0 遗忘曲线 | 1 学习情况 | 2 记忆持久度
  bool _cognitionMode = true; // true=认知情况 false=复习·新学

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final progress = await MaimemoService.getStudyProgress(widget.token);
      final today = await MaimemoService.fetchAllTodayWords(widget.token);
      final records = await MaimemoService.fetchAllStudyRecords(widget.token);
      if (!mounted) return;
      setState(() {
        _records = records;
        _todayWords = today;
        _studyTimeSec = progress.studyTime;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 构建 过去4天 + 今天 + 未来6天 共 11 列统计
  List<_DayStat> _buildDays() {
    final now = DateTime.now();
    final days = <_DayStat>[];
    // 历史日期索引（lastStudyDate/firstStudyDate 取前 10 字符做键）
    final lastStudyByDay = <String, int>{};
    final firstStudyByDay = <String, int>{};
    final dueByDay = <String, int>{};
    for (final r in _records) {
      final last = r.lastStudyDate;
      if (last != null && last.length >= 10) {
        lastStudyByDay[last.substring(0, 10)] = (lastStudyByDay[last.substring(0, 10)] ?? 0) + 1;
      }
      final first = r.firstStudyDate;
      if (first != null && first.length >= 10) {
        firstStudyByDay[first.substring(0, 10)] = (firstStudyByDay[first.substring(0, 10)] ?? 0) + 1;
      }
      final next = r.nextStudyDate;
      if (next != null && next.length >= 10) {
        dueByDay[next.substring(0, 10)] = (dueByDay[next.substring(0, 10)] ?? 0) + 1;
      }
    }
    for (var i = -4; i <= 6; i++) {
      final d = DateTime(now.year, now.month, now.day + i);
      final key = _dateKey(d);
      if (i < 0) {
        final st = _DayStat(d)
          ..learned = lastStudyByDay[key] ?? 0
          ..newWords = firstStudyByDay[key] ?? 0;
        days.add(st);
      } else if (i == 0) {
        // 今天：实时认知细分
        final st = _DayStat(d);
        st.learned = _todayWords.length;
        for (final w in _todayWords) {
          if (w.isNew) st.newWords++;
          switch (w.firstResponse) {
            case 'WELL_FAMILIAR':
              st.wellFamiliar++;
            case 'FAMILIAR':
              st.familiar++;
            case 'VAGUE':
              st.vague++;
            case 'FORGET':
              st.forget++;
          }
        }
        days.add(st);
      } else {
        final st = _DayStat(d, isFuture: true)
          ..due = dueByDay[key] ?? 0;
        days.add(st);
      }
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Tab 行
        Row(children: [
          _tabItem('遗忘曲线', 0, c),
          _tabItem('学习情况', 1, c),
          _tabItem('记忆持久度', 2, c),
        ]),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 56),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(children: [
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.5)),
              const SizedBox(height: 12),
              TextButton(onPressed: _refresh, child: const Text('重试')),
            ]),
          )
        else if (_tab == 1) ...[
          _buildStudyTab(c),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(_tab == 0 ? '遗忘曲线视图开发中，敬请期待' : '记忆持久度视图开发中，敬请期待',
                  style: TextStyle(fontSize: 13, color: c.textTertiary)),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _tabItem(String label, int idx, AppColors c) {
    final sel = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: Container(
        margin: const EdgeInsets.only(right: 18),
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: sel ? c.primaryText : Colors.transparent, width: 2)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? c.text : c.textTertiary)),
      ),
    );
  }

  // ===== 学习情况 Tab =====
  Widget _buildStudyTab(AppColors c) {
    final days = _buildDays();
    final today = days.firstWhere((d) => !d.isFuture && d.date.day == DateTime.now().day);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 视图切换
      Row(children: [
        _viewChip('认知情况', _cognitionMode, c),
        const SizedBox(width: 8),
        _viewChip('复习·新学', !_cognitionMode, c),
        const Spacer(),
        // 今日时长
        Text('今日时长 ${(_studyTimeSec / 60).round()} 分钟',
            style: TextStyle(fontSize: 12, color: c.textTertiary)),
      ]),
      const SizedBox(height: 14),
      // 柱状图
      SizedBox(height: 170, width: double.infinity, child: CustomPaint(painter: _BarPainter(days: days, cognition: _cognitionMode, textColor: c.text, gridColor: c.border))),
      const SizedBox(height: 10),
      // 图例
      Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          if (_cognitionMode) ...[
            _legend('已学', _cLearned, c),
            _legend('今日熟知', _cWellFamiliar, c),
            _legend('今日认识', _cFamiliar, c),
            _legend('今日模糊', _cVague, c),
            _legend('今日忘记', _cForget, c),
            _legend('待学', _cDue, c),
          ] else ...[
            _legend('已学(含复习)', _cLearned, c),
            _legend('新学', _cNew, c),
            _legend('待学', _cDue, c),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _cognitionMode
            ? '历史柱为当日学习词数（无法回溯当日认知细分）；今日柱按墨墨实时认知状态着色；未来柱为到期复习预测'
            : '历史柱按「最后学习日期」聚合，新学部分按「首次学习日期」近似；今日按新词标记拆分',
        style: TextStyle(fontSize: 10.5, color: c.textTertiary, height: 1.5),
      ),
      const SizedBox(height: 4),
      Text('今日已完成 ${_todayWords.length} 词 · 计划总量以墨墨 App 为准',
          style: TextStyle(fontSize: 11, color: c.textTertiary)),
      if (today.learned == 0 && _todayWords.isEmpty) ...[
        const SizedBox(height: 4),
        Text('今天还没有学习记录，打开墨墨 App 开始学习后点右上角刷新',
            style: TextStyle(fontSize: 11, color: c.textTertiary)),
      ],
    ]);
  }

  Widget _viewChip(String label, bool sel, AppColors c) {
    return GestureDetector(
      onTap: () => setState(() => _cognitionMode = label == '认知情况'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? c.primaryBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? c.primaryBorder : c.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? c.primaryText : c.textSecondary)),
      ),
    );
  }

  Widget _legend(String label, Color color, AppColors c) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
    ]);
  }
}

class _BarPainter extends CustomPainter {
  final List<_DayStat> days;
  final bool cognition;
  final Color textColor;
  final Color gridColor;

  _BarPainter({required this.days, required this.cognition, required this.textColor, required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    const axisPad = 16.0;
    final chartH = size.height - axisPad - 18;
    final n = days.length;
    final colW = size.width / n;
    final barW = colW * 0.52;
    var maxV = 1;
    for (final d in days) {
      if (d.total > maxV) maxV = d.total;
    }
    maxV = (maxV * 1.15).ceil();

    // 网格线（3 条横线）
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    for (var g = 0; g <= 2; g++) {
      final y = chartH - chartH * g / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final dateStyle = TextStyle(fontSize: 9.5, color: textColor.withValues(alpha: 0.55));
    final todayStyle = TextStyle(fontSize: 9.5, color: textColor.withValues(alpha: 0.9), fontWeight: FontWeight.w700);
    final now = DateTime.now();

    for (var i = 0; i < n; i++) {
      final d = days[i];
      final cx = colW * i + colW / 2;
      final left = cx - barW / 2;
      final total = d.total;
      final totalH = total <= 0 ? 0.0 : chartH * total / maxV;

      void seg(double yTop, double height, Color color) {
        if (height <= 0) return;
        final rrect = RRect.fromRectAndCorners(
          Rect.fromLTWH(left, yTop, barW, height),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rrect, Paint()..color = color);
      }

      double top = chartH;
      if (d.isFuture) {
        seg(top - totalH, totalH, _cDue);
      } else if (cognition) {
        // 四色堆叠（自底向上：忘记/模糊/认识/熟知？墨墨习惯：从底往上按量绘制）
        final parts = <(int, Color)>[
          (d.forget, _cForget),
          (d.vague, _cVague),
          (d.familiar, _cFamiliar),
          (d.wellFamiliar, _cWellFamiliar),
        ];
        for (final (v, color) in parts) {
          if (v <= 0) continue;
          final h = chartH * v / maxV;
          top -= h;
          seg(top, h, color);
        }
        // 今日无认知细分但已学（first_response 为空的词）：用认识蓝补齐
        final misc = d.learned - d.wellFamiliar - d.familiar - d.vague - d.forget;
        if (misc > 0) {
          final h = chartH * misc / maxV;
          top -= h;
          seg(top, h, _cFamiliar.withValues(alpha: 0.6));
        }
      } else {
        // 复习·新学：新学段（青）在上，复习段（蓝紫）在下
        final newH = chartH * d.newWords / maxV;
        final reviewH = chartH * (d.learned - d.newWords).clamp(0, 1 << 31) / maxV;
        top -= newH;
        seg(top, newH, _cNew);
        top -= reviewH;
        seg(top, reviewH, _cLearned);
      }

      // 数值标注（仅最大几根柱显示，避免拥挤：有值且 > 0 时显示）
      if (total > 0) {
        final tp = TextPainter(
          text: TextSpan(text: '$total', style: TextStyle(fontSize: 9, color: textColor.withValues(alpha: 0.7))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, (top - 13).clamp(0, chartH - 12)));
      }

      // 日期标签
      final isToday = d.date.year == now.year && d.date.month == now.month && d.date.day == now.day;
      final label = isToday
          ? '今天'
          : '${d.date.month}.${d.date.day}';
      final dp = TextPainter(
        text: TextSpan(text: label, style: isToday ? todayStyle : dateStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      dp.paint(canvas, Offset(cx - dp.width / 2, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.days != days || old.cognition != cognition || old.textColor != textColor;
}
