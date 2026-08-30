// AI 逐题作答的答案解析逻辑验证（纯 Dart，不依赖 Flutter）
// 从 lib/state.dart 中复制的两个纯函数 + 一组断言用例

int? _parseLetterIdx(String reply, int optionCount) {
  int? toIdx(String? s) {
    if (s == null || s.isEmpty) return null;
    final idx = s.toUpperCase().codeUnitAt(0) - 65;
    return (idx >= 0 && idx < optionCount) ? idx : null;
  }

  final t = reply.trim();
  // 1) 整条回复就是（或以）一个字母开头：A / (B) / C. / D、
  final m1 = RegExp(r'^\(?([A-Za-z])\)?[.、:：）)]?\s').firstMatch('$t ');
  final i1 = toIdx(m1?.group(1));
  if (i1 != null) return i1;
  // 2) "答案：B" / "answer is B" / "选项 C" 等
  final m2 = RegExp(r'(?:答案|answer|选项|选|option|choice)[^A-Za-z]{0,6}\(?([A-Za-z])\)?', caseSensitive: false).firstMatch(t);
  final i2 = toIdx(m2?.group(1));
  if (i2 != null) return i2;
  // 3) 兜底：首个独立出现的字母
  for (final m in RegExp(r'(?<![A-Za-z])([A-Za-z])(?![A-Za-z])').allMatches(t)) {
    final i3 = toIdx(m.group(1));
    if (i3 != null) return i3;
  }
  return null;
}

int? _matchWordBankIdx(String reply, List<String> wordBank) {
  var w = reply.trim();
  // 剥离 "C. word" / "(B) word" / "word." 等包装
  w = w.replaceFirst(RegExp(r'^\(?[A-Za-z][.、)）]\s*'), '');
  w = w.replaceAll(RegExp(r'[^A-Za-z\- ]'), '').trim();
  if (w.isEmpty) return null;
  var idx = wordBank.indexWhere((b) => b.toLowerCase() == w.toLowerCase());
  if (idx >= 0) return idx;
  idx = wordBank.indexWhere((b) => b.toLowerCase().startsWith(w.toLowerCase()));
  if (idx >= 0) return idx;
  idx = wordBank.indexWhere((b) => w.toLowerCase().startsWith(b.toLowerCase()));
  return idx >= 0 ? idx : null;
}

int _passed = 0, _failed = 0;

void check(String name, Object? actual, Object? expected) {
  if (actual == expected) {
    _passed++;
  } else {
    _failed++;
    print('FAIL: $name  expected=$expected  actual=$actual');
  }
}

void main() {
  // ===== 选项字母解析 =====
  check('纯字母 A', _parseLetterIdx('A', 4), 0);
  check('纯字母 B', _parseLetterIdx('B', 4), 1);
  check('带括号 (C)', _parseLetterIdx('(C)', 4), 2);
  check('带点 D.', _parseLetterIdx('D.', 4), 3);
  check('带顿号 B、', _parseLetterIdx('B、', 4), 1);
  check('答案：C', _parseLetterIdx('答案：C', 4), 2);
  check('答案是 B', _parseLetterIdx('答案是 B', 4), 1);
  check('answer is D', _parseLetterIdx('The answer is D', 4), 3);
  check('选项 A', _parseLetterIdx('选项 A', 4), 0);
  check('字母在范围内', _parseLetterIdx('C. because', 4), 2);
  check('小写 b', _parseLetterIdx('b', 4), 1);
  check('超出范围 E(4项)', _parseLetterIdx('E', 4), null);
  check('空回复', _parseLetterIdx('', 4), null);
  check('无字母', _parseLetterIdx('我不知道', 4), null);
  check('7选项 G', _parseLetterIdx('G', 7), 6);
  check('7选项 H 越界', _parseLetterIdx('H', 7), null);

  // ===== 选词填空词库匹配 =====
  final bank = ['achieve', 'benefit', 'crucial', 'develop', 'efficient'];
  check('纯单词', _matchWordBankIdx('crucial', bank), 2);
  check('带字母前缀 C. crucial', _matchWordBankIdx('C. crucial', bank), 2);
  check('带括号 (B) benefit', _matchWordBankIdx('(B) benefit', bank), 1);
  check('大写 CRUCIAL', _matchWordBankIdx('CRUCIAL', bank), 2);
  check('带句号 achieve.', _matchWordBankIdx('achieve.', bank), 0);
  check('前缀匹配 developing→develop', _matchWordBankIdx('developing', bank), 3);
  check('词库外单词', _matchWordBankIdx('elephant', bank), null);
  check('空回复', _matchWordBankIdx('', bank), null);

  print('通过 $_passed / ${_passed + _failed}');
  if (_failed > 0) {
    print('存在失败用例');
  }
}
