/// 全局设置弹窗：左侧导航栏 + 右侧分区
library;

import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, AppColors;
import 'learn_page.dart' show AppScope;
import '../services/skill_store.dart' show AgentSkill;

const _primary = kPrimary;

const _models = ['gpt-5.1', 'gpt-5.1-instant', 'gpt-5.5', 'gpt-4o', 'deepseek-v4-flash', 'deepseek-v4-pro', 'kimi', 'longcat'];

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
  late int _contextLen;
  late bool _vision;
  late bool _fullUrl;
  late String _questionMode;
  late String _questionSpeed;
  late int _editIdx;
  bool _obscureKey = true;
  // 墨墨同步
  late final TextEditingController _maimemoTokenCtrl;
  bool _maimemoObscure = true;
  bool _maimemoBusy = false;
  String? _maimemoMsg; // 同步结果提示

  // 联网搜索服务
  late final TextEditingController _searchUrlCtrl;
  late final TextEditingController _searchKeyCtrl;
  bool _searchObscure = true;

  /// 设置分组：手机 'home'=入口列表页；桌面与手机子页：
  /// 'model' 模型设置 | 'interface' 界面设置 | 'account' 账户安全 | 'advanced' 高级功能
  String _section = 'home';

  @override
  void initState() {
    super.initState();
    // 根据初始屏幕宽度决定默认展示入口页（手机）还是直接展示模型设置（桌面）
    final width = MediaQuery.of(context).size.width;
    _section = width < 600 ? 'home' : 'model';
    final s = AppScope.of(context);
    _editIdx = s.apiProfiles.indexWhere((p) => p.config.url == s.apiConfig.url && p.config.key == s.apiConfig.key);
    _url = TextEditingController(text: s.apiConfig.url);
    _key = TextEditingController(text: s.apiConfig.key);
    _modelCtrl = TextEditingController(text: s.apiConfig.model);
    _temp = s.apiConfig.temperature.isEmpty ? '0.3' : s.apiConfig.temperature;
    _contextLen = s.apiConfig.contextLength > 0 ? s.apiConfig.contextLength : 200000;
    _vision = s.apiConfig.vision;
    _fullUrl = s.apiConfig.fullUrl;
    _questionMode = s.apiConfig.questionMode.isEmpty ? 'auto' : s.apiConfig.questionMode;
    _questionSpeed = s.apiConfig.questionSpeed.isEmpty ? 'fast' : s.apiConfig.questionSpeed;
    _maimemoTokenCtrl = TextEditingController(text: s.maimemoToken);
    _searchUrlCtrl = TextEditingController(text: s.searchUrl);
    _searchKeyCtrl = TextEditingController(text: s.searchKey);
    s.addListener(_onStateChanged);
  }

  void _onStateChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    AppScope.of(context).removeListener(_onStateChanged);
    _url.dispose();
    _key.dispose();
    _modelCtrl.dispose();
    _maimemoTokenCtrl.dispose();
    _searchUrlCtrl.dispose();
    _searchKeyCtrl.dispose();
    super.dispose();
  }

  void _loadFrom(ApiConfig c) {
    _url.text = c.url;
    _key.text = c.key;
    _modelCtrl.text = c.model;
    setState(() {
      _temp = c.temperature.isEmpty ? '0.3' : c.temperature;
      _contextLen = c.contextLength > 0 ? c.contextLength : 200000;
      _vision = c.vision;
      _fullUrl = c.fullUrl;
      _questionMode = c.questionMode.isEmpty ? 'auto' : c.questionMode;
      _questionSpeed = c.questionSpeed.isEmpty ? 'fast' : c.questionSpeed;
    });
  }

  void _saveConfig(AppState s) {
    final c = ApiConfig(url: _url.text.trim(), key: _key.text.trim(), model: _modelCtrl.text.trim(), temperature: _temp, vision: _vision, fullUrl: _fullUrl, questionMode: _questionMode, questionSpeed: _questionSpeed, contextLength: _contextLen);
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
    final isLight = c.isLight;
    // 桌面端 SettingsDialog 容器色（dark 模式略调亮，避免"全黑"观感）
    final cardBg = isLight ? const Color(0xFFF4F4F8) : const Color(0xFF1E1E22);
    final sidebarBg = isLight ? const Color(0xFFF4F4F8) : const Color(0xFF18181C);
    // 参考图二：右侧内容区白底，设置行用浅灰卡片
    final contentBg = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF232328);

    // 检测是否为小屏（手机）
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      if (_section == 'home') {
        // 手机端：分组入口列表（参考样式：白底圆角卡片分组 + 右侧箭头，点击进子页）
        return Scaffold(
          backgroundColor: isLight ? const Color(0xFFEDEEF3) : const Color(0xFF1A1A1E),
          appBar: AppBar(
            backgroundColor: isLight ? const Color(0xFFEDEEF3) : const Color(0xFF1A1A1E),
            elevation: 0,
            titleSpacing: 4,
            title: Text('设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text)),
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: c.text),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _mobileGroup(c, const [
                ['model', '模型设置'],
                ['interface', '界面设置'],
              ]),
              const SizedBox(height: 10),
              _mobileGroup(c, const [
                ['skills', '技能管理'],
                ['account', '账户安全'],
                ['advanced', '高级功能'],
              ]),
            ],
          ),
        );
      }
      // 手机端子页：返回箭头 + 分区标题 + 分区内容
      final title = switch (_section) {
        'model' => '模型设置',
        'interface' => '界面设置',
        'skills' => '技能管理',
        'account' => '账户安全',
        _ => '高级功能',
      };
      return Scaffold(
        backgroundColor: isLight ? const Color(0xFFEDEEF3) : const Color(0xFF1A1A1E),
        appBar: AppBar(
          backgroundColor: isLight ? const Color(0xFFEDEEF3) : const Color(0xFF1A1A1E),
          elevation: 0,
          titleSpacing: 4,
          title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: c.text),
            onPressed: () => setState(() => _section = 'home'),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: _buildSection(s, c),
        ),
      );
    }

    // 桌面端：左右分栏 Dialog
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
              _navItem(ColorFiltered(
                colorFilter: ColorFilter.mode(c.text, BlendMode.srcIn),
                child: Image.asset('assets/icons/model_settings.png', width: 18, height: 18, filterQuality: FilterQuality.high),
              ), '模型设置', 'model', c),
              _navItem(Icon(Icons.palette_outlined, size: 18, color: c.text), '界面设置', 'interface', c),
              _navItem(Icon(Icons.auto_awesome_outlined, size: 18, color: c.text), '技能管理', 'skills', c),
              _navItem(Icon(Icons.shield_outlined, size: 18, color: c.text), '账户安全', 'account', c),
              _navItem(Icon(Icons.hub_outlined, size: 18, color: c.text), '高级功能', 'advanced', c),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('AFloat · v1.0', style: TextStyle(fontSize: 11, color: c.textTertiary)),
              ),
            ]),
          ),
          // ============ 右侧内容（参考图二：顶部标题 + 关闭按钮，卡片式设置行） ============
          Expanded(child: Container(
            color: contentBg,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 22, 16, 12),
                child: Row(children: [
                  Expanded(child: Text('设置', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.text))),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: c.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                  child: _buildSection(s, c),
                ),
              ),
            ]),
          )),
        ]),
      ),
    );
  }

  /// 手机端分组卡片：纯白圆角，组内条目以 1px 浅色分隔线隔开（贴近参考图一）
  Widget _mobileGroup(AppColors c, List<List<String>> entries) {
    final isLight = c.isLight;
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      children.add(_mobileEntry(c, entries[i][0], entries[i][1]));
      if (i < entries.length - 1) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Divider(height: 1, thickness: 1, color: isLight ? const Color(0xFFEEEEEE) : const Color(0xFF2F2F35)),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF232328),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isLight
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  /// 手机端分组条目：标题 + 右箭头
  Widget _mobileEntry(AppColors c, String key, String label) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _section = key),
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 15, color: c.text)),
              ),
              Icon(Icons.chevron_right_rounded, size: 22, color: c.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- 左侧导航条目（参考图二：选中为灰底圆角 + 深色文字） ----
  Widget _navItem(Widget icon, String label, String key, AppColors c) {
    final selected = _section == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _section = key),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: selected ? (c.isLight ? const Color(0xFFE4E4E8) : const Color(0xFF35353C)) : Colors.transparent,
            ),
            child: Row(children: [
              icon,
              const SizedBox(width: 10),
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: c.text)),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- 按 section 构建右侧 / 手机子页内容 ----
  Widget _buildSection(AppState s, AppColors c) {
    switch (_section) {
      case 'model':     return _sectionModelContent(s, c);
      case 'interface': return _sectionInterfaceContent(s, c);
      case 'skills':    return _sectionSkillsContent(s, c);
      case 'account':   return _sectionAccountContent(s, c);
      case 'advanced':  return _sectionAdvanced(s, c);
      default:          return _sectionModelContent(s, c);
    }
  }

  // ============== Section: 模型设置 ==============
  Widget _sectionModelContent(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('模型设置', c),
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
        Expanded(child: Text('完整 URL', style: TextStyle(fontSize: 12, color: c.textSecondary))),
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
            DropdownMenuItem(value: '0', child: Text('精确 (0)')),
            DropdownMenuItem(value: '0.3', child: Text('保守 (0.3)')),
            DropdownMenuItem(value: '0.7', child: Text('均衡 (0.7)')),
            DropdownMenuItem(value: '1.0', child: Text('创意 (1.0)')),
          ],
          onChanged: (v) => setState(() => _temp = v ?? _temp),
        ),
        c,
      ),
      const SizedBox(height: 12),
      // 上下文长度
      _labeledField(
        '上下文长度',
        DropdownButtonFormField<int>(
          value: _contextLen,
          decoration: _deco(c, hint: '默认 200K'),
          items: const [
            DropdownMenuItem(value: 32000, child: Text('32K')),
            DropdownMenuItem(value: 64000, child: Text('64K')),
            DropdownMenuItem(value: 128000, child: Text('128K')),
            DropdownMenuItem(value: 200000, child: Text('200K（默认）')),
            DropdownMenuItem(value: 1000000, child: Text('1000K（1M）')),
          ],
          onChanged: (v) => setState(() => _contextLen = v ?? _contextLen),
        ),
        c,
      ),
      const SizedBox(height: 12),
      // 出题策略
      _labeledField(
        '出题策略',
        DropdownButtonFormField<String>(
          value: _questionMode,
          decoration: _deco(c),
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('自动（JSON优先，失败自动切换文本格式）')),
            DropdownMenuItem(value: 'json', child: Text('仅 JSON')),
            DropdownMenuItem(value: 'text', child: Text('仅文本行格式')),
          ],
          onChanged: (v) => setState(() => _questionMode = v ?? _questionMode),
        ),
        c,
      ),
      const SizedBox(height: 12),
      // 出题速度
      _labeledField(
        '出题速度',
        DropdownButtonFormField<String>(
          value: _questionSpeed,
          decoration: _deco(c),
          items: const [
            DropdownMenuItem(value: 'fast', child: Text('快速')),
            DropdownMenuItem(value: 'normal', child: Text('正常')),
          ],
          onChanged: (v) => setState(() => _questionSpeed = v ?? _questionSpeed),
        ),
        c,
      ),
      const SizedBox(height: 12),
      // 图形能力
      _SwitchRow(
        icon: Icons.image_outlined,
        title: '图形能力',
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
    ]);
  }

  // ============== Section: 界面设置（界面设置与通用设置融合，不含数据备份） ==============
  Widget _sectionInterfaceContent(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('界面设置', c),
      const SizedBox(height: 14),
      // 界面模式
      _settingRow('界面模式', c, child: Wrap(spacing: 10, runSpacing: 8, children: [
        _buildChip2(s.uiMode.isEmpty ? 'desktop' : s.uiMode, 'desktop', '电脑端', s, c, (v) => s.setUiMode(v)),
        _buildChip2(s.uiMode.isEmpty ? 'desktop' : s.uiMode, 'mobile', '手机端', s, c, (v) => s.setUiMode(v)),
      ])),
      const SizedBox(height: 14),
      // 主题（第三大主题：经典 / 毛玻璃 / 深色）
      _settingRow('主题', c, child: Wrap(spacing: 10, runSpacing: 8, children: [
        _buildChip2(s.darkMode ? 'dark' : s.uiStyle, 'classic', '经典', s, c, (_) => s.setThemeStyle('classic')),
        _buildChip2(s.darkMode ? 'dark' : s.uiStyle, 'glass', '毛玻璃', s, c, (_) => s.setThemeStyle('glass')),
        _buildChip2(s.darkMode ? 'dark' : s.uiStyle, 'dark', '深色', s, c, (_) => s.setThemeStyle('dark')),
      ])),
      const SizedBox(height: 14),
      // 导航指示器
      _settingRow('导航指示器', c, child: Wrap(spacing: 10, runSpacing: 8, children: [
        _buildChip2(s.navIndicator, 'underline', '灰色下划线', s, c, (v) => s.setNavIndicator(v)),
        _buildChip2(s.navIndicator, 'pill', '紫色渐变胶囊', s, c, (v) => s.setNavIndicator(v)),
      ])),
      const SizedBox(height: 18),
      CheckboxListTile(
        value: s.fullscreen,
        onChanged: (v) {
          Navigator.of(context).pop();
          Future.delayed(const Duration(milliseconds: 200), () => s.toggleFullscreen(v ?? false));
        },
        title: Text('全屏模式', style: TextStyle(fontSize: 14, color: c.text)),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 6),
      CheckboxListTile(
        value: s.powerSavingMode,
        onChanged: (v) => s.togglePowerSavingMode(v ?? false),
        title: Text('省电模式', style: TextStyle(fontSize: 14, color: c.text)),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 6),
      _SwitchRow(
        icon: Icons.speed_rounded,
        title: '高性能模式',
        value: s.highPerformanceMode,
        onChanged: (v) => s.toggleHighPerformanceMode(v),
        c: c,
      ),
      const SizedBox(height: 6),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.replay_rounded, size: 20, color: c.textTertiary),
        title: Text('重新查看引导', style: TextStyle(fontSize: 14, color: c.text)),
        onTap: () { Navigator.of(context).pop(); s.resetOnboarding(); },
      ),
    ]);
  }

  // ============== 统一卡片容器（参考图二：图标 + 标题 + 内容） ==============
  Widget _settingsCard({
    required AppColors c,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF2E2E35),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isLight ? 0.04 : 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 22, color: _primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  // ============== Section: 账户安全（含数据备份、墨墨、联网） ==============
  Widget _sectionAccountContent(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('账户安全', c),
      const SizedBox(height: 14),
      _buildBackupCard(s, c),
      const SizedBox(height: 22),
      _buildMaimemoCard(s, c),
      const SizedBox(height: 22),
      _buildSearchCard(s, c),
    ]);
  }

  // ============== 数据备份卡片 ==============
  Widget _buildBackupCard(AppState s, AppColors c) {
    return _settingsCard(
      c: c,
      icon: Icons.cloud_sync_outlined,
      title: '数据备份',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _backup(s),
            icon: const Icon(Icons.save_alt, size: 16),
            label: const Text('一键备份数据'),
            style: FilledButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _export(s), icon: const Icon(Icons.download, size: 16), label: const Text('导出备份'))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: () => _import(s), icon: const Icon(Icons.upload, size: 16), label: const Text('导入备份'))),
        ]),
      ]),
    );
  }

  // ============== 墨墨同步卡片 ==============
  Widget _buildMaimemoCard(AppState s, AppColors c) {
    return _settingsCard(
      c: c,
      icon: Icons.auto_stories_outlined,
      title: '墨墨背单词同步',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _maimemoTokenCtrl,
          obscureText: _maimemoObscure,
          style: TextStyle(fontSize: 13, color: c.text),
          decoration: _deco(c, hint: '墨墨 App「实验功能 → 开放 API」获取').copyWith(
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: _maimemoObscure ? '显示' : '隐藏',
                onPressed: () => setState(() => _maimemoObscure = !_maimemoObscure),
                icon: Icon(_maimemoObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: c.textTertiary),
              ),
            ]),
          ),
          onChanged: (_) {
            s.setMaimemoToken(_maimemoTokenCtrl.text);
            setState(() {});
          },
        ),
        const SizedBox(height: 10),
        if (s.maimemoToken.isNotEmpty) ...[
          _maimemoStatusLine(s, c),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          height: 42,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: s.maimemoToken.trim().isEmpty || _maimemoBusy
                ? null
                : () => _syncMaimemo(s),
            child: _maimemoBusy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    s.maimemoLastSync > 0 ? '再次同步今日单词' : '同步今日单词',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
        if (_maimemoMsg != null) ...[
          const SizedBox(height: 8),
          Text(_maimemoMsg!, style: TextStyle(fontSize: 12, color: _maimemoMsg!.contains('失败') || _maimemoMsg!.contains('错误') ? const Color(0xFFDC2626) : const Color(0xFF16A34A))),
        ],
      ]),
    );
  }

  // ============== 联网搜索卡片 ==============
  Widget _buildSearchCard(AppState s, AppColors c) {
    return _settingsCard(
      c: c,
      icon: Icons.travel_explore,
      title: '联网搜索服务',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _searchUrlCtrl,
          style: TextStyle(fontSize: 13, color: c.text),
          decoration: _deco(c, hint: '搜索服务地址'),
          onChanged: (_) {
            s.setSearchConfig(_searchUrlCtrl.text, _searchKeyCtrl.text);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchKeyCtrl,
          obscureText: _searchObscure,
          style: TextStyle(fontSize: 13, color: c.text),
          decoration: _deco(c, hint: 'AppBuilder API Key').copyWith(
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: _searchObscure ? '显示' : '隐藏',
                onPressed: () => setState(() => _searchObscure = !_searchObscure),
                icon: Icon(_searchObscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18, color: c.textTertiary),
              ),
            ]),
          ),
          onChanged: (_) {
            s.setSearchConfig(_searchUrlCtrl.text, _searchKeyCtrl.text);
          },
        ),
      ]),
    );
  }

  Widget _maimemoStatusLine(AppState s, AppColors c) {
    final items = <Widget>[
      _miniStat(c, '累计同步', '${s.maimemoSyncedCount}'),
    ];
    if (s.maimemoProgress != null) {
      items.add(const SizedBox(width: 16));
      items.add(_miniStat(c, '今日墨墨', '${s.maimemoProgress!.finished}/${s.maimemoProgress!.total}'));
    }
    if (s.maimemoLastSync > 0) {
      items.add(const SizedBox(width: 16));
      final dt = DateTime.fromMillisecondsSinceEpoch(s.maimemoLastSync);
      items.add(_miniStat(c, '上次同步', '${dt.month}-${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'));
    }
    return Wrap(spacing: 0, children: items);
  }

  Widget _miniStat(AppColors c, String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
      Text(label, style: TextStyle(fontSize: 10.5, color: c.textTertiary)),
    ]);
  }

  Future<void> _syncMaimemo(AppState s) async {
    setState(() {
      _maimemoBusy = true;
      _maimemoMsg = null;
    });
    try {
      final added = await s.syncMaimemoWords();
      if (!mounted) return;
      setState(() {
        _maimemoMsg = added > 0
            ? '同步成功，新增 $added 个今日已学习单词到墨墨词库'
            : '同步完成，今日已学习单词均已收录';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _maimemoMsg = '同步失败：$e';
      });
    } finally {
      if (mounted) setState(() => _maimemoBusy = false);
    }
  }

  // ============== Section: 技能管理 ==============
  Widget _sectionSkillsContent(AppState s, AppColors c) {
    final skills = s.skillStore.all;
    final enabledCount = skills.where((sk) => sk.enabled).length;
    // 按分类分组（保持插入顺序）
    final groups = <String, List<AgentSkill>>{};
    for (final sk in skills) {
      groups.putIfAbsent(sk.category, () => []).add(sk);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _sectionTitle('技能管理', c)),
        ElevatedButton.icon(
          onPressed: () => _showAddSkillDialog(s, c),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('添加技能', style: TextStyle(fontSize: 12.5)),
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Text(
        '共 ${skills.length} 个技能，已启用 $enabledCount 个。技能仅在 AI 需要时才加载完整指令（渐进式披露），不会占用对话上下文。',
        style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.5),
      ),
      const SizedBox(height: 14),
      if (!s.skillStore.loaded)
        const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 8),
            child: Text(entry.key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textSecondary)),
          ),
          ...entry.value.map((sk) => _skillCard(s, sk, c)),
        ],
      const SizedBox(height: 10),
      Text(
        '提示：部分技能（如智谱 GLM 系列）需要 ZHIPU_API_KEY 环境变量或对应服务的 API Key 才能实际执行；技能正文会指导 AI 如何调用。',
        style: TextStyle(fontSize: 11, color: c.textTertiary, height: 1.5),
      ),
    ]);
  }

  Widget _skillCard(AppState s, AgentSkill sk, AppColors c) {
    final isLight = c.isLight;
    final isCustom = sk.source == 'custom';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFFAFBFD) : const Color(0xFF2E2E35),
        borderRadius: BorderRadius.circular(12),
        border: sk.enabled ? null : Border.all(color: c.border.withValues(alpha: 0.6)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(sk.name, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: sk.enabled ? c.text : c.textTertiary), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              if (isCustom)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: _primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('自定义', style: TextStyle(fontSize: 9.5, color: _primary, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 4),
            Text(
              sk.description,
              style: TextStyle(fontSize: 11.5, color: sk.enabled ? c.textSecondary : c.textTertiary, height: 1.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(children: [
              GestureDetector(
                onTap: () => _showViewSkillDialog(sk, c),
                child: Row(children: [
                  Icon(Icons.visibility_outlined, size: 13, color: c.textTertiary),
                  const SizedBox(width: 3),
                  Text('查看', style: TextStyle(fontSize: 11, color: c.textTertiary)),
                ]),
              ),
              if (isCustom) ...[
                const SizedBox(width: 14),
                GestureDetector(
                  onTap: () {
                    s.skillStore.remove(sk.id);
                    s.notifyListeners();
                  },
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded, size: 13, color: c.textTertiary),
                    const SizedBox(width: 3),
                    Text('删除', style: TextStyle(fontSize: 11, color: c.textTertiary)),
                  ]),
                ),
              ],
            ]),
          ]),
        ),
        Switch(
          value: sk.enabled,
          onChanged: (v) {
            s.skillStore.setEnabled(sk.id, v);
            s.notifyListeners();
          },
          activeThumbColor: Colors.white,
          activeTrackColor: _kSwitchGreen,
        ),
      ]),
    );
  }

  void _showViewSkillDialog(AgentSkill sk, AppColors c) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 640,
          height: 560,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.isLight ? Colors.white : const Color(0xFF232328),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(sk.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text))),
              IconButton(icon: Icon(Icons.close_rounded, size: 18, color: c.textSecondary), onPressed: () => Navigator.of(ctx).pop()),
            ]),
            Text('${sk.category} · ${sk.id}', style: TextStyle(fontSize: 11, color: c.textTertiary)),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF1A1A1E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(sk.content, style: TextStyle(fontSize: 12, height: 1.7, color: c.text, fontFamily: 'Consolas')),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showAddSkillDialog(AppState s, AppColors c) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final catCtrl = TextEditingController(text: '自定义');
    final contentCtrl = TextEditingController();
    var error = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 640,
            height: 600,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.isLight ? Colors.white : const Color(0xFF232328),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('添加自定义技能', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
              const SizedBox(height: 4),
              Text('技能描述决定 AI 何时触发该技能；正文为完整指令（Markdown）', style: TextStyle(fontSize: 11, color: c.textTertiary)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _labeledField('技能名称', TextField(controller: nameCtrl, style: TextStyle(fontSize: 13, color: c.text), decoration: _deco(c, hint: '如：会议纪要专家')), c)),
                const SizedBox(width: 12),
                Expanded(child: _labeledField('分类', TextField(controller: catCtrl, style: TextStyle(fontSize: 13, color: c.text), decoration: _deco(c, hint: '自定义')), c)),
              ]),
              const SizedBox(height: 10),
              _labeledField(
                '触发描述（AI 依据它判断何时使用此技能）',
                TextField(controller: descCtrl, maxLines: 2, style: TextStyle(fontSize: 13, color: c.text), decoration: _deco(c, hint: '当用户要求…时使用此技能')),
                c,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _labeledField(
                  '技能正文（Markdown 指令）',
                  TextField(
                    controller: contentCtrl,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: TextStyle(fontSize: 12, color: c.text, fontFamily: 'Consolas'),
                    decoration: _deco(c, hint: '# 技能标题\n\n完整的工作流指令…'),
                  ),
                  c,
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                if (error.isNotEmpty) Expanded(child: Text(error, style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)), overflow: TextOverflow.ellipsis)),
                const Spacer(),
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) {
                      setDialog(() => error = '名称与正文不能为空');
                      return;
                    }
                    s.skillStore.addCustom(
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim().isEmpty ? '用户自定义技能：${nameCtrl.text.trim()}' : descCtrl.text.trim(),
                      category: catCtrl.text.trim(),
                      content: contentCtrl.text.trim(),
                    );
                    s.notifyListeners();
                    Navigator.of(ctx).pop();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
                  child: const Text('保存'),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ============== Section 4: 高级功能 ==============
  Widget _sectionAdvanced(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('高级功能', c),
      const SizedBox(height: 14),
      _SwitchRow(
        icon: Icons.bug_report_outlined,
        title: '开发者模式',
        value: s.devMode,
        onChanged: (v) => s.setDevMode(v),
        c: c,
      ),
      const SizedBox(height: 24),
      _sectionTitle('MCP 服务器 (dsh-mcp-client)', c),
      const SizedBox(height: 6),
      Text(
        '点击预置模板可一键添加常用 server（12306 车票查询 / Git 仓库 / GitHub），或用「自定义添加」填表添加。\n'
        '也支持直接编辑 JSON 数组；保存后会自动拉起并把它们的工具挂给 AI。\n'
        '注意：npx 模板需本机已安装 Node.js；uvx 模板需已安装 uv。',
        style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.5),
      ),
      const SizedBox(height: 10),
      _McpConfigEditor(s: s, c: c),
      const SizedBox(height: 10),
      if (s.mcpRegistry.clients.isNotEmpty)
        _McpStatusPanel(s: s, c: c)
      else if (s.mcpConfigJson.trim().isNotEmpty && s.mcpConfigJson.trim() != '[]')
        Text('配置存在但尚未拉起 server；点保存后重启对话。', style: TextStyle(fontSize: 11, color: c.textTertiary)),
    ]);
  }

  // ============== 小组件 ==============

  Widget _sectionTitle(String t, AppColors c) => Text(t, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text, letterSpacing: 0.2));

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

  Widget _settingRow(String label, AppColors c, {required Widget child}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text)),
    const SizedBox(height: 8),
    child,
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

  /// 一键备份：电脑保存到「下载」文件夹，手机保存到应用默认文件夹
  Future<void> _backup(AppState s) async {
    try {
      Directory? dir;
      if (Platform.isAndroid || Platform.isIOS) {
        // 手机：应用默认文件夹（Android 为应用专属外部存储）
        try {
          dir = await getExternalStorageDirectory();
        } catch (_) {
          dir = null;
        }
        dir ??= await getApplicationDocumentsDirectory();
      } else {
        // 电脑：系统「下载」文件夹
        dir = await getDownloadsDirectory();
        dir ??= (await getApplicationDocumentsDirectory());
      }
      final name = 'afloat-backup-${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.create(recursive: true);
      await file.writeAsString(s.buildBackupJson());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('备份已保存到 ${file.path}'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('备份失败：$e'), behavior: SnackBarBehavior.floating));
      }
    }
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

// MCP 配置编辑器（高级功能下方）
class _McpConfigEditor extends StatefulWidget {
  final AppState s;
  final AppColors c;
  const _McpConfigEditor({required this.s, required this.c});
  @override
  State<_McpConfigEditor> createState() => _McpConfigEditorState();
}

class _McpConfigEditorState extends State<_McpConfigEditor> {
  late TextEditingController _ctrl;
  String? _hint;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.s.mcpConfigJson);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 解析当前 JSON（失败返回 null）
  List<dynamic>? _parseCurrent() {
    try {
      final v = jsonDecode(_ctrl.text.trim().isEmpty ? '[]' : _ctrl.text);
      return v is List ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 把一个 server 配置合并进 JSON（按 name 去重）并立即保存重连
  Future<void> _mergeServer(String name, String command, List<String> args) async {
    final list = _parseCurrent();
    if (list == null) {
      setState(() => _hint = '当前 JSON 格式有误，请先修正后再添加');
      return;
    }
    list.removeWhere((e) => e is Map && e['name'] == name);
    list.add({'name': name, 'command': command, 'args': args, 'env': {}});
    _ctrl.text = jsonEncode(list);
    await _save();
    if (mounted) setState(() => _hint = '✓ 已添加 $name 并尝试连接');
  }

  Future<void> _save() async {
    try {
      await widget.s.setMcpConfigJson(_ctrl.text);
    } catch (e) {
      if (mounted) setState(() => _hint = '保存失败：$e');
    }
  }

  Widget _presetChip(String label, String name, String command, List<String> args, IconData icon) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: widget.c.textSecondary),
      label: Text(label, style: TextStyle(fontSize: 12, color: widget.c.text)),
      onPressed: () => _mergeServer(name, command, args),
    );
  }

  void _showAddServerDialog() {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController(text: 'npx');
    final argsCtrl = TextEditingController();
    final c = widget.c;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: c.isLight ? Colors.white : const Color(0xFF232328),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('添加 MCP 服务器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 4),
            Text('保存后会自动拉起 server 并把它的工具挂给 AI', style: TextStyle(fontSize: 11, color: c.textTertiary)),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, style: TextStyle(fontSize: 13, color: c.text), decoration: InputDecoration(labelText: '名称（如 12306-mcp）', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            TextField(controller: cmdCtrl, style: TextStyle(fontSize: 13, color: c.text), decoration: InputDecoration(labelText: '命令（如 npx / uvx / node）', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 12),
            TextField(controller: argsCtrl, style: TextStyle(fontSize: 13, color: c.text), decoration: InputDecoration(labelText: '参数（空格分隔，如 -y 12306-mcp）', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty || cmdCtrl.text.trim().isEmpty) return;
                  final args = argsCtrl.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
                  Navigator.of(ctx).pop();
                  await _mergeServer(name, cmdCtrl.text.trim(), args);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                child: const Text('添加并连接'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 预置模板 + 可视化添加
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _presetChip('12306 车票查询', '12306-mcp', 'npx', const ['-y', '12306-mcp'], Icons.train_rounded),
          _presetChip('Git 仓库', 'git', 'uvx', const ['mcp-server-git'], Icons.call_split_rounded),
          _presetChip('GitHub', 'github', 'npx', const ['-y', '@modelcontextprotocol/server-github'], Icons.code_rounded),
          ActionChip(
            avatar: Icon(Icons.add_rounded, size: 16, color: widget.c.textSecondary),
            label: Text('自定义添加', style: TextStyle(fontSize: 12, color: widget.c.text)),
            onPressed: _showAddServerDialog,
          ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(
          color: widget.c.isLight ? const Color(0xFFF1F2F4) : const Color(0xFF1A1A1F),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: widget.c.divider),
        ),
        child: TextField(
          controller: _ctrl,
          maxLines: 8,
          minLines: 4,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: widget.c.text,
          ),
          decoration: InputDecoration(
            hintText: '[{"name":"...","command":"...","args":[...],"env":{}}]',
            contentPadding: const EdgeInsets.all(12),
            border: InputBorder.none,
          ),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        ElevatedButton.icon(
          onPressed: () async {
            setState(() => _hint = null);
            try {
              await widget.s.setMcpConfigJson(_ctrl.text);
              if (mounted) setState(() => _hint = '✓ 已保存并尝试连接 ${widget.s.mcpRegistry.clients.length} 个 server');
            } catch (e) {
              if (mounted) setState(() => _hint = '保存失败：$e');
            }
          },
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('保存并重连'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () async {
            await widget.s.setMcpConfigJson('[]');
            _ctrl.text = '[]';
            if (mounted) setState(() => _hint = '已清空并断开所有 MCP server');
          },
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('清空'),
        ),
        const SizedBox(width: 10),
        if (_hint != null) Expanded(child: Text(_hint!, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981)), overflow: TextOverflow.ellipsis)),
      ]),
    ]);
  }
}

class _McpStatusPanel extends StatelessWidget {
  final AppState s;
  final AppColors c;
  const _McpStatusPanel({required this.s, required this.c});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF16161A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF10B981)),
          const SizedBox(width: 6),
          Text('已连接 ${s.mcpRegistry.clients.length} 个 MCP server', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        for (final client in s.mcpRegistry.clients) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.hub, size: 14, color: Color(0xFFADADB8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${client.name} (${client.serverInfo ?? "?"}) — ${client.tools.length} 个工具',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ]),
          ),
          if (client.tools.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 6),
              child: Wrap(spacing: 6, runSpacing: 4, children: client.tools.take(20).map((t) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text(t.name, style: const TextStyle(fontSize: 10, color: Color(0xFFA78BFA))),
                );
              }).toList()),
            ),
        ],
      ]),
    );
  }
}

// 开关设置卡片行（参考图二：浅灰圆角卡片 + 粗标题 + 描述 + 绿色开关）
const _kSwitchGreen = Color(0xFF34C77B);

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AppColors c;
  const _SwitchRow({required this.icon, required this.title, required this.value, required this.onChanged, required this.c});

  @override
  Widget build(BuildContext context) {
    final isLight = c.isLight;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFFAFBFD) : const Color(0xFF2E2E35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
          ]),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: _kSwitchGreen,
          inactiveTrackColor: isLight ? const Color(0xFFE2E2E6) : const Color(0xFF3F3F46),
          inactiveThumbColor: Colors.white,
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
///
/// 模式选择：使用全局配置 / 启用独立配置
/// - 独立配置：可选择已保存的对话配置（chatProfiles），也可新建/编辑/删除
/// - 行为开关：流式输出、显示思考过程
class ChatSettingsDialog extends StatefulWidget {
  const ChatSettingsDialog({super.key});

  @override
  State<ChatSettingsDialog> createState() => _ChatSettingsDialogState();
}

class _ChatSettingsDialogState extends State<ChatSettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _modelCtrl;
  late String _temp;
  late int _contextLen;
  late bool _vision;
  late bool _fullUrl;
  late bool _independent;
  late int _editIdx;
  late bool _stream;
  late bool _showReasoning;
  late bool _thinking;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final s = AppScope.of(context);
    // 当前实际生效的配置（独立优先）
    final cfg = s.effectiveChatConfig;
    _editIdx = s.chatProfiles.indexWhere(
      (p) => p.config.url == cfg.url && p.config.key == cfg.key && p.config.model == cfg.model,
    );
    _url = TextEditingController(text: cfg.url);
    _key = TextEditingController(text: cfg.key);
    _modelCtrl = TextEditingController(text: cfg.model);
    _temp = cfg.temperature.isEmpty ? '0.3' : cfg.temperature;
    _contextLen = cfg.contextLength > 0 ? cfg.contextLength : 200000;
    _vision = cfg.vision;
    _fullUrl = cfg.fullUrl;
    _independent = s.chatApiIndependent;
    _stream = s.chatStream;
    _showReasoning = s.chatShowReasoning;
    _thinking = s.chatThinking;
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
      _temp = c.temperature.isEmpty ? '0.3' : c.temperature;
      _contextLen = c.contextLength > 0 ? c.contextLength : 200000;
      _vision = c.vision;
      _fullUrl = c.fullUrl;
    });
  }

  void _save() {
    final s = AppScope.of(context);
    final cfg = ApiConfig(
      url: _url.text.trim(),
      key: _key.text.trim(),
      model: _modelCtrl.text.trim(),
      temperature: _temp,
      vision: _vision,
      fullUrl: _fullUrl,
      contextLength: _contextLen,
    );
    if (_independent) {
      // 保存到 chatProfiles
      final profiles = List.of(s.chatProfiles);
      int activeIdx;
      if (_editIdx >= 0 && _editIdx < profiles.length) {
        profiles[_editIdx] = ApiProfile(name: profiles[_editIdx].name, config: cfg);
        activeIdx = _editIdx;
      } else {
        profiles.add(ApiProfile(name: '对话配置${profiles.length + 1}', config: cfg));
        activeIdx = profiles.length - 1;
      }
      s.saveChatProfiles(profiles, activeIdx);
      s.saveChatSettings(independent: true, config: cfg, showReasoning: _showReasoning, stream: _stream, thinking: _thinking);
    } else {
      // 切回全局：保留当前编辑的全局配置（注意：此处仅切换模式，不再保存全局配置本身）
      s.saveChatSettings(independent: false, config: cfg, showReasoning: _showReasoning, stream: _stream, thinking: _thinking);
    }
  }

  void _deleteConfig() {
    final s = AppScope.of(context);
    if (_editIdx < 0 || _editIdx >= s.chatProfiles.length) return;
    final profiles = List.of(s.chatProfiles)..removeAt(_editIdx);
    final activeIdx = profiles.isEmpty ? -1 : (_editIdx < profiles.length ? _editIdx : profiles.length - 1);
    s.saveChatProfiles(profiles, activeIdx);
    setState(() {
      _editIdx = -1;
      _loadFrom(ApiConfig());
    });
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

  Widget _buildChip(String current, String value, String label, AppColors c, ValueChanged<String> onTap) {
    final sel = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: sel ? c.primaryBg : c.chipUnselected,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: sel ? c.primary.withValues(alpha: 0.4) : c.border, width: 1),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: sel ? c.primaryText : c.textSecondary)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = AppColors.of(context);
    final isLight = c.isLight;
    return AlertDialog(
      backgroundColor: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        Icon(Icons.tune_rounded, size: 20, color: c.primary),
        const SizedBox(width: 8),
        Text('对话助手设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 模式选择
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('API 模式', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF))),
            ),
            Row(children: [
              _buildChip(_independent ? 'on' : 'off', 'off', '使用全局配置', c, (v) {
                if (v == 'off') {
                  setState(() {
                    _independent = false;
                    // 切回全局时，把全局配置回填到表单
                    _loadFrom(s.apiConfig);
                  });
                }
              }),
              const SizedBox(width: 10),
              _buildChip(_independent ? 'on' : 'off', 'on', '启用独立配置', c, (v) {
                if (v == 'on') {
                  setState(() {
                    _independent = true;
                    _editIdx = s.chatProfiles.isNotEmpty ? 0 : -1;
                    if (_editIdx >= 0) {
                      _loadFrom(s.chatProfiles[_editIdx].config);
                    } else {
                      _loadFrom(ApiConfig());
                    }
                  });
                }
              }),
            ]),
            const SizedBox(height: 16),
            if (_independent) ...[
              // 已保存的对话配置下拉
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('已保存的对话配置', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF))),
              ),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('chat_$_editIdx'),
                    initialValue: _editIdx,
                    decoration: _deco(c).copyWith(
                      filled: true,
                      fillColor: isLight ? Colors.white : const Color(0xFF33333A),
                    ),
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
                  onPressed: s.chatProfiles.isEmpty || _editIdx < 0 || _editIdx >= s.chatProfiles.length ? null : _deleteConfig,
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
                Expanded(child: Text('完整 URL', style: TextStyle(fontSize: 12, color: c.textSecondary))),
              ]),
              const SizedBox(height: 12),
              // API Key
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
              // 温度
              _labeledField(
                '温度',
                DropdownButtonFormField<String>(
                  value: _temp,
                  decoration: _deco(c),
                  items: const [
                    DropdownMenuItem(value: '0', child: Text('精确 (0)')),
                    DropdownMenuItem(value: '0.3', child: Text('保守 (0.3)')),
                    DropdownMenuItem(value: '0.7', child: Text('均衡 (0.7)')),
                    DropdownMenuItem(value: '1.0', child: Text('创意 (1.0)')),
                  ],
                  onChanged: (v) => setState(() => _temp = v ?? _temp),
                ),
                c,
              ),
              const SizedBox(height: 12),
              // 上下文长度
              _labeledField(
                '上下文长度',
                DropdownButtonFormField<int>(
                  value: _contextLen,
                  decoration: _deco(c, hint: '默认 200K'),
                  items: const [
                    DropdownMenuItem(value: 32000, child: Text('32K')),
                    DropdownMenuItem(value: 64000, child: Text('64K')),
                    DropdownMenuItem(value: 128000, child: Text('128K')),
                    DropdownMenuItem(value: 200000, child: Text('200K（默认）')),
                    DropdownMenuItem(value: 1000000, child: Text('1000K（1M）')),
                  ],
                  onChanged: (v) => setState(() => _contextLen = v ?? _contextLen),
                ),
                c,
              ),
              const SizedBox(height: 12),
              // 图形能力
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : const Color(0xFF33333A),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.15), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(children: [
                  Icon(Icons.image_outlined, size: 20, color: c.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('图形能力', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
                    ]),
                  ),
                  Switch(value: _vision, onChanged: (v) => setState(() => _vision = v)),
                ]),
              ),
              const SizedBox(height: 12),
            ] else ...[
              // 全局模式提示
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.primaryBg.withValues(alpha: isLight ? 0.5 : 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.primary.withValues(alpha: 0.25)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline, size: 16, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前正在使用全局配置：${s.apiConfig.ready ? "${s.apiConfig.model}" : "尚未配置"}。如需独立 API，请切到「启用独立配置」。',
                      style: TextStyle(fontSize: 12, color: c.text, height: 1.5),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            // 行为开关
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Text('行为', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF))),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isLight ? Colors.white : const Color(0xFF33333A),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.15), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text('流式输出', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                  Switch(value: _stream, onChanged: (v) => setState(() => _stream = v)),
                ]),
                const Divider(height: 18),
                Row(children: [
                  Expanded(
                    child: Text('思考模式', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                  Switch(value: _thinking, onChanged: (v) => setState(() => _thinking = v)),
                ]),
                const Divider(height: 18),
                Row(children: [
                  Expanded(
                    child: Text('显示思考过程', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
                  ),
                  Switch(value: _showReasoning, onChanged: (v) => setState(() => _showReasoning = v)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () {
            _save();
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('对话助手设置已保存'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating));
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
