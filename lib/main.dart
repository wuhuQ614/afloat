/// SmartEnglish 智能英语学习 - Flutter Windows 桌面版 (afloat 风格)
library;

import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'dart:io' show File, FileMode, Platform, Directory, Process, ProcessStartMode;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' show FontFeature, PlatformDispatcher;
import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'services/api_service.dart';
import 'package:window_manager/window_manager.dart';
import 'state.dart';
import 'models.dart';
import 'services/tts_service.dart';
import 'services/chat_capabilities.dart';
import 'services/knowledge_base.dart';
import 'theme_colors.dart';
import 'theme_diy.dart';
import 'widgets/diy_backdrop.dart';
import 'widgets/learn_page.dart';
import 'widgets/grammar_page.dart';
import 'widgets/onboarding_page.dart';
import 'widgets/pages.dart';
import 'widgets/exam_page.dart';
import 'widgets/dev_console.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/update_dialog.dart';
import 'widgets/platform_select_page.dart';
import 'widgets/timetable_page.dart';
import 'widgets/glass_background.dart';
import 'widgets/code_card.dart';
import 'widgets/chart_card.dart';
import 'widgets/maimemo_wordbook_page.dart';
import 'widgets/browser_page.dart';
import 'widgets/snake_game_page.dart';
import 'widgets/gomoku_page.dart';
import 'widgets/minesweeper_page.dart';
import 'widgets/source_viewer_page.dart';
import 'widgets/agent_rows.dart';
import 'widgets/multi_expert_page.dart';
import 'widgets/debate_page.dart';
import 'pages/mail_page.dart';

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
  (Icons.grid_3x3_rounded, '五子棋', '双人对战五子连珠', 23),
  (Icons.grid_on_rounded, '扫雷', '微软经典玩法复刻', 28),
  (Icons.forum_outlined, '辩论模式', '两个模型正反方对辩', 26),
  (Icons.groups_outlined, '多专家团', '解析·执行·验证协作', 25),
  (Icons.email_outlined, '邮箱', '收发邮件/写信', 27),
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

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // ===== 沉浸全屏：让 Flutter 渐变背景延伸到状态栏后面 =====
  // 顶部不再有系统那一条突兀的纯色横带，主界面顶部直接是极光渐变。
  // 状态栏图标深色（适配浅色渐变背景），与 MainActivity.kt 的
  // WindowCompat.setDecorFitsSystemWindows 配合实现真正的 edge-to-edge。
  if (!_isWindows) {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }
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
  runApp(SmartEnglishApp(launchUrl: _extractLaunchUrl(args)));
}

/// 从命令行参数提取要打开的 URL（Windows 默认浏览器以 `afloat.exe "https://..."` 形式唤起）。
/// 兼容 `--` 前缀与裸 URL；非 URL 参数返回 null。
String? _extractLaunchUrl(List<String> args) {
  if (args.isEmpty) return null;
  for (final raw in args) {
    final a = raw.trim();
    if (a.isEmpty) continue;
    final url = a.startsWith('"') && a.endsWith('"') && a.length >= 2
        ? a.substring(1, a.length - 1)
        : a;
    final lower = url.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) return url;
    if (lower.startsWith('mailto:')) return url;
    if (lower.startsWith('afloat://')) return 'https://${url.substring(9)}';
  }
  return null;
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

  /// 历史会话项：极简（参考 deepseek）—— 只有标题文字，
  /// active 态：浅底 + 右侧 "..." 菜单；hover 态：浅底 + 右侧 "..." 菜单。
  /// 没有图标、没有副标、没有删除按钮直接露出。
  class _SessionItem extends StatefulWidget {
    final String title;
    final bool isActive;
    final Color activeBg;
    final Color hoverBg;
    final Color textPrimary;
    final Color textTertiary;
    final Color accent;
    final VoidCallback onTap;
    final VoidCallback onMore;
    const _SessionItem({
      required this.title,
      required this.isActive,
      required this.activeBg,
      required this.hoverBg,
      required this.textPrimary,
      required this.textTertiary,
      required this.accent,
      required this.onTap,
      required this.onMore,
    });
    @override
    State<_SessionItem> createState() => _SessionItemState();
  }

  class _SessionItemState extends State<_SessionItem> {
    bool _hovered = false;

    @override
    Widget build(BuildContext context) {
      // 背景：active 一直显示底色；hover 浅底；默认透明
      final showBg = widget.isActive || _hovered;
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: widget.accent.withValues(alpha: 0.10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              decoration: BoxDecoration(
                color: showBg
                    ? (widget.isActive ? widget.activeBg : widget.hoverBg)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // 标题（单行 ellipsis）
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 15,
                      color: widget.textPrimary,
                      fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w500,
                      height: 1.3,
                      // 显式关闭下划线：兜底覆盖路由/DefaultTextStyle 透出来的 decoration
                      decoration: TextDecoration.none,
                      decorationColor: Colors.transparent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 右侧：active/hover 时显示 "..." 菜单按钮。
                // 必须始终占位 28px，否则 hover 时 _MoreChip 突然出现会挤压标题可用宽度，
                // 引发 ellipsis 重算 → 文字"抽搐"跳动。
                Visibility(
                  visible: showBg,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  maintainSemantics: false,
                  maintainInteractivity: false,
                  child: _MoreChip(
                    onTap: widget.onMore,
                    hoverBg: widget.accent.withValues(alpha: 0.10),
                    iconColor: widget.textTertiary,
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }
  }

  /// "..." 菜单小按钮：纯图标，hover 浅紫底
  class _MoreChip extends StatefulWidget {
    final VoidCallback onTap;
    final Color hoverBg;
    final Color iconColor;
    const _MoreChip({required this.onTap, required this.hoverBg, required this.iconColor});
    @override
    State<_MoreChip> createState() => _MoreChipState();
  }

  class _MoreChipState extends State<_MoreChip> {
    bool _hovered = false;
    @override
    Widget build(BuildContext context) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverBg : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.more_horiz_rounded, size: 18, color: widget.iconColor),
          ),
        ),
      );
    }
  }

/// 圆形轻量 icon 按钮：透明底 + hover 浅底，统一用于关闭/删除等次级操作
// _IconChip / _SearchField 已移除（历史版本中保留，现不再使用）

class SmartEnglishApp extends StatefulWidget {
  const SmartEnglishApp({super.key, this.launchUrl});

  /// 启动时携带的 URL（Windows 被设为默认浏览器后，外部链接以此唤起）
  final String? launchUrl;

  @override
  State<SmartEnglishApp> createState() => _SmartEnglishAppState();
}

class _SmartEnglishAppState extends State<SmartEnglishApp> {
  final AppState _state = AppState();
  bool _ready = false;
  // 页面索引已上提到 AppState.page（0 学习 1 答题 2 学习报告 3 查询 | 更多: 4 题库 5 错题本 6 生词本 7 答题记录 8 默写）
  bool _lastDarkMode = false;
  bool _lastFullscreen = false;
  /// 决定根页面结构的字段快照（用于 _onState 判断是否需要重建 MaterialApp）
  bool _lastOnboarded = false;
  String _lastAppMode = '';
  String _lastUiMode = '';
  bool _lastGlass = false;
  int _lastPage = 0;
  bool _lastAgentFullscreen = false;
  bool _lastDevMode = false;
  /// 手机端浏览器页是否临时显示底部导航栏
  bool _showBrowserNav = false;
  Timer? _browserNavTimer;
  /// 各聊天按钮的 GlobalKey，用于从按钮位置浮出对应面板
  final GlobalKey _modelSelectorBtnKey = GlobalKey();
  final GlobalKey _plusBtnKey = GlobalKey();
  final GlobalKey _contextRingKey = GlobalKey();
  final GlobalKey _permissionBtnKey = GlobalKey();
  /// Root Navigator 句柄，用于切换 uiMode 前清空浮层/modal
  final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();

  // R5: Markdown 解析 RegExp 提升为 static final，避免每次重建新建
  static final _reStrikethrough = RegExp(r'~~(.+?)~~');
  static final _reBold = RegExp(r'\*\*(.+?)\*\*');
  static final _reItalic = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final _reInlineCode = RegExp(r'`([^`]+)`');
  static final _reLink = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final _reOrderedList = RegExp(r'^(\d+)\.\s+(.*)$');
  // R7: 表格解析（| col1 | col2 | + |---|---| 分隔行）
  // R38: 尾 `|` 可选——模型常省略数据行尾管道（如 `| word | pos. → 释义`），
  // 此前要求强制 `\|$` 会让这类行无法被识别为表格行，触发"表格 0 数据行"bug
  // （_parseTableRow 内部已经 substring 兼容无尾管道，正则无需重复约束）。
  static final _reTableRow = RegExp(r'^\s*\|.+\|?\s*$');
  static final _reTableSeparator = RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)+\|?\s*$');
  // R14: 水平分割线（--- 或 *** 或 ___）：3 个及以上相同字符即可，
  // 旧正则要求 ≥5 个字符，导致模型最常用的 "---" 显示为字面文本
  static final _reHorizontalRule = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
  // R19: 反斜杠转义（\* \` \~ 等输出字面符号）——AI 教 markdown 语法本身时必需，
  // 否则 \`代码\` 会被行内代码正则错误配对（空芯片 + 悬空反引号）
  static final _reEscape = RegExp(r'\\([\\`*_{}\[\]()#+\-.!~>|])');
  // R8: 行内数学公式 $...$：两端 $ 紧邻非空字符，且不与 $$ 块语法混淆
  static final _reInlineMath = RegExp(r'\$(?!\$)(\S(?:[^$\n]*?\S)?)\$(?!\$)');
  // R5: Markdown 解析缓存（按 内容+颜色 失效；R29: 键改用完整文本字符串——
  // 旧版 int 哈希键存在碰撞可能，碰撞时会把别的消息的缓存渲染到当前消息上，
  // 表现为"发出去的文字/AI 回复间歇性空白"）
  final Map<String, TextSpan> _markdownCache = {};
  // R6: 滚动节流：记录上次滚动时间
  int _lastScrollTime = 0;

  @override
  void initState() {
    super.initState();
    // 初始化模式字段快照：_state.init() 异步加载后会与初值不同，
    // _onState 据此触发一次重建（此时 _ready 已 true，直接渲染正确分支）
    _lastOnboarded = _state.onboardingDone;
    _lastAppMode = _state.appMode;
    _lastUiMode = _state.uiMode;
    _lastGlass = _state.isGlassUI;
    _lastDarkMode = _state.darkMode;
    _lastFullscreen = _state.fullscreen;
    _lastPage = _state.page;
    _lastAgentFullscreen = _state.agentFullscreen;
    _lastDevMode = _state.devMode;
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
    // 外部 URL 唤起：写入 pendingBrowserUrl 并跳转浏览器页（page 19）
    final url = widget.launchUrl;
    if (url != null && url.isNotEmpty) {
      _state.pendingBrowserUrl = url;
      _state.browserNavSeq++;
      _state.setPage(19);
    }
    // 初始化帧率
    _updateFrameRate();
    // 启动 6 秒后静默检查在线更新：有新版才弹窗，网络失败/已是最新则完全无感知
    unawaited(Future<void>.delayed(const Duration(seconds: 6), () {
      if (mounted) UpdateDialog.checkAndShow(context);
    }));
  }

  /// 状态监听：只在「影响根页面结构/窗口状态的字段」变化时才 setState 重建 MaterialApp。
  /// AI 流式输出、词汇剖析进度、课程表 30s 定时刷新等高频通知一律不重建根树——
  /// 子树内部已有各自的 ListenableBuilder 做细粒度刷新。
  void _onState() {
    if (!mounted) return;
    var needRebuild = false;
    if (_state.darkMode != _lastDarkMode) {
      _lastDarkMode = _state.darkMode;
      needRebuild = true;
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
      needRebuild = true;
    }
    // 以下 4 个字段决定根页面树结构（加载页 / 引导页 / 课程表 / 学习模式），
    // 变化时重建——两个模式页面由此按需构造：切走即销毁，不会同时加载
    if (_state.onboardingDone != _lastOnboarded) {
      _lastOnboarded = _state.onboardingDone;
      needRebuild = true;
    }
    if (_state.appMode != _lastAppMode) {
      _lastAppMode = _state.appMode;
      needRebuild = true;
    }
    if (_state.uiMode != _lastUiMode) {
      _lastUiMode = _state.uiMode;
      needRebuild = true;
    }
    if (_state.isGlassUI != _lastGlass) {
      _lastGlass = _state.isGlassUI;
      needRebuild = true;
    }
    // devMode：控制全局开发者控制台挂载/卸载（位于根 Stack，需根树重建）
    if (_state.devMode != _lastDevMode) {
      _lastDevMode = _state.devMode;
      needRebuild = true;
    }
    // page / agentFullscreen：决定"浏览器页/考场全屏独占、隐藏侧边栏"与"专注全屏"布局分支，
    // 该判定位于子树 ListenableBuilder 之外，需根树重建才生效（均为用户点击级低频变化）
    if (_state.page != _lastPage) {
      _lastPage = _state.page;
      needRebuild = true;
    }
    if (_state.agentFullscreen != _lastAgentFullscreen) {
      _lastAgentFullscreen = _state.agentFullscreen;
      needRebuild = true;
    }
    // 根据省电模式调整帧率
    _updateFrameRate();
    // 离开浏览器页后重置临时导航栏状态
    if (_state.page != 19 && _showBrowserNav) {
      _showBrowserNav = false;
      _browserNavTimer?.cancel();
      needRebuild = true;
    }
    if (needRebuild) setState(() {});
  }

  static const _frameRateChannel = MethodChannel('com.smartenglish/framerate');

  void _updateFrameRate() {
    // 帧率策略：
    // - 电脑端（Windows）：跟随显示器刷新率，165Hz 屏即 165fps——Flutter 桌面端
    //   垂直同步渲染，无程序化锁帧通道，不做任何限制；
    // - 手机端：省电模式锁 60；其余状态一律不锁帧（fps=0，交还系统自适应，
    //   高刷屏跑满 120/144Hz）。曾默认锁 120，高刷屏（144Hz 等）会被压帧，
    //   毛玻璃等特效主题下感知尤其明显，故移除默认上限。
    if (_isWindows) return;
    final targetFps = _state.powerSavingMode ? 60 : 0;
    _frameRateChannel.invokeMethod('setFrameRate', {'fps': targetFps});
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
    // R31: 预解码常用模型图标——避免首条消息流式重建时图标解码空窗
    for (final m in const ['glm-4.6v', 'deepseek-v4-flash', 'kimi-k2', 'qwen3-max', 'gpt-4o']) {
      final a = _getAiIconAsset(m);
      if (a != null) precacheImage(AssetImage(a), context);
    }
    // 注意：此处不监听 _state 重建 MaterialApp——状态变化由 _onState 按字段判断是否需要
    // setState（AI 流式输出等高频通知不会重建整棵树），模式页面也只在切换时才构造
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'AFloat',
        debugShowCheckedModeBanner: false,
        navigatorKey: _rootNavKey,
        // 中文本地化（showDatePicker 等 Material 组件需注册后才能用 zh locale）
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: _state.darkMode ? ThemeMode.dark : ThemeMode.light,
        home: Builder(builder: (context) {
          final c = AppColors.of(context);
          // 背景层分域：毛玻璃主题的蓝色渐隐背景全场景保留，但分两种形态——
          // 引导页：动态极光（呼吸漂移）；主界面（桌面/手机/课程表）：同一幅画的
          // 静态帧（不启动 Ticker、画一次后缓存）。此前主界面每帧全屏重绘 +
          // 壳层全屏 BackdropFilter 连带重模糊是卡顿根源；静态帧视觉不变、零逐帧开销。
          // 非 glass 主题（经典/深色/高性能）仍为纯色实底。
          return Stack(children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: _AppGlassBackground(
                  colors: c,
                  isGlass: _state.isGlassUI,
                  animated: !_state.onboardingDone,
                  diyBackdrop: _state.diyBackdropOf(_state.diyCurrentTarget),
                  animateAllowed: !_state.powerSavingMode && !_state.highPerformanceMode,
                ),
              ),
            ),
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
                        // 课程表模式：与英语学习完全独立的两大模式，整树切换
                        : _state.appMode == 'timetable'
                            ? KeyedSubtree(
                                key: const ValueKey('timetable'),
                                child: TimetablePage(state: _state),
                              )
                            : _state.uiMode.isEmpty
                            ? PlatformSelectPage(
                                onDesktop: () => _switchUiMode('desktop'),
                                onMobile: () => _switchUiMode('mobile'),
                              )
                            : _state.uiMode == 'desktop'
                                ? KeyedSubtree(
                                    key: const ValueKey('english_desktop'),
                                    child: Scaffold(
                                    // 浏览器页（19）与考场/游戏一样全屏独占：隐藏侧边栏与 AI 对话栏
                                    // 内容区不再包 _state ListenableBuilder：内部已用 pageNotifier
                                    // 细粒度控制，AI 流式输出等高频通知不会连带重建学习/答题页
                                    body: (_state.page == 10 || _state.page == 11 || _state.page == 20 || _state.page == 19 || _state.page == 28)
                                        ? _buildMainContent()
                                        : (_state.agentFullscreen
                                            // R14: 专注全屏：图标导航栏 + 全宽聊天页（可带侧边浏览器）
                                            ? ListenableBuilder(
                                                listenable: Listenable.merge([_state, _state.sideBrowserNotifier]),
                                                builder: (ctx, _) {
                                                  final fc = AppColors(!_state.darkMode);
                                                  return Row(children: [
                                                    _buildAgentRail(),
                                                    Expanded(flex: 5, child: _buildChatPanel(fullscreen: true)),
                                                    // 全屏模式下同样支持侧边浏览器面板（默认关闭）
                                                    if (_state.sideBrowserOpen)
                                                      Expanded(
                                                        flex: 4,
                                                        child: Container(
                                                          decoration: BoxDecoration(
                                                            border: Border(left: BorderSide(color: fc.divider)),
                                                          ),
                                                          child: BrowserPage(onClose: () => _state.toggleSideBrowser(open: false)),
                                                        ),
                                                      ),
                                                  ]);
                                                },
                                              )
                                            : Row(children: [
                                                _buildSidebar(),
                                                Expanded(child: _buildMainContent()),
                                              ])),
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
            // 全局"等待用户选择"弹窗宿主（墨墨导出格式选择 / 跨工作区授权等）
            AgentPromptHost(state: _state),
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
      // scaffold 透明：由根部全局背景层承接底色（引导页=动态极光；主界面=静态实底）
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
        style: diyToButtonStyle(
          _state.effectiveButtonStyleOf(_state.diyCurrentTarget),
          primary: seedColor,
          onPrimary: Colors.white,
          foreground: seedColor,
          isLight: isLight,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: diyToButtonStyle(
          _state.effectiveButtonStyleOf(_state.diyCurrentTarget),
          primary: seedColor,
          onPrimary: Colors.white,
          foreground: seedColor,
          isLight: isLight,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: diyToButtonStyle(
          _state.effectiveButtonStyleOf(_state.diyCurrentTarget).copyWith(
                // 描边按钮无论主样式如何，底色必须透明、文字用主色，
                // 否则"描边"语义会在全局失效（变成实底一片）
                fill: DiyButtonFill.outline,
              ),
          primary: seedColor,
          onPrimary: Colors.white,
          foreground: seedColor,
          isLight: isLight,
          fontSize: 13,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: diyToButtonStyle(
          _state.effectiveButtonStyleOf(_state.diyCurrentTarget).copyWith(
                fill: DiyButtonFill.ghost,
                borderWidth: 0,
              ),
          primary: seedColor,
          onPrimary: Colors.white,
          foreground: seedColor,
          isLight: isLight,
          fontSize: 13,
        ).copyWith(
          padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12)),
          minimumSize: WidgetStateProperty.all(Size(0, _state
              .effectiveButtonStyleOf(_state.diyCurrentTarget)
              .height)),
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
      final inSubFeature = page >= 4 && (page <= 8 || (page >= 12 && page <= 17) || page == 18 || page == 19 || page == 20 || page == 21 || page == 22 || page == 23 || page == 24 || page == 25 || page == 26 || page == 27 || page == 28);
      const moreTitle = '更多功能';
      const moreIcon = Icons.grid_view_outlined;
      final isGlass = _state.isGlassUI;
      return RepaintBoundary(
        child: Container(
          width: 200,
          decoration: BoxDecoration(
            // 玻璃模式：半透明染色即可，不再挂 BackdropFilter——背景层已换
            // 静态实底，对纯色背景做高斯模糊没有视觉意义，侧栏重绘时还要
            // 全高重跑模糊，纯耗性能
            color: isGlass ? null : c.sidebar,
            gradient: isGlass ? glassTintGradient(c.sidebar, _state.darkMode ? 0.5 : 0.55) : null,
            border: Border(right: BorderSide(color: c.divider)),
          ),
          child: _buildSidebarContent(c, page, mainItems, inMore, inSubFeature, moreTitle, moreIcon, context),
        ),
      );
      },
    );
  }

  /// R14: 专注全屏模式的图标导航栏（无文字，悬停 tooltip），同侧栏一套页面。
  /// 点击导航项 = 退出全屏并跳转（全屏视图只有聊天，导航是回到正常界面的快捷通道）。
  Widget _buildAgentRail() {
    final c = AppColors.of(context);
    final page = _state.page;
    final isGlass = _state.isGlassUI;
    const railItems = [
      (Icons.home_outlined, '学习', 0),
      (Icons.help_outline, '答题', 1),
      (Icons.bar_chart_rounded, '学习报告', 2),
      (Icons.search_outlined, '查询', 3),
    ];
    Widget railBtn(IconData icon, String tip, bool selected, VoidCallback onTap) {
      return Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: selected ? c.primary.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 22, color: selected ? c.primary : c.textTertiary),
          ),
        ),
      );
    }

    void exitAndGo(int target) {
      if (_state.agentFullscreen) _state.toggleAgentFullscreen();
      _state.setPage(target);
    }

    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: isGlass ? c.sidebar.withValues(alpha: 0.4) : c.sidebar,
        border: Border(right: BorderSide(color: c.divider)),
      ),
      child: Column(children: [
        const SizedBox(height: 18),
        for (final it in railItems)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: railBtn(it.$1, it.$2, page == it.$3, () => exitAndGo(it.$3)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: railBtn(Icons.grid_view_outlined, '更多功能', page >= 4, () => exitAndGo(_morePageIndex)),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: railBtn(
            Icons.settings_outlined,
            '设置',
            false,
            // R21: 用 rootNavKey 的 context 弹窗——本组件的 context 在 MaterialApp
            // 上方，Navigator.of 找不到路由导致点击设置无反应
            () {
              final navCtx = _rootNavKey.currentContext;
              if (navCtx != null) {
                showDialog(context: navCtx, builder: (_) => const SettingsDialog());
              }
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildSidebarContent(AppColors c, int page, List mainItems, bool inMore, bool inSubFeature, String moreTitle, IconData moreIcon, BuildContext context) {
    final isGlass = _state.isGlassUI;
    return Column(children: [
          const SizedBox(height: 24),
          // 主题胶囊已隐藏（用户要求移除左上角主题切换入口；切换改由设置页完成）
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
  /// 页面切换动画：轻量淡入 + 微上移（220ms），避免生硬跳变。
  /// 以 page 索引为 key，切换时旧页淡出、新页淡入。
  Widget _animatedPage() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      // 旧页立即移除（不播淡出），避免切换时闪现上一个页面的内容
      reverseDuration: Duration.zero,
      switchInCurve: Curves.easeOut,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(_state.page), child: _buildPage()),
    );
  }

  /// 内容区：只监听 pageNotifier（切页才重建布局），AI 流式输出等高频
  /// notifyListeners 不会连带重建学习/答题页面，右侧对话面板自行细粒度刷新
  Widget _buildMainContent() {
    final c = AppColors(!_state.darkMode);
    return ListenableBuilder(
      // 同时监听切页与侧边浏览器开关，两侧任一变化都重建布局
      listenable: Listenable.merge([_state.pageNotifier, _state.sideBrowserNotifier]),
      builder: (ctx, _) {
        final isGlass = _state.isGlassUI;
        // 考场/游戏/浏览器沉浸模式（page==10/11/20/19）：隐藏 AI 对话栏（右侧30%），内容独占
        // page==25 多专家团：自身就是多角色对话页，右侧再挂 AI 对话栏没有意义，同样独占
        if (_state.page == 10 || _state.page == 11 || _state.page == 20 || _state.page == 19 || _state.page == 25 || _state.page == 28) {
          return Row(children: [
            Expanded(child: _animatedPage()),
          ]);
        }
        // 内容区（玻璃模式半透明染色 / 普通实底）
        final contentArea = isGlass
            ? Container(
                decoration: BoxDecoration(
                  gradient: glassTintGradient(c.bg, _state.darkMode ? 0.45 : 0.5),
                ),
                child: _animatedPage(),
              )
            : _animatedPage();
        // 右侧 AI 对话助手 — 监听 darkMode + chatUpdate，避免流式输出时全应用重建
        final chatPanel = ListenableBuilder(
          listenable: _state,
          builder: (ctx2, _) => ListenableBuilder(
            listenable: _state.chatUpdateNotifier,
            builder: (ctx3, _) => _buildChatPanel(),
          ),
        );
        // 侧边浏览器开启：内容区/聊天栏/浏览器按 5:2:3 分配
        if (_state.sideBrowserOpen) {
          return Row(children: [
            Expanded(flex: 5, child: contentArea),
            Expanded(flex: 2, child: chatPanel),
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.divider)),
                ),
                child: BrowserPage(onClose: () => _state.toggleSideBrowser(open: false)),
              ),
            ),
          ]);
        }
        return Row(children: [
          // 中间内容区（70%）
          Expanded(flex: 7, child: contentArea),
          // 右侧 AI 对话助手（30%）
          Expanded(flex: 3, child: chatPanel),
        ]);
      },
    );
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
        final inMore = _state.page >= 4 || _state.page == 3;
        final navIndex = inMore ? 3 : (_state.page == 3 ? 4 : _state.page.clamp(0, 2));
        final isGlass = _state.isGlassUI;
        // R29: 顶栏与内容区同底色——此前顶栏用 sidebar 色、内容区玻璃染色用 bg 色，
        // 两个色相上下相接形成明显的颜色接缝
        final glassBg = c.bg;
        return Scaffold(
          // 始终透明：根 Stack 最底层已有全局背景层兜底，Scaffold 再铺白底会在
          // 悬浮导航栏后露出一截白色残带（页面内容区有自己的背景色不受影响）
          backgroundColor: Colors.transparent,
          // body 延伸到导航栏之后：玻璃染色层连续覆盖全屏，否则 bottomNavigationBar
          // 槽位露出未染色的玻璃底层，与 body 之间会出现一条锋利的色差接缝
          extendBody: true,
          // 手机端顶部不再有 AppBar 容器——避免顶部"白色挡板"；
          // 右上角的设置入口改放 body Stack 右上角（绝对定位），内容由 SafeArea 顶开状态栏
          appBar: null,
          // body 外层 SafeArea(top:true) 兜住状态栏空间——删 AppBar 后，
          // 主页内容（LearnPage 等）顶部不再被刘海遮挡；bottom:false 让导航栏仍能紧贴底部
          body: Stack(children: [
            // 玻璃染色层铺满全屏：edge-to-edge 下覆盖到状态栏后面，
            // 顶部与主界面无缝同色，不再露出一截底色分界线
            if (isGlass)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: glassTintGradient(c.bg, _state.darkMode ? 0.4 : 0.45),
                  ),
                ),
              ),
            SafeArea(
              top: true,
              bottom: false,
              child: Stack(children: [
                Positioned.fill(
                  child: Builder(builder: (bctx) => Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(bctx).padding.bottom),
                    child: _animatedPage(),
                  )),
                ),
              // 右上角"三点"设置入口（取代原 AppBar.actions）：半透明胶囊底，
              // 绝对定位、外层 SafeArea 已 top:true 自动避开状态栏；不占 AppBar 高度→顶部不再有白色挡板
              Positioned(
                top: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6, top: 4),
                  child: _NavPressFeedback(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => showDialog(context: ctx, builder: (_) => const SettingsDialog()),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.isLight
                            ? Colors.white.withValues(alpha: 0.55)
                            : const Color(0xFF141418).withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.more_horiz_rounded, size: 20, color: c.textSecondary),
                    ),
                  ),
                ),
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
              : _buildCoolApkNavBar(ctx, c, navIndex, inMore),
        );
      },
    );
  }

  // ===== 手机端底部导航（酷安 V16 悬浮胶囊风格）=====
  // 特征：悬浮圆角胶囊条（毛玻璃半透明底 + 顶部高光）+ 图标/文字标签 tab +
  // 中央大厂蓝 AI 按钮 + 滑动椭圆选中指示器（切换时胶囊在 tab 间平滑滑动）。
  Widget _buildCoolApkNavBar(BuildContext ctx, AppColors c, int navIndex, bool inMore) {
    // (选中图标, 未选中图标, 页面索引, 标签)；-1 = 打开更多页
    const tabs = [
      (Icons.home_rounded, Icons.home_outlined, 0, '学习'),
      (Icons.quiz_rounded, Icons.quiz_outlined, 1, '答题'),
      (Icons.insights_rounded, Icons.insights_outlined, 2, '报告'),
      (Icons.widgets_rounded, Icons.widgets_outlined, -1, '更多'),
    ];
    // 当前选中落在哪个 tab（更多页/查词页时高亮最后一个 tab）
    final selectedTab = inMore ? 3 : switch (navIndex) {
      0 => 0,
      1 => 1,
      2 => 2,
      _ => -1,
    };
    // 毛玻璃：玻璃模式下实时模糊；高性能模式退化为高不透明度实底。
    // 底色 alpha 极低（0.18/0.28）——导航栏彻底悬浮在主页面之上，主页卡片/背景可从胶囊
    // 透过来看到，酷安 V16 风格；之前 0.55/0.7 仍形成"挡板"挡住主页面底部内容
    final useBlur = _state.isGlassUI && !_state.highPerformanceMode;
    final barColor = c.isLight
        ? Colors.white.withValues(alpha: useBlur ? 0.18 : 0.28)
        : const Color(0xFF141418).withValues(alpha: useBlur ? 0.18 : 0.28);

    Widget tabItem(int i, (IconData, IconData, int, String) tab) {
      final selected = selectedTab == i;
      final color = selected ? kPrimary : c.textTertiary;
      return Expanded(
        child: _NavPressFeedback(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            final page = tab.$3;
            if (page < 0) {
              _state.setPage(_morePageIndex);
            } else {
              _state.setPage(page);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Icon(
                  selected ? tab.$1 : tab.$2,
                  key: ValueKey(selected),
                  size: 22,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tab.$4,
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ]),
          ),
        ),
      );
    }

    const barHeight = 62.0;
    final bar = LayoutBuilder(builder: (ctx, cons) {
      // 5 个等宽槽位（tab0 / tab1 / 中央AI / tab2 / tab3），椭圆指示器在槽位间滑动
      final slotW = cons.maxWidth / 5;
      const pillH = 44.0;
      final pillW = (slotW - 12).clamp(48.0, 84.0);
      // selectedTab(0-3) → 槽位（0,1,3,4；槽位 2 是中央按钮）
      final slot = switch (selectedTab) { 0 => 0, 1 => 1, 2 => 3, 3 => 4, _ => -1 };
      return Stack(children: [
        // 滑动椭圆选中指示器（灰色液态玻璃：半透明渐变 + 细描边 + 顶部高光）
        AnimatedPositioned(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          left: slot < 0 ? slotW / 2 - pillW / 2 : slot * slotW + (slotW - pillW) / 2,
          // 略微上移：视觉上与图标主体重心对齐（居中会显得偏下）
          top: (barHeight - pillH) / 2 - 3,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: slot < 0 ? 0 : 1,
            child: Container(
              width: pillW,
              height: pillH,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: c.isLight
                      ? [Colors.black.withValues(alpha: 0.055), Colors.black.withValues(alpha: 0.02)]
                      : [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.04)],
                ),
                border: Border.all(color: c.isLight ? Colors.black.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.16), width: 1),
                boxShadow: [
                  // 顶部内高光：液态玻璃的"受光"感
                  BoxShadow(color: Colors.white.withValues(alpha: c.isLight ? 0.60 : 0.12), blurRadius: 0, spreadRadius: 0, offset: const Offset(0, -0.5)),
                ],
              ),
            ),
          ),
        ),
        Row(children: [
          tabItem(0, tabs[0]),
          tabItem(1, tabs[1]),
          // 中央 AI 助手按钮（酷安"+"位）：大厂蓝圆角方块
          _NavPressFeedback(
            pressedScale: 0.88,
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showMobileChatSheet(ctx),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                width: 54,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Colors.white),
              ),
            ),
          ),
          tabItem(2, tabs[2]),
          tabItem(3, tabs[3]),
        ]),
      ]);
    });

    final barShell = Container(
      height: barHeight,
      decoration: BoxDecoration(
        color: barColor,
        borderRadius: BorderRadius.circular(999),
        // 边框几乎隐去（0.18）——之前 0.6 形成明显"胶囊外壳"挡板感；
        // 不彻底删是为了在浅色背景上保留极淡的轮廓以让胶囊有形
        border: Border.all(color: c.divider.withValues(alpha: 0.18)),
        // 不再画 boxShadow：阴影是"挡板感"主因，去掉后导航栏真正贴合背景
        boxShadow: const [],
      ),
      child: Stack(children: [
        // 液态玻璃顶部高光：一条自上而下渐隐的白色柔光
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white.withValues(alpha: c.isLight ? 0.5 : 0.08), Colors.white.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
        ),
        bar,
      ]),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          // 玻璃模式启用实时背景模糊（酷安 V16 同款高斯模糊底）
          child: BackdropFilter(
            enabled: useBlur,
            filter: glassBlurFilter(sigma: 18),
            child: barShell,
          ),
        ),
      ),
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
        // R15: 专注全屏时对话面板满宽（ListenableBuilder 驱动宽度实时切换）
        return ListenableBuilder(
          listenable: _state,
          builder: (ctx, _) {
            final w = MediaQuery.of(ctx).size.width;
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: _state.agentFullscreen ? w : w * 0.92,
                child: _buildMobileChatContent(context),
              ),
            );
          },
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
              // 头部（未配置 AI 时隐藏头像，仅保留标题与操作）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(children: [
                  if (cfg.ready) ...[
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
                  ],
                  Text(modelName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
                  const Spacer(),
                  // R29: 历史对话（移动端此前没有入口）
                  IconButton(
                    icon: const Icon(Icons.space_dashboard_rounded, size: 18, color: Color(0xFFADADB8)),
                    tooltip: '历史对话',
                    onPressed: () => _showHistoryPicker(ctx, c, _state),
                  ),
                  // R15: 专注全屏切换（全屏时对话面板满宽）
                  IconButton(
                    icon: Icon(
                      _state.agentFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      size: 18,
                      color: c.textTertiary,
                    ),
                    tooltip: _state.agentFullscreen ? '退出专注全屏' : '专注全屏',
                    onPressed: () => _state.toggleAgentFullscreen(),
                  ),
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
                    final scrollCtrl = _mobileChatScrollCtrl;
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
                          return _buildChatBubble(s.chatHistory[i], c.isLight, running: isTail, msgIndex: i);
                        }
                        return AgentDeepDivingRow(accent: c.primary, light: c.isLight);
                      },
                    );
                  },
                ),
              ),
              // R29: 上下文占用已由输入栏圆环承担，移除旧式分布长条
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
      case 21:
        return const SourceViewerPage();
      case 23:
        return const _PageScaffold(title: '五子棋', child: GomokuPage());
      case 28:
        // 扫雷沉浸模式：不套 _PageScaffold，页面自身就是完整游戏界面
        return const MinesweeperPage();
      case 25:
        return const _PageScaffold(title: '多专家团', child: MultiExpertPage());
      case 26:
        return const _PageScaffold(title: '辩论模式', child: DebatePage());
      case 27:
        return const MailPage();
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
    if (lower.contains('glm') || lower.contains('chatglm') || lower.contains('zhipu') || lower.contains('智谱')) return 'assets/ai-icons/glm.png';
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
  /// PNG 是彩色位图（如 GLM / Kimi 官方 logo），原样渲染，不着色。
  Widget _aiLogo(String model, {double size = 30}) {
    final asset = _getAiIconAsset(model);
    final (c1, _) = _aiBrandColors(model);
    final brand = _state.darkMode ? Color.lerp(c1, Colors.white, 0.35)! : c1;
    if (asset == null) return Icon(Icons.smart_toy_outlined, size: size * 0.8, color: brand);
    return asset.toLowerCase().endsWith('.png')
        ? Image.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            // R31: 流式高频重建时不闪烁；资产异常时回退通用图标（不渲染空白）
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Icon(Icons.smart_toy_outlined, size: size * 0.8, color: brand),
          )
        : SvgPicture.asset(
            asset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            color: brand,
          );
  }

  // ===== 右侧 AI 对话助手面板 =====
  /// [fullscreen] 专注全屏模式：去掉左侧分割线，整体内容限宽 980 居中——
  /// 否则头部按钮与输入条会被拉到整屏两端（全屏 UI 适配的核心）。
  Widget _buildChatPanel({bool fullscreen = false}) {
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
  Widget panelContent(BuildContext panelCtx) => fullscreen
      ? Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: _buildChatPanelContent(panelCtx, c, s, cfg, modelName, levelName, typeName, aiIconAsset, fullscreen: true),
          ),
        )
      : _buildChatPanelContent(panelCtx, c, s, cfg, modelName, levelName, typeName, aiIconAsset);
    // RepaintBoundary：聊天面板处于流式重建区，隔离重绘
    return RepaintBoundary(
      child: DropTarget(
      onDragDone: (details) => _setChatImageFromFiles(details.files),
      child: isGlass
        // 玻璃模式：半透明染色即可（背景层为静态实底，无需 BackdropFilter）
        ? Container(
            decoration: BoxDecoration(
              gradient: glassTintGradient(c.sidebar, s.darkMode ? 0.4 : 0.45),
              border: fullscreen ? null : Border(left: BorderSide(color: c.divider)),
            ),
            child: Builder(builder: (panelCtx) => panelContent(panelCtx)),
          )
        : Container(
        decoration: BoxDecoration(
          // 透明：让全局玻璃背景层透出
          color: Colors.transparent,
          border: fullscreen ? null : Border(left: BorderSide(color: c.divider)),
        ),
        child: Builder(builder: (panelCtx) => panelContent(panelCtx)),
      ),
      ),
    );
  }

  Widget _buildChatPanelContent(BuildContext ctx, AppColors c, AppState s, dynamic cfg, String modelName, String levelName, String typeName, String? aiIconAsset, {bool fullscreen = false}) {
    return Column(children: [
          // 头部（AI 头像 + 标题 + 操作按钮）— 透明背景 + 底部分割线
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(bottom: BorderSide(color: c.divider)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (cfg.ready == true) ...[
                _aiLogo(modelName, size: 30),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(modelName, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              // R14: 专注全屏切换（纯净聊天视图，保留图标导航栏）
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(
                  s.agentFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                  size: 18,
                  color: c.textTertiary,
                ),
                tooltip: s.agentFullscreen ? '退出专注全屏' : '专注全屏',
                onPressed: () => s.toggleAgentFullscreen(),
              ),
              // R12: 工作区选择已移入输入框左下角；头部仅保留清空与历史对话
              IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(Icons.refresh_rounded, size: 18, color: c.textTertiary),
                tooltip: '清空对话',
                onPressed: () => s.clearChat(),
              ),
              // R12: 历史对话移到最右（原「对话设置」位置，设置入口已移除）
              Builder(builder: (hsCtx) => IconButton(
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                icon: Icon(Icons.space_dashboard_rounded, size: 18, color: c.textTertiary),
                tooltip: '历史对话',
                onPressed: () => _showHistoryPicker(hsCtx, c, s),
              )),
              // 侧边浏览器：对话栏右侧滑出内嵌浏览器面板（普通布局与专注全屏均支持）
                IconButton(
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  icon: Icon(Icons.public_rounded, size: 18, color: s.sideBrowserOpen ? c.primary : c.textTertiary),
                  tooltip: s.sideBrowserOpen ? '关闭侧边浏览器' : '打开侧边浏览器',
                  onPressed: () => s.toggleSideBrowser(),
                ),
            ]),
          ),
        // R32: 旧式「上下文分布」长条已删除——占用情况统一由输入栏圆环承担（含全屏）
        const SizedBox(height: 8),
        // 消息列表（专注全屏下限宽 920 居中，避免大屏文字拉满整行影响阅读）
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
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
                              return _buildChatBubble(s.chatHistory[i], c.isLight, running: isTail, msgIndex: i);
                            }
                            return AgentDeepDivingRow(accent: c.primary, light: c.isLight);
                          },
                        );
                      },
                    ),
            ),
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
            // 未配置 API 的引导头像：用 DeepSeek 品牌图标，不用"AI"文字占位
            _aiLogo('deepseek', size: 32),
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

  Widget _buildChatBubble(ChatMessage msg, bool isLight, {bool running = false, int? msgIndex}) {
    final c = AppColors(isLight);
    final isUser = msg.role == 'user';
    // R22: 用户消息悬停显示 复制/编辑（编辑=从该条截断对话并回填输入框重发）
    void editMessage() {
      if (msgIndex == null) return;
      _chatCtrl.text = msg.content;
      _chatCtrl.selection = TextSelection.collapsed(offset: _chatCtrl.text.length);
      _state.truncateConversationAt(msgIndex);
    }
    // AI 消息操作栏动作：复制 / 编辑（截断本条并回填上一条用户消息）/ 重试（截断本条并自动重发）
    Future<void> copyAiMessage() async {
      await Clipboard.setData(ClipboardData(text: msg.content));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制', style: TextStyle(fontSize: 12.5)),
            behavior: SnackBarBehavior.floating,
            duration: Duration(milliseconds: 1200),
          ),
        );
      }
    }
    void editAiMessage() {
      final idx = msgIndex;
      if (idx == null || msg.role != 'ai') return;
      String? prevUser;
      for (var i = idx - 1; i >= 0; i--) {
        if (_state.chatHistory[i].role == 'user') {
          prevUser = _state.chatHistory[i].content;
          break;
        }
      }
      _chatCtrl.text = prevUser ?? '';
      _chatCtrl.selection = TextSelection.collapsed(offset: _chatCtrl.text.length);
      _state.truncateConversationAt(idx);
    }
    void retryAiMessage() {
      final idx = msgIndex;
      if (idx == null || msg.role != 'ai') return;
      _state.retryChatAt(idx);
    }
    // R21: 系统提示消息（如压缩对话生成的【早期对话摘要】）渲染为细长通知条——
    // 此前按普通 AI 气泡渲染（带模型头像+名称），压缩后看起来像"对话凭空消失、AI 自言自语"
    if (msg.role == 'system') {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.compress_rounded, size: 14, color: c.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  msg.content,
                  style: TextStyle(fontSize: 12, height: 1.5, color: c.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // R34: 主流 AI 对话样式——AI 回复不再用气泡包裹（去白底/边框/内边距），
    // 文字与上方头像左缘齐平；用户消息保留气泡
    // （模型名头行已按需求移除：AI 消息不再显示 logo+模型名，正文直接顶格）
    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: isUser ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10) : EdgeInsets.zero,
      constraints: isUser ? const BoxConstraints(maxWidth: 280) : null,
      decoration: isUser
          ? BoxDecoration(
              color: c.chatBubbleAi,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.divider),
            )
          : null,
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
                      // imageBytes 可能为 null（base64 损坏/空 data URL）：用灰块兜底，
                      // 避免 `imageBytes!` 非空断言崩溃 → 整条消息渲染成空白占位
                      child: msg.imageBytes != null
                          ? Image.memory(msg.imageBytes!, width: 168, height: 120, fit: BoxFit.cover)
                          : Container(
                              width: 168,
                              height: 120,
                              color: Colors.grey.shade300,
                              child: const Center(
                                child: Icon(Icons.broken_image_outlined, size: 26, color: Colors.grey),
                              ),
                            ),
                    ),
                  ),
            const SizedBox(height: 8),
          ],
          // 消息内容（支持 Markdown 渲染）——R18: 基础行距 1.5，正文更接近对话流排版
          if (msg.content.isNotEmpty)
            Text.rich(
              _parseMarkdown(msg.content, c.text, streaming: running),
              style: TextStyle(fontSize: 14, height: 1.5, color: c.text),
            )
          else if (msg.role == 'ai')
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primaryText)),
        ],
      ),
    );
    if (isUser) {
      return _UserBubbleHover(
        content: msg.content,
        msgIndex: msgIndex,
        onEdit: msgIndex == null ? null : editMessage,
        light: isLight,
        // R26: 移动端没有悬停，长按气泡呼出操作按钮
        tapToggles: _state.uiMode == 'mobile',
        child: Align(alignment: Alignment.centerRight, child: bubble),
      );
    }
    // Agent 过程步骤（思考行 / 工具行 / 终端块）放在气泡外、气泡上方，
    // 全宽无容器展示（仿 deepseek-harness：步骤不属于消息正文）。
    final hasReasoning = msg.showReasoning &&
        ((msg.reasoning?.isNotEmpty ?? false) || msg.reasoningSegs.any((s) => s.text.trim().isNotEmpty));
    final hasSteps = msg.toolSteps.isNotEmpty;
    final hasStatus = running && !isUser && (msg.statusLabel ?? '').isNotEmpty;
    if (!hasReasoning && !hasSteps) {
      if (hasStatus) {
        // 后续轮决策间隙：状态行（"思考下一步（第 N 轮）…"）+ 转圈
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _statusRow(msg, isLight),
          bubble,
        ]);
      }
      // 首轮流式决策期间（"正在分析请求"已按需求移除）：
      // 无思考/步骤/正文时不渲染任何内容，等首个 token 到达正文自然顶格出现
      if (running && msg.content.isEmpty) return const SizedBox.shrink();
      if (running) return bubble;
      // AI 消息生成完成：气泡下方常驻操作栏（复制/编辑/重试/输出 token 统计）
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        bubble,
        _AiBubbleActionBar(
          msg: msg,
          msgIndex: msgIndex,
          light: isLight,
          onCopy: copyAiMessage,
          onEdit: editAiMessage,
          onRetry: retryAiMessage,
        ),
      ]);
    }
    // 内容尚未到达时（纯思考/工具阶段）不渲染空气泡
    final bool showBubble = msg.content.isNotEmpty || !running;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 运行状态行：流式决策期间告诉用户"现在到哪一步了"
      if (hasStatus) _statusRow(msg, isLight),
      if (msg.todoList.isNotEmpty) ...[
        AgentTodoList(items: msg.todoList, light: isLight),
        const SizedBox(height: 2),
      ],
      // R9: 工作流时间线：思考段（带时长）与工具步骤按轮次穿插（仿 coding-agent 过程流）
      // 「思考过程」折叠容器（仿 TraeWork）：运行中默认展开，结束自动收起，点击切换
      if (msg.showReasoning)
        _ThinkingFold(children: _buildAgentTimeline(msg, isLight, running), running: running, light: isLight),
      if (hasSteps) const SizedBox(height: 2),
      // dsh-tool-ask-user：弹问题让用户选。
      // 多轮提问按序堆叠展示，每轮独立 ValueKey：新一轮是全新 State，
      // 不会复用上一轮已折叠（_confirmed）的面板导致第二个问题无法显示
      for (final round in msg.askRounds) ...[
        AgentAskUserPanel(key: ValueKey(round.key), questions: round.questions, answers: round.answers, light: isLight),
        const SizedBox(height: 4),
      ],
      // dsh-plan-mode：提交计划让用户审批
      if (msg.plan != null) ...[
        AgentPlanPanel(plan: msg.plan!, light: isLight),
        const SizedBox(height: 4),
      ],
      if (showBubble) bubble,
      // AI 消息生成完成：气泡下方常驻操作栏（复制/编辑/重试/输出 token 统计）
      if (showBubble && !running)
        _AiBubbleActionBar(
          msg: msg,
          msgIndex: msgIndex,
          light: isLight,
          onCopy: copyAiMessage,
          onEdit: editAiMessage,
          onRetry: retryAiMessage,
        ),
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
  TextSpan _parseMarkdown(String text, Color textColor, {bool streaming = false}) {
    // 流式中的内容每帧变化，不进缓存
    if (streaming) {
      try {
        return _parseMarkdownImpl(_normalizeDashTables(text), textColor, streaming: true);
      } catch (e) {
        // 解析异常绝不吞内容：回退纯文本
        return TextSpan(text: text);
      }
    }
    // R29: 用完整文本做键（Map 字符串键深度相等，彻底避免哈希碰撞串显）
    final cacheKey = '$text\u0000${textColor.value}';
    final cached = _markdownCache[cacheKey];
    if (cached != null) return cached;
    TextSpan result;
    try {
      result = _parseMarkdownImpl(_normalizeDashTables(text), textColor);
    } catch (e) {
      // 解析异常兜底：整条回退纯文本，防止个别消息渲染失败导致"内容消失"
      result = TextSpan(text: text);
    }
    // 限制缓存大小，防止无限增长
    if (_markdownCache.length > 200) _markdownCache.clear();
    _markdownCache[cacheKey] = result;
    return result;
  }

  // R37: 无管道对齐表的识别（表头 + 「空格分隔的多段短横线」分隔行 + 空格对齐内容行）
  static final _reDashRowSep = RegExp(r'^\s*-{2,}(?:\s+-{2,})+\s*$');
  static final _reAlignSplit = RegExp(r'\s{2,}');
  // R38: 单空格也能切分——用于从分隔行推算列数、以及表头用单空格分隔时的 fallback。
  // 仅在「切分列数与分隔行列数一致」时才采信，避免把普通句子误判成表。
  static final _reAlignSplitAnySpace = RegExp(r'\s+');

  /// R37: 把模型常输出的"无管道空格对齐表"预处理成标准管道表，
  /// 复用既有表格渲染（此前这类表只被渲染成分割线 + 散落文本）。
  /// 围栏代码块内不做转换。
  String _normalizeDashTables(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    var inCode = false;
    var inDashTable = false;
    var tableCols = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('```')) {
        inCode = !inCode;
        out.add(line);
        continue;
      }
      if (inCode) {
        out.add(line);
        continue;
      }
      final t = line.trim();
      if (t.isEmpty) {
        inDashTable = false;
        out.add(line);
        continue;
      }
      if (!inDashTable && out.isNotEmpty && out.last.trim().isNotEmpty && !out.last.contains('|') && _reDashRowSep.hasMatch(line)) {
        // 上一行是表头（非空、非管道、非其他块级语法）→ 转成管道表头 + 分隔行。
        // R38: 分隔行的列数决定表头该怎么切。模型表头常只用「单个空格」分隔
        // （如 `单词 词性 释义`），而 _reAlignSplit 要求 2+ 空格 → 切出 1 列，
        // headerCells.length>=2 不成立，整张表退化为散落文本。
        // 此处先用多空格切，列数与分隔行不一致时退回单空格切分。
        final sepCols = t.split(_reAlignSplitAnySpace).length;
        var headerCells = out.last.trim().split(_reAlignSplit);
        if (headerCells.length != sepCols) {
          final single = out.last.trim().split(_reAlignSplitAnySpace);
          if (single.length == sepCols) headerCells = single;
        }
        // 列数仍与分隔行不一致 → 不是对齐表（可能是普通句子），退化为正常行。
        if (headerCells.length >= 2 && headerCells.length == sepCols) {
          inDashTable = true;
          tableCols = headerCells.length;
          out[out.length - 1] = '| ${headerCells.join(' | ')} |';
          out.add('|${List.filled(tableCols, ' --- ').join('|')}|');
          continue;
        }
      }
      if (inDashTable) {
        if (t.startsWith('#') || t.startsWith('>') || t.startsWith('```')) {
          inDashTable = false; // 表结束，当前行走正常解析
          out.add(line);
          continue;
        }
        // R38: 已是管道格式的数据行（模型混用「空格表头 + 管道数据行」）保持原样。
        // 此前这类行会被按空格切分并重拼，切出 `| | word | pos | |  |` 的嵌套管道错乱列。
        if (t.contains('|')) {
          out.add(line);
          continue;
        }
        final cells = t.split(_reAlignSplit).where((c) => c.isNotEmpty).toList();
        if (cells.isEmpty) {
          out.add('');
          continue;
        }
        while (cells.length < tableCols) {
          cells.add('');
        }
        out.add('| ${cells.take(tableCols).join(' | ')} |');
        continue;
      }
      out.add(line);
    }
    return out.join('\n');
  }

  TextSpan _parseMarkdownImpl(String text, Color textColor, {bool streaming = false}) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var inCodeBlock = false;
    String codeLang = '';
    final codeBuffer = <String>[];
    // R17: 上一行是否为块级组件（分割线/表格/公式/代码卡）——
    // 模型写 "---" 时习惯上下各留空行，而组件自带外边距，空行+边距会叠出
    // 60px+ 的大空洞，视觉上像"横线下面吞了内容"；组件后的单个空行直接折叠。
    var lastWasBlockWidget = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 代码块处理
      if (line.startsWith('```')) {
        if (inCodeBlock) {
          // R16: 可执行代码卡片（仿 Gemini/ChatGPT Canvas）：语法高亮 + 预览运行/复制/下载
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: chartAwareCodeBlock(codeBuffer.join('\n'), codeLang),
          ));
          codeBuffer.clear();
          inCodeBlock = false;
          codeLang = '';
          lastWasBlockWidget = true;
        } else {
          // 开始代码块（围栏语言决定卡片标题与运行方式）
          inCodeBlock = true;
          codeLang = line.length > 3 ? line.substring(3).trim() : '';
        }
        continue;
      }
      
      if (inCodeBlock) {
        codeBuffer.add(line);
        continue;
      }

      if (i > 0) {
        // R17: 块级组件后的单个空行折叠（组件自带外边距，不再叠加空行高度）
        if (lastWasBlockWidget && line.trim().isEmpty) {
          continue;
        }
        spans.add(const TextSpan(text: '\n'));
      }
      lastWasBlockWidget = false;

      // R8: 块级数学公式 $$...$$（单行闭合 / 独立 $$ 分隔的多行两种形态）
      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('\$\$')) {
        var body = trimmedLine.substring(2);
        var closed = false;
        if (body.endsWith('\$\$')) {
          // 单行闭合：$$公式$$
          body = body.substring(0, body.length - 2);
          closed = true;
        }
        if (!closed) {
          // 跨行：收集到闭合 $$ 或行尾带 $$ 的行为止（流式输出中未闭合也先渲染已有部分）
          final buf = <String>[];
          if (body.trim().isNotEmpty) buf.add(body);
          var j = i + 1;
          while (j < lines.length) {
            final l = lines[j].trim();
            if (l == '\$\$') {
              j++;
              break;
            }
            if (l.endsWith('\$\$') && l.length > 2) {
              buf.add(l.substring(0, l.length - 2));
              j++;
              break;
            }
            buf.add(lines[j]);
            j++;
          }
          body = buf.join('\n').trim();
          i = j - 1;
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildMathBlock(body, textColor),
        ));
        lastWasBlockWidget = true;
        continue;
      }

      // R7: 水平分割线（--- / *** / ___）
      // R47: HR 必须独立成行。原实现（R17）会移除前面的换行符，把 HR 占位符
      // 内联拼在上一行文字尾部，完全依赖 Flutter 自动换行把横线挤到下一行——
      // 占位行高在这种内联形态下计算不稳定，部分行宽/字体组合会把后续文本
      // 挤出可视区（表现为"横线下面内容看不见"）。改为确保占位符前有且仅有
      // 一个换行：横线独占一行，后续文本从新行开始，布局确定性 100%。
      if (_reHorizontalRule.hasMatch(line)) {
        if (spans.isNotEmpty) {
          final last = spans.last;
          final lastIsNewline = last is TextSpan && last.text == '\n';
          if (!lastIsNewline) spans.add(const TextSpan(text: '\n'));
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            height: 1,
            color: textColor.withValues(alpha: 0.15),
          ),
        ));
        lastWasBlockWidget = true;
        continue;
      }

      // R7: 表格块检测 —— 当前行是表格行 + 下一行是分隔行
      if (_reTableRow.hasMatch(line) &&
          i + 1 < lines.length &&
          _reTableSeparator.hasMatch(lines[i + 1]) &&
          // R37: 表头必须有至少一个非空单元格——否则退化为普通行渲染，
          // 避免模型异常输出渲染成"只有几条线的空表格"
          _parseTableRow(line).any((c) => c.trim().isNotEmpty)) {
        final headerCells = _parseTableRow(line);
        final alignments = _parseTableAlignments(lines[i + 1]);
        final rows = <List<String>>[];
        var j = i + 2;
        while (j < lines.length && _reTableRow.hasMatch(lines[j])) {
          rows.add(_parseTableRow(lines[j]));
          j++;
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: _buildMarkdownTable(headerCells, rows, alignments, textColor),
        ));
        // 跳过已处理的所有表格行
        i = j - 1;
        lastWasBlockWidget = true;
        continue;
      }

      // R18: 引用（仿对话流引用样式）：左侧圆角竖条 + 亮色文本 + 支持行内 markdown
      if (line == '>' || line.startsWith('> ')) {
        final content = line == '>' ? '' : line.substring(2);
        final inner = <InlineSpan>[];
        _parseInlineSpans(content, textColor, inner);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: inner),
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ));
        continue;
      }
      
      // 标题（R18: 层级更分明——大标题 17.5 / 中标题 16 / 小标题 14，加粗）
      if (line.startsWith('### ')) {
        spans.add(TextSpan(text: line.substring(4), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor, height: 1.5)));
        continue;
      }
      if (line.startsWith('## ')) {
        spans.add(TextSpan(text: line.substring(3), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor, height: 1.5)));
        continue;
      }
      if (line.startsWith('# ')) {
        spans.add(TextSpan(text: line.substring(2), style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: textColor, height: 1.5)));
        continue;
      }
      // 无序列表
      if (line.startsWith('- ') || line.startsWith('* ')) {
        spans.add(const TextSpan(text: '• ', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))));
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

    // R30: 流式代码块——AI 正在输出长代码时围栏尚未闭合，此前这些行被直接丢弃，
    // 用户看到的是"卡住了"；现在把未闭合部分渲染为实时更新的代码卡片
    if (inCodeBlock && codeBuffer.isNotEmpty) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: chartAwareCodeBlock(codeBuffer.join('\n'), codeLang),
      ));
    }
    // 未闭合代码块：内容以等宽文本直出（原版静默丢弃，
    // 流式输出到代码块时"看起来输出到一半就消失了"）
    if (inCodeBlock && codeBuffer.isNotEmpty) {
      spans.add(TextSpan(
        text: codeBuffer.join('\n'),
        style: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          fontFamily: 'monospace',
          color: textColor.withValues(alpha: 0.85),
        ),
      ));
    }
    return TextSpan(children: spans, style: TextStyle(fontSize: 14.5, height: 1.5));
  }

  void _parseInlineSpans(String text, Color textColor, List<InlineSpan> spans) {
    // R5: 使用 static final RegExp，避免每次新建
    final patterns = <RegExp>[
      _reStrikethrough,
      _reBold,
      _reItalic,
      _reInlineCode,
      _reLink,
      _reInlineMath,
      _reEscape,
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
        // 行内代码：背景色 TextSpan（等宽字体）。
        // 曾用 WidgetSpan 灰底芯片——单条消息行内代码多时（如粘贴系统提示词全文，
        // 可达数百个）会产生几百个嵌入 widget，Windows 上 Paragraph 布局崩溃，
        // 表现为"输出到一半文字突然消失、占位还在、滚动后整列表空白"。
        // 改为背景色文本后 span 树保持纯文本结构，任意长度稳定渲染。
        spans.add(TextSpan(
          text: earliestMatch.group(1)!,
          style: TextStyle(
            color: textColor,
            fontSize: 12.5,
            fontFamily: 'Consolas',
            backgroundColor: textColor.withValues(alpha: 0.12),
          ),
        ));
      } else if (earliestPattern == patterns[5]) {
        // R8: 行内数学公式 $...$
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildInlineMath(earliestMatch.group(1)!, textColor),
        ));
      } else if (earliestPattern == patterns[6]) {
        // R19: 转义符号 —— 反斜杠后的字符按字面输出
        spans.add(TextSpan(text: earliestMatch.group(1), style: TextStyle(color: textColor)));
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

  /// R7: 解析 markdown 表格的一行单元格
  /// 去掉首尾的 `|`，按 `|` 分割并 trim。空行返回空列表。
  List<String> _parseTableRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).toList();
  }

  /// R7: 解析 markdown 表格分隔行的列对齐方式
  /// `:---`=左对齐，`---:`=右对齐，`:---:`=居中，其他=默认左对齐
  List<TextAlign> _parseTableAlignments(String sepLine) {
    final cells = _parseTableRow(sepLine);
    return cells.map((c) {
      final p = c.trim();
      if (p.startsWith(':') && p.endsWith(':')) return TextAlign.center;
      if (p.endsWith(':')) return TextAlign.right;
      return TextAlign.left;
    }).toList();
  }

  /// R8: 渲染块级 TeX 数学公式（flutter_math_fork，KaTeX 风格纯 Dart 渲染）。
  /// 解析失败时回退显示原文——流式输出中的半截公式不会崩、不会空白。
  Widget _buildMathBlock(String tex, Color textColor) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.10), width: 0.6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          tex,
          mathStyle: MathStyle.display,
          textStyle: TextStyle(fontSize: 14, color: textColor),
          onErrorFallback: (err) => Text(
            '\$\$$tex\$\$',
            style: TextStyle(fontSize: 12.5, color: textColor.withValues(alpha: 0.75), fontFamily: 'Consolas'),
          ),
        ),
      ),
    );
  }

  /// R8: 渲染行内数学公式 $...$（与正文基线居中对齐）
  Widget _buildInlineMath(String tex, Color textColor) {
    return Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: TextStyle(fontSize: 13, color: textColor),
      onErrorFallback: (err) => Text(
        '\$$tex\$',
        style: TextStyle(fontSize: 12.5, color: const Color(0xFF7C3AED), fontFamily: 'Consolas'),
      ),
    );
  }

  /// R7: 构建 markdown 表格 widget
  /// 风格与聊天消息气泡融合：圆角外框 + 浅色边线 + 表头底色高亮
  Widget _buildMarkdownTable(
    List<String> headers,
    List<List<String>> rows,
    List<TextAlign> alignments,
    Color textColor,
  ) {
    // 统一列数：取 max(headers, rows)，缺位补空串，对齐数组按列数截/补
    final colCount = <int>[headers.length, alignments.length, ...rows.map((r) => r.length)]
        .fold<int>(0, (a, b) => a > b ? a : b);
    while (headers.length < colCount) {
      headers.add('');
    }
    while (alignments.length < colCount) {
      alignments.add(TextAlign.left);
    }
    for (var r = 0; r < rows.length; r++) {
      while (rows[r].length < colCount) {
        rows[r].add('');
      }
    }

    // 颜色（基于 textColor 派生，确保深/浅主题都能看）
    final borderColor = textColor.withValues(alpha: 0.18);
    final headerBg = textColor.withValues(alpha: 0.10);
    final headerText = textColor;

    Widget cellText(String content, {required bool isHeader, required TextAlign align}) {
      // 表头用粗体，正文用普通字重；行内支持粗体/斜体/删除线/行内代码（不做链接）
      final base = TextStyle(
        fontSize: 12.5,
        color: isHeader ? headerText : textColor,
        fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
        height: 1.45,
        decoration: TextDecoration.none,
      );
      // 简单内联：把 `code` 用单独高亮 TextSpan；其他用纯 Text（避免开销与错误）
      final codeRe = RegExp(r'`([^`]+)`');
      if (!codeRe.hasMatch(content)) {
        return Text(content, style: base, textAlign: align);
      }
      final spans = <TextSpan>[];
      var rest = content;
      while (rest.isNotEmpty) {
        final m = codeRe.firstMatch(rest);
        if (m == null) {
          spans.add(TextSpan(text: rest, style: base));
          break;
        }
        if (m.start > 0) {
          spans.add(TextSpan(text: rest.substring(0, m.start), style: base));
        }
        spans.add(TextSpan(
          text: m.group(1),
          style: base.copyWith(
            fontFamily: 'Consolas',
            fontSize: 12,
            color: const Color(0xFF7C3AED),
            backgroundColor: textColor.withValues(alpha: 0.06),
          ),
        ));
        rest = rest.substring(m.end);
      }
      return Text.rich(TextSpan(children: spans), textAlign: align);
    }

    Widget buildCell(String content, {required bool isHeader, required TextAlign align}) {
      // 网格线统一由 Table.border 绘制（见下方说明），单元格只负责底色与内容
      return Container(
        decoration: BoxDecoration(
          color: isHeader ? headerBg : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        alignment: align == TextAlign.center
            ? Alignment.center
            : (align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
        child: cellText(content, isHeader: isHeader, align: align),
      );
    }

    // Flutter Table 强制等宽列；用 Expanded 在外层做流式等分
    final tableRows = <TableRow>[];
    // 表头行
    tableRows.add(TableRow(
      children: [
        for (var c = 0; c < colCount; c++)
          buildCell(
            headers[c],
            isHeader: true,
            align: alignments[c],
          ),
      ],
    ));
    // 数据行
    for (final row in rows) {
      tableRows.add(TableRow(
        children: [
          for (var c = 0; c < colCount; c++)
            buildCell(
              row[c],
              isHeader: false,
              align: alignments[c],
            ),
        ],
      ));
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        // R37: 显式撑满可用宽度——无气泡布局下 Table 处于宽松约束时会收缩
        child: SizedBox(
          width: double.infinity,
          child: Table(
            columnWidths: {
              for (var c = 0; c < colCount; c++) c: const FlexColumnWidth(1.0),
            },
          // 网格线交给 Table.border 统一绘制：此前由每个单元格自绘 Border，
          // 配合 middle 垂直对齐时不同行高的单元格各自居中，边框错位、竖线断开。
          // fill 让单元格撑满整行高度，Table 画的横竖线天然对齐；左右外框由
          // 外层圆角 Container 提供，故只画顶/底/内部线。
          border: TableBorder(
            top: BorderSide(color: borderColor, width: 0.5),
            bottom: BorderSide(color: borderColor, width: 0.5),
            horizontalInside: BorderSide(color: borderColor, width: 0.5),
            verticalInside: BorderSide(color: borderColor, width: 0.5),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.fill,
          children: tableRows,
        ),
      ),
      ),
    );
  }

  /// R9: 工作流时间线——「思考段（带时长）」与「工具步骤」按轮次归并穿插，
  /// 仿 coding-agent 的过程流：思考 · 持续了 N 秒 → 编辑/终端/工具行 → 下一轮思考…
  /// 同一轮内思考在前（思考发生在该轮流式决策阶段，步骤在其后执行）；
  /// 终端块与子 Agent 卡片保持专属样式，文件编辑行由 AgentToolRow 按 filePath 自动切换。
  List<Widget> _buildAgentTimeline(ChatMessage msg, bool isLight, bool running) {
    final segs = msg.reasoningSegs.where((s) => s.text.trim().isNotEmpty).toList();
    final steps = msg.toolSteps;
    final rows = <Widget>[];
    var si = 0;
    var ti = 0;
    while (si < segs.length || ti < steps.length) {
      final s = si < segs.length ? segs[si] : null;
      final t = ti < steps.length ? steps[ti] : null;
      if (t == null || (s != null && s.round <= t.round)) {
        rows.add(AgentThinkRow(
          text: s!.text,
          running: s.endedAt == null && running,
          seconds: s.endedAt == null ? null : s.endedAt!.difference(s.startedAt).inSeconds,
          light: isLight,
        ));
        si++;
      } else {
        if (t.terminal) {
          rows.add(AgentTerminalBlock(
            command: t.command ?? '',
            running: t.running,
            failed: t.failed,
            exitCode: t.exitCode,
            output: t.output,
            light: isLight,
          ));
        } else if (t.name == 'spawn_subagent') {
          // 子 Agent 派发：专属卡片（类型徽章 + 执行轨迹 + 报告）
          rows.add(AgentSubagentCard(
            type: t.subType ?? 'general',
            task: t.subTask ?? '',
            label: t.label,
            running: t.running,
            done: t.done,
            failed: t.failed,
            events: t.subEvents,
            output: t.output,
            light: isLight,
          ));
        } else {
          rows.add(AgentToolRow(
            name: t.name,
            label: t.label,
            running: t.running,
            done: t.done,
            failed: t.failed,
            input: t.input,
            output: t.output,
            filePath: t.filePath,
            addedLines: t.addedLines,
            removedLines: t.removedLines,
            light: isLight,
          ));
        }
        ti++;
      }
      rows.add(const SizedBox(height: 2));
    }
    return rows;
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
  /// 移动端聊天浮层的滚动控制器（与桌面 _chatScrollCtrl 分离，避免跨布局共用）；
  /// 复用而非每帧新建，防止流式重建时反复换绑/泄漏导致构建异常
  final ScrollController _mobileChatScrollCtrl = ScrollController();
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

  /// 按文件头魔数识别图片类型（Android 相册/SAF 返回的文件名常无扩展名，
  /// 仅靠扩展名判断会把图片误判成"不支持解析的文件"）
  String? _imageMimeFromBytes(Uint8List b) {
    if (b.length < 12) return null;
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpeg';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) return 'gif';
    if (b[0] == 0x42 && b[1] == 0x4D) return 'bmp';
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'webp';
    }
    return null;
  }

  /// 选择任意文件作为聊天附件：图片走 vision，文本文件读取内容注入，其余类型仅记文件名
  Future<void> _pickChatFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      final name = f.name;
      // bytes 兜底链：withData 在 Android 部分相册/SAF 路径下拿不到字节，
      // 退回用 path 直接读文件（原实现 bytes==null 直接静默 return，
      // 即手机端"选了图没反应"的根因）
      var bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        final p = f.path;
        if (p != null && p.isNotEmpty) {
          try {
            bytes = await File(p).readAsBytes();
          } catch (_) {}
        }
      }
      if (bytes == null || bytes.isEmpty) {
        if (mounted) _showChatToast(context, '无法读取所选文件，请换一个来源重试');
        return;
      }
      final lower = name.toLowerCase();
      final isImage = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].any((e) => lower.endsWith(e));
      // 无扩展名/不可信文件名：按字节魔数兜底识别图片
      final mimeFromBytes = isImage ? null : _imageMimeFromBytes(bytes!);
      if (isImage || mimeFromBytes != null) {
        final mime = isImage ? _imageMime(name) : mimeFromBytes!;
        final dataUrl = 'data:image/$mime;base64,${base64Encode(bytes!)}';
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
          text = utf8.decode(bytes!);
        } catch (_) {
          text = latin1.decode(bytes!);
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
        if (mounted) _showChatToast(context, '该文件类型暂不支持内容解析，将以附件名发送');
      }
    } catch (e) {
      // 选择失败：不再静默吞掉（用户无从得知为什么没反应）
      if (mounted) _showChatToast(context, '选择文件失败：$e');
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
      var page = 'main'; // main / kb / skills / connectors
      return StatefulBuilder(
        builder: (ctx, setSt) {
          Widget body;
          if (page == 'skills') {
            // 合并三类技能：通用对话技能（kChatSkills 5 个） + Agent 工具技能（kAgentToolSkills 19 个） +
            // SkillStore 动态加载技能（26 内置 + 11 原生 + 用户自定义）。前者为兼容旧"已激活技能"体系，
            // 后者才是真正"内置"技能库（用户在设置中启用/禁用、新增自定义后实时同步）
            // ListenableBuilder(listenable: s) 让 SkillStore 异步加载完成后自动重建
            body = ListenableBuilder(
              listenable: s,
              builder: (innerCtx, _) {
                final merged = <ChatSkill>[
                  ...kChatSkills,
                  ...kAgentToolSkills,
                  for (final sk in s.skillStore.enabled)
                    ChatSkill(
                      sk.id, sk.name, sk.description, sk.content,
                      icon: Icons.auto_fix_high_rounded,
                    ),
                ];
                // 按 id 去重：前面的来源优先（kChatSkills > kAgentToolSkills > SkillStore）
                final seen = <String>{};
                final skills = <ChatSkill>[];
                for (final sk in merged) {
                  if (seen.add(sk.id)) skills.add(sk);
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildHeader('选择技能', onBack: () => setSt(() => page = 'main')),
                    if (!s.skillStore.loaded)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(children: [
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFA78BFA)),
                          ),
                          const SizedBox(width: 8),
                          Text('正在加载技能库…',
                              style: TextStyle(fontSize: 12, color: textTertiary)),
                        ]),
                      ),
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
                          for (final skill in skills)
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
              },
            );
          } else if (page == 'kb') {
            // 知识库：上传外挂文档，AI 通过 search_knowledge_base 工具检索
            final kbDocs = KnowledgeBase.docs;
            body = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                buildHeader('知识库', onBack: () => setSt(() => page = 'main')),
                if (kbDocs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Column(children: [
                      Text('暂无文档', style: TextStyle(fontSize: 13, color: textSecondary)),
                      const SizedBox(height: 6),
                      Text('上传 txt / md / csv / json 等文本文件，\nAI 会自动检索知识库内容来回答问题',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 11, color: textTertiary, height: 1.5)),
                    ]),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: kbDocs.length,
                    itemBuilder: (ctx3, i) {
                      final d = kbDocs[i];
                      final sizeLabel = d.sizeBytes >= 1024 * 1024
                          ? '${(d.sizeBytes / 1024 / 1024).toStringAsFixed(1)}MB'
                          : '${(d.sizeBytes / 1024).toStringAsFixed(1)}KB';
                      return _darkMenuItem(
                        icon: const Icon(Icons.description_outlined, size: 20, color: textSecondary),
                        title: d.name,
                        subtitle: sizeLabel,
                        trailing: GestureDetector(
                          onTap: () {
                            KnowledgeBase.remove(d.id);
                            setSt(() {});
                          },
                          child: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFFF87171)),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.upload_file_outlined, size: 20, color: Color(0xFF10B981)),
                  title: '上传文档',
                  subtitle: 'txt / md / csv / json 等，单份 ≤1MB',
                  onTap: () async {
                    final err = await _pickKbFile();
                    if (!ctx.mounted) return;
                    if (err != null) {
                      _showChatToast(context, err);
                    } else {
                      setSt(() {});
                      if (KnowledgeBase.docs.isNotEmpty) {
                        _showChatToast(context, '已加入知识库，可直接向 AI 提问');
                      }
                    }
                  },
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
            // 主菜单：一比一复刻目标样式（图标 + 标题 + 右箭头，分组分隔线）
            Widget chevron({bool dot = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
                  if (dot) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const Icon(Icons.chevron_right_rounded, size: 16, color: textTertiary),
                ]);
            body = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _darkMenuItem(
                  icon: Icon(
                    s.workspacePath.isEmpty ? Icons.folder_open_outlined : Icons.folder_rounded,
                    size: 20,
                    color: s.workspacePath.isEmpty ? textSecondary : const Color(0xFF10B981),
                  ),
                  title: '工作区',
                  trailing: chevron(),
                  onTap: () {
                    entry.remove();
                    _showWorkspacePicker(context, c, s);
                  },
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.attach_file_outlined, size: 20, color: textSecondary),
                  title: '添加文件',
                  trailing: chevron(),
                  onTap: () {
                    entry.remove();
                    _pickChatFile();
                  },
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.library_books_outlined, size: 20, color: textSecondary),
                  title: '知识库',
                  trailing: chevron(dot: KnowledgeBase.docs.isNotEmpty),
                  onTap: () => setSt(() => page = 'kb'),
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.auto_fix_high_outlined, size: 20, color: textSecondary),
                  title: '技能',
                  trailing: chevron(dot: s.currentSkill != null),
                  onTap: () => setSt(() => page = 'skills'),
                ),
                const Divider(height: 1, color: Color(0xFF3D3D45)),
                _darkMenuItem(
                  icon: const Icon(Icons.lan_outlined, size: 20, color: textSecondary),
                  title: '连接器',
                  trailing: chevron(dot: s.searchEnabled),
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
      width: 250,
      height: 300,
      content: contentBuilder(context, (_) {}),
    );
  }

  /// 选择文本文件加入外挂知识库。成功返回 null；失败返回错误文案。
  Future<String?> _pickKbFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      if (res == null || res.files.isEmpty) return null;
      final f = res.files.first;
      final bytes = f.bytes;
      final name = f.name;
      if (bytes == null || bytes.isEmpty) return '文件为空';
      final lower = name.toLowerCase();
      const textExts = ['.txt', '.md', '.json', '.dart', '.js', '.ts', '.html', '.htm', '.css', '.csv', '.xml', '.yml', '.yaml', '.log', '.py', '.java', '.c', '.cpp', '.h', '.sql'];
      final isText = textExts.any((e) => lower.endsWith(e));
      if (!isText) return '暂支持 txt / md / csv / json 等文本文件';
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = latin1.decode(bytes);
      }
      if (text.trim().isEmpty) return '文件内容为空';
      return KnowledgeBase.add(name, text);
    } catch (e) {
      return '选择文件失败：$e';
    }
  }

  void _showChatToast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 13)),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ));
  }

  /// 历史会话项 "..." 菜单：删除 / 重命名（保留扩展点），从 _MoreChip 触发。
  /// 复用全屏浮层能力（_showOverlayPanel）。重命名暂未实现，预留按钮位。
  void _showSessionItemMenu(BuildContext context, AppColors c, AppState s, String sessionId) {
    final anchorKey = GlobalKey();
    // 用一个 0 尺寸的 anchor 占位；用 pushModal 形式更简单（不依赖锚点）
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        // R23: 置顶状态（置顶/取消置顶菜单项）
        final sessionMap = s.chatSessions.firstWhere((e) => e['id'] == sessionId, orElse: () => <String, dynamic>{});
        final pinned = sessionMap['pinned'] == true;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.isLight ? Colors.white : const Color(0xFF1F1F25),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // R23: 置顶 / 取消置顶（最多同时置顶 10 个）
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    s.toggleSessionPin(sessionId);
                    if (context.mounted) _showChatToast(context, pinned ? '已取消置顶' : '已置顶（最多 10 个）');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(children: [
                      Icon(Icons.push_pin_rounded, size: 18, color: c.textSecondary),
                      const SizedBox(width: 12),
                      Text(pinned ? '取消置顶' : '置顶',
                          style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.divider),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    s.deleteSession(sessionId);
                    if (context.mounted) _showChatToast(context, '已删除对话');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: const Color(0xFFEF4444)),
                      const SizedBox(width: 12),
                      Text('删除此对话',
                          style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.divider),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (context.mounted) _showChatToast(context, '重命名功能开发中');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(children: [
                      Icon(Icons.drive_file_rename_outline_rounded, size: 18, color: c.textSecondary),
                      const SizedBox(width: 12),
                      Text('重命名',
                          style: TextStyle(fontSize: 14, color: c.text, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
              Divider(height: 1, thickness: 1, color: c.divider),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(children: [
                      Icon(Icons.close_rounded, size: 18, color: c.textTertiary),
                      const SizedBox(width: 12),
                      Text('取消',
                          style: TextStyle(fontSize: 14, color: c.textTertiary)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  /// 通用桌面端浮层：从 anchorKey 按钮位置弹出指定尺寸的深色卡片。
  /// [content] 为浮层内容（已用 ClipRRect + Material 包裹好）。
  /// 浮层位置默认在按钮正上方、左对齐到按钮左侧；屏幕边距不足时自动翻转到下方/右对齐。
  /// 浮层外点击空白处自动关闭；返回 OverlayEntry 供调用方在合适时机关闭。
  /// 手机端（窄屏或锚点不可用——锚点 key 在手机端不挂载）改为底部上滑面板，
  /// 避免锚点缺失时坐标落到 (0,0)、菜单从屏幕左上角弹出的违和效果。
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
    final isMobileLayout = MediaQuery.of(context).size.width < 500;
    if (renderBox == null || isMobileLayout) {
      return _showBottomSheetPanel(overlay, height, content);
    }
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

  /// 手机端底部弹出面板：全宽贴底、上滑淡入、半透明遮罩，点击遮罩关闭。
  OverlayEntry _showBottomSheetPanel(OverlayState overlay, double height, Widget content) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => entry.remove(),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: 1,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: height,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (ctx, t, child) => Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 48),
                  child: child,
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Material(
                  color: const Color(0xFF2B2B32),
                  elevation: 8,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).padding.bottom),
                    child: content,
                  ),
                ),
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

  /// 历史对话抽屉：参考图二（深色侧栏），从 agent 右侧滑入，按今天/昨天/7天内分组。
  void _showHistoryPicker(BuildContext context, AppColors c, AppState s) {
    final nav = Navigator.of(context, rootNavigator: true);
    final isLight = c.isLight;
    // 抽屉宽度：约 340，对齐 deepseek/ChatGPT 侧栏的紧凑比例
    const drawerWidth = 340.0;
    // ===== 配色（紧贴 AppColors，浅/深/毛玻璃都自然） =====
    final drawerBg = isLight ? Colors.white : const Color(0xFF111114);
    final drawerBorder = isLight ? const Color(0xFFEDEDF1) : const Color(0xFF25252B);
    final textPrimary = c.text;
    final textTertiary = c.textTertiary;
    // 强调色：紫（与主品牌色 kPrimary 一致）
    final accent = c.primary;
    // 状态色：active 项 8% 紫底；hover 项 4% 中性底
    final activeBg = c.primary.withValues(alpha: isLight ? 0.08 : 0.14);
    final hoverBg = (isLight ? Colors.black : Colors.white).withValues(alpha: 0.04);
    // 分组小标题字色：比 tertiary 更弱
    final sectionLabel = isLight ? const Color(0xFF8E8E96) : const Color(0xFF6E6E78);

    nav.push(PageRouteBuilder(
      opaque: false,
      barrierColor: const Color(0x66000000),
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (pc, anim, secAnim) {
        // 抽屉右对齐：从屏幕右边缘滑入
        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(builder: (ctx, setSt) {
            final sessions = List<Map<String, dynamic>>.from(s.chatSessions);

            // 按时间分组：今天 / 昨天 / 7天内 / 更早
            final now = DateTime.now();
            DateTime? parseTime(String? iso) {
              try {
                return DateTime.parse(iso ?? '');
              } catch (_) {
                return null;
              }
            }

            String sectionOf(String? iso) {
              final t = parseTime(iso);
              if (t == null) return '更早';
              final d = now.difference(t);
              if (d.inDays < 1) return '今天';
              if (d.inDays < 2) return '昨天';
              if (d.inDays < 7) return '7天内';
              return '更早';
            }

            // 按分组顺序聚合（R23: 置顶会话单独分组置顶展示）
            final pinnedList = sessions.where((ssn) => ssn['pinned'] == true).toList();
            final unpinnedSessions = sessions.where((ssn) => ssn['pinned'] != true).toList();
            const order = ['今天', '昨天', '7天内', '更早'];
            final groups = <String, List<Map<String, dynamic>>>{
              for (final k in order) k: <Map<String, dynamic>>[],
            };
            for (final ssn in unpinnedSessions) {
              groups[sectionOf(ssn['createdAt'] as String?)]!.add(ssn);
            }
            // 每个分组内按 createdAt 倒序
            for (final list in groups.values) {
              list.sort((a, b) {
                final ta = parseTime(a['createdAt'] as String?) ?? DateTime(1970);
                final tb = parseTime(b['createdAt'] as String?) ?? DateTime(1970);
                return tb.compareTo(ta);
              });
            }

            // 列表项：分组小标题 + 会话
            Widget buildList() {
              if (sessions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                  child: Column(children: [
                    Text('还没有历史对话',
                        style: TextStyle(
                          fontSize: 14,
                          color: textTertiary,
                          // 兜底关闭下划线（路由/DefaultTextStyle 透出的装饰）
                          decoration: TextDecoration.none,
                          decorationColor: Colors.transparent,
                        )),
                  ]),
                );
              }
              final children = <Widget>[];
              // R23: 会话条目构造（置顶组与时间分组共用）
              Widget sessionItem(Map<String, dynamic> ssn) {
                final title = (ssn['title'] as String?) ?? '（无标题）';
                final isActive = ssn['id'] == s.activeSessionIdForUi;
                return _SessionItem(
                  title: title,
                  isActive: isActive,
                  activeBg: activeBg,
                  hoverBg: hoverBg,
                  textPrimary: textPrimary,
                  textTertiary: textTertiary,
                  accent: accent,
                  onTap: () {
                    s.loadSession('${ssn['id']}');
                    nav.pop();
                  },
                  onMore: () => _showSessionItemMenu(ctx, c, s, '${ssn['id']}'),
                );
              }

              // R23: 置顶分组（最多 10 个，见 toggleSessionPin）
              if (pinnedList.isNotEmpty) {
                children.add(Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(children: [
                    Icon(Icons.push_pin_rounded, size: 12, color: sectionLabel),
                    const SizedBox(width: 4),
                    Text('已置顶',
                        style: TextStyle(
                          fontSize: 12,
                          color: sectionLabel,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                          decoration: TextDecoration.none,
                          decorationColor: Colors.transparent,
                        )),
                  ]),
                ));
                for (final ssn in pinnedList) {
                  children.add(sessionItem(ssn));
                }
              }
              for (final key in order) {
                final list = groups[key]!;
                if (list.isEmpty) continue;
                children.add(Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Text(
                    key,
                    style: TextStyle(
                      fontSize: 12,
                      color: sectionLabel,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                      // 显式关闭下划线：兜底覆盖路由/DefaultTextStyle 透出来的 decoration
                      decoration: TextDecoration.none,
                      decorationColor: Colors.transparent,
                    ),
                  ),
                ));
                for (final ssn in list) {
                  children.add(sessionItem(ssn));
                }
              }
              children.add(const SizedBox(height: 24));
              return ListView(
                padding: EdgeInsets.zero,
                children: children,
              );
            }

            return Container(
              width: drawerWidth,
              height: MediaQuery.of(context).size.height,
              decoration: BoxDecoration(
                color: drawerBg,
                border: Border(left: BorderSide(color: drawerBorder, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(-4, 0),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 顶部：整宽"开启新对话"胶囊按钮（参考图一）
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          onTap: () {
                            s.startNewSession();
                            nav.pop();
                          },
                          borderRadius: BorderRadius.circular(999),
                          hoverColor: hoverBg,
                          child: Container(
                            width: double.infinity,
                            height: 44,
                            decoration: BoxDecoration(
                              border: Border.all(color: drawerBorder, width: 1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.add_rounded, size: 18, color: textPrimary),
                              const SizedBox(width: 6),
                              Text('开启新对话',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textPrimary,
                                    fontWeight: FontWeight.w500,
                                    // 兜底关闭下划线（路由/DefaultTextStyle 透出的装饰）
                                    decoration: TextDecoration.none,
                                    decorationColor: Colors.transparent,
                                  )),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    // 分组列表
                    Expanded(child: buildList()),
                  ],
                ),
              ),
            );
          }),
        );
      },
      // 滑入：抽屉从屏幕右外 100% 平移回 0；半透明 barrier 同步淡入
      transitionsBuilder: (ctx, anim, secAnim, child) {
        final slide = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .chain(CurveTween(curve: Curves.easeOutCubic))
            .animate(anim);
        return Stack(children: [
          // 背景：barrier 渐入
          FadeTransition(
            opacity: anim.drive(CurveTween(curve: Curves.easeOut)),
            child: const SizedBox.expand(),
          ),
          // 抽屉：水平平移
          SlideTransition(position: slide, child: child),
        ]);
      },
    ));
  }

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

    const popupWidth = 190.0;
    const popupMaxHeight = 220.0;

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
            fontSize: 9.45,
            fontWeight: FontWeight.w600,
            height: 1.2,
            letterSpacing: 0,
            decoration: TextDecoration.none,
            decorationColor: Colors.transparent,
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
    // 初始选中：按当前生效配置（effectiveChatConfig）匹配；无匹配时默认选中第一个
    int initialIdx = 0;
    final eff = s.effectiveChatConfig;
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i].config.url == eff.url &&
          profiles[i].config.key == eff.key &&
          profiles[i].config.model == eff.model) {
        initialIdx = i;
        break;
      }
    }
    // 选中状态提升到外层闭包：避免 StatefulBuilder 每次 build 重新初始化（修复选中特效不变）
    int curSelectedIdx = initialIdx;

    // ===== R20: 悬停模型详情卡（仿 Cherry Studio：右侧浮出模型信息 + 思考强度） =====
    // DeepSeek 系显示 关闭/高/超高 三档思考强度（真实写入请求参数）；
    // 其他模型仅显示"是否思考"开关。鼠标离开行与卡片 220ms 后自动收起。
    Timer? hoverHideTimer;
    OverlayEntry? hoverEntry;

    void hideHoverCard() {
      hoverHideTimer?.cancel();
      hoverEntry?.remove();
      hoverEntry = null;
    }

    void scheduleHideHoverCard() {
      hoverHideTimer?.cancel();
      hoverHideTimer = Timer(const Duration(milliseconds: 220), hideHoverCard);
    }

    void showHoverCard(BuildContext rowCtx, ApiProfile p) {
      final box = rowCtx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      hoverHideTimer?.cancel();
      hoverEntry?.remove();
      final overlay = Overlay.of(rowCtx, rootOverlay: true);
      final pos = box.localToGlobal(Offset.zero);
      final size = box.size;
      final screen = MediaQuery.of(rowCtx).size;
      const cardW = 244.0;
      double cx = pos.dx + size.width + 10;
      if (cx + cardW > screen.width - 12) cx = pos.dx - cardW - 10;
      double cy = pos.dy - 6;
      if (cy + 230 > screen.height - 12) cy = screen.height - 242;
      if (cy < 8) cy = 8;

      hoverEntry = OverlayEntry(builder: (cardCtx) {
        return StatefulBuilder(builder: (cardCtx, setCard) {
          final isDeepSeek = ApiService.isDeepSeekModel(p.config.model);
          final title = p.config.model.isNotEmpty ? p.config.model.toUpperCase() : p.name.toUpperCase();
          Widget cardRow(String label, Widget trailing) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Text(label, style: const TextStyle(fontSize: 12, color: textMuted, decoration: TextDecoration.none)),
                const Spacer(),
                trailing,
              ]),
            );
          }

          return Positioned(
            left: cx,
            top: cy,
            width: cardW,
            child: MouseRegion(
              onEnter: (_) => hoverHideTimer?.cancel(),
              onExit: (_) => scheduleHideHoverCard(),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: borderColor, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textPrimary, decoration: TextDecoration.none),
                    ),
                    const Divider(height: 18, color: dividerColor),
                    if ((p.priceLabel ?? '').isNotEmpty) ...[
                      cardRow(
                        '消耗速度',
                        Text(p.priceLabel!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent, decoration: TextDecoration.none)),
                      ),
                      const Divider(height: 12, color: dividerColor),
                    ],
                    if (isDeepSeek) ...[
                      const Text('思考强度', style: TextStyle(fontSize: 12, color: textMuted, decoration: TextDecoration.none)),
                      const SizedBox(height: 8),
                      Row(children: [
                        for (final lv in const [('off', '关闭'), ('high', '高'), ('ultra', '超高')])
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () {
                                s.setChatThinkLevel(lv.$1);
                                setCard(() {});
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: s.chatThinkLevel == lv.$1 ? accent.withValues(alpha: 0.16) : const Color(0xFF24242B),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: s.chatThinkLevel == lv.$1 ? accent : const Color(0xFF2D2D35),
                                    width: 0.6,
                                  ),
                                ),
                                child: Text(
                                  lv.$2,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: s.chatThinkLevel == lv.$1 ? accent : textMuted,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
          );
        });
      });
      overlay.insert(hoverEntry!);
    }

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
      ApiProfile? profile,
    }) {
      return StatefulBuilder(builder: (ctx, setState) {
        bool hover = false;
        return MouseRegion(
          onEnter: (_) {
            setState(() => hover = true);
            // R20: 悬停显示模型详情卡（思考强度/是否思考）
            if (profile != null) showHoverCard(ctx, profile);
          },
          onExit: (_) {
            setState(() => hover = false);
            scheduleHideHoverCard();
          },
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: onTap,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: Container(
              color: (selected || hover) ? surfaceHighlight : Colors.transparent,
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
                              fontSize: 11.5,
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              decoration: TextDecoration.none,
                              decorationColor: Colors.transparent,
                            ),
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
                        fontSize: 11.7,
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
          ),
        );
      });
    }

    // 把 ApiProfile.tags（{text, colorValue}）转成 UI 用的 {text, color}
    List<({String text, Color color})> profileTags(ApiProfile p) {
      return p.tags
          .map((t) => (text: t.text, color: Color(t.colorValue)))
          .toList();
    }

    // 关闭回调：OverlayEntry 在 builder 中通过 [onClose] 传入；
    // "配置自定义模型" 等需要先关掉浮层再走新路由的入口，调用 onClose() 即可移除浮层
    Widget content(int selectedIdx, void Function(int) onChanged, {VoidCallback? onClose}) {
      final listItems = <Widget>[
        Container(height: 1, color: dividerColor),
        // 模型行：价格 + tags 都来自 ApiProfile 字段（不硬编码）；行间不加分割线（R23）
        for (var i = 0; i < profiles.length; i++) ...[
          buildRow(
            icon: modelIcon(profiles[i].config.model),
            title: profiles[i].config.model.isNotEmpty
                ? profiles[i].config.model.toUpperCase()
                : profiles[i].name.toUpperCase(),
            priceLabel: profiles[i].priceLabel,
            selected: selectedIdx == i,
            tags: profileTags(profiles[i]),
            profile: profiles[i],
            onTap: () {
              s.disableAutoModel();
              // 开启"独立配置"时写入对话助手配置库，否则写全局配置库
              // notify: false 避免弹窗内触发全量重建导致卡顿
              if (s.chatApiIndependent) {
                s.saveChatProfiles(s.chatProfiles, i, notify: false);
              } else {
                s.saveApiProfiles(s.apiProfiles, i, notify: false);
              }
              onChanged(i);
            },
          ),
        ],

        // 配置自定义模型
        Container(height: 1, color: dividerColor),
        InkWell(
          onTap: () {
            // 关键：先关掉自定义 OverlayEntry 浮层（Navigator.pop 关不掉 OverlayEntry）
            // 避免浮层覆盖在新弹出的 SettingsDialog 上造成"设置背景变黑"假象
            onClose?.call();
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
                    fontSize: 12.15,
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
            void onChanged(int idx) {
              setState(() {
                curSelectedIdx = idx;
              });
            }
            return Container(
              decoration: const BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: chrome(content(curSelectedIdx, onChanged, onClose: () => Navigator.of(ctx).pop())),
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
              void onChanged(int idx) {
                setState(() {
                  curSelectedIdx = idx;
                });
              }
              return SizedBox(
                width: popupWidth,
                child: chrome(content(curSelectedIdx, onChanged, onClose: () => Navigator.of(ctx).pop())),
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
          void onChanged(int idx) {
            setState(() {
              curSelectedIdx = idx;
            });
          }
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    hideHoverCard();
                    entry.remove();
                  },
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
                        scale: scale * 1.25,
                        alignment: Alignment.bottomRight,
                        child: child,
                      ),
                    ),
                    child: chrome(content(curSelectedIdx, onChanged, onClose: () {
                      hideHoverCard();
                      entry.remove();
                    })),
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


  /// 上下文用量详细分布弹窗（按图6：顶部大百分比 + 副文字 + 白色细分割线彩色分段进度条 + 5 行圆点百分比）
  void _showContextUsageBreakdown(BuildContext context, AppState s, {GlobalKey? anchorKey}) {
    final bd = s.contextTokenBreakdown();    // 5 个分类，按图6配色：绿/橙/紫/蓝/浅紫
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
      anchorKey ?? _contextRingKey,
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
      // R21: 显式撑满父宽——否则外壳收缩到内容宽度，右侧按钮组不贴输入框最右边
      width: double.infinity,
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
                // R28: 显式清除全局主题的聚焦描边（输入框外壳自带容器，内层不需要边框）
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
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
          // 工具行宽度依 chat panel 实际宽度判断，而非整窗 640 阈值；
          // chat panel 在桌面默认 ~340px，但可能更窄，"完全访问"文字会撑掉发送键
          LayoutBuilder(builder: (ctx, rowConstraints) {
            final narrow = rowConstraints.maxWidth < 360;
            return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // 左侧工具：+ / 权限（工作区选择已移入 + 菜单）
            _ChatInputIconButton(
              key: isMobile ? null : _plusBtnKey,
              icon: Icons.add_rounded,
              tooltip: '工具',
              onPressed: () => _showChatPlusMenu(context, c, s),
              c: c,
            ),
            const SizedBox(width: 4),
            // 权限按钮：chat panel 实际窄时收缩为纯图标，避免文字撑开把发送键挤出去
            if (narrow)
                _ChatInputIconButton(
                  key: isMobile ? null : _permissionBtnKey,
                  icon: s.chatFullAccess ? Icons.shield_rounded : Icons.shield_outlined,
                  tooltip: s.chatFullAccess ? '完全访问' : '默认权限',
                  onPressed: () => _showChatPermissionMenu(context, c, s),
                  c: c,
                )
              else
                _ChatInputTextButton(
                  key: isMobile ? null : _permissionBtnKey,
                  icon: Icons.shield_outlined,
                  label: s.chatFullAccess ? '完全访问' : '默认权限',
                  onPressed: () => _showChatPermissionMenu(context, c, s),
                  c: c,
                ),
            const Spacer(),
            // 模型按钮：Flexible 让标签过长时 ellipsis，不会挤掉发送键
            Flexible(
              child: _ChatInputTextButton(
                key: isMobile ? null : _modelSelectorBtnKey,
                icon: null,
                leading: aiIcon,
                label: s.chatApiIndependent ? '$modelLabel·独立' : modelLabel,
                onPressed: () => _showChatModelSelector(context, c, s),
                c: c,
              ),
            ),
            const SizedBox(width: 10),
            // R27: 上下文占用圆环（点击在圆环正上方弹出分布详情）
            _ContextUsageRing(
              s: s,
              anchorKey: _contextRingKey,
              onTap: () => _showContextUsageBreakdown(context, s, anchorKey: _contextRingKey),
            ),
            const SizedBox(width: 10),
            // 发送按钮：带 Material 涟漪 + 按下缩放反馈，永远完整可见不被裁切
            _ChatSendButton(
              sending: s.chatSending,
              c: c,
              onPressed: () {
                if (s.chatSending) {
                  s.cancelChat();
                } else {
                  _sendChat(s);
                }
              },
            ),
          ]);
          }),
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
    // R40: 图片大小防护——base64 膨胀 33%，超 4MB 的请求体多数服务商会拒收/超时，
    // 异常曾在回退路径无兜底时导致 chatSending 卡死（表现为"发送无响应"）。
    if (img != null && img.length > 4 * 1024 * 1024) {
      _showChatToast(context, '图片过大（base64 后 ${(img.length / 1024 / 1024).toStringAsFixed(1)}MB），请压缩或截图后重试');
      return;
    }
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
  /// 自定义图标色（默认 textTertiary）；工作区已设置时显示绿色
  final Color? iconColor;
  const _ChatInputIconButton({super.key, required this.icon, this.tooltip, required this.onPressed, required this.c, this.iconColor});

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
          child: Icon(icon, size: 18, color: iconColor ?? c.textTertiary),
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

/// 聊天栏发送按钮：Material 涟漪 + 按下缩放反馈，避免窄窗口下被外层圆角裁切看不见
class _ChatSendButton extends StatefulWidget {
  final bool sending;
  final AppColors c;
  final VoidCallback onPressed;
  const _ChatSendButton({required this.sending, required this.c, required this.onPressed});

  @override
  State<_ChatSendButton> createState() => _ChatSendButtonState();
}

class _ChatSendButtonState extends State<_ChatSendButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.sending ? const Color(0xFFEF4444) : widget.c.primary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: widget.sending
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [widget.c.primary, widget.c.primary],
                    ),
              color: widget.sending ? const Color(0xFFEF4444) : null,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: widget.sending
                ? const Icon(Icons.stop_rounded, size: 18, color: Colors.white)
                : const Icon(Icons.arrow_upward_rounded, size: 18, color: Colors.white),
          ),
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
    // 手机端：隐藏贪吃蛇单机/双人（桌面独占体验）；查询入口从底部导航移入这里
    final moreItems = isMobile
        ? [
            (Icons.search_rounded, '查词', '查单词/翻译', 3),
            ..._moreItemsData.where((e) => e.$4 != 20 && e.$4 != 24),
          ]
        : _moreItemsData;
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

/// 全局背景层：
/// - isGlass=true：毛玻璃主题的蓝色渐隐背景（渐变底 + 柔光斑 + 光带 + 网格）。
///   [animated] 仅引导页为 true（呼吸极光）；主界面一律 false——同一幅画的
///   静态帧，画一次后缓存，不再每帧重绘（每帧全屏重绘叠加壳层 BackdropFilter
///   连带重模糊是此前主界面卡顿的根源）
/// - isGlass=false：静态纯色实底（浅色 _lightBgTint / 深色 kDarkBg，无光斑）。
///   经典主题 / 深色模式 / 高性能模式用它
class _AppGlassBackground extends StatelessWidget {
  final AppColors colors;
  final bool isGlass;
  final bool animated;
  /// 当前主题的 DIY 背景配置（null = 未 DIY，走内置默认）
  final DiyBackdrop? diyBackdrop;
  /// 是否允许动效（省电/高性能模式下为 false）
  final bool animateAllowed;
  const _AppGlassBackground({
    required this.colors,
    this.isGlass = false,
    this.animated = true,
    this.diyBackdrop,
    this.animateAllowed = true,
  });

  @override
  Widget build(BuildContext context) {
    // DIY 优先级最高：用户自己调过的背景（含经典/深色主题也得生效）
    final diy = diyBackdrop;
    if (diy != null) {
      return DiyBackdropView(
        config: diy,
        isLight: colors.isLight,
        // 模糊只在毛玻璃主题下叠加，经典/深色主题保持清晰
        blur: isGlass ? diy.blur : 0,
        animate: animated && animateAllowed,
      );
    }
    if (isGlass) {
      return GlassBackground(isLight: colors.isLight, animated: animated && animateAllowed);
    }
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.appBgGradientTop),
      child: const SizedBox.expand(),
    );
  }
}

/// 全局"等待用户选择"弹窗宿主。
/// 监听 AppState.promptRequest（导出格式选择 / 跨工作区授权），
/// 触发后弹出模态对话框，用户点选后通过 respondPrompt 唤醒工具调用。
class AgentPromptHost extends StatefulWidget {
  final AppState state;
  const AgentPromptHost({super.key, required this.state});

  @override
  State<AgentPromptHost> createState() => _AgentPromptHostState();
}

class _AgentPromptHostState extends State<AgentPromptHost> {
  int? _shownId;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final req = widget.state.promptRequest;
    if (req == null || req['id'] == _shownId) return;
    _shownId = req['id'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.state.promptRequest == null ||
          widget.state.promptRequest!['id'] != req['id']) {
        return;
      }
      _showDialog(req);
    });
  }

  void _close(String? selectedId, Map<String, dynamic> req, BuildContext ctx) {
    _shownId = null;
    widget.state.respondPrompt(selectedId, id: req['id'] as int?);
    if (ctx.mounted) Navigator.of(ctx).pop();
  }

  void _showDialog(Map<String, dynamic> req) {
    final options = ((req['options'] as List?) ?? const <dynamic>[])
        .cast<Map<String, dynamic>>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isLight = !widget.state.darkMode;
        return AlertDialog(
          title: Text('${req['title']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${req['message']}', style: const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 16),
                for (final o in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _close('${o['id']}', req, ctx),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: isLight ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937),
                            border: Border.all(
                              color: isLight ? const Color(0xFFE5E7EB) : const Color(0xFF374151),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${o['label']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              if (o['description'] != null && (o['description'] as String).isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text('${o['description']}', style: TextStyle(fontSize: 12, color: AppColors.of(ctx).hintText)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => _close(null, req, ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// AI 消息生成的最终回复下方常驻操作栏：token 统计（输出 · 输入缓存命中/未命中 ·
/// 输出速度）+ 复制 / 编辑（截断本条并回填上一条用户消息）/ 重试（截断本条自动重发）。
/// 灰调小字 + 细图标按钮，与用户消息悬停操作（_UserBubbleHover）风格一致。
class _AiBubbleActionBar extends StatelessWidget {
  final ChatMessage msg;
  final int? msgIndex;
  final bool light;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onRetry;
  const _AiBubbleActionBar({
    required this.msg,
    required this.msgIndex,
    required this.light,
    required this.onCopy,
    required this.onEdit,
    required this.onRetry,
  });

  /// "输出 312 · 命中 400 · 未命中 800 · 45.2 tok/s"；
  /// 命中/未命中为 DeepSeek 等网关的输入缓存统计（无该信息时不显示该项）；
  /// 生成耗时缺失时省略速度；无任何 token 信息时返回 null。
  String? get _tokenText {
    final out = msg.outputTokens;
    final hit = msg.inputCacheHitTokens;
    final miss = msg.inputCacheMissTokens;
    if (out == null && hit == null && miss == null) return null;
    final parts = <String>[];
    if (out != null) parts.add('输出 $out');
    if (miss != null) parts.add('未命中 $miss');
    if (hit != null) parts.add('命中 $hit');
    final ms = msg.generationMs;
    if (out != null && ms != null && ms > 0) {
      parts.add('${(out / (ms / 1000.0)).toStringAsFixed(1)} tok/s');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors(light);
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 10),
      child: Row(children: [
        if (_tokenText != null)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Tooltip(
                message: '输出 token · 输入缓存未命中/命中（DeepSeek 命中输入免费）',
                child: Text(
                  _tokenText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.textSecondary),
                ),
              ),
            ),
          ),
        _AiActionIcon(icon: Icons.copy_rounded, tip: '复制', light: light, onTap: onCopy),
        const SizedBox(width: 2),
        if (msgIndex != null)
          _AiActionIcon(icon: Icons.edit_outlined, tip: '编辑（截断本条并回填上一条消息）', light: light, onTap: onEdit),
        if (msgIndex != null) const SizedBox(width: 2),
        if (msgIndex != null)
          _AiActionIcon(icon: Icons.refresh_rounded, tip: '重试', light: light, onTap: onRetry),
      ]),
    );
  }
}

/// AI 消息操作栏细图标按钮（灰调无边框，悬停加深）
class _AiActionIcon extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool light;
  const _AiActionIcon({required this.icon, required this.tip, required this.onTap, required this.light});

  @override
  Widget build(BuildContext context) {
    final c = AppColors(light);
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: c.textSecondary),
        ),
      ),
    );
  }
}

/// R22: 用户消息气泡悬停操作（复制 / 编辑重答）——仿 ChatGPT。
/// 悬停时在气泡下缘右侧浮出操作按钮，不占布局空间；
/// 编辑 = 从该条消息截断会话（含此条及之后全部删除），并把文本回填输入框。
class _UserBubbleHover extends StatefulWidget {
  final String content;
  final int? msgIndex;
  final VoidCallback? onEdit;
  final Widget child;
  final bool light;
  /// R26: 触屏模式——长按气泡切换操作按钮显隐（桌面端为悬停触发）
  final bool tapToggles;
  const _UserBubbleHover({
    required this.content,
    required this.msgIndex,
    required this.onEdit,
    required this.child,
    required this.light,
    this.tapToggles = false,
  });

  @override
  State<_UserBubbleHover> createState() => _UserBubbleHoverState();
}

class _UserBubbleHoverState extends State<_UserBubbleHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        // R26: 移动端长按切换（桌面端无长按绑定，不影响悬停）
        onLongPress: widget.tapToggles ? () => setState(() => _hover = !_hover) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.child,
            // R27: 气泡下方 26px 常驻交互带——鼠标移到气泡周围（含按钮区）不丢失
            // 悬停状态，复制/编辑按钮始终可点，不再"移向按钮就消失"
            SizedBox(
              height: 26,
              child: IgnorePointer(
                ignoring: !_hover,
                child: AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _BubbleActionIcon(
                    icon: Icons.copy_rounded,
                    tip: '复制',
                    light: widget.light,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: widget.content));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已复制', style: TextStyle(fontSize: 12.5)),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(milliseconds: 1200),
                          ),
                        );
                      }
                    },
                  ),
                  if (widget.onEdit != null) const SizedBox(width: 6),
                  if (widget.onEdit != null)
                    _BubbleActionIcon(
                      icon: Icons.edit_outlined,
                      tip: '编辑（截断此后对话）',
                      light: widget.light,
                      onTap: widget.onEdit!,
                    ),
                ]),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// 悬停操作小图标按钮
class _BubbleActionIcon extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool light;
  const _BubbleActionIcon({required this.icon, required this.tip, required this.onTap, required this.light});

  @override
  Widget build(BuildContext context) {
    final c = AppColors(light);
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: c.isLight ? Colors.white : const Color(0xFF2A2A32),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.divider),
          ),
          child: Icon(icon, size: 14, color: c.textSecondary),
        ),
      ),
    );
  }
}

/// R24: 输入栏上下文占用圆环（仿 Cherry Studio）：环形进度 + 百分比，
/// 点击打开上下文分布详情弹窗。颜色随占用率 绿→黄→红。
class _ContextUsageRing extends StatelessWidget {
  final AppState s;
  final VoidCallback onTap;
  final GlobalKey? anchorKey;
  const _ContextUsageRing({required this.s, required this.onTap, this.anchorKey});

  @override
  Widget build(BuildContext context) {
    final bd = s.contextTokenBreakdown();
    final ratio = bd.maxTokens <= 0 ? 0.0 : (bd.used / bd.maxTokens).clamp(0.0, 1.0);
    // R28: 圆环与文字统一浅灰（不再按占用率变色）
    const color = Color(0xFF9AA3AF);
    return KeyedSubtree(
      key: anchorKey,
      child: GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '上下文占用 ${bd.formatUsedPct()}（点击查看分布）',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox(
            width: 26,
            height: 26,
            child: Stack(alignment: Alignment.center, children: [
              CustomPaint(
                size: const Size(26, 26),
                painter: _ContextRingPainter(ratio: ratio, color: color),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1,
                  decoration: TextDecoration.none,
                ),
              ),
            ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆环绘制：灰色底环 + 彩色进度弧（12 点方向起）
class _ContextRingPainter extends CustomPainter {
  final double ratio;
  final Color color;
  _ContextRingPainter({required this.ratio, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 2.6;
    final inset = strokeWidth / 2 + 0.5;
    final arcRect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color.withValues(alpha: 0.28);
    canvas.drawArc(arcRect, 0, 6.2831853, false, track);
    if (ratio > 0.005) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(arcRect, -1.5707963, 6.2831853 * ratio, false, arc);
    }
  }

  @override
  bool shouldRepaint(_ContextRingPainter old) => old.ratio != ratio || old.color != color;
}

/// 「思考过程」折叠容器（仿 TraeWork）：把思考段 + 工具调用时间线收进一个
/// 可展开/收起的块。运行中默认展开（用户看得到进度），结束后自动收起，
/// 点击 header 随时切换。展开内容左侧带竖线连接，保持时间线视觉。
class _ThinkingFold extends StatefulWidget {
  final List<Widget> children;
  final bool running;
  final bool light;

  const _ThinkingFold({required this.children, required this.running, required this.light});

  @override
  State<_ThinkingFold> createState() => _ThinkingFoldState();
}

class _ThinkingFoldState extends State<_ThinkingFold> {
  late bool _expanded;
  bool _wasRunning = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.running;
    _wasRunning = widget.running;
  }

  @override
  void didUpdateWidget(covariant _ThinkingFold old) {
    super.didUpdateWidget(old);
    // 运行结束：自动收起（用户需要细节时点开）
    if (_wasRunning && !widget.running && _expanded) {
      setState(() => _expanded = false);
    }
    _wasRunning = widget.running;
  }

  Color get _subText => widget.light ? const Color(0xFF85859A) : const Color(0xFFADADB8);
  Color get _lineColor => widget.light ? const Color(0xFFDDDEE6) : const Color(0xFF3A3D46);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('思考过程',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500,
                    color: widget.light ? const Color(0xFF6B6D78) : _subText)),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 160),
              child: Icon(Icons.chevron_right_rounded, size: 16, color: _subText),
            ),
          ]),
        ),
      ),
      // 展开内容：左侧竖线 + 缩进（时间线视觉）
      AnimatedCrossFade(
        firstChild: const SizedBox(width: double.infinity),
        secondChild: Container(
          margin: const EdgeInsets.only(left: 6, top: 2, bottom: 4),
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: _lineColor, width: 1.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.children),
        ),
        crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 160),
      ),
    ]);
  }
}
