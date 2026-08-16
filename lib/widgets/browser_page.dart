/// 轻量浏览器页面：地址栏 + 前进/后退/刷新 + 内嵌 WebView（基于 flutter_inappwebview / Windows WebView2）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../theme_colors.dart' show AppColors;

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

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
          ]),
        ),
        // 加载进度条
        if (_loading)
          LinearProgressIndicator(
            value: _progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),
        // WebView 内容
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_homeUrl)),
            initialSettings: _settings,
            onWebViewCreated: (controller) {
              _webCtrl = controller;
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _loading = true;
                _progress = 0;
                _currentUrl = url?.toString() ?? '';
                _urlCtrl.text = _currentUrl;
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