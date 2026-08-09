/// 全局设置弹窗：左侧导航栏 + 右侧分区
library;

import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
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
  // API 配置字段（沿用原来）
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _modelCtrl;
  late String _temp;
  late bool _vision;
  late bool _fullUrl;
  late int _editIdx;
  bool _obscureKey = true;

  /// 左侧设置分组：'model' | 'general' | 'account' | 'advanced'
  String _section = 'model';

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

  void _onStateChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    AppScope.of(context).removeListener(_onStateChanged);
    _url.dispose();
    _key.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

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

  void _deleteConfig(AppState s) {
    if (_editIdx < 0 || _editIdx >= s.apiProfiles.length) return;
    final profiles = List.of(s.apiProfiles)..removeAt(_editIdx);
    final activeIdx = profiles.isEmpty ? -1 : (_editIdx < profiles.length ? _editIdx : profiles.length - 1);
    s.saveApiProfiles(profiles, activeIdx);
    setState(() { _editIdx = -1; _loadFrom(ApiConfig()); });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    // p4 卡片风格：纯白/深灰不透明背景 + 圆角 + 柔和阴影
    final isLight = c.isLight;
    final cardBg = isLight ? const Color(0xFFF4F4F8) : const Color(0xFF2A2A32);
    final sidebarBg = isLight ? const Color(0xFFF4F4F8) : const Color(0xFF222228);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 760,
        height: 640,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.06 : 0.35),
              blurRadius: 32,
              offset: const Offset(0, 10),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Row(children: [
          // ============ 左侧导航 ============
          Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
            decoration: BoxDecoration(
              color: sidebarBg,
              border: Border(right: BorderSide(color: c.border.withValues(alpha: 0.5), width: 1)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              _navItem(Icons.extension_outlined, '模型与界面', 'model', c),
              _navItem(Icons.settings_outlined, '通用设置', 'general', c),
              _navItem(Icons.shield_outlined, '账户安全', 'account', c),
              _navItem(Icons.hub_outlined, '高级功能', 'advanced', c),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('AFloat · v1.0', style: TextStyle(fontSize: 11, color: c.textTertiary)),
              ),
            ]),
          ),
          // ============ 右侧内容 ============
          Expanded(child: Container(
            color: cardBg,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: _buildSection(s, c),
            ),
          )),
        ]),
      ),
    );
  }

  // ---- 左侧导航条目 ----
  Widget _navItem(IconData icon, String label, String key, AppColors c) {
    final selected = _section == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _section = key),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected ? c.primaryBg.withValues(alpha: c.isLight ? 0.75 : 0.28) : Colors.transparent,
            ),
            child: Row(children: [
              Icon(icon, size: 18, color: selected ? c.primaryText : c.textSecondary),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? c.primaryText : c.textSecondary)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- 按 section 构建右侧 ----
  Widget _buildSection(AppState s, AppColors c) {
    switch (_section) {
      case 'model':   return _sectionModel(s, c);
      case 'general': return _sectionGeneral(s, c);
      case 'account': return _sectionAccount(s, c);
      case 'advanced':return _sectionAdvanced(s, c);
      default: return const SizedBox.shrink();
    }
  }

  // ============== Section 1: 模型与界面 ==============
  Widget _sectionModel(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('模型配置', c),
      const SizedBox(height: 14),
      // 配置库下拉 + 删除
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey(_editIdx),
            initialValue: _editIdx,
            decoration: InputDecoration(
              isDense: true, labelText: '已保存的配置', labelStyle: TextStyle(color: c.textSecondary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.border)),
            ),
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
          tooltip: '删除当前配置', onPressed: s.apiProfiles.isEmpty || _editIdx < 0 || _editIdx >= s.apiProfiles.length ? null : () => _deleteConfig(s),
          icon: Icon(Icons.delete_outline_rounded, size: 20, color: c.textTertiary),
        ),
      ]),
      const SizedBox(height: 12),
      // API 地址
      _labeledField('API 地址', TextField(
        controller: _url,
        decoration: _deco(c, hint: 'https://api.openai.com/v1'),
      ), c),
      const SizedBox(height: 4),
      Row(children: [
        Checkbox(value: _fullUrl, onChanged: (v) => setState(() => _fullUrl = v ?? false)),
        const SizedBox(width: 4),
        Expanded(child: Text('完整 URL（关闭时自动添加 /chat/completions）', style: TextStyle(fontSize: 12, color: c.textTertiary))),
      ]),
      const SizedBox(height: 12),
      // API Key（带复制 + 明/暗切换）
      _labeledField(
        'API Key',
        TextField(
          controller: _key,
          obscureText: _obscureKey,
          decoration: _deco(c, hint: 'sk-...').copyWith(
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: '复制',
                onPressed: () { if (_key.text.isNotEmpty) Clipboard.setData(ClipboardData(text: _key.text)); },
                icon: Icon(Icons.copy_rounded, size: 18, color: c.textTertiary),
              ),
              IconButton(
                tooltip: _obscureKey ? '显示' : '隐藏',
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
                icon: Icon(_obscureKey ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: c.textTertiary),
              ),
            ]),
          ),
        ),
        c,
      ),
      const SizedBox(height: 12),
      // 模型
      _labeledField('模型', TextField(controller: _modelCtrl, decoration: _deco(c, hint: '例如 qwen3.7-plus')), c),
      const SizedBox(height: 12),
      // 温度下拉
      _labeledField(
        '温度',
        DropdownButtonFormField<String>(
          value: _temp,
          decoration: _deco(c),
          items: const [
            DropdownMenuItem(value: 'default', child: Text('厂家默认')),
            DropdownMenuItem(value: '0', child: Text('精确 (0)')),
            DropdownMenuItem(value: '0.3', child: Text('保守 (0.3)')),
            DropdownMenuItem(value: '0.7', child: Text('均衡 (0.7)')),
            DropdownMenuItem(value: '1.0', child: Text('创意 (1.0)')),
          ],
          onChanged: (v) => setState(() => _temp = v ?? _temp),
        ),
        c,
      ),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text('温度值越低答案越准确、越随机度低；厂家默认最稳', style: TextStyle(fontSize: 11, color: c.textTertiary)),
      ),
      const SizedBox(height: 12),
      // 图形能力
      _SwitchRow(
        icon: Icons.image_outlined,
        title: '图形能力',
        subtitle: '开启后支持图片上传与 AI 识别',
        subtitle2: '开启后支持图片上传为 AI 识别。',
        value: _vision,
        onChanged: (v) => setState(() => _vision = v),
        c: c,
      ),
      const SizedBox(height: 18),
      // 保存按钮（紫色胶囊全宽）
      SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          onPressed: () {
            _saveConfig(s);
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
          },
          child: const Text('保存'),
        ),
      ),
      const SizedBox(height: 26),
      // ---- 界面与风格 ----
      _sectionTitle('界面与风格', c),
      const SizedBox(height: 14),
      // 界面模式
      _settingRow('界面模式', c, child: Row(children: [
        _buildChip2(s.uiMode.isEmpty ? 'desktop' : s.uiMode, 'desktop', '电脑端', s, c, (v) => s.setUiMode(v)),
        const SizedBox(width: 10),
        _buildChip2(s.uiMode.isEmpty ? 'desktop' : s.uiMode, 'mobile', '手机端', s, c, (v) => s.setUiMode(v)),
      ]), hint: '切换后立即生效，也可按 F8 快速切换'),
      const SizedBox(height: 14),
      // 深色模式
      _SwitchRow(
        icon: Icons.dark_mode_outlined,
        title: '深色模式',
        subtitle: '开启后使用深色界面，与侧边栏月亮/太阳图标同步',
        value: s.darkMode,
        onChanged: (v) => s.toggleDarkMode(v),
        c: c,
      ),
      const SizedBox(height: 14),
      // 界面风格：纯文字选项（与导航指示器样式一致）
      _settingRow('界面风格', c, child: Row(children: [
        _buildChip2(s.uiStyle, 'classic', '经典', s, c, (v) => s.setUiStyle(v)),
        const SizedBox(width: 10),
        _buildChip2(s.uiStyle, 'glass', '毛玻璃', s, c, (v) => s.setUiStyle(v)),
      ])),
      const SizedBox(height: 14),
      // 导航指示器
      _settingRow('导航指示器', c, child: Row(children: [
        _buildChip2(s.navIndicator, 'underline', '灰色下划线', s, c, (v) => s.setNavIndicator(v)),
        const SizedBox(width: 10),
        _buildChip2(s.navIndicator, 'pill', '紫色渐变胶囊', s, c, (v) => s.setNavIndicator(v)),
      ]), hint: '控制侧边栏选中项的视觉表现'),
    ]);
  }

  // ============== Section 2: 通用设置 ==============
  Widget _sectionGeneral(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('通用设置', c),
      const SizedBox(height: 14),
      CheckboxListTile(
        value: s.fullscreen,
        onChanged: (v) {
          Navigator.of(context).pop();
          Future.delayed(const Duration(milliseconds: 200), () => s.toggleFullscreen(v ?? false));
        },
        title: Text('全屏模式', style: TextStyle(fontSize: 14, color: c.text)),
        subtitle: Text('开启后进入全屏，按 F11 可快速切换', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        value: s.powerSavingMode,
        onChanged: (v) => s.togglePowerSavingMode(v ?? true),
        title: Text('省电模式', style: TextStyle(fontSize: 14, color: c.text)),
        subtitle: Text('开启后锁定60帧以节省电量，关闭后支持120帧高刷', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 6),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.replay_rounded, size: 20, color: c.textTertiary),
        title: Text('重新查看引导', style: TextStyle(fontSize: 14, color: c.text)),
        subtitle: Text('再次打开首次启动的快速引导向导', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
        onTap: () { Navigator.of(context).pop(); s.resetOnboarding(); },
      ),
      const SizedBox(height: 22),
      _sectionTitle('数据备份', c),
      const SizedBox(height: 6),
      Text('备份包含 API 配置、收藏、错题本、学习记录、生词本等；API Key 敏感，请妥善保管', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
      const SizedBox(height: 12),
      Row(children: [
        OutlinedButton.icon(onPressed: () => _export(s), icon: const Icon(Icons.download, size: 16), label: const Text('导出备份')),
        const SizedBox(width: 10),
        OutlinedButton.icon(onPressed: () => _import(s), icon: const Icon(Icons.upload, size: 16), label: const Text('导入备份')),
      ]),
    ]);
  }

  // ============== Section 3: 账户安全 ==============
  Widget _sectionAccount(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('账户安全', c),
      const SizedBox(height: 14),
      _emptyHint('账户与云同步功能正在规划中…', c),
    ]);
  }

  // ============== Section 4: 高级功能 ==============
  Widget _sectionAdvanced(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('高级功能', c),
      const SizedBox(height: 14),
      _emptyHint('高级功能正在开发中…', c),
    ]);
  }

  // ============== 小组件 ==============

  Widget _sectionTitle(String t, AppColors c) => Text(t, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text, letterSpacing: 0.2));

  Widget _emptyHint(String t, AppColors c) {
    final isLight = c.isLight;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isLight ? Colors.white : const Color(0xFF33333A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: Column(children: [
        Icon(Icons.construction_outlined, size: 40, color: c.textTertiary),
        const SizedBox(height: 10),
        Text(t, style: TextStyle(fontSize: 13, color: c.textTertiary)),
      ])),
    );
  }

  InputDecoration _deco(AppColors c, {String? hint}) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: c.inputHint),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
  );

  Widget _labeledField(String label, Widget field, AppColors c) {
    final isLight = c.isLight;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 2, bottom: 6), child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF)))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF33333A),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: field,
      ),
    ]);
  }

  Widget _settingRow(String label, AppColors c, {required Widget child, String? hint}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
    const SizedBox(height: 8),
    child,
    if (hint != null) const SizedBox(height: 4),
    if (hint != null) Padding(padding: const EdgeInsets.only(left: 2), child: Text(hint, style: TextStyle(fontSize: 11, color: c.textTertiary))),
  ]);

  Widget _buildChip2(String current, String value, String label, AppState s, AppColors c, ValueChanged<String> onTap) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? c.primaryBg : c.chipUnselected,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? _primary : c.chipBorder, width: 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? c.primaryText : c.textSecondary)),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份已导出到 $path'), duration: const Duration(seconds: 3), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e'), behavior: SnackBarBehavior.floating));
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
          title: const Text('导入备份'), content: const Text('导入将覆盖当前收藏、错题本、学习记录、生词本、记录本等数据，确定继续吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确认导入')),
          ],
        ),
      );
      if (confirmed != true) return;
      final ok = s.importBackup(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? '导入成功' : '导入失败：文件格式不正确'), behavior: SnackBarBehavior.floating));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e'), behavior: SnackBarBehavior.floating));
    }
  }
}

// 带图标 + 大开关的行（用于：图形能力、深色模式）
class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? subtitle2;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AppColors c;
  const _SwitchRow({required this.icon, required this.title, required this.subtitle, this.subtitle2, required this.value, required this.onChanged, required this.c});

  @override
  Widget build(BuildContext context) {
    final isLight = c.isLight;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF33333A),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Icon(icon, size: 22, color: c.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
            if (subtitle2 != null) ...[
              const SizedBox(height: 2),
              Text(subtitle2!, style: TextStyle(fontSize: 11, color: c.textTertiary)),
            ],
          ]),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: _primary,
          activeTrackColor: _primary.withValues(alpha: 0.4),
        ),
      ]),
    );
  }
}

// 界面风格预览卡片（经典=方形图标；毛玻璃=渐变方形图标）
class _StylePreviewCard extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final AppState s;
  final AppColors c;
  const _StylePreviewCard({required this.value, required this.label, required this.selected, required this.s, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => s.setUiStyle(value),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 160, height: 110,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: c.card,
            border: Border.all(color: selected ? _primary : c.border, width: selected ? 1.6 : 1),
            boxShadow: selected ? [BoxShadow(color: _primary.withValues(alpha: 0.2), blurRadius: 14, offset: const Offset(0, 4))] : null,
          ),
          child: value == 'classic'
              ? Center(child: Icon(Icons.grid_3x3_outlined, size: 42, color: c.textSecondary))
              : Center(
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF0E8FF), Color(0xFFC4B5FD), Color(0xFFA78BFA)]),
                    ),
                    child: Center(child: Icon(Icons.circle_outlined, color: Colors.white, size: 20)),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Padding(padding: const EdgeInsets.only(left: 2), child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? _primary : c.textSecondary))),
      ]),
    );
  }
}

// ---- 占位类：原来的 Clipboard / Data / Random 工具 ----
// 防止旧代码 import 报错的哑类型（若后面有 ChatSettingsDialog 需要保留则在下方继续写）

/// 对话助手独立设置弹窗
class ChatSettingsDialog extends StatefulWidget {
  const ChatSettingsDialog({super.key});

  @override
  State<ChatSettingsDialog> createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> {
  @override
  Widget build(BuildContext context) {
    // 占位实现：原 ChatSettingsDialog 暂未启用，先返回简易提示
    // 避免旧调用点崩溃。需要正式实现时可参考 _SettingsDialogState 重建。
    return AlertDialog(
      title: const Text('对话助手设置'),
      content: const Text('该功能暂未实现，请使用主设置中心配置对话助手。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('关闭')),
      ],
    );
  }
}
