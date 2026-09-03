/// 页面 DIY：主题外观的自定义配置（背景 / 按钮）。
///
/// 设计要点：
/// 1. 三种内置主题（经典 classic / 毛玻璃 glass / 深色 dark）各自持有一份配置，
///    **互不覆盖**；未配置的主题走内置默认，行为与改造前完全一致。
/// 2. 背景采用「基座 + 图层栈」模型：基座决定底色或渐变，图层栈可叠加多种效果
///    （柔光斑 / 网格 / 光带 / 噪点 / 条纹 / 光束 / 圆点 / 暗角），支持混搭、
///    调色、调角度与强度，图层可排序、显隐、增删。
/// 3. 所有数值字段都带范围钳制，JSON 反序列化对脏数据（越界、缺字段、非法颜色）
///    一律回退到安全值，保证老版本/损坏配置不会让界面崩溃。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

// ============================================================================
// 一、图层
// ============================================================================

/// 背景图层种类。每个种类对 [DiyLayer] 的通用字段有各自解释（见下表）：
///
/// | 种类       | x / y            | size        | angle      | intensity   | density      | color2     |
/// |-----------|------------------|-------------|------------|-------------|--------------|------------|
/// | glow 柔光斑 | 圆心（0-1）       | 半径(占比)   | —          | 不透明度     | 边缘柔和度     | 渐变外圈色  |
/// | grid 网格   | 偏移（0-1）       | 格间距(px)   | 倾斜角      | 线不透明度    | 线宽(px)     | 次要线色    |
/// | ribbon 光带 | 起始锚点(0-1)     | 带宽(占比)   | 走向角      | 不透明度     | 摆动幅度      | 高光色      |
/// | noise 噪点  | —                | 颗粒(px)    | —          | 不透明度     | 密度(0-1)    | 次要颗粒色  |
/// | stripe 条纹 | —                | 条宽(px)    | 倾斜角      | 不透明度     | 占空比(0-1)  | 交替色      |
/// | beam 光束   | 起点(0-1)        | 束宽(占比)   | 方向角      | 不透明度     | 边缘衰减      | 末端色      |
/// | dots 圆点   | 偏移(0-1)        | 点间距(px)   | —          | 不透明度     | 点半径(px)   | 交错点色    |
/// | vignette 暗角 | —              | 内缩(占比)   | —          | 最深不透明度  | 过渡柔和度    | —          |
enum DiyLayerKind {
  glow,
  grid,
  ribbon,
  noise,
  stripe,
  beam,
  dots,
  vignette;

  String get key => name;

  /// 中文名（UI 与 Agent 提示共用）
  String get label => switch (this) {
        DiyLayerKind.glow => '柔光斑',
        DiyLayerKind.grid => '网格',
        DiyLayerKind.ribbon => '光带',
        DiyLayerKind.noise => '噪点',
        DiyLayerKind.stripe => '条纹',
        DiyLayerKind.beam => '光束',
        DiyLayerKind.dots => '圆点',
        DiyLayerKind.vignette => '暗角',
      };

  static DiyLayerKind? fromKey(String? k) {
    if (k == null) return null;
    for (final v in DiyLayerKind.values) {
      if (v.key == k.toLowerCase()) return v;
    }
    return null;
  }
}

/// 图层数量上限：防止无限叠加拖慢渲染（大厂设计里的"克制"约束）
const int kDiyMaxLayers = 6;

/// 一个背景图层。所有 kind 共用同一组数值字段，按上表解释。
class DiyLayer {
  final DiyLayerKind kind;
  final bool enabled;
  /// 主色
  final Color color;
  /// 次色（渐变外圈 / 交替条纹 / 高光等，按 kind 解释）
  final Color color2;
  /// 归一化横坐标 0-1
  final double x;
  /// 归一化纵坐标 0-1
  final double y;
  /// 尺寸：半径 / 间距 / 带宽等（按 kind 解释）
  final double size;
  /// 角度（度，0-360）
  final double angle;
  /// 强度：不透明度 0-1
  final double intensity;
  /// 密度 / 线宽 / 衰减等（按 kind 解释）
  final double density;

  const DiyLayer({
    required this.kind,
    this.enabled = true,
    this.color = const Color(0xFF7C3AED),
    this.color2 = const Color(0xFFA78BFA),
    this.x = 0.5,
    this.y = 0.5,
    this.size = 0.4,
    this.angle = 0,
    this.intensity = 0.3,
    this.density = 0.5,
  });

  /// 钳制到合法区间（所有来源——UI 拖动、Agent 参数、JSON——都过这一层）
  factory DiyLayer.clamped({
    required DiyLayerKind kind,
    bool enabled = true,
    Color? color,
    Color? color2,
    double x = 0.5,
    double y = 0.5,
    double size = 0.4,
    double angle = 0,
    double intensity = 0.3,
    double density = 0.5,
  }) {
    return DiyLayer(
      kind: kind,
      enabled: enabled,
      color: color ?? const Color(0xFF7C3AED),
      color2: color2 ?? const Color(0xFFA78BFA),
      // x/y 允许略出屏幕（-0.5~1.5）：光束/柔光斑等图层常把锚点放在屏幕
      // 边缘外以获得"从画外照进来"的观感，0-1 的严格钳制会把这类预设拉回画面
      x: x.clamp(-0.5, 1.5),
      y: y.clamp(-0.5, 1.5),
      // size 依 kind 语义不同量级差异很大（网格 8-80px，柔光斑 0.1-1.2 占比），
      // 这里只做宽松上界，具体 kind 的下限在构造预设时保证
      size: size.clamp(0.0, 400.0),
      angle: angle.clamp(0.0, 360.0),
      intensity: intensity.clamp(0.0, 1.0),
      // density 上限放宽到 12：圆点图层的 density 语义是点半径（px，0.3-12），
      // 其余图层语义为 0-1 的比例值，UI 滑块各自限定了范围，此处只兜底防脏数据
      density: density.clamp(0.0, 12.0),
    );
  }

  DiyLayer copyWith({
    DiyLayerKind? kind,
    bool? enabled,
    Color? color,
    Color? color2,
    double? x,
    double? y,
    double? size,
    double? angle,
    double? intensity,
    double? density,
  }) {
    return DiyLayer.clamped(
      kind: kind ?? this.kind,
      enabled: enabled ?? this.enabled,
      color: color ?? this.color,
      color2: color2 ?? this.color2,
      x: x ?? this.x,
      y: y ?? this.y,
      size: size ?? this.size,
      angle: angle ?? this.angle,
      intensity: intensity ?? this.intensity,
      density: density ?? this.density,
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.key,
        'enabled': enabled,
        'color': color.toARGB32(),
        'color2': color2.toARGB32(),
        'x': _r3(x),
        'y': _r3(y),
        'size': _r3(size),
        'angle': _r3(angle),
        'intensity': _r3(intensity),
        'density': _r3(density),
      };

  /// 容错反序列化：任何字段缺失/类型错误都退回该 kind 的默认图层
  factory DiyLayer.fromJson(Map<String, dynamic> j) {
    final kind = DiyLayerKind.fromKey(j['kind'] as String?) ?? DiyLayerKind.glow;
    final def = DiyLayer.defaultOf(kind);
    return DiyLayer.clamped(
      kind: kind,
      enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
      color: _parseColor(j['color'], def.color),
      color2: _parseColor(j['color2'], def.color2),
      x: _parseDouble(j['x'], def.x),
      y: _parseDouble(j['y'], def.y),
      size: _parseDouble(j['size'], def.size),
      angle: _parseDouble(j['angle'], def.angle),
      intensity: _parseDouble(j['intensity'], def.intensity),
      density: _parseDouble(j['density'], def.density),
    );
  }

  /// 各图层种类的默认参数（新建图层 / 反序列化兜底都用它）
  factory DiyLayer.defaultOf(DiyLayerKind kind) {
    switch (kind) {
      case DiyLayerKind.glow:
        return const DiyLayer(
          kind: DiyLayerKind.glow,
          color: Color(0xFF7C3AED),
          color2: Color(0xFFA78BFA),
          x: 0.18,
          y: 0.16,
          size: 0.55,
          intensity: 0.34,
          density: 0.7,
        );
      case DiyLayerKind.grid:
        return const DiyLayer(
          kind: DiyLayerKind.grid,
          color: Color(0xFF94A3B8),
          color2: Color(0xFFCBD5E1),
          size: 32,
          angle: 0,
          intensity: 0.16,
          density: 1,
        );
      case DiyLayerKind.ribbon:
        return const DiyLayer(
          kind: DiyLayerKind.ribbon,
          color: Color(0xFF5EB2F7),
          color2: Color(0xFFD8EDFF),
          x: 0.1,
          y: 0.22,
          size: 0.16,
          angle: -8,
          intensity: 0.5,
          density: 0.45,
        );
      case DiyLayerKind.noise:
        return const DiyLayer(
          kind: DiyLayerKind.noise,
          color: Color(0xFF0F172A),
          color2: Color(0xFFFFFFFF),
          size: 2.2,
          intensity: 0.06,
          density: 0.5,
        );
      case DiyLayerKind.stripe:
        return const DiyLayer(
          kind: DiyLayerKind.stripe,
          color: Color(0xFF7C3AED),
          color2: Color(0xFFF1F5F9),
          size: 26,
          angle: 45,
          intensity: 0.14,
          density: 0.5,
        );
      case DiyLayerKind.beam:
        return const DiyLayer(
          kind: DiyLayerKind.beam,
          color: Color(0xFFFBBF24),
          color2: Color(0xFFFFFFFF),
          x: 0.2,
          y: -0.1,
          size: 0.3,
          angle: 28,
          intensity: 0.3,
          density: 0.6,
        );
      case DiyLayerKind.dots:
        return const DiyLayer(
          kind: DiyLayerKind.dots,
          color: Color(0xFF64748B),
          color2: Color(0xFF94A3B8),
          size: 26,
          intensity: 0.22,
          density: 1.8,
        );
      case DiyLayerKind.vignette:
        return const DiyLayer(
          kind: DiyLayerKind.vignette,
          color: Color(0xFF000000),
          size: 0.55,
          intensity: 0.22,
          density: 0.6,
        );
    }
  }
}

// ============================================================================
// 二、基座（底色 / 渐变）
// ============================================================================

/// 基座填充方式
enum DiyBaseKind { solid, linear, radial, sweep }

extension DiyBaseKindX on DiyBaseKind {
  String get key => name;
  String get label => switch (this) {
        DiyBaseKind.solid => '纯色',
        DiyBaseKind.linear => '线性渐变',
        DiyBaseKind.radial => '径向渐变',
        DiyBaseKind.sweep => '锥形渐变',
      };
  static DiyBaseKind fromKey(String? k) {
    if (k == null) return DiyBaseKind.solid;
    for (final v in DiyBaseKind.values) {
      if (v.key == k.toLowerCase()) return v;
    }
    return DiyBaseKind.solid;
  }
}

/// 背景配置
class DiyBackdrop {
  final DiyBaseKind base;
  /// 渐变色序列（1-4 个；纯色时只用第一个）
  final List<Color> colors;
  /// 色标位置（与 colors 等长，0-1 递增）；为空时自动均分
  final List<double> stops;
  /// 渐变角度（度，线性/锥形生效）
  final double angle;
  /// 图层栈（按数组顺序自下而上叠加）
  final List<DiyLayer> layers;
  /// 是否开启动效（光带漂移 / 光束呼吸）；关闭后为静态帧，省电
  final bool animated;
  /// 毛玻璃主题的模糊强度（sigma）。仅毛玻璃主题有意义，其余主题渲染时忽略
  final double blur;
  /// 内容区蒙层不透明度：背景太花时压一层底色保证文字可读（0=不加）
  final double scrim;

  const DiyBackdrop({
    this.base = DiyBaseKind.linear,
    this.colors = const [Color(0xFFEDF2F9), Color(0xFFF6F8FB)],
    this.stops = const [],
    this.angle = 135,
    this.layers = const [],
    this.animated = true,
    this.blur = 24,
    this.scrim = 0,
  });

  factory DiyBackdrop.clamped({
    DiyBaseKind base = DiyBaseKind.linear,
    List<Color>? colors,
    List<double>? stops,
    double angle = 135,
    List<DiyLayer>? layers,
    bool animated = true,
    double blur = 24,
    double scrim = 0,
  }) {
    var cs = (colors == null || colors.isEmpty)
        ? const <Color>[Color(0xFFEDF2F9), Color(0xFFF6F8FB)]
        : colors.take(4).toList();
    if (cs.isEmpty) cs = const <Color>[Color(0xFFEDF2F9)];
    return DiyBackdrop(
      base: base,
      colors: cs,
      stops: _normalizeStops(stops, cs.length),
      angle: angle.clamp(0.0, 360.0),
      layers: (layers ?? const <DiyLayer>[]).take(kDiyMaxLayers).toList(),
      animated: animated,
      blur: blur.clamp(0.0, 60.0),
      scrim: scrim.clamp(0.0, 0.85),
    );
  }

  DiyBackdrop copyWith({
    DiyBaseKind? base,
    List<Color>? colors,
    List<double>? stops,
    double? angle,
    List<DiyLayer>? layers,
    bool? animated,
    double? blur,
    double? scrim,
  }) {
    return DiyBackdrop.clamped(
      base: base ?? this.base,
      colors: colors ?? this.colors,
      stops: stops ?? this.stops,
      angle: angle ?? this.angle,
      layers: layers ?? this.layers,
      animated: animated ?? this.animated,
      blur: blur ?? this.blur,
      scrim: scrim ?? this.scrim,
    );
  }

  /// 增删图层后的新配置（越界索引一律忽略，不抛异常）
  DiyBackdrop withLayerAt(int index, DiyLayer layer) {
    if (index < 0 || index > layers.length) return this;
    final next = List<DiyLayer>.of(layers);
    if (index == next.length) {
      if (next.length >= kDiyMaxLayers) return this;
      next.add(layer);
    } else {
      next[index] = layer;
    }
    return copyWith(layers: next);
  }

  DiyBackdrop withoutLayerAt(int index) {
    if (index < 0 || index >= layers.length) return this;
    final next = List<DiyLayer>.of(layers)..removeAt(index);
    return copyWith(layers: next);
  }

  /// 交换两个图层（上移/下移）
  DiyBackdrop withLayerSwapped(int a, int b) {
    if (a == b || a < 0 || b < 0 || a >= layers.length || b >= layers.length) {
      return this;
    }
    final next = List<DiyLayer>.of(layers);
    final t = next[a];
    next[a] = next[b];
    next[b] = t;
    return copyWith(layers: next);
  }

  Map<String, dynamic> toJson() => {
        'base': base.key,
        'colors': [for (final c in colors) c.toARGB32()],
        'stops': [for (final s in stops) _r3(s)],
        'angle': _r3(angle),
        'layers': [for (final l in layers) l.toJson()],
        'animated': animated,
        'blur': _r3(blur),
        'scrim': _r3(scrim),
      };

  factory DiyBackdrop.fromJson(Map<String, dynamic> j) {
    final rawColors = j['colors'];
    final cs = <Color>[];
    if (rawColors is List) {
      for (final e in rawColors) {
        final col = _parseColor(e, null);
        if (col != null) cs.add(col);
      }
    }
    final rawLayers = j['layers'];
    final ls = <DiyLayer>[];
    if (rawLayers is List) {
      for (final e in rawLayers) {
        if (e is Map) {
          ls.add(DiyLayer.fromJson(e.map((k, v) => MapEntry('$k', v))));
        }
      }
    }
    final rawStops = j['stops'];
    final st = <double>[];
    if (rawStops is List) {
      for (final e in rawStops) {
        st.add(_parseDouble(e, 0));
      }
    }
    return DiyBackdrop.clamped(
      base: DiyBaseKindX.fromKey(j['base'] as String?),
      colors: cs.isEmpty ? null : cs,
      stops: st.isEmpty ? null : st,
      angle: _parseDouble(j['angle'], 135),
      layers: ls,
      animated: j['animated'] is bool ? j['animated'] as bool : true,
      blur: _parseDouble(j['blur'], 24),
      scrim: _parseDouble(j['scrim'], 0),
    );
  }
}

/// 校验并归一化色标：长度对齐 colors，单调递增且落在 0-1
List<double> _normalizeStops(List<double>? stops, int n) {
  if (stops == null || stops.length != n || n < 2) return const [];
  final out = <double>[];
  var prev = -1.0;
  for (var i = 0; i < n; i++) {
    var v = stops[i];
    if (!v.isFinite) v = n <= 1 ? 0 : i / (n - 1);
    v = v.clamp(0.0, 1.0);
    // 保证严格不减（相等会让 shader 报错）
    if (v < prev) v = prev;
    out.add(v);
    prev = v;
  }
  // 首 0 尾 1，渐变才有完整跨度
  if (out.isNotEmpty) {
    out[0] = 0.0;
    out[out.length - 1] = 1.0;
  }
  return out;
}

// ============================================================================
// 三、按钮样式
// ============================================================================

/// 按钮填充方式
enum DiyButtonFill {
  /// 实底
  solid,
  /// 渐变填充
  gradient,
  /// 毛玻璃（半透明 + 模糊）
  glass,
  /// 描边（透明底 + 边框）
  outline,
  /// 幽灵（无边框无底色，仅文字）
  ghost;

  String get key => name;
  String get label => switch (this) {
        DiyButtonFill.solid => '实底',
        DiyButtonFill.gradient => '渐变',
        DiyButtonFill.glass => '毛玻璃',
        DiyButtonFill.outline => '描边',
        DiyButtonFill.ghost => '幽灵',
      };
  static DiyButtonFill fromKey(String? k) {
    if (k == null) return DiyButtonFill.solid;
    for (final v in DiyButtonFill.values) {
      if (v.key == k.toLowerCase()) return v;
    }
    return DiyButtonFill.solid;
  }
}

/// 按钮绘制样式
class DiyButtonStyle {
  final DiyButtonFill fill;
  /// 主色；null 表示跟随主题主色（改主题色时按钮自动跟随）
  final Color? color;
  /// 渐变次色；null 时由主色自动派生
  final Color? color2;
  /// 圆角半径（px）
  final double radius;
  /// 高度（px）
  final double height;
  /// 描边宽度（px）
  final double borderWidth;
  /// 描边不透明度 0-1
  final double borderOpacity;
  /// 阴影模糊半径（px）
  final double shadowBlur;
  /// 阴影不透明度 0-1
  final double shadowOpacity;
  /// 字重（400/500/600/700）
  final double fontWeight;

  const DiyButtonStyle({
    this.fill = DiyButtonFill.solid,
    this.color,
    this.color2,
    this.radius = 12,
    this.height = 44,
    this.borderWidth = 1,
    this.borderOpacity = 0.3,
    this.shadowBlur = 8,
    this.shadowOpacity = 0.06,
    this.fontWeight = 600,
  });

  factory DiyButtonStyle.clamped({
    DiyButtonFill fill = DiyButtonFill.solid,
    Color? color,
    Color? color2,
    double radius = 12,
    double height = 44,
    double borderWidth = 1,
    double borderOpacity = 0.3,
    double shadowBlur = 8,
    double shadowOpacity = 0.06,
    double fontWeight = 600,
  }) {
    return DiyButtonStyle(
      fill: fill,
      color: color,
      color2: color2,
      radius: radius.clamp(0.0, 32.0),
      height: height.clamp(32.0, 64.0),
      borderWidth: borderWidth.clamp(0.0, 4.0),
      borderOpacity: borderOpacity.clamp(0.0, 1.0),
      shadowBlur: shadowBlur.clamp(0.0, 40.0),
      shadowOpacity: shadowOpacity.clamp(0.0, 0.6),
      // 字重只允许四档，避免中间值落到系统不存在的字重
      fontWeight: _snapWeight(fontWeight),
    );
  }

  DiyButtonStyle copyWith({
    DiyButtonFill? fill,
    Color? color,
    Color? color2,
    double? radius,
    double? height,
    double? borderWidth,
    double? borderOpacity,
    double? shadowBlur,
    double? shadowOpacity,
    double? fontWeight,
    bool clearColor = false,
    bool clearColor2 = false,
  }) {
    return DiyButtonStyle.clamped(
      fill: fill ?? this.fill,
      color: clearColor ? null : (color ?? this.color),
      color2: clearColor2 ? null : (color2 ?? this.color2),
      radius: radius ?? this.radius,
      height: height ?? this.height,
      borderWidth: borderWidth ?? this.borderWidth,
      borderOpacity: borderOpacity ?? this.borderOpacity,
      shadowBlur: shadowBlur ?? this.shadowBlur,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      fontWeight: fontWeight ?? this.fontWeight,
    );
  }

  Map<String, dynamic> toJson() => {
        'fill': fill.key,
        if (color != null) 'color': color!.toARGB32(),
        if (color2 != null) 'color2': color2!.toARGB32(),
        'radius': _r3(radius),
        'height': _r3(height),
        'borderWidth': _r3(borderWidth),
        'borderOpacity': _r3(borderOpacity),
        'shadowBlur': _r3(shadowBlur),
        'shadowOpacity': _r3(shadowOpacity),
        'fontWeight': fontWeight,
      };

  factory DiyButtonStyle.fromJson(Map<String, dynamic> j) {
    return DiyButtonStyle.clamped(
      fill: DiyButtonFill.fromKey(j['fill'] as String?),
      color: _parseColor(j['color'], null),
      color2: _parseColor(j['color2'], null),
      radius: _parseDouble(j['radius'], 12),
      height: _parseDouble(j['height'], 44),
      borderWidth: _parseDouble(j['borderWidth'], 1),
      borderOpacity: _parseDouble(j['borderOpacity'], 0.3),
      shadowBlur: _parseDouble(j['shadowBlur'], 8),
      shadowOpacity: _parseDouble(j['shadowOpacity'], 0.06),
      fontWeight: _parseDouble(j['fontWeight'], 600),
    );
  }
}

// ============================================================================
// 四、单个主题的 DIY 配置
// ============================================================================

/// 三个可 DIY 的主题标识
enum DiyThemeTarget { classic, glass, dark }

extension DiyThemeTargetX on DiyThemeTarget {
  String get key => name;
  String get label => switch (this) {
        DiyThemeTarget.classic => '经典',
        DiyThemeTarget.glass => '毛玻璃',
        DiyThemeTarget.dark => '深色',
      };
  static DiyThemeTarget? fromKey(String? k) {
    if (k == null) return null;
    for (final v in DiyThemeTarget.values) {
      if (v.key == k.toLowerCase()) return v;
    }
    return null;
  }
}

/// 某一主题的 DIY 配置。backdrop / button 为 null 表示该部分沿用内置默认。
class DiyThemeConfig {
  final DiyBackdrop? backdrop;
  final DiyButtonStyle? button;

  const DiyThemeConfig({this.backdrop, this.button});

  bool get isEmpty => backdrop == null && button == null;

  DiyThemeConfig copyWith({DiyBackdrop? backdrop, DiyButtonStyle? button,
      bool clearBackdrop = false, bool clearButton = false}) {
    return DiyThemeConfig(
      backdrop: clearBackdrop ? null : (backdrop ?? this.backdrop),
      button: clearButton ? null : (button ?? this.button),
    );
  }

  Map<String, dynamic> toJson() => {
        if (backdrop != null) 'backdrop': backdrop!.toJson(),
        if (button != null) 'button': button!.toJson(),
      };

  factory DiyThemeConfig.fromJson(Map<String, dynamic> j) {
    DiyBackdrop? bd;
    final rawBd = j['backdrop'];
    if (rawBd is Map) {
      bd = DiyBackdrop.fromJson(rawBd.map((k, v) => MapEntry('$k', v)));
    }
    DiyButtonStyle? bt;
    final rawBt = j['button'];
    if (rawBt is Map) {
      bt = DiyButtonStyle.fromJson(rawBt.map((k, v) => MapEntry('$k', v)));
    }
    return DiyThemeConfig(backdrop: bd, button: bt);
  }
}

/// 全部主题的 DIY 配置集合（整体序列化到一处，读写一次即可）
class DiyThemeSet {
  final Map<DiyThemeTarget, DiyThemeConfig> _map;

  const DiyThemeSet({Map<DiyThemeTarget, DiyThemeConfig>? themes})
      : _map = themes ?? const {};

  static const DiyThemeSet empty = DiyThemeSet();

  DiyThemeConfig? configOf(DiyThemeTarget t) => _map[t];

  bool get isEmpty => _map.isEmpty;

  /// 某主题是否已改过（用于 UI 显示"已自定义"标记）
  bool isCustomized(DiyThemeTarget t) {
    final cfg = _map[t];
    return cfg != null && !cfg.isEmpty;
  }

  DiyThemeSet withConfig(DiyThemeTarget t, DiyThemeConfig? cfg) {
    final next = Map<DiyThemeTarget, DiyThemeConfig>.of(_map);
    if (cfg == null || cfg.isEmpty) {
      next.remove(t);
    } else {
      next[t] = cfg;
    }
    return DiyThemeSet(themes: next);
  }

  /// 清空某一主题（恢复默认）
  DiyThemeSet without(DiyThemeTarget t) {
    if (!_map.containsKey(t)) return this;
    final next = Map<DiyThemeTarget, DiyThemeConfig>.of(_map)..remove(t);
    return DiyThemeSet(themes: next);
  }

  Map<String, dynamic> toJson() => {
        for (final e in _map.entries) e.key.key: e.value.toJson(),
      };

  factory DiyThemeSet.fromJson(Map<String, dynamic> j) {
    final out = <DiyThemeTarget, DiyThemeConfig>{};
    for (final e in j.entries) {
      final t = DiyThemeTargetX.fromKey(e.key);
      if (t == null) continue;
      final v = e.value;
      if (v is Map) {
        final cfg = DiyThemeConfig.fromJson(v.map((k, w) => MapEntry('$k', w)));
        if (!cfg.isEmpty) out[t] = cfg;
      }
    }
    return DiyThemeSet(themes: out);
  }

  /// 从 JSON 字符串解析：任何异常/脏数据都返回空配置（=全部走内置默认）
  static DiyThemeSet decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return DiyThemeSet.empty;
    try {
      final decoded = _decodeJsonMap(raw);
      if (decoded == null) return DiyThemeSet.empty;
      return DiyThemeSet.fromJson(decoded);
    } catch (_) {
      return DiyThemeSet.empty;
    }
  }

  String encode() => _encodeJsonMap(toJson());
}

// ============================================================================
// 五、风格预设（快速套用，套完仍可逐项微调）
// ============================================================================

/// 一个风格预设：给出基座与图层组合。颜色由 [forLight] 决定明暗取向，
/// 这样同一预设在深色主题下自动换成暗色版本，不会出现"深色主题配亮背景"。
class DiyPreset {
  final String key;
  final String label;
  final String desc;
  final DiyBackdrop Function(bool forLight) build;

  const DiyPreset({
    required this.key,
    required this.label,
    required this.desc,
    required this.build,
  });
}

/// 预设库。命名与文案走"人话"，避免堆砌形容词。
const List<DiyPreset> kDiyPresets = [
  DiyPreset(
    key: 'aurora',
    label: '极光',
    desc: '蓝紫斜向渐变，两道柔光带缓慢漂移',
    build: _presetAurora,
  ),
  DiyPreset(
    key: 'dawn',
    label: '晨雾',
    desc: '暖橙粉渐变，左上斜射光束',
    build: _presetDawn,
  ),
  DiyPreset(
    key: 'ink',
    label: '墨夜',
    desc: '近黑底，细密星点与四周暗角',
    build: _presetInk,
  ),
  DiyPreset(
    key: 'grid',
    label: '图纸',
    desc: '冷灰网格打底，配稀疏圆点',
    build: _presetGrid,
  ),
  DiyPreset(
    key: 'paper',
    label: '纸感',
    desc: '米白底，细微噪点，像打印纸',
    build: _presetPaper,
  ),
  DiyPreset(
    key: 'mint',
    label: '薄荷',
    desc: '青绿渐变，斜条纹打断单调',
    build: _presetMint,
  ),
  DiyPreset(
    key: 'sunset',
    label: '落日',
    desc: '橙到紫的径向渐变，边缘压暗',
    build: _presetSunset,
  ),
  DiyPreset(
    key: 'plain',
    label: '素底',
    desc: '单一底色，不加任何图层',
    build: _presetPlain,
  ),
];

DiyPreset? presetOfKey(String? key) {
  if (key == null) return null;
  for (final p in kDiyPresets) {
    if (p.key == key.toLowerCase()) return p;
  }
  return null;
}

DiyBackdrop _presetAurora(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.linear,
      colors: forLight
          ? const [Color(0xFFE8EEFB), Color(0xFFF3F0FD), Color(0xFFEAF6FB)]
          : const [Color(0xFF0B1020), Color(0xFF161233), Color(0xFF0A1A26)],
      angle: 135,
      layers: [
        DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
          color: forLight ? const Color(0xFF7C3AED) : const Color(0xFF6D5CF0),
          color2: forLight ? const Color(0xFFA78BFA) : const Color(0xFF3B2E7E),
          x: 0.16,
          y: 0.14,
          size: 0.62,
          intensity: forLight ? 0.34 : 0.42,
        ),
        DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
          color: const Color(0xFF38BDF8),
          color2: const Color(0xFF0EA5E9),
          x: 0.86,
          y: 0.82,
          size: 0.55,
          intensity: forLight ? 0.26 : 0.32,
        ),
        DiyLayer.defaultOf(DiyLayerKind.ribbon).copyWith(
          color: forLight ? const Color(0xFF8B5CF6) : const Color(0xFF7C6CF6),
          color2: forLight ? const Color(0xFFE9E2FF) : const Color(0xFFBFC6FF),
          y: 0.24,
          size: 0.15,
          angle: -10,
          intensity: forLight ? 0.4 : 0.46,
        ),
        DiyLayer.defaultOf(DiyLayerKind.ribbon).copyWith(
          color: forLight ? const Color(0xFF5EB2F7) : const Color(0xFF2E86C8),
          color2: forLight ? const Color(0xFFDFF2FF) : const Color(0xFF9ED8F2),
          y: 0.78,
          size: 0.12,
          angle: 8,
          intensity: forLight ? 0.3 : 0.34,
        ),
      ],
      animated: true,
      blur: 26,
    );

DiyBackdrop _presetDawn(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.linear,
      colors: forLight
          ? const [Color(0xFFFFF3E6), Color(0xFFFDE8EF), Color(0xFFF1F5FB)]
          : const [Color(0xFF2A1A16), Color(0xFF3B2231), Color(0xFF1A1622)],
      angle: 120,
      layers: [
        DiyLayer.defaultOf(DiyLayerKind.beam).copyWith(
          color: forLight ? const Color(0xFFFFB86B) : const Color(0xFFB9743A),
          color2: forLight ? const Color(0xFFFFFFFF) : const Color(0xFFFFD9A8),
          x: 0.12,
          y: -0.06,
          size: 0.34,
          angle: 32,
          intensity: forLight ? 0.34 : 0.26,
        ),
        DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
          color: forLight ? const Color(0xFFFB7185) : const Color(0xFF9F3A57),
          color2: forLight ? const Color(0xFFFDA4AF) : const Color(0xFF5E2338),
          x: 0.82,
          y: 0.18,
          size: 0.5,
          intensity: forLight ? 0.3 : 0.34,
        ),
        DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
          color: forLight ? const Color(0xFFFCD34D) : const Color(0xFF9A7B25),
          x: 0.3,
          y: 0.88,
          size: 0.44,
          intensity: forLight ? 0.22 : 0.24,
        ),
      ],
      animated: true,
      blur: 22,
    );

DiyBackdrop _presetInk(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.radial,
      colors: forLight
          ? const [Color(0xFFF8FAFC), Color(0xFFE2E8F0)]
          : const [Color(0xFF14161C), Color(0xFF07080B)],
      angle: 0,
      layers: [
        DiyLayer.defaultOf(DiyLayerKind.dots).copyWith(
          color: forLight ? const Color(0xFF94A3B8) : const Color(0xFF8FA0C0),
          size: 34,
          intensity: forLight ? 0.18 : 0.26,
          density: 1.1,
        ),
        DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
          color: forLight ? const Color(0xFF6366F1) : const Color(0xFF4F46E5),
          x: 0.5,
          y: 0.42,
          size: 0.7,
          intensity: forLight ? 0.12 : 0.2,
        ),
        DiyLayer.defaultOf(DiyLayerKind.vignette).copyWith(
          color: Colors.black,
          intensity: forLight ? 0.12 : 0.34,
          size: 0.5,
        ),
      ],
      animated: false,
      blur: 18,
    );

DiyBackdrop _presetGrid(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.solid,
      colors: [forLight ? const Color(0xFFF7F8FA) : const Color(0xFF1B1D23)],
      layers: [
        DiyLayer.defaultOf(DiyLayerKind.grid).copyWith(
          color: forLight ? const Color(0xFF94A3B8) : const Color(0xFF3F4654),
          size: 30,
          intensity: forLight ? 0.16 : 0.3,
          density: 1,
        ),
        DiyLayer.defaultOf(DiyLayerKind.dots).copyWith(
          color: forLight ? const Color(0xFF7C3AED) : const Color(0xFF8B7BF0),
          size: 150,
          intensity: forLight ? 0.2 : 0.28,
          density: 2.4,
        ),
        DiyLayer.defaultOf(DiyLayerKind.vignette).copyWith(
          intensity: forLight ? 0.06 : 0.2,
        ),
      ],
      animated: false,
      blur: 12,
    );

DiyBackdrop _presetPaper(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.solid,
      colors: [forLight ? const Color(0xFFFAF8F3) : const Color(0xFF23211D)],
      layers: [
        DiyLayer.defaultOf(DiyLayerKind.noise).copyWith(
          color: forLight ? const Color(0xFF78716C) : const Color(0xFFD6D3D1),
          size: 2.4,
          intensity: forLight ? 0.07 : 0.06,
          density: 0.6,
        ),
        DiyLayer.defaultOf(DiyLayerKind.grid).copyWith(
          color: forLight ? const Color(0xFFD6D3CD) : const Color(0xFF3A3833),
          size: 44,
          intensity: 0.1,
          density: 1,
        ),
      ],
      animated: false,
      blur: 8,
    );

DiyBackdrop _presetMint(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.linear,
      colors: forLight
          ? const [Color(0xFFECFDF5), Color(0xFFE0F2FE), Color(0xFFF0FDFA)]
          : const [Color(0xFF0C1F1B), Color(0xFF0B1E2A), Color(0xFF08201E)],
      angle: 150,
      layers: [
        DiyLayer.defaultOf(DiyLayerKind.stripe).copyWith(
          color: forLight ? const Color(0xFF34D399) : const Color(0xFF1E7F63),
          color2: forLight ? const Color(0xFFA7F3D0) : const Color(0xFF143A31),
          size: 30,
          angle: 60,
          intensity: forLight ? 0.16 : 0.2,
          density: 0.5,
        ),
        DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
          color: forLight ? const Color(0xFF06B6D4) : const Color(0xFF0E7490),
          x: 0.88,
          y: 0.14,
          size: 0.5,
          intensity: forLight ? 0.22 : 0.26,
        ),
      ],
      animated: true,
      blur: 20,
    );

DiyBackdrop _presetSunset(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.radial,
      colors: forLight
          ? const [Color(0xFFFFF7ED), Color(0xFFFED7AA), Color(0xFFE9D5FF)]
          : const [Color(0xFF2B1810), Color(0xFF4A1D2E), Color(0xFF1A1030)],
      layers: [
        DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
          color: forLight ? const Color(0xFFFB923C) : const Color(0xFFC2410C),
          x: 0.5,
          y: 0.72,
          size: 0.66,
          intensity: forLight ? 0.34 : 0.4,
        ),
        DiyLayer.defaultOf(DiyLayerKind.vignette).copyWith(
          intensity: forLight ? 0.14 : 0.36,
          size: 0.48,
        ),
      ],
      animated: false,
      blur: 16,
    );

DiyBackdrop _presetPlain(bool forLight) => DiyBackdrop.clamped(
      base: DiyBaseKind.solid,
      colors: [forLight ? const Color(0xFFF4F4F8) : const Color(0xFF1A1A1E)],
      layers: const [],
      animated: false,
      blur: 0,
    );

// ============================================================================
// 六、内置默认（未 DIY 时使用，与改造前观感一致）
// ============================================================================

/// 各主题的内置默认背景（用于"恢复默认"与预览初始值）。
/// 取值对齐改造前 GlassBackground / AppColors 的观感。
DiyBackdrop defaultBackdropOf(DiyThemeTarget t) {
  switch (t) {
    case DiyThemeTarget.glass:
      return DiyBackdrop.clamped(
        base: DiyBaseKind.linear,
        colors: const [Color(0xFFEDF2F9), Color(0xFFF1F4F9), Color(0xFFF6F8FB)],
        angle: 135,
        layers: [
          DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
            color: const Color(0xFF3E9BF0),
            x: 0.06,
            y: 0.10,
            size: 0.55,
            intensity: 0.42,
          ),
          DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
            color: const Color(0xFF2FBFD8),
            x: 0.08,
            y: 0.86,
            size: 0.52,
            intensity: 0.30,
          ),
          DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(
            color: const Color(0xFF9ED8F2),
            x: 0.42,
            y: 0.52,
            size: 0.60,
            intensity: 0.12,
          ),
          DiyLayer.defaultOf(DiyLayerKind.ribbon).copyWith(
            color: const Color(0xFF5EB2F7),
            color2: const Color(0xFFD8EDFF),
            y: 0.16,
            size: 0.15,
            angle: -6,
            intensity: 0.5,
          ),
        ],
        animated: true,
        blur: 24,
      );
    case DiyThemeTarget.dark:
      return DiyBackdrop.clamped(
        base: DiyBaseKind.solid,
        colors: const [Color(0xFF1A1A1E)],
        layers: const [],
        animated: false,
        blur: 0,
      );
    case DiyThemeTarget.classic:
      return DiyBackdrop.clamped(
        base: DiyBaseKind.solid,
        colors: const [Color(0xFFF4F4F8)],
        layers: const [],
        animated: false,
        blur: 0,
      );
  }
}

/// 各主题的内置默认按钮样式
DiyButtonStyle defaultButtonStyleOf(DiyThemeTarget t) {
  switch (t) {
    case DiyThemeTarget.glass:
      return DiyButtonStyle.clamped(
        fill: DiyButtonFill.glass,
        radius: 14,
        height: 44,
        borderWidth: 1,
        borderOpacity: 0.28,
        shadowBlur: 10,
        shadowOpacity: 0.08,
        fontWeight: 600,
      );
    case DiyThemeTarget.dark:
      return DiyButtonStyle.clamped(
        fill: DiyButtonFill.solid,
        radius: 12,
        height: 44,
        borderWidth: 1,
        borderOpacity: 0.3,
        shadowBlur: 6,
        shadowOpacity: 0.04,
        fontWeight: 600,
      );
    case DiyThemeTarget.classic:
      return DiyButtonStyle.clamped(
        fill: DiyButtonFill.solid,
        radius: 12,
        height: 44,
        borderWidth: 1,
        borderOpacity: 0.3,
        shadowBlur: 8,
        shadowOpacity: 0.06,
        fontWeight: 600,
      );
  }
}

// ============================================================================
// 七、工具函数
// ============================================================================

/// 保留 3 位小数，避免浮点尾数把配置串撑长
double _r3(double v) => (v * 1000).round() / 1000;

double _parseDouble(dynamic raw, double fallback) {
  if (raw is num) {
    final v = raw.toDouble();
    if (v.isFinite) return v;
    return fallback;
  }
  if (raw is String) {
    final v = double.tryParse(raw);
    if (v != null && v.isFinite) return v;
  }
  return fallback;
}

Color? _parseColor(dynamic raw, Color? fallback) {
  if (raw is num) {
    final v = raw.toInt();
    // 允许 0xRRGGBB 与 0xAARRGGBB 两种写法
    if (v >= 0 && v <= 0xFFFFFFFF) {
      return v <= 0xFFFFFF ? Color(0xFF000000 | v) : Color(v);
    }
    return fallback;
  }
  if (raw is String) {
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s';
    if (s.length == 8) {
      final v = int.tryParse(s, radix: 16);
      if (v != null) return Color(v);
    }
  }
  return fallback;
}

/// 字重吸附到四档
double _snapWeight(double w) {
  if (!w.isFinite) return 600;
  if (w <= 450) return 400;
  if (w <= 550) return 500;
  if (w <= 650) return 600;
  return 700;
}

/// 极简 JSON 编码：只为把 Map<String, dynamic>（仅含 bool/num/String/List/Map）
/// 写成一行字符串，避免引入 dart:convert 之外的依赖与转义坑。
String _encodeJsonMap(Map<String, dynamic> m) {
  final sb = StringBuffer('{');
  var first = true;
  for (final e in m.entries) {
    if (!first) sb.write(',');
    first = false;
    sb.write('"${_esc(e.key)}":');
    sb.write(_encodeValue(e.value));
  }
  sb.write('}');
  return sb.toString();
}

String _encodeValue(dynamic v) {
  if (v == null) return 'null';
  if (v is bool) return v ? 'true' : 'false';
  if (v is num) return '$v';
  if (v is String) return '"${_esc(v)}"';
  if (v is List) {
    final sb = StringBuffer('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) sb.write(',');
      sb.write(_encodeValue(v[i]));
    }
    sb.write(']');
    return sb.toString();
  }
  if (v is Map) {
    final sb = StringBuffer('{');
    var first = true;
    for (final e in v.entries) {
      if (!first) sb.write(',');
      first = false;
      sb.write('"${_esc('${e.key}')}":');
      sb.write(_encodeValue(e.value));
    }
    sb.write('}');
    return sb.toString();
  }
  return 'null';
}

String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('"', '\\"')
    .replaceAll('\n', '\\n')
    .replaceAll('\r', '\\r');

/// 极简 JSON 解码：仅支持本项目配置用到的结构（对象/数组/字符串/数字/bool）。
/// 解析失败返回 null，由调用方回退默认值。
Map<String, dynamic>? _decodeJsonMap(String src) {
  final s = src.trim();
  if (!s.startsWith('{') || !s.endsWith('}')) return null;
  var i = 0;

  void skipWs() {
    while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) {
      i++;
    }
  }

  String? parseString() {
    // 调用前已确认 s[i] == '"'
    i++;
    final sb = StringBuffer();
    while (i < s.length) {
      final c = s[i];
      if (c == '"') {
        i++;
        return sb.toString();
      }
      if (c == '\\') {
        i++;
        if (i >= s.length) return null;
        final e = s[i];
        switch (e) {
          case 'n':
            sb.write('\n');
          case 'r':
            sb.write('\r');
          case 't':
            sb.write('\t');
          case '"':
            sb.write('"');
          case '\\':
            sb.write('\\');
          case '/':
            sb.write('/');
          default:
            sb.write(e);
        }
        i++;
        continue;
      }
      sb.write(c);
      i++;
    }
    return null;
  }

  dynamic parseValue() {
    skipWs();
    if (i >= s.length) return null;
    final ch = s[i];
    if (ch == '{') {
      i++;
      final out = <String, dynamic>{};
      skipWs();
      if (i < s.length && s[i] == '}') {
        i++;
        return out;
      }
      while (i < s.length) {
        skipWs();
        if (s[i] != '"') return null;
        final key = parseString();
        if (key == null) return null;
        skipWs();
        if (i >= s.length || s[i] != ':') return null;
        i++;
        final v = parseValue();
        if (v == null) return null;
        out[key] = v;
        skipWs();
        if (i < s.length && s[i] == ',') {
          i++;
          continue;
        }
        if (i < s.length && s[i] == '}') {
          i++;
          return out;
        }
        return null;
      }
      return null;
    }
    if (ch == '[') {
      i++;
      final out = <dynamic>[];
      skipWs();
      if (i < s.length && s[i] == ']') {
        i++;
        return out;
      }
      while (i < s.length) {
        final v = parseValue();
        if (v == null) return null;
        out.add(v);
        skipWs();
        if (i < s.length && s[i] == ',') {
          i++;
          continue;
        }
        if (i < s.length && s[i] == ']') {
          i++;
          return out;
        }
        return null;
      }
      return null;
    }
    if (ch == '"') return parseString();
    if (ch == 't') {
      if (s.startsWith('true', i)) {
        i += 4;
        return true;
      }
      return null;
    }
    if (ch == 'f') {
      if (s.startsWith('false', i)) {
        i += 5;
        return false;
      }
      return null;
    }
    if (ch == 'n') {
      if (s.startsWith('null', i)) {
        i += 4;
        return null;
      }
      return null;
    }
    // 数字
    final start = i;
    while (i < s.length &&
        (s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57 ||
            s[i] == '-' ||
            s[i] == '+' ||
            s[i] == '.' ||
            s[i] == 'e' ||
            s[i] == 'E')) {
      i++;
    }
    if (start == i) return null;
    return num.tryParse(s.substring(start, i));
  }

  final result = parseValue();
  if (result is Map<String, dynamic>) return result;
  if (result is Map) return result.map((k, v) => MapEntry('$k', v));
  return null;
}

/// 十六进制颜色字符串（#RRGGBB），供 UI 展示与 Agent 参数使用
String diyColorToHex(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// 解析颜色：支持 #RGB / #RRGGBB / #AARRGGBB / 十进制整数 / 常用英文色名
Color? diyParseColor(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
  }
  if (s.length == 6) s = 'FF$s';
  if (s.length == 8) {
    final v = int.tryParse(s, radix: 16);
    if (v != null) return Color(v);
  }
  final num = int.tryParse(raw);
  if (num != null && num >= 0 && num <= 0xFFFFFFFF) {
    return num <= 0xFFFFFF ? Color(0xFF000000 | num) : Color(num);
  }
  return kDiyNamedColors[raw.trim().toLowerCase()];
}

/// 常用色名（Agent 与用户都可直接写"天蓝""墨黑"这类词）
const Map<String, Color> kDiyNamedColors = {
  '紫': Color(0xFF7C3AED),
  'purple': Color(0xFF7C3AED),
  '蓝': Color(0xFF3B82F6),
  'blue': Color(0xFF3B82F6),
  '天蓝': Color(0xFF38BDF8),
  'skyblue': Color(0xFF38BDF8),
  '青': Color(0xFF06B6D4),
  'cyan': Color(0xFF06B6D4),
  '绿': Color(0xFF22C55E),
  'green': Color(0xFF22C55E),
  '黄': Color(0xFFFACC15),
  'yellow': Color(0xFFFACC15),
  '橙': Color(0xFFF97316),
  'orange': Color(0xFFF97316),
  '红': Color(0xFFEF4444),
  'red': Color(0xFFEF4444),
  '粉': Color(0xFFEC4899),
  'pink': Color(0xFFEC4899),
  '白': Color(0xFFFFFFFF),
  'white': Color(0xFFFFFFFF),
  '黑': Color(0xFF000000),
  'black': Color(0xFF000000),
  '灰': Color(0xFF94A3B8),
  'gray': Color(0xFF94A3B8),
  'grey': Color(0xFF94A3B8),
  '墨': Color(0xFF1A1A1E),
  'ink': Color(0xFF1A1A1E),
};

/// UI 取色板：DIY 页面色块选择用（常用 12 色 + 主题主色由调用方补）
const List<Color> kDiyPalette = [
  Color(0xFF7C3AED),
  Color(0xFF3B82F6),
  Color(0xFF38BDF8),
  Color(0xFF06B6D4),
  Color(0xFF22C55E),
  Color(0xFF84CC16),
  Color(0xFFFACC15),
  Color(0xFFF97316),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF94A3B8),
  Color(0xFF1A1A1E),
];

/// 角度（度）→ 线性渐变起止对齐。0°=自左向右，90°=自上向下。
(Alignment, Alignment) diyGradientAlignments(double degrees) {
  final rad = degrees * math.pi / 180;
  final dx = math.cos(rad);
  final dy = math.sin(rad);
  return (Alignment(-dx, -dy), Alignment(dx, dy));
}

// ============================================================================
// 八、样式 → Flutter 控件样式
// ============================================================================

/// 把按钮 DIY 配置转成 [ButtonStyle]，供全局主题注入与预览卡复用。
///
/// 说明：Flutter 的 ButtonStyle 不支持渐变底色，故 [DiyButtonFill.gradient]
/// 取"主色 → 次色"按 3:7 混合后的实色作为底色，并把次色用作按压态叠色
/// （按下时透出次色，观感接近渐变）。预览卡里会绘制真实渐变。
ButtonStyle diyToButtonStyle(
  DiyButtonStyle s, {
  required Color primary,
  required Color onPrimary,
  required Color foreground,
  required bool isLight,
  double fontSize = 13.5,
}) {
  final main = s.color ?? primary;
  final second = s.color2 ?? Color.lerp(main, isLight ? Colors.white : Colors.black, 0.28)!;
  final radius = BorderRadius.circular(s.radius);
  final weight = _weightOf(s.fontWeight);
  final shadowColor =
      (isLight ? Colors.black : Colors.black).withValues(alpha: s.shadowOpacity);

  Color bg;
  Color fg;
  BorderSide side = BorderSide.none;
  Color? overlay;

  switch (s.fill) {
    case DiyButtonFill.solid:
      bg = main;
      fg = onPrimary;
    case DiyButtonFill.gradient:
      bg = Color.lerp(main, second, 0.3)!;
      fg = onPrimary;
      overlay = second.withValues(alpha: 0.28);
    case DiyButtonFill.glass:
      bg = main.withValues(alpha: isLight ? 0.16 : 0.28);
      fg = foreground;
      side = BorderSide(
        color: main.withValues(alpha: s.borderOpacity),
        width: s.borderWidth,
      );
    case DiyButtonFill.outline:
      bg = Colors.transparent;
      fg = main;
      side = BorderSide(
        color: main.withValues(alpha: s.borderOpacity.clamp(0.12, 1.0)),
        width: s.borderWidth,
      );
    case DiyButtonFill.ghost:
      bg = Colors.transparent;
      fg = main;
  }

  return ButtonStyle(
    backgroundColor: WidgetStateProperty.all(bg),
    foregroundColor: WidgetStateProperty.all(fg),
    overlayColor: WidgetStateProperty.all(overlay ?? fg.withValues(alpha: 0.08)),
    shadowColor: WidgetStateProperty.all(shadowColor),
    elevation: WidgetStateProperty.all(0),
    // 阴影用 BoxShadow 无法注入，退而用 elevation + shadowColor 的柔和投影近似
    surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
    shape: WidgetStateProperty.all(RoundedRectangleBorder(
      borderRadius: radius,
      side: side,
    )),
    minimumSize: WidgetStateProperty.all(Size(0, s.height)),
    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 20)),
    textStyle: WidgetStateProperty.all(TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      letterSpacing: 0.1,
    )),
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

FontWeight _weightOf(double w) {
  if (w <= 400) return FontWeight.w400;
  if (w <= 500) return FontWeight.w500;
  if (w <= 600) return FontWeight.w600;
  return FontWeight.w700;
}

/// 按钮阴影（DIY 页面预览与自定义按钮用；ThemeData 无法直接表达偏移阴影，
/// 故提供此装饰供需要精确还原的场景使用）
List<BoxShadow> diyButtonShadows(DiyButtonStyle s, {bool isLight = true}) {
  if (s.shadowBlur <= 0 || s.shadowOpacity <= 0) return const [];
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: s.shadowOpacity),
      blurRadius: s.shadowBlur,
      offset: const Offset(0, 2),
    ),
  ];
}

/// 渐变按钮的真实底色（预览/自定义按钮用）
LinearGradient diyButtonGradient(DiyButtonStyle s, Color primary, bool isLight) {
  final main = s.color ?? primary;
  final second = s.color2 ?? Color.lerp(main, isLight ? Colors.white : Colors.black, 0.28)!;
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [main, second],
  );
}
