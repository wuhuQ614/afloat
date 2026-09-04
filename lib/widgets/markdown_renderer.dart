/// 公共 Markdown 渲染器：与 main.dart 对话面板的渲染管线 1:1 同源
/// （块级：```代码卡 / $$公式$$ / 分割线 / 表格 / 引用 / 标题 / 列表；
///  行内：粗斜删、行内代码（背景色 TextSpan）、链接、$行内公式$、反斜杠转义）。
///
/// 供多专家团、辩论等多智能体页面复用。修改此处时同步 main.dart。
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'code_card.dart';

class MarkdownRenderer {
  // 解析 RegExp（static final，避免每次重建新建）
  static final RegExp _reStrikethrough = RegExp(r'~~(.+?)~~');
  static final RegExp _reBold = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _reItalic = RegExp(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)');
  static final RegExp _reInlineCode = RegExp(r'`([^`]+)`');
  static final RegExp _reLink = RegExp(r'\[([^\]]+)\]\(([^)]+)\)');
  static final RegExp _reOrderedList = RegExp(r'^(\d+)\.\s+(.*)$');
  static final RegExp _reTableRow = RegExp(r'^\s*\|.+\|?\s*$');
  static final RegExp _reTableSeparator = RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)+\|?\s*$');
  static final RegExp _reHorizontalRule = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
  static final RegExp _reEscape = RegExp(r'\\([\\`*_{}\[\]()#+\-.!~>|])');
  static final RegExp _reInlineMath = RegExp(r'\$(?!\$)(\S(?:[^$\n]*?\S)?)\$(?!\$)');

  // 解析缓存（键 = 完整文本 + 颜色，防止哈希碰撞串显）
  static final Map<String, TextSpan> _cache = {};

  static TextSpan parse(String text, Color textColor) {
    final cacheKey = '$text\u0000${textColor.value}';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;
    final result = _parseImpl(_normalizeDashTables(text), textColor);
    if (_cache.length > 200) _cache.clear();
    _cache[cacheKey] = result;
    return result;
  }

  // 把"无管道空格对齐表"预处理成标准管道表（围栏代码块内不转换）
  static String _normalizeDashTables(String text) {
    final lines = text.split('\n');
    final out = <String>[];
    var inCode = false;
    var inDashTable = false;
    var tableCols = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('```')) {
        inCode = !inCode;
        out.add(line);
        continue;
      }
      if (inCode) {
        out.add(line);
        continue;
      }
      final t = line.trim();
      if (t.isEmpty) {
        inDashTable = false;
        out.add(line);
        continue;
      }
      if (!inDashTable && out.isNotEmpty && out.last.trim().isNotEmpty && !out.last.contains('|') && _reDashRowSep.hasMatch(line)) {
        final sepCols = t.split(_reAlignSplitAnySpace).length;
        var headerCells = out.last.trim().split(_reAlignSplit);
        if (headerCells.length != sepCols) {
          final single = out.last.trim().split(_reAlignSplitAnySpace);
          if (single.length == sepCols) headerCells = single;
        }
        if (headerCells.length >= 2 && headerCells.length == sepCols) {
          inDashTable = true;
          tableCols = headerCells.length;
          out[out.length - 1] = '| ${headerCells.join(' | ')} |';
          out.add('|${List.filled(tableCols, ' --- ').join('|')}|');
          continue;
        }
      }
      if (inDashTable) {
        if (t.startsWith('#') || t.startsWith('>') || t.startsWith('```')) {
          inDashTable = false;
          out.add(line);
          continue;
        }
        if (t.contains('|')) {
          out.add(line);
          continue;
        }
        final cells = t.split(_reAlignSplit).where((c) => c.isNotEmpty).toList();
        if (cells.isEmpty) {
          out.add('');
          continue;
        }
        while (cells.length < tableCols) {
          cells.add('');
        }
        out.add('| ${cells.take(tableCols).join(' | ')} |');
        continue;
      }
      out.add(line);
    }
    return out.join('\n');
  }

  static final RegExp _reDashRowSep = RegExp(r'^\s*-{2,}(?:\s+-{2,})+\s*$');
  static final RegExp _reAlignSplit = RegExp(r'\s{2,}');
  static final RegExp _reAlignSplitAnySpace = RegExp(r'\s+');

  static TextSpan _parseImpl(String text, Color textColor) {
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    var inCodeBlock = false;
    String codeLang = '';
    final codeBuffer = <String>[];
    var lastWasBlockWidget = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.startsWith('```')) {
        if (inCodeBlock) {
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: CodeCard(code: codeBuffer.join('\n'), lang: codeLang),
          ));
          codeBuffer.clear();
          inCodeBlock = false;
          codeLang = '';
          lastWasBlockWidget = true;
        } else {
          inCodeBlock = true;
          codeLang = line.length > 3 ? line.substring(3).trim() : '';
        }
        continue;
      }

      if (inCodeBlock) {
        codeBuffer.add(line);
        continue;
      }

      if (i > 0) {
        if (lastWasBlockWidget && line.trim().isEmpty) {
          continue;
        }
        spans.add(const TextSpan(text: '\n'));
      }
      lastWasBlockWidget = false;

      final trimmedLine = line.trim();
      if (trimmedLine.startsWith('\$\$')) {
        var body = trimmedLine.substring(2);
        var closed = false;
        if (body.endsWith('\$\$')) {
          body = body.substring(0, body.length - 2);
          closed = true;
        }
        if (!closed) {
          final buf = <String>[];
          if (body.trim().isNotEmpty) buf.add(body);
          var j = i + 1;
          while (j < lines.length) {
            final l = lines[j].trim();
            if (l == '\$\$') {
              j++;
              break;
            }
            if (l.endsWith('\$\$') && l.length > 2) {
              buf.add(l.substring(0, l.length - 2));
              j++;
              break;
            }
            buf.add(lines[j]);
            j++;
          }
          body = buf.join('\n').trim();
          i = j - 1;
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildMathBlock(body, textColor),
        ));
        lastWasBlockWidget = true;
        continue;
      }

      if (_reHorizontalRule.hasMatch(line)) {
        if (spans.isNotEmpty && spans.last is TextSpan && (spans.last as TextSpan).text == '\n') {
          spans.removeLast();
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            height: 1,
            color: textColor.withValues(alpha: 0.15),
          ),
        ));
        lastWasBlockWidget = true;
        continue;
      }

      if (_reTableRow.hasMatch(line) &&
          i + 1 < lines.length &&
          _reTableSeparator.hasMatch(lines[i + 1]) &&
          _parseTableRow(line).any((c) => c.trim().isNotEmpty)) {
        final headerCells = _parseTableRow(line);
        final alignments = _parseTableAlignments(lines[i + 1]);
        final rows = <List<String>>[];
        var j = i + 2;
        while (j < lines.length && _reTableRow.hasMatch(lines[j])) {
          rows.add(_parseTableRow(lines[j]));
          j++;
        }
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.top,
          child: _buildMarkdownTable(headerCells, rows, alignments, textColor),
        ));
        i = j - 1;
        lastWasBlockWidget = true;
        continue;
      }

      // 引用：左侧圆角竖条 + 支持行内 markdown
      if (line == '>' || line.startsWith('> ')) {
        final content = line == '>' ? '' : line.substring(2);
        final inner = <InlineSpan>[];
        _parseInlineSpans(content, textColor, inner);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: inner),
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: textColor),
                  ),
                ),
              ],
            ),
          ),
        ));
        continue;
      }

      // 标题（大 17.5 / 中 16 / 小 14，加粗）
      if (line.startsWith('### ')) {
        spans.add(TextSpan(text: line.substring(4), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor, height: 1.5)));
        continue;
      }
      if (line.startsWith('## ')) {
        spans.add(TextSpan(text: line.substring(3), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: textColor, height: 1.5)));
        continue;
      }
      if (line.startsWith('# ')) {
        spans.add(TextSpan(text: line.substring(2), style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: textColor, height: 1.5)));
        continue;
      }
      // 无序列表
      if (line.startsWith('- ') || line.startsWith('* ')) {
        spans.add(const TextSpan(text: '• ', style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))));
        _parseInlineSpans(line.substring(2), textColor, spans);
        continue;
      }
      // 有序列表
      final orderedMatch = _reOrderedList.firstMatch(line);
      if (orderedMatch != null) {
        spans.add(TextSpan(text: '${orderedMatch.group(1)}. ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF7C3AED))));
        _parseInlineSpans(orderedMatch.group(2)!, textColor, spans);
        continue;
      }
      // 普通行
      _parseInlineSpans(line, textColor, spans);
    }

    // 流式未闭合代码块：已累积部分渲染为实时代码卡片（内容不丢弃）
    if (inCodeBlock && codeBuffer.isNotEmpty) {
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: CodeCard(code: codeBuffer.join('\n'), lang: codeLang),
      ));
    }
    return TextSpan(children: spans, style: TextStyle(fontSize: 14.5, height: 1.5));
  }

  static void _parseInlineSpans(String text, Color textColor, List<InlineSpan> spans) {
    final patterns = <RegExp>[
      _reStrikethrough,
      _reBold,
      _reItalic,
      _reInlineCode,
      _reLink,
      _reInlineMath,
      _reEscape,
    ];
    var remaining = text;
    while (remaining.isNotEmpty) {
      int? earliestStart;
      int? earliestEnd;
      RegExpMatch? earliestMatch;
      RegExp? earliestPattern;
      for (final pattern in patterns) {
        final m = pattern.firstMatch(remaining);
        if (m != null && (earliestStart == null || m.start < earliestStart)) {
          earliestStart = m.start;
          earliestEnd = m.end;
          earliestMatch = m;
          earliestPattern = pattern;
        }
      }
      if (earliestMatch == null) {
        spans.add(TextSpan(text: remaining, style: TextStyle(color: textColor)));
        break;
      }
      if (earliestStart! > 0) {
        spans.add(TextSpan(text: remaining.substring(0, earliestStart), style: TextStyle(color: textColor)));
      }
      if (earliestPattern == patterns[0]) {
        spans.add(TextSpan(text: earliestMatch.group(1)!, style: TextStyle(color: textColor.withValues(alpha: 0.5), decoration: TextDecoration.lineThrough)));
      } else if (earliestPattern == patterns[1]) {
        spans.add(TextSpan(text: earliestMatch.group(1)!, style: TextStyle(color: textColor, fontWeight: FontWeight.w700)));
      } else if (earliestPattern == patterns[2]) {
        spans.add(TextSpan(text: earliestMatch.group(1)!, style: TextStyle(color: textColor, fontStyle: FontStyle.italic)));
      } else if (earliestPattern == patterns[3]) {
        // 行内代码：背景色 TextSpan（禁用 WidgetSpan 芯片——数量大时 Paragraph 布局崩溃）
        spans.add(TextSpan(
          text: earliestMatch.group(1)!,
          style: TextStyle(
            color: textColor,
            fontSize: 12.5,
            fontFamily: 'Consolas',
            backgroundColor: textColor.withValues(alpha: 0.12),
          ),
        ));
      } else if (earliestPattern == patterns[5]) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildInlineMath(earliestMatch.group(1)!, textColor),
        ));
      } else if (earliestPattern == patterns[6]) {
        spans.add(TextSpan(text: earliestMatch.group(1), style: TextStyle(color: textColor)));
      } else {
        spans.add(TextSpan(
          text: earliestMatch.group(1)!,
          style: TextStyle(color: const Color(0xFF7C3AED), decoration: TextDecoration.underline),
        ));
      }
      remaining = remaining.substring(earliestEnd!);
    }
  }

  static List<String> _parseTableRow(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).toList();
  }

  static List<TextAlign> _parseTableAlignments(String sepLine) {
    final cells = _parseTableRow(sepLine);
    return cells.map((c) {
      final p = c.trim();
      if (p.startsWith(':') && p.endsWith(':')) return TextAlign.center;
      if (p.endsWith(':')) return TextAlign.right;
      return TextAlign.left;
    }).toList();
  }

  static Widget _buildMathBlock(String tex, Color textColor) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.10), width: 0.6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          tex,
          mathStyle: MathStyle.display,
          textStyle: TextStyle(fontSize: 14, color: textColor),
          onErrorFallback: (err) => Text(
            '\$\$$tex\$\$',
            style: TextStyle(fontSize: 12.5, color: textColor.withValues(alpha: 0.75), fontFamily: 'Consolas'),
          ),
        ),
      ),
    );
  }

  static Widget _buildInlineMath(String tex, Color textColor) {
    return Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: TextStyle(fontSize: 13, color: textColor),
      onErrorFallback: (err) => Text(
        '\$$tex\$',
        style: TextStyle(fontSize: 12.5, color: textColor.withValues(alpha: 0.75), fontFamily: 'Consolas'),
      ),
    );
  }

  static Widget _buildMarkdownTable(
    List<String> headers,
    List<List<String>> rows,
    List<TextAlign> alignments,
    Color textColor,
  ) {
    final colCount = <int>[headers.length, alignments.length, ...rows.map((r) => r.length)]
        .fold<int>(0, (a, b) => a > b ? a : b);
    while (headers.length < colCount) {
      headers.add('');
    }
    while (alignments.length < colCount) {
      alignments.add(TextAlign.left);
    }
    for (var r = 0; r < rows.length; r++) {
      while (rows[r].length < colCount) {
        rows[r].add('');
      }
    }

    final borderColor = textColor.withValues(alpha: 0.18);
    final headerBg = textColor.withValues(alpha: 0.10);
    final headerText = textColor;

    Widget cellText(String content, {required bool isHeader, required TextAlign align}) {
      final base = TextStyle(
        fontSize: 12.5,
        color: isHeader ? headerText : textColor,
        fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
        height: 1.45,
        decoration: TextDecoration.none,
      );
      final codeRe = RegExp(r'`([^`]+)`');
      if (!codeRe.hasMatch(content)) {
        return Text(content, style: base, textAlign: align);
      }
      final spans = <TextSpan>[];
      var rest = content;
      while (rest.isNotEmpty) {
        final m = codeRe.firstMatch(rest);
        if (m == null) {
          spans.add(TextSpan(text: rest, style: base));
          break;
        }
        if (m.start > 0) {
          spans.add(TextSpan(text: rest.substring(0, m.start), style: base));
        }
        spans.add(TextSpan(
          text: m.group(1),
          style: base.copyWith(
            fontFamily: 'Consolas',
            fontSize: 12,
            color: const Color(0xFF7C3AED),
            backgroundColor: textColor.withValues(alpha: 0.06),
          ),
        ));
        rest = rest.substring(m.end);
      }
      return Text.rich(TextSpan(children: spans), textAlign: align);
    }

    Widget buildCell(String content, {required bool isHeader, required TextAlign align}) {
      return Container(
        decoration: BoxDecoration(
          color: isHeader ? headerBg : Colors.transparent,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        alignment: align == TextAlign.center
            ? Alignment.center
            : (align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft),
        child: cellText(content, isHeader: isHeader, align: align),
      );
    }

    final tableRows = <TableRow>[];
    tableRows.add(TableRow(
      children: [
        for (var c = 0; c < colCount; c++)
          buildCell(headers[c], isHeader: true, align: alignments[c]),
      ],
    ));
    for (final row in rows) {
      tableRows.add(TableRow(
        children: [
          for (var c = 0; c < colCount; c++)
            buildCell(row[c], isHeader: false, align: alignments[c]),
        ],
      ));
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: double.infinity,
          child: Table(
            columnWidths: {
              for (var c = 0; c < colCount; c++) c: const FlexColumnWidth(1.0),
            },
            border: TableBorder(
              top: BorderSide(color: borderColor, width: 0.5),
              bottom: BorderSide(color: borderColor, width: 0.5),
              horizontalInside: BorderSide(color: borderColor, width: 0.5),
              verticalInside: BorderSide(color: borderColor, width: 0.5),
            ),
            defaultVerticalAlignment: TableCellVerticalAlignment.fill,
            children: tableRows,
          ),
        ),
      ),
    );
  }
}
