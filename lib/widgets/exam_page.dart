/// 沉浸式考场界面（page=10）与成绩解析页（page=11）
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../state.dart';

/// 整个考试（含答题、成绩）外层容器。会根据 AppState.page 自动切换。
class ExamShell extends StatefulWidget {
  const ExamShell({super.key});

  @override
  State<ExamShell> createState() => _ExamShellState();
}

class _ExamShellState extends State<ExamShell> {
  Timer? _timer;
  late AppState _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _state = AppScope.of(context);
    if (_state.page == 10) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        _state.tickExamTimer();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        if (_state.page == 11 && _state.currentExamResult != null) {
          return ExamResultPage(state: _state);
        }
        if (_state.currentExamPaper == null) {
          return Container(
            color: const Color(0xFF0F172A),
            child: const Center(child: Text('暂无试卷', style: TextStyle(color: Colors.white))),
          );
        }
        return ExamRoomPage(state: _state);
      },
    );
  }
}

// ========= 沉浸考场 =========

class ExamRoomPage extends StatelessWidget {
  final AppState state;
  const ExamRoomPage({super.key, required this.state});

  String formatDuration(int s) {
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = s % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    // 还没生成任何题目时，全屏显示加载动画（放在最前面避免后续代码崩溃）
    if (state.examGeneratedCount == 0) {
      final genFailed = state.examGenerationDone && !state.examGeneratingBatch;
      return Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (genFailed)
                const Icon(Icons.error_outline_rounded, size: 56, color: Color(0xFFEF4444))
              else
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                genFailed ? '试卷生成失败' : '加载中...',
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (state.examGeneratingHint.isNotEmpty) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: Text(
                    state.examGeneratingHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.6),
                  ),
                ),
              ],
              if (genFailed) ...[
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () => state.generateFullExam(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新生成全卷'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final paper = state.currentExamPaper!;
    final total = paper.totalQuestions;
    final remaining = state.examRemainingSec;
    final totalMax = paper.totalTimeMin * 60;
    final timePct = totalMax <= 0 ? 0.0 : (totalMax - remaining) / totalMax;

    // 已答题数
    final answered = _countAnswered(state);

    final current = state.examCurrentQuestion.clamp(1, total);
    final resolved = state.resolveExamQuestion(current);
    final danger = remaining <= 600;

    // 手机端走全新布局（电脑端完全不变）
    final isMobile = state.uiMode == 'mobile';
    if (isMobile) {
      return _buildMobileExam(context, paper, resolved, current, answered, total, remaining, danger);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  // 中性色渐变（去掉粉紫色调）
                  colors: [Color(0xFFF0F2F6), Color(0xFFF5F6F9), Color(0xFFFAFAF8)],
                ),
              ),
              constraints: const BoxConstraints.expand(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧题号导航（手机端隐藏）
                  _buildLeftNav(paper),
                  // 中间答题区
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: _buildQuestionArea(paper, resolved, current),
                    ),
                  ),
                  // 右侧答题卡
                  SizedBox(
                    width: 220,
                    child: _buildAnswerCard(context, paper, current, answered, total, compact: false),
                  ),
                ],
              ),
            ),
            // 顶部生成状态横幅（生成中：进度条；失败：重新生成缺失部分）
            Positioned(
              top: 12,
              left: 310,
              right: 250,
              child: _ExamGenBanner(state: state),
            ),
          ],
        ),
      ),
    );
  }

  // ========= 手机端考场布局 =========

  Widget _buildMobileExam(BuildContext context, FullExamPaper paper, dynamic resolved, int current, int answered, int total, int remaining, bool danger) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // 中性色渐变（去掉粉紫色调）
              colors: [Color(0xFFF0F2F6), Color(0xFFF5F6F9), Color(0xFFFAFAF8)],
            ),
          ),
          child: Column(
            children: [
              // 顶部状态栏：倒计时 + 题号进度 + 答题卡入口
              _buildMobileTopBar(context, current, answered, total, remaining, danger),
              // 生成状态横幅（内联，不再 Positioned 覆盖）
              _ExamGenBanner(state: state),
              // 答题区（全宽可滚动）
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: _buildQuestionContent(paper, resolved, current),
                ),
              ),
              // 底部工具栏：上一题 / 题号 / 下一题
              _buildMobileBottomBar(context, current, total),
            ],
          ),
        ),
      ),
    );
  }

  /// 手机端顶部状态栏：紧凑显示倒计时、题号进度，并提供答题卡入口
  Widget _buildMobileTopBar(BuildContext context, int current, int answered, int total, int remaining, bool danger) {
    final pct = total == 0 ? 0.0 : answered / total;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 8)],
      ),
      child: Row(
        children: [
          // 倒计时
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: danger ? const Color(0xFF7F1D1D) : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: danger ? const Color(0xFFDC2626) : Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(danger ? Icons.timer_outlined : Icons.schedule_rounded,
                    color: danger ? const Color(0xFFFCA5A5) : const Color(0xFF93C5FD), size: 15),
                const SizedBox(width: 6),
                Text(
                  formatDuration(remaining),
                  style: TextStyle(
                    color: danger ? const Color(0xFFFFE4E4) : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 题号 + 进度条
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text('第 $current / $total 题',
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text('已答 $answered',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: const Color(0xFF334155),
                    valueColor: AlwaysStoppedAnimation(Color.lerp(const Color(0xFF3B82F6), const Color(0xFF8B5CF6), pct)!),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // 答题卡入口
          IconButton(
            onPressed: () => _showMobileAnswerSheet(context, current, answered, total),
            icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF93C5FD), size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.08),
              minimumSize: const Size(38, 38),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ],
      ),
    );
  }

  /// 手机端底部工具栏：上一题 / 当前题号 / 下一题
  Widget _buildMobileBottomBar(BuildContext context, int current, int total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.08), blurRadius: 12, offset: const Offset(0, -3))],
      ),
      child: Row(
        children: [
          // 上一题
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: state.examCurrentQuestion > 1
                  ? () {
                      state.examCurrentQuestion--;
                      state.touch();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('上一题', style: TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 中间题号（点击弹出答题卡）
          GestureDetector(
            onTap: () => _showMobileAnswerSheet(context, current, state.examCurrentQuestion > 0 ? _countAnswered(state) : 0, total),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text('$current / $total',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF))),
            ),
          ),
          const SizedBox(width: 10),
          // 下一题
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(
              onPressed: state.examCurrentQuestion < total
                  ? () {
                      state.examCurrentQuestion++;
                      state.touch();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('下一题', style: TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 手机端答题卡弹窗：环形统计 + 各题型进度 + 题号网格 + 交卷
  void _showMobileAnswerSheet(BuildContext context, int current, int answered, int total) {
    final paper = state.currentExamPaper!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.82),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示器 + 标题
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Column(
                  children: [
                    Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Text('答题卡', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        const Spacer(),
                        Text('第 $current / $total 题', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 环形统计 + 已答概览
                      Row(
                        children: [
                          _RingStat(answered: answered, total: total, compact: true),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('进度分布', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                                const SizedBox(height: 8),
                                ...ExamSection.values.map((s) {
                                  final n = _sectionAnswered(s);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 46,
                                          child: Text(s.shortLabel,
                                              style: TextStyle(fontSize: 9.5, color: Colors.grey[600], overflow: TextOverflow.ellipsis)),
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: s.questionCount == 0 ? 0 : n / s.questionCount,
                                              backgroundColor: const Color(0xFFF1F5F9),
                                              valueColor: AlwaysStoppedAnimation(Color(n == s.questionCount ? 0xFF10B981 : 0xFF3B82F6)),
                                              minHeight: 4,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        SizedBox(
                                          width: 32,
                                          child: Text('$n/${s.questionCount}',
                                              textAlign: TextAlign.right,
                                              style: TextStyle(fontSize: 9, color: n == s.questionCount ? const Color(0xFF059669) : Colors.grey[600])),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      const SizedBox(height: 12),
                      // 各题型题号网格
                      ...ExamSection.values.map((sec) => _buildMobileSectionGrid(ctx, paper, sec, current)),
                      const SizedBox(height: 10),
                      // 图例
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          _Legend(color: Color(0xFF3B82F6), label: '当前'),
                          SizedBox(width: 12),
                          _Legend(color: Color(0xFF10B981), label: '已答'),
                          SizedBox(width: 12),
                          _Legend(color: Color(0xFFE5E7EB), label: '未答', dark: true),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              // 底部交卷按钮
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: const Color(0xFFF1F5F9), width: 1)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      showDialog(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('确定交卷？'),
                          content: Text('你当前已答 $answered / $total 题。\n交卷后无法修改，确定提交并查看成绩分析吗？'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('再检查一下')),
                            ElevatedButton(
                              onPressed: () {
                                Navigator.pop(dctx);
                                state.submitFullExam();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('确定交卷'),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.flag_rounded, size: 16),
                    label: const Text('交卷评分', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 手机端答题卡中的分题型题号网格
  Widget _buildMobileSectionGrid(BuildContext context, FullExamPaper paper, ExamSection sec, int current) {
    final sheet = state.currentExamAnswerSheet!;
    final start = sec.startIndex;
    final count = sec.questionCount;
    List<int?>? Function(int) answeredOf;
    if (sec == ExamSection.vocab) {
      answeredOf = (i) => [sheet.vocab[i]];
    } else if (sec == ExamSection.reading) {
      answeredOf = (i) {
        final pi = i ~/ 5;
        final qi = i % 5;
        if (pi < sheet.reading.length && qi < sheet.reading[pi].length) {
          return [sheet.reading[pi][qi]];
        }
        return [null];
      };
    } else if (sec == ExamSection.cloze) {
      answeredOf = (i) => [sheet.cloze[i]];
    } else if (sec == ExamSection.dialogue) {
      answeredOf = (i) => [sheet.dialogue[i]];
    } else if (sec == ExamSection.bankedCloze) {
      answeredOf = (i) => [sheet.bankedCloze[i]];
    } else if (sec == ExamSection.en2zh5) {
      answeredOf = (i) => [sheet.en2zh5[i].isNotEmpty ? 1 : null];
    } else {
      answeredOf = (i) => [sheet.writing.isNotEmpty ? 1 : null];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(sec.shortLabel,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                ),
                Text('${sec.totalScore}分 · ${sec.questionCount}题',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey[500])),
              ],
            ),
          ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: List.generate(count, (i) {
              final idx1 = start + i;
              final a = answeredOf(i);
              final answered = a != null && a.isNotEmpty && a.first != null;
              final isCurrent = idx1 == current;
              final generated = idx1 <= state.examGeneratedCount;
              return GestureDetector(
                onTap: generated
                    ? () {
                        state.examCurrentQuestion = idx1;
                        state.touch();
                        Navigator.of(context).pop();
                      }
                    : null,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: !generated
                        ? const Color(0xFFF1F5F9)
                        : isCurrent
                            ? const Color(0xFF3B82F6)
                            : answered
                                ? const Color(0xFF10B981)
                                : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: !generated
                          ? const Color(0xFFE2E8F0)
                          : isCurrent
                              ? const Color(0xFF2563EB)
                              : answered
                                  ? const Color(0xFF059669)
                                  : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: isCurrent && generated
                        ? [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$idx1',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: !generated
                          ? const Color(0xFFCBD5E1)
                          : (isCurrent || answered) ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(double timePct, int remaining) {
    final danger = remaining <= 600;
    final paper = state.currentExamPaper!;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8)],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  paper.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                const Text(
                  '全真模拟 · 关闭AI助手 · 独立作答',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          // 提示标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB020), size: 15),
                SizedBox(width: 6),
                Text('考试中：禁止退出 / 切换 / AI 协助', style: TextStyle(color: Color(0xFFE2E8F0), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // 倒计时
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: danger ? const Color(0xFF7F1D1D) : const Color(0xFF334155),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: danger ? const Color(0xFFDC2626) : Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(danger ? Icons.timer_outlined : Icons.schedule_rounded,
                    color: danger ? const Color(0xFFFCA5A5) : const Color(0xFF93C5FD), size: 16),
                const SizedBox(width: 8),
                Text(
                  formatDuration(remaining),
                  style: TextStyle(
                    color: danger ? const Color(0xFFFFE4E4) : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftNav(FullExamPaper paper) {
    return Container(
      width: 280,
      margin: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Text('题目导航', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const Spacer(),
                Text('共 ${paper.totalQuestions} 题', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: Color(0xFFF1F5F9)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: ExamSection.values
                    .map((sec) => _buildSectionBlock(paper, sec))
                    .toList(),
              ),
            ),
          ),
          // 图例
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 8),
                const Text('图例', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    _Legend(color: Color(0xFF3B82F6), label: '当前'),
                    SizedBox(width: 10),
                    _Legend(color: Color(0xFF10B981), label: '已答'),
                    SizedBox(width: 10),
                    _Legend(color: Color(0xFFE5E7EB), label: '未答', dark: true),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBlock(FullExamPaper paper, ExamSection sec) {
    final sheet = state.currentExamAnswerSheet!;
    final start = sec.startIndex;
    final count = sec.questionCount;
    List<int?>? Function(int) answeredOf;
    if (sec == ExamSection.vocab) {
      answeredOf = (i) => [sheet.vocab[i]];
    } else if (sec == ExamSection.reading) {
      answeredOf = (i) {
        final pi = i ~/ 5;
        final qi = i % 5;
        if (pi < sheet.reading.length && qi < sheet.reading[pi].length) {
          return [sheet.reading[pi][qi]];
        }
        return [null];
      };
    } else if (sec == ExamSection.cloze) {
      answeredOf = (i) => [sheet.cloze[i]];
    } else if (sec == ExamSection.dialogue) {
      answeredOf = (i) => [sheet.dialogue[i]];
    } else if (sec == ExamSection.bankedCloze) {
      answeredOf = (i) => [sheet.bankedCloze[i]];
    } else if (sec == ExamSection.en2zh5) {
      answeredOf = (i) => [sheet.en2zh5[i].isNotEmpty ? 1 : null];
    } else {
      answeredOf = (i) => [sheet.writing.isNotEmpty ? 1 : null];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sec.shortLabel,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                ),
                Text(
                  '${sec.totalScore}分 · ${sec.questionCount}题',
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(count, (i) {
              final idx1 = start + i;
              final a = answeredOf(i);
              final answered = a != null && a.isNotEmpty && a.first != null;
              final current = idx1 == state.examCurrentQuestion;
              final generated = idx1 <= state.examGeneratedCount;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: generated ? () {
                    state.examCurrentQuestion = idx1;
                    state.touch();
                  } : null,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: !generated
                          ? const Color(0xFFF1F5F9)
                          : current
                              ? const Color(0xFF3B82F6)
                              : answered
                                  ? const Color(0xFF10B981)
                                  : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !generated
                            ? const Color(0xFFE2E8F0)
                            : current
                                ? const Color(0xFF2563EB)
                                : answered
                                    ? const Color(0xFF059669)
                                    : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: current && generated
                          ? [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 2))]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${idx1}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                        color: !generated
                            ? const Color(0xFFCBD5E1)
                            : (current || answered) ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // 中间答题区（可滚动）
  Widget _buildQuestionArea(FullExamPaper paper, ({ExamSection section, int relIdx, int passageIdx}) resolved, int current) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: _buildQuestionContent(paper, resolved, current),
      ),
    );
  }

  Widget _buildQuestionContent(FullExamPaper paper, ({ExamSection section, int relIdx, int passageIdx}) resolved, int current) {
    switch (resolved.section) {
      case ExamSection.vocab:
        return _VocabArea(state: state, paper: paper, relIdx: resolved.relIdx, idx1: current);
      case ExamSection.reading:
        return _ReadingArea(state: state, paper: paper, passageIdx: resolved.passageIdx, relQIdx: resolved.relIdx, idx1: current);
      case ExamSection.cloze:
        return _ClozeArea(state: state, paper: paper, relIdx: resolved.relIdx, idx1: current);
      case ExamSection.dialogue:
        return _DialogueArea(state: state, paper: paper, relIdx: resolved.relIdx, idx1: current);
      case ExamSection.bankedCloze:
        return _BankedClozeArea(state: state, paper: paper, relIdx: resolved.relIdx, idx1: current);
      case ExamSection.en2zh5:
        return _En2zh5Area(state: state, paper: paper, relIdx: resolved.relIdx, idx1: current);
      case ExamSection.writing:
        return _WritingArea(state: state, paper: paper, idx1: current);
    }
  }

  Widget _buildAnswerCard(BuildContext context, FullExamPaper paper, int current, int answered, int total, {bool compact = false}) {
    final remaining = state.examRemainingSec;
    final danger = remaining <= 600;
    return Container(
      margin: EdgeInsets.fromLTRB(0, 12, compact ? 8 : 16, 12),
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      // 窗口较窄/高度不足时右侧面板整体可滚动
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 倒计时（移到答题卡顶部）
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: compact ? 8 : 10),
              decoration: BoxDecoration(
                color: danger ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: danger ? const Color(0xFFFCA5A5) : const Color(0xFF93C5FD)),
              ),
              child: Row(
                children: [
                  Icon(danger ? Icons.timer_outlined : Icons.schedule_rounded,
                      color: danger ? const Color(0xFFDC2626) : const Color(0xFF3B82F6), size: compact ? 16 : 18),
                  const SizedBox(width: 6),
                  Text(
                    formatDuration(remaining),
                    style: TextStyle(
                      color: danger ? const Color(0xFFDC2626) : const Color(0xFF1E40AF),
                      fontSize: compact ? 16 : 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '剩余',
                    style: TextStyle(
                      fontSize: compact ? 10 : 11,
                      color: danger ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            Text('答题卡', style: TextStyle(fontSize: compact ? 12 : 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
            const SizedBox(height: 2),
            Text('第 ${current.clamp(1, total)} / $total 题', style: TextStyle(fontSize: compact ? 10 : 11.5, color: Colors.grey[500])),
            SizedBox(height: compact ? 10 : 14),
            _RingStat(answered: answered, total: total, compact: compact),
            SizedBox(height: compact ? 10 : 16),
            Text('进度分布', style: TextStyle(fontSize: compact ? 10 : 12, fontWeight: FontWeight.w600, color: const Color(0xFF334155))),
            SizedBox(height: compact ? 6 : 10),
            ...ExamSection.values.map((s) {
              final n = _sectionAnswered(s);
              return Padding(
                padding: EdgeInsets.only(bottom: compact ? 5 : 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: compact ? 42 : 58,
                      child: Text(s.label, style: TextStyle(fontSize: compact ? 9 : 10.5, color: Colors.grey[600], overflow: TextOverflow.ellipsis)),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: s.questionCount == 0 ? 0 : n / s.questionCount,
                          backgroundColor: const Color(0xFFF1F5F9),
                          valueColor: AlwaysStoppedAnimation(Color(n == s.questionCount ? 0xFF10B981 : 0xFF3B82F6)),
                          minHeight: compact ? 4 : 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('$n/${s.questionCount}',
                        style: TextStyle(fontSize: compact ? 8 : 10, color: n == s.questionCount ? const Color(0xFF059669) : Colors.grey[600])),
                  ],
                ),
              );
            }),
            SizedBox(height: compact ? 8 : 12),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            SizedBox(height: compact ? 8 : 10),
            // 上一题 / 下一题（原底部操作栏并入）
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.examCurrentQuestion > 1
                        ? () {
                            state.examCurrentQuestion--;
                            state.touch();
                          }
                        : null,
                    icon: Icon(Icons.chevron_left, size: compact ? 14 : 16),
                    label: Text('上一题', style: TextStyle(fontSize: compact ? 10 : 12)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 7 : 9),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 4 : 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.examCurrentQuestion < total
                        ? () {
                            state.examCurrentQuestion++;
                            state.touch();
                          }
                        : null,
                    icon: Icon(Icons.chevron_right, size: compact ? 14 : 16),
                    label: Text('下一题', style: TextStyle(fontSize: compact ? 10 : 12)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 7 : 9),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
            // 交卷评分（保留二次确认弹窗）
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('确定交卷？'),
                      content: Text('你当前已答 $answered / $total 题。\n交卷后无法修改，确定提交并查看成绩分析吗？'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('再检查一下')),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            state.submitFullExam();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('确定交卷'),
                        ),
                      ],
                    ),
                  );
                },
                icon: Icon(Icons.flag_rounded, size: compact ? 14 : 16),
                label: Text('交卷评分', style: TextStyle(fontSize: compact ? 11 : 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.symmetric(vertical: compact ? 9 : 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _sectionAnswered(ExamSection sec) {
    final sheet = state.currentExamAnswerSheet!;
    if (sec == ExamSection.vocab) return sheet.vocab.where((e) => e != null).length;
    if (sec == ExamSection.reading) {
      return sheet.reading.expand((e) => e).where((e) => e != null).length;
    }
    if (sec == ExamSection.cloze) return sheet.cloze.where((e) => e != null).length;
    if (sec == ExamSection.dialogue) return sheet.dialogue.where((e) => e != null).length;
    if (sec == ExamSection.bankedCloze) return sheet.bankedCloze.where((e) => e != null).length;
    if (sec == ExamSection.en2zh5) return sheet.en2zh5.where((e) => e.isNotEmpty).length;
    return sheet.writing.isNotEmpty ? 1 : 0;
  }
}

// ========== 各题型答题小部件 ==========

/// 考场顶部生成状态横幅：生成中显示进度条与提示；结束后若有失败批次，
/// 显示中文失败清单与“重新生成缺失部分”按钮
class _ExamGenBanner extends StatelessWidget {
  final AppState state;
  const _ExamGenBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state.examGeneratingBatch) {
      final pct = state.examTotalQuestions <= 0
          ? 0.0
          : (state.examGeneratedCount / state.examTotalQuestions).clamp(0.0, 1.0);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFBFDBFE)),
          boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '正在生成试卷题目… ${state.examGeneratedCount} / ${state.examTotalQuestions} 题',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A)),
                  ),
                  if (state.examGeneratingHint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      state.examGeneratingHint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFDBEAFE),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF3B82F6)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (state.examGenerationDone && state.examFailedSectionLabels.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFCA5A5)),
          boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.06), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFDC2626)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '部分题型未能生成：${state.examFailedSectionLabels.join('、')}。其余题型可正常作答。',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF7F1D1D), height: 1.5),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => state.regenerateFailedExamBatches(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: const Text('重新生成缺失部分', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _VocabArea extends StatelessWidget {
  final AppState state;
  final FullExamPaper paper;
  final int relIdx;
  final int idx1;
  const _VocabArea({required this.state, required this.paper, required this.relIdx, required this.idx1});

  @override
  Widget build(BuildContext context) {
    if (relIdx >= paper.vocab.length) return const Center(child: Text('题目未生成'));
    final q = paper.vocab[relIdx];
    final sheet = state.currentExamAnswerSheet!;
    final sel = sheet.vocab[relIdx];
    return _QuestionCard(
      tag: '第一部分 词汇与语法结构',
      tagColor: const Color(0xFF3B82F6),
      scoreText: '第 $idx1 题 · 1分',
      title: q.question.isNotEmpty ? q.question : q.text,
      child: Column(
        children: List.generate(q.options.length, (i) {
          final letter = String.fromCharCode(65 + i);
          final checked = sel == i;
          return _OptionTile(
            letter: letter,
            text: q.options[i],
            checked: checked,
            onTap: () {
              sheet.vocab[relIdx] = i;
              state.touch();
            },
          );
        }),
      ),
    );
  }
}

class _ReadingArea extends StatelessWidget {
  final AppState state;
  final FullExamPaper paper;
  final int passageIdx;
  final int relQIdx;
  final int idx1;
  const _ReadingArea({
    required this.state,
    required this.paper,
    required this.passageIdx,
    required this.relQIdx,
    required this.idx1,
  });

  @override
  Widget build(BuildContext context) {
    if (passageIdx >= paper.readings.length) return const Center(child: Text('题目未生成'));
    final p = paper.readings[passageIdx];
    final qs = p.questions;
    final sheet = state.currentExamAnswerSheet!;
    final sub = relQIdx < qs.length ? qs[relQIdx] : null;
    return Column(
      children: [
        _QuestionCard(
          tag: '第二部分 阅读理解 · 第 ${passageIdx + 1} 篇',
          tagColor: const Color(0xFF8B5CF6),
          scoreText: '共 5 题 · 每题 2 分',
          title: null,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: SelectableText(
              p.passage,
              style: const TextStyle(fontSize: 14.5, color: Color(0xFF1E293B), height: 1.75, letterSpacing: 0.2),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (sub != null)
          _QuestionCard(
            tag: '第 ${passageIdx + 1} 篇 · 第 ${relQIdx + 1} 题',
            tagColor: const Color(0xFF6366F1),
            scoreText: '第 $idx1 题 · 2 分',
            title: sub.question,
            child: Column(
              children: List.generate(sub.options.length, (i) {
                final letter = String.fromCharCode(65 + i);
                final checked = sheet.reading[passageIdx][relQIdx] == i;
                return _OptionTile(
                  letter: letter,
                  text: sub.options[i],
                  checked: checked,
                  onTap: () {
                    sheet.reading[passageIdx][relQIdx] = i;
                    state.touch();
                  },
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _ClozeArea extends StatelessWidget {
  final AppState state;
  final FullExamPaper paper;
  final int relIdx;
  final int idx1;
  const _ClozeArea({required this.state, required this.paper, required this.relIdx, required this.idx1});

  @override
  Widget build(BuildContext context) {
    final passage = paper.cloze.isNotEmpty ? (paper.cloze.first.passage ?? '') : '';
    final subs = paper.clozeSubs ?? [];
    final sheet = state.currentExamAnswerSheet!;
    final sub = relIdx < subs.length ? subs[relIdx] : null;
    return Column(
      children: [
        _QuestionCard(
          tag: '第三部分 完形填空',
          tagColor: const Color(0xFF10B981),
          scoreText: '共 15 题 · 每题 1 分',
          title: null,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: SelectableText(
              passage.isEmpty ? '（请根据下面每小题作答）' : passage,
              style: const TextStyle(fontSize: 14.5, color: Color(0xFF1E293B), height: 1.75),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (sub != null)
          _QuestionCard(
            tag: '第 ${sub.blankIdx} 空',
            tagColor: const Color(0xFF059669),
            scoreText: '第 $idx1 题 · 1 分',
            title: sub.sentence,
            child: Column(
              children: List.generate(sub.options.length, (i) {
                final letter = String.fromCharCode(65 + i);
                final checked = sheet.cloze[relIdx] == i;
                return _OptionTile(
                  letter: letter,
                  text: sub.options[i],
                  checked: checked,
                  onTap: () {
                    sheet.cloze[relIdx] = i;
                    state.touch();
                  },
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _DialogueArea extends StatelessWidget {
  final AppState state;
  final FullExamPaper paper;
  final int relIdx;
  final int idx1;
  const _DialogueArea({required this.state, required this.paper, required this.relIdx, required this.idx1});

  @override
  Widget build(BuildContext context) {
    final d = paper.dialogue;
    final sheet = state.currentExamAnswerSheet!;
    if (d == null) return const Center(child: Text('题目未生成'));
    final userIdx = sheet.dialogue[relIdx];
    return Column(
      children: [
        _QuestionCard(
          tag: '第四部分 补全对话',
          tagColor: const Color(0xFFF59E0B),
          scoreText: '共 5 题 · 每题 2 分',
          title: d.scenario,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...d.dialogueLines.map((e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(e, style: const TextStyle(fontSize: 14, height: 1.7, color: Color(0xFF1E293B))),
                  )),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: List.generate(d.options.length, (i) {
                  final letter = String.fromCharCode(65 + i);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFCD34D)),
                    ),
                    child: Text('$letter. ${d.options[i]}',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF78350F), height: 1.5)),
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _QuestionCard(
          tag: '第 ${relIdx + 1} 空 · 选择填入句子',
          tagColor: const Color(0xFFD97706),
          scoreText: '第 $idx1 题 · 2 分',
          title: '请为对话第 ${relIdx + 1} 个空选出正确选项（从 A-G 7项中选 1 项）',
          child: Column(
            children: List.generate(d.options.length, (i) {
              final letter = String.fromCharCode(65 + i);
              final checked = userIdx == i;
              return _OptionTile(
                letter: letter,
                text: d.options[i],
                checked: checked,
                onTap: () {
                  sheet.dialogue[relIdx] = i;
                  state.touch();
                },
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _BankedClozeArea extends StatelessWidget {
  final AppState state;
  final FullExamPaper paper;
  final int relIdx;
  final int idx1;
  const _BankedClozeArea({required this.state, required this.paper, required this.relIdx, required this.idx1});

  @override
  Widget build(BuildContext context) {
    final bc = paper.bankedCloze;
    final sheet = state.currentExamAnswerSheet!;
    if (bc == null) return const Center(child: Text('题目未生成'));
    final userIdx = sheet.bankedCloze[relIdx];
    return Column(
      children: [
        _QuestionCard(
          tag: '第五部分 选词填空（15选10）',
          tagColor: const Color(0xFFEC4899),
          scoreText: '共 10 题 · 每题 2 分',
          title: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(bc.wordBank.length, (i) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE7F3),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFF9A8D4)),
                    ),
                    child: Text(
                      '${String.fromCharCode(65 + i)}. ${bc.wordBank[i]}',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF9D174D), fontWeight: FontWeight.w500),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              SelectableText(
                bc.passage.isEmpty ? '（请根据短文填入下列单词）' : bc.passage,
                style: const TextStyle(fontSize: 14.5, color: Color(0xFF1E293B), height: 1.75),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _QuestionCard(
          tag: '第 ${relIdx + 1} 空 · 选择填入单词',
          tagColor: const Color(0xFFDB2777),
          scoreText: '第 $idx1 题 · 2 分',
          title: '请为第 ${relIdx + 1} 个空格选择正确的单词（每词限用一次）',
          child: Column(
            children: List.generate(bc.wordBank.length, (i) {
              final letter = String.fromCharCode(65 + i);
              final checked = userIdx == i;
              return _OptionTile(
                letter: letter,
                text: bc.wordBank[i],
                checked: checked,
                onTap: () {
                  sheet.bankedCloze[relIdx] = i;
                  state.touch();
                },
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _En2zh5Area extends StatefulWidget {
  final AppState state;
  final FullExamPaper paper;
  final int relIdx;
  final int idx1;
  const _En2zh5Area({required this.state, required this.paper, required this.relIdx, required this.idx1});

  @override
  State<_En2zh5Area> createState() => _En2zh5AreaState();
}

class _En2zh5AreaState extends State<_En2zh5Area> {
  late TextEditingController _controller;
  late int _lastRelIdx;

  @override
  void initState() {
    super.initState();
    final sheet = widget.state.currentExamAnswerSheet!;
    _lastRelIdx = widget.relIdx;
    _controller = TextEditingController(text: sheet.en2zh5[_lastRelIdx]);
  }

  @override
  void didUpdateWidget(covariant _En2zh5Area oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换题目时，从答题卡读取对应题目已保存的答案更新到输入框
    if (oldWidget.relIdx != widget.relIdx) {
      final sheet = widget.state.currentExamAnswerSheet!;
      _lastRelIdx = widget.relIdx;
      // 不重置光标，仅更新文本（保持光标在末尾方便继续编辑）
      final saved = sheet.en2zh5[widget.relIdx];
      if (_controller.text != saved) {
        _controller.value = TextEditingValue(
          text: saved,
          selection: TextSelection.collapsed(offset: saved.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e5 = widget.paper.en2zh5;
    if (e5 == null || widget.relIdx >= e5.sentences.length) return const Center(child: Text('题目未生成'));
    return _QuestionCard(
      tag: '第六部分 英译汉 · 第 ${widget.relIdx + 1} 句',
      tagColor: const Color(0xFF06B6D4),
      scoreText: '第 ${widget.idx1} 题 · 4 分',
      title: e5.sentences[widget.relIdx],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请将上面的英文句子翻译成中文：',
              style: TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 5,
            onChanged: (v) {
              widget.state.currentExamAnswerSheet!.en2zh5[widget.relIdx] = v;
              widget.state.touch();
            },
            decoration: InputDecoration(
              hintText: '在此输入中文译文...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ],
      ),
    );
  }
}

class _WritingArea extends StatefulWidget {
  final AppState state;
  final FullExamPaper paper;
  final int idx1;
  const _WritingArea({required this.state, required this.paper, required this.idx1});

  @override
  State<_WritingArea> createState() => _WritingAreaState();
}

class _WritingAreaState extends State<_WritingArea> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final sheet = widget.state.currentExamAnswerSheet!;
    _controller = TextEditingController(text: sheet.writing);
  }

  @override
  void didUpdateWidget(covariant _WritingArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 写作只有1题，但若答题卡引用变化时同步已保存的内容
    final sheet = widget.state.currentExamAnswerSheet!;
    if (_controller.text != sheet.writing) {
      final saved = sheet.writing;
      _controller.value = TextEditingValue(
        text: saved,
        selection: TextSelection.collapsed(offset: saved.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.paper.writing;
    final sheet = widget.state.currentExamAnswerSheet!;
    final words = sheet.writing.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;
    return _QuestionCard(
      tag: '第七部分 写作',
      tagColor: const Color(0xFF7C3AED),
      scoreText: '第 ${widget.idx1} 题 · 20 分 · 已写 $words 词',
      title: w?.topic ?? '写作题目',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请按要求用英文写一篇短文（不少于 120 词）：',
              style: TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 18,
            onChanged: (v) {
              sheet.writing = v;
              widget.state.touch();
            },
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 14.5, letterSpacing: 0.2, height: 1.7),
            decoration: InputDecoration(
              hintText: 'Start your essay here...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: const Color(0xFFFBFAFF),
              contentPadding: const EdgeInsets.all(14),
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ========== 通用卡片 / 选项 / 统计 ==========

class _QuestionCard extends StatelessWidget {
  final String tag;
  final Color tagColor;
  final String scoreText;
  final String? title;
  final Widget child;
  const _QuestionCard({
    required this.tag,
    required this.tagColor,
    required this.scoreText,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: tagColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(tag, style: TextStyle(fontSize: isMobile ? 10.5 : 11, fontWeight: FontWeight.w700, color: tagColor, letterSpacing: 0.2)),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(scoreText, style: TextStyle(fontSize: isMobile ? 11 : 12, color: Colors.grey[600], fontWeight: FontWeight.w600), textAlign: TextAlign.right),
              ),
            ],
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SelectableText(
                title!,
                style: TextStyle(fontSize: isMobile ? 14.5 : 15.5, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A), height: 1.65),
              ),
            ),
          SizedBox(height: isMobile ? 10 : 12),
          child,
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String letter;
  final String text;
  final bool checked;
  final VoidCallback onTap;
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isMobile ? 4 : 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: EdgeInsets.all(isMobile ? 10 : 12),
            decoration: BoxDecoration(
              color: checked ? const Color(0xFFEFF6FF) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: checked ? const Color(0xFF3B82F6) : const Color(0xFFE2E8F0),
                width: checked ? 1.4 : 1,
              ),
              boxShadow: checked
                  ? [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.12), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: isMobile ? 25 : 28,
                  height: isMobile ? 25 : 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: checked ? const Color(0xFF3B82F6) : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: checked ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1)),
                  ),
                  child: Text(
                    letter,
                    style: TextStyle(fontSize: isMobile ? 12 : 13, fontWeight: FontWeight.w700, color: checked ? Colors.white : const Color(0xFF475569)),
                  ),
                ),
                SizedBox(width: isMobile ? 10 : 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: isMobile ? 13.5 : 14,
                        color: checked ? const Color(0xFF1E3A8A) : const Color(0xFF1E293B),
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dark;
  const _Legend({required this.color, required this.label, this.dark = false});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10.5, color: dark ? const Color(0xFF475569) : Colors.black87)),
      ],
    );
  }
}

class _RingStat extends StatelessWidget {
  final int answered;
  final int total;
  final bool compact;
  const _RingStat({required this.answered, required this.total, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : answered / total;
    final size = compact ? 80.0 : 120.0;
    final strokeW = compact ? 7.0 : 10.0;
    return SizedBox(
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: strokeW,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation<Color>(
                Color.lerp(const Color(0xFF3B82F6), const Color(0xFF8B5CF6), 0.5)!,
              ),
              strokeCap: StrokeCap.round,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: compact ? 16 : 22, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
              Text('$answered / $total', style: TextStyle(fontSize: compact ? 9 : 11.5, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
    );
  }
}

// ========= 成绩解析页 =========

class ExamResultPage extends StatelessWidget {
  final AppState state;
  const ExamResultPage({super.key, required this.state});

  String fmtDur(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '${m}分${s.toString().padLeft(2, '0')}秒';
  }

  @override
  Widget build(BuildContext context) {
    final r = state.currentExamResult!;
    final isMobile = state.uiMode == 'mobile';
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEEF2FF), Color(0xFFF6F7FB)],
          ),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 14 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部按钮行（手机端两个按钮等宽撑满）
              Row(
                children: [
                  Expanded(
                    flex: isMobile ? 1 : 0,
                    child: OutlinedButton.icon(
                      onPressed: state.exitFullExam,
                      icon: const Icon(Icons.arrow_back_rounded, size: 16),
                      label: const Text('返回首页', style: TextStyle(fontSize: 12.5)),
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 9)),
                    ),
                  ),
                  if (isMobile) const SizedBox(width: 10) else const Spacer(),
                  Expanded(
                    flex: isMobile ? 1 : 0,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // 回看错题：返回考场，但其实直接重进首页
                        state.page = 9;
                        state.touch();
                      },
                      icon: const Icon(Icons.analytics_rounded, size: 16),
                      label: const Text('去错题本复盘', style: TextStyle(fontSize: 12.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _ResultHero(r: r, isMobile: isMobile),
              const SizedBox(height: 18),
              // AI 批改状态轻提示（进行中 / 已完成）
              if (r.aiGrading) const _AiGradingBanner(text: 'AI 正在批改英译汉与写作，稍后自动更新评语与得分…', done: false)
              else if (r.aiGraded) const _AiGradingBanner(text: '主观题已由 AI 智能批改，评语与得分已更新。', done: true),
              if (r.aiGrading || r.aiGraded) const SizedBox(height: 18),
              if (isMobile)
                Column(
                  children: [
                    _SectionBreakdown(r: r, isMobile: true),
                    const SizedBox(height: 16),
                    _OverallStats(r: r, dur: fmtDur(r.durationSec), isMobile: true),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _SectionBreakdown(r: r, isMobile: false)),
                    const SizedBox(width: 18),
                    Expanded(flex: 2, child: _OverallStats(r: r, dur: fmtDur(r.durationSec), isMobile: false)),
                  ],
                ),
              const SizedBox(height: 18),
              // 英译汉逐句反馈（AI 批改后展示逐句评语；批改中显示轻提示）
              if (r.paper.en2zh5 != null)
                _En2zhFeedbackCard(r: r),
              if (r.paper.en2zh5 != null) const SizedBox(height: 18),
              // 写作单独点评
              if (r.writingScore.isNotEmpty || r.aiGrading)
                _WritingScoreCard(r: r),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultHero extends StatelessWidget {
  final ExamResult r;
  final bool isMobile;
  const _ResultHero({required this.r, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final pct = r.maxScore == 0 ? 0.0 : r.totalScore / r.maxScore;
    final totalCorrect = r.sectionCorrect.values.fold<int>(0, (a, b) => a + b);
    return Container(
      padding: EdgeInsets.all(isMobile ? 18 : 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pct >= 0.7
              ? const [Color(0xFF1E3A8A), Color(0xFF6366F1), Color(0xFF8B5CF6)]
              : pct >= 0.6
                  ? const [Color(0xFF047857), Color(0xFF10B981), Color(0xFF34D399)]
                  : const [Color(0xFFB45309), Color(0xFFF59E0B), Color(0xFFFCD34D)],
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: isMobile
          ? Column(
              children: [
                // 评级圆环居中
                Container(
                  width: 92,
                  height: 92,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 3),
                  ),
                  child: Text(
                    r.rank,
                    style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 2),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('考试已结束 · 成绩分析报告', style: TextStyle(color: Colors.white70, fontSize: 11.5, letterSpacing: 0.4), textAlign: TextAlign.center),
                const SizedBox(height: 5),
                Text(
                  r.paper.title,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
                // 4个指标 2x2 网格
                Row(
                  children: [
                    Expanded(child: _ScoreBadge(label: '总分', value: '${r.totalScore}', sub: '/ ${r.maxScore}')),
                    const SizedBox(width: 10),
                    Expanded(child: _ScoreBadge(label: '百分位', value: '${(pct * 100).toStringAsFixed(1)}', sub: '%')),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _ScoreBadge(label: '评级', value: r.rank, sub: '等级')),
                    const SizedBox(width: 10),
                    Expanded(child: _ScoreBadge(label: '做对', value: '$totalCorrect', sub: '/ 76')),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 3),
                  ),
                  child: Text(
                    r.rank,
                    style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, letterSpacing: 2),
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('考试已结束 · 成绩分析报告', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 0.6)),
                      const SizedBox(height: 6),
                      Text(
                        r.paper.title,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _ScoreBadge(label: '总分', value: '${r.totalScore}', sub: '/ ${r.maxScore}'),
                          const SizedBox(width: 18),
                          _ScoreBadge(label: '百分位', value: '${(pct * 100).toStringAsFixed(1)}', sub: '%'),
                          const SizedBox(width: 18),
                          _ScoreBadge(label: '评级', value: r.rank, sub: '等级'),
                          const SizedBox(width: 18),
                          _ScoreBadge(label: '做对', value: '$totalCorrect', sub: '/ 76'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  const _ScoreBadge({required this.label, required this.value, required this.sub});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(sub, style: const TextStyle(color: Colors.white60, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionBreakdown extends StatelessWidget {
  final ExamResult r;
  final bool isMobile;
  const _SectionBreakdown({required this.r, required this.isMobile});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('各题型得分', style: TextStyle(fontSize: isMobile ? 14.5 : 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
          const SizedBox(height: 4),
          Text('逐题型展示得分/满分/正确率，帮助定位薄弱环节', style: TextStyle(fontSize: isMobile ? 11 : 12, color: Colors.grey[500])),
          const SizedBox(height: 14),
          ...ExamSection.values.map((s) {
            final sc = r.sectionScores[s] ?? 0;
            final max = r.sectionMax[s] ?? s.totalScore;
            final correct = r.sectionCorrect[s] ?? 0;
            final total = s.questionCount;
            final pct = max == 0 ? 0.0 : sc / max;
            return Padding(
              padding: EdgeInsets.symmetric(vertical: isMobile ? 6 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.shortLabel,
                            style: TextStyle(fontSize: isMobile ? 12.5 : 13.5, fontWeight: FontWeight.w600, color: const Color(0xFF1E293B)),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('做对 $correct/$total',
                          style: TextStyle(fontSize: isMobile ? 10.5 : 11.5, color: Colors.grey[500])),
                      SizedBox(width: isMobile ? 8 : 12),
                      Text('$sc/$max',
                          style: TextStyle(fontSize: isMobile ? 12 : 13, fontWeight: FontWeight.w700, color: const Color(0xFF1E3A8A))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        pct >= 0.8
                            ? const Color(0xFF10B981)
                            : pct >= 0.6
                                ? const Color(0xFF3B82F6)
                                : pct >= 0.4
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFFEF4444),
                      ),
                      minHeight: isMobile ? 8 : 10,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _OverallStats extends StatelessWidget {
  final ExamResult r;
  final String dur;
  final bool isMobile;
  const _OverallStats({required this.r, required this.dur, required this.isMobile});
  @override
  Widget build(BuildContext context) {
    final totalCorrect = r.sectionCorrect.values.fold<int>(0, (a, b) => a + b);
    final totalQ = r.sectionTotal.values.fold<int>(0, (a, b) => a + b);
    final qpm = r.durationSec == 0 ? 0 : totalQ / (r.durationSec / 60);
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 14 : 18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('整体表现', style: TextStyle(fontSize: isMobile ? 14.5 : 16, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
          SizedBox(height: isMobile ? 10 : 14),
          _StatRow(icon: Icons.timer_rounded, label: '答题用时', value: dur, accent: const Color(0xFF3B82F6)),
          _StatRow(icon: Icons.gavel_rounded, label: '客观做对', value: '$totalCorrect 题', accent: const Color(0xFF10B981)),
          _StatRow(icon: Icons.track_changes_rounded, label: '客观作答', value: '$totalQ 题', accent: const Color(0xFF8B5CF6)),
          _StatRow(icon: Icons.speed_rounded, label: '平均速度', value: '${qpm.toStringAsFixed(1)} 题/分钟', accent: const Color(0xFFF59E0B)),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),
          const Text('教练建议', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: Text(
              _advice(r),
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E3A8A), height: 1.7),
            ),
          ),
        ],
      ),
    );
  }

  String _advice(ExamResult r) {
    final pct = r.percentage;
    final weak = <String>[];
    for (final s in ExamSection.values) {
      final max = r.sectionMax[s] ?? s.totalScore;
      final sc = r.sectionScores[s] ?? 0;
      if (max > 0 && sc / max < 0.5) weak.add(s.label);
    }
    final sb = StringBuffer();
    if (pct >= 0.85) {
      sb.writeln('表现优秀！保持节奏，建议重点突破薄弱环节并进行限时训练。');
    } else if (pct >= 0.7) {
      sb.writeln('表现良好！建议对阅读和写作做专项强化，提升稳定度。');
    } else if (pct >= 0.6) {
      sb.writeln('及格附近，再提分机会很大！建议先攻克词汇语法和完形两大基础题型。');
    } else {
      sb.writeln('基础尚需加强：建议先过一遍专升本核心词，并做专项模块练习再做套卷。');
    }
    if (weak.isNotEmpty) {
      sb.write('\n当前薄弱：${weak.join("、")}，请针对性训练。');
    }
    return sb.toString();
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  const _StatRow({required this.icon, required this.label, required this.value, required this.accent});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

/// AI 批改状态轻提示横幅（进行中 / 已完成）
class _AiGradingBanner extends StatelessWidget {
  final String text;
  final bool done;
  const _AiGradingBanner({required this.text, required this.done});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: done ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: done ? const Color(0xFF6EE7B7) : const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          if (done)
            const Icon(Icons.verified_rounded, size: 17, color: Color(0xFF059669))
          else
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6)),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              done ? text : 'AI 批改中… $text',
              style: TextStyle(fontSize: 12.5, height: 1.5, color: done ? const Color(0xFF065F46) : const Color(0xFF1E3A8A)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 英译汉逐句反馈卡：AI 批改后展示逐句评语，批改中显示轻提示，AI 未参与时维持简洁现状
class _En2zhFeedbackCard extends StatelessWidget {
  final ExamResult r;
  const _En2zhFeedbackCard({required this.r});
  @override
  Widget build(BuildContext context) {
    final e5 = r.paper.en2zh5!;
    final sc = r.sectionScores[ExamSection.en2zh5] ?? 0;
    final max = r.sectionMax[ExamSection.en2zh5] ?? ExamSection.en2zh5.totalScore;
    final comments = r.en2zh5AiComments;
    final hasAi = r.aiGraded && comments.any((c) => c.trim().isNotEmpty);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Icon(Icons.translate_rounded, color: Color(0xFF2563EB), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasAi ? '英译汉反馈 · AI 逐句点评' : '英译汉反馈',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ),
              Text('$sc / $max 分', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1E3A8A))),
            ],
          ),
          const SizedBox(height: 12),
          if (r.aiGrading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6))),
                  SizedBox(width: 8),
                  Expanded(child: Text('AI 批改中… 逐句评语稍后自动展示', style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)))),
                ],
              ),
            )
          else if (hasAi)
            ...List.generate(min(5, e5.sentences.length), (i) {
              final comment = i < comments.length ? comments[i] : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('第 ${i + 1} 句：${e5.sentences[i]}',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B), height: 1.5)),
                    if (comment.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('评语：$comment', style: const TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.5)),
                      ),
                  ],
                ),
              );
            })
          else
            Text('本地启发式评分：按参考译文关键词命中率估算，配置 AI 接口后可获得逐句点评。',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600], height: 1.6)),
        ],
      ),
    );
  }
}

class _WritingScoreCard extends StatelessWidget {
  final ExamResult r;
  const _WritingScoreCard({required this.r});
  @override
  Widget build(BuildContext context) {
    final title = r.aiGraded ? '写作评分 · AI 智能点评' : '写作评分 · AI 启发式点评';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFAF0),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDBA74)),
            ),
            child: const Icon(Icons.edit_note_rounded, color: Color(0xFFEA580C), size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                if (r.aiGrading)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3B82F6))),
                        SizedBox(width: 8),
                        Expanded(child: Text('AI 批改中… 写作评语稍后自动展示', style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)))),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    r.writingScore.isNotEmpty ? r.writingScore : '暂无点评',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.6),
                  ),
                  if (r.aiGraded && r.writingAiSuggestion.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text('改进建议：${r.writingAiSuggestion}',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E3A8A), height: 1.6)),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text('${r.writingScoreNum} / 20', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF7C2D12))),
        ],
      ),
    );
  }
}

int _countAnswered(AppState state) {
  final s = state.currentExamAnswerSheet;
  if (s == null) return 0;
  var n = 0;
  n += s.vocab.where((e) => e != null).length;
  n += s.reading.expand((e) => e).where((e) => e != null).length;
  n += s.cloze.where((e) => e != null).length;
  n += s.dialogue.where((e) => e != null).length;
  n += s.bankedCloze.where((e) => e != null).length;
  n += s.en2zh5.where((e) => e.isNotEmpty).length;
  if (s.writing.isNotEmpty) n++;
  return n;
}

/// 全卷生成完成后的醒目大弹窗：选择"进入考场"或"暂不进入"
class ExamConfirmDialog extends StatelessWidget {
  final AppState state;
  const ExamConfirmDialog({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final paper = state.currentExamPaper;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 40, offset: const Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部渐变横幅
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.assignment_turned_in_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('全卷已生成', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                            SizedBox(height: 4),
                            Text('专升本英语综合模拟全卷', style: TextStyle(fontSize: 13, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              // 内容区
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 22, 28, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (paper != null)
                        Text(paper.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                      const SizedBox(height: 18),
                      // 四个指标卡（读试卷实际数据）
                      Row(children: [
                        _metricCard('${paper?.totalQuestions ?? 76}', '题量', const Color(0xFF3B82F6)),
                        const SizedBox(width: 10),
                        _metricCard('150', '总分', const Color(0xFF8B5CF6)),
                        const SizedBox(width: 10),
                        _metricCard('7', '题型', const Color(0xFF10B981)),
                        const SizedBox(width: 10),
                        _metricCard('${paper?.totalTimeMin ?? 120}', '分钟', const Color(0xFFF59E0B)),
                      ]),
                      const SizedBox(height: 20),
                      // 题型分布
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('题型分布', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
                            SizedBox(height: 8),
                            Text('① 词汇与语法 20题  ② 阅读理解 20题\n③ 完形填空 15题  ④ 补全对话 5题\n⑤ 选词填空 10题  ⑥ 英译汉 5题\n⑦ 写作 1题', style: TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.7)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 提示
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '进入考场后 AI 助手将自动隐藏，需独立作答，超时自动交卷。',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8), height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 底部按钮
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        state.examPendingConfirm = false;
                        state.notifyListeners();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF64748B),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('暂不进入', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        state.enterFullExam();
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('进入考场', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          ],
        ),
      ),
    );
  }
}
