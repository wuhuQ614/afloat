import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartenglish/widgets/drawing/drawing_feature_page.dart';
import 'package:smartenglish/widgets/drawing/drawing_workspace_page.dart';
import 'package:smartenglish/widgets/drawing/drawing_tab_page.dart';
import 'package:smartenglish/widgets/drawing/drawing_canvas_view.dart';
import 'package:smartenglish/widgets/drawing/drawing_canvas.dart';

/// 画板完整用户流程集成测试（新入口逻辑）：
/// - 无已保存画作 → 直接进入画布 → 绘制 → 笔迹产生
/// - 有已保存画作 → 进入画作列表 → 打开/新建 → 画布
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('新流程：无画作时直接进入画布并可绘制', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: DrawingFeaturePage(darkMode: false)),
    );
    await tester.pumpAndSettle();

    // 无画作时应直接进入画板页（不再停在空列表）
    expect(find.byType(DrawingTabPage), findsOneWidget,
        reason: '无已保存画作时应直接进入画布，而非空列表页');
    final canvasFinder = find.byType(DrawingCanvasView);
    expect(canvasFinder, findsOneWidget);

    // 画布尺寸正常
    final rect = tester.getRect(canvasFinder);
    expect(rect.width, greaterThan(100), reason: '画布宽度应>100（实际=${rect.width}）');
    expect(rect.height, greaterThan(100), reason: '画布高度应>100（实际=${rect.height}）');

    // 绘制
    final viewWidget = tester.widget<DrawingCanvasView>(canvasFinder);
    expect(viewWidget.controller.strokes, isEmpty);
    await tester.dragFrom(rect.center, const Offset(100, 80));
    await tester.pumpAndSettle();
    expect(viewWidget.controller.strokes.length, 1, reason: '拖拽应产生笔迹');

    // 返回按钮应回到画作列表
    final backBtn = find.byIcon(Icons.arrow_back_rounded);
    expect(backBtn, findsOneWidget, reason: '画板页应有返回按钮');
    await tester.tap(backBtn);
    await tester.pumpAndSettle();
    expect(find.byType(DrawingWorkspacePage), findsOneWidget, reason: '返回后应到画作列表');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('新流程：新建画布对话框选预设', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: DrawingFeaturePage(darkMode: false)),
    );
    await tester.pumpAndSettle();

    // 直接进入画布后，返回列表
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(DrawingWorkspacePage), findsOneWidget);

    // 点 + 打开尺寸对话框
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('新建画布'), findsOneWidget);

    // 选「方型小」
    await tester.tap(find.textContaining('方型小'));
    await tester.pumpAndSettle();

    // 进入 512x512 画布
    expect(find.byType(DrawingTabPage), findsOneWidget);
    final canvasFinder = find.byType(DrawingCanvasView);
    expect(canvasFinder, findsOneWidget);
    final viewWidget = tester.widget<DrawingCanvasView>(canvasFinder);
    expect(viewWidget.controller.width, 512);
    expect(viewWidget.controller.height, 512);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('画布在窄容器中不被挤压为零', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final controller = DrawingCanvasController(width: 1920, height: 1080);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(children: [
            Expanded(
              flex: 7,
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
            Expanded(flex: 3, child: Container(color: Colors.grey)),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byType(DrawingCanvasView));
    expect(rect.width, greaterThan(100), reason: '画布宽度不应被挤压为零');
    expect(rect.height, greaterThan(100), reason: '画布高度不应被挤压为零');

    final center = rect.center;
    await tester.dragFrom(center, const Offset(80, 60));
    await tester.pumpAndSettle();
    expect(controller.strokes.length, 1, reason: '在 flex:7 容器内应能绘制');

    controller.dispose();
  }, timeout: const Timeout(Duration(seconds: 60)));
}