/// 功能页：错题本 / 学习报告 / 生词本 / 答题记录 / 查词 / 默写
library;

import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/api_service.dart' as api;
import '../services/dict_service.dart';
import '../services/maimemo_service.dart';
import '../services/tts_service.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, kSuccess, kDanger, kDarkCard, AppColors;
import 'learn_page.dart' show AppScope;

const _primary = kPrimary;
const _success = kSuccess;
const _danger = kDanger;

class WrongBookPage extends StatefulWidget {
  const WrongBookPage({super.key});

  @override
  State<WrongBookPage> createState() => _WrongBookPageState();
}

class _WrongBookPageState extends State<WrongBookPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final list = s.wrongQuestions.where((w) => _filter == 'all' || (_filter == 'pending' && !w.mastered) || (_filter == 'mastered' && w.mastered)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(child: Text('错题本', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.text))),
          TextButton(onPressed: () {
            if (s.wrongQuestions.isEmpty) return;
            s.clearWrongQuestions();
          }, child: const Text('清空错题本')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          _Stat(label: '全部错题', value: '${s.wrongQuestions.length}'),
          const SizedBox(width: 24),
          _Stat(label: '待巩固', value: '${s.wrongQuestions.where((w) => !w.mastered).length}'),
          const SizedBox(width: 24),
          _Stat(label: '已掌握', value: '${s.wrongQuestions.where((w) => w.mastered).length}'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('全部')),
            ButtonSegment(value: 'pending', label: Text('待巩固')),
            ButtonSegment(value: 'mastered', label: Text('已掌握')),
          ],
          selected: {_filter},
          onSelectionChanged: (v) => setState(() => _filter = v.first),
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? const _EmptyState(icon: Icons.task_alt_rounded, title: '还没有错题，继续加油！', subtitle: '做错的题目会自动收录到这里')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: list.length,
                itemBuilder: (ctx, i) => _buildCard(list[i], s),
              ),
      ),
    ]);
  }

  Widget _buildCard(WrongItem w, AppState s) {
    final c = AppColors.of(context);
    final q = w.question;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: w.mastered ? c.successBorder : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _Tag(text: qTypeName(q.type), color: _primary),
            const SizedBox(width: 6),
            _Tag(text: levelName(q.level), color: Colors.orange),
            if (w.mastered) ...[const SizedBox(width: 6), _Tag(text: '已掌握', color: c.scoreHigh)],
            const Spacer(),
            Text('${w.score}分', style: TextStyle(fontWeight: FontWeight.bold, color: w.score >= 60 ? c.scoreHigh : c.scoreLow)),
          ]),
          const SizedBox(height: 8),
          Text(w.question.text.isEmpty ? w.question.chinese : w.question.text, style: TextStyle(fontSize: 13.5, height: 1.6, color: c.text)),
          if (w.userAnswer.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('你的作答：${w.userAnswer}', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          ],
          if (w.correctAnswer.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('正确答案：${w.correctAnswer}', style: TextStyle(fontSize: 12.5, color: c.scoreHigh)),
          ],
          const SizedBox(height: 8),
          Row(children: [
            Text('错误 ${w.wrongCount} 次 · ${_fmtTime(w.lastWrongTime)}', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
            const Spacer(),
            TextButton(onPressed: () => s.retryWrong(w), child: const Text('重新练习', style: TextStyle(fontSize: 12.5))),
            TextButton(onPressed: () => s.toggleMastered(w.id), child: Text(w.mastered ? '标记未掌握' : '标记掌握', style: const TextStyle(fontSize: 12.5))),
            TextButton(onPressed: () => s.removeWrong(w.id), child: const Text('移出', style: TextStyle(fontSize: 12.5))),
          ]),
        ]),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // 深色模式下给文字提亮一些，对比度更好
    final effectiveColor = isLight ? color : Color.lerp(color, Colors.white, 0.25) ?? color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: effectiveColor.withValues(alpha: isLight ? 0.12 : 0.22), borderRadius: BorderRadius.circular(5)),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: effectiveColor)),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
        boxShadow: [BoxShadow(color: c.shadowLight, blurRadius: 12, offset: const Offset(0, 3))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 3, height: 30, decoration: BoxDecoration(color: _primary, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.primaryText, height: 1.1)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
        ]),
      ]),
    );
  }
}

/// 统一空状态：图标 + 主标题 + 副标题
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: c.primaryBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 30, color: c.primaryText.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 16),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textSecondary)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
        ],
      ]),
    );
  }
}

String _fmtTime(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  String pad(int n) => n < 10 ? '0$n' : '$n';
  final hm = '${pad(d.hour)}:${pad(d.minute)}';
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '今天 $hm';
  final y = DateTime(now.year, now.month, now.day - 1);
  if (d.year == y.year && d.month == y.month && d.day == y.day) return '昨天 $hm';
  return '${d.month}月${d.day}日 $hm';
}

// ===== 学习报告 =====
/// 一比一还原用户提供的参考图：
///  - 顶部 header：标题"学习报告"，副标题"YYYY年M月D日 星期X"，右上角三个点菜单
///  - 4 个统计卡：圆图标背景 + 数值 + 标签，第一个卡底部带紫色指示条
///  - 最近一次模拟考试：左文字（超大分数 + 用时 + 正确率） + 右 3D E图标
///  - 最近7天答题趋势：左Y轴刻度 + 今日高亮紫色渐变柱 + 顶部数字气泡 + 右上角"题目数"下拉
///  - 历史考试记录：左分数 /Max + 中标题 + 右时间+箭头 + 右上"查看全部"
class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final records = s.studyRecords;

    // 计算统计数据
    final total = records.length;
    final sum = records.fold<int>(0, (acc, r) => acc + r.score);
    final avg = total == 0 ? 0.0 : sum / total;
    final pass = records.where((r) => r.score >= 70).length;
    final rate = total == 0 ? 0 : (pass / total * 100).round();
    final totalSec = records.fold<int>(0, (acc, r) => acc + r.duration);
    final totalMin = totalSec >= 60 ? '${(totalSec / 60).round()}min' : '${totalSec}s';

    // 今天日期字符串
    final now = DateTime.now();
    final wkday = ['一', '二', '三', '四', '五', '六', '日'][now.weekday - 1];
    final dateSubtitle = '${now.year}年${now.month}月${now.day}日 星期$wkday';

    // 检测小屏（手机端）
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 500;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 20, isMobile ? 14 : 20, isMobile ? 14 : 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== 1. 顶部 Header ==========
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('学习报告',
                          style: TextStyle(
                              fontSize: isMobile ? 20 : 24,
                              fontWeight: FontWeight.w700,
                              color: c.text,
                              height: 1.2,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 6),
                      Text(dateSubtitle,
                          style: TextStyle(
                              fontSize: 12, color: c.textTertiary, height: 1.4)),
                    ],
                  ),
                ),
                // 右上角三个点菜单
                _DotsMenu(onClear: s.studyRecords.isNotEmpty ? () => s.clearStudyRecords() : null),
              ],
            ),
            SizedBox(height: isMobile ? 14 : 20),

            // ========== 2. 4 个统计卡（手机端 2x2 网格，桌面端一行 4 列）==========
            if (isMobile) ...[
              Row(
                children: [
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.edit_note_rounded,
                    value: '$total',
                    label: '累计练习',
                    isActive: true,
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.star_rounded,
                    value: total == 0 ? '-' : avg.toStringAsFixed(1),
                    label: '平均得分',
                  )),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.gps_fixed_rounded,
                    value: total == 0 ? '-' : '$rate%',
                    label: '达标率(≥70分)',
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.schedule_rounded,
                    value: totalMin,
                    label: '学习时长',
                  )),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.edit_note_rounded,
                    value: '$total',
                    label: '累计练习',
                    isActive: true,
                  )),
                  const SizedBox(width: 14),
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.star_rounded,
                    value: total == 0 ? '-' : avg.toStringAsFixed(1),
                    label: '平均得分',
                  )),
                  const SizedBox(width: 14),
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.gps_fixed_rounded,
                    value: total == 0 ? '-' : '$rate%',
                    label: '达标率(≥70分)',
                  )),
                  const SizedBox(width: 14),
                  Expanded(
                      child: _KpiCard(
                    c: c,
                    icon: Icons.schedule_rounded,
                    value: totalMin,
                    label: '学习时长',
                  )),
                ],
              ),
            ],
            SizedBox(height: isMobile ? 12 : 16),

            // ========== 3. 最近一次模拟考试 ==========
            _PaperCard(c: c, s: s),
            const SizedBox(height: 16),

            // ========== 4. 最近7天答题趋势 ==========
            _TrendCard(c: c, records: records),
            const SizedBox(height: 16),

            // ========== 5. 历史考试记录 ==========
            _HistoryCard(c: c, s: s),
          ],
        ),
      ),
    );
  }
}

// =========================================================
//  1. 顶部三个点菜单
// =========================================================
class _DotsMenu extends StatelessWidget {
  final VoidCallback? onClear;
  const _DotsMenu({this.onClear});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'clear' && onClear != null) onClear!();
      },
      color: c.card,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'clear',
          enabled: onClear != null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Text('清空记录',
              style: TextStyle(
                  fontSize: 13,
                  color: onClear != null ? c.text : c.textTertiary)),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.more_horiz_rounded,
            size: 22, color: c.textSecondary),
      ),
    );
  }
}

// =========================================================
//  2. KPI 统计卡（4 张同形状，首张带底栏高亮）
// =========================================================
class _KpiCard extends StatelessWidget {
  final AppColors c;
  final IconData icon;
  final String value;
  final String label;
  final bool isActive;
  const _KpiCard(
      {required this.c,
      required this.icon,
      required this.value,
      required this.label,
      this.isActive = false});

  @override
  Widget build(BuildContext context) {
    final isLight = c.isLight;
    // 按图：纯白卡 + 柔和圆角 + 轻阴影
    final bg = isLight ? Colors.white : const Color(0xFF2A2A32);
    final iconBg = (c.isLight
            ? const Color(0xFFF3EEFF)
            : const Color(0xFF3D3258))
        .withValues(alpha: isLight ? 1.0 : 0.55);
    final iconColor = c.primaryText;

    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 22),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: isLight ? 0.035 : 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: -6),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部圆形图标背景
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(height: 14),
              Text(value,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                      height: 1.05,
                      letterSpacing: -0.3)),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: c.textSecondary,
                      height: 1.2)),
            ],
          ),
        ),
        // 第一张卡底部紫色小指示条
        if (isActive)
          Positioned(
            bottom: -1,
            child: Container(
              width: 34,
              height: 3.5,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  c.gradientEnd.withValues(alpha: 0.9),
                  c.gradientStart.withValues(alpha: 0.9),
                ]),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: c.primary.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// =========================================================
//  3. 最近一次模拟考试卡
// =========================================================
class _PaperCard extends StatelessWidget {
  final AppColors c;
  final AppState s;
  const _PaperCard({required this.c, required this.s});

  String _fmtDuration(int sec) {
    final m = sec ~/ 60;
    final r = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = c.isLight;
    final bg = isLight ? Colors.white : const Color(0xFF2A2A32);

    // 检测小屏
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 500;

    // 取"最近一次"：优先 currentExamResult，否则 examHistory 最近一条
    final cur = s.currentExamResult;
    final lastHist = s.examHistory.isEmpty ? null : s.examHistory.first;
    final bool hasCur = cur != null;
    final String title = hasCur
        ? cur.paper.title
        : (lastHist?.title.isEmpty ?? true ? '暂无考试记录' : lastHist!.title);
    final int totalScore = hasCur ? cur.totalScore : (lastHist?.totalScore ?? 0);
    final int maxScore = hasCur ? cur.maxScore : (lastHist?.maxScore ?? 150);
    final int durationSec = hasCur ? cur.durationSec : 0;
    final double pct =
        maxScore == 0 ? 0 : totalScore / maxScore;
    final String correctRate = '${(pct * 100).toStringAsFixed(1)}%';
    final bool hasExam = hasCur || lastHist != null;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 22, isMobile ? 16 : 20, isMobile ? 12 : 16, isMobile ? 16 : 20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.035 : 0.22),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: -6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text('最近一次模拟考试',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                  height: 1.2)),
          SizedBox(height: isMobile ? 12 : 16),
          // 手机端：垂直布局；桌面端：左右布局
          if (isMobile) ...[
            // 分数
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(hasExam ? '$totalScore' : '--',
                    style: TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w800,
                        color: c.primaryText,
                        height: 0.95,
                        letterSpacing: -1)),
                const SizedBox(width: 4),
                Text('/$maxScore 分',
                    style: TextStyle(
                        fontSize: 13,
                        color: c.textTertiary,
                        height: 1.2)),
              ],
            ),
            const SizedBox(height: 8),
            Text(hasExam ? title : '暂无，考完一次即可在这里查看',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.text,
                    height: 1.3)),
            const SizedBox(height: 10),
            // 用时 + 正确率
            Row(children: [
              Icon(Icons.schedule_rounded,
                  size: 14, color: c.textTertiary),
              const SizedBox(width: 4),
              Text(hasExam ? '用时 ${_fmtDuration(durationSec)}' : '用时 --:--',
                  style: TextStyle(
                      fontSize: 12, color: c.textTertiary)),
              const SizedBox(width: 14),
              Icon(Icons.check_circle_outline_rounded,
                  size: 14, color: c.textTertiary),
              const SizedBox(width: 4),
              Text('正确率 $correctRate',
                  style: TextStyle(
                      fontSize: 12, color: c.textTertiary)),
            ]),
            // 查看成绩分析
            if (hasCur) ...[
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => s.setPage(11),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('查看成绩分析',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: c.primaryText,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_rounded,
                        size: 14, color: c.primaryText),
                  ],
                ),
              ),
            ],
          ] else ...[
            // 桌面端：左右布局
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左：分数 + 信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(hasExam ? '$totalScore' : '--',
                              style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.w800,
                                  color: c.primaryText,
                                  height: 0.95,
                                  letterSpacing: -1)),
                          const SizedBox(width: 4),
                          Text('/$maxScore 分',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: c.textTertiary,
                                  height: 1.2)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(hasExam ? title : '暂无，考完一次即可在这里查看',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                              height: 1.3)),
                      const SizedBox(height: 14),
                      // 用时 + 正确率
                      Row(children: [
                        Icon(Icons.schedule_rounded,
                            size: 14, color: c.textTertiary),
                        const SizedBox(width: 4),
                        Text(hasExam ? '用时 ${_fmtDuration(durationSec)}' : '用时 --:--',
                            style: TextStyle(
                                fontSize: 12, color: c.textTertiary)),
                        const SizedBox(width: 14),
                        Icon(Icons.check_circle_outline_rounded,
                            size: 14, color: c.textTertiary),
                        const SizedBox(width: 4),
                        Text('正确率 $correctRate',
                            style: TextStyle(
                                fontSize: 12, color: c.textTertiary)),
                      ]),
                    ],
                  ),
                ),
                // 右：3D E 字图标 + 查看成绩分析
                SizedBox(
                  width: 146,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // 3D E 字（紫色渐变玻璃方块 + 光晕）
                      SizedBox(
                        height: 110,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 外层光环
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    c.primary.withValues(alpha: 0.22),
                                    c.primary.withValues(alpha: 0.0),
                                  ],
                                  stops: const [0.3, 1.0],
                                ),
                              ),
                            ),
                            // 玻璃方块
                            Transform.rotate(
                              angle: -0.18,
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      (c.isLight
                                              ? const Color(0xFFE9DFFF)
                                              : const Color(0xFF58477A))
                                          .withValues(alpha: 0.85),
                                      (c.isLight
                                              ? const Color(0xFFC8B8FA)
                                              : const Color(0xFF7D66B3))
                                          .withValues(alpha: 0.82),
                                    ],
                                  ),
                                  border: Border.all(
                                      color: (c.isLight
                                              ? Colors.white
                                              : Colors.white.withValues(
                                                  alpha: 0.3))
                                          .withValues(alpha: 0.85),
                                      width: 1.5),
                                  boxShadow: [
                                    BoxShadow(
                                        color: c.primary.withValues(alpha: 0.28),
                                        blurRadius: 22,
                                        offset: const Offset(2, 8)),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: Text('E',
                                    style: TextStyle(
                                        fontSize: 48,
                                        fontWeight: FontWeight.w800,
                                        color: (c.isLight
                                                ? const Color(0xFF7E5CE8)
                                                : const Color(0xFFD9CEFF))
                                            .withValues(alpha: 0.92),
                                        letterSpacing: -1)),
                              ),
                            ),
                            // 右下侧环
                            Positioned(
                              right: 6,
                              bottom: 8,
                              child: Container(
                                width: 86,
                                height: 6,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  gradient: LinearGradient(
                                    colors: [
                                      c.primary.withValues(alpha: 0.0),
                                      c.primary.withValues(alpha: 0.55),
                                      c.primary.withValues(alpha: 0.0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 查看成绩分析
                      if (hasCur) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => s.setPage(11),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('查看成绩分析',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: c.primaryText,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 2),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 14, color: c.primaryText),
                            ],
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =========================================================
//  4. 最近 7 天答题趋势
// =========================================================
class _TrendCard extends StatelessWidget {
  final AppColors c;
  final List<StudyRecord> records;
  const _TrendCard({required this.c, required this.records});

  @override
  Widget build(BuildContext context) {
    final isLight = c.isLight;
    final bg = isLight ? Colors.white : const Color(0xFF2A2A32);

    // 构建7天数据（最近7天，今天是最后一条）
    final days = <({String label, int count, bool isToday})>[];
    final now = DateTime.now();
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day - i);
      final start = DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
      final end = start + 86400000;
      final cnt = records.where((r) => r.timestamp >= start && r.timestamp < end).length;
      days.add((
        label: '${d.month}/${d.day}',
        count: cnt,
        isToday: (i == 0),
      ));
    }
    final maxCount = days.fold<int>(1, (m, x) => max(m, x.count));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 20, 18, 18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.035 : 0.22),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: -6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 右上角下拉
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('最近 7 天答题趋势',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                      height: 1.2)),
              const Spacer(),
              // 题目数下拉
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.isLight
                      ? const Color(0xFFF3EEFF)
                      : const Color(0xFF3D3258),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('题目数',
                        style: TextStyle(
                            fontSize: 12,
                            color: c.primaryText,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 3),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: c.primaryText),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // 左 Y 轴刻度 + 柱状图区
          SizedBox(
            height: 190,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Y 轴刻度（3 档：100/200/300，与 max 动态适应）
                SizedBox(
                  width: 42,
                  height: 160,
                  child: _YAxisTicks(c: c, maxV: maxCount),
                ),
                const SizedBox(width: 6),
                // 7 列柱状图
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final d in days)
                        Expanded(
                          child: _BarCell(
                            c: c,
                            label: d.label,
                            count: d.count,
                            maxCount: maxCount,
                            isToday: d.isToday,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Y 轴刻度：300, 200, 100（与数据 max 对齐，数据级低时自动 4 档）
class _YAxisTicks extends StatelessWidget {
  final AppColors c;
  final int maxV;
  const _YAxisTicks({required this.c, required this.maxV});

  @override
  Widget build(BuildContext context) {
    final steps = <String>[];
    final realMax = maxV < 100 ? 100 : (maxV < 300 ? 300 : ((maxV / 100).ceil() * 100));
    // 3 档：100/200/300 或按 realMax 自动算
    final n = 3;
    final step = realMax ~/ n;
    for (var i = n; i >= 1; i--) {
      steps.add('${step * i}');
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(s,
                style: TextStyle(
                    fontSize: 10.5, color: c.textTertiary, height: 1)),
          ),
      ],
    );
  }
}

/// 单根柱：今日高亮渐变紫 + 数字气泡，其它浅紫
class _BarCell extends StatelessWidget {
  final AppColors c;
  final String label;
  final int count;
  final int maxCount;
  final bool isToday;
  const _BarCell({
    required this.c,
    required this.label,
    required this.count,
    required this.maxCount,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final chartH = 150.0;
    final ratio = count == 0 ? 0.0 : (count / max(1, maxCount));
    final barH = count == 0 ? 4.0 : (6 + ratio * (chartH - 10));

    final lightBar = c.isLight
        ? const Color(0xFFE4DCFF)
        : const Color(0xFF463B62);
    final darkBarTop = c.isLight
        ? const Color(0xFFA48BFF)
        : const Color(0xFFC7B5FF);
    final darkBarBot = c.isLight
        ? const Color(0xFF7E5CE8)
        : const Color(0xFF9378EA);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 数字气泡（仅非 0 显示，今日额外高亮）
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: isToday
                  ? (c.isLight
                      ? const Color(0xFF8B6EF5)
                      : const Color(0xFFA78BFA))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isToday ? Colors.white : c.textTertiary,
                    height: 1)),
          )
        else
          const SizedBox(height: 20),
        // 柱
        SizedBox(
          height: chartH,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: LayoutBuilder(builder: (context, cons) {
              final w = (cons.maxWidth * 0.52).clamp(10.0, 28.0);
              return Container(
                width: w,
                height: barH,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                  gradient: isToday
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [darkBarTop, darkBarBot],
                        )
                      : null,
                  color: isToday ? null : lightBar,
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        // X 轴日期标签
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: isToday ? c.primaryText : c.textTertiary,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                height: 1)),
      ],
    );
  }
}

// =========================================================
//  5. 历史考试记录
// =========================================================
class _HistoryCard extends StatelessWidget {
  final AppColors c;
  final AppState s;
  const _HistoryCard({required this.c, required this.s});

  String _fmtForHistory(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    String pad(int n) => n < 10 ? '0$n' : '$n';
    if (d.year == now.year &&
        d.month == now.month &&
        d.day == now.day) {
      return '今天 ${pad(d.hour)}:${pad(d.minute)}';
    }
    final y = DateTime(now.year, now.month, now.day - 1);
    if (d.year == y.year && d.month == y.month && d.day == y.day) {
      return '昨天 ${pad(d.hour)}:${pad(d.minute)}';
    }
    return '${d.month}月${d.day}日 ${pad(d.hour)}:${pad(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = c.isLight;
    final bg = isLight ? Colors.white : const Color(0xFF2A2A32);

    // 列表：最近一次 examHistory 列表
    final list = s.examHistory;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 20, 14, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.035 : 0.22),
              blurRadius: 24,
              offset: const Offset(0, 8),
              spreadRadius: -6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 查看全部
          Row(
            children: [
              Text('历史考试记录',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.text,
                      height: 1.2)),
              const Spacer(),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // 预留：跳转全部历史（暂无独立页）
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('查看全部',
                        style: TextStyle(
                            fontSize: 12, color: c.textTertiary, height: 1.2)),
                    const SizedBox(width: 1),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 11, color: c.textTertiary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 列表
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text('暂无历史考试，快去参加一次模拟考试吧~',
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary)),
              ),
            )
          else
            for (var i = 0; i < list.length; i++) ...[
              _HistoryRow(
                c: c,
                score: list[i].totalScore,
                maxScore: list[i].maxScore,
                title:
                    list[i].title.isEmpty ? '模拟全卷' : list[i].title,
                time: _fmtForHistory(list[i].submittedAt),
              ),
              if (i < list.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 44),
                  child: Divider(
                      height: 1,
                      thickness: 1,
                      color: c.divider.withValues(alpha: 0.6)),
                ),
            ],
        ],
      ),
    );
  }
}

/// 历史记录单行： 分数 /Max ｜ 标题 ｜ 时间 + 箭头
class _HistoryRow extends StatelessWidget {
  final AppColors c;
  final int score;
  final int maxScore;
  final String title;
  final String time;
  const _HistoryRow({
    required this.c,
    required this.score,
    required this.maxScore,
    required this.title,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    final pct = maxScore == 0 ? 0.0 : score / maxScore;
    // 颜色：>=70% 橙红色偏亮，低分红色
    late Color scoreColor;
    if (pct >= 0.7) {
      scoreColor = c.isLight ? const Color(0xFFFB7A1C) : const Color(0xFFFF9955);
    } else if (pct >= 0.4) {
      scoreColor = c.isLight ? const Color(0xFFF05A2C) : const Color(0xFFFF7B52);
    } else {
      scoreColor = c.isLight ? const Color(0xFFE84242) : const Color(0xFFFF6565);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 分数（橙红色） / Max
          Text('$score',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: scoreColor,
                  height: 1.1)),
          const SizedBox(width: 2),
          Text('/$maxScore',
              style: TextStyle(
                  fontSize: 11.5, color: c.textTertiary, height: 1.1)),
          const SizedBox(width: 18),
          // 标题
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: c.text,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          // 时间 + 右箭头
          Text(time,
              style: TextStyle(
                  fontSize: 11.5, color: c.textTertiary, height: 1.2)),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_ios_rounded,
              size: 11.5, color: c.textTertiary),
        ],
      ),
    );
  }
}

// ===== 生词本 =====
class WordBookPage extends StatefulWidget {
  const WordBookPage({super.key});

  @override
  State<WordBookPage> createState() => _WordBookPageState();
}

class _WordBookPageState extends State<WordBookPage> {
  int _flashIdx = 0;
  bool _reviewing = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(child: Text('生词本', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.text))),
          if (s.wordbook.isNotEmpty)
            OutlinedButton(onPressed: () => setState(() { _reviewing = true; _flashIdx = 0; }), child: const Text('开始复习')),
          const SizedBox(width: 8),
          if (s.wordbook.isNotEmpty)
            TextButton(onPressed: () {
              s.clearWordBook();
              setState(() {});
            }, child: const Text('清空')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          _Stat(label: '已收藏单词', value: '${s.wordbook.length}'),
          const SizedBox(width: 24),
          _Stat(label: '已复习次数', value: '${s.wordbook.fold<int>(0, (a, w) => a + w.reviewCount)}'),
        ]),
      ),
      Expanded(
        child: _reviewing
            ? _buildFlashcard(s)
            : s.wordbook.isEmpty
                ? const _EmptyState(icon: Icons.star_outline_rounded, title: '还没有收藏生词', subtitle: '做题或查词时点击收藏即可加入')
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    itemCount: s.wordbook.length,
                    itemBuilder: (ctx, i) {
                      final w = s.wordbook[i];
                      final ph = DictService.lookup(w.word)?.phonetic ?? '';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          title: Row(children: [
                            Text(w.word, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                            if (ph.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text('/$ph/', style: TextStyle(fontSize: 12, color: c.textTertiary), overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ]),
                          subtitle: Text(w.translation, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('复习 ${w.reviewCount} 次', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                            if (TtsService.instance.available)
                              IconButton(
                                icon: Icon(Icons.volume_up, size: 16, color: c.primaryText),
                                tooltip: '发音',
                                onPressed: () => TtsService.instance.speakWord(w.word),
                              ),
                            IconButton(icon: Icon(Icons.close, size: 16, color: c.textTertiary), onPressed: () { s.removeFromWordBook(w.word); }),
                          ]),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }

  Widget _buildFlashcard(AppState s) {
    final c = AppColors.of(context);
    if (_flashIdx >= s.wordbook.length) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('复习完成！', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.text)),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => setState(() => _reviewing = false), child: const Text('返回列表')),
        ]),
      );
    }
    final w = s.wordbook[_flashIdx];
    final ph = DictService.lookup(w.word)?.phonetic ?? '';
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(children: [
              Text('${_flashIdx + 1}/${s.wordbook.length}', style: TextStyle(fontSize: 12, color: c.textTertiary)),
              const SizedBox(height: 16),
              Text(w.word, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: c.text)),
              if (ph.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('/$ph/', style: TextStyle(fontSize: 14, color: c.textTertiary)),
              ],
              const SizedBox(height: 12),
              Text(w.translation, style: TextStyle(fontSize: 15, color: c.textSecondary)),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (TtsService.instance.available)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                onPressed: () => TtsService.instance.speakWord(w.word),
                icon: Icon(Icons.volume_up, color: c.primaryText),
                tooltip: '发音',
              ),
            ),
          OutlinedButton(
            onPressed: () {
              s.wordbook[_flashIdx] = WordBookItem(
                  word: w.word, translation: w.translation, reviewCount: w.reviewCount + 1, lastReview: DateTime.now().millisecondsSinceEpoch, addedAt: w.addedAt);
              setState(() => _flashIdx++);
            },
            child: const Text('知道了'),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => setState(() => _flashIdx++),
            child: const Text('下一个'),
          ),
        ]),
      ]),
    );
  }
}

// ===== 答题记录（单词记录本） =====
class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String _search = '';
  String _sort = 'freq';
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final entries = s.recordedWords.entries.toList();
    final fromCount = <String>{};
    for (final e in entries) {
      fromCount.addAll(e.value.sources);
    }
    final filtered = entries.where((e) => _search.isEmpty || e.key.contains(_search.toLowerCase())).toList();
    if (_sort == 'alpha') filtered.sort((a, b) => a.key.compareTo(b.key));
    if (_sort == 'newest') filtered.sort((a, b) => b.value.lastSeen.compareTo(a.value.lastSeen));
    if (_sort == 'freq') filtered.sort((a, b) => b.value.count.compareTo(a.value.count));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(child: Text('答题记录', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.text))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _primary),
            onPressed: _generating ? null : () => _generateFromWords(s),
            child: _generating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('用选中单词 AI 出题'),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: () => s.clearRecords(), child: const Text('清空记录')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Text('总单词 ${entries.length}', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(width: 20),
          Text('已选 ${s.recordsSelected.length}', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(width: 20),
          Text('来自 $fromCount 道题', style: TextStyle(fontSize: 13, color: c.textSecondary)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(hintText: '搜索单词...', isDense: true, border: OutlineInputBorder(), hintStyle: TextStyle(color: c.inputHint)),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _sort,
            isDense: true,
            items: const [
              DropdownMenuItem(value: 'freq', child: Text('按频率排序')),
              DropdownMenuItem(value: 'alpha', child: Text('按字母排序')),
              DropdownMenuItem(value: 'newest', child: Text('按最新')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? 'freq'),
          ),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: () => _selectTop10(s), child: const Text('选前10高频', style: TextStyle(fontSize: 12))),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: () {
            s.recordsSelected.addAll(entries.map((e) => e.key));
            s.touch();
            setState(() {});
          }, child: const Text('全选', style: TextStyle(fontSize: 12))),
          const SizedBox(width: 6),
          OutlinedButton(onPressed: () {
            s.recordsSelected.clear();
            s.touch();
            setState(() {});
          }, child: const Text('取消全选', style: TextStyle(fontSize: 12))),
        ]),
      ),
      Expanded(
        child: filtered.isEmpty
            ? const _EmptyState(icon: Icons.bookmark_border_rounded, title: '暂无答题记录', subtitle: '做题后点击题旁的书签按钮可记录单词')
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final e = filtered[i];
                  final checked = s.recordsSelected.contains(e.key);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: checked ? c.primaryBorder : Colors.transparent),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Checkbox(
                        value: checked,
                        onChanged: (v) {
                          if (v == true) {
                            s.recordsSelected.add(e.key);
                          } else {
                            s.recordsSelected.remove(e.key);
                          }
                          s.touch();
                          setState(() {});
                        },
                      ),
                      title: Text(e.key, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
                      subtitle: Text('出现 ${e.value.count} 次 · 来自 ${e.value.sources.length} 道题', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  void _selectTop10(AppState s) {
    final sorted = s.recordedWords.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));
    for (final e in sorted.take(10)) {
      s.recordsSelected.add(e.key);
    }
    s.touch();
    setState(() {});
  }

  Future<void> _generateFromWords(AppState s) async {
    if (s.recordsSelected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先勾选单词再出题'), behavior: SnackBarBehavior.floating));
      return;
    }
    if (!s.apiConfig.ready) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置 AI 接口'), behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _generating = true);
    final wordList = s.recordsSelected.take(20).join('、');
    final count = min(s.recordsSelected.length, 5);
    final systemPrompt = '你是一个英语出题专家。请使用以下单词生成 $count 道翻译题：$wordList\n\n' +
        '要求：\n' +
        '1. 每道题必须包含至少 2-3 个给定单词\n' +
        '2. 题目难度适中，适合英语学习者\n' +
        '3. 翻译方向为中译英（题目为中文，答案为英文）\n\n' +
        '请以JSON数组格式返回，格式如下：\n' +
        '[{"chinese": "中文内容", "english": "英文内容", "knowledge": ["知识点1"]}]\n' +
        '只返回JSON数组，不要其他内容。';
    final reply = await api.ApiService.callAI(
      [
        {'role': 'user', 'content': '请用以下单词出题'}
      ],
      systemPrompt,
      config: s.apiConfig,
      maxTokens: 8192,
      extraParams: api.ApiService.noThinkingParams(s.apiConfig.model),
    );
    setState(() => _generating = false);
    if (reply != null) {
      final list = api.ApiService.extractJsonArray(reply);
      if (list != null && list.isNotEmpty) {
        s.generatedQuestions = list.map((q) => s.normalizeGeneratedQuestion(q, QType.translation, 'medium')).toList();
        s.generatedQuestionIdx = 0;
        s.loadGeneratedQuestion();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已生成 ${list.length} 道题目（基于记录单词）'), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('生成失败，请检查 API 配置后重试'), behavior: SnackBarBehavior.floating));
  }
}

// ===== 查词 =====
class DictionaryPage extends StatefulWidget {
  const DictionaryPage({super.key});

  @override
  State<DictionaryPage> createState() => _DictionaryPageState();
}

class _DictionaryPageState extends State<DictionaryPage> {
  final TextEditingController _ctrl = TextEditingController();
  String? _result;
  String? _foundWord; // 本地词库命中的单词（结构化展示）
  DictEntry? _foundEntry;
  MaimemoWordLookup? _maimemoLookup; // 墨墨开放 API 查词结果
  bool _searching = false;
  List<String> _collocations = [];
  List<String> _synonyms = [];
  List<String> _mnemonics = []; // AI 生成的助记
  List<Map<String, String>> _examples = []; // [{en, zh}]
  bool _loadingExtras = false;

  @override
  void initState() {
    super.initState();
    // 提前初始化 TTS，就绪后刷新以显示发音按钮
    TtsService.instance.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final isMobile = s.uiMode == 'mobile';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 20, isMobile ? 14 : 20, isMobile ? 14 : 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('单词查询', style: TextStyle(fontSize: isMobile ? 17 : 20, fontWeight: FontWeight.bold, color: c.text)),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: c.cardAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Row(children: [
              const SizedBox(width: 14),
              Icon(Icons.search_rounded, size: 20, color: c.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  style: TextStyle(color: c.text),
                  decoration: InputDecoration(
                    hintText: '输入英文单词或中文词语...',
                    isDense: true,
                    filled: true,
                    fillColor: c.cardAlt,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintStyle: TextStyle(color: c.inputHint),
                    suffixIcon: _ctrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.cancel_rounded, size: 18, color: c.textTertiary),
                            onPressed: () {
                              _ctrl.clear();
                              setState(() { _foundEntry = null; _foundWord = null; _result = null; _maimemoLookup = null; _mnemonics = []; });
                            },
                          )
                        : null,
                  ),
                  onSubmitted: (_) => _search(s),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _searching ? null : () => _search(s),
                  child: const Text('查询'),
                ),
              ),
            ]),
          ),
        ]),
      ),
      Expanded(child: _buildResult(s)),
    ]);
  }

  Widget _buildResult(AppState s) {
    final c = AppColors.of(context);
    if (_searching) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: _primary)),
        const SizedBox(height: 12),
        Text('查询中...', style: TextStyle(fontSize: 13, color: c.textTertiary)),
      ]));
    }
    if (_result == null && _foundEntry == null && _maimemoLookup == null) {
      return _EmptyState(
        icon: Icons.search_rounded,
        title: '输入单词开始查询',
        subtitle: s.dictSource == 'maimemo'
            ? '墨墨模式下仅支持英文单词查询，结果由墨墨提供'
            : '英文优先匹配本地词库，中文走 AI 翻译',
      );
    }
    final entry = _foundEntry;
    final word = _foundWord;
    final isMobile = s.uiMode == 'mobile';
    // 墨墨查询结果：优先展示其释义/例句/助记（墨墨不提供音标，音标取本地词典）
    final maimemo = _maimemoLookup;
    final phonetic = entry?.phonetic.isNotEmpty == true ? entry!.phonetic : '';
    final maimemoDefs = (maimemo != null && maimemo.definitions.isNotEmpty) ? maimemo.definitions : null;
    // 例句：墨墨模式只取墨墨 API 数据；AI 模式用 AI 生成结果
    final exampleList = maimemo != null
        ? maimemo.examples.map((e) => {'en': e.content, 'zh': e.translation}).toList()
        : _examples;
    // 助记：墨墨模式只取墨墨 API 数据；AI 模式用 AI 生成结果
    final noteList = maimemo != null
        ? maimemo.notes.map((n) => n.content).toList()
        : _mnemonics;

    final body = (entry != null || maimemo != null) && word != null
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 单词头部：单词 + 音标 + 发音
              Row(children: [
                Flexible(
                  child: Text(word, style: TextStyle(fontSize: isMobile ? 24 : 28, fontWeight: FontWeight.bold, color: c.text), overflow: TextOverflow.ellipsis),
                ),
                if (TtsService.instance.available)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: IconButton(
                      icon: Icon(Icons.volume_up_rounded, size: 22, color: _primary),
                      tooltip: '发音',
                      onPressed: () => TtsService.instance.speakWord(word),
                    ),
                  ),
              ]),
              if (phonetic.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('/$phonetic/', style: TextStyle(fontSize: 15, color: c.textTertiary)),
                ),
              const SizedBox(height: 16),
              // 词性、释义（墨墨优先，AI/词典兜底）
              if (maimemoDefs != null)
                ...maimemoDefs.map((d) => _InfoRow(
                      label: d.tags.isNotEmpty ? d.tags.join('、') : '释义',
                      value: d.content,
                      c: c,
                    ))
              else ...[
                if (entry != null && entry.pos.isNotEmpty) _InfoRow(label: '词性', value: entry.pos, c: c),
                if (entry != null && entry.translation.isNotEmpty) _InfoRow(label: '释义', value: entry.translation, c: c),
                if (entry != null && entry.other.isNotEmpty) _InfoRow(label: '补充', value: entry.other, c: c),
              ],
              const SizedBox(height: 16),
              Divider(height: 1, color: c.divider),
              const SizedBox(height: 12),
              // 手机端：垂直布局；桌面端：左右两栏
              if (isMobile) ...[
                // 例句
                Text('例句', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                if (_loadingExtras && exampleList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (exampleList.isEmpty)
                  Text('暂无例句', style: TextStyle(fontSize: 13, color: c.textTertiary))
                else
                  ...exampleList.map((ex) => Column(
                        children: [
                          _ExampleItem(en: ex['en'] ?? '', zh: ex['zh'] ?? '', c: c),
                          const SizedBox(height: 8),
                        ],
                      )),
                const SizedBox(height: 16),
                // 助记
                Text('助记', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                if (_loadingExtras && noteList.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (noteList.isEmpty)
                  Text('暂无助记', style: TextStyle(fontSize: 13, color: c.textTertiary))
                else
                  ...noteList.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: c.primaryBg.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(m, style: TextStyle(fontSize: 13, height: 1.5, color: c.text)),
                        ),
                      )),
                const SizedBox(height: 16),
                // 常见搭配
                Text('常见搭配', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 10),
                if (_loadingExtras)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _collocations.isEmpty
                        ? [_Chip(text: '暂无', c: null)]
                        : _collocations.map((col) => _Chip(text: col, c: c)).toList(),
                  ),
                const SizedBox(height: 16),
                // 同义词
                Text('同义词', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 10),
                if (_loadingExtras)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _synonyms.isEmpty
                        ? [_Chip(text: '暂无', c: null)]
                        : _synonyms.map((syn) => _Chip(text: syn, c: c)).toList(),
                  ),
              ] else ...[
                // 桌面端：左右两栏布局
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 左侧：例句
                  Expanded(
                    flex: 5,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('例句', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                      const SizedBox(height: 8),
                      if (_loadingExtras && exampleList.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (exampleList.isEmpty)
                        Text('暂无例句', style: TextStyle(fontSize: 13, color: c.textTertiary))
                      else
                        ...exampleList.map((ex) => Column(
                              children: [
                                _ExampleItem(en: ex['en'] ?? '', zh: ex['zh'] ?? '', c: c),
                                const SizedBox(height: 8),
                              ],
                            )),
                      const SizedBox(height: 16),
                      // 助记
                      Text('助记', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                      const SizedBox(height: 8),
                      if (_loadingExtras && noteList.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (noteList.isEmpty)
                        Text('暂无助记', style: TextStyle(fontSize: 13, color: c.textTertiary))
                      else
                        ...noteList.map((m) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: c.primaryBg.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(m, style: TextStyle(fontSize: 13, height: 1.5, color: c.text)),
                              ),
                            )),
                    ]),
                  ),
                  // 右侧分隔线
                  Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 20), color: c.divider),
                  // 右侧：搭配与同义词
                  Expanded(
                    flex: 5,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('常见搭配', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                      const SizedBox(height: 10),
                      if (_loadingExtras)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _collocations.isEmpty
                              ? [_Chip(text: '暂无', c: null)]
                              : _collocations.map((col) => _Chip(text: col, c: c)).toList(),
                        ),
                      const SizedBox(height: 20),
                      Text('同义词', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                      const SizedBox(height: 10),
                      if (_loadingExtras)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _synonyms.isEmpty
                              ? [_Chip(text: '暂无', c: null)]
                              : _synonyms.map((syn) => _Chip(text: syn, c: c)).toList(),
                        ),
                    ]),
                  ),
                ]),
              ],
              const SizedBox(height: 16),
              // 加入生词本按钮
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primary,
                    side: BorderSide(color: _primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final w = word.toLowerCase();
                    final defText = maimemoDefs != null
                        ? maimemoDefs.map((d) => d.content).join('；')
                        : (entry?.translation ?? '');
                    s.addToWordBook(w, defText);
                    setState(() {});
                  },
                  icon: const Icon(Icons.star_outline_rounded, size: 18),
                  label: const Text('加入生词本'),
                ),
              ),
            ])
          : Text(_result ?? '', style: TextStyle(fontSize: 14, height: 1.7, color: c.text));
    if (isMobile) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
        child: body,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
      child: body,
    );
  }

  List<String> _buildCollocations(String word) {
    final map = <String, List<String>>{
      'with': ['with you', 'with him', 'with her', 'with it', 'with them'],
      'go': ['go home', 'go to school', 'go shopping', 'go out'],
      'make': ['make a decision', 'make progress', 'make friends', 'make sense'],
      'take': ['take action', 'take care', 'take place', 'take time'],
      'get': ['get up', 'get along', 'get ready', 'get used to'],
      'have': ['have a look', 'have fun', 'have trouble', 'have to'],
      'do': ['do homework', 'do exercise', 'do well', 'do one\'s best'],
      'come': ['come true', 'come up', 'come back', 'come from'],
      'look': ['look at', 'look for', 'look after', 'look forward to'],
      'put': ['put on', 'put off', 'put up', 'put down'],
    };
    return map[word.toLowerCase()] ?? ['搭配 1', '搭配 2', '搭配 3'];
  }

  List<String> _buildSynonyms(String word) {
    final map = <String, List<String>>{
      'with': ['along with', 'together with', 'accompanied by'],
      'go': ['proceed', 'move', 'travel', 'depart'],
      'make': ['create', 'produce', 'build', 'construct'],
      'take': ['grab', 'seize', 'acquire', 'obtain'],
      'get': ['obtain', 'receive', 'acquire', 'gain'],
      'have': ['possess', 'own', 'hold', 'contain'],
      'do': ['perform', 'execute', 'accomplish', 'achieve'],
      'come': ['arrive', 'approach', 'appear', 'emerge'],
      'look': ['gaze', 'stare', 'glance', 'observe'],
      'put': ['place', 'set', 'lay', 'position'],
    };
    return map[word.toLowerCase()] ?? ['同义词 1', '同义词 2', '同义词 3'];
  }

  Widget _InfoRow({required String label, required String value, required AppColors c}) {
    // 将字面量 \n 替换为实际换行
    final displayValue = value.replaceAll(r'\n', '\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 50, child: Text('$label：', style: TextStyle(fontSize: 14, color: c.textSecondary))),
        Expanded(child: Text(displayValue, style: TextStyle(fontSize: 14, color: c.text))),
      ]),
    );
  }

  Widget _ExampleItem({required String en, required String zh, required AppColors c}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(en, style: TextStyle(fontSize: 13.5, color: c.text, height: 1.5)),
      Text(zh, style: TextStyle(fontSize: 12.5, color: c.textTertiary, height: 1.4)),
    ]);
  }

  Widget _Chip({required String text, required AppColors? c}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c?.primaryBg ?? const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: c?.textSecondary ?? const Color(0xFF888888))),
    );
  }

  Future<void> _search(AppState s) async {
    final query = _ctrl.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _foundEntry = null;
      _foundWord = null;
      _result = null;
      _maimemoLookup = null;
      _collocations = [];
      _synonyms = [];
      _mnemonics = [];
      _examples = [];
      _loadingExtras = false;
    });
    final isEnglishWord = RegExp(r'^[a-zA-Z\s\-]+$').hasMatch(query);
    final singleWord = query.toLowerCase().trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length == 1
        ? query.toLowerCase().trim()
        : null;
    // 墨墨模式：单词查询结果只由墨墨开放 API 提供，绝不降级到 AI/本地链路
    if (s.dictSource == 'maimemo') {
      if (singleWord == null) {
        // 墨墨接口仅支持按英文单词拼写查询
        _result = '墨墨模式仅支持英文单词查询，如需查询中文或短语，请在设置中切换为「AI 生成」';
        setState(() => _searching = false);
        return;
      }
      try {
        final lookup = await s.lookupWordMaimemo(singleWord);
        if (!mounted) return;
        if (lookup == null) {
          _result = '墨墨词库中未找到 "$singleWord"，可前往设置切换为「AI 生成」';
          setState(() => _searching = false);
          return;
        }
        final entry = DictService.lookup(singleWord);
        _maimemoLookup = lookup;
        _foundWord = lookup.word;
        _foundEntry = entry;
        setState(() => _searching = false);
        // 墨墨模式：释义/例句/助记全部来自墨墨 API，不混入 AI 生成内容
        return;
      } catch (e) {
        if (!mounted) return;
        _result = e is MaimemoException ? e.message : '墨墨查询失败：$e';
        setState(() => _searching = false);
        return;
      }
    }
    // 英文 → 本地词库
    if (isEnglishWord) {
      final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (words.length == 1) {
        final entry = DictService.lookup(words.first);
        if (entry != null) {
          _foundWord = words.first;
          _foundEntry = entry;
          setState(() => _searching = false);
          // AI 获取搭配和同义词
          if (s.apiConfig.ready) {
            _fetchWordExtras(s, words.first);
          }
          return;
        }
      }
    }
    // 英文不在本地词库 或 中文 → AI 查词（结构化）
    final isChinese = !RegExp(r'^[a-zA-Z\s\-]+$').hasMatch(query);
    final aiPrompt = isChinese
        ? '将中文"$query"翻译为英文单词。必须返回 JSON：{"word":"英文单词","phonetic":"音标","pos":"词性(如 noun/verb)","translation":"中文释义","other":"补充"}。只返回 JSON，不要其他内容。'
        : '给出英文单词 "$query" 的音标、词性、中文释义。必须返回 JSON：{"word":"$query","phonetic":"音标","pos":"词性","translation":"中文释义","other":"补充"}。只返回 JSON，不要其他内容。';
    final reply = await api.ApiService.callAI(
      [
        {'role': 'user', 'content': aiPrompt}
      ],
      '你是英语词典。只返回 JSON，不要其他内容。',
      config: s.apiConfig,
      maxTokens: 256,
      extraParams: api.ApiService.noThinkingParams(s.apiConfig.model),
    );
    if (reply != null) {
      final obj = api.ApiService.extractJsonObject(reply);
      if (obj != null) {
        final w = (obj['word'] ?? '').toString().trim();
        if (w.isNotEmpty) {
          _foundWord = w.toLowerCase();
          _foundEntry = DictEntry(
            phonetic: (obj['phonetic'] ?? '').toString(),
            pos: (obj['pos'] ?? '').toString(),
            translation: (obj['translation'] ?? '').toString(),
            other: (obj['other'] ?? '').toString(),
          );
          setState(() => _searching = false);
          if (s.apiConfig.ready) {
            _fetchWordExtras(s, _foundWord!);
          }
          return;
        }
      }
      // Fallback: 解析纯文本格式 "英文：xxx\n词性：xxx\n释义：xxx"
      final parsed = _parsePlainDictReply(reply);
      if (parsed != null) {
        _foundWord = parsed['word']?.toLowerCase();
        _foundEntry = DictEntry(
          phonetic: parsed['phonetic'] ?? '',
          pos: parsed['pos'] ?? '',
          translation: parsed['translation'] ?? '',
          other: parsed['other'] ?? '',
        );
        setState(() => _searching = false);
        if (s.apiConfig.ready && _foundWord != null) {
          _fetchWordExtras(s, _foundWord!);
        }
        return;
      }
    }
    _result = '查询失败，请检查 API 配置';
    setState(() => _searching = false);
  }

  /// 解析 AI 返回的纯文本格式（非 JSON）
  /// 支持格式：英文：xxx / 词性：xxx / 释义：xxx / 音标：xxx / 补充：xxx
  Map<String, String>? _parsePlainDictReply(String text) {
    final lines = text.split(RegExp(r'\n+'));
    String? word, phonetic, pos, translation, other;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 匹配 "key：value" 或 "key:value"
      final m = RegExp(r'^(英文|word|音标|phonetic|词性|pos|释义|translation|补充|other)\s*[:：]\s*(.+)$', caseSensitive: false).firstMatch(trimmed);
      if (m != null) {
        final key = m.group(1)!.toLowerCase();
        final val = m.group(2)!.trim();
        if (key == '英文' || key == 'word') word = val;
        else if (key == '音标' || key == 'phonetic') phonetic = val;
        else if (key == '词性' || key == 'pos') pos = val;
        else if (key == '释义' || key == 'translation') translation = val;
        else if (key == '补充' || key == 'other') other = val;
      }
    }
    if (word == null && translation == null) return null;
    return {
      'word': word ?? '',
      'phonetic': phonetic ?? '',
      'pos': pos ?? '',
      'translation': translation ?? '',
      'other': other ?? '',
    };
  }

  /// AI 获取单词的搭配、同义词、例句和助记（关闭思考模式）
  Future<void> _fetchWordExtras(AppState s, String word) async {
    if (!mounted) return;
    setState(() => _loadingExtras = true);
    final prompt = '给出单词 "$word" 的 5 个常见搭配、3 个同义词、2 个例句和 2 条助记（谐音/联想/词根词缀等，帮助记忆）。'
        '返回 JSON：{"collocations":["..."],"synonyms":["..."],"examples":[{"en":"...","zh":"..."}],"mnemonics":["...","..."]}';
    final reply = await api.ApiService.callAI(
      [
        {'role': 'user', 'content': prompt}
      ],
      '你是英语词典助手。只返回 JSON，不要其他内容。',
      config: s.apiConfig,
      maxTokens: 600,
      extraParams: api.ApiService.noThinkingParams(s.apiConfig.model),
    );
    if (!mounted) return;
    if (reply != null) {
      final obj = api.ApiService.extractJsonObject(reply);
      if (obj != null) {
        final cols = (obj['collocations'] as List?)?.whereType<String>().toList() ?? [];
        final syns = (obj['synonyms'] as List?)?.whereType<String>().toList() ?? [];
        final mnes = (obj['mnemonics'] as List?)?.whereType<String>().toList() ?? [];
        final examples = (obj['examples'] as List?)
            ?.whereType<Map>()
            .map((e) => {
                  'en': (e['en'] ?? '').toString(),
                  'zh': (e['zh'] ?? '').toString(),
                })
            .toList() ?? [];
        setState(() {
          _collocations = cols;
          _synonyms = syns;
          _mnemonics = mnes;
          _examples = examples;
          _loadingExtras = false;
        });
        return;
      }
    }
    setState(() => _loadingExtras = false);
  }
}

// ===== 默写 =====
class DictationPage extends StatefulWidget {
  const DictationPage({super.key});

  @override
  State<DictationPage> createState() => _DictationPageState();
}

// ===== 题库面板 =====
class QuestionListPanel extends StatelessWidget {
  const QuestionListPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('题库', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c.text)),
          const SizedBox(height: 16),
          Text('已生成 ${s.questions.length} 道题目', style: TextStyle(fontSize: 14, color: c.textSecondary)),
          const SizedBox(height: 24),
          Expanded(
            child: s.questions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.library_books_outlined, size: 64, color: c.textTertiary),
                        const SizedBox(height: 16),
                        Text('暂无题目', style: TextStyle(fontSize: 16, color: c.textSecondary)),
                        const SizedBox(height: 8),
                        Text('请前往"学习"页面生成题目', style: TextStyle(fontSize: 13, color: c.textTertiary)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: s.questions.length,
                    itemBuilder: (context, index) {
                      final q = s.questions[index];
                      final answered = s.answeredBankIndices.contains(q.bankIdx ?? index);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Stack(clipBehavior: Clip.none, children: [
                            CircleAvatar(
                              backgroundColor: answered
                                  ? (c.isLight ? const Color(0xFF22C55E).withValues(alpha: 0.12) : const Color(0xFF4ADE80).withValues(alpha: 0.15))
                                  : c.primaryBg,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: answered ? const Color(0xFF16A34A) : c.primaryText,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (answered)
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF22C55E),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: c.isLight ? Colors.white : const Color(0xFF2A2A32), width: 1.5),
                                  ),
                                  child: const Icon(Icons.check, size: 10, color: Colors.white),
                                ),
                              ),
                          ]),
                          title: Row(children: [
                            if (answered) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '已作答',
                                  style: TextStyle(fontSize: 10, color: Color(0xFF16A34A), fontWeight: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                q.type == QType.translation ? q.english : q.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.text),
                              ),
                            ),
                          ]),
                          subtitle: Text('${qTypeName(q.type)} · ${q.level}', style: TextStyle(fontSize: 12, color: c.textTertiary)),
                          trailing: Icon(Icons.chevron_right, color: c.textTertiary),
                          onTap: () {
                            // 先切换页面，再加载题目
                            s.setPage(1);
                            // 延迟加载确保 AnswerPage 已初始化并捕获当前 questionSeq
                            Future.delayed(const Duration(milliseconds: 50), () {
                              s.loadQuestionFromBank(index);
                            });
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DictationPageState extends State<DictationPage> {
  String _mode = 'zh2en';
  int _count = 10;
  /// 词库来源：'custom' = 自定义词库 | 'zsb' = 专升本词库 | 'maimemo' = 墨墨词库
  String _source = 'custom';
  late final int _zsbCount;
  final TextEditingController _ansCtrl = TextEditingController();
  String? _feedback;
  bool _isCorrect = false;
  bool _showAnswer = false;
  bool _autoAdvance = true;
  bool _aiGrading = false; // AI 批改中
  String _aiComment = ''; // AI 点评
  int? _autoAdvanceTimer;
  final FocusNode _focusNode = FocusNode();
  final List<WordToken> _wrongWords = [];

  @override
  void initState() {
    super.initState();
    _zsbCount = DictService.zsbWords().length;
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {}
    });
  }

  @override
  void dispose() {
    _autoAdvanceTimer = null;
    _ansCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetDictationState() {
    _ansCtrl.clear();
    _feedback = null;
    _isCorrect = false;
    _showAnswer = false;
    _aiGrading = false;
    _aiComment = '';
    _autoAdvanceTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final w = s.currentDictationWord;
    if (s.dictationQueue.isEmpty) {
      return _buildStartPage(s);
    }
    if (s.dictationFinished) {
      return _buildFinishPage(s);
    }
    // 兜底：队列非空但当前词取不到时回到开始页，避免 w! 空崩溃
    if (w == null) {
      return _buildStartPage(s);
    }
    return _buildAnsweringPage(s, w);
  }

  // ===== 开始页面：选择词库 + 默写设置 =====
  Widget _buildStartPage(AppState s) {
    final c = AppColors.of(context);
    final sources = <({String key, IconData icon, String name, int count, String desc})>[
      (key: 'custom', icon: Icons.create_new_folder_outlined, name: '自定义词库', count: s.customWordbook.length, desc: '手动添加自己整理的单词'),
      (key: 'zsb', icon: Icons.school_outlined, name: '专升本词库', count: _zsbCount, desc: '覆盖专升本考纲核心词汇'),
      (key: 'maimemo', icon: Icons.auto_stories_outlined, name: '墨墨词库', count: s.maimemoWordbook.length, desc: '同步自墨墨今日已学习单词'),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: SizedBox(
          width: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 标题
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: c.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('单词默写', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.text)),
                Text('选择词库开始默写，AI 智能批改', style: TextStyle(fontSize: 12, color: c.textTertiary)),
              ]),
            ]),
            const SizedBox(height: 24),
            // 词库选择
            Text('选择词库', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 10),
            for (final src in sources) ...[
              _sourceCard(s, c, src),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            // 模式选择
            Text('默写模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'zh2en', label: Text('中文 → 英文')),
                ButtonSegment(value: 'en2zh', label: Text('英文 → 中文')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 20),
            // 题量
            Text('题量', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 10),
            Row(children: [
              for (final n in const [5, 10, 20, 30])
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: ChoiceChip(
                    label: Text('$n 题'),
                    selected: _count == n,
                    onSelected: (_) => setState(() => _count = n),
                    selectedColor: c.primaryBg,
                    checkmarkColor: c.primaryText,
                    backgroundColor: c.chipUnselected,
                  ),
                ),
            ]),
            const SizedBox(height: 20),
            // 自动跳转
            CheckboxListTile(
              value: _autoAdvance,
              onChanged: (v) => setState(() => _autoAdvance = v ?? true),
              title: Text('答完自动跳转下一题', style: TextStyle(fontSize: 13, color: c.text)),
              subtitle: Text('答对后 1 秒自动进入下一题', style: TextStyle(fontSize: 11, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 24),
            // 开始按钮
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  s.startDictation(_mode, _count, source: _source);
                  _resetDictationState();
                  WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
                  setState(() {});
                },
                child: const Text('开始默写', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ===== 词库来源显示名 =====
  String _sourceName(AppState s) {
    return switch (s.dictationSource) {
      'custom' => '自定义',
      'maimemo' => '墨墨词库',
      _ => '专升本',
    };
  }

  // ===== 词库选择卡片 =====
  Widget _sourceCard(AppState s, AppColors c, ({String key, IconData icon, String name, int count, String desc}) src) {
    final selected = _source == src.key;
    return GestureDetector(
      onTap: () => setState(() => _source = src.key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.primaryBg : c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? c.primaryBorder : c.border, width: selected ? 1.6 : 1),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: selected ? kPrimary.withValues(alpha: 0.15) : c.primaryBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(src.icon, size: 20, color: selected ? kPrimary : c.primaryText),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(src.name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: selected ? kPrimary.withValues(alpha: 0.12) : c.primaryBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('${src.count} 词', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: selected ? kPrimary : c.primaryText)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(src.desc, style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
            ]),
          ),
          if (src.key == 'custom')
            IconButton(
              icon: Icon(Icons.tune, size: 18, color: c.textTertiary),
              tooltip: '管理自定义词库',
              onPressed: () => _showCustomWordbookDialog(s),
            ),
          const SizedBox(width: 2),
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: selected ? kPrimary : c.textTertiary),
        ]),
      ),
    );
  }

  // ===== 自定义词库管理弹窗 =====
  void _showCustomWordbookDialog(AppState s) {
    final wordCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        final c = AppColors.of(ctx);
        void add() {
          final w = wordCtrl.text.trim();
          if (w.isEmpty) return;
          final entry = DictService.lookup(w.toLowerCase());
          s.addToCustomWordbook(w, entry?.translation ?? '');
          wordCtrl.clear();
          setDialogState(() {});
        }

        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.create_new_folder_outlined, size: 20),
            const SizedBox(width: 8),
            const Text('自定义词库', style: TextStyle(fontSize: 17)),
            const Spacer(),
            Text('${s.customWordbook.length} 词', style: TextStyle(fontSize: 12, color: c.textTertiary)),
          ]),
          content: SizedBox(
            width: 380, height: 360,
            child: Column(children: [
              // 添加
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: wordCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '输入英文单词，回车添加',
                      isDense: true,
                      filled: true,
                      fillColor: c.inputFill,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kPrimary),
                  onPressed: add,
                  child: const Text('添加'),
                ),
              ]),
              const SizedBox(height: 12),
              // 列表
              Expanded(
                child: s.customWordbook.isEmpty
                    ? Center(child: Text('词库为空，先添加单词吧', style: TextStyle(fontSize: 13, color: c.textTertiary)))
                    : ListView.builder(
                        itemCount: s.customWordbook.length,
                        itemBuilder: (ctx, i) {
                          final item = s.customWordbook[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.menu_book_outlined, size: 18, color: c.primaryText),
                            title: Text(item.word, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                            subtitle: Text(item.translation.isEmpty ? '（无释义）' : item.translation, style: TextStyle(fontSize: 12, color: c.textTertiary)),
                            trailing: IconButton(
                              icon: Icon(Icons.delete_outline, size: 18, color: c.textTertiary),
                              onPressed: () {
                                s.removeFromCustomWordbook(item.word);
                                setDialogState(() {});
                              },
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('完成')),
          ],
        );
      }),
    );
  }

  // ===== 答题页面 =====
  Widget _buildAnsweringPage(AppState s, WordToken w) {
    final c = AppColors.of(context);
    final progress = s.dictationQueue.isEmpty ? 0.0 : (s.dictationIdx / s.dictationQueue.length);
    // 使用 s.dictationMode（切页回来 State 重建后 _mode 可能过期）
    final isZh2En = s.dictationMode == 'zh2en';
    final promptText = isZh2En ? '请翻译成英文' : '请写出中文释义';
    final hintText = isZh2En ? '输入英文单词...' : '输入中文释义...';

    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 进度条
        Row(children: [
          Text('${_sourceName(s)} · ${s.dictationIdx + 1} / ${s.dictationQueue.length}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primaryText)),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: c.progressBg,
                valueColor: AlwaysStoppedAnimation(c.primaryText),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('答对 ${s.dictationCorrect}', style: TextStyle(fontSize: 13, color: c.scoreHigh, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 24),
        // 提示
        Text(promptText, style: TextStyle(fontSize: 13, color: c.textTertiary)),
        const SizedBox(height: 8),
        // 题目卡片
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: c.isLight
                  ? [kPrimary.withValues(alpha: 0.08), Colors.white]
                  : [kPrimary.withValues(alpha: 0.2), kDarkCard],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.primaryBorder),
          ),
          child: Text(
            isZh2En ? w.translation : w.word,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: c.text),
          ),
        ),
        const SizedBox(height: 20),
        // 输入框
        TextField(
          controller: _ansCtrl,
          focusNode: _focusNode,
          autofocus: true,
          enabled: !_aiGrading,
          style: TextStyle(fontSize: 16, color: c.text),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 14, color: c.inputHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _feedback != null ? (_isCorrect ? c.scoreHigh : c.scoreLow) : kPrimary, width: 2),
            ),
            suffixIcon: _aiGrading
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : _feedback == null
                    ? IconButton(onPressed: () => _submit(s), icon: const Icon(Icons.check_circle_outline, size: 22))
                    : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onSubmitted: (_) {
            if (_aiGrading) return;
            if (_feedback != null) {
              _nextQuestion(s);
            } else {
              _submit(s);
            }
          },
        ),
        // AI 批改中
        if (_aiGrading) ...[
          const SizedBox(height: 12),
          Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('AI 批改中...', style: TextStyle(fontSize: 13, color: c.primaryText)),
          ]),
        ],
        // 反馈区
        if (_feedback != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isCorrect ? c.successBg : c.dangerBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _isCorrect ? c.successBorder : c.dangerBorder),
            ),
            child: Row(children: [
              Icon(_isCorrect ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _isCorrect ? c.scoreHigh : c.scoreLow, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _isCorrect ? '回答正确！' : '回答错误',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _isCorrect ? c.scoreHigh : c.scoreLow),
                  ),
                  if (_aiComment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(_aiComment, style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.5)),
                  ],
                  if (!_isCorrect || _showAnswer) ...[
                    const SizedBox(height: 4),
                    Text('正确答案：${w.word}  ${w.translation}', style: TextStyle(fontSize: 13, color: c.textSecondary)),
                  ],
                ]),
              ),
              if (_autoAdvance && _isCorrect)
                Text('自动跳转...', style: TextStyle(fontSize: 11, color: c.textTertiary)),
            ]),
          ),
        ],
        const SizedBox(height: 14),
        // 操作按钮
        Row(children: [
          if (_feedback != null)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kPrimary),
              onPressed: () => _nextQuestion(s),
              child: const Text('下一题'),
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kPrimary),
              onPressed: _aiGrading ? null : () => _submit(s),
              child: Text(_aiGrading ? '批改中...' : '提交'),
            ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: _aiGrading ? null : () => _skip(s),
            child: const Text('跳过'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() => _showAnswer = !_showAnswer);
            },
            child: Text(_showAnswer ? '隐藏答案' : '显示答案', style: TextStyle(color: c.textTertiary)),
          ),
        ]),
      ]),
    );
  }

  // ===== 完成页面 =====
  Widget _buildFinishPage(AppState s) {
    final c = AppColors.of(context);
    final correct = s.dictationCorrect;
    final total = s.dictationTotal;
    final rate = total == 0 ? 0.0 : correct / total;
    final good = rate >= 0.8;

    final goodColor = c.scoreHigh;
    final midColor = c.scoreMid;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 90, height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: good ? [goodColor, kPrimary] : [kPrimary, midColor]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: (good ? goodColor : kPrimary).withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Icon(good ? Icons.emoji_events_rounded : Icons.school_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 20),
            Text('本轮默写完成', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, children: [
              Text('$correct', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: c.primaryText)),
              Text(' / $total', style: TextStyle(fontSize: 18, color: c.textTertiary)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: good ? c.successBg : c.warningBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('正确率 ${(rate * 100).round()}%', style: TextStyle(fontSize: 14, color: good ? c.scoreHigh : c.warning, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kPrimary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () {
                  s.dictationQueue = [];
                  s.touch();
                  _resetDictationState();
                  setState(() {});
                },
                child: const Text('再来一轮', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _submit(AppState s) async {
    final ans = _ansCtrl.text.trim();
    if (ans.isEmpty || _aiGrading) return;
    // 先取当前词，再批改（advance=false 不推进索引，避免 UI 刷新后显示错位）
    final w = s.currentDictationWord;
    setState(() => _aiGrading = true);
    try {
      final result = await s.checkDictationAnswerAI(ans, advance: false);
      if (!mounted) return;
      setState(() {
        _aiGrading = false;
        _isCorrect = result.correct;
        _feedback = result.correct ? '回答正确！' : '回答错误';
        _aiComment = result.comment;
        _showAnswer = !result.correct;
        if (!result.correct && w != null) {
          _wrongWords.add(w);
        }
      });
      if (_autoAdvance && result.correct) {
        _autoAdvanceTimer = DateTime.now().millisecondsSinceEpoch;
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted && _feedback != null && _isCorrect) {
            _nextQuestion(s);
          }
        });
      }
    } catch (_) {
      // 兜底：AI 调用异常时回退本地批改
      if (!mounted) return;
      final correct = s.checkDictationAnswer(ans, advance: false);
      setState(() {
        _aiGrading = false;
        _isCorrect = correct;
        _feedback = correct ? '回答正确！' : '回答错误';
        _aiComment = 'AI 批改失败，已用本地批改';
        _showAnswer = !correct;
        if (!correct && w != null) _wrongWords.add(w);
      });
    }
  }

  void _nextQuestion(AppState s) {
    s.nextDictationQuestion();
    _resetDictationState();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  void _skip(AppState s) {
    final w = s.currentDictationWord;
    if (w == null) return;
    s.skipDictation();
    _resetDictationState();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }
}
