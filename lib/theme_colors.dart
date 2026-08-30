/// 全局主题色常量 - 复刻 afloat 紫色主题
library;

import 'dart:ui';
import 'package:flutter/material.dart';

/// 主色 - 紫色
const Color kPrimary = Color(0xFF7C3AED);
const Color kPrimaryLight = Color(0xFFF3EEFF);
const Color kSuccess = Color(0xFF22C55E);
const Color kDanger = Color(0xFFEF4444);
/// 页面浅色背景 - 纯白
const Color kBgLight = Color(0xFFFFFFFF);
/// 卡片柔和阴影色
const Color kShadow = Color(0x0A000000);
/// 题型卡片选中边框色
const Color kCardSelectedBorder = Color(0xFFC4B5FD);
/// 题型卡片选中背景
const Color kCardSelectedBg = Color(0xFFF5F3FF);
/// 难度选中色
const Color kDifficultySelected = Color(0xFF7C3AED);
/// 滑块活跃色
const Color kSliderActive = Color(0xFF7C3AED);

/// ============== 深色模式专用色（中性深灰 · 三级层次） ==============
/// 层次：背景(最深) → 卡片(中) → 输入框/气泡(最亮)，统一中性灰调
/// 深色模式页面背景（最深层）
const Color kDarkBg = Color(0xFF1A1A1E);
/// 深色模式侧边栏背景（菜单栏，比背景亮一级）
const Color kDarkSidebar = Color(0xFF232328);
/// 深色模式卡片/容器背景（中层，主内容卡片）
const Color kDarkCard = Color(0xFF2B2B32);
/// 深色模式二级容器（输入框/内嵌块/气泡，最亮层）
const Color kDarkCardAlt = Color(0xFF33333A);
/// 深色模式 AI 聊天气泡底色（和二级容器统一）
const Color kDarkChatBubbleAi = Color(0xFF33333A);
/// 深色模式分割线/边框
const Color kDarkBorder = Color(0xFF3D3D45);
/// 深色模式主要文本
const Color kDarkText = Color(0xFFE4E4E8);
/// 深色模式次要文本
const Color kDarkTextSecondary = Color(0xFFADADB8);
/// 深色模式提示/三级文本
const Color kDarkTextTertiary = Color(0xFF85859A);
/// 深色模式轻量背景（紫色调）
const Color kDarkPrimaryLight = Color(0xFF2A2540);

/// 快捷功能卡图标底变体（暖橙/绿/蓝/粉）
enum FeatureIconVariant { warm, green, blue, pink }

/// ============== 固定配色（仅白色 / 深色两种模式） ==============
/// 浅色模式调色板
const Color _lightPrimary = Color(0xFF7C3AED);
const Color _lightGradientStart = Color(0xFFA78BFA);
const Color _lightGradientEnd = Color(0xFF7C3AED);
/// 浅色主题页面背景：柔和中性灰白（避免经典模式纯白刺眼）
const Color _lightBgTint = Color(0xFFF4F4F8);

/// 深色模式调色板（加深加饱和紫色，在纯深灰底上更明显）
const Color _darkPrimary = Color(0xFFA78BFA);
const Color _darkGradientStart = Color(0xFFC4B5FD);
const Color _darkGradientEnd = Color(0xFF8B5CF6);

/// 主题上下文工具：根据 isLight 返回对应颜色
class AppColors {
  /// 高性能模式全局开关（由 AppState 切换时同步）：
  /// 开启后所有半透明玻璃色改为不透明实色，消除透明图层的额外合成开销。
  static bool highPerformance = false;

  final bool isLight;

  AppColors(this.isLight);

  /// 主题主色
  Color get primary => isLight ? _lightPrimary : _darkPrimary;
  Color get gradientStart => isLight ? _lightGradientStart : _darkGradientStart;
  Color get gradientEnd => isLight ? _lightGradientEnd : _darkGradientEnd;

  /// 深色模式下主色的可读亮变体
  Color get primaryBright => isLight ? primary : Color.lerp(primary, Colors.white, 0.45)!;

  Color get bg => isLight ? _lightBgTint : kDarkBg;
  Color get card => glassCardColor(isLight);
  /// 不透明卡片色（弹窗/对话框专用）：玻璃主题下 card 为 78% 半透明白，
  /// 作为 Dialog 底色会让下层页面（毛玻璃背景 + 粒子动效）持续参与合成，
  /// 滚动/输入时开销明显；弹窗一律用此实底色，等价于高性能模式下的 card
  Color get cardSolid => isLight ? Colors.white : kDarkCard;
  Color get sidebar => glassSidebarColor(isLight);
  Color get border => glassBorderColor(isLight);
  Color get cardAlt => isLight ? _lightBgTint : kDarkCardAlt;
  Color get text => isLight ? const Color(0xFF1A1A2E) : kDarkText;
  Color get textSecondary => isLight ? Colors.grey.shade700 : kDarkTextSecondary;
  Color get textTertiary => isLight ? Colors.grey.shade500 : kDarkTextTertiary;
  Color get primaryLight => isLight ? Color.alphaBlend(_lightPrimary.withValues(alpha: 0.08), _lightBgTint) : kDarkPrimaryLight;
  Color get inputFill => isLight ? Color.alphaBlend(_lightPrimary.withValues(alpha: 0.05), Colors.white) : kDarkChatBubbleAi;
  Color get chipUnselected => isLight ? _lightBgTint : kDarkChatBubbleAi;
  Color get chipBorder => isLight ? const Color(0xFFE5E7EB) : kDarkBorder;

  // 工具色
  Color get divider => isLight ? const Color(0x0D000000) : Colors.white.withValues(alpha: 0.08);
  Color get overlay => isLight ? Colors.white : kDarkCard;
  Color get chatBubbleAi => isLight ? Colors.white : kDarkChatBubbleAi;
  Color get hintText => isLight ? const Color(0xFF9CA3AF) : const Color(0xFF6B6B85);
  Color get titleText => isLight ? const Color(0xFF1A1A2E) : kDarkText;
  Color get successBg => isLight ? kSuccess.withValues(alpha: 0.08) : kSuccess.withValues(alpha: 0.18);
  Color get successBorder => isLight ? kSuccess.withValues(alpha: 0.3) : kSuccess.withValues(alpha: 0.4);
  Color get dangerBg => isLight ? kDanger.withValues(alpha: 0.08) : kDanger.withValues(alpha: 0.18);
  Color get dangerBorder => isLight ? kDanger.withValues(alpha: 0.25) : kDanger.withValues(alpha: 0.4);
  Color get primaryBg => isLight ? _lightPrimary.withValues(alpha: 0.08) : _darkPrimary.withValues(alpha: 0.38);
  Color get primaryBgStrong => isLight ? _lightPrimary.withValues(alpha: 0.15) : _darkPrimary.withValues(alpha: 0.52);
  Color get primaryBorder => isLight ? _lightPrimary.withValues(alpha: 0.3) : _darkPrimary.withValues(alpha: 0.72);
  Color get sliderInactive => isLight ? const Color(0xFFE5E7EB) : const Color(0xFF4A4A4A);
  Color get warning => isLight ? const Color(0xFFF59E0B) : const Color(0xFFFBBF24);
  Color get warningBg => isLight ? const Color(0xFFF59E0B).withValues(alpha: 0.08) : const Color(0xFFFBBF24).withValues(alpha: 0.2);
  Color get scoreHigh => isLight ? kSuccess : const Color(0xFF4ADE80);
  Color get scoreMid => isLight ? const Color(0xFFF59E0B) : const Color(0xFFFBBF24);
  Color get scoreLow => isLight ? kDanger : const Color(0xFFF87171);
  Color get progressBg => isLight ? _lightPrimary.withValues(alpha: 0.1) : _darkPrimary.withValues(alpha: 0.42);
  Color get shadowLight => isLight ? const Color(0x08000000) : const Color(0x30000000);
  Color get shadowMedium => isLight ? const Color(0x0A000000) : const Color(0x40000000);
  LinearGradient get primaryGradient => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [gradientStart, gradientEnd],
    );
  Color get orangeBg => isLight ? Colors.orange.withValues(alpha: 0.12) : Colors.orange.withValues(alpha: 0.22);
  Color get cardSelectedBg => isLight ? Color.alphaBlend(_lightPrimary.withValues(alpha: 0.06), Colors.white) : _darkPrimary.withValues(alpha: 0.38);
  Color get primaryText => isLight ? primary : primaryBright;
  Color get inputHint => isLight ? Colors.grey.shade400 : Colors.grey.shade600;

  Color featureIconBg(FeatureIconVariant v) {
    if (isLight) {
      return switch (v) {
        FeatureIconVariant.warm => const Color(0xFFFFF3E0),
        FeatureIconVariant.green => const Color(0xFFE8F5E9),
        FeatureIconVariant.blue => const Color(0xFFE3F2FD),
        FeatureIconVariant.pink => const Color(0xFFFCE4EC),
      };
    }
    final base = switch (v) {
      FeatureIconVariant.warm => const Color(0xFFFF9800),
      FeatureIconVariant.green => const Color(0xFF4CAF50),
      FeatureIconVariant.blue => const Color(0xFF2196F3),
      FeatureIconVariant.pink => const Color(0xFFE91E63),
    };
    return base.withValues(alpha: 0.18);
  }

  Color get chipSelectedBg => isLight ? _lightPrimary.withValues(alpha: 0.08) : _darkPrimary.withValues(alpha: 0.42);
  Color get chipSelectedBorder => isLight ? _lightPrimary : _darkPrimary.withValues(alpha: 0.9);
  Color get chipSelectedText => isLight ? _lightPrimary : primaryBright;

  Color get appBgGradientTop => isLight ? _lightBgTint : kDarkBg;
  Color get appBgGradientBottom =>
      isLight ? _lightBgTint : kDarkBg;

  List<({Color color, double alpha})> get glowColors => [
        (color: primary, alpha: isLight ? 0.12 : 0.18),
        (color: gradientStart, alpha: isLight ? 0.10 : 0.14),
        (color: gradientEnd, alpha: isLight ? 0.07 : 0.10),
      ];

  static Color glassCardColor(bool isLight) {
    if (!isLight) return kDarkCard;
    // 高性能模式：不透明纯白卡片，避免半透明图层的合成开销
    if (highPerformance) return Colors.white;
    return Colors.white.withValues(alpha: 0.78);
  }

  static Color glassSidebarColor(bool isLight) {
    if (!isLight) return kDarkSidebar;
    // 高性能模式：不透明浅灰白侧边栏
    if (highPerformance) return _lightBgTint;
    return Colors.white.withValues(alpha: 0.65);
  }

  static Color glassBorderColor(bool isLight) =>
      isLight ? Colors.black.withValues(alpha: 0.06) : kDarkBorder;

  static AppColors of(BuildContext context) =>
      AppColors(Theme.of(context).brightness == Brightness.light);
}

/// 学习报告 / 成绩分析页专属配色：企业蓝 + 语义色（绿/青/琥珀）+ 中性灰图表，
/// 不随应用紫色主题（大厂数据面板风格：中性底 + 单一强调色 + 语义点缀）。
class ReportPalette {
  final bool isLight;
  const ReportPalette({required this.isLight});

  /// 主强调：企业蓝（链接/今日柱/环形进度/指示条）
  Color get accent => isLight ? const Color(0xFF2563EB) : const Color(0xFF60A5FA);
  Color get accentSoft => isLight ? const Color(0xFFEFF6FF) : const Color(0xFF1C2B4D);
  Color get accentBright => isLight ? const Color(0xFF60A5FA) : const Color(0xFF93C5FD);

  /// 语义色：平均得分（青）、达标率（绿）、学习时长（琥珀）
  Color get teal => isLight ? const Color(0xFF0F766E) : const Color(0xFF2DD4BF);
  Color get tealSoft => isLight ? const Color(0xFFF0FDFA) : const Color(0xFF10312D);
  Color get green => isLight ? const Color(0xFF16A34A) : const Color(0xFF4ADE80);
  Color get greenSoft => isLight ? const Color(0xFFF0FDF4) : const Color(0xFF12301D);
  Color get amber => isLight ? const Color(0xFFD97706) : const Color(0xFFFBBF24);
  Color get amberSoft => isLight ? const Color(0xFFFFFBEB) : const Color(0xFF3A2C10);

  /// 图表中性与轨道色
  Color get barTrack => isLight ? const Color(0xFFE8ECF2) : const Color(0xFF3A3A44);
  Color get ringTrack => isLight ? const Color(0xFFEDF0F5) : const Color(0xFF3A3A44);
  Color get chip => isLight ? const Color(0xFFF3F4F6) : const Color(0xFF33333A);
  Color get pageBg => isLight ? const Color(0xFFF5F6FA) : const Color(0xFF1A1A1E);
  Color get cardBg => isLight ? Colors.white : const Color(0xFF2A2A32);

  /// 得分分档色（历史记录/成绩分析共用）：橙（≥70%）→ 深橙（≥40%）→ 红（<40%）
  Color scoreByPct(double pct) {
    if (pct >= 0.7) return isLight ? const Color(0xFFEA8A1F) : const Color(0xFFFBA24C);
    if (pct >= 0.4) return isLight ? const Color(0xFFE0642A) : const Color(0xFFFF8A5C);
    return isLight ? const Color(0xFFDC4A4A) : const Color(0xFFFF7070);
  }

  /// 题型进度条四档：绿（≥80%）/ 蓝（≥60%）/ 琥珀（≥40%）/ 红
  Color barByPct(double pct) {
    if (pct >= 0.8) return green;
    if (pct >= 0.6) return accent;
    if (pct >= 0.4) return amber;
    return isLight ? const Color(0xFFDC4A4A) : const Color(0xFFFF7070);
  }

  /// 评级：(标签, 前景色, 底色)。≥85% 优秀 / ≥70% 良好 / ≥60% 合格 / 其余待提升
  (String, Color, Color) rankOf(double pct) {
    if (pct >= 0.85) return ('优秀', green, greenSoft);
    if (pct >= 0.70) return ('良好', accent, accentSoft);
    if (pct >= 0.60) return ('合格', amber, amberSoft);
    return ('待提升', isLight ? const Color(0xFFDC4A4A) : const Color(0xFFFF7070), isLight ? const Color(0xFFFEF2F2) : const Color(0xFF3A1A1A));
  }
}
