/// 暴力数字（随机数）页面：一比一复刻参考项目 NumberTab.jsx。
///
/// 参考实现：
/// - 默认范围 1-100，min/max 两个输入框
/// - 点击"暴力生成数字"：70ms 间隔跳变，25 次后定格
/// - 开始播 playTick，结束播 playNumberDing
/// - 结果在紫色圆形容器中放大展示，生成中容器放大 1.1 倍
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../theme_colors.dart';
import 'tools_audio.dart';

class NumberTabPage extends StatefulWidget {
  const NumberTabPage({super.key});

  @override
  State<NumberTabPage> createState() => _NumberTabPageState();
}

class _NumberTabPageState extends State<NumberTabPage> {
  final TextEditingController _minCtrl = TextEditingController(text: '1');
  final TextEditingController _maxCtrl = TextEditingController(text: '100');
  int? _num;
  bool _isGenerating = false;
  Timer? _timer;
  /// P1-2：用 ValueNotifier 隔离数字跳变，避免每 70ms 重建整个页面
  final ValueNotifier<int?> _numNotifier = ValueNotifier(null);

  @override
  void dispose() {
    _timer?.cancel();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _numNotifier.dispose();
    super.dispose();
  }

  void _generate() {
    if (_isGenerating) return;
    final minV = int.tryParse(_minCtrl.text) ?? 1;
    final maxV = int.tryParse(_maxCtrl.text) ?? 100;
    if (maxV < minV) return;

    ToolsAudio.instance.playTick();
    HapticFeedback.lightImpact(); // 对齐参考项目 vibrate(20)
    setState(() => _isGenerating = true);

    final rng = math.Random();
    var count = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 70), (timer) {
      // P1-2：只更新 ValueNotifier，不触发整页 setState
      _numNotifier.value = minV + rng.nextInt(maxV - minV + 1);
      count++;
      if (count > 25) {
        timer.cancel();
        ToolsAudio.instance.playNumberDing(); // 对齐参考项目 playNumberDing
        HapticFeedback.heavyImpact(); // 对齐参考项目 vibrate([50,50])
        setState(() {
          _isGenerating = false;
          _num = _numNotifier.value;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 结果圆形容器
          AnimatedScale(
            scale: _isGenerating ? 1.1 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              width: 192,
              height: 192,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.isLight ? Colors.white : const Color(0xFF1F2937),
                border: Border.all(
                  color: _isGenerating
                      ? const Color(0x66A855F7)
                      : (c.isLight
                          ? const Color(0xFFF3E8FF)
                          : const Color(0xFF581C87)),
                  width: 8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                // P1-2：ValueListenableBuilder 隔离数字显示区域，仅数字文本随跳变重建
                child: ValueListenableBuilder<int?>(
                  valueListenable: _numNotifier,
                  builder: (context, notifierNum, _) {
                    final displayNum = _isGenerating ? notifierNum : _num;
                    return Text(
                      displayNum == null ? '?' : '$displayNum',
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF9333EA),
                        letterSpacing: -2,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 48),
          // min / max 输入
          SizedBox(
            width: 320,
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最小值',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: c.textTertiary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _minCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      enabled: !_isGenerating,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: c.text),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: c.isLight
                            ? const Color(0xFFF3F4F6)
                            : const Color(0xFF1F2937),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最大值',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: c.textTertiary)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _maxCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      enabled: !_isGenerating,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: c.text),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: c.isLight
                            ? const Color(0xFFF3F4F6)
                            : const Color(0xFF1F2937),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          // 生成按钮（对齐参考项目紫色渐变 from-purple-600 to-fuchsia-600）
          SizedBox(
            width: 320,
            child: GestureDetector(
              onTap: _isGenerating ? null : _generate,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  gradient: _isGenerating
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF9333EA), Color(0xFFC026D3)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                  color: _isGenerating ? Colors.grey : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _isGenerating
                      ? null
                      : [
                          BoxShadow(
                            color: const Color(0xFF9333EA).withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tag, size: 24, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        _isGenerating ? '暴力计算中...' : '暴力生成数字',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
