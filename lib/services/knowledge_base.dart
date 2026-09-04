/// 外挂知识库：用户上传的文本文档集合，供 AI 通过 search_knowledge_base 工具检索。
///
/// 存储基于 SharedPreferences（JSON），限制总量防止配置文件膨胀：
/// 单文档 ≤ 1MB，总量 ≤ 5MB。检索为本地关键词评分（切块 + 命中计分），无网络依赖。
library;

import 'dart:convert';

import 'storage.dart';

/// 知识库文档
class KbDoc {
  final String id;
  final String name;
  final String content;
  final int addedAt; // ms 时间戳

  const KbDoc({required this.id, required this.name, required this.content, required this.addedAt});

  int get sizeBytes => utf8.encode(content).length;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'content': content, 'addedAt': addedAt};

  static KbDoc fromJson(Map<String, dynamic> j) => KbDoc(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        addedAt: ((j['addedAt'] ?? 0) as num).toInt(),
      );
}

/// 检索命中片段
class KbHit {
  final KbDoc doc;
  final String snippet;
  final int score;

  const KbHit({required this.doc, required this.snippet, required this.score});
}

class KnowledgeBase {
  static const int kMaxDocBytes = 1 * 1024 * 1024; // 单文档 1MB
  static const int kMaxTotalBytes = 5 * 1024 * 1024; // 总量 5MB
  static const int _chunkSize = 600; // 切块长度（字符）
  static const int _chunkStep = 400; // 切块步长（相邻块重叠 200 字符）
  static const int _snippetMax = 500; // 返回片段截断

  static List<KbDoc> _docs = [];
  static bool _loaded = false;

  static List<KbDoc> get docs => List.unmodifiable(_docs);
  static bool get isEmpty => _docs.isEmpty;
  static int get totalBytes => _docs.fold(0, (n, d) => n + d.sizeBytes);

  static void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    final raw = Storage.loadKnowledgeBase();
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List?;
      if (list == null) return;
      _docs = list
          .whereType<Map<String, dynamic>>()
          .map(KbDoc.fromJson)
          .where((d) => d.id.isNotEmpty && d.content.isNotEmpty)
          .toList();
    } catch (_) {
      _docs = [];
    }
  }

  static void _persist() {
    Storage.saveKnowledgeBase(jsonEncode(_docs.map((d) => d.toJson()).toList()));
  }

  /// 添加文档。成功返回 null；失败返回错误原因（中文）。
  static String? add(String name, String content) {
    ensureLoaded();
    final bytes = utf8.encode(content).length;
    if (bytes > kMaxDocBytes) return '文件过大（${(bytes / 1024 / 1024).toStringAsFixed(1)}MB），单文档上限 1MB';
    if (totalBytes + bytes > kMaxTotalBytes) return '知识库总量已达上限（5MB），请先删除部分文档';
    final doc = KbDoc(
      id: 'kb-${DateTime.now().millisecondsSinceEpoch}-${_docs.length}',
      name: name,
      content: content,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _docs.add(doc);
    _persist();
    return null;
  }

  static bool remove(String id) {
    ensureLoaded();
    final n0 = _docs.length;
    _docs.removeWhere((d) => d.id == id);
    final changed = _docs.length != n0;
    if (changed) _persist();
    return changed;
  }

  static void clear() {
    _docs = [];
    _persist();
  }

  /// 生成给系统提示词的知识库概况（空库返回空串）
  static String catalogPrompt() {
    ensureLoaded();
    if (_docs.isEmpty) return '';
    final sb = StringBuffer()
      ..writeln('## 外挂知识库')
      ..writeln('用户已上传 ${_docs.length} 份知识库文档：${_docs.map((d) => d.name).join('、')}。')
      ..writeln('当用户的问题可能与这些文档相关时，先调用 search_knowledge_base 工具检索相关片段，再基于检索结果回答；')
      ..writeln('检索无结果时如实说明，不要编造文档内容。');
    return sb.toString();
  }

  /// 关键词检索：把查询拆成词元（英文按空格、中文按 2 字滑窗），
  /// 对每篇文档切块计分，返回得分最高的片段。
  static List<KbHit> search(String query, {int topK = 5}) {
    ensureLoaded();
    final terms = _tokenize(query);
    if (terms.isEmpty || _docs.isEmpty) return [];
    final hits = <KbHit>[];
    for (final doc in _docs) {
      for (final chunk in _chunks(doc.content)) {
        final lower = chunk.toLowerCase();
        var score = 0;
        for (final t in terms) {
          var idx = 0;
          while (true) {
            idx = lower.indexOf(t, idx);
            if (idx < 0) break;
            score++;
            idx += t.length;
          }
        }
        if (score > 0) {
          hits.add(KbHit(
            doc: doc,
            snippet: chunk.length > _snippetMax ? chunk.substring(0, _snippetMax) : chunk,
            score: score,
          ));
        }
      }
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(topK).toList();
  }

  /// 词元化：英文/数字按连续段，CJK 按 2 字滑窗（兼顾词组与短词）
  static List<String> _tokenize(String q) {
    final out = <String>{};
    final buffer = StringBuffer();
    void flush() {
      final w = buffer.toString().trim().toLowerCase();
      if (w.length >= 2) out.add(w);
      buffer.clear();
    }

    for (final ch in q.runes) {
      final c = String.fromCharCode(ch);
      final isCjk = ch >= 0x4E00 && ch <= 0x9FFF;
      final isWord = !isCjk && (ch > 32 && ch != 44 && ch != 46 && ch != 12289 && ch != 12290);
      if (isCjk) {
        flush();
        out.add(c);
      } else if (isWord) {
        buffer.write(c);
      } else {
        flush();
      }
    }
    flush();
    // 中文 2 字滑窗（补充词组命中）
    final cjk = q.runes.where((r) => r >= 0x4E00 && r <= 0x9FFF).map(String.fromCharCode).toList();
    for (var i = 0; i + 1 < cjk.length; i++) {
      out.add('${cjk[i]}${cjk[i + 1]}');
    }
    return out.where((t) => t.isNotEmpty).toList();
  }

  static List<String> _chunks(String text) {
    if (text.length <= _chunkSize) return [text];
    final out = <String>[];
    for (var i = 0; i < text.length; i += _chunkStep) {
      out.add(text.substring(i, (i + _chunkSize).clamp(0, text.length)));
      if (i + _chunkSize >= text.length) break;
    }
    return out;
  }
}
