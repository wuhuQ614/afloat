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
import 'widgets/gomoku_page.dart';
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
  (Icons.grid_3x3_rounded, '五子棋', '双人对战五子连珠', 23),
];

// 更多功能选择页索引
const _morePageIndex = 9;

// ===== _buildPage 路由入口（节选） =====

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

// ===== AI 图标识别与品牌色（节选） =====

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
    // LongCat / Longcat / 紫东太初：暂用 mistral 作 fallback（猫形相近）
    if (lower.contains('longcat') || lower.contains('long-cat')) return 'assets/ai-icons/mistral.svg';
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
