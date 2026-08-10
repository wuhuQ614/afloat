/// 画板功能页：封装「画作列表 ↔ 画板」两级切换
///
/// 流程：
/// - 若有已保存画作或未保存会话 → 进入 DrawingWorkspace（画作列表），
///   点新建/打开画作后进入 DrawingTab（绘画），返回时回到列表。
/// - 若什么都没有 → 直接进入一张 1920×1080 新画布，
///   保证用户一进来就能看到画布并绘制（工具栏可返回列表）。
library;

import 'package:flutter/material.dart';
import 'drawing_workspace_page.dart';
import 'drawing_tab_page.dart';
import 'drawing_storage.dart';

class DrawingFeaturePage extends StatefulWidget {
  final bool darkMode;
  const DrawingFeaturePage({super.key, required this.darkMode});

  @override
  State<DrawingFeaturePage> createState() => _DrawingFeaturePageState();
}

class _DrawingFeaturePageState extends State<DrawingFeaturePage> {
  // 当前画布状态
  int _canvasW = 1920;
  int _canvasH = 1080;
  String? _initialDataUrl;
  bool _inDrawing = false;
  // 存储初始化完成前不渲染内容，避免同步读取拿到空值导致误判
  bool _storageReady = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 关键：先异步初始化存储，再决定进入列表还是画布。
    // 若直接同步读取，进程首次进入时必然为空，会把有画作的用户误判为"无画作"。
    await DrawingStorage.init();
    if (!mounted) return;
    setState(() {
      _inDrawing = _shouldAutoEnterCanvas();
      _storageReady = true;
    });
  }

  bool _shouldAutoEnterCanvas() {
    try {
      final hasArtwork = DrawingStorage.loadArtworks().isNotEmpty ||
          DrawingStorage.loadSavedCanvases().isNotEmpty;
      final session = DrawingStorage.loadSessionCanvas();
      final hasSession = session != null && session.startsWith('data:image');
      return !hasArtwork && !hasSession;
    } catch (_) {
      return true;
    }
  }

  void _enterDrawing(int w, int h, {String? dataUrl}) {
    setState(() {
      _canvasW = w;
      _canvasH = h;
      _initialDataUrl = dataUrl;
      _inDrawing = true;
    });
  }

  void _backToList() {
    setState(() => _inDrawing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_storageReady) {
      // 存储初始化中，显示加载占位，避免误判入口
      return const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    if (_inDrawing) {
      return DrawingTabPage(
        width: _canvasW,
        height: _canvasH,
        initialDataUrl: _initialDataUrl,
        onBack: _backToList,
        darkMode: widget.darkMode,
      );
    }
    return DrawingWorkspacePage(
      onNewCanvas: (w, h) => _enterDrawing(w, h),
      onOpenArtwork: (art) => _enterDrawing(art.w > 0 ? art.w : 1920, art.h > 0 ? art.h : 1080, dataUrl: art.dataUrl),
      onClose: null,
      onRecoverSession: (art) => _enterDrawing(art.w > 0 ? art.w : 1920, art.h > 0 ? art.h : 1080, dataUrl: art.dataUrl),
      darkMode: widget.darkMode,
    );
  }
}