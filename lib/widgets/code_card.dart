/// 聊天中的可执行代码卡片（仿 Gemini / ChatGPT Canvas）：
///  - 卡片头部：语言标题 + 预览运行 / 复制 / 下载 三个操作
///  - 代码区：highlight 纯 Dart 语法高亮（深色 One-Dark 风配色），限高滚动
///  - 预览：HTML / SVG 原样渲染，JavaScript 包装成带 console 捕获的运行壳，
///    以全屏浮层打开（顶栏：关闭 / 代码与预览切换 / 重新运行 / 下载）
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:path_provider/path_provider.dart';

/// markdown 围栏语言 → 规范化 id
String normalizeCodeLang(String raw) {
  final l = raw.trim().toLowerCase();
  const map = {
    'js': 'javascript',
    'ts': 'typescript',
    'py': 'python',
    'c++': 'cpp',
    'c#': 'csharp',
    'sh': 'bash',
    'shell': 'bash',
    'zsh': 'bash',
    'yml': 'yaml',
    'htm': 'html',
    'svg': 'xml',
  };
  return map[l] ?? l;
}

/// 深色高亮配色（One-Dark 风，与聊天内代码块深底一致）
class _CodePalette {
  static const base = Color(0xFFDCE0E8);
  static const _colors = <String, Color>{
    'keyword': Color(0xFFC678DD),
    'built_in': Color(0xFFE5C07B),
    'literal': Color(0xFF56B6C2),
    'number': Color(0xFFD19A66),
    'string': Color(0xFF98C379),
    'comment': Color(0xFF6B7280),
    'title': Color(0xFF61AFEF),
    'function': Color(0xFF61AFEF),
    'class': Color(0xFFE5C07B),
    'attr': Color(0xFFD19A66),
    'attribute': Color(0xFFD19A66),
    'symbol': Color(0xFF61AFEF),
    'tag': Color(0xFFE06C75),
    'name': Color(0xFFE06C75),
    'variable': Color(0xFFE06C75),
    'meta': Color(0xFF61AFEF),
    'type': Color(0xFFE5C07B),
    'params': Color(0xFFDCE0E8),
    'selector-tag': Color(0xFFE06C75),
    'selector-id': Color(0xFF61AFEF),
    'selector-class': Color(0xFFD19A66),
    'section': Color(0xFF61AFEF),
    'regexp': Color(0xFF98C379),
    'deletion': Color(0xFFE06C75),
    'addition': Color(0xFF98C379),
  };

  static TextStyle styleFor(String? className) {
    final c = className == null ? null : _colors[className];
    return TextStyle(
      color: c ?? base,
      fontStyle: className == 'comment' ? FontStyle.italic : FontStyle.normal,
    );
  }
}

/// 是否可直接在 WebView 中预览运行（html 原样 / xml 疑似 svg / js 包装运行壳）
bool isRunnableCode(String normLang, String code) {
  if (normLang == 'html') return true;
  if (normLang == 'xml') return code.trimLeft().startsWith('<svg') || code.trimLeft().startsWith('<!DOCTYPE svg');
  if (normLang == 'javascript') return true;
  return false;
}

/// 构造预览用 HTML：html 原样；svg 包白底居中壳；js 包 console 捕获壳
String buildPreviewHtml(String code, String normLang) {
  if (normLang == 'xml' && code.trimLeft().startsWith('<svg')) {
    return '<!doctype html><html><head><meta charset="utf-8"><style>'
        'html,body{height:100%;margin:0;background:#fff;display:flex;'
        'align-items:center;justify-content:center}'
        'svg{max-width:96%;max-height:96%}'
        '</style></head><body>$code</body></html>';
  }
  if (normLang == 'javascript') {
    const shellHead = '<!doctype html><html><head><meta charset="utf-8"><style>'
        'body{background:#141518;color:#d6d8dd;font-family:Consolas,monospace;'
        'padding:14px;font-size:13px;line-height:1.6}'
        '#out{white-space:pre-wrap;word-break:break-word}'
        '#err{color:#ff7b72;white-space:pre-wrap;word-break:break-word;margin-top:8px}'
        '</style></head><body><div id="out"></div><div id="err"></div>'
        '<script>(function(){'
        'var out=document.getElementById("out"),err=document.getElementById("err");'
        'function fmt(a){return a.map(function(x){try{return typeof x==="object"?JSON.stringify(x):String(x)}catch(e){return String(x)}}).join(" ")}'
        'console.log=function(){out.textContent+=fmt([].slice.call(arguments))+"\\n"};'
        'console.info=console.log;console.warn=console.log;'
        'console.error=function(){err.textContent+=fmt([].slice.call(arguments))+"\\n"};'
        'window.onerror=function(m,s,l){err.textContent+=m+" (line "+l+")\\n"};'
        '})();</script>'
        '<script>try{';
    const shellTail =
        '}catch(e){document.getElementById("err").textContent+="Error: "+e.message+"\\n"}</script></body></html>';
    // 防止用户代码里的 </script> 提前截断运行壳
    return shellHead + code.replaceAll('</script', '<\\/script') + shellTail;
  }
  return code;
}

/// 聊天消息里的代码卡片
class CodeCard extends StatefulWidget {
  final String code;
  final String lang;
  const CodeCard({super.key, required this.code, this.lang = ''});

  @override
  State<CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<CodeCard> {
  late String _code;
  List<TextSpan> _spans = const [];

  @override
  void initState() {
    super.initState();
    _code = widget.code;
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(covariant CodeCard old) {
    super.didUpdateWidget(old);
    // 流式输出时代码逐渐变长，内容变化才重建高亮
    if (widget.code != _code) {
      _code = widget.code;
      _rebuildSpans();
    }
  }

  String get _normLang => normalizeCodeLang(widget.lang);

  bool get _looksSvg => _code.trimLeft().startsWith('<svg');

  String get _title {
    final l = _normLang;
    const names = {
      'html': 'HTML',
      'css': 'CSS',
      'javascript': 'JavaScript',
      'typescript': 'TypeScript',
      'python': 'Python',
      'java': 'Java',
      'dart': 'Dart',
      'cpp': 'C++',
      'json': 'JSON',
      'bash': 'Shell',
      'sql': 'SQL',
      'yaml': 'YAML',
      'markdown': 'Markdown',
    };
    if (names.containsKey(l)) return names[l]!;
    if (l == 'xml') return _looksSvg ? 'SVG' : 'XML';
    if (l == 'plaintext' || l.isEmpty) return '代码';
    return widget.lang.trim().toUpperCase();
  }

  String get _ext {
    switch (_normLang) {
      case 'javascript':
        return 'js';
      case 'typescript':
        return 'ts';
      case 'python':
        return 'py';
      case 'cpp':
        return 'cpp';
      case 'c':
        return 'c';
      case 'csharp':
        return 'cs';
      case 'bash':
        return 'sh';
      case 'yaml':
        return 'yaml';
      case 'markdown':
        return 'md';
      case 'html':
        return 'html';
      case 'xml':
        return _looksSvg ? 'svg' : 'xml';
      case 'json':
        return 'json';
      case 'css':
        return 'css';
      default:
        return 'txt';
    }
  }

  bool get _runnable => isRunnableCode(_normLang, _code);

  void _rebuildSpans() {
    final langId = _normLang == 'html' ? 'xml' : _normLang;
    hl.Result r;
    try {
      r = hl.highlight.parse(_code, language: langId);
    } catch (_) {
      r = hl.Result(nodes: [hl.Node(value: _code)]);
    }
    final spans = <TextSpan>[];
    void walk(hl.Node node) {
      if (node.value != null) {
        spans.add(TextSpan(text: node.value, style: _CodePalette.styleFor(node.className)));
      }
      for (final child in node.children ?? const <hl.Node>[]) {
        walk(child);
      }
    }

    for (final node in r.nodes ?? const <hl.Node>[]) {
      walk(node);
    }
    _spans = spans;
  }

  static const _baseMono = TextStyle(
    fontFamily: 'Consolas',
    fontFamilyFallback: ['Courier New', 'Microsoft YaHei'],
    fontSize: 12.5,
    height: 1.55,
    color: _CodePalette.base,
  );

  Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap, {Color? color}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 17, color: color ?? const Color(0xFF9AA0AA)),
        ),
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg, style: const TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating, duration: const Duration(milliseconds: 1600)),
    );
  }

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    _toast('代码已复制到剪贴板');
  }

  Future<void> _download() async {
    final fileName = 'snippet.${_ext}';
    try {
      final res = await FilePicker.platform.saveFile(
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [_ext],
      );
      if (res == null) return;
      await File(res).writeAsString(_code, flush: true);
      if (!mounted) return;
      _toast('已保存到 $res');
    } catch (e) {
      // 桌面保存对话框不可用 / 用户环境异常：退回临时目录
      try {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}${Platform.pathSeparator}$fileName');
        await f.writeAsString(_code, flush: true);
        if (!mounted) return;
        _toast('已保存到 ${f.path}');
      } catch (_) {
        if (mounted) _toast('保存失败：$e');
      }
    }
  }

  void _run() {
    Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 160),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      pageBuilder: (_, __, ___) => CodePreviewPage(
        title: _title,
        code: _code,
        html: buildPreviewHtml(_code, _normLang),
        lang: _normLang,
        fileName: 'snippet.${_ext}',
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C1F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E3036)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部：语言标题 + 预览运行 / 复制 / 下载
          Container(
            padding: const EdgeInsets.fromLTRB(12, 3, 4, 3),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2E3036)))),
            child: Row(children: [
              const Icon(Icons.code_rounded, size: 15, color: Color(0xFF9AA0AA)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _title,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFC9CDD4), fontFamily: 'Consolas'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_runnable)
                _iconBtn(Icons.play_arrow_rounded, '预览运行', _run, color: const Color(0xFF4CC38A)),
              _iconBtn(Icons.content_copy_rounded, '复制', _copy),
              _iconBtn(Icons.download_rounded, '下载', _download),
            ]),
          ),
          // 代码区：限高滚动（横向长行单独滚动）
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text.rich(TextSpan(children: _spans), style: _baseMono),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 全屏预览页：顶栏（关闭 / 代码切换 / 重新运行 / 下载）+ WebView 与代码视图切换
class CodePreviewPage extends StatefulWidget {
  final String title;
  final String code;
  final String html;
  final String lang;
  final String fileName;
  const CodePreviewPage({
    super.key,
    required this.title,
    required this.code,
    required this.html,
    required this.lang,
    required this.fileName,
  });

  @override
  State<CodePreviewPage> createState() => _CodePreviewPageState();
}

class _CodePreviewPageState extends State<CodePreviewPage> {
  bool _showCode = false;
  int _reload = 0;

  List<TextSpan> _buildSpans() {
    final langId = widget.lang == 'html' ? 'xml' : widget.lang;
    hl.Result r;
    try {
      r = hl.highlight.parse(widget.code, language: langId);
    } catch (_) {
      r = hl.Result(nodes: [hl.Node(value: widget.code)]);
    }
    final spans = <TextSpan>[];
    void walk(hl.Node node) {
      if (node.value != null) {
        spans.add(TextSpan(text: node.value, style: _CodePalette.styleFor(node.className)));
      }
      for (final child in node.children ?? const <hl.Node>[]) {
        walk(child);
      }
    }

    for (final node in r.nodes ?? const <hl.Node>[]) {
      walk(node);
    }
    return spans;
  }

  Widget _barBtn(IconData icon, String tip, VoidCallback onTap, {bool active = false, Color? color}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF2E3036) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color ?? const Color(0xFFC9CDD4)),
        ),
      ),
    );
  }

  Future<void> _download() async {
    try {
      final res = await FilePicker.platform.saveFile(
        fileName: widget.fileName,
        type: FileType.custom,
        allowedExtensions: [widget.fileName.split('.').last],
      );
      if (res == null) return;
      await File(res).writeAsString(widget.code, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到 $res', style: const TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141518),
      body: SafeArea(
        child: Column(children: [
          // 顶栏
          Container(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1B1C1F),
              border: Border(bottom: BorderSide(color: Color(0xFF2E3036))),
            ),
            child: Row(children: [
              _barBtn(Icons.close_rounded, '关闭 (Esc)', () => Navigator.of(context).pop()),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFFE4E6EA), fontFamily: 'Consolas'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _barBtn(Icons.code_rounded, _showCode ? '预览' : '查看代码', () => setState(() => _showCode = !_showCode), active: _showCode),
              _barBtn(Icons.play_arrow_rounded, '重新运行', () => setState(() => _reload++), color: const Color(0xFF4CC38A)),
              _barBtn(Icons.download_rounded, '下载', _download),
            ]),
          ),
          Divider(height: 1, thickness: 1, color: const Color(0xFF2E3036)),
          // 内容：预览 / 代码
          Expanded(
            child: IndexedStack(
              index: _showCode ? 1 : 0,
              children: [
                InAppWebView(
                  key: ValueKey(_reload),
                  initialData: InAppWebViewInitialData(
                    data: widget.html,
                    mimeType: 'text/html',
                    encoding: 'utf-8',
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    transparentBackground: false,
                    supportZoom: false,
                  ),
                ),
                Container(
                  color: const Color(0xFF1B1C1F),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text.rich(
                        TextSpan(children: _buildSpans()),
                        style: const TextStyle(
                          fontFamily: 'Consolas',
                          fontFamilyFallback: ['Courier New', 'Microsoft YaHei'],
                          fontSize: 12.5,
                          height: 1.55,
                          color: _CodePalette.base,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
