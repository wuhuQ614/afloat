/// 引导页氛围背景（按主题分三种形态）。
///
/// - 经典浅色：清新蓝极光流动光带（仿 deepseek.com/harness hero 顶部流光带）——
///   数条宽大、两端收窄、边缘柔和的光带缓慢漂移摆动，浅蓝白核心 + 天蓝外晕。
/// - 深色模式：深海霓虹极光——同构光带，但配色更饱和（青蓝/电光蓝）、
///   发光更强（plus 混合），在黑底上形成深邃的霓虹光幕。
/// - 毛玻璃主题（liquidGlass）：液态玻璃——高级晨光氛围（R26 起去掉底层的
///   彩色泡泡球与悬浮液滴，改为"只有光、没有物"的构成）：
///   整幅对角弥散的晨光渐变（中心缓漂）+ 两条超宽、边缘完全柔化的斜向光带
///   （缓慢漂移，只留明暗层次观感）+ 数十颗 1~2px 微光尘粒子（上浮游动），
///   动静结合呈现通透克制的高级感，配色与主界面 GlassBackground 天蓝同族一致。
///
/// 实现说明：
///  - 光带由 4 个归一化锚点定义，锚点按正弦缓慢摆动；Catmull-Rom 采样成
///    平滑曲线后，沿法线向两侧展开为多边形（宽度包络两端收窄、中部饱满），
///    再填充"沿带方向透明→主色→透明"的线性渐变 + MaskFilter 高斯模糊。
///    每条带画两层：外层宽而淡（光晕），内层窄而亮（白色核心），形成丝缎质感。
///  - 光尘粒子使用固定种子的伪随机序列（每帧重复），位置是时间的纯函数，
///    无需状态管理，纵向循环上浮 + 横向轻摆 + 透明度浮潜。
///  - Ticker 驱动（非 AnimationController），每帧只重绘画布（repaint listenable），
///    不重建 widget 子树；active=false 时停 Ticker，零开销。
///  - 全平台启用：每帧 2 次模糊光带 + 64 颗小粒子，开销可控。
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class AuroraBackdrop extends StatefulWidget {
  /// 深色模式：true 用深海霓虹光带（plus 混合发光）；false 按 liquidGlass 分流
  final bool dark;

  /// 毛玻璃主题（仅浅色下有意义）：true 画液态玻璃液滴，false 画清新蓝极光带
  final bool liquidGlass;

  /// 仅在 active 时驱动动画；false 暂停 Ticker，零开销
  final bool active;

  const AuroraBackdrop({
    super.key,
    required this.dark,
    this.liquidGlass = false,
    this.active = true,
  });

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

/// 一条光带的静态描述（位置用相对画布的归一化坐标，运行时再换算成像素）
class _Ribbon {
  /// 4 个锚点（相对画布宽/高），Catmull-Rom 插值成平滑曲线
  final List<Offset> anchors;

  /// 基础宽度（相对画布高度）
  final double width;

  /// 锚点摆动幅度（相对画布高度）
  final double sway;

  /// 摆动角速度 rad/s（越小越缓慢）
  final double speed;

  /// 初相，错开各带节奏
  final double phase;

  /// 取色索引（深/浅两套色板各自取模）
  final int colorIndex;

  /// 整体不透明度系数（用于压暗陪衬带）
  final double alpha;

  const _Ribbon({
    required this.anchors,
    required this.width,
    required this.sway,
    required this.speed,
    required this.phase,
    required this.colorIndex,
    this.alpha = 1.0,
  });
}

/// 光带布局：左上斜带 + 顶部下垂带（还原参考图两条主带）+ 底部淡陪衬带
const List<_Ribbon> _ribbons = [
  _Ribbon(
    anchors: [
      Offset(-0.08, 0.16),
      Offset(0.22, 0.02),
      Offset(0.52, 0.14),
      Offset(0.78, 0.00),
    ],
    width: 0.16,
    sway: 0.030,
    speed: 0.22,
    phase: 0.0,
    colorIndex: 0,
  ),
  _Ribbon(
    anchors: [
      Offset(0.34, -0.10),
      Offset(0.52, 0.08),
      Offset(0.68, 0.20),
      Offset(0.94, 0.26),
    ],
    width: 0.13,
    sway: 0.036,
    speed: 0.17,
    phase: 2.1,
    colorIndex: 1,
  ),
  _Ribbon(
    anchors: [
      Offset(-0.06, 0.78),
      Offset(0.26, 0.88),
      Offset(0.52, 0.96),
      Offset(0.72, 1.06),
    ],
    width: 0.11,
    sway: 0.024,
    speed: 0.13,
    phase: 4.4,
    colorIndex: 2,
    alpha: 0.55,
  ),
];

/// 一条宽幅柔光带的静态描述（位置用相对画布的归一化坐标，运行时再换算成像素）
class _Beam {
  /// 4 个锚点（相对画布宽/高），Catmull-Rom 插值成平滑曲线
  final List<Offset> anchors;

  /// 基础宽度（相对画布高度）
  final double width;

  /// 锚点摆动幅度（相对画布高度）
  final double sway;

  /// 摆动角速度 rad/s（越小越缓慢）
  final double speed;

  /// 初相，错开各带节奏
  final double phase;

  /// 取色索引（取模）
  final int colorIndex;

  /// 整体不透明度系数（压暗淡化陪衬带）
  final double alpha;

  const _Beam({
    required this.anchors,
    required this.width,
    required this.sway,
    required this.speed,
    required this.phase,
    required this.colorIndex,
    this.alpha = 1.0,
  });
}

/// 宽幅柔光带布局：左上→右下主光带 + 右上→左下陪衬光带（超宽、极淡，
/// 完全柔化后只剩明暗层次，看不出形状边界）
const List<_Beam> _beams = [
  _Beam(
    anchors: [
      Offset(-0.10, 0.12),
      Offset(0.24, 0.02),
      Offset(0.54, 0.12),
      Offset(0.88, -0.06),
    ],
    width: 0.36,
    sway: 0.022,
    speed: 0.10,
    phase: 0.0,
    colorIndex: 0,
  ),
  _Beam(
    anchors: [
      Offset(0.60, 1.10),
      Offset(0.78, 0.90),
      Offset(0.96, 0.72),
      Offset(1.12, 0.58),
    ],
    width: 0.26,
    sway: 0.018,
    speed: 0.085,
    phase: 2.4,
    colorIndex: 1,
    alpha: 0.8,
  ),
];

/// 动画模型：仅持有累计时间与形态标志，step 后通知画布重绘
class _AModel extends ChangeNotifier {
  bool dark;
  bool liquidGlass;
  double elapsed = 0;
  _AModel(this.dark, this.liquidGlass);

  void step(double dt) {
    elapsed += dt;
    notifyListeners();
  }
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final _AModel _m;
  late final Ticker _ticker;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    _m = _AModel(widget.dark, widget.liquidGlass);
    _ticker = createTicker(_onTick);
    if (widget.active) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant AuroraBackdrop old) {
    super.didUpdateWidget(old);
    if (widget.dark != old.dark || widget.liquidGlass != old.liquidGlass) {
      _m.dark = widget.dark;
      _m.liquidGlass = widget.liquidGlass;
      _m.step(0); // 立即按新形态/配色重绘一帧
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
    // RepaintBoundary：每帧重绘限制在本画布，不扩散到引导页内容树。
    // size: Size.infinite —— 即使处于宽松约束（如主题切换时 AnimatedSwitcher 内部）
    // 也能撑满父容器，否则 CustomPaint 无约束时默认 Size.zero 画不出来
    return RepaintBoundary(
      child: CustomPaint(size: Size.infinite, painter: _AuroraPainter(_m)),
    );
  }
}

/// 渲染层：按主题形态分流——液态玻璃液滴 / 极光光带（浅色清新蓝、深色深海霓虹）
class _AuroraPainter extends CustomPainter {
  final _AModel m;
  _AuroraPainter(this.m) : super(repaint: m);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (m.liquidGlass && !m.dark) {
      _paintLiquidGlass(canvas, size);
      return;
    }
    _paintAurora(canvas, size);
  }

  // ===== 液态玻璃（毛玻璃主题，浅底） =====
  /// 高级晨光氛围（R26：去掉底层彩色泡泡球与悬浮液滴，改为无形状的光）：
  ///  1. 晨光基底——整幅对角弥散渐变（冰蓝→淡青→暖白），中心缓慢漂移；
  ///  2. 宽幅斜向柔光带——超宽、边缘完全柔化，只留光线明暗层次，不构成形状；
  ///  3. 光尘粒子——64 颗 1~2px 微小亮点缓慢上浮、轻摆、透明度浮潜，
  ///     像尘埃在光束里，赋予"呼吸感"。
  void _paintLiquidGlass(Canvas canvas, Size size) {
    _paintDawn(canvas, size); // 1) 晨光基底
    _paintSunbeams(canvas, size); // 2) 宽幅斜向柔光带
    _paintDust(canvas, size); // 3) 光尘粒子
  }

  /// 晨光基底：大半径径向渐变自左上铺满全幅，中心按约 60s 周期缓慢漂移，
  /// 冰蓝 → 淡青 → 暖白，作为整幅背景的呼吸底色（无任何形状边界）
  void _paintDawn(Canvas c, Size size) {
    final w = size.width;
    final h = size.height;
    final t = m.elapsed;
    final cx = w * (0.32 + 0.045 * math.sin(t * 0.10));
    final cy = h * (0.22 + 0.035 * math.cos(t * 0.085));
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: w * 1.15);
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: const [
            Color(0xFFFDFEFF), // 核心暖白
            Color(0xFFE4F1FE), // 冰蓝
            Color(0xFFD4EBFA), // 淡青
            Color(0xFFE8F3FA), // 边缘冷调
          ],
          stops: const [0, 0.42, 0.75, 1],
        ).createShader(rect),
    );
  }

  /// 宽幅斜向柔光带：2 条超宽光束斜穿画面，锚点缓慢摆动；
  /// 高斯模糊 sigma 达带宽的 60%，视觉只剩明暗过渡（"光"而非"物件"）
  void _paintSunbeams(Canvas c, Size size) {
    final h = size.height;
    final t = m.elapsed;
    for (final b in _beams) {
      final pts = <Offset>[];
      for (var i = 0; i < b.anchors.length; i++) {
        final a = b.anchors[i];
        final dx = math.sin(t * b.speed + b.phase + i * 1.3) * b.sway * h;
        final dy = math.cos(t * b.speed * 0.8 + b.phase + i * 0.9) * b.sway * 0.6 * h;
        pts.add(Offset(a.dx * size.width + dx, a.dy * h + dy));
      }
      final samples = _spline(pts, 24);
      _paintRibbon(
        c,
        samples,
        b.width * h,
        widthScale: 1.0,
        colors: _beamColors(b.colorIndex, b.alpha),
        sigma: b.width * h * 0.6,
        blend: BlendMode.srcOver,
      );
    }
  }

  /// 光束色板：极淡乳白天蓝，只做明暗层次，不抢玻璃卡片内容
  List<Color> _beamColors(int i, double alpha) {
    const cols = [Color(0xFFA9D0F2), Color(0xFFB9E2F4)];
    final c = cols[i % cols.length];
    final a = 0.20 * alpha;
    return [c.withValues(alpha: 0), c.withValues(alpha: a), c.withValues(alpha: 0)];
  }

  /// 光尘粒子：固定种子伪随机序列（每帧重复同一序列），位置是时间的纯函数——
  /// 纵向循环上浮（约 30~60s 一屏）+ 横向轻摆 + 透明度浮潜，像尘埃在光束里
  void _paintDust(Canvas c, Size size) {
    final w = size.width;
    final h = size.height;
    final t = m.elapsed;
    final rng = math.Random(0x5EED);
    for (var i = 0; i < 64; i++) {
      final px = rng.nextDouble();
      final py0 = rng.nextDouble();
      final sp = 0.018 + rng.nextDouble() * 0.026; // 上浮速度（屏/h）
      final ph = rng.nextDouble() * 6.2832;
      final s = 0.6 + rng.nextDouble() * 1.5; // 1~2px
      final a = 0.10 + rng.nextDouble() * 0.18; // 基础透明度
      final y = (((py0 - t * sp) % 1.0) + 1.0) % 1.0 * h;
      final x = (px + 0.018 * math.sin(t * 0.45 + ph)) * w;
      final alpha = a * (0.55 + 0.45 * math.sin(t * 0.7 + ph * 1.7));
      final col = Color.lerp(Colors.white, const Color(0xFFCFE6F8), 0.45)!;
      c.drawCircle(Offset(x, y), s, Paint()..color = col.withValues(alpha: alpha.clamp(0.0, 1.0)));
    }
  }

  // ===== 极光光带（经典浅色 / 深色模式） =====
  void _paintAurora(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final isDark = m.dark;

    for (final r in _ribbons) {
      // 整带"呼吸"漂移：水平/垂直两个慢周期正弦（约 21s / 27s），
      // 幅度 ~2% 屏宽、~2.5% 屏高——肉眼可辨的缓慢上下左右浮动
      final driftX = math.sin(m.elapsed * 0.30 + r.phase * 1.7) * 0.020 * w;
      final driftY = math.cos(m.elapsed * 0.23 + r.phase) * 0.025 * h;
      // 锚点缓慢摆动（水平/垂直两个相位错开的正弦），营造"流动"感
      final pts = <Offset>[];
      for (var i = 0; i < r.anchors.length; i++) {
        final a = r.anchors[i];
        final dx = math.sin(m.elapsed * r.speed + r.phase + i * 1.3) * r.sway * h;
        final dy = math.cos(m.elapsed * r.speed * 0.8 + r.phase + i * 0.9) * r.sway * 0.6 * h;
        pts.add(Offset(a.dx * w + driftX + dx, a.dy * h + driftY + dy));
      }
      final samples = _spline(pts, 28);
      // 宽度呼吸：约 24s 周期 ±8% 胀缩，配合漂移形成"活"的光带
      final breathe = 1 + 0.08 * math.sin(m.elapsed * 0.26 + r.phase * 2.3);
      final baseW = r.width * h * breathe;

      // 外层：宽而淡的光晕
      _paintRibbon(
        canvas,
        samples,
        baseW,
        widthScale: 1.0,
        colors: _bandColors(r.colorIndex, isDark, r.alpha, core: false),
        sigma: baseW * 0.45,
        blend: isDark ? BlendMode.plus : BlendMode.srcOver,
      );
      // 内层：窄而亮的白色核心（丝缎高光）
      _paintRibbon(
        canvas,
        samples,
        baseW,
        widthScale: 0.42,
        colors: _bandColors(r.colorIndex, isDark, r.alpha, core: true),
        sigma: baseW * 0.22,
        blend: isDark ? BlendMode.plus : BlendMode.srcOver,
      );
    }
  }

  /// 沿采样点展开光带多边形并柔边填充：
  /// 宽度包络两端收窄、中部饱满；渐变沿带方向 透明→主色→透明
  void _paintRibbon(
    Canvas canvas,
    List<Offset> sp,
    double baseW, {
    required double widthScale,
    required List<Color> colors,
    required double sigma,
    required BlendMode blend,
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
          colors: colors,
          stops: const [0, 0.5, 1],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromPoints(sp.first, sp.last))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma)
        ..blendMode = blend,
    );
  }

  /// 光带色板：返回 [头透明, 中主色, 尾透明]。
  /// core=true 取偏白的高亮色；深色底为深海霓虹（饱和青蓝/电光蓝），
  /// 浅色底为低饱和清新天蓝。
  List<Color> _bandColors(int i, bool dark, double alpha, {required bool core}) {
    if (dark) {
      const halo = [Color(0xFF4FC3FF), Color(0xFF39D5E8), Color(0xFF7E9BFF)];
      const coreCols = [Color(0xFFDFF3FF), Color(0xFFCDF6FB), Color(0xFFDCE6FF)];
      final c = (core ? coreCols : halo)[i % 3];
      final a = (core ? 0.55 : 0.34) * alpha;
      return [c.withValues(alpha: 0), c.withValues(alpha: a), c.withValues(alpha: 0)];
    }
    const halo = [Color(0xFF7FC4F8), Color(0xFF9AD2FB), Color(0xFF6FBCF5)];
    const coreCols = [Color(0xFFDFF1FF), Color(0xFFEDF8FF), Color(0xFFD6ECFF)];
    final c = (core ? coreCols : halo)[i % 3];
    final a = (core ? 0.55 : 0.38) * alpha;
    return [c.withValues(alpha: 0), c.withValues(alpha: a), c.withValues(alpha: 0)];
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
  bool shouldRepaint(_AuroraPainter old) => true; // repaint listenable 已驱动
}
