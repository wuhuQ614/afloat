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

/// 工具调用（Function Calling）
class ToolCall {
  final String id;
  final String name;
  final String arguments; // JSON 字符串
  const ToolCall({required this.id, required this.name, required this.arguments});
}

/// 带 tools 的 AI 响应：包含文本内容 + 工具调用列表 + 思考过程
class AIResponse {
  final String? content;
  final List<ToolCall> toolCalls;
  final String reasoning; // 思考过程内容（reasoning_content 字段）
  const AIResponse({required this.content, required this.toolCalls, this.reasoning = ''});
}

class ApiService {
  /// 最近一次 AI 请求的失败原因（供调用方透传给用户排查；非请求异常时为 null）
  static String? lastError;

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
    if (cfg == null || !cfg.ready) {
      lastError = '未配置 API 地址或密钥';
      return const AIResult(null, null);
    }
    lastError = null;
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
      if (resp.statusCode != 200) {
        final errBody = utf8.decode(resp.bodyBytes, allowMalformed: true).trim();
        lastError = 'HTTP ${resp.statusCode}${errBody.length <= 200 ? '：$errBody' : ''}';
        return const AIResult(null, null);
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        lastError = '响应缺少 choices 字段';
        return const AIResult(null, null);
      }
      final choice = choices.first as Map<String, dynamic>;
      final msg = choice['message'] as Map<String, dynamic>?;
      return AIResult((msg?['content'] as String?) ?? '', choice['finish_reason']?.toString());
    } on TimeoutException catch (_) {
      lastError = '请求超时（120 秒）';
      return const AIResult(null, null);
    } catch (e) {
      lastError = e.toString();
      return const AIResult(null, null);
    }
  }

  /// 带 tools 的非流式调用（Function Calling）。
  /// 返回 AIResponse：包含 content 和 toolCalls 列表。
  /// 如果模型不支持 tools 或返回纯文本，toolCalls 为空。
  static Future<AIResponse> callAIWithTools(
    List<Map<String, dynamic>> messages,
    String systemPrompt, {
    ApiConfig? config,
    List<Map<String, dynamic>>? tools,
    double? temperature,
    int maxTokens = 4096,
    Map<String, dynamic>? extraParams,
  }) async {
    final cfg = config;
    if (cfg == null || !cfg.ready) {
      lastError = '未配置 API 地址或密钥';
      return const AIResponse(content: null, toolCalls: []);
    }
    lastError = null;
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
      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }
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
      if (resp.statusCode != 200) {
        final errBody = utf8.decode(resp.bodyBytes, allowMalformed: true).trim();
        lastError = 'HTTP ${resp.statusCode}${errBody.length <= 200 ? '：$errBody' : ''}';
        return const AIResponse(content: null, toolCalls: []);
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        lastError = '响应缺少 choices 字段';
        return const AIResponse(content: null, toolCalls: []);
      }
      final choice = choices.first as Map<String, dynamic>;
      final msg = choice['message'] as Map<String, dynamic>? ?? {};
      final content = (msg['content'] as String?) ?? '';
      // 提取思考过程（reasoning_content 字段，部分模型在 message 中返回）
      final reasoning = (msg['reasoning_content'] as String?) ?? '';
      final toolCallsRaw = msg['tool_calls'] as List?;
      final toolCalls = <ToolCall>[];
      if (toolCallsRaw != null) {
        for (final tc in toolCallsRaw) {
          final m = tc as Map<String, dynamic>;
          final fn = m['function'] as Map<String, dynamic>?;
          if (fn != null) {
            toolCalls.add(ToolCall(
              id: (m['id'] ?? '').toString(),
              name: (fn['name'] ?? '').toString(),
              arguments: (fn['arguments'] ?? '{}').toString(),
            ));
          }
        }
      }
      return AIResponse(content: content, toolCalls: toolCalls, reasoning: reasoning);
    } on TimeoutException catch (_) {
      lastError = '请求超时（120 秒）';
      return const AIResponse(content: null, toolCalls: []);
    } catch (e) {
      lastError = e.toString();
      return const AIResponse(content: null, toolCalls: []);
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
    Map<String, dynamic>? extraParams,
  }) async {
    final resp = await streamChatWithTools(messages, systemPrompt,
        config: config, onReasoning: onReasoning, onDelta: onDelta, temperature: temperature, extraParams: extraParams);
    return resp.content ?? '';
  }

  /// 复用静态 http.Client（流式请求），避免每次请求新建不关闭
  static final http.Client _sharedClient = http.Client();

  /// 流式对话（SSE），支持 tools。增量累积 tool_calls，返回 AIResponse。
  static Future<AIResponse> streamChatWithTools(
    List<Map<String, dynamic>> messages,
    String systemPrompt, {
    ApiConfig? config,
    void Function(String chunk)? onReasoning,
    void Function(String chunk)? onDelta,
    double? temperature,
    List<Map<String, dynamic>>? tools,
    Map<String, dynamic>? extraParams,
  }) async {
    final cfg = config;
    if (cfg == null || !cfg.ready) return const AIResponse(content: null, toolCalls: []);
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    // 按 index 增量累积 tool_calls
    final tcId = <int, String>{};
    final tcName = <int, String>{};
    final tcArgs = <int, StringBuffer>{};
    try {
      final body = <String, dynamic>{
        'model': _realModel(cfg.model),
        'temperature': _resolveTemp(cfg, temperature),
        'stream': true,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          ...messages,
        ],
      };
      if (tools != null && tools.isNotEmpty) {
        body['tools'] = tools;
        body['tool_choice'] = 'auto';
      }
      if (extraParams != null && extraParams.isNotEmpty) {
        body.addAll(extraParams);
      }
      final req = http.Request('POST', Uri.parse(cfg.effectiveUrl));
      req.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${cfg.key}',
      });
      req.body = jsonEncode(body);
      final streamed = await _sharedClient.send(req).timeout(const Duration(seconds: 120));
      if (streamed.statusCode != 200) return const AIResponse(content: null, toolCalls: []);
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
          // reasoning_content
          final reasoning = delta['reasoning_content'] as String?;
          if (reasoning != null && reasoning.isNotEmpty) {
            reasoningBuf.write(reasoning);
            if (onReasoning != null) onReasoning(reasoning);
          }
          // content
          final content = delta['content'] as String?;
          if (content != null && content.isNotEmpty) {
            contentBuf.write(content);
            if (onDelta != null) onDelta(content);
          }
          // tool_calls 增量累积
          final toolCallsDelta = delta['tool_calls'] as List?;
          if (toolCallsDelta != null) {
            for (final tcRaw in toolCallsDelta) {
              final tc = tcRaw as Map<String, dynamic>;
              final idx = (tc['index'] as num?)?.toInt() ?? 0;
              final id = tc['id'] as String?;
              if (id != null && id.isNotEmpty) tcId[idx] = id;
              final fn = tc['function'] as Map<String, dynamic>?;
              if (fn != null) {
                final name = fn['name'] as String?;
                if (name != null && name.isNotEmpty) tcName[idx] = name;
                final args = fn['arguments'] as String?;
                if (args != null) {
                  tcArgs.putIfAbsent(idx, StringBuffer.new).write(args);
                }
              }
            }
          }
        } catch (_) {
          // 忽略单行解析失败
        }
      }
    } catch (_) {
      // 流中断
    }
    // 组装 tool_calls
    final toolCalls = <ToolCall>[];
    final allIdx = <int>{...tcId.keys, ...tcName.keys, ...tcArgs.keys};
    for (final idx in allIdx) {
      toolCalls.add(ToolCall(
        id: tcId[idx] ?? '',
        name: tcName[idx] ?? '',
        arguments: tcArgs[idx]?.toString() ?? '{}',
      ));
    }
    return AIResponse(
      content: contentBuf.toString(),
      toolCalls: toolCalls,
      reasoning: reasoningBuf.toString(),
    );
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

  /// 关闭模型深度思考的请求参数：按实际模型名添加，覆盖所有已知支持思考的模型。
  /// 仅用于 AI 出题、词汇剖析、查词等非对话链路；对话助手由"显示思考过程"开关单独控制。
  static Map<String, dynamic> noThinkingParams(String modelName) {
    final m = _realModel(modelName).toLowerCase();
    final p = <String, dynamic>{};
    // enable_thinking: false 适用于多数国产模型
    if (m.contains('deepseek') ||
        m.contains('qwen') ||
        m.contains('glm') ||
        m.contains('kimi') ||
        m.contains('moonshot') ||
        m.contains('doubao') ||
        m.contains('hunyuan') ||
        m.contains('baichuan') ||
        m.contains('spark') ||
        m.contains('ernie') ||
        m.contains('wenxin') ||
        m.contains('step') ||
        m.contains('yi-') ||
        m.contains('minimax') ||
        m.contains('grok')) {
      p['enable_thinking'] = false;
    }
    // OpenAI o 系列使用 minimal 完全关闭推理
    if (m.startsWith('o1') || m.startsWith('o3') || m.startsWith('o4')) {
      p['reasoning_effort'] = 'minimal';
    }
    // Claude 系列禁用 extended thinking
    if (m.contains('claude')) {
      p['thinking'] = {'type': 'disabled'};
    }
    // Gemini 系列将 thinking budget 设为 0
    if (m.contains('gemini')) {
      p['thinking_config'] = {'thinking_budget': 0};
    }
    return p;
  }

  /// 开启模型深度思考的请求参数：与 [noThinkingParams] 相反。
  /// 用于对话助手"思考模式"开启时显式请求思考过程。
  static Map<String, dynamic> thinkingParams(String modelName) {
    final m = _realModel(modelName).toLowerCase();
    final p = <String, dynamic>{};
    // enable_thinking: true 适用于多数国产模型
    if (m.contains('deepseek') ||
        m.contains('qwen') ||
        m.contains('glm') ||
        m.contains('kimi') ||
        m.contains('moonshot') ||
        m.contains('doubao') ||
        m.contains('hunyuan') ||
        m.contains('baichuan') ||
        m.contains('spark') ||
        m.contains('ernie') ||
        m.contains('wenxin') ||
        m.contains('step') ||
        m.contains('yi-') ||
        m.contains('minimax') ||
        m.contains('grok')) {
      p['enable_thinking'] = true;
    }
    // OpenAI o 系列使用 high 完全开启推理
    if (m.startsWith('o1') || m.startsWith('o3') || m.startsWith('o4')) {
      p['reasoning_effort'] = 'high';
    }
    // Claude 系列启用 extended thinking
    if (m.contains('claude')) {
      p['thinking'] = {'type': 'enabled', 'budget_tokens': 2048};
    }
    // Gemini 系列设置 thinking budget
    if (m.contains('gemini')) {
      p['thinking_config'] = {'thinking_budget': 16384};
    }
    return p;
  }

  /// 调用百度千帆 AI 搜索组件（联网搜索），返回 {answer, references}。
  /// 失败时抛异常。url 默认即千帆搜索端点；key 为 AppBuilder API Key。
  static Future<Map<String, dynamic>> searchWeb({
    required String url,
    required String key,
    required String query,
  }) async {
    final resp = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'X-Appbuilder-Authorization': 'Bearer ${key.trim()}',
          },
          body: jsonEncode({
            'messages': [
              {'content': query, 'role': 'user'},
            ],
            'stream': false,
            'enable_deep_search': false,
            'enable_followup_query': false,
            'resource_type_filter': [
              {'type': 'web', 'top_k': 5},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    final bodyText = utf8.decode(resp.bodyBytes);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(bodyText) as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception('${data['error']}');
    }
    final answer = (data['answer'] ?? '') as String;
    final refs = (data['references'] as List?) ?? <dynamic>[];
    final refList = refs.take(5).map<Map<String, dynamic>>((e) {
      final m = e as Map<String, dynamic>;
      final content = (m['content'] ?? '').toString();
      return {
        'title': (m['title'] ?? '').toString(),
        'url': (m['url'] ?? '').toString(),
        'content': content.length > 200 ? content.substring(0, 200) : content,
      };
    }).toList();
    return {'answer': answer, 'references': refList};
  }
}
