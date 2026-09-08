/// AI 服务商目录：内置 Base URL 与「获取 API 密钥」链接，
/// 用户无需手动输入 API 地址。数据来源为各服务商官方文档（2026-09 核实）。
library;

import 'package:flutter/material.dart';

class AiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final String keyUrl; // 获取 API 密钥的官网链接
  final Color color; // 图标徽章底色
  final String badge; // 徽章文字（缩写/汉字）
  final String? defaultModel; // 默认模型名（可选）

  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.keyUrl,
    required this.color,
    required this.badge,
    this.defaultModel,
  });
}

/// 服务商列表（顺序与设计稿一致；自定义模型单独置顶处理，不在列）
const List<AiProvider> kAiProviders = [
  AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    keyUrl: 'https://platform.deepseek.com/api_keys',
    color: Color(0xFF4D6BFE),
    badge: 'DS',
  ),
  AiProvider(
    id: 'volces',
    name: '火山引擎',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    keyUrl: 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey',
    color: Color(0xFF1664FF),
    badge: '火',
  ),
  AiProvider(
    id: 'minimax_cn',
    name: 'MiniMax CN',
    baseUrl: 'https://api.minimaxi.com/v1',
    keyUrl: 'https://platform.minimaxi.com',
    color: Color(0xFFF23E5B),
    badge: 'MM',
  ),
  AiProvider(
    id: 'minimax_global',
    name: 'MiniMax Global',
    baseUrl: 'https://api.minimax.io/v1',
    keyUrl: 'https://platform.minimax.io',
    color: Color(0xFFF23E5B),
    badge: 'MM',
  ),
  AiProvider(
    id: 'bigmodel',
    name: 'Bigmodel',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    keyUrl: 'https://open.bigmodel.cn/usercenter/apikeys',
    color: Color(0xFF3859FF),
    badge: 'Z',
  ),
  AiProvider(
    id: 'aliyun',
    name: '阿里云',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    keyUrl: 'https://bailian.console.aliyun.com/?apiKey=1',
    color: Color(0xFF615CED),
    badge: '阿',
  ),
  AiProvider(
    id: 'xiaomi_mimo',
    name: 'Xiaomi MIMO',
    baseUrl: 'https://api.xiaomimimo.com/v1',
    keyUrl: 'https://platform.xiaomimimo.com',
    color: Color(0xFFFF6900),
    badge: 'Mi',
    defaultModel: 'mimo-v2.5-pro',
  ),
  AiProvider(
    id: 'siliconflow',
    name: '硅基流动',
    baseUrl: 'https://api.siliconflow.cn/v1',
    keyUrl: 'https://cloud.siliconflow.cn/account/ak',
    color: Color(0xFF7C3AED),
    badge: '硅',
  ),
  AiProvider(
    id: 'zai',
    name: 'Z.ai',
    baseUrl: 'https://api.z.ai/api/paas/v4',
    keyUrl: 'https://z.ai/model-api',
    color: Color(0xFF2E5CE6),
    badge: 'Z',
  ),
  AiProvider(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    keyUrl: 'https://openrouter.ai/settings/keys',
    color: Color(0xFF6467F2),
    badge: 'OR',
  ),
  AiProvider(
    id: 'kimi_cn',
    name: 'Kimi CN',
    baseUrl: 'https://api.moonshot.cn/v1',
    keyUrl: 'https://platform.moonshot.cn/console/api-keys',
    color: Color(0xFF111111),
    badge: 'K',
  ),
  AiProvider(
    id: 'kimi_global',
    name: 'Kimi Global',
    baseUrl: 'https://api.moonshot.ai/v1',
    keyUrl: 'https://platform.moonshot.ai/console/api-keys',
    color: Color(0xFF111111),
    badge: 'K',
  ),
  AiProvider(
    id: 'byteplus',
    name: 'BytePlus',
    baseUrl: 'https://ark.ap-southeast.bytepluses.com/api/v3',
    keyUrl: 'https://console.bytepluses.com/ark/apiKey',
    color: Color(0xFF325AB4),
    badge: 'BP',
  ),
  AiProvider(
    id: 'aws',
    name: 'AWS',
    baseUrl: 'https://bedrock-runtime.us-east-1.amazonaws.com/openai/v1',
    keyUrl: 'https://console.aws.amazon.com/bedrock/home',
    color: Color(0xFF232F3E),
    badge: 'aws',
  ),
  AiProvider(
    id: 'tencent',
    name: '腾讯云',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
    keyUrl: 'https://console.cloud.tencent.com/hunyuan/api-key',
    color: Color(0xFF0052D9),
    badge: '腾',
  ),
  AiProvider(
    id: 'gitee_ai',
    name: '模力方舟',
    baseUrl: 'https://ai.gitee.com/v1',
    keyUrl: 'https://ai.gitee.com/serverless-api-key',
    color: Color(0xFFC71D23),
    badge: '模',
  ),
  AiProvider(
    id: 'ppio',
    name: 'PPIO',
    baseUrl: 'https://api.ppinfra.com/v3/openai',
    keyUrl: 'https://ppinfra.com/user/console/api-keys',
    color: Color(0xFF7C3AED),
    badge: 'P',
  ),
];
