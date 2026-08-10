/// 画布可视化渲染组件（矢量直绘版）
///
/// CustomPainter 直接调用控制器的矢量笔迹渲染，
/// 首帧即可显示、笔迹即时跟手，不再依赖任何异步位图合成。
///
/// 坐标系：控制器用「画布逻辑坐标」（width × height，如 1920×1080）；
/// 显示区按 contain 等比缩放到可用空间。手势坐标经 scale 换算后交给控制器。
library;

import 'package:flutter/material.dart';
import 'drawing_canvas.dart';

class DrawingCanvasView extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool showGrid;
  final void Function(Offset canvasPoint)? onTap;
  final void Function(Offset canvasPoint)? onPanDown;
  final void Function(Offset canvasPoint)? onPanStart;
  final void Function(Offset canvasPoint)? onPanUpdate;
  final void Function()? onPanEnd;
  final VoidCallback? onPanCancel;

  const DrawingCanvasView({
    super.key,
    required this.controller,
    this.showGrid = false,
    this.onTap,
    this.onPanDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
  });

  @override
  State<DrawingCanvasView> createState() => _DrawingCanvasViewState();
}

class _DrawingCanvasViewState extends State<DrawingCanvasView> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(DrawingCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final c = widget.controller;
      final contentSize = Size(c.width.toDouble(), c.height.toDouble());
      final displaySize = _fitSize(contentSize, Size(constraints.maxWidth, constraints.maxHeight));
      final scale = displaySize.width / c.width;

      // 显示坐标 → 画布逻辑坐标
      Offset toCanvas(Offset display) => Offset(display.dx / scale, display.dy / scale);

      return Center(
        child: SizedBox(
          width: displaySize.width,
          height: displaySize.height,
          child: GestureDetector(
            // CustomPaint 无 child 时 deferToChild 命中测试会失败，必须 opaque
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onTap?.call(toCanvas(d.localPosition)),
            onPanDown: (d) => widget.onPanDown?.call(toCanvas(d.localPosition)),
            onPanStart: (d) => widget.onPanStart?.call(toCanvas(d.localPosition)),
            onPanUpdate: (d) => widget.onPanUpdate?.call(toCanvas(d.localPosition)),
            onPanEnd: (_) => widget.onPanEnd?.call(),
            onPanCancel: widget.onPanCancel,
            child: CustomPaint(
              painter: _CanvasPainter(controller: c, scale: scale),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
    });
  }

  Size _fitSize(Size content, Size constraint) {
    final scale = _fitScale(content.width, content.height, constraint.width, constraint.height);
    return Size(content.width * scale, content.height * scale);
  }

  double _fitScale(double cw, double ch, double maxW, double maxH) {
    if (maxW <= 0 || maxH <= 0) return 1;
    final sx = maxW / cw;
    final sy = maxH / ch;
    return sx < sy ? sx : sy;
  }
}

class _CanvasPainter extends CustomPainter {
  final DrawingCanvasController controller;
  final double scale;

  _CanvasPainter({required this.controller, required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    // 缩放到画布逻辑坐标系
    canvas.scale(scale, scale);

    final logicalSize = Size(controller.width.toDouble(), controller.height.toDouble());

    // 白底 + 全部矢量笔迹（首帧即有内容，直接矢量绘制）
    controller.paintAll(canvas, logicalSize);

    // 画布边框
    canvas.drawRect(
      Rect.fromLTWH(0, 0, logicalSize.width, logicalSize.height),
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale,
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return true; // 控制器 notifyListeners → setState → 重建重绘
  }
}