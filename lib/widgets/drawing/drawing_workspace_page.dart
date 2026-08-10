/// 画作管理器（对应参考项目 DrawingWorkspace.jsx）
///
/// 提供：全部画作/历史保存/自动保存 三标签列表、新建画布(8预设+自定义)、
/// 恢复未保存画作、删除作品、导入图片。
library;

import 'dart:convert' show Base64Codec;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'drawing_models.dart';
import 'drawing_storage.dart';

/// 新建画布回调：返回所选尺寸
typedef NewCanvasCallback = void Function(int w, int h);
/// 打开画作回调
typedef OpenArtworkCallback = void Function(DrawingArtwork art);

class DrawingWorkspacePage extends StatefulWidget {
  final NewCanvasCallback onNewCanvas;
  final OpenArtworkCallback onOpenArtwork;
  final VoidCallback? onClose;
  final void Function(DrawingArtwork art)? onRecoverSession;
  final bool darkMode;
  const DrawingWorkspacePage({
    super.key,
    required this.onNewCanvas,
    required this.onOpenArtwork,
    this.onClose,
    this.onRecoverSession,
    required this.darkMode,
  });

  @override
  State<DrawingWorkspacePage> createState() => _DrawingWorkspacePageState();
}

class _DrawingWorkspacePageState extends State<DrawingWorkspacePage> {
  String _tab = 'all';
  bool _showSizeDialog = false;
  final TextEditingController _customW = TextEditingController(text: '1920');
  final TextEditingController _customH = TextEditingController(text: '1080');

  List<DrawingArtwork> _loadAll() {
    final all = <DrawingArtwork>[];
    final seenData = <String>{};
    void add(DrawingArtwork a) {
      if (a.dataUrl != null && seenData.contains(a.dataUrl)) return;
      if (a.dataUrl != null) seenData.add(a.dataUrl!);
      all.add(a);
    }
    DrawingStorage.loadArtworks().forEach(add);
    DrawingStorage.loadSavedCanvases().forEach(add);
    DrawingStorage.loadAutoSaveHistory().forEach(add);
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all.take(80).toList();
  }

  List<DrawingArtwork> _filtered(List<DrawingArtwork> all) {
    if (_tab == 'saved') return all.where((a) => a.isSaved).toList();
    if (_tab == 'auto') return all.where((a) => a.isAutoSave).toList();
    return all.where((a) => !a.isSaved && !a.isAutoSave).toList();
  }

  void _delete(DrawingArtwork a) {
    if (a.isSaved) {
      final list = DrawingStorage.loadSavedCanvases()
          .where((x) => x.date != a.date)
          .toList();
      DrawingStorage.saveSavedCanvases(list);
    } else if (a.isAutoSave) {
      final list = DrawingStorage.loadAutoSaveHistory()
          .where((x) => x.date != a.date && x.timestamp != a.timestamp)
          .toList();
      DrawingStorage.saveAutoSaveHistory(list);
    } else {
      final list = DrawingStorage.loadArtworks()
          .where((x) => x.id != a.id)
          .toList();
      DrawingStorage.saveArtworks(list);
    }
    setState(() {});
  }

  bool get _hasSession {
    final d = DrawingStorage.loadSessionCanvas();
    return d != null && d.isNotEmpty && d.startsWith('data:image');
  }

  @override
  Widget build(BuildContext context) {
    final all = _loadAll();
    final filtered = _filtered(all);
    final savedCount = all.where((a) => a.isSaved).length;
    final autoCount = all.where((a) => a.isAutoSave).length;
    final mainCount = all.length - savedCount - autoCount;
    final bg = widget.darkMode ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final cardBg = widget.darkMode ? const Color(0xFF1F2937) : Colors.white;
    final textColor = widget.darkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final subColor = widget.darkMode ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        Positioned.fill(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 顶部
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                if (widget.onClose != null)
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: textColor),
                    onPressed: widget.onClose,
                  ),
                Text(
                  _tab == 'all' ? '我的画作' : (_tab == 'saved' ? '历史保存' : '自动保存'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                ),
                const Spacer(),
                Text('${filtered.length} 幅', style: TextStyle(fontSize: 12, color: subColor)),
              ]),
            ),
            // 标签
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xFF1F2937) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  _tabBtn('all', '全部画作 ($mainCount)'),
                  _tabBtn('saved', '历史保存 ($savedCount)'),
                  _tabBtn('auto', '自动保存 ($autoCount)'),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            // 恢复未保存画作
            if (_hasSession && widget.onRecoverSession != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: GestureDetector(
                  onTap: () {
                    final data = DrawingStorage.loadSessionCanvas();
                    final w = int.tryParse(DrawingStorage.loadSessionCanvasWidth() ?? '') ?? 1920;
                    final h = int.tryParse(DrawingStorage.loadSessionCanvasHeight() ?? '') ?? 1080;
                    widget.onRecoverSession!(DrawingArtwork(
                      id: 'recover_session',
                      name: '恢复的画作',
                      w: w,
                      h: h,
                      dataUrl: data,
                      thumbnail: data,
                      date: '刚刚',
                      timestamp: DateTime.now().millisecondsSinceEpoch,
                    ));
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: const Color(0xFF6366F1).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.restore_rounded, color: Color(0xFF818CF8), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('恢复未保存的画作', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFA5B4FC))),
                          const SizedBox(height: 2),
                          Text('上次退出前未保存的内容', style: TextStyle(fontSize: 10, color: subColor)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: const Color(0xFF818CF8)),
                    ]),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            // 画作列表
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.image_outlined, size: 64, color: subColor.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(_tab == 'all' ? '还没有作品' : (_tab == 'saved' ? '暂无历史保存' : '暂无自动保存'),
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: subColor)),
                        const SizedBox(height: 4),
                        Text(_tab == 'all' ? '点击右下角 + 创建新画布' : '切换标签查看其他画作',
                            style: TextStyle(fontSize: 12, color: subColor)),
                      ]),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 1.4,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final art = filtered[i];
                        return _ArtworkCard(
                          art: art,
                          cardBg: cardBg,
                          textColor: textColor,
                          subColor: subColor,
                          darkMode: widget.darkMode,
                          onTap: () => widget.onOpenArtwork(art),
                          onDelete: () => _delete(art),
                        );
                      },
                    ),
            ),
          ]),
        ),
        // 右下角新建按钮
        Positioned(
          right: 24,
          bottom: 24,
          child: GestureDetector(
            onTap: () => setState(() => _showSizeDialog = true),
            child: Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
            ),
          ),
        ),
        // 新建画布对话框
        if (_showSizeDialog)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _showSizeDialog = false),
              child: Container(color: Colors.black54),
            ),
          ),
        if (_showSizeDialog)
          Center(
            child: Container(
              width: 380,
              constraints: const BoxConstraints(maxHeight: 500),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: widget.darkMode ? const Color(0xFF1F2937) : Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _buildSizeDialog(cardBg, textColor, subColor),
            ),
          ),
      ]),
    );
  }

  Widget _tabBtn(String key, String label) {
    final active = _tab == key;
    final bg = widget.darkMode ? const Color(0xFF1F2937) : Colors.white;
    final activeColor = widget.darkMode ? const Color(0xFFE0E7FF) : const Color(0xFF4F46E5);
    final subColor = widget.darkMode ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? bg : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3)] : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: active ? activeColor : subColor),
          ),
        ),
      ),
    );
  }

  Widget _buildSizeDialog(Color cardBg, Color textColor, Color subColor) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('新建画布', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
        const Spacer(),
        IconButton(
          icon: Icon(Icons.close_rounded, color: subColor),
          onPressed: () => setState(() => _showSizeDialog = false),
        ),
      ]),
      const SizedBox(height: 8),
      // 预设
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.6,
        children: [
          for (final p in kCanvasPresets)
            GestureDetector(
              onTap: () {
                widget.onNewCanvas(p.w, p.h);
                setState(() => _showSizeDialog = false);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: widget.darkMode ? const Color(0xFF374151) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(p.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
                  const SizedBox(height: 2),
                  Text('${p.w}×${p.h}', style: TextStyle(fontSize: 10, color: subColor)),
                ]),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      // 自定义尺寸
      Row(children: [
        Expanded(
          child: TextField(
            controller: _customW,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 14, color: textColor),
            decoration: InputDecoration(
              hintText: '宽',
              filled: true,
              fillColor: widget.darkMode ? const Color(0xFF374151) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('×', style: TextStyle(fontSize: 18, color: subColor)),
        ),
        Expanded(
          child: TextField(
            controller: _customH,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: 14, color: textColor),
            decoration: InputDecoration(
              hintText: '高',
              filled: true,
              fillColor: widget.darkMode ? const Color(0xFF374151) : const Color(0xFFF1F5F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () {
            final w = (int.tryParse(_customW.text) ?? 1920).clamp(1, 8192);
            final h = (int.tryParse(_customH.text) ?? 1080).clamp(1, 8192);
            widget.onNewCanvas(w, h);
            setState(() => _showSizeDialog = false);
          },
          child: const Text('使用自定义尺寸'),
        ),
      ),
    ]);
  }
}

/// 单个画作卡片
class _ArtworkCard extends StatelessWidget {
  final DrawingArtwork art;
  final Color cardBg;
  final Color textColor;
  final Color subColor;
  final bool darkMode;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ArtworkCard({
    required this.art,
    required this.cardBg,
    required this.textColor,
    required this.subColor,
    required this.darkMode,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: darkMode ? const Color(0xFF374151) : const Color(0xFFE2E8F0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 缩略图
          Expanded(
            child: Container(
              width: double.infinity,
              color: const Color(0xFFE5E7EB),
              child: art.thumbnail != null && art.thumbnail!.startsWith('data:image')
                  ? Image.memory(_decode(art.thumbnail!), fit: BoxFit.cover)
                  : const Center(child: Icon(Icons.image_outlined, color: Colors.grey)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                child: Text(art.name.isEmpty ? '未命名' : art.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor)),
              ),
              if (art.isSaved)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF3B82F6).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: const Text('手动', style: TextStyle(fontSize: 9, color: Color(0xFF60A5FA))),
                ),
              if (art.isAutoSave)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: const Text('自动', style: TextStyle(fontSize: 9, color: Color(0xFFFBBF24))),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(
              '${art.w > 0 && art.h > 0 ? '${art.w}×${art.h}' : ''}${art.w > 0 && art.h > 0 && art.date.isNotEmpty ? ' · ' : ''}${art.date}',
              style: TextStyle(fontSize: 10, color: subColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }

  Uint8List _decode(String dataUrl) {
    final idx = dataUrl.indexOf(',');
    return const Base64Codec().decode(dataUrl.substring(idx + 1));
  }
}

// 供图片导入等复用
Future<ui.Image?> pickAndDecodeImage() async {
  try {
    final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return null;
    final bytes = res.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}