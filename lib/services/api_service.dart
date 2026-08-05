/// AI 接口服务：非流式调用 + SSE 流式对话，兼容 OpenAI / DeepSeek 等 API
library;

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models.dart';

/// AI 非流式调用结果：content 为 null 表示请求失败；finishReason 用于检测输出截断（'length'）
class AIResult {
  final String? content;
  final String? finishReason;
  const AIResult(this.content, this.finishReason);
}

class ApiService {
  /// 模型名映射（UI 显示名 → 真实 API 模型名）
  static String _realModel(String model) {
    const map = {
      'gpt-5.1': 'gpt-4o',
      'gpt-5.1-instant': 'gpt-4o-mini',
      'gpt-5.5': 'gpt-4o',
      'gpt-4o': 'gpt-4o',
    };
    return map[model] ?? model;
  }

  /// 对外暴露的真实 API 模型名（供调用方按模型名选择请求参数）
  static String realModelName(String model) => _realModel(model);

  /// 厂家默认温度
  static double _defaultTemp(String model) {
    if (model == 'deepseek-v4-pro') return 0.0;
    if (model == 'deepseek-v4-flash') return 1.0;
    return 0.7;
  }

  static double _resolveTemp(ApiConfig cfg, double? override) {
    if (override != null) return override;
    final t = cfg.temperature;
    if (t.isNotEmpty && t != 'default') {
      final v = double.tryParse(t);
      if (v != null) return v;
    }
    return _defaultTemp(cfg.model);
  }

  /// 将文本 + 可选图片（base64 data URL）构造成 OpenAI 兼容的多模态 content。
  /// 图片为空时返回纯文本字符串，兼容纯文本模型。
  static Object buildContent(String text, String? imageData) {
    if (imageData == null || imageData.isEmpty) return text;
    return [
      {'type': 'text', 'text': text},
      {'type': 'image_url', 'image_url': {'url': imageData}},
    ];
  }

  /// 非流式调用，返回完整内容文本；失败返回 null
  /// extraParams：额外请求体参数（透传到请求体顶层，仅限调用方按需传入）
  static Future<String?> callAI(
    List<Map<String, dynamic>> messages,
    String systemPrompt, {
    ApiConfig? config,
    int maxTokens = 4096,
    double? temperature,
    Map<String, dynamic>? extraParams,
  }) async {
    final r = await callAIResult(messages, systemPrompt,
        config: config, maxTokens: maxTokens, temperature: temperature, extraParams: extraParams);
    return r.content;
  }

  /// 非流式调用，返回 AIResult（含 finish_reason，供调用方检测 'length' 截断）；失败时 content 为 null
  static Future<AIResult> callAIResult(
    List<Map<String, dynamic>> messages,
    String systemPrompt, {
    ApiConfig? config,
    int maxTokens = 4096,
    double? temperature,
    Map<String, dynamic>? extraParams,
  }) async {
    final cfg = config;
    if (cfg == null || !cfg.ready) return const AIResult(null, null);
    try {
      final body = <String, dynamic>{
        'model': _realModel(cfg.model),
        'temperature': _resolveTemp(cfg, temperature),
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...messages,
        ],
      };
      if (extraParams != null && extraParams.isNotEmpty) {
        body.addAll(extraParams);
      }
      final resp = await http
          .post(
            Uri.parse(cfg.effectiveUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${cfg.key}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) return const AIResult(null, null);
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) return const AIResult(null, null);
      final choice = choices.first as Map<String, dynamic>;
      final msg = choice['message'] as Map<String, dynamic>?;
      return AIResult((msg?['content'] as String?) ?? '', choice['finish_reason']?.toString());
    } catch (_) {
      return const AIResult(null, null);
    }
  }

  /// 流式对话（SSE）。onReasoning/onDelta 回调增量内容，返回完整内容
  static Future<String> streamChat(
    List<Map<String, dynamic>> messages,
    String systemPrompt, {
    ApiConfig? config,
    void Function(String chunk)? onReasoning,
    void Function(String chunk)? onDelta,
    double? temperature,
  }) async {
    final cfg = config;
    if (cfg == null || !cfg.ready) return '';
    String full = '';
    try {
      final body = {
        'model': _realModel(cfg.model),
        'temperature': _resolveTemp(cfg, temperature),
        'stream': true,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...messages,
        ],
      };
      final req = http.Request('POST', Uri.parse(cfg.url));
      req.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${cfg.key}',
      });
      req.body = jsonEncode(body);
      final streamed = await http.Client().send(req).timeout(const Duration(seconds: 120));
      if (streamed.statusCode != 200) return '';
      final lines = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed == 'data: [DONE]') break;
        if (!trimmed.startsWith('data: ')) continue;
        final data = trimmed.substring(6);
        try {
          final obj = jsonDecode(data) as Map<String, dynamic>;
          final choices = obj['choices'] as List?;
          if (choices == null || choices.isEmpty) continue;
          final delta = (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>? ?? {};
          final reasoning = delta['reasoning_content'] as String?;
          if (reasoning != null && reasoning.isNotEmpty && onReasoning != null) {
            onReasoning(reasoning);
          }
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            full += content;
            if (onDelta != null) onDelta(content);
          }
        } catch (_) {
          // 忽略单行解析失败（可能为注释行等）
        }
      }
    } catch (_) {
      // 流中断
    }
    return full;
  }

  /// 剥离任意位置的 markdown 代码块围栏（兼容截断时只有开头围栏的情况）
  static String _stripFences(String text) {
    var s = text.trim();
    if (s.contains('```')) {
      s = s.replaceAll(RegExp(r'```[a-zA-Z]*\s*'), '').trim();
    }
    return s;
  }

  /// 从 AI 回复中提取 JSON 对象（兼容 ```json 代码块、前后缀文本、截断修复）
  static Map<String, dynamic>? extractJsonObject(String text) {
    if (text.isEmpty) return null;
    final s = _stripFences(text);
    final start = s.indexOf('{');
    if (start < 0) return null;
    // 找到配对的大括号
    int depth = 0;
    bool inStr = false;
    bool esc = false;
    int lastTopLevelEnd = -1; // 顶层容器内某个嵌套容器完整闭合的位置（用于截断修复）
    for (int i = start; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) {
          final candidate = s.substring(start, i + 1);
          try {
            return jsonDecode(candidate) as Map<String, dynamic>;
          } catch (_) {
            break;
          }
        } else if (depth == 1) {
          lastTopLevelEnd = i;
        }
      } else if (c == ']' && depth == 1) {
        lastTopLevelEnd = i;
      }
    }
    // 截断修复：截至最后一个完整嵌套容器，补上收尾大括号再尝试解码
    if (lastTopLevelEnd > start) {
      var tail = s.substring(start, lastTopLevelEnd + 1);
      tail = tail.replaceAll(RegExp(r',\s*$'), '');
      try {
        return jsonDecode('$tail}') as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 从 AI 回复中提取 JSON 数组（兼容代码块、前后缀文本；截断时尝试丢弃残缺尾元素后补 ] 修复）
  static List<Map<String, dynamic>>? extractJsonArray(String text) {
    if (text.isEmpty) return null;
    final s = _stripFences(text);
    final start = s.indexOf('[');
    if (start < 0) return null;
    int depth = 0;
    bool inStr = false;
    bool esc = false;
    int lastTopObjEnd = -1; // 根数组内某个元素对象完整闭合的位置（用于截断修复）
    for (int i = start; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == '\\') {
          esc = true;
        } else if (c == '"') {
          inStr = false;
        }
        continue;
      }
      if (c == '"') {
        inStr = true;
      } else if (c == '[') {
        depth++;
      } else if (c == ']') {
        depth--;
        if (depth == 0) {
          final candidate = s.substring(start, i + 1);
          try {
            final list = jsonDecode(candidate) as List;
            return list.whereType<Map<String, dynamic>>().toList();
          } catch (_) {
            break;
          }
        }
      } else if (c == '}' && depth == 1) {
        lastTopObjEnd = i;
      }
    }
    // 截断修复：保留最后一个完整元素对象，丢弃残缺尾部，补上 ] 再尝试解码
    if (lastTopObjEnd > start) {
      final candidate = '${s.substring(start, lastTopObjEnd + 1)}]';
      try {
        final list = jsonDecode(candidate) as List;
        final out = list.whereType<Map<String, dynamic>>().toList();
        return out.isEmpty ? null : out;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 简易哈希（用于词汇分析缓存键）
  static int simpleHash(String str) {
    var h = 0;
    for (final c in str.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  /// 关闭模型深度思考的请求参数：按实际模型名添加，未知模型不添加以避免 400。
  /// DeepSeek / 通义千问 / 智谱系关闭思考；OpenAI o 系降低推理强度快速直出。
  /// 仅用于 AI 出题、词汇剖析、查词等非对话链路；对话助手由"显示思考过程"开关单独控制。
  static Map<String, dynamic> noThinkingParams(String modelName) {
    final m = _realModel(modelName).toLowerCase();
    final p = <String, dynamic>{};
    if (m.contains('deepseek') || m.contains('qwen') || m.contains('glm')) {
      p['enable_thinking'] = false;
    }
    if (m.startsWith('o1') || m.startsWith('o3') || m.startsWith('o4')) {
      p['reasoning_effort'] = 'low';
    }
    return p;
  }
}
