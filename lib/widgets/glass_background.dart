/// 毛玻璃背景层 —— 彩色柔光基底（供 BackdropFilter 模糊折射）
library;

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import '../theme_colors.dart' show kPrimary;

/// 玻璃模糊滤镜：统一收口的玻璃高斯模糊（各面板共用同一 sigma 语义）。
/// 玻璃的"通透感"主要靠背景层的高饱和色斑提供（见 _GlassBasePainter），
/// 模糊只负责把色斑柔化成朦胧光晕。
ImageFilter glassBlurFilter({double sigma = 20}) {
  return ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
}

/// 玻璃染色：左上浓、右下淡的对角微渐变（替代平面纯色，产生玻璃厚度感）
LinearGradient glassTintGradient(Color base, double opacity) {
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [base.withValues(alpha: opacity), base.withValues(alpha: opacity * 0.78)],
  );
}

/// 彩色柔光基底背景：仅在 uiStyle == 'glass' 时显示。
/// 放在 widget 树最底层，上层的半透明容器通过 BackdropFilter 模糊这块背景。
/// 玻璃感的前提是"玻璃后面有内容"：均匀纯色无论怎么模糊都不产生变化，
/// 所以基底必须自带大尺度低饱和色斑，玻璃面板才能显出"透"与"折射"。
///
/// R10: 效仿引导页深色主题的呼吸极光（aurora_backdrop 的深色形态）——
/// 在基底渐变与静态色斑之上，叠加数条缓慢漂移、锚点摆动、宽度呼吸的柔光带，
/// 配色沿用毛玻璃主题现有色板（天蓝/薰衣草紫/樱粉）。
/// R11: 补齐引导页深色背景的完整设计语言——90px 网格线 + 交点小点
/// （移植 ParticleBackdrop 的网格设计）与右下角发光节点星座多边形，
/// 位置/大小可按玻璃主题调整，整体透明度随呼吸明暗。
/// Ticker 驱动、每帧仅重绘画布（repaint listenable），不重建 widget 子树；
/// 外层已有 RepaintBoundary，重绘不扩散到内容树。
///
/// [animated] = false 时为**静态帧**模式：不启动 Ticker，整幅画面在固定相位
/// （elapsed=1.5）一次性画好——渐变底、柔光斑、光带、网格全部保留，只是不再
/// 呼吸漂移；之后仅在尺寸变化 / 明暗主题切换时重绘。主界面用静态帧：
/// 蓝色渐隐背景保留，但不再每帧重绘（性能与动画版唯一的差别就是"不动"）。
class GlassBackground extends StatefulWidget {
  final bool isLight;
  final bool animated;
  const GlassBackground({super.key, required this.isLight, this.animated = true});

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

/// 动画模型：仅持有累计时间与明暗标志，step 后通知画布重绘
class _GlassAnim extends ChangeNotifier {
  bool isLight;
  double elapsed = 0;
  _GlassAnim(this.isLight);
  void step(double dt) {
    elapsed += dt;
    notifyListeners();
  }
}

class _GlassBackgroundState extends State<GlassBackground>
    with SingleTickerProviderStateMixin {
  /// 静态帧固定相位：让光带/网格停在一个观感自然的时刻（呼吸中值附近）
  static const double _staticElapsed = 1.5;

  late final _GlassAnim _m;
  late final Ticker _ticker;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _m = _GlassAnim(widget.isLight);
    if (!widget.animated) _m.elapsed = _staticElapsed;
    _ticker = createTicker(_onTick);
    if (widget.animated) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant GlassBackground old) {
    super.didUpdateWidget(old);
    if (widget.isLight != old.isLight) {
      _m.isLight = widget.isLight;
      _m.step(0); // 立即按新配色重绘一帧
    }
    // 动画 <-> 静态切换（引导页 -> 主界面）：停表定格当前相位，
    // 画面无缝静止，不跳变
    if (widget.animated != old.animated) {
      if (widget.animated) {
        _last = 0;
        _ticker.start();
      } else {
        _ticker.stop();
        _m.step(0); // 通知画布按当前相位定帧重绘
      }
    }
  }

  void _onTick(Duration time) {
    final t = time.inMicroseconds / 1e6;
    var dt = _last == 0 ? 0.016 : (t - _last);
    _last = t;
    if (dt <= 0) dt = 0.016;
    if (dt > 0.05) dt = 0.05; // 后台回来钳制，避免光带跳变
    _m.step(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.infinite, painter: _GlassBasePainter(_m));
  }
}

/// 一条呼吸光带的静态描述（锚点/宽度/摆动均为归一化坐标，运行时换算像素）
class _GRibbon {
  final List<Offset> anchors;
  final double width;
  final double sway;
  final double speed;
  final double phase;
  final int colorIndex;
  final double alpha;
  const _GRibbon({
    required this.anchors,
    required this.width,
    required this.sway,
    required this.speed,
    required this.phase,
    required this.colorIndex,
    this.alpha = 1.0,
  });
}

/// 光带布局：顶部两条主带（一左斜一右斜）+ 底部淡陪衬带（呼应引导页深色极光的构图）
const List<_GRibbon> _gRibbons = [
  _GRibbon(
    anchors: [
      Offset(-0.08, 0.18),
      Offset(0.24, 0.04),
      Offset(0.55, 0.16),
      Offset(0.82, 0.02),
    ],
    width: 0.15,
    sway: 0.030,
    speed: 0.20,
    phase: 0.0,
    colorIndex: 0,
  ),
  _GRibbon(
    anchors: [
      Offset(0.30, -0.08),
      Offset(0.52, 0.10),
      Offset(0.70, 0.22),
      Offset(0.96, 0.28),
    ],
    width: 0.12,
    sway: 0.034,
    speed: 0.16,
    phase: 2.1,
    colorIndex: 1,
  ),
  _GRibbon(
    anchors: [
      Offset(-0.06, 0.80),
      Offset(0.28, 0.90),
      Offset(0.55, 0.98),
      Offset(0.78, 1.06),
    ],
    width: 0.11,
    sway: 0.024,
    speed: 0.13,
    phase: 4.4,
    colorIndex: 2,
    alpha: 0.6,
  ),
];

/// 光带配色 = 毛玻璃主题蓝青同族色板（R21: 与柔光斑统一，去掉粉/紫撞色）
const List<Color> _gRibbonHalo = [Color(0xFF5EB2F7), Color(0xFF54B0EA), Color(0xFF45C3DE)];
const List<Color> _gRibbonCore = [Color(0xFFD8EDFF), Color(0xFFE2F2FF), Color(0xFFDFF5FA)];

class _GlassBasePainter extends CustomPainter {
  final _GlassAnim m;
  _GlassBasePainter(this.m) : super(repaint: m);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // 1) 基底对角渐变：浅色冷白蓝灰；深色深蓝黑
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: m.isLight
              ? const [Color(0xFFEDF2F9), Color(0xFFF1F4F9), Color(0xFFF6F8FB)]
              : const [Color(0xFF10121A), Color(0xFF0D0F15), Color(0xFF0D1015)],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );

    // 2) 大尺度柔光斑（R27: 左重右淡——从左缘向右快速衰减，约 2/3 处基本消失；
    //    整体透明度下调，避免背景过浓压过前景）
    const washes = [
      (Offset(0.06, 0.10), 0.55, Color(0xFF3E9BF0), 0.42), // 左上天蓝（最重）
      (Offset(0.08, 0.86), 0.52, Color(0xFF2FBFD8), 0.30), // 左下青
      (Offset(0.42, 0.52), 0.60, Color(0xFF9ED8F2), 0.12), // 中部淡蓝（过渡）
      (Offset(0.80, 0.16), 0.50, Color(0xFFCFE4F5), 0.08), // 右上极淡
      (Offset(0.88, 0.88), 0.48, Color(0xFFDCEEF5), 0.06), // 右下几乎不可见
    ];
    final darkScale = m.isLight ? 1.0 : 0.55;
    for (final (p, r0, col, a) in washes) {
      final center = Offset(p.dx * w, p.dy * h);
      final r = r0 * math.max(w, h);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [col.withValues(alpha: a * darkScale), col.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }

    // 3) 呼吸光带：整带慢漂移 + 锚点摆动 + 宽度呼吸（参数与引导页深色极光同源）
    for (final r in _gRibbons) {
      final driftX = math.sin(m.elapsed * 0.30 + r.phase * 1.7) * 0.020 * w;
      final driftY = math.cos(m.elapsed * 0.23 + r.phase) * 0.012 * h;
      final pts = <Offset>[];
      for (var i = 0; i < r.anchors.length; i++) {
        final a = r.anchors[i];
        // R32: 光带中心移向屏幕上下外缘——不再透过玻璃面板在边缘形成色带
        final dy0 = a.dy < 0.5 ? a.dy - 0.10 : a.dy + 0.10;
        final dx = math.sin(m.elapsed * r.speed + r.phase + i * 1.3) * r.sway * h;
        final dy = math.cos(m.elapsed * r.speed * 0.8 + r.phase + i * 0.9) * r.sway * 0.6 * h;
        pts.add(Offset(a.dx * w + driftX + dx, dy0 * h + driftY + dy));
      }
      final samples = _spline(pts, 24);
      // 宽度呼吸：约 24s 周期 ±8% 胀缩
      final breathe = 1 + 0.08 * math.sin(m.elapsed * 0.26 + r.phase * 2.3);
      final baseW = r.width * h * breathe;
      final halo = _gRibbonHalo[r.colorIndex % _gRibbonHalo.length];
      final core = _gRibbonCore[r.colorIndex % _gRibbonCore.length];
      // 外层：宽而淡的光晕；内层：窄而亮的柔光核心（R32: 再减淡，避免边缘色带）
      _paintRibbon(canvas, samples, baseW,
          widthScale: 1.0, color: halo, alpha: 0.15 * r.alpha * darkScale, sigma: baseW * 0.45);
      _paintRibbon(canvas, samples, baseW,
          widthScale: 0.42, color: core, alpha: 0.22 * r.alpha * darkScale, sigma: baseW * 0.22);
    }

    // 4) 网格线 + 交点小点（移植引导页 ParticleBackdrop 的网格设计）：
    //    90px 点阵、线段两端留 10px 缺口、交点 1.8px 方点；整体透明度缓慢呼吸。
    //    位置/密度归一化随窗口自适应，浅色下压得很淡，只给玻璃后加一层"结构感"。
    final gridLine = m.isLight ? const Color(0xFF5A7BA8) : const Color(0xFF5A80B2);
    final gridDot = m.isLight ? const Color(0xFF3C64A0) : const Color(0xFF86A9D6);
    final breathe = 0.75 + 0.25 * math.sin(m.elapsed * 0.4);
    final lineA = (m.isLight ? 0.085 : 0.30) * breathe;
    final dotA = (m.isLight ? 0.20 : 0.50) * breathe;
    const spacing = 90.0;
    final cols = (w / spacing).ceil() + 1;
    final rows = (h / spacing).ceil() + 1;
    final offX = (w - (cols - 1) * spacing) / 2;
    final offY = (h - (rows - 1) * spacing) / 2;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round;
    for (var r = 0; r < rows; r++) {
      final y = offY + r * spacing;
      for (var c = 0; c < cols - 1; c++) {
        final x0 = offX + c * spacing;
        linePaint.color = gridLine.withValues(alpha: lineA);
        canvas.drawLine(Offset(x0 + 10, y), Offset(x0 + spacing - 10, y), linePaint);
      }
    }
    for (var c = 0; c < cols; c++) {
      final x = offX + c * spacing;
      for (var r = 0; r < rows - 1; r++) {
        final y0 = offY + r * spacing;
        linePaint.color = gridLine.withValues(alpha: lineA);
        canvas.drawLine(Offset(x, y0 + 10), Offset(x, y0 + spacing - 10), linePaint);
      }
    }
    final dotPaint = Paint()..color = gridDot.withValues(alpha: dotA);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawRect(
          Rect.fromLTWH(offX + c * spacing - 0.9, offY + r * spacing - 0.9, 1.8, 1.8),
          dotPaint,
        );
      }
    }
    // 注：原先的第 5) 星座多边形（右下角五边形 + 发光节点）已取消——
    // 课程表页大块留白区域星座显得突兀，删除后背景更干净
  }

  /// 沿采样点展开光带多边形并柔边填充：宽度包络两端收窄、中部饱满
  void _paintRibbon(
    Canvas canvas,
    List<Offset> sp,
    double baseW, {
    required double widthScale,
    required Color color,
    required double alpha,
    required double sigma,
  }) {
    final n = sp.length;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < n; i++) {
      final t = i / (n - 1);
      final prev = sp[i == 0 ? 0 : i - 1];
      final next = sp[i == n - 1 ? n - 1 : i + 1];
      final dir = next - prev;
      final len = dir.distance;
      final nrm = len < 1e-6 ? const Offset(0, 1) : Offset(-dir.dy / len, dir.dx / len);
      // sin^0.7 包络：端部保留 15% 宽度（模糊后自然收成圆头），中部最宽
      final env = math.pow(math.sin(math.pi * t), 0.7).toDouble();
      final half = baseW * widthScale * (0.15 + 0.85 * env) / 2;
      left.add(sp[i] + nrm * half);
      right.add(sp[i] - nrm * half);
    }
    final path = Path()..addPolygon([...left, ...right.reversed], true);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromPoints(sp.first, sp.last))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
  }

  /// Catmull-Rom 采样：端点重复，4 锚点插值为 samples+1 个平滑点
  List<Offset> _spline(List<Offset> p, int samples) {
    final ext = [p.first, ...p, p.last];
    final out = <Offset>[];
    final seg = p.length - 1;
    for (var s = 0; s <= samples; s++) {
      final t = s / samples * seg;
      final i = t.floor().clamp(0, seg - 1);
      final u = t - i;
      out.add(_cr(ext[i], ext[i + 1], ext[i + 2], ext[i + 3], u));
    }
    return out;
  }

  Offset _cr(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    double f(double a, double b, double c, double d) =>
        0.5 *
        ((2 * b) +
            (-a + c) * t +
            (2 * a - 5 * b + 4 * c - d) * t * t +
            (-a + 3 * b - 3 * c + d) * t * t * t);
    return Offset(
      f(p0.dx, p1.dx, p2.dx, p3.dx),
      f(p0.dy, p1.dy, p2.dy, p3.dy),
    );
  }

  @override
  bool shouldRepaint(_GlassBasePainter old) => m.isLight != old.m.isLight;
  // 动画模式：repaint listenable（_GlassAnim）每帧驱动重绘，不走这里；
  // 静态模式：仅明暗切换时重绘，父级重建不再连带整幅背景重绘
}

/// 毛玻璃容器包装器：BackdropFilter（模糊+提饱和）+ 渐变染色 + 受光层 + 顶部高光
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? color;
  final double opacity;
  final Border? border;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 20,
    this.color,
    this.opacity = 0.65,
    this.border,
    this.borderRadius,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final base = color ?? Colors.white;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: glassBlurFilter(sigma: blur),
        child: Stack(children: [
          Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: glassTintGradient(base, opacity),
              borderRadius: radius,
              // 未指定边框时用默认玻璃描边：半透明白，模拟玻璃切面反光
              border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
            ),
            child: child,
          ),
          // 受光层：顶部微亮、底部微暗，让平面产生"厚度"
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.16),
                      Colors.white.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.04),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
          ),
          // 顶部高光线：玻璃上沿的反光
          Positioned(
            top: 0,
            left: 1,
            right: 1,
            child: IgnorePointer(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.8),
                    Colors.white.withValues(alpha: 0),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// =================================================================
// 毛玻璃按钮组件（仅在 uiStyle == 'glass' 时使用，自动回退到原主题样式）
// =================================================================

/// 毛玻璃主按钮（替代 FilledButton）
class GlassFilledButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final double opacity;
  final bool fullWidth;

  const GlassFilledButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding,
    this.blur = 16,
    this.opacity = 0.55,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final radius = BorderRadius.circular(12);
    final btn = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: disabled
              ? kPrimary.withValues(alpha: 0.35)
              : kPrimary.withValues(alpha: opacity),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: Colors.white.withValues(alpha: disabled ? 0.1 : 0.35),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Container(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              alignment: Alignment.center,
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// 毛玻璃次按钮（替代 OutlinedButton）
class GlassOutlinedButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color? color;
  final bool fullWidth;

  const GlassOutlinedButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding,
    this.blur = 14,
    this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? kPrimary;
    final radius = BorderRadius.circular(12);
    final btn = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: tint.withValues(alpha: 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: tint.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: Container(
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              alignment: Alignment.center,
              child: DefaultTextStyle(
                style: TextStyle(
                  color: tint,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    return fullWidth ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

/// 毛玻璃图标按钮（替代 IconButton）
class GlassIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final double size;
  final double blur;
  final Color? color;
  final double opacity;

  const GlassIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.size = 36,
    this.blur = 14,
    this.color,
    this.opacity = 0.45,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Colors.white;
    final radius = BorderRadius.circular(size / 2);
    Widget btn = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: tint.withValues(alpha: opacity),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: radius,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// 毛玻璃发送按钮（圆形 + 渐变）
class GlassSendButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool sending;
  final double size;
  final double blur;

  const GlassSendButton({
    super.key,
    required this.onPressed,
    this.sending = false,
    this.size = 36,
    this.blur = 16,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(side: BorderSide(color: Colors.white24, width: 1)),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: sending
                    ? SizedBox(
                        width: size * 0.5,
                        height: size * 0.5,
                        child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.send_rounded, size: size * 0.5, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃悬浮按钮（替代 FloatingActionButton）
///
/// 设计要点：
/// - 底色是真正的毛玻璃：BackdropFilter 模糊下层 + 半透明白/深填充
///   （**不**用实色紫渐变挡住模糊效果）
/// - 品牌紫色只作为强调色：图标 + 微妙的紫色外光晕
class GlassFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final double blur;
  final bool isLight;

  const GlassFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.blur = 18,
    this.isLight = true,
  });

  @override
  Widget build(BuildContext context) {
    // 半透明白（亮色）/ 透明深灰（深色），让背后模糊层透出形成真正的毛玻璃
    final base = isLight
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.white.withValues(alpha: 0.10);
    final borderColor = isLight
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.white.withValues(alpha: 0.18);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: borderColor, width: 1.2),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: base,
                boxShadow: [
                  // 中性投影 + 紫色微光（弱化为主角，不抢毛玻璃的戏）
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: isLight ? 0.18 : 0.32),
                    blurRadius: 18,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }
}

/// 高级毛玻璃选中项（苹果风格）：
/// 真实模糊 + 多层渐变玻璃厚度 + 呼吸光晕 + 顶部扫光高光 + 内反射
class GlassSelectedTile extends StatefulWidget {
  final Widget child;
  final BorderRadius radius;
  final double blur;
  final bool active;

  const GlassSelectedTile({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(14)),
    this.blur = 28,
    this.active = true,
  });

  @override
  State<GlassSelectedTile> createState() => _GlassSelectedTileState();
}

class _GlassSelectedTileState extends State<GlassSelectedTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath; // 外发光呼吸

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    // 未选中态不挂 vsync 回调，避免呼吸动画在后台每帧空转
    if (widget.active) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant GlassSelectedTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _breath.repeat(reverse: true);
      } else {
        _breath.stop();
      }
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.radius;
    if (!widget.active) {
      // 未选中：完全透明占位，保持布局稳定
      return ClipRRect(
        borderRadius: radius,
        child: widget.child,
      );
    }

    return AnimatedBuilder(
      animation: _breath,
      builder: (context, _) {
        final t = _breath.value; // 0..1 呼吸
        final glow = 0.35 + 0.35 * t; // 0.35..0.7
        final shadowAlpha = 0.35 + 0.3 * t;

        return Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            // 多层外发光（紫色光晕 + 蓝色副光晕）
            boxShadow: [
              BoxShadow(
                color: kPrimary.withValues(alpha: glow),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 0),
              ),
              BoxShadow(
                color: const Color(0xFF8B5CF6).withValues(alpha: shadowAlpha * 0.6),
                blurRadius: 36,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: const Color(0xFF60A5FA).withValues(alpha: shadowAlpha * 0.35),
                blurRadius: 48,
                spreadRadius: 4,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                // 层1：真实模糊（透出底层动态光斑）
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
                    child: const SizedBox.expand(),
                  ),
                ),
                // 层2：彩色高饱和玻璃底（紫色 + 蓝色混色）
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFB794F6), // 浅紫（高光区）
                          Color(0xFF8B5CF6), // 主紫
                          Color(0xFF6D28D9), // 深紫
                          Color(0xFF4F46E5), // 靛蓝（暗部）
                        ],
                        stops: [0.0, 0.35, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
                // 层3：内部左下到右上反向渐变（增加玻璃厚度感）
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.18),
                          Colors.white.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: 0.18),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                ),
                // 层4：内高亮边框（玻璃边光）
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                // 层5：内描边（细一圈，营造"夹层玻璃"边缘）
                Positioned.fill(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius.subtract(const BorderRadius.all(Radius.circular(2))),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 层6：顶部高亮（细线 + 渐变厚度）
                Positioned(
                  top: 0,
                  left: 8,
                  right: 8,
                  child: IgnorePointer(
                    child: Container(
                      height: 1.2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.95),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.6),
                            blurRadius: 4,
                            offset: const Offset(0, 0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 层7：顶部高光区域（高 14px 的柔光带，模拟反射）
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(14),
                          topRight: Radius.circular(14),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.32),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 层8：左边缘高光（垂直细光带）
                Positioned(
                  top: 6,
                  bottom: 6,
                  left: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.6),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 内容（必须是非定位子元素，决定 Stack 尺寸）
                widget.child,
              ],
            ),
          ),
        );
      },
    );
  }
}
