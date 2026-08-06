/// 首次启动平台选择页面 — 仿截图风格：淡紫渐变背景 + 居中卡片
library;

import 'dart:ui';
import 'package:flutter/material.dart';

class PlatformSelectPage extends StatelessWidget {
  final VoidCallback onDesktop;
  final VoidCallback onMobile;

  const PlatformSelectPage({super.key, required this.onDesktop, required this.onMobile});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth < 500 ? (screenWidth - 64).clamp(260.0, 400.0) : 420.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF3F0FF), // 淡紫
              Color(0xFFF8F7FF), // 近白
              Color(0xFFEEF0FF), // 淡蓝紫
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // 标题
              const Text(
                '选择你的使用方式',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1C1C1E),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '一个应用，多端体验',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(height: 48),
              // 电脑端卡片
              _DeviceCard(
                icon: Icons.laptop_mac_outlined,
                title: '电脑端',
                desc: '大屏工作流\nAI 助手常驻',
                onTap: onDesktop,
                width: cardWidth,
              ),
              const SizedBox(height: 20),
              // 手机端卡片
              _DeviceCard(
                icon: Icons.phone_iphone_outlined,
                title: '手机端',
                desc: '随时学习\n移动体验',
                onTap: onMobile,
                width: cardWidth,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;
  final double width;

  const _DeviceCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(children: [
          // 图标容器
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
            ),
            child: Icon(icon, size: 28, color: const Color(0xFF1C1C1E)),
          ),
          const SizedBox(height: 16),
          // 标题
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(height: 8),
          // 描述
          Text(
            desc,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Color(0xFF8E8E93),
            ),
          ),
        ]),
      ),
    );
  }
}
