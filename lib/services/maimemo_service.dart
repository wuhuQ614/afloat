/// 墨墨开放 API 服务：读取用户在墨墨背单词的学习数据，供 AFloat 同步。
///
/// 官方文档：https://open.maimemo.com/
/// 鉴权：Bearer token（墨墨 App「我的 → 更多设置 → 实验功能 → 开放 API」获取）
/// 频控：10秒20次 / 60秒40次 / 5小时2000次（墨墨背单词）
/// 所有 POST 请求的响应体均为 { "data": {...} } 结构。
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// 今日学习进度
class MaimemoProgress {
  final int finished;
  final int total;
  final int studyTime; // 秒
  const MaimemoProgress({
    required this.finished,
    required this.total,
    required this.studyTime,
  });
}

/// 今日学习单词条目
class MaimemoTodayWord {
  final String vocId;
  final String spelling;
  final int order;
  final String? firstResponse;
  final bool isNew;
  final bool isFinished;
  const MaimemoTodayWord({
    required this.vocId,
    required this.spelling,
    required this.order,
    this.firstResponse,
    required this.isNew,
    required this.isFinished,
  });
}

/// 学习记录条目（含复习状态）
class MaimemoStudyRecord {
  final String vocId;
  final String spelling;
  final String? addDate;
  final String? firstStudyDate;
  final String? lastStudyDate;
  final String? nextStudyDate;
  final int studyCount;
  const MaimemoStudyRecord({
    required this.vocId,
    required this.spelling,
    this.addDate,
    this.firstStudyDate,
    this.lastStudyDate,
    this.nextStudyDate,
    required this.studyCount,
  });
}

/// 词汇查询结果（仅 id + spelling）
class MaimemoVocabulary {
  final String id;
  final String spelling;
  const MaimemoVocabulary({required this.id, required this.spelling});
}

/// 单词完整详情（墨墨仅提供 id + spelling，音标/发音不提供）
class MaimemoVocabularyDetail {
  final String id;
  final String spelling;
  const MaimemoVocabularyDetail({required this.id, required this.spelling});
}

/// 释义条目
class MaimemoDefinition {
  final String id;
  final String content; // 中文释义（如 "n. 苹果；苹果树"）
  final List<String> tags; // 标签（如来源/分类）
  const MaimemoDefinition({required this.id, required this.content, this.tags = const []});
}

/// 例句条目（墨墨的 phrase）
class MaimemoExample {
  final String id;
  final String content; // 英文句子
  final String translation; // 中文翻译
  final String source; // 来源
  const MaimemoExample({required this.id, required this.content, this.translation = '', this.source = ''});
}

/// 助记条目
class MaimemoNote {
  final String id;
  final String content; // 助记内容（谐音/联想等）
  final String type; // 类型（如"谐音"）
  const MaimemoNote({required this.id, required this.content, this.type = ''});
}

/// 墨墨查词聚合结果（释义 + 例句 + 助记）
class MaimemoWordLookup {
  final String word;
  final MaimemoVocabularyDetail? detail;
  final List<MaimemoDefinition> definitions;
  final List<MaimemoExample> examples;
  final List<MaimemoNote> notes;
  const MaimemoWordLookup({
    required this.word,
    this.detail,
    required this.definitions,
    required this.examples,
    required this.notes,
  });
}

class MaimemoException implements Exception {
  final String message;
  const MaimemoException(this.message);
  @override
  String toString() => message;
}

/// 墨墨开放 API 封装（只读：学习数据 + 词汇查询）
class MaimemoService {
  static const String _base = 'https://open.maimemo.com/open';
  static final http.Client _client = http.Client();

  /// 请求墨墨接口（统一解析 { data, ... } 包装），支持 GET / POST
  static Future<Map<String, dynamic>> _send(
    String token,
    String path, {
    String method = 'POST',
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (token.trim().isEmpty) {
      throw const MaimemoException('尚未配置墨墨 API Token');
    }
    try {
      final uri = Uri.parse('$_base$path').replace(queryParameters: query);
      final headers = {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${token.trim()}',
        'Content-Type': 'application/json',
      };
      final resp = await (method == 'GET'
              ? _client.get(uri, headers: headers)
              : _client.post(uri, headers: headers, body: jsonEncode(body ?? {})))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const MaimemoException('墨墨 Token 无效或已过期，请检查后重试');
      }
      if (resp.statusCode == 429) {
        throw const MaimemoException('请求过于频繁，墨墨限制了访问频率，请稍后再试');
      }
      if (resp.statusCode != 200) {
        throw MaimemoException('墨墨接口返回 HTTP ${resp.statusCode}');
      }
      final obj = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final data = obj['data'];
      if (data is! Map<String, dynamic>) {
        throw MaimemoException('墨墨响应缺少 data 字段：${obj['msg'] ?? '未知错误'}');
      }
      return data;
    } on TimeoutException {
      throw const MaimemoException('连接墨墨服务器超时');
    } on FormatException {
      throw const MaimemoException('墨墨响应不是合法 JSON');
    } catch (e) {
      if (e is MaimemoException) rethrow;
      throw MaimemoException('墨墨请求失败：$e');
    }
  }

  /// POST JSON body 请求
  static Future<Map<String, dynamic>> _post(
      String token, String path, Map<String, dynamic> body) {
    return _send(token, path, body: body);
  }

  /// GET 请求（query 参数）
  static Future<Map<String, dynamic>> _get(
      String token, String path, Map<String, String> query) {
    return _send(token, path, method: 'GET', query: query);
  }

  /// 获取今日学习进度（公测）
  static Future<MaimemoProgress> getStudyProgress(String token) async {
    final data = await _post(token, '/api/v1/study/get_study_progress', {});
    final p = data['progress'] as Map<String, dynamic>? ?? {};
    return MaimemoProgress(
      finished: (p['finished'] as num?)?.toInt() ?? 0,
      total: (p['total'] as num?)?.toInt() ?? 0,
      studyTime: (p['study_time'] as num?)?.toInt() ?? 0,
    );
  }

  /// 获取今日学习单词列表（公测）
  /// [status]: all | unfinished | finished；[freshness]: all | new | review
  static Future<List<MaimemoTodayWord>> getTodayWords(
    String token, {
    String status = 'all',
    String freshness = 'all',
    int? limit,
  }) async {
    final body = <String, dynamic>{
      'is_finished': status == 'all' ? null : (status == 'finished'),
      'is_new': freshness == 'all' ? null : (freshness == 'new'),
      if (limit != null) 'limit': limit,
    }..removeWhere((k, v) => v == null);
    final data = await _post(token, '/api/v1/study/get_today_items', body);
    final list = data['today_items'] as List? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return MaimemoTodayWord(
        vocId: (m['voc_id'] ?? '') as String,
        spelling: (m['voc_spelling'] ?? '') as String,
        order: ((m['order'] ?? 0) as num).toInt(),
        firstResponse: m['first_response'] as String?,
        isNew: (m['is_new'] ?? false) as bool,
        isFinished: (m['is_finished'] ?? false) as bool,
      );
    }).toList();
  }

  /// 拉取今日全部学习单词（去重合并）。
  ///
  /// 墨墨接口无分页参数且单次 limit 上限为 1000。策略：
  /// 1. 先按全部状态拉一次；若返回数 < 上限，说明已拉全，直接返回；
  /// 2. 若达到上限（今日单词可能超过 1000），再按「已完成 / 未完成」
  ///    拆分两次拉取，按 vocId/spelling 去重合并，覆盖更多今日单词。
  static Future<List<MaimemoTodayWord>> fetchAllTodayWords(
    String token, {
    int pageSize = 1000,
  }) async {
    final all = <MaimemoTodayWord>[];
    final seen = <String>{};
    void merge(List<MaimemoTodayWord> words) {
      for (final w in words) {
        final key = w.vocId.isNotEmpty ? w.vocId : w.spelling.toLowerCase();
        if (seen.add(key)) all.add(w);
      }
    }

    var words = await getTodayWords(token, limit: pageSize);
    merge(words);
    if (words.length < pageSize) return all;

    words = await getTodayWords(token, status: 'finished', limit: pageSize);
    merge(words);
    words = await getTodayWords(token, status: 'unfinished', limit: pageSize);
    merge(words);
    return all;
  }

  /// 查询学习记录（公测），支持按下次复习日期筛选
  /// [start]/[end]: 'YYYY-MM-DD'
  static Future<List<MaimemoStudyRecord>> queryStudyRecords(
    String token, {
    String? start,
    String? end,
    int? limit,
  }) async {
    final body = <String, dynamic>{
      if (start != null || end != null)
        'next_study_date': {
          if (start != null) 'start': start,
          if (end != null) 'end': end,
        },
      if (limit != null) 'limit': limit,
    };
    final data = await _post(token, '/api/v1/study/query_study_records', body);
    final list = data['records'] as List? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return MaimemoStudyRecord(
        vocId: (m['voc_id'] ?? '') as String,
        spelling: (m['voc_spelling'] ?? '') as String,
        addDate: m['add_date'] as String?,
        firstStudyDate: m['first_study_date'] as String?,
        lastStudyDate: m['last_study_date'] as String?,
        nextStudyDate: m['next_study_date'] as String?,
        studyCount: ((m['study_count'] ?? 0) as num).toInt(),
      );
    }).toList();
  }

  /// 查询词汇（按拼写或 ID），返回 id + spelling 基本字段
  static Future<List<MaimemoVocabulary>> queryVocabulary(
    String token, {
    List<String>? spellings,
    List<String>? ids,
  }) async {
    if ((spellings == null || spellings.isEmpty) &&
        (ids == null || ids.isEmpty)) {
      return const [];
    }
    final body = <String, dynamic>{};
    if (spellings != null && spellings.isNotEmpty) body['spellings'] = spellings;
    if (ids != null && ids.isNotEmpty) body['ids'] = ids;
    final data = await _post(token, '/api/v1/vocabulary/query', body);
    final list = data['voc'] as List? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return MaimemoVocabulary(
        id: (m['id'] ?? '') as String,
        spelling: (m['spelling'] ?? '') as String,
      );
    }).toList();
  }

  /// 获取词汇详情：GET /api/v1/vocabulary?spelling=xxx（墨墨仅返回 id + spelling）
  static Future<MaimemoVocabularyDetail?> getVocabulary(
    String token, {
    required String spelling,
  }) async {
    final data = await _get(token, '/api/v1/vocabulary', {'spelling': spelling});
    final v = data['voc'];
    if (v is! Map<String, dynamic>) return null;
    return MaimemoVocabularyDetail(
      id: (v['id'] ?? '') as String,
      spelling: (v['spelling'] ?? '') as String,
    );
  }

  /// 查询指定单词下的所有释义：GET /api/v1/interpretations?voc_id=xxx
  static Future<List<MaimemoDefinition>> listDefinitions(
    String token, {
    required String vocId,
  }) async {
    final data = await _get(token, '/api/v1/interpretations', {'voc_id': vocId});
    final list = data['interpretations'] as List? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return MaimemoDefinition(
        id: (m['id'] ?? '') as String,
        content: (m['interpretation'] ?? m['content'] ?? '') as String,
        tags: (m['tags'] as List?)?.whereType<String>().toList() ?? const [],
      );
    }).toList();
  }

  /// 查询指定单词下的所有例句：GET /api/v1/phrases?voc_id=xxx
  static Future<List<MaimemoExample>> listExamples(
    String token, {
    required String vocId,
  }) async {
    final data = await _get(token, '/api/v1/phrases', {'voc_id': vocId});
    final list = data['phrases'] as List? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return MaimemoExample(
        id: (m['id'] ?? '') as String,
        content: (m['phrase'] ?? '') as String,
        translation: (m['interpretation'] ?? '') as String,
        source: (m['origin'] ?? '') as String,
      );
    }).toList();
  }

  /// 查询指定单词下的所有助记：GET /api/v1/notes?voc_id=xxx
  static Future<List<MaimemoNote>> listNotes(
    String token, {
    required String vocId,
  }) async {
    final data = await _get(token, '/api/v1/notes', {'voc_id': vocId});
    final list = data['notes'] as List? ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return MaimemoNote(
        id: (m['id'] ?? '') as String,
        content: (m['note'] ?? '') as String,
        type: (m['note_type'] ?? '') as String,
      );
    }).toList();
  }
}
