/// 全局设置弹窗：API 配置 + 数据备份/导入
library;

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary;
import 'learn_page.dart' show AppScope;

const _primary = kPrimary;

const _models = ['gpt-5.1', 'gpt-5.1-instant', 'gpt-5.5', 'gpt-4o', 'deepseek-v4-flash', 'deepseek-v4-pro'];

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  late String _model;
  late String _temp;

  @override
  void initState() {
    super.initState();
    final s = AppScope.of(context);
    _url = TextEditingController(text: s.apiConfig.url);
    _key = TextEditingController(text: s.apiConfig.key);
    _model = s.apiConfig.model;
    _temp = s.apiConfig.temperature.isEmpty ? 'default' : s.apiConfig.temperature;
    s.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppScope.of(context).removeListener(_onStateChanged);
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Dialog(
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('全局 AI 设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('用于 AI 出题、批改、词汇剖析等；对话助手可使用独立配置', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(controller: _url, decoration: const InputDecoration(labelText: 'API 地址', hintText: 'https://api.openai.com/v1/chat/completions', isDense: true, border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'API Key', hintText: 'sk-...', isDense: true, border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _model,
              decoration: const InputDecoration(labelText: '模型', isDense: true, border: OutlineInputBorder()),
              items: [for (final m in _models) DropdownMenuItem(value: m, child: Text(m))],
              onChanged: (v) => setState(() => _model = v ?? _model),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _temp,
              decoration: const InputDecoration(labelText: '温度', isDense: true, border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('厂家默认')),
                DropdownMenuItem(value: '0', child: Text('精确 (0)')),
                DropdownMenuItem(value: '0.3', child: Text('保守 (0.3)')),
                DropdownMenuItem(value: '0.7', child: Text('均衡 (0.7)')),
                DropdownMenuItem(value: '1.0', child: Text('创意 (1.0)')),
              ],
              onChanged: (v) => setState(() => _temp = v ?? _temp),
            ),
            const Divider(height: 24),
            const Text('界面设置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // 界面模式切换
            const Text('界面模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: [
              _buildModeChip('desktop', '电脑端', s.uiMode.isEmpty ? 'desktop' : s.uiMode, s),
              const SizedBox(width: 10),
              _buildModeChip('mobile', '手机端', s.uiMode.isEmpty ? 'desktop' : s.uiMode, s),
            ]),
            const SizedBox(height: 4),
            Text('切换后立即生效，也可按 F8 快速切换', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: s.fullscreen,
              onChanged: (v) => s.toggleFullscreen(v ?? false),
              title: const Text('全屏模式', style: TextStyle(fontSize: 14)),
              subtitle: const Text('开启后进入全屏，按 F11 可快速切换', style: TextStyle(fontSize: 11.5)),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: s.powerSavingMode,
              onChanged: (v) => s.togglePowerSavingMode(v ?? true),
              title: const Text('省电模式', style: TextStyle(fontSize: 14)),
              subtitle: const Text('开启后锁定60帧以节省电量，关闭后支持120帧高刷', style: TextStyle(fontSize: 11.5)),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('数据备份', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            const Text('备份包含 API 配置、收藏、错题本、学习记录、生词本等；API Key 敏感，请妥善保管', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () => _export(s),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('导出备份'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _import(s),
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('导入备份'),
              ),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _primary),
                  onPressed: () {
                    s.saveApiConfig(ApiConfig(url: _url.text.trim(), key: _key.text.trim(), model: _model, temperature: _temp));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
                  },
                  child: const Text('保存'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _buildModeChip(String value, String label, String current, AppState s) {
    final isSelected = current == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => s.setUiMode(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? kPrimary.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? kPrimary : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? kPrimary : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Future<void> _export(AppState s) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出备份',
        fileName: 'smartenglish-backup-${DateTime.now().millisecondsSinceEpoch}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null) return;
      final file = File(path);
      await file.writeAsString(s.buildBackupJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份已导出到 $path'), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
  }

  Future<void> _import(AppState s) async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (res == null || res.files.isEmpty) return;
      final content = await File(res.files.first.path!).readAsString();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入备份'),
          content: const Text('导入将覆盖当前收藏、错题本、学习记录、生词本、记录本等数据，确定继续吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确认导入')),
          ],
        ),
      );
      if (confirmed != true) return;
      final ok = s.importBackup(content);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '导入成功' : '导入失败：文件格式不正确'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
  }
}

/// 对话助手独立设置弹窗
class ChatSettingsDialog extends StatefulWidget {
  const ChatSettingsDialog({super.key});

  @override
  State<ChatSettingsDialog> createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> {
  late bool _independent;
  late final TextEditingController _url;
  late final TextEditingController _key;
  late String _model;
  late String _temp;
  late bool _showReasoning;
  late bool _stream;

  @override
  void initState() {
    super.initState();
    final s = AppScope.of(context);
    _independent = s.chatApiIndependent;
    _url = TextEditingController(text: s.chatApiConfig.url);
    _key = TextEditingController(text: s.chatApiConfig.key);
    _model = s.chatApiConfig.model;
    _temp = s.chatApiConfig.temperature.isEmpty ? 'default' : s.chatApiConfig.temperature;
    _showReasoning = s.chatShowReasoning;
    _stream = s.chatStream;
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Dialog(
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('AI 对话助手设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _independent,
              onChanged: (v) => setState(() => _independent = v ?? false),
              title: const Text('使用独立 API 配置', style: TextStyle(fontSize: 14)),
              subtitle: const Text('开启后对话助手使用下方独立配置；关闭则使用全局统一 API', style: TextStyle(fontSize: 11.5)),
              contentPadding: EdgeInsets.zero,
            ),
            if (_independent) ...[
              const SizedBox(height: 8),
              TextField(controller: _url, decoration: const InputDecoration(labelText: 'API 地址', isDense: true, border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'API Key', isDense: true, border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _model,
                decoration: const InputDecoration(labelText: '模型', isDense: true, border: OutlineInputBorder()),
                items: [for (final m in _models) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (v) => setState(() => _model = v ?? _model),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _temp,
                decoration: const InputDecoration(labelText: '温度', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('厂家默认')),
                  DropdownMenuItem(value: '0', child: Text('精确 (0)')),
                  DropdownMenuItem(value: '0.3', child: Text('保守 (0.3)')),
                  DropdownMenuItem(value: '0.7', child: Text('均衡 (0.7)')),
                  DropdownMenuItem(value: '1.0', child: Text('创意 (1.0)')),
                ],
                onChanged: (v) => setState(() => _temp = v ?? _temp),
              ),
              const Divider(height: 24),
            ],
            CheckboxListTile(
              value: _showReasoning,
              onChanged: (v) => setState(() => _showReasoning = v ?? false),
              title: const Text('显示思考过程', style: TextStyle(fontSize: 14)),
              subtitle: const Text('开启后，AI 回答前会展开显示其思考过程（需模型支持）', style: TextStyle(fontSize: 11.5)),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _stream,
              onChanged: (v) => setState(() => _stream = v ?? false),
              title: const Text('流式输出', style: TextStyle(fontSize: 14)),
              subtitle: const Text('开启后逐字显示回复', style: TextStyle(fontSize: 11.5)),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _primary),
              onPressed: () {
                s.saveChatSettings(
                  independent: _independent,
                  config: ApiConfig(url: _url.text.trim(), key: _key.text.trim(), model: _model, temperature: _temp),
                  showReasoning: _showReasoning,
                  stream: _stream,
                );
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('对话助手设置已保存'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
              },
              child: const Text('保存'),
            ),
          ]),
        ),
      ),
    );
  }
}
