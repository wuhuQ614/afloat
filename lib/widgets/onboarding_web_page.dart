/// WebView 版引导向导（HTML/JS 实现，用于替代原 OnboardingPage 测试效果）
/// 原 Flutter 代码保留在 onboarding_page.dart 中，不删除
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models.dart';
import '../state.dart';

class OnboardingWebPage extends StatefulWidget {
  final AppState state;
  const OnboardingWebPage({super.key, required this.state});

  @override
  State<OnboardingWebPage> createState() => _OnboardingWebPageState();
}

class _OnboardingWebPageState extends State<OnboardingWebPage> {
  late final WebViewController _controller;
  bool _pageReady = false;
  bool _htmlLoaded = false;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    // #docregion webview_controller
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(s.darkMode ? const Color(0xFF121316) : const Color(0xFFFAFAFA))
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _htmlLoaded = true);
              _sendInitData();
            }
          },
          onWebResourceError: (error) {
            if (kDebugMode) {
              print('[OnboardingWeb] WebView 错误: ${error.description}');
              print('[OnboardingWeb] 错误类型: ${error.errorType}');
              print('[OnboardingWeb] 错误代码: ${error.errorCode}');
            }
          },
        ),
      );
    // #enddocregion webview_controller

    // 从 assets 读取 HTML 内容并加载
    try {
      final htmlContent = await rootBundle.loadString('assets/onboarding.html');
      if (kDebugMode) print('[OnboardingWeb] HTML 加载成功，长度: ${htmlContent.length}');
      
      // 使用 loadHtmlString 方法（如果支持）
      await _controller.loadHtmlString(htmlContent);
      if (kDebugMode) print('[OnboardingWeb] loadHtmlString 调用成功');
    } catch (e) {
      if (kDebugMode) print('[OnboardingWeb] 加载 HTML 失败: $e');
      // 降级方案：使用 data URI
      try {
        final htmlContent = await rootBundle.loadString('assets/onboarding.html');
        final dataUri = Uri.dataFromString(
          htmlContent,
          mimeType: 'text/html',
          encoding: Encoding.getByName('utf-8'),
        ).toString();
        await _controller.loadRequest(Uri.parse(dataUri));
        if (kDebugMode) print('[OnboardingWeb] data URI 降级方案调用成功');
      } catch (e2) {
        if (kDebugMode) print('[OnboardingWeb] data URI 也失败: $e2');
      }
    }
  }

  /// 页面加载完成后，把当前 Flutter 状态同步给 HTML
  void _sendInitData() {
    final initData = <String, dynamic>{
      'darkMode': s.darkMode,
      'analysisMode': s.analysisMode,
      'apiKey': s.apiConfig.key,
      'apiUrl': s.apiConfig.url,
      'apiModel': s.apiConfig.model,
      'fullUrl': s.apiConfig.fullUrl,
    };
    _callJs('init', initData);
    if (mounted) setState(() => _pageReady = true);
  }

  /// 调用 JS 的 window.flutterCall(action, data)
  void _callJs(String action, [dynamic data]) {
    final dataStr = data == null ? 'null' : jsonEncode(data);
    _controller.runJavaScript('if(window.flutterCall){window.flutterCall("$action",$dataStr);}');
  }

  /// 处理 HTML → Flutter 的消息
  void _onJsMessage(JavaScriptMessage message) {
    try {
      final msg = jsonDecode(message.message) as Map<String, dynamic>;
      final action = msg['action'] as String?;
      switch (action) {
        case 'ready':
          // HTML 页面已就绪（内部会再发 init，但这里兜底标记）
          break;
        case 'setDarkMode':
          final v = msg['value'] as bool? ?? false;
          s.toggleDarkMode(v);
          break;
        case 'setAnalysisMode':
          final v = msg['value'] as String? ?? 'fast';
          s.setAnalysisMode(v);
          break;
        case 'saveApiConfig':
          final v = msg['value'] as Map<String, dynamic>?;
          if (v != null) {
            s.saveApiConfig(ApiConfig(
              key: (v['key'] as String?) ?? '',
              url: (v['url'] as String?) ?? '',
              model: (v['model'] as String?) ?? '',
              fullUrl: (v['fullUrl'] as bool?) ?? false,
              temperature: s.apiConfig.temperature,
              vision: s.apiConfig.vision,
            ));
          }
          break;
        case 'completeOnboarding':
          s.completeOnboarding();
          break;
        default:
          if (kDebugMode) print('[OnboardingWeb] 未知 action: $action');
      }
    } catch (e) {
      if (kDebugMode) print('[OnboardingWeb] JS 消息解析失败: $e');
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 背景透明，让外层的全局玻璃背景透出（与原 OnboardingPage 保持一致）
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            // WebView 加载过程中的占位（避免白屏）
            if (!_htmlLoaded)
              Container(
                color: s.darkMode ? const Color(0xFF121316) : const Color(0xFFFAFAFA),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '正在加载...',
                        style: TextStyle(
                          fontSize: 12,
                          color: s.darkMode ? Colors.white54 : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
