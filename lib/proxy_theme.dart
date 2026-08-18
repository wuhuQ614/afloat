/// Mihomo 控制台专属深色调色板（参考 mihomo_gui_dashboard.html）。
///
/// 设计目标：与主 App（theme_colors.dart）完全独立，使用该页面时视觉上像是
/// 另一个应用，不复用主 App 任何颜色。
library;

import 'package:flutter/material.dart';

/// 背景四层
const Color kProxyBg = Color(0xFF0E0F14); // 全局背景
const Color kProxySidebar = Color(0xFF13141C); // 侧边栏
const Color kProxyCard = Color(0xFF181922); // 卡片
const Color kProxyCardHover = Color(0xFF20222E); // 卡片 hover
const Color kProxyBorder = Color(0xFF272938); // 默认边框
const Color kProxyBorderActive = Color(0xFF7C3AED); // 选中边框
const Color kProxyInputFill = Color(0xFF0B0C10); // 输入框/日志背景

/// 文字
const Color kProxyText = Color(0xFFF1F5F9); // 主文字
const Color kProxyMuted = Color(0xFF94A3B8); // 次要文字

/// 强调
const Color kProxyAccent = Color(0xFF8B5CF6); // 强调
const Color kProxyAccentMuted = Color(0x267C3AED); // 强调浅（alpha）
const Color kProxyAccentSoft = Color(0xFF7C3AED); // 强调主色
const Color kProxySuccess = Color(0xFF34D399); // 成功
const Color kProxyWarn = Color(0xFFFBBF24); // 警告
const Color kProxyDanger = Color(0xFFF87171); // 危险
const Color kProxyInfo = Color(0xFF60A5FA); // 信息

/// 阴影
List<BoxShadow> kProxyGlow = const [
  BoxShadow(
    color: Color(0x597C3AED),
    blurRadius: 20,
    offset: Offset(0, 0),
  ),
];
List<BoxShadow> kProxyGlowSm = const [
  BoxShadow(
    color: Color(0x407C3AED),
    blurRadius: 10,
    offset: Offset(0, 0),
  ),
];

/// 主题上下文（Mihomo 控制台专用，固定深色）
class ProxyColors {
  final bool isLight;
  ProxyColors([this.isLight = false]);

  Color get bg => kProxyBg;
  Color get sidebar => kProxySidebar;
  Color get card => kProxyCard;
  Color get cardHover => kProxyCardHover;
  Color get border => kProxyBorder;
  Color get borderActive => kProxyBorderActive;
  Color get inputFill => kProxyInputFill;
  Color get text => kProxyText;
  Color get muted => kProxyMuted;
  Color get accent => kProxyAccent;
  Color get accentSoft => kProxyAccentSoft;
  Color get success => kProxySuccess;
  Color get warn => kProxyWarn;
  Color get danger => kProxyDanger;
  Color get info => kProxyInfo;
}

/// 通用 18% 透明背景
Color proxySurface(Color c, {double opacity = 0.18}) =>
    c.withValues(alpha: opacity);

/// 通用 30% 透明背景
Color proxyFill(Color c) => c.withValues(alpha: 0.30);
