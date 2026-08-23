/// 引导页氛围背景（按主题分三种形态）。
///
/// - 经典浅色：清新蓝极光流动光带（仿 deepseek.com/harness hero 顶部流光带）——
///   数条宽大、两端收窄、边缘柔和的光带缓慢漂移摆动，浅蓝白核心 + 天蓝外晕。
/// - 深色模式：深海霓虹极光——同构光带，但配色更饱和（青蓝/电光蓝）、
///   发光更强（plus 混合），在黑底上形成深邃的霓虹光幕。
/// - 毛玻璃主题（liquidGlass）：液态玻璃——底层多彩柔光斑上悬浮数颗缓慢游走、
///   边缘持续形变的半透明液滴，透过液滴可见轻微放大错位的底图（折射），
///   配合白色厚度渐变与明亮边缘描边，呈现厚玻璃质感。
///
/// 实现说明：
///  - 光带由 4 个归一化锚点定义，锚点按正弦缓慢摆动；Catmull-Rom 采样成
///    平滑曲线后，沿法线向两侧展开为多边形（宽度包络两端收窄、中部饱满），
///    再填充"沿带方向透明→主色→透明"的线性渐变 + MaskFilter 高斯模糊。
///    每条带画两层：外层宽而淡（光晕），内层窄而亮（白色核心），形成丝缎质感。
///  - 液滴轮廓为半径受 2 组正弦谐波调制的闭合曲线（液态形变）；底层光斑先录制
///    成 Picture，液滴 clip 内重放（放大 + 偏移）制造折射错位。
///  - Ticker 驱动（非 AnimationController），每帧只重绘画布（repaint listenable），
///    不重建 widget 子树；active=false 时停 Ticker，零开销。
///  - 全平台启用：每帧十余次模糊填充/描边，开销可控。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;
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

/// 一颗液态玻璃液滴的静态描述（位置/漂移幅度均为归一化坐标）
class _GBlob {
  /// 中心（相对画布宽/高）
  final Offset c;

  /// 基础半径（相对画布高度）
  final double r;

  /// 漂移幅度（相对画布宽/高）
  final double dx, dy;

  /// 漂移角速度 rad/s
  final double speed;

  /// 初相
  final double phase;

  /// 取色索引
  final int colorIndex;

  const _GBlob(this.c, this.r, this.dx, this.dy, this.speed, this.phase, this.colorIndex);
}

/// 液态玻璃液滴布局：四角错落分布，大小/速度/相位各异
const List<_GBlob> _gblobs = [
  _GBlob(Offset(0.20, 0.28), 0.21, 0.045, 0.040, 0.20, 0.0, 0),
  _GBlob(Offset(0.76, 0.20), 0.16, 0.040, 0.050, 0.16, 1.9, 1),
  _GBlob(Offset(0.62, 0.76), 0.23, 0.050, 0.035, 0.13, 3.6, 2),
  _GBlob(Offset(0.14, 0.82), 0.13, 0.035, 0.045, 0.18, 5.1, 0),
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
    // RepaintBoundary：每帧重绘限制在本画布，不扩散到引导页内容树
    return RepaintBoundary(
      child: CustomPaint(painter: _AuroraPainter(_m)),
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
  /// 玻璃感的三个必要条件：
  ///  1. 底下有彩色内容（多彩柔光斑）——没有参照物就显不出"透明"；
  ///  2. 透过液滴看到轻微放大 + 错位的底图（折射扭曲）；
  ///  3. 液滴内部白色厚度渐变 + 明亮边缘描边 + 高光点（玻璃轮廓语言）。
  void _paintLiquidGlass(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final t = m.elapsed;

    // 1) 底层多彩光斑先录成 Picture：直接铺底，同时供每个液滴 clip 内重放做折射
    final recorder = ui.PictureRecorder();
    final layer = Canvas(recorder);
    _paintLightSpots(layer, size, t);
    final pic = recorder.endRecording();
    canvas.drawPicture(pic);

    for (final b in _gblobs) {
      // 中心缓慢游走（双轴错频利萨茹轨迹）+ 整体胀缩
      final cx = (b.c.dx + b.dx * math.sin(t * b.speed + b.phase)) * w;
      final cy = (b.c.dy + b.dy * math.cos(t * b.speed * 0.83 + b.phase * 1.4)) * h;
      final radius = b.r * h * (1 + 0.06 * math.sin(t * 0.22 + b.phase * 2));
      final center = Offset(cx, cy);
      final path = _blobPath(cx, cy, radius, t, b.phase);
      final gradRect = Rect.fromCircle(center: center, radius: radius * 1.35);

      // 2) 折射层：clip 进液滴后重放底层图案（放大 1.08 + 向右下偏移），
      //    液滴内部的图案与外部错位 → 一眼可辨的玻璃折射；再叠白色柔光模拟玻璃厚度
      canvas.save();
      canvas.clipPath(path);
      canvas.transform(
        (Matrix4.identity()
              ..translate(radius * 0.22, radius * 0.18)
              ..scale(1.08))
            .storage,
      );
      canvas.drawPicture(pic);
      canvas.drawRect(
        gradRect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFFDFF2FF).withValues(alpha: 0.50),
              const Color(0x00FFFFFF),
            ],
            stops: const [0, 1],
          ).createShader(gradRect),
      );
      canvas.restore();

      // 3) 玻璃轮廓：外缘白色亮描边（微模糊）+ 内侧淡蓝细边，勾勒出厚玻璃的折线
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = Colors.white.withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = const Color(0xFF9CCBF2).withValues(alpha: 0.35),
      );
      // 高光点：左上方强白柔光（玻璃反光的点睛笔）
      final hl = center + Offset(-radius * 0.34, -radius * 0.40);
      canvas.drawCircle(
        hl,
        radius * 0.32,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.85),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: hl, radius: radius * 0.32))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.06),
      );
    }
  }

  /// 底层多彩柔光斑：蓝/紫/青/粉四色，缓慢漂移，充当玻璃折射的参照物
  void _paintLightSpots(Canvas c, Size size, double t) {
    final w = size.width;
    final h = size.height;
    const spots = [
      (Offset(0.24, 0.30), 0.30, Color(0xFF7CC4F8), 0.14, 0.0),
      (Offset(0.78, 0.24), 0.26, Color(0xFF9D7FF0), 0.11, 1.7),
      (Offset(0.64, 0.78), 0.28, Color(0xFF6FD8E8), 0.10, 3.2),
      (Offset(0.18, 0.80), 0.22, Color(0xFFF2A8C8), 0.12, 4.6),
    ];
    for (final (c0, r0, col, spd, ph) in spots) {
      final cx = (c0.dx + 0.03 * math.sin(t * spd + ph)) * w;
      final cy = (c0.dy + 0.03 * math.cos(t * spd * 0.8 + ph * 1.3)) * h;
      final r = r0 * h;
      c.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              col.withValues(alpha: 0.32),
              col.withValues(alpha: 0.12),
              const Color(0x00000000),
            ],
            stops: const [0, 0.6, 1],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.25),
      );
    }
  }

  /// 液态形变轮廓：半径受 2 组正弦谐波调制的闭合曲线
  Path _blobPath(double cx, double cy, double radius, double t, double phase) {
    final path = Path();
    const n = 48;
    for (var k = 0; k <= n; k++) {
      final th = 2 * math.pi * k / n;
      final rr = radius *
          (1 +
              0.09 * math.sin(3 * th + t * 0.45 + phase) +
              0.05 * math.sin(5 * th - t * 0.30 + phase * 2));
      final p = Offset(cx + rr * math.cos(th), cy + rr * math.sin(th));
      if (k == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
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
