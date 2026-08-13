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
  // 墨墨同步
  late final TextEditingController _maimemoTokenCtrl;
  bool _maimemoObscure = true;
  bool _maimemoBusy = false;
  String? _maimemoMsg; // 同步结果提示

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
    _maimemoTokenCtrl = TextEditingController(text: s.maimemoToken);
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
    final isLight = c.isLight;
    final cardBg = isLight ? const Color(0xFFF4F4F8) : const Color(0xFF2A2A32);
    final sidebarBg = isLight ? const Color(0xFFF4F4F8) : const Color(0xFF222228);

    // 检测是否为小屏（手机）
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      // 手机端：全屏 Tab 布局
      return Scaffold(
        backgroundColor: cardBg,
        appBar: AppBar(
          backgroundColor: sidebarBg,
          elevation: 0,
          title: Text('设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.close_rounded, color: c.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Column(
          children: [
            // 顶部 Tab 栏
            Container(
              color: sidebarBg,
              child: Row(
                children: [
                  _mobileTabItem('模型', 'model', c),
                  _mobileTabItem('通用', 'general', c),
                  _mobileTabItem('账户', 'account', c),
                  _mobileTabItem('高级', 'advanced', c),
                ],
              ),
            ),
            // 内容区
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: _buildSection(s, c),
              ),
            ),
          ],
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

  /// 手机端 Tab 项
  Widget _mobileTabItem(String label, String key, AppColors c) {
    final selected = _section == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _section = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? _primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _primary : c.textSecondary,
            ),
          ),
        ),
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
      _settingRow('界面模式', c, child: Wrap(spacing: 10, runSpacing: 8, children: [
        _buildChip2(s.uiMode.isEmpty ? 'desktop' : s.uiMode, 'desktop', '电脑端', s, c, (v) => s.setUiMode(v)),
        _buildChip2(s.uiMode.isEmpty ? 'desktop' : s.uiMode, 'mobile', '手机端', s, c, (v) => s.setUiMode(v)),
      ]), hint: '切换后立即生效，也可按 F8 快速切换'),
      const SizedBox(height: 14),
      // 主题（第三大主题：经典 / 毛玻璃 / 深色）
      _settingRow('主题', c, child: Wrap(spacing: 10, runSpacing: 8, children: [
        _buildChip2(s.darkMode ? 'dark' : s.uiStyle, 'classic', '经典', s, c, (_) => s.setThemeStyle('classic')),
        _buildChip2(s.darkMode ? 'dark' : s.uiStyle, 'glass', '毛玻璃', s, c, (_) => s.setThemeStyle('glass')),
        _buildChip2(s.darkMode ? 'dark' : s.uiStyle, 'dark', '深色', s, c, (_) => s.setThemeStyle('dark')),
      ]), hint: '经典与毛玻璃为浅色主题，深色为独立深色主题；也可用侧边栏月亮/太阳图标快速切换'),
      const SizedBox(height: 14),
      // 导航指示器
      _settingRow('导航指示器', c, child: Wrap(spacing: 10, runSpacing: 8, children: [
        _buildChip2(s.navIndicator, 'underline', '灰色下划线', s, c, (v) => s.setNavIndicator(v)),
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
        onChanged: (v) => s.togglePowerSavingMode(v ?? false),
        title: Text('省电模式', style: TextStyle(fontSize: 14, color: c.text)),
        subtitle: Text('开启后锁定60帧以节省电量，关闭后支持120帧高刷', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
        contentPadding: EdgeInsets.zero,
      ),
      const SizedBox(height: 6),
      _SwitchRow(
        icon: Icons.speed_rounded,
        title: '高性能模式',
        subtitle: '低配设备推荐：关闭毛玻璃模糊等重特效、使用不透明实色界面且不锁帧，大幅提升流畅度，所有功能不受影响',
        value: s.highPerformanceMode,
        onChanged: (v) => s.toggleHighPerformanceMode(v),
        c: c,
      ),
      const SizedBox(height: 6),
      _settingRow('应用模式', c, child: Row(children: [
        _buildChip2(s.appMode.isEmpty ? 'english' : s.appMode, 'english', '英语学习模式', s, c, (v) => s.setAppMode(v)),
        const SizedBox(width: 10),
        _buildChip2(s.appMode.isEmpty ? 'english' : s.appMode, 'tools', '工具模式', s, c, (v) => s.setAppMode(v)),
      ]), hint: '工具模式包含转盘/翻牌/数字/画板/五子棋/象棋等，切换后立即生效'),
      const SizedBox(height: 14),
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
        Expanded(child: OutlinedButton.icon(onPressed: () => _export(s), icon: const Icon(Icons.download, size: 16), label: const Text('导出备份'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton.icon(onPressed: () => _import(s), icon: const Icon(Icons.upload, size: 16), label: const Text('导入备份'))),
      ]),
    ]);
  }

  // ============== Section 3: 账户安全 ==============
  Widget _sectionAccount(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('账户与同步', c),
      const SizedBox(height: 14),
      // 墨墨背单词同步卡片
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.isLight ? Colors.white : const Color(0xFF33333A),
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
            Icon(Icons.auto_stories_outlined, size: 22, color: _primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('墨墨背单词同步', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 2),
                Text('将墨墨今日学习单词同步到 AFloat 墨墨词库', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          // Token 输入框
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
          // 状态行
          if (s.maimemoToken.isNotEmpty) ...[
            _maimemoStatusLine(s, c),
            const SizedBox(height: 10),
          ],
          // 同步按钮
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
          const SizedBox(height: 8),
          Text('如何获取 Token：打开墨墨背单词 App → 我的 → 更多设置 → 实验功能 → 开放 API，点击生成后复制。', style: TextStyle(fontSize: 11, color: c.textTertiary, height: 1.5)),
        ]),
      ),
      const SizedBox(height: 14),
      _emptyHint('更多账户与云同步功能正在规划中…', c),
    ]);
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
    _temp = cfg.temperature.isEmpty ? 'default' : cfg.temperature;
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
      _temp = c.temperature.isEmpty ? 'default' : c.temperature;
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
                Expanded(child: Text('完整 URL（关闭时自动添加 /chat/completions）', style: TextStyle(fontSize: 12, color: c.textTertiary))),
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
                      const SizedBox(height: 2),
                      Text('开启后支持图片上传与 AI 识别', style: TextStyle(fontSize: 11, color: c.textTertiary)),
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
