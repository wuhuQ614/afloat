/// MCP (Model Context Protocol) stdio 客户端实现（仿 dsh-mcp-client）。
///
/// 仅实现 stdio transport + JSON-RPC 2.0，methods: initialize / tools/list / tools/call。
/// MCP 协议本身是基于 LSP-style 的消息头（Content-Length）+ JSON-RPC 2.0 体。
///
/// 不实现：SSE/HTTP transport、auth、resources、prompts、sampling。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// MCP server 配置（stdio）
class McpServerConfig {
  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> env;
  const McpServerConfig({
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
  });

  Map<String, dynamic> toJson() => {'name': name, 'command': command, 'args': args, 'env': env};
  factory McpServerConfig.fromJson(Map<String, dynamic> j) => McpServerConfig(
        name: (j['name'] as String?) ?? '',
        command: (j['command'] as String?) ?? '',
        args: ((j['args'] as List?) ?? const []).map((e) => e.toString()).toList(),
        env: ((j['env'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), v.toString())),
      );
}

/// MCP 工具描述
class McpTool {
  final String name;
  final String? description;
  final Map<String, dynamic> inputSchema;
  const McpTool({required this.name, this.description, this.inputSchema = const {}});

  factory McpTool.fromJson(Map<String, dynamic> j) => McpTool(
        name: (j['name'] as String?) ?? '',
        description: j['description'] as String?,
        inputSchema: (j['inputSchema'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// 连接到 stdio MCP server 的客户端
class McpStdioClient {
  final McpServerConfig config;
  Process? _process;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  int _nextId = 1;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  // 原始字节缓冲（勿按 chunk 解码：多字节 UTF-8 字符跨块会被截断损坏）
  List<int> _bufBytes = <int>[];
  bool _initialized = false;

  /// 工具列表（initialize + tools/list 后填充）
  List<McpTool> tools = [];
  String? serverInfo;

  McpStdioClient(this.config);

  bool get isRunning => _process != null;
  String get name => config.name;

  Future<void> connect() async {
    _process = await Process.start(
      config.command,
      config.args,
      environment: {...Platform.environment, ...config.env},
    );
    _stdoutSub = _process!.stdout.listen(_onStdout);
    _stderrSub = _process!.stderr.listen((_) {}); // 丢弃 stderr（noise）
    // 子进程退出：立即失败所有挂起 RPC，避免调用方空等 60s 超时
    _process!.exitCode.then((_) => _failAllPending());

    // initialize 握手
    final initResp = await _send(
      {
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2024-11-05',
          'capabilities': {},
          'clientInfo': {'name': 'afloat', 'version': '1.0'},
        },
      },
      timeout: const Duration(seconds: 20),
    );
    // 握手失败（超时/写失败/协议错误）必须抛异常，
    // 否则客户端会带空工具列表"假连接"，UI 显示已连接但所有工具不可用
    if (initResp.containsKey('error')) {
      throw StateError('MCP initialize 失败: ${initResp['error']}');
    }
    serverInfo = (initResp['serverInfo'] is Map) ? (initResp['serverInfo']['name']?.toString()) : null;
    _initialized = true;
    // initialized notification
    _sendNotify({'jsonrpc': '2.0', 'method': 'notifications/initialized'});

    // list tools
    final listResp = await _send(
      {
        'jsonrpc': '2.0',
        'id': _nextId++,
        'method': 'tools/list',
        'params': {},
      },
      timeout: const Duration(seconds: 20),
    );
    if (listResp.containsKey('error')) {
      throw StateError('MCP tools/list 失败: ${listResp['error']}');
    }
    final rawTools = (listResp['result'] is Map && (listResp['result'] as Map)['tools'] is List)
        ? (listResp['result'] as Map)['tools'] as List
        : <dynamic>[];
    tools = rawTools.map((e) => McpTool.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// 调用工具
  Future<Map<String, dynamic>> callTool(String toolName, Map<String, dynamic> arguments) async {
    if (!_initialized) throw StateError('MCP client not initialized');
    final resp = await _send({
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'tools/call',
      'params': {'name': toolName, 'arguments': arguments},
    });
    if (resp.containsKey('error')) {
      return {'ok': false, 'error': resp['error']};
    }
    final result = resp['result'] as Map?;
    final content = result?['content'] as List?;
    final text = content == null
        ? ''
        : content
            .where((e) => e is Map && (e['type'] == 'text'))
            .map((e) => (e['text'] as String?) ?? '')
            .join('\n');
    return {
      'ok': result?['isError'] != true,
      'content': text,
      'isError': result?['isError'] == true,
    };
  }

  Future<Map<String, dynamic>> _send(Map<String, dynamic> msg, {Duration timeout = const Duration(seconds: 60)}) async {
    if (_process == null) throw StateError('MCP process not running');
    final id = msg['id'] as int;
    final body = jsonEncode(msg);
    final bytes = utf8.encode(body);
    final header = 'Content-Length: ${bytes.length}\r\n\r\n';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    // 写入失败（子进程已死等）立即失败该 RPC，而非让调用方等 60s 超时
    try {
      _process!.stdin.add(utf8.encode(header));
      _process!.stdin.add(bytes);
    } catch (e) {
      _pending.remove(id);
      return {'jsonrpc': '2.0', 'id': id, 'error': {'code': -32000, 'message': 'mcp_write_failed: $e'}};
    }
    // 单次 RPC 最多等 timeout（握手 20s / 工具调用 60s）
    return completer.future.timeout(timeout, onTimeout: () {
      _pending.remove(id);
      return {'jsonrpc': '2.0', 'id': id, 'error': {'code': -32000, 'message': 'mcp_timeout'}};
    });
  }

  void _sendNotify(Map<String, dynamic> msg) {
    if (_process == null) return;
    final body = jsonEncode(msg);
    final bytes = utf8.encode(body);
    final header = 'Content-Length: ${bytes.length}\r\n\r\n';
    _process!.stdin.add(utf8.encode(header));
    _process!.stdin.add(bytes);
  }

  void _onStdout(List<int> chunk) {
    _bufBytes.addAll(chunk);
    while (true) {
      final sep = _findSeparator(_bufBytes);
      if (sep < 0) return;
      // 头部为 ASCII，单独解码安全
      final header = utf8.decode(_bufBytes.sublist(0, sep), allowMalformed: true);
      final m = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(header);
      if (m == null) {
        // 非法头部：仅丢弃该段头部继续扫描，不清空整段缓冲
        _bufBytes = _bufBytes.sublist(sep + 4);
        continue;
      }
      final len = int.parse(m.group(1)!);
      final bodyStart = sep + 4;
      if (_bufBytes.length < bodyStart + len) return; // 还没收完
      // body 整体解码一次：多字节字符跨 chunk 也不会损坏
      final body = utf8.decode(_bufBytes.sublist(bodyStart, bodyStart + len), allowMalformed: true);
      _bufBytes = _bufBytes.sublist(bodyStart + len);
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final id = json['id'];
        if (id is int && _pending.containsKey(id)) {
          _pending.remove(id)!.complete(json);
        }
      } catch (_) {}
    }
  }

  /// 在字节流中查找 \r\n\r\n 分隔符位置；未找到返回 -1
  static int _findSeparator(List<int> b) {
    for (var i = 0; i + 3 < b.length; i++) {
      if (b[i] == 13 && b[i + 1] == 10 && b[i + 2] == 13 && b[i + 3] == 10) return i;
    }
    return -1;
  }

  /// 进程退出/写入失败时，立即让所有挂起 RPC 失败，不再傻等 60s 超时
  void _failAllPending([String reason = 'mcp_process_exit']) {
    if (_pending.isEmpty) return;
    final entries = _pending.entries.toList();
    _pending.clear();
    for (final e in entries) {
      if (!e.value.isCompleted) {
        e.value.complete({'jsonrpc': '2.0', 'id': e.key, 'error': {'code': -32000, 'message': reason}});
      }
    }
  }

  Future<void> dispose() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _process?.kill();
    _process = null;
  }
}

/// 管理多个 MCP server 客户端
class McpRegistry {
  final List<McpStdioClient> _clients = [];
  /// 进行中的连接 Future：并发调用 connectAll 复用同一 Future，
  /// 避免早到的调用方拿到陈旧/空工具列表
  Future<List<McpTool>>? _connectFuture;

  List<McpStdioClient> get clients => List.unmodifiable(_clients);

  /// 给定配置列表，启动所有 server。
  /// 单个失败不影响其他；返回的工具列表是所有 server 工具合并的结果。
  Future<List<McpTool>> connectAll(List<McpServerConfig> configs) {
    final inFlight = _connectFuture;
    if (inFlight != null) return inFlight;
    final f = _doConnectAll(configs);
    _connectFuture = f;
    return f.whenComplete(() {
      if (identical(_connectFuture, f)) _connectFuture = null;
    });
  }

  Future<List<McpTool>> _doConnectAll(List<McpServerConfig> configs) async {
    // 先断开旧的
    await disconnectAll();
    for (final cfg in configs) {
      if (cfg.name.isEmpty || cfg.command.isEmpty) continue;
      final client = McpStdioClient(cfg);
      try {
        await client.connect();
        _clients.add(client);
      } catch (e) {
        // 失败的 server 不进 _clients（不"假连接"），但留日志供排查
        debugPrint('[MCP] server "${cfg.name}" 连接失败: $e');
        await client.dispose();
      }
    }
    return allTools;
  }

  List<McpTool> get allTools => _clients.expand((c) => c.tools).toList();

  Map<String, List<McpTool>> get toolsByServer => {
        for (final c in _clients) c.name: c.tools,
      };

  McpStdioClient? clientForServer(String name) {
    for (final c in _clients) {
      if (c.name == name) return c;
    }
    return null;
  }

  Future<void> disconnectAll() async {
    for (final c in _clients) {
      await c.dispose();
    }
    _clients.clear();
  }
}