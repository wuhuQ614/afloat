/// 语法学习页：学习路径总览 / 知识点学习 / 随堂练习（四选一即时判分 + AI 扩题）
/// 仅订阅 GrammarStore，不依赖 AppState
library;

import 'package:flutter/material.dart';
import '../grammar_store.dart';
import '../models.dart';
import '../services/tts_service.dart';
import '../theme_colors.dart' show kSuccess, kDanger, AppColors;

class GrammarPage extends StatefulWidget {
  const GrammarPage({super.key});

  @override
  State<GrammarPage> createState() => _GrammarPageState();
}

class _GrammarPageState extends State<GrammarPage> {
  final GrammarStore _store = GrammarStore.instance;

  @override
  void initState() {
    super.initState();
    _store.ensureCourse();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (ctx, _) {
        switch (_store.view) {
          case GrammarView.learn:
            final t = _store.currentTopic;
            if (t == null) return const _OverviewView();
            return _LearnView(topic: t);
          case GrammarView.quiz:
            final t = _store.currentTopic;
            if (t == null) return const _OverviewView();
            return _QuizView(topic: t);
          case GrammarView.overview:
            return const _OverviewView();
        }
      },
    );
  }
}

// ===== 1. 学习路径总览 =====
class _OverviewView extends StatelessWidget {
  const _OverviewView();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = GrammarStore.instance;
    if (store.courseLoading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.primary)),
          const SizedBox(height: 12),
          Text('正在加载语法课程...', style: TextStyle(fontSize: 13, color: c.textTertiary)),
        ]),
      );
    }
    if (store.courseError.isNotEmpty || store.levels.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hourglass_empty_rounded, size: 40, color: c.textTertiary),
          const SizedBox(height: 10),
          Text(store.courseError.isEmpty ? '暂无课程数据' : store.courseError,
              style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重新加载'),
            onPressed: () => GrammarStore.instance.ensureCourse(),
          ),
        ]),
      );
    }
    final total = store.totalTopicCount;
    final learned = store.learnedTopicCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      children: [
        // 整体进度卡
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('专升本语法通关', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                  const Spacer(),
                  Text('已完成 $learned / $total 个知识点',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
                ]),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : learned / total,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.25),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // 各层级卡片
        for (final level in store.levels) ...[
          _LevelCard(level: level),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  final GrammarLevel level;
  const _LevelCard({required this.level});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = GrammarStore.instance;
    final done = level.topics.where((t) => store.progressOf(t.id).learned).length;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: c.primaryBg, borderRadius: BorderRadius.circular(8)),
              child: Text(level.id, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c.primaryText)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(level.name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
                if (level.desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(level.desc, style: TextStyle(fontSize: 12, color: c.textTertiary), overflow: TextOverflow.ellipsis),
                ],
              ]),
            ),
            Text('$done/${level.topics.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textTertiary)),
          ]),
        ),
        Divider(height: 1, color: c.divider),
        for (final topic in level.topics) _TopicRow(topic: topic),
      ]),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final GrammarTopic topic;
  const _TopicRow({required this.topic});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = GrammarStore.instance;
    final p = store.progressOf(topic.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => store.openTopic(topic),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(children: [
            Icon(
              p.learned ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 20,
              color: p.learned ? kSuccess : c.textTertiary.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(topic.name,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text),
                    overflow: TextOverflow.ellipsis),
                if (p.learned) ...[
                  const SizedBox(height: 2),
                  Text('最佳正确率 ${p.best}% · 练习 ${p.attempts} 次',
                      style: TextStyle(fontSize: 11, color: c.textTertiary)),
                ],
              ]),
            ),
            _WeightBadge(weight: topic.weight),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ]),
        ),
      ),
    );
  }
}

/// 考频徽标：high 标"高频"
class _WeightBadge extends StatelessWidget {
  final String weight;
  const _WeightBadge({required this.weight});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (label, bg, fg) = switch (weight) {
      'high' => ('高频', c.warningBg, c.warning),
      'mid' => ('中频', c.primaryBg, c.primaryText),
      _ => ('低频', c.cardAlt, c.textTertiary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

// ===== 2. 知识点学习页 =====
class _LearnView extends StatelessWidget {
  final GrammarTopic topic;
  const _LearnView({required this.topic});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = GrammarStore.instance;
    final p = store.progressOf(topic.id);
    return Column(children: [
      // 顶部返回 + 标题
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
        child: Row(children: [
          IconButton(
            tooltip: '返回总览',
            icon: Icon(Icons.arrow_back_rounded, size: 20, color: c.textSecondary),
            onPressed: () => store.goBack(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(topic.name,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.text),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                _WeightBadge(weight: topic.weight),
              ]),
              const SizedBox(height: 2),
              Text(
                p.learned ? '已学会 · 最佳正确率 ${p.best}%' : '考纲第 ${topic.syllabusRef.join('、')} 项 · 尚未学习',
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          children: [
            // 讲解（分段渲染）
            if (topic.intro.isNotEmpty) ...[
              const _SectionLabel(icon: Icons.lightbulb_outline_rounded, text: '讲解'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final para in topic.intro.split('\n').where((s) => s.trim().isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(para.trim(), style: TextStyle(fontSize: 13.5, color: c.text, height: 1.7)),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            // 公式卡
            if (topic.formula.isNotEmpty) ...[
              const _SectionLabel(icon: Icons.functions_rounded, text: '公式'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.primaryBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.primaryBorder),
                ),
                child: Text(topic.formula,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.primaryText, height: 1.7)),
              ),
              const SizedBox(height: 16),
            ],
            // 例句
            if (topic.examples.isNotEmpty) ...[
              const _SectionLabel(icon: Icons.format_quote_rounded, text: '例句'),
              const SizedBox(height: 8),
              for (final ex in topic.examples) ...[
                _ExampleCard(example: ex),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
            ],
            // 易错点
            if (topic.pitfalls.isNotEmpty) ...[
              const _SectionLabel(icon: Icons.warning_amber_rounded, text: '易错点'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.warningBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.warning.withValues(alpha: 0.3)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final tip in topic.pitfalls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Icon(Icons.error_outline_rounded, size: 14, color: c.warning),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tip, style: TextStyle(fontSize: 13, color: c.text, height: 1.6))),
                      ]),
                    ),
                ]),
              ),
            ],
          ],
        ),
      ),
      // 底部开始练习
      Container(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
        child: Row(children: [
          Expanded(
            child: Text(
              '随堂练习 ${topic.quiz.length} 题 · 点击选项即时判分',
              style: TextStyle(fontSize: 12, color: c.textTertiary),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.quiz_rounded, size: 18, color: Colors.white),
            label: const Text('开始练习', style: TextStyle(color: Colors.white, fontSize: 14)),
            onPressed: topic.quiz.isEmpty ? null : () => store.startPractice(topic),
          ),
        ]),
      ),
    ]);
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(children: [
      Icon(icon, size: 16, color: c.primaryText),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
    ]);
  }
}

class _ExampleCard extends StatelessWidget {
  final GrammarExample example;
  const _ExampleCard({required this.example});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final ttsAvailable = TtsService.instance.available;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(example.en, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text, height: 1.5)),
            const SizedBox(height: 4),
            Text(example.zh, style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.5)),
            if (example.point.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: c.primaryBg, borderRadius: BorderRadius.circular(8)),
                child: Text(example.point, style: TextStyle(fontSize: 11, color: c.primaryText)),
              ),
            ],
          ]),
        ),
        if (ttsAvailable)
          IconButton(
            tooltip: '朗读',
            icon: Icon(Icons.volume_up_rounded, size: 20, color: c.primaryText),
            onPressed: () => TtsService.instance.speakText(example.en),
          ),
      ]),
    );
  }
}

// ===== 3. 随堂练习页 =====
class _QuizView extends StatelessWidget {
  final GrammarTopic topic;
  const _QuizView({required this.topic});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = GrammarStore.instance;
    if (store.sessionQuiz.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.quiz_rounded, size: 40, color: c.textTertiary),
          const SizedBox(height: 10),
          Text('该知识点暂无练习题', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: () => store.goBack(), child: const Text('返回学习')),
        ]),
      );
    }
    return Column(children: [
      // 顶部：返回 + 进度
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
        child: Row(children: [
          IconButton(
            tooltip: '返回学习页',
            icon: Icon(Icons.arrow_back_rounded, size: 20, color: c.textSecondary),
            onPressed: () => store.goBack(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text('${topic.name} · 随堂练习',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                overflow: TextOverflow.ellipsis),
          ),
          Text('${store.sessionIndex + 1} / ${store.sessionQuiz.length}',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.primaryText)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (store.sessionIndex + (store.sessionPicks[store.sessionIndex] != null ? 1 : 0)) / store.sessionQuiz.length,
            minHeight: 5,
            backgroundColor: c.progressBg,
            valueColor: AlwaysStoppedAnimation<Color>(c.primary),
          ),
        ),
      ),
      Expanded(child: store.sessionFinished ? const _ResultCard() : _QuestionCard(index: store.sessionIndex)),
    ]);
  }
}

class _QuestionCard extends StatelessWidget {
  final int index;
  const _QuestionCard({required this.index});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = GrammarStore.instance;
    final quiz = store.sessionQuiz[index];
    final pick = store.sessionPicks[index];
    final answered = pick != null;
    final correct = answered && store.sessionResults[index];
    const letters = ['A', 'B', 'C', 'D'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      children: [
        // 题干
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Text(quiz.question, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.text, height: 1.6)),
        ),
        const SizedBox(height: 12),
        // 四选一选项瓦片
        for (var i = 0; i < quiz.options.length && i < 4; i++)
          _GrammarOptionTile(
            letter: letters[i],
            text: quiz.options[i],
            state: !answered
                ? _TileState.normal
                : (i == quiz.answerIdx
                    ? _TileState.correct
                    : (i == pick ? _TileState.wrong : _TileState.dim)),
            onTap: answered ? null : () => store.answerOption(i),
          ),
        // 判分后显示解析
        if (answered) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: correct ? c.successBg : c.dangerBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: correct ? c.successBorder : c.dangerBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(correct ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    size: 18, color: correct ? kSuccess : kDanger),
                const SizedBox(width: 6),
                Text(correct ? '回答正确' : '回答错误 · 正确答案 ${quiz.answer}',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: correct ? kSuccess : kDanger)),
              ]),
              if (quiz.analysis.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(quiz.analysis, style: TextStyle(fontSize: 13, color: c.text, height: 1.6)),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: c.primary,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 17, color: Colors.white),
              label: Text(index + 1 < store.sessionQuiz.length ? '下一题' : '查看成绩',
                  style: const TextStyle(color: Colors.white, fontSize: 13.5)),
              onPressed: () => store.nextQuestion(),
            ),
          ),
        ],
      ],
    );
  }
}

/// 选项瓦片状态
enum _TileState { normal, correct, wrong, dim }

/// 自研轻量四选一选项瓦片（视觉参考 exam_page 的 _OptionTile，独立实现并适配深浅色）
class _GrammarOptionTile extends StatelessWidget {
  final String letter;
  final String text;
  final _TileState state;
  final VoidCallback? onTap;
  const _GrammarOptionTile({required this.letter, required this.text, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    final (bg, border, letterBg, letterFg, textFg) = switch (state) {
      _TileState.correct => (
          kSuccess.withValues(alpha: isLight ? 0.08 : 0.18),
          kSuccess.withValues(alpha: 0.55),
          kSuccess,
          Colors.white,
          c.text,
        ),
      _TileState.wrong => (
          kDanger.withValues(alpha: isLight ? 0.08 : 0.18),
          kDanger.withValues(alpha: 0.55),
          kDanger,
          Colors.white,
          c.text,
        ),
      _TileState.dim => (
          c.card.withValues(alpha: isLight ? 0.5 : 0.4),
          c.border,
          c.cardAlt,
          c.textTertiary,
          c.textTertiary,
        ),
      _TileState.normal => (
          c.card,
          c.border,
          c.cardAlt,
          c.textSecondary,
          c.text,
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: state == _TileState.normal ? 1 : 1.4),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: letterBg,
                  shape: BoxShape.circle,
                  border: state == _TileState.normal ? Border.all(color: c.border) : null,
                ),
                child: Text(letter,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: letterFg)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Text(text, style: TextStyle(fontSize: 13.5, color: textFg, height: 1.55)),
                    ),
                    if (state == _TileState.correct)
                      const Icon(Icons.check_circle_rounded, size: 18, color: kSuccess)
                    else if (state == _TileState.wrong)
                      const Icon(Icons.cancel_rounded, size: 18, color: kDanger),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ===== 练习结束成绩卡 =====
class _ResultCard extends StatelessWidget {
  const _ResultCard();

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final store = GrammarStore.instance;
    final pct = store.sessionScorePct;
    final wrongCount = store.wrongIndexes.length;
    final pctColor = pct >= 80 ? c.scoreHigh : (pct >= 60 ? c.scoreMid : c.scoreLow);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
      children: [
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Column(children: [
              Text('练习完成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
              const SizedBox(height: 14),
              Text('$pct%', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: pctColor)),
              const SizedBox(height: 4),
              Text('正确率', style: TextStyle(fontSize: 12, color: c.textTertiary)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _ResultStat(label: '总题数', value: '${store.sessionQuiz.length}', color: c.text),
                const SizedBox(width: 28),
                _ResultStat(label: '答对', value: '${store.sessionCorrectCount}', color: kSuccess),
                const SizedBox(width: 28),
                _ResultStat(label: '答错', value: '$wrongCount', color: kDanger),
              ]),
              if (store.aiMessage.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(store.aiMessage,
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.textTertiary)),
              ],
              const SizedBox(height: 20),
              // AI 出更多题
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: store.aiLoading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_awesome_rounded, size: 17, color: Colors.white),
                  label: Text(store.aiLoading ? 'AI 正在出题...' : 'AI 出更多题',
                      style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                  onPressed: store.aiLoading ? null : () => store.requestAiQuiz(),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                if (wrongCount > 0) ...[
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kDanger,
                          side: BorderSide(color: kDanger.withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.replay_rounded, size: 17),
                        label: Text('错题重练 ($wrongCount)'),
                        onPressed: () => store.retryWrong(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.list_alt_rounded, size: 17),
                      label: const Text('返回'),
                      onPressed: () => store.backToOverview(),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ResultStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ResultStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 11, color: c.textTertiary)),
    ]);
  }
}
