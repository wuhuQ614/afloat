/// SmartEnglish 智能英语学习 - Flutter Windows 桌面版 (afloat 风格)
library;

import 'dart:convert';
import 'dart:io' show File, Platform;
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';
import 'state.dart';
import 'services/tts_service.dart';
import 'theme_colors.dart';
import 'widgets/learn_page.dart';
import 'widgets/grammar_page.dart';
import 'widgets/onboarding_page.dart';
import 'widgets/pages.dart';
import 'widgets/exam_page.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/platform_select_page.dart';

final bool _isWindows = !kIsWeb && Platform.isWindows;

// 更多功能列表：(图标, 标题, 副标题, 页面索引)
const _moreItemsData = [
  (Icons.list_alt_rounded, '题库', '管理题目集', 4),
  (Icons.error_outline_rounded, '错题本', '复习做错的题', 5),
  (Icons.star_outline_rounded, '生词本', '收藏的生词', 6),
  (Icons.bookmark_add_outlined, '答题记录', '记录已答单词', 7),
  (Icons.edit_note_rounded, '默写', '单词默写练习', 8),
  (Icons.school_rounded, '语法学习', '从零学会专升本语法', 12),
];

// 更多功能选择页索引
const _morePageIndex = 9;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isWindows) {
    await windowManager.ensureInitialized();
  }
  // 后台初始化 TTS（失败时自动降级为不可用）
  TtsService.instance.init();
  runApp(const SmartEnglishApp());
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
  /// 考试确认对话框是否正在显示
  bool _examDialogShowing = false;

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
      _state.setUiMode(_state.uiMode == 'mobile' ? 'desktop' : 'mobile');
      return true;
    }

    return false;
  }

  Future<void> _init() async {
    await _state.init().timeout(const Duration(seconds: 8), onTimeout: () {});
    _state.loadFavorites();
    _state.loadWrongQuestions();
    _state.loadStudyRecords();
    _state.loadWordBook();
    _state.loadRecordedWords();
    _state.loadRecordsSelected();
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
    // 全卷生成完成（examPendingConfirm=true）时触发确认弹窗
    _checkExamConfirmDialog();
    setState(() {});
  }

  /// 在 build 中检测考试确认弹窗触发条件
  void _checkExamConfirmDialog() {
    if (_state.examPendingConfirm && _state.currentExamPaper != null && !_examDialogShowing) {
      _examDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _state.examPendingConfirm && _state.currentExamPaper != null) {
          _showExamConfirmDialog();
        } else {
          _examDialogShowing = false;
        }
      });
    }
  }

  static const _frameRateChannel = MethodChannel('com.smartenglish/framerate');

  void _updateFrameRate() {
    // 省电模式锁60帧，否则120帧
    final targetFps = _state.powerSavingMode ? 60 : 120;
    if (!_isWindows) {
      _frameRateChannel.invokeMethod('setFrameRate', {'fps': targetFps});
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    _state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'AFloat',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: _state.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: Builder(builder: (context) {
          final c = AppColors.of(context);
          // 全局玻璃背景层（渐变 + 3 光斑）覆盖加载页/引导页/桌面/手机全部分支
          return Stack(children: [
            Positioned.fill(child: RepaintBoundary(child: _AppGlassBackground(colors: c))),
            Positioned.fill(
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
                    _state.toggleFullscreen(!_state.fullscreen);
                    return KeyEventResult.handled;
                  }
                  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f8) {
                    _state.setUiMode(_state.uiMode == 'mobile' ? 'desktop' : 'mobile');
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
                                onDesktop: () => _state.setUiMode('desktop'),
                                onMobile: () => _state.setUiMode('mobile'),
                              )
                            : _state.uiMode == 'desktop'
                                ? Scaffold(
                                    body: (_state.page == 10 || _state.page == 11)
                                        ? ListenableBuilder(listenable: _state, builder: (ctx, _) => _buildMainContent())
                                        : Row(children: [
                                            _buildSidebar(),
                                            Expanded(child: ListenableBuilder(listenable: _state, builder: (ctx, _) => _buildMainContent())),
                                          ]),
                                  )
                                : _buildMobileLayout(),
              ),
            ),
          ]);
        }),
      ),
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
    return Builder(builder: (context) {
      final c = AppColors.of(context);
      final page = _state.page;
      const mainItems = [
        (Icons.home_rounded, '学习', 0),
        (Icons.quiz_rounded, '答题', 1),
        (Icons.insights_rounded, '学习报告', 2),
        (Icons.search_rounded, '查询', 3),
      ];
      final inMore = page >= 4;
      final inSubFeature = page >= 4 && (page <= 8 || page == 12);
      final moreTitle = inSubFeature ? _moreItemsData.firstWhere((e) => e.$4 == page).$2 : '更多功能';
      final moreIcon = inSubFeature ? _moreItemsData.firstWhere((e) => e.$4 == page).$1 : Icons.apps_rounded;
      return RepaintBoundary(
        child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: c.sidebar,
          border: Border(right: BorderSide(color: c.divider)),
        ),
        child: Column(children: [
          const SizedBox(height: 24),
          // 应用名
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              const Spacer(),
              Tooltip(
                message: _state.darkMode ? '切换浅色模式' : '切换深色模式',
                child: InkWell(
                  onTap: () => _state.toggleDarkMode(!_state.darkMode),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      _state.darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      size: 16,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 28),
          // 主导航项
          for (final item in mainItems)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Tooltip(
                message: item.$2,
                child: InkWell(
                  onTap: () => _state.setPage(item.$3),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: page == item.$3 ? c.primaryGradient : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: page == item.$3 ? [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))] : null,
                    ),
                    child: Row(children: [
                      Icon(item.$1, size: 20, color: page == item.$3 ? Colors.white : c.textTertiary),
                      const SizedBox(width: 12),
                      Text(item.$2, style: TextStyle(fontSize: 14, fontWeight: page == item.$3 ? FontWeight.w700 : FontWeight.w500, color: page == item.$3 ? Colors.white : c.textSecondary)),
                    ]),
                  ),
                ),
              ),
            ),
          // 更多功能按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Tooltip(
              message: '更多功能',
              child: InkWell(
                onTap: () => _state.setPage(_morePageIndex),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: inMore ? c.primaryGradient : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: inMore ? [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  child: Row(children: [
                    Icon(moreIcon, size: 20, color: inMore ? Colors.white : c.textTertiary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(moreTitle, style: TextStyle(fontSize: 14, fontWeight: inMore ? FontWeight.w700 : FontWeight.w500, color: inMore ? Colors.white : c.textSecondary), overflow: TextOverflow.ellipsis)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: inMore ? Colors.white70 : c.textTertiary),
                  ]),
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
        ]),
      ),
      );
    });
  }

  // ===== 主内容区 =====
  Widget _buildMainContent() {
    // 考场沉浸模式（page==10/11）：隐藏 AI 对话栏（右侧30%），卷面独占
    if (_state.page == 10 || _state.page == 11) {
      return Row(children: [
        Expanded(child: _buildPage()),
      ]);
    }
    return Row(children: [
      // 中间内容区（70%）
      Expanded(
        flex: 7,
        child: _buildPage(),
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
        // 考场沉浸模式（page==10/11）：手机端同样全屏化，隐藏顶栏/底部导航/AI 悬浮球
        final examMode = _state.page == 10 || _state.page == 11;
        // 主导航：0学习 1答题 2报告 3更多(触发) 4查询
        const navItems = [
          (Icons.home_rounded, '学习', 0),
          (Icons.quiz_rounded, '答题', 1),
          (Icons.insights_rounded, '报告', 2),
          (Icons.apps_rounded, '更多', -1),
          (Icons.search_rounded, '查询', 3),
        ];
        final inMore = _state.page >= 4;
        final inSubFeature = _state.page >= 4 && (_state.page <= 8 || _state.page == 12);
        final navIndex = inMore ? 3 : (_state.page == 3 ? 4 : _state.page.clamp(0, 2));
        return Scaffold(
          // 透明：让全局玻璃背景层透出
          backgroundColor: Colors.transparent,
          appBar: examMode
              ? null
              : AppBar(
            backgroundColor: c.sidebar,
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
          body: _buildPage(),
          bottomNavigationBar: examMode
              ? null
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
            backgroundColor: c.sidebar,
            indicatorColor: kPrimary.withValues(alpha: c.isLight ? 0.12 : 0.3),
            destinations: [
              for (var i = 0; i < navItems.length; i++)
                NavigationDestination(
                  icon: Icon(navItems[i].$1, size: 22, color: (i == 3 ? inMore : navIndex == i) ? kPrimary : c.textTertiary),
                  selectedIcon: Icon(navItems[i].$1, size: 22, color: kPrimary),
                  label: i == 3 && inSubFeature ? _moreItemsData.firstWhere((e) => e.$4 == _state.page).$2 : navItems[i].$2,
                ),
            ],
          ),
          floatingActionButton: examMode
              ? null
              : Container(
            decoration: BoxDecoration(
              gradient: c.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: FloatingActionButton(
              onPressed: () => _showMobileChatSheet(ctx),
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
            ),
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
                  Text('AI 对话助手', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.settings_outlined, size: 18, color: c.textTertiary),
                    tooltip: '对话设置',
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      showDialog(context: context, builder: (_) => const ChatSettingsDialog());
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
                        return _buildApiConfigPrompt(c.isLight);
                      }
                      final levelName = s.selectedLevel.isEmpty ? '高中' : s.selectedLevel;
                      final typeName = s.selectedType.isEmpty ? '综合' : s.selectedType;
                      return _buildChatWelcome(c.isLight, cfg.model, levelName, typeName, localAiIconAsset);
                    }
                    final scrollCtrl = ScrollController();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (scrollCtrl.hasClients) {
                        scrollCtrl.animateTo(
                          scrollCtrl.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                    return ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: s.chatHistory.length,
                      itemBuilder: (ctx, i) => _buildChatBubble(s.chatHistory[i], c.isLight),
                    );
                  },
                ),
              ),
              // 输入框
              Container(
                padding: EdgeInsets.fromLTRB(12, 8, 16, MediaQuery.of(ctx).padding.bottom + 8),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (_chatImageData != null) ...[
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.divider),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(base64Decode(_chatImageData!.split(',').last), width: 56, height: 56, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 8),
                        Text('已选择图片，将随消息发送', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        const SizedBox(width: 4),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.close_rounded, size: 16),
                          color: c.textTertiary,
                          onPressed: () => setState(() => _chatImageData = null),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(children: [
                    IconButton(
                      tooltip: '上传图片',
                      icon: const Icon(Icons.image_outlined, size: 20),
                      color: c.textTertiary,
                      onPressed: _pickChatImage,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _chatCtrl,
                        minLines: 1,
                        maxLines: 3,
                        style: TextStyle(fontSize: 13, color: c.text),
                        decoration: InputDecoration(
                          hintText: '输入你的问题...',
                          hintStyle: TextStyle(fontSize: 13, color: c.hintText),
                          filled: true,
                          fillColor: c.inputFill,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _sendChat(_state),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: c.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: _state.chatSending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                        onPressed: _state.chatSending ? null : () => _sendChat(_state),
                      ),
                    ),
                  ]),
                ]),
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
  String? _getAiIconAsset(String modelName) {
    final lower = modelName.toLowerCase();
    // 按优先级匹配，越具体的越靠前
    if (lower.contains('gpt-4') || lower.contains('gpt-3.5') || lower.contains('openai')) return 'assets/ai-icons/openai.svg';
    if (lower.contains('claude') || lower.contains('anthropic')) return 'assets/ai-icons/claude.svg';
    if (lower.contains('glm') || lower.contains('chatglm') || lower.contains('zhipu') || lower.contains('智谱')) return 'assets/ai-icons/chatglm.svg';
    if (lower.contains('qwen') || lower.contains('千问') || lower.contains('通义')) return 'assets/ai-icons/qwen.svg';
    if (lower.contains('deepseek') || lower.contains('deep-seek')) return 'assets/ai-icons/deepseek.svg';
    if (lower.contains('gemini') || lower.contains('google')) return 'assets/ai-icons/gemini.svg';
    if (lower.contains('doubao') || lower.contains('豆包')) return 'assets/ai-icons/doubao.svg';
    if (lower.contains('minimax') || lower.contains('minimax')) return 'assets/ai-icons/minimax.svg';
    if (lower.contains('step') || lower.contains('阶跃') || lower.contains('stepfun')) return 'assets/ai-icons/stepfun.svg';
    if (lower.contains('kimi') || lower.contains('moonshot')) return 'assets/ai-icons/kimi.svg';
    if (lower.contains('baichuan') || lower.contains('百川')) return 'assets/ai-icons/baichuan.svg';
    if (lower.contains('yi-') || lower.contains('零一')) return 'assets/ai-icons/yi.svg';
    if (lower.contains('spark') || lower.contains('星火') || lower.contains('xunfei') || lower.contains('讯飞')) return 'assets/ai-icons/spark.svg';
    if (lower.contains('wenxin') || lower.contains('文心') || lower.contains('ernie')) return 'assets/ai-icons/wenxin.svg';
    if (lower.contains('hunyuan') || lower.contains('混元') || lower.contains('tencent')) return 'assets/ai-icons/hunyuan.svg';
    if (lower.contains('mistral')) return 'assets/ai-icons/mistral.svg';
    if (lower.contains('llama') || lower.contains('meta')) return 'assets/ai-icons/llama.svg';
    if (lower.contains('grok') || lower.contains('xai')) return 'assets/ai-icons/grok.svg';
    if (lower.contains('cohere')) return 'assets/ai-icons/cohere.svg';
    if (lower.contains('perplexity')) return 'assets/ai-icons/perplexity.svg';
    if (lower.contains('together')) return 'assets/ai-icons/together.svg';
    return null;
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
    // RepaintBoundary：聊天面板处于流式重建区，隔离重绘
    return RepaintBoundary(
      child: DropTarget(
      onDragDone: (details) => _setChatImageFromFiles(details.files),
      child: Container(
        decoration: BoxDecoration(
          // 透明：让全局玻璃背景层透出
          color: Colors.transparent,
          border: Border(left: BorderSide(color: c.divider)),
        ),
        child: Column(children: [
          // 头部（AI信息栏 + 操作按钮）— 透明背景 + 底部分割线
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(bottom: BorderSide(color: c.divider)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // AI 头像（缩小到30px，和按钮对齐）
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: aiIconAsset == null ? c.primaryGradient : null,
                  color: aiIconAsset != null ? null : c.primary,
                  shape: BoxShape.circle,
                  boxShadow: c.isLight
                      ? [BoxShadow(color: c.primary.withValues(alpha: 0.22), blurRadius: 6, offset: const Offset(0, 1))]
                      : [
                          BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.48), blurRadius: 10, spreadRadius: 1),
                          BoxShadow(color: const Color(0xFFA78BFA).withValues(alpha: 0.22), blurRadius: 15, spreadRadius: 2),
                        ],
                ),
                child: aiIconAsset != null
                    ? ClipOval(child: SvgPicture.asset(aiIconAsset, width: 30, height: 30, fit: BoxFit.cover,
                        colorFilter: c.isLight ? null : const ColorFilter.mode(Color(0xFFC4B5FD), BlendMode.srcATop)))
                    : const Center(child: Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(modelName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: cfg.ready ? c.text : c.textTertiary), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 2),
                    // 底层模型切换
                    PopupMenuButton<int>(
                      tooltip: '切换模型',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.swap_vert_rounded, size: 15, color: c.textTertiary),
                      onSelected: (v) => s.selectChatProfile(v),
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: -1,
                          child: Row(children: [
                            Icon(Icons.public_rounded, size: 16, color: c.textTertiary),
                            const SizedBox(width: 8),
                            Expanded(child: Text('全局配置', style: TextStyle(fontSize: 13, color: c.text))),
                            if (!s.chatApiIndependent)
                              Icon(Icons.check_rounded, size: 16, color: kPrimary),
                          ]),
                        ),
                        for (var i = 0; i < s.chatProfiles.length; i++)
                          PopupMenuItem(
                            value: i,
                            child: Row(children: [
                              Icon(Icons.smart_toy_outlined, size: 16, color: c.textTertiary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${s.chatProfiles[i].label} · ${s.chatProfiles[i].config.model}',
                                  style: TextStyle(fontSize: 13, color: c.text),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (s.chatApiIndependent && s.chatProfileIdx == i)
                                Icon(Icons.check_rounded, size: 16, color: kPrimary),
                            ]),
                          ),
                      ],
                    ),
                  ]),
                ]),
              ),
              const SizedBox(width: 4),
              // 刷新按钮（与头像居中对齐）
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(Icons.refresh_rounded, size: 18, color: c.textTertiary),
                tooltip: '清空对话',
                onPressed: () => s.clearChat(),
              ),
              // 设置按钮（与头像居中对齐）
              Builder(builder: (btnCtx) => IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(Icons.tune_rounded, size: 18, color: c.textTertiary),
                tooltip: '对话设置',
                onPressed: () => showDialog(context: btnCtx, builder: (_) => const ChatSettingsDialog()),
              )),
            ]),
          ),
        const SizedBox(height: 8),
        // 消息列表
        Expanded(
          child: s.chatHistory.isEmpty
              ? (cfg.ready
                  ? _buildChatWelcome(c.isLight, modelName, levelName, typeName, aiIconAsset)
                  : _buildApiConfigPrompt(c.isLight))
              : ValueListenableBuilder<int>(
                  valueListenable: s.chatUpdateNotifier,
                  builder: (ctx, _, __) {
                    // 流式输出时自动滚动到底部
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollChatToBottom());
                    return ListView.builder(
                      controller: _chatScrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: s.chatHistory.length,
                      itemBuilder: (ctx, i) => _buildChatBubble(s.chatHistory[i], c.isLight),
                    );
                  },
                ),
        ),
        // 快捷问题（已移除，减少占位）
        if (s.chatHistory.isEmpty) ...[
          const SizedBox(height: 4),
        ],
        // 输入框
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 待发送图片预览
            if (_chatImageData != null) ...[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.divider),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(base64Decode(_chatImageData!.split(',').last), width: 56, height: 56, fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 8),
                  Text('已选择图片，将随消息发送', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: c.textTertiary,
                    onPressed: () => setState(() => _chatImageData = null),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              // 图片上传按钮
              IconButton(
                tooltip: '上传图片（也可直接拖拽图片到面板）',
                icon: const Icon(Icons.image_outlined, size: 20),
                color: c.textTertiary,
                onPressed: _pickChatImage,
              ),
              Expanded(
                child: Focus(
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
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(fontSize: 13, color: c.text),
                    decoration: InputDecoration(
                      hintText: '',
                      hintStyle: TextStyle(fontSize: 13, color: c.hintText),
                      filled: true,
                      fillColor: c.inputFill,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendChat(s),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: c.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: IconButton(
                  icon: s.chatSending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                  onPressed: s.chatSending ? null : () => _sendChat(s),
                ),
              ),
            ]),
          ]),
        ),
      ]),
      ),
      ),
    );
  }

  Widget _buildChatWelcome(bool isLight, String modelName, String levelName, String typeName, String? aiIconAsset) {
    final c = AppColors(isLight);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // AI 欢迎消息
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: aiIconAsset == null ? c.primaryGradient : null,
              color: aiIconAsset != null ? null : c.primary,
              shape: BoxShape.circle,
              boxShadow: c.isLight
                  ? null
                  : [
                      BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5), blurRadius: 12, spreadRadius: 1.5),
                      BoxShadow(color: const Color(0xFFA78BFA).withValues(alpha: 0.25), blurRadius: 18, spreadRadius: 3),
                    ],
            ),
            child: aiIconAsset != null
                ? ClipOval(child: SvgPicture.asset(aiIconAsset, width: 32, height: 32, fit: BoxFit.cover,
                    colorFilter: c.isLight ? null : const ColorFilter.mode(Color(0xFFC4B5FD), BlendMode.srcATop)))
                : const Center(child: Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12))),
          ),
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

  /// API 未配置时的引导气泡
  Widget _buildApiConfigPrompt(bool isLight) {
    final c = AppColors(isLight);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.chatBubbleAi,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.divider),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('配置 API', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 6),
              Text('AI 助手需要配置 API 才能使用。', style: TextStyle(fontSize: 13, color: c.text, height: 1.5)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  showDialog(context: context, builder: (_) => const ChatSettingsDialog());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.settings_outlined, size: 14, color: c.primary),
                    const SizedBox(width: 4),
                    Text('是否前往配置', style: TextStyle(fontSize: 12, color: c.primary, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ]),
          )),
        ]),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 显示考试确认对话框
  void _showExamConfirmDialog() {
    final s = _state;
    if (s.currentExamPaper == null) {
      _examDialogShowing = false;
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ExamConfirmDialog(state: s),
    ).then((_) {
      _examDialogShowing = false;
    });
  }

  Widget _buildChatBubble(ChatMessage msg, bool isLight) {
    final c = AppColors(isLight);
    final isUser = msg.role == 'user';
    final aiIconAsset = _getAiIconAsset(_state.effectiveChatConfig.model);
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
          // 思考过程（可折叠）
          if (msg.reasoning != null && msg.reasoning!.isNotEmpty && msg.showReasoning) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.primaryBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.primaryBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => msg.reasoningExpanded = !msg.reasoningExpanded),
                    child: Row(children: [
                      Icon(
                        msg.reasoningExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                        size: 14,
                        color: c.primaryText.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 2),
                      Text('思考过程', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c.primaryText)),
                    ]),
                  ),
                  if (msg.reasoningExpanded) ...[
                    const SizedBox(height: 4),
                    Text(msg.reasoning!, style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 1.5)),
                  ],
                ],
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
    // AI 气泡：左侧带图标头像
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 28,
        height: 28,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
          gradient: aiIconAsset == null ? c.primaryGradient : null,
          color: aiIconAsset != null ? null : c.primary,
          shape: BoxShape.circle,
          boxShadow: c.isLight
              ? null
              : [
                  BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.48), blurRadius: 10, spreadRadius: 1),
                  BoxShadow(color: const Color(0xFFA78BFA).withValues(alpha: 0.22), blurRadius: 15, spreadRadius: 2),
                ],
        ),
        child: aiIconAsset != null
            ? ClipOval(child: SvgPicture.asset(aiIconAsset, width: 28, height: 28, fit: BoxFit.cover,
                colorFilter: c.isLight ? null : const ColorFilter.mode(Color(0xFFC4B5FD), BlendMode.srcATop)))
            : const Center(child: Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10))),
      ),
      const SizedBox(width: 8),
      Expanded(child: bubble),
    ]);
  }

  /// 简易 Markdown 解析：支持 **粗体**、*斜体*、~~删除线~~、`行内代码`、标题、列表、代码块、引用、链接
  TextSpan _parseMarkdown(String text, Color textColor) {
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
      final orderedMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(line);
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
    // 匹配顺序：~~删除线~~ > **粗体** > *斜体* > `代码` > [链接](url)
    final patterns = <RegExp>[
      RegExp(r'~~(.+?)~~'),
      RegExp(r'\*\*(.+?)\*\*'),
      RegExp(r'\*(.+?)\*'),
      RegExp(r'`([^`]+)`'),
      RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
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

  void _scrollChatToBottom() {
    if (_chatScrollCtrl.hasClients) {
      _chatScrollCtrl.animateTo(
        _chatScrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
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

  /// 通过文件选择器选取图片作为待发送附件
  Future<void> _pickChatImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final dataUrl = 'data:image/${_imageMime(f.name)};base64,${base64Encode(bytes)}';
      setState(() => _chatImageData = dataUrl);
    } catch (_) {
      // 选择失败忽略
    }
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
    if (msg.isEmpty && img == null) return;
    if (text == null) _chatCtrl.clear();
    setState(() => _chatImageData = null);
    await s.sendChat(msg, imageData: img);
    // 发送完成后检查是否需要弹出考试确认对话框（全卷生成成功后）
    if (mounted && s.examPendingConfirm && s.currentExamPaper != null && !_examDialogShowing) {
      _examDialogShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _state.examPendingConfirm && _state.currentExamPaper != null) {
          _showExamConfirmDialog();
        } else {
          _examDialogShowing = false;
        }
      });
    }
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

// ===== "更多功能"独立选择页面（桌面/手机自适应） =====
class _MoreSelectPage extends StatelessWidget {
  final int currentIndex;
  final void Function(int index) onSelect;
  const _MoreSelectPage({required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    final crossCount = isMobile ? 2 : 3;
    final aspectRatio = isMobile ? 1.0 : 2.4;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32, isMobile ? 12 : 24, isMobile ? 16 : 32, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 标题区
          Row(children: [
            Container(
              width: isMobile ? 36 : 44,
              height: isMobile ? 36 : 44,
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Icon(Icons.apps_rounded, color: Colors.white, size: isMobile ? 20 : 24),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('更多功能', style: TextStyle(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.w800, color: c.text)),
              const SizedBox(height: 2),
              Text('选择你需要的工具', style: TextStyle(fontSize: isMobile ? 11.5 : 13, color: c.textTertiary)),
            ]),
          ]),
          SizedBox(height: isMobile ? 16 : 24),
          // 功能网格
          Expanded(
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossCount,
                mainAxisSpacing: isMobile ? 10 : 14,
                crossAxisSpacing: isMobile ? 10 : 14,
                childAspectRatio: aspectRatio,
              ),
              itemCount: _moreItemsData.length,
              itemBuilder: (ctx, i) {
                final item = _moreItemsData[i];
                return _MoreCard(
                  icon: item.$1,
                  title: item.$2,
                  subtitle: item.$3,
                  selected: currentIndex == item.$4,
                  isLight: c.isLight,
                  isMobile: isMobile,
                  onTap: () => onSelect(item.$4),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _MoreCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool isLight;
  final bool isMobile;
  final VoidCallback onTap;
  const _MoreCard({required this.icon, required this.title, required this.subtitle, required this.selected, required this.isLight, required this.isMobile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors(isLight);
    // 手机端：纵向布局（图标在上，文字在下）
    if (isMobile) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: selected ? c.primaryGradient : null,
              color: selected ? null : c.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? Colors.transparent : c.divider),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: selected ? LinearGradient(colors: [Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.1)]) : c.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : c.text)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : c.textTertiary), overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      );
    }
    // 桌面端：横向布局（图标在左，文字在右）
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: selected ? c.primaryGradient : null,
            color: selected ? null : c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? Colors.transparent : c.divider),
            boxShadow: selected ? [BoxShadow(color: c.primary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))] : null,
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: selected ? LinearGradient(colors: [Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.1)]) : c.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: selected ? Colors.white : c.text)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12, color: selected ? Colors.white70 : c.textTertiary), overflow: TextOverflow.ellipsis),
            ])),
            if (selected)
              Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.check_circle_rounded, size: 20, color: Colors.white.withValues(alpha: 0.9))),
          ]),
        ),
      ),
    );
  }
}

/// 全局背景层：纯色（浅色纯白 / 深色纯深灰，无光斑无渐变旋涡）
class _AppGlassBackground extends StatelessWidget {
  final AppColors colors;
  const _AppGlassBackground({required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.appBgGradientTop),
      child: const SizedBox.expand(),
    );
  }
}
