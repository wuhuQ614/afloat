/// 源码查看器：浏览项目精选源码（assets/sources 打包）或本机文件，
/// 语法高亮 + 行号，深/浅色主题跟随全局。
///
/// 高亮基于 highlight 纯 Dart 包（无 WebView 依赖），
/// 配色为内建 github（浅色）/ monokai-sublime（深色）风格映射。
library;

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:highlight/highlight.dart';
import '../state.dart' show AppScope;
import '../theme_colors.dart' show AppColors;

/// 更多功能选择页索引（与 main.dart 中的 _morePageIndex 对应）
const _morePageIndex = 9;

/// 打包在 assets/sources 下的精选源码（显示名, asset 路径, 语言）
const _bundledFiles = [
  _SourceFile('state.dart', 'assets/sources/state.dart', 'dart'),
  _SourceFile('api_service.dart', 'assets/sources/api_service.dart', 'dart'),
  _SourceFile('main_excerpt.dart', 'assets/sources/main_excerpt.dart', 'dart'),
  _SourceFile('snake_logic.cpp', 'assets/sources/snake_logic.cpp', 'cpp'),
  _SourceFile('snake_logic.h', 'assets/sources/snake_logic.h', 'cpp'),
];

class _SourceFile {
  final String name;
  final String asset;
  final String language;
  const _SourceFile(this.name, this.asset, this.language);
}

class SourceViewerPage extends StatefulWidget {
  /// 本机源码文件路径（agent 文件引用跳转入参，绝对路径，可空）
  final String? initialPath;
  /// 定位起始行（1 起，可空）：agent 显示 "文件 + 行号范围"时高亮该区间
  final int? lineFrom;
  /// 定位结束行（可空）
  final int? lineTo;
  const SourceViewerPage({
    super.key,
    this.initialPath,
    this.lineFrom,
    this.lineTo,
  });

  @override
  State<SourceViewerPage> createState() => _SourceViewerPageState();
}

class _SourceViewerPageState extends State<SourceViewerPage> {
  String? _assetPath; // 当前 asset 文件
  String _localPath = ''; // 当前本地文件路径（显示用）
  String _language = 'dart';
  String _code = '';
  bool _loading = false;
  String _loadError = '';

  // 高亮解析结果缓存：按 (代码+语言+主题) 缓存行列表，切换主题/文件时重建
  List<String> _lines = const [];
  List<List<TextSpan>> _lineSpans = const [];
  bool _cachedLight = true; // 上次构建行缓存时的主题
  bool _softWrap = true; // 长行自动换行开关

  // 定位行区间（1 起）；区间内行带高亮背景 + 自动滚动到起始行
  int _hlFrom = 0;
  int _hlTo = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final init = widget.initialPath;
    if (init != null && init.trim().isNotEmpty) {
      _loadPathFile(init.trim(), widget.lineFrom, widget.lineTo);
    } else {
      // 默认打开第一个打包文件
      _selectBundled(_bundledFiles.first);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 读取本机源码文件（agent 文件引用跳转用），并按行区间定位高亮
  Future<void> _loadPathFile(String path, int? from, int? to) async {
    setState(() {
      _assetPath = null;
      _localPath = path.split(RegExp(r'[\\/]')).last;
      _language = _langFromName(_localPath);
      _loading = true;
      _loadError = '';
      _hlFrom = 0;
      _hlTo = 0;
    });
    try {
      final bytes = await File(path).readAsBytes();
      if (!mounted) return;
      final code = utf8.decode(bytes, allowMalformed: true);
      setState(() {
        _code = code;
        _loading = false;
        _hlFrom = (from ?? 0).clamp(1, 1 << 22);
        _hlTo = (to ?? _hlFrom).clamp(_hlFrom, 1 << 22);
        _rebuildLines();
      });
      if (_hlFrom > 0) _jumpToLine(_hlFrom);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _code = '';
        _loading = false;
        _loadError = '打开文件失败：$e';
      });
    }
  }

  /// 滚动到某一行（近似行高估算，越界自动收敛）
  void _jumpToLine(int line) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      const lineH = 22.0;
      final target = (line - 1).toDouble() * lineH;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  /// 从 assets 加载精选文件
  Future<void> _selectBundled(_SourceFile f) async {
    setState(() {
      _assetPath = f.asset;
      _localPath = '';
      _language = f.language;
      _loading = true;
      _loadError = '';
      _hlFrom = 0;
      _hlTo = 0;
    });
    try {
      final code = await rootBundle.loadString(f.asset);
      if (!mounted) return;
      setState(() {
        _code = code;
        _loading = false;
        _rebuildLines();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _code = '';
        _loading = false;
        _loadError = '加载失败：$e';
      });
    }
  }

  /// 用 file_picker 选择本机文件
  Future<void> _pickLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择要查看的源码文件',
        type: FileType.custom,
        allowedExtensions: ['dart', 'cpp', 'h', 'hpp', 'c', 'java', 'kt', 'swift', 'py', 'js', 'ts', 'json', 'yaml', 'yml', 'xml', 'html', 'css', 'md', 'txt'],
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final path = result.files.single.path;
      if (path == null) return;
      final bytes = await result.files.single.xFile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _assetPath = null;
        _localPath = path.split(RegExp(r'[\\/]')).last;
        _language = _langFromName(_localPath);
        _code = utf8.decode(bytes, allowMalformed: true);
        _loading = false;
        _loadError = '';
        _hlFrom = 0;
        _hlTo = 0;
        _rebuildLines();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '打开文件失败：$e');
    }
  }

  String _langFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart')) return 'dart';
    if (lower.endsWith('.cpp') || lower.endsWith('.h') || lower.endsWith('.hpp') || lower.endsWith('.c')) return 'cpp';
    if (lower.endsWith('.json')) return 'json';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'yaml';
    if (lower.endsWith('.md')) return 'markdown';
    if (lower.endsWith('.py')) return 'python';
    if (lower.endsWith('.js') || lower.endsWith('.ts')) return 'javascript';
    return 'plaintext';
  }

  /// 整段 parse 一次，按 \n 拆成行（正确处理跨行注释/字符串）
  /// 注意：纯计算字段，不调用 setState（build 中主题切换时也直接调用）
  void _rebuildLines() {
    final light = Theme.of(context).brightness == Brightness.light;
    _cachedLight = light;
    final palette = _HighlightPalette(light);
    Result result;
    try {
      result = highlight.parse(_code, language: _language);
    } catch (_) {
      result = Result(nodes: [Node(value: _code)]);
    }

    final texts = <String>[];
    final spans = <List<TextSpan>>[];
    final cur = StringBuffer();
    final curSpans = <TextSpan>[];

    void flush() {
      texts.add(cur.toString());
      spans.add(List.unmodifiable(curSpans));
      cur.clear();
      curSpans.clear();
    }

    void walk(Node node) {
      final style = TextStyle(
        color: palette.colorFor(node.className),
        fontStyle: node.className == 'comment' ? FontStyle.italic : FontStyle.normal,
      );
      if (node.value != null) {
        final parts = node.value!.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) flush();
          final part = parts[i];
          if (part.isNotEmpty) {
            cur.write(part);
            curSpans.add(TextSpan(text: part, style: style));
          }
        }
      }
      final children = node.children;
      if (children != null) {
        for (final child in children) {
          walk(child);
        }
      }
    }

    for (final node in result.nodes ?? const <Node>[]) {
      walk(node);
    }
    if (cur.isNotEmpty || curSpans.isNotEmpty) flush();

    _lines = texts;
    _lineSpans = spans;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    // 主题切换时重建高亮缓存（直接改字段，本帧后续渲染即用新值）
    if ((Theme.of(context).brightness == Brightness.light) != _cachedLight) {
      _rebuildLines();
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏：返回 + 标题 + 打开本地文件
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      final nav = Navigator.maybeOf(context);
                      if (nav != null && nav.canPop()) {
                        nav.pop(); // 作为路由弹出时（agent 跳转）返回聊天
                      } else {
                        AppScope.of(context).setPage(_morePageIndex);
                      }
                    },
                    icon: Icon(Icons.arrow_back_rounded, size: 22, color: c.textSecondary),
                    tooltip: '返回',
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.code_rounded, size: 18, color: c.textSecondary),
                  const SizedBox(width: 8),
                  Text('源码查看',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.text)),
                  const Spacer(),
                  // 语言标识
                  _langChip(c, _language),
                  const SizedBox(width: 8),
                  // 换行开关
                  IconButton(
                    onPressed: () => setState(() => _softWrap = !_softWrap),
                    tooltip: _softWrap ? '当前：自动换行（点击关闭）' : '当前：单行截断（点击开启换行）',
                    icon: Icon(
                      _softWrap ? Icons.wrap_text_rounded : Icons.remove_red_eye_outlined,
                      size: 20,
                      color: _softWrap ? c.primary : c.textTertiary,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _loading ? null : _pickLocalFile,
                    icon: Icon(Icons.folder_open_rounded, size: 16, color: c.primary),
                    label: Text('打开本机文件', style: TextStyle(fontSize: 13, color: c.primary, fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                      backgroundColor: c.primaryBg,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
            // 文件选择条：精选文件 chip 横向滚动
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _bundledFiles.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final f = _bundledFiles[i];
                  final selected = _assetPath == f.asset;
                  return GestureDetector(
                    onTap: () => _selectBundled(f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? c.primaryBgStrong : c.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected ? c.primaryBorder : c.border,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        f.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? c.primaryText : c.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            // 当前文件名信息
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 13, color: c.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _localPath.isNotEmpty ? _localPath : (_assetPath ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: c.textTertiary),
                    ),
                  ),
                  Text('${_lines.length} 行',
                      style: TextStyle(fontSize: 11.5, color: c.textTertiary, fontWeight: FontWeight.w600)),
                  if (_hlFrom > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.primaryBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.primaryBorder),
                      ),
                      child: Text(
                        '已定位 $_hlFrom${_hlTo > _hlFrom ? '-$_hlTo' : ''} 行',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: c.primaryText),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 代码区
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border, width: 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildCodeArea(c, isMobile),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _langChip(AppColors c, String lang) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border, width: 1),
      ),
      child: Text(lang,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.textSecondary)),
    );
  }

  Widget _buildCodeArea(AppColors c, bool isMobile) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_loadError.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_loadError, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.scoreLow)),
        ),
      );
    }
    if (_lines.isEmpty) {
      return Center(
        child: Text('暂无内容', style: TextStyle(fontSize: 13, color: c.textTertiary)),
      );
    }

    final baseStyle = TextStyle(
      fontSize: isMobile ? 11.5 : 13,
      height: 1.5,
      color: c.text,
      fontFamily: 'monospace',
    );
    final lineNoStyle = TextStyle(
      fontSize: isMobile ? 11.5 : 13,
      height: 1.5,
      color: c.textTertiary,
      fontFamily: 'monospace',
    );
    final lineNoWidth = isMobile ? 44.0 : 56.0;

    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        itemCount: _lines.length,
        itemBuilder: (ctx, i) {
          final spans = i < _lineSpans.length ? _lineSpans[i] : const <TextSpan>[];
          final isZebra = i.isOdd;
          final inHl = _hlFrom > 0 && i + 1 >= _hlFrom && i + 1 <= _hlTo;
          final Color bg;
          if (inHl) {
            bg = c.isLight ? const Color(0x33FFB74D) : const Color(0x444C9E5A);
          } else {
            bg = isZebra ? c.divider : Colors.transparent;
          }
          return Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: lineNoWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.right,
                      style: lineNoStyle,
                    ),
                  ),
                ),
                Expanded(
                  child: spans.isEmpty
                      ? const Text('')
                      : RichText(
                          text: TextSpan(children: spans, style: baseStyle),
                          maxLines: _softWrap ? null : 1,
                          softWrap: _softWrap,
                          overflow: _softWrap ? TextOverflow.clip : TextOverflow.ellipsis,
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// hljs 语法类别 → 颜色映射（浅色 github / 深色 monokai-sublime 风格）
class _HighlightPalette {
  final bool isLight;
  const _HighlightPalette(this.isLight);

  Color _c(int light, int dark) =>
      Color(isLight ? light : dark);

  Color get plain => _c(0xFF24292E, 0xFFF8F8F2);

  Color colorFor(String? className) {
    switch (className) {
      case 'keyword':
        return _c(0xFFD73A49, 0xFFF92672); // 关键字 红/粉
      case 'string':
        return _c(0xFF032F62, 0xFFE6DB74); // 字符串 深蓝/黄
      case 'comment':
        return _c(0xFF6A737D, 0xFF75715E); // 注释 灰/灰棕
      case 'number':
      case 'literal':
        return _c(0xFF005CC5, 0xFFAE81FF); // 数字/字面量 蓝/紫
      case 'title':
      case 'name':
      case 'selector-id':
      case 'selector-class':
        return _c(0xFF6F42C1, 0xFFA6E22E); // 函数名/类名 紫/绿
      case 'built_in':
      case 'type':
      case 'meta':
        return _c(0xFF005CC5, 0xFFA6E22E); // 内建/类型 蓝/绿
      case 'variable':
      case 'attribute':
        return _c(0xFFE36209, 0xFFFD971F); // 变量/属性 橙
      case 'symbol':
      case 'regexp':
        return _c(0xFF005CC5, 0xFFE6DB74);
      case 'tag':
      case 'selector-tag':
        return _c(0xFF22863A, 0xFFF92672); // HTML 标签 绿/粉
      case 'params':
        return _c(0xFF24292E, 0xFFF8F8F2);
      case 'section':
        return _c(0xFF6F42C1, 0xFFA6E22E);
      case 'addition':
        return _c(0xFF22863A, 0xFFA6E22E);
      case 'deletion':
        return _c(0xFFB31D28, 0xFFF92672);
      default:
        return plain;
    }
  }
}
