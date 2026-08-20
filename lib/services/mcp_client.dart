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
  final StringBuffer _buf = StringBuffer();
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

    // initialize 握手
    final initResp = await _send({
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'afloat', 'version': '1.0'},
      },
    });
    serverInfo = (initResp['serverInfo'] is Map) ? (initResp['serverInfo']['name']?.toString()) : null;
    _initialized = true;
    // initialized notification
    _sendNotify({'jsonrpc': '2.0', 'method': 'notifications/initialized'});

    // list tools
    final listResp = await _send({
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': 'tools/list',
      'params': {},
    });
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

  Future<Map<String, dynamic>> _send(Map<String, dynamic> msg) async {
    if (_process == null) throw StateError('MCP process not running');
    final id = msg['id'] as int;
    final body = jsonEncode(msg);
    final bytes = utf8.encode(body);
    final header = 'Content-Length: ${bytes.length}\r\n\r\n';
    _process!.stdin.add(utf8.encode(header));
    _process!.stdin.add(bytes);
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    // 单次 RPC 最多等 60s
    return completer.future.timeout(const Duration(seconds: 60), onTimeout: () {
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
    _buf.write(utf8.decode(chunk, allowMalformed: true));
    while (true) {
      final text = _buf.toString();
      final sepIdx = text.indexOf('\r\n\r\n');
      if (sepIdx < 0) return;
      final headerPart = text.substring(0, sepIdx);
      final m = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false).firstMatch(headerPart);
      if (m == null) {
        _buf.clear();
        return;
      }
      final len = int.parse(m.group(1)!);
      final bodyStart = sepIdx + 4;
      if (text.length < bodyStart + len) return; // 还没收完
      final body = text.substring(bodyStart, bodyStart + len);
      // 已读完，移除缓冲
      _buf.clear();
      _buf.write(text.substring(bodyStart + len));
      try {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final id = json['id'];
        if (id is int && _pending.containsKey(id)) {
          _pending.remove(id)!.complete(json);
        }
      } catch (_) {}
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
  bool _connecting = false;

  List<McpStdioClient> get clients => List.unmodifiable(_clients);

  /// 给定配置列表，启动所有 server。
  /// 单个失败不影响其他；返回的工具列表是所有 server 工具合并的结果。
  Future<List<McpTool>> connectAll(List<McpServerConfig> configs) async {
    if (_connecting) return allTools;
    _connecting = true;
    // 先断开旧的
    await disconnectAll();
    for (final cfg in configs) {
      if (cfg.name.isEmpty || cfg.command.isEmpty) continue;
      final client = McpStdioClient(cfg);
      try {
        await client.connect();
        _clients.add(client);
      } catch (_) {
        await client.dispose();
      }
    }
    _connecting = false;
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