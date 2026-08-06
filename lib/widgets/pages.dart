/// 功能页：错题本 / 学习报告 / 生词本 / 答题记录 / 查词 / 默写
library;

import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/api_service.dart' as api;
import '../services/dict_service.dart';
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
class ReportPage extends StatelessWidget {
  const ReportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final records = s.studyRecords;
    final total = records.length;
    final sum = records.fold<int>(0, (acc, r) => acc + r.score);
    final avg = total == 0 ? 0.0 : sum / total;
    final pass = records.where((r) => r.score >= 70).length;
    final rate = total == 0 ? 0 : (pass / total * 100).round();
    final totalSec = records.fold<int>(0, (acc, r) => acc + r.duration);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Expanded(child: Text('学习报告', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.text))),
          TextButton(onPressed: s.studyRecords.isEmpty ? null : () => s.clearStudyRecords(), child: const Text('清空记录')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          _Stat(label: '累计作答', value: '$total'),
          const SizedBox(width: 24),
          _Stat(label: '平均分', value: total == 0 ? '-' : avg.toStringAsFixed(1)),
          const SizedBox(width: 24),
          _Stat(label: '达标率(≥70分)', value: total == 0 ? '-' : '$rate%'),
          const SizedBox(width: 24),
          _Stat(label: '学习时长', value: totalSec >= 60 ? '${(totalSec / 60).round()}分钟' : '${totalSec}秒'),
        ]),
      ),
      // 模拟考试成绩（交卷后持久化的最近一次成绩 + 历史摘要）
      if (s.currentExamResult != null || s.examHistory.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.assignment_turned_in_rounded, size: 16, color: c.primaryText),
                  const SizedBox(width: 6),
                  Text('模拟考试成绩', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                  const Spacer(),
                  if (s.currentExamResult != null)
                    TextButton(onPressed: () => s.setPage(11), child: const Text('查看成绩分析', style: TextStyle(fontSize: 12.5))),
                ]),
                if (s.currentExamResult != null) ...[
                  const SizedBox(height: 10),
                  Builder(builder: (context) {
                    final r = s.currentExamResult!;
                    final good = r.rank == 'A' || r.rank == 'B';
                    return Row(children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: good ? c.successBg : c.dangerBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(r.rank, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: good ? c.scoreHigh : c.scoreLow)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.paper.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
                          const SizedBox(height: 2),
                          Text(
                            '${_fmtTime(r.submittedAt)} · 用时 ${r.durationSec >= 60 ? '${(r.durationSec / 60).round()}分钟' : '${r.durationSec}秒'}',
                            style: TextStyle(fontSize: 11.5, color: c.textTertiary),
                          ),
                        ]),
                      ),
                      Text('${r.totalScore}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: good ? c.scoreHigh : c.scoreLow)),
                      Text(' / ${r.maxScore}分', style: TextStyle(fontSize: 12, color: c.textTertiary)),
                    ]);
                  }),
                ],
                if (s.examHistory.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: c.divider),
                  const SizedBox(height: 8),
                  Text('历史成绩（最近 ${s.examHistory.length} 次）', style: TextStyle(fontSize: 12, color: c.textTertiary)),
                  const SizedBox(height: 4),
                  for (final h in s.examHistory.take(10))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: (h.rank == 'A' || h.rank == 'B') ? c.successBg : ((h.rank == 'C') ? c.card : c.dangerBg),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(h.rank, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: (h.rank == 'A' || h.rank == 'B') ? c.scoreHigh : ((h.rank == 'C') ? c.primaryText : c.scoreLow))),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(h.title.isEmpty ? '模拟全卷' : h.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.text))),
                        Text('${h.totalScore}/${h.maxScore}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text)),
                        const SizedBox(width: 12),
                        Text(_fmtTime(h.submittedAt), style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                      ]),
                    ),
                ],
              ]),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('最近 7 天作答趋势', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 14),
              SizedBox(height: 140, child: _TrendChart(records: records)),
            ]),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('最近作答记录', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 8),
              if (records.isEmpty)
                Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('暂无作答记录，快去练习吧！', style: TextStyle(color: c.textTertiary, fontSize: 13))))
              else
                for (final r in records.take(20))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: (r.isWrong ? c.dangerBg : c.successBg), borderRadius: BorderRadius.circular(4)),
                        child: Text(r.isWrong ? '错' : '对', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: r.isWrong ? c.scoreLow : c.scoreHigh)),
                      ),
                      const SizedBox(width: 8),
                      Text(qTypeName(r.type), style: TextStyle(fontSize: 12, color: c.textSecondary)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.text))),
                      Text('${r.score}分', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text)),
                      const SizedBox(width: 12),
                      Text(_fmtTime(r.timestamp), style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                    ]),
                  ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _TrendChart extends StatelessWidget {
  final List<StudyRecord> records;
  const _TrendChart({required this.records});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final days = <({String label, int count})>[];
    final now = DateTime.now();
    for (var i = 6; i >= 0; i--) {
      final d = DateTime(now.year, now.month, now.day - i);
      final start = d.millisecondsSinceEpoch;
      final end = start + 86400000;
      final cnt = records.where((r) => r.timestamp >= start && r.timestamp < end).length;
      days.add((label: '${d.month}/${d.day}', count: cnt));
    }
    final maxCount = days.fold<int>(1, (m, d) => max(m, d.count));
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final d in days)
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(d.count > 0 ? '${d.count}题' : '', style: TextStyle(fontSize: 10, color: c.textTertiary)),
            const SizedBox(height: 4),
            Container(
              width: 24,
              height: d.count == 0 ? 6 : max(10, (d.count / maxCount * 90)).toDouble(),
              decoration: BoxDecoration(
                gradient: d.count == 0
                    ? null
                    : (c.isLight
                        ? const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF4F6EF7), Color(0xFF8B5CF6)])
                        : const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xFF7C8FF7), Color(0xFFB794F6)])),
                color: d.count == 0 ? c.sliderInactive : null,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
            const SizedBox(height: 4),
            Text(d.label, style: TextStyle(fontSize: 10, color: c.textTertiary)),
          ]),
        ),
    ]);
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
  bool _searching = false;
  List<String> _collocations = [];
  List<String> _synonyms = [];
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
                              setState(() { _foundEntry = null; _foundWord = null; _result = null; });
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
    if (_result == null && _foundEntry == null) {
      return const _EmptyState(icon: Icons.search_rounded, title: '输入单词开始查询', subtitle: '英文优先匹配本地词库，中文走 AI 翻译');
    }
    final entry = _foundEntry;
    final word = _foundWord;
    final isMobile = s.uiMode == 'mobile';

    final body = entry != null && word != null
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
              if (entry.phonetic.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('/${entry.phonetic}/', style: TextStyle(fontSize: 15, color: c.textTertiary)),
                ),
              const SizedBox(height: 16),
              // 词性、释义、补充
              if (entry.pos.isNotEmpty) _InfoRow(label: '词性', value: entry.pos, c: c),
              if (entry.translation.isNotEmpty) _InfoRow(label: '释义', value: entry.translation, c: c),
              if (entry.other.isNotEmpty) _InfoRow(label: '补充', value: entry.other, c: c),
              const SizedBox(height: 16),
              Divider(height: 1, color: c.divider),
              const SizedBox(height: 12),
              // 手机端：垂直布局；桌面端：左右两栏
              if (isMobile) ...[
                // 例句
                Text('例句', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                if (_loadingExtras)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_examples.isEmpty)
                  Text('暂无例句', style: TextStyle(fontSize: 13, color: c.textTertiary))
                else
                  ..._examples.map((ex) => Column(
                        children: [
                          _ExampleItem(en: ex['en'] ?? '', zh: ex['zh'] ?? '', c: c),
                          const SizedBox(height: 8),
                        ],
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
                      if (_loadingExtras)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (_examples.isEmpty)
                        Text('暂无例句', style: TextStyle(fontSize: 13, color: c.textTertiary))
                      else
                        ..._examples.map((ex) => Column(
                              children: [
                                _ExampleItem(en: ex['en'] ?? '', zh: ex['zh'] ?? '', c: c),
                                const SizedBox(height: 8),
                              ],
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
                    s.addToWordBook(w, entry.translation);
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
      _collocations = [];
      _synonyms = [];
      _loadingExtras = false;
    });
    // 英文 → 本地词库
    if (RegExp(r'^[a-zA-Z\s\-]+$').hasMatch(query)) {
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

  /// AI 获取单词的搭配、同义词和例句（关闭思考模式）
  Future<void> _fetchWordExtras(AppState s, String word) async {
    if (!mounted) return;
    setState(() => _loadingExtras = true);
    final prompt = '给出单词 "$word" 的 5 个常见搭配、3 个同义词和 2 个例句。返回 JSON：{"collocations":["..."],"synonyms":["..."],"examples":[{"en":"...","zh":"..."}]}';
    final reply = await api.ApiService.callAI(
      [
        {'role': 'user', 'content': prompt}
      ],
      '你是英语词典助手。只返回 JSON，不要其他内容。',
      config: s.apiConfig,
      maxTokens: 512,
      extraParams: api.ApiService.noThinkingParams(s.apiConfig.model),
    );
    if (!mounted) return;
    if (reply != null) {
      final obj = api.ApiService.extractJsonObject(reply);
      if (obj != null) {
        final cols = (obj['collocations'] as List?)?.whereType<String>().toList() ?? [];
        final syns = (obj['synonyms'] as List?)?.whereType<String>().toList() ?? [];
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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: c.primaryBg,
                            child: Text('${index + 1}', style: TextStyle(color: c.primaryText, fontWeight: FontWeight.bold)),
                          ),
                          title: Text(q.type == QType.translation ? q.english : q.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.text)),
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
  final TextEditingController _ansCtrl = TextEditingController();
  String? _feedback;
  bool _isCorrect = false;
  bool _showAnswer = false;
  bool _autoAdvance = true;
  int? _autoAdvanceTimer;
  final FocusNode _focusNode = FocusNode();
  final List<WordToken> _wrongWords = [];

  @override
  void initState() {
    super.initState();
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
    return _buildAnsweringPage(s, w!);
  }

  // ===== 开始页面 =====
  Widget _buildStartPage(AppState s) {
    final c = AppColors.of(context);
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
                Text('从专升本词库随机抽词，系统自动批改', style: TextStyle(fontSize: 12, color: c.textTertiary)),
              ]),
            ]),
            const SizedBox(height: 28),
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
                  s.startDictation(_mode, _count);
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

  // ===== 答题页面 =====
  Widget _buildAnsweringPage(AppState s, WordToken w) {
    final c = AppColors.of(context);
    final progress = s.dictationQueue.isEmpty ? 0.0 : (s.dictationIdx / s.dictationQueue.length);
    final isZh2En = _mode == 'zh2en';
    final promptText = isZh2En ? '请翻译成英文' : '请写出中文释义';
    final hintText = isZh2En ? '输入英文单词...' : '输入中文释义...';

    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 进度条
        Row(children: [
          Text('${s.dictationIdx + 1} / ${s.dictationQueue.length}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primaryText)),
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
          style: TextStyle(fontSize: 16, color: c.text),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 14, color: c.inputHint),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _feedback != null ? (_isCorrect ? c.scoreHigh : c.scoreLow) : kPrimary, width: 2),
            ),
            suffixIcon: _feedback == null
                ? IconButton(onPressed: () => _submit(s), icon: const Icon(Icons.check_circle_outline, size: 22))
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          onSubmitted: (_) {
            if (_feedback != null) {
              _nextQuestion(s);
            } else {
              _submit(s);
            }
          },
        ),
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
              onPressed: () => _submit(s),
              child: const Text('提交'),
            ),
          const SizedBox(width: 10),
          OutlinedButton(
            onPressed: () => _skip(s),
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

  void _submit(AppState s) {
    final ans = _ansCtrl.text.trim();
    if (ans.isEmpty) return;
    // 先取当前词，再批改（advance=false 不推进索引，避免 UI 刷新后显示错位）
    final w = s.currentDictationWord;
    final correct = s.checkDictationAnswer(ans, advance: false);
    setState(() {
      _isCorrect = correct;
      _feedback = correct ? '回答正确！' : '回答错误';
      _showAnswer = !correct;
      if (!correct && w != null) {
        _wrongWords.add(w);
      }
    });
    if (_autoAdvance && correct) {
      _autoAdvanceTimer = DateTime.now().millisecondsSinceEpoch;
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted && _feedback != null && _isCorrect) {
          _nextQuestion(s);
        }
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
