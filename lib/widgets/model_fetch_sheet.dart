/// 模型获取面板：从 OpenAI 兼容接口拉取 /models 模型列表，
/// 支持搜索过滤、点 + 添加到配置的模型收藏、点 − 移除、点行选为当前模型。
///
/// 参考交互（用户提供的截图）：底部弹层 + 搜索框 + 列表行右侧圆圈加减号，
/// 已添加的排在前面显示红色 −，未添加的显示绿色 +。
library;

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/api_service.dart';
import '../theme_colors.dart';

class ModelFetchResult {
  /// 面板关闭时的收藏列表（增删后的最终状态）
  final List<String> models;
  /// 点行选中的模型（写入模型输入框）；null = 未点行，仅增删收藏
  final String? pickedModel;

  const ModelFetchResult({required this.models, this.pickedModel});
}

class ModelFetchSheet extends StatefulWidget {
  /// 每次点「重新获取」时调用，取最新的 url/key 构造请求
  final ApiConfig Function() configProvider;
  final List<String> initialModels;
  final String currentModel;
  /// true：点 + 添加后立即关闭面板并把该模型作为 pickedModel 返回
  ///（服务商添加表单场景）；false：仅收藏（主表单原行为）
  final bool autoCloseOnAdd;

  const ModelFetchSheet({
    super.key,
    required this.configProvider,
    required this.initialModels,
    required this.currentModel,
    this.autoCloseOnAdd = false,
  });

  static Future<ModelFetchResult?> show(
    BuildContext context, {
    required ApiConfig Function() configProvider,
    required List<String> initialModels,
    required String currentModel,
    bool autoCloseOnAdd = false,
  }) {
    return showModalBottomSheet<ModelFetchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ModelFetchSheet(
        configProvider: configProvider,
        initialModels: initialModels,
        autoCloseOnAdd: autoCloseOnAdd,
        currentModel: currentModel,
      ),
    );
  }

  @override
  State<ModelFetchSheet> createState() => _ModelFetchSheetState();
}

class _ModelFetchSheetState extends State<ModelFetchSheet> {
  final TextEditingController _search = TextEditingController();
  List<String>? _remote; // 远端模型列表（null = 尚未成功）
  bool _loading = false;
  String? _error;
  late List<String> _added; // 收藏列表
  String _current = '';

  @override
  void initState() {
    super.initState();
    _added = List.of(widget.initialModels);
    _current = widget.currentModel;
    // 首帧即显示 loading；不在这里 setState（initState 中禁止），由 _fetch(silent) 续接
    _loading = true;
    _fetch(silent: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final list = await ApiService.fetchModels(widget.configProvider());
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (list != null) {
        _remote = list;
      } else {
        _error = ApiService.lastError ?? '获取失败';
      }
    });
  }

  void _add(String m) {
    setState(() {
      if (!_added.contains(m)) _added.add(m);
      _current = m;
    });
    if (widget.autoCloseOnAdd) {
      Navigator.pop(context, ModelFetchResult(models: _added, pickedModel: m));
    }
  }

  void _remove(String m) {
    setState(() => _added.remove(m));
  }

  void _pick(String m) {
    Navigator.pop(context, ModelFetchResult(models: _added, pickedModel: m));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dark = !c.isLight;
    final mq = MediaQuery.of(context);
    final kw = _search.text.trim().toLowerCase();

    // 合并列表：收藏优先（含不在远端的），再接远端未收藏的
    final all = <String>[..._added];
    if (_remote != null) {
      for (final m in _remote!) {
        if (!all.contains(m)) all.add(m);
      }
    }
    final filtered = kw.isEmpty ? all : all.where((m) => m.toLowerCase().contains(kw)).toList();

    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.75),
      decoration: BoxDecoration(
        color: c.cardSolid,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, mq.padding.bottom + 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 顶部拖动条 + 标题 + 获取按钮
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: c.isLight ? const Color(0xFFE2E2E8) : const Color(0xFF3A3A44),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(children: [
            const SizedBox(width: 76),
            Expanded(
              child: Text('模型',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
            ),
            SizedBox(
              width: 76,
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : () => _fetch(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    foregroundColor: c.primary,
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                      : const Text('获取', style: TextStyle(fontSize: 13)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          // 搜索框
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 13.5, color: c.text),
            decoration: InputDecoration(
              hintText: '搜索模型...',
              hintStyle: TextStyle(fontSize: 13, color: c.hintText),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: c.textTertiary),
              isDense: true,
              filled: true,
              fillColor: c.isLight ? const Color(0xFFF3F3F7) : const Color(0xFF26262C),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: _buildBody(filtered, c, dark),
          ),
        ]),
      ),
    );
  }

  Widget _buildBody(List<String> filtered, AppColors c, bool dark) {
    if (_loading && _remote == null && _added.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: c.primary)),
      );
    }
    if (_error != null && _remote == null && _added.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: kDanger)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => _fetch(),
            child: Text('重试', style: TextStyle(fontSize: 13, color: c.primary)),
          ),
        ]),
      );
    }
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('无匹配模型', style: TextStyle(fontSize: 13, color: c.textTertiary))),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final m = filtered[i];
        final isAdded = _added.contains(m);
        final isCurrent = m == _current;
        return InkWell(
          onTap: () => _pick(m),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.divider)),
            ),
            child: Row(children: [
              Expanded(
                child: Text(m,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: c.text,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis),
              ),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('当前',
                      style: TextStyle(fontSize: 10.5, color: c.primary)),
                ),
              _roundAction(
                dark: dark,
                danger: isAdded,
                icon: isAdded ? Icons.remove_rounded : Icons.add_rounded,
                onTap: () => isAdded ? _remove(m) : _add(m),
              ),
            ]),
          ),
        );
      },
    );
  }

  /// 圆圈加减号（贴截图样式：描边圆 + 中心符号）
  Widget _roundAction({required bool dark, required bool danger, required IconData icon, required VoidCallback onTap}) {
    final color = danger ? kDanger : kSuccess;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.4),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
