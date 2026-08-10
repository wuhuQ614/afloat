// 画板数据模型：图层、笔刷、画作、动画帧（对齐参考项目 DrawingTab.jsx 的数据结构）
library;

import 'dart:ui' show Color, BlendMode;

// ==================== 混合模式 ====================
/// 混合模式列表（value 用于存储，label 中文名，blend 对应 Flutter BlendMode）
class BlendModeEntry {
  final String value;
  final String label;
  final BlendMode blend;
  const BlendModeEntry(this.value, this.label, this.blend);
}

const List<BlendModeEntry> kBlendModes = [
  BlendModeEntry('source-over', '正常', BlendMode.srcOver),
  BlendModeEntry('multiply', '正片叠底', BlendMode.multiply),
  BlendModeEntry('screen', '滤色', BlendMode.screen),
  BlendModeEntry('overlay', '叠加', BlendMode.overlay),
  BlendModeEntry('darken', '变暗', BlendMode.darken),
  BlendModeEntry('lighten', '变亮', BlendMode.lighten),
  BlendModeEntry('color-dodge', '颜色减淡', BlendMode.colorDodge),
  BlendModeEntry('color-burn', '颜色加深', BlendMode.colorBurn),
  BlendModeEntry('hard-light', '强光', BlendMode.hardLight),
  BlendModeEntry('soft-light', '柔光', BlendMode.softLight),
  BlendModeEntry('difference', '差值', BlendMode.difference),
  BlendModeEntry('exclusion', '排除', BlendMode.exclusion),
  BlendModeEntry('hue', '色相', BlendMode.hue),
  BlendModeEntry('saturation', '饱和度', BlendMode.saturation),
  BlendModeEntry('color', '颜色', BlendMode.color),
  BlendModeEntry('luminosity', '明度', BlendMode.luminosity),
];

BlendMode resolveBlendMode(String? value) {
  for (final e in kBlendModes) {
    if (e.value == value) return e.blend;
  }
  return BlendMode.srcOver;
}

String blendValueOf(BlendMode b) {
  for (final e in kBlendModes) {
    if (e.blend == b) return e.value;
  }
  return 'source-over';
}

// ==================== 笔刷 ====================
/// 笔刷纹理类型
enum BrushTexture {
  solid, grainy, flat, semi, spray, watercolor, crayon, charcoal, gpen,
  dippen, inkbrush, oilpaint, pastel, airbrush, halftone, neon, fur, pixel,
  chalk, softpastel, acrylic, gouache, grass, cloud, noiseGrain, halftone2,
  doubleline, smudge, mixer, crosshatch, splatter, stipple, grunge, sand,
  scratch, calligraphy, cloth,
}

/// 笔刷分组
enum BrushGroup { line, paint, sketch, texture, special }

/// 单个笔刷定义
class DrawingBrush {
  final String id;
  final String name;
  final double defaultWidth;
  final BrushTexture texture;
  final bool grain;
  final double opacity; // 0-1，默认 1
  final int particleCount;
  final BrushGroup group;

  const DrawingBrush({
    required this.id,
    required this.name,
    required this.defaultWidth,
    required this.texture,
    this.grain = false,
    this.opacity = 1,
    this.particleCount = 0,
    required this.group,
  });

  static const List<DrawingBrush> all = [
    DrawingBrush(id: 'pencil', name: '铅笔', defaultWidth: 2, texture: BrushTexture.grainy, grain: true, group: BrushGroup.line),
    DrawingBrush(id: 'round', name: '圆头画笔', defaultWidth: 6, texture: BrushTexture.solid, group: BrushGroup.paint),
    DrawingBrush(id: 'flat', name: '扁头画笔', defaultWidth: 10, texture: BrushTexture.flat, group: BrushGroup.paint),
    DrawingBrush(id: 'marker', name: '马克笔', defaultWidth: 14, texture: BrushTexture.semi, opacity: 0.7, group: BrushGroup.line),
    DrawingBrush(id: 'ballpoint', name: '圆珠笔', defaultWidth: 2, texture: BrushTexture.solid, opacity: 0.6, group: BrushGroup.line),
    DrawingBrush(id: 'pen', name: '勾线画笔', defaultWidth: 1.5, texture: BrushTexture.solid, group: BrushGroup.line),
    DrawingBrush(id: 'spray', name: '喷枪', defaultWidth: 20, texture: BrushTexture.spray, particleCount: 50, group: BrushGroup.paint),
    DrawingBrush(id: 'watercolor', name: '水彩笔', defaultWidth: 12, texture: BrushTexture.watercolor, opacity: 0.15, group: BrushGroup.paint),
    DrawingBrush(id: 'crayon', name: '蜡笔', defaultWidth: 10, texture: BrushTexture.crayon, grain: true, group: BrushGroup.sketch),
    DrawingBrush(id: 'charcoal', name: '碳笔', defaultWidth: 6, texture: BrushTexture.charcoal, grain: true, group: BrushGroup.sketch),
    DrawingBrush(id: 'gpen', name: 'G笔', defaultWidth: 4, texture: BrushTexture.gpen, group: BrushGroup.line),
    DrawingBrush(id: 'dippen', name: '蘸水笔', defaultWidth: 2, texture: BrushTexture.dippen, group: BrushGroup.line),
    DrawingBrush(id: 'inkbrush', name: '毛笔', defaultWidth: 8, texture: BrushTexture.inkbrush, group: BrushGroup.special),
    DrawingBrush(id: 'oilpaint', name: '油画笔', defaultWidth: 12, texture: BrushTexture.oilpaint, grain: true, group: BrushGroup.paint),
    DrawingBrush(id: 'pastel', name: '粉彩笔', defaultWidth: 14, texture: BrushTexture.pastel, grain: true, group: BrushGroup.paint),
    DrawingBrush(id: 'airbrush', name: '柔边喷枪', defaultWidth: 18, texture: BrushTexture.airbrush, group: BrushGroup.paint),
    DrawingBrush(id: 'halftone', name: '网点笔', defaultWidth: 16, texture: BrushTexture.halftone, group: BrushGroup.texture),
    DrawingBrush(id: 'neon', name: '荧光笔', defaultWidth: 6, texture: BrushTexture.neon, group: BrushGroup.texture),
    DrawingBrush(id: 'fur', name: '毛发笔', defaultWidth: 10, texture: BrushTexture.fur, group: BrushGroup.special),
    DrawingBrush(id: 'pixel', name: '像素笔', defaultWidth: 4, texture: BrushTexture.pixel, group: BrushGroup.special),
    DrawingBrush(id: 'chalk', name: '粉笔', defaultWidth: 8, texture: BrushTexture.chalk, grain: true, opacity: 0.7, group: BrushGroup.sketch),
    DrawingBrush(id: 'softpastel', name: '色粉笔', defaultWidth: 14, texture: BrushTexture.softpastel, grain: true, opacity: 0.5, group: BrushGroup.paint),
    DrawingBrush(id: 'acrylic', name: '丙烯', defaultWidth: 10, texture: BrushTexture.acrylic, opacity: 0.85, group: BrushGroup.paint),
    DrawingBrush(id: 'gouache', name: '水粉', defaultWidth: 12, texture: BrushTexture.gouache, opacity: 0.75, group: BrushGroup.paint),
    DrawingBrush(id: 'grass', name: '草丛', defaultWidth: 8, texture: BrushTexture.grass, particleCount: 12, group: BrushGroup.special),
    DrawingBrush(id: 'cloud', name: '云朵', defaultWidth: 20, texture: BrushTexture.cloud, opacity: 0.3, group: BrushGroup.texture),
    DrawingBrush(id: 'noise', name: '噪点', defaultWidth: 14, texture: BrushTexture.noiseGrain, grain: true, opacity: 0.5, group: BrushGroup.texture),
    DrawingBrush(id: 'halftone2', name: '半调', defaultWidth: 16, texture: BrushTexture.halftone2, group: BrushGroup.texture),
    DrawingBrush(id: 'doubleline', name: '双线', defaultWidth: 6, texture: BrushTexture.doubleline, group: BrushGroup.line),
    DrawingBrush(id: 'smudge', name: '涂抹', defaultWidth: 16, texture: BrushTexture.smudge, opacity: 0.4, group: BrushGroup.special),
    DrawingBrush(id: 'mixer', name: '混色', defaultWidth: 14, texture: BrushTexture.mixer, opacity: 0.5, group: BrushGroup.special),
    DrawingBrush(id: 'crosshatch', name: '交叉排线', defaultWidth: 10, texture: BrushTexture.crosshatch, opacity: 0.7, group: BrushGroup.sketch),
    DrawingBrush(id: 'splatter', name: '泼溅', defaultWidth: 18, texture: BrushTexture.splatter, particleCount: 30, group: BrushGroup.texture),
    DrawingBrush(id: 'stipple', name: '点画', defaultWidth: 14, texture: BrushTexture.stipple, opacity: 0.8, group: BrushGroup.sketch),
    DrawingBrush(id: 'grunge', name: '肌理', defaultWidth: 16, texture: BrushTexture.grunge, grain: true, opacity: 0.55, group: BrushGroup.texture),
    DrawingBrush(id: 'sand', name: '砂粒', defaultWidth: 12, texture: BrushTexture.sand, grain: true, opacity: 0.5, group: BrushGroup.texture),
    DrawingBrush(id: 'scratch', name: '刮擦', defaultWidth: 8, texture: BrushTexture.scratch, opacity: 0.7, group: BrushGroup.sketch),
    DrawingBrush(id: 'calligraphy', name: '书法笔', defaultWidth: 12, texture: BrushTexture.calligraphy, opacity: 0.9, group: BrushGroup.special),
    DrawingBrush(id: 'cloth', name: '布料纹理', defaultWidth: 14, texture: BrushTexture.cloth, grain: true, opacity: 0.55, group: BrushGroup.texture),
  ];

  static DrawingBrush byId(String id) {
    for (final b in all) {
      if (b.id == id) return b;
    }
    return all[1];
  }
}

/// 笔刷分组显示元信息
class BrushGroupInfo {
  final BrushGroup group;
  final String key;
  final String name;
  final String icon;
  final String desc;
  const BrushGroupInfo(this.group, this.key, this.name, this.icon, this.desc);
}

const List<BrushGroupInfo> kBrushGroups = [
  BrushGroupInfo(BrushGroup.line, 'line', '勾线', '━', '精细线条'),
  BrushGroupInfo(BrushGroup.paint, 'paint', '上色', '●', '绘画涂色'),
  BrushGroupInfo(BrushGroup.sketch, 'sketch', '素描', '╱', '素描质感'),
  BrushGroupInfo(BrushGroup.texture, 'texture', '纹理', '▦', '特效纹理'),
  BrushGroupInfo(BrushGroup.special, 'special', '特殊', '◆', '创意笔刷'),
];

// ==================== 颜色 ====================
/// 预设调色板（6 行 × 6 列，对齐参考项目 basicColors）
const List<List<Color>> kBasicColors = [
  [Color(0xFF000000), Color(0xFF333333), Color(0xFF666666), Color(0xFF999999), Color(0xFFCCCCCC), Color(0xFFFFFFFF)],
  [Color(0xFFEF4444), Color(0xFFF97316), Color(0xFFF59E0B), Color(0xFFFBBF24), Color(0xFF84CC16), Color(0xFF22C55E)],
  [Color(0xFF10B981), Color(0xFF14B8A6), Color(0xFF06B6D4), Color(0xFF0EA5E9), Color(0xFF3BF6E6), Color(0xFF6366F1)],
  [Color(0xFF8B5CF6), Color(0xFFA855F7), Color(0xFFD946EF), Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFFFB7185)],
  [Color(0xFF7C2D12), Color(0xFF92400E), Color(0xFFB45309), Color(0xFFD97706), Color(0xFFCA8A04), Color(0xFF65A30D)],
  [Color(0xFF15803D), Color(0xFF0D9488), Color(0xFF0891B2), Color(0xFF0284C7), Color(0xFF2563EB), Color(0xFF4F46E5)],
];

// ==================== 图层 ====================
class CanvasLayer {
  int id;
  String name;
  bool visible;
  double opacity; // 0-1
  String blendMode; // value in kBlendModes
  bool locked;
  bool clippingMask;
  /// 图层栅格数据（像素字节 RGBA，宽高与画布一致）；null 表示空图层
  dynamic pixels;

  CanvasLayer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1,
    this.blendMode = 'source-over',
    this.locked = false,
    this.clippingMask = false,
    this.pixels,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'visible': visible,
        'opacity': opacity,
        'blendMode': blendMode,
        'locked': locked,
        'clippingMask': clippingMask,
      };

  factory CanvasLayer.fromJson(Map<String, dynamic> j) => CanvasLayer(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] as String?) ?? '图层',
        visible: (j['visible'] as bool?) ?? true,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
        blendMode: (j['blendMode'] as String?) ?? 'source-over',
        locked: (j['locked'] as bool?) ?? false,
        clippingMask: (j['clippingMask'] as bool?) ?? false,
      );
}

// ==================== 画作 ====================
class DrawingArtwork {
  String id;
  String name;
  int w;
  int h;
  String? dataUrl; // PNG base64 data URL
  String? thumbnail;
  String date;
  int timestamp;
  bool isSaved;
  bool isAutoSave;

  DrawingArtwork({
    required this.id,
    required this.name,
    this.w = 0,
    this.h = 0,
    this.dataUrl,
    this.thumbnail,
    this.date = '',
    required this.timestamp,
    this.isSaved = false,
    this.isAutoSave = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'w': w,
        'h': h,
        'dataURL': dataUrl,
        'thumbnail': thumbnail,
        'date': date,
        'timestamp': timestamp,
        'isSaved': isSaved,
        'isAutoSave': isAutoSave,
      };

  factory DrawingArtwork.fromJson(Map<String, dynamic> j) => DrawingArtwork(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '未命名',
        w: (j['w'] as num?)?.toInt() ?? 0,
        h: (j['h'] as num?)?.toInt() ?? 0,
        dataUrl: (j['dataURL'] as String?) ?? (j['dataUrl'] as String?),
        thumbnail: (j['thumbnail'] as String?),
        date: (j['date'] as String?) ?? '',
        timestamp: (j['timestamp'] as num?)?.toInt() ?? 0,
        isSaved: (j['isSaved'] as bool?) ?? false,
        isAutoSave: (j['isAutoSave'] as bool?) ?? false,
      );
}

// ==================== 画布预设 ====================
class CanvasPreset {
  final String label;
  final int w;
  final int h;
  const CanvasPreset(this.label, this.w, this.h);
}

const List<CanvasPreset> kCanvasPresets = [
  CanvasPreset('默认', 1920, 1080),
  CanvasPreset('正方形', 1080, 1080),
  CanvasPreset('A4竖版', 3508, 2480),
  CanvasPreset('A4横版', 2480, 3508),
  CanvasPreset('16:9', 1080, 1920),
  CanvasPreset('4:3', 1600, 1200),
  CanvasPreset('手机竖屏', 1080, 1920),
  CanvasPreset('方型小', 512, 512),
];

// ==================== 动画帧 ====================
class AnimFrame {
  final int id;
  String? dataUrl; // PNG base64
  AnimFrame({required this.id, this.dataUrl});
}

// ==================== 滤镜 ====================
class DrawingFilter {
  double blur = 0;
  double brightness = 100;
  double contrast = 100;
  double saturate = 100;
  double hueRotate = 0;
  double grayscale = 0;
  double invert = 0;
  double sepia = 0;

  DrawingFilter();

  bool get isIdentity =>
      blur == 0 &&
      brightness == 100 &&
      contrast == 100 &&
      saturate == 100 &&
      hueRotate == 0 &&
      grayscale == 0 &&
      invert == 0 &&
      sepia == 0;

  Map<String, dynamic> toJson() => {
        'blur': blur,
        'brightness': brightness,
        'contrast': contrast,
        'saturate': saturate,
        'hueRotate': hueRotate,
        'grayscale': grayscale,
        'invert': invert,
        'sepia': sepia,
      };

  factory DrawingFilter.fromJson(Map<String, dynamic> j) {
    final f = DrawingFilter();
    f.blur = (j['blur'] as num?)?.toDouble() ?? 0;
    f.brightness = (j['brightness'] as num?)?.toDouble() ?? 100;
    f.contrast = (j['contrast'] as num?)?.toDouble() ?? 100;
    f.saturate = (j['saturate'] as num?)?.toDouble() ?? 100;
    f.hueRotate = (j['hueRotate'] as num?)?.toDouble() ?? 0;
    f.grayscale = (j['grayscale'] as num?)?.toDouble() ?? 0;
    f.invert = (j['invert'] as num?)?.toDouble() ?? 0;
    f.sepia = (j['sepia'] as num?)?.toDouble() ?? 0;
    return f;
  }
}

// ==================== 洋葱皮设置 ====================
class OnionSkinSettings {
  bool prevEnabled = true;
  bool nextEnabled = true;
  Color prevColor = const Color(0xFFFF4444);
  Color nextColor = const Color(0xFF4444FF);
  int prevOpacity = 35;
  int nextOpacity = 35;
  int range = 3;
  bool useTint = false;
  bool blendWithBg = false;

  OnionSkinSettings();

  Map<String, dynamic> toJson() => {
        'prevEnabled': prevEnabled,
        'nextEnabled': nextEnabled,
        'prevColor': prevColor.toARGB32(),
        'nextColor': nextColor.toARGB32(),
        'prevOpacity': prevOpacity,
        'nextOpacity': nextOpacity,
        'range': range,
        'useTint': useTint,
        'blendWithBg': blendWithBg,
      };

  factory OnionSkinSettings.fromJson(Map<String, dynamic> j) {
    final s = OnionSkinSettings();
    s.prevEnabled = (j['prevEnabled'] as bool?) ?? true;
    s.nextEnabled = (j['nextEnabled'] as bool?) ?? true;
    s.prevColor = Color((j['prevColor'] as num?)?.toInt() ?? 0xFFFF4444);
    s.nextColor = Color((j['nextColor'] as num?)?.toInt() ?? 0xFF4444FF);
    s.prevOpacity = (j['prevOpacity'] as num?)?.toInt() ?? 35;
    s.nextOpacity = (j['nextOpacity'] as num?)?.toInt() ?? 35;
    s.range = (j['range'] as num?)?.toInt() ?? 3;
    s.useTint = (j['useTint'] as bool?) ?? false;
    s.blendWithBg = (j['blendWithBg'] as bool?) ?? false;
    return s;
  }
}