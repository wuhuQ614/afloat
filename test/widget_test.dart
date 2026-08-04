import 'package:flutter_test/flutter_test.dart';
import 'package:smartenglish/models.dart';

void main() {
  test('题型名称映射', () {
    expect(qTypeName(QType.translation), '翻译题');
    expect(qTypeName(QType.choice), '选择题');
    expect(qTypeName(QType.reading), '阅读理解');
    expect(qTypeFrom('choice'), QType.choice);
  });

  test('难度名称映射', () {
    expect(levelName('zsb'), '专升本');
    expect(levelName('easy'), '简单');
  });
}
