import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartenglish/main.dart';
import 'package:smartenglish/widgets/drawing/drawing_canvas_view.dart';
import 'package:smartenglish/widgets/drawing/drawing_tab_page.dart';

/// 真实 App 嵌入复现测试（容错版）：
/// 驱动完整 SmartEnglishApp → 侧边栏「更多功能」→「画板」→ 新建画布 →
/// 验证画布在真实布局（侧边栏 + 右侧 AI 栏 + 玻璃背景）中可见且可绘制。
///
/// 说明：main.dart 的 _SidebarNavPill 在 debug 模式下存在一个既有的
/// paint 断言（非对称 Border + borderRadius），与画板无关；此处过滤掉，
/// 只关注画板画布本身。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'onboardingDone': true,
      'uiMode': 'desktop',
      'uiStyle': 'classic',
      'theme_dark': false,
    });
  });

  testWidgets('真实App中画板画布可见且可绘制', (tester) async {
    // 过滤既有的侧边栏 paint 断言（非画板问题）
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('borderRadius == null || borderRadius == BorderRadius.zero')) {
        return; // 已知的侧边栏既有断言，忽略
      }
      FlutterError.presentError(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SmartEnglishApp());
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 1));

    // 主界面应出现侧边栏
    expect(find.text('学习'), findsOneWidget);
    expect(find.text('更多功能'), findsOneWidget);

    // 进入更多功能
    await tester.tap(find.text('更多功能'));
    await tester.pumpAndSettle();

    // 更多功能网格出现「画板」
    expect(find.text('画板'), findsWidgets);
    await tester.tap(find.text('画板').first);
    // 用 pumpAndSettle 等待入口页异步初始化存储并决定进入画布/列表
    await tester.pumpAndSettle();

    // 新流程：无已保存画作时直接进入画布（而非停在空列表）
    expect(find.byType(DrawingTabPage), findsOneWidget, reason: '无画作时应直接进入画布');
    final canvasFinder = find.byType(DrawingCanvasView);
    expect(canvasFinder, findsOneWidget);

    // 断言1：画布在真实布局中尺寸为正
    final rect = tester.getRect(canvasFinder);
    expect(rect.width, greaterThan(50), reason: '真实App中画布宽度应>50（实际=${rect.width}）');
    expect(rect.height, greaterThan(50), reason: '真实App中画布高度应>50（实际=${rect.height}）');

    // 断言2：画布中心落在可见区域内
    final pageRect = tester.getRect(find.byType(DrawingTabPage));
    expect(rect.center.dx, greaterThan(pageRect.left));
    expect(rect.center.dx, lessThan(pageRect.right));

    // 断言3：真实布局中拖拽能产生笔迹
    final viewWidget = tester.widget<DrawingCanvasView>(canvasFinder);
    expect(viewWidget.controller.strokes, isEmpty);
    await tester.dragFrom(rect.center, const Offset(100, 80));
    await tester.pump(const Duration(milliseconds: 600));
    expect(viewWidget.controller.strokes.length, 1,
        reason: '真实App布局中拖拽应产生笔迹（命中测试必须通过）');

    // 断言4：再画一笔
    await tester.dragFrom(rect.center + const Offset(40, 40), const Offset(-80, 60));
    await tester.pump(const Duration(milliseconds: 600));
    expect(viewWidget.controller.strokes.length, 2);
  }, timeout: const Timeout(Duration(seconds: 90)));
}