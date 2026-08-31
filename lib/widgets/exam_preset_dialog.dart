/// 综合模拟套卷的来源选择弹窗：
/// 1) 选择某一年的四川专升本真题直接作答（汇编无官方答案，载入后由 AI 补参考答案）；
/// 2) 选择「AI 生成一套」——生成规则锚定 2023—2026 真题的题型结构与考查侧重点。
library;

import 'package:flutter/material.dart';
import '../exam_real_papers.dart';
import '../models.dart';
import '../theme_colors.dart' show AppColors, kPrimary;

/// 返回 'ai' 表示 AI 生成；返回年份字符串（如 '2024'）表示载入该年真题；
/// 返回 null 表示取消。
Future<String?> showExamPaperSourceDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _ExamPaperSourceDialog(),
  );
}

class _ExamPaperSourceDialog extends StatelessWidget {
  const _ExamPaperSourceDialog();

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final c = AppColors(isLight);
    return Dialog(
      backgroundColor: c.cardSolid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '综合模拟套卷',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
              ),
              const SizedBox(height: 6),
              Text(
                '选择一套真题直接作答，或让 AI 按真题题型与考查侧重点新出一套。',
                style: TextStyle(fontSize: 12.5, color: c.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final p in kRealExamPresets) ...[
                        _PresetTile(
                          title: '${p.year} 年四川专升本真题',
                          subtitle: p.summary,
                          badge: _layoutBadge(p.build(), p),
                          icon: Icons.history_edu_rounded,
                          color: kPrimary,
                          onTap: () => Navigator.pop(context, p.year),
                        ),
                        const SizedBox(height: 8),
                      ],
                      _PresetTile(
                        title: 'AI 生成一套（推荐）',
                        subtitle: '结构对齐 2024 起真题：词汇20 / 阅读4篇16题 / 完形20 / 补全对话5 / 选词填空10 / 英译汉5 / 写作1，满分150分；话题与考点锚定四川专升本近四年真题。',
                        badge: '77题 · 150分',
                        icon: Icons.auto_awesome_rounded,
                        color: const Color(0xFF7C5CFF),
                        onTap: () => Navigator.pop(context, 'ai'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('取消', style: TextStyle(color: c.textSecondary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 生成卷面摘要角标：如「75题 · 100分」「77题 · 150分」
  String _layoutBadge(FullExamPaper paper, RealExamPreset preset) {
    final missing = preset.fillHints.isNotEmpty;
    final base = '${paper.layoutTotalQuestions}题 · ${paper.layoutTotalScore}分';
    return missing ? '$base · 缺部分题目，AI 补全' : base;
  }
}

class _PresetTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final String badge;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _PresetTile({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    final c = AppColors(isLight);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: _hover ? widget.color.withValues(alpha: 0.08) : c.cardAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? widget.color.withValues(alpha: 0.45) : c.chipBorder,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.icon, size: 18, color: widget.color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(widget.title,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: c.text),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(widget.badge,
                            style: TextStyle(
                                fontSize: 10.5,
                                color: widget.color,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(widget.subtitle,
                        style: TextStyle(
                            fontSize: 11.5, color: c.textSecondary, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
