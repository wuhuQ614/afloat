/// 转盘设置页：一比一复刻参考项目 WheelSettings.jsx。
///
/// 呈现形式为全屏覆盖层（对齐参考项目 fixed inset-0 z-[100] + createPortal），
/// 由 wheel_page.dart 以透明路由（opaque: false）打开，底层转盘页保持可见，
/// 彻底消除旧版 MaterialPageRoute 默认黑底的问题。
///
/// 背景（对齐 WheelSettings.jsx:53）：
/// - glass: 半透明白 + backdrop-blur-xl
/// - dark:  bg-gray-900/95 + backdrop-blur-xl
/// - light: bg-white/95 + backdrop-blur-xl
///
/// 进出场动画（对齐 index.css settingsReveal / settingsExit）：
/// - 入场 0.5s cubic-bezier(0.22,1,0.36,1)：scale(0.94)+translateY(24px)+opacity 0 → 复位
/// - 出场 0.3s cubic-bezier(0.55,0,1,0.45)：反向播放后再 pop
///
/// 可编辑：场景名称、项目标签、项目权重（百分比显示，blur 时反算）、
/// 删除项目、添加项目、删除场景。
/// 权重反算公式（对齐参考实现）：
///   newWeight = otherWeight == 0 ? newPct : (newPct × otherWeight) / (100 - newPct)
///   钳制 ≥ 0.1
library;

import 'dart:ui' as ui show ImageFilter;
import 'package:flutter/material.dart';
import 'wheel_data.dart';
import 'wheel_models.dart';

class WheelSettingsPage extends StatefulWidget {
  final WheelCollection collection;
  final bool darkMode;
  final bool glassMode;
  final bool canDelete;

  const WheelSettingsPage({
    super.key,
    required this.collection,
    required this.darkMode,
    required this.glassMode,
    required this.canDelete,
  });

  @override
  State<WheelSettingsPage> createState() => _WheelSettingsPageState();
}

class _WheelSettingsPageState extends State<WheelSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _nameCtrl;
  late List<WheelItem> _items;
  final List<TextEditingController> _labelCtrls = [];

  /// 进出场动画（入场 forward 500ms，出场 animateTo(0) 300ms）
  late final AnimationController _ctrl;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.collection.name);
    _items = widget.collection.items
        .map((i) => WheelItem(label: i.label, weight: i.weight))
        .toList();
    _syncLabelCtrls();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _ctrl.forward();
  }

  void _syncLabelCtrls() {
    while (_labelCtrls.length < _items.length) {
      _labelCtrls.add(TextEditingController());
    }
    while (_labelCtrls.length > _items.length) {
      _labelCtrls.removeLast().dispose();
    }
    for (var i = 0; i < _items.length; i++) {
      if (_labelCtrls[i].text != _items[i].label) {
        _labelCtrls[i].text = _items[i].label;
      }
    }
  }

  double get _totalWeight =>
      _items.fold<double>(0, (s, i) => s + (i.weight <= 0 ? 0 : i.weight));

  @override
  void dispose() {
    _ctrl.dispose();
    _nameCtrl.dispose();
    for (final c in _labelCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// 关闭覆盖层：先播放 300ms 出场动画再 pop（对齐参考项目 handleClose 的 300ms 延迟）
  void _close([Map<String, dynamic>? result]) {
    if (_closing) return;
    _closing = true;
    FocusScope.of(context).unfocus();
    _ctrl
        .animateTo(0,
            duration: const Duration(milliseconds: 300),
            curve: const Cubic(0.55, 0, 1, 0.45))
        .then((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  void _save() {
    final updated = WheelCollection(
      id: widget.collection.id,
      name: _nameCtrl.text.trim().isEmpty
          ? widget.collection.name
          : _nameCtrl.text.trim(),
      items: _items,
    );
    _close({'action': 'save', 'collection': updated});
  }

  void _delete() => _close({'action': 'delete'});

  Color _parseHex(String hex) {
    try {
      final h = hex.replaceFirst('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return const Color(0xFFE63946);
    }
  }

  // ==================== 主题色 ====================
  bool get _dark => widget.darkMode && !widget.glassMode;

  Color get _bg => widget.glassMode
      ? Colors.white.withValues(alpha: 0.72)
      : _dark
          ? const Color(0xFF111827).withValues(alpha: 0.95)
          : Colors.white.withValues(alpha: 0.95);

  Color get _divider => widget.glassMode
      ? Colors.white.withValues(alpha: 0.15)
      : _dark
          ? const Color(0xFF1F2937)
          : const Color(0xFFF3F4F6);

  Color get _textMain => widget.glassMode
      ? const Color(0xFF334155)
      : _dark
          ? Colors.white
          : const Color(0xFF1F2937);

  Color get _textSub => widget.glassMode
      ? const Color(0xFF64748B)
      : _dark
          ? const Color(0xFF6B7280)
          : const Color(0xFF9CA3AF);

  Color get _rowBg => widget.glassMode
      ? Colors.white.withValues(alpha: 0.2)
      : _dark
          ? const Color(0xFF1F2937).withValues(alpha: 0.6)
          : const Color(0xFFF9FAFB).withValues(alpha: 0.8);

  Color get _addBg => widget.glassMode
      ? Colors.white.withValues(alpha: 0.25)
      : _dark
          ? const Color(0xFF1F2937).withValues(alpha: 0.6)
          : const Color(0xFFF9FAFB);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final t = const Cubic(0.22, 1, 0.36, 1).transform(_ctrl.value);
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - t)),
              child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
            ),
          );
        },
        child: Stack(children: [
          // 全屏半透明背景 + 模糊（对齐参考项目 backdrop-blur-xl）
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(color: _bg),
            ),
          ),
          SafeArea(
            child: Column(children: [
              _buildHeader(),
              _buildStats(),
              Expanded(child: _buildList()),
              if (widget.canDelete) _buildFooter(),
            ]),
          ),
        ]),
      ),
    );
  }

  /// 顶栏（对齐 WheelSettings.jsx:54-60）：返回 + 场景名输入 + 保存
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _divider)),
      ),
      child: Row(children: [
        // 返回按钮（p-2 rounded-xl）
        InkWell(
          onTap: () => _close(),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.arrow_back, size: 18, color: _textSub),
          ),
        ),
        // 场景名称（居中，max-w-[180px]）
        Expanded(
          child: Center(
            child: SizedBox(
              width: 180,
              child: TextField(
                controller: _nameCtrl,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _textMain),
                decoration: InputDecoration(
                  hintText: '场景名称',
                  hintStyle: TextStyle(
                      fontSize: 14,
                      color: _textSub.withValues(alpha: 0.6)),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
          ),
        ),
        // 保存按钮（px-4 py-1.5 rounded-xl indigo）
        InkWell(
          onTap: _save,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: widget.glassMode
                  ? Colors.white.withValues(alpha: 0.4)
                  : _dark
                      ? const Color(0xFF4F46E5)
                      : const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '保存',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: widget.glassMode
                    ? const Color(0xFF334155)
                    : Colors.white,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// 统计行（对齐 WheelSettings.jsx:62-66）
  Widget _buildStats() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: _divider.withValues(alpha: 0.6))),
      ),
      child: Center(
        child: Text(
          '${_items.length} 个项目 · 总权重 ${_totalWeight.toStringAsFixed(1)}',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold, color: _textSub),
        ),
      ),
    );
  }

  /// 项目列表 + 添加按钮（对齐 WheelSettings.jsx:68-108）
  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _items.length + 1,
      itemBuilder: (ctx, idx) {
        if (idx == _items.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              onTap: () {
                setState(() {
                  _items.add(WheelItem(label: '新项目', weight: 1));
                  _syncLabelCtrls();
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _addBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 12, color: _textSub),
                      const SizedBox(width: 6),
                      Text('添加项目',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _textSub)),
                    ]),
              ),
            ),
          );
        }
        final item = _items[idx];
        final pct =
            _totalWeight > 0 ? (item.weight / _totalWeight * 100) : 0.0;
        final color =
            _parseHex(kWheelItemColors[idx % kWheelItemColors.length]);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _rowBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            // 色条（w-2.5 h-7 rounded-full）
            Container(
              width: 10,
              height: 28,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 10),
            // 名称输入（透明底，无边框）
            Expanded(
              child: TextField(
                controller: _labelCtrls[idx],
                onChanged: (v) => item.label = v,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _textMain),
                decoration: const InputDecoration(
                  hintText: '项目名称',
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 权重百分比编辑
            SizedBox(
              width: 82,
              child: _WeightEditor(
                percentage: pct,
                darkMode: _dark,
                glassMode: widget.glassMode,
                onCommit: (newPct) {
                  setState(() {
                    final other = _totalWeight - item.weight;
                    final clamped = newPct.clamp(0.0, 100.0);
                    final newWeight = other <= 0
                        ? clamped
                        : (clamped * other) / (100 - clamped);
                    item.weight = newWeight < 0.1 ? 0.1 : newWeight;
                  });
                },
              ),
            ),
            // 删除（XIcon 14）
            InkWell(
              onTap: () => setState(() => _items.removeAt(idx)),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close,
                    size: 14, color: const Color(0xFFD1D5DB)),
              ),
            ),
          ]),
        );
      },
    );
  }

  /// 底部删除场景（对齐 WheelSettings.jsx:110-112）
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _divider)),
      ),
      child: InkWell(
        onTap: _delete,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: widget.glassMode
                ? const Color(0xFFFFE4E6).withValues(alpha: 0.3)
                : _dark
                    ? const Color(0xFF7F1D1D).withValues(alpha: 0.2)
                    : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.delete_outline,
                size: 14,
                color: _dark
                    ? const Color(0xFFF87171)
                    : const Color(0xFFEF4444)),
            const SizedBox(width: 6),
            Text(
              '删除',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _dark
                      ? const Color(0xFFF87171)
                      : const Color(0xFFEF4444)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 权重百分比编辑器：显示百分比，编辑确认后回调
class _WeightEditor extends StatefulWidget {
  final double percentage;
  final bool darkMode;
  final bool glassMode;
  final ValueChanged<double> onCommit;

  const _WeightEditor({
    required this.percentage,
    required this.darkMode,
    required this.glassMode,
    required this.onCommit,
  });

  @override
  State<_WeightEditor> createState() => _WeightEditorState();
}

class _WeightEditorState extends State<_WeightEditor> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl =
        TextEditingController(text: widget.percentage.toStringAsFixed(1));
  }

  @override
  void didUpdateWidget(_WeightEditor old) {
    super.didUpdateWidget(old);
    // 外部权重变化时同步显示（非编辑状态）
    if (!FocusScope.of(context).hasFocus &&
        (double.tryParse(_ctrl.text) ?? -1) != widget.percentage) {
      _ctrl.text = widget.percentage.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    final v = double.tryParse(_ctrl.text);
    if (v != null) {
      widget.onCommit(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.glassMode
            ? Colors.white.withValues(alpha: 0.35)
            : widget.darkMode
                ? const Color(0xFF374151).withValues(alpha: 0.5)
                : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: widget.glassMode || widget.darkMode
            ? null
            : Border.all(color: const Color(0xFFE5E7EB).withValues(alpha: 0.8)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2563EB)),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              suffixText: '%',
              suffixStyle:
                  const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF)),
            ),
            onSubmitted: (_) => _commit(),
            onEditingComplete: _commit,
          ),
        ),
      ]),
    );
  }
}
