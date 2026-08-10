import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartenglish/widgets/drawing/drawing_canvas.dart';

/// 像素级渲染验证：真正把笔迹渲染成位图，检查是否产生可见（非白）像素。
/// 这能证明"画布可见 + 画的内容真的显示出来"，而不只是数据被记录。
///
/// 注意：renderToImage / toByteData 是真实引擎异步调用，
/// 必须在 tester.runAsync 中执行，否则在测试的 FakeAsync 环境会挂起。
void main() {
  testWidgets('画布渲染：画一条红线后，位图里必须出现红色像素', (tester) async {
    final c = DrawingCanvasController(width: 200, height: 200);
    c.setColor(const Color(0xFFFF0000));
    c.setLineWidth(10);

    // 画一条从左上到右下的粗线
    c.beginStroke(const Offset(20, 20));
    c.extendStroke(const Offset(100, 100));
    c.extendStroke(const Offset(180, 180));
    c.endStroke();
    expect(c.strokes.length, 1);

    final counts = await tester.runAsync(() async {
      final img = await c.renderToImage();
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      final px = byteData!.buffer.asUint32List();
      int redCount = 0;
      int nonWhite = 0;
      for (final v in px) {
        final r = v & 0xff;
        final g = (v >> 8) & 0xff;
        final b = (v >> 16) & 0xff;
        if (r > 250 && g > 250 && b > 250) continue;
        nonWhite++;
        if (r > 150 && g < 100 && b < 100) redCount++;
      }
      return (nonWhite: nonWhite, red: redCount, total: px.length);
    });

    expect(counts, isNotNull);
    expect(counts!.nonWhite, greaterThan(100),
        reason: '画布渲染后应有大量非白像素（实际 nonWhite=${counts.nonWhite}/${counts.total}）——若接近0说明画布根本没渲染出内容');
    expect(counts.red, greaterThan(50),
        reason: '应出现红色笔迹像素（实际 red=${counts.red}）');

    c.dispose();
  });

  testWidgets('画布渲染：空画布应为纯白背景（画布本身可见）', (tester) async {
    final c = DrawingCanvasController(width: 100, height: 100);

    final counts = await tester.runAsync(() async {
      final img = await c.renderToImage();
      final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      final px = byteData!.buffer.asUint32List();
      int white = 0;
      for (final v in px) {
        final r = v & 0xff;
        final g = (v >> 8) & 0xff;
        final b = (v >> 16) & 0xff;
        final a = (v >> 24) & 0xff;
        if (r > 250 && g > 250 && b > 250 && a > 250) white++;
      }
      return (white: white, total: px.length);
    });

    expect(counts!.white, greaterThan(counts.total - 10),
        reason: '空画布应几乎全白（white=${counts.white}/${counts.total}）');
    c.dispose();
  });

  testWidgets('完整绘制链路：拖拽手势 → 笔迹 → 渲染出蓝色像素', (tester) async {
    final c = DrawingCanvasController(width: 300, height: 300);
    c.setColor(const Color(0xFF0000FF));
    c.setLineWidth(8);

    // 用与真实页面相同的手势接入
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanDown: (d) => c.beginStroke(d.localPosition),
              onPanStart: (d) => c.extendStroke(d.localPosition),
              onPanUpdate: (d) => c.extendStroke(d.localPosition),
              onPanEnd: (_) => c.endStroke(),
              child: CustomPaint(
                painter: _TestPainter(controller: c),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragFrom(const Offset(60, 60), const Offset(150, 120));
    await tester.pumpAndSettle();

    expect(c.strokes.length, 1);

    final counts = await tester.runAsync(() async {
      final img = await c.renderToImage();
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      final px = bd!.buffer.asUint32List();
      int blue = 0;
      for (final v in px) {
        final r = v & 0xff;
        final g = (v >> 8) & 0xff;
        final b = (v >> 16) & 0xff;
        if (b > 150 && r < 100 && g < 100) blue++;
      }
      return blue;
    });

    expect(counts, greaterThan(50), reason: '拖拽后应有蓝色笔迹像素（实际 blue=$counts）');
    c.dispose();
  });

  testWidgets('像素模式：渲染出网格对齐的色块', (tester) async {
    final c = DrawingCanvasController(width: 160, height: 160);
    c.setPixelMode(true);
    c.setPixelGridSize(16);
    c.setColor(const Color(0xFF00AA00));

    c.beginStroke(const Offset(24, 24));
    c.extendStroke(const Offset(40, 24));
    c.endStroke();

    expect(c.strokes.length, 1);
    expect(c.strokes.first.isPixel, isTrue);

    final counts = await tester.runAsync(() async {
      final img = await c.renderToImage();
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      final px = bd!.buffer.asUint32List();
      int green = 0;
      for (final v in px) {
        final r = v & 0xff;
        final g = (v >> 8) & 0xff;
        final b = (v >> 16) & 0xff;
        if (g > 100 && r < 100 && b < 100) green++;
      }
      return green;
    });

    // 像素笔迹应填满完整网格单元（每个16x16单元=256像素）
    expect(counts, greaterThan(200), reason: '像素模式应渲染出完整色块（实际 green=$counts）');
    c.dispose();
  });
}

class _TestPainter extends CustomPainter {
  final DrawingCanvasController controller;
  _TestPainter({required this.controller});

  @override
  void paint(Canvas canvas, Size size) {
    controller.paintAll(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _TestPainter old) => true;
}