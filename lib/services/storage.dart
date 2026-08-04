/// 本地存储：基于 shared_preferences，替代网页版 localStorage
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models.dart';

class Storage {
  static SharedPreferences? _p;

  static Future<void> init() async {
    if (_p != null) return;
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      _p = null; // 容错：权限失败时用内存模式，应用仍可进入主界面
    }
  }

  static String _get(String key, String def) {
    try {
      return _p?.getString(key) ?? def;
    } catch (_) {
      return def;
    }
  }

  static void _set(String key, String v) {
    try {
      _p?.setString(key, v);
    } catch (_) {}
  }

  static bool _getBool(String key, bool def) {
    try {
      return _p?.getBool(key) ?? def;
    } catch (_) {
      return def;
    }
  }

  static void _setBool(String key, bool v) {
    try {
      _p?.setBool(key, v);
    } catch (_) {}
  }

  // ===== API 配置 =====
  static ApiConfig loadApiConfig() => ApiConfig(
        url: _get('apiUrl', ''),
        key: _get('apiKey', ''),
        model: _get('apiModel', 'gpt-5.1'),
        temperature: _get('apiTemp', 'default'),
      );

  static void saveApiConfig(ApiConfig c) {
    _set('apiUrl', c.url);
    _set('apiKey', c.key);
    _set('apiModel', c.model);
    _set('apiTemp', c.temperature);
  }

  static bool loadChatIndependent() => _getBool('chatApiIndependent', false);
  static void saveChatIndependent(bool v) => _setBool('chatApiIndependent', v);

  static ApiConfig loadChatConfig() => ApiConfig(
        url: _get('chatApiUrl', ''),
        key: _get('chatApiKey', ''),
        model: _get('chatApiModel', 'gpt-5.1'),
        temperature: _get('chatApiTemp', 'default'),
      );

  static void saveChatConfig(ApiConfig c) {
    _set('chatApiUrl', c.url);
    _set('chatApiKey', c.key);
    _set('chatApiModel', c.model);
    _set('chatApiTemp', c.temperature);
  }

  static bool loadChatShowReasoning() => _getBool('chatShowReasoning', false);
  static void saveChatShowReasoning(bool v) => _setBool('chatShowReasoning', v);

  static bool loadChatStream() => _getBool('chatStream', true);
  static void saveChatStream(bool v) => _setBool('chatStream', v);

  static bool loadDarkMode() => _getBool('theme_dark', false);
  static void saveDarkMode(bool v) => _setBool('theme_dark', v);

  static bool loadFullscreen() => _getBool('fullscreen', false);
  static void saveFullscreen(bool v) => _setBool('fullscreen', v);

  static bool loadPowerSavingMode() => _getBool('powerSavingMode', true);
  static void savePowerSavingMode(bool v) => _setBool('powerSavingMode', v);

  // ===== 界面模式 =====
  /// 'desktop' | 'mobile' | '' (未选择，首次启动)
  static String loadUiMode() => _get('uiMode', '');
  static void saveUiMode(String v) => _set('uiMode', v);

  // ===== 收藏 =====
  static List<Favorite> loadFavorites() {
    final s = _get('favorites', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => Favorite.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveFavorites(List<Favorite> list) {
    _set('favorites', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ===== 错题本 =====
  static List<WrongItem> loadWrongQuestions() {
    final s = _get('wrongQuestions', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => WrongItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveWrongQuestions(List<WrongItem> list) {
    _set('wrongQuestions', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ===== 学习记录 =====
  static List<StudyRecord> loadStudyRecords() {
    final s = _get('studyRecords', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => StudyRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveStudyRecords(List<StudyRecord> list) {
    _set('studyRecords', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ===== 生词本 =====
  static List<WordBookItem> loadWordBook() {
    final s = _get('wordbook', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => WordBookItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveWordBook(List<WordBookItem> list) {
    _set('wordbook', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ===== 答题记录（单词记录本） =====
  static Map<String, RecordedWord> loadRecordedWords() {
    final s = _get('recordedWords', '');
    if (s.isEmpty) return {};
    try {
      final obj = jsonDecode(s) as Map<String, dynamic>;
      final out = <String, RecordedWord>{};
      obj.forEach((k, v) => out[k] = RecordedWord.fromJson(v as Map<String, dynamic>));
      return out;
    } catch (_) {
      return {};
    }
  }

  static void saveRecordedWords(Map<String, RecordedWord> obj) {
    final out = <String, dynamic>{};
    obj.forEach((k, v) => out[k] = v.toJson());
    _set('recordedWords', jsonEncode(out));
  }

  static Set<String> loadRecordsSelected() {
    final s = _get('recordsSelected', '');
    if (s.isEmpty) return {};
    try {
      return (jsonDecode(s) as List).cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  static void saveRecordsSelected(Set<String> sel) {
    _set('recordsSelected', jsonEncode(sel.toList()));
  }

  // ===== 词汇分析缓存 =====
  static List<WordToken>? readAnalysisCache(String key) {
    final s = _get('wa_$key', '');
    if (s.isEmpty) return null;
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => WordToken.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  static void writeAnalysisCache(String key, List<WordToken> tokens) {
    _set('wa_$key', jsonEncode(tokens.map((e) => e.toJson()).toList()));
  }

  // ===== 备份 / 导入 =====
  static String buildBackupJson() {
    final data = {
      'apiUrl': _get('apiUrl', ''),
      'apiKey': _get('apiKey', ''),
      'apiModel': _get('apiModel', ''),
      'apiTemp': _get('apiTemp', ''),
      'uiMode': _get('uiMode', ''),
      'favorites': _get('favorites', ''),
      'wrongQuestions': _get('wrongQuestions', ''),
      'studyRecords': _get('studyRecords', ''),
      'wordbook': _get('wordbook', ''),
      'recordedWords': _get('recordedWords', ''),
      'recordsSelected': _get('recordsSelected', ''),
    };
    return jsonEncode(data);
  }

  /// 导入备份，返回是否成功
  static bool importBackup(String content) {
    try {
      final data = jsonDecode(content) as Map<String, dynamic>;
      if (data.containsKey('apiUrl')) _set('apiUrl', data['apiUrl'] as String);
      if (data.containsKey('apiKey')) _set('apiKey', data['apiKey'] as String);
      if (data.containsKey('apiModel')) _set('apiModel', data['apiModel'] as String);
      if (data.containsKey('apiTemp')) _set('apiTemp', data['apiTemp'] as String);
      if (data.containsKey('uiMode')) _set('uiMode', data['uiMode'] as String);
      if (data.containsKey('favorites')) _set('favorites', data['favorites'] as String);
      if (data.containsKey('wrongQuestions')) _set('wrongQuestions', data['wrongQuestions'] as String);
      if (data.containsKey('studyRecords')) _set('studyRecords', data['studyRecords'] as String);
      if (data.containsKey('wordbook')) _set('wordbook', data['wordbook'] as String);
      if (data.containsKey('recordedWords')) _set('recordedWords', data['recordedWords'] as String);
      if (data.containsKey('recordsSelected')) _set('recordsSelected', data['recordsSelected'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 清空记录相关数据（导入覆盖前确认用）
  static void clearUserData() {
    _set('favorites', '');
    _set('wrongQuestions', '');
    _set('studyRecords', '');
    _set('wordbook', '');
    _set('recordedWords', '');
    _set('recordsSelected', '');
  }
}
