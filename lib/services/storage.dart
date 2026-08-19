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

  static int _getInt(String key, int def) {
    try {
      return _p?.getInt(key) ?? def;
    } catch (_) {
      return def;
    }
  }

  static void _setInt(String key, int v) {
    try {
      _p?.setInt(key, v);
    } catch (_) {}
  }

  // ===== API 配置 =====
  static ApiConfig loadApiConfig() => ApiConfig(
        url: _get('apiUrl', ''),
        key: _get('apiKey', ''),
        model: _get('apiModel', 'gpt-5.1'),
        temperature: _get('apiTemp', 'default'),
        fullUrl: _getBool('apiFullUrl', false),
        questionMode: _get('apiQuestionMode', 'auto'),
        questionSpeed: _get('apiQuestionSpeed', 'fast'),
      );

  static void saveApiConfig(ApiConfig c) {
    _set('apiUrl', c.url);
    _set('apiKey', c.key);
    _set('apiModel', c.model);
    _set('apiTemp', c.temperature);
    _setBool('apiFullUrl', c.fullUrl);
    _set('apiQuestionMode', c.questionMode);
    _set('apiQuestionSpeed', c.questionSpeed);
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

  static bool loadChatThinking() => _getBool('chatThinking', true);
  static void saveChatThinking(bool v) => _setBool('chatThinking', v);

  // ===== 开发者模式（显示 AI 出题思维链与输出文本） =====
  static bool loadDevMode() => _getBool('devMode', false);
  static void saveDevMode(bool v) => _setBool('devMode', v);

  // ===== 联网搜索服务（百度千帆 AI 搜索组件） =====
  static String loadSearchUrl() => _get('searchUrl', 'https://qianfan.baidubce.com/v2/ai_search/chat/completions');
  static void saveSearchUrl(String v) => _set('searchUrl', v);
  static String loadSearchKey() => _get('searchKey', '');
  static void saveSearchKey(String v) => _set('searchKey', v);

  // ===== 墨墨背单词同步 =====
  static String loadMaimemoToken() => _get('maimemoToken', '');
  static void saveMaimemoToken(String v) => _set('maimemoToken', v);
  static int loadMaimemoLastSync() => _getInt('maimemoLastSync', 0);
  static void saveMaimemoLastSync(int v) => _setInt('maimemoLastSync', v);
  static int loadMaimemoSyncedCount() => _getInt('maimemoSyncedCount', 0);
  static void saveMaimemoSyncedCount(int v) => _setInt('maimemoSyncedCount', v);

  // ===== 贪吃蛇游戏最高分 =====
  static int loadSnakeHighScore() => _getInt('snakeHighScore', 0);
  static void saveSnakeHighScore(int v) => _setInt('snakeHighScore', v);

  // ===== 墨墨词库 =====
  static List<WordBookItem> loadMaimemoWordbook() {
    final s = _get('maimemoWordbook', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => WordBookItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveMaimemoWordbook(List<WordBookItem> list) {
    _set('maimemoWordbook', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

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

  // ===== 高性能模式 =====
  /// 低配设备性能优化：关闭毛玻璃等重特效、锁 60 帧，功能不变
  static bool loadHighPerformanceMode() => _getBool('highPerformanceMode', false);
  static void saveHighPerformanceMode(bool v) => _setBool('highPerformanceMode', v);

  // ===== 界面模式 =====
  /// 'desktop' | 'mobile' | '' (未选择，首次启动)
  static String loadUiMode() => _get('uiMode', '');
  static void saveUiMode(String v) => _set('uiMode', v);

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

  // ===== 自定义词库（默写用，用户手动创建） =====
  static List<WordBookItem> loadCustomWordbook() {
    final s = _get('customWordbook', '');
    if (s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list.map((e) => WordBookItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static void saveCustomWordbook(List<WordBookItem> list) {
    _set('customWordbook', jsonEncode(list.map((e) => e.toJson()).toList()));
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
      // 聊天独立 API 配置
      'chatApiIndependent': _getBool('chatApiIndependent', false),
      'chatApiUrl': _get('chatApiUrl', ''),
      'chatApiKey': _get('chatApiKey', ''),
      'chatApiModel': _get('chatApiModel', ''),
      'chatApiTemp': _get('chatApiTemp', ''),
      'chatApiFullUrl': _getBool('chatApiFullUrl', false),
      'chatShowReasoning': _getBool('chatShowReasoning', false),
      'chatStream': _getBool('chatStream', true),
      'chatThinking': _getBool('chatThinking', true),
      // 开发者模式
      'devMode': _getBool('devMode', false),
      // 联网搜索服务
      'searchUrl': _get('searchUrl', ''),
      'searchKey': _get('searchKey', ''),
      // 墨墨词库
      'maimemoToken': _get('maimemoToken', ''),
      'maimemoWordbook': _get('maimemoWordbook', ''),
      // API 配置档
      'apiProfiles': _get('apiProfiles', ''),
      'chatProfiles': _get('chatProfiles', ''),
      // 界面与模式
      'theme_dark': _getBool('theme_dark', false),
      'analysisMode': _get('analysisMode', 'normal'),
      'fullscreen': _getBool('fullscreen', false),
      'powerSavingMode': _getBool('powerSavingMode', false),
      'highPerformanceMode': _getBool('highPerformanceMode', false),
      'uiStyle': _get('uiStyle', 'classic'),
      'navIndicator': _get('navIndicator', 'underline'),
      // 自定义词库
      'customWordbook': _get('customWordbook', ''),
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
      // 聊天独立 API 配置
      if (data.containsKey('chatApiIndependent')) _setBool('chatApiIndependent', data['chatApiIndependent'] as bool);
      if (data.containsKey('chatApiUrl')) _set('chatApiUrl', data['chatApiUrl'] as String);
      if (data.containsKey('chatApiKey')) _set('chatApiKey', data['chatApiKey'] as String);
      if (data.containsKey('chatApiModel')) _set('chatApiModel', data['chatApiModel'] as String);
      if (data.containsKey('chatApiTemp')) _set('chatApiTemp', data['chatApiTemp'] as String);
      if (data.containsKey('chatApiFullUrl')) _setBool('chatApiFullUrl', data['chatApiFullUrl'] as bool);
      if (data.containsKey('chatShowReasoning')) _setBool('chatShowReasoning', data['chatShowReasoning'] as bool);
      if (data.containsKey('chatStream')) _setBool('chatStream', data['chatStream'] as bool);
      if (data.containsKey('chatThinking')) _setBool('chatThinking', data['chatThinking'] as bool);
      // 开发者模式
      if (data.containsKey('devMode')) _setBool('devMode', data['devMode'] as bool);
      // 联网搜索服务
      if (data.containsKey('searchUrl')) _set('searchUrl', data['searchUrl'] as String);
      if (data.containsKey('searchKey')) _set('searchKey', data['searchKey'] as String);
      // 墨墨词库
      if (data.containsKey('maimemoToken')) _set('maimemoToken', data['maimemoToken'] as String);
      if (data.containsKey('maimemoWordbook')) _set('maimemoWordbook', data['maimemoWordbook'] as String);
      // API 配置档
      if (data.containsKey('apiProfiles')) _set('apiProfiles', data['apiProfiles'] as String);
      if (data.containsKey('chatProfiles')) _set('chatProfiles', data['chatProfiles'] as String);
      // 界面与模式
      if (data.containsKey('theme_dark')) _setBool('theme_dark', data['theme_dark'] as bool);
      if (data.containsKey('analysisMode')) _set('analysisMode', data['analysisMode'] as String);
      if (data.containsKey('fullscreen')) _setBool('fullscreen', data['fullscreen'] as bool);
      if (data.containsKey('powerSavingMode')) _setBool('powerSavingMode', data['powerSavingMode'] as bool);
      if (data.containsKey('highPerformanceMode')) _setBool('highPerformanceMode', data['highPerformanceMode'] as bool);
      if (data.containsKey('uiStyle')) _set('uiStyle', data['uiStyle'] as String);
      if (data.containsKey('navIndicator')) _set('navIndicator', data['navIndicator'] as String);
      // 自定义词库
      if (data.containsKey('customWordbook')) _set('customWordbook', data['customWordbook'] as String);
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
