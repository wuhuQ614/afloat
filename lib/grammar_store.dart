/// 语法学习状态：课程加载、视图切换、随堂练习会话、进度持久化、AI 扩题
/// 独立于 AppState（单例），页面通过 ListenableBuilder 订阅
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'models.dart';
import 'services/api_service.dart';
import 'services/storage.dart';

/// 语法学习视图
enum GrammarView { overview, learn, quiz }

class GrammarStore extends ChangeNotifier {
  GrammarStore._();
  static final GrammarStore instance = GrammarStore._();

  // ===== 课程数据（懒加载） =====
  List<GrammarLevel> _levels = [];
  bool _courseLoading = false;
  String _courseError = '';
  Future<void>? _courseFuture;

  List<GrammarLevel> get levels => _levels;
  bool get courseLoading => _courseLoading;
  String get courseError => _courseError;

  int get totalTopicCount => _levels.fold(0, (s, l) => s + l.topics.length);
  int get learnedTopicCount =>
      _levels.fold(0, (s, l) => s + l.topics.where((t) => progressOf(t.id).learned).length);

  /// 全部知识点（按层级顺序展平）
  List<GrammarTopic> get allTopics =>
      _levels.expand((l) => l.topics).toList();

  /// 幂等懒加载课程 JSON（仿 DictService.loadZsbDict 模式）
  Future<void> ensureCourse() => _courseFuture ??= _loadCourse();

  Future<void> _loadCourse() async {
    _courseLoading = true;
    _courseError = '';
    notifyListeners();
    try {
      final raw = await rootBundle.loadString('assets/grammar_course.json');
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      final list = (obj['levels'] as List?) ?? [];
      _levels = list
          .whereType<Map<String, dynamic>>()
          .map(GrammarLevel.fromJson)
          .toList();
    } catch (_) {
      _levels = [];
      _courseError = '课程数据加载失败，请确认 assets/grammar_course.json 已注册';
      _courseFuture = null; // 失败后允许重试
    } finally {
      _courseLoading = false;
      notifyListeners();
    }
  }

  // ===== 视图状态 =====
  GrammarView view = GrammarView.overview;
  GrammarTopic? currentTopic;

  void openTopic(GrammarTopic topic) {
    currentTopic = topic;
    view = GrammarView.learn;
    notifyListeners();
  }

  void backToOverview() {
    view = GrammarView.overview;
    currentTopic = null;
    _clearSession();
    notifyListeners();
  }

  /// 学习页/练习页返回上一级
  void goBack() {
    if (view == GrammarView.quiz) {
      view = GrammarView.learn;
      _clearSession();
    } else {
      view = GrammarView.overview;
      currentTopic = null;
      _clearSession();
    }
    notifyListeners();
  }

  // ===== 练习会话 =====
  List<GrammarQuiz> sessionQuiz = [];
  int sessionIndex = 0;
  /// 每题作答的选项索引（null 表示未作答）
  List<int?> sessionPicks = [];
  List<bool> sessionResults = [];
  bool sessionFinished = false;
  bool aiLoading = false;
  String aiMessage = '';

  int get sessionCorrectCount => sessionResults.where((r) => r).length;

  int get sessionScorePct =>
      sessionQuiz.isEmpty ? 0 : (sessionCorrectCount * 100 / sessionQuiz.length).round();

  List<int> get wrongIndexes => [
        for (var i = 0; i < sessionResults.length; i++)
          if (!sessionResults[i]) i,
      ];

  void _clearSession() {
    sessionQuiz = [];
    sessionIndex = 0;
    sessionPicks = [];
    sessionResults = [];
    sessionFinished = false;
    aiLoading = false;
    aiMessage = '';
  }

  /// 开始练习（默认使用知识点的静态随堂题）
  void startPractice(GrammarTopic topic, {List<GrammarQuiz>? quizzes}) {
    currentTopic = topic;
    sessionQuiz = (quizzes ?? topic.quiz)
        .where((q) => q.question.isNotEmpty && q.options.length >= 4)
        .toList();
    sessionIndex = 0;
    sessionPicks = List<int?>.filled(sessionQuiz.length, null);
    sessionResults = List<bool>.filled(sessionQuiz.length, false);
    sessionFinished = sessionQuiz.isEmpty;
    aiLoading = false;
    aiMessage = '';
    view = GrammarView.quiz;
    notifyListeners();
  }

  /// 作答当前题（已作答则忽略），返回是否答对
  bool answerOption(int idx) {
    if (sessionFinished ||
        sessionIndex < 0 ||
        sessionIndex >= sessionQuiz.length) {
      return false;
    }
    if (sessionPicks[sessionIndex] != null) return sessionResults[sessionIndex];
    final correct = idx == sessionQuiz[sessionIndex].answerIdx;
    sessionPicks[sessionIndex] = idx;
    sessionResults[sessionIndex] = correct;
    notifyListeners();
    return correct;
  }

  /// 下一题 / 结束
  void nextQuestion() {
    if (sessionFinished) return;
    if (sessionPicks[sessionIndex] == null) return;
    if (sessionIndex + 1 < sessionQuiz.length) {
      sessionIndex++;
    } else {
      sessionFinished = true;
      _commitProgress();
    }
    notifyListeners();
  }

  /// 错题重练：仅用本轮答错的题重新开会话
  void retryWrong() {
    final topic = currentTopic;
    if (topic == null) return;
    final wrong = wrongIndexes.map((i) => sessionQuiz[i]).toList();
    if (wrong.isEmpty) return;
    startPractice(topic, quizzes: wrong);
  }

  // ===== 进度 =====
  Map<String, GrammarProgress> _progress = {};
  bool _progressLoaded = false;

  void _ensureProgress() {
    if (_progressLoaded) return;
    _progressLoaded = true;
    _progress = Storage.loadGrammarProgress();
  }

  GrammarProgress progressOf(String topicId) {
    _ensureProgress();
    return _progress[topicId] ?? GrammarProgress();
  }

  /// 完成一轮练习后写入进度（learned=true、best 取最高、attempts+1）
  void _commitProgress() {
    final topic = currentTopic;
    if (topic == null || sessionQuiz.isEmpty) return;
    _ensureProgress();
    final p = _progress[topic.id] ?? GrammarProgress();
    p.learned = true;
    p.attempts += 1;
    if (sessionScorePct > p.best) p.best = sessionScorePct;
    _progress[topic.id] = p;
    Storage.saveGrammarProgress(_progress);
  }

  // ===== AI 扩展出题 =====
  /// 请求 AI 为当前知识点追加 5 道新题。
  /// 成功返回 true（题目已追加到当前会话）；失败时给出友好提示并保留静态题，不影响主流程。
  Future<bool> requestAiQuiz() async {
    final topic = currentTopic;
    if (topic == null || aiLoading) return false;
    aiLoading = true;
    aiMessage = '';
    notifyListeners();
    try {
      // 优先全局 API 配置，未配置时回退对话助手配置（只读 Storage，不依赖 AppState）
      var cfg = Storage.loadApiConfig();
      if (!cfg.ready) cfg = Storage.loadChatConfig();
      if (!cfg.ready) {
        aiMessage = '未配置 AI 接口，可在设置中填写 API 后再试，当前可继续练习内置题';
        return false;
      }
      final systemPrompt =
          '你是四川专升本英语语法命题专家。请围绕四川专升本考纲第 ${topic.syllabusRef.join('、')} 项语法"${topic.name}"出 5 道四选一单选题。'
          '要求：1. 词汇不超出专升本 3500 词范围；2. 每题只有一个正确答案，干扰项合理；3. 解析简明扼要，用中文；'
          '4. 严格返回 JSON 数组 [{"question":"题干","options":["选项1","选项2","选项3","选项4"],"answer":"A或B或C或D","analysis":"解析"}]，'
          '不要 markdown 围栏，不要输出任何其他文字。';
      final r = await ApiService.callAIResult(
        [
          {'role': 'user', 'content': '请出 5 道题。'}
        ],
        systemPrompt,
        config: cfg,
        extraParams: ApiService.noThinkingParams(cfg.model),
      );
      final content = r.content;
      if (content == null) {
        // 透传请求层失败原因（如超时、连接被拦截、HTTP 错误码），便于移动端排查
        final detail = ApiService.lastError;
        aiMessage = detail != null
            ? 'AI 请求失败（$detail），可稍后重试，当前可继续练习内置题'
            : 'AI 请求失败，请稍后重试，当前可继续练习内置题';
        return false;
      }
      final arr = ApiService.extractJsonArray(content);
      if (arr == null || arr.isEmpty) {
        aiMessage = 'AI 返回格式异常，已保留内置题目，可稍后再试';
        return false;
      }
      final fresh = <GrammarQuiz>[];
      for (final j in arr) {
        final q = GrammarQuiz.fromJson(j);
        if (q.question.isEmpty || q.options.length < 4) continue;
        fresh.add(q);
      }
      if (fresh.isEmpty) {
        aiMessage = 'AI 未返回有效题目，已保留内置题目';
        return false;
      }
      // 追加到当前会话（成绩卡之后续答新题）
      sessionQuiz.addAll(fresh);
      sessionPicks.addAll(List<int?>.filled(fresh.length, null));
      sessionResults.addAll(List<bool>.filled(fresh.length, false));
      sessionIndex = sessionQuiz.length - fresh.length;
      sessionFinished = false;
      aiMessage = 'AI 已追加 ${fresh.length} 道新题';
      return true;
    } catch (_) {
      aiMessage = 'AI 出题出错，已保留内置题目';
      return false;
    } finally {
      aiLoading = false;
      notifyListeners();
    }
  }
}
