/// DIY 背景渲染引擎：把 [DiyBackdrop] 配置画成真实背景。
///
/// 渲染顺序（自下而上）：基座 → 图层栈（按配置数组顺序） → 蒙层 scrim。
/// 动效仅在 [DiyBackdrop.animated] 为真且图层中存在可动图层（光带/光束/柔光斑）时启动 Ticker，
/// 否则画一帧静态图后不再重绘——这是主界面卡顿问题的治本做法。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme_diy.dart';

/// DIY 背景视图。
///
/// [blur] 大于 0 时在其上叠一层模糊（毛玻璃主题）；[isLight] 参与噪点/暗角的默认取向。
class DiyBackdropView extends StatefulWidget {
  final DiyBackdrop config;
  final bool isLight;
  /// 毛玻璃模糊 sigma（0 = 不模糊）。通常由主题决定，DIY 配置的 blur 与之取较大者。
  final double blur;
  /// 是否允许动效（省电模式 / 高性能模式下由外部传 false）
  final bool animate;

  const DiyBackdropView({
    super.key,
    required this.config,
    required this.isLight,
    this.blur = 0,
    this.animate = true,
  });

  @override
  State<DiyBackdropView> createState() => _DiyBackdropViewState();
}

class _DiyBackdropViewState extends State<DiyBackdropView>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  double _t = 1.5;

  bool get _needAnim {
    if (!widget.animate || !widget.config.animated) return false;
    for (final l in widget.config.layers) {
      if (!l.enabled) continue;
      if (l.kind == DiyLayerKind.ribbon ||
          l.kind == DiyLayerKind.beam ||
          l.kind == DiyLayerKind.glow) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant DiyBackdropView old) {
    super.didUpdateWidget(old);
    if (old.config != widget.config || old.animate != widget.animate) {
      _syncController();
    }
  }

  void _syncController() {
    final need = _needAnim;
    if (need && _ctrl == null) {
      _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 24))
        ..addListener(_onTick)
        ..repeat();
    } else if (!need && _ctrl != null) {
      _ctrl!
        ..stop()
        ..dispose();
      _ctrl = null;
    }
    // 静态时定格在固定相位，避免每次重建跳变
    if (!need) _t = 1.5;
  }

  void _onTick() {
    if (!mounted) return;
    // 24 秒一圈，换算成秒制相位（与 GlassBackground 的呼吸节奏接近）
    _t = (_ctrl?.value ?? 0) * 24;
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl
      ?..stop()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sigma = math.max(widget.blur, widget.config.blur);
    final paint = CustomPaint(
      size: Size.infinite,
      isComplex: true,
      painter: _DiyBackdropPainter(
        config: widget.config,
        isLight: widget.isLight,
        t: _t,
      ),
    );
    if (sigma <= 0) return paint;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: paint,
    );
  }
}

/// 供设置页小尺寸预览复用（无 Ticker，静态帧）。blur > 0 时同样叠模糊，
/// 与真实背景观感一致（毛玻璃主题的 DIY 预览需要看到模糊后的效果）。
class DiyBackdropPreview extends StatelessWidget {
  final DiyBackdrop config;
  final bool isLight;
  final double blur;

  const DiyBackdropPreview({
    super.key,
    required this.config,
    required this.isLight,
    this.blur = 0,
  });

  @override
  Widget build(BuildContext context) {
    final paint = CustomPaint(
      size: Size.infinite,
      isComplex: true,
      painter: _DiyBackdropPainter(config: config, isLight: isLight, t: 1.5),
    );
    if (blur <= 0) return paint;
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: paint,
    );
  }
}

class _DiyBackdropPainter extends CustomPainter {
  final DiyBackdrop config;
  final bool isLight;
  final double t;

  _DiyBackdropPainter({
    required this.config,
    required this.isLight,
    required this.t,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    _paintBase(canvas, size, rect);
    for (final l in config.layers) {
      if (!l.enabled) continue;
      switch (l.kind) {
        case DiyLayerKind.glow:
          _paintGlow(canvas, size, l);
        case DiyLayerKind.grid:
          _paintGrid(canvas, size, l);
        case DiyLayerKind.ribbon:
          _paintRibbon(canvas, size, l);
        case DiyLayerKind.noise:
          _paintNoise(canvas, size, l);
        case DiyLayerKind.stripe:
          _paintStripe(canvas, size, l);
        case DiyLayerKind.beam:
          _paintBeam(canvas, size, l);
        case DiyLayerKind.dots:
          _paintDots(canvas, size, l);
        case DiyLayerKind.vignette:
          _paintVignette(canvas, size, l);
      }
    }
    if (config.scrim > 0) {
      canvas.drawRect(
        rect,
        Paint()..color = (isLight ? Colors.white : Colors.black)
            .withValues(alpha: config.scrim),
      );
    }
  }

  // ---------- 基座 ----------
  void _paintBase(Canvas canvas, Size size, Rect rect) {
    final cs = config.colors;
    if (cs.isEmpty) return;
    final first = cs.first;
    if (config.base == DiyBaseKind.solid || cs.length == 1) {
      canvas.drawRect(rect, Paint()..color = first);
      return;
    }
    final stops = config.stops.length == cs.length ? config.stops : null;
    switch (config.base) {
      case DiyBaseKind.linear:
        final (a, b) = diyGradientAlignments(config.angle);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: a,
              end: b,
              colors: cs,
              stops: stops,
            ).createShader(rect),
        );
      case DiyBaseKind.radial:
        final c = size.center(Offset.zero);
        final r = math.max(size.width, size.height) * 0.78;
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: Alignment.center,
              radius: 1,
              colors: cs,
              stops: stops,
            ).createShader(Rect.fromCircle(center: c, radius: r)),
        );
      case DiyBaseKind.sweep:
        final c = size.center(Offset.zero);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = SweepGradient(
              center: Alignment.center,
              startAngle: config.angle * math.pi / 180,
              endAngle: config.angle * math.pi / 180 + math.pi * 2,
              colors: cs,
              stops: stops,
            ).createShader(Rect.fromCircle(
              center: c,
              radius: math.max(size.width, size.height),
            )),
        );
      case DiyBaseKind.solid:
        canvas.drawRect(rect, Paint()..color = first);
    }
  }

  // ---------- 柔光斑 ----------
  void _paintGlow(Canvas canvas, Size size, DiyLayer l) {
    final w = size.width;
    final h = size.height;
    // 呼吸：半径在 ±6% 间缓慢起伏
    final pulse = 1.0 + math.sin(t * 0.42 + l.x * 6.2) * 0.06;
    final radius = math.max(8.0, l.size * math.max(w, h) * pulse);
    final center = Offset(l.x * w, l.y * h);
    // density 控制边缘柔和度：越大中心越实、边缘越紧
    final soft = 0.35 + (1 - l.density) * 0.6;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            l.color.withValues(alpha: l.intensity),
            l.color2.withValues(alpha: l.intensity * soft),
            l.color2.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  // ---------- 网格 ----------
  void _paintGrid(Canvas canvas, Size size, DiyLayer l) {
    final step = l.size.clamp(6.0, 200.0);
    if (step < 6) return;
    final paint = Paint()
      ..color = l.color.withValues(alpha: l.intensity)
      ..strokeWidth = l.density.clamp(0.2, 4.0)
      ..style = PaintingStyle.stroke;
    final rect = Offset.zero & size;
    canvas.save();
    if (l.angle != 0) {
      // 绕中心旋转，画完再裁回原矩形（避免露白）
      canvas.clipRect(rect);
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(l.angle * math.pi / 180);
      canvas.translate(-size.width, -size.height);
      final span = size.width + size.height;
      for (var x = 0.0; x <= span * 2; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, span * 2), paint);
      }
      for (var y = 0.0; y <= span * 2; y += step) {
        canvas.drawLine(Offset(0, y), Offset(span * 2, y), paint);
      }
    } else {
      final offX = (l.x * step) % step;
      final offY = (l.y * step) % step;
      for (var x = -offX; x <= size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = -offY; y <= size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    }
    canvas.restore();
  }

  // ---------- 光带 ----------
  void _paintRibbon(Canvas canvas, Size size, DiyLayer l) {
    final w = size.width;
    final h = size.height;
    final bandH = math.max(6.0, l.size * h);
    final swayAmp = l.density * h * 0.06;
    final baseY = l.y * h + math.sin(t * 0.32 + l.x * 5) * swayAmp;
    final path = Path();
    const segs = 5;
    path.moveTo(-w * 0.1, baseY + bandH / 2);
    for (var i = 0; i <= segs; i++) {
      final px = -w * 0.1 + (w * 1.2) * (i / segs);
      final py = baseY + math.sin(t * 0.5 + i * 1.15 + l.x * 4) * swayAmp * 0.7;
      path.lineTo(px, py - bandH / 2);
    }
    for (var i = segs; i >= 0; i--) {
      final px = -w * 0.1 + (w * 1.2) * (i / segs);
      final py = baseY + bandH * 0.7 +
          math.sin(t * 0.5 + i * 1.15 + l.x * 4) * swayAmp * 0.7;
      path.lineTo(px, py);
    }
    path.close();
    final rect = Rect.fromLTWH(0, baseY - bandH, w, bandH * 2.4);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            l.color2.withValues(alpha: 0),
            l.color.withValues(alpha: l.intensity),
            l.color2.withValues(alpha: l.intensity * 0.5),
            l.color.withValues(alpha: 0),
          ],
          stops: const [0, 0.35, 0.6, 1],
        ).createShader(rect),
    );
  }

  // ---------- 噪点 ----------
  void _paintNoise(Canvas canvas, Size size, DiyLayer l) {
    // 固定种子：同一配置每次渲染位置一致，不会"闪"
    final rnd = math.Random(0x5EED ^ (l.size * 1000).round() ^ (l.color.value & 0xFFFF));
    final density = l.density.clamp(0.05, 1.0);
    final count = (size.width * size.height / 900 * density).round().clamp(60, 4200);
    final grain = l.size.clamp(0.5, 6.0);
    final p = Paint()..color = l.color.withValues(alpha: l.intensity);
    final p2 = Paint()..color = l.color2.withValues(alpha: l.intensity * 0.7);
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      // 交替两种颗粒色，形成细微颗粒感
      canvas.drawRect(
        Rect.fromLTWH(x, y, grain, grain),
        i.isEven ? p : p2,
      );
    }
  }

  // ---------- 条纹 ----------
  void _paintStripe(Canvas canvas, Size size, DiyLayer l) {
    final band = l.size.clamp(2.0, 200.0);
    final duty = l.density.clamp(0.05, 0.95);
    final paintA = Paint()..color = l.color.withValues(alpha: l.intensity);
    final paintB = Paint()..color = l.color2.withValues(alpha: l.intensity * 0.55);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(l.angle * math.pi / 180);
    final span = (size.width + size.height) * 1.2;
    var pos = -span / 2;
    var flip = false;
    while (pos < span) {
      final cur = pos > -span / 2 ? pos : -span / 2;
      canvas.drawRect(
        Rect.fromLTWH(cur, -span / 2, band * duty, span),
        flip ? paintB : paintA,
      );
      pos += band;
      flip = !flip;
    }
    canvas.restore();
  }

  // ---------- 光束 ----------
  void _paintBeam(Canvas canvas, Size size, DiyLayer l) {
    final w = size.width;
    final h = size.height;
    final origin = Offset(l.x * w, l.y * h);
    final angle = l.angle * math.pi / 180;
    final halfWidth = math.max(8.0, l.size * math.max(w, h) * 0.5);
    final length = math.max(w, h) * 2.2;
    final dx = math.cos(angle);
    final dy = math.sin(angle);
    // 呼吸：宽度与强度轻微起伏
    final pulse = 1.0 + math.sin(t * 0.38 + l.x * 3) * 0.10;
    final perp = Offset(-dy, dx);
    final path = Path()
      ..moveTo(origin.dx + perp.dx * halfWidth * 0.35,
          origin.dy + perp.dy * halfWidth * 0.35)
      ..lineTo(origin.dx - perp.dx * halfWidth * 0.35,
          origin.dy - perp.dy * halfWidth * 0.35)
      ..lineTo(origin.dx + dx * length - perp.dx * halfWidth * pulse,
          origin.dy + dy * length - perp.dy * halfWidth * pulse)
      ..lineTo(origin.dx + dx * length + perp.dx * halfWidth * pulse,
          origin.dy + dy * length + perp.dy * halfWidth * pulse)
      ..close();
    final end = Offset(origin.dx + dx * length, origin.dy + dy * length);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            l.color.withValues(alpha: l.intensity),
            l.color2.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromPoints(origin, end)),
    );
  }

  // ---------- 圆点 ----------
  void _paintDots(Canvas canvas, Size size, DiyLayer l) {
    final step = l.size.clamp(6.0, 200.0);
    final r = l.density.clamp(0.3, 12.0);
    final p = Paint()..color = l.color.withValues(alpha: l.intensity);
    final p2 = Paint()..color = l.color2.withValues(alpha: l.intensity * 0.8);
    final offX = (l.x * step) % step;
    final offY = (l.y * step) % step;
    var row = 0;
    for (var y = -offY; y <= size.height + step; y += step, row++) {
      // 交错行用次色，形成斜向点阵观感
      final paint = row.isEven ? p : p2;
      for (var x = -offX; x <= size.width + step; x += step) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  // ---------- 暗角 ----------
  void _paintVignette(Canvas canvas, Size size, DiyLayer l) {
    final rect = Offset.zero & size;
    // size 越大暗角越靠外：inner 表示纯透明区域占比
    final inner = (1 - l.size.clamp(0.05, 0.95)) * 0.5;
    final soft = l.density.clamp(0.05, 1.0);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.78,
          colors: [
            l.color.withValues(alpha: 0),
            l.color.withValues(alpha: l.intensity * soft * 0.5),
            l.color.withValues(alpha: l.intensity),
          ],
          stops: [0.0, (inner + (1 - inner) * (1 - soft)).clamp(0.01, 0.99), 1.0],
        ).createShader(rect),
    );
  }

  /// 仅在配置或明暗变化时重绘；动效由 _DiyBackdropViewState 的 setState 驱动
  /// （painter 实例每帧新建，故此处返回 false 不影响动画）。
  @override
  bool shouldRepaint(covariant _DiyBackdropPainter old) =>
      old.config != config || old.isLight != isLight || old.t != t;
}
