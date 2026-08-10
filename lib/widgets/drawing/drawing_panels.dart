/// 画板工具栏与子面板（与矢量直绘控制器对齐）
///
/// 底部工具栏：返回/画笔/橡皮/油漆桶/吸管/直线/圆形/颜色/笔刷/撤销/重做/保存/导出/更多
/// 弹出面板：颜色选择（预设色板 + HSL 取色器）、笔刷选择（38 种分 5 组 + 粗细/不透明度）
library;

import 'package:flutter/material.dart';
import 'drawing_canvas.dart';
import 'drawing_models.dart';

/// 画板工具栏回调集合
class DrawingToolbarCallbacks {
  final void Function(DrawingTool tool) onToolChanged;
  final VoidCallback? onColorTap;
  final VoidCallback? onBrushTap;
  final VoidCallback? onSymmetryTap;
  final VoidCallback? onFilterTap;
  final VoidCallback? onLayerTap;
  final VoidCallback? onPixelTap;
  final VoidCallback? onPerspectiveTap;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final Future<void> Function() onSave;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final VoidCallback? onBack;
  final VoidCallback onClearAll;
  const DrawingToolbarCallbacks({
    required this.onToolChanged,
    this.onColorTap,
    this.onBrushTap,
    this.onSymmetryTap,
    this.onFilterTap,
    this.onLayerTap,
    this.onPixelTap,
    this.onPerspectiveTap,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
    required this.onExport,
    required this.onImport,
    this.onBack,
    required this.onClearAll,
  });
}

/// 底部工具栏
class DrawingToolbar extends StatelessWidget {
  final DrawingCanvasController controller;
  final DrawingToolbarCallbacks callbacks;
  final bool darkMode;
  const DrawingToolbar({
    super.key,
    required this.controller,
    required this.callbacks,
    required this.darkMode,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final rowColor = darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = darkMode ? Colors.white70 : Colors.black87;
    final activeColor = const Color(0xFF7C3AED);

    Widget toolBtn(IconData icon, DrawingTool t, String tip) {
      final active = c.tool == t;
      return IconButton(
        tooltip: tip,
        icon: Icon(icon, size: 22, color: active ? activeColor : iconColor),
        onPressed: () => callbacks.onToolChanged(t),
      );
    }

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Container(
        height: 56,
        decoration: BoxDecoration(
          color: rowColor,
          border: Border(top: BorderSide(color: darkMode ? Colors.white12 : Colors.black12)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (callbacks.onBack != null)
                IconButton(
                  tooltip: '返回画作列表',
                  icon: Icon(Icons.arrow_back_rounded, color: iconColor),
                  onPressed: callbacks.onBack,
                ),
              toolBtn(Icons.brush_rounded, DrawingTool.brush, '画笔'),
              toolBtn(Icons.auto_fix_high_rounded, DrawingTool.eraser, '橡皮擦'),
              toolBtn(Icons.format_color_fill_rounded, DrawingTool.bucket, '油漆桶'),
              toolBtn(Icons.colorize_rounded, DrawingTool.eyedropper, '吸管'),
              toolBtn(Icons.show_chart_rounded, DrawingTool.line, '直线'),
              toolBtn(Icons.circle_outlined, DrawingTool.circle, '圆形'),
              const VerticalDivider(width: 16),
              // 颜色
              IconButton(
                tooltip: '颜色',
                onPressed: callbacks.onColorTap,
                icon: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: c.color,
                    shape: BoxShape.circle,
                    border: Border.all(color: iconColor.withValues(alpha: 0.5), width: 1.5),
                  ),
                ),
              ),
              // 笔刷
              IconButton(
                tooltip: '笔刷 · ${c.brush.name}',
                icon: Icon(Icons.brush_outlined, color: iconColor),
                onPressed: callbacks.onBrushTap,
              ),
              // 对称
              IconButton(
                tooltip: c.symmetryMode == 'none' ? '对称绘制' : '对称：${c.symmetryMode}',
                icon: Icon(Icons.flip_rounded, color: c.symmetryMode != 'none' ? activeColor : iconColor),
                onPressed: callbacks.onSymmetryTap,
              ),
              // 滤镜
              IconButton(
                tooltip: '滤镜',
                icon: Icon(Icons.auto_fix_normal_rounded, color: iconColor),
                onPressed: callbacks.onFilterTap,
              ),
              const VerticalDivider(width: 16),
              // 图层
              IconButton(
                tooltip: '图层',
                icon: Icon(Icons.layers_rounded, color: c.layers.length > 1 ? activeColor : iconColor),
                onPressed: callbacks.onLayerTap,
              ),
              // 像素模式
              IconButton(
                tooltip: c.pixelMode ? '像素模式：开' : '像素模式',
                icon: Icon(Icons.grid_on_rounded, color: c.pixelMode ? activeColor : iconColor),
                onPressed: callbacks.onPixelTap,
              ),
              // 透视辅助线
              IconButton(
                tooltip: c.showPerspectiveGuides ? '透视辅助线：开' : '透视辅助线',
                icon: Icon(Icons.view_in_ar_rounded, color: c.showPerspectiveGuides ? activeColor : iconColor),
                onPressed: callbacks.onPerspectiveTap,
              ),
              const VerticalDivider(width: 16),
              IconButton(
                tooltip: '撤销 (Ctrl+Z)',
                icon: Icon(Icons.undo_rounded, color: c.canUndo ? iconColor : iconColor.withValues(alpha: 0.3)),
                onPressed: c.canUndo ? callbacks.onUndo : null,
              ),
              IconButton(
                tooltip: '重做 (Ctrl+Y)',
                icon: Icon(Icons.redo_rounded, color: c.canRedo ? iconColor : iconColor.withValues(alpha: 0.3)),
                onPressed: c.canRedo ? callbacks.onRedo : null,
              ),
              const VerticalDivider(width: 16),
              IconButton(
                tooltip: '保存',
                icon: Icon(Icons.save_rounded, color: iconColor),
                onPressed: () => callbacks.onSave(),
              ),
              IconButton(
                tooltip: '导出图片',
                icon: Icon(Icons.download_rounded, color: iconColor),
                onPressed: () => callbacks.onExport(),
              ),
              IconButton(
                tooltip: '导入图片',
                icon: Icon(Icons.upload_rounded, color: iconColor),
                onPressed: () => callbacks.onImport(),
              ),
              IconButton(
                tooltip: '清空画布',
                icon: Icon(Icons.delete_outline_rounded, color: iconColor),
                onPressed: callbacks.onClearAll,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 颜色选择面板
class ColorPanel extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool darkMode;
  const ColorPanel({super.key, required this.controller, required this.darkMode});

  @override
  State<ColorPanel> createState() => _ColorPanelState();
}

class _ColorPanelState extends State<ColorPanel> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bg = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = widget.darkMode ? Colors.white70 : Colors.black87;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.darkMode ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black26)),
          ),
          const SizedBox(width: 10),
          Text('当前颜色', style: TextStyle(fontSize: 13, color: iconColor)),
          const Spacer(),
          IconButton(
            tooltip: '自定义颜色',
            icon: Icon(Icons.color_lens_rounded, color: iconColor, size: 20),
            onPressed: () => _showHslPicker(c),
          ),
        ]),
        const SizedBox(height: 10),
        for (final row in kBasicColors)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              for (final col in row)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      c.setColor(col);
                      setState(() {});
                    },
                    child: Container(
                      height: 26,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: col,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: c.color.toARGB32() == col.toARGB32() ? const Color(0xFF7C3AED) : Colors.black12,
                          width: c.color.toARGB32() == col.toARGB32() ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }

  void _showHslPicker(DrawingCanvasController c) {
    HSVColor hsv = HSVColor.fromColor(c.color);
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('选择颜色'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: hsv.toColor(), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('色相', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: hsv.hue,
                  max: 360,
                  onChanged: (v) => setDialogState(() => hsv = HSVColor.fromAHSV(hsv.alpha, v, hsv.saturation, hsv.value)),
                ),
              ),
            ]),
            Row(children: [
              const Text('饱和', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: hsv.saturation,
                  onChanged: (v) => setDialogState(() => hsv = HSVColor.fromAHSV(hsv.alpha, hsv.hue, v, hsv.value)),
                ),
              ),
            ]),
            Row(children: [
              const Text('明度', style: TextStyle(fontSize: 12)),
              Expanded(
                child: Slider(
                  value: hsv.value,
                  onChanged: (v) => setDialogState(() => hsv = HSVColor.fromAHSV(hsv.alpha, hsv.hue, hsv.saturation, v)),
                ),
              ),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                c.setColor(hsv.toColor());
                setState(() {});
                Navigator.pop(dialogCtx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 笔刷选择面板（38 种分 5 组）
class BrushPanel extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool darkMode;
  const BrushPanel({super.key, required this.controller, required this.darkMode});

  @override
  State<BrushPanel> createState() => _BrushPanelState();
}

class _BrushPanelState extends State<BrushPanel> {
  BrushGroup _group = BrushGroup.paint;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bg = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = widget.darkMode ? Colors.white70 : Colors.black87;
    final brushes = DrawingBrush.all.where((b) => b.group == _group).toList();

    return Container(
      width: 340,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.darkMode ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (final g in kBrushGroups)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(g.name, style: const TextStyle(fontSize: 12)),
                selected: _group == g.group,
                onSelected: (_) => setState(() => _group = g.group),
                selectedColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                checkmarkColor: const Color(0xFF7C3AED),
                backgroundColor: widget.darkMode ? const Color(0xFF2A2A32) : const Color(0xFFF1F5F9),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final b in brushes)
            GestureDetector(
              onTap: () {
                c.setBrush(b);
                setState(() {});
              },
              child: Container(
                width: 66,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: c.brush.id == b.id
                      ? const Color(0xFF7C3AED).withValues(alpha: 0.15)
                      : (widget.darkMode ? const Color(0xFF2A2A32) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.brush.id == b.id ? const Color(0xFF7C3AED) : Colors.transparent),
                ),
                child: Column(children: [
                  Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: b.opacity),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(b.name, style: TextStyle(fontSize: 10, color: iconColor), overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Icon(Icons.line_weight, size: 18, color: iconColor),
          Expanded(
            child: Slider(
              value: c.lineWidth.clamp(1.0, 60.0).toDouble(),
              min: 1,
              max: 60,
              onChanged: (v) {
                c.setLineWidth(v);
                setState(() {});
              },
            ),
          ),
          SizedBox(width: 30, child: Text('${c.lineWidth.round()}', style: TextStyle(fontSize: 12, color: iconColor))),
        ]),
        Row(children: [
          Icon(Icons.opacity, size: 18, color: iconColor),
          Expanded(
            child: Slider(
              value: c.brushOpacity.clamp(0.05, 1.0).toDouble(),
              min: 0.05,
              max: 1,
              onChanged: (v) {
                c.setBrushOpacity(v);
                setState(() {});
              },
            ),
          ),
          SizedBox(width: 36, child: Text('${(c.brushOpacity * 100).round()}%', style: TextStyle(fontSize: 12, color: iconColor))),
        ]),
      ]),
    );
  }
}

/// 对称绘制面板
class SymmetryPanel extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool darkMode;
  const SymmetryPanel({super.key, required this.controller, required this.darkMode});

  @override
  State<SymmetryPanel> createState() => _SymmetryPanelState();
}

class _SymmetryPanelState extends State<SymmetryPanel> {
  static const _modes = [
    ('none', '无'),
    ('h', '水平镜像'),
    ('v', '垂直镜像'),
    ('quad', '四象限'),
    ('hex', '六向'),
    ('oct', '八向'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bg = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = widget.darkMode ? Colors.white70 : Colors.black87;
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.darkMode ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('对称绘制', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: iconColor)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (key, label) in _modes)
            ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: c.symmetryMode == key,
              onSelected: (_) {
                c.setSymmetryMode(key);
                setState(() {});
              },
              selectedColor: const Color(0xFF7C3AED).withValues(alpha: 0.15),
              checkmarkColor: const Color(0xFF7C3AED),
              backgroundColor: widget.darkMode ? const Color(0xFF2A2A32) : const Color(0xFFF1F5F9),
            ),
        ]),
        const SizedBox(height: 8),
        Text('开启后，每一笔会自动镜像复制到对应位置。', style: TextStyle(fontSize: 11, color: iconColor.withValues(alpha: 0.7))),
      ]),
    );
  }
}

/// 滤镜面板（应用于整幅画面）
class FilterPanel extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool darkMode;
  const FilterPanel({super.key, required this.controller, required this.darkMode});

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final f = c.filter;
    final bg = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = widget.darkMode ? Colors.white70 : Colors.black87;

    Widget slider(String label, double value, double max, ValueChanged<double> onChange) {
      return Row(children: [
        SizedBox(width: 56, child: Text(label, style: TextStyle(fontSize: 12, color: iconColor))),
        Expanded(child: Slider(value: value.clamp(0.0, max).toDouble(), max: max, onChanged: onChange)),
        SizedBox(width: 36, child: Text('${value.round()}', style: TextStyle(fontSize: 11, color: iconColor))),
      ]);
    }

    return Container(
      width: 320,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.darkMode ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('滤镜（应用于整幅画面）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: iconColor)),
        const SizedBox(height: 6),
        slider('模糊', f.blur, 30, (v) => setState(() => f.blur = v)),
        slider('亮度', f.brightness, 200, (v) => setState(() => f.brightness = v)),
        slider('对比度', f.contrast, 200, (v) => setState(() => f.contrast = v)),
        slider('饱和度', f.saturate, 200, (v) => setState(() => f.saturate = v)),
        slider('色相', f.hueRotate, 360, (v) => setState(() => f.hueRotate = v)),
        slider('灰度', f.grayscale, 100, (v) => setState(() => f.grayscale = v)),
        slider('反色', f.invert, 100, (v) => setState(() => f.invert = v)),
        slider('怀旧', f.sepia, 100, (v) => setState(() => f.sepia = v)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _applying
                  ? null
                  : () async {
                      setState(() => _applying = true);
                      await c.applyFilter(f);
                      if (mounted) setState(() => _applying = false);
                    },
              child: _applying
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('应用滤镜'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() {
                f.blur = 0;
                f.brightness = 100;
                f.contrast = 100;
                f.saturate = 100;
                f.hueRotate = 0;
                f.grayscale = 0;
                f.invert = 0;
                f.sepia = 0;
              }),
              child: const Text('重置'),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// 图层面板：图层列表 + 增删/可见/透明度/混合模式/锁定/排序
class LayerPanel extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool darkMode;
  const LayerPanel({super.key, required this.controller, required this.darkMode});

  @override
  State<LayerPanel> createState() => _LayerPanelState();
}

class _LayerPanelState extends State<LayerPanel> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bg = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = widget.darkMode ? Colors.white70 : Colors.black87;
    final subColor = widget.darkMode ? Colors.white38 : Colors.black38;
    final itemBg = widget.darkMode ? const Color(0xFF2A2A32) : const Color(0xFFF1F5F9);
    // 图层倒序显示（上层在前）
    final layers = List.of(c.layers).reversed.toList();

    return Container(
      width: 300,
      constraints: const BoxConstraints(maxHeight: 420),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.darkMode ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('图层', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: iconColor)),
          const Spacer(),
          IconButton(
            tooltip: '新建图层',
            icon: Icon(Icons.add_rounded, color: iconColor, size: 20),
            onPressed: () {
              c.addLayer();
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 4),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: layers.length,
            itemBuilder: (ctx, i) {
              final layer = layers[i];
              final isActive = layer.id == c.activeLayer?.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF7C3AED).withValues(alpha: 0.12) : itemBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive ? const Color(0xFF7C3AED) : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    // 可见性
                    IconButton(
                      tooltip: layer.visible ? '隐藏图层' : '显示图层',
                      icon: Icon(
                        layer.visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        size: 18,
                        color: layer.visible ? iconColor : subColor,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () {
                        c.setLayerVisible(layer.id, !layer.visible);
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 4),
                    // 锁定
                    IconButton(
                      tooltip: layer.locked ? '解锁图层' : '锁定图层',
                      icon: Icon(
                        layer.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        size: 18,
                        color: layer.locked ? iconColor : subColor,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                      onPressed: () {
                        c.setLayerLocked(layer.id, !layer.locked);
                        setState(() {});
                      },
                    ),
                    const SizedBox(width: 6),
                    // 名称
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          c.setActiveLayer(layer.id);
                          setState(() {});
                        },
                        child: Text(
                          layer.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                            color: iconColor,
                          ),
                        ),
                      ),
                    ),
                    // 上移/下移
                    IconButton(
                      tooltip: '上移',
                      icon: Icon(Icons.arrow_upward_rounded, size: 16, color: subColor),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: i > 0
                          ? () {
                              c.moveLayer(layer.id, 1);
                              setState(() {});
                            }
                          : null,
                    ),
                    IconButton(
                      tooltip: '下移',
                      icon: Icon(Icons.arrow_downward_rounded, size: 16, color: subColor),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: i < layers.length - 1
                          ? () {
                              c.moveLayer(layer.id, -1);
                              setState(() {});
                            }
                          : null,
                    ),
                    // 删除
                    IconButton(
                      tooltip: '删除图层',
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                      onPressed: c.layers.length > 1
                          ? () {
                              c.removeLayer(layer.id);
                              setState(() {});
                            }
                          : null,
                    ),
                  ]),
                  const SizedBox(height: 4),
                  // 不透明度滑块
                  Row(children: [
                    Icon(Icons.opacity, size: 14, color: subColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Slider(
                        value: layer.opacity.clamp(0.0, 1.0).toDouble(),
                        min: 0,
                        max: 1,
                        onChanged: (v) {
                          c.setLayerOpacity(layer.id, v);
                          setState(() {});
                        },
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text('${(layer.opacity * 100).round()}%', style: TextStyle(fontSize: 11, color: subColor)),
                    ),
                  ]),
                  // 混合模式
                  Row(children: [
                    Icon(Icons.layers_rounded, size: 14, color: subColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: layer.blendMode,
                        style: TextStyle(fontSize: 12, color: iconColor),
                        dropdownColor: bg,
                        items: kBlendModes
                            .map((b) => DropdownMenuItem(value: b.value, child: Text(b.label)))
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          c.setLayerBlendMode(layer.id, v);
                          setState(() {});
                        },
                      ),
                    ),
                  ]),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// 像素模式面板：开关 + 网格大小
class PixelModePanel extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool darkMode;
  const PixelModePanel({super.key, required this.controller, required this.darkMode});

  @override
  State<PixelModePanel> createState() => _PixelModePanelState();
}

class _PixelModePanelState extends State<PixelModePanel> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bg = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = widget.darkMode ? Colors.white70 : Colors.black87;
    final subColor = widget.darkMode ? Colors.white38 : Colors.black38;

    return Container(
      width: 260,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.darkMode ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('像素模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: iconColor)),
          const Spacer(),
          Switch(
            value: c.pixelMode,
            onChanged: (v) {
              c.setPixelMode(v);
              setState(() {});
            },
          ),
        ]),
        if (c.pixelMode) ...[
          Row(children: [
            Icon(Icons.grid_on_rounded, size: 16, color: subColor),
            const SizedBox(width: 4),
            Expanded(
              child: Slider(
                value: c.pixelGridSize.toDouble(),
                min: 4,
                max: 128,
                onChanged: (v) {
                  c.setPixelGridSize(v.round());
                  setState(() {});
                },
              ),
            ),
            SizedBox(width: 40, child: Text('${c.pixelGridSize}px', style: TextStyle(fontSize: 11, color: subColor))),
          ]),
          Text('笔迹自动吸附到网格，呈现像素画效果。', style: TextStyle(fontSize: 11, color: subColor)),
        ] else ...[
          Text('开启后笔迹吸附网格，画像素画。', style: TextStyle(fontSize: 11, color: subColor)),
        ],
      ]),
    );
  }
}

/// 透视辅助线面板：开关 + 快速放置消失点（左/中/右预设位置）+ 清除
class PerspectivePanel extends StatefulWidget {
  final DrawingCanvasController controller;
  final bool darkMode;
  const PerspectivePanel({super.key, required this.controller, required this.darkMode});

  @override
  State<PerspectivePanel> createState() => _PerspectivePanelState();
}

class _PerspectivePanelState extends State<PerspectivePanel> {
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final bg = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final iconColor = widget.darkMode ? Colors.white70 : Colors.black87;
    final subColor = widget.darkMode ? Colors.white38 : Colors.black38;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: widget.darkMode ? Colors.white12 : Colors.black12),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('透视辅助线', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: iconColor)),
          const Spacer(),
          Switch(
            value: c.showPerspectiveGuides,
            onChanged: (v) {
              c.setPerspectiveGuides(v);
              setState(() {});
            },
          ),
        ]),
        if (c.showPerspectiveGuides) ...[
          Text('消失点 (${c.perspectivePoints.length}/3)', style: TextStyle(fontSize: 12, color: subColor)),
          const SizedBox(height: 6),
          // 快速放置：一点透视（中央）
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  c.clearPerspectivePoints();
                  c.addPerspectivePoint(Offset(c.width / 2, c.height / 2));
                  setState(() {});
                },
                child: const Text('一点透视', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  c.clearPerspectivePoints();
                  c.addPerspectivePoint(Offset(c.width * 0.1, c.height / 2));
                  c.addPerspectivePoint(Offset(c.width * 0.9, c.height / 2));
                  setState(() {});
                },
                child: const Text('两点透视', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  c.clearPerspectivePoints();
                  c.addPerspectivePoint(Offset(c.width * 0.1, c.height / 2));
                  c.addPerspectivePoint(Offset(c.width * 0.9, c.height / 2));
                  c.addPerspectivePoint(Offset(c.width / 2, c.height * 0.1));
                  setState(() {});
                },
                child: const Text('三点透视', style: TextStyle(fontSize: 12)),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  c.clearPerspectivePoints();
                  setState(() {});
                },
                child: const Text('清除消失点'),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 6),
        Text('消失点用于辅助绘制有透视感的画面（一点/两点/三点透视）。',
            style: TextStyle(fontSize: 11, color: subColor)),
      ]),
    );
  }
}