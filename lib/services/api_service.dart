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
  final String reasoning; // 思考过程（reasoning_content 字段，供开发者模式展示）
  const AIResult(this.content, this.finishReason, {this.reasoning = ''});
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
  final String? finishReason; // 'stop' | 'length'（输出被 max_tokens 截断）| 'tool_calls' | ...
  const AIResponse({
    required this.content,
    required this.toolCalls,
    this.reasoning = '',
    this.finishReason,
  });
}

class ApiService {
  /// 最近一次 AI 请求的失败原因（供调用方透传给用户排查；非请求异常时为 null）
  static String? lastError;

  // ===== 开发者模式日志 =====
  /// 开发者模式日志输出回调（由 AppState 注册，用于展示 AI 出题思维链与输出文本）
  static void Function(String line)? devLogSink;

  /// 写入一行开发者日志（未注册回调或非开发者模式时为空操作）
  static void devLog(String line) {
    try {
      devLogSink?.call(line);
    } catch (_) {}
  }

  /// 截断过长的文本，避免日志缓冲区被单次输出占满
  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}\n…（共 ${s.length} 字，已截断）';
  }

  /// 记录一次非流式 AI 请求的开发者日志（提示词 + 思维链 + 输出文本）
  static void _logNonStream(ApiConfig cfg, String systemPrompt, List<Map<String, dynamic>> messages, String content, String reasoning) {
    if (devLogSink == null) return;
    final sb = StringBuffer();
    sb.writeln('══════ 出题请求 ══════');
    sb.writeln('模型: ${cfg.model}（真实: ${realModelName(cfg.model)}）');
    if (messages.isNotEmpty) {
      sb.writeln('用户消息:');
      for (final m in messages) {
        final c = m['content'];
        sb.writeln('  ${m['role']}: ${c is String ? _truncate(c, 2000) : c}');
      }
    }
    sb.writeln('系统提示词:');
    sb.writeln(_truncate(systemPrompt, 3000));
    devLog(sb.toString());
    if (reasoning.isNotEmpty) {
      devLog('────── 思维链（reasoning_content） ──────\n${_truncate(reasoning, 20000)}');
    }
    devLog('────── 输出文本（content） ──────\n${_truncate(content, 20000)}');
  }

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
    // 统一默认 0.3（保守）
    if (model == 'deepseek-v4-pro') return 0.0;
    if (model == 'deepseek-v4-flash') return 0.3;
    return 0.3;
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

  /// 返回当前请求应使用的 http.Client（默认直连客户端）。
  static http.Client _requestClient() {
    return http.Client();
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
      final resp = await _requestClient()
          .post(
            Uri.parse(cfg.effectiveUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${cfg.key}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 300));
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
      final content = (msg?['content'] as String?) ?? '';
      final reasoning = (msg?['reasoning_content'] as String?) ?? '';
      _logNonStream(cfg, systemPrompt, messages, content, reasoning);
      return AIResult(content, choice['finish_reason']?.toString(), reasoning: reasoning);
    } on TimeoutException catch (_) {
      lastError = '请求超时（300 秒）';
      devLog('✗ 请求失败: $lastError');
      return const AIResult(null, null);
    } catch (e) {
      lastError = e.toString();
      devLog('✗ 请求失败: $lastError');
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
      final resp = await _requestClient()
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
      if (toolCalls.isNotEmpty) {
        devLog('────── 工具调用（tool_calls） ──────');
        for (final tc in toolCalls) {
          devLog('  • ${tc.name}: ${_truncate(tc.arguments, 5000)}');
        }
      } else {
        _logNonStream(cfg, systemPrompt, messages, content, reasoning);
      }
      return AIResponse(content: content, toolCalls: toolCalls, reasoning: reasoning);
    } on TimeoutException catch (_) {
      lastError = '请求超时（120 秒）';
      devLog('✗ 请求失败: $lastError');
      return const AIResponse(content: null, toolCalls: []);
    } catch (e) {
      lastError = e.toString();
      devLog('✗ 请求失败: $lastError');
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
    int maxTokens = 16384,
  }) async {
    final cfg = config;
    if (cfg == null || !cfg.ready) return const AIResponse(content: null, toolCalls: []);
    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();
    // 按 index 增量累积 tool_calls
    final tcId = <int, String>{};
    final tcName = <int, String>{};
    final tcArgs = <int, StringBuffer>{};
    // finishReason 需在 try 外声明，供函数末尾 return 使用
    String? finishReason;
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
      // R7: Agent 工具循环必须给足输出预算（推理模型思考会占用大量 token，
      // 默认 4096 很容易在长任务中触发 finish_reason='length' 截断 → 表现为"干一半就结束"）。
      // 显式设置 max_tokens（思考模式下调用方会传更大值）；OpenAI o 系列用 max_completion_tokens。
      final realModel = _realModel(cfg.model).toLowerCase();
      if (realModel.startsWith('o1') || realModel.startsWith('o3') || realModel.startsWith('o4')) {
        body.putIfAbsent('max_completion_tokens', () => maxTokens);
      } else {
        body.putIfAbsent('max_tokens', () => maxTokens);
      }
      final req = http.Request('POST', Uri.parse(cfg.effectiveUrl));
      req.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${cfg.key}',
      });
      req.body = jsonEncode(body);
      final streamed = await _requestClient().send(req).timeout(const Duration(seconds: 120));
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
          final first = choices.first as Map<String, dynamic>;
          final fr = first['finish_reason'] as String?;
          if (fr != null && fr.isNotEmpty) finishReason = fr;
          final delta = first['delta'] as Map<String, dynamic>? ?? {};
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
    final reasoning = reasoningBuf.toString();
    final content = contentBuf.toString();
    if (devLogSink != null) {
      devLog('══════ 流式请求 ══════\n模型: ${cfg.model}（真实: ${realModelName(cfg.model)}）');
      if (toolCalls.isNotEmpty) {
        devLog('────── 工具调用（tool_calls） ──────');
        for (final tc in toolCalls) {
          devLog('  • ${tc.name}: ${_truncate(tc.arguments, 5000)}');
        }
      } else {
        if (reasoning.isNotEmpty) {
          devLog('────── 思维链（reasoning_content） ──────\n${_truncate(reasoning, 20000)}');
        }
        devLog('────── 输出文本（content） ──────\n${_truncate(content, 20000)}');
      }
    }
    return AIResponse(
      content: content,
      toolCalls: toolCalls,
      reasoning: reasoning,
      finishReason: finishReason,
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

  /// 文本行格式解析器：从 AI 输出的"键: 值"分行文本中提取题目列表（作为 JSON 出题的兜底策略）。
  ///
  /// 支持的格式示例（题目之间用空行 / `---` / `第N题` 分隔）：
  /// ```
  /// 第1题：
  /// chinese: 中文内容
  /// english: 英文内容
  /// knowledge: 知识点1|知识点2
  ///
  /// 第2题：
  /// question: 英文题干
  /// options: A. 选项1|B. 选项2|C. 选项3|D. 选项4
  /// answer: B
  /// analysis: 答案解析
  /// ```
  /// reading 题型使用编号子题键：
  /// ```
  /// 第1题：
  /// passage: 英文短文（可跨多行，直到遇到下一个键）
  /// sub1: 问题1
  /// opt1: A. ...|B. ...|C. ...|D. ...
  /// ans1: A
  /// ana1: 解析1
  /// sub2: 问题2
  /// opt2: ...
  /// ans2: C
  /// ```
  /// 键支持中英文别名；未知键行会被忽略；无法解析时返回 null。
  static List<Map<String, dynamic>>? parseTextQuestions(String text) {
    if (text.isEmpty) return null;
    // 剥离 markdown 围栏
    var s = text.replaceAll(RegExp(r'```[a-zA-Z]*\s*'), '').trim();

    // 键别名 → 标准字段
    Map<String, String> keyAlias() => {
          'chinese': 'chinese', '中文': 'chinese', '中文内容': 'chinese', '题目': 'chinese', '题干': 'chinese', '提示': 'chinese',
          'english': 'english', '英文': 'english', '英文内容': 'english', '答案': 'english', '范文': 'english', '内容': 'english',
          'question': 'question', '问题': 'question', 'q': 'question',
          'options': 'options', '选项': 'options', 'opt': 'options',
          'answer': 'answer', '正确选项': 'answer', '答案字母': 'answer', 'ans': 'answer',
          'analysis': 'analysis', '解析': 'analysis', '解释': 'analysis', 'ana': 'analysis',
          'knowledge': 'knowledge', '知识点': 'knowledge', '考点': 'knowledge',
          'passage': 'passage', '短文': 'passage', '文章': 'passage',
        };

    final questions = <Map<String, dynamic>>[];
    Map<String, dynamic>? cur;
    String? lastKey; // 上一个正在累积的键（用于多行值）
    final lines = s.split('\n');

    void closeQuestion() {
      if (cur != null && cur!.isNotEmpty) {
        // 收集 reading 子题
        final subs = <Map<String, dynamic>>[];
        final subIdx = <int>[];
        cur!.forEach((k, v) {
          final m = RegExp(r'^sub(\d+)$').firstMatch(k);
          if (m != null) {
            final n = int.parse(m.group(1)!);
            subIdx.add(n);
            subs.add(<String, dynamic>{'q': v, 'o': cur!['opt$n'], 'a': cur!['ans$n'], 'an': cur!['ana$n']});
          }
        });
        if (subIdx.isNotEmpty) {
          // 按编号排序
          final order = List.of(subIdx)..sort();
          final ordered = <Map<String, dynamic>>[];
          for (final n in order) {
            final i = subIdx.indexOf(n);
            ordered.add(subs[i]);
          }
          cur!['questions'] = ordered.map((s2) {
            return <String, dynamic>{
              'question': s2['q'] ?? '',
              'options': (s2['o'] as String?)?.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList() ?? [],
              'answer': (s2['a'] as String?) ?? '',
              'analysis': (s2['an'] as String?) ?? '',
            };
          }).toList();
        }
        questions.add(cur!);
      }
      cur = null;
      lastKey = null;
    }

    final alias = keyAlias();
    for (final rawLine in lines) {
      final line = rawLine.trim();
      // 题目分隔：空行、---、第N题、#N
      if (line.isEmpty ||
          RegExp(r'^-{2,}$').hasMatch(line) ||
          RegExp(r'^#+\s*\d*\s*题').hasMatch(line) ||
          RegExp(r'^第\s*\d+\s*题').hasMatch(line)) {
        closeQuestion();
        continue;
      }
      // 键: 值 行
      final m = RegExp(r'^([a-zA-Z\u4e00-\u9fa5]{1,12})\s*[:：]\s*(.*)$').firstMatch(line);
      if (m != null) {
        final rawKey = m.group(1)!.trim().toLowerCase();
        final value = m.group(2)!.trim();
        final stdKey = alias[rawKey];
        if (stdKey != null) {
          cur ??= <String, dynamic>{};
          if (stdKey == 'options') {
            cur![stdKey] = value.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          } else if (stdKey == 'knowledge') {
            cur![stdKey] = value.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
          } else {
            cur![stdKey] = value;
          }
          lastKey = stdKey;
          continue;
        }
        // reading 子题编号键：subN/optN/ansN/anaN（中英文键）
        final sub = RegExp(r'^(sub|opt|ans|ana)\s*(\d+)$').firstMatch(rawKey);
        if (sub != null) {
          cur ??= <String, dynamic>{};
          final kind = sub.group(1)!;
          final n = sub.group(2)!;
          if (kind == 'sub') {
            cur!['sub$n'] = value;
          } else if (kind == 'opt') {
            cur!['opt$n'] = value;
          } else if (kind == 'ans') {
            cur!['ans$n'] = value;
          } else if (kind == 'ana') {
            cur!['ana$n'] = value;
          }
          lastKey = 'sub$n';
          continue;
        }
        // 中文子题键：问题N/选项N/答案N/解析N
        final subZh = RegExp(r'^(问题|选项|答案|解析)\s*(\d+)$').firstMatch(rawKey);
        if (subZh != null) {
          cur ??= <String, dynamic>{};
          final kind = subZh.group(1)!;
          final n = subZh.group(2)!;
          if (kind == '问题') cur!['sub$n'] = value;
          if (kind == '选项') cur!['opt$n'] = value;
          if (kind == '答案') cur!['ans$n'] = value;
          if (kind == '解析') cur!['ana$n'] = value;
          lastKey = 'sub$n';
          continue;
        }
        // 未知键：作为多行内容追加到上一键（避免丢失正文）
        if (cur != null && lastKey != null) {
          final prev = cur![lastKey!];
          if (prev is String) cur![lastKey!] = '$prev\n$line';
        }
        continue;
      }
      // 非键行：追加到上一值（支持 passage 跨多行）
      if (cur != null && lastKey != null) {
        final prev = cur![lastKey!];
        if (prev is String) cur![lastKey!] = '$prev\n$line';
      }
    }
    closeQuestion();
    return questions.isEmpty ? null : questions;
  }

  /// 关闭模型深度思考的请求参数：按实际模型名添加，覆盖所有已知支持思考的模型。
  /// 仅用于 AI 出题、词汇剖析、查词等非对话链路；对话助手由"显示思考过程"开关单独控制。
  static Map<String, dynamic> noThinkingParams(String modelName) {
    final m = _realModel(modelName).toLowerCase();
    final p = <String, dynamic>{};
    // DeepSeek V4 系列（deepseek-v4-pro / deepseek-v4-flash）：默认开启思考，
    // 官方正确关闭方式为 "thinking": {"type": "disabled"}；
    // 布尔值 enable_thinking 对 V4 无效（返回 400 或被忽略），故不再发送。
    if (m.contains('deepseek') && m.contains('v4')) {
      p['thinking'] = {'type': 'disabled'};
      return p;
    }
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
    // DeepSeek V4 系列：官方开启思考方式为 "thinking": {"type": "enabled"}
    if (m.contains('deepseek') && m.contains('v4')) {
      p['thinking'] = {'type': 'enabled'};
      return p;
    }
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
    final resp = await _requestClient()
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
