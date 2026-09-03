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
import '../services/mcp_client.dart';
import '../services/wechat_service.dart';
import '../state.dart';
import '../theme_colors.dart' show kPrimary, AppColors;
import '../theme_diy.dart';
import 'diy_backdrop.dart';
import 'learn_page.dart' show AppScope;
import 'update_dialog.dart';

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
  // R33: 配置库选择器锚点 + 浮层
  final GlobalKey _cfgFieldKey = GlobalKey();
  OverlayEntry? _cfgMenuEntry;
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
  /// 'model' 模型设置 | 'interface' 界面设置 | 'account' 账户安全 | 'advanced' 高级功能 | 'diy' 页面 DIY
  String _section = 'home';

  // ---- 页面 DIY 编辑器状态 ----
  /// 正在编辑的主题（经典/毛玻璃/深色各自独立，互不影响）
  DiyThemeTarget _diyTarget = DiyThemeTarget.classic;
  /// 背景工作副本：null = 该主题背景未开始编辑（显示并沿用当前生效值）。
  /// 一旦有修改即非空，并随 onChangeEnd / 点击类操作提交到 AppState（同步持久化）。
  DiyBackdrop? _diyWorkBd;
  /// 按钮样式工作副本，语义同上
  DiyButtonStyle? _diyWorkBtn;
  /// 滑块拖动中产生、尚未提交到 AppState 的改动
  bool _diyDirty = false;
  /// 展开编辑的图层索引（null = 全部收起）
  int? _diyExpandedLayer;

  @override
  void initState() {
    super.initState();
    // 注意：不能在这里调 MediaQuery.of / AppScope.of（State 处于 created 生命周期，
    // dependOnInheritedWidgetOfExactType 会断言崩溃），依赖读取移至 didChangeDependencies
  }

  /// 依赖读取只执行一次（didChangeDependencies 可能被多次回调）
  bool _depsInited = false;
  /// 缓存 AppState 引用，dispose 阶段无法再 AppScope.of(context)
  AppState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_depsInited) return;
    _depsInited = true;
    // 根据初始屏幕宽度决定默认展示入口页（手机）还是直接展示模型设置（桌面）
    final width = MediaQuery.of(context).size.width;
    _section = width < 600 ? 'home' : 'model';
    final s = AppScope.of(context);
    _state = s;
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
    // R33: 弹窗关闭时收起配置选择浮层
    _hideConfigMenu();
    // didChangeDependencies 未跑过（极端时序）时 late 字段未初始化，跳过清理
    if (_depsInited) {
      _state?.removeListener(_onStateChanged);
      _url.dispose();
      _key.dispose();
      _modelCtrl.dispose();
      _maimemoTokenCtrl.dispose();
      _searchUrlCtrl.dispose();
      _searchKeyCtrl.dispose();
    }
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
              _buildAppModeCard(s, c),
              const SizedBox(height: 14),
              _mobileGroup(c, const [
                ['model', '模型设置'],
                ['interface', '界面设置'],
              ]),
              const SizedBox(height: 10),
              _mobileGroup(c, const [
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
        'account' => '账户安全',
        'diy' => '页面 DIY',
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
            // DIY 页从"高级功能"进入，返回也回到高级功能；其余子页回首页。
            // 返回前先把拖动中未落盘的改动提交，避免丢最后一次滑块调整
            onPressed: () => setState(() {
              if (_section == 'diy') _diyCommit(s);
              _section = _section == 'diy' ? 'advanced' : 'home';
            }),
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
                    onPressed: () {
                      _diyCommit(s); // DIY 页拖动中直接关窗也先落盘
                      Navigator.of(context).pop();
                    },
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _buildSection(s, c),
                  ]),
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

  /// 应用模式切换卡：课程表 / 学习模式（桌面 + 手机共用）
  /// 切换后整树切换到对应模式，UI 立即反映
  Widget _buildAppModeCard(AppState s, AppColors c) {
    final isTimetable = s.appMode == 'timetable';
    Widget seg(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: selected ? c.primaryBg : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? c.primary.withValues(alpha: 0.4) : c.border, width: selected ? 1.4 : 1),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 19, color: selected ? c.primary : c.textTertiary),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? c.primary : c.textSecondary)),
              ]),
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.swap_horizontal_circle_outlined, size: 16, color: c.textTertiary),
          const SizedBox(width: 6),
          Text('应用模式', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          seg('课程表', Icons.calendar_month_outlined, isTimetable, () {
            if (isTimetable) return;
            if (s.uiMode.isEmpty) s.setUiMode('desktop');
            s.setAppMode('timetable');
          }),
          const SizedBox(width: 8),
          seg('学习模式', Icons.school_outlined, !isTimetable, () {
            if (!isTimetable) return;
            if (s.uiMode.isEmpty) s.setUiMode('desktop');
            s.setAppMode('english');
          }),
        ]),
      ]),
    );
  }

  // ---- 左侧导航条目（参考图二：选中为灰底圆角 + 深色文字） ----
  Widget _navItem(Widget icon, String label, String key, AppColors c) {
    // DIY 编辑器从高级功能进入，属于其子页：编辑中仍高亮「高级功能」
    final selected = _section == key || (_section == 'diy' && key == 'advanced');
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
      case 'account':   return _sectionAccountContent(s, c);
      case 'advanced':  return _sectionAdvanced(s, c);
      case 'diy':       return _sectionDiy(s, c);
      default:          return _sectionModelContent(s, c);
    }
  }

  // ============== Section: 模型设置 ==============
  /// R33: 关闭配置选择浮层
  void _hideConfigMenu() {
    _cfgMenuEntry?.remove();
    _cfgMenuEntry = null;
  }

  /// R33: 自绘配置选择浮层（白色圆角面板，锚定在字段正下方；中性高亮，无系统粉色）
  void _showConfigMenu(BuildContext anchorCtx, AppColors c, AppState s) {
    if (_cfgMenuEntry != null) {
      _hideConfigMenu();
      return;
    }
    final box = _cfgFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay = Overlay.of(anchorCtx, rootOverlay: true);
    final pos = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(anchorCtx).size;
    const menuW = 320.0;
    double mx = pos.dx.clamp(12.0, screen.width - menuW - 12);
    double my = pos.dy + box.size.height + 8;
    if (my + 200 > screen.height - 12) my = pos.dy - 200;

    _cfgMenuEntry = OverlayEntry(builder: (menuCtx) {
      return StatefulBuilder(builder: (menuCtx, setMenu) {
        Widget item({required IconData icon, required String title, String? sub, required VoidCallback onTap}) {
          return InkWell(
            onTap: onTap,
            hoverColor: const Color(0x0F000000),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Icon(icon, size: 16, color: c.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text), overflow: TextOverflow.ellipsis),
                    if (sub != null && sub.isNotEmpty)
                      Text(sub, style: TextStyle(fontSize: 11, color: c.textTertiary), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          );
        }

        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hideConfigMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: mx,
            top: my,
            width: menuW,
            child: Material(
              color: c.isLight ? Colors.white : const Color(0xFF26262C),
              borderRadius: BorderRadius.circular(14),
              elevation: 12,
              shadowColor: Colors.black45,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  item(
                    icon: Icons.add_rounded,
                    title: '新建配置',
                    sub: '填入全新的 API 地址与模型',
                    onTap: () {
                      _hideConfigMenu();
                      setState(() {
                        _editIdx = -1;
                        _loadFrom(ApiConfig());
                      });
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: c.divider),
                  for (var i = 0; i < s.apiProfiles.length; i++)
                    item(
                      icon: Icons.tune_rounded,
                      title: '${s.apiProfiles[i].label} · ${s.apiProfiles[i].config.model}',
                      sub: s.apiProfiles[i].config.url,
                      onTap: () {
                        _hideConfigMenu();
                        setState(() {
                          _editIdx = i;
                          _loadFrom(s.apiProfiles[i].config);
                        });
                      },
                    ),
                ]),
              ),
            ),
          ),
        ]);
      });
    });
    overlay.insert(_cfgMenuEntry!);
  }

  Widget _sectionModelContent(AppState s, AppColors c) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('模型设置', c),
      const SizedBox(height: 14),
      // R33: 配置库选择——自绘简约选择器（替代系统 DropdownButton：无粉色高亮、白色浮层）
      Row(children: [
        Expanded(
          child: Builder(builder: (fieldCtx) {
            final current = (_editIdx >= 0 && _editIdx < s.apiProfiles.length)
                ? '${s.apiProfiles[_editIdx].label} · ${s.apiProfiles[_editIdx].config.model}'
                : '新建配置';
            return InkWell(
              key: _cfgFieldKey,
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showConfigMenu(fieldCtx, c, s),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: c.isLight ? Colors.white : const Color(0xFF26262C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(current,
                        style: TextStyle(fontSize: 13.5, color: c.text, overflow: TextOverflow.ellipsis)),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.textTertiary),
                ]),
              ),
            );
          }),
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
      // 应用模式（课程表 / 学习模式）
      _settingRow('应用模式', c, child: Wrap(spacing: 10, runSpacing: 8, children: [
        _buildChip2(s.appMode, 'timetable', '课程表', s, c, (_) {
          if (s.appMode == 'timetable') return;
          if (s.uiMode.isEmpty) s.setUiMode('desktop');
          s.setAppMode('timetable');
        }),
        _buildChip2(s.appMode, 'english', '学习模式', s, c, (_) {
          if (s.appMode == 'english') return;
          if (s.uiMode.isEmpty) s.setUiMode('desktop');
          s.setAppMode('english');
        }),
      ])),
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
    Color? iconColor,
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
          Icon(icon, size: 22, color: iconColor ?? _primary),
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
      iconColor: c.textTertiary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _backup(s),
            icon: const Icon(Icons.save_alt, size: 16),
            label: const Text('一键备份数据'),
            // 数据备份/墨墨/搜索统一用中性灰（避免品牌紫/纯黑）
            style: FilledButton.styleFrom(
              backgroundColor: c.isLight ? const Color(0xFF6B7280) : const Color(0xFF8A8D94),
              foregroundColor: Colors.white,
            ),
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
      iconColor: c.textTertiary,
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
              // 同步按钮同样改为中性灰（避免品牌紫/纯黑）
              backgroundColor: c.isLight ? const Color(0xFF6B7280) : const Color(0xFF8A8D94),
              disabledBackgroundColor: c.isLight ? const Color(0xFFC9CBD0) : const Color(0xFF8A8D94).withValues(alpha: 0.5),
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
      iconColor: c.textTertiary,
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

  // ============== Section 4: 高级功能 ==============
  Widget _sectionAdvanced(AppState s, AppColors c) {
    final wechatState = WeChatService.bound
        ? (WeChatService.autoReply ? '已连接 · 自动回复中' : '已连接 · 自动回复关闭')
        : (WeChatService.lastError ?? '未绑定');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('高级功能', c),
      const SizedBox(height: 14),
      // 页面 DIY：三个主题（经典/毛玻璃/深色）的背景与按钮样式自定义
      _diyEntryCard(s, c),
      const SizedBox(height: 10),
      // 开发者模式开关已按需求从学习模式设置中隐藏（用户要求）。
      // 若要恢复：取消下面注释即可（devMode 状态与持久化逻辑仍在 state.dart / storage.dart 中保留）。
      // _SwitchRow(
      //   icon: Icons.bug_report_outlined,
      //   title: '开发者模式',
      //   value: s.devMode,
      //   onChanged: (v) => s.setDevMode(v),
      //   c: c,
      // ),
      const SizedBox(height: 10),
      // R35: 微信 ClawBot 接入（weixin_clawbot）：扫码绑定 → 收消息 → agent 应答回传微信
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF26262C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 18, color: c.isLight ? const Color(0xFF10B981) : const Color(0xFF34D399)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('微信接入（ClawBot）', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 2),
                Text(wechatState, style: TextStyle(fontSize: 11.5, color: WeChatService.bound ? const Color(0xFF10B981) : c.textTertiary)),
              ]),
            ),
            _SwitchRow(
              icon: Icons.reply_rounded,
              title: '',
              value: WeChatService.autoReply,
              onChanged: (v) {
                if (!WeChatService.bound) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请先扫码绑定微信', style: TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating),
                  );
                  return;
                }
                WeChatService.autoReply = v;
                setState(() {});
              },
              c: c,
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: Icon(WeChatService.bound ? Icons.refresh_rounded : Icons.qr_code_scanner_rounded, size: 16),
                label: Text(WeChatService.bound ? '重新扫码绑定' : '扫码绑定微信',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                onPressed: () async {
                  final ok = await WeChatService.bind(context: context);
                  if (mounted) setState(() {});
                  if (ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('微信绑定成功', style: TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating),
                    );
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('绑定失败：${WeChatService.lastError ?? '未知原因'}', style: const TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating),
                    );
                  }
                },
              ),
            ),
            if (WeChatService.bound) ...[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off_rounded, size: 16),
                label: const Text('解绑', style: TextStyle(fontSize: 12.5)),
                onPressed: () {
                  WeChatService.unbind();
                  setState(() {});
                },
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Text(
            '绑定后微信收到的消息会转给 AI 助手自动应答回传（速率约 7 条 / 5 分钟，由微信 ClawBot 限制）。\n'
            '前置：需在 OpenClaw 微信插件完成一次命令行登录。',
            style: TextStyle(fontSize: 10.5, height: 1.5, color: c.textTertiary),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      // MCP 服务管理与「在线更新」入口已按用户要求从界面隐藏（底层调用能力不受影响）。
      // 需要恢复时，在下方 children 中加回 _mcpManagerCard(s, c) / _updateEntryCard(c)。
    ]);
  }

  // ignore: unused_element
  /// MCP 服务（连接器）管理卡：预置模板一键添加 + 已配置列表（按用户要求隐藏，恢复时在 _sectionAdvanced 调用）
  Widget _mcpManagerCard(AppState s, AppColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF26262C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.hub_outlined, size: 18, color: c.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MCP 服务（连接器）', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 2),
              Text('配置后 Agent 可调用外部工具（需本机 Node.js，npx 启动）', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
            ]),
          ),
          if (s.mcpRegistry.clients.isNotEmpty)
            Text('已连 ${s.mcpRegistry.clients.length} 个', style: TextStyle(fontSize: 11.5, color: const Color(0xFF10B981))),
        ]),
        const SizedBox(height: 12),
        // 预置模板一键添加
        Text('预置模板', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textSecondary)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in AppState.mcpTemplates.entries)
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: Text(e.key.split(' ').first, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              backgroundColor: c.isLight ? Colors.white : const Color(0xFF33333A),
              side: BorderSide(color: c.border),
              onPressed: () async {
                // 需要 API Key 的模板：空 env 占位 → 弹窗补填后再添加
                final emptyEnv = e.value.env.entries.where((kv) => kv.value.isEmpty).toList();
                var cfg = e.value;
                if (emptyEnv.isNotEmpty) {
                  final controllers = <String, TextEditingController>{
                    for (final kv in emptyEnv) kv.key: TextEditingController(),
                  };
                  final filled = await showDialog<Map<String, String>>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('配置 ${e.key.split(' ').first}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      content: SizedBox(
                        width: 320,
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('该服务需密钥才能调用（可前往服务官网免费申请）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 12),
                          for (final kv in emptyEnv) ...[
                            Text(kv.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: controllers[kv.key],
                              obscureText: true,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '请输入 ${kv.key}',
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ]),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () {
                            final filled = <String, String>{
                              for (final kv in emptyEnv) kv.key: controllers[kv.key]!.text.trim(),
                            };
                            if (filled.values.any((v) => v.isEmpty)) {
                              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                                content: Text('请填完所有密钥字段', style: TextStyle(fontSize: 12.5)),
                                behavior: SnackBarBehavior.floating,
                              ));
                              return;
                            }
                            Navigator.pop(ctx, filled);
                          },
                          child: const Text('添加'),
                        ),
                      ],
                    ),
                  );
                  if (filled == null || !mounted) return;
                  cfg = McpServerConfig(
                    name: e.value.name,
                    command: e.value.command,
                    args: e.value.args,
                    env: {...e.value.env, ...filled},
                  );
                }
                final added = await s.addMcpServer(cfg);
                if (!mounted) return;
                if (!added) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('「${e.key.split(' ').first}」已存在', style: const TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加 ${e.key.split(' ').first}，正在连接…', style: const TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating),
                  );
                }
                if (mounted) setState(() {});
              },
            ),
        ]),
        // 已配置列表
        const SizedBox(height: 12),
        Text('已配置', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textSecondary)),
        const SizedBox(height: 8),
        if (s.parseMcpConfigs().isEmpty)
          Text('未配置任何 MCP server', style: TextStyle(fontSize: 12, color: c.textTertiary))
        else
          for (final cfg in s.parseMcpConfigs()) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: c.isLight ? Colors.white : const Color(0xFF2C2C33),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Row(children: [
                Icon(Icons.hub_rounded, size: 16, color: c.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cfg.name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text)),
                    const SizedBox(height: 2),
                    Text('${cfg.command} ${cfg.args.join(' ')}', style: TextStyle(fontSize: 10.5, color: c.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: c.textTertiary,
                  tooltip: '移除',
                  onPressed: () async {
                    await s.removeMcpServer(cfg.name);
                    if (mounted) setState(() {});
                  },
                ),
              ]),
            ),
          ],
        if (s.mcpRegistry.connectErrors.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Expanded(
                child: Text(
                  '部分 server 连接失败（检查本机 Node.js/npx 或 uvx 是否安装）',
                  style: TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
              ),
              TextButton(
                onPressed: () async {
                  await s.setMcpConfigJson(s.mcpConfigJson);
                  if (mounted) setState(() {});
                },
                style: TextButton.styleFrom(minimumSize: const Size(0, 28), padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: const Text('重连', style: TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          '提示：添加后需在对话中执行 list_mcp_tools 即可看到工具；快递100 等商业服务需填 API Key（模板点击后会弹窗），其余（deepwiki/12306 等）零配置直接用。',
          style: TextStyle(fontSize: 10.5, height: 1.5, color: c.textTertiary),
        ),
      ]),
    );
  }

  // ignore: unused_element
  /// 在线更新入口卡（按用户要求隐藏，恢复时在 _sectionAdvanced 调用）
  Widget _updateEntryCard(AppColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF26262C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(children: [
        Icon(Icons.system_update_alt_rounded, size: 18, color: c.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('在线更新', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 2),
            Text('从 GitHub Releases 检查新版本', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
          ]),
        ),
        OutlinedButton(
          onPressed: () => UpdateDialog.checkAndShow(context, quiet: false, manual: true),
          child: const Text('检查更新', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }

  // ============== Section: 页面 DIY ==============

  /// 高级功能里的「页面 DIY」入口卡：显示已自定义的主题数，点击进入编辑器
  Widget _diyEntryCard(AppState s, AppColors c) {
    final customized = DiyThemeTarget.values.where((t) => s.diyThemes.isCustomized(t)).length;
    final isLight = c.isLight;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          _diyCommit(s);
          setState(() {
            _diyTarget = s.diyCurrentTarget;
            _diyWorkBd = null;
            _diyWorkBtn = null;
            _diyDirty = false;
            _diyExpandedLayer = null;
            _section = 'diy';
          });
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isLight ? const Color(0xFFF7F8FA) : const Color(0xFF26262C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            Icon(Icons.palette_outlined, size: 18, color: isLight ? kPrimary : const Color(0xFFA78BFA)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('页面 DIY', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(height: 2),
                Text('自定义经典、毛玻璃、深色主题的背景与按钮样式',
                    style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(
              customized > 0 ? '已自定义 $customized/3' : '未自定义',
              style: TextStyle(
                fontSize: 11.5,
                color: customized > 0 ? (isLight ? kPrimary : const Color(0xFFA78BFA)) : c.textTertiary,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.textSecondary),
          ]),
        ),
      ),
    );
  }

  /// 当前编辑中的背景（工作副本优先，否则取该主题当前生效值）
  DiyBackdrop _diyBd(AppState s) => _diyWorkBd ?? s.effectiveBackdropOf(_diyTarget);

  /// 当前编辑中的按钮样式（工作副本优先，否则取该主题当前生效值）
  DiyButtonStyle _diyBtn(AppState s) => _diyWorkBtn ?? s.effectiveButtonStyleOf(_diyTarget);

  /// 点击类修改：本地更新 + 立即提交（AppState 内部同步持久化）
  void _diyUpdateBd(AppState s, DiyBackdrop bd) {
    setState(() {
      _diyWorkBd = bd;
      _diyDirty = false;
    });
    s.setDiyBackdrop(_diyTarget, bd);
  }

  /// 滑块拖动中：只更新本地工作副本保证预览跟手，onChangeEnd 时才提交
  void _diyDragBd(DiyBackdrop bd) {
    setState(() {
      _diyWorkBd = bd;
      _diyDirty = true;
    });
  }

  void _diyUpdateBtn(AppState s, DiyButtonStyle st) {
    setState(() {
      _diyWorkBtn = st;
      _diyDirty = false;
    });
    s.setDiyButtonStyle(_diyTarget, st);
  }

  void _diyDragBtn(DiyButtonStyle st) {
    setState(() {
      _diyWorkBtn = st;
      _diyDirty = true;
    });
  }

  /// 提交所有未落盘的滑块改动（切换主题 / 离开编辑器前调用，避免丢最后一次拖动）
  void _diyCommit(AppState s) {
    if (!_diyDirty) return;
    if (_diyWorkBd != null) s.setDiyBackdrop(_diyTarget, _diyWorkBd);
    if (_diyWorkBtn != null) s.setDiyButtonStyle(_diyTarget, _diyWorkBtn);
    _diyDirty = false;
  }

  /// 切换编辑目标主题
  void _diySwitchTarget(AppState s, DiyThemeTarget t) {
    if (t == _diyTarget) return;
    _diyCommit(s);
    setState(() {
      _diyTarget = t;
      _diyWorkBd = null;
      _diyWorkBtn = null;
      _diyExpandedLayer = null;
    });
  }

  /// DIY 编辑器主体（桌面端内容区与手机端子页共用）
  Widget _sectionDiy(AppState s, AppColors c) {
    final isLight = c.isLight;
    final bd = _diyBd(s);
    final btn = _diyBtn(s);
    final customized = s.diyThemes.isCustomized(_diyTarget);
    final accent = isLight ? kPrimary : const Color(0xFFA78BFA);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 桌面端没有系统返回键，给一个返回高级功能的文字入口；手机端由 AppBar 返回
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 600) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextButton.icon(
            onPressed: () {
              _diyCommit(s);
              setState(() => _section = 'advanced');
            },
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 14, color: c.textSecondary),
            label: Text('返回高级功能', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30)),
          ),
        );
      }),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text(
            '三个主题相互独立，改动即时生效并自动保存；未调整的部分保持原样。',
            style: TextStyle(fontSize: 12.5, height: 1.5, color: c.textSecondary),
          ),
        ),
        if (customized) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
            child: Text('已自定义', style: TextStyle(fontSize: 11, color: accent)),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      // 主题切换（三个主题 tab，自带"已自定义"圆点）
      _diyThemeTabs(s, c),
      const SizedBox(height: 14),
      // 实时预览：背景 + 按钮一起看，所见即所得
      _diyPreviewCard(s, c, bd, btn),
      const SizedBox(height: 22),

      _diyGroupTitle(c, '风格预设', '套用后可继续逐项微调'),
      const SizedBox(height: 10),
      _diyPresetStrip(s, c),
      const SizedBox(height: 22),

      _diyGroupTitle(c, '背景基座', null),
      const SizedBox(height: 10),
      _diyBaseEditor(s, c, bd),
      const SizedBox(height: 22),

      _diyGroupTitle(c, '背景图层', '自下而上叠加，最多 6 层'),
      const SizedBox(height: 10),
      _diyLayerList(s, c, bd),
      const SizedBox(height: 22),

      _diyGroupTitle(c, '观感', null),
      const SizedBox(height: 10),
      _diyFeelEditor(s, c, bd),
      const SizedBox(height: 22),

      _diyGroupTitle(c, '按钮', '作用于全局主按钮、次按钮与链接样式'),
      const SizedBox(height: 10),
      _diyButtonEditor(s, c, btn),
      const SizedBox(height: 24),

      // 恢复默认
      Row(children: [
        OutlinedButton.icon(
          // 未自定义时禁用：没有可恢复的内容，避免"已恢复默认"的误导提示
          onPressed: customized
              ? () {
                  s.resetDiyTheme(_diyTarget);
                  setState(() {
                    _diyWorkBd = null;
                    _diyWorkBtn = null;
                    _diyDirty = false;
                    _diyExpandedLayer = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('已恢复「${_diyTarget.label}」的默认外观', style: const TextStyle(fontSize: 12.5)),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              : null,
          icon: const Icon(Icons.restart_alt_rounded, size: 16),
          label: const Text('恢复此主题默认', style: TextStyle(fontSize: 12.5)),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: s.diyThemes.isEmpty
              ? null
              : () {
                  s.resetAllDiyThemes();
                  setState(() {
                    _diyWorkBd = null;
                    _diyWorkBtn = null;
                    _diyDirty = false;
                    _diyExpandedLayer = null;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('已恢复全部主题默认外观', style: TextStyle(fontSize: 12.5)),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
          icon: const Icon(Icons.undo_rounded, size: 16),
          label: const Text('全部恢复默认', style: TextStyle(fontSize: 12.5)),
        ),
      ]),
    ]);
  }

  /// 小节标题：主标题 + 可选的灰色说明
  Widget _diyGroupTitle(AppColors c, String title, String? hint) {
    return Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
      Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
      if (hint != null) ...[
        const SizedBox(width: 8),
        Expanded(child: Text(hint, style: TextStyle(fontSize: 11.5, color: c.textTertiary), overflow: TextOverflow.ellipsis)),
      ],
    ]);
  }

  /// 主题 tab 行：三个主题等宽分段，已自定义的主题名前带小圆点
  Widget _diyThemeTabs(AppState s, AppColors c) {
    final isLight = c.isLight;
    final accent = isLight ? kPrimary : const Color(0xFFA78BFA);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFEDEEF3) : const Color(0xFF1B1B20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        for (final t in DiyThemeTarget.values)
          Expanded(
            child: GestureDetector(
              onTap: () => _diySwitchTarget(s, t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t == _diyTarget ? (isLight ? Colors.white : const Color(0xFF33333A)) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: t == _diyTarget && isLight
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                      : null,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (s.diyThemes.isCustomized(t)) ...[
                    Container(width: 5, height: 5, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    t.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: t == _diyTarget ? FontWeight.w700 : FontWeight.w500,
                      color: t == _diyTarget ? c.text : c.textSecondary,
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  /// 预览卡：当前编辑主题的背景 + 一组示例按钮，所见即所得
  Widget _diyPreviewCard(AppState s, AppColors c, DiyBackdrop bd, DiyButtonStyle btn) {
    final isLight = c.isLight;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final onPrimary = (btn.fill == DiyButtonFill.glass || btn.fill == DiyButtonFill.outline || btn.fill == DiyButtonFill.ghost)
        ? (btn.color ?? (isLight ? kPrimary : const Color(0xFFA78BFA)))
        : Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: isMobile ? 130 : 150,
        child: Stack(fit: StackFit.expand, children: [
          DiyBackdropPreview(config: bd, isLight: _diyTarget != DiyThemeTarget.dark, blur: _diyTarget == DiyThemeTarget.glass ? bd.blur : 0),
          Positioned(
            left: 16,
            bottom: 14,
            right: 16,
            child: Row(children: [
              // 用工作副本样式绘制示例按钮（不走全局主题：编辑中的可能不是当前主题）
              ElevatedButton(
                onPressed: () {},
                style: diyToButtonStyle(btn, primary: isLight ? kPrimary : const Color(0xFFA78BFA), onPrimary: onPrimary, foreground: isLight ? kPrimary : const Color(0xFFA78BFA), isLight: isLight),
                child: const Text('开始学习'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () {},
                style: diyToButtonStyle(btn.copyWith(fill: DiyButtonFill.outline), primary: btn.color ?? (isLight ? kPrimary : const Color(0xFFA78BFA)), onPrimary: Colors.white, foreground: isLight ? kPrimary : const Color(0xFFA78BFA), isLight: isLight),
                child: const Text('换个说法'),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.black : Colors.white).withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${_diyTarget.label} · 预览', style: TextStyle(fontSize: 10.5, color: isLight ? Colors.white : Colors.black.withValues(alpha: 0.85))),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// 风格预设横滚条：小预览图 + 名称，点击套用（保留按钮样式与毛玻璃模糊）
  Widget _diyPresetStrip(AppState s, AppColors c) {
    final forLight = _diyTarget != DiyThemeTarget.dark;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kDiyPresets.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final p = kDiyPresets[i];
          final preview = p.build(forLight);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                s.applyDiyPreset(_diyTarget, p.key);
                setState(() {
                  _diyWorkBd = null; // 回到"跟随已保存值"
                  _diyDirty = false;
                  _diyExpandedLayer = null;
                });
              },
              child: Container(
                width: 128,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.isLight ? Colors.white : const Color(0xFF2C2C33),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: DiyBackdropPreview(config: preview, isLight: forLight),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    child: Text(p.label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.text)),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 背景基座：填充方式 + 颜色序列 + 渐变角度
  Widget _diyBaseEditor(AppState s, AppColors c, DiyBackdrop bd) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _diySegmented<DiyBaseKind>(
        c,
        [for (final k in DiyBaseKind.values) (k, k.label)],
        bd.base,
        (v) => _diyUpdateBd(s, bd.copyWith(base: v)),
      ),
      const SizedBox(height: 12),
      // 颜色序列：1-4 个色块，可增删；点击色块弹色板
      Row(children: [
        Text('颜色', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(width: 12),
        for (var i = 0; i < bd.colors.length; i++) ...[
          _diyColorChip(c, bd.colors[i], onTap: () => _pickDiyColor(c, bd.colors[i], allowFollow: false,
              onPicked: (col) {
                if (col == null) return;
                final cs = List<Color>.of(bd.colors)..[i] = col;
                _diyUpdateBd(s, bd.copyWith(colors: cs));
              }),
            onRemove: bd.colors.length > 1
                ? () {
                    final cs = List<Color>.of(bd.colors)..removeAt(i);
                    _diyUpdateBd(s, bd.copyWith(colors: cs));
                  }
                : null,
          ),
          const SizedBox(width: 8),
        ],
        if (bd.colors.length < 4)
          GestureDetector(
            onTap: () {
              // 新增色取当前末位的邻近色（同色加深），避免突兀；用户可再改
              final last = bd.colors.last;
              _diyUpdateBd(s, bd.copyWith(colors: [...bd.colors, Color.lerp(last, Colors.black, 0.12)!]));
            },
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c.isLight ? Colors.white : const Color(0xFF33333A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Icon(Icons.add_rounded, size: 15, color: c.textSecondary),
            ),
          ),
      ]),
      // 渐变角度：纯色不需要
      if (bd.base == DiyBaseKind.linear || bd.base == DiyBaseKind.sweep) ...[
        const SizedBox(height: 4),
        _diySlider(
          c,
          label: '渐变角度',
          value: bd.angle,
          min: 0,
          max: 360,
          fmt: (v) => '${v.round()}°',
          onChanged: (v) => _diyDragBd(bd.copyWith(angle: v)),
          onChangeEnd: (v) => _diyUpdateBd(s, bd.copyWith(angle: v)),
        ),
      ],
    ]);
  }

  /// 观感：动效开关、内容蒙层、毛玻璃模糊（仅毛玻璃主题）
  Widget _diyFeelEditor(AppState s, AppColors c, DiyBackdrop bd) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _diySwitchLine(c, '背景动效', '光带漂移与光斑呼吸；低电量时建议关闭', bd.animated,
          (v) => _diyUpdateBd(s, bd.copyWith(animated: v))),
      const SizedBox(height: 2),
      _diySlider(
        c,
        label: '内容蒙层',
        hint: '背景较花时压一层底色保证正文可读',
        value: bd.scrim,
        min: 0,
        max: 0.85,
        fmt: (v) => v <= 0.005 ? '关' : '${(v * 100).round()}%',
        onChanged: (v) => _diyDragBd(bd.copyWith(scrim: v)),
        onChangeEnd: (v) => _diyUpdateBd(s, bd.copyWith(scrim: v)),
      ),
      if (_diyTarget == DiyThemeTarget.glass)
        _diySlider(
          c,
          label: '毛玻璃模糊',
          value: bd.blur,
          min: 0,
          max: 60,
          fmt: (v) => v.round().toString(),
          onChanged: (v) => _diyDragBd(bd.copyWith(blur: v)),
          onChangeEnd: (v) => _diyUpdateBd(s, bd.copyWith(blur: v)),
        ),
    ]);
  }

  /// 按钮编辑器：填充方式 + 颜色 + 形状 + 描边 + 阴影 + 字重
  Widget _diyButtonEditor(AppState s, AppColors c, DiyButtonStyle btn) {
    final accent = c.isLight ? kPrimary : const Color(0xFFA78BFA);
    final showBorder = btn.fill == DiyButtonFill.glass || btn.fill == DiyButtonFill.outline;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _diySegmented<DiyButtonFill>(
        c,
        [for (final f in DiyButtonFill.values) (f, f.label)],
        btn.fill,
        (v) => _diyUpdateBtn(s, btn.copyWith(fill: v)),
      ),
      const SizedBox(height: 12),
      // 主色：可"跟随主题主色"
      Row(children: [
        Text('主色', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _pickDiyColor(c, btn.color ?? accent, allowFollow: true,
              onPicked: (col) => _diyUpdateBtn(s, col == null ? btn.copyWith(clearColor: true) : btn.copyWith(color: col))),
          child: _followThemeChip(c, btn.color == null, btn.color ?? accent, '跟随主题'),
        ),
        const SizedBox(width: 8),
        _diyColorChip(c, btn.color ?? accent, onTap: () => _pickDiyColor(c, btn.color ?? accent, allowFollow: true,
            onPicked: (col) => _diyUpdateBtn(s, col == null ? btn.copyWith(clearColor: true) : btn.copyWith(color: col))),
          onRemove: null,
        ),
      ]),
      // 渐变次色：仅渐变填充时出现
      if (btn.fill == DiyButtonFill.gradient) ...[
        const SizedBox(height: 10),
        Row(children: [
          Text('次色', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _pickDiyColor(c, btn.color2 ?? Color.lerp(btn.color ?? accent, c.isLight ? Colors.white : Colors.black, 0.28)!,
                allowFollow: true,
                onPicked: (col) => _diyUpdateBtn(s, col == null ? btn.copyWith(clearColor2: true) : btn.copyWith(color2: col))),
            child: _followThemeChip(c, btn.color2 == null,
                btn.color2 ?? Color.lerp(btn.color ?? accent, c.isLight ? Colors.white : Colors.black, 0.28)!, '自动派生'),
          ),
          const SizedBox(width: 8),
          _diyColorChip(c, btn.color2 ?? Color.lerp(btn.color ?? accent, c.isLight ? Colors.white : Colors.black, 0.28)!,
              onTap: () => _pickDiyColor(c, btn.color2 ?? Color.lerp(btn.color ?? accent, c.isLight ? Colors.white : Colors.black, 0.28)!,
                  allowFollow: true,
                  onPicked: (col) => _diyUpdateBtn(s, col == null ? btn.copyWith(clearColor2: true) : btn.copyWith(color2: col))),
            onRemove: null,
          ),
        ]),
      ],
      const SizedBox(height: 4),
      _diySlider(c, label: '圆角', value: btn.radius, min: 0, max: 32,
        fmt: (v) => '${v.round()}',
        onChanged: (v) => _diyDragBtn(btn.copyWith(radius: v)),
        onChangeEnd: (v) => _diyUpdateBtn(s, btn.copyWith(radius: v))),
      _diySlider(c, label: '高度', value: btn.height, min: 32, max: 64,
        fmt: (v) => '${v.round()}',
        onChanged: (v) => _diyDragBtn(btn.copyWith(height: v)),
        onChangeEnd: (v) => _diyUpdateBtn(s, btn.copyWith(height: v))),
      if (showBorder) ...[
        _diySlider(c, label: '描边宽度', value: btn.borderWidth, min: 0, max: 4,
          fmt: (v) => '${v.toStringAsFixed(1)}',
          onChanged: (v) => _diyDragBtn(btn.copyWith(borderWidth: v)),
          onChangeEnd: (v) => _diyUpdateBtn(s, btn.copyWith(borderWidth: v))),
        _diySlider(c, label: '描边深浅', value: btn.borderOpacity, min: 0.05, max: 1,
          fmt: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _diyDragBtn(btn.copyWith(borderOpacity: v)),
          onChangeEnd: (v) => _diyUpdateBtn(s, btn.copyWith(borderOpacity: v))),
      ],
      _diySlider(c, label: '阴影模糊', value: btn.shadowBlur, min: 0, max: 40,
        fmt: (v) => v.round().toString(),
        onChanged: (v) => _diyDragBtn(btn.copyWith(shadowBlur: v)),
        onChangeEnd: (v) => _diyUpdateBtn(s, btn.copyWith(shadowBlur: v))),
      _diySlider(c, label: '阴影浓度', value: btn.shadowOpacity, min: 0, max: 0.6,
        fmt: (v) => '${(v * 100).round()}%',
        onChanged: (v) => _diyDragBtn(btn.copyWith(shadowOpacity: v)),
        onChangeEnd: (v) => _diyUpdateBtn(s, btn.copyWith(shadowOpacity: v))),
      const SizedBox(height: 8),
      _diySegmented<double>(
        c,
        const [(400, '常规'), (500, '中等'), (600, '半粗'), (700, '加粗')],
        btn.fontWeight,
        (v) => _diyUpdateBtn(s, btn.copyWith(fontWeight: v)),
      ),
    ]);
  }

  /// 图层列表：每层一行（种类 / 上下移 / 显隐 / 删除），点行展开逐项调节
  Widget _diyLayerList(AppState s, AppColors c, DiyBackdrop bd) {
    final layers = bd.layers;
    if (layers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF26262C),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border.withValues(alpha: 0.6)),
        ),
        child: Column(children: [
          Text('还没有图层', style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
          const SizedBox(height: 8),
          _diyAddLayerButton(s, c, bd),
        ]),
      );
    }
    return Column(children: [
      for (var i = 0; i < layers.length; i++) _diyLayerRow(s, c, bd, i),
      const SizedBox(height: 10),
      if (layers.length < kDiyMaxLayers) _diyAddLayerButton(s, c, bd),
    ]);
  }

  Widget _diyAddLayerButton(AppState s, AppColors c, DiyBackdrop bd) {
    return OutlinedButton.icon(
      onPressed: () => _showLayerKindPicker(s, c, bd),
      icon: const Icon(Icons.add_rounded, size: 16),
      label: const Text('添加图层', style: TextStyle(fontSize: 12.5)),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 14)),
    );
  }

  Widget _diyLayerRow(AppState s, AppColors c, DiyBackdrop bd, int i) {
    final l = bd.layers[i];
    final expanded = _diyExpandedLayer == i;
    final isLight = c.isLight;
    final first = i == 0;
    final last = i == bd.layers.length - 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF2C2C33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: expanded ? (isLight ? kPrimary.withValues(alpha: 0.35) : const Color(0xFFA78BFA).withValues(alpha: 0.4)) : c.border),
      ),
      child: Column(children: [
        // 摘要行
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _diyExpandedLayer = expanded ? null : i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(_diyLayerIcon(l.kind), size: 17, color: isLight ? kPrimary : const Color(0xFFA78BFA)),
              const SizedBox(width: 9),
              Text(l.kind.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(width: 8),
              // 双色小预览点
              Container(width: 10, height: 10, decoration: BoxDecoration(color: l.color, shape: BoxShape.circle)),
              const SizedBox(width: 3),
              Container(width: 10, height: 10, decoration: BoxDecoration(color: l.color2, shape: BoxShape.circle)),
              const Spacer(),
              if (!l.enabled)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('已隐藏', style: TextStyle(fontSize: 10.5, color: c.textTertiary)),
                ),
              _diyIconBtn(c, Icons.keyboard_arrow_up_rounded, first ? null : () =>
                  _diyUpdateBd(s, bd.withLayerSwapped(i, i - 1))),
              _diyIconBtn(c, Icons.keyboard_arrow_down_rounded, last ? null : () =>
                  _diyUpdateBd(s, bd.withLayerSwapped(i, i + 1))),
              _diyIconBtn(c, l.enabled ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  () => _diyUpdateBd(s, bd.withLayerAt(i, l.copyWith(enabled: !l.enabled)))),
              _diyIconBtn(c, Icons.close_rounded, () => _diyUpdateBd(s, bd.withoutLayerAt(i))),
            ]),
          ),
        ),
        // 展开的参数面板
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: _diyLayerParams(s, c, bd, i),
          ),
      ]),
    );
  }

  /// 单个图层的参数面板：颜色 + 按 kind 出现的数值项
  Widget _diyLayerParams(AppState s, AppColors c, DiyBackdrop bd, int i) {
    final l = bd.layers[i];
    final kind = l.kind;

    void update(DiyLayer nl) => _diyUpdateBd(s, bd.withLayerAt(i, nl));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text('颜色', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(width: 12),
        _diyColorChip(c, l.color, onTap: () => _pickDiyColor(c, l.color, allowFollow: false,
            onPicked: (col) { if (col != null) update(l.copyWith(color: col)); }), onRemove: null),
        const SizedBox(width: 8),
        _diyColorChip(c, l.color2, onTap: () => _pickDiyColor(c, l.color2, allowFollow: false,
            onPicked: (col) { if (col != null) update(l.copyWith(color2: col)); }), onRemove: null),
        const SizedBox(width: 8),
        Text('主色 · 次色', style: TextStyle(fontSize: 10.5, color: c.textTertiary)),
      ]),
      // 位置：网格/圆点为偏移，其余为锚点（允许略出屏幕，与光束/光带"画外照入"的预设一致）
      if (kind != DiyLayerKind.noise && kind != DiyLayerKind.stripe && kind != DiyLayerKind.vignette) ...[
        _diySlider(c, label: '横向位置', value: l.x, min: -0.2, max: 1.2,
          fmt: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _diyDragBd(bd.withLayerAt(i, l.copyWith(x: v))),
          onChangeEnd: (v) => _diyUpdateBd(s, bd.withLayerAt(i, l.copyWith(x: v)))),
        _diySlider(c, label: '纵向位置', value: l.y, min: -0.2, max: 1.2,
          fmt: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _diyDragBd(bd.withLayerAt(i, l.copyWith(y: v))),
          onChangeEnd: (v) => _diyUpdateBd(s, bd.withLayerAt(i, l.copyWith(y: v)))),
      ],
      _diySlider(c, label: _layerSizeLabel(kind), value: l.size, min: _layerSizeRange(kind).$1, max: _layerSizeRange(kind).$2,
        fmt: (v) => _layerSizeFmt(kind, v),
        onChanged: (v) => _diyDragBd(bd.withLayerAt(i, l.copyWith(size: v))),
        onChangeEnd: (v) => _diyUpdateBd(s, bd.withLayerAt(i, l.copyWith(size: v)))),
      if (kind == DiyLayerKind.grid || kind == DiyLayerKind.stripe || kind == DiyLayerKind.beam)
        _diySlider(c, label: '角度', value: l.angle, min: 0, max: 360,
          fmt: (v) => '${v.round()}°',
          onChanged: (v) => _diyDragBd(bd.withLayerAt(i, l.copyWith(angle: v))),
          onChangeEnd: (v) => _diyUpdateBd(s, bd.withLayerAt(i, l.copyWith(angle: v)))),
      _diySlider(c, label: '强度', value: l.intensity, min: 0, max: 1,
        fmt: (v) => '${(v * 100).round()}%',
        onChanged: (v) => _diyDragBd(bd.withLayerAt(i, l.copyWith(intensity: v))),
        onChangeEnd: (v) => _diyUpdateBd(s, bd.withLayerAt(i, l.copyWith(intensity: v)))),
      _diySlider(c, label: _layerDensityLabel(kind), value: l.density, min: _layerDensityRange(kind).$1, max: _layerDensityRange(kind).$2,
        fmt: (v) => _layerDensityFmt(kind, v),
        onChanged: (v) => _diyDragBd(bd.withLayerAt(i, l.copyWith(density: v))),
        onChangeEnd: (v) => _diyUpdateBd(s, bd.withLayerAt(i, l.copyWith(density: v)))),
    ]);
  }

  IconData _diyLayerIcon(DiyLayerKind k) => switch (k) {
        DiyLayerKind.glow => Icons.blur_on_rounded,
        DiyLayerKind.grid => Icons.grid_on_rounded,
        DiyLayerKind.ribbon => Icons.waves_rounded,
        DiyLayerKind.noise => Icons.grain,
        DiyLayerKind.stripe => Icons.texture_rounded,
        DiyLayerKind.beam => Icons.highlight,
        DiyLayerKind.dots => Icons.circle,
        DiyLayerKind.vignette => Icons.vignette,
      };

  /// size 滑块的量程与文案（按图层种类的真实语义）
  (double, double) _layerSizeRange(DiyLayerKind k) => switch (k) {
        DiyLayerKind.glow => (0.1, 1.2),
        DiyLayerKind.grid => (8, 96),
        DiyLayerKind.ribbon => (0.04, 0.4),
        DiyLayerKind.noise => (0.5, 6),
        DiyLayerKind.stripe => (4, 90),
        DiyLayerKind.beam => (0.05, 0.6),
        DiyLayerKind.dots => (8, 120),
        DiyLayerKind.vignette => (0.2, 0.95),
      };

  String _layerSizeLabel(DiyLayerKind k) => switch (k) {
        DiyLayerKind.glow => '半径占比',
        DiyLayerKind.grid => '格间距',
        DiyLayerKind.ribbon => '带宽占比',
        DiyLayerKind.noise => '颗粒大小',
        DiyLayerKind.stripe => '条宽',
        DiyLayerKind.beam => '束宽占比',
        DiyLayerKind.dots => '点间距',
        DiyLayerKind.vignette => '内缩占比',
      };

  String _layerSizeFmt(DiyLayerKind k, double v) => switch (k) {
        DiyLayerKind.grid || DiyLayerKind.noise || DiyLayerKind.stripe || DiyLayerKind.dots => '${v.toStringAsFixed(v < 10 ? 1 : 0)}',
        _ => '${(v * 100).round()}%',
      };

  /// density 滑块的量程与文案（各 kind 的 density 含义不同）
  (double, double) _layerDensityRange(DiyLayerKind k) => switch (k) {
        DiyLayerKind.glow => (0, 1),
        DiyLayerKind.grid => (0.2, 4),
        DiyLayerKind.ribbon => (0, 1),
        DiyLayerKind.noise => (0.05, 1),
        DiyLayerKind.stripe => (0.05, 0.95),
        DiyLayerKind.beam => (0, 1),
        DiyLayerKind.dots => (0.3, 12),
        DiyLayerKind.vignette => (0.05, 1),
      };

  String _layerDensityLabel(DiyLayerKind k) => switch (k) {
        DiyLayerKind.glow => '边缘柔和',
        DiyLayerKind.grid => '线宽',
        DiyLayerKind.ribbon => '摆动幅度',
        DiyLayerKind.noise => '颗粒密度',
        DiyLayerKind.stripe => '占空比',
        DiyLayerKind.beam => '边缘衰减',
        DiyLayerKind.dots => '点半径',
        DiyLayerKind.vignette => '过渡柔和',
      };

  String _layerDensityFmt(DiyLayerKind k, double v) => switch (k) {
        DiyLayerKind.grid || DiyLayerKind.dots => v.toStringAsFixed(v < 10 ? 1 : 0),
        _ => '${(v * 100).round()}%',
      };

  /// 添加图层：选择种类
  Future<void> _showLayerKindPicker(AppState s, AppColors c, DiyBackdrop bd) async {
    final isLight = c.isLight;
    final picked = await showDialog<DiyLayerKind>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: isLight ? Colors.white : const Color(0xFF2B2B32),
        title: Text('选择图层种类', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
        children: [
          for (final k in DiyLayerKind.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, k),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(_diyLayerIcon(k), size: 18, color: isLight ? kPrimary : const Color(0xFFA78BFA)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(k.label, style: TextStyle(fontSize: 13.5, color: c.text))),
                ]),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    _diyUpdateBd(s, bd.withLayerAt(bd.layers.length, DiyLayer.defaultOf(picked)));
    setState(() => _diyExpandedLayer = bd.layers.length); // 展开新图层方便继续调
  }

  // ============== DIY 通用小组件 ==============

  Widget _diyIconBtn(AppColors c, IconData icon, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 17, color: onTap == null ? c.textTertiary.withValues(alpha: 0.4) : c.textSecondary),
        ),
      );

  /// 自绘分段选择（比 SegmentedButton 更紧凑，项目设置页风格一致）
  Widget _diySegmented<T>(AppColors c, List<(T, String)> items, T current, ValueChanged<T> onTap) {
    final isLight = c.isLight;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFEDEEF3) : const Color(0xFF1B1B20),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        for (final (v, label) in items)
          Expanded(
            child: GestureDetector(
              onTap: () => onTap(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: identical(v, current) || v == current ? (isLight ? Colors.white : const Color(0xFF33333A)) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: identical(v, current) && isLight
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 1))]
                      : null,
                ),
                child: Text(label, style: TextStyle(
                    fontSize: 12,
                    fontWeight: identical(v, current) || v == current ? FontWeight.w700 : FontWeight.w500,
                    color: identical(v, current) || v == current ? c.text : c.textSecondary)),
              ),
            ),
          ),
      ]),
    );
  }

  /// 统一滑块行：标签 + 当前值 + 滑块；hint 为次要说明
  Widget _diySlider(
    AppColors c, {
    required String label,
    required double value,
    required double min,
    required double max,
    required String Function(double) fmt,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    String? hint,
  }) {
    final accent = c.isLight ? kPrimary : const Color(0xFFA78BFA);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textSecondary)),
          const Spacer(),
          Text(fmt(value.clamp(min, max)), style: TextStyle(fontSize: 11.5, color: c.textTertiary, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(hint, style: TextStyle(fontSize: 10.5, color: c.textTertiary)),
          ),
        SizedBox(
          height: 26,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: accent.withValues(alpha: 0.55),
              inactiveTrackColor: c.sliderInactive.withValues(alpha: 0.5),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ),
      ]),
    );
  }

  /// 开关行
  Widget _diySwitchLine(AppColors c, String label, String hint, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 2),
            Text(hint, style: TextStyle(fontSize: 10.5, color: c.textTertiary)),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 28,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: c.isLight ? kPrimary : const Color(0xFFA78BFA),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ]),
    );
  }

  /// 单个色块：圆角方块 + 当前色描边环，可选右上角删除
  Widget _diyColorChip(AppColors c, Color color, {required VoidCallback onTap, required VoidCallback? onRemove}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.isLight ? Colors.black.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.2), width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0, 1))],
        ),
        child: onRemove == null
            ? null
            : GestureDetector(
                onTap: onRemove,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: c.isLight ? Colors.white : const Color(0xFF33333A),
                      shape: BoxShape.circle,
                      border: Border.all(color: c.border, width: 0.8),
                    ),
                    child: Icon(Icons.close_rounded, size: 9, color: c.textSecondary),
                  ),
                ),
              ),
      ),
    );
  }

  /// "跟随主题"胶囊：展示当前生效色 + 说明状态；已跟随时整颗高亮
  Widget _followThemeChip(AppColors c, bool following, Color color, String label) {
    final isLight = c.isLight;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: following
            ? (isLight ? kPrimary.withValues(alpha: 0.1) : const Color(0xFFA78BFA).withValues(alpha: 0.16))
            : (isLight ? Colors.white : const Color(0xFF33333A)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: following
              ? (isLight ? kPrimary.withValues(alpha: 0.5) : const Color(0xFFA78BFA).withValues(alpha: 0.55))
              : (isLight ? Colors.black.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: following ? FontWeight.w700 : FontWeight.w500, color: following ? (isLight ? kPrimary : const Color(0xFFA78BFA)) : c.textSecondary)),
      ]),
    );
  }

  /// 取色弹窗：12 色板 + 自定义 hex；allowFollow 时提供"跟随主题"（返回 null）
  Future<void> _pickDiyColor(AppColors c, Color current,
      {required bool allowFollow, required ValueChanged<Color?> onPicked}) async {
    final isLight = c.isLight;
    final accent = isLight ? kPrimary : const Color(0xFFA78BFA);
    final hexCtrl = TextEditingController(text: diyColorToHex(current));
    Color? picked = current;
    final result = await showDialog<Color?>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          backgroundColor: isLight ? Colors.white : const Color(0xFF2B2B32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('选择颜色', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
          content: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final col in kDiyPalette)
                    GestureDetector(
                      onTap: () => setDlg(() => picked = col),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: col,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: picked == col ? accent : (isLight ? Colors.black.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.18)),
                            width: picked == col ? 2.4 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: hexCtrl,
                    style: TextStyle(fontSize: 13, color: c.text),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '#RRGGBB',
                      hintStyle: TextStyle(fontSize: 12, color: c.textTertiary),
                      filled: true,
                      fillColor: isLight ? const Color(0xFFF4F4F8) : const Color(0xFF33333A),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) {
                      final col = diyParseColor(v);
                      if (col != null) setDlg(() => picked = col);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: picked ?? current,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                ),
              ]),
              if (allowFollow) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: Text('恢复跟随主题主色', style: TextStyle(fontSize: 12.5, color: accent)),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, current), child: Text('取消', style: TextStyle(fontSize: 13, color: c.textSecondary))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, picked),
              style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, minimumSize: const Size(0, 36)),
              child: const Text('确定', style: TextStyle(fontSize: 13)),
            ),
          ],
        );
      }),
    );
    if (result != null) onPicked(result);
  }

  // ============== 小组件 ==============

  Widget _sectionTitle(String t, AppColors c) => Text(t, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text, letterSpacing: 0.2));

  InputDecoration _deco(AppColors c, {String? hint}) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: c.inputHint),
    isDense: true,
    // 显式透明填充，避免 Material 3 默认的 surfaceTint 浅紫色渗入
    filled: true,
    fillColor: Colors.transparent,
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
    // 不能在 initState 调 AppScope.of（created 生命周期断言崩溃），移至 didChangeDependencies
  }

  bool _depsInited = false;
  AppState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_depsInited) return;
    _depsInited = true;
    final s = AppScope.of(context);
    _state = s;
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
    if (_depsInited) {
      _state?.removeListener(_onStateChanged);
      _url.dispose();
      _key.dispose();
      _modelCtrl.dispose();
    }
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
    // 显式透明填充，避免 Material 3 默认的 surfaceTint 浅紫色渗入
    filled: true,
    fillColor: Colors.transparent,
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
