/// 引导页第一页粒子动效背景（仅 PC / 桌面端启用）。
///
/// 由两层叠加，还原 deepseek.com/harness 首页 hero 的鼠标动态粒子观感：
///  1. 蓝白流动光晕 —— 若干缓慢游走的大半径径向光斑 + 以鼠标为中心的光晕扰动；
///  2. 蓝色网格光点 + 点间连线 —— 90px 网格点阵，鼠标靠近排斥、弹性回位，
///     点/线随拉伸距离改变透明度，近鼠标处变亮放大（算法参考其 2D 网格粒子）。
///
/// 实现说明：
///  - 用 Ticker 驱动（非 AnimationController），每帧更新粒子模型并只重绘画布，
///    通过 CustomPainter 的 repaint listenable 触发，避免重建 widget 子树。
///  - 网格与光晕都是轻量绘制（点数 = (w/90+1)*(h/90+1)，桌面窗口约一两百个点），
///    径向渐变 shader 按尺寸缓存，性能友好。
///  - 仅要求 PC 端：非 Windows 直接返回空组件，不影响手机端原有引导页。
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 是否启用粒子背景（仅桌面端）。web 无 dart:io，用 defaultTargetPlatform 判断。
bool get _isDesktop {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
}

class ParticleBackdrop extends StatefulWidget {
  /// 深色模式：true 用白亮光点 + 深蓝光晕，false 用深蓝点线 + 浅蓝淡光晕
  final bool dark;

  /// 仅在 active（第一页）时才驱动动画；false 时暂停，零开销
  final bool active;

  /// 外部全屏鼠标输入（由引导页顶层全屏 MouseRegion 驱动），用于驱动网格点/光晕跟随。
  /// 比内部 MouseRegion 更可靠：引导页中间的卡片是不透明的，会挡住底层 MouseRegion 的 hover，
  /// 导致鼠标滑到中部时粒子无响应；把捕获放到最顶层则任何位置都能驱动粒子。
  final ValueNotifier<Offset?> mouseInput;

  const ParticleBackdrop({
    super.key,
    required this.dark,
    required this.active,
    required this.mouseInput,
  });

  @override
  State<ParticleBackdrop> createState() => _ParticleBackdropState();
}

/// 网格点（位置 + 速度）
class _GridPoint {
  double restX, restY, x, y, vx, vy;
  _GridPoint(this.restX, this.restY)
      : x = restX,
        y = restY,
        vx = 0,
        vy = 0;
}

/// 缓慢游走的流动光斑
class _Blob {
  double cx, cy; // 游走中心
  double ampX, ampY;
  double speed;
  double phase;
  double radius;
  int colorIndex;
  _Blob(this.cx, this.cy, this.ampX, this.ampY, this.speed, this.phase, this.radius, this.colorIndex);
}

/// 粒子上层数据 + 触发重绘的 listenable
class _PModel extends ChangeNotifier {
  bool dark;
  bool mouseActive = false;
  double mouseX = double.nan;
  double mouseY = double.nan;
  double mouseSmoothX = 0.5;
  double mouseSmoothY = 0.5;
  double elapsed = 0;
  Size size = Size.zero;
  List<_GridPoint> points = [];
  List<_Blob> blobs = [];
  int cols = 0;
  int rows = 0;

  /// 外部全屏鼠标输入（引导页顶层的 MouseRegion 驱动）；null 表示鼠标不在区域内
  ValueNotifier<Offset?>? mouseInput;

  _PModel(this.dark);

  /// 网格重塑（窗口尺寸变化时）
  void resize(double w, double h) {
    size = Size(w, h);
    const spacing = 90.0;
    cols = (w / spacing).ceil() + 1;
    rows = (h / spacing).ceil() + 1;
    final offX = (w - (cols - 1) * spacing) / 2;
    final offY = (h - (rows - 1) * spacing) / 2;
    points = List.generate(rows * cols, (i) {
      final c = i % cols;
      final r = i ~/ cols;
      return _GridPoint(offX + c * spacing, offY + r * spacing);
    });
    // 流动光斑：基于窗口尺寸居中布局，少量即可营造氛围
    final blobs = <_Blob>[];
    final rng = math.Random(7);
    const count = 5;
    for (var i = 0; i < count; i++) {
      blobs.add(_Blob(
        w * rng.nextDouble(),
        h * rng.nextDouble(),
        w * (0.06 + 0.08 * rng.nextDouble()),
        h * (0.06 + 0.08 * rng.nextDouble()),
        0.25 + 0.45 * rng.nextDouble(),
        rng.nextDouble() * 6.28,
        240 + 180 * rng.nextDouble(),
        i % 3,
      ));
    }
    this.blobs = blobs;
  }

  void step(double dt) {
    // 每帧从外部鼠标输入读取最新坐标（全屏 MouseRegion 在引导页顶层驱动）
    final mv = mouseInput?.value;
    if (mv != null) {
      mouseActive = true;
      mouseX = mv.dx;
      mouseY = mv.dy;
      mouseSmoothX += (mouseX - mouseSmoothX) * 0.1;
      mouseSmoothY += (mouseY - mouseSmoothY) * 0.1;
    } else {
      mouseActive = false;
    }
    // 网格：仅当鼠标在组件内才施加排斥力
    if (mouseActive && (size.width > 0)) {
      final mx = mouseSmoothX;
      final my = mouseSmoothY;
      for (final p in points) {
        final dx = p.x - mx;
        final dy = p.y - my;
        final d = math.sqrt(dx * dx + dy * dy);
        if (d < 140 && d > 0.1) {
          final f = (1 - d / 140) * 3.0; // 排斥强度（等价原式 *0.1*30）
          final inv = 1 / d;
          p.vx += dx * inv * f;
          p.vy += dy * inv * f;
        }
        // 弹性回拉 + 阻尼 + 积分
        p.vx += 0.05 * (p.restX - p.x);
        p.vy += 0.05 * (p.restY - p.y);
        p.vx *= 0.85;
        p.vy *= 0.85;
        p.x += p.vx;
        p.y += p.vy;
      }
    }
    elapsed += dt;
  }

  /// 供外部（State / Ticker 回调）请求重绘画布
  void markDirty() => notifyListeners();
}

class _ParticleBackdropState extends State<ParticleBackdrop>
    with SingleTickerProviderStateMixin {
  late final _PModel _m;
  late final Ticker _ticker;
  double _last = 0;

  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _m = _PModel(widget.dark)..mouseInput = widget.mouseInput;
    _ticker = createTicker(_onTick);
    if (widget.active) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant ParticleBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.dark != old.dark) {
      _m.dark = widget.dark;
      _m.markDirty();
    }
    if (widget.active != old.active) {
      if (widget.active) {
        _last = 0;
        _ticker.start();
      } else {
        _ticker.stop();
      }
    }
  }

  void _onTick(Duration time) {
    final t = time.inMicroseconds / 1e6;
    var dt = _last == 0 ? 0.016 : (t - _last);
    _last = t;
    if (dt <= 0) dt = 0.016;
    if (dt > 0.05) dt = 0.05; // 后台回来钳制
    _m.step(dt);
    _m.markDirty();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final h = constraints.maxHeight;
      if (w > 0 && h > 0 && (_lastSize.width != w || _lastSize.height != h)) {
        _lastSize = Size(w, h);
        _m.resize(w, h);
      }
      return RepaintBoundary(
        child: CustomPaint(
          size: Size(w, h),
          painter: _ParticlePainter(_m),
        ),
      );
    });
  }
}

/// 渲染层：读模型画"光晕 + 网格粒子"
class _ParticlePainter extends CustomPainter {
  final _PModel m;

  _ParticlePainter(this.m) : super(repaint: m);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    // 网格只有初次 resize 后才填充；为空时跳过全部
    if (m.points.isEmpty) return;

    final isDark = m.dark;

    // —— 1. 流动光晕（底层氛围） ——
    // 每个光斑一次径向渐变；Flutter 对相同 colors/stops 的 Gradient 内部复用 shader
    for (final b in m.blobs) {
      final ox = b.ampX * math.sin(m.elapsed * b.speed + b.phase);
      final oy = b.ampY * math.cos(m.elapsed * b.speed * 0.8 + b.phase);
      final cx = b.cx + ox;
      final cy = b.cy + oy;
      final col = _blobColor(b.colorIndex, isDark);
      canvas.drawCircle(
        Offset(cx, cy),
        b.radius,
        Paint()
          ..shader = RadialGradient(colors: [col, col.withValues(alpha: 0.5), const Color(0x00000000)], stops: const [0, 0.5, 1])
              .createShader(Rect.fromCircle(center: Offset(cx, cy), radius: b.radius * 1.7))
          ..blendMode = BlendMode.plus,
      );
    }

    // —— 2. 鼠标光晕扰动（随鼠标位置，浅色更淡以避免刺眼） ——
    if (m.mouseActive && !m.mouseX.isNaN) {
      const r = 220.0;
      final core = isDark ? const Color(0x55FFFFFF) : const Color(0x26FFFFFF);
      final mid = isDark ? const Color(0x408FC0FF) : const Color(0x00FFFFFF);
      canvas.drawCircle(
        Offset(m.mouseSmoothX, m.mouseSmoothY),
        r,
        Paint()
          ..shader = RadialGradient(colors: [core, mid, const Color(0x00000000)], stops: const [0, 0.4, 1])
              .createShader(Rect.fromCircle(center: Offset(m.mouseSmoothX, m.mouseSmoothY), radius: r))
          ..blendMode = BlendMode.plus,
      );
    }

    // —— 3. 网格连线 ——
    final lineBase = isDark ? const Color(0x805A80B2) : const Color(0x4C3C6490);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round;
    final cols = m.cols;
    // 横向连线（同一行相邻点）
    for (var r = 0; r < m.rows; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final a = m.points[r * cols + c];
        final b = m.points[r * cols + c + 1];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 20) continue;
        final inv = 1 / dist;
        final lx = dx * inv, ly = dy * inv;
        // 随拉伸变透明
        final stretch = ((dist - 90) / 60).clamp(0.0, 1.0);
        linePaint.color = lineBase.withValues(alpha: (1 - stretch) * 0.9);
        canvas.drawLine(Offset(a.x + 10 * lx, a.y + 10 * ly), Offset(b.x - 10 * lx, b.y - 10 * ly), linePaint);
      }
    }
    // 纵向连线（同一列相邻点）
    for (var r = 0; r < m.rows - 1; r++) {
      for (var c = 0; c < cols; c++) {
        final a = m.points[r * cols + c];
        final b = m.points[(r + 1) * cols + c];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 20) continue;
        final inv = 1 / dist;
        final lx = dx * inv, ly = dy * inv;
        final stretch = ((dist - 90) / 60).clamp(0.0, 1.0);
        linePaint.color = lineBase.withValues(alpha: (1 - stretch) * 0.9);
        canvas.drawLine(Offset(a.x + 10 * lx, a.y + 10 * ly), Offset(b.x - 10 * lx, b.y - 10 * ly), linePaint);
      }
    }

    // —— 4. 网格点 ——
    final dotBase = isDark ? const Color(0xFF86A9D6) : const Color(0xFF3C64A0);
    final dotPaint = Paint();
    if (m.mouseActive && !m.mouseX.isNaN) {
      final mx = m.mouseSmoothX, my = m.mouseSmoothY;
      for (final p in m.points) {
        final dx = p.x - mx, dy = p.y - my;
        final d = math.sqrt(dx * dx + dy * dy);
        final fall = math.max(0.0, 1 - d / 140);
        final size = 1.8 + 2 * fall;
        dotPaint.color = dotBase.withValues(alpha: (isDark ? 0.55 : 0.5) + 0.45 * fall);
        final half = size / 2;
        canvas.drawRect(Rect.fromLTWH(p.x - half, p.y - half, size, size), dotPaint);
      }
    } else {
      dotPaint.color = dotBase.withValues(alpha: isDark ? 0.5 : 0.45);
      const half = 0.9;
      for (final p in m.points) {
        canvas.drawRect(Rect.fromLTWH(p.x - half, p.y - half, 1.8, 1.8), dotPaint);
      }
    }
  }

  Color _blobColor(int i, bool dark) {
    if (dark) {
      const pal = [Color(0x33FFFFFF), Color(0x2E9BC4FF), Color(0x3D5A8BD6)];
      return pal[i % pal.length];
    }
    const pal = [Color(0x1E7FB3E8), Color(0x1A8FC0FF), Color(0x1E6B9AD4)];
    return pal[i % pal.length];
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true; // repaint listenable 已驱动
}