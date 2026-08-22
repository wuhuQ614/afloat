/// SmartEnglish 智能英语学习 - Flutter Windows 桌面版 (afloat 风格)
library;

import 'dart:async' show Timer;
import 'dart:convert';
import 'dart:io' show File, FileMode, Platform, Directory, Process, ProcessStartMode;
import 'dart:ui' show FontFeature, ImageFilter, PlatformDispatcher;
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';
import 'state.dart';
import 'models.dart';
import 'services/tts_service.dart';
import 'services/chat_capabilities.dart';
import 'theme_colors.dart';
import 'widgets/learn_page.dart';
import 'widgets/grammar_page.dart';
import 'widgets/onboarding_page.dart';
import 'widgets/pages.dart';
import 'widgets/exam_page.dart';
import 'widgets/dev_console.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/platform_select_page.dart';
import 'widgets/glass_background.dart';
import 'widgets/maimemo_wordbook_page.dart';
import 'widgets/browser_page.dart';
import 'widgets/snake_game_page.dart';
import 'widgets/snake_pvp_page.dart';
import 'widgets/gomoku_page.dart';
import 'widgets/source_viewer_page.dart';
import 'widgets/agent_rows.dart';

final bool _isWindows = !kIsWeb && Platform.isWindows;

// 更多功能列表：(图标, 标题, 副标题, 页面索引)
const _moreItemsData = [
  (Icons.list_alt_outlined, '题库', '管理题目集', 4),
  (Icons.error_outline_outlined, '错题本', '复习做错的题', 5),
  (Icons.star_outline_outlined, '生词本', '收藏的生词', 6),
  (Icons.bookmark_add_outlined, '答题记录', '记录已答单词', 7),
  (Icons.edit_note_outlined, '默写', '单词默写练习', 8),
  (Icons.auto_stories_outlined, '墨墨', '同步墨墨词库', 18),
  (Icons.school_outlined, '语法学习', '从零学会专升本语法', 12),
  (Icons.language_rounded, '浏览器', '轻量网页浏览', 19),
  (Icons.videogame_asset_outlined, '贪吃蛇', '经典小游戏放松', 20),
  (Icons.groups_outlined, '贪吃蛇双人', '40×40 双蛇对战', 24),
  (Icons.grid_3x3_rounded, '五子棋', '双人对战五子连珠', 23),
];

// 更多功能选择页索引
const _morePageIndex = 9;

/// 导航项按压反馈：按下时整体缩放，松开回弹
class _NavPressFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double pressedScale;
  final BorderRadius borderRadius;
  const _NavPressFeedback({
    required this.child,
    required this.onTap,
    this.pressedScale = 0.94,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });
  @override
  State<_NavPressFeedback> createState() => _NavPressFeedbackState();
}

class _NavPressFeedbackState extends State<_NavPressFeedback> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// 侧边栏导航指示器：underline=灰色下划线，pill=紫色渐变胶囊
class _SidebarNavPill extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final bool showChevron;
  final String indicator; // 'underline' | 'pill'
  const _SidebarNavPill({required this.selected, required this.icon, required this.label, this.showChevron = false, this.indicator = 'underline'});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final usePill = indicator == 'pill';

    if (usePill) {
      // === 紫色渐变胶囊 ===
      return AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xFF9F7AEA), Color(0xFF7C3AED)],
                )
              : null,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kPrimary.withValues(alpha: 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: _buildRow(c, selected: selected, usePill: true),
      );
    }

    // === 灰色下划线 ===（背景完全透明，只在底部画一条 3px 灰线）
    final underlineColor = c.isLight ? const Color(0xFF9CA3AF) : const Color(0xFFB0B5C0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        // 选中时用极淡的灰色背景指示行，未选中全透明
        color: selected
            ? (c.isLight ? Colors.black.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.04))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        // 未选中时不画底边线，避免 width:0 配圆角触发 hairline 断言
        border: selected
            ? Border(bottom: BorderSide(color: underlineColor, width: 3.0))
            : null,
      ),
      child: _buildRow(c, selected: selected, usePill: false),
    );
  }

  Row _buildRow(AppColors c, {required bool selected, required bool usePill}) {
    final textColor = usePill && selected ? Colors.white : c.text;
    final iconColor = usePill && selected ? Colors.white : c.textSecondary;
    return Row(children: [
      Icon(icon, size: 19, color: iconColor),
      const SizedBox(width: 11),
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? textColor : c.textSecondary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (showChevron)
        Icon(
          Icons.chevron_right_rounded,
          size: 17,
          color: (usePill && selected) ? Colors.white.withValues(alpha: 0.8) : c.textTertiary,
        ),
    ]);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 全局异常日志：捕获未处理异常写入文件，便于定位运行时白屏/崩溃
  FlutterError.onError = (details) {
    _writeErrorLog(details.exceptionAsString(), details.stack?.toString() ?? '');
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _writeErrorLog(error.toString(), stack.toString());
    return true;
  };
  if (_isWindows) {
    await windowManager.ensureInitialized();
  }
  // 后台初始化 TTS（失败时自动降级为不可用）
  TtsService.instance.init();
  runApp(const SmartEnglishApp());
}

/// 追加写入运行时错误日志（Windows: %APPDATA%\AFloat\error_log.txt；其他: 应用目录）
void _writeErrorLog(String err, String stack) {
  try {
    final dir = Platform.environment['APPDATA'];
    final base = (dir != null && dir.isNotEmpty) ? '$dir\\AFloat' : '.';
    final f = File('$base\\error_log.txt');
    f.createSync(recursive: true);
    f.writeAsStringSync(
      '==== ${DateTime.now()} ====\n$err\n$stack\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

class SmartEnglishApp extends StatefulWidget {
  const SmartEnglishApp({super.key});

  @override
  State<SmartEnglishApp> createState() => _SmartEnglishAppState();
}

class _SmartEnglishAppState extends State<SmartEnglishApp> {
  final AppState _state = AppState();
  bool _ready = false;
  // 页面索引已上提到 AppState.page（0 学习 1 答题 2 学习报告 3 查询 | 更多: 4 题库 5 错题本 6 生词本 7 答题记录 8 默写）
  bool _lastDarkMode = false;
  bool _lastFullscreen = false;
  /// 手机端浏览器页是否临时显示底部导航栏
  bool _showBrowserNav = false;
  Timer? _browserNavTimer;
  /// 各聊天按钮的 GlobalKey，用于从按钮位置浮出对应面板
  final GlobalKey _modelSelectorBtnKey = GlobalKey();
  final GlobalKey _plusBtnKey = GlobalKey();
  final GlobalKey _contextPillKey = GlobalKey();
  final GlobalKey _permissionBtnKey = GlobalKey();
  final GlobalKey _workspaceBtnKey = GlobalKey();
  /// Root Navigator 句柄，用于切换 uiMode 前清空浮层/modal
  final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();

  // R5: Markdown 解析 RegExp 提升为 static final，避免每次重建新建
  static final _reStrikethrough = RegExp(r'~~(.+?)~~');
  static final _reBold = RegExp(r'\*\*(.+?)\*\*');
  static final _reItalic = RegExp(r'\*(.+?)\*');
  static final _reInlineCode = RegExp(r'`([^`]+)`');
  static final _reLink = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final _reOrderedList = RegExp(r'^(\d+)\.\s+(.*)$');
  // R5: Markdown 解析缓存（按内容+颜色哈希失效）
  final Map<int, TextSpan> _markdownCache = {};
  // R6: 滚动节流：记录上次滚动时间
  int _lastScrollTime = 0;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
    _init();
    // 全局键盘监听（不受焦点转移影响）
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.f11) {
      _state.toggleFullscreen(!_state.fullscreen);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.f8) {
      _switchUiMode(_state.uiMode == 'mobile' ? 'desktop' : 'mobile');
      return true;
    }

    return false;
  }

  /// 切换 UI 模式（mobile <-> desktop），关键步骤：
  /// 1. 先把 root navigator 上的所有 modal/dialog 关闭（包括 mobile 端打开的 AI chat 全屏页、
  ///    dev console、设置弹窗等），避免切到 desktop 时上面还盖着一层 mobile 状态导致白屏/空白。
  /// 2. 再调用 setState 通知 AppState 切换 uiMode，并由 MaterialApp 的 ListenableBuilder
  ///    用 KeyedSubtree 重建 desktop/mobile 布局分支。
  void _switchUiMode(String mode) {
    // popUntil first route — 先把浮在上面的 overlay（modal/dialog/snackbar/tooltip）
    // 全部 pop 掉，避免 desktop 切完后下方还有 mobile 状态的浮动 UI 残留造成视觉错位
    final nav = _rootNavKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    _state.setUiMode(mode);
  }

  Future<void> _init() async {
    await _state.init().timeout(const Duration(seconds: 8), onTimeout: () {});
    _state.loadFavorites();
    _state.loadWrongQuestions();
    _state.loadStudyRecords();
    _state.loadWordBook();
    _state.loadRecordedWords();
    _state.loadRecordsSelected();
    _state.loadAnsweredBankIndices();
    if (mounted) setState(() => _ready = true);
    // 初始化帧率
    _updateFrameRate();
  }

  void _onState() {
    if (!mounted) return;
    if (_state.darkMode != _lastDarkMode) {
      _lastDarkMode = _state.darkMode;
    }
    // 全屏切换：仅在状态变化时应用，并延迟到当前帧渲染完成之后，
    // 避免启动首帧或设置对话框打开时与窗口全屏切换冲突导致白屏/卡死
    if (_state.fullscreen != _lastFullscreen) {
      _lastFullscreen = _state.fullscreen;
      if (_isWindows) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          windowManager.setFullScreen(_state.fullscreen).catchError((_) {});
        });
      }
    }
    // 根据省电模式调整帧率
    _updateFrameRate();
    // 离开浏览器页后重置临时导航栏状态
    if (_state.page != 19 && _showBrowserNav) {
      _showBrowserNav = false;
      _browserNavTimer?.cancel();
    }
    setState(() {});
  }

  static const _frameRateChannel = MethodChannel('com.smartenglish/framerate');

  void _updateFrameRate() {
    // 省电模式锁60帧；高性能模式不锁帧（解锁），其余锁定120帧
    final targetFps = _state.powerSavingMode ? 60 : 120;
    if (!_isWindows) {
      _frameRateChannel.invokeMethod('setFrameRate', {'fps': targetFps});
    }
  }

  @override
  void dispose() {
    _browserNavTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
        title: 'AFloat',
        debugShowCheckedModeBanner: false,
        navigatorKey: _rootNavKey,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: _state.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: Builder(builder: (context) {
          final c = AppColors.of(context);
          // 全局玻璃背景层（渐变 + 3 光斑）覆盖加载页/引导页/桌面/手机全部分支
          return Stack(children: [
            Positioned.fill(child: RepaintBoundary(child: _AppGlassBackground(colors: c, isGlass: _state.isGlassUI))),
            Positioned.fill(
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
                    _state.toggleFullscreen(!_state.fullscreen);
                    return KeyEventResult.handled;
                  }
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f8) {
                    _switchUiMode(_state.uiMode == 'mobile' ? 'desktop' : 'mobile');
                    return KeyEventResult.handled;
                  }
                  // F7：直接加载 mock 试卷进入考场预览（不调用 AI）
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f7) {
                    _state.loadMockExam();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: !_ready
                    ? Scaffold(
                        body: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3)),
                            const SizedBox(height: 14),
                            Text('正在加载...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                          ]),
                        ),
                      )
                    : !_state.onboardingDone
                        ? OnboardingPage(state: _state)
                        : _state.uiMode.isEmpty
                            ? PlatformSelectPage(
                                onDesktop: () => _switchUiMode('desktop'),
                                onMobile: () => _switchUiMode('mobile'),
                              )
                            : _state.uiMode == 'desktop'
                                ? KeyedSubtree(
                                    key: const ValueKey('english_desktop'),
                                    child: Scaffold(
                                    body: (_state.page == 10 || _state.page == 11 || _state.page == 20)
                                        ? ListenableBuilder(listenable: _state, builder: (ctx, _) => _buildMainContent())
                                        : Row(children: [
                                            _buildSidebar(),
                                            Expanded(child: ListenableBuilder(listenable: _state, builder: (ctx, _) => _buildMainContent())),
                                          ]),
                                    ),
                                  )
                                : KeyedSubtree(
                                    key: const ValueKey('english_mobile'),
                                    child: _buildMobileLayout(),
                                  ),
              ),
            ),
            // 开发者模式：全局开发者控制台（右下角入口 + 全屏日志浮层），
            // 覆盖答题/翻译题、单词查询、词汇剖析、考场等所有页面
            if (_state.devMode)
              Positioned.fill(child: DevConsoleEntry(state: _state)),
          ]);
        }),
      )),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    // 固定 seed 色（紫色主题）
    const seedColor = Color(0xFF7C3AED);
    final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
    final isLight = brightness == Brightness.light;
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI']);
    return base.copyWith(
      // scaffold 透明：由根部全局玻璃背景层（渐变 + 光斑）承接底色
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkRipple.splashFactory,
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.glassCardColor(isLight),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.glassBorderColor(isLight)),
        ),
      ),
      // dialog 保持不透明（浮在黑色 scrim 上，不玻璃化）
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? Colors.white : kDarkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? Color.alphaBlend(seedColor.withValues(alpha: 0.05), Colors.white) : kDarkCardAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: seedColor, width: 1.5),
        ),
        labelStyle: TextStyle(color: isLight ? Colors.grey.shade600 : kDarkTextSecondary),
        hintStyle: TextStyle(fontSize: 13, color: isLight ? const Color(0xFF9CA3AF) : const Color(0xFF6B6B85)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seedColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seedColor,
          side: BorderSide(color: seedColor.withValues(alpha: isLight ? 0.2 : 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: seedColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: isLight ? Colors.grey.shade600 : kDarkTextSecondary,
        ),
      ),
      iconTheme: IconThemeData(color: isLight ? Colors.grey.shade600 : kDarkTextSecondary),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide(color: isLight ? seedColor.withValues(alpha: 0.1) : Colors.white24)),
          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12.5)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          visualDensity: VisualDensity.compact,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? const Color(0xFF1F2937) : kDarkCardAlt,
        contentTextStyle: TextStyle(color: isLight ? Colors.white : kDarkText, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: isLight ? const Color(0x0D000000) : Colors.white12, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: isLight ? Colors.grey.shade600 : kDarkTextSecondary,
        textColor: isLight ? const Color(0xFF1A1A2E) : kDarkText,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return seedColor;
          return Colors.transparent;
        }),
        side: BorderSide(color: isLight ? const Color(0xFFCBD5E1) : const Color(0xFF5A5A7A), width: 1.5),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: isLight ? const Color(0xE6262B3A) : const Color(0xE6E8EAEF), borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(fontSize: 12, color: isLight ? Colors.white : Colors.black87),
        waitDuration: const Duration(milliseconds: 400),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: isLight ? const Color(0xFF1A1A2E) : kDarkText,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.glassSidebarColor(isLight),
        indicatorColor: seedColor.withValues(alpha: isLight ? 0.12 : 0.3),
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(fontSize: 11, color: isLight ? Colors.grey.shade600 : kDarkTextSecondary, fontWeight: FontWeight.w500),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: seedColor, size: 22);
          }
          return IconThemeData(color: isLight ? Colors.grey.shade500 : kDarkTextTertiary, size: 22);
        }),
      ),
    );
  }

  // ===== 左侧导航栏 =====
  Widget _buildSidebar() {
    // 独立监听 _state，确保每次 setPage 后导航指示器都可靠重建，
    // 避免从「更多功能」子页（如墨墨词库）出题跳转后高亮残留。
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final c = AppColors.of(context);
        final page = _state.page;
      const mainItems = [
        (Icons.home_outlined, '学习', 0),
        (Icons.help_outline, '答题', 1),
        (Icons.bar_chart_rounded, '学习报告', 2),
        (Icons.search_outlined, '查询', 3),
      ];
      final inMore = page >= 4;
      final inSubFeature = page >= 4 && (page <= 8 || (page >= 12 && page <= 17) || page == 18 || page == 19 || page == 20 || page == 21 || page == 22 || page == 23 || page == 24);
      const moreTitle = '更多功能';
      const moreIcon = Icons.grid_view_outlined;
      final isGlass = _state.isGlassUI;
      return RepaintBoundary(
        child: isGlass
          ? ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  width: 200,
                  decoration: BoxDecoration(
                    color: c.sidebar.withValues(alpha: _state.darkMode ? 0.5 : 0.55),
                    border: Border(right: BorderSide(color: c.divider)),
                  ),
                  child: _buildSidebarContent(c, page, mainItems, inMore, inSubFeature, moreTitle, moreIcon, context),
                ),
              ),
            )
          : Container(
        width: 200,
        decoration: BoxDecoration(
          color: c.sidebar,
          border: Border(right: BorderSide(color: c.divider)),
        ),
        child: _buildSidebarContent(c, page, mainItems, inMore, inSubFeature, moreTitle, moreIcon, context),
      ),
      );
      },
    );
  }

  Widget _buildSidebarContent(AppColors c, int page, List mainItems, bool inMore, bool inSubFeature, String moreTitle, IconData moreIcon, BuildContext context) {
    final isGlass = _state.isGlassUI;
    return Column(children: [
          const SizedBox(height: 24),
          // 主题胶囊（经典 / 毛玻璃 / 深色，滑块跟随所选）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildThemeCapsule(c),
          ),
          const SizedBox(height: 28),
          // 主导航项
          for (final item in mainItems)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Tooltip(
                message: item.$2,
                child: _NavPressFeedback(
                  onTap: () => _state.setPage(item.$3),
                  child: _SidebarNavPill(
                    selected: page == item.$3,
                    icon: item.$1,
                    label: item.$2,
                    showChevron: false,
                    indicator: _state.navIndicator,
                  ),
                ),
              ),
            ),
          // 更多功能按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Tooltip(
              message: '更多功能',
              child: _NavPressFeedback(
                onTap: () => _state.setPage(_morePageIndex),
                child: _SidebarNavPill(
                  selected: inMore,
                  icon: moreIcon,
                  label: moreTitle,
                  showChevron: true,
                  indicator: _state.navIndicator,
                ),
              ),
            ),
          ),
          const Spacer(),
          // 设置按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: InkWell(
              onTap: () => showDialog(context: context, builder: (_) => const SettingsDialog()),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Icon(Icons.settings_outlined, size: 20, color: c.textTertiary),
                  const SizedBox(width: 12),
                  Text('设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.textSecondary)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
    ]);
  }

  /// 侧边栏顶部主题胶囊：经典 / 毛玻璃 / 深色 三选一，滑块滑到所选主题。
  Widget _buildThemeCapsule(AppColors c) {
    const themes = [
      ('classic', '经典', Icons.light_mode_outlined),
      ('glass', '毛玻璃', Icons.blur_on_outlined),
      ('dark', '深色', Icons.dark_mode_outlined),
    ];
    // 当前激活的主题 key
    final active = _state.darkMode ? 'dark' : _state.uiStyle;
    final activeIndex = themes.indexWhere((t) => t.$1 == active);
    final idx = activeIndex < 0 ? 0 : activeIndex;
    return LayoutBuilder(builder: (context, box) {
      // 滑块宽度 = (总宽 - 两侧内边距) / 3，位置随 idx 平移
      const pad = 4.0;
      final segW = (box.maxWidth - pad * 2) / 3;
      return Container(
        height: 40,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: c.inputFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.border),
        ),
        child: Stack(children: [
          // 滑块
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: segW * idx,
            top: 0,
            bottom: 0,
            width: segW,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: _state.darkMode ? c.primaryBgStrong : Colors.white,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
          // 三个主题选项
          Row(
            children: [
              for (final t in themes)
                Expanded(
                  child: Tooltip(
                    message: t.$2,
                    child: InkWell(
                      onTap: () => _state.setThemeStyle(t.$1),
                      borderRadius: BorderRadius.circular(999),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(t.$3, size: 14, color: themes[idx].$1 == t.$1 ? c.primaryText : c.textTertiary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                t.$2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: themes[idx].$1 == t.$1 ? FontWeight.w600 : FontWeight.w400,
                                  color: themes[idx].$1 == t.$1 ? c.primaryText : c.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ]),
      );
    });
  }

  // ===== 主内容区 =====
  Widget _buildMainContent() {
    final isGlass = _state.isGlassUI;
    final c = AppColors(!_state.darkMode);
    // 考场/游戏沉浸模式（page==10/11/20）：隐藏 AI 对话栏（右侧30%），内容独占
    if (_state.page == 10 || _state.page == 11 || _state.page == 20) {
      return Row(children: [
        Expanded(child: _buildPage()),
      ]);
    }
    return Row(children: [
      // 中间内容区（70%）
      Expanded(
        flex: 7,
        child: isGlass
          ? ClipRect(child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: c.bg.withValues(alpha: _state.darkMode ? 0.45 : 0.5),
                ),
                child: _buildPage(),
              ),
            ))
          : _buildPage(),
      ),
      // 右侧 AI 对话助手（30%）— 监听 darkMode + chatUpdate，避免流式输出时全应用重建
      Expanded(
        flex: 3,
        child: ListenableBuilder(
          listenable: _state,
          builder: (ctx, _) => ListenableBuilder(
            listenable: _state.chatUpdateNotifier,
            builder: (ctx, _) => _buildChatPanel(),
          ),
        ),
      ),
    ]);
  }

  // ===== 手机端布局 =====
  Widget _buildMobileLayout() {
    return ListenableBuilder(
      listenable: _state,
      builder: (ctx, _) {
        final c = AppColors.of(ctx);
        // 考场/游戏沉浸模式（page==10/11/20）：手机端同样全屏化，隐藏顶栏/底部导航/AI 悬浮球
        final examMode = _state.page == 10 || _state.page == 11 || _state.page == 20;
        // 浏览器沉浸模式（page==19）：隐藏顶栏/底部导航/AI 悬浮球，底部上滑唤出导航栏
        final browserMode = _state.page == 19;
        final immersiveMode = examMode || browserMode;
        // 主导航：0学习 1答题 2报告 3更多(触发) 4查询
        const navItems = [
          (Icons.home_outlined, '学习', 0),
          (Icons.help_outline, '答题', 1),
          (Icons.analytics_outlined, '报告', 2),
          (Icons.grid_view_outlined, '更多', -1),
          (Icons.search_outlined, '查询', 3),
        ];
        final inMore = _state.page >= 4;
        final navIndex = inMore ? 3 : (_state.page == 3 ? 4 : _state.page.clamp(0, 2));
        final isGlass = _state.isGlassUI;
        final glassBg = isGlass ? c.sidebar.withValues(alpha: _state.darkMode ? 0.5 : 0.55) : c.sidebar;
        return Scaffold(
          // 透明：让全局玻璃背景层透出；高性能模式改用不透明底色，减少合成开销
          backgroundColor: _state.highPerformanceMode ? c.bg : Colors.transparent,
          appBar: immersiveMode
              ? null
              : AppBar(
            backgroundColor: glassBg,
            elevation: 0,
            title: Row(children: [
              const SizedBox(width: 0),
            ]),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 20),
                onPressed: () => showDialog(context: ctx, builder: (_) => const SettingsDialog()),
              ),
            ],
          ),
          body: Stack(children: [
            Positioned.fill(
              child: isGlass
                ? ClipRect(child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.bg.withValues(alpha: _state.darkMode ? 0.4 : 0.45),
                      ),
                      child: _buildPage(),
                    ),
                  ))
                : _buildPage(),
            ),
            // 浏览器沉浸模式下，底部上滑区域唤出导航栏
            if (browserMode && !_showBrowserNav)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 28,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (details) {
                    if (details.primaryDelta != null && details.primaryDelta! < -8) {
                      setState(() {
                        _showBrowserNav = true;
                        _browserNavTimer?.cancel();
                        _browserNavTimer = Timer(const Duration(seconds: 3), () {
                          if (mounted) setState(() => _showBrowserNav = false);
                        });
                      });
                    }
                  },
                  onTap: () => setState(() {
                    _showBrowserNav = true;
                    _browserNavTimer?.cancel();
                    _browserNavTimer = Timer(const Duration(seconds: 3), () {
                      if (mounted) setState(() => _showBrowserNav = false);
                    });
                  }),
                  child: Container(color: Colors.transparent),
                ),
              ),
          ]),
          bottomNavigationBar: immersiveMode
              ? (browserMode && _showBrowserNav ? NavigationBar(
            selectedIndex: navIndex,
            onDestinationSelected: (i) {
              if (navItems[i].$3 == -1) {
                _state.setPage(_morePageIndex);
              } else {
                _state.setPage(navItems[i].$3);
              }
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            backgroundColor: glassBg,
            indicatorColor: kPrimary.withValues(alpha: c.isLight ? 0.12 : 0.3),
            destinations: [
              for (var i = 0; i < navItems.length; i++)
                NavigationDestination(
                  icon: Icon(navItems[i].$1, size: 22, color: (i == 3 ? inMore : navIndex == i) ? kPrimary : c.textTertiary),
                  selectedIcon: Icon(navItems[i].$1, size: 22, color: kPrimary),
                  label: navItems[i].$2,
                ),
            ],
          ) : null)
              : NavigationBar(
            selectedIndex: navIndex,
            onDestinationSelected: (i) {
              if (navItems[i].$3 == -1) {
                _state.setPage(_morePageIndex);
              } else {
                _state.setPage(navItems[i].$3);
              }
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            backgroundColor: glassBg,
            indicatorColor: kPrimary.withValues(alpha: c.isLight ? 0.12 : 0.3),
            destinations: [
              for (var i = 0; i < navItems.length; i++)
                NavigationDestination(
                  icon: Icon(navItems[i].$1, size: 22, color: (i == 3 ? inMore : navIndex == i) ? kPrimary : c.textTertiary),
                  selectedIcon: Icon(navItems[i].$1, size: 22, color: kPrimary),
                  label: navItems[i].$2,
                ),
            ],
          ),
          floatingActionButton: immersiveMode
              ? null
              : _state.highPerformanceMode
                  // 高性能模式：不使用毛玻璃模糊，改用实色悬浮按钮
                  ? FloatingActionButton(
                      onPressed: () => _showMobileChatSheet(ctx),
                      backgroundColor: _state.darkMode ? const Color(0xFF2B2B32) : Colors.white,
                      elevation: 2,
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C3AED), size: 24),
                    )
                  : GlassFab(
                      isLight: !_state.darkMode,
                      onPressed: () => _showMobileChatSheet(ctx),
                      icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7C3AED), size: 24),
                    ),
        );
      },
    );
  }

  // ===== 手机端更多功能底部弹出面板 =====（已改为独立页面 _MoreSelectPage）

  void _showMobileChatSheet(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭对话助手',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final tween = Tween(begin: const Offset(1, 0), end: Offset.zero);
        return SlideTransition(
          position: tween.animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) {
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.92,
            child: _buildMobileChatContent(context),
          ),
        );
      },
    );
  }

  Widget _buildMobileChatContent(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (ctx, _) {
        final c = AppColors.of(ctx);
        final cfg = _state.effectiveChatConfig;
        final modelName = cfg.ready ? cfg.model : '未配置';
        // 浮在 black54 barrier 上：用主题背景渐变实底，不透明
        return Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c.appBgGradientTop, c.appBgGradientBottom]),
            ),
            child: SafeArea(
            child: Column(children: [
              // 头部
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: c.primaryGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(modelName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.settings_outlined, size: 18, color: c.textTertiary),
                    tooltip: '对话设置',
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      showDialog(context: context, builder: (_) => const SettingsDialog());
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, size: 20, color: c.textTertiary),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ]),
              ),
              Divider(height: 1, color: c.divider),
              // 消息列表
              Expanded(
                child: ListenableBuilder(
                  listenable: _state.chatUpdateNotifier,
                  builder: (ctx, _) {
                    final s = _state;
                    final cfg = s.effectiveChatConfig;
                    final localAiIconAsset = _getAiIconAsset(cfg.ready ? cfg.model : '');
                    if (s.chatHistory.isEmpty) {
                      if (!cfg.ready) {
                        return _buildApiConfigPrompt(ctx, c.isLight);
                      }
                      final levelName = s.selectedLevel.isEmpty ? '高中' : s.selectedLevel;
                      final typeName = s.selectedType.isEmpty ? '综合' : s.selectedType;
                      return _buildChatWelcome(c.isLight, cfg.model, levelName, typeName, localAiIconAsset);
                    }
                    final scrollCtrl = ScrollController();
                    // R6: 手机端滚动同样节流
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (scrollCtrl.hasClients) {
                        final pos = scrollCtrl.position;
                        final distFromBottom = pos.maxScrollExtent - pos.pixels;
                        if (distFromBottom <= 150) {
                          final now = DateTime.now().millisecondsSinceEpoch;
                          if (now - _lastScrollTime >= 300) {
                            _lastScrollTime = now;
                            scrollCtrl.animateTo(
                              pos.maxScrollExtent,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                            );
                          }
                        }
                      }
                    });
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: s.chatHistory.length + (s.chatSending ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i < s.chatHistory.length) {
                          final isTail = s.chatSending && i == s.chatHistory.length - 1 && s.chatHistory[i].role == 'ai';
                          return _buildChatBubble(s.chatHistory[i], c.isLight, running: isTail);
                        }
                        return AgentDeepDivingRow(accent: c.primary, light: c.isLight);
                      },
                    );
                  },
                ),
              ),
              // 上下文用量
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  _buildContextUsagePill(ctx, c, _state),
                ]),
              ),
              // 输入框
              Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, MediaQuery.of(ctx).padding.bottom + 8),
                child: _buildChatInputBar(ctx, c, _state, isMobile: true),
              ),
            ]),
          ),
          ),
        );
      },
    );
  }

  Widget _buildPage() {
    switch (_state.page) {
      case 0:
        return LearnPage(state: _state);
      case 1:
        return _PageScaffold(title: '答题', child: ListenableBuilder(listenable: _state, builder: (ctx, _) => AnswerPage(state: _state)));
      case 2:
        return const ReportPage();
      case 3:
        return const DictionaryPage();
      case 4:
        return _PageScaffold(title: '题库', child: QuestionListPanel());
      case 5:
        return const WrongBookPage();
      case 6:
        return const WordBookPage();
      case 7:
        return const RecordsPage();
      case 8:
        return const DictationPage();
      case 12:
        return const _PageScaffold(title: '语法学习', child: GrammarPage());
      case 18:
        return const _PageScaffold(title: '墨墨词库', child: MaimemoWordbookPage());
      case 19:
        // 浏览器沉浸模式：不套 _PageScaffold，页面自身就是完整浏览器界面
        return const BrowserPage();
      case 20:
        return const SnakeGamePage();
      case 24:
        return const SnakePvpPage();
      case 21:
        return const SourceViewerPage();
      case 23:
        return const _PageScaffold(title: '五子棋', child: GomokuPage());
      case 10:
      case 11:
        // 沉浸考场或成绩解析页（外层已隐藏 AI 对话栏）
        return const ExamShell();
      case _morePageIndex:
        return _MoreSelectPage(currentIndex: _state.page, onSelect: (idx) => _state.setPage(idx));
      default:
        return const SizedBox();
    }
  }

  // ===== AI 图标识别 =====
  /// 根据模型名称返回对应的图标 asset 路径
  /// 兜底：所有未识别模型返回默认 MiniMax.svg，不再返回 null
  String? _getAiIconAsset(String modelName) {
    final lower = modelName.toLowerCase();
    // 按优先级匹配，越具体的越靠前
    if (lower.contains('gpt-4') || lower.contains('gpt-3.5') || lower.contains('openai')) return 'assets/ai-icons/openai.svg';
    if (lower.contains('claude') || lower.contains('anthropic')) return 'assets/ai-icons/claude.svg';
    if (lower.contains('glm') || lower.contains('chatglm') || lower.contains('zhipu') || lower.contains('智谱')) return 'assets/ai-icons/chatglm.svg';
    if (lower.contains('qwen') || lower.contains('千问') || lower.contains('通义') || lower.contains('qwq') || lower.contains('qvq')) return 'assets/ai-icons/qwen.svg';
    if (lower.contains('deepseek') || lower.contains('deep-seek')) return 'assets/ai-icons/deepseek.svg';
    if (lower.contains('gemini') || lower.contains('google')) return 'assets/ai-icons/gemini.svg';
    if (lower.contains('doubao') || lower.contains('豆包') || lower.contains('seed-' )) return 'assets/ai-icons/doubao.svg';
    // MiniMax / hy（参考图中 hy3 用 MiniMax logo）
    if (lower.contains('minimax') || lower.contains('hy') || lower.contains('hy3')) return 'assets/ai-icons/minimax.svg';
    if (lower.contains('step') || lower.contains('阶跃') || lower.contains('stepfun')) return 'assets/ai-icons/stepfun.svg';
    if (lower.contains('kimi') || lower.contains('moonshot')) return 'assets/ai-icons/kimi.svg';
    if (lower.contains('baichuan') || lower.contains('百川')) return 'assets/ai-icons/baichuan.svg';
    if (lower.contains('yi-') || lower.contains('零一') || lower.contains('yi_lite') || lower.contains('yi-large')) return 'assets/ai-icons/yi.svg';
    if (lower.contains('spark') || lower.contains('星火') || lower.contains('xunfei') || lower.contains('讯飞')) return 'assets/ai-icons/spark.svg';
    if (lower.contains('wenxin') || lower.contains('文心') || lower.contains('ernie')) return 'assets/ai-icons/wenxin.svg';
    if (lower.contains('hunyuan') || lower.contains('混元') || lower.contains('tencent')) return 'assets/ai-icons/hunyuan.svg';
    if (lower.contains('mistral') || lower.contains('mixtral')) return 'assets/ai-icons/mistral.svg';
    if (lower.contains('llama') || lower.contains('meta-')) return 'assets/ai-icons/llama.svg';
    if (lower.contains('grok') || lower.contains('xai')) return 'assets/ai-icons/grok.svg';
    if (lower.contains('cohere') || lower.contains('command-r')) return 'assets/ai-icons/cohere.svg';
    if (lower.contains('perplexity') || lower.contains('sonar')) return 'assets/ai-icons/perplexity.svg';
    if (lower.contains('together') || lower.contains('Llama-3') || lower.contains('Qwen2-')) return 'assets/ai-icons/together.svg';
    // LongCat / 龙猫（美团）专用图标
    if (lower.contains('longcat') || lower.contains('long-cat') || lower.contains('龙猫') || lower.contains('美团')) return 'assets/ai-icons/longcat.svg';
    if (lower.contains('taichu') || lower.contains('太初')) return 'assets/ai-icons/zhipu.svg';
    // 兜底：任何未匹配都给一个通用 MiniMax 图标，不再返回 null
    return 'assets/ai-icons/minimax.svg';
  }

  /// AI 模型品牌色（渐变首色→尾色），让每个模型 logo 都有辨识度的彩色圆底
  (Color, Color) _aiBrandColors(String model) {
    final lower = model.toLowerCase();
    const def = (Color(0xFF7C3AED), Color(0xFFA78BFA)); // 默认紫
    if (lower.contains('hy') || lower.contains('minimax')) {
      return (const Color(0xFF00C3FF), const Color(0xFF00E0A8)); // MiniMax 青
    }
    if (lower.contains('glm') || lower.contains('zhipu') || lower.contains('chatglm')) {
      return (const Color(0xFF3B82F6), const Color(0xFF22D3EE)); // 智谱 GLM 蓝绿
    }
    if (lower.contains('qwen') || lower.contains('千问')) {
      return (const Color(0xFF6366F1), const Color(0xFF8B5CF6)); // 通义 紫
    }
    if (lower.contains('deepseek')) {
      return (const Color(0xFF4D6BFE), const Color(0xFF8B5CF6)); // DeepSeek 蓝紫
    }
    if (lower.contains('kimi') || lower.contains('moonshot')) {
      return (const Color(0xFFF59E0B), const Color(0xFFF97316)); // Kimi 橙
    }
    if (lower.contains('gemini') || lower.contains('google')) {
      return (const Color(0xFF4285F4), const Color(0xFF9B72CB)); // Gemini 蓝紫
    }
    if (lower.contains('doubao') || lower.contains('豆包')) {
      return (const Color(0xFF2563EB), const Color(0xFF60A5FA)); // 豆包 蓝
    }
    if (lower.contains('gpt') || lower.contains('openai')) {
      return (const Color(0xFF10A37F), const Color(0xFF34D399)); // OpenAI 绿
    }
    if (lower.contains('step') || lower.contains('阶跃')) {
      return (const Color(0xFFFF7A00), const Color(0xFFFFA63E)); // 阶跃 橙
    }
    if (lower.contains('baichuan') || lower.contains('百川')) {
      return (const Color(0xFFEF4444), const Color(0xFFF97316)); // 百川 红橙
    }
    if (lower.contains('yi') || lower.contains('零一')) {
      return (const Color(0xFF06B6D4), const Color(0xFF22D3EE)); // 零一 cyan
    }
    if (lower.contains('spark') || lower.contains('星火') || lower.contains('讯飞')) {
      return (const Color(0xFF1F7AEF), const Color(0xFF60A5FA)); // 星火 蓝
    }
    if (lower.contains('wenxin') || lower.contains('文心') || lower.contains('ernie')) {
      return (const Color(0xFF3B82F6), const Color(0xFF93C5FD)); // 文心 蓝
    }
    if (lower.contains('hunyuan') || lower.contains('混元') || lower.contains('tencent')) {
      return (const Color(0xFF0284C7), const Color(0xFF38BDF8)); // 混元 蓝
    }
    if (lower.contains('mistral') || lower.contains('mixtral')) {
      return (const Color(0xFFF97316), const Color(0xFFFBBF24)); // Mistral 橙黄
    }
    if (lower.contains('llama') || lower.contains('meta')) {
      return (const Color(0xFFDC2626), const Color(0xFFF87171)); // Llama 红
    }
    if (lower.contains('grok') || lower.contains('xai')) {
      return (const Color(0xFF374151), const Color(0xFF6B7280)); // Grok 深灰
    }
    if (lower.contains('cohere')) {
      return (const Color(0xFF2563EB), const Color(0xFF60A5FA)); // Cohere 蓝
    }
    if (lower.contains('perplexity') || lower.contains('sonar')) {
      return (const Color(0xFF0F766E), const Color(0xFF14B8A6)); // Perplexity teal
    }
    if (lower.contains('together')) {
      return (const Color(0xFF7C3AED), const Color(0xFFC084FC)); // Together 紫
    }
    if (lower.contains('longcat')) {
      return (const Color(0xFF3B82F6), const Color(0xFF60A5FA)); // LongCat 蓝
    }
    if (lower.contains('taichu') || lower.contains('太初')) {
      return (const Color(0xFF6366F1), const Color(0xFF8B5CF6)); // 太初 紫
    }
    return def;
  }

  /// 渲染 AI 模型 logo：不要渐变圆底图层，只渲染图标本体。
  /// SVG 是 currentColor 单色，直接用品牌色渲染；dark 模式下与白色 lerp 35% 提亮保证可见。
  Widget _aiLogo(String model, {double size = 30}) {
    final asset = _getAiIconAsset(model);
    final (c1, _) = _aiBrandColors(model);
    final brand = _state.darkMode ? Color.lerp(c1, Colors.white, 0.35)! : c1;
    return asset != null
        ? SvgPicture.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            color: brand,
          )
        : Icon(Icons.smart_toy_outlined, size: size * 0.8, color: brand);
  }

  // ===== 右侧 AI 对话助手面板 =====
  Widget _buildChatPanel() {
    final s = _state;
    // 注意：不能用 AppColors.of(context)，因为 this.context 在 MaterialApp 上方，
    // Theme.of(context).brightness 会返回默认的 light 模式，导致深色模式下颜色全白。
    // 改用 _state.darkMode 直接判断。
    final c = AppColors(!_state.darkMode);
    final cfg = s.effectiveChatConfig;
    final modelName = cfg.ready ? cfg.model : '未配置';
    final levelName = {'cet4': '四级', 'zsb': '专升本', 'easy': '简单', 'medium': '中等', 'hard': '困难'}[s.selectedLevel] ?? s.selectedLevel;
    final typeName = {'translation': '翻译题', 'reading': '阅读理解', 'grammar': '语法填空', 'choice': '选择题', 'writing': '写作题', 'mixed': '综合套卷'}[s.selectedType] ?? s.selectedType;
    final aiIconAsset = _getAiIconAsset(modelName);
    final isGlass = s.isGlassUI;
    // RepaintBoundary：聊天面板处于流式重建区，隔离重绘
    return RepaintBoundary(
      child: DropTarget(
      onDragDone: (details) => _setChatImageFromFiles(details.files),
      child: isGlass
        ? ClipRect(child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: c.sidebar.withValues(alpha: s.darkMode ? 0.4 : 0.45),
                border: Border(left: BorderSide(color: c.divider)),
              ),
              child: Builder(builder: (panelCtx) => _buildChatPanelContent(panelCtx, c, s, cfg, modelName, levelName, typeName, aiIconAsset)),
            ),
          ))
        : Container(
        decoration: BoxDecoration(
          // 透明：让全局玻璃背景层透出
          color: Colors.transparent,
          border: Border(left: BorderSide(color: c.divider)),
        ),
        child: Builder(builder: (panelCtx) => _buildChatPanelContent(panelCtx, c, s, cfg, modelName, levelName, typeName, aiIconAsset)),
      ),
      ),
    );
  }

  Widget _buildChatPanelContent(BuildContext ctx, AppColors c, AppState s, dynamic cfg, String modelName, String levelName, String typeName, String? aiIconAsset) {
    return Column(children: [
          // 头部（AI 头像 + 标题 + 操作按钮）— 透明背景 + 底部分割线
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(bottom: BorderSide(color: c.divider)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _aiLogo(modelName, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(modelName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Builder(builder: (wsCtx) => IconButton(
                key: _workspaceBtnKey,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(
                  s.workspacePath.isEmpty ? Icons.folder_open_outlined : Icons.folder_rounded,
                  size: 18,
                  color: s.workspacePath.isEmpty ? c.textTertiary : const Color(0xFF10B981),
                ),
                tooltip: s.workspacePath.isEmpty
                    ? '工作区：默认（C:\\Users 下所有位置）'
                    : '工作区：${s.workspacePath}',
                onPressed: () {
                  debugPrint('[workspace] tap -> _showWorkspacePicker');
                  _showWorkspacePicker(wsCtx, c, s);
                },
              )),
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(Icons.refresh_rounded, size: 18, color: c.textTertiary),
                tooltip: '清空对话',
                onPressed: () => s.clearChat(),
              ),
              Builder(builder: (btnCtx) => IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(Icons.tune_rounded, size: 18, color: c.textTertiary),
                tooltip: '对话设置',
                onPressed: () => showDialog(context: btnCtx, builder: (_) => const SettingsDialog()),
              )),
            ]),
          ),
        // 上下文用量
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            _buildContextUsagePill(ctx, c, s, anchorKey: _contextPillKey),
          ]),
        ),
        const SizedBox(height: 8),
        // 消息列表
        Expanded(
          child: s.chatHistory.isEmpty
              ? (cfg.ready
                  ? _buildChatWelcome(c.isLight, modelName, levelName, typeName, aiIconAsset)
                  : _buildApiConfigPrompt(ctx, c.isLight))
              : ValueListenableBuilder<int>(
                  valueListenable: s.chatUpdateNotifier,
                  builder: (ctx, _, __) {
                    // 流式输出时自动滚动到底部
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollChatToBottom());
                    return ListView.builder(
                      controller: _chatScrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: s.chatHistory.length + (s.chatSending ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i < s.chatHistory.length) {
                          final isTail = s.chatSending && i == s.chatHistory.length - 1 && s.chatHistory[i].role == 'ai';
                          return _buildChatBubble(s.chatHistory[i], c.isLight, running: isTail);
                        }
                        return AgentDeepDivingRow(accent: c.primary, light: c.isLight);
                      },
                    );
                  },
                ),
        ),
        // 快捷问题（已移除，减少占位）
        if (s.chatHistory.isEmpty) ...[
          const SizedBox(height: 4),
        ],
        // 输入框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
          child: _buildChatInputBar(ctx, c, s),
        ),
      ],
    );
  }

  Widget _buildChatWelcome(bool isLight, String modelName, String levelName, String typeName, String? aiIconAsset) {
    final c = AppColors(isLight);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // AI 欢迎消息
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _aiLogo(modelName, size: 32),
          const SizedBox(width: 10),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.chatBubbleAi,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hi! 我是你的 AI 备考助手', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 6),
              Text('已自动关联题目，有问题可以随时问我', style: TextStyle(fontSize: 13, color: c.text, height: 1.5)),
            ]),
          )),
        ]),
        const SizedBox(height: 16),
      ],
    );
  }

  /// API 未配置时的引导气泡（整个气泡可点击，直接打开设置）
  Widget _buildApiConfigPrompt(BuildContext ctx, bool isLight) {
    final c = AppColors(isLight);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        GestureDetector(
          onTap: () {
            Navigator.of(ctx).pop();
            showDialog(context: ctx, builder: (_) => const SettingsDialog());
          },
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: c.isLight
                    ? null
                    : [
                        BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 1.5),
                        BoxShadow(color: const Color(0xFFA78BFA).withValues(alpha: 0.25), blurRadius: 18, spreadRadius: 3),
                      ],
              ),
              child: const Center(child: Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.chatBubbleAi,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.primary.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(Icons.settings_outlined, size: 16, color: c.primary),
                const SizedBox(width: 8),
                Text('请在设置内配置 API', style: TextStyle(fontSize: 13, color: c.primary, fontWeight: FontWeight.w600)),
              ]),
            )),
          ]),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildChatBubble(ChatMessage msg, bool isLight, {bool running = false}) {
    final c = AppColors(isLight);
    final isUser = msg.role == 'user';
    // AI 气泡上方的模型头像 + 名称（参考图风格）。Auto 模式下每条 AI 消息会用其所选 profile 的模型名。
    String? aiModelName;
    if (!isUser) {
      aiModelName = (msg.modelLabel != null && msg.modelLabel!.isNotEmpty)
          ? msg.modelLabel
          : _state.effectiveChatConfig.model;
    }
    final aiIconAsset = aiModelName == null ? null : _getAiIconAsset(aiModelName);
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: isUser ? null : c.chatBubbleAi,
        gradient: isUser ? c.primaryGradient : null,
        borderRadius: BorderRadius.circular(14),
        border: isUser ? null : Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 用户消息图片（模型无图形能力时显示错误提示）
          if (msg.imageData != null && msg.imageData!.isNotEmpty) ...[
            msg.imageDark
                ? Container(
                    width: 168,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.error_outline_rounded, size: 26, color: Colors.red),
                        SizedBox(height: 6),
                        Text('当前模型不支持图片', style: TextStyle(fontSize: 11, color: Colors.red)),
                      ]),
                    ),
                  )
                : RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(msg.imageBytes!, width: 168, height: 120, fit: BoxFit.cover),
                    ),
                  ),
            const SizedBox(height: 8),
          ],
          // 消息内容（支持 Markdown 渲染）
          if (msg.content.isNotEmpty)
            RichText(
              text: _parseMarkdown(msg.content, isUser ? Colors.white : c.text),
            )
          else if (msg.role == 'ai')
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primaryText)),
        ],
      ),
    );
    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }
    // Agent 过程步骤（思考行 / 工具行 / 终端块）放在气泡外、气泡上方，
    // 全宽无容器展示（仿 deepseek-harness：步骤不属于消息正文）。
    final hasReasoning = msg.reasoning != null && msg.reasoning!.isNotEmpty && msg.showReasoning;
    final hasSteps = msg.toolSteps.isNotEmpty;
    final avatarRow = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _aiLogo(aiModelName ?? '', size: 28),
      ),
      const SizedBox(width: 8),
      Expanded(child: bubble),
    ]);
    // AI 消息气泡上方的模型名行（与 Reasoning / ToolSteps 独立成行，避免压住头像）
    Widget? modelHeader;
    if (!isUser && aiModelName != null) {
      // 模型名小行：不再额外显示小头像（与下方 28 气泡头像重复），仅显示模型名
      modelHeader = Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          aiModelName!,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFADADB8),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      );
    }
    final hasStatus = running && !isUser && (msg.statusLabel ?? '').isNotEmpty;
    if (!hasReasoning && !hasSteps) {
      if (!hasStatus) {
        if (modelHeader == null) return avatarRow;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [modelHeader, avatarRow]);
      }
      // 仅有状态行（流式决策期间）：状态 + 模型名，不渲染空气泡
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (modelHeader != null) modelHeader,
        _statusRow(msg, isLight),
        avatarRow,
      ]);
    }
    // 内容尚未到达时（纯思考/工具阶段）不渲染空气泡
    final bool showBubble = msg.content.isNotEmpty || !running;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (modelHeader != null) modelHeader,
      // 运行状态行：流式决策期间告诉用户"现在到哪一步了"
      if (hasStatus) _statusRow(msg, isLight),
      if (hasReasoning) ...[
        AgentThinkRow(text: msg.reasoning!, running: running, light: isLight),
        const SizedBox(height: 2),
      ],
      if (msg.todoList.isNotEmpty) ...[
        AgentTodoList(items: msg.todoList, light: isLight),
        const SizedBox(height: 2),
      ],
      if (hasSteps)
        ...msg.toolSteps.map((ts) {
          if (ts.terminal) {
            return AgentTerminalBlock(
              command: ts.command ?? '',
              running: ts.running,
              failed: ts.failed,
              exitCode: ts.exitCode,
              output: ts.output,
              light: isLight,
            );
          }
          // 子 Agent 派发：专属卡片（类型徽章 + 执行轨迹 + 报告）
          if (ts.name == 'spawn_subagent') {
            return AgentSubagentCard(
              type: ts.subType ?? 'general',
              task: ts.subTask ?? '',
              label: ts.label,
              running: ts.running,
              done: ts.done,
              failed: ts.failed,
              events: ts.subEvents,
              output: ts.output,
              light: isLight,
            );
          }
          return AgentToolRow(
            name: ts.name,
            label: ts.label,
            running: ts.running,
            done: ts.done,
            failed: ts.failed,
            input: ts.input,
            output: ts.output,
            light: isLight,
          );
        }),
      if (hasSteps) const SizedBox(height: 2),
      // dsh-tool-ask-user：弹问题让用户选
      if (msg.askQuestions.isNotEmpty) ...[
        AgentAskUserPanel(questions: msg.askQuestions, answers: msg.askAnswers, msgRef: msg, light: isLight),
        const SizedBox(height: 4),
      ],
      // dsh-plan-mode：提交计划让用户审批
      if (msg.plan != null) ...[
        AgentPlanPanel(plan: msg.plan!, light: isLight),
        const SizedBox(height: 4),
      ],
      if (showBubble) avatarRow,
    ]);
  }

  /// 运行状态行（"思考下一步（第 2 轮）…"）：小转轮 + 一句话进度，
  /// 让用户在模型流式决策期间也知道 Agent 没卡死、进行到第几步。
  Widget _statusRow(ChatMessage msg, bool isLight) {
    final text = msg.statusLabel ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Row(children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: isLight ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: isLight ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF)),
          ),
        ),
      ]),
    );
  }

  /// R5: 简易 Markdown 解析：支持 **粗体**、*斜体*、~~删除线~~、`行内代码`、标题、列表、代码块、引用、链接
  /// 带缓存：相同内容+颜色组合直接返回缓存结果
  TextSpan _parseMarkdown(String text, Color textColor) {
    final cacheKey = text.hashCode * 31 + textColor.value;
    final cached = _markdownCache[cacheKey];
    if (cached != null) return cached;
    final result = _parseMarkdownImpl(text, textColor);
    // 限制缓存大小，防止无限增长
    if (_markdownCache.length > 200) _markdownCache.clear();
    _markdownCache[cacheKey] = result;
    return result;
  }

  TextSpan _parseMarkdownImpl(String text, Color textColor) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var inCodeBlock = false;
    final codeBuffer = <String>[];
    
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      // 代码块处理
      if (line.startsWith('```')) {
        if (inCodeBlock) {
          // 结束代码块 - 用 WidgetSpan 添加背景色
          spans.add(WidgetSpan(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                codeBuffer.join('\n'),
                style: const TextStyle(color: Color(0xFF7C3AED), fontFamily: 'Consolas', fontSize: 12.5, height: 1.4),
              ),
            ),
          ));
          codeBuffer.clear();
          inCodeBlock = false;
        } else {
          // 开始代码块
          inCodeBlock = true;
        }
        continue;
      }
      
      if (inCodeBlock) {
        codeBuffer.add(line);
        continue;
      }
      
      if (i > 0) spans.add(const TextSpan(text: '\n'));
      
      // 引用
      if (line.startsWith('> ')) {
        spans.add(const TextSpan(text: '│ ', style: TextStyle(fontSize: 13, color: Color(0xFF7C3AED))));
        _parseInlineSpans(line.substring(2), textColor.withValues(alpha: 0.85), spans);
        continue;
      }
      
      // 标题
      if (line.startsWith('### ')) {
        spans.add(TextSpan(text: line.substring(4), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)));
        continue;
      }
      if (line.startsWith('## ')) {
        spans.add(TextSpan(text: line.substring(3), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)));
        continue;
      }
      if (line.startsWith('# ')) {
        spans.add(TextSpan(text: line.substring(2), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: textColor)));
        continue;
      }
      // 无序列表
      if (line.startsWith('- ') || line.startsWith('* ')) {
        spans.add(const TextSpan(text: '• ', style: TextStyle(fontSize: 13, color: Color(0xFF7C3AED))));
        _parseInlineSpans(line.substring(2), textColor, spans);
        continue;
      }
      // 有序列表
      final orderedMatch = _reOrderedList.firstMatch(line);
      if (orderedMatch != null) {
        spans.add(TextSpan(text: '${orderedMatch.group(1)}. ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF7C3AED))));
        _parseInlineSpans(orderedMatch.group(2)!, textColor, spans);
        continue;
      }
      // 普通行
      _parseInlineSpans(line, textColor, spans);
    }
    return TextSpan(children: spans, style: TextStyle(fontSize: 13, height: 1.5));
  }

  void _parseInlineSpans(String text, Color textColor, List<InlineSpan> spans) {
    // R5: 使用 static final RegExp，避免每次新建
    final patterns = <RegExp>[
      _reStrikethrough,
      _reBold,
      _reItalic,
      _reInlineCode,
      _reLink,
    ];
    var remaining = text;
    while (remaining.isNotEmpty) {
      // 找到最早匹配的位置和类型
      int? earliestStart;
      int? earliestEnd;
      RegExpMatch? earliestMatch;
      RegExp? earliestPattern;
      for (final pattern in patterns) {
        final m = pattern.firstMatch(remaining);
        if (m != null && (earliestStart == null || m.start < earliestStart)) {
          earliestStart = m.start;
          earliestEnd = m.end;
          earliestMatch = m;
          earliestPattern = pattern;
        }
      }
      if (earliestMatch == null) {
        spans.add(TextSpan(text: remaining, style: TextStyle(color: textColor)));
        break;
      }
      // 匹配前的普通文本
      if (earliestStart! > 0) {
        spans.add(TextSpan(text: remaining.substring(0, earliestStart), style: TextStyle(color: textColor)));
      }
      if (earliestPattern == patterns[0]) {
        // 删除线
        spans.add(TextSpan(text: earliestMatch.group(1)!, style: TextStyle(color: textColor.withValues(alpha: 0.5), decoration: TextDecoration.lineThrough)));
      } else if (earliestPattern == patterns[1]) {
        // 粗体
        spans.add(TextSpan(text: earliestMatch.group(1)!, style: TextStyle(color: textColor, fontWeight: FontWeight.w700)));
      } else if (earliestPattern == patterns[2]) {
        // 斜体
        spans.add(TextSpan(text: earliestMatch.group(1)!, style: TextStyle(color: textColor, fontStyle: FontStyle.italic)));
      } else if (earliestPattern == patterns[3]) {
        // 行内代码
        spans.add(TextSpan(text: earliestMatch.group(1)!, style: TextStyle(color: const Color(0xFF7C3AED), fontFamily: 'Consolas', fontSize: 12.5)));
      } else {
        // 链接 [文字](url)
        spans.add(TextSpan(
          text: earliestMatch.group(1)!,
          style: TextStyle(color: const Color(0xFF7C3AED), decoration: TextDecoration.underline),
          recognizer: null,
        ));
      }
      remaining = remaining.substring(earliestEnd!);
    }
  }

  static const _clipboardChannel = MethodChannel('com.smartenglish/clipboard');

  /// 从剪贴板读取图片（Windows 平台）
  Future<Uint8List?> _pasteImageFromClipboard() async {
    try {
      final bytes = await _clipboardChannel.invokeMethod<Uint8List>('getImage');
      return bytes;
    } catch (_) {
      return null;
    }
  }

  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();
  /// 待发送的图片（base64 data URL）；null 表示未选择
  String? _chatImageData;
  /// 待发送的非图片附件文件名；null 表示未选择
  String? _chatAttachmentName;
  /// 待发送的文本文件内容（已读取的原始文本）；null 表示无文本附件
  String? _chatFileText;
  /// 本会话已附加过的文件名（供「引用对话中的文件」使用）
  final List<String> _conversationFiles = [];

  /// R6: 滚动节流：仅贴近底部且距上次滚动 >300ms 时才执行
  void _scrollChatToBottom() {
    if (!_chatScrollCtrl.hasClients) return;
    final pos = _chatScrollCtrl.position;
    final distFromBottom = pos.maxScrollExtent - pos.pixels;
    // 仅当距底部 <150px 时才自动滚动（用户已主动上滚则不打断）
    if (distFromBottom > 150) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScrollTime < 300) return;
    _lastScrollTime = now;
    _chatScrollCtrl.animateTo(
      pos.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// 根据扩展名返回 MIME 类型
  String _imageMime(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'gif':
        return 'gif';
      case 'webp':
        return 'webp';
      case 'bmp':
        return 'bmp';
      default:
        return 'png';
    }
  }

  /// 选择任意文件作为聊天附件：图片走 vision，文本文件读取内容注入，其余类型仅记文件名
  Future<void> _pickChatFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      final name = f.name;
      if (bytes == null || bytes.isEmpty) return;
      final lower = name.toLowerCase();
      final isImage = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].any((e) => lower.endsWith(e));
      if (isImage) {
        final dataUrl = 'data:image/${_imageMime(name)};base64,${base64Encode(bytes)}';
        setState(() {
          _chatImageData = dataUrl;
          _chatFileText = null;
        });
        return;
      }
      // 文本类文件：读取内容注入给 AI
      const textExts = ['.txt', '.md', '.json', '.dart', '.js', '.ts', '.jsx', '.tsx', '.html', '.htm', '.css', '.csv', '.xml', '.yml', '.yaml', '.log', '.py', '.java', '.c', '.cpp', '.h', '.sql'];
      if (textExts.any((e) => lower.endsWith(e))) {
        String text;
        try {
          text = utf8.decode(bytes);
        } catch (_) {
          text = latin1.decode(bytes);
        }
        setState(() {
          _chatAttachmentName = name;
          _chatFileText = text;
          _chatImageData = null;
        });
      } else {
        // 其他二进制文件（pdf/docx/zip 等）暂不支持解析，仅记文件名
        setState(() {
          _chatAttachmentName = name;
          _chatFileText = null;
          _chatImageData = null;
        });
        _showChatToast(context, '该文件类型暂不支持内容解析，将以附件名发送');
      }
    } catch (_) {
      // 选择失败忽略
    }
  }

  /// 判断当前上下文是否为小屏 / 紧凑布局
  bool _isCompact(BuildContext context) => MediaQuery.of(context).size.width < 640;

  /// 显示 + 菜单（添加文件 / 技能 / 连接器），统一为深色浮层；技能与连接器为子页
  void _showChatPlusMenu(BuildContext context, AppColors c, AppState s) {
    const textSecondary = Color(0xFFADADB8);
    const text = Color(0xFFE4E4E8);
    const textTertiary = Color(0xFF85859A);

    Widget skillIcon(ChatSkill skill) {
      final isActive = s.activeSkill == skill.id;
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF4C1D95).withValues(alpha: 0.25) : const Color(0xFF3D3D45),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(skill.icon, size: 16, color: isActive ? const Color(0xFFA78BFA) : const Color(0xFFADADB8)),
      );
    }

    late OverlayEntry entry;

    Widget buildHeader(String title, {required VoidCallback onBack}) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF3D3D45), width: 0.5))),
        child: Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.arrow_back_rounded, size: 18, color: textSecondary),
            onPressed: onBack,
          ),
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text)),
        ]),
      );
    }

    StatefulBuilder contentBuilder(BuildContext ctx, void Function(void Function()) setState) {
      var page = 'main'; // main / skills / connectors
      return StatefulBuilder(
        builder: (ctx, setSt) {
          Widget body;
          if (page == 'skills') {
            body = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildHeader('选择技能', onBack: () => setSt(() => page = 'main')),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      _darkMenuItem(
                        icon: const Icon(Icons.block_outlined, size: 20, color: textSecondary),
                        title: '无技能',
                        trailing: s.activeSkill.isEmpty
                            ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF10B981))
                            : const SizedBox(width: 18),
                        onTap: () {
                          s.setActiveSkill('');
                          entry.remove();
                          _showChatToast(context, '已清除技能');
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFF3D3D45)),
                      for (final skill in kAgentToolSkills)
                        _darkMenuItem(
                          icon: skillIcon(skill),
                          title: skill.name,
                          subtitle: skill.description,
                          trailing: s.activeSkill == skill.id
                              ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF10B981))
                              : const SizedBox(width: 18),
                          onTap: () {
                            s.setActiveSkill(skill.id);
                            entry.remove();
                            _showChatToast(context, '已启用技能「${skill.name}」');
                          },
                        ),
                    ],
                  ),
                ),
              ],
            );
          } else if (page == 'connectors') {
            body = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildHeader('连接器', onBack: () => setSt(() => page = 'main')),
                StatefulBuilder(
                  builder: (ctx2, setLocal) => _darkMenuItem(
                    icon: Icon(Icons.travel_explore, size: 20, color: s.searchEnabled ? const Color(0xFF10B981) : textSecondary),
                    title: '联网搜索',
                    subtitle: '开启后 AI 可联网检索实时信息',
                    trailing: Switch(
                      value: s.searchEnabled,
                      onChanged: (v) {
                        s.setSearchEnabled(v);
                        setLocal(() {});
                      },
                      activeColor: const Color(0xFF10B981),
                    ),
                    onTap: () {
                      s.setSearchEnabled(!s.searchEnabled);
                      setLocal(() {});
                    },
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.settings_outlined, size: 20, color: textSecondary),
                  title: '联网搜索设置',
                  onTap: () {
                    entry.remove();
                    showDialog(context: context, builder: (_) => const SettingsDialog());
                  },
                ),
              ],
            );
          } else {
            body = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _darkMenuItem(
                  icon: const Icon(Icons.attach_file_outlined, size: 20, color: textSecondary),
                  title: '添加文件',
                  onTap: () {
                    entry.remove();
                    _pickChatFile();
                  },
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 20, color: textSecondary),
                  title: '技能',
                  trailing: s.currentSkill != null
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                        )
                      : const SizedBox(width: 18),
                  onTap: () => setSt(() => page = 'skills'),
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.lan_outlined, size: 20, color: textSecondary),
                  title: '连接器',
                  trailing: s.searchEnabled
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                        )
                      : const SizedBox(width: 18),
                  onTap: () => setSt(() => page = 'connectors'),
                ),
              ],
            );
          }
          // 抑制未使用变量警告
          // ignore: unused_local_variable
          final _ = textTertiary;
          return body;
        },
      );
    }

    entry = _showOverlayPanel(
      context,
      _plusBtnKey,
      width: 240,
      height: 200,
      content: contentBuilder(context, (_) {}),
    );
  }

  void _showChatToast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 13)),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  /// 通用桌面端浮层：从 anchorKey 按钮位置弹出指定尺寸的深色卡片。
  /// [content] 为浮层内容（已用 ClipRRect + Material 包裹好）。
  /// 浮层位置默认在按钮正上方、左对齐到按钮左侧；屏幕边距不足时自动翻转到下方/右对齐。
  /// 浮层外点击空白处自动关闭；返回 OverlayEntry 供调用方在合适时机关闭。
  OverlayEntry _showOverlayPanel(
    BuildContext context,
    GlobalKey anchorKey, {
    required double width,
    required double height,
    required Widget content,
    Alignment align = Alignment.bottomLeft,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final renderBox = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    double popupX = 0;
    double popupY = 0;
    if (renderBox != null) {
      final anchorGlobal = renderBox.localToGlobal(Offset.zero);
      final anchorSize = renderBox.size;
      final screenSize = MediaQuery.of(context).size;
      // 默认浮在按钮上方；上方空间不够则改下方
      popupX = anchorGlobal.dx;
      popupY = anchorGlobal.dy - height - 8;
      if (popupY < 12) popupY = anchorGlobal.dy + anchorSize.height + 8;
      // 浮层右对齐按钮（默认）、或左对齐，按 align 决定
      if (align == Alignment.bottomRight) {
        popupX = anchorGlobal.dx + anchorSize.width - width;
      } else if (align == Alignment.topRight) {
        popupX = anchorGlobal.dx + anchorSize.width - width;
        popupY = anchorGlobal.dy + anchorSize.height + 8;
        if (popupY + height > screenSize.height - 12) popupY = anchorGlobal.dy - height - 8;
      }
      // 屏幕边界夹取
      if (popupX < 12) popupX = 12;
      if (popupX + width > screenSize.width - 12) popupX = screenSize.width - width - 12;
      if (popupY + height > screenSize.height - 12) popupY = screenSize.height - height - 12;
    }
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => entry.remove(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: popupX,
            top: popupY,
            width: width,
            height: height,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0.94, end: 1.0),
              builder: (ctx, scale, child) => Opacity(
                opacity: ((scale - 0.94) / 0.06).clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: scale,
                  alignment: align,
                  child: child,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(color: const Color(0xFF2B2B32), child: content),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(entry);
    return entry;
  }

  /// 深色菜单单行项（左侧图标 + 文字 + 右侧箭头）
  static Widget _darkMenuItem({
    required Widget icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    const hover = Color(0xFF33333A);
    const border = Color(0xFF3D3D45);
    const text = Color(0xFFE4E4E8);
    const textSecondary = Color(0xFFADADB8);
    const textTertiary = Color(0xFF85859A);
    return InkWell(
      onTap: onTap,
      hoverColor: hover,
      splashColor: hover,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: border, width: 0.5))),
        child: Row(children: [
          SizedBox(width: 20, child: icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(fontSize: 13, color: danger ? const Color(0xFFF87171) : text)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: textSecondary)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
          if (trailing == null) const Icon(Icons.chevron_right_rounded, size: 16, color: textTertiary),
        ]),
      ),
    );
  }

  /// 权限选择弹窗（默认权限 / 允许完全访问，从权限按钮位置浮出）
  void _showChatPermissionMenu(BuildContext context, AppColors c, AppState s) {
    late OverlayEntry entry;
    entry = _showOverlayPanel(
      context,
      _permissionBtnKey,
      width: 280,
      height: 200,
      content: StatefulBuilder(
        builder: (ctx, setLocal) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: const [
                Icon(Icons.shield_outlined, size: 18, color: Color(0xFFA78BFA)),
                SizedBox(width: 8),
                Text('权限设置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE4E4E8))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '当前为默认权限，所有操作都会在安全沙箱约束内进行，超出范围会请求你的允许。',
                style: TextStyle(fontSize: 12, color: const Color(0xFFADADB8), height: 1.5),
              ),
            ),
            _darkMenuItem(
              icon: const Icon(Icons.verified_user_outlined, size: 20, color: Color(0xFFADADB8)),
              title: '允许完全访问',
              trailing: Switch(
                value: s.chatFullAccess,
                onChanged: (v) {
                  s.setChatFullAccess(v);
                  setLocal(() {});
                },
                activeColor: const Color(0xFF10B981),
              ),
              onTap: () {
                s.setChatFullAccess(!s.chatFullAccess);
                setLocal(() {});
              },
            ),
            const Divider(height: 1, color: Color(0xFF3D3D45)),
            _darkMenuItem(
              icon: const Icon(Icons.shield_outlined, size: 20, color: Color(0xFF10B981)),
              title: '默认权限',
              trailing: !s.chatFullAccess
                  ? const Icon(Icons.check_rounded, size: 18, color: Color(0xFF10B981))
                  : const SizedBox(width: 18),
              onTap: () {
                s.setChatFullAccess(false);
                entry.remove();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// AI 助手工作区选择器（从工作区按钮位置弹出的居中深色卡片）
  void _showWorkspacePicker(BuildContext context, AppColors c, AppState s) {
    debugPrint('[workspace] showDialog called');
    final nav = Navigator.of(context, rootNavigator: true);
    nav.push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (pc, __, ___) => StatefulBuilder(builder: (ctx, setSt) {
        final hasWs = s.workspacePath.isNotEmpty;
        final displayPath = hasWs ? s.workspacePath : r'C:\Users（默认）';
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(
              color: const Color(0xFF2B2B32),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Row(children: [
                        const Icon(Icons.work_outline_rounded, size: 18, color: Color(0xFF10B981)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('工作区',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE4E4E8))),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFADADB8)),
                          onPressed: () => nav.pop(),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(children: [
                        Icon(Icons.folder_rounded, size: 16, color: hasWs ? const Color(0xFF10B981) : const Color(0xFFADADB8)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            displayPath,
                            style: TextStyle(fontSize: 12, color: hasWs ? const Color(0xFFE4E4E8) : const Color(0xFFADADB8)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        'AI 助手只能在该目录及其子目录内读写文件、执行 Shell。',
                        style: TextStyle(fontSize: 11, color: Color(0xFF85859A), height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final selected = await FilePicker.platform.getDirectoryPath(
                          dialogTitle: '选择 AI 助手工作目录',
                          initialDirectory: s.workspacePath.isNotEmpty ? s.workspacePath : null,
                        );
                        if (selected == null) return;
                        s.setWorkspacePath(selected.replaceAll('/', '\\'));
                        if (pc.mounted) {
                          _showChatToast(pc, '已设置工作区：$selected');
                          setSt(() {});
                        }
                      },
                      hoverColor: const Color(0xFF33333A),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: const [
                          Icon(Icons.create_new_folder_outlined, size: 18, color: Color(0xFFADADB8)),
                          SizedBox(width: 10),
                          Text('选择目录', style: TextStyle(fontSize: 14, color: Color(0xFFE4E4E8))),
                          Spacer(),
                          Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF85859A)),
                        ]),
                      ),
                    ),
                    if (hasWs) ...[
                      const Divider(height: 1, indent: 42, endIndent: 0, color: Color(0xFF3D3D45)),
                      InkWell(
                        onTap: () {
                          s.setWorkspacePath('');
                          if (pc.mounted) {
                            _showChatToast(pc, '已恢复默认工作区');
                            setSt(() {});
                          }
                        },
                        hoverColor: const Color(0xFF33333A),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(children: const [
                            Icon(Icons.restart_alt_rounded, size: 18, color: Color(0xFFF87171)),
                            SizedBox(width: 10),
                            Text('重置为默认', style: TextStyle(fontSize: 14, color: Color(0xFFF87171))),
                          ]),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    ));
  }

  /// 模型选择器（单列紧凑版：顶部「最大上下文模式」开关；列表项 = 图标 + 模型名（白字）+ 彩色标签 + 对勾；删倍率）
  void _showChatModelSelector(BuildContext context, AppColors c, AppState s) {
    // ===== 视觉常量（贴近参考图：近黑底 + 胶囊 chip + 自定义绿色开关） =====
    const surface = Color(0xFF17171C);          // 主浮层背景
    const surfaceHighlight = Color(0xFF24242B); // 选中态背景
    const surfaceHover = Color(0xFF1F1F25);
    const dividerColor = Color(0xFF24242B);
    const borderColor = Color(0xFF2D2D35);
    const textPrimary = Color(0xFFFFFFFF);
    const textMuted = Color(0xFF888892);
    const accent = Color(0xFF10B981);

    // 标签颜色
    const cBlue = Color(0xFF60A5FA);
    const cRed = Color(0xFFEF4444);
    const cAmber = Color(0xFFF59E0B);
    const cGreen = Color(0xFF34D399);

    const popupWidth = 380.0;
    const popupMaxHeight = 440.0;

    // 胶囊 chip 标签（参考图：半透明色底 + 同色细边 + 同色文字）
    Widget tagPill(String text, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45), width: 0.5),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent,
          ),
        ),
      );
    }

    // Max 模式自定义开关：白色 thumb + 绿色激活态 + 圆角胶囊
    Widget maxSwitch(bool value, ValueChanged<bool> onChanged) {
      return GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: value ? accent : const Color(0xFF34343C),
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 21,
              height: 21,
              decoration: BoxDecoration(
                color: value ? Colors.white : const Color(0xFFBDBDC6),
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 模型 logo：品牌色渐变圆底 + 白色图标（不裸渲染黑灰 SVG）
    Widget modelIcon(String model) {
      return _aiLogo(model, size: 24);
    }

    final compact = _isCompact(context);
    // 列表源：开启"独立配置"时展示对话助手配置库，否则展示全局配置库
    final profiles = s.chatApiIndependent ? s.chatProfiles : s.apiProfiles;
    // 初始选中：useAutoModel → Auto(idx=-1)；否则按当前生效配置（effectiveChatConfig）匹配
    int initialIdx = -1;
    if (!s.useAutoModel) {
      final eff = s.effectiveChatConfig;
      for (var i = 0; i < profiles.length; i++) {
        if (profiles[i].config.url == eff.url &&
            profiles[i].config.key == eff.key &&
            profiles[i].config.model == eff.model) {
          initialIdx = i;
          break;
        }
      }
    }
    // 选中状态提升到外层闭包：避免 StatefulBuilder 每次 build 重新初始化（修复选中特效不变）
    int curSelectedIdx = initialIdx;
    bool curMaxMode = s.chatThinking;

    // 行渲染（icon + 名称 + tags + 价格）
    // - tags：来自 ApiProfile.tags（数据驱动，不硬编码）
    // - priceText：来自 ApiProfile.priceLabel，可空
    Widget buildRow({
      required Widget icon,
      required String title,
      required String? priceLabel,
      required bool selected,
      required List<({String text, Color color})> tags,
      required VoidCallback onTap,
    }) {
      return InkWell(
        onTap: onTap,
        // hover 时仅显示亮度微调（surfaceHighlight），不用 hoverColor 防止在某些
        // 主题里出现 underline-like 视觉假象
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: Container(
          color: selected ? surfaceHighlight : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              SizedBox(width: 22, height: 22, child: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          decoration: TextDecoration.none,
                          decorationColor: Colors.transparent,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (tags.isNotEmpty) const SizedBox(width: 6),
                    ...List.generate(tags.length, (i) {
                      final t = tags[i];
                      return Padding(
                        padding: EdgeInsets.only(right: i == tags.length - 1 ? 0 : 4),
                        child: tagPill(t.text, t.color),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 48,
                child: Text(
                  priceLabel ?? '',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    color: (priceLabel == null || priceLabel!.isEmpty)
                        ? textMuted
                        : textPrimary,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    height: 1.2,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 把 ApiProfile.tags（{text, colorValue}）转成 UI 用的 {text, color}
    List<({String text, Color color})> profileTags(ApiProfile p) {
      return p.tags
          .map((t) => (text: t.text, color: Color(t.colorValue)))
          .toList();
    }

    Widget content(int selectedIdx, bool maxMode, void Function(int, bool) onChanged) {
      final listItems = <Widget>[
        // 顶部 Max 模式行
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              // 钻石图标 + 阴影提亮，避免在深底上发暗看起来像黑图标
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  boxShadow: const [
                    BoxShadow(color: Color(0x55FFFFFF), blurRadius: 4, offset: Offset(0, 0)),
                  ],
                ),
                child: const Icon(
                  Icons.diamond_outlined,
                  color: Color(0xFFFFFFFF),
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Max 模式',
                  style: TextStyle(
                    fontSize: 14,
                    color: textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                  ),
                ),
              ),
              maxSwitch(maxMode, (v) => onChanged(selectedIdx, v)),
            ],
          ),
        ),
        Container(height: 1, color: dividerColor),

        // Auto 行：循环图标 + w600 文字
        buildRow(
          icon: Container(
            decoration: const BoxDecoration(
              boxShadow: [BoxShadow(color: Color(0x33FFFFFF), blurRadius: 3, offset: Offset(0, 0))],
            ),
            child: const Icon(Icons.autorenew_rounded, size: 22, color: textPrimary),
          ),
          title: 'Auto',
          priceLabel: null,
          selected: selectedIdx == -1,
          tags: const [],
          onTap: () {
            s.enableAutoModel();
            onChanged(-1, maxMode);
          },
        ),
        Container(height: 1, color: dividerColor),

        // 模型行：价格 + tags 都来自 ApiProfile 字段（不硬编码）
        for (var i = 0; i < profiles.length; i++) ...[
          buildRow(
            icon: modelIcon(profiles[i].config.model),
            title: profiles[i].config.model.isNotEmpty
                ? profiles[i].config.model
                : profiles[i].name,
            priceLabel: profiles[i].priceLabel,
            selected: selectedIdx == i,
            tags: profileTags(profiles[i]),
            onTap: () {
              s.disableAutoModel();
              // 开启"独立配置"时写入对话助手配置库，否则写全局配置库
              if (s.chatApiIndependent) {
                s.saveChatProfiles(s.chatProfiles, i);
              } else {
                s.saveApiProfiles(s.apiProfiles, i);
              }
              onChanged(i, maxMode);
            },
          ),
          Container(height: 1, color: dividerColor),
        ],

        // 配置自定义模型
        InkWell(
          onTap: () {
            Navigator.pop(context);
            // 强制走 rootNavigator，确保从浮层触发也能弹出完整 SettingsDialog
            // barrierColor 用 40% 半透明黑，避免看起来"全黑"
            showDialog(
              context: context,
              useRootNavigator: true,
              barrierColor: const Color(0x66000000),
              builder: (_) => const SettingsDialog(),
            );
          },
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: const [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Icon(Icons.edit_outlined, color: textMuted, size: 18),
                ),
                SizedBox(width: 12),
                Text(
                  '配置自定义模型',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: textPrimary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                    decorationColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];

      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: popupMaxHeight),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const ClampingScrollPhysics(),
          children: listItems,
        ),
      );
    }

    // 浮层外壳：圆角 + 黑底 + 细边 + 阴影
    Widget chrome(Widget child) {
      return Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }

    if (compact) {
      // 手机端：底部弹层
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setState) {
            void onChanged(int idx, bool mode) {
              setState(() {
                curSelectedIdx = idx;
                curMaxMode = mode;
              });
              if (mode != s.chatThinking) s.setChatThinking(mode);
            }
            return Container(
              decoration: const BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: chrome(content(curSelectedIdx, curMaxMode, onChanged)),
              ),
            );
          });
        },
      );
    } else {
      // 桌面端：从模型按钮位置浮出
      final renderBox =
          _modelSelectorBtnKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) {
        // fallback：弹居中 Dialog
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: StatefulBuilder(builder: (ctx, setState) {
              void onChanged(int idx, bool mode) {
                setState(() {
                  curSelectedIdx = idx;
                  curMaxMode = mode;
                });
                if (mode != s.chatThinking) s.setChatThinking(mode);
              }
              return SizedBox(
                width: popupWidth,
                child: chrome(content(curSelectedIdx, curMaxMode, onChanged)),
              );
            }),
          ),
        );
        return;
      }

      final anchorGlobal = renderBox.localToGlobal(Offset.zero);
      final anchorSize = renderBox.size;
      final screenSize = MediaQuery.of(context).size;
      double popupX = anchorGlobal.dx + anchorSize.width - popupWidth;
      double popupY = anchorGlobal.dy - popupMaxHeight - 8;
      if (popupY < 8) popupY = 8;
      if (popupX < 12) popupX = 12;
      if (popupX + popupWidth > screenSize.width - 12) {
        popupX = screenSize.width - popupWidth - 12;
      }

      final overlay = Overlay.of(context, rootOverlay: true);
      late OverlayEntry entry;
      entry = OverlayEntry(builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          void onChanged(int idx, bool mode) {
            setState(() {
              curSelectedIdx = idx;
              curMaxMode = mode;
            });
            if (mode != s.chatThinking) s.setChatThinking(mode);
          }
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => entry.remove(),
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned(
                left: popupX,
                top: popupY,
                width: popupWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: popupMaxHeight),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0.94, end: 1.0),
                    builder: (ctx, scale, child) => Opacity(
                      opacity: ((scale - 0.94) / 0.06).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.bottomRight,
                        child: child,
                      ),
                    ),
                    child: chrome(content(curSelectedIdx, curMaxMode, onChanged)),
                  ),
                ),
              ),
            ],
          );
        });
      });
      overlay.insert(entry);
    }
  }

  /// 上下文用量可视化进度条：分段彩色 + 白色细分割线，点击打开详细弹窗
  Widget _buildContextUsagePill(BuildContext context, AppColors c, AppState s, {Key? anchorKey}) {
    final bd = s.contextTokenBreakdown();
    final pct = bd.usedPct;
    const colors = [
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFF60A5FA),
      Color(0xFFA78BFA),
    ];
    final values = [bd.system, bd.tools, bd.messages, bd.connectors, bd.skills];
    final usedK = bd.formatK(bd.used);
    final maxK = bd.formatK(bd.maxTokens);

    return Expanded(
      child: GestureDetector(
        key: anchorKey,
        onTap: () => _showContextUsageBreakdown(context, s),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Text('上下文分布', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.textSecondary)),
                const Spacer(),
                Text('${bd.formatUsedPct()} · ${usedK} / ${maxK}', style: TextStyle(fontSize: 11, color: c.textTertiary)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 6,
                  color: c.inputFill,
                  child: Row(
                    children: [
                      for (var i = 0; i < values.length; i++)
                        if (values[i] > 0 && pct > 0)
                          Expanded(
                            flex: ((values[i] / bd.maxTokens) * 10000).round().clamp(1, 10000),
                            child: Container(color: colors[i]),
                          ),
                      if (pct < 1)
                        Expanded(
                          flex: (((1 - pct) * 10000).round()).clamp(1, 10000),
                          child: const SizedBox.shrink(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 上下文用量详细分布弹窗（按图6：顶部大百分比 + 副文字 + 白色细分割线彩色分段进度条 + 5 行圆点百分比）
  void _showContextUsageBreakdown(BuildContext context, AppState s) {
    final bd = s.contextTokenBreakdown();
    // 5 个分类，按图6配色：绿/橙/紫/蓝/浅紫
    const colors = [
      Color(0xFF10B981), // 系统提示词（绿）
      Color(0xFFF59E0B), // 工具及子智能体（橙）
      Color(0xFF8B5CF6), // 对话消息（紫）
      Color(0xFF60A5FA), // 连接器及 MCP（蓝）
      Color(0xFFA78BFA), // 技能（浅紫）
    ];
    final names = ['系统提示词', '工具及子智能体', '对话消息', '连接器及 MCP', '技能'];
    final values = [bd.system, bd.tools, bd.messages, bd.connectors, bd.skills];

    _showOverlayPanel(
      context,
      _contextPillKey,
      width: 360,
      height: 380,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题区：大百分比 + 副文字
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(
                    bd.formatUsedPct(),
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFFE4E4E8), height: 1.0),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '已使用 ${bd.formatK(bd.used)} / ${bd.formatK(bd.maxTokens)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFFADADB8)),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    '剩余 ${bd.formatK(bd.maxTokens - bd.used)} (${(100 - bd.usedPct * 100).toStringAsFixed(1)}%)',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF85859A)),
                  ),
                  if (s.chatThinking) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: const Text('Max 模式 1M', style: TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                    ),
                  ],
                ]),
              ],
            ),
          ),
          // 主进度条：白色细分割线分段（圆角 6，整体高度 10）
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Container(
                height: 10,
                color: const Color(0xFF3D3D45),
                child: Row(
                  children: [
                    for (var i = 0; i < values.length; i++)
                      if (values[i] > 0)
                        Expanded(
                          flex: ((values[i] / bd.maxTokens) * 10000).round().clamp(1, 10000),
                          child: Container(color: colors[i]),
                        ),
                    // 剩余空间（容量空白）的暗灰色条
                    if (bd.used < bd.maxTokens)
                      Expanded(
                        flex: (((bd.maxTokens - bd.used) / bd.maxTokens) * 10000).round().clamp(1, 10000),
                        child: Container(color: const Color(0xFF3D3D45)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text('分布', style: TextStyle(fontSize: 11, color: Color(0xFF85859A), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < values.length; i++) ...[
            InkWell(
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: colors[i], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(names[i], style: const TextStyle(fontSize: 13, color: Color(0xFFE4E4E8)))),
                  const SizedBox(width: 10),
                  Text(bd.formatK(values[i]), style: const TextStyle(fontSize: 12, color: Color(0xFFADADB8))),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 56,
                    child: Text(
                      bd.formatPctOf(values[i]),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFFFFFFF), fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ]),
              ),
            ),
            if (i < values.length - 1) const Divider(height: 1, indent: 38, endIndent: 20, color: Color(0xFF3D3D45)),
          ],
        ],
      ),
    );
  }

  /// 当前已启用的能力标签（模式/技能/专家/工具），用于输入栏上方的状态条
  List<String> _activeCapabilityChips(AppState s) {
    final chips = <String>[];
    for (final m in kChatModes) {
      if (m.id == s.chatMode && m.id != 'chat') chips.add('模式·${m.name}');
    }
    final skill = s.currentSkill;
    if (skill != null) {
      final prefix = skill.toolName != null ? '工具·' : '技能·';
      chips.add('$prefix${skill.name}');
    }
    final expert = s.currentExpert;
    if (expert != null) chips.add('专家·${expert.name}');
    return chips;
  }

  /// 点击能力标签的 × 时清除对应能力
  void _clearCapability(String chip, AppState s) {
    if (chip.startsWith('模式·')) {
      s.setChatMode('chat');
    } else if (chip.startsWith('技能·') || chip.startsWith('工具·')) {
      s.setActiveSkill('');
    } else if (chip.startsWith('专家·')) {
      s.setActiveExpert('');
    }
  }

  /// 新版 AI 助手聊天输入栏（桌面 + 手机通用）
  /// 布局参考现代 AI 聊天框：顶部能力标签、中间输入区、底部工具行 + 圆形发送按钮。
  Widget _buildChatInputBar(BuildContext context, AppColors c, AppState s, {bool isMobile = false}) {
    final compact = _isCompact(context) || isMobile;
    final cfg = s.effectiveChatConfig;
    final modelLabel = cfg.ready ? cfg.model : '未配置';
    final aiIconAsset = _getAiIconAsset(modelLabel);
    final aiIcon = aiIconAsset != null
        ? _aiLogo(modelLabel, size: 18)
        : Icon(Icons.smart_toy_outlined, size: 14, color: c.text);

    // 附件/图片预览条
    Widget preview = const SizedBox.shrink();
    if (_chatImageData != null || _chatAttachmentName != null) {
      preview = Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_chatImageData != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(base64Decode(_chatImageData!.split(',').last), width: 48, height: 48, fit: BoxFit.cover),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: c.inputFill, borderRadius: BorderRadius.circular(6)),
              child: Icon(Icons.insert_drive_file_outlined, size: 20, color: c.primary),
            ),
          const SizedBox(width: 8),
          Text(
            _chatImageData != null
                ? '已选择图片'
                : (_chatFileText != null ? '已读取「$_chatAttachmentName」内容' : _chatAttachmentName!),
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
          const SizedBox(width: 4),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 16, color: c.textTertiary),
            onPressed: () => setState(() {
              _chatImageData = null;
              _chatAttachmentName = null;
              _chatFileText = null;
            }),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.isLight ? const Color(0xFFF7F8FA) : const Color(0xFF232328),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.divider),
        boxShadow: c.isLight
            ? [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          preview,
          // 当前已启用的能力（技能 / 模式 / 专家 / 工具）状态条
          if (_activeCapabilityChips(s).isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: _activeCapabilityChips(s).map((chip) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(chip, style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    GestureDetector(
                      onTap: () => _clearCapability(chip, s),
                      child: Icon(Icons.close_rounded, size: 12, color: c.primary),
                    ),
                  ]),
                );
              }).toList()),
            ),
          Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.keyV &&
                  HardwareKeyboard.instance.isControlPressed) {
                _pasteImageFromClipboard().then((bytes) {
                  if (bytes != null && bytes.isNotEmpty) {
                    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
                    setState(() => _chatImageData = dataUrl);
                  }
                });
                return KeyEventResult.ignored;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _chatCtrl,
              minLines: compact ? 2 : 3,
              maxLines: compact ? 5 : 7,
              style: TextStyle(fontSize: 14, color: c.text, height: 1.5),
              decoration: InputDecoration(
                hintText: '今天帮你做些什么？@ 引用文件',
                hintStyle: TextStyle(fontSize: 14, color: c.hintText),
                filled: false,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              ),
              onSubmitted: (_) {
                if (s.chatSending) {
                  s.cancelChat();
                } else {
                  _sendChat(s);
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            // 左侧工具：+ / 权限
            _ChatInputIconButton(
              key: isMobile ? null : _plusBtnKey,
              icon: Icons.add_rounded,
              tooltip: '工具',
              onPressed: () => _showChatPlusMenu(context, c, s),
              c: c,
            ),
            const SizedBox(width: 4),
            _ChatInputTextButton(
              key: isMobile ? null : _permissionBtnKey,
              icon: Icons.shield_outlined,
              label: s.chatFullAccess ? '完全访问' : '默认权限',
              onPressed: () => _showChatPermissionMenu(context, c, s),
              c: c,
            ),
            const Spacer(),
            // 右侧：模型 / 发送（独立配置生效时加"独立"标识）
            _ChatInputTextButton(
              key: isMobile ? null : _modelSelectorBtnKey,
              icon: null,
              leading: aiIcon,
              label: s.chatApiIndependent ? '$modelLabel·独立' : modelLabel,
              onPressed: () => _showChatModelSelector(context, c, s),
              c: c,
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () {
                if (s.chatSending) {
                  // 跑动中：再次点击中止 agent 循环
                  s.cancelChat();
                } else {
                  _sendChat(s);
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: s.chatSending
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [c.primary, c.primary],
                        ),
                  color: s.chatSending ? const Color(0xFFEF4444) : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (s.chatSending ? const Color(0xFFEF4444) : c.primary).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: s.chatSending
                    ? const Icon(Icons.stop_rounded, size: 18, color: Colors.white)
                    : Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// 沉浸式全卷满分显示：用固定 150 分（四川专升本 2024/2025 真题满分）
  int _computeMaxScore(AppState s) => 150;

  /// 处理拖拽/选择进来的图片文件（仅取第一个有效图片）
  Future<void> _setChatImageFromFiles(List<XFile> files) async {
    const exts = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'];
    final target = files.where((f) => exts.any((e) => f.name.toLowerCase().endsWith(e))).toList();
    if (target.isEmpty) return;
    final f = target.first;
    if (f.path.isEmpty) return;
    try {
      final bytes = await File(f.path).readAsBytes();
      final dataUrl = 'data:image/${_imageMime(f.name)};base64,${base64Encode(bytes)}';
      setState(() => _chatImageData = dataUrl);
    } catch (_) {
      // 读取失败忽略
    }
  }

  void _sendChat(AppState s, {String? text}) async {
    final msg = text ?? _chatCtrl.text.trim();
    final img = _chatImageData;
    final attach = _chatAttachmentName;
    final fileText = _chatFileText;
    if (msg.isEmpty && img == null && attach == null) return;
    if (text == null) _chatCtrl.clear();
    if (attach != null && !_conversationFiles.contains(attach)) {
      _conversationFiles.add(attach);
    }
    setState(() {
      _chatImageData = null;
      _chatAttachmentName = null;
      _chatFileText = null;
    });
    final prevPage = s.page;
    // attachmentText 为文本文件内容；无文本内容但有附件名时（如 pdf/docx），以附件名提示 AI
    await s.sendChat(msg, imageData: img, attachmentText: fileText ?? (attach != null ? '[附件: $attach]' : null));
    // 手机端：出题后页面跳到了答题页/考场，自动关闭聊天浮层让用户看到新页面
    if (mounted && _state.uiMode == 'mobile' && _state.page != prevPage &&
        (_state.page == 1 || _state.page == 10 || _state.page == 11)) {
      Navigator.of(context).pop();
      return;
    }
  }
}

/// 聊天输入栏圆形图标按钮
class _ChatInputIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final AppColors c;
  const _ChatInputIconButton({super.key, required this.icon, this.tooltip, required this.onPressed, required this.c});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: c.inputFill,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 18, color: c.textTertiary),
        ),
      ),
    );
  }
}

/// 聊天输入栏文字+图标按钮
class _ChatInputTextButton extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String label;
  final VoidCallback? onPressed;
  final AppColors c;
  const _ChatInputTextButton({super.key, this.icon, this.leading, required this.label, required this.onPressed, required this.c});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: c.inputFill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (leading != null) ...[leading!, const SizedBox(width: 4)],
            if (icon != null) ...[Icon(icon, size: 14, color: c.textTertiary), const SizedBox(width: 4)],
            Flexible(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: c.textSecondary),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: c.textTertiary),
          ]),
        ),
      ),
    );
  }
}

// 2x2 网格功能卡片
class _ChatFeatureCard extends StatelessWidget {
  final IconData icon;
  final FeatureIconVariant iconVariant;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ChatFeatureCard({required this.icon, required this.iconVariant, required this.iconColor, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.featureIconBg(iconVariant), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(fontSize: 11, color: c.textTertiary)),
        ]),
      ),
    );
  }
}

class _QuickQuestion extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _QuickQuestion({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: c.primaryBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.primaryBorder),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: c.primaryText)),
      ),
    );
  }
}

class _PageScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const _PageScaffold({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    return Column(children: [
      Padding(
        padding: isMobile ? const EdgeInsets.fromLTRB(16, 8, 16, 6) : const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: TextStyle(fontSize: isMobile ? 17 : 20, fontWeight: FontWeight.bold, color: c.text)),
        ),
      ),
      Expanded(child: child),
    ]);
  }
}

// ===== "更多功能"独立选择页面（桌面/手机自适应） — 毛玻璃大面板 =====
class _MoreSelectPage extends StatefulWidget {
  final int currentIndex;
  final void Function(int index) onSelect;
  const _MoreSelectPage({required this.currentIndex, required this.onSelect});

  @override
  State<_MoreSelectPage> createState() => _MoreSelectPageState();
}

class _MoreSelectPageState extends State<_MoreSelectPage> {
  int? _hoveredIdx;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    final crossCount = isMobile ? 2 : 3;
    final moreItems = _moreItemsData;
    // 功能网格（glass/classic 共用）
    final moreGrid = GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossCount,
        mainAxisSpacing: isMobile ? 10 : 16,
        crossAxisSpacing: isMobile ? 10 : 16,
        childAspectRatio: isMobile ? 1.05 : 2.4,
      ),
      itemCount: moreItems.length,
      itemBuilder: (ctx, i) {
        final item = moreItems[i];
        return _GlassFeatureCard(
          icon: item.$1,
          title: item.$2,
          subtitle: item.$3,
          selected: widget.currentIndex == item.$4,
          hovered: _hoveredIdx == i,
          c: c,
          isMobile: isMobile,
          onHover: (h) => setState(() => _hoveredIdx = h ? i : (_hoveredIdx == i ? null : _hoveredIdx)),
          onTap: () => widget.onSelect(item.$4),
        );
      },
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(isMobile ? 14 : 32, isMobile ? 12 : 24, isMobile ? 14 : 32, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 标题区
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(Icons.grid_view_outlined, color: c.textSecondary, size: isMobile ? 24 : 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('更多功能', style: TextStyle(
                  fontSize: isMobile ? 20 : 26,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                  letterSpacing: 0.2,
                )),
                const SizedBox(height: 2),
                Text('选择你需要的工具', style: TextStyle(fontSize: isMobile ? 11.5 : 13, color: c.textTertiary)),
              ]),
            ),
            // 右上角 + 按钮：克制灰底半透明
            _GlassAddButton(onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('更多自定义功能正在规划中…'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }),
          ]),
          SizedBox(height: isMobile ? 14 : 22),
          // 功能网格直接铺开，不再包裹在超大面板中
          Expanded(child: moreGrid),
        ]),
      ),
    );
  }
}

/// 毛玻璃功能卡片：56px 渐变图标 + 标题 + 副标题 + hover 抬起效果
class _GlassFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool hovered;
  final AppColors c;
  final bool isMobile;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  const _GlassFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.hovered,
    required this.c,
    required this.isMobile,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final lift = (hovered || selected) ? -1.5 : 0.0;
    final iconSize = isMobile ? 28.0 : 32.0;
    final cardRadius = BorderRadius.circular(isMobile ? 16 : 18);

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, lift, 0),
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 14 : 18,
            vertical: isMobile ? 14 : 16,
          ),
          decoration: BoxDecoration(
            color: (c.isLight ? Colors.white : const Color(0xFF2A2A32)).withValues(
              alpha: selected ? 0.95 : (hovered ? 0.85 : 0.7),
            ),
            borderRadius: cardRadius,
            border: Border.all(
              // 统一中性灰阶边框：与题卡同款，去掉紫色调
              color: selected
                  ? (c.isLight ? Colors.black.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.30))
                  : (hovered
                      ? (c.isLight ? Colors.black.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.20))
                      : (c.isLight ? Colors.white.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.1))),
              width: selected ? 1.2 : 1,
            ),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isLight ? 0.10 : 0.32),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              else if (hovered)
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isLight ? 0.07 : 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isLight ? 0.04 : 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: isMobile
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [_buildIcon(iconSize), const SizedBox(height: 10), _buildTitle(), const SizedBox(height: 3), _buildSubtitle()])
              : Row(children: [
                  _buildIcon(iconSize),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    _buildTitle(),
                    const SizedBox(height: 4),
                    _buildSubtitle(),
                  ])),
                ]),
        ),
      ),
    );
  }

  Widget _buildIcon(double size) {
    return Icon(icon, size: size, color: c.textSecondary);
  }

  Widget _buildTitle() {
    return Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: isMobile ? 14.5 : 16,
        fontWeight: FontWeight.w700,
        color: c.text,
      ),
    );
  }

  Widget _buildSubtitle() {
    return Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: isMobile ? 11.5 : 13,
        color: c.textTertiary,
      ),
    );
  }
}

/// 右上角 + 按钮（毛玻璃圆形）
class _GlassAddButton extends StatefulWidget {
  final VoidCallback onTap;
  const _GlassAddButton({required this.onTap});

  @override
  State<_GlassAddButton> createState() => _GlassAddButtonState();
}

class _GlassAddButtonState extends State<_GlassAddButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scale = _pressed ? 0.94 : (_hovered ? 1.03 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 160),
          curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: c.border, width: 1),
              boxShadow: [
                if (_hovered)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: c.isLight ? 0.06 : 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: Icon(Icons.add, size: 20, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// 全局背景层：纯色（浅色纯白 / 深色纯深灰，无光斑无渐变旋涡）
class _AppGlassBackground extends StatelessWidget {
  final AppColors colors;
  final bool isGlass;
  const _AppGlassBackground({required this.colors, this.isGlass = false});

  @override
  Widget build(BuildContext context) {
    if (isGlass) {
      return GlassBackground(isLight: colors.isLight);
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.appBgGradientTop),
      child: const SizedBox.expand(),
    );
  }
}
