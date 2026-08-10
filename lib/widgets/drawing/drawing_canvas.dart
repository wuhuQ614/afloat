/// 画布核心控制器（矢量直绘架构 · 功能完整版）
///
/// 笔迹以矢量点列存储，由 CustomPainter 每帧直接绘制——画布立即可见、
/// 笔迹即时跟手。支持：38 种笔刷差异化渲染、橡皮擦、油漆桶、吸管、
/// 直线/圆形、撤销/重做、导入图片。
library;

import 'dart:async';
import 'dart:convert' show Base64Codec;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'drawing_models.dart';

/// 画布工具类型
enum DrawingTool { brush, eraser, bucket, eyedropper, line, circle }

/// 笔迹形态
enum StrokeKind { freehand, line, circle, bitmap }

/// 确定性伪随机数（保证实时预览与提交后渲染一致）
class _Rand {
  int s;
  _Rand(this.s) {
    if (s == 0) s = 1;
  }
  double next() {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s / 0x7fffffff;
  }
}

/// 一条笔迹（矢量或位图）
class Stroke {
  final StrokeKind kind;
  final List<Offset> points;
  final Color color;
  final double width;
  final double opacity;
  final bool isEraser;
  final String brushId;
  final int seed;
  final ui.Image? image;
  final int layerId;
  final bool isPixel;

  const Stroke({
    required this.kind,
    required this.points,
    required this.color,
    required this.width,
    this.opacity = 1,
    this.isEraser = false,
    this.brushId = 'round',
    this.seed = 1,
    this.image,
    this.layerId = 0,
    this.isPixel = false,
  });
}

/// 笔刷渲染风格
enum _BrushStyle { solid, grainy, particles, tapered, ribbon, pixel }

/// 画布控制器
class DrawingCanvasController extends ChangeNotifier {
  int width;
  int height;

  // ===== 笔刷状态 =====
  DrawingTool tool = DrawingTool.brush;
  Color color = const Color(0xFFEF4444);
  double lineWidth = 6;
  double brushOpacity = 1;
  DrawingBrush brush = DrawingBrush.byId('round');

  // ===== 对称模式：none | h | v | quad | hex | oct =====
  String symmetryMode = 'none';

  // ===== 像素模式：笔迹吸附到网格，呈现像素画效果 =====
  bool pixelMode = false;
  int pixelGridSize = 16;

  // ===== 透视辅助线：显示 1-3 个消失点的参考线 =====
  bool showPerspectiveGuides = false;
  final List<Offset> perspectivePoints = [];

  // ===== 图层系统 =====
  final List<CanvasLayer> layers = [];
  int _activeLayerId = 0;
  int _nextLayerId = 0;

  // ===== 滤镜（对已绘内容的整体调整，作用于渲染与导出） =====
  final DrawingFilter filter = DrawingFilter();

  // ===== 笔迹（唯一数据源） =====
  final List<Stroke> strokes = [];

  // ===== 实时绘制中的临时点 =====
  final List<Offset> livePoints = [];
  bool isDrawing = false;
  int _liveSeed = 1;

  // ===== 撤销/重做（按笔迹组，对称镜像一次撤销） =====
  final List<List<Stroke>> _undoStack = [];
  final List<List<Stroke>> _redoStack = [];

  // ===== 画布背景色 =====
  Color backgroundColor = Colors.white;

  bool _disposed = false;
  void Function()? onAutosave;

  DrawingCanvasController({required this.width, required this.height}) {
    // 初始化默认图层
    addLayer();
  }

  bool get disposed => _disposed;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  CanvasLayer? get activeLayer => _layerById(_activeLayerId);

  CanvasLayer? _layerById(int id) {
    for (final l in layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  // ==================== 图层管理 ====================

  /// 新增图层并设为活动图层
  CanvasLayer addLayer() {
    final layer = CanvasLayer(id: _nextLayerId, name: '图层 ${_nextLayerId + 1}');
    _nextLayerId++;
    layers.add(layer);
    _activeLayerId = layer.id;
    notifyListeners();
    return layer;
  }

  /// 删除图层（至少保留一个）
  bool removeLayer(int id) {
    if (layers.length <= 1) return false;
    layers.removeWhere((l) => l.id == id);
    if (_activeLayerId == id) {
      _activeLayerId = layers.last.id;
    }
    // 同时移除该图层上的笔迹
    strokes.removeWhere((s) => s.layerId == id);
    notifyListeners();
    onAutosave?.call();
    return true;
  }

  /// 切换活动图层
  void setActiveLayer(int id) {
    if (_layerById(id) == null) return;
    _activeLayerId = id;
    notifyListeners();
  }

  /// 设置图层可见性
  void setLayerVisible(int id, bool visible) {
    final l = _layerById(id);
    if (l == null) return;
    l.visible = visible;
    notifyListeners();
  }

  /// 设置图层不透明度（0-1）
  void setLayerOpacity(int id, double opacity) {
    final l = _layerById(id);
    if (l == null) return;
    l.opacity = opacity.clamp(0.0, 1.0).toDouble();
    notifyListeners();
  }

  /// 设置图层混合模式（kBlendModes 的 value）
  void setLayerBlendMode(int id, String blendMode) {
    final l = _layerById(id);
    if (l == null) return;
    l.blendMode = blendMode;
    notifyListeners();
  }

  /// 设置图层锁定（锁定后不可绘制）
  void setLayerLocked(int id, bool locked) {
    final l = _layerById(id);
    if (l == null) return;
    l.locked = locked;
    notifyListeners();
  }

  /// 上移/下移图层（order：+1 上移，-1 下移）
  void moveLayer(int id, int order) {
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    final newIdx = idx + order;
    if (newIdx < 0 || newIdx >= layers.length) return;
    final layer = layers.removeAt(idx);
    layers.insert(newIdx, layer);
    notifyListeners();
  }

  /// 设置画笔颜色并刷新
  void setColor(Color c) {
    color = c;
    notifyListeners();
  }

  /// 选择笔刷并刷新
  void setBrush(DrawingBrush b) {
    brush = b;
    if (b.defaultWidth > 0) lineWidth = b.defaultWidth;
    notifyListeners();
  }

  /// 设置线条粗细并刷新
  void setLineWidth(double w) {
    lineWidth = w.clamp(1.0, 60.0).toDouble();
    notifyListeners();
  }

  /// 设置笔刷不透明度并刷新
  void setBrushOpacity(double o) {
    brushOpacity = o.clamp(0.05, 1.0).toDouble();
    notifyListeners();
  }

  /// 设置对称模式并刷新
  void setSymmetryMode(String mode) {
    symmetryMode = mode;
    notifyListeners();
  }

  /// 切换像素模式并刷新
  void setPixelMode(bool on) {
    pixelMode = on;
    notifyListeners();
  }

  /// 设置像素网格大小并刷新
  void setPixelGridSize(int size) {
    pixelGridSize = size.clamp(4, 128);
    notifyListeners();
  }

  /// 切换透视辅助线显示并刷新
  void setPerspectiveGuides(bool show) {
    showPerspectiveGuides = show;
    notifyListeners();
  }

  /// 添加/清除透视消失点（最多3个）
  void addPerspectivePoint(Offset p) {
    if (perspectivePoints.length >= 3) perspectivePoints.removeAt(0);
    perspectivePoints.add(p);
    notifyListeners();
  }

  void clearPerspectivePoints() {
    perspectivePoints.clear();
    notifyListeners();
  }

  /// 像素吸附：把点吸附到网格中心
  Offset _snapToGrid(Offset p) {
    if (!pixelMode) return p;
    final g = pixelGridSize.toDouble();
    return Offset(
      (p.dx / g).floor() * g + g / 2,
      (p.dy / g).floor() * g + g / 2,
    );
  }

  // ==================== 绘制交互 ====================

  /// 当前活动图层是否允许绘制
  bool get _canDrawOnActiveLayer {
    final l = activeLayer;
    return l != null && !l.locked;
  }

  void beginStroke(Offset p) {
    if (!_canDrawOnActiveLayer) return;
    isDrawing = true;
    _liveSeed = (DateTime.now().microsecondsSinceEpoch & 0x7fffffff) | 1;
    livePoints
      ..clear()
      ..add(_snapToGrid(p));
    notifyListeners();
  }

  void extendStroke(Offset p) {
    if (!isDrawing) return;
    final sp = _snapToGrid(p);
    if (tool == DrawingTool.line || tool == DrawingTool.circle) {
      // 形状模式只保留起点 + 当前点
      if (livePoints.length < 2) {
        livePoints.add(sp);
      } else {
        livePoints[1] = sp;
      }
      notifyListeners();
      return;
    }
    final last = livePoints.last;
    if ((sp - last).distance < 1) return;
    livePoints.add(sp);
    notifyListeners();
  }

  /// 单点：画一个点
  void tapStroke(Offset p) {
    if (!_canDrawOnActiveLayer) return;
    _commitStroke([_snapToGrid(p)]);
  }

  void endStroke() {
    if (!isDrawing) return;
    isDrawing = false;
    if (livePoints.isEmpty) return;
    final pts = List.of(livePoints);
    livePoints.clear();
    _commitStroke(pts);
  }

  void cancelStroke() {
    isDrawing = false;
    livePoints.clear();
    notifyListeners();
  }

  void _commitStroke(List<Offset> pts) {
    if (pts.isEmpty) return;
    StrokeKind kind = StrokeKind.freehand;
    if (tool == DrawingTool.line && pts.length >= 2) kind = StrokeKind.line;
    if (tool == DrawingTool.circle && pts.length >= 2) kind = StrokeKind.circle;

    // 对称模式：生成镜像点集组
    final pointGroups = _symmetricGroups(pts);
    final group = <Stroke>[];
    for (final g in pointGroups) {
      group.add(Stroke(
        kind: kind,
        points: g,
        color: color,
        width: lineWidth,
        opacity: brushOpacity,
        isEraser: tool == DrawingTool.eraser,
        brushId: brush.id,
        seed: _liveSeed,
        layerId: _activeLayerId,
        isPixel: pixelMode,
      ));
    }
    strokes.addAll(group);
    _undoStack.add(group);
    _redoStack.clear();
    notifyListeners();
    onAutosave?.call();
  }

  /// 对称模式点集扩展
  List<List<Offset>> _symmetricGroups(List<Offset> pts) {
    final result = <List<Offset>>[pts];
    final cx = width / 2;
    final cy = height / 2;
    Offset mirrorH(Offset p) => Offset(2 * cx - p.dx, p.dy);
    Offset mirrorV(Offset p) => Offset(p.dx, 2 * cy - p.dy);
    List<Offset> mapAll(List<Offset> src, Offset Function(Offset) f) => src.map(f).toList();
    List<Offset> rotate(List<Offset> src, double rad) {
      return src.map((p) {
        final dx = p.dx - cx;
        final dy = p.dy - cy;
        return Offset(cx + dx * math.cos(rad) - dy * math.sin(rad), cy + dx * math.sin(rad) + dy * math.cos(rad));
      }).toList();
    }

    switch (symmetryMode) {
      case 'h':
        result.add(mapAll(pts, mirrorH));
        break;
      case 'v':
        result.add(mapAll(pts, mirrorV));
        break;
      case 'quad':
        result.add(mapAll(pts, mirrorH));
        result.add(mapAll(pts, mirrorV));
        result.add(pts.map((p) => mirrorV(mirrorH(p))).toList());
        break;
      case 'hex':
        for (var i = 1; i < 6; i++) {
          result.add(rotate(pts, i * math.pi / 3));
        }
        break;
      case 'oct':
        for (var i = 1; i < 8; i++) {
          result.add(rotate(pts, i * math.pi / 4));
        }
        break;
    }
    return result;
  }

  // ==================== 撤销 / 重做 ====================

  void undo() {
    if (_undoStack.isEmpty) return;
    final group = _undoStack.removeLast();
    for (final s in group) {
      strokes.remove(s);
    }
    _redoStack.add(group);
    notifyListeners();
    onAutosave?.call();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    final group = _redoStack.removeLast();
    strokes.addAll(group);
    _undoStack.add(group);
    notifyListeners();
    onAutosave?.call();
  }

  // ==================== 清空 ====================

  Future<void> clearAll() async {
    strokes.clear();
    _undoStack.clear();
    _redoStack.clear();
    livePoints.clear();
    notifyListeners();
    onAutosave?.call();
  }

  // ==================== 滤镜 ====================

  /// 应用滤镜：仅处理活动图层——栅格化该图层 → 像素变换 → 用一张位图笔迹
  /// 替换该图层原有笔迹（可撤销）。
  Future<void> applyFilter(DrawingFilter f) async {
    final layerId = _activeLayerId;
    final hasLayerStrokes = strokes.any((s) => s.layerId == layerId);
    if (!hasLayerStrokes || f.isIdentity) return;
    final base = await renderLayerToImage(layerId);

    // 模糊：走 ImageFilter 离屏合成
    ui.Image cur = base;
    bool ownsCur = false;
    if (f.blur > 0) {
      final rec = ui.PictureRecorder();
      final cv = Canvas(rec);
      cv.saveLayer(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: f.blur, sigmaY: f.blur),
      );
      cv.drawImage(cur, Offset.zero, Paint());
      cv.restore();
      final pic = rec.endRecording();
      final blurred = await pic.toImage(width, height);
      pic.dispose();
      cur.dispose();
      cur = blurred;
      ownsCur = true;
    }

    final needPixel = f.brightness != 100 ||
        f.contrast != 100 ||
        f.saturate != 100 ||
        f.hueRotate != 0 ||
        f.grayscale > 0 ||
        f.invert > 0 ||
        f.sepia > 0;

    if (needPixel) {
      final byteData = await cur.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData != null) {
        final rgba = byteData.buffer.asUint8List();
        final bright = f.brightness / 100;
        final contrast = f.contrast / 100;
        final sat = f.saturate / 100;
        final grayAmt = f.grayscale / 100;
        final invAmt = f.invert / 100;
        final sepAmt = f.sepia / 100;
        final hueRad = f.hueRotate * math.pi / 180;
        final hueCos = math.cos(hueRad);
        final hueSin = math.sin(hueRad);
        for (var i = 0; i < rgba.length; i += 4) {
          if (rgba[i + 3] == 0) continue;
          var r = rgba[i].toDouble();
          var g = rgba[i + 1].toDouble();
          var b = rgba[i + 2].toDouble();
          // 灰度
          if (grayAmt > 0) {
            final gray = 0.299 * r + 0.587 * g + 0.114 * b;
            r = r * (1 - grayAmt) + gray * grayAmt;
            g = g * (1 - grayAmt) + gray * grayAmt;
            b = b * (1 - grayAmt) + gray * grayAmt;
          }
          // 棕褐色
          if (sepAmt > 0) {
            final sr = 0.393 * r + 0.769 * g + 0.189 * b;
            final sg = 0.349 * r + 0.686 * g + 0.168 * b;
            final sb = 0.272 * r + 0.534 * g + 0.131 * b;
            r = r * (1 - sepAmt) + sr * sepAmt;
            g = g * (1 - sepAmt) + sg * sepAmt;
            b = b * (1 - sepAmt) + sb * sepAmt;
          }
          // 反色
          if (invAmt > 0) {
            r = (255 - r) * invAmt + r * (1 - invAmt);
            g = (255 - g) * invAmt + g * (1 - invAmt);
            b = (255 - b) * invAmt + b * (1 - invAmt);
          }
          // 色相旋转
          if (f.hueRotate != 0) {
            final nr = (0.213 + hueCos * 0.787 - hueSin * 0.213) * r +
                (0.715 - hueCos * 0.715 - hueSin * 0.715) * g +
                (0.072 - hueCos * 0.072 + hueSin * 0.928) * b;
            final ng = (0.213 - hueCos * 0.213 + hueSin * 0.143) * r +
                (0.715 + hueCos * 0.285 + hueSin * 0.140) * g +
                (0.072 - hueCos * 0.072 - hueSin * 0.283) * b;
            final nb = (0.213 - hueCos * 0.213 - hueSin * 0.787) * r +
                (0.715 - hueCos * 0.715 + hueSin * 0.715) * g +
                (0.072 + hueCos * 0.928 + hueSin * 0.072) * b;
            r = nr;
            g = ng;
            b = nb;
          }
          // 亮度 + 对比度
          r = ((r * bright - 128) * contrast + 128);
          g = ((g * bright - 128) * contrast + 128);
          b = ((b * bright - 128) * contrast + 128);
          // 饱和度
          if (sat != 1) {
            final l = 0.299 * r + 0.587 * g + 0.114 * b;
            r = l + (r - l) * sat;
            g = l + (g - l) * sat;
            b = l + (b - l) * sat;
          }
          rgba[i] = r.round().clamp(0, 255);
          rgba[i + 1] = g.round().clamp(0, 255);
          rgba[i + 2] = b.round().clamp(0, 255);
        }
        final filtered = await _imageFromPixels(rgba, width, height);
        if (ownsCur) cur.dispose();
        cur = filtered;
        ownsCur = true;
      }
    }

    if (_disposed) {
      if (ownsCur) cur.dispose();
      return;
    }

    // 仅替换活动图层的笔迹为一张位图笔迹（旧笔迹进撤销栈可恢复）
    final layerStrokes = strokes.where((s) => s.layerId == layerId).toList();
    _undoStack.add(layerStrokes);
    _redoStack.clear();
    strokes.removeWhere((s) => s.layerId == layerId);
    strokes.add(Stroke(
      kind: StrokeKind.bitmap,
      points: const [],
      color: Colors.white,
      width: 1,
      image: cur,
      layerId: layerId,
    ));
    notifyListeners();
    onAutosave?.call();
  }

  // ==================== 油漆桶 / 吸管 ====================

  /// 油漆桶：栅格化当前画面 → flood fill → 结果作为位图笔迹
  Future<void> floodFill(Offset p, Color fill) async {
    final img = await renderToImage();
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (byteData == null) return;
    final px = byteData.buffer.asUint32List();

    final x = p.dx.clamp(0.0, (width - 1).toDouble()).round();
    final y = p.dy.clamp(0.0, (height - 1).toDouble()).round();
    final target = px[y * width + x];
    final fillVal = _rgba(fill);
    if (target == fillVal) return;

    const tolerance = 30;
    // 小端 Uint32：R 在最低字节、A 在最高字节
    bool close(int a, int b) {
      final dr = (a & 0xff) - (b & 0xff);
      final dg = ((a >> 8) & 0xff) - ((b >> 8) & 0xff);
      final db = ((a >> 16) & 0xff) - ((b >> 16) & 0xff);
      final da = ((a >> 24) & 0xff) - ((b >> 24) & 0xff);
      return dr * dr + dg * dg + db * db + da * da <= tolerance * tolerance * 4;
    }

    final stack = <int>[y * width + x];
    final visited = Uint8List(width * height);
    while (stack.isNotEmpty) {
      final idx = stack.removeLast();
      if (visited[idx] == 1) continue;
      if (!close(px[idx], target)) continue;
      visited[idx] = 1;
      px[idx] = fillVal;
      final ix = idx % width;
      if (ix > 0) stack.add(idx - 1);
      if (ix < width - 1) stack.add(idx + 1);
      if (idx >= width) stack.add(idx - width);
      if (idx < width * (height - 1)) stack.add(idx + width);
    }

    final filled = await _imageFromPixels(byteData.buffer.asUint8List(), width, height);
    final bmp = Stroke(
      kind: StrokeKind.bitmap,
      points: const [],
      color: fill,
      width: 1,
      image: filled,
      layerId: _activeLayerId,
    );
    strokes.add(bmp);
    _undoStack.add([bmp]);
    _redoStack.clear();
    notifyListeners();
    onAutosave?.call();
  }

  /// 吸管：栅格化当前画面，读取指定像素颜色
  Future<Color?> eyedrop(Offset p) async {
    final img = await renderToImage();
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (byteData == null) return null;
    final px = byteData.buffer.asUint32List();
    final x = p.dx.clamp(0.0, (width - 1).toDouble()).round();
    final y = p.dy.clamp(0.0, (height - 1).toDouble()).round();
    final v = px[y * width + x];
    // 小端 Uint32：R 在最低字节，A 在最高字节
    return Color.fromARGB((v >> 24) & 0xff, v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff);
  }

  /// 导入图片：缩放适配画布后作为位图笔迹
  Future<void> importImageToLayer(ui.Image img) async {
    await _addBitmap(img);
    onAutosave?.call();
  }

  /// 恢复会话画作（不触发自动保存回调）
  Future<void> restoreFromDataUrl(String dataUrl) async {
    try {
      final idx = dataUrl.indexOf(',');
      if (idx < 0) return;
      final bytes = const Base64Codec().decode(dataUrl.substring(idx + 1));
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      await _addBitmap(frame.image);
      frame.image.dispose();
    } catch (_) {}
  }

  Future<void> _addBitmap(ui.Image img) async {
    final scale = math.min(width / img.width, height / img.height);
    final dw = img.width * scale;
    final dh = img.height * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH((width - dw) / 2, (height - dh) / 2, dw, dh),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final raster = await picture.toImage(width, height);
    picture.dispose();
    if (_disposed) {
      raster.dispose();
      return;
    }
    strokes.add(Stroke(
      kind: StrokeKind.bitmap,
      points: const [],
      color: Colors.white,
      width: 1,
      image: raster,
      layerId: _activeLayerId,
    ));
    _undoStack.add([strokes.last]);
    _redoStack.clear();
    notifyListeners();
  }

  /// rawRgba 内存字节序为 R,G,B,A；小端 Uint32 读取时 R 在最低字节
  int _rgba(Color c) =>
      (c.r * 255).round() |
      ((c.g * 255).round() << 8) |
      ((c.b * 255).round() << 16) |
      ((c.a * 255).round() << 24);

  Future<ui.Image> _imageFromPixels(Uint8List rgba, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      w,
      h,
      ui.PixelFormat.rgba8888,
      (ui.Image image) => completer.complete(image),
    );
    return completer.future;
  }

  // ==================== 导出 ====================

  Future<ui.Image> renderToImage() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    paintAll(canvas, Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    picture.dispose();
    return img;
  }

  /// 只渲染指定图层的笔迹（不含背景/网格/辅助线），用于滤镜与图层导出
  Future<ui.Image> renderLayerToImage(int layerId) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (final stroke in strokes) {
      if (stroke.layerId != layerId) continue;
      paintStroke(canvas, stroke, gridSize: pixelGridSize);
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    picture.dispose();
    return img;
  }

  Future<Uint8List?> exportPng() async {
    final img = await renderToImage();
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return byteData?.buffer.asUint8List();
  }

  Future<String> exportPngDataUrl() async {
    final bytes = await exportPng();
    if (bytes == null) return '';
    return 'data:image/png;base64,${const Base64Codec().encode(bytes)}';
  }

  // ==================== 渲染（供 CustomPainter 复用） ====================

  /// 把整个画布画到 canvas 上（视图层 CustomPainter 直接调用）
  void paintAll(Canvas canvas, Size size) {
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);

    // 背景
    canvas.drawRect(bounds, Paint()..color = backgroundColor);

    // 逐图层渲染：每个图层独立 saveLayer，应用不透明度与混合模式；
    // 橡皮擦（BlendMode.clear）只清除所在图层内容。
    for (final layer in layers) {
      if (!layer.visible) continue;
      final layerPaint = Paint()
        ..blendMode = resolveBlendMode(layer.blendMode)
        ..color = Color.fromRGBO(255, 255, 255, layer.opacity);
      canvas.saveLayer(bounds, layerPaint);
      // 该图层的笔迹
      for (final stroke in strokes) {
        if (stroke.layerId != layer.id) continue;
        paintStroke(canvas, stroke, gridSize: pixelGridSize);
      }
      // 实时笔迹画在活动图层上
      if (layer.id == _activeLayerId && livePoints.isNotEmpty) {
        final live = Stroke(
          kind: tool == DrawingTool.line
              ? StrokeKind.line
              : (tool == DrawingTool.circle ? StrokeKind.circle : StrokeKind.freehand),
          points: List.of(livePoints),
          color: color,
          width: lineWidth,
          opacity: brushOpacity,
          isEraser: tool == DrawingTool.eraser,
          brushId: brush.id,
          seed: _liveSeed,
          layerId: _activeLayerId,
          isPixel: pixelMode,
        );
        paintStroke(canvas, live, gridSize: pixelGridSize);
      }
      canvas.restore();
    }

    // 像素网格（叠加在最上层，仅编辑提示）
    if (pixelMode) {
      _paintPixelGrid(canvas, bounds);
    }

    // 透视辅助线
    if (showPerspectiveGuides && perspectivePoints.isNotEmpty) {
      _paintPerspectiveGuides(canvas);
    }
  }

  /// 绘制像素网格
  void _paintPixelGrid(Canvas canvas, Rect bounds) {
    final g = pixelGridSize.toDouble();
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (double x = 0; x <= bounds.width; x += g) {
      canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), paint);
    }
    for (double y = 0; y <= bounds.height; y += g) {
      canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), paint);
    }
  }

  /// 绘制透视辅助线：连接各消失点，并标记消失点
  void _paintPerspectiveGuides(Canvas canvas) {
    final linePaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.fill;
    // 连接每对消失点
    for (var i = 0; i < perspectivePoints.length; i++) {
      for (var j = i + 1; j < perspectivePoints.length; j++) {
        canvas.drawLine(perspectivePoints[i], perspectivePoints[j], linePaint);
      }
    }
    // 单点时也画一条水平参考线
    if (perspectivePoints.length == 1) {
      final p = perspectivePoints[0];
      canvas.drawLine(Offset(0, p.dy), Offset(width.toDouble(), p.dy), linePaint);
    }
    // 标记消失点
    for (final p in perspectivePoints) {
      canvas.drawCircle(p, 5, dotPaint);
      canvas.drawCircle(p, 9, Paint()
        ..color = const Color(0xFF3B82F6).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }
  }

  /// 渲染单条笔迹。[gridSize] 用于像素模式笔迹的网格填充。
  static void paintStroke(Canvas canvas, Stroke stroke, {int gridSize = 16}) {
    if (stroke.kind == StrokeKind.bitmap) {
      if (stroke.image != null) {
        canvas.drawImage(stroke.image!, Offset.zero, Paint());
      }
      return;
    }
    if (stroke.points.isEmpty) return;

    switch (stroke.kind) {
      case StrokeKind.line:
        _paintLine(canvas, stroke);
        return;
      case StrokeKind.circle:
        _paintCircle(canvas, stroke);
        return;
      default:
        break;
    }

    // 像素模式笔迹：按网格填充方块（橡皮则按网格擦除方块）
    if (stroke.isPixel) {
      _paintPixelCells(canvas, stroke.points, stroke.color.withValues(alpha: stroke.opacity),
          gridSize, isEraser: stroke.isEraser);
      return;
    }

    final brush = DrawingBrush.byId(stroke.brushId);
    final style = _styleOf(brush);
    final col = stroke.color.withValues(alpha: stroke.opacity);
    final eraserPaint = Paint()
      ..blendMode = BlendMode.clear
      ..strokeWidth = stroke.width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    if (stroke.isEraser) {
      canvas.drawPath(_smoothPath(stroke.points), eraserPaint);
      return;
    }

    switch (style) {
      case _BrushStyle.pixel:
        _paintPixel(canvas, stroke.points, col, stroke.width, stroke.seed);
        break;
      case _BrushStyle.particles:
        _paintParticles(canvas, stroke.points, col, stroke.width, stroke.seed);
        break;
      case _BrushStyle.grainy:
        _paintSmoothPath(canvas, stroke.points, col.withValues(alpha: stroke.opacity * 0.85), stroke.width);
        _paintGrain(canvas, stroke.points, col, stroke.width, stroke.seed);
        break;
      case _BrushStyle.tapered:
        _paintTapered(canvas, stroke.points, col, stroke.width);
        break;
      case _BrushStyle.ribbon:
        _paintRibbon(canvas, stroke.points, col, stroke.width);
        break;
      default:
        _paintSmoothPath(canvas, stroke.points, col, stroke.width);
    }
  }

  /// 像素模式：把点吸附到的网格单元格填充为方块（去重）
  static void _paintPixelCells(Canvas canvas, List<Offset> points, Color color, int gridSize, {bool isEraser = false}) {
    final g = gridSize.toDouble();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    if (isEraser) paint.blendMode = BlendMode.clear;
    final seen = <int>{};
    for (final p in points) {
      final gx = (p.dx / g).floor();
      final gy = (p.dy / g).floor();
      final key = gx * 100000 + gy;
      if (!seen.add(key)) continue;
      canvas.drawRect(Rect.fromLTWH(gx * g, gy * g, g, g), paint);
    }
  }

  static _BrushStyle _styleOf(DrawingBrush b) {
    switch (b.texture) {
      case BrushTexture.pixel:
        return _BrushStyle.pixel;
      case BrushTexture.calligraphy:
      case BrushTexture.flat:
        return _BrushStyle.ribbon;
      case BrushTexture.gpen:
      case BrushTexture.dippen:
      case BrushTexture.inkbrush:
        return _BrushStyle.tapered;
      case BrushTexture.spray:
      case BrushTexture.airbrush:
      case BrushTexture.cloud:
      case BrushTexture.splatter:
      case BrushTexture.stipple:
      case BrushTexture.fur:
      case BrushTexture.grass:
        return _BrushStyle.particles;
      case BrushTexture.crayon:
      case BrushTexture.charcoal:
      case BrushTexture.chalk:
      case BrushTexture.pastel:
      case BrushTexture.oilpaint:
      case BrushTexture.softpastel:
      case BrushTexture.acrylic:
      case BrushTexture.gouache:
      case BrushTexture.sand:
      case BrushTexture.grunge:
      case BrushTexture.cloth:
      case BrushTexture.noiseGrain:
        return _BrushStyle.grainy;
      default:
        return _BrushStyle.solid;
    }
  }

  // ---------- 形状 ----------
  static void _paintLine(Canvas canvas, Stroke s) {
    if (s.points.length < 2) return;
    final paint = Paint()
      ..color = s.isEraser ? const Color(0x00000000) : s.color.withValues(alpha: s.opacity)
      ..blendMode = s.isEraser ? BlendMode.clear : BlendMode.srcOver
      ..strokeWidth = s.width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawLine(s.points.first, s.points.last, paint);
  }

  static void _paintCircle(Canvas canvas, Stroke s) {
    if (s.points.length < 2) return;
    final center = s.points.first;
    final radius = (s.points.last - center).distance;
    final paint = Paint()
      ..color = s.color.withValues(alpha: s.opacity)
      ..strokeWidth = s.width
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawCircle(center, radius, paint);
  }

  // ---------- 基础路径 ----------
  static Path _smoothPath(List<Offset> points) {
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);
    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
      return path;
    }
    for (var i = 1; i < points.length - 1; i++) {
      final mid = Offset((points[i].dx + points[i + 1].dx) / 2, (points[i].dy + points[i + 1].dy) / 2);
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  static void _paintSmoothPath(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length == 1) {
      canvas.drawCircle(points[0], math.max(width / 2, 0.5), Paint()..color = color);
      return;
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(width, 0.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.drawPath(_smoothPath(points), paint);
  }

  // ---------- 颗粒 ----------
  static void _paintGrain(Canvas canvas, List<Offset> points, Color color, double width, int seed) {
    final rand = _Rand(seed);
    final paint = Paint()..color = color;
    final step = math.max(width * 0.4, 2.0);
    final along = _samplesAlong(points, step);
    for (final p in along) {
      final n = 2 + rand.next() * 3;
      for (var i = 0; i < n; i++) {
        final ang = rand.next() * 2 * math.pi;
        final dist = rand.next() * width * 0.6;
        final r = math.max(0.3, width * 0.08 * rand.next());
        canvas.drawCircle(p + Offset(math.cos(ang) * dist, math.sin(ang) * dist), r, paint);
      }
    }
  }

  // ---------- 喷枪/颗粒云 ----------
  static void _paintParticles(Canvas canvas, List<Offset> points, Color color, double width, int seed) {
    final rand = _Rand(seed);
    final paint = Paint()..color = color;
    final step = math.max(width * 0.3, 1.5);
    final along = _samplesAlong(points, step);
    for (final p in along) {
      final n = 6 + (rand.next() * 8).toInt();
      for (var i = 0; i < n; i++) {
        final ang = rand.next() * 2 * math.pi;
        final dist = rand.next() * width * 0.9;
        final r = math.max(0.4, width * 0.12 * rand.next());
        canvas.drawCircle(p + Offset(math.cos(ang) * dist, math.sin(ang) * dist), r, paint);
      }
    }
  }

  // ---------- 锥形（压感笔） ----------
  static void _paintTapered(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    if (points.length == 1) {
      canvas.drawCircle(points[0], width / 2, paint);
      return;
    }
    final n = points.length;
    for (var i = 0; i < n; i++) {
      // 两端细中间粗的压感曲线
      final t = i / (n - 1);
      final pressure = 0.3 + 0.7 * math.sin(t * math.pi);
      final r = math.max(width / 2 * pressure, 0.4);
      canvas.drawCircle(points[i], r, paint);
    }
  }

  // ---------- 扁带（书法/扁头） ----------
  static void _paintRibbon(Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length < 2) {
      if (points.isNotEmpty) canvas.drawCircle(points[0], width / 2, Paint()..color = color);
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    // 固定 45° 笔尖方向
    final dir = const Offset(0.7071, 0.7071);
    final perp = Offset(-dir.dy, dir.dx);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final half = width / 2;
      final p1 = a + perp * half;
      final p2 = b + perp * half;
      final p3 = b - perp * half;
      final p4 = a - perp * half;
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(p3.dx, p3.dy)
        ..lineTo(p4.dx, p4.dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  // ---------- 像素 ----------
  static void _paintPixel(Canvas canvas, List<Offset> points, Color color, double width, int seed) {
    final cell = math.max(width.round(), 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    final seen = <int>{};
    for (final p in points) {
      final gx = (p.dx / cell).floor();
      final gy = (p.dy / cell).floor();
      final key = gx * 100003 + gy;
      if (!seen.add(key)) continue;
      canvas.drawRect(
        Rect.fromLTWH(gx * cell.toDouble(), gy * cell.toDouble(), cell.toDouble(), cell.toDouble()),
        paint,
      );
    }
  }

  /// 沿点列按步长取样
  static List<Offset> _samplesAlong(List<Offset> points, double step) {
    final out = <Offset>[];
    if (points.isEmpty) return out;
    out.add(points[0]);
    var acc = 0.0;
    for (var i = 1; i < points.length; i++) {
      final seg = (points[i] - points[i - 1]).distance;
      var travelled = 0.0;
      while (acc + (seg - travelled) >= step) {
        final need = step - acc;
        travelled += need;
        final t = seg == 0 ? 0.0 : travelled / seg;
        out.add(Offset.lerp(points[i - 1], points[i], t.clamp(0.0, 1.0).toDouble())!);
        acc = 0.0;
      }
      acc += seg - travelled;
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    // 去重收集：当前笔迹 + 撤销/重做栈中的笔迹（撤销后的笔迹不在 strokes 里）
    final all = <Stroke>{...strokes};
    for (final group in _undoStack) {
      all.addAll(group);
    }
    for (final group in _redoStack) {
      all.addAll(group);
    }
    for (final s in all) {
      s.image?.dispose();
    }
    strokes.clear();
    _undoStack.clear();
    _redoStack.clear();
    livePoints.clear();
    super.dispose();
  }
}