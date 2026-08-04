/// AI 接口服务：非流式调用 + SSE 流式对话，兼容 OpenAI / DeepSeek 等 API
library;

import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models.dart';

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

  /// 非流式调用，返回完整内容文本；失败返回 null
  static Future<String?> callAI(
    List<Map<String, String>> messages,
    String systemPrompt, {
    ApiConfig? config,
    int maxTokens = 4096,
    double? temperature,
  }) async {
    final cfg = config;
    if (cfg == null || !cfg.ready) return null;
    try {
      final body = {
        'model': _realModel(cfg.model),
        'temperature': _resolveTemp(cfg, temperature),
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...messages,
        ],
      };
      final resp = await http
          .post(
            Uri.parse(cfg.url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${cfg.key}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final msg = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      return (msg?['content'] as String?) ?? '';
    } catch (_) {
      return null;
    }
  }

  /// 流式对话（SSE）。onReasoning/onDelta 回调增量内容，返回完整内容
  static Future<String> streamChat(
    List<Map<String, String>> messages,
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

  /// 从 AI 回复中提取 JSON 对象（兼容 ```json 代码块、前后缀文本、截断等）
  static Map<String, dynamic>? extractJsonObject(String text) {
    if (text.isEmpty) return null;
    var s = text.trim();
    // 去掉代码块围栏
    if (s.startsWith('```')) {
      s = s.replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '');
      s = s.replaceAll(RegExp(r'\s*```$'), '');
      s = s.trim();
    }
    final start = s.indexOf('{');
    if (start < 0) return null;
    // 找到配对的大括号
    int depth = 0;
    bool inStr = false;
    bool esc = false;
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
            return null;
          }
        }
      }
    }
    return null;
  }

  /// 从 AI 回复中提取 JSON 数组
  static List<Map<String, dynamic>>? extractJsonArray(String text) {
    if (text.isEmpty) return null;
    var s = text.trim();
    if (s.startsWith('```')) {
      s = s.replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '');
      s = s.replaceAll(RegExp(r'\s*```$'), '');
      s = s.trim();
    }
    final start = s.indexOf('[');
    if (start < 0) return null;
    int depth = 0;
    bool inStr = false;
    bool esc = false;
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
            return null;
          }
        }
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
}
