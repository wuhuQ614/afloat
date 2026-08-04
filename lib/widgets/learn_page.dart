/// 学习页：AI智能出题面板 + 当前题目 + 对话助手
library;

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, kPrimaryLight, kSuccess, kDanger, kGradientStart, kGradientEnd;

const _primary = kPrimary;
const _primaryLight = kPrimaryLight;
const _success = kSuccess;
const _danger = kDanger;

class LearnPage extends StatefulWidget {
  final AppState state;
  const LearnPage({super.key, required this.state});

  @override
  State<LearnPage> createState() => _LearnPageState();
}

class AnswerPage extends StatefulWidget {
  final AppState state;
  const AnswerPage({super.key, required this.state});

  @override
  State<AnswerPage> createState() => _AnswerPageState();
}

class _AnswerPageState extends State<AnswerPage> {
  final TextEditingController _answerCtrl = TextEditingController();
  bool _showAnalysis = false;

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  AppState get s => widget.state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        final q = s.currentQuestion;
        final isLight = Theme.of(context).brightness == Brightness.light;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 题目标签栏
            _buildQuestionHeader(q),
            const SizedBox(height: 16),
            // 题目内容卡片
            _buildQuestionCard(q, isLight),
            // 词汇剖析面板
            if (_showAnalysis) ...[
              const SizedBox(height: 16),
              _buildAnalysisPanel(q, isLight),
            ],
            const SizedBox(height: 16),
            // 答题区
            _buildAnswerArea(q, isLight),
            const SizedBox(height: 16),
            // 操作栏
            _buildActionBar(q),
            // 批改结果
            if (s.hasGrading) ...[
              const SizedBox(height: 20),
              _buildGradingResult(q, isLight),
            ],
          ]),
        );
      },
    );
  }

  // ===== 题目标签栏 =====
  Widget _buildQuestionHeader(Question q) {
    return Row(children: [
      _Tag(text: qTypeName(q.type), color: _primary),
      const SizedBox(width: 8),
      _Tag(text: levelName(q.level), color: const Color(0xFFF59E0B)),
      if (q.type == QType.translation) ...[
        const SizedBox(width: 12),
        InkWell(
          onTap: () => s.setDirection(s.isZh2En ? 'en2zh' : 'zh2en'),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.swap_horiz_rounded, size: 14, color: _primary),
              const SizedBox(width: 4),
              Text(s.isZh2En ? '中→英' : '英→中', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _primary)),
            ]),
          ),
        ),
      ],
      const Spacer(),
      if (s.generatedQuestions.length > 1)
        TextButton.icon(
          onPressed: () {
            s.nextQuestion();
            _answerCtrl.clear();
            s.textAnswerValue = '';
          },
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('换一道'),
        ),
    ]);
  }

  // ===== 题目内容卡片 =====
  Widget _buildQuestionCard(Question q, bool isLight) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF2A2A40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLight ? const Color(0xFFE8E8F0) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.directionLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primary)),
        const SizedBox(height: 12),
        // 阅读理解：展示短文
        if (q.type == QType.reading && q.passage.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(q.passage, style: const TextStyle(fontSize: 14, height: 1.8, color: Color(0xFF1A1A2E))),
          ),
          const SizedBox(height: 16),
        ],
        // 题目文本
        if (q.type != QType.reading || q.passage.isEmpty)
          Text(q.text, style: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF1A1A2E))),
        // 选择题：显示题干
        if (q.type == QType.choice && q.question.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(q.question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
        ],
      ]),
    );
  }

  // ===== 答题区 =====
  Widget _buildAnswerArea(Question q, bool isLight) {
    // 阅读理解
    if (q.type == QType.reading && q.passage.isNotEmpty && q.questions.isNotEmpty) {
      return _buildReadingAnswer(q, isLight);
    }
    // 选择题
    if (q.type == QType.choice && q.options.isNotEmpty) {
      return _buildChoiceAnswer(q, isLight);
    }
    // 文本作答（翻译/语法/写作）
    return _buildTextAnswer(q, isLight);
  }

  // ===== 文本作答区 =====
  Widget _buildTextAnswer(Question q, bool isLight) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF2A2A40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLight ? const Color(0xFFE8E8F0) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('你的答案：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        const SizedBox(height: 10),
        TextField(
          controller: _answerCtrl,
          maxLines: 5,
          maxLength: 500,
          style: const TextStyle(fontSize: 14, height: 1.6),
          decoration: InputDecoration(
            hintText: s.answerPlaceholder,
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            filled: true,
            fillColor: isLight ? const Color(0xFFF8F6FF) : const Color(0xFF1E1E32),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
            contentPadding: const EdgeInsets.all(14),
          ),
          onChanged: (v) => s.textAnswerValue = v,
        ),
      ]),
    );
  }

  // ===== 选择题作答区 =====
  Widget _buildChoiceAnswer(Question q, bool isLight) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF2A2A40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLight ? const Color(0xFFE8E8F0) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('请选择答案：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ...List.generate(q.options.length, (i) {
          final letter = 'ABCDEFGH'[i];
          final selected = q.userAnswerIdx == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: s.submitting ? null : () {
                s.currentQuestion = q.copyWith(userAnswerIdx: i);
                s.notifyListeners();
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? _primary.withValues(alpha: 0.08) : (isLight ? const Color(0xFFF8F6FF) : const Color(0xFF1E1E32)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected ? _primary : (isLight ? const Color(0xFFE5E7EB) : Colors.white12), width: selected ? 2 : 1),
                ),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: selected ? _primary : (isLight ? Colors.white : const Color(0xFF2A2A40)),
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? _primary : Colors.grey.shade300),
                    ),
                    child: Center(child: Text(letter, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : Colors.grey.shade500))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(q.options[i], style: TextStyle(fontSize: 13.5, color: selected ? _primary : const Color(0xFF1A1A2E)))),
                  if (selected) Icon(Icons.check_circle_rounded, size: 20, color: _primary),
                ]),
              ),
            ),
          );
        }),
      ]),
    );
  }

  // ===== 阅读理解作答区 =====
  Widget _buildReadingAnswer(Question q, bool isLight) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF2A2A40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLight ? const Color(0xFFE8E8F0) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('阅读理解作答：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ...List.generate(q.questions.length, (qi) {
          final sub = q.questions[qi];
          final userAnswers = List<int?>.from(q.userAnswers);
          while (userAnswers.length <= qi) userAnswers.add(null);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${qi + 1}. ${sub.question}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 8),
              ...List.generate(sub.options.length, (i) {
                final letter = 'ABCDEFGH'[i];
                final selected = userAnswers[qi] == i;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 16),
                  child: InkWell(
                    onTap: s.submitting ? null : () {
                      userAnswers[qi] = i;
                      s.currentQuestion = q.copyWith(userAnswers: userAnswers);
                      s.notifyListeners();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? _primary.withValues(alpha: 0.08) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? _primary : const Color(0xFFE5E7EB), width: selected ? 2 : 1),
                      ),
                      child: Row(children: [
                        Text('$letter.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? _primary : Colors.grey.shade500)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(sub.options[i], style: TextStyle(fontSize: 13, color: selected ? _primary : const Color(0xFF1A1A2E)))),
                      ]),
                    ),
                  ),
                );
              }),
            ]),
          );
        }),
      ]),
    );
  }

  // ===== 操作栏 =====
  Widget _buildActionBar(Question q) {
    final hasAnswer = (q.type == QType.choice && q.userAnswerIdx != null) ||
        (q.type == QType.reading && q.questions.isNotEmpty && q.userAnswers.any((a) => a != null)) ||
        (q.type != QType.choice && q.type != QType.reading && _answerCtrl.text.trim().isNotEmpty);
    return Column(children: [
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: hasAnswer && !s.submitting
                  ? () async {
                      if (q.type != QType.choice && q.type != QType.reading) {
                        s.textAnswerValue = _answerCtrl.text.trim();
                      }
                      await s.submitCurrent();
                    }
                  : null,
              child: s.submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('提交答案', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: const BorderSide(color: _primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              s.nextQuestion();
              _answerCtrl.clear();
              s.textAnswerValue = '';
              _showAnalysis = false;
            },
            child: const Text('换一道', style: TextStyle(fontSize: 14)),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: s.isCurrentFavorite ? _primary : Colors.grey.shade500,
              side: BorderSide(color: s.isCurrentFavorite ? _primary : Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => s.toggleFavorite(),
            icon: Icon(s.isCurrentFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 18),
            label: Text(s.isCurrentFavorite ? '已收藏' : '收藏', style: const TextStyle(fontSize: 13)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      // 第二行：词汇剖析 + 一键收藏单词
      Row(children: [
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _showAnalysis ? _primary : Colors.grey.shade600,
              side: BorderSide(color: _showAnalysis ? _primary : Colors.grey.shade300),
              backgroundColor: _showAnalysis ? _primary.withValues(alpha: 0.08) : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () {
              setState(() => _showAnalysis = !_showAnalysis);
              if (_showAnalysis && s.analysisTokens.isEmpty) {
                s.analyzeWords(q.text, force: true);
              }
            },
            icon: Icon(Icons.search_rounded, size: 16),
            label: Text(_showAnalysis ? '收起剖析' : '词汇剖析', style: const TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () {
              final result = s.recordWordsFromQuestion();
              if (result != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已记录 ${result.total} 个单词（${result.newCount} 个新词）'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: _success,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('未检测到可记录的英文单词'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: Icon(Icons.bookmark_add_outlined, size: 16),
            label: const Text('一键收藏单词', style: TextStyle(fontSize: 13)),
          ),
        ),
      ]),
    ]);
  }

  // ===== 词汇剖析面板 =====
  Widget _buildAnalysisPanel(Question q, bool isLight) {
    final tokens = s.analysisTokens;
    final isLoading = s.analyzing;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF2A2A40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLight ? const Color(0xFFE8E8F0) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.search_rounded, size: 18, color: _primary),
          const SizedBox(width: 8),
          const Text('词汇剖析', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (isLoading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (!isLoading && tokens.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => s.analyzeWords(q.text, force: true),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重新分析', style: TextStyle(fontSize: 12)),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        if (tokens.isEmpty && !isLoading)
          const Text('点击"词汇剖析"按钮开始分析', style: TextStyle(color: Colors.grey))
        else if (tokens.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tokens.map((token) {
              final isPhrase = token.type == 'phrase';
              final bgColor = isPhrase
                  ? _primary.withValues(alpha: 0.15)
                  : (isLight ? const Color(0xFFF5F5F5) : const Color(0xFF3A3A50));
              return Tooltip(
                message: token.translation.isEmpty ? '分析中...' : token.translation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: isPhrase
                        ? Border.all(color: _primary, width: 1.5)
                        : null,
                  ),
                  child: Text(
                    token.word,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isPhrase ? FontWeight.w600 : FontWeight.normal,
                      color: isPhrase ? _primary : null,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ]),
    );
  }

  // ===== 批改结果 =====
  Widget _buildGradingResult(Question q, bool isLight) {
    final grading = s.lastGrading;
    if (grading == null) return const SizedBox();
    final scoreColor = grading.score >= 80 ? _success : grading.score >= 60 ? const Color(0xFFF59E0B) : _danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF2A2A40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isLight ? const Color(0xFFE8E8F0) : Colors.white12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题 + 分数
        Row(children: [
          const Text('AI 批改结果', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          const Spacer(),
          Text('得分：', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          Text('${grading.score}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scoreColor)),
          Text('/100', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ]),
        const Divider(height: 24),
        // 正确答案
        if (grading.correctAnswer.isNotEmpty) ...[
          Text('正确答案', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _success.withValues(alpha: 0.2)),
            ),
            child: Text(grading.correctAnswer, style: TextStyle(fontSize: 13.5, color: _success, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 16),
        ],
        // 错误分析
        if (grading.errors.isNotEmpty) ...[
          Text('错误分析', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          ...List.generate(grading.errors.length, (i) {
            final e = grading.errors[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _danger.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _danger.withValues(alpha: 0.15)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ${e.item}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _danger)),
                  if (e.explain.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(e.explain, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, height: 1.5)),
                  ],
                ]),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        // 知识点
        if (grading.knowledge.isNotEmpty) ...[
          Text('知识点总结', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in grading.knowledge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _primary.withValues(alpha: 0.15)),
                ),
                child: Text(k, style: TextStyle(fontSize: 12, color: _primary)),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _LearnPageState extends State<LearnPage> {
  // AI出题面板状态
  String _selectedType = 'translation';
  String _selectedLevel = 'zsb';
  double _countSlider = 1;
  double _wordCountSlider = 80;
  final TextEditingController _customReqCtrl = TextEditingController();
  final Set<String> _focusAreas = {};

  static const _focusAreaOptions = [
    ('core_words', '核心高频词'),
    ('clause_inversion', '从句倒装'),
    ('long_sentence', '长难句切分'),
    ('logical_connectors', '逻辑衔接词'),
  ];

  @override
  void dispose() {
    _customReqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 01. 题型选择
        _buildSectionHeader('01. 题型选择'),
        const SizedBox(height: 12),
        _buildTypeGrid(),
        const SizedBox(height: 24),
        // 02. 目标难度等级 + 03. 强化侧重点（并排）
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _buildCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSectionHeader('02. 目标难度等级'),
                const SizedBox(height: 12),
                _buildDifficultyChips(),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildSectionHeader('03. 强化侧重点'),
                const SizedBox(height: 12),
                _buildFocusChips(),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        // 04. 题目规模与时间估算
        _buildCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _buildSectionHeader('04. 题目规模与时间估算'),
              const Spacer(),
              Text('预估耗时: ${_estimateTime()}分钟',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _primary)),
            ]),
            const SizedBox(height: 16),
            _buildScaleSliders(),
          ]),
        ),
        const SizedBox(height: 24),
        // 自定义提示
        _buildCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildSectionHeader('05. 自定义要求（可选）'),
            const SizedBox(height: 12),
            TextField(
              controller: _customReqCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '例如：要求 50 词以内、中译英方向、侧重商务话题...',
                hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                filled: true,
                fillColor: const Color(0xFFF8F6FF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        // 生成按钮
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            onPressed: widget.state.generating ? null : () => _generate(widget.state),
            child: widget.state.generating
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('生成题目', style: TextStyle(color: Colors.white)),
                  ]),
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  String _estimateTime() {
    final count = _countSlider.round();
    if (_selectedType == 'reading') return '${(count * 3).clamp(1, 30)}';
    if (_selectedType == 'writing') return '${(count * 2).clamp(1, 20)}';
    return '${count.clamp(1, 50)}';
  }

  Widget _buildSectionHeader(String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: _primary, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF4A4A6A))),
    ]);
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E8F0)),
      ),
      child: child,
    );
  }

  // ===== 01. 题型 3x2 网格 =====
  Widget _buildTypeGrid() {
    final types = [
      ('translation', '翻译题', '中英互译·长难句', Icons.translate_rounded, const Color(0xFF7C3AED)),
      ('reading', '阅读理解', '细节理解·推断题', Icons.menu_book_rounded, const Color(0xFF3B82F6)),
      ('grammar', '语法填空', '时态语态·从句', Icons.quiz_rounded, const Color(0xFF10B981)),
      ('choice', '选择题', '单选 / 多选辨析', Icons.check_circle_rounded, const Color(0xFFF59E0B)),
      ('writing', '写作题', '应用文·议论文', Icons.edit_rounded, const Color(0xFFEC4899)),
      ('mixed', '综合模拟套卷', 'AI混合全题型考卷', Icons.layers_rounded, const Color(0xFF8B5CF6)),
    ];
    return Column(children: [
      for (var row = 0; row < 2; row++)
        Padding(
          padding: EdgeInsets.only(bottom: row == 0 ? 12 : 0),
          child: Row(children: [
            for (var col = 0; col < 3; col++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: col < 2 ? 12 : 0),
                  child: _TypeCardV2(
                    type: types[row * 3 + col].$1,
                    title: types[row * 3 + col].$2,
                    subtitle: types[row * 3 + col].$3,
                    icon: types[row * 3 + col].$4,
                    iconColor: types[row * 3 + col].$5,
                    selected: _selectedType == types[row * 3 + col].$1,
                    isMixed: types[row * 3 + col].$1 == 'mixed',
                    onTap: () => setState(() => _selectedType = types[row * 3 + col].$1),
                  ),
                ),
              ),
          ]),
        ),
    ]);
  }

  // ===== 02. 难度选择 =====
  Widget _buildDifficultyChips() {
    final levels = [
      ('cet4', '四级'),
      ('zsb', '专升本'),
      ('easy', '简单'),
      ('medium', '中等'),
      ('hard', '困难'),
    ];
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final l in levels)
        InkWell(
          onTap: () => setState(() => _selectedLevel = l.$1),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _selectedLevel == l.$1 ? _primary : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _selectedLevel == l.$1 ? _primary : const Color(0xFFE5E7EB)),
              boxShadow: _selectedLevel == l.$1 ? [BoxShadow(color: _primary.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2))] : null,
            ),
            child: Text(l.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _selectedLevel == l.$1 ? Colors.white : Colors.grey.shade600)),
          ),
        ),
    ]);
  }

  // ===== 03. 强化侧重点（多选） =====
  Widget _buildFocusChips() {
    return Wrap(spacing: 10, runSpacing: 10, children: [
      for (final f in _focusAreaOptions)
        InkWell(
          onTap: () => setState(() {
            if (_focusAreas.contains(f.$1)) {
              _focusAreas.remove(f.$1);
            } else {
              _focusAreas.add(f.$1);
            }
          }),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _focusAreas.contains(f.$1) ? _primary.withValues(alpha: 0.1) : const Color(0xFFF8F6FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _focusAreas.contains(f.$1) ? _primary : const Color(0xFFE5E7EB)),
            ),
            child: Text(f.$2, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _focusAreas.contains(f.$1) ? _primary : Colors.grey.shade600)),
          ),
        ),
    ]);
  }

  // ===== 04. 题目规模滑块 =====
  Widget _buildScaleSliders() {
    final count = _countSlider.round();
    final wordCount = _wordCountSlider.round();
    return Row(children: [
      // 题量显示
      Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F6FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text('$count', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: _primary)),
          const SizedBox(height: 2),
          Text('题量', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
      const SizedBox(width: 20),
      // 两个滑块
      Expanded(
        child: Column(children: [
          // 题量滑块
          _buildSliderRow(
            value: _countSlider,
            min: 1,
            max: 50,
            divisions: 49,
            label: '$count',
            onChanged: (v) => setState(() => _countSlider = v),
            marks: {1.0: '1道(速练)', 10.0: '10', 25.0: '25(标准试卷)', 50.0: '50(深度模考)'},
          ),
          const SizedBox(height: 16),
          // 单词量滑块
          _buildSliderRow(
            value: _wordCountSlider,
            min: 30,
            max: 300,
            divisions: 27,
            label: '$wordCount词',
            onChanged: (v) => setState(() => _wordCountSlider = v),
            marks: {30.0: '30词', 80.0: '80词', 150.0: '150词', 300.0: '300词'},
          ),
        ]),
      ),
    ]);
  }

  Widget _buildSliderRow({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
    required Map<double, String> marks,
  }) {
    return Column(children: [
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: _primary,
          inactiveTrackColor: const Color(0xFFE5E7EB),
          thumbColor: _primary,
          activeTickMarkColor: _primary,
          inactiveTickMarkColor: const Color(0xFFE5E7EB),
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          for (final entry in marks.entries) ...[
            Expanded(child: Text(entry.value, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400))),
          ],
        ]),
      ),
    ]);
  }

  Future<void> _generate(AppState s) async {
    s.selectedType = _selectedType;
    s.selectedLevel = _selectedLevel;
    final actualCount = _countSlider.round();
    final wordCount = _wordCountSlider.round();

    // 构建自定义要求
    final parts = <String>[];
    final customText = _customReqCtrl.text.trim();
    if (customText.isNotEmpty) parts.add(customText);
    if (_focusAreas.isNotEmpty) {
      final focusLabels = _focusAreaOptions.where((f) => _focusAreas.contains(f.$1)).map((f) => f.$2).toList();
      parts.add('强化侧重点：${focusLabels.join('、')}');
    }
    parts.add('每题约 $wordCount 词');
    if (_selectedLevel == 'zsb') {
      parts.add('必须从专升本大纲词汇中选词，不得使用超纲词汇');
    }
    final customReq = parts.join('；');

    final ok = await s.generateQuestions(count: actualCount, customReq: customReq, wordCount: wordCount);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(SnackBar(content: Text(actualCount > 1 ? '已生成 $actualCount 道题目' : '题目已生成！'), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
    } else {
      messenger.showSnackBar(const SnackBar(content: Text('生成失败，请检查 API 配置后重试'), behavior: SnackBarBehavior.floating));
    }
  }
}

// ===== 题型卡片 V2（3x2 网格样式） =====
class _TypeCardV2 extends StatelessWidget {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool selected;
  final bool isMixed;
  final VoidCallback onTap;
  const _TypeCardV2({required this.type, required this.title, required this.subtitle, required this.icon, required this.iconColor, required this.selected, required this.isMixed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF5F3FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _primary : const Color(0xFFE5E7EB), width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: kPrimary.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 2))] : null,
        ),
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? kPrimary : const Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ]),
          if (isMixed)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('MIX', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kPrimary)),
              ),
            ),
          if (selected && !isMixed)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: _primary, shape: BoxShape.circle),
              ),
            ),
        ]),
      ),
    );
  }
}

// ===== 小组件 =====
class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
