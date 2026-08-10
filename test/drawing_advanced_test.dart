import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartenglish/widgets/drawing/drawing_canvas.dart';

/// 高阶功能测试：图层系统 / 像素模式 / 透视辅助线
void main() {
  test('图层系统：增删/切换/锁定/可见/透明度/混合模式', () {
    final c = DrawingCanvasController(width: 400, height: 300);

    // 默认有一个图层
    expect(c.layers.length, 1);
    final layer0 = c.layers.first;
    expect(c.activeLayer?.id, layer0.id);

    // 在默认图层画一笔
    c.tapStroke(const Offset(50, 50));
    expect(c.strokes.length, 1);
    expect(c.strokes.first.layerId, layer0.id);

    // 新增图层并画一笔
    final layer1 = c.addLayer();
    expect(c.layers.length, 2);
    expect(c.activeLayer?.id, layer1.id);
    c.tapStroke(const Offset(100, 100));
    expect(c.strokes.length, 2);
    expect(c.strokes.last.layerId, layer1.id);

    // 切换回默认图层
    c.setActiveLayer(layer0.id);
    expect(c.activeLayer?.id, layer0.id);

    // 锁定默认图层后不能绘制
    c.setLayerLocked(layer0.id, true);
    final before = c.strokes.length;
    c.tapStroke(const Offset(200, 200));
    expect(c.strokes.length, before, reason: '锁定图层不应产生笔迹');

    // 解锁后可绘制
    c.setLayerLocked(layer0.id, false);
    c.tapStroke(const Offset(200, 200));
    expect(c.strokes.length, before + 1);

    // 可见性/透明度/混合模式
    c.setLayerVisible(layer1.id, false);
    expect(c.layers.firstWhere((l) => l.id == layer1.id).visible, isFalse);
    c.setLayerOpacity(layer1.id, 0.5);
    expect(c.layers.firstWhere((l) => l.id == layer1.id).opacity, 0.5);
    c.setLayerBlendMode(layer1.id, 'multiply');
    expect(c.layers.firstWhere((l) => l.id == layer1.id).blendMode, 'multiply');

    // 删除图层同时移除其笔迹
    final strokesBefore = c.strokes.length;
    final layer1Strokes = c.strokes.where((s) => s.layerId == layer1.id).length;
    expect(layer1Strokes, greaterThan(0));
    c.removeLayer(layer1.id);
    expect(c.layers.length, 1);
    expect(c.strokes.length, strokesBefore - layer1Strokes);

    // 至少保留一个图层
    expect(c.removeLayer(c.layers.first.id), isFalse);
    expect(c.layers.length, 1);

    c.dispose();
  });

  test('像素模式：笔迹吸附网格并按网格填充', () {
    final c = DrawingCanvasController(width: 320, height: 320);
    c.setPixelMode(true);
    c.setPixelGridSize(16);
    expect(c.pixelMode, isTrue);

    c.beginStroke(const Offset(30, 30));
    c.extendStroke(const Offset(100, 100));
    c.endStroke();

    expect(c.strokes.length, 1);
    final stroke = c.strokes.first;
    expect(stroke.isPixel, isTrue);

    // 点应吸附到 16px 网格中心（8, 24, 40, ...）
    for (final p in stroke.points) {
      final gx = (p.dx / 16).floor();
      final gy = (p.dy / 16).floor();
      expect(p.dx, closeTo(gx * 16 + 8, 0.5), reason: '点应吸附到网格中心');
      expect(p.dy, closeTo(gy * 16 + 8, 0.5));
    }

    c.dispose();
  });

  test('透视辅助线：开关与消失点管理', () {
    final c = DrawingCanvasController(width: 400, height: 300);

    expect(c.showPerspectiveGuides, isFalse);
    c.setPerspectiveGuides(true);
    expect(c.showPerspectiveGuides, isTrue);

    c.addPerspectivePoint(const Offset(200, 150));
    expect(c.perspectivePoints.length, 1);
    c.addPerspectivePoint(const Offset(50, 150));
    c.addPerspectivePoint(const Offset(350, 150));
    expect(c.perspectivePoints.length, 3);

    // 超过3个会移除最早的
    c.addPerspectivePoint(const Offset(100, 50));
    expect(c.perspectivePoints.length, 3);

    c.clearPerspectivePoints();
    expect(c.perspectivePoints, isEmpty);

    c.dispose();
  });

  test('图层混合模式与不透明度参与渲染（paintAll 不抛异常）', () {
    final c = DrawingCanvasController(width: 200, height: 200);
    final l2 = c.addLayer();
    c.setLayerBlendMode(l2.id, 'multiply');
    c.setLayerOpacity(l2.id, 0.5);
    c.tapStroke(const Offset(100, 100));

    // 用 PictureRecorder 触发 paintAll，验证图层渲染路径无异常
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    c.paintAll(canvas, const Size(200, 200));
    final picture = recorder.endRecording();
    expect(picture, isNotNull);
    picture.dispose();

    c.dispose();
  });
}