/// 全局设置弹窗：API 配置 + 数据备份/导入
library;

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, AppColors;
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
  late final TextEditingController _modelCtrl;
  late String _temp;
  late bool _vision;
  late bool _fullUrl;
  /// 当前编辑的配置库索引；-1 表示新建
  late int _editIdx;

  @override
  void initState() {
    super.initState();
    final s = AppScope.of(context);
    _editIdx = s.apiProfiles.indexWhere((p) => p.config.url == s.apiConfig.url && p.config.key == s.apiConfig.key);
    _url = TextEditingController(text: s.apiConfig.url);
    _key = TextEditingController(text: s.apiConfig.key);
    _modelCtrl = TextEditingController(text: s.apiConfig.model);
    _temp = s.apiConfig.temperature.isEmpty ? 'default' : s.apiConfig.temperature;
    _vision = s.apiConfig.vision;
    _fullUrl = s.apiConfig.fullUrl;
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
    _modelCtrl.dispose();
    super.dispose();
  }

  /// 将一份配置加载到表单
  void _loadFrom(ApiConfig c) {
    _url.text = c.url;
    _key.text = c.key;
    _modelCtrl.text = c.model;
    setState(() {
      _temp = c.temperature.isEmpty ? 'default' : c.temperature;
      _vision = c.vision;
      _fullUrl = c.fullUrl;
    });
  }

  /// 保存：更新或追加配置到全局配置库，并设为当前生效配置
  void _saveConfig(AppState s) {
    final c = ApiConfig(url: _url.text.trim(), key: _key.text.trim(), model: _modelCtrl.text.trim(), temperature: _temp, vision: _vision, fullUrl: _fullUrl);
    final profiles = List.of(s.apiProfiles);
    int activeIdx;
    if (_editIdx >= 0 && _editIdx < profiles.length) {
      profiles[_editIdx] = ApiProfile(name: profiles[_editIdx].name, config: c);
      activeIdx = _editIdx;
    } else {
      profiles.add(ApiProfile(name: '配置${profiles.length + 1}', config: c));
      activeIdx = profiles.length - 1;
    }
    s.saveApiProfiles(profiles, activeIdx);
  }

  /// 删除当前编辑的配置
  void _deleteConfig(AppState s) {
    if (_editIdx < 0 || _editIdx >= s.apiProfiles.length) return;
    final profiles = List.of(s.apiProfiles)..removeAt(_editIdx);
    final activeIdx = profiles.isEmpty ? -1 : (_editIdx < profiles.length ? _editIdx : profiles.length - 1);
    s.saveApiProfiles(profiles, activeIdx);
    setState(() {
      _editIdx = -1;
      _loadFrom(ApiConfig());
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    return Dialog(
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('全局 AI 设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 4),
            Text('用于 AI 出题、批改、词汇剖析等；可保存多套配置随时切换，对话助手也可单独配置', style: TextStyle(fontSize: 12, color: c.textTertiary)),
            const SizedBox(height: 16),
            // 配置库选择
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey(_editIdx),
                  initialValue: _editIdx,
                  decoration: InputDecoration(labelText: '已保存的配置', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary)),
                  items: [
                    const DropdownMenuItem(value: -1, child: Text('＋ 新建配置')),
                    for (var i = 0; i < s.apiProfiles.length; i++)
                      DropdownMenuItem(value: i, child: Text('${s.apiProfiles[i].label} · ${s.apiProfiles[i].config.model}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    final idx = v ?? -1;
                    setState(() => _editIdx = idx);
                    _loadFrom(idx >= 0 && idx < s.apiProfiles.length ? s.apiProfiles[idx].config : ApiConfig());
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '删除当前配置',
                onPressed: s.apiProfiles.isEmpty || _editIdx < 0 || _editIdx >= s.apiProfiles.length ? null : () => _deleteConfig(s),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: c.textTertiary,
              ),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _url, decoration: InputDecoration(labelText: 'API 地址', hintText: 'https://api.openai.com/v1', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary), hintStyle: TextStyle(color: c.inputHint))),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _fullUrl,
              onChanged: (v) => setState(() => _fullUrl = v ?? false),
              title: Text('完整 URL', style: TextStyle(fontSize: 13.5, color: c.text)),
              subtitle: Text('关闭时自动在地址后添加 /chat/completions', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            TextField(controller: _key, obscureText: true, decoration: InputDecoration(labelText: 'API Key', hintText: 'sk-...', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary), hintStyle: TextStyle(color: c.inputHint))),
            const SizedBox(height: 12),
            TextField(controller: _modelCtrl, decoration: InputDecoration(labelText: '模型', hintText: '输入模型名称，如 gpt-4o', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary), hintStyle: TextStyle(color: c.inputHint))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _temp,
              decoration: InputDecoration(labelText: '温度', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary)),
              items: const [
                DropdownMenuItem(value: 'default', child: Text('厂家默认')),
                DropdownMenuItem(value: '0', child: Text('精确 (0)')),
                DropdownMenuItem(value: '0.3', child: Text('保守 (0.3)')),
                DropdownMenuItem(value: '0.7', child: Text('均衡 (0.7)')),
                DropdownMenuItem(value: '1.0', child: Text('创意 (1.0)')),
              ],
              onChanged: (v) => setState(() => _temp = v ?? _temp),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _vision,
              onChanged: (v) => setState(() => _vision = v ?? false),
              title: Text('图形能力（支持上传图片）', style: TextStyle(fontSize: 13.5, color: c.text)),
              subtitle: Text('开启后对话中可上传图片给 AI 识别；关闭时上传的图片显示为黑色占位', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 14),
            // 仅 API 设置需要保存，其余设置点击即生效
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _primary),
                onPressed: () {
                  _saveConfig(s);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('API 设置已保存'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
                },
                child: const Text('保存'),
              ),
            ),
            const Divider(height: 24),
            Text('界面设置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 8),
            // 界面模式切换
            Text('界面模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 6),
            Row(children: [
              _buildModeChip('desktop', '电脑端', s.uiMode.isEmpty ? 'desktop' : s.uiMode, s, c),
              const SizedBox(width: 10),
              _buildModeChip('mobile', '手机端', s.uiMode.isEmpty ? 'desktop' : s.uiMode, s, c),
            ]),
            const SizedBox(height: 4),
            Text('切换后立即生效，也可按 F8 快速切换', style: TextStyle(fontSize: 11, color: c.textTertiary)),
            const SizedBox(height: 12),
            SwitchListTile(
              value: s.darkMode,
              onChanged: (v) => s.toggleDarkMode(v),
              title: Text('深色模式', style: TextStyle(fontSize: 14, color: c.text)),
              subtitle: Text('开启后使用深色界面，与侧边栏月亮/太阳图标同步', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: s.fullscreen,
              onChanged: (v) {
                // 先关闭对话框再切换全屏，避免弹窗与窗口全屏切换冲突导致卡死
                Navigator.of(context).pop();
                Future.delayed(const Duration(milliseconds: 200), () {
                  s.toggleFullscreen(v ?? false);
                });
              },
              title: Text('全屏模式', style: TextStyle(fontSize: 14, color: c.text)),
              subtitle: Text('开启后进入全屏，按 F11 可快速切换', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: s.powerSavingMode,
              onChanged: (v) => s.togglePowerSavingMode(v ?? true),
              title: Text('省电模式', style: TextStyle(fontSize: 14, color: c.text)),
              subtitle: Text('开启后锁定60帧以节省电量，关闭后支持120帧高刷', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            // 重新查看首次启动引导
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.replay_rounded, size: 20, color: c.textTertiary),
              title: Text('重新查看引导', style: TextStyle(fontSize: 14, color: c.text)),
              subtitle: Text('再次打开首次启动的快速引导向导', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              onTap: () {
                Navigator.of(context).pop();
                s.resetOnboarding();
              },
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('数据备份', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.text))),
            ]),
            const SizedBox(height: 4),
            Text('备份包含 API 配置、收藏、错题本、学习记录、生词本等；API Key 敏感，请妥善保管', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
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
          ]),
        ),
      ),
    );
  }

  Widget _buildModeChip(String value, String label, String current, AppState s, AppColors c) {
    final isSelected = current == value;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => s.setUiMode(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? c.primaryBg : c.chipUnselected,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? _primary : c.chipBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isSelected ? c.primaryText : c.textSecondary,
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
  late final TextEditingController _modelCtrl;
  late String _temp;
  late bool _vision;
  late bool _fullUrl;
  late bool _showReasoning;
  late bool _stream;
  /// 当前编辑的对话配置库索引；-1 表示新建
  late int _editIdx;

  @override
  void initState() {
    super.initState();
    final s = AppScope.of(context);
    _independent = s.chatApiIndependent;
    _url = TextEditingController(text: s.chatApiConfig.url);
    _key = TextEditingController(text: s.chatApiConfig.key);
    _modelCtrl = TextEditingController(text: s.chatApiConfig.model);
    _temp = s.chatApiConfig.temperature.isEmpty ? 'default' : s.chatApiConfig.temperature;
    _vision = s.chatApiConfig.vision;
    _fullUrl = s.chatApiConfig.fullUrl;
    _showReasoning = s.chatShowReasoning;
    _stream = s.chatStream;
    _editIdx = s.chatProfileIdx;
    // 监听状态变化，同步更新本地变量（确保 toggleDarkMode 等触发的 notifyListeners 能刷新 UI）
    s.addListener(_syncFromState);
  }

  void _syncFromState() {
    if (!mounted) return;
    final s = AppScope.of(context);
    if (_showReasoning != s.chatShowReasoning) setState(() => _showReasoning = s.chatShowReasoning);
    if (_stream != s.chatStream) setState(() => _stream = s.chatStream);
    if (_independent != s.chatApiIndependent) setState(() => _independent = s.chatApiIndependent);
  }

  @override
  void dispose() {
    AppScope.of(context).removeListener(_syncFromState);
    _url.dispose();
    _key.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  /// 将一份配置加载到表单
  void _loadFrom(ApiConfig c) {
    _url.text = c.url;
    _key.text = c.key;
    _modelCtrl.text = c.model;
    setState(() {
      _temp = c.temperature.isEmpty ? 'default' : c.temperature;
      _vision = c.vision;
      _fullUrl = c.fullUrl;
    });
  }

  /// 保存：更新或追加配置到对话配置库，并设为当前选中
  void _saveConfig(AppState s) {
    final c = ApiConfig(url: _url.text.trim(), key: _key.text.trim(), model: _modelCtrl.text.trim(), temperature: _temp, vision: _vision, fullUrl: _fullUrl);
    final profiles = List.of(s.chatProfiles);
    int idx;
    if (_editIdx >= 0 && _editIdx < profiles.length) {
      profiles[_editIdx] = ApiProfile(name: profiles[_editIdx].name, config: c);
      idx = _editIdx;
    } else {
      profiles.add(ApiProfile(name: '模型${profiles.length + 1}', config: c));
      idx = profiles.length - 1;
    }
    s.saveChatProfiles(profiles, idx);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    return Dialog(
      child: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('AI 对话助手设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c.text)),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _independent,
              onChanged: (v) => setState(() => _independent = v ?? false),
              title: Text('使用独立 API 配置', style: TextStyle(fontSize: 14, color: c.text)),
              subtitle: Text('开启后对话助手使用下方独立配置；关闭则使用全局统一 API', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            if (_independent) ...[
              const SizedBox(height: 8),
              // 对话配置库选择
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(_editIdx),
                    initialValue: _editIdx,
                    decoration: InputDecoration(labelText: '对话模型配置', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary)),
                    items: [
                      const DropdownMenuItem(value: -1, child: Text('＋ 新建配置')),
                      for (var i = 0; i < s.chatProfiles.length; i++)
                        DropdownMenuItem(value: i, child: Text('${s.chatProfiles[i].label} · ${s.chatProfiles[i].config.model}', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      final idx = v ?? -1;
                      setState(() => _editIdx = idx);
                      _loadFrom(idx >= 0 && idx < s.chatProfiles.length ? s.chatProfiles[idx].config : ApiConfig());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '删除当前配置',
                  onPressed: s.chatProfiles.isEmpty || _editIdx < 0 || _editIdx >= s.chatProfiles.length ? null : () => s.removeChatProfile(_editIdx),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: c.textTertiary,
                ),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _url, decoration: InputDecoration(labelText: 'API 地址', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary))),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: _fullUrl,
                onChanged: (v) => setState(() => _fullUrl = v ?? false),
                title: Text('完整 URL', style: TextStyle(fontSize: 13.5, color: c.text)),
                subtitle: Text('关闭时自动在地址后添加 /chat/completions', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 12),
              TextField(controller: _key, obscureText: true, decoration: InputDecoration(labelText: 'API Key', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary))),
              const SizedBox(height: 12),
              TextField(controller: _modelCtrl, decoration: InputDecoration(labelText: '模型', hintText: '输入模型名称，如 gpt-4o', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary), hintStyle: TextStyle(color: c.inputHint))),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _temp,
                decoration: InputDecoration(labelText: '温度', isDense: true, border: const OutlineInputBorder(), labelStyle: TextStyle(color: c.textSecondary)),
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('厂家默认')),
                  DropdownMenuItem(value: '0', child: Text('精确 (0)')),
                  DropdownMenuItem(value: '0.3', child: Text('保守 (0.3)')),
                  DropdownMenuItem(value: '0.7', child: Text('均衡 (0.7)')),
                  DropdownMenuItem(value: '1.0', child: Text('创意 (1.0)')),
                ],
                onChanged: (v) => setState(() => _temp = v ?? _temp),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _vision,
                onChanged: (v) => setState(() => _vision = v ?? false),
                title: Text('图形能力（支持上传图片）', style: TextStyle(fontSize: 13.5, color: c.text)),
                subtitle: Text('开启后对话中可上传图片给 AI 识别；关闭时上传的图片显示为黑色占位', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(height: 24),
            ],
            CheckboxListTile(
              value: _showReasoning,
              onChanged: (v) => setState(() => _showReasoning = v ?? false),
              title: Text('显示思考过程', style: TextStyle(fontSize: 14, color: c.text)),
              subtitle: Text('开启后，AI 回答前会展开显示其思考过程（需模型支持）', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            CheckboxListTile(
              value: _stream,
              onChanged: (v) => setState(() => _stream = v ?? false),
              title: Text('流式输出', style: TextStyle(fontSize: 14, color: c.text)),
              subtitle: Text('开启后逐字显示回复', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _primary),
              onPressed: () {
                s.saveChatSettings(
                  independent: _independent,
                  config: ApiConfig(url: _url.text.trim(), key: _key.text.trim(), model: _modelCtrl.text.trim(), temperature: _temp, vision: _vision, fullUrl: _fullUrl),
                  showReasoning: _showReasoning,
                  stream: _stream,
                );
                // 独立配置开启时，把当前表单同步到对话配置库并设为选中
                if (_independent) _saveConfig(s);
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
