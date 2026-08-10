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
        fullUrl: _getBool('apiFullUrl', false),
      );

  static void saveApiConfig(ApiConfig c) {
    _set('apiUrl', c.url);
    _set('apiKey', c.key);
    _set('apiModel', c.model);
    _set('apiTemp', c.temperature);
    _setBool('apiFullUrl', c.fullUrl);
  }

  static bool loadChatIndependent() => _getBool('chatApiIndependent', false);
  static void saveChatIndependent(bool v) => _setBool('chatApiIndependent', v);

  static ApiConfig loadChatConfig() => ApiConfig(
        url: _get('chatApiUrl', ''),
        key: _get('chatApiKey', ''),
        model: _get('chatApiModel', 'gpt-5.1'),
        temperature: _get('chatApiTemp', 'default'),
        fullUrl: _getBool('chatApiFullUrl', false),
      );

  static void saveChatConfig(ApiConfig c) {
    _set('chatApiUrl', c.url);
    _set('chatApiKey', c.key);
    _set('chatApiModel', c.model);
    _set('chatApiTemp', c.temperature);
    _setBool('chatApiFullUrl', c.fullUrl);
  }

  static bool loadChatShowReasoning() => _getBool('chatShowReasoning', false);
  static void saveChatShowReasoning(bool v) => _setBool('chatShowReasoning', v);

  static bool loadChatStream() => _getBool('chatStream', true);
  static void saveChatStream(bool v) => _setBool('chatStream', v);

  // ===== 多配置记忆（配置库） =====
  static List<ApiProfile> loadApiProfiles() {
    final s = _get('apiProfiles', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => ApiProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveApiProfiles(List<ApiProfile> list) {
    _set('apiProfiles', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static List<ApiProfile> loadChatProfiles() {
    final s = _get('chatProfiles', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => ApiProfile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveChatProfiles(List<ApiProfile> list) {
    _set('chatProfiles', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  static int loadChatProfileIdx() {
    try {
      return _p?.getInt('chatProfileIdx') ?? -1;
    } catch (_) {
      return -1;
    }
  }

  static void saveChatProfileIdx(int v) {
    try {
      _p?.setInt('chatProfileIdx', v);
    } catch (_) {}
  }

  static bool loadDarkMode() => _getBool('theme_dark', false);
  static void saveDarkMode(bool v) => _setBool('theme_dark', v);

  // ===== 首次启动引导 =====
  static bool loadOnboardingDone() => _getBool('onboardingDone', false);
  static void saveOnboardingDone(bool v) => _setBool('onboardingDone', v);

  static String loadAnalysisMode() => _get('analysisMode', 'normal');
  static void saveAnalysisMode(String v) => _set('analysisMode', v);

  static bool loadFullscreen() => _getBool('fullscreen', false);
  static void saveFullscreen(bool v) => _setBool('fullscreen', v);

  static bool loadPowerSavingMode() => _getBool('powerSavingMode', false);
  static void savePowerSavingMode(bool v) => _setBool('powerSavingMode', v);

  // ===== 界面模式 =====
  /// 'desktop' | 'mobile' | '' (未选择，首次启动)
  static String loadUiMode() => _get('uiMode', '');
  static void saveUiMode(String v) => _set('uiMode', v);

  // ===== 应用模式 =====
  /// 'english' = 英语学习模式（现有） | 'tools' = 工具模式（复刻参考项目）
  /// '' = 未选择（新手引导中让用户选择）
  static String loadAppMode() => _get('appMode', '');
  static void saveAppMode(String v) => _set('appMode', v);

  // ===== UI 风格 =====
  /// 'classic' | 'glass'
  static String loadUiStyle() => _get('uiStyle', 'classic');
  static void saveUiStyle(String v) => _set('uiStyle', v);

  // ===== 导航指示器 =====
  /// 'underline' = 灰色下划线 | 'pill' = 紫色渐变胶囊
  static String loadNavIndicator() => _get('navIndicator', 'underline');
  static void saveNavIndicator(String v) => _set('navIndicator', v);

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

  // ===== 题库已作答索引 =====
  static Set<int> loadAnsweredBankIndices() {
    final s = _get('answeredBankIdx', '');
    if (s.isEmpty) return <int>{};
    try {
      final list = jsonDecode(s) as List;
      return Set<int>.from(list.whereType<int>());
    } catch (_) {
      return <int>{};
    }
  }

  static void saveAnsweredBankIndices(Set<int> set) {
    _set('answeredBankIdx', jsonEncode(set.toList()));
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

  // ===== 全卷模拟考试（最近一次试卷 + 成绩 + 历史摘要） =====
  /// 最近一次交卷的试卷（供成绩页/复盘回看）
  static FullExamPaper? loadLastExamPaper() {
    final s = _get('examLastPaper', '');
    if (s.isEmpty) return null;
    try {
      return FullExamPaper.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static void saveLastExamPaper(FullExamPaper p) {
    _set('examLastPaper', jsonEncode(p.toJson()));
  }

  /// 最近一次交卷成绩（含试卷与答题卡快照）
  static ExamResult? loadLastExamResult() {
    final s = _get('examLastResult', '');
    if (s.isEmpty) return null;
    try {
      return ExamResult.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static void saveLastExamResult(ExamResult r) {
    _set('examLastResult', jsonEncode(r.toJson()));
  }

  /// 考试成绩历史摘要（最多 10 条，新→旧）
  static List<ExamHistoryEntry> loadExamHistory() {
    final s = _get('examHistory', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => ExamHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveExamHistory(List<ExamHistoryEntry> list) {
    _set('examHistory', jsonEncode(list.map((e) => e.toJson()).toList()));
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

  // ===== 语法学习进度 =====
  static Map<String, GrammarProgress> loadGrammarProgress() {
    final s = _get('grammarProgress', '');
    if (s.isEmpty) return {};
    try {
      final obj = jsonDecode(s) as Map<String, dynamic>;
      final out = <String, GrammarProgress>{};
      obj.forEach((k, v) => out[k] = GrammarProgress.fromJson(v as Map<String, dynamic>));
      return out;
    } catch (_) {
      return {};
    }
  }

  static void saveGrammarProgress(Map<String, GrammarProgress> obj) {
    final out = <String, dynamic>{};
    obj.forEach((k, v) => out[k] = v.toJson());
    _set('grammarProgress', jsonEncode(out));
  }

  // ===== 备份 / 导入 =====
  static String buildBackupJson() {
    final data = {
      'apiUrl': _get('apiUrl', ''),
      'apiKey': _get('apiKey', ''),
      'apiModel': _get('apiModel', ''),
      'apiTemp': _get('apiTemp', ''),
      'apiFullUrl': _getBool('apiFullUrl', false),
      'uiMode': _get('uiMode', ''),
      'themeId': _get('themeId', ''),
      'lastLightTheme': _get('lastLightTheme', ''),
      'onboardingDone': _getBool('onboardingDone', false) ? 'true' : 'false',
      'favorites': _get('favorites', ''),
      'wrongQuestions': _get('wrongQuestions', ''),
      'studyRecords': _get('studyRecords', ''),
      'wordbook': _get('wordbook', ''),
      'recordedWords': _get('recordedWords', ''),
      'recordsSelected': _get('recordsSelected', ''),
      'examLastPaper': _get('examLastPaper', ''),
      'examLastResult': _get('examLastResult', ''),
      'examHistory': _get('examHistory', ''),
      'grammarProgress': _get('grammarProgress', ''),
      'answeredBankIdx': _get('answeredBankIdx', ''),
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
      if (data.containsKey('apiFullUrl')) _setBool('apiFullUrl', data['apiFullUrl'] as bool);
      if (data.containsKey('uiMode')) _set('uiMode', data['uiMode'] as String);
      if (data.containsKey('themeId')) _set('themeId', data['themeId'] as String);
      if (data.containsKey('lastLightTheme')) _set('lastLightTheme', data['lastLightTheme'] as String);
      if (data.containsKey('onboardingDone')) _setBool('onboardingDone', data['onboardingDone'] == 'true');
      if (data.containsKey('favorites')) _set('favorites', data['favorites'] as String);
      if (data.containsKey('wrongQuestions')) _set('wrongQuestions', data['wrongQuestions'] as String);
      if (data.containsKey('studyRecords')) _set('studyRecords', data['studyRecords'] as String);
      if (data.containsKey('wordbook')) _set('wordbook', data['wordbook'] as String);
      if (data.containsKey('recordedWords')) _set('recordedWords', data['recordedWords'] as String);
      if (data.containsKey('recordsSelected')) _set('recordsSelected', data['recordsSelected'] as String);
      if (data.containsKey('examLastPaper')) _set('examLastPaper', data['examLastPaper'] as String);
      if (data.containsKey('examLastResult')) _set('examLastResult', data['examLastResult'] as String);
      if (data.containsKey('examHistory')) _set('examHistory', data['examHistory'] as String);
      if (data.containsKey('grammarProgress')) _set('grammarProgress', data['grammarProgress'] as String);
      if (data.containsKey('answeredBankIdx')) _set('answeredBankIdx', data['answeredBankIdx'] as String);
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
    _set('examLastPaper', '');
    _set('examLastResult', '');
    _set('examHistory', '');
    _set('grammarProgress', '');
    _set('answeredBankIdx', '');
  }
}
