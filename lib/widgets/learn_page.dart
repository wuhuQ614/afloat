/// 学习页：AI智能出题面板 + 当前题目 + 对话助手
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/dict_service.dart';
import '../services/tts_service.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, kPrimaryLight, kSuccess, kDanger, AppColors;
import 'settings_dialog.dart';
import 'glass_background.dart';

const _primary = kPrimary;
const _primaryLight = kPrimaryLight;
const _success = kSuccess;
const _danger = kDanger;

/// 文本渲染单元：要么是单个普通 token，要么是一个词组（多个连续 token）
class _TextUnit {
  final WordToken? token;       // 单个 token 模式
  final List<WordToken>? groupTokens; // 词组模式：组内所有 token（含标点夹在中间的情况一般不会有）
  final PhraseInfo? phraseInfo; // 词组模式：词组信息

  const _TextUnit.single(this.token)
      : groupTokens = null,
        phraseInfo = null;

  const _TextUnit.phrase(this.groupTokens, this.phraseInfo)
      : token = null;

  bool get isSingle => token != null;
  bool get isPhrase => groupTokens != null;
}

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
  OverlayEntry? _wordPopup;
  final GlobalKey _popupAnchorKey = GlobalKey();

  /// 记录当前题目对应的 questionSeq，换题（对话指令出题/换一道等）时自动清空作答区
  late int _questionSeq;

  @override
  void initState() {
    super.initState();
    _questionSeq = widget.state.questionSeq;
    widget.state.addListener(_onQuestionChanged);
  }

  void _onQuestionChanged() {
    if (widget.state.questionSeq == _questionSeq) return;
    _questionSeq = widget.state.questionSeq;
    _answerCtrl.clear();
    widget.state.textAnswerValue = '';
    _showAnalysis = false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.state.removeListener(_onQuestionChanged);
    _dismissWordPopup();
    _answerCtrl.dispose();
    super.dispose();
  }

  AppState get s => widget.state;

  void _dismissWordPopup() {
    _wordPopup?.remove();
    _wordPopup = null;
  }

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
    final c = AppColors.of(context);
    return Row(children: [
      _Tag(text: qTypeName(q.type), color: _primary),
      const SizedBox(width: 8),
      _Tag(text: levelName(q.level), color: c.warning),
      if (q.type == QType.translation) ...[
        const SizedBox(width: 12),
        Container(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _buildDirSwitch('中', s.isZh2En, () => s.setDirection('zh2en'), c),
            const SizedBox(width: 3),
            _buildDirSwitch('英', !s.isZh2En, () => s.setDirection('en2zh'), c),
          ]),
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

  // 中英方向分段切换：
  //  - 浅色主题：选中态用「深色字 + 浅灰容器」(避免白字融白底)
  //  - 深色主题：选中态用「白色字 + 深灰容器」(保持原有对比)
  Widget _buildDirSwitch(String label, bool active, VoidCallback onTap, AppColors c) {
    // 选中态前景色按主题取
    final activeTextColor = c.isLight ? c.primaryText : Colors.white;
    final text = Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: active ? activeTextColor : c.primaryText.withValues(alpha: 0.55),
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: active
          ? Container(
              width: 34,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.chipUnselected,
                borderRadius: BorderRadius.circular(6),
              ),
              child: text,
            )
          : SizedBox(width: 34, height: 26, child: Center(child: text)),
    );
  }

  // ===== 题目内容卡片 =====
  Widget _buildQuestionCard(Question q, bool isLight) {
    final c = AppColors(isLight);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (ctx, constraints) {
          // 窄屏（手机）：方向标签独占一行，剖析模式+词汇剖析按钮在第二行
          final narrow = constraints.maxWidth < 420;
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.directionLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primaryText)),
              const SizedBox(height: 8),
              Row(children: [
                _buildAnalysisModeSwitcher(q, c),
                const SizedBox(width: 8),
                _buildAnalysisButton(q, c),
                const Spacer(),
                if (TtsService.instance.available)
                  InkWell(
                    onTap: () {
                      final textToSpeak = q.type == QType.reading && q.passage.isNotEmpty ? q.passage : q.text;
                      TtsService.instance.speakText(textToSpeak);
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.textTertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.volume_up_rounded, size: 14, color: c.textSecondary),
                        const SizedBox(width: 4),
                        Text('朗读', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary)),
                      ]),
                    ),
                  ),
              ]),
            ]);
          }
          // 宽屏：保持原样
          return Row(children: [
            Text(s.directionLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primaryText)),
            const Spacer(),
            _buildAnalysisModeSwitcher(q, c),
            const SizedBox(width: 8),
            _buildAnalysisButton(q, c),
            const SizedBox(width: 8),
            if (TtsService.instance.available)
              InkWell(
                onTap: () {
                  final textToSpeak = q.type == QType.reading && q.passage.isNotEmpty ? q.passage : q.text;
                  TtsService.instance.speakText(textToSpeak);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.textTertiary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.volume_up_rounded, size: 14, color: c.textSecondary),
                    const SizedBox(width: 4),
                    Text('朗读', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary)),
                  ]),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 12),
        // 阅读理解：展示短文
        if (q.type == QType.reading && q.passage.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.cardAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: (_showAnalysis || s.chatTriggeredAnalysis) && s.analysisTokens.isNotEmpty
                ? _buildAnalyzedText(q.passage, isLight)
                : Text(q.passage, style: TextStyle(fontSize: 14, height: 1.8, color: c.text)),
          ),
          const SizedBox(height: 16),
        ],
        // 题目文本（翻译题显示实时进度变色）
        if (q.type != QType.reading || q.passage.isEmpty)
          q.type == QType.translation && s.textAnswerValue.isNotEmpty && !_showAnalysis && !s.chatTriggeredAnalysis
              ? _buildTextWithProgress(q, isLight)
              : ((_showAnalysis || s.chatTriggeredAnalysis) && s.analysisTokens.isNotEmpty
                  ? _buildAnalyzedText(_analysisSource(q), isLight)
                  : Text(q.text, style: TextStyle(fontSize: 15, height: 1.7, color: c.text))),
        // 选择题：显示题干
        if (q.type == QType.choice && q.question.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(q.question, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
        ],
        // 分析中提示
        if ((_showAnalysis || s.chatTriggeredAnalysis) && s.analyzing) ...[
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: c.primaryText)),
            const SizedBox(width: 8),
            Text('分析中...', style: TextStyle(fontSize: 12, color: c.textTertiary)),
          ]),
        ],
      ]),
    );
  }

  // ===== 词汇剖析按钮（提取为独立方法，供 LayoutBuilder 窄屏/宽屏共用） =====
  /// 词汇剖析的源文本：一律剖析英文内容，避免翻译题中译英时剖析中文题目。
  /// 阅读剖析短文；翻译题剖析英文答案；其余题型剖析题干文本。
  String _analysisSource(Question q) {
    if (q.type == QType.reading && q.passage.isNotEmpty) return q.passage;
    if (q.type == QType.translation && q.english.isNotEmpty) return q.english;
    return q.text;
  }

  Widget _buildAnalysisButton(Question q, AppColors c) {
    return InkWell(
      onTap: () {
        if ((s.analysisMode == 'normal' || s.analysisMode == 'deep') && !s.apiConfig.ready) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('API 未配置'),
              content: const Text('API 尚未配置，请前往设置页面中配置。'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                TextButton(onPressed: () { Navigator.of(ctx).pop(); showDialog(context: context, builder: (_) => const SettingsDialog()); }, child: const Text('去设置')),
              ],
            ),
          );
          return;
        }
        setState(() => _showAnalysis = !_showAnalysis);
        if (_showAnalysis) {
          s.analyzeWords(_analysisSource(q));
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _showAnalysis ? c.primaryBgStrong : c.textTertiary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_rounded, size: 14, color: _showAnalysis ? c.primaryText : c.textTertiary),
          const SizedBox(width: 4),
          Text(_showAnalysis ? '收起剖析' : '词汇剖析', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _showAnalysis ? c.primaryText : c.textSecondary)),
        ]),
      ),
    );
  }

  // ===== 剖析模式三选一分段控件 =====
  Widget _buildAnalysisModeSwitcher(Question q, AppColors c) {
    const modes = [('fast', '快速'), ('normal', '正常'), ('deep', '深度')];
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.textTertiary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (mode, label) in modes)
          InkWell(
            onTap: s.analyzing
                ? null
                : () {
                    if (s.analysisMode == mode) return;
                    // 检查API配置（正常/深度模式需要API）
                    if ((mode == 'normal' || mode == 'deep') && !s.apiConfig.ready) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('API 未配置'),
                          content: const Text('API 尚未配置，请前往设置页面中配置。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                showDialog(context: context, builder: (_) => const SettingsDialog());
                              },
                              child: const Text('去设置'),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                    s.setAnalysisMode(mode);
                    // 已有剖析结果时按新模式重新剖析（缓存 key 含 mode，命中缓存则即时切换）
                    if (_showAnalysis && s.analysisTokens.isNotEmpty) {
                      s.analyzeWords(q.text);
                    }
                  },
            borderRadius: BorderRadius.circular(5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: s.analysisMode == mode ? c.primaryBgStrong : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: s.analysisMode == mode ? FontWeight.w600 : FontWeight.w400,
                  color: s.analysisMode == mode ? c.primaryText : c.textTertiary,
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // ===== 在原文上标注词汇剖析 =====
  Widget _buildAnalyzedText(String text, bool isLight) {
    final c = AppColors(isLight);
    final tokens = s.analysisTokens;
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    final fontSize = isMobile ? 13.0 : 15.0;
    if (tokens.isEmpty) return Text(text, style: TextStyle(fontSize: fontSize, height: 1.7, color: c.text));

    // 按 phraseGroup 合并相邻同组词组 token，构建渲染单元
    // 注意：词组单词之间的空格/标点 token 没有 phraseGroup，需要手动纳入
    final units = <_TextUnit>[];
    var i = 0;
    while (i < tokens.length) {
      final t = tokens[i];
      if (t.phraseGroup.isNotEmpty) {
        final group = t.phraseGroup;
        final groupTokens = <WordToken>[];
        PhraseInfo? pi;
        // 收集该词组的所有 token：包括单词和单词之间的空格/标点
        while (i < tokens.length) {
          final gt = tokens[i];
          // 如果下一个 token 是 other（空格/标点），且后面还有同组单词，则一并纳入
          if (gt.phraseGroup == group) {
            groupTokens.add(gt);
            if (pi == null) {
              for (final p in gt.phrases) {
                if (p.text == group) { pi = p; break; }
              }
            }
            i++;
          } else if (gt.type == 'other' && i + 1 < tokens.length && tokens[i + 1].phraseGroup == group) {
            // 空格/标点夹在同组单词之间，纳入词组
            groupTokens.add(gt);
            i++;
          } else {
            break;
          }
        }
        units.add(_TextUnit.phrase(
          groupTokens,
          pi ?? PhraseInfo(text: group, translation: ''),
        ));
      } else {
        units.add(_TextUnit.single(t));
        i++;
      }
    }

    return Wrap(
      spacing: 0,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: units.map((u) {
        if (u.isSingle) {
          final token = u.token!;
          final isWord = token.type == 'word' || token.type == 'phrase';
          if (!isWord) {
            return Text(token.text, style: TextStyle(fontSize: fontSize, height: 1.7, color: c.text));
          }
          return Builder(
            builder: (ctx) => InkWell(
              onTap: () => _showWordPopupAbove(ctx, token),
              child: Text(
                token.text,
                style: TextStyle(
                  fontSize: fontSize,
                  height: 1.7,
                  color: c.text,
                  decoration: TextDecoration.underline,
                  decorationColor: c.textTertiary,
                  decorationThickness: 1.2,
                ),
              ),
            ),
          );
        } else {
          // 词组：每个单词各自一条灰细下划线（紧贴文字），词组下方一条贯穿的红色长下划线
          // 用 Stack 让红线紧贴文字底部，而不是垂直堆叠
          final groupTokens = u.groupTokens!;
          
          return IntrinsicWidth(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 单词行：每个单词独立可点击
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: groupTokens.map((t) {
                    final isWord = t.type == 'word' || t.type == 'phrase';
                    if (!isWord) {
                      return Text(t.text, style: TextStyle(fontSize: fontSize, height: 1.7, color: c.text));
                    }
                    return Builder(
                      builder: (ctx) => InkWell(
                        onTap: () => _showWordPopupAbove(ctx, t),
                        child: Text(
                          t.text,
                          style: TextStyle(
                            fontSize: fontSize,
                            height: 1.7,
                            color: c.text,
                            decoration: TextDecoration.underline,
                            decorationColor: c.textTertiary,
                            decorationThickness: 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                // 红色长下划线：紧贴文字底部（bottom: -2 让线与文字下划线重叠一点）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: -2,
                  child: Container(
                    height: 1.5,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
            ),
          );
        }
      }).toList(),
    );
  }

  // ===== 翻译进度：在原文上直接变色（已翻译单词变紫色） =====
  Widget _buildTextWithProgress(Question q, bool isLight) {
    final c = AppColors(isLight);
    final originalText = q.text; // 原文（用户要翻译的文本）
    final targetText = s.isZh2En ? q.english : q.chinese; // 目标译文
    final userInput = s.textAnswerValue.trim();

    if (originalText.isEmpty || targetText.isEmpty || userInput.isEmpty) {
      return Text(originalText, style: TextStyle(fontSize: 15, height: 1.7, color: c.text));
    }

    // 提取原文中的"词"
    final List<String> originalWords;
    final List<int> originalWordStarts; // 每个词在原文中的起始位置
    if (s.isZh2En) {
      // 中文原文：按字拆分
      originalWords = <String>[];
      originalWordStarts = <int>[];
      for (var i = 0; i < originalText.length; i++) {
        final ch = originalText[i];
        if (ch.trim().isNotEmpty && !RegExp(r'[\s\p{P}]', unicode: true).hasMatch(ch)) {
          originalWords.add(ch);
          originalWordStarts.add(i);
        }
      }
    } else {
      // 英文原文：按单词拆分
      originalWords = <String>[];
      originalWordStarts = <int>[];
      final re = RegExp(r"[A-Za-z']+");
      for (final m in re.allMatches(originalText)) {
        originalWords.add(m.group(0)!);
        originalWordStarts.add(m.start);
      }
    }

    if (originalWords.isEmpty) {
      return Text(originalText, style: TextStyle(fontSize: 15, height: 1.7, color: c.text));
    }

    // 提取用户输入中的"词"
    final List<String> userWords;
    if (s.isZh2En) {
      // 用户输入英文
      userWords = RegExp(r"[A-Za-z']+")
          .allMatches(userInput.toLowerCase())
          .map((m) => m.group(0)!)
          .toList();
    } else {
      // 用户输入中文
      userWords = userInput
          .split('')
          .where((c) => c.trim().isNotEmpty && !RegExp(r'[\s\p{P}]', unicode: true).hasMatch(c))
          .map((c) => c.toLowerCase())
          .toList();
    }

    // 子序列匹配：用户输入按顺序匹配目标译文中的词
    // 然后计算匹配比例，标记原文中对应位置的词为"已完成"
    final targetWords = s.isZh2En
        ? RegExp(r"[A-Za-z']+").allMatches(targetText).map((m) => m.group(0)!.toLowerCase()).toList()
        : targetText.split('').where((c) => c.trim().isNotEmpty && !RegExp(r'[\s\p{P}]', unicode: true).hasMatch(c)).map((c) => c.toLowerCase()).toList();

    // 计算用户输入匹配了多少目标词
    int matchedTargetCount = 0;
    int userIdx = 0;
    for (var i = 0; i < targetWords.length && userIdx < userWords.length; i++) {
      if (targetWords[i] == userWords[userIdx]) {
        matchedTargetCount++;
        userIdx++;
      }
    }

    // 根据匹配比例，标记原文中前 N 个词为"已完成"
    final progressRatio = targetWords.isNotEmpty ? matchedTargetCount / targetWords.length : 0.0;
    final completedOriginalCount = (progressRatio * originalWords.length).round();

    // 构建带颜色的原文
    final spans = <InlineSpan>[];
    int wordIdx = 0;
    int pos = 0;
    final highlightColor = c.primaryText;

    while (pos < originalText.length) {
      // 找到当前位置是否是某个词的起始
      final wordPos = originalWordStarts.indexOf(pos);
      if (wordPos >= 0 && wordPos < originalWords.length) {
        final isCompleted = wordIdx < completedOriginalCount;
        spans.add(TextSpan(
          text: originalWords[wordIdx],
          style: TextStyle(
            fontSize: 15,
            height: 1.7,
            color: isCompleted ? highlightColor : c.text,
            fontWeight: isCompleted ? FontWeight.w700 : FontWeight.normal,
          ),
        ));
        wordIdx++;
        pos += originalWords[wordIdx - 1].length;
      } else {
        // 非词字符（标点、空格等）
        spans.add(TextSpan(
          text: originalText[pos],
          style: TextStyle(fontSize: 15, height: 1.7, color: c.text),
        ));
        pos++;
      }
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  // ===== 在单词上方显示气泡 =====
  void _showWordPopupAbove(BuildContext context, WordToken token, {List<WordToken>? phraseTokens}) {
    _dismissWordPopup();

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 词组整体的位置和尺寸
    final wordSize = renderBox.size;
    final wordOffset = renderBox.localToGlobal(Offset.zero);

    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isMobile = AppScope.of(context).uiMode == 'mobile';

    const bubbleWidth = 260.0; // 更宽一些，便于容纳词组标题和单词明细
    final effectiveBubbleWidth = isMobile ? (screenWidth - 32).clamp(200.0, 260.0) : bubbleWidth;

    final translation = token.translation;
    final other = token.other;
    final wordText = token.word.isNotEmpty ? token.word : token.text;
    final phonetic = DictService.lookup(wordText.toLowerCase())?.phonetic ?? '';
    final ttsReady = TtsService.instance.available;

    final isLight = Theme.of(context).brightness == Brightness.light;
    final c = AppColors(isLight);

    // 判断是否为词组入口（phraseTokens 非空 或 token.phraseGroup 非空）
    final hasPhrase = phraseTokens != null || token.phraseGroup.isNotEmpty;
    final phraseInfo = token.phraseGroup.isNotEmpty
        ? token.phrases.where((p) => p.text == token.phraseGroup).firstOrNull
        : null;
    // 词组内的有效单词 token（过滤标点/空格）
    final phraseWordTokens = phraseTokens
            ?.where((t) => t.type == 'word' || t.type == 'phrase')
            .toList() ??
        <WordToken>[];

    // 默认显示词组视图（如果是词组入口）
    bool showPhrase = hasPhrase;

    // 粗略估算气泡高度（词组模式按最大内容估，单词模式按 3 个单词明细估）
    final estPhraseTransLines = ((phraseInfo?.translation.length ?? 0) / 22).ceil().clamp(1, 6);
    final estWordCards = phraseWordTokens.isEmpty ? 1 : phraseWordTokens.length.clamp(1, 5);
    double bubbleHeight = 30 + // 标题行
        22 + // 音标/发音行
        (showPhrase
            ? (8 + estPhraseTransLines * 18.2 + (other.isNotEmpty ? 3 + 16 : 0))
            : (8 + estWordCards * 42.0)) +
        8 + // 分隔
        28 + // 收藏按钮
        20; // padding + 余量

    double left = wordOffset.dx + (wordSize.width - effectiveBubbleWidth) / 2;
    double top = wordOffset.dy - bubbleHeight - 2;

    if (top < 10) {
      top = wordOffset.dy + wordSize.height + 2;
    }
    if (top + bubbleHeight > screenHeight - 10) {
      top = screenHeight - bubbleHeight - 10;
    }
    if (left < 8) left = 8;
    if (left + effectiveBubbleWidth > screenWidth - 8) {
      left = screenWidth - effectiveBubbleWidth - 8;
    }

    final isInWordBook = s.wordbook.any((e) => e.word.toLowerCase() == wordText.toLowerCase());

    _wordPopup = OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final displayTitle = (showPhrase && phraseInfo != null)
              ? phraseInfo.text
              : wordText;
          final displayTranslation = (showPhrase && phraseInfo != null)
              ? phraseInfo.translation
              : translation;
          final displayPhonetic = showPhrase ? '' : phonetic;
          final displayPos = showPhrase ? '' : token.pos;

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: _dismissWordPopup,
                  behavior: HitTestBehavior.translucent,
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: effectiveBubbleWidth,
                    constraints: BoxConstraints(
                      maxHeight: screenHeight - 40,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.overlay,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 标题行：词组/单词标题 + 词性胶囊 + 切换按钮
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  displayTitle,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: c.text,
                                  ),
                                ),
                              ),
                              if (displayPos.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: c.primaryBgStrong,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    displayPos,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: c.primaryText,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                              // 词组/单词切换按钮
                              if (hasPhrase) ...[
                                const Spacer(),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      showPhrase = !showPhrase;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: showPhrase
                                          ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                                          : c.inputFill,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: showPhrase
                                            ? const Color(0xFFEF4444)
                                            : c.border,
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          showPhrase ? Icons.group : Icons.text_fields,
                                          size: 12,
                                          color: showPhrase
                                              ? const Color(0xFFEF4444)
                                              : c.textSecondary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          showPhrase ? '词组' : '单词',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: showPhrase
                                                ? const Color(0xFFEF4444)
                                                : c.textSecondary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // 音标 + 发音按钮（仅单词模式或非词组入口时显示）
                          if (displayPhonetic.isNotEmpty || (ttsReady && !showPhrase)) ...[
                            const SizedBox(height: 2),
                            Row(children: [
                              if (ttsReady && !showPhrase)
                                InkWell(
                                  onTap: () => TtsService.instance.speakWord(wordText),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: Icon(Icons.volume_up, size: 14, color: c.primaryText),
                                  ),
                                ),
                              if (ttsReady && !showPhrase && displayPhonetic.isNotEmpty)
                                const SizedBox(width: 4),
                              if (displayPhonetic.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    '/$displayPhonetic/',
                                    style: TextStyle(fontSize: 12, color: c.textTertiary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ]),
                          ],
                          // —— 词组模式：词组整体释义 ——
                          if (showPhrase) ...[
                            if (displayTranslation.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  displayTranslation,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: c.text,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                            if (token.contextTranslation.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('词典：',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: c.textTertiary,
                                          fontWeight: FontWeight.w600)),
                                  Expanded(
                                    child: Text(token.contextTranslation,
                                        style: TextStyle(
                                            fontSize: 11, color: c.textTertiary, height: 1.3)),
                                  ),
                                ],
                              ),
                            ],
                          ]
                          // —— 单词模式：词组内每个单词的完整释义 ——
                          else if (phraseWordTokens.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              '词组内单词：',
                              style: TextStyle(
                                fontSize: 10,
                                color: c.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...phraseWordTokens.map((wt) {
                              // 优先用 token 上的 AI 释义，为空则用词典兜底
                              final wEntry = DictService.lookup(wt.text.toLowerCase());
                              final wPhon = wEntry?.phonetic ?? '';
                              final wPos = wt.pos.isNotEmpty ? wt.pos : (wEntry?.pos ?? '');
                              final wTrans = wt.translation.isNotEmpty
                                  ? wt.translation
                                  : (wEntry?.translation ?? '');
                              final wOther = wt.other.isNotEmpty
                                  ? wt.other
                                  : (wEntry?.other ?? '');
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: c.inputFill,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: c.border, width: 0.3),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Text(
                                          wt.text,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: c.text,
                                          ),
                                        ),
                                        if (wPos.isNotEmpty) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 0.5),
                                            decoration: BoxDecoration(
                                              color: c.primaryBgStrong,
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                            child: Text(
                                              wPos,
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: c.primaryText,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        if (ttsReady)
                                          InkWell(
                                            onTap: () =>
                                                TtsService.instance.speakWord(wt.text),
                                            borderRadius: BorderRadius.circular(3),
                                            child: Padding(
                                              padding: const EdgeInsets.all(1.5),
                                              child: Icon(
                                                Icons.volume_up,
                                                size: 12,
                                                color: c.primaryText,
                                              ),
                                            ),
                                          ),
                                        if (wPhon.isNotEmpty) ...[
                                          const SizedBox(width: 3),
                                          Text('/$wPhon/',
                                              style: TextStyle(
                                                  fontSize: 10, color: c.textTertiary)),
                                        ],
                                      ]),
                                      if (wTrans.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          wTrans,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: c.text,
                                              height: 1.35,
                                              fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                      if (wOther.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          wOther,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: c.textTertiary,
                                              height: 1.3),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ]
                          // —— 普通单个单词模式（非词组入口） ——
                          else ...[
                            if (displayTranslation.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(displayTranslation,
                                  style: TextStyle(
                                      fontSize: 13, color: c.text, height: 1.4)),
                            ],
                            if (token.contextTranslation.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('词典：',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: c.textTertiary,
                                          fontWeight: FontWeight.w600)),
                                  Expanded(
                                    child: Text(token.contextTranslation,
                                        style: TextStyle(
                                            fontSize: 11, color: c.textTertiary, height: 1.3)),
                                  ),
                                ],
                              ),
                            ],
                            if (other.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(other,
                                  style: TextStyle(
                                      fontSize: 11, color: c.textTertiary, height: 1.3)),
                            ],
                          ],
                          const SizedBox(height: 8),
                          // 收藏按钮（仅收藏当前主词，非词组）
                          Divider(height: 1, color: c.border),
                          const SizedBox(height: 4),
                          _WordBookButton(
                            word: wordText,
                            translation: translation,
                            added: isInWordBook,
                            state: s,
                            onChanged: () {
                              if (mounted) _dismissWordPopup();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    Overlay.of(context).insert(_wordPopup!);
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
    final c = AppColors(isLight);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('你的答案：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 10),
        TextField(
          controller: _answerCtrl,
          maxLines: 5,
          // 翻译题允许作答 1000 字，其余文本题（语法/写作）保持 500
          maxLength: q.type == QType.translation ? 1000 : 500,
          style: TextStyle(fontSize: 14, height: 1.6, color: c.text),
          decoration: InputDecoration(
            hintText: s.answerPlaceholder,
            hintStyle: TextStyle(fontSize: 13, color: c.textTertiary),
            filled: true,
            fillColor: c.inputFill,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
            contentPadding: const EdgeInsets.all(14),
          ),
          onChanged: (v) {
            s.textAnswerValue = v;
            setState(() {}); // 触发重建以更新翻译进度
          },
        ),
      ]),
    );
  }

  // ===== 选择题作答区 =====
  Widget _buildChoiceAnswer(Question q, bool isLight) {
    final c = AppColors(isLight);
    final highlight = c.primaryText;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('请选择答案：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 12),
        ...List.generate(q.options.length, (i) {
          final letter = 'ABCDEFGH'[i];
          final selected = q.userAnswerIdx == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: s.submitting ? null : () {
                s.currentQuestion = q.copyWith(userAnswerIdx: i);
                s.touch();
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? c.primaryBgStrong : c.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: selected ? highlight : c.chipBorder, width: selected ? 2 : 1),
                ),
                child: Row(children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: selected ? highlight : c.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? highlight : c.chipBorder),
                    ),
                    child: Center(child: Text(letter, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : c.textTertiary))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(q.options[i], style: TextStyle(fontSize: 13.5, color: selected ? highlight : c.text))),
                  if (selected) Icon(Icons.check_circle_rounded, size: 20, color: highlight),
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
    final c = AppColors(isLight);
    final highlight = c.primaryText;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('阅读理解作答：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 12),
        ...List.generate(q.questions.length, (qi) {
          final sub = q.questions[qi];
          final userAnswers = List<int?>.from(q.userAnswers);
          while (userAnswers.length <= qi) userAnswers.add(null);
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${qi + 1}. ${sub.question}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
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
                      s.touch();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? c.primaryBgStrong : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: selected ? highlight : c.chipBorder, width: selected ? 2 : 1),
                      ),
                      child: Row(children: [
                        Text('$letter.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? highlight : c.textTertiary)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(sub.options[i], style: TextStyle(fontSize: 13, color: selected ? highlight : c.text))),
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
    final c = AppColors.of(context);
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
              foregroundColor: s.isCurrentFavorite ? _primary : c.textTertiary,
              side: BorderSide(color: s.isCurrentFavorite ? _primary : c.chipBorder),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => s.toggleFavorite(),
            icon: Icon(s.isCurrentFavorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 18),
            label: Text(s.isCurrentFavorite ? '已收藏' : '收藏', style: const TextStyle(fontSize: 13)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      // 第二行：一键收藏单词
      Row(children: [
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textSecondary,
              side: BorderSide(color: c.chipBorder),
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

  // ===== 批改结果 =====
  Widget _buildGradingResult(Question q, bool isLight) {
    final grading = s.lastGrading;
    if (grading == null) return const SizedBox();
    final c = AppColors(isLight);
    final scoreColor = grading.score >= 80 ? c.scoreHigh : grading.score >= 60 ? c.scoreMid : c.scoreLow;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题 + 分数
        Row(children: [
          Text('AI 批改结果', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
          const Spacer(),
          Text('得分：', style: TextStyle(fontSize: 13, color: c.textTertiary)),
          Text('${grading.score}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scoreColor)),
          Text('/100', style: TextStyle(fontSize: 13, color: c.textTertiary)),
        ]),
        Divider(height: 24, color: c.border),
        // 正确答案
        if (grading.correctAnswer.isNotEmpty) ...[
          Text('正确答案', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.successBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.successBorder),
            ),
            child: Text(grading.correctAnswer, style: TextStyle(fontSize: 13.5, color: c.scoreHigh, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 16),
        ],
        // 错误分析
        if (grading.errors.isNotEmpty) ...[
          Text('错误分析', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(height: 8),
          ...List.generate(grading.errors.length, (i) {
            final e = grading.errors[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.dangerBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.dangerBorder),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. ${e.item}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.scoreLow)),
                  if (e.explain.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(e.explain, style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.5)),
                  ],
                ]),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
        // 知识点
        if (grading.knowledge.isNotEmpty) ...[
          Text('知识点总结', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in grading.knowledge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.primaryBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.primaryBorder),
                ),
                child: Text(k, style: TextStyle(fontSize: 12, color: c.primaryText)),
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

  @override
  void dispose() {
    _customReqCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    final isMixed = _selectedType == 'mixed';
    final card02 = _buildCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSectionHeader('02. 目标难度等级'),
        const SizedBox(height: 12),
        _buildDifficultyChips(),
      ]),
    );
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 01. 题型选择
        _buildSectionHeader('01. 题型选择'),
        const SizedBox(height: 12),
        _buildTypeGrid(),
        const SizedBox(height: 24),
        // 02. 目标难度等级
        card02,
        const SizedBox(height: 24),
        // 03. 题目规模与时间估算（综合模拟套卷为固定76题，隐藏滑块）
        if (!isMixed)
          _buildCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _buildSectionHeader('03. 题目规模与时间估算'),
                const Spacer(),
                Text('预估耗时: ${_estimateTime()}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primaryText)),
              ]),
              const SizedBox(height: 16),
              _buildScaleSliders(),
            ]),
          ),
        if (isMixed)
          _buildCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _buildSectionHeader('04. 全卷信息'),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.primaryBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('考试时间 120 分钟', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.primaryText)),
                ),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.primary.withValues(alpha: 0.12)),
                ),
                child: Row(children: [
                  _buildMetricChip('76', '题量', c),
                  const SizedBox(width: 12),
                  _buildMetricChip('150', '总分', c),
                  const SizedBox(width: 12),
                  _buildMetricChip('7', '题型', c),
                  const SizedBox(width: 12),
                  _buildMetricChip('120', '分钟', c),
                ]),
              ),
              const SizedBox(height: 10),
              Text('题型包含：词汇语法20 + 阅读20 + 完形15 + 补全对话5 + 选词填空10 + 英译汉5 + 写作1',
                  style: TextStyle(fontSize: 11.5, color: c.textTertiary, height: 1.5)),
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
              style: TextStyle(fontSize: 13, color: c.text),
              decoration: InputDecoration(
                hintText: isMixed
                    ? '例如：侧重商务话题、指定写作文体...'
                    : '例如：要求 50 词以内、中译英方向、侧重商务话题...',
                hintStyle: TextStyle(fontSize: 12.5, color: c.hintText),
                filled: true,
                fillColor: c.chipUnselected,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        // 生成按钮（纯玻璃：无底色，磨砂+紫边框+紫字；classic 模式保持紫色实底）
        SizedBox(
          width: double.infinity,
          height: 52,
          child: widget.state.isGlassUI
              ? _PureGlassGenerateButton(
                  onPressed: (widget.state.generating || widget.state.generatingFullExam) ? null : () => _generate(widget.state),
                  isLoading: (widget.state.generating || widget.state.generatingFullExam),
                  isMixed: isMixed,
                )
              : FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            onPressed: (widget.state.generating || widget.state.generatingFullExam) ? null : () => _generate(widget.state),
            child: (widget.state.generating || widget.state.generatingFullExam)
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(isMixed ? Icons.assignment_rounded : Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(isMixed ? '生成全卷' : '生成题目', style: const TextStyle(color: Colors.white)),
                  ]),
          ),
        ),
        const SizedBox(height: 32),
      ]),
    );
  }

  // ===== 语法学习快捷入口卡片 =====
  Widget _buildGrammarEntry(AppColors c) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.state.setPage(12),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: const Icon(Icons.school_rounded, size: 22, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('语法学习', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 3),
                Text('从零学会专升本语法', style: TextStyle(fontSize: 12, color: c.textTertiary)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.textTertiary),
          ]),
        ),
      ),
    );
  }

  Widget _buildMetricChip(String value, String label, AppColors c) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.primaryText)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: c.textTertiary)),
        ]),
      ),
    );
  }

  String _estimateTime() {
    final count = _countSlider.round();
    int totalSeconds;
    if (_selectedType == 'reading') {
      totalSeconds = count * 60; // 每题约1分钟（含阅读短文+3-4道小题）
    } else if (_selectedType == 'writing') {
      totalSeconds = count * 40; // 每题约40秒
    } else {
      totalSeconds = count * 20; // 每题20秒
    }
    if (totalSeconds < 60) return '${totalSeconds}秒';
    final minutes = (totalSeconds / 60).ceil();
    return '$minutes分钟';
  }

  Widget _buildSectionHeader(String text) {
    final c = AppColors.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: _primary, shape: BoxShape.circle)),
      const SizedBox(width: 8),
      Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
    ]);
  }

  // 纯玻璃卡片外壳：与上方三张题卡（_TypeCardV2）完全同款
  // glass：真实模糊 + 半透明白玻璃；classic：不透明实色（无毛玻璃）
  Widget _buildCard({required Widget child}) {
    final c = AppColors.of(context);
    final isGlass = AppScope.of(context).isGlassUI;
    final fillColor = (c.isLight ? Colors.white : const Color(0xFF2A2A32)).withValues(alpha: c.isLight ? 0.78 : 0.72);
    final card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isGlass ? fillColor : (c.isLight ? Colors.white : const Color(0xFF2A2A32)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: c.isLight ? Colors.white.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.12),
          width: 1.2,
        ),
        boxShadow: [
          // 中性阴影：去掉 kPrimary 紫色投影，与 _TypeCardV2 一致
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isLight ? 0.04 : 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isLight ? 0.02 : 0.10),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
    return isGlass
        ? ClipRRect(borderRadius: BorderRadius.circular(20), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: card))
        : card;
  }

  // ===== 01. 题型 3x2 网格 — 每张卡片自带毛玻璃 =====
  Widget _buildTypeGrid() {
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    final cols = isMobile ? 2 : 3;
    final types = [
      ('translation', '翻译题', '中英互译·长难句', Icons.translate_outlined),
      ('reading', '阅读理解', '细节理解·推断题', Icons.menu_book_outlined),
      ('grammar', '语法填空', '时态语态·从句', Icons.quiz_outlined),
      ('choice', '选择题', '单选 / 多选辨析', Icons.check_circle_outline),
      ('writing', '写作题', '应用文·议论文', Icons.edit_outlined),
      ('mixed', '综合模拟套卷', 'AI混合全题型考卷', Icons.layers_outlined),
    ];
    final rows = (types.length / cols).ceil();
    return Column(children: [
      for (var row = 0; row < rows; row++)
        Padding(
          padding: EdgeInsets.only(bottom: row < rows - 1 ? (isMobile ? 10 : 16) : 0),
          child: Row(children: [
            for (var col = 0; col < cols; col++)
              Expanded(
                child: _buildTypeCell(types, row * cols + col, isMobile, col, cols),
              ),
          ]),
        ),
    ]);
  }

  // 构建单个题型卡片（索引越界时渲染空白占位，避免报错灰屏）
  Widget _buildTypeCell(List<(String, String, String, IconData)> types, int idx, bool isMobile, int col, int cols) {
    if (idx >= types.length) {
      return const SizedBox.shrink();
    }
    final t = types[idx];
    return Padding(
      padding: EdgeInsets.only(right: col < cols - 1 ? (isMobile ? 10 : 16) : 0),
      child: _TypeCardV2(
        type: t.$1,
        title: t.$2,
        subtitle: t.$3,
        icon: t.$4,
        selected: _selectedType == t.$1,
        isMixed: t.$1 == 'mixed',
        onTap: () => setState(() => _selectedType = t.$1),
      ),
    );
  }

  // ===== 02. 难度选择 =====
  Widget _buildDifficultyChips() {
    final c = AppColors.of(context);
    final levels = [
      ('cet4', '四级'),
      ('zsb', '专升本'),
      ('easy', '简单'),
      ('medium', '中等'),
      ('hard', '困难'),
      ('maimemo', '墨墨词库'),
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
              color: _selectedLevel == l.$1 ? c.chipSelectedBg : c.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _selectedLevel == l.$1 ? c.chipSelectedBorder : c.chipBorder),
              // 选中态用中性阴影，不带紫色调
              boxShadow: _selectedLevel == l.$1 ? [BoxShadow(color: Colors.black.withValues(alpha: c.isLight ? 0.05 : 0.25), blurRadius: 8, offset: const Offset(0, 2))] : null,
            ),
            child: Text(l.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _selectedLevel == l.$1 ? c.chipSelectedText : c.textSecondary)),
          ),
        ),
    ]);
  }

  // ===== 03. 题目规模滑块 =====
  Widget _buildScaleSliders() {
    final c = AppColors.of(context);
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    final count = _countSlider.round();
    final wordCount = _wordCountSlider.round();
    return Row(children: [
      // 题量显示
      Container(
        width: isMobile ? 64 : 80,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: c.chipUnselected,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text('$count', style: TextStyle(fontSize: isMobile ? 24 : 28, fontWeight: FontWeight.w800, color: c.primaryText)),
          const SizedBox(height: 2),
          Text('题量', style: TextStyle(fontSize: 12, color: c.textTertiary)),
        ]),
      ),
      SizedBox(width: isMobile ? 12 : 20),
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
    final c = AppColors.of(context);
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    return Column(children: [
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: _primary,
          inactiveTrackColor: c.sliderInactive,
          thumbColor: _primary,
          activeTickMarkColor: _primary,
          inactiveTickMarkColor: c.sliderInactive,
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
            Expanded(child: Text(entry.value, textAlign: TextAlign.center, style: TextStyle(fontSize: isMobile ? 9 : 10.5, color: c.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ]),
      ),
    ]);
  }

  Future<void> _generate(AppState s) async {
    s.selectedType = _selectedType;
    s.selectedLevel = _selectedLevel;

    // 综合模拟套卷：先弹出确认对话框，确认后进入考场并逐批生成
    if (_selectedType == 'mixed') {
      final customText = _customReqCtrl.text.trim();
      // 弹出确认对话框
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('综合模拟套卷'),
          content: const Text('进入考场后，AI将逐批生成题目（每次约10题），共76题。\n\n是否进入考场？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('进入考场'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      
      final ok = await s.generateFullExam(customReq: customText);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('进入考场失败，请检查 API 配置后重试'), behavior: SnackBarBehavior.floating));
      }
      return;
    }

    final actualCount = _countSlider.round();
    final wordCount = _wordCountSlider.round();

    // 墨墨词库模式：MoE 式从词库中随机选取 1/7 词汇作为 AI 参考池出题
    if (_selectedLevel == 'maimemo') {
      if (s.maimemoWordbook.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('墨墨词库为空，请先在「更多功能 → 墨墨词库」中同步'), behavior: SnackBarBehavior.floating));
        return;
      }
      final refWords = s.maimemoRefWords();
      final customText = _customReqCtrl.text.trim();
      final parts = <String>[];
      if (customText.isNotEmpty) parts.add(customText);
      parts.add('每题约 $wordCount 词');
      final customReq = parts.join('；');
      final ok = await s.generateQuestions(count: actualCount, customReq: customReq, wordCount: wordCount, maimemoWords: refWords);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (ok) {
        messenger.showSnackBar(SnackBar(
            content: Text('已基于墨墨词库（${refWords.length} 个参考词）生成 $actualCount 道题目'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating));
        s.setPage(1);
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('生成失败，请检查 API 配置后重试'), behavior: SnackBarBehavior.floating));
      }
      return;
    }

    // 构建自定义要求
    final parts = <String>[];
    final customText = _customReqCtrl.text.trim();
    if (customText.isNotEmpty) parts.add(customText);
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

// ===== 纯玻璃生成按钮（无填充色，只做磨砂+紫边+紫字） =====
class _PureGlassGenerateButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isMixed;
  const _PureGlassGenerateButton({required this.onPressed, required this.isLoading, required this.isMixed});

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    const radius = BorderRadius.all(Radius.circular(14));
    final iconData = isMixed ? Icons.assignment_outlined : Icons.auto_awesome_outlined;
    final btnText = isMixed ? '生成全卷' : '生成题目';
    final isGlass = AppScope.of(context).isGlassUI;
    if (!isGlass) {
      // 经典模式：紫色实底按钮（无毛玻璃）
      return Material(
        color: disabled ? kPrimary.withValues(alpha: 0.35) : kPrimary,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: SizedBox(
            height: double.infinity,
            width: double.infinity,
            child: Center(
              child: isLoading
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(iconData, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        btnText,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                    ]),
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent, // 纯玻璃：无底色
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: disabled
                  ? kPrimary.withValues(alpha: 0.25)
                  : kPrimary.withValues(alpha: 0.65),
              width: 1.3,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: SizedBox(
              height: double.infinity,
              width: double.infinity,
              child: Center(
                child: isLoading
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: kPrimary))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(iconData, color: kPrimary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          btnText,
                          style: const TextStyle(color: kPrimary, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                        ),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== 题型卡片 V2（毛玻璃外观） =====
class _TypeCardV2 extends StatefulWidget {
  final String type;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool isMixed;
  final VoidCallback onTap;
  const _TypeCardV2({required this.type, required this.title, required this.subtitle, required this.icon, required this.selected, required this.isMixed, required this.onTap});

  @override
  State<_TypeCardV2> createState() => _TypeCardV2State();
}

class _TypeCardV2State extends State<_TypeCardV2> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isSelected = widget.selected;
    final isHovered = _hovered;
    final lift = (isHovered || isSelected) ? -1.5 : 0.0;
    final cardRadius = BorderRadius.circular(16);

    final content = Stack(children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 纯灰 outlined 图标，不再套紫色方块
        Icon(widget.icon, size: 28, color: c.textSecondary),
        const SizedBox(height: 14),
        Text(widget.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text(widget.subtitle, style: TextStyle(fontSize: 11, color: c.textTertiary)),
      ]),
      if (widget.isMixed)
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.chipBorder.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('MIX', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c.textSecondary)),
          ),
        ),
    ]);

    final isGlass = AppScope.of(context).isGlassUI;
    final cardFill = isGlass
        ? (c.isLight ? Colors.white : const Color(0xFF2A2A32)).withValues(
            alpha: isSelected ? 0.95 : (isHovered ? 0.85 : 0.7),
          )
        : (c.isLight ? Colors.white : const Color(0xFF2A2A32));
    final cardBody = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, lift, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardFill,
        borderRadius: cardRadius,
        border: Border.all(
          // 选中/悬停态边框统一用中性灰阶，与上方三张题卡同款
          color: isSelected
              ? (c.isLight ? Colors.black.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.30))
              : (isHovered
                  ? (c.isLight ? Colors.black.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.20))
                  : (c.isLight ? Colors.white.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.12))),
          width: isSelected ? 1.2 : 1,
        ),
        boxShadow: [
          // 中性阴影：与上方三张题卡同款，去掉 kPrimary 紫调
          if (isSelected)
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isLight ? 0.10 : 0.32),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          else if (isHovered)
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isLight ? 0.07 : 0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isLight ? 0.04 : 0.18),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: content,
    );
    final glassBody = isGlass
        ? ClipRRect(
            borderRadius: cardRadius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: cardBody,
            ),
          )
        : cardBody;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: glassBody,
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
    final isLight = Theme.of(context).brightness == Brightness.light;
    // 深色模式下给文字提亮一些，对比度更好
    final effectiveColor = isLight ? color : Color.lerp(color, Colors.white, 0.25) ?? color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: effectiveColor.withValues(alpha: isLight ? 0.12 : 0.22), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: effectiveColor)),
    );
  }
}

/// 词汇剖析气泡中的收藏按钮
class _WordBookButton extends StatefulWidget {
  final String word;
  final String translation;
  final bool added;
  final AppState state;
  final VoidCallback? onChanged;

  const _WordBookButton({
    required this.word,
    required this.translation,
    required this.added,
    required this.state,
    this.onChanged,
  });

  @override
  State<_WordBookButton> createState() => _WordBookButtonState();
}

class _WordBookButtonState extends State<_WordBookButton> {
  late bool _added = widget.added;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final addedColor = c.scoreHigh;
    final unaddedColor = c.primaryText;
    return SizedBox(
      width: double.infinity,
      height: 28,
      child: TextButton.icon(
        onPressed: _toggle,
        icon: Icon(
          _added ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
          size: 14,
          color: _added ? addedColor : unaddedColor,
        ),
        label: Text(
          _added ? '已加入生词本' : '加入生词本',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _added ? addedColor : unaddedColor),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }

  void _toggle() {
    if (_added) {
      widget.state.removeFromWordBook(widget.word);
    } else {
      widget.state.addToWordBook(widget.word, widget.translation);
    }
    setState(() => _added = !_added);
    widget.onChanged?.call();
  }
}
