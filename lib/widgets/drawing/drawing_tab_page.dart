/// 画板主页面（对应参考项目 DrawingTab.jsx）
///
/// 集成：画布显示、手势绘制、工具栏、颜色/笔刷面板、
/// 保存/导入/导出、自动保存、返回画作列表。
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, HardwareKeyboard, KeyDownEvent;
import 'package:path_provider/path_provider.dart';
import 'drawing_canvas.dart';
import 'drawing_canvas_view.dart';
import 'drawing_models.dart';
import 'drawing_panels.dart';
import 'drawing_storage.dart';
import 'drawing_workspace_page.dart' show pickAndDecodeImage;

class DrawingTabPage extends StatefulWidget {
  final int width;
  final int height;
  final String? initialDataUrl; // 恢复已有画作
  final VoidCallback? onBack;
  final bool darkMode;
  const DrawingTabPage({
    super.key,
    required this.width,
    required this.height,
    this.initialDataUrl,
    this.onBack,
    required this.darkMode,
  });

  @override
  State<DrawingTabPage> createState() => DrawingTabPageState();
}

class DrawingTabPageState extends State<DrawingTabPage> {
  late DrawingCanvasController _controller;
  bool _showBrushPanel = false;
  bool _showColorPanel = false;
  bool _showSymmetryPanel = false;
  bool _showFilterPanel = false;
  bool _showLayerPanel = false;
  bool _showPixelPanel = false;
  bool _showPerspectivePanel = false;
  final FocusNode _focusNode = FocusNode();
  Timer? _autosaveDebounce;

  void _closeAllPanels() {
    _showBrushPanel = false;
    _showColorPanel = false;
    _showSymmetryPanel = false;
    _showFilterPanel = false;
    _showLayerPanel = false;
    _showPixelPanel = false;
    _showPerspectivePanel = false;
  }

  @override
  void initState() {
    super.initState();
    _controller = DrawingCanvasController(width: widget.width, height: widget.height);
    _controller.onAutosave = _autosave;
    // 恢复已有画作
    if (widget.initialDataUrl != null && widget.initialDataUrl!.isNotEmpty) {
      _controller.restoreFromDataUrl(widget.initialDataUrl!);
    }
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ==================== 手势（画布坐标） ====================
  /// 指针按下：绘制类工具立即起笔（不等手势阈值，保证起笔不丢点）；
  /// 油漆桶/吸管留给 onTap 处理，避免点击时双重触发。
  void _onPanDown(Offset p) {
    switch (_controller.tool) {
      case DrawingTool.bucket:
      case DrawingTool.eyedropper:
        return;
      default:
        _controller.beginStroke(p);
    }
  }

  void _onPanStart(Offset p) {
    // beginStroke 已在 onPanDown 处理；此处只需延伸当前笔迹
    if (_controller.isDrawing) {
      _controller.extendStroke(p);
    }
  }

  void _onPanUpdate(Offset p) {
    _controller.extendStroke(p);
  }

  void _onPanEnd() {
    _controller.endStroke();
  }

  void _onPanCancel() {
    _controller.cancelStroke();
  }

  void _onTap(Offset p) {
    switch (_controller.tool) {
      case DrawingTool.bucket:
        _controller.floodFill(p, _controller.color);
        break;
      case DrawingTool.eyedropper:
        _pickColor(p);
        break;
      default:
        if (_controller.isDrawing) {
          // onPanDown 已起笔（livePoints 里已有该点），
          // 结束这一笔即可，切勿再提交新笔，否则点一下出两条重影。
          _controller.endStroke();
        } else {
          // panDown 未触发的场景（部分手势/测试环境），正常提交单点。
          _controller.tapStroke(p);
        }
    }
  }

  Future<void> _pickColor(Offset p) async {
    final c = await _controller.eyedrop(p);
    if (c != null && !_controller.disposed) {
      _controller.setColor(c);
      if (mounted) setState(() {});
    }
  }

  // ==================== 保存 ====================
  Future<void> _saveSession() async {
    if (_controller.disposed) return;
    final dataUrl = await _controller.exportPngDataUrl();
    if (dataUrl.isEmpty || _controller.disposed) return;
    await DrawingStorage.saveSessionCanvas(dataUrl);
    await DrawingStorage.saveSessionCanvasWidth(_controller.width);
    await DrawingStorage.saveSessionCanvasHeight(_controller.height);
  }

  Future<void> _autosave() async {
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(seconds: 2), () {
      if (mounted && !_controller.disposed) _saveSession();
    });
  }

  Future<void> _manualSave() async {
    final dataUrl = await _controller.exportPngDataUrl();
    if (dataUrl.isEmpty || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败'), behavior: SnackBarBehavior.floating));
      return;
    }
    final saved = DrawingStorage.loadSavedCanvases();
    saved.insert(0, DrawingArtwork(
      id: 'saved_${DateTime.now().millisecondsSinceEpoch}',
      name: '画作 ${saved.length + 1}',
      w: _controller.width,
      h: _controller.height,
      dataUrl: dataUrl,
      thumbnail: dataUrl,
      date: _nowStr(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSaved: true,
    ));
    if (saved.length > 30) saved.removeRange(30, saved.length);
    await DrawingStorage.saveSavedCanvases(saved);
    await _saveSession();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到画作库'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _exportImage() async {
    final bytes = await _controller.exportPng();
    if (bytes == null || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导出失败'), behavior: SnackBarBehavior.floating));
      return;
    }
    try {
      final dir = await _downloadsDir();
      if (dir == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取下载目录'), behavior: SnackBarBehavior.floating));
        return;
      }
      final file = File('${dir.path}/画板_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出到 ${file.path}'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导出失败'), behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _importImage() async {
    final img = await pickAndDecodeImage();
    if (img == null || _controller.disposed) return;
    await _controller.importImageToLayer(img);
    img.dispose();
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final panelColor = widget.darkMode ? const Color(0xFF1F1F26) : Colors.white;
    final textColor = widget.darkMode ? Colors.white : Colors.black87;
    final subColor = widget.darkMode ? Colors.white54 : Colors.grey;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.keyZ && HardwareKeyboard.instance.isControlPressed) {
              c.undo();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyY && HardwareKeyboard.instance.isControlPressed) {
              c.redo();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              setState(() {
                _showBrushPanel = false;
                _showColorPanel = false;
                _showSymmetryPanel = false;
                _showFilterPanel = false;
              });
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Column(children: [
          // 顶部状态栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: panelColor,
              border: Border(bottom: BorderSide(color: widget.darkMode ? Colors.white12 : Colors.black12)),
            ),
            child: ListenableBuilder(
              listenable: c,
              builder: (context, _) => Row(children: [
                Icon(Icons.brush_rounded, size: 18, color: subColor),
                const SizedBox(width: 8),
                Text('画板', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textColor)),
                const SizedBox(width: 12),
                Text('${c.width}×${c.height}', style: TextStyle(fontSize: 12, color: subColor)),
                const Spacer(),
                // 当前颜色/笔刷指示
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(5), border: Border.all(color: widget.darkMode ? Colors.white24 : Colors.black26)),
                ),
                const SizedBox(width: 8),
                Text(c.brush.name, style: TextStyle(fontSize: 12, color: textColor)),
                const SizedBox(width: 12),
                Text('粗细 ${c.lineWidth.round()}', style: TextStyle(fontSize: 12, color: subColor)),
              ]),
            ),
          ),
          // 画布区
          Expanded(
            child: Stack(children: [
              // 画布
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DrawingCanvasView(
                    controller: c,
                    onTap: _onTap,
                    onPanDown: _onPanDown,
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    onPanCancel: _onPanCancel,
                  ),
                ),
              ),
              // 弹出面板
              if (_showColorPanel)
                Positioned(left: 16, bottom: 12,
                  child: ColorPanel(controller: c, darkMode: widget.darkMode)),
              if (_showBrushPanel)
                Positioned(left: 16, bottom: 12,
                  child: BrushPanel(controller: c, darkMode: widget.darkMode)),
              if (_showSymmetryPanel)
                Positioned(right: 16, bottom: 12,
                  child: SymmetryPanel(controller: c, darkMode: widget.darkMode)),
              if (_showFilterPanel)
                Positioned(right: 16, bottom: 12,
                  child: FilterPanel(controller: c, darkMode: widget.darkMode)),
              if (_showLayerPanel)
                Positioned(right: 16, top: 12,
                  child: LayerPanel(controller: c, darkMode: widget.darkMode)),
              if (_showPixelPanel)
                Positioned(left: 16, bottom: 12,
                  child: PixelModePanel(controller: c, darkMode: widget.darkMode)),
              if (_showPerspectivePanel)
                Positioned(right: 16, bottom: 12,
                  child: PerspectivePanel(controller: c, darkMode: widget.darkMode)),
            ]),
          ),
          // 工具栏
          DrawingToolbar(
            controller: c,
            darkMode: widget.darkMode,
            callbacks: DrawingToolbarCallbacks(
              onToolChanged: (t) {
                setState(() {
                  c.tool = t;
                  _closeAllPanels();
                });
              },
              onColorTap: () => setState(() {
                final on = !_showColorPanel;
                _closeAllPanels();
                _showColorPanel = on;
              }),
              onBrushTap: () => setState(() {
                final on = !_showBrushPanel;
                _closeAllPanels();
                _showBrushPanel = on;
              }),
              onSymmetryTap: () => setState(() {
                final on = !_showSymmetryPanel;
                _closeAllPanels();
                _showSymmetryPanel = on;
              }),
              onFilterTap: () => setState(() {
                final on = !_showFilterPanel;
                _closeAllPanels();
                _showFilterPanel = on;
              }),
              onLayerTap: () => setState(() {
                final on = !_showLayerPanel;
                _closeAllPanels();
                _showLayerPanel = on;
              }),
              onPixelTap: () => setState(() {
                final on = !_showPixelPanel;
                _closeAllPanels();
                _showPixelPanel = on;
              }),
              onPerspectiveTap: () => setState(() {
                final on = !_showPerspectivePanel;
                _closeAllPanels();
                _showPerspectivePanel = on;
              }),
              onUndo: () => c.undo(),
              onRedo: () => c.redo(),
              onSave: _manualSave,
              onExport: _exportImage,
              onImport: _importImage,
              onBack: widget.onBack,
              onClearAll: () => _confirmClear(),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空画布'),
        content: const Text('确定清空画布上的所有内容吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok == true && !_controller.disposed) {
      await _controller.clearAll();
    }
  }

  String _nowStr() {
    final d = DateTime.now();
    String pad(int n) => n < 10 ? '0$n' : '$n';
    return '${d.month}月${d.day}日 ${pad(d.hour)}:${pad(d.minute)}';
  }

  /// 获取下载目录。path_provider 的 getDownloadsDirectory 在 Windows 上
  /// 返回 null，需回退到 %USERPROFILE%\Downloads。
  Future<Directory?> _downloadsDir() async {
    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    } catch (_) {}
    // Windows / 其他平台回退
    final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return null;
    final dir = Directory('$home${Platform.pathSeparator}Downloads');
    if (dir.existsSync()) return dir;
    // 目录不存在时尝试应用支持目录
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }
}