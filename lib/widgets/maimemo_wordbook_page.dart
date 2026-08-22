/// 墨墨词库页面：展示墨墨同步的单词，支持编辑、删除、出题
library;

import 'package:flutter/material.dart';
import '../models.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, kSuccess, AppColors;
import '../services/dict_service.dart';
import '../services/tts_service.dart';
import 'settings_dialog.dart';

class MaimemoWordbookPage extends StatefulWidget {
  const MaimemoWordbookPage({super.key});

  @override
  State<MaimemoWordbookPage> createState() => _MaimemoWordbookPageState();
}

class _MaimemoWordbookPageState extends State<MaimemoWordbookPage> {
  bool _syncing = false;
  String? _syncError;
  bool _generating = false;
  bool _hasAutoSynced = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _typeFilter = 'all'; // all / noun / verb / adj
  String _sort = 'default'; // default / az / za

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 词性分类（用于筛选）
  String _posType(String pos) {
    final p = pos.toLowerCase();
    if (p.contains('adj') || p.startsWith('a.')) return 'adj';
    if (p.contains('verb') || p.startsWith('v')) return 'verb';
    if (p.contains('noun') || p.startsWith('n')) return 'noun';
    return '';
  }

  /// 词性显示缩写
  String _posLabel(String pos) {
    switch (_posType(pos)) {
      case 'noun':
        return 'n.';
      case 'verb':
        return 'v.';
      case 'adj':
        return 'adj.';
      default:
        return pos;
    }
  }

  /// 按 搜索关键词 + 词性筛选 + 排序 得出可见条目。
  /// 返回 (源列表真实下标, 单词) 对——编辑/删除必须作用于源下标，
  /// 不用 list.indexOf(w) 反查（重复单词或列表被同步重建时会错位/返回 -1）。
  List<MapEntry<int, WordBookItem>> _visibleWords() {
    final s = AppScope.of(context);
    final kw = _searchCtrl.text.trim().toLowerCase();
    final entries = <MapEntry<int, WordBookItem>>[];
    for (final e in s.maimemoWordbook.asMap().entries) {
      final w = e.value;
      if (_typeFilter != 'all') {
        final pt = DictService.lookup(w.word)?.pos ?? '';
        if (_posType(pt) != _typeFilter) continue;
      }
      if (kw.isNotEmpty) {
        final ph = DictService.lookup(w.word)?.phonetic ?? '';
        final hit = w.word.toLowerCase().contains(kw) ||
            w.translation.toLowerCase().contains(kw) ||
            ph.toLowerCase().contains(kw);
        if (!hit) continue;
      }
      entries.add(e);
    }
    int cmpWord(MapEntry<int, WordBookItem> a, MapEntry<int, WordBookItem> b, bool asc) {
      final c = a.value.word.toLowerCase().compareTo(b.value.word.toLowerCase());
      return asc ? c : -c;
    }
    if (_sort == 'az') {
      entries.sort((a, b) => cmpWord(a, b, true));
    } else if (_sort == 'za') {
      entries.sort((a, b) => cmpWord(a, b, false));
    }
    return entries;
  }

  /// 今日新增数
  int _todayCount() {
    final s = AppScope.of(context);
    final now = DateTime.now();
    return s.maimemoWordbook.where((w) {
      final d = DateTime.fromMillisecondsSinceEpoch(w.addedAt);
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasAutoSynced) {
      _hasAutoSynced = true;
      final s = AppScope.of(context);
      if (s.maimemoToken.isNotEmpty) {
        // 延迟到首帧后同步，避免 build 期间调 setState 报错
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncMaimemo();
        });
      }
    }
  }

  Future<void> _syncMaimemo() async {
    if (_syncing) return;
    final s = AppScope.of(context);
    if (s.maimemoToken.trim().isEmpty) {
      setState(() => _syncError = '尚未配置墨墨 API Token，请先前往设置中配置');
      return;
    }
    setState(() {
      _syncing = true;
      _syncError = null;
    });
    try {
      await s.syncMaimemoWords();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _syncError = e.toString());
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _generateFromMaimemo() async {
    final s = AppScope.of(context);
    if (s.maimemoWordbook.isEmpty) return;
    if (!s.apiConfig.ready) {
      _showSnackBar('请先配置 AI 接口');
      return;
    }
    final words = s.maimemoWordbook.map((w) => w.word).toList();
    // 弹出窗口选择题目的长度（与首页滑动条一致）
    final length = await showDialog<_MaimemoLengthResult>(
      context: context,
      builder: (_) => _MaimemoLengthDialog(
        defaultCount: (words.length / 5).ceil().clamp(1, 10).toInt(),
        defaultWordCount: 80,
      ),
    );
    if (length == null || !mounted) return;

    setState(() => _generating = true);
    try {
      s.selectedType = 'maimemo';
      // 参考词抽取：总量 <=500 取全部，>500 取 500+总量/7
      final ok = await s.generateQuestions(
        count: length.count,
        customReq: '',
        wordCount: length.wordCount,
        maimemoWords: s.maimemoRefWords(),
      );
      if (!mounted) return;
      if (ok) {
        _showSnackBar('已基于墨墨词库（${words.length} 个单词）生成 ${length.count} 道题目');
        s.setPage(1);
        return;
      }
      _showSnackBar('生成失败，请检查 API 配置后重试');
    } catch (e) {
      _showSnackBar('出题失败：$e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3)),
    );
  }

  void _editWord(int index, WordBookItem item) {
    final wordCtrl = TextEditingController(text: item.word);
    final transCtrl = TextEditingController(text: item.translation);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑单词'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: wordCtrl,
            decoration: const InputDecoration(labelText: '单词', isDense: true),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: transCtrl,
            decoration: const InputDecoration(labelText: '释义', isDense: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final s = AppScope.of(context);
              s.updateMaimemoWordbookItem(index, WordBookItem(
                word: wordCtrl.text.trim(),
                translation: transCtrl.text.trim(),
                addedAt: item.addedAt,
              ));
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).whenComplete(() {
      // 弹窗关闭后释放临时控制器（保存路径在 pop 前已取完值）
      wordCtrl.dispose();
      transCtrl.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final list = s.maimemoWordbook;

    // 未配置墨墨 Token：显示配置提示
    if (s.maimemoToken.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text('墨墨词库', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.text)),
        ),
        Expanded(
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.sync_problem, size: 48, color: c.textTertiary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('尚未配置墨墨 API Token', style: TextStyle(fontSize: 15, color: c.textSecondary)),
              const SizedBox(height: 8),
              Text('请前往设置 → 账户与同步 中配置', style: TextStyle(fontSize: 13, color: c.textTertiary)),
              const SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kPrimary),
                onPressed: () => showDialog(context: context, builder: (_) => const SettingsDialog()),
                child: const Text('前往设置'),
              ),
            ]),
          ),
        ),
      ]);
    }

    final visible = _visibleWords();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('墨墨词库', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.text)),
              const SizedBox(height: 5),
              Text(
                '${list.length} 个单词 · 累计同步 ${s.maimemoSyncedCount} 个',
                style: TextStyle(fontSize: 13, color: c.textTertiary),
              ),
            ]),
          ),
          if (list.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 40),
              ),
              onPressed: _generating ? null : _generateFromMaimemo,
              icon: _generating
                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(_generating ? '生成中...' : '用词库出题', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textSecondary,
              side: BorderSide(color: c.border),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: _syncing ? null : _syncMaimemo,
            icon: _syncing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync, size: 15),
            label: Text(_syncing ? '同步中' : '同步', style: const TextStyle(fontSize: 13)),
          ),
        ]),
      ),
      // 同步状态
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSuccess,
              boxShadow: [BoxShadow(color: kSuccess.withValues(alpha: 0.5), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 8),
          Text('已同步', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          const SizedBox(width: 8),
          Text('·', style: TextStyle(color: c.textTertiary)),
          const SizedBox(width: 8),
          Text(
            s.maimemoLastSync > 0 ? '最后同步 ${_formatTime(s.maimemoLastSync)}' : '尚未同步',
            style: TextStyle(fontSize: 12.5, color: c.textTertiary),
          ),
        ]),
      ),
      if (_syncError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Row(children: [
            Icon(Icons.error_outline, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 6),
            Expanded(child: Text(_syncError!, style: TextStyle(fontSize: 12, color: Colors.red.shade400))),
          ]),
        ),
      // 统计区
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Container(
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [
            _stat(c, '${list.length}', '词汇总数'),
            _statDivider(c),
            _stat(c, '${s.maimemoSyncedCount}', '累计同步'),
            _statDivider(c),
            _stat(c, '${_todayCount()}', '今日新增'),
          ]),
        ),
      ),
      // 工具栏：搜索 + 词性筛选 + 排序
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          Expanded(child: _buildSearchField(c)),
          const SizedBox(width: 10),
          _buildDropdown(
            c,
            value: _typeFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('全部词汇')),
              DropdownMenuItem(value: 'noun', child: Text('名词')),
              DropdownMenuItem(value: 'verb', child: Text('动词')),
              DropdownMenuItem(value: 'adj', child: Text('形容词')),
            ],
            onChanged: (v) => setState(() => _typeFilter = v),
          ),
          const SizedBox(width: 8),
          _buildDropdown(
            c,
            value: _sort,
            items: const [
              DropdownMenuItem(value: 'default', child: Text('默认排序')),
              DropdownMenuItem(value: 'az', child: Text('A → Z')),
              DropdownMenuItem(value: 'za', child: Text('Z → A')),
            ],
            onChanged: (v) => setState(() => _sort = v),
          ),
        ]),
      ),
      // Section 标题
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
        child: Row(children: [
          Text('全部词汇', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const Spacer(),
          Text('${visible.length} 个词', style: TextStyle(fontSize: 12, color: c.textTertiary)),
        ]),
      ),
      // 列表或空状态
      Expanded(
        child: visible.isEmpty
            ? Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.search_off, size: 40, color: c.textTertiary.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  Text('没有找到相关词汇', style: TextStyle(fontSize: 14, color: c.textTertiary)),
                  const SizedBox(height: 6),
                  Text(
                    list.isEmpty ? '点击上方「同步」按钮拉取今日已学单词' : '换个关键词试试',
                    style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                  ),
                ]),
              )
            : _buildList(c, list, visible),
      ),
    ]);
  }

  Widget _stat(AppColors c, String num, String label) {
    return Expanded(
      child: Column(children: [
        Text(num, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.text)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: c.textTertiary)),
      ]),
    );
  }

  Widget _statDivider(AppColors c) => Container(width: 1, height: 34, color: c.border);

  Widget _buildSearchField(AppColors c) {
    return Container(
      height: 42,
      decoration: BoxDecoration(color: c.inputFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(() {}),
        style: TextStyle(fontSize: 14, color: c.text),
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.search, size: 18, color: c.textTertiary),
          hintText: '搜索单词、释义、音标...',
          hintStyle: TextStyle(fontSize: 13, color: c.hintText),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildDropdown(
    AppColors c, {
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: c.inputFill, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          items: items,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          style: TextStyle(fontSize: 13, color: c.textSecondary),
          icon: Icon(Icons.arrow_drop_down, color: c.textTertiary),
        ),
      ),
    );
  }

  Widget _buildList(AppColors c, List<WordBookItem> list, List<MapEntry<int, WordBookItem>> visible) {
    final s = AppScope.of(context);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: visible.length,
      separatorBuilder: (_, __) => Divider(height: 1, thickness: 1, color: c.divider, indent: 20, endIndent: 20),
      itemBuilder: (ctx, i) {
        final w = visible[i].value;
        final origIndex = visible[i].key; // 源列表真实下标（随筛选结果携带，非反查）
        final entry = DictService.lookup(w.word);
        final ph = entry?.phonetic ?? '';
        final pos = entry?.pos ?? '';
        return InkWell(
          onTap: () => _editWord(origIndex, w),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(w.word, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.text)),
                  if (pos.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(_posLabel(pos), style: TextStyle(fontSize: 12, color: c.textTertiary)),
                  ],
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 112,
                child: Text(
                  ph.isEmpty ? '' : '/$ph/',
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: Text(w.translation, style: TextStyle(fontSize: 14, color: c.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (TtsService.instance.available)
                  IconButton(
                    icon: Icon(Icons.volume_up, size: 18, color: c.textTertiary),
                    tooltip: '发音',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => TtsService.instance.speakWord(w.word),
                  ),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 18, color: c.textTertiary),
                  tooltip: '编辑',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editWord(origIndex, w),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: c.textTertiary),
                  tooltip: '删除',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    s.removeFromMaimemoWordbook(w.word);
                    setState(() {});
                  },
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 出题长度选择结果：题量 + 每题单词量
class _MaimemoLengthResult {
  final int count;
  final int wordCount;
  const _MaimemoLengthResult(this.count, this.wordCount);
}

/// 出题长度选择弹窗（与首页滑动条一致：题量 + 单词量）
class _MaimemoLengthDialog extends StatefulWidget {
  final int defaultCount;
  final int defaultWordCount;
  const _MaimemoLengthDialog({required this.defaultCount, required this.defaultWordCount});

  @override
  State<_MaimemoLengthDialog> createState() => _MaimemoLengthDialogState();
}

class _MaimemoLengthDialogState extends State<_MaimemoLengthDialog> {
  late double _count;
  late double _wordCount;

  @override
  void initState() {
    super.initState();
    _count = widget.defaultCount.toDouble().clamp(1, 50).toDouble();
    _wordCount = widget.defaultWordCount.toDouble().clamp(30, 300).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择题目长度'),
      content: SizedBox(
        width: 360,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _buildSliderRow(
            label: '题量',
            value: _count,
            min: 1,
            max: 50,
            valueText: '${_count.round()} 道',
            onChanged: (v) => setState(() => _count = v),
          ),
          const SizedBox(height: 14),
          _buildSliderRow(
            label: '每题长度',
            value: _wordCount,
            min: 30,
            max: 300,
            valueText: '${_wordCount.round()} 词',
            onChanged: (v) => setState(() => _wordCount = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kPrimary),
          onPressed: () => Navigator.pop(context, _MaimemoLengthResult(_count.round(), _wordCount.round())),
          child: const Text('开始出题'),
        ),
      ],
    );
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required String valueText,
    required ValueChanged<double> onChanged,
  }) {
    final c = AppColors.of(context);
    return Row(children: [
      SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.primaryText))),
      Expanded(
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: kPrimary,
            inactiveTrackColor: c.sliderInactive,
            thumbColor: kPrimary,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            label: valueText,
            onChanged: onChanged,
          ),
        ),
      ),
      SizedBox(width: 64, child: Text(valueText, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.primaryText))),
    ]);
  }
}