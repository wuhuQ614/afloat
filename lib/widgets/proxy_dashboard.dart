/// Mihomo 控制台（复刻 mihomo_gui_dashboard.html）。
///
/// - 独立深色主题（与主 App 完全隔开）
/// - 桌面端从主 App 侧边栏点击后通过 window_manager 弹出独立子窗口
/// - 移动端全屏沉浸路由
/// - 内容完全自包含：5 个 Tab + 节点选择弹层 + Toast 通知
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../proxy_theme.dart';
import '../services/mihomo_service.dart';
import '../services/storage.dart';
import '../services/system_proxy.dart';

/// Mihomo 控制台页面入口
class ProxyDashboardPage extends StatelessWidget {
  const ProxyDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mihomo Verge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: kProxyBg,
        canvasColor: kProxyBg,
        textTheme: const TextTheme().apply(
          bodyColor: kProxyText,
          displayColor: kProxyText,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const _DashboardScaffold(),
    );
  }
}

class _DashboardScaffold extends StatefulWidget {
  const _DashboardScaffold();

  @override
  State<_DashboardScaffold> createState() => _DashboardScaffoldState();
}

class _DashboardScaffoldState extends State<_DashboardScaffold> {
  String _tab = 'proxy'; // proxy / rules / logs / connections / settings
  bool _running = false;
  String _coreVersion = '';
  ProxyMode _mode = ProxyMode.rule;
  String _version = 'v1.19.13';
  bool _isMobile = !Platform.isWindows && !Platform.isMacOS && !Platform.isLinux;

  // 模拟数据（与 HTML 一致）
  int _trafficToday = 248; // MB * 10
  int _trafficUp = 124;
  int _trafficDown = 124;
  Duration _uptime = const Duration(days: 2, hours: 4);
  Timer? _ticker;
  bool _logsPaused = false;
  final List<_LogLine> _logs = [];
  final ScrollController _logCtrl = ScrollController();
  final List<_Connection> _conns = [
    _Connection('api.github.com', 443, 'TCP', 'Rule: GitHub', 'HK 01 - IPLC', 1.2, 45),
    _Connection('www.baidu.com', 443, 'TCP', 'Rule: GEOIP CN', 'DIRECT', 0.1, 0.2),
    _Connection('cloudflare-dns.com', 443, 'TCP', 'Rule: Match', 'JP 01 - Tokyo', 0.4, 8.1),
    _Connection('api.openai.com', 443, 'TCP', 'Rule: OpenAI', 'SG 01 - Premium', 0.6, 12.3),
  ];

  late final MihomoService _mihomo = MihomoService.instance;

  @override
  void initState() {
    super.initState();
    // 移动端进入代理控制台时启用沉浸式系统 UI（与主场景隔开）
    if (!kIsWeb && Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _initState();
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isAndroid) {
      // 退出代理控制台：恢复系统 UI
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _ticker?.cancel();
    _logCtrl.dispose();
    super.dispose();
  }

  Future<void> _initState() async {
    _mode = ProxyMode.fromName(Storage.loadProxyMode());
    _coreVersion = await _mihomo.version() ?? '';
    if (_coreVersion.isEmpty) _coreVersion = 'v1.19.13';
    setState(() {
      _running = _mihomo.processAlive;
    });
    _ticker = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_running) return;
      final du = (1 + (DateTime.now().millisecond % 5)).toDouble() / 10;
      final dd = (1 + (DateTime.now().second % 7)).toDouble() / 10;
      setState(() {
        _trafficUp = (_trafficUp + du).round();
        _trafficDown = (_trafficDown + dd).round();
        _trafficToday = ((_trafficUp + _trafficDown) * 10).round();
        _uptime = _uptime + const Duration(seconds: 3);
      });
      if (!_logsPaused) _appendRandomLog();
    });
  }

  void _appendRandomLog() {
    final hosts = ['api.github.com', 'google.com', 'client.mihomo.dev', 'cloudflare-dns.com'];
    final h = hosts[DateTime.now().second % hosts.length];
    final t = DateTime.now().toString().split(' ').last.split('.').first;
    _logs.add(_LogLine(t, _logsPaused ? 'INFO' : 'CONNECT', '匹配流量 [$h:443] -> PROXY'));
    if (_logs.length > 200) _logs.removeAt(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logCtrl.hasClients) {
        _logCtrl.animateTo(_logCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
      }
    });
  }

  // ============== Actions ==============
  Future<void> _toggleMaster(bool on) async {
    if (on) {
      final ok = await _mihomo.start(Storage.loadProxySubscriptions());
      if (ok) {
        SystemProxy.enable(MihomoService.controllerHost, MihomoService.mixedPort);
        await Future.delayed(const Duration(milliseconds: 300));
      }
      final v = await _mihomo.version();
      if (!mounted) return;
      setState(() {
        _running = _mihomo.processAlive;
        if (ok && v != null) _coreVersion = v;
      });
    } else {
      await _mihomo.stop();
      SystemProxy.restore();
      if (!mounted) return;
      setState(() {
        _running = false;
      });
    }
    if (!mounted) return;
    _toast(on ? 'Mihomo 代理已开启' : 'Mihomo 代理已关闭', on ? 'success' : 'info');
  }

  Future<void> _selectStrategy(ProxyMode m) async {
    final ok = await _mihomo.setMode(m);
    if (ok) Storage.saveProxyMode(m.name);
    setState(() => _mode = m);
    _toast('已切换至: ${_modeName(m)}', 'info');
  }

  void _openNodeSelector(String groupName) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => _NodeSelectorDialog(groupName: groupName, mihomo: _mihomo),
    );
  }

  void _reloadConfig() {
    _toast('配置重新加载中...', 'info');
    Future.delayed(const Duration(milliseconds: 500), () {
      _toast('配置文件重载成功', 'success');
    });
  }

  void _updateSubs() {
    _toast('开始同步订阅链接...', 'info');
    Future.delayed(const Duration(milliseconds: 1200), () {
      _toast('订阅同步成功 (共更新 46 个节点)', 'success');
    });
  }

  void _closeApp() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      SystemNavigator.pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  // ============== UI ==============
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kProxyBg,
      body: Row(
        children: [
          _sidebar(),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _sidebar() {
    return Container(
      width: 256,
      color: kProxySidebar,
      child: Column(
        children: [
          // Logo
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x66272938))),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9333EA), Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: kProxyGlowSm,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Mihomo Verge',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kProxyText)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: _running ? kProxySuccess : kProxyMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('内核 $_coreVersion',
                            style: const TextStyle(fontSize: 11, color: kProxyMuted)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Nav
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _navItem('proxy', Icons.dns_rounded, '代理'),
                  _navItem('rules', Icons.list_alt_rounded, '规则'),
                  _navItem('logs', Icons.terminal_rounded, '日志'),
                  _navItem('connections', Icons.hub_rounded, '连接'),
                  _navItem('settings', Icons.settings_rounded, '设置'),
                ],
              ),
            ),
          ),
          // Bottom Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0x66272938))),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kProxyCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x99272938)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: _running ? kProxySuccess : kProxyMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('混合端口 ${MihomoService.mixedPort}',
                            style: TextStyle(
                                fontSize: 12,
                                color: _running ? kProxySuccess : kProxyMuted,
                                fontWeight: FontWeight.w500)),
                      ]),
                      const SizedBox(height: 4),
                      Text(_running ? '系统代理已启用' : '代理未启用',
                          style: const TextStyle(fontSize: 11, color: kProxyMuted)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.brightness_6_rounded, color: kProxyMuted, size: 18),
                      onPressed: () => _toast('已是深色极客主题', 'info'),
                      tooltip: '切换主题',
                    ),
                    IconButton(
                      icon: const Icon(Icons.cleaning_services_rounded, color: kProxyMuted, size: 18),
                      onPressed: () => _toast('节点缓存已清除', 'info'),
                      tooltip: '清除缓存',
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: kProxyMuted, size: 18),
                      onPressed: () => setState(() => _tab = 'settings'),
                      tooltip: '内核配置',
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: kProxyCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: kProxyBorder),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 16, height: 16, alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0x4D8B5CF6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('M',
                              style: TextStyle(color: kProxyAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                        Text(_coreVersion,
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: kProxyMuted)),
                        const Icon(Icons.chevron_right_rounded, size: 10, color: kProxyMuted),
                      ]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 关闭/返回独立应用按钮
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _closeApp,
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: Text(_isMobile ? '返回' : '关闭控制台'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kProxyMuted,
                      side: const BorderSide(color: kProxyBorder),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(String key, IconData icon, String label) {
    final active = _tab == key;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _tab = key),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: active ? const Color(0x337C3AED) : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? const Color(0x4D7C3AED) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18,
                    color: active ? kProxyAccent : kProxyMuted),
                const SizedBox(width: 14),
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: active ? kProxyAccent : kProxyMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (_tab) {
      case 'rules':
        return _rulesTab();
      case 'logs':
        return _logsTab();
      case 'connections':
        return _connectionsTab();
      case 'settings':
        return _settingsTab();
      case 'proxy':
      default:
        return _proxyTab();
    }
  }

  // ============== Proxy Tab ==============
  Widget _proxyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _runningBanner(),
            const SizedBox(height: 16),
            _metricsGrid(),
            const SizedBox(height: 16),
            _middleRow(),
            const SizedBox(height: 16),
            _bottomRow(),
          ],
        ),
      ),
    );
  }

  Widget _runningBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kProxyCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kProxyBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: _running ? const Color(0x1A34D399) : const Color(0x1A94A3B8),
              border: Border.all(
                  color: _running ? const Color(0x3334D399) : const Color(0x3394A3B8)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _running ? Icons.rocket_launch_rounded : Icons.power_settings_new_rounded,
              color: _running ? kProxySuccess : kProxyMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(_running ? '代理运行中' : '代理已停止',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: kProxyText)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: kProxyBorder,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('mihomo $_coreVersion',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: kProxyMuted)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                    _running
                        ? '混合端口 ${MihomoService.mixedPort} · 系统代理已启用'
                        : '核心未运行 · 流量未通过代理',
                    style: const TextStyle(fontSize: 12, color: kProxyMuted)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _running ? const Color(0x1A34D399) : const Color(0x1A94A3B8),
              border: Border.all(
                  color: _running ? const Color(0x3334D399) : const Color(0x3394A3B8)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_running ? '已启动' : '已关停',
                style: TextStyle(
                    fontSize: 12,
                    color: _running ? kProxySuccess : kProxyMuted,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          // 自定义 toggle
          GestureDetector(
            onTap: () => _toggleMaster(!_running),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48, height: 24,
              decoration: BoxDecoration(
                color: _running ? kProxyAccentSoft : kProxyBorder,
                borderRadius: BorderRadius.circular(12),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _running ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 20, height: 20,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: const [
                      BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsGrid() {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth < 720 ? 1 : (c.maxWidth < 1000 ? 2 : 4);
      final cards = <Widget>[
        _metric(Icons.public_rounded, kProxyAccent, '活动节点', '3',
            'DIRECT · 2 代理'),
        _metric(Icons.link_rounded, kProxyInfo, '活跃订阅', '1',
            '刚刚更新', success: true),
        _metric(Icons.show_chart_rounded, kProxySuccess, '今日流量',
            (_trafficToday / 10).toStringAsFixed(1),
            '↑ ${(_trafficUp / 10).toStringAsFixed(1)} MB   ↓ ${(_trafficDown / 10).toStringAsFixed(1)} MB'),
        _metric(Icons.schedule_rounded, kProxyWarn, '运行时长',
            _fmtUptime(_uptime),
            '自 ${DateTime.now().toIso8601String().split('T').first}'),
      ];
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 3.2,
        children: cards,
      );
    });
  }

  Widget _metric(IconData icon, Color accent, String label, String value, String sub,
      {bool success = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kProxyCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kProxyBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(value, style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold, color: kProxyText)),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontSize: 12, color: kProxyMuted, fontWeight: FontWeight.w500)),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  if (success) ...[
                    const Icon(Icons.check_circle_rounded, color: kProxySuccess, size: 11),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: success ? kProxySuccess : kProxyMuted)),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _middleRow() {
    return LayoutBuilder(builder: (ctx, c) {
      final stack = c.maxWidth < 900;
      final left = _nodeGroupsCard();
      final right = _currentNodeCard();
      if (stack) {
        return Column(children: [left, const SizedBox(height: 12), right]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ]);
    });
  }

  Widget _nodeGroupsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('节点组',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kProxyText)),
            const Spacer(),
            InkWell(
              onTap: () => _toast('打开添加节点组对话框', 'info'),
              child: const Row(children: [
                Icon(Icons.add_rounded, color: kProxyAccent, size: 13),
                SizedBox(width: 4),
                Text('添加组', style: TextStyle(color: kProxyAccent, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          _groupItem('GLOBAL', kProxyAccent, Icons.public_rounded, '自动选择', 3),
          const SizedBox(height: 8),
          _groupItem('PROXY', kProxyInfo, Icons.shield_rounded, '节点延迟', 46),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _toast('可在此创建自定义规则组', 'info'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: kProxyBorder, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_rounded, color: kProxyMuted, size: 13),
                SizedBox(width: 6),
                Text('添加节点组', style: TextStyle(color: kProxyMuted, fontSize: 12)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _groupItem(String name, Color color, IconData icon, String strategy, int count) {
    return InkWell(
      onTap: () => _openNodeSelector(name),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kProxyBg.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kProxyBorder),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kProxyText)),
              const SizedBox(height: 2),
              Text.rich(TextSpan(children: [
                const TextSpan(text: '选择策略：', style: TextStyle(fontSize: 12, color: kProxyMuted)),
                TextSpan(text: strategy, style: const TextStyle(fontSize: 12, color: kProxyText)),
              ])),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: kProxyBorder, borderRadius: BorderRadius.circular(6)),
            child: Text('$count',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: kProxyMuted)),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, color: kProxyMuted, size: 12),
        ]),
      ),
    );
  }

  Widget _currentNodeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('当前节点',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kProxyText)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0x1A34D399),
                border: Border.all(color: const Color(0x3334D399)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('直连',
                  style: TextStyle(fontSize: 11, color: kProxySuccess, fontWeight: FontWeight.w500)),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: kProxyAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.send_rounded, color: kProxyAccent, size: 18),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DIRECT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: kProxyText)),
                SizedBox(height: 4),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  Text('类型: DIRECT', style: TextStyle(fontSize: 11, color: kProxyMuted)),
                  Text('流量: 12.4 MB ↑ 8.7 MB ↓', style: TextStyle(fontSize: 11, color: kProxyMuted)),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kProxyBg.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kProxyBorder),
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('延迟', style: TextStyle(fontSize: 11, color: kProxyMuted)),
                const SizedBox(height: 4),
                const Text('—', style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: kProxyMuted)),
              ])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('更新时间', style: TextStyle(fontSize: 11, color: kProxyMuted)),
                const SizedBox(height: 4),
                Text(DateTime.now().toString().split('.').first,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: kProxyText)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _openNodeSelector('PROXY'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kProxyText,
                side: const BorderSide(color: kProxyBorder),
                backgroundColor: kProxyBorder.withValues(alpha: 0.6),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('切换节点', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                SizedBox(width: 6),
                Icon(Icons.expand_more_rounded, color: kProxyMuted, size: 14),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomRow() {
    return LayoutBuilder(builder: (ctx, c) {
      final stack = c.maxWidth < 900;
      final strategy = _strategyCard();
      final quick = _quickActionsCard();
      if (stack) {
        return Column(children: [strategy, const SizedBox(height: 12), quick]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(flex: 2, child: strategy),
        const SizedBox(width: 12),
        Expanded(child: quick),
      ]);
    });
  }

  Widget _strategyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('运行策略',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kProxyText)),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (ctx, c) {
          final cols = c.maxWidth < 480 ? 2 : 4;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.2,
            children: [
              _modeCard(ProxyMode.rule, Icons.description_rounded, '规则', '根据规则列表匹配流量'),
              _modeCard(ProxyMode.global, Icons.public_rounded, '全局', '所有流量走当前节点'),
              _modeCard(ProxyMode.direct, Icons.power_rounded, '直连', '所有流量直连不走代理'),
              _modeCard(null, Icons.code_rounded, '脚本', '使用脚本动态决定'),
            ],
          );
        }),
      ]),
    );
  }

  Widget _modeCard(ProxyMode? mode, IconData icon, String label, String desc) {
    final active = mode != null && _mode == mode;
    return InkWell(
      onTap: mode == null
          ? () => _toast('脚本模式需配置 JS 脚本', 'info')
          : () => _selectStrategy(mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kProxyBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? kProxyAccentSoft : kProxyBorder,
            width: active ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: active ? kProxyAccent : kProxyBorder, width: 2),
                ),
                alignment: Alignment.center,
                child: active
                    ? Container(
                        width: 10, height: 10,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: kProxyAccent),
                      )
                    : null,
              ),
              Icon(icon, color: active ? kProxyAccent : kProxyMuted, size: 18),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: active ? kProxyAccent : kProxyText)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(fontSize: 11, color: kProxyMuted)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _quickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('快捷操作',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kProxyText)),
        const SizedBox(height: 12),
        _quickItem(Icons.refresh_rounded, kProxyAccent, '重载配置', null, (_) => _reloadConfig()),
        _quickItem(Icons.cloud_download_rounded, kProxyInfo, '更新订阅', null, (_) => _updateSubs()),
        _quickItem(Icons.desktop_windows_rounded, kProxySuccess, '系统代理', true, (_) {
          if (_running) {
            SystemProxy.restore();
            _toast('系统代理已关闭', 'info');
          } else {
            SystemProxy.enable(MihomoService.controllerHost, MihomoService.mixedPort);
            _toast('系统代理已开启', 'success');
          }
          setState(() {});
        }),
        _quickItem(Icons.power_settings_new_rounded, kProxyMuted, '开机自启', false, (_) {
          _toast('开机自启已切换', 'info');
        }),
        _quickItem(Icons.receipt_long_rounded, kProxyWarn, '打开日志', null,
                (_) => setState(() => _tab = 'logs')),
      ]),
    );
  }

  Widget _quickItem(IconData icon, Color color, String label, bool? toggle, void Function(bool?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: kProxyBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kProxyBorder.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: kProxyText, fontWeight: FontWeight.w500)),
          ),
          if (toggle != null)
            SizedBox(
              height: 18,
              child: Switch(
                value: toggle,
                onChanged: onChanged,
                activeColor: kProxyAccent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
          else
            const Icon(Icons.chevron_right_rounded, color: kProxyMuted, size: 12),
        ]),
      ),
    );
  }

  // ============== Rules Tab ==============
  Widget _rulesTab() {
    final rules = _mockRules();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('规则管理',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kProxyText)),
                const SizedBox(height: 4),
                Text('当前匹配规则数: ${rules.length} 条',
                    style: const TextStyle(fontSize: 12, color: kProxyMuted)),
              ]),
            ),
            SizedBox(
              width: 260,
              child: TextField(
                style: const TextStyle(color: kProxyText, fontSize: 12),
                decoration: InputDecoration(
                  hintText: '搜索规则域名/IP...',
                  hintStyle: const TextStyle(color: kProxyMuted, fontSize: 12),
                  prefixIcon: const Icon(Icons.search_rounded, color: kProxyMuted, size: 16),
                  filled: true,
                  fillColor: kProxyCard,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kProxyBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kProxyAccent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _toast('正在刷新规则', 'info'),
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('刷新规则'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kProxyAccentSoft,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: kProxyCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kProxyBorder),
            ),
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 52,
              headingRowColor: WidgetStatePropertyAll(kProxyBg.withValues(alpha: 0.6)),
              headingTextStyle: const TextStyle(color: kProxyMuted, fontSize: 12, fontWeight: FontWeight.w600),
              dataTextStyle: const TextStyle(color: kProxyText, fontSize: 12, fontFamily: 'monospace'),
              dividerThickness: 0.4,
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('类型')),
                DataColumn(label: Text('匹配目标')),
                DataColumn(label: Text('出站策略组')),
                DataColumn(label: Text('状态')),
              ],
              rows: rules.map((r) {
                Color tc;
                switch (r.type) {
                  case 'DOMAIN-SUFFIX': tc = kProxyAccent; break;
                  case 'GEOIP': tc = kProxyInfo; break;
                  case 'DOMAIN-KEYWORD': tc = kProxyWarn; break;
                  default: tc = kProxyMuted;
                }
                return DataRow(cells: [
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: tc.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(r.type, style: TextStyle(color: tc, fontSize: 11)),
                  )),
                  DataCell(Text(r.target, style: const TextStyle(color: kProxyText, fontFamily: 'monospace'))),
                  DataCell(Text(r.policy, style: TextStyle(color: r.policy == 'DIRECT' ? kProxySuccess : kProxyAccent))),
                  const DataCell(Text('生效中', style: TextStyle(color: kProxySuccess))),
                ]);
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }

  // ============== Logs Tab ==============
  Widget _logsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('实时运行日志',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kProxyText)),
                const SizedBox(height: 4),
                const Text('Mihomo 内核输出记录',
                    style: TextStyle(fontSize: 12, color: kProxyMuted)),
              ]),
            ),
            OutlinedButton(
              onPressed: () {
                setState(() => _logs.clear());
                _toast('日志记录已清空', 'info');
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: kProxyText,
                side: const BorderSide(color: kProxyBorder),
                backgroundColor: kProxyCard,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('清空日志'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => setState(() => _logsPaused = !_logsPaused),
              style: ElevatedButton.styleFrom(
                backgroundColor: _logsPaused ? kProxyBorder : kProxyAccentSoft,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              child: Text(_logsPaused ? '恢复日志' : '暂停日志'),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            height: 500,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kProxyInputFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kProxyBorder),
            ),
            child: _logs.isEmpty
                ? const Center(child: Text('暂无日志', style: TextStyle(color: kProxyMuted)))
                : ListView.builder(
                    controller: _logCtrl,
                    itemCount: _logs.length,
                    itemBuilder: (_, i) {
                      final l = _logs[i];
                      Color c;
                      switch (l.level) {
                        case 'INFO': c = kProxySuccess; break;
                        case 'DEBUG': c = kProxyInfo; break;
                        case 'WARN': c = kProxyWarn; break;
                        case 'ERROR': c = kProxyDanger; break;
                        default: c = kProxyMuted;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: kProxyMuted, height: 1.5),
                            children: [
                              TextSpan(text: '[${l.time}] ', style: const TextStyle(color: kProxyMuted)),
                              TextSpan(text: '[${l.level}] ', style: TextStyle(color: c)),
                              TextSpan(text: l.message, style: const TextStyle(color: kProxyText)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  // ============== Connections Tab ==============
  Widget _connectionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('活动连接',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kProxyText)),
                const SizedBox(height: 4),
                Text('当前建立的 ${_conns.length} 个活跃 Socket 链接',
                    style: const TextStyle(fontSize: 12, color: kProxyMuted)),
              ]),
            ),
            OutlinedButton.icon(
              onPressed: () => _toast('已断开所有连接', 'info'),
              icon: const Icon(Icons.link_off_rounded, size: 14, color: kProxyDanger),
              label: const Text('断开所有连接'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kProxyDanger,
                side: const BorderSide(color: Color(0x33F87171)),
                backgroundColor: kProxyDanger.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: kProxyCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kProxyBorder),
            ),
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 52,
              headingRowColor: WidgetStatePropertyAll(kProxyBg.withValues(alpha: 0.6)),
              headingTextStyle: const TextStyle(color: kProxyMuted, fontSize: 12, fontWeight: FontWeight.w600),
              dataTextStyle: const TextStyle(color: kProxyText, fontSize: 12, fontFamily: 'monospace'),
              dividerThickness: 0.4,
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('目标主机')),
                DataColumn(label: Text('类型')),
                DataColumn(label: Text('匹配规则')),
                DataColumn(label: Text('节点')),
                DataColumn(label: Text('实时速率')),
              ],
              rows: _conns.map((c) {
                return DataRow(cells: [
                  DataCell(Text('${c.host}:${c.port}',
                      style: const TextStyle(color: kProxyText, fontFamily: 'Roboto, monospace', fontWeight: FontWeight.w500))),
                  DataCell(Text(c.proto, style: const TextStyle(color: kProxyMuted))),
                  DataCell(Text(c.rule, style: TextStyle(
                      color: c.rule.contains('GEOIP') ? kProxySuccess : kProxyAccent))),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.node == 'DIRECT'
                          ? kProxySuccess.withValues(alpha: 0.2)
                          : kProxyAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(c.node,
                        style: TextStyle(
                            color: c.node == 'DIRECT' ? const Color(0xFFA7F3D0) : const Color(0xFFDDD6FE),
                            fontSize: 11)),
                  )),
                  DataCell(Text('↑ ${c.up.toStringAsFixed(1)} KB/s   ↓ ${c.down.toStringAsFixed(1)} KB/s',
                      style: const TextStyle(color: kProxySuccess))),
                ]);
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }

  // ============== Settings Tab ==============
  Widget _settingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('系统设置',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kProxyText)),
          const SizedBox(height: 4),
          const Text('自定义 Mihomo Verge 运行参数',
              style: TextStyle(fontSize: 12, color: kProxyMuted)),
          const SizedBox(height: 24),
          _settingsCard('网络与端口', [
            Row(children: [
              Expanded(child: _numberField('混合端口 (HTTP/SOCKS5)', MihomoService.mixedPort.toString())),
              const SizedBox(width: 16),
              Expanded(child: _numberField('RESTful API 端口', MihomoService.controllerPort.toString())),
            ]),
          ]),
          const SizedBox(height: 16),
          _settingsCard('高级设置', [
            _settingsToggle('允许局域网连接 (Allow LAN)',
                '开启后同一局域网设备可通过此电脑代理', true),
            const Divider(color: kProxyBorder, height: 24),
            _settingsToggle('TUN 模式 (虚拟网卡流量捕获)',
                '接管全局网卡流量，无需手动配置系统代理', false),
          ]),
          const SizedBox(height: 16),
          _settingsCard('订阅与同步', [
            _settingsAction('导入订阅', Icons.upload_rounded, kProxyAccent, () async {
              final r = await FilePicker.platform.pickFiles(type: FileType.any);
              if (r != null && r.files.single.path != null) {
                _toast('已选择文件: ${r.files.single.name}', 'info');
              }
            }),
            const Divider(color: kProxyBorder, height: 24),
            _settingsAction('手动添加节点', Icons.add_circle_outline_rounded, kProxyInfo, () {
              _toast('打开手动添加节点面板', 'info');
            }),
          ]),
        ]),
      ),
    );
  }

  Widget _settingsCard(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kProxyAccent)),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  Widget _numberField(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: kProxyMuted)),
      const SizedBox(height: 6),
      TextField(
        controller: TextEditingController(text: value),
        style: const TextStyle(color: kProxyText, fontSize: 13),
        decoration: InputDecoration(
          filled: true,
          fillColor: kProxyBg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kProxyBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kProxyAccent),
          ),
        ),
      ),
    ]);
  }

  Widget _settingsToggle(String title, String desc, bool initial) {
    var v = initial.obs;
    return StatefulBuilder(builder: (ctx, set) {
      return Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 13, color: kProxyText, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(desc, style: const TextStyle(fontSize: 11, color: kProxyMuted)),
          ]),
        ),
        Switch(
          value: v.value,
          onChanged: (val) {
            v.value = val;
            set(() {});
            _toast(val ? '$title 已开启' : '$title 已关闭', 'info');
          },
          activeColor: kProxyAccent,
        ),
      ]);
    });
  }

  Widget _settingsAction(String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 13, color: kProxyText))),
          const Icon(Icons.chevron_right_rounded, color: kProxyMuted, size: 14),
        ]),
      ),
    );
  }

  // ============== Helpers ==============
  BoxDecoration _cardDeco() => BoxDecoration(
        color: kProxyCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kProxyBorder),
      );

  String _modeName(ProxyMode m) {
    switch (m) {
      case ProxyMode.rule: return '规则模式';
      case ProxyMode.global: return '全局模式';
      case ProxyMode.direct: return '直连模式';
    }
  }

  String _fmtUptime(Duration d) {
    final d2 = d.inDays;
    final h2 = d.inHours.remainder(24);
    if (d2 > 0) return '$d2 天 $h2 小时';
    if (h2 > 0) return '$h2 小时';
    return '${d.inMinutes} 分钟';
  }

  List<_Rule> _mockRules() => const [
        _Rule('DOMAIN-SUFFIX', 'google.com', 'PROXY'),
        _Rule('GEOIP', 'CN', 'DIRECT'),
        _Rule('DOMAIN-KEYWORD', 'github', 'PROXY'),
        _Rule('IP-CIDR', '192.168.0.0/16', 'DIRECT'),
        _Rule('DOMAIN-SUFFIX', 'openai.com', 'PROXY'),
        _Rule('GEOIP', 'LAN', 'DIRECT'),
        _Rule('PROCESS-NAME', 'steam.exe', 'GLOBAL'),
        _Rule('DOMAIN-SUFFIX', 'youtube.com', 'PROXY'),
        _Rule('MATCH', '*', 'GLOBAL'),
      ];

  // ============== Toast ==============
  OverlayEntry? _toastEntry;
  void _toast(String msg, String type) {
    _toastEntry?.remove();
    Color border;
    IconData icon;
    switch (type) {
      case 'success':
        border = kProxySuccess;
        icon = Icons.check_circle_rounded;
        break;
      case 'error':
        border = kProxyDanger;
        icon = Icons.error_rounded;
        break;
      default:
        border = kProxyAccent;
        icon = Icons.info_rounded;
    }
    final entry = OverlayEntry(builder: (_) {
      return Positioned(
        bottom: 24, right: 24,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (_, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: kProxyCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border.withValues(alpha: 0.4)),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: border, size: 14),
                const SizedBox(width: 10),
                Text(msg, style: const TextStyle(color: kProxyText, fontSize: 12, fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        ),
      );
    });
    Overlay.of(context).insert(entry);
    _toastEntry = entry;
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (_toastEntry == entry) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }
}

// ============== 节点选择弹层 ==============
class _NodeSelectorDialog extends StatefulWidget {
  final String groupName;
  final MihomoService mihomo;
  const _NodeSelectorDialog({required this.groupName, required this.mihomo});

  @override
  State<_NodeSelectorDialog> createState() => _NodeSelectorDialogState();
}

class _NodeSelectorDialogState extends State<_NodeSelectorDialog> {
  final _searchCtrl = TextEditingController();
  List<ProxyNode> _nodes = [];
  Map<String, int> _delays = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final proxyGroups = await widget.mihomo.groups();
    ProxyGroup? g;
    for (final p in proxyGroups) {
      if (p.name == widget.groupName) { g = p; break; }
    }
    final nodes = await widget.mihomo.allNodes();
    if (!mounted) return;
    setState(() {
      _nodes = nodes.where((n) {
        if (g == null) return true;
        return g.all.contains(n.name);
      }).toList();
      _loading = false;
    });
  }

  Future<void> _testAll() async {
    for (final n in _nodes) {
      if (n.type == 'DIRECT') continue;
      final d = await widget.mihomo.testDelay(n.name);
      if (d != null) {
        setState(() => _delays[n.name] = d);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _nodes.where((n) {
      if (_searchCtrl.text.isEmpty) return true;
      return n.name.toLowerCase().contains(_searchCtrl.text.toLowerCase());
    }).toList();
    return Dialog(
      backgroundColor: kProxyCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('选择节点 (${widget.groupName})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kProxyText)),
                  const SizedBox(height: 4),
                  const Text('点击节点进行切换并测试延迟',
                      style: TextStyle(fontSize: 12, color: kProxyMuted)),
                ]),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: kProxyMuted, size: 18),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: kProxyText, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '搜索节点名称...',
                    hintStyle: const TextStyle(color: kProxyMuted, fontSize: 12),
                    prefixIcon: const Icon(Icons.search_rounded, color: kProxyMuted, size: 16),
                    filled: true,
                    fillColor: kProxyBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kProxyBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kProxyAccent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _testAll,
                icon: const Icon(Icons.bolt_rounded, size: 14),
                label: const Text('测试全部延迟'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kProxyAccentSoft.withValues(alpha: 0.2),
                  foregroundColor: const Color(0xFFDDD6FE),
                  side: const BorderSide(color: Color(0x4D7C3AED)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: kProxyAccent, strokeWidth: 2))
                  : filtered.isEmpty
                      ? const Center(child: Text('未匹配到节点', style: TextStyle(color: kProxyMuted)))
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final n = filtered[i];
                            final delay = _delays[n.name];
                            Color? badge;
                            if (n.type == 'DIRECT') {
                              badge = kProxyMuted;
                            } else if (delay != null) {
                              badge = delay < 150 ? kProxySuccess : kProxyWarn;
                            }
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                await widget.mihomo.selectNode(widget.groupName, n.name);
                                if (mounted) Navigator.pop(context);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: kProxyBg.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: kProxyBorder),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 6, height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: n.isNow ? kProxyAccent : kProxyBorder,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(n.name,
                                          style: const TextStyle(fontSize: 13, color: kProxyText, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(n.type,
                                          style: const TextStyle(fontSize: 11, color: kProxyMuted, fontFamily: 'monospace')),
                                    ]),
                                  ),
                                  if (badge != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badge.withValues(alpha: 0.1),
                                        border: Border.all(color: badge.withValues(alpha: 0.2)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        n.type == 'DIRECT' ? '直连' : (delay != null ? '$delay ms' : '—'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: badge,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                ]),
                              ),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============== 数据类型 ==============
class _LogLine {
  final String time;
  final String level;
  final String message;
  _LogLine(this.time, this.level, this.message);
}

class _Connection {
  final String host;
  final int port;
  final String proto;
  final String rule;
  final String node;
  final double up;
  final double down;
  _Connection(this.host, this.port, this.proto, this.rule, this.node, this.up, this.down);
}

class _Rule {
  final String type;
  final String target;
  final String policy;
  const _Rule(this.type, this.target, this.policy);
}

extension on bool {
  _BoolRef get obs => _BoolRef(this);
}
class _BoolRef {
  bool value;
  _BoolRef(this.value);
}
