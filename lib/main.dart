/// SmartEnglish 智能英语学习 - Flutter Windows 桌面版 (afloat 风格)
library;

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:window_manager/window_manager.dart';
import 'state.dart';
import 'theme_colors.dart';
import 'widgets/learn_page.dart';
import 'widgets/pages.dart';
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
];

// 更多功能选择页索引
const _morePageIndex = 9;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isWindows) {
    await windowManager.ensureInitialized();
  }
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
  // 0 学习 1 答题 2 学习报告 3 查询 | 更多: 4 题库 5 错题本 6 生词本 7 答题记录 8 默写
  int _page = 0;
  bool _lastDarkMode = false;

  @override
  void initState() {
    super.initState();
    _state.addListener(_onState);
    _init();
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
    if (_isWindows) {
      if (_state.fullscreen) {
        windowManager.setFullScreen(true);
      } else {
        windowManager.setFullScreen(false);
      }
    }
    // 根据省电模式调整帧率
    _updateFrameRate();
    setState(() {});
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
    _state.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'afloat',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: _state.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: Focus(
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
              : _state.uiMode.isEmpty
                  ? PlatformSelectPage(
                      onDesktop: () => _state.setUiMode('desktop'),
                      onMobile: () => _state.setUiMode('mobile'),
                    )
                  : _state.uiMode == 'desktop'
                      ? Scaffold(
                          body: Row(children: [
                            _buildSidebar(),
                            Expanded(child: ListenableBuilder(listenable: _state, builder: (ctx, _) => _buildMainContent())),
                          ]),
                        )
                      : _buildMobileLayout(),
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: kPrimary, brightness: brightness);
    final isLight = brightness == Brightness.light;
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, fontFamilyFallback: const ['Microsoft YaHei', 'Segoe UI']);
    return base.copyWith(
      scaffoldBackgroundColor: isLight ? kBgLight : const Color(0xFF1A1A2E),
      splashFactory: InkRipple.splashFactory,
      cardTheme: CardThemeData(
        elevation: 0,
        color: isLight ? Colors.white : null,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: isLight ? const Color(0x0D000000) : Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight ? Colors.white : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF5F3FF) : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPrimary, width: 1.5),
        ),
        hintStyle: TextStyle(fontSize: 13, color: isLight ? Colors.grey.shade400 : Colors.grey.shade600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kPrimary,
          side: const BorderSide(color: Color(0x337C3AED)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide(color: isLight ? const Color(0x1A7C3AED) : Colors.white24)),
          textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12.5)),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          visualDensity: VisualDensity.compact,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: isLight ? const Color(0x0D000000) : Colors.white12, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: isLight ? const Color(0xE6262B3A) : const Color(0xE6E8EAEF), borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(fontSize: 12, color: isLight ? Colors.white : Colors.black87),
        waitDuration: const Duration(milliseconds: 400),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? kBgLight : null,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }

  // ===== 左侧导航栏 =====
  Widget _buildSidebar() {
    return Builder(builder: (context) {
      final isLight = Theme.of(context).brightness == Brightness.light;
      const mainItems = [
        (Icons.home_rounded, '学习', 0),
        (Icons.quiz_rounded, '答题', 1),
        (Icons.insights_rounded, '学习报告', 2),
        (Icons.search_rounded, '查询', 3),
      ];
      final inMore = _page >= 4;
      final inSubFeature = _page >= 4 && _page <= 8;
      final moreTitle = inSubFeature ? _moreItemsData.firstWhere((e) => e.$4 == _page).$2 : '更多功能';
      final moreIcon = inSubFeature ? _moreItemsData.firstWhere((e) => e.$4 == _page).$1 : Icons.apps_rounded;
      return Container(
        width: 200,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF1E1E32),
          border: Border(right: BorderSide(color: isLight ? const Color(0x0D000000) : Colors.white.withValues(alpha: 0.06))),
        ),
        child: Column(children: [
          const SizedBox(height: 24),
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('afloat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
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
                      color: Colors.grey.shade500,
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
                  onTap: () => setState(() => _page = item.$3),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      gradient: _page == item.$3 ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kNavGradientStart, kNavGradientEnd]) : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _page == item.$3 ? [BoxShadow(color: kPrimary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))] : null,
                    ),
                    child: Row(children: [
                      Icon(item.$1, size: 20, color: _page == item.$3 ? Colors.white : Colors.grey.shade500),
                      const SizedBox(width: 12),
                      Text(item.$2, style: TextStyle(fontSize: 14, fontWeight: _page == item.$3 ? FontWeight.w700 : FontWeight.w500, color: _page == item.$3 ? Colors.white : Colors.grey.shade600)),
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
                onTap: () => setState(() => _page = _morePageIndex),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    gradient: inMore ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kNavGradientStart, kNavGradientEnd]) : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: inMore ? [BoxShadow(color: kPrimary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))] : null,
                  ),
                  child: Row(children: [
                    Icon(moreIcon, size: 20, color: inMore ? Colors.white : Colors.grey.shade500),
                    const SizedBox(width: 12),
                    Expanded(child: Text(moreTitle, style: TextStyle(fontSize: 14, fontWeight: inMore ? FontWeight.w700 : FontWeight.w500, color: inMore ? Colors.white : Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: inMore ? Colors.white70 : Colors.grey.shade400),
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
                  Icon(Icons.settings_outlined, size: 20, color: Colors.grey.shade500),
                  const SizedBox(width: 12),
                  Text('设置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade600)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ]),
      );
    });
  }

  // ===== 主内容区 =====
  Widget _buildMainContent() {
    return Row(children: [
      // 中间内容区（70%）
      Expanded(
        flex: 7,
        child: Column(children: [
          _buildTopBar(),
          Expanded(child: _buildPage()),
        ]),
      ),
      // 右侧 AI 对话助手（30%）— 独立监听，避免流式输出时全应用重建
      Expanded(
        flex: 3,
        child: ListenableBuilder(
          listenable: _state.chatUpdateNotifier,
          builder: (ctx, _) => _buildChatPanel(),
        ),
      ),
    ]);
  }

  // ===== 手机端布局 =====
  Widget _buildMobileLayout() {
    return ListenableBuilder(
      listenable: _state,
      builder: (ctx, _) {
        final isLight = Theme.of(ctx).brightness == Brightness.light;
        // 主导航：0学习 1答题 2报告 3更多(触发) 4查询
        const navItems = [
          (Icons.home_rounded, '学习', 0),
          (Icons.quiz_rounded, '答题', 1),
          (Icons.insights_rounded, '报告', 2),
          (Icons.apps_rounded, '更多', -1),
          (Icons.search_rounded, '查询', 3),
        ];
        final inMore = _page >= 4;
        final inSubFeature = _page >= 4 && _page <= 8;
        final navIndex = inMore ? 3 : (_page == 3 ? 4 : _page.clamp(0, 2));
        return Scaffold(
          backgroundColor: isLight ? kBgLight : const Color(0xFF1A1A2E),
          appBar: AppBar(
            backgroundColor: isLight ? Colors.white : const Color(0xFF1E1E32),
            elevation: 0,
            title: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              const Text('afloat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
            ]),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 20),
                onPressed: () => showDialog(context: ctx, builder: (_) => const SettingsDialog()),
              ),
            ],
          ),
          body: _buildPage(),
          bottomNavigationBar: NavigationBar(
            selectedIndex: navIndex,
            onDestinationSelected: (i) {
              if (navItems[i].$3 == -1) {
                setState(() => _page = _morePageIndex);
              } else {
                setState(() => _page = navItems[i].$3);
              }
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            backgroundColor: isLight ? Colors.white : const Color(0xFF1E1E32),
            indicatorColor: kPrimary.withValues(alpha: 0.12),
            destinations: [
              for (var i = 0; i < navItems.length; i++)
                NavigationDestination(
                  icon: Icon(navItems[i].$1, size: 22, color: (i == 3 ? inMore : navIndex == i) ? kPrimary : Colors.grey.shade500),
                  selectedIcon: Icon(navItems[i].$1, size: 22, color: kPrimary),
                  label: i == 3 && inSubFeature ? _moreItemsData.firstWhere((e) => e.$4 == _page).$2 : navItems[i].$2,
                ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showMobileChatSheet(ctx),
            backgroundColor: kPrimary,
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
          ),
        );
      },
    );
  }

  // ===== 手机端更多功能底部弹出面板 =====（已改为独立页面 _MoreSelectPage）

  void _showMobileChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            // 拖拽指示器
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            // 头部
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, size: 14, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Text('AI 对话助手', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.settings_outlined, size: 18, color: Colors.grey.shade500),
                  tooltip: '对话设置',
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    showDialog(context: context, builder: (_) => const ChatSettingsDialog());
                  },
                ),
              ]),
            ),
            const Divider(height: 1),
            // 消息列表
            Expanded(
              child: ListenableBuilder(
                listenable: _state.chatUpdateNotifier,
                builder: (ctx, _) {
                  final s = _state;
                  final isLight = Theme.of(context).brightness == Brightness.light;
                  final modelName = s.effectiveChatConfig.model.isEmpty ? 'GPT-5.1' : s.effectiveChatConfig.model;
                  final localAiIconAsset = _getAiIconAsset(modelName);
                  if (s.chatHistory.isEmpty) {
                    final levelName = s.selectedLevel.isEmpty ? '高中' : s.selectedLevel;
                    final typeName = s.selectedType.isEmpty ? '综合' : s.selectedType;
                    return _buildChatWelcome(isLight, modelName, levelName, typeName, localAiIconAsset);
                  }
                  return ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: s.chatHistory.length,
                    itemBuilder: (ctx, i) => _buildChatBubble(s.chatHistory[i], isLight),
                  );
                },
              ),
            ),
            // 输入框
            Container(
              padding: EdgeInsets.fromLTRB(16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _chatCtrl,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '输入你的问题...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Theme.of(context).brightness == Brightness.light ? const Color(0xFFF5F3FF) : const Color(0xFF2A2A40),
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
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
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
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3))),
      ),
      child: const Row(children: [
        Spacer(),
      ]),
    );
  }

  Widget _buildPage() {
    switch (_page) {
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
      case _morePageIndex:
        return _MoreSelectPage(currentIndex: _page, onSelect: (idx) => setState(() => _page = idx));
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
    if (lower.contains('glm') || lower.contains('chatglm') || lower.contains('zhipu')) return 'assets/ai-icons/chatglm.svg';
    if (lower.contains('qwen') || lower.contains('千问') || lower.contains('通义')) return 'assets/ai-icons/qwen.svg';
    if (lower.contains('deepseek') || lower.contains('deep-seek')) return 'assets/ai-icons/deepseek.svg';
    if (lower.contains('gemini') || lower.contains('google')) return 'assets/ai-icons/gemini.svg';
    if (lower.contains('doubao') || lower.contains('豆包')) return 'assets/ai-icons/doubao.svg';
    if (lower.contains('minimax') || lower.contains('minimax')) return 'assets/ai-icons/minimax.svg';
    if (lower.contains('step') || lower.contains('阶跃') || lower.contains('stepfun')) return 'assets/ai-icons/stepfun.svg';
    return null;
  }

  // ===== 右侧 AI 对话助手面板 =====
  Widget _buildChatPanel() {
    final s = _state;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final modelName = s.effectiveChatConfig.model;
    final levelName = {'cet4': '四级', 'zsb': '专升本', 'easy': '简单', 'medium': '中等', 'hard': '困难'}[s.selectedLevel] ?? s.selectedLevel;
    final typeName = {'translation': '翻译题', 'reading': '阅读理解', 'grammar': '语法填空', 'choice': '选择题', 'writing': '写作题', 'mixed': '综合套卷'}[s.selectedType] ?? s.selectedType;
    final aiIconAsset = _getAiIconAsset(modelName);
    return Container(
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFFDFBFF) : const Color(0xFF1E1E32),
        border: Border(left: BorderSide(color: isLight ? const Color(0x0D000000) : Colors.white.withValues(alpha: 0.06))),
      ),
      child: Column(children: [
        // 头部
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            // AI 头像（自动识别模型图标，未识别则显示默认 AI 文字）
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: aiIconAsset == null ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]) : null,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: aiIconAsset != null
                  ? ClipOval(child: SvgPicture.asset(aiIconAsset, width: 36, height: 36, fit: BoxFit.cover))
                  : const Center(child: Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(modelName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
                const SizedBox(width: 6),
                Text('v3.5', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: kSuccess, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('已连线，随时解答答疑', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ]),
            ])),
            // 刷新按钮
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 18, color: Colors.grey.shade500),
              tooltip: '清空对话',
              onPressed: () => s.clearChat(),
            ),
            // 设置按钮
            Builder(builder: (btnCtx) => IconButton(
              icon: Icon(Icons.tune_rounded, size: 18, color: Colors.grey.shade500),
              tooltip: '对话设置',
              onPressed: () => showDialog(context: btnCtx, builder: (_) => const ChatSettingsDialog()),
            )),
          ]),
        ),
        // 当前关联考题提示
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF3EEFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(Icons.link_rounded, size: 14, color: kPrimary.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Expanded(child: Text('当前关联考题: [$levelName $typeName]', style: TextStyle(fontSize: 11.5, color: kPrimary.withValues(alpha: 0.8)))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('实时同步', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: kPrimary.withValues(alpha: 0.8))),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // 消息列表
        Expanded(
          child: s.chatHistory.isEmpty
              ? _buildChatWelcome(isLight, modelName, levelName, typeName, aiIconAsset)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: s.chatHistory.length,
                  itemBuilder: (ctx, i) => _buildChatBubble(s.chatHistory[i], isLight),
                ),
        ),
        // 快捷问题（仅无消息时显示）
        if (s.chatHistory.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              _QuickQuestion(text: '这道题如何拿满分？', onTap: () => _sendChat(s, text: '这道题如何拿满分？')),
              const SizedBox(height: 6),
              _QuickQuestion(text: '拆解句中的高频考点词', onTap: () => _sendChat(s, text: '拆解句中的高频考点词')),
            ]),
          ),
        ],
        // 输入框
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '输入你的问题...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  filled: true,
                  fillColor: isLight ? const Color(0xFFF5F3FF) : const Color(0xFF2A2A40),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendChat(s),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: IconButton(
                icon: s.chatSending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                onPressed: s.chatSending ? null : () => _sendChat(s),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildChatWelcome(bool isLight, String modelName, String levelName, String typeName, String? aiIconAsset) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 快捷助手功能标题
        Align(alignment: Alignment.centerLeft, child: Text('快捷助手功能', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade700))),
        const SizedBox(height: 12),
        // 2x2 功能卡片网格
        Row(children: [
          Expanded(child: _ChatFeatureCard(icon: Icons.lightbulb_outline_rounded, iconBg: const Color(0xFFFFF3E0), iconColor: const Color(0xFFFF9800), title: '深度讲解', subtitle: '拆解语法解题逻辑', onTap: () => _sendChat(_state, text: '请深度讲解这道题的语法和解题逻辑'))),
          const SizedBox(width: 10),
          Expanded(child: _ChatFeatureCard(icon: Icons.edit_note_rounded, iconBg: const Color(0xFFE8F5E9), iconColor: const Color(0xFF4CAF50), title: '作文智能批改', subtitle: '优化高级词汇句型', onTap: () => _sendChat(_state, text: '请帮我批改这篇作文，优化高级词汇和句型'))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _ChatFeatureCard(icon: Icons.translate_rounded, iconBg: const Color(0xFFE3F2FD), iconColor: const Color(0xFF2196F3), title: '词汇解析', subtitle: '派生词与近义辨析', onTap: () => _sendChat(_state, text: '请解析这句话中的核心词汇，包括派生词和近义词辨析'))),
          const SizedBox(width: 10),
          Expanded(child: _ChatFeatureCard(icon: Icons.trending_up_rounded, iconBg: const Color(0xFFFCE4EC), iconColor: const Color(0xFFE91E63), title: '错题推荐', subtitle: '根据薄弱点精准推题', onTap: () => _sendChat(_state, text: '根据我的错题记录，推荐针对性的练习题'))),
        ]),
        const SizedBox(height: 20),
        // AI 欢迎消息
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: aiIconAsset == null ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]) : null,
              shape: BoxShape.circle,
            ),
            child: aiIconAsset != null
                ? ClipOval(child: SvgPicture.asset(aiIconAsset, width: 32, height: 32, fit: BoxFit.cover))
                : const Center(child: Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isLight ? Colors.white : const Color(0xFF2A2A40),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: const Color(0x0A000000), blurRadius: 4, offset: const Offset(0, 1))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hi Liam! 我是你的 AI 备考 Copilot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isLight ? const Color(0xFF1A1A2E) : Colors.white)),
              const SizedBox(height: 6),
              Text('我已经为你匹配了【$levelName $typeName】练习范本，随时为你进行点拨解析。', style: TextStyle(fontSize: 13, color: isLight ? const Color(0xFF1A1A2E) : Colors.white, height: 1.5)),
            ]),
          )),
        ]),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildChatBubble(ChatMessage msg, bool isLight) {
    final isUser = msg.role == 'user';
    final aiIconAsset = _getAiIconAsset(_state.effectiveChatConfig.model);
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color: isUser ? kPrimary : (isLight ? Colors.white : const Color(0xFF2A2A40)),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: const Color(0x0A000000), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 思考过程
          if (msg.reasoning != null && msg.reasoning!.isNotEmpty && msg.showReasoning) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.psychology_outlined, size: 12, color: kPrimary.withValues(alpha: 0.7)),
                    const SizedBox(width: 4),
                    Text('思考过程', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kPrimary.withValues(alpha: 0.8))),
                  ]),
                  const SizedBox(height: 4),
                  Text(msg.reasoning!, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          // 消息内容
          if (msg.content.isNotEmpty)
            Text(msg.content, style: TextStyle(fontSize: 13, color: isUser ? Colors.white : (isLight ? const Color(0xFF1A1A2E) : Colors.white), height: 1.5))
          else if (msg.role == 'ai')
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: isLight ? kPrimary : Colors.white)),
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
          gradient: aiIconAsset == null ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]) : null,
          shape: BoxShape.circle,
        ),
        child: aiIconAsset != null
            ? ClipOval(child: SvgPicture.asset(aiIconAsset, width: 28, height: 28, fit: BoxFit.cover))
            : const Center(child: Text('AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 9))),
      ),
      const SizedBox(width: 8),
      Expanded(child: bubble),
    ]);
  }

  final TextEditingController _chatCtrl = TextEditingController();

  void _sendChat(AppState s, {String? text}) async {
    final msg = text ?? _chatCtrl.text.trim();
    if (msg.isEmpty) return;
    if (text == null) _chatCtrl.clear();
    await s.sendChat(msg);
  }
}

class _ChatFeatureItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  const _ChatFeatureItem({required this.icon, required this.iconBg, required this.iconColor, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x0D000000)),
        boxShadow: [BoxShadow(color: const Color(0x05000000), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
        ])),
      ]),
    );
  }
}

// 2x2 网格功能卡片
class _ChatFeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _ChatFeatureCard({required this.icon, required this.iconBg, required this.iconColor, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x0D000000)),
          boxShadow: [BoxShadow(color: const Color(0x05000000), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 3),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3EEFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED))),
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
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    return Column(children: [
      Padding(
        padding: isMobile ? const EdgeInsets.fromLTRB(16, 8, 16, 6) : const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(title, style: TextStyle(fontSize: isMobile ? 17 : 20, fontWeight: FontWeight.bold)),
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
    final isLight = Theme.of(context).brightness == Brightness.light;
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
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
                borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
                boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Icon(Icons.apps_rounded, color: Colors.white, size: isMobile ? 20 : 24),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('更多功能', style: TextStyle(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.w800, color: isLight ? const Color(0xFF1A1A2E) : Colors.white)),
              const SizedBox(height: 2),
              Text('选择你需要的工具', style: TextStyle(fontSize: isMobile ? 11.5 : 13, color: Colors.grey.shade500)),
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
                  isLight: isLight,
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
    // 手机端：纵向布局（图标在上，文字在下）
    if (isMobile) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: selected ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kNavGradientStart, kNavGradientEnd]) : null,
              color: selected ? null : (isLight ? const Color(0xFFF8F6FF) : const Color(0xFF2A2A40)),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selected ? Colors.transparent : (isLight ? const Color(0x0D000000) : Colors.white.withValues(alpha: 0.06))),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: selected ? LinearGradient(colors: [Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.1)]) : const LinearGradient(colors: [kGradientStart, kGradientEnd]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 22, color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: selected ? Colors.white : (isLight ? const Color(0xFF1A1A2E) : Colors.white))),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : Colors.grey.shade500), overflow: TextOverflow.ellipsis),
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
            gradient: selected ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kNavGradientStart, kNavGradientEnd]) : null,
            color: selected ? null : (isLight ? const Color(0xFFF8F6FF) : const Color(0xFF2A2A40)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? Colors.transparent : (isLight ? const Color(0x0D000000) : Colors.white.withValues(alpha: 0.06))),
            boxShadow: selected ? [BoxShadow(color: kPrimary.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))] : null,
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: selected ? LinearGradient(colors: [Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.1)]) : const LinearGradient(colors: [kGradientStart, kGradientEnd]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 24, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: selected ? Colors.white : (isLight ? const Color(0xFF1A1A2E) : Colors.white))),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12, color: selected ? Colors.white70 : Colors.grey.shade500), overflow: TextOverflow.ellipsis),
            ])),
            if (selected)
              Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.check_circle_rounded, size: 20, color: Colors.white.withValues(alpha: 0.9))),
          ]),
        ),
      ),
    );
  }
}
