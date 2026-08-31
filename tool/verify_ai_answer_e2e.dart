// 端到端校验：模拟推理模型返回空 content + reasoning_content 有内容（含 think 块），
// 确认 ApiService 归一化 + _stripThinkTags + _parseLetterIdx + _matchWordBankIdx
// 完整链路能拿到正解（用真实可访问的静态方法 + 内联逻辑模拟私有方法）。
// 用法：dart run tool/verify_ai_answer_e2e.dart
// ignore_for_file: avoid_print

import '../lib/services/api_service.dart';
import '../lib/models.dart';

/// 与 state.dart _stripThinkTags 完全一致的剥 think 块逻辑（仅在这里复刻以做黑盒验证）
String stripThinkTags(String s) =>
    s.replaceAll(RegExp(r'<think(?:ing)?>[\s\S]*?</think(?:ing)?>', caseSensitive: false), '').trim();

/// 与 state.dart _parseLetterIdx 完全一致的字母解析（仅在这里复刻以做黑盒验证）
int? parseLetterIdx(String reply, int optionCount, [List<String> options = const <String>[]]) {
  int? toIdx(String? s) {
    if (s == null || s.isEmpty) return null;
    final idx = s.toUpperCase().codeUnitAt(0) - 65;
    return (idx >= 0 && idx < optionCount) ? idx : null;
  }

  final tt = reply.trim();
  if (options.isNotEmpty) {
    final low = tt.toLowerCase();
    for (var i = 0; i < options.length && i < optionCount; i++) {
      final o = options[i].trim().toLowerCase();
      if (o.isNotEmpty && (low == o || low.endsWith(o))) return i;
    }
  }
  final m1 = RegExp(r'^\(?([A-Za-z])\)?[.、:：）)]?\s').firstMatch('$tt ');
  final i1 = toIdx(m1?.group(1));
  if (i1 != null) return i1;
  final m2 = RegExp(r'(?:答案|answer|选项|选|option|choice)[^A-Za-z]{0,6}\(?([A-Za-z])\)?', caseSensitive: false).firstMatch(tt);
  final i2 = toIdx(m2?.group(1));
  if (i2 != null) return i2;
  for (final m in RegExp(r'(?<![A-Za-z])([A-Za-z])(?![A-Za-z])').allMatches(tt)) {
    final i3 = toIdx(m.group(1));
    if (i3 != null) return i3;
  }
  return null;
}

/// 与 state.dart _matchWordBankIdx 多行版完全一致（复刻以做黑盒验证）
int? matchWordBankIdx(String reply, List<String> wordBank) {
  if (wordBank.isEmpty) return null;
  final rawLines = reply
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (rawLines.isEmpty) return null;

  /// 把一行文本剥前缀包装+标点后取出首个单词；不是有效单词返回 null
  String? firstWord(String line) {
    var w = line.replaceFirst(RegExp(r'^\(?[A-Za-z][.、)）：:]\s*'), '');
    w = w.replaceAll(RegExp(r'[^A-Za-z\- ]'), '').trim();
    if (w.isEmpty) return null;
    final head = w.split(RegExp(r'\s+')).first;
    return head.isEmpty ? null : head;
  }

  /// 在词库中按精确/前缀/反向前缀查
  int? lookup(String head) {
    var idx = wordBank.indexWhere((b) => b.toLowerCase() == head.toLowerCase());
    if (idx >= 0) return idx;
    idx = wordBank.indexWhere((b) => b.toLowerCase().startsWith(head.toLowerCase()));
    if (idx >= 0) return idx;
    idx = wordBank.indexWhere((b) => head.toLowerCase().startsWith(b.toLowerCase()));
    return idx >= 0 ? idx : null;
  }

  // 1) 优先用首行；若首行只是单字母（仅是选项标识）则向后找含真实单词的行
  for (var i = 0; i < rawLines.length; i++) {
    final head = firstWord(rawLines[i]);
    if (head == null) continue;
    if (head.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(head) && i < rawLines.length - 1) {
      continue; // 单字母包装，跳过继续看后续行
    }
    return lookup(head);
  }
  return null;
}

void main() {
  var pass = 0, fail = 0;
  void check(String name, bool ok, [String? detail]) {
    if (ok) {
      pass++;
      print('  ✓ $name');
    } else {
      fail++;
      print('  ✗ $name  ${detail ?? ''}');
    }
  }

  print('── 1) ApiService.extractJsonArray 对推理模型包裹的 JSON 仍能提取 ──');
  final j1 = ApiService.extractJsonArray('[{"q":"A"}, {"q":"B"}]');
  check('标准 JSON 数组可解', j1 != null && j1.length == 2);
  final j2 = ApiService.extractJsonArray('<think>reasoning</think>[{"q":"X"}]');
  check('think 块包裹 JSON 也能提取', j2 != null && j2.length == 1,
      'got=$j2');

  print('── 2) ApiService 推理模型空 content + reasoning_content 含正文 → 应回退正文 ──');
  // 这条直接复刻 ApiService 修复后的归一化路径
  String mockNormalize(String content, String reasoning) {
    final c = content.trim();
    final r = reasoning.trim();
    return c.isEmpty ? r : c;
  }
  final norm = mockNormalize('', '<think>推理</think>\nB');
  check('空 content + 推理含 B → 归一化后含 B', norm.contains('B'), 'norm="$norm"');
  final stripped = stripThinkTags(norm);
  final letter = parseLetterIdx(stripped, 4);
  check('剥离 think 后解析为索引 1（B）', letter == 1, 'letter=$letter stripped="$stripped"');

  print('── 3) _parseLetterIdx 多格式正例 ──');
  final letterCases = <String, int?>{
    'A': 0,
    'B.': 1,
    '(B)': 1,
    'C,': 2,
    'D：': 3,
    'answer: A': 0,
    '选项 C': 2,
    '答案 B': 1,
    '选 D': 3,
    '选A': 0,
    'the answer is B': 1,
    'C\n因为...': 2,
    '<think>reasoning</think>A\ndone': 0,
    '答案\n\n选 A': 0,
  };
  for (final e in letterCases.entries) {
    final got = parseLetterIdx(e.key, 4);
    check('"${e.key.replaceAll('\n', '\\n')}" → ${e.value}', got == e.value, 'got=$got');
  }

  print('── 4) _parseLetterIdx 反例：超出范围/未匹配 ──');
  check('"E" 超范围返回 null', parseLetterIdx('E', 4) == null);
  check('空字符串返回 null', parseLetterIdx('', 4) == null);
  check('全标点返回 null', parseLetterIdx('......', 4) == null);

  print('── 5) _matchWordBankIdx 多行/字母包装/多词（新版） ──');
  final bank = ['walk', 'walks', 'walking', 'quickly', 'because', 'around'];
  final wordCases = <String, int?>{
    'walk': 0,
    'walks': 1,
    'walks.': 1,
    'B. walks': 1,
    '(B) walks': 1,
    'B、 walks': 1,
    'B: walks': 1,
    'walks\nbecause...': 1, // 多行：取首行后去标点 → "walks"
    'walks because': 1, // 多词：取首个分词 → "walks"
    'walked': 0, // "walked" 前缀 "walk" → startsWith 设计行为
    '': null,
    'B': null, // 模型纯字母答（词库首字母非 B）—— 设计上让字母包装失效
    'walks.': 1,
    'B.\nwalks': 1, // 多行：首行 "B." 剥成单字母 → 跳到下一行取 "walks"
  };
  for (final e in wordCases.entries) {
    final got = matchWordBankIdx(e.key, bank);
    check('"${e.key.replaceAll('\n', '\\n')}" → ${e.value}', got == e.value, 'got=$got');
  }

  print('── 6) ExamSection.kZsb2024ExamCounts 总数校验 ──');
  final counts = kZsb2024ExamCounts;
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  check('2024 真题 77 题（vocab+reading+cloze+dialogue+bankedCloze+en2zh5+writing）',
      total == 77, 'total=$total');

  print('\n════ $pass passed, $fail failed ════');
  if (fail > 0) {
    print('失败，请检查 ApiService / state.dart 的归一化与解析逻辑');
  }
}