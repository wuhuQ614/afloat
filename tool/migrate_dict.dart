/// JSON → 二进制词库迁移工具
/// 用法: dart run tool/migrate_dict.dart
///
/// 二进制格式：
/// Header (12 bytes):
///   [4B count][4B indexSectionSize][4B dataSectionSize]
///
/// Index section（按 word 排序，用于二分查找）：
///   每个条目: [2B wordLen][word bytes][4B dataOffset][4B dataLen]
///
/// Data section：
///   每个条目: [2B phoneticLen][phonetic][2B posLen][pos][2B transLen][trans][2B otherLen][other]
import 'dart:convert';
import 'dart:io';

void main() async {
  await migrate('assets/dict-merged.json', 'assets/dict.bin');
  await migrate('assets/zsb-dict.json', 'assets/zsb-dict.bin');
  print('Done!');
}

Future<void> migrate(String jsonPath, String binPath) async {
  final jsonFile = File(jsonPath);
  if (!jsonFile.existsSync()) {
    print('Skip $jsonPath (not found)');
    return;
  }

  final raw = await jsonFile.readAsString(encoding: utf8);
  final obj = jsonDecode(raw) as Map<String, dynamic>;

  final entries = <_Entry>[];
  obj.forEach((word, v) {
    final m = v as Map<String, dynamic>;
    entries.add(_Entry(
      word: word.toLowerCase(),
      phonetic: (m['phonetic'] ?? '') as String,
      pos: (m['pos'] ?? '') as String,
      translation: (m['translation'] ?? '') as String,
      other: (m['other'] ?? '') as String,
    ));
  });

  entries.sort((a, b) => a.word.compareTo(b.word));

  // 第一遍：计算 index 和 data 大小
  var indexSize = 0;
  var dataSize = 0;
  final indexEntrySizes = <int>[];
  final dataEntrySizes = <int>[];

  for (final e in entries) {
    final wordBytes = utf8.encode(e.word);
    final phoneticBytes = utf8.encode(e.phonetic);
    final posBytes = utf8.encode(e.pos);
    final transBytes = utf8.encode(e.translation);
    final otherBytes = utf8.encode(e.other);

    final ieSize = 2 + wordBytes.length + 4 + 4;
    final deSize = 2 + phoneticBytes.length + 2 + posBytes.length + 2 + transBytes.length + 2 + otherBytes.length;

    indexEntrySizes.add(ieSize);
    dataEntrySizes.add(deSize);
    indexSize += ieSize;
    dataSize += deSize;
  }

  // 第二遍：写入文件
  final outBuf = BytesBuilder(copy: false);

  // Header
  outBuf.add(_uint32(entries.length));
  outBuf.add(_uint32(indexSize));
  outBuf.add(_uint32(dataSize));

  // Index section
  var dataOffset = 0;
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final wordBytes = utf8.encode(e.word);
    outBuf.add(_uint16(wordBytes.length));
    outBuf.add(wordBytes);
    outBuf.add(_uint32(dataOffset));
    outBuf.add(_uint32(dataEntrySizes[i]));
    dataOffset += dataEntrySizes[i];
  }

  // Data section
  for (final e in entries) {
    final phoneticBytes = utf8.encode(e.phonetic);
    final posBytes = utf8.encode(e.pos);
    final transBytes = utf8.encode(e.translation);
    final otherBytes = utf8.encode(e.other);

    outBuf.add(_uint16(phoneticBytes.length));
    outBuf.add(phoneticBytes);
    outBuf.add(_uint16(posBytes.length));
    outBuf.add(posBytes);
    outBuf.add(_uint16(transBytes.length));
    outBuf.add(transBytes);
    outBuf.add(_uint16(otherBytes.length));
    outBuf.add(otherBytes);
  }

  final outFile = File(binPath);
  await outFile.writeAsBytes(outBuf.toBytes());

  final sizeKB = outFile.lengthSync() / 1024;
  print('$jsonPath -> $binPath: ${entries.length} entries, ${sizeKB.toStringAsFixed(1)} KB');
}

class _Entry {
  final String word, phonetic, pos, translation, other;
  _Entry({required this.word, required this.phonetic, required this.pos, required this.translation, required this.other});
}

List<int> _uint16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _uint32(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];
