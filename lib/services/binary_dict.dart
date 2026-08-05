/// 二进制词典：从 .bin 文件加载，支持 O(log n) 二分查找
///
/// 文件格式（小端序）：
/// Header (12B):  [count:u32][indexSize:u32][dataSize:u32]
/// Index section: 重复条目 [wordLen:u16][word:UTF-8][dataOffset:u32][dataLen:u32]
/// Data section:  重复条目 [phoneticLen:u16][phonetic][posLen:u16][pos][transLen:u16][trans][otherLen:u16][other]
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import '../models.dart';

class BinaryDict {
  Uint8List? _buf;
  List<_Idx>? _idx;
  int _dataBase = 0;
  List<String>? _wordsCache;
  bool _loaded = false;

  /// 从 Flutter asset 加载二进制词典
  Future<void> load(String assetPath) async {
    if (_loaded) return;
    _loaded = true;
    try {
      final bd = await rootBundle.load(assetPath);
      _buf = bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes);
      if (_buf!.length < 12) return;

      final count = _u32(0);
      final idxSize = _u32(4);

      _idx = [];
      var p = 12;
      final idxEnd = 12 + idxSize;

      while (p + 10 <= idxEnd && _idx!.length < count) {
        final wLen = _u16(p);
        if (p + 2 + wLen + 8 > idxEnd) break;
        final word = utf8.decode(_buf!.sublist(p + 2, p + 2 + wLen));
        final dOff = _u32(p + 2 + wLen);
        final dLen = _u32(p + 2 + wLen + 4);
        _idx!.add(_Idx(word, dOff, dLen));
        p += 2 + wLen + 8;
      }

      _dataBase = 12 + idxSize;
    } catch (_) {
      _buf = null;
      _idx = null;
    }
  }

  /// 是否已成功加载且有数据
  bool get isLoaded => _idx != null && _idx!.isNotEmpty;

  /// 二分查找单词，返回 DictEntry 或 null
  DictEntry? lookup(String word) {
    final idx = _idx;
    if (idx == null || idx.isEmpty) return null;
    final w = word.toLowerCase();
    var lo = 0, hi = idx.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final c = idx[mid].word.compareTo(w);
      if (c == 0) return _decode(idx[mid]);
      if (c < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  /// 所有单词列表（首次调用时缓存）
  List<String> words() {
    if (_wordsCache != null) return _wordsCache!;
    _wordsCache = _idx?.map((e) => e.word).toList() ?? [];
    return _wordsCache!;
  }

  /// 前缀搜索：返回所有以 [prefix] 开头的单词及其释义，最多 [limit] 条
  List<MapEntry<String, DictEntry>> searchPrefix(String prefix, {int limit = 20}) {
    final idx = _idx;
    if (idx == null || idx.isEmpty) return [];
    final p = prefix.toLowerCase();

    // 二分查找第一个 >= prefix 的位置
    var lo = 0, hi = idx.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (idx[mid].word.compareTo(p) < 0) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    final results = <MapEntry<String, DictEntry>>[];
    for (var i = lo; i < idx.length && results.length < limit; i++) {
      if (!idx[i].word.startsWith(p)) break;
      results.add(MapEntry(idx[i].word, _decode(idx[i])));
    }
    return results;
  }

  /// 模糊搜索：编辑距离 <= [maxDist] 的单词，最多 [limit] 条
  /// 对短词（<=4字符）maxDist 自动限制为 1，避免结果过多
  List<MapEntry<String, DictEntry>> searchFuzzy(String query, {int maxDist = 2, int limit = 20}) {
    final idx = _idx;
    if (idx == null || idx.isEmpty) return [];
    final q = query.toLowerCase();
    final effectiveMaxDist = q.length <= 4 ? 1 : maxDist;

    final results = <MapEntry<String, DictEntry>>[];
    for (final e in idx) {
      if (_editDistance(e.word, q) <= effectiveMaxDist) {
        results.add(MapEntry(e.word, _decode(e)));
        if (results.length >= limit) break;
      }
    }
    return results;
  }

  /// Levenshtein 编辑距离
  static int _editDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // 优化：长度差超过阈值直接返回
    final diff = (a.length - b.length).abs();
    if (diff > 2) return diff;

    final la = a.length, lb = b.length;
    var prev = List<int>.generate(lb + 1, (i) => i);
    var curr = List<int>.filled(lb + 1, 0);

    for (var i = 1; i <= la; i++) {
      curr[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = _min3(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[lb];
  }

  static int _min3(int a, int b, int c) => a < b ? (a < c ? a : c) : (b < c ? b : c);

  DictEntry _decode(_Idx e) {
    final buf = _buf!;
    var p = _dataBase + e.dataOff;
    final phLen = _u16(p); p += 2;
    final phonetic = utf8.decode(buf.sublist(p, p + phLen)); p += phLen;
    final psLen = _u16(p); p += 2;
    final pos = utf8.decode(buf.sublist(p, p + psLen)); p += psLen;
    final trLen = _u16(p); p += 2;
    final trans = utf8.decode(buf.sublist(p, p + trLen)); p += trLen;
    final otLen = _u16(p); p += 2;
    final other = utf8.decode(buf.sublist(p, p + otLen));
    return DictEntry(phonetic: phonetic, pos: pos, translation: trans, other: other);
  }

  int _u16(int o) => _buf![o] | (_buf![o + 1] << 8);
  int _u32(int o) => _buf![o] | (_buf![o + 1] << 8) | (_buf![o + 2] << 16) | (_buf![o + 3] << 24);
}

class _Idx {
  final String word;
  final int dataOff;
  final int dataLen;
  _Idx(this.word, this.dataOff, this.dataLen);
}
