/// 墨墨词库页面：展示墨墨同步的单词，支持编辑、删除、出题
library;

import 'package:flutter/material.dart';
import '../models.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, AppColors;
import '../services/dict_service.dart';
import '../services/api_service.dart' as api;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasAutoSynced) {
      _hasAutoSynced = true;
      final s = AppScope.of(context);
      if (s.maimemoToken.isNotEmpty) {
        _syncMaimemo();
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
    setState(() => _generating = true);
    try {
      final words = s.maimemoWordbook.map((w) => w.word).toList();
      final sample = words.take(20).toList();
      final wordList = sample.join('、');
      final count = (sample.length / 5).ceil().clamp(1, 5);
      final systemPrompt = '你是一个英语出题专家。请使用以下单词生成 $count 道翻译题：$wordList\n\n'
          '要求：\n'
          '1. 每道题必须包含至少 2-3 个给定单词\n'
          '2. 题目难度适中，适合英语学习者\n'
          '3. 翻译方向为中译英（题目为中文，答案为英文）\n\n'
          '请以JSON数组格式返回，格式如下：\n'
          '[{"chinese": "中文内容", "english": "英文内容", "knowledge": ["知识点1"]}]\n'
          '只返回JSON数组，不要其他内容。';
      final reply = await api.ApiService.callAI(
        [
          {'role': 'user', 'content': '请用以下单词出题'}
        ],
        systemPrompt,
        config: s.apiConfig,
        maxTokens: 8192,
        extraParams: api.ApiService.noThinkingParams(s.apiConfig.model),
      );
      if (reply != null) {
        final list = api.ApiService.extractJsonArray(reply);
        if (list != null && list.isNotEmpty) {
          s.generatedQuestions = list.map((q) => s.normalizeGeneratedQuestion(q, QType.translation, 'medium')).toList();
          s.generatedQuestionIdx = 0;
          s.loadGeneratedQuestion();
          if (!mounted) return;
          _showSnackBar('已生成 ${list.length} 道题目（基于墨墨词库）');
          s.setPage(1);
          return;
        }
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final list = s.maimemoWordbook;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 顶部信息栏
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('墨墨词库', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.text)),
              const SizedBox(height: 4),
              if (s.maimemoToken.isNotEmpty)
                Text(
                  '共 ${list.length} 个单词 | 累计同步 ${s.maimemoSyncedCount} 个',
                  style: TextStyle(fontSize: 12.5, color: c.textTertiary),
                ),
            ]),
          ),
          // 操作按钮
          if (s.maimemoToken.isNotEmpty && list.isNotEmpty)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kPrimary),
              onPressed: _generating ? null : () => _generateFromMaimemo(),
              icon: _generating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome_rounded, size: 16),
              label: Text(_generating ? '生成中...' : '用词库出题'),
            ),
          const SizedBox(width: 8),
          if (list.isNotEmpty)
            TextButton(
              onPressed: () {
                s.clearMaimemoWordbook();
                setState(() {});
              },
              child: const Text('清空'),
            ),
        ]),
      ),
      // 同步状态
      if (s.maimemoToken.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(children: [
            if (_syncing)
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            if (_syncing) ...[
              const SizedBox(width: 8),
              Text('正在同步...', style: TextStyle(fontSize: 12, color: c.textTertiary)),
            ] else if (s.maimemoLastSync > 0) ...[
              Icon(Icons.check_circle, size: 14, color: Colors.green.shade400),
              const SizedBox(width: 6),
              Text(
                '上次同步 ${_formatTime(s.maimemoLastSync)}',
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
            ],
            const Spacer(),
            if (!_syncing)
              TextButton.icon(
                onPressed: _syncMaimemo,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('同步', style: TextStyle(fontSize: 12.5)),
                style: TextButton.styleFrom(foregroundColor: kPrimary, padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
          ]),
        ),
      if (_syncError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Row(children: [
            Icon(Icons.error_outline, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_syncError!, style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
            ),
          ]),
        ),
      // 配置提示
      if (s.maimemoToken.isEmpty)
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
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const SettingsDialog(),
                  );
                },
                child: const Text('前往设置'),
              ),
            ]),
          ),
        )
      else if (list.isEmpty && !_syncing)
        // 空状态
        Expanded(
          child: Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.auto_stories_outlined, size: 48, color: c.textTertiary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('墨墨词库为空', style: TextStyle(fontSize: 15, color: c.textSecondary)),
              const SizedBox(height: 8),
              Text('仅同步今日已学习过的单词', style: TextStyle(fontSize: 13, color: c.textTertiary)),
              const SizedBox(height: 4),
              Text('点击上方「同步」按钮拉取', style: TextStyle(fontSize: 13, color: c.textTertiary)),
            ]),
          ),
        )
      else
        // 单词列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: list.length,
            itemBuilder: (ctx, i) {
              final w = list[i];
              final ph = DictService.lookup(w.word)?.phonetic ?? '';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  title: Row(children: [
                    Text(w.word, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                    if (ph.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('/$ph/', style: TextStyle(fontSize: 12, color: c.textTertiary), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ]),
                  subtitle: Text(w.translation, style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (TtsService.instance.available)
                      IconButton(
                        icon: Icon(Icons.volume_up, size: 16, color: c.primaryText),
                        tooltip: '发音',
                        onPressed: () => TtsService.instance.speakWord(w.word),
                      ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined, size: 16, color: c.textTertiary),
                      tooltip: '编辑',
                      onPressed: () => _editWord(i, w),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: c.textTertiary),
                      onPressed: () {
                        s.removeFromMaimemoWordbook(w.word);
                        setState(() {});
                      },
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
    ]);
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}