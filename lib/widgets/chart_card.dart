/// 图表卡片：解析 AI 输出的 ```chart 代码块 JSON，渲染柱状/折线/饼图。
/// 与 CodeCard 同级（嵌入聊天流），深色卡片风格。
/// JSON 格式：
/// {
///   "type": "bar" | "line" | "pie",
///   "title": "标题（可选）",
///   "labels": ["9.1","9.2"],
///   "datasets": [ {"label": "认识", "data": [52,31], "color": "#3B82F6"} ],
///   "stacked": true   // 仅 bar 有效：多数据集堆叠（默认并列）
/// }
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'code_card.dart';

/// 代码块分发：lang == 'chart' 时尝试解析为图表卡（JSON 非法时回退普通代码卡）。
/// main.dart 与 markdown_renderer.dart 的四处代码块渲染统一走这里。
Widget chartAwareCodeBlock(String code, String lang) {
  if (lang.toLowerCase().trim() == 'chart') {
    try {
      final v = jsonDecode(code);
      if (v is Map<String, dynamic>) return ChartCard(rawJson: code);
    } catch (_) {}
  }
  return CodeCard(code: code, lang: lang);
}

class ChartCard extends StatelessWidget {
  final String rawJson;
  const ChartCard({super.key, required this.rawJson});

  // 默认调色板（数据集未指定颜色时循环使用）
  static const List<Color> _palette = [
    Color(0xFF3B82F6), Color(0xFF10B981), Color(0xFFF59E0B),
    Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFF06B6D4),
    Color(0xFFEC4899), Color(0xFF84CC16),
  ];

  static Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final s = hex.replaceFirst('#', '').trim();
    if (s.length == 6) return Color(int.parse('FF$s', radix: 16));
    if (s.length == 8) return Color(int.parse(s, radix: 16));
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? cfg;
    String? err;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        cfg = decoded;
      } else {
        err = 'chart JSON 顶层必须是对象';
      }
    } catch (e) {
      err = 'chart JSON 解析失败：$e';
    }

    final type = (cfg?['type'] ?? 'bar').toString().toLowerCase();
    final title = (cfg?['title'] ?? '').toString();
    final labels = ((cfg?['labels'] as List?) ?? [])
        .map((e) => e.toString())
        .toList();
    final rawSets = ((cfg?['datasets'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final stacked = (cfg?['stacked'] ?? false) == true;

    final datasets = <_Series>[];
    for (var i = 0; i < rawSets.length; i++) {
      final s = rawSets[i];
      final data = ((s['data'] as List?) ?? [])
          .map((e) => (e is num) ? e.toDouble() : (double.tryParse(e.toString()) ?? 0.0))
          .toList();
      // 对齐 labels 长度：短补 0，长截断
      while (data.length < labels.length) {
        data.add(0);
      }
      if (data.length > labels.length) data.removeRange(labels.length, data.length);
      datasets.add(_Series(
        label: (s['label'] ?? '系列${i + 1}').toString(),
        data: data,
        color: _parseColor(s['color'] as String?) ?? _palette[i % _palette.length],
      ));
    }

    if (err == null && (datasets.isEmpty || labels.isEmpty)) {
      err = 'chart JSON 需要 labels 与 datasets 字段';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2028),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2E3036)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 标题栏（仿 CodeCard）
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF2E3036))),
          ),
          child: Row(children: [
            Icon(_iconFor(type), size: 14, color: const Color(0xFF9FE1CB)),
            const SizedBox(width: 7),
            Text(
              err != null ? 'chart（解析失败）' : (title.isEmpty ? '图表 · $type' : title),
              style: const TextStyle(fontSize: 12, color: Color(0xFFD5D7DE)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: err != null
              ? Text(err, style: const TextStyle(fontSize: 12, color: Color(0xFFF87171)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    height: type == 'pie' ? 180 : 200,
                    width: double.infinity,
                    child: _ChartPaint(type: type, labels: labels, datasets: datasets, stacked: stacked),
                  ),
                  if (datasets.length > 1 || type == 'pie') ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        for (final d in datasets)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 9, height: 9, decoration: BoxDecoration(color: d.color, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 4),
                            Text(d.label, style: const TextStyle(fontSize: 11, color: Color(0xFFB8BAC2))),
                          ]),
                      ],
                    ),
                  ],
                ]),
        ),
      ]),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'line':
        return Icons.show_chart_rounded;
      case 'pie':
        return Icons.pie_chart_outline_rounded;
      default:
        return Icons.bar_chart_rounded;
    }
  }
}

class _Series {
  final String label;
  final List<double> data;
  final Color color;
  const _Series({required this.label, required this.data, required this.color});
}

class _ChartPaint extends StatelessWidget {
  final String type;
  final List<String> labels;
  final List<_Series> datasets;
  final bool stacked;

  const _ChartPaint({required this.type, required this.labels, required this.datasets, required this.stacked});

  @override
  Widget build(BuildContext context) {
    if (type == 'pie') {
      return CustomPaint(painter: _PiePainter(datasets: datasets), child: const SizedBox.expand());
    }
    return CustomPaint(
      painter: _BarLinePainter(type: type, labels: labels, datasets: datasets, stacked: stacked),
      child: const SizedBox.expand(),
    );
  }
}

class _BarLinePainter extends CustomPainter {
  final String type;
  final List<String> labels;
  final List<_Series> datasets;
  final bool stacked;

  _BarLinePainter({required this.type, required this.labels, required this.datasets, required this.stacked});

  @override
  void paint(Canvas canvas, Size size) {
    const axisPad = 22.0;
    const labelH = 16.0;
    final chartW = size.width - axisPad * 2;
    final chartH = size.height - axisPad - labelH;
    final n = labels.length;
    if (n == 0 || datasets.isEmpty) return;

    // 坐标轴
    final axisPaint = Paint()
      ..color = const Color(0xFF3A3D46)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(axisPad, axisPad), Offset(axisPad, axisPad + chartH), axisPaint);
    canvas.drawLine(Offset(axisPad, axisPad + chartH), Offset(axisPad + chartW, axisPad + chartH), axisPaint);

    double maxV = 1;
    if (stacked) {
      for (var i = 0; i < n; i++) {
        var sum = 0.0;
        for (final s in datasets) {
          sum += s.data[i];
        }
        if (sum > maxV) maxV = sum;
      }
    } else {
      for (final s in datasets) {
        for (final v in s.data) {
          if (v > maxV) maxV = v;
        }
      }
    }
    maxV *= 1.15;

    final labelStyle = TextStyle(fontSize: 9.5, color: const Color(0xFFB8BAC2).withValues(alpha: 0.8));

    if (type == 'line') {
      // 折线：每系列一条
      for (final s in datasets) {
        final path = Path();
        final points = <Offset>[];
        for (var i = 0; i < n; i++) {
          final x = axisPad + (n == 1 ? chartW / 2 : chartW * i / (n - 1));
          final y = axisPad + chartH - chartH * s.data[i] / maxV;
          points.add(Offset(x, y));
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(path, Paint()..color = s.color..style = PaintingStyle.stroke..strokeWidth = 2);
        for (final p in points) {
          canvas.drawCircle(p, 3, Paint()..color = s.color);
        }
      }
    } else {
      // 柱状：stacked 堆叠 / 否则组内并列
      final groupW = chartW / n;
      for (var i = 0; i < n; i++) {
        final cx = axisPad + groupW * i + groupW / 2;
        if (stacked) {
          var top = axisPad + chartH;
          for (final s in datasets) {
            final h = chartH * s.data[i] / maxV;
            top -= h;
            _bar(canvas, cx, top, groupW * 0.5, h, s.color);
          }
        } else {
          final m = datasets.length;
          final barW = (groupW * 0.6) / m;
          for (var si = 0; si < m; si++) {
            final s = datasets[si];
            final h = chartH * s.data[i] / maxV;
            final left = axisPad + groupW * i + groupW * 0.2 + barW * si;
            _bar(canvas, left + barW / 2, axisPad + chartH - h, barW, h, s.color);
          }
        }
      }
    }

    // x 轴标签
    for (var i = 0; i < n; i++) {
      final cx = axisPad + (n == 1 ? chartW / 2 : chartW * i / (n - 1));
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, axisPad + chartH + 3));
    }
  }

  void _bar(Canvas canvas, double cx, double top, double w, double h, Color color) {
    if (h <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(cx - w / 2, top, w, h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _BarLinePainter old) =>
      old.labels != labels || old.datasets != datasets || old.stacked != stacked || old.type != type;
}

class _PiePainter extends CustomPainter {
  final List<_Series> datasets;
  _PiePainter({required this.datasets});

  @override
  void paint(Canvas canvas, Size size) {
    final data = datasets.isEmpty ? [] : datasets.first.data;
    final total = data.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(size.width, size.height) / 2 - 8;
    var start = -math.pi / 2;
    for (var i = 0; i < datasets.length; i++) {
      final v = data[i];
      if (v <= 0) continue;
      final sweep = math.pi * 2 * v / total;
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: radius), start, sweep, true,
          Paint()..color = datasets[i].color);
      // 扇区描边（与背景同色，形成分隔）
      canvas.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: radius), start, sweep, true,
          Paint()..color = const Color(0xFF1E2028)..style = PaintingStyle.stroke..strokeWidth = 2);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) => old.datasets != datasets;
}
