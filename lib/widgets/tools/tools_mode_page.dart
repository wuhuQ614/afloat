/// 工具模式外壳：一比一复刻参考项目（优化版本）App.jsx 的界面架构。
///
/// 结构（对齐参考项目）：
/// - 垂直三段式：顶部标题栏（空内容 + 主题切换 + 设置按钮）→ 中间内容区 → 底部胶囊标签栏
/// - max-w-md 居中（桌面）/ 全宽（手机）
/// - 玻璃主题（aurora 极光渐变背景 + 毛玻璃卡片/标签栏），暗色/亮色模式
///
/// 标签页（参考项目去掉骰子后保留的四个）：
/// - wheel  暴力转盘（紫）
/// - bomb   暴力翻牌（橙）
/// - number 暴力数字（紫罗兰）
/// - games  更多（玫红）：画板 / BMI 计算 / 五子棋 / 中国象棋 入口卡片
library;

import 'dart:ui' as ui show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_svg/flutter_svg.dart';
import '../../state.dart';
import '../settings_dialog.dart';
import '../drawing/drawing_feature_page.dart';
import 'bomb_page.dart';
import 'bmi_page.dart';
import 'gomoku_page.dart';
import 'chess_page.dart';
import 'number_page.dart';
import 'wheel_page.dart';

/// 工具模式主题：white（亮色）/ dark（暗色）/ glass（极光玻璃），循环切换
enum _ToolsTheme { white, dark, glass }

class ToolsModePage extends StatefulWidget {
  final AppState state;
  const ToolsModePage({super.key, required this.state});

  @override
  State<ToolsModePage> createState() => _ToolsModePageState();
}

class _ToolsModePageState extends State<ToolsModePage> with TickerProviderStateMixin {
  String _activeTab = 'wheel'; // wheel | bomb | number | games
  /// 标签栏滑块动画（对齐 cubic-bezier(0.25,1,0.5,1) 0.35s）
  late final AnimationController _sliderCtrl;
  late final CurvedAnimation _sliderCurve;
  int _prevTabIndex = 0;

  /// 页面切换方向感知动画（对齐参考项目 page-slide-left/right-enter）：
  /// 0.55s cubic-bezier(0.22,1,0.36,1)，translateX(±30px)+scale(0.95)+opacity(0.6)→复位
  late final AnimationController _pageCtrl;
  /// 切换方向：true = 从右滑入（向后切，新索引>旧索引），false = 从左滑入
  bool _slideFromRight = true;

  // "更多"页内部子导航：null = 入口卡片列表；否则为具体游戏
  String? _activeGame; // 'bmi' | 'gomoku' | 'chess' | 'drawing'

  AppState get s => widget.state;

  /// P0-1：缓存 AppState 中本页面实际使用的字段，仅当这些字段变化时才 setState
  late String _prevUiStyle;
  late bool _prevDarkMode;

  /// P1-4：缓存游戏入口列表，仅在 initState 时创建一次
  late final List<_GameEntry> _gameEntries;

  static const List<_TabDef> _tabs = [
    _TabDef(id: 'wheel', label: '暴力转盘', color: Color(0xFF8B5CF6)),
    _TabDef(id: 'bomb', label: '暴力翻牌', color: Color(0xFFF97316)),
    _TabDef(id: 'number', label: '暴力数字', color: Color(0xFF9333EA)),
    _TabDef(id: 'games', label: '更多', color: Color(0xFFF43F5E)),
  ];

  _ToolsTheme get _theme {
    if (s.isGlassUI) return _ToolsTheme.glass;
    return s.darkMode ? _ToolsTheme.dark : _ToolsTheme.white;
  }

  @override
  void initState() {
    super.initState();
    _sliderCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    // 预创建 CurvedAnimation，避免在 AnimatedBuilder.builder 内每帧创建新实例
    _sliderCurve = CurvedAnimation(
      parent: _sliderCtrl,
      curve: const Cubic(0.25, 1, 0.5, 1),
    );
    _pageCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _prevUiStyle = s.uiStyle;
    _prevDarkMode = s.darkMode;
    s.addListener(_onState);
    _gameEntries = _buildGameEntries();
  }

  /// P0-1：仅在 darkMode / uiStyle 实际变化时才 setState，避免 AppState 其他 93 处 notify 触发整页重建
  void _onState() {
    if (!mounted) return;
    if (s.uiStyle != _prevUiStyle || s.darkMode != _prevDarkMode) {
      _prevUiStyle = s.uiStyle;
      _prevDarkMode = s.darkMode;
      setState(() {});
    }
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    _sliderCurve.dispose();
    _sliderCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  void _selectTab(String id) {
    final idx = _tabs.indexWhere((t) => t.id == id);
    if (idx < 0 || id == _activeTab) return;
    // 对齐参考项目 vibrate(10)：短促触感反馈（桌面端为 no-op，不影响运行）
    HapticFeedback.selectionClick();
    final oldIdx = _tabs.indexWhere((t) => t.id == _activeTab);
    _prevTabIndex = oldIdx < 0 ? 0 : oldIdx; // 动画起点 = 旧位置
    // 方向：新索引 > 旧索引 → 向后切 → 从右滑入（page-slide-left-enter）
    _slideFromRight = idx > oldIdx;
    setState(() {
      _activeTab = id;
      _activeGame = null; // 切换标签时重置"更多"页子导航
    });
    _sliderCtrl.forward(from: 0);
    _pageCtrl.forward(from: 0); // 触发页面方向感知滑入动画
  }

  /// 主题循环：white → dark → glass → white（对齐参考项目 cycleTheme）
  void _cycleTheme() {
    switch (_theme) {
      case _ToolsTheme.white:
        s.toggleDarkMode(true);
        s.setUiStyle('classic');
      case _ToolsTheme.dark:
        s.toggleDarkMode(false);
        s.setUiStyle('glass');
      case _ToolsTheme.glass:
        s.setUiStyle('classic');
        s.toggleDarkMode(false);
    }
  }

  bool get _isGlass => _theme == _ToolsTheme.glass;
  bool get _isDark => _theme == _ToolsTheme.dark;

  // ==================== 主题配色 ====================

  /// 背景（极光玻璃渐变 / 暗色 / 亮色）
  Widget _buildBackground() {
    if (_isGlass) {
      // aurora-bg：135° 六色极光渐变
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE0F2FE),
              Color(0xFFE8EAF6),
              Color(0xFFFCE4EC),
              Color(0xFFE0F7FA),
              Color(0xFFEDE7F6),
              Color(0xFFE0F2FE),
            ],
            stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
          ),
        ),
      );
    }
    return Container(color: _isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB));
  }

  Color get _textPrimary => _isGlass
      ? const Color(0xFF1E293B)
      : _isDark
          ? Colors.white
          : const Color(0xFF111827);

  Color get _textSub => _isGlass
      ? const Color(0xFF64748B)
      : _isDark
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF6B7280);

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: RepaintBoundary(child: _buildBackground())),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448), // max-w-md
                  child: Column(
                    children: [
                      RepaintBoundary(child: _buildTopBar()),
                      Expanded(child: _wrapPageTransition(_buildContent())),
                      RepaintBoundary(child: _buildTabBar()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部栏：左侧空白（对齐参考项目 App.jsx:813-814）+ 右侧胶囊按钮容器
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Spacer(),
          _buildTopButtonPill(),
        ],
      ),
    );
  }

  /// 顶栏按钮胶囊容器（对齐参考项目 App.jsx:816-822）：
  /// rounded-full p-1 gap-0.5，glass 时毛玻璃+白边框+阴影，暗色时半透明灰
  /// P0-2：顶栏玻璃容器添加 RepaintBoundary 隔离重绘
  Widget _buildTopButtonPill() {
    final Widget pillContent = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 主题切换按钮（p-2.5 rounded-full，激活时 active:scale-90）
        _buildThemeToggleButton(),
        // 设置按钮（三横线菜单图标）
        Tooltip(
          message: '设置',
          child: InkWell(
            onTap: () => showDialog(context: context, builder: (_) => const SettingsDialog()),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SvgPicture.string(
                _svgMenu,
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  _isGlass ? const Color(0xFF64748B) : _isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (_isGlass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: Colors.white.withValues(alpha: 0.18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                boxShadow: const [
                  BoxShadow(color: Color(0x0F1F2687), blurRadius: 32, offset: Offset(0, 8)),
                ],
              ),
              child: pillContent,
            ),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: _isDark ? const Color(0xFF374151).withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.04),
        border: Border.all(
          color: _isDark ? const Color(0xFF4B5563).withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: pillContent,
    );
  }

  /// 主题切换按钮：白色模式显示太阳、暗色显示月亮、glass 显示晶体（对齐参考项目）
  Widget _buildThemeToggleButton() {
    final String svg;
    final Color iconColor;
    final String tooltip;
    switch (_theme) {
      case _ToolsTheme.white:
        svg = _svgSun;
        iconColor = const Color(0xFF4B5563); // text-gray-600
        tooltip = '白色模式 · 点击切换深色';
      case _ToolsTheme.dark:
        svg = _svgMoon;
        iconColor = const Color(0xFFFACC15); // text-yellow-400
        tooltip = '深色模式 · 点击切换通透';
      case _ToolsTheme.glass:
        svg = _svgCrystal;
        iconColor = const Color(0xFF475569); // text-slate-600
        tooltip = '通透主题 · 点击切换白色';
    }
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: _cycleTheme,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SvgPicture.string(
            svg,
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  /// 页面切换方向感知动画（对齐参考项目 slideLeftIn / slideRightIn）：
  /// from { translateX(±24px) } → to { 复位 }
  /// 缓动 cubic-bezier(0.22, 1, 0.36, 1)，时长 0.55s
  ///
  /// 性能优化：
  /// - 去掉 Opacity（saveLayer 是切换卡顿主因）
  /// - 去掉 scale（移动端 GPU 负担）
  /// - child 复用，builder 只创建 Transform
  /// - 整页被 RepaintBoundary 隔离
  Widget _wrapPageTransition(Widget child) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pageCtrl,
        builder: (context, _) {
          final t = const Cubic(0.22, 1, 0.36, 1).transform(_pageCtrl.value);
          final dx = (1.0 - t) * 14.0 * (_slideFromRight ? 1.0 : -1.0);
          return Transform.translate(
            offset: Offset(dx, 0),
            child: child,
          );
        },
        child: child,
      ),
    );
  }

  /// 中间内容区
  /// 使用 IndexedStack 保持所有页面 State 存活，切换时无需 dispose/recreate
  Widget _buildContent() {
    // "更多"标签：内部子导航（不参与 IndexedStack）
    if (_activeTab == 'games') {
      if (_activeGame == null) return _buildGamesHub();
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: _buildActiveGame(),
      );
    }

    // 3 个主标签页用 IndexedStack 保持 State 存活
    final idx = _tabs.indexWhere((t) => t.id == _activeTab);
    return IndexedStack(
      index: idx,
      children: [
        WheelTabPage(state: s),
        const BombTabPage(),
        const NumberTabPage(),
        const SizedBox(), // games 占位（实际走上面的分支）
      ],
    );
  }

  /// P1-4：构建游戏入口列表（缓存为字段，仅初始化时调用一次）
  List<_GameEntry> _buildGameEntries() {
    return [
      _GameEntry(
        title: '画板',
        icon: const Icon(Icons.brush_rounded, color: Colors.white, size: 28),
        iconGradient: const [Color(0xFF3B82F6), Color(0xFF4F46E5)],
        decoColor: const Color(0x3360A5FA), // blue-400/20
        onTap: () => setState(() => _activeGame = 'drawing'),
      ),
      _GameEntry(
        title: 'BMI 计算',
        icon: const Text('BMI',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1)),
        iconGradient: const [Color(0xFF86EFAC), Color(0xFF34D399)],
        decoColor: const Color(0x33818CF8), // indigo-400/20
        onTap: () => setState(() => _activeGame = 'bmi'),
      ),
      _GameEntry(
        title: '五子棋',
        icon: CustomPaint(size: const Size(28, 28), painter: _GomokuIconPainter()),
        iconGradient: const [Color(0xFFD97706), Color(0xFFB45309)],
        decoColor: const Color(0x33FBBF24), // amber-400/20
        onTap: () => setState(() => _activeGame = 'gomoku'),
      ),
      _GameEntry(
        title: '中国象棋',
        icon: const Text('象',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24)),
        iconGradient: const [Color(0xFFEF4444), Color(0xFFEA580C)],
        decoColor: const Color(0x33F87171), // red-400/20
        onTap: () => setState(() => _activeGame = 'chess'),
      ),
    ];
  }

  /// "更多"页：入口卡片列表（对齐 GamesTab：画板/BMI/五子棋/象棋）
  Widget _buildGamesHub() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: _gameEntries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, i) => _GameEntryCard(
        entry: _gameEntries[i],
        textPrimary: _textPrimary,
        textSub: _textSub,
        isGlass: _isGlass,
        isDark: _isDark,
      ),
    );
  }

  Widget _buildActiveGame() {
    switch (_activeGame) {
      case 'drawing':
        return DrawingFeaturePage(darkMode: _isDark);
      case 'bmi':
        return BmiTabPage(onBack: () => setState(() => _activeGame = null));
      case 'gomoku':
        return const GomokuPage();
      case 'chess':
        return const ChineseChessPage();
      default:
        return const SizedBox();
    }
  }

  // ==================== 底部胶囊标签栏 ====================

  Widget _buildTabBar() {
    final curIdx = _tabs.indexWhere((t) => t.id == _activeTab);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: _glassTabBarContainer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final segW = w / _tabs.length;
            return SizedBox(
              height: 64,
              child: Stack(
                children: [
                  // 滑块动画（使用预创建的 _sliderCurve，避免每帧创建 CurvedAnimation）
                  AnimatedBuilder(
                    animation: _sliderCtrl,
                    builder: (context, child) {
                      final animT = _sliderCurve.value;
                      final from = _prevTabIndex.toDouble();
                      final to = curIdx.toDouble();
                      final pos = from + (to - from) * animT;
                      return Positioned(
                        left: pos * segW + 4,
                        top: 4,
                        bottom: 4,
                        width: segW - 8,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            // 对齐参考项目：glass 0.4 白 / 暗色 0.1 白 / 亮色 0.8 白
                            color: _isGlass
                                ? Colors.white.withValues(alpha: 0.4)
                                : _isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: _isGlass ? 0.04 : 0.06),
                                blurRadius: 3,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // 标签项
                  Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: _buildTabItem(_tabs[i], i == curIdx),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _glassTabBarContainer({required Widget child}) {
    if (_isGlass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                boxShadow: [
                  BoxShadow(color: const Color(0x0F1F2687), blurRadius: 32, offset: const Offset(0, 8)),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  Widget _buildTabItem(_TabDef tab, bool active) {
    // 激活态：上移2px + 放大1.08（对齐参考项目）
    final color = active ? tab.color : _textSub;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectTab(tab.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: const Cubic(0.25, 1, 0.5, 1),
        transform: active
            ? (Matrix4.identity()..translate(0.0, -2.0)..scale(1.08))
            : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 一比一复刻参考项目的 SVG 图标（对齐 size=18）
            SvgPicture.string(
              _tabIconSvg(tab.id),
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(height: 2),
            Text(
              tab.label,
              // 激活态 fontWeight=700，非激活 opacity=0.7 + fontWeight=500（对齐参考项目）
              style: TextStyle(
                fontSize: 9,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? color : color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== 底部标签栏 SVG 图标（一比一复刻参考项目 icons.jsx 的原始 path） =====

  /// 转盘图标（WheelIcon：圆 + 6 条辐条）
  static const String _svgWheel = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<circle cx="12" cy="12" r="10"/>
<path d="m14.31 8 5.74 9.94"/>
<path d="M9.69 8h11.48"/>
<path d="m7.38 12 5.74-9.94"/>
<path d="M9.69 16 3.95 6.06"/>
<path d="M14.31 16H2.83"/>
<path d="m16.62 12-5.74 9.94"/>
</svg>''';

  /// 翻牌图标（App.jsx 内联：旋转的扑克牌 + 菱形花纹）
  static const String _svgBomb = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
<rect transform="rotate(90 12 12)" x="3" y="5" width="18" height="14" rx="2"/>
<line x1="8" y1="6" x2="8.01" y2="6"/>
<line x1="16" y1="18" x2="16.01" y2="18"/>
<path d="M12 16l-3-4 3-4 3 4z" fill="currentColor"/>
</svg>''';

  /// 数字图标（HashIcon：# 井号）
  static const String _svgNumber = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<line x1="4" x2="20" y1="9" y2="9"/>
<line x1="4" x2="20" y1="15" y2="15"/>
<line x1="10" x2="8" y1="3" y2="21"/>
<line x1="16" x2="14" y1="3" y2="21"/>
</svg>''';

  /// 更多图标（App.jsx 内联：手机 + 加号 + 圆点）
  static const String _svgGames = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<rect x="6" y="3" width="12" height="18" rx="2"/>
<path d="M12 8v4"/>
<path d="M10 10h4"/>
<circle cx="12" cy="16" r="1"/>
</svg>''';

  /// 主题切换：太阳图标（SunIcon，白色模式显示）
  static const String _svgSun = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<circle cx="12" cy="12" r="4"/>
<path d="M12 2v2"/><path d="M12 20v2"/>
<path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/>
<path d="M2 12h2"/><path d="M20 12h2"/>
<path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>
</svg>''';

  /// 主题切换：月亮图标（MoonIcon，暗色模式显示）
  static const String _svgMoon = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>
</svg>''';

  /// 主题切换：晶体图标（glass 模式显示，App.jsx 内联六边形晶体）
  static const String _svgCrystal = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
<path d="M12 3L19 8.5V15.5L12 21L5 15.5V8.5Z" opacity="0.5"/>
<path d="M12 3V21" opacity="0.25"/>
<path d="M5 8.5L19 8.5" opacity="0.25"/>
<path d="M5 15.5L19 15.5" opacity="0.25"/>
<path d="M5 8.5L12 12L19 8.5" opacity="0.4"/>
<path d="M5 15.5L12 12L19 15.5" opacity="0.4"/>
</svg>''';

  /// 设置：三横线菜单图标（App.jsx 内联）
  static const String _svgMenu = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
<path d="M3 12h18M3 6h18M3 18h18"/>
</svg>''';

  String _tabIconSvg(String id) {
    switch (id) {
      case 'wheel':
        return _svgWheel;
      case 'bomb':
        return _svgBomb;
      case 'number':
        return _svgNumber;
      case 'games':
      default:
        return _svgGames;
    }
  }
}

/// 标签定义
class _TabDef {
  final String id;
  final String label;
  final Color color;
  const _TabDef({required this.id, required this.label, required this.color});
}

/// 游戏入口定义
class _GameEntry {
  final String title;
  final Widget icon;
  final List<Color> iconGradient;
  final Color decoColor;
  final VoidCallback onTap;
  const _GameEntry({
    required this.title,
    required this.icon,
    required this.iconGradient,
    required this.decoColor,
    required this.onTap,
  });
}

/// P1-3：游戏入口卡片（StatefulWidget，hover 状态下沉到内部，避免整页 setState）
class _GameEntryCard extends StatefulWidget {
  final _GameEntry entry;
  final Color textPrimary;
  final Color textSub;
  final bool isGlass;
  final bool isDark;
  const _GameEntryCard({
    required this.entry,
    required this.textPrimary,
    required this.textSub,
    required this.isGlass,
    required this.isDark,
  });

  @override
  State<_GameEntryCard> createState() => _GameEntryCardState();
}

class _GameEntryCardState extends State<_GameEntryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: e.onTap,
        child: _buildGlassCard(
          borderRadius: 16,
          isGlass: widget.isGlass,
          isDark: widget.isDark,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [e.decoColor, Colors.transparent],
                    ),
                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(96)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: e.iconGradient,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: e.icon,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(e.title,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: widget.textPrimary)),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      transform: _hovered
                          ? (Matrix4.identity()..translate(4.0, 0.0))
                          : Matrix4.identity(),
                      child: Icon(Icons.chevron_right_rounded, size: 20, color: widget.textSub),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 毛玻璃/普通卡片表面容器（与 _glassSurface 视觉一致，但内联以避免依赖父 State）
  static Widget _buildGlassCard({
    required Widget child,
    required double borderRadius,
    required bool isGlass,
    required bool isDark,
  }) {
    if (isGlass) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(borderRadius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(color: Colors.white.withValues(alpha: 0.6), blurRadius: 0, offset: const Offset(0, 1)),
                  BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 6)),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

/// 五子棋入口图标（四个渐变透明度的圆，对齐参考项目 SVG）
class _GomokuIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.125;
    void dot(double cx, double cy, double opacity) {
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }
    dot(size.width * 0.3, size.height * 0.3, 0.9);
    dot(size.width * 0.7, size.height * 0.3, 0.6);
    dot(size.width * 0.3, size.height * 0.7, 0.6);
    dot(size.width * 0.7, size.height * 0.7, 0.3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
