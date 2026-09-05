/// 轻量浏览器页面：地址栏 + 前进/后退/刷新 + 内嵌 WebView（基于 flutter_inappwebview / Windows WebView2）
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../state.dart';
import '../theme_colors.dart' show AppColors;

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key, this.onClose});

  /// 自定义关闭回调：以侧边面板嵌入时传入（关闭侧边浏览器），
  /// 为 null 时默认退出浏览器回首页（page 0）
  final VoidCallback? onClose;

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final FocusNode _urlFocus = FocusNode();
  InAppWebViewController? _webCtrl;
  InAppWebViewSettings? _settings;
  bool _loading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  double _progress = 0;
  String _currentUrl = '';
  /// 当前页面是否判定为 Flash 页面（提示用户用 IE 内核外部浏览器打开）
  bool _flashDetected = false;
  /// 待消费的外部 URL（didChangeDependencies 注入，onWebViewCreated 时真正加载）
  String? _pendingUrl;

  static const _homeUrl = 'https://www.bing.com';

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = _homeUrl;
    _currentUrl = _homeUrl;
    _settings = InAppWebViewSettings(
      isInspectable: false,
      supportZoom: false,
      javaScriptEnabled: true,
      javaScriptCanOpenWindowsAutomatically: true,
      mediaPlaybackRequiresUserGesture: false,
      useShouldOverrideUrlLoading: false,
      transparentBackground: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 外部 URL 唤起（Windows 默认浏览器/Agent 注入的 pendingBrowserUrl）：
    // 有则消费并记录，待 WebView 创建后加载
    if (_pendingUrl == null) {
      final s = AppScope.of(context);
      final pending = s.pendingBrowserUrl;
      if (pending.isNotEmpty) {
        _pendingUrl = pending;
        s.pendingBrowserUrl = '';
        s.browserNavSeq++;
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  /// 规范化并加载地址
  void _loadUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) {
      _urlCtrl.text = _currentUrl;
      return;
    }
    if (!url.contains('://')) {
      final lower = url.toLowerCase();
      if (lower.startsWith('localhost') || lower.startsWith('127.0.0.1')) {
        url = 'http://$url';
      } else if (lower.endsWith('.html') || lower.endsWith('.htm') || lower.endsWith('.svg')) {
        // 本地文件路径（含盘符 / 相对路径 / file:// 之外的写法）→ file:/// URI
        var p = url.replaceAll('/', r'\');
        if (p.startsWith(r'.\')) p = p.substring(2);
        if (!RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(p)) {
          p = '${Directory.current.path}\\$p';
        }
        url = Uri.file(p).toString();
      } else {
        url = 'https://$url';
      }
    }
    _webCtrl?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    _currentUrl = url;
    _urlCtrl.text = url;
    _urlFocus.unfocus();
  }

  void _goBack() => _webCtrl?.goBack();
  void _goForward() => _webCtrl?.goForward();
  void _reload() => _webCtrl?.reload();
  void _stop() => _webCtrl?.stopLoading();

  void _goHome() {
    _urlCtrl.text = _homeUrl;
    _loadUrl(_homeUrl);
  }

  /// Flash 特征判断：.swf / 4399、7k7k 等 Flash 游戏站，或 URL 含 flash 标识。
  /// 这类页面需要 IE 内核 + Flash ActiveX 插件，WebView2（Chromium）无法运行。
  bool _isFlashLink(String url) {
    final u = url.toLowerCase();
    return u.contains('.swf')
        || u.contains('play.flash')
        || u.contains('/flash/')
        || u.contains('4399.com')
        || u.contains('7k7k.com')
        || u.contains('2144.cn')
        || u.contains('u9game')
        || u.contains('hf.gl');
  }

  /// 用外部浏览器打开（优先 Edge；找不到再回退系统默认浏览器）。
  /// 不用系统默认浏览器作首选，避免 AFloat 被设为默认后自己打开自己造成循环。
  Future<void> _launchExternal(String url) async {
    final hasScheme = url.contains('://') || url.startsWith('about:');
    final target = hasScheme ? url : 'https://$url';
    final edgePaths = const [
      r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      r'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
    ];
    String? edge;
    for (final p in edgePaths) {
      if (File(p).existsSync()) {
        edge = p;
        break;
      }
    }
    if (edge != null) {
      await Process.start(edge, [target]);
      return;
    }
    // 兜底：系统默认浏览器（若默认即是 AFloat，用户浏览器页内可手动退出，风险可控）
    await Process.start('rundll32', ['url.dll,FileProtocolHandler', target]);
  }

  /// 轻提示：已用外部浏览器打开
  void _showExternalHint(String url) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已用外部浏览器打开：$url\nFlash 页面需 IE 模式 + Flash 插件方可播放', style: const TextStyle(fontSize: 12)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(children: [
        // 地址栏工具条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.inputFill,
            border: Border(bottom: BorderSide(color: c.divider)),
          ),
          child: Row(children: [
            // 关闭：侧边面板模式下关闭面板；全屏浏览器模式下返回首页
            _toolBtn(Icons.close_rounded, true, () {
              final cb = widget.onClose;
              if (cb != null) {
                cb();
              } else {
                AppScope.of(context).setPage(0);
              }
            }, widget.onClose != null ? '关闭侧边浏览器' : '退出浏览器', danger: true),
            const SizedBox(width: 8),
            _toolBtn(Icons.arrow_back_ios_new_rounded, _canGoBack, _goBack, '后退'),
            const SizedBox(width: 4),
            _toolBtn(Icons.arrow_forward_ios_rounded, _canGoForward, _goForward, '前进'),
            const SizedBox(width: 4),
            _toolBtn(_loading ? Icons.close_rounded : Icons.refresh_rounded, true, _loading ? _stop : _reload, _loading ? '停止' : '刷新', danger: _loading),
            const SizedBox(width: 8),
            // 地址输入框
            Expanded(
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: c.border),
                ),
                child: Row(children: [
                  Icon(Icons.public, size: 16, color: c.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _urlCtrl,
                      focusNode: _urlFocus,
                      style: TextStyle(fontSize: 13, color: c.text),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '输入网址，回车打开',
                        hintStyle: TextStyle(fontSize: 13, color: c.textTertiary),
                      ),
                      onSubmitted: _loadUrl,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            _toolBtn(Icons.home_rounded, true, _goHome, '主页'),
            const SizedBox(width: 4),
            _toolBtn(Icons.open_in_new_rounded, _currentUrl.isNotEmpty, () {
              final u = _urlCtrl.text.trim();
              final target = u.isEmpty ? _currentUrl : u;
              if (target.isNotEmpty) _launchExternal(target);
              _showExternalHint(target);
            }, '在外部浏览器打开（Flash 页面可用）'),
          ]),
        ),
        // 加载进度条
        if (_loading)
          LinearProgressIndicator(
            value: _progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
        // Flash 页面提示条：WebView2 无法运行 Flash，引导用外部浏览器（IE 模式）
        if (_flashDetected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: const Color(0x22F59E0B),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '检测到 Flash 页面，当前内核无法播放，请用外部浏览器打开（需 IE 模式 + Flash 插件）',
                  style: TextStyle(fontSize: 12, color: c.text),
                ),
              ),
              TextButton(
                onPressed: () {
                  _launchExternal(_currentUrl);
                  _flashDetected = false;
                  setState(() {});
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB45309),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('用 Edge 打开', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        // WebView 内容
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
            initialSettings: _settings,
            onWebViewCreated: (controller) {
              _webCtrl = controller;
              // 外部 URL 唤起：WebView 就绪后立即跳转
              final pending = _pendingUrl;
              if (pending != null && pending.isNotEmpty) {
                _pendingUrl = null;
                _loadUrl(pending);
              }
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _loading = true;
                _progress = 0;
                _currentUrl = url?.toString() ?? '';
                _urlCtrl.text = _currentUrl;
                _flashDetected = _isFlashLink(_currentUrl);
              });
            },
            onProgressChanged: (controller, progress) {
              if (!mounted) return;
              setState(() => _progress = progress / 100);
            },
            onLoadStop: (controller, url) async {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _progress = 1;
                _currentUrl = url?.toString() ?? _currentUrl;
                _urlCtrl.text = _currentUrl;
              });
              final back = await controller.canGoBack();
              final fwd = await controller.canGoForward();
              if (mounted) setState(() {
                _canGoBack = back;
                _canGoForward = fwd;
              });
            },
            onUpdateVisitedHistory: (controller, url, isReload) async {
              if (!mounted) return;
              final back = await controller.canGoBack();
              final fwd = await controller.canGoForward();
              if (mounted) setState(() {
                _canGoBack = back;
                _canGoForward = fwd;
                _currentUrl = url?.toString() ?? _currentUrl;
                _urlCtrl.text = _currentUrl;
                _flashDetected = _isFlashLink(_currentUrl);
              });
            },
          ),
        ),
      ]),
    );
  }

  Widget _toolBtn(IconData icon, bool enabled, VoidCallback onTap, String tooltip, {bool danger = false}) {
    final c = AppColors.of(context);
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 19, color: danger
            ? Colors.redAccent
            : (enabled ? c.textSecondary : c.textTertiary.withValues(alpha: 0.35))),
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}