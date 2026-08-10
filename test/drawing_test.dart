import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartenglish/widgets/drawing/drawing_canvas.dart';
import 'package:smartenglish/widgets/drawing/drawing_canvas_view.dart';

/// 画板核心链路测试：渲染可见 + 手势绘制跟手 + 撤销/重做 + 单点
void main() {
  testWidgets('画布可见且绘制手势能产生笔迹', (tester) async {
    final controller = DrawingCanvasController(width: 400, height: 300);
    int autosaveCount = 0;
    controller.onAutosave = () => autosaveCount++;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: DrawingCanvasView(
              controller: controller,
              onPanDown: controller.beginStroke,
              onPanStart: (p) {
                if (controller.isDrawing) controller.extendStroke(p);
              },
              onPanUpdate: controller.extendStroke,
              onPanEnd: controller.endStroke,
              onPanCancel: controller.cancelStroke,
              onTap: controller.tapStroke,
            ),
          ),
        ),
      ),
    );

    // 画布首帧即被绘制（CustomPaint 存在）
    expect(find.byType(CustomPaint), findsWidgets);
    expect(controller.strokes, isEmpty);

    // 模拟一次拖拽绘制（起点在画布内）
    final start = const Offset(60, 60);
    await tester.dragFrom(start, const Offset(120, 80));
    await tester.pumpAndSettle();

    // 拖拽应产生一条笔迹
    expect(controller.strokes.length, 1, reason: '一次拖拽应提交一条笔迹');
    expect(controller.strokes.first.points.length, greaterThan(1), reason: '笔迹应包含多个点');
    expect(autosaveCount, greaterThan(0), reason: '提交笔迹应触发自动保存');

    // 再画一笔
    await tester.dragFrom(const Offset(200, 200), const Offset(60, 40));
    await tester.pumpAndSettle();
    expect(controller.strokes.length, 2);

    // 撤销：笔迹回到 1
    controller.undo();
    await tester.pumpAndSettle();
    expect(controller.strokes.length, 1);
    expect(controller.canRedo, isTrue);

    // 重做：笔迹回到 2
    controller.redo();
    await tester.pumpAndSettle();
    expect(controller.strokes.length, 2);

    controller.dispose();
  });

  testWidgets('单点点击产生笔迹（画点）', (tester) async {
    final controller = DrawingCanvasController(width: 400, height: 300);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: DrawingCanvasView(
              controller: controller,
              onPanDown: controller.beginStroke,
              onPanUpdate: controller.extendStroke,
              onPanEnd: controller.endStroke,
              onPanCancel: controller.cancelStroke,
              onTap: controller.tapStroke,
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(150, 150));
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 1, reason: '单点点击应提交一条点笔迹');
    expect(controller.strokes.first.points.length, 1);

    controller.dispose();
  });

  testWidgets('橡皮擦笔迹标记为 eraser', (tester) async {
    final controller = DrawingCanvasController(width: 400, height: 300);
    controller.tool = DrawingTool.eraser;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: DrawingCanvasView(
              controller: controller,
              onPanDown: controller.beginStroke,
              onPanStart: (p) {
                if (controller.isDrawing) controller.extendStroke(p);
              },
              onPanUpdate: controller.extendStroke,
              onPanEnd: controller.endStroke,
              onPanCancel: controller.cancelStroke,
              onTap: controller.tapStroke,
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(80, 80), const Offset(100, 60));
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.isEraser, isTrue, reason: '橡皮工具提交的笔迹应标记为 eraser');

    controller.dispose();
  });

  testWidgets('直线工具只保留起终点', (tester) async {
    final controller = DrawingCanvasController(width: 400, height: 300);
    controller.tool = DrawingTool.line;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: DrawingCanvasView(
              controller: controller,
              onPanDown: controller.beginStroke,
              onPanStart: (p) {
                if (controller.isDrawing) controller.extendStroke(p);
              },
              onPanUpdate: controller.extendStroke,
              onPanEnd: controller.endStroke,
              onPanCancel: controller.cancelStroke,
              onTap: controller.tapStroke,
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(const Offset(50, 50), const Offset(200, 120));
    await tester.pumpAndSettle();

    expect(controller.strokes.length, 1);
    expect(controller.strokes.first.kind, StrokeKind.line);
    expect(controller.strokes.first.points.length, 2, reason: '直线应只有起点与终点');

    controller.dispose();
  });

  test('对称模式生成镜像笔迹组', () {
    final controller = DrawingCanvasController(width: 400, height: 300);
    controller.symmetryMode = 'quad';
    controller.tapStroke(const Offset(100, 100));
    // 四象限：原点 + 3 个镜像 = 4 条
    expect(controller.strokes.length, 4, reason: '四象限对称单点应产生 4 条笔迹');

    controller.undo();
    expect(controller.strokes.length, 0, reason: '一次撤销应移除整组镜像笔迹');
    controller.dispose();
  });
}