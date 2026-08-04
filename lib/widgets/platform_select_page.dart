/// 首次启动平台选择页面
library;

import 'package:flutter/material.dart';
import '../theme_colors.dart' show kPrimary, kGradientStart, kGradientEnd;

class PlatformSelectPage extends StatelessWidget {
  final VoidCallback onDesktop;
  final VoidCallback onMobile;

  const PlatformSelectPage({super.key, required this.onDesktop, required this.onMobile});

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF8F6FF) : const Color(0xFF1A1A2E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Logo
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: kPrimary.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 20),
            const Text('afloat', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text('选择你的使用设备', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 40),
            // 电脑端
            _PlatformCard(
              icon: Icons.computer_rounded,
              title: '电脑端',
              subtitle: '侧边栏导航 + AI 助手常驻\n适合大屏桌面使用',
              onTap: onDesktop,
              isLight: isLight,
            ),
            const SizedBox(height: 16),
            // 手机端
            _PlatformCard(
              icon: Icons.phone_android_rounded,
              title: '手机端',
              subtitle: '底部导航栏 + 全屏页面\n适合小屏移动使用',
              onTap: onMobile,
              isLight: isLight,
            ),
          ]),
        ),
      ),
    );
  }
}

class _PlatformCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLight;

  const _PlatformCard({required this.icon, required this.title, required this.subtitle, required this.onTap, required this.isLight});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isLight ? Colors.white : const Color(0xFF2A2A40),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isLight ? const Color(0x0D000000) : Colors.white.withValues(alpha: 0.06)),
          boxShadow: [BoxShadow(color: const Color(0x08000000), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kGradientStart, kGradientEnd]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey.shade500)),
          ])),
          const Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey),
        ]),
      ),
    );
  }
}
