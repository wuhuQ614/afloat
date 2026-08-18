/// mihomo (Clash Meta) 核心服务：内置核心进程管理、RESTful 控制 API、
/// 订阅解析与 config.yaml 生成。作为「复刻 Clash」的后端引擎。
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models.dart';

/// mihomo 核心服务的单例入口，负责进程与 API 控制。
class MihomoService {
  MihomoService._();
  static final MihomoService instance = MihomoService._();

  /// 固定监听端口
  static const int mixedPort = 7890;
  static const int controllerPort = 9090;
  static const String controllerHost = '127.0.0.1';

  Process? _process;
  bool _running = false;

  /// 核心是否已启动
  bool get running => _running;

  /// 核心进程是否存活
  bool get processAlive => _process != null;

  // ==================== 进程管理 ====================

  /// 定位内置 mihomo 核心（与 afloat.exe 同目录）
  File _coreFile() {
    final exe = File(Platform.resolvedExecutable);
    final dir = exe.parent.path;
    return File('$dir${Platform.pathSeparator}mihomo.exe');
  }

  /// 核心工作目录（config.yaml / providers / mmdb 等）
  Future<Directory> _workDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}mihomo');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 生成 config.yaml 并根据订阅列表启动核心。
  /// 返回 true 表示启动命令已下发（不代表已就绪，需等待 controller 可访问）。
  Future<bool> start(List<ProxySubscription> subs) async {
    try {
      final work = await _workDir();
      final core = _coreFile();
      if (!core.existsSync()) return false;

      await _buildConfig(work, subs);

      // 结束可能残留的旧进程
      await stop();
      await Future.delayed(const Duration(milliseconds: 200));

      _process = await Process.start(
        core.path,
        ['-d', work.path, '-f', 'config.yaml'],
        workingDirectory: work.path,
        runInShell: false,
      );
      _running = true;

      // 异步收集日志，避免管道堵塞；同时落盘以便诊断“节点不显示”等问题
      final logSink = File('${work.path}${Platform.pathSeparator}core.log')
          .openWrite(mode: FileMode.writeOnlyAppend);
      _process!.stdout.transform(utf8.decoder).listen(logSink.write);
      _process!.stderr.transform(utf8.decoder).listen(logSink.write);
      _process!.exitCode.then((_) {
        _running = false;
        _process = null;
        logSink.flush().then((_) => logSink.close());
      }).catchError((_) {});

      // 等待核心就绪（最多 8 秒）
      for (var i = 0; i < 40; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (await _ping()) return true;
      }
      return _running;
    } catch (_) {
      _running = false;
      return false;
    }
  }

  /// 停止核心并退出（退出前还原系统代理由调用方负责）。
  Future<void> stop() async {
    try {
      _process?.kill(ProcessSignal.sigkill);
      await _process?.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {}
    _process = null;
    _running = false;
  }

  Future<bool> _ping() async {
    try {
      final r = await http
          .get(Uri.parse('http://$controllerHost:$controllerPort/version'))
          .timeout(const Duration(seconds: 2));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==================== 配置生成 ====================

  /// 把订阅列表写入工作目录并生成 config.yaml。
  /// - URL 订阅：用 proxy-providers 的 http 类型，由 mihomo 自动下载解析（含 base64）。
  /// - 本地文件/内容：解码并转换成标准 proxies YAML 后作为 file provider。
  Future<void> _buildConfig(Directory work, List<ProxySubscription> subs) async {
    final providersDir = Directory('${work.path}/providers');
    if (!providersDir.existsSync()) providersDir.createSync(recursive: true);

    final buf = StringBuffer();
    buf.writeln('mixed-port: $mixedPort');
    buf.writeln('allow-lan: false');
    buf.writeln('mode: rule');
    buf.writeln('log-level: warning');
    buf.writeln('ipv6: false');
    buf.writeln('external-controller: $controllerHost:$controllerPort');
    buf.writeln('geo-auto-update: false');
    buf.writeln();

    final providers = <String>[];
    final useNames = <String>[];

    // 所有 provider 条目必须挂在顶层键 "proxy-providers:" 之下，否则
    // mihomo 无法识别，导致核心启动即退出、节点不显示。
    buf.writeln('proxy-providers:');
    for (var i = 0; i < subs.length; i++) {
      final s = subs[i];
      final pid = 'sub$i';
      final isUrl = s.sourceType == 'url' && s.url.isNotEmpty;

      // 尝试把本地内容解析为 proxies YAML
      final yaml = s.content.trim().isNotEmpty
          ? _subscriptionToProxiesYaml(s)
          : null;
      if (yaml != null && yaml.trim().isNotEmpty) {
        // 方案一：已解析出节点 → file provider（本地，稳定）
        final f = File('${providersDir.path}/$pid.yaml');
        f.writeAsStringSync(yaml);
        buf.writeln('  $pid:');
        buf.writeln('    type: file');
        buf.writeln('    path: ${f.path.replaceAll('\\', '/')}');
      } else if (isUrl) {
        // 方案二：无本地内容 → http provider，让 mihomo 自行下载
        buf.writeln('  $pid:');
        buf.writeln('    type: http');
        buf.writeln('    url: "${_yamlEscape(s.url)}"');
        buf.writeln('    path: ${providersDir.path.replaceAll('\\', '/')}/$pid.yaml');
      } else {
        // 本地导入但内容无法解析 → 跳过
        continue;
      }
      buf.writeln('    interval: 3600');
      buf.writeln('    health-check:');
      buf.writeln('      enable: true');
      buf.writeln('      url: http://www.gstatic.com/generate_204');
      buf.writeln('      interval: 300');
      providers.add(pid);
      useNames.add(pid);
    }

    // 全部订阅源都不可用时，追加一个空直连组，保证能启动
    if (providers.isNotEmpty) {
      buf.writeln('proxy-groups:');
      buf.writeln('  - name: PROXY');
      buf.writeln('    type: select');
      buf.writeln('    use:');
      for (final n in useNames) {
        buf.writeln('      - $n');
      }
      buf.writeln();
      buf.writeln('rules:');
      buf.writeln('  - MATCH,PROXY');
    } else {
      buf.writeln('proxies:');
      buf.writeln('  - name: DIRECT');
      buf.writeln('    type: direct');
      buf.writeln('proxy-groups:');
      buf.writeln('  - name: PROXY');
      buf.writeln('    type: select');
      buf.writeln('    proxies:');
      buf.writeln('      - DIRECT');
      buf.writeln();
      buf.writeln('rules:');
      buf.writeln('  - MATCH,PROXY');
    }

    final cfg = File('${work.path}/config.yaml');
    cfg.writeAsStringSync(buf.toString());
  }

  /// YAML 双引号转义（最小实现）
  String _yamlEscape(String s) => s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  /// 把订阅内容解析为标准 `proxies:` YAML 列表。
  /// 返回 null 表示无法识别。
  String? _subscriptionToProxiesYaml(ProxySubscription sub) {
    var content = sub.content.trim();

    // 尝试 base64 解码（订阅常为 base64 编码的 URI 列表）
    final decoded = _tryBase64Decode(content);
    if (decoded != null && _looksLikeNodeList(decoded)) {
      content = decoded;
    } else if (_looksLikeBase64(content)) {
      // 原文本身是 base64 但解码失败
      final d2 = _tryBase64Decode(content);
      if (d2 != null) content = d2;
    }

    // 情况 1：标准 YAML（含 proxies: 或 proxy-groups:）
    if (content.contains('proxies:') || content.contains('proxy-groups:')) {
      // 提取 proxies 段，去掉 groups/rules，只保留节点
      return _extractProxiesYaml(content);
    }

    // 情况 2：URI 列表（每行 ss:// vmess:// vless:// trojan:// ...）
    if (_looksLikeNodeList(content)) {
      return _uriListToProxiesYaml(content);
    }

    return null;
  }

  /// 从完整 Clash YAML 中仅提取 `proxies:` 列表段
  String? _extractProxiesYaml(String yaml) {
    final lines = yaml.split('\n');
    final out = StringBuffer();
    int idx = 0;
    // 找到 proxies: 起始
    bool inProxies = false;
    for (final raw in lines) {
      final line = raw;
      if (!inProxies) {
        if (line.trimLeft().startsWith('proxies:')) {
          inProxies = true;
          out.writeln('proxies:');
          // 若和其它配置同行，忽略
        }
        continue;
      }
      // 遇到后续顶层键（无缩进且非 proxies 子项）则结束
      if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('\t')) {
        if (line.trimLeft().startsWith('proxies:')) continue;
        break;
      }
      out.writeln(line);
      idx++;
    }
    return idx > 0 ? out.toString() : null;
  }

  // ==================== 节点 URI 解析 ====================

  /// 判断内容是否像节点列表（含协议 URI）
  bool _looksLikeNodeList(String s) {
    return RegExp(r'(?:ss|ssr|vmess|vless|trojan|hysteria2?|hy2|tuic)://')
        .hasMatch(s);
  }

  /// 判断是否 base64（纯 base64 字符串）
  bool _looksLikeBase64(String s) {
    if (s.contains('://') || s.contains('proxies:') || s.contains('\n')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(s);
  }

  String? _tryBase64Decode(String s) {
    // 兼容 URL-safe base64 和去掉填充
    var t = s.trim().replaceAll('-', '+').replaceAll('_', '/');
    while (t.isNotEmpty && t.length % 4 != 0) t += '=';
    try {
      final bytes = base64.decode(t);
      final decoded = utf8.decode(bytes, allowMalformed: true);
      if (decoded.contains('://') || decoded.contains('proxies:')) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// 把每行一个的节点 URI 转换成 proxies YAML
  String? _uriListToProxiesYaml(String list) {
    final out = StringBuffer();
    out.writeln('proxies:');
    int count = 0;
    for (final raw in list.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final yaml = _singleUriToYaml(line);
      if (yaml == null || yaml.trim().isEmpty) continue;
      out.writeln('  $yaml');
      count++;
    }
    return count > 0 ? out.toString() : null;
  }

  /// 单条 URI → 一段 YAML（缩进对齐当前层级，不含前导缩进的两空格前缀）
  String? _singleUriToYaml(String uri) {
    try {
      if (uri.startsWith('ss://')) return _ssToYaml(uri);
      if (uri.startsWith('ssr://')) return _ssrToYaml(uri);
      if (uri.startsWith('vmess://')) return _vmessToYaml(uri);
      if (uri.startsWith('vless://')) return _vlessToYaml(uri);
      if (uri.startsWith('trojan://')) return _trojanToYaml(uri);
      if (uri.startsWith('hysteria2://') || uri.startsWith('hy2://')) {
        return _hysteria2ToYaml(uri);
      }
      if (uri.startsWith('tuic://')) return _tuicToYaml(uri);
    } catch (_) {}
    return null;
  }

  String _nameOf(Uri u, String fallback) {
    var name = u.fragment.isNotEmpty ? Uri.decodeComponent(u.fragment) : fallback;
    return name.replaceAll('\'', '').replaceAll('"', '');
  }

  String? _ssToYaml(String uri) {
    final s = uri.substring(5);
    // 查找 # 分离名称
    String body = s;
    String? name;
    final hashIdx = s.indexOf('#');
    if (hashIdx >= 0) {
      body = s.substring(0, hashIdx);
      name = Uri.decodeComponent(s.substring(hashIdx + 1));
    }
    // 分离 plugin（SIP002）
    String plugin = '';
    final qIdx = body.indexOf('?');
    if (qIdx >= 0) {
      plugin = body.substring(qIdx + 1);
      body = body.substring(0, qIdx);
    }
    // 分离 host:port
    final atIdx = body.lastIndexOf('@');
    final hostPort = atIdx >= 0 ? body.substring(atIdx + 1) : '';
    final userinfo = atIdx >= 0 ? body.substring(0, atIdx) : '';
    if (hostPort.isEmpty) return null;
    final colon = hostPort.lastIndexOf(':');
    final host = hostPort.substring(0, colon);
    final port = colon >= 0 ? hostPort.substring(colon + 1) : '';
    // 解码 userinfo（base64 方法:密码）
    String method = '', password = '';
    final decoded = _tryBase64Decode(userinfo);
    final upair = decoded ?? userinfo;
    final upColon = upair.indexOf(':');
    if (upColon >= 0) {
      method = upair.substring(0, upColon);
      password = upair.substring(upColon + 1);
    }
    if (host.isEmpty || method.isEmpty) return null;
    final n = name ?? '$host:$port';
    final b = StringBuffer();
    b.writeln('- name: "$n"');
    b.writeln('  type: ss');
    b.writeln('  server: $host');
    b.writeln('  port: ${int.tryParse(port) ?? 443}');
    b.writeln('  cipher: $method');
    b.writeln('  password: "$password"');
    if (plugin.isNotEmpty) {
      b.writeln('  plugin: "$plugin"');
    }
    return b.toString().trimRight();
  }

  String? _ssrToYaml(String uri) {
    final s = uri.substring(6);
    final decoded = _tryBase64Decode(s);
    if (decoded == null) return null;
    // ssr:// 格式: host:port:protocol:method:obfs:base64pass/?params
    final mainAndParams = decoded.split('/?');
    final main = mainAndParams[0];
    final parts = main.split(':');
    if (parts.length < 6) return null;
    final host = parts[0];
    final port = parts[1];
    final protocol = parts[2];
    final method = parts[3];
    final obfs = parts[4];
    final passB64 = parts[5];
    final pass = _tryBase64Decode(passB64) ?? passB64;
    final name = Uri.decodeComponent(mainAndParams.length > 1
        ? (mainAndParams[1].split('&').where((e) => e.startsWith('remarks='))
                .firstOrNull?.substring(8) ?? '$host:$port')
        : '$host:$port');
    final b = StringBuffer();
    b.writeln('- name: "$name"');
    b.writeln('  type: ssr');
    b.writeln('  server: $host');
    b.writeln('  port: ${int.tryParse(port) ?? 443}');
    b.writeln('  cipher: $method');
    b.writeln('  password: "$pass"');
    b.writeln('  protocol: $protocol');
    b.writeln('  obfs: $obfs');
    return b.toString().trimRight();
  }

  String? _vmessToYaml(String uri) {
    final s = uri.substring(8);
    final jsonStr = _tryBase64Decode(s) ?? s;
    final j = jsonDecode(jsonStr) as Map<String, dynamic>;
    final host = (j['add'] ?? '').toString();
    if (host.isEmpty) return null;
    final port = (j['port'] as num?)?.toInt() ?? 443;
    final uuid = (j['id'] ?? '').toString();
    final aid = (j['aid'] as num?)?.toInt() ?? 0;
    final network = (j['net'] ?? 'tcp').toString();
    final tls = (j['tls'] ?? '').toString();
    final name = (j['ps'] ?? '$host:$port').toString();
    final b = StringBuffer();
    b.writeln('- name: "$name"');
    b.writeln('  type: vmess');
    b.writeln('  server: $host');
    b.writeln('  port: $port');
    b.writeln('  uuid: "$uuid"');
    b.writeln('  alterId: $aid');
    b.writeln('  cipher: auto');
    b.writeln('  network: $network');
    b.writeln('  udp: true');
    if (tls == 'tls') b.writeln('  tls: true');
    if (network == 'ws') {
      final path = (j['path'] ?? '/').toString();
      final hostHeader = (j['host'] ?? '').toString();
      b.writeln('  ws-opts:');
      b.writeln('    path: "$path"');
      if (hostHeader.isNotEmpty) {
        b.writeln('    headers:');
        b.writeln('      Host: "$hostHeader"');
      }
    }
    return b.toString().trimRight();
  }

  String? _vlessToYaml(String uri) {
    final u = Uri.parse(uri);
    final host = u.host;
    final port = u.port;
    final uuid = u.userInfo;
    if (host.isEmpty || uuid.isEmpty) return null;
    final name = _nameOf(u, '$host:$port');
    final b = StringBuffer();
    b.writeln('- name: "$name"');
    b.writeln('  type: vless');
    b.writeln('  server: $host');
    b.writeln('  port: $port');
    b.writeln('  uuid: "$uuid"');
    b.writeln('  udp: true');
    final network = u.queryParameters['type'] ?? 'tcp';
    final security = u.queryParameters['security'] ?? 'none';
    b.writeln('  network: $network');
    if (security != 'none') {
      b.writeln('  tls: true');
      b.writeln('  servername: "${u.queryParameters['sni'] ?? u.queryParameters['host'] ?? host}"');
    }
    if (network == 'ws') {
      b.writeln('  ws-opts:');
      b.writeln('    path: "${u.queryParameters['path'] ?? '/'}"');
      final h = u.queryParameters['host'];
      if (h != null && h.isNotEmpty) {
        b.writeln('    headers:');
        b.writeln('      Host: "$h"');
      }
    }
    return b.toString().trimRight();
  }

  String? _trojanToYaml(String uri) {
    final u = Uri.parse(uri);
    final host = u.host;
    final port = u.port;
    final password = u.userInfo;
    if (host.isEmpty || password.isEmpty) return null;
    final name = _nameOf(u, '$host:$port');
    final sni = u.queryParameters['sni'] ?? u.queryParameters['peer'] ?? host;
    final b = StringBuffer();
    b.writeln('- name: "$name"');
    b.writeln('  type: trojan');
    b.writeln('  server: $host');
    b.writeln('  port: $port');
    b.writeln('  password: "$password"');
    b.writeln('  udp: true');
    b.writeln('  sni: "$sni"');
    return b.toString().trimRight();
  }

  String? _hysteria2ToYaml(String uri) {
    final u = Uri.parse(uri);
    final host = u.host;
    final port = u.port;
    final auth = u.userInfo;
    if (host.isEmpty || auth.isEmpty) return null;
    final name = _nameOf(u, '$host:$port');
    final sni = u.queryParameters['sni'] ?? host;
    final b = StringBuffer();
    b.writeln('- name: "$name"');
    b.writeln('  type: hysteria2');
    b.writeln('  server: $host');
    b.writeln('  port: $port');
    b.writeln('  password: "$auth"');
    b.writeln('  sni: "$sni"');
    final insecure = u.queryParameters['insecure'] ?? '0';
    if (insecure == '1') b.writeln('  skip-cert-verify: true');
    return b.toString().trimRight();
  }

  String? _tuicToYaml(String uri) {
    final u = Uri.parse(uri);
    final host = u.host;
    final port = u.port;
    if (host.isEmpty) return null;
    final uuid = u.userInfo;
    final pass = u.queryParameters['password'] ?? uuid;
    final name = _nameOf(u, '$host:$port');
    final sni = u.queryParameters['sni'] ?? host;
    final b = StringBuffer();
    b.writeln('- name: "$name"');
    b.writeln('  type: tuic');
    b.writeln('  server: $host');
    b.writeln('  port: $port');
    b.writeln('  uuid: "${uuid.isEmpty ? pass : uuid}"');
    b.writeln('  password: "$pass"');
    b.writeln('  sni: "$sni"');
    return b.toString().trimRight();
  }

  // ==================== RESTful 控制 API ====================

  Future<http.Response?> _get(String path) async {
    try {
      return await http
          .get(Uri.parse('http://$controllerHost:$controllerPort$path'))
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<bool> _put(String path, Map<String, dynamic> body) async {
    try {
      final r = await http
          .put(Uri.parse('http://$controllerHost:$controllerPort$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));
      return r.statusCode == 204 || r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _patch(String path, Map<String, dynamic> body) async {
    try {
      final r = await http
          .patch(Uri.parse('http://$controllerHost:$controllerPort$path'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 8));
      return r.statusCode == 204 || r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 获取核心版本
  Future<String?> version() async {
    final r = await _get('/version');
    if (r == null || r.statusCode != 200) return null;
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (j['version'] ?? '').toString();
    } catch (_) {
      return null;
    }
  }

  /// 获取当前模式（rule/global/direct）
  Future<ProxyMode> mode() async {
    final r = await _get('/configs');
    if (r == null || r.statusCode != 200) return ProxyMode.rule;
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return ProxyMode.fromName((j['mode'] ?? 'rule').toString());
    } catch (_) {
      return ProxyMode.rule;
    }
  }

  /// 切换运行模式
  Future<bool> setMode(ProxyMode m) async {
    final name = m == ProxyMode.global
        ? 'global'
        : m == ProxyMode.direct
            ? 'direct'
            : 'rule';
    return _patch('/configs', {'mode': name});
  }

  /// 获取所有策略组（含组内节点与当前选中）
  Future<List<ProxyGroup>> groups() async {
    final r = await _get('/proxies');
    if (r == null || r.statusCode != 200) return [];
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final proxies = (j['proxies'] ?? {}) as Map<String, dynamic>;
      final out = <ProxyGroup>[];
      for (final e in proxies.entries) {
        final v = e.value as Map<String, dynamic>;
        final type = (v['type'] ?? '').toString();
        final all = (v['all'] as List?)?.map((x) => x.toString()).toList() ?? [];
        // 只有含 all 且类型为组类型才是策略组
        if (all.isNotEmpty &&
            (type == 'Selector' || type == 'URLTest' || type == 'Fallback' ||
                type == 'LoadBalance')) {
          out.add(ProxyGroup(
            name: e.key,
            type: type,
            now: (v['now'] ?? '').toString(),
            all: all,
          ));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// 获取指定策略组的详情（组名或节点名）
  Future<ProxyGroup?> groupDetail(String name) async {
    final r = await _get('/proxies/${Uri.encodeComponent(name)}');
    if (r == null || r.statusCode != 200) return null;
    try {
      final v = jsonDecode(r.body) as Map<String, dynamic>;
      final type = (v['type'] ?? '').toString();
      final all = (v['all'] as List?)?.map((x) => x.toString()).toList() ?? [];
      return ProxyGroup(
        name: name,
        type: type,
        now: (v['now'] ?? '').toString(),
        all: all,
      );
    } catch (_) {
      return null;
    }
  }

  /// 切换策略组的选中节点
  Future<bool> selectNode(String groupName, String nodeName) {
    return _put('/proxies/${Uri.encodeComponent(groupName)}', {'name': nodeName});
  }

  /// 所有节点的类型映射（name -> type），供 UI 展示协议标签。
  /// 过滤策略组（Selector/URLTest 等）只保留真实节点。
  Future<Map<String, String>> allNodeTypes() async {
    const groupTypes = {
      'Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Relay',
    };
    final r = await _get('/proxies');
    if (r == null || r.statusCode != 200) return {};
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final proxies = (j['proxies'] ?? {}) as Map<String, dynamic>;
      final out = <String, String>{};
      for (final e in proxies.entries) {
        final v = e.value as Map<String, dynamic>;
        final type = (v['type'] ?? '').toString();
        final all = v['all'];
        if (all == null && !groupTypes.contains(type)) {
          out[e.key] = type;
        }
      }
      return out;
    } catch (_) {
      return {};
    }
  }

/// 获取所有真实节点（不包含策略组）
  Future<List<ProxyNode>> allNodes() async {
    const groupTypes = {
      'Selector', 'URLTest', 'Fallback', 'LoadBalance', 'Relay',
    };
    final r = await _get('/proxies');
    if (r == null || r.statusCode != 200) return [];
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final proxies = (j['proxies'] ?? {}) as Map<String, dynamic>;
      // 先收集所有真实节点
      final all = <ProxyNode>[];
      for (final e in proxies.entries) {
        final v = e.value as Map<String, dynamic>;
        final type = (v['type'] ?? '').toString();
        if (!groupTypes.contains(type)) {
          all.add(ProxyNode(name: e.key, type: type));
        }
      }
      // 再找出每个节点的所属策略组（选第一个含它的组）
      final map = <String, String>{};
      for (final e in proxies.entries) {
        final v = e.value as Map<String, dynamic>;
        final type = (v['type'] ?? '').toString();
        if (groupTypes.contains(type)) {
          final allInGroup = (v['all'] as List?)?.map((x) => x.toString()).toList() ?? const [];
          final now = (v['now'] ?? '').toString();
          for (final n in allInGroup) {
            map.putIfAbsent(n, () => e.key);
          }
          for (final n in all) {
            if (n.name == now) n.isNow = true;
            n.group = map[n.name] ?? '';
          }
        }
      }
      return all;
    } catch (_) {
      return [];
    }
  }

  /// 下载订阅 URL 内容（返回原始文本，可能为 base64/YAML），失败返回 null
  Future<String?> fetchSubscription(String url) async {
    try {
      final r = await http
          .get(Uri.parse(url),
              headers: {'User-Agent': 'clash-verge/2.0'})
          .timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) return null;
      // 优先按字节解码（部分订阅是 gzip，http 包已自动解压）
      final bytes = r.bodyBytes;
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = utf8.decode(bytes, allowMalformed: true);
      }
      return text;
    } catch (_) {
      return null;
    }
  }

  /// 测试节点延迟（毫秒），失败返回 null
  Future<int?> testDelay(String nodeName, {int timeoutMs = 3000}) async {
    try {
      final url =
          'http://$controllerHost:$controllerPort/proxies/${Uri.encodeComponent(nodeName)}/delay'
          '?timeout=$timeoutMs&url=${Uri.encodeComponent('http://www.gstatic.com/generate_204')}';
      final r = await http.get(Uri.parse(url)).timeout(Duration(milliseconds: timeoutMs + 2000));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final d = j['delay'];
      if (d is int) return d;
      if (d is num) return d.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }
}