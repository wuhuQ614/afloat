// 主题 DIY 逻辑自检（flutter test 版）：模型容错、序列化往返、clamp 边界、
// 图层增删排序、预设构建、颜色解析、按钮颜色清除语义。
// 运行：flutter test test/verify_theme_diy_test.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/theme_diy.dart';

void main() {
  test('主题 DIY 模型逻辑', () {
    void expectTrue(String name, bool cond) {
      expect(cond, isTrue, reason: name);
    }

    // ── 1) 序列化往返 ──
    final set = DiyThemeSet.empty
        .withConfig(DiyThemeTarget.glass, DiyThemeConfig(
          backdrop: DiyBackdrop.clamped(
            base: DiyBaseKind.linear,
            colors: const [Color(0xFF7C3AED), Color(0xFFA78BFA)],
            angle: 200,
            layers: [
              DiyLayer.defaultOf(DiyLayerKind.glow).copyWith(x: 0.3, intensity: 0.7),
              DiyLayer.defaultOf(DiyLayerKind.dots).copyWith(density: 3.5, enabled: false),
            ],
            animated: false,
            blur: 30,
            scrim: 0.2,
          ),
          button: DiyButtonStyle.clamped(
            fill: DiyButtonFill.gradient,
            color: const Color(0xFF22C55E),
            color2: const Color(0xFF84CC16),
            radius: 18,
            fontWeight: 700,
          ),
        ))
        .withConfig(DiyThemeTarget.dark, const DiyThemeConfig(backdrop: DiyBackdrop()));
    final back = DiyThemeSet.decode(set.encode());
    final bd = back.configOf(DiyThemeTarget.glass)?.backdrop;
    final btn = back.configOf(DiyThemeTarget.glass)?.button;
    expectTrue('glass 配置保留', back.configOf(DiyThemeTarget.glass) != null);
    expectTrue('base=linear', bd?.base == DiyBaseKind.linear);
    expectTrue('2 色保留', bd?.colors.length == 2 && bd!.colors[0] == const Color(0xFF7C3AED));
    expectTrue('角度 200', (bd?.angle ?? 0) == 200);
    expectTrue('图层 2 个且顺序保持', bd?.layers.length == 2 && bd!.layers[0].kind == DiyLayerKind.glow);
    expectTrue('圆点密度 3.5 未被钳制', (bd?.layers[1].density ?? 0) == 3.5);
    expectTrue('图层显隐保留', bd?.layers[1].enabled == false);
    expectTrue('blur/scrim', (bd?.blur ?? 0) == 30 && (bd?.scrim ?? 0) == 0.2);
    expectTrue('按钮渐变+圆角18+字重700', btn?.fill == DiyButtonFill.gradient && btn!.radius == 18 && btn.fontWeight == 700);
    expectTrue('深色 backdrop 非空', back.configOf(DiyThemeTarget.dark)?.backdrop != null);
    expectTrue('经典未配置', back.configOf(DiyThemeTarget.classic) == null);
    expectTrue('空串回退空集合', DiyThemeSet.decode('').isEmpty);
    expectTrue('null 回退空集合', DiyThemeSet.decode(null).isEmpty);

    // ── 2) 脏数据容错 ──
    expectTrue('坏 JSON 回退空集合', DiyThemeSet.decode('{not json!!').isEmpty);
    expectTrue('数组 JSON 回退空集合', DiyThemeSet.decode('[1,2,3]').isEmpty);
    const dirty = '{"glass":{"backdrop":{"base":"linear","colors":["#ZZZZZZ",-5,99999999999,1.5],'
        '"angle":999,"blur":-3,"scrim":99,"animated":"yes",'
        '"layers":[{"kind":"nonsense","x":9,"y":-9,"size":99999,"intensity":5,"density":-2},'
        '{"kind":"glow","x":0.5}],'
        '"button":{"fill":"weird","radius":999,"height":0,"fontWeight":333}}}';
    final s = DiyThemeSet.decode(dirty);
    final cfg = s.configOf(DiyThemeTarget.glass);
    final bd2 = cfg?.backdrop;
    final btn2 = cfg?.button;
    expectTrue('脏 JSON 不全丢', cfg != null);
    expectTrue('非法颜色回退默认', (bd2?.colors.first ?? const Color(0)) == const Color(0xFFEDF2F9));
    expectTrue('角度钳 360', (bd2?.angle ?? 0) == 360);
    expectTrue('blur 钳 0', (bd2?.blur ?? -1) == 0);
    expectTrue('scrim 钳 0.85', (bd2?.scrim ?? 0) == 0.85);
    expectTrue('未知图层回退 glow', bd2?.layers.first.kind == DiyLayerKind.glow);
    expectTrue('图层坐标钳制', bd2?.layers.first.x == 1.5 && bd2!.layers.first.y == -0.5);
    expectTrue('按钮 fill 回退 solid', btn2?.fill == DiyButtonFill.solid);
    expectTrue('按钮字重吸附 400', btn2?.fontWeight == 400);
    expectTrue('按钮高度钳 32', btn2?.height == 32);

    // ── 3) clamp 边界 ──
    final l = DiyLayer.clamped(kind: DiyLayerKind.glow, x: 2, y: -2, size: -50, angle: 999, intensity: 2, density: 50);
    expectTrue('x/y 钳到 [-0.5,1.5]', l.x == 1.5 && l.y == -0.5);
    expectTrue('size 钳 0', l.size == 0);
    expectTrue('angle 钳 360', l.angle == 360);
    expectTrue('intensity 钳 1', l.intensity == 1);
    expectTrue('density 钳 12', l.density == 12);
    final bdA = DiyBackdrop.clamped(colors: List.generate(10, (_) => Colors.red), stops: const [0.5, 0.1, 0.9, 0.3, 1.5]);
    expectTrue('颜色最多 4 个', bdA.colors.length == 4);
    expectTrue('stops 长度不对齐忽略', bdA.stops.isEmpty);
    final bdB = DiyBackdrop.clamped(colors: const [Colors.red, Colors.blue, Colors.green], stops: const [0.5, 0.1, 0.9]);
    expectTrue('stops 归一化首0尾1递增', bdB.stops.first == 0 && bdB.stops.last == 1 && bdB.stops[1] >= bdB.stops[0]);

    // ── 4) 图层增删 / 排序边界 ──
    final bdC = DiyBackdrop.clamped(layers: [
      DiyLayer.defaultOf(DiyLayerKind.glow),
      DiyLayer.defaultOf(DiyLayerKind.grid),
    ]);
    expectTrue('空列表增层', DiyBackdrop.clamped().withLayerAt(0, DiyLayer.defaultOf(DiyLayerKind.glow)).layers.length == 1);
    expectTrue('负索引增层忽略', bdC.withLayerAt(-1, DiyLayer.defaultOf(DiyLayerKind.beam)).layers.length == 2);
    expectTrue('超上限增层忽略', bdC.withLayerAt(99, DiyLayer.defaultOf(DiyLayerKind.beam)).layers.length == 2);
    expectTrue('替换位置 ok', bdC.withLayerAt(1, DiyLayer.defaultOf(DiyLayerKind.beam)).layers[1].kind == DiyLayerKind.beam);
    expectTrue('删除首位', bdC.withoutLayerAt(0).layers.first.kind == DiyLayerKind.grid);
    expectTrue('越界删除忽略', bdC.withoutLayerAt(5).layers.length == 2);
    expectTrue('空列表删除忽略', DiyBackdrop.clamped().withoutLayerAt(0).layers.isEmpty);
    expectTrue('交换 0<->1', bdC.withLayerSwapped(0, 1).layers.first.kind == DiyLayerKind.grid);
    expectTrue('同位置交换忽略', bdC.withLayerSwapped(0, 0).layers.first.kind == DiyLayerKind.glow);
    expectTrue('越界交换忽略', bdC.withLayerSwapped(0, 9).layers.length == 2);
    var full = DiyBackdrop.clamped();
    for (var i = 0; i < 6; i++) {
      full = full.withLayerAt(i, DiyLayer.defaultOf(DiyLayerKind.glow));
    }
    expectTrue('6 层上限', full.layers.length == 6);
    expectTrue('第 7 层被拒', full.withLayerAt(6, DiyLayer.defaultOf(DiyLayerKind.beam)).layers.length == 6);

    // ── 5) 8 预设 × 明暗两版 ──
    for (final p in kDiyPresets) {
      final light = p.build(true);
      final dark = p.build(false);
      expectTrue('预设「${p.label}」明暗可用', light.colors.isNotEmpty && dark.colors.isNotEmpty &&
          light.layers.length <= kDiyMaxLayers && dark.layers.length <= kDiyMaxLayers);
    }
    expectTrue('presetOfKey 命中', presetOfKey('aurora')?.label == '极光');
    expectTrue('presetOfKey 未命中', presetOfKey('nope') == null);

    // ── 6) 颜色解析 ──
    expectTrue('#RRGGBB', diyParseColor('#7C3AED') == const Color(0xFF7C3AED));
    expectTrue('#abc 短格式', diyParseColor('#abc') == const Color(0xFFAABBCC));
    expectTrue('无 # 前缀', diyParseColor('7C3AED') == const Color(0xFF7C3AED));
    expectTrue('十进制', diyParseColor('4286545645') != null);
    expectTrue('中文色名', diyParseColor('天蓝') == const Color(0xFF38BDF8));
    expectTrue('英文色名', diyParseColor('purple') == const Color(0xFF7C3AED));
    expectTrue('非法返回 null', diyParseColor('xyz') == null);
    expectTrue('空串返回 null', diyParseColor('') == null);
    expectTrue('hex 往返', diyParseColor(diyColorToHex(const Color(0xFF38BDF8))) == const Color(0xFF38BDF8));

    // ── 7) 默认背景 / 按钮 ──
    expectTrue('经典默认纯色', defaultBackdropOf(DiyThemeTarget.classic).base == DiyBaseKind.solid);
    expectTrue('深色默认纯色', defaultBackdropOf(DiyThemeTarget.dark).base == DiyBaseKind.solid);
    expectTrue('毛玻璃默认渐变+动效', defaultBackdropOf(DiyThemeTarget.glass).base == DiyBaseKind.linear &&
        defaultBackdropOf(DiyThemeTarget.glass).animated);
    expectTrue('毛玻璃默认按钮 glass', defaultButtonStyleOf(DiyThemeTarget.glass).fill == DiyButtonFill.glass);
    expectTrue('经典默认按钮 solid', defaultButtonStyleOf(DiyThemeTarget.classic).fill == DiyButtonFill.solid);
    expectTrue('深色默认按钮 solid', defaultButtonStyleOf(DiyThemeTarget.dark).fill == DiyButtonFill.solid);
    final auroraLight = presetOfKey('aurora')!.build(true);
    final auroraDark = presetOfKey('aurora')!.build(false);
    expectTrue('极光明暗基座不同', auroraLight.colors.first != auroraDark.colors.first);

    // ── 8) withConfig / without 语义 ──
    var set2 = DiyThemeSet.empty.withConfig(DiyThemeTarget.classic, const DiyThemeConfig(backdrop: DiyBackdrop()));
    expectTrue('配置后已自定义', set2.isCustomized(DiyThemeTarget.classic));
    set2 = set2.withConfig(DiyThemeTarget.classic, null);
    expectTrue('写 null 后未自定义', !set2.isCustomized(DiyThemeTarget.classic));
    set2 = DiyThemeSet.empty.withConfig(DiyThemeTarget.classic, const DiyThemeConfig(backdrop: DiyBackdrop())).without(DiyThemeTarget.classic);
    expectTrue('without 移除主题', !set2.isCustomized(DiyThemeTarget.classic));
    expectTrue('空配置 JSON 不保留', DiyThemeSet.fromJson(const {'classic': {}}).isEmpty);

    // ── 9) 按钮颜色清除语义 ──
    final withColor = DiyButtonStyle.clamped(color: const Color(0xFF22C55E));
    expectTrue('clearColor 后 null', withColor.copyWith(clearColor: true).color == null);
    expectTrue('指定颜色保留', withColor.copyWith(color: const Color(0xFF3B82F6)).color == const Color(0xFF3B82F6));
    expectTrue('clearColor2 后 null', DiyButtonStyle.clamped(color2: const Color(0xFF84CC16)).copyWith(clearColor2: true).color2 == null);
  });
}
