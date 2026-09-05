import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 单日统计
class DayStat {
  final DateTime date;
  int learned = 0;
  int newWords = 0;
  int wellFamiliar = 0;
  int familiar = 0;
  int vague = 0;
  int forget = 0;
  final bool isFuture;
  int due = 0;

  DayStat(this.date, {this.isFuture = false});

  int get total => isFuture ? due : learned;
}

// 提取原图精准配色
const cStatWellFamiliar = Color(0xFF38B58A); // 熟知 (墨绿)
const cStatFamiliar = Color(0xFF8DC5A0); // 认识 (浅绿)
const cStatVague = Color(0xFFEEB640); // 模糊 (黄橙)
const cStatForget = Color(0xFFDB6953); // 忘记 (橘红)
const cStatDue = Color(0xFFE5E5E5); // 待学 (浅灰)
const cStatLearned = Color(0xFF5B7FD4); // 历史已学
const cStatNew = Color(0xFF22C1A3); // 新学
const cStatTodayBg = Color(0xFFF6F6F6); // 今天整列的浅灰背景

class StatsBarChart extends StatelessWidget {
  final List<DayStat> days;
  final bool cognition;
  final Color textColor;
  final Color gridColor;

  const StatsBarChart({
    super.key,
    required this.days,
    required this.cognition,
    required this.textColor,
    required this.gridColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StatsBarPainter(
        days: days,
        cognition: cognition,
        textColor: textColor,
        gridColor: gridColor,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _StatsBarPainter extends CustomPainter {
  final List<DayStat> days;
  final bool cognition;
  final Color textColor;
  final Color gridColor;

  _StatsBarPainter({
    required this.days,
    required this.cognition,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 布局常量
    const yAxisWidth = 36.0; // 左侧 Y 轴留白宽度
    const xAxisHeight = 60.0; // 底部 X 轴文案留白高度
    final chartW = size.width - yAxisWidth;
    final chartH = size.height - xAxisHeight;
    final n = days.length;
    final colW = chartW / n;
    final barW = colW * 0.65; // 柱子稍微加宽，贴合原图

    // 计算 Y 轴最大值和步长
    int maxV = 1;
    for (final d in days) {
      if (d.total > maxV) maxV = d.total;
    }
    // 动态计算合适的网格步长 (划分为约 8-10 份)
    int step = _calculateNiceStep(maxV);
    int maxAxisValue = (maxV / step).ceil() * step;
    if (maxAxisValue == 0) maxAxisValue = step * 10;
    int gridLinesCount = (maxAxisValue / step).ceil();

    final dateStyle = TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5), height: 1.2);
    final yAxisStyle = TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.4));
    const todayStyle = TextStyle(fontSize: 11, color: Colors.white, height: 1.2, fontWeight: FontWeight.bold);

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    // 1. 绘制 Y 轴网格线和数值
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    for (var i = 0; i <= gridLinesCount; i++) {
      final value = i * step;
      final y = chartH - (chartH * value / maxAxisValue);

      // 横向网格线 (跳过最底部的 0 线以贴合原图视觉)
      if (i > 0) {
        canvas.drawLine(Offset(yAxisWidth, y), Offset(size.width, y), gridPaint);
      }

      // Y 轴数值 (左侧，右对齐)
      final tp = TextPainter(
        text: TextSpan(text: '$value', style: yAxisStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout(maxWidth: yAxisWidth - 8);

      tp.paint(canvas, Offset(yAxisWidth - tp.width - 8, y - tp.height / 2));
    }

    // 2. 绘制柱子和 X 轴
    for (var i = 0; i < n; i++) {
      final d = days[i];
      final targetDate = DateTime(d.date.year, d.date.month, d.date.day);
      final diff = targetDate.difference(todayDate).inDays;
      final isToday = diff == 0;

      final cx = yAxisWidth + colW * i + colW / 2;
      final left = cx - barW / 2;
      final totalH = d.total <= 0 ? 0.0 : chartH * d.total / maxAxisValue;

      // 如果是今天，绘制整列浅灰背景带
      if (isToday) {
        canvas.drawRect(
          Rect.fromLTWH(yAxisWidth + colW * i, 0, colW, chartH),
          Paint()..color = cStatTodayBg,
        );
      }

      // 绘制普通矩形段（移除 RRect，消除堆叠缝隙）
      void seg(double yTop, double height, Color color) {
        if (height <= 0) return;
        canvas.drawRect(
          Rect.fromLTWH(left, yTop, barW, height),
          Paint()..color = color,
        );
      }

      double top = chartH;
      if (d.isFuture) {
        seg(top - totalH, totalH, cStatDue);
      } else if (cognition) {
        // 四色堆叠（自底向上）
        final parts = <(int, Color)>[
          (d.forget, cStatForget),
          (d.vague, cStatVague),
          (d.familiar, cStatFamiliar),
          (d.wellFamiliar, cStatWellFamiliar),
        ];
        for (final (v, color) in parts) {
          if (v <= 0) continue;
          final h = chartH * v / maxAxisValue;
          top -= h;
          seg(top, h, color);
        }
        // 兜底补齐缺失认知的数据
        final misc = d.learned - d.wellFamiliar - d.familiar - d.vague - d.forget;
        if (misc > 0) {
          final h = chartH * misc / maxAxisValue;
          top -= h;
          seg(top, h, cStatFamiliar);
        }
      } else {
        // 复习·新学模式
        final newH = chartH * d.newWords / maxAxisValue;
        final reviewH = chartH * (d.learned - d.newWords).clamp(0, 1 << 31) / maxAxisValue;
        top -= newH;
        seg(top, newH, cStatNew);
        top -= reviewH;
        seg(top, reviewH, cStatLearned);
      }

      // X 轴日期标签（垂直排版）
      final label = _getRelativeDayLabel(diff);
      final dp = TextPainter(
        text: TextSpan(text: label, style: isToday ? todayStyle : dateStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      final labelY = chartH + 12;

      // 如果是今天，绘制绿色圆角背景块
      if (isToday) {
        final bgRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, labelY + dp.height / 2),
            width: dp.width + 12,
            height: dp.height + 8,
          ),
          const Radius.circular(6),
        );
        canvas.drawRRect(bgRect, Paint()..color = cStatWellFamiliar);
      }

      dp.paint(canvas, Offset(cx - dp.width / 2, labelY));
    }
  }

  // 辅助方法：生成垂直的相对日期文案
  String _getRelativeDayLabel(int diff) {
    if (diff == 0) return "今\n天";
    if (diff == -1) return "昨\n天";
    if (diff == -2) return "前\n天";
    if (diff < -2) return "${-diff}\n天\n前";
    if (diff == 1) return "明\n天";
    if (diff == 2) return "后\n天";
    return "$diff\n天\n后";
  }

  // 辅助方法：计算舒适的 Y 轴步长
  int _calculateNiceStep(int maxVal) {
    if (maxVal <= 10) return 2;
    if (maxVal <= 50) return 10;
    if (maxVal <= 100) return 20;
    if (maxVal <= 500) return 50;
    if (maxVal <= 1000) return 100;

    // 超大数值动态计算
    double roughStep = maxVal / 8;
    double mag = math.pow(10, roughStep.floor().toString().length - 1).toDouble();
    double normalizedStep = roughStep / mag;
    if (normalizedStep <= 1.5) return (1 * mag).toInt();
    if (normalizedStep <= 2.5) return (2 * mag).toInt();
    if (normalizedStep <= 7.5) return (5 * mag).toInt();
    return (10 * mag).toInt();
  }

  @override
  bool shouldRepaint(covariant _StatsBarPainter old) =>
      old.days != days || old.cognition != cognition || old.textColor != textColor;
}
