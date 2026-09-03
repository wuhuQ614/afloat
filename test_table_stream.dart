// 模拟流式场景下 _normalizeDashTables 的行为
// 运行: dart run test_table_stream.dart

void main() {
  // 场景1: 标准管道表，逐行流式到达
  print('=== 场景1: 标准管道表逐行到达 ===');
  final rows1 = [
    '抽样预览（完整 186 词已就绪）',
    '',
    '| 单词 | 词性 | 释义 |',
    '|---|---|---|',
    '| excitement | n. | 兴奋 |',
    '| abandon | v. | 放弃 |',
    '| cherry | n. | 樱桃 |',
    '',
    '---',
    '',
    '还想对这批词做点什么？',
  ];
  simulateStreaming(rows1);

  // 场景2: 管道表数据行无尾管道
  print('\n=== 场景2: 数据行无尾管道 ===');
  final rows2 = [
    '抽样预览',
    '',
    '| 单词 | 词性 | 释义 |',
    '|---|---|---|',
    '| excitement | n. | 兴奋',
    '| abandon | v. | 放弃',
    '',
    '---',
    '',
    '后续内容',
  ];
  simulateStreaming(rows2);

  // 场景3: 无管道空格对齐表（dash table）
  print('\n=== 场景3: 无管道空格对齐表 ===');
  final rows3 = [
    '抽样预览',
    '',
    '单词  词性  释义',
    '---  ---  ---',
    'excitement  n.  兴奋',
    'abandon  v.  放弃',
    '',
    '---',
    '',
    '后续内容',
  ];
  simulateStreaming(rows3);

  // 场景4: 混合格式 - 表头无管道，数据行有管道
  print('\n=== 场景4: 表头无管道，数据行有管道 ===');
  final rows4 = [
    '抽样预览',
    '',
    '单词 词性 释义',
    '--- --- ---',
    '| excitement | n. | 兴奋 |',
    '| abandon | v. | 放弃 |',
    '',
    '---',
    '',
    '后续内容',
  ];
  simulateStreaming(rows4);

  // 场景5: 分隔行无首管道
  print('\n=== 场景5: 分隔行无首管道 ===');
  final rows5 = [
    '抽样预览',
    '',
    '| 单词 | 词性 | 释义 |',
    '---|---|---|',
    '| excitement | n. | 兴奋 |',
    '| abandon | v. | 放弃 |',
    '',
    '---',
    '',
    '后续内容',
  ];
  simulateStreaming(rows5);
}

void simulateStreaming(List<String> rows) {
  var accumulated = '';
  for (var i = 0; i < rows.length; i++) {
    accumulated += rows[i] + (i < rows.length - 1 ? '\n' : '');
    final normalized = normalizeDashTables(accumulated);
    final tableInfo = detectTable(normalized);
    print('步骤 ${i + 1} (行 "${rows[i].length > 40 ? rows[i].substring(0, 40) + "..." : rows[i]}"): '
        '表格检测=${tableInfo.detected ? "是(行数=${tableInfo.rowCount})" : "否"}, '
        '包含管道表行=${normalized.contains("|") ? "是" : "否"}');
    if (tableInfo.detected && tableInfo.rowCount == 0) {
      print('  ⚠️ 表格已检测但0数据行！表头: ${tableInfo.header}');
    }
    if (!tableInfo.detected && normalized.contains('|')) {
      // 检查是否有未被识别的管道行
      final lines = normalized.split('\n');
      final pipeLines = lines.where((l) => l.trim().startsWith('|') && l.trim().endsWith('|')).toList();
      if (pipeLines.isNotEmpty) {
        print('  ⚠️ 有管道行但未检测为表格: ${pipeLines.take(3).map((l) => '"$l"').join(", ")}');
      }
    }
  }
}

class TableInfo {
  final bool detected;
  final int rowCount;
  final String header;
  TableInfo(this.detected, this.rowCount, this.header);
}

TableInfo detectTable(String text) {
  // R38: 尾 `|` 可选——与 lib/main.dart 同步
  final reTableRow = RegExp(r'^\s*\|.+\|?\s*$');
  final reTableSeparator = RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)+\|?\s*$');
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (reTableRow.hasMatch(lines[i]) &&
        i + 1 < lines.length &&
        reTableSeparator.hasMatch(lines[i + 1])) {
      final header = lines[i];
      final headerCells = parseTableRow(header);
      if (!headerCells.any((c) => c.trim().isNotEmpty)) {
        return TableInfo(false, 0, header);
      }
      var rowCount = 0;
      var j = i + 2;
      while (j < lines.length && reTableRow.hasMatch(lines[j])) {
        rowCount++;
        j++;
      }
      return TableInfo(true, rowCount, header);
    }
  }
  return TableInfo(false, 0, '');
}

List<String> parseTableRow(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((c) => c.trim()).toList();
}

// 复制 _normalizeDashTables 逻辑
final reDashRowSep = RegExp(r'^\s*-{2,}(?:\s+-{2,})+\s*$');
final reAlignSplit = RegExp(r'\s{2,}');
final reAlignSplitAnySpace = RegExp(r'\s+');

String normalizeDashTables(String text) {
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
    if (!inDashTable && out.isNotEmpty && out.last.trim().isNotEmpty && !out.last.contains('|') && reDashRowSep.hasMatch(line)) {
      // R38: 分隔行列数决定表头切法，支持单空格表头
      final sepCols = t.split(reAlignSplitAnySpace).length;
      var headerCells = out.last.trim().split(reAlignSplit);
      if (headerCells.length != sepCols) {
        final single = out.last.trim().split(reAlignSplitAnySpace);
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
      // R38: 已是管道格式的数据行保持原样
      if (t.contains('|')) {
        out.add(line);
        continue;
      }
      final cells = t.split(reAlignSplit).where((c) => c.isNotEmpty).toList();
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
