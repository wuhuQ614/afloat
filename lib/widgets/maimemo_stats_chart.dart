/// 墨墨学习情况统计卡（复刻墨墨 App 统计页「学习情况」柱状图）：
/// - 三 Tab：遗忘曲线 / 学习情况 / 记忆持久度（v1 完整实现「学习情况」）
/// - 学习情况：认知情况（今日四色堆叠）/ 复习·新学（新学+复习堆叠）
/// - 时间轴：过去 4 天 + 今天 + 未来 6 天；历史柱 = lastStudyDate 聚合，
///   未来柱 = nextStudyDate 聚合（待学），今日 = get_today_items 实时认知细分
library;

import 'package:flutter/material.dart';

import '../services/maimemo_service.dart';
import '../theme_colors.dart' show AppColors;
import 'stats_bar_chart.dart' show StatsBarChart, DayStat, cStatWellFamiliar, cStatFamiliar, cStatVague, cStatForget, cStatDue, cStatLearned, cStatNew;

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

  /// 构建 过去4天 + 今天 + 未来6天 共 11 列统计。
  /// 认知分层统一用 StudyRecord.last_response（该词当前记忆状态）：
  /// 历史当天的一次性认知细分 API 不提供，用当前状态近似（WELL_FAMILIAR/FAMILIAR/VAGUE/FORGET，
  /// CANCEL_WELL_FAMILIAR 与空值归入「认识」）。
  List<DayStat> _buildDays() {
    final now = DateTime.now();
    final days = <DayStat>[];
    // 按日期索引：已学（lastStudyDate）、新学（firstStudyDate）、四色（lastStudyDate × lastResponse）、待学（nextStudyDate）
    final learnedByDay = <String, int>{};
    final firstStudyByDay = <String, int>{};
    final dueByDay = <String, int>{};
    final respByDay = <String, Map<String, int>>{};
    for (final r in _records) {
      final last = r.lastStudyDate;
      if (last != null && last.length >= 10) {
        final key = last.substring(0, 10);
        learnedByDay[key] = (learnedByDay[key] ?? 0) + 1;
        final resp = switch (r.lastResponse) {
          'WELL_FAMILIAR' => 'WELL_FAMILIAR',
          'VAGUE' => 'VAGUE',
          'FORGET' => 'FORGET',
          _ => 'FAMILIAR', // FAMILIAR / CANCEL_WELL_FAMILIAR / null 均归「认识」
        };
        final bucket = respByDay.putIfAbsent(key, () => {});
        bucket[resp] = (bucket[resp] ?? 0) + 1;
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
        final st = DayStat(d)
          ..learned = learnedByDay[key] ?? 0
          ..newWords = firstStudyByDay[key] ?? 0;
        final bucket = respByDay[key];
        if (bucket != null) {
          st.wellFamiliar = bucket['WELL_FAMILIAR'] ?? 0;
          st.familiar = bucket['FAMILIAR'] ?? 0;
          st.vague = bucket['VAGUE'] ?? 0;
          st.forget = bucket['FORGET'] ?? 0;
        }
        days.add(st);
      } else if (i == 0) {
        // 今天：与历史同一数据源（lastStudyDate 聚合），保证柱形与总量一致
        final st = DayStat(d);
        st.learned = learnedByDay[key] ?? 0;
        st.newWords = _todayWords.where((w) => w.isNew).length;
        final bucket = respByDay[key];
        if (bucket != null) {
          st.wellFamiliar = bucket['WELL_FAMILIAR'] ?? 0;
          st.familiar = bucket['FAMILIAR'] ?? 0;
          st.vague = bucket['VAGUE'] ?? 0;
          st.forget = bucket['FORGET'] ?? 0;
        }
        days.add(st);
      } else {
        final st = DayStat(d, isFuture: true)
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
      SizedBox(height: 220, width: double.infinity, child: StatsBarChart(days: days, cognition: _cognitionMode, textColor: c.text, gridColor: c.border)),
      const SizedBox(height: 10),
      // 图例
      Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          if (_cognitionMode) ...[
            _legend('熟知', cStatWellFamiliar, c),
            _legend('认识', cStatFamiliar, c),
            _legend('模糊', cStatVague, c),
            _legend('忘记', cStatForget, c),
            _legend('等待复习', cStatDue, c),
          ] else ...[
            _legend('已学(含复习)', cStatLearned, c),
            _legend('新学', cStatNew, c),
            _legend('等待复习', cStatDue, c),
          ],
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _cognitionMode
            ? '每天的柱按当日学习词数绘制，四色对应该批词当前的记忆状态（熟知/认识/模糊/忘记）；灰色为未来到期待复习预测'
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

