/// 毛玻璃背景层 —— 动态渐变光斑（供 BackdropFilter 模糊）
library;

import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../theme_colors.dart' show kPrimary;

/// 动态渐变光斑背景：仅在 uiStyle == 'glass' 时显示
/// 放在 widget 树最底层，上层的半透明容器通过 BackdropFilter 模糊这块背景
class GlassBackground extends StatefulWidget {
  final bool isLight;
  const GlassBackground({super.key, required this.isLight});

  @override
  State<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends State<GlassBackground>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.isLight;
    // 纯色基底：浅色淡灰白 / 深色深灰，去掉动态光斑
    final baseColor = isLight ? const Color(0xFFE8E9F0) : const Color(0xFF0E0E12);
    return DecoratedBox(
      decoration: BoxDecoration(color: baseColor),
      child: const SizedBox.expand(),
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t;
  final Color baseColor;
  final List<(Color, double)> blobs;

  _BlobPainter(this.t, this.baseColor, this.blobs);

  @override
  void paint(Canvas canvas, Size size) {
    // 填充底色
    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);

    final w = size.width;
    final h = size.height;

    for (var i = 0; i < blobs.length; i++) {
      final (color, alpha) = blobs[i];
      // 每个光斑的轨道参数
      final angle = t * 0.5 + i * (pi / 2.5);
      final cx = w * (0.25 + 0.18 * cos(angle + i * 1.3));
      final cy = h * (0.3 + 0.2 * sin(angle * 0.8 + i * 0.7));
      final radius = min(w, h) * (0.45 + 0.1 * sin(t * 0.5 + i));

      final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius);
      final shader = RadialGradient(
        colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        stops: const [0, 1],
      ).createShader(rect);
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()..shader = shader,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) =>
      oldDelegate.t != t;
}

/// 毛玻璃容器包装器：BackdropFilter + 半透明叠加
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
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (color ?? Colors.white).withValues(alpha: opacity),
            borderRadius: radius,
            border: border,
          ),
          child: child,
        ),
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
class GlassFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String? tooltip;
  final double blur;

  const GlassFab({
    super.key,
    required this.onPressed,
    required this.icon,
    this.tooltip,
    this.blur = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.35), width: 1.2),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(28),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
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
    )..repeat(reverse: true);
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
