/// AI 头像公共组件：按模型名匹配内置品牌 logo + 品牌色。
///
/// 多专家团 / 辩论模式等多智能体页面共用，避免各页面复制一套图标匹配逻辑。
/// 与 main.dart 中的私有实现保持一致（那里是单模型助手面板），
/// 这里做成公共函数供多模型同屏展示的场景使用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 根据模型名称返回对应的图标 asset 路径（兜底 minimax.svg，永不返回 null）
String aiIconAssetFor(String modelName) {
  final lower = modelName.toLowerCase();
  if (lower.contains('gpt-4') || lower.contains('gpt-3.5') || lower.contains('openai')) return 'assets/ai-icons/openai.svg';
  if (lower.contains('claude') || lower.contains('anthropic')) return 'assets/ai-icons/claude.svg';
  if (lower.contains('glm') || lower.contains('chatglm') || lower.contains('zhipu') || lower.contains('智谱')) return 'assets/ai-icons/glm.png';
  if (lower.contains('qwen') || lower.contains('千问') || lower.contains('通义') || lower.contains('qwq') || lower.contains('qvq')) return 'assets/ai-icons/qwen.svg';
  if (lower.contains('deepseek') || lower.contains('deep-seek')) return 'assets/ai-icons/deepseek.svg';
  if (lower.contains('gemini') || lower.contains('google')) return 'assets/ai-icons/gemini.svg';
  if (lower.contains('doubao') || lower.contains('豆包') || lower.contains('seed-')) return 'assets/ai-icons/doubao.svg';
  if (lower.contains('minimax') || lower.contains('hy3')) return 'assets/ai-icons/minimax.svg';
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
  if (lower.contains('together') || lower.contains('llama-3') || lower.contains('qwen2-')) return 'assets/ai-icons/together.svg';
  if (lower.contains('longcat') || lower.contains('long-cat') || lower.contains('龙猫') || lower.contains('美团')) return 'assets/ai-icons/longcat.svg';
  if (lower.contains('taichu') || lower.contains('太初')) return 'assets/ai-icons/zhipu.svg';
  return 'assets/ai-icons/minimax.svg';
}

/// AI 模型品牌色（首色, 尾色），用于头像渐变底与消息强调色
(Color, Color) aiBrandColorsFor(String model) {
  final lower = model.toLowerCase();
  if (lower.contains('hy3') || lower.contains('minimax')) return (const Color(0xFF00C3FF), const Color(0xFF00E0A8));
  if (lower.contains('glm') || lower.contains('zhipu') || lower.contains('chatglm')) return (const Color(0xFF3B82F6), const Color(0xFF22D3EE));
  if (lower.contains('qwen') || lower.contains('千问')) return (const Color(0xFF6366F1), const Color(0xFF8B5CF6));
  if (lower.contains('deepseek')) return (const Color(0xFF4D6BFE), const Color(0xFF8B5CF6));
  if (lower.contains('kimi') || lower.contains('moonshot')) return (const Color(0xFFF59E0B), const Color(0xFFF97316));
  if (lower.contains('gemini') || lower.contains('google')) return (const Color(0xFF4285F4), const Color(0xFF9B72CB));
  if (lower.contains('doubao') || lower.contains('豆包')) return (const Color(0xFF2563EB), const Color(0xFF60A5FA));
  if (lower.contains('gpt') || lower.contains('openai')) return (const Color(0xFF10A37F), const Color(0xFF34D399));
  if (lower.contains('step') || lower.contains('阶跃')) return (const Color(0xFF6366F1), const Color(0xFF22D3EE));
  if (lower.contains('claude') || lower.contains('anthropic')) return (const Color(0xFFD97757), const Color(0xFFF0A882));
  if (lower.contains('hunyuan') || lower.contains('混元')) return (const Color(0xFF0052D9), const Color(0xFF4E8BFF));
  if (lower.contains('wenxin') || lower.contains('文心') || lower.contains('ernie')) return (const Color(0xFF2932E1), const Color(0xFF6D7BFF));
  if (lower.contains('spark') || lower.contains('星火')) return (const Color(0xFF0066FF), const Color(0xFF4DA3FF));
  if (lower.contains('grok') || lower.contains('xai')) return (const Color(0xFF111827), const Color(0xFF4B5563));
  if (lower.contains('mistral') || lower.contains('mixtral')) return (const Color(0xFFFF7000), const Color(0xFFFFA755));
  if (lower.contains('llama') || lower.contains('meta-')) return (const Color(0xFF0668E1), const Color(0xFF4FA0FF));
  if (lower.contains('longcat') || lower.contains('龙猫')) return (const Color(0xFFFF6B35), const Color(0xFFFFA94D));
  return (const Color(0xFF7C3AED), const Color(0xFFA78BFA));
}

/// 品牌 logo 头像：圆形渐变底 + 内置品牌图标。
/// [dark] 深色模式下自动提亮品牌色，保证 logo 在深色底上可辨识。
class AiAvatar extends StatelessWidget {
  final String model;
  final double size;
  final bool dark;

  const AiAvatar({super.key, required this.model, this.size = 28, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final asset = aiIconAssetFor(model);
    final (c1, c2) = aiBrandColorsFor(model);
    final brand = dark ? Color.lerp(c1, Colors.white, 0.35)! : c1;
    final bg = dark
        ? Color.lerp(const Color(0xFF1A1A2E), c2, 0.22)!
        : Color.lerp(Colors.white, c2, 0.16)!;
    Widget logo;
    if (asset.toLowerCase().endsWith('.png')) {
      logo = Image.asset(
        asset,
        width: size * 0.62,
        height: size * 0.62,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else {
      logo = SvgPicture.asset(
        asset,
        width: size * 0.62,
        height: size * 0.62,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(brand, BlendMode.srcIn),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg, Color.lerp(bg, c2, 0.35)!],
        ),
        border: Border.all(color: brand.withValues(alpha: dark ? 0.35 : 0.28), width: 1),
      ),
      child: Center(child: logo),
    );
  }
}
