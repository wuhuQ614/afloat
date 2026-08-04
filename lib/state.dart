/// 全局状态与核心业务逻辑（对应网页版 index.html 中的 state 与各函数）
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'models.dart';
import 'services/api_service.dart';
import 'services/storage.dart';
import 'services/dict_service.dart';

class ChatMessage {
  String role; // user / ai
  String content;
  bool showReasoning;
  String? reasoning;

  ChatMessage({required this.role, required this.content, this.showReasoning = false, this.reasoning});
}

/// 全局状态 InheritedWidget，提供 AppState 给子树
class AppScope extends InheritedWidget {
  final AppState state;
  const AppScope({super.key, required this.state, required super.child});

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in context');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => state != oldWidget.state;
}

class AppState extends ChangeNotifier {
  // ===== 基础状态 =====
  String direction = 'zh2en';
  List<ChatMessage> chatHistory = [];
  List<Question> generatedQuestions = [];
  int generatedQuestionIdx = 0;
  Question currentQuestion = Question();
  List<Question> questions = []; // 题库
  ApiConfig apiConfig = ApiConfig();
  bool chatApiIndependent = false;
  ApiConfig chatApiConfig = ApiConfig();
  bool chatShowReasoning = false;
  bool chatStream = true;
  bool darkMode = false;
  bool fullscreen = false;
  bool powerSavingMode = true; // 省电模式，默认开启，锁60帧
  /// '' = 未选择（首次启动）, 'desktop' = 桌面端, 'mobile' = 手机端
  String uiMode = '';
  String selectedType = 'translation';
  String selectedLevel = 'zsb';
  int questionStartTime = 0;

  // 词汇剖析状态
  bool analysisLoading = false;
  List<WordToken> analysisTokens = [];

  // 默写状态
  List<WordToken> dictationQueue = [];
  int dictationIdx = 0;
  String dictationMode = 'zh2en';
  int dictationTotal = 0;
  int dictationCorrect = 0;

  // ===== 初始化 =====
  Future<void> init() async {
    await Storage.init();
    apiConfig = Storage.loadApiConfig();
    chatApiIndependent = Storage.loadChatIndependent();
    chatApiConfig = Storage.loadChatConfig();
    chatShowReasoning = Storage.loadChatShowReasoning();
    chatStream = Storage.loadChatStream();
    darkMode = Storage.loadDarkMode();
    fullscreen = Storage.loadFullscreen();
    powerSavingMode = Storage.loadPowerSavingMode();
    uiMode = Storage.loadUiMode();
    // 加载题库
    try {
      final raw = await rootBundle.loadString('assets/questions.json');
      final list = jsonDecode(raw) as List;
      questions = List.generate(list.length, (i) {
        final q = Question.fromBank(list[i] as Map<String, dynamic>, i);
        return q;
      });
    } catch (_) {
      questions = [];
    }
    if (questions.isNotEmpty) {
      loadQuestionFromBank(0);
    } else {
      currentQuestion = Question(
        type: QType.translation,
        level: 'medium',
        chinese: '人工智能正在改变我们的学习方式和生活方式。',
        english: 'Artificial intelligence is changing the way we learn and live.',
        text: '人工智能正在改变我们的学习方式和生活方式。',
        correctAnswer: 'Artificial intelligence is changing the way we learn and live.',
      );
    }
    questionStartTime = DateTime.now().millisecondsSinceEpoch;
    // 延迟加载词库，不阻塞启动
    DictService.loadExternalDict();
    DictService.loadZsbDict();
    notifyListeners();
  }

  ApiConfig get effectiveChatConfig => chatApiIndependent ? chatApiConfig : apiConfig;

  // ===== 当前题目展示 =====
  bool get isZh2En => direction == 'zh2en';

  String get directionLabel {
    switch (currentQuestion.type) {
      case QType.translation:
        return isZh2En ? '将下列中文翻译成英文。' : '将下列英文翻译成中文。';
      case QType.choice:
        return '请从下列选项中选择正确的答案。';
      case QType.reading:
        return '阅读下面的短文，回答后面的问题。';
      case QType.writing:
        return '请根据题目要求完成写作。';
      case QType.dictation:
        return '';
      case QType.grammar:
        return '请根据语境填入合适的单词或词组。';
    }
  }

  String get answerPlaceholder {
    switch (currentQuestion.type) {
      case QType.translation:
        return isZh2En ? '在此输入你的英文翻译...' : '在此输入你的中文翻译...';
      case QType.writing:
        return '在此输入你的英文写作...';
      case QType.dictation:
        return '';
      case QType.grammar:
        return '在此输入你的答案...';
      default:
        return '';
    }
  }

  bool get showDirectionSwitcher => currentQuestion.type == QType.translation;

  /// 应用方向（仅翻译题切换中英文）
  void applyDirection() {
    if (currentQuestion.type == QType.translation) {
      if (currentQuestion.chinese.isNotEmpty && currentQuestion.english.isNotEmpty) {
        currentQuestion = currentQuestion.copyWith(
          text: isZh2En ? currentQuestion.chinese : currentQuestion.english,
          correctAnswer: isZh2En ? currentQuestion.english : currentQuestion.chinese,
        );
      } else {
        final t = isZh2En ? currentQuestion.chinese : currentQuestion.english;
        if (t.isNotEmpty) {
          currentQuestion = currentQuestion.copyWith(text: t);
        }
      }
    }
    notifyListeners();
  }

  void setDirection(String d) {
    direction = d;
    questionStartTime = DateTime.now().millisecondsSinceEpoch;
    applyDirection();
  }

  // ===== 题库 =====
  void loadQuestionFromBank(int idx) {
    if (idx < 0 || idx >= questions.length) return;
    final q = questions[idx];
    direction = 'zh2en';
    currentQuestion = q.copyWith(userAnswerIdx: null, userAnswers: []);
    questionStartTime = DateTime.now().millisecondsSinceEpoch;
    applyDirection();
    notifyListeners();
  }

  void loadQuestion(Question q) {
    currentQuestion = q.copyWith(userAnswerIdx: null, userAnswers: []);
    questionStartTime = DateTime.now().millisecondsSinceEpoch;
    applyDirection();
    notifyListeners();
  }

  void nextQuestion() {
    if (generatedQuestions.length > 1) {
      generatedQuestionIdx = (generatedQuestionIdx + 1) % generatedQuestions.length;
      loadGeneratedQuestion();
    } else if (questions.isNotEmpty) {
      loadQuestionFromBank(Random().nextInt(questions.length));
    }
  }

  // ===== 生成题目 =====
  bool generating = false;

  Future<bool> generateQuestions({required int count, required String customReq, int wordCount = 80}) async {
    generating = true;
    notifyListeners();
    final levelNames = {
      'cet4': '大学英语四级（CET-4）',
      'zsb': '专升本英语',
      'easy': '简单',
      'medium': '中等',
      'hard': '困难',
    };
    final levelGuides = {
      'cet4': '要求：词汇范围以四级大纲为准（约4500词），句式多样，涉及校园生活、社会热点、科普常识、日常交际等话题。翻译题长度约 100-150 字（中文）或 80-120 词（英文），难度对标四级翻译真题。',
      'zsb': '要求：词汇范围以专升本大纲为准（约3500-4000词），侧重基础语法和常见句型，话题贴近日常生活、学习、工作、社会现象。翻译题长度约 80-120 字（中文）或 60-100 词（英文），难度对标各省专升本英语真题。',
      'easy': '要求：使用基础词汇和简单句式，适合初学者。',
      'medium': '要求：使用中等难度词汇和复合句式，适合有一定基础的学习者。',
      'hard': '要求：使用高级词汇和复杂句式，适合挑战高难度的学习者。',
    };
    final dirDesc = isZh2En ? '中译英（题目为中文，答案为英文）' : '英译中（题目为英文，答案为中文）';
    var vocabHint = '';
    if (selectedLevel == 'zsb' && DictService.zsbReady) {
      final allWords = DictService.zsbWords();
      if (allWords.length >= 20) {
        // 根据用户设置的单词量决定每题从词库抽取的单词数
        final wordsPerQuestion = wordCount;
        final used = <String>{};
        String pickUnique() {
          if (used.length >= allWords.length) {
            return allWords[Random().nextInt(allWords.length)];
          }
          String w;
          var tries = 0;
          do {
            w = allWords[Random().nextInt(allWords.length)];
            tries++;
          } while (used.contains(w) && tries < 10);
          used.add(w);
          return w;
        }

        final articlePool = <List<String>>[];
        for (var qi = 0; qi < count; qi++) {
          final qWords = <String>[];
          // 抽取约 wordsPerQuestion 个不重复单词作为该题词汇池
          final targetWords = min(wordsPerQuestion, allWords.length);
          for (var k = 0; k < targetWords; k++) {
            qWords.add(pickUnique());
          }
          articlePool.add(qWords);
        }
        final sb = StringBuffer();
        for (var i = 0; i < articlePool.length; i++) {
          sb.writeln('第${i + 1}题(${articlePool[i].length}词): ${articlePool[i].join(', ')}');
        }
        vocabHint = '\n【本次出题词汇池】以下单词已由系统从专升本大纲随机抽取（必须从对应词汇池中选词组句，允许使用派生词、变形及少量连接词/介词/冠词；不必用完全部单词）：\n$sb';
      }
    }

    String systemPrompt;
    final typeName = qTypeName(qTypeFrom(selectedType));

    if (selectedLevel == 'zsb' && vocabHint.isNotEmpty) {
      if (selectedType == 'reading') {
        systemPrompt = '你是一个英语出题专家。请根据下方给出的【词汇池】，从每个词汇池中挑选合适的单词，写成一篇通顺、地道的英文短文（约 $wordCount 词），并针对短文出 3-4 道阅读理解选择题。' +
            (customReq.isNotEmpty ? '额外要求：$customReq。' : '') +
            '要求：${levelGuides['zsb']}' +
            '每个词汇池对应一篇文章；英文必须优先使用词汇池中的单词（允许使用派生词、变形及少量连接词/介词/冠词），不得大量使用词汇池之外的生僻词；题目紧扣文章内容，考查细节理解、推断、主旨大意等；每题 4 个选项且只有一个正确答案。' +
            '\n\n$vocabHint' +
            '\n请以JSON数组格式返回，每道题对应一个词汇池，格式如下：\n' +
            '[{"passage": "英文短文", "questions": [{"question": "问题1", "options": ["A. 选项", "B. 选项", "C. 选项", "D. 选项"], "answer": "A", "analysis": "答案解析", "knowledge": ["知识点"]}]}]\n' +
            '只返回JSON数组，不要其他内容。';
      } else if (selectedType == 'choice') {
        systemPrompt = '你是一个英语出题专家。请根据下方给出的【词汇池】，从每个词汇池中挑选合适的单词，各出 1 道单项选择题（题干为英文，4 个选项，考查词汇辨析、固定搭配或基础语法）。' +
            (customReq.isNotEmpty ? '额外要求：$customReq。' : '') +
            '要求：${levelGuides['zsb']}' +
            '每个词汇池对应一道题；题干和选项优先使用词汇池中的单词（允许使用派生词、变形及少量连接词/介词/冠词）；正确答案必须唯一且给出解析。' +
            '\n\n$vocabHint' +
            '\n请以JSON数组格式返回，每道题对应一个词汇池，格式如下：\n' +
            '[{"question": "英文题干", "options": ["A. 选项", "B. 选项", "C. 选项", "D. 选项"], "answer": "B", "analysis": "答案解析", "knowledge": ["知识点"]}]\n' +
            '只返回JSON数组，不要其他内容。';
      } else if (selectedType == 'grammar') {
        systemPrompt = '你是一个英语出题专家。请根据下方给出的【词汇池】，从每个词汇池中挑选合适的单词，各出 1 道语法填空题。给出带空格的英文句子（用 ____ 表示空格），并给出中文语境提示。' +
            (customReq.isNotEmpty ? '额外要求：$customReq。' : '') +
            '要求：${levelGuides['zsb']}' +
            '每个词汇池对应一道题；句子优先使用词汇池中的单词（允许使用派生词、变形及少量连接词/介词/冠词）。' +
            '\n\n$vocabHint' +
            '\n请以JSON数组格式返回，每道题对应一个词汇池，格式如下：\n' +
            '[{"chinese": "中文语境提示", "english": "含 ____ 空格的英文句子", "knowledge": ["知识点1"]}]\n' +
            '只返回JSON数组，不要其他内容。';
      } else if (selectedType == 'writing') {
        systemPrompt = '你是一个英语出题专家。请根据下方给出的【词汇池】，从每个词汇池中挑选合适的单词，各出 1 道写作题（给出写作要求和参考范文）。' +
            (customReq.isNotEmpty ? '额外要求：$customReq。' : '') +
            '要求：${levelGuides['zsb']}' +
            '每个词汇池对应一道题；范文优先使用词汇池中的单词（允许使用派生词、变形及少量连接词/介词/冠词）。' +
            '\n\n$vocabHint' +
            '\n请以JSON数组格式返回，每道题对应一个词汇池，格式如下：\n' +
            '[{"chinese": "写作题目要求（中文）", "english": "参考范文", "knowledge": ["知识点1"]}]\n' +
            '只返回JSON数组，不要其他内容。';
      } else {
        // translation / mixed 默认走翻译题模式
        systemPrompt = '你是一个英语出题专家。请根据下方给出的【词汇池】，从每个词汇池中挑选合适的单词，组合成一篇通顺、地道的英文短文（约 $wordCount 词），并为每篇短文写一句对应内容的中文翻译作为题目（中文字数与英文相当）。' +
            (customReq.isNotEmpty ? '额外要求：$customReq。' : '') +
            '要求：${levelGuides['zsb']}' +
            '每个词汇池对应生成一道题；所有英文必须优先使用词汇池中的单词（允许使用派生词、变形及少量连接词/介词/冠词），不得大量使用词汇池之外的生僻词；句子语法正确、自然流畅。' +
            '\n\n$vocabHint' +
            '\n请以JSON数组格式返回，每道题对应一个词汇池，格式如下：\n' +
            '[{"chinese": "中文题目（对应英文内容）", "english": "用该题词汇池单词写成的英文内容", "knowledge": ["知识点1"]}]\n' +
            '只返回JSON数组，不要其他内容。';
      }
    } else if (selectedType == 'reading') {
      systemPrompt = '你是一个英语出题专家。请生成 $count 篇阅读理解题，难度为${levelNames[selectedLevel]}。每篇包含一篇英文短文（约 $wordCount 词）和 3-4 道单选题。' +
          (customReq.isNotEmpty ? '额外要求：$customReq' : '') +
          '\n${levelGuides[selectedLevel]}\n\n' +
          '请以JSON数组格式返回，格式如下：\n' +
          '[{"passage": "英文短文", "questions": [{"question": "问题", "options": ["A. 选项", "B. 选项", "C. 选项", "D. 选项"], "answer": "A", "analysis": "答案解析", "knowledge": ["知识点"]}]}]\n' +
          '题目考查细节、推断、主旨等，答案必须唯一；只返回JSON数组，不要其他内容。';
    } else if (selectedType == 'choice') {
      systemPrompt = '你是一个英语出题专家。请生成 $count 道单项选择题，难度为${levelNames[selectedLevel]}。题干为英文，考查词汇辨析、固定搭配或基础语法。' +
          (customReq.isNotEmpty ? '额外要求：$customReq' : '') +
          '\n${levelGuides[selectedLevel]}\n\n' +
          '请以JSON数组格式返回，格式如下：\n' +
          '[{"question": "英文题干", "options": ["A. 选项", "B. 选项", "C. 选项", "D. 选项"], "answer": "B", "analysis": "答案解析", "knowledge": ["知识点1"]}]\n' +
          '正确答案必须唯一且包含在选项中；只返回JSON数组，不要其他内容。';
    } else if (selectedType == 'grammar') {
      systemPrompt = '你是一个英语出题专家。请生成 $count 道语法填空题，难度为${levelNames[selectedLevel]}。给出带空格的英文句子（用 ____ 表示空格），并给出中文语境提示。' +
          (customReq.isNotEmpty ? '额外要求：$customReq' : '') +
          '\n${levelGuides[selectedLevel]}\n\n' +
          '请以JSON数组格式返回，格式如下：\n' +
          '[{"chinese": "中文语境提示", "english": "含 ____ 空格的英文句子", "knowledge": ["知识点1"]}]\n' +
          '只返回JSON数组，不要其他内容。';
    } else if (selectedType == 'writing') {
      systemPrompt = '你是一个英语出题专家。请生成 $count 道写作题，难度为${levelNames[selectedLevel]}。题目贴近考试常见文体（书信、议论文、记叙文等）。' +
          (customReq.isNotEmpty ? '额外要求：$customReq' : '') +
          '\n${levelGuides[selectedLevel]}\n\n' +
          '请以JSON数组格式返回，格式如下：\n' +
          '[{"chinese": "写作题目要求（中文）", "english": "参考范文", "knowledge": ["知识点1"]}]\n' +
          '只返回JSON数组，不要其他内容。';
    } else if (selectedType == 'mixed') {
      // 综合模拟套卷：混合多种题型
      systemPrompt = '你是一个英语出题专家。请生成一套综合模拟试卷，包含 $count 道题目，混合以下题型：翻译题、阅读理解、语法填空、选择题、写作题。难度为${levelNames[selectedLevel]}。' +
          '翻译方向：$dirDesc。' +
          (customReq.isNotEmpty ? '额外要求：$customReq' : '') +
          '\n${levelGuides[selectedLevel]}\n\n' +
          '请以JSON数组格式返回，每道题注明题型，格式如下：\n' +
          '[{"type": "translation|reading|grammar|choice|writing", "chinese": "中文内容", "english": "英文内容", "passage": "阅读短文（仅reading需要）", "questions": [{"question": "问题", "options": ["A. 选项", "B. 选项", "C. 选项", "D. 选项"], "answer": "A", "analysis": "答案解析", "knowledge": ["知识点"]}], "knowledge": ["知识点1"]}]\n' +
          '只返回JSON数组，不要其他内容。';
    } else {
      systemPrompt = '你是一个英语出题专家。请生成 $count 道$typeName，难度为${levelNames[selectedLevel]}。' +
          '翻译方向：$dirDesc。' +
          (customReq.isNotEmpty ? '额外要求：$customReq' : '') +
          '\n${levelGuides[selectedLevel]}\n\n' +
          '请以JSON数组格式返回，格式如下：\n' +
          '[{"chinese": "中文内容", "english": "英文内容", "knowledge": ["知识点1"]}]\n' +
          '只返回JSON数组，不要其他内容。';
    }

    final maxTokens = (selectedLevel == 'zsb' || selectedType == 'reading' || selectedType == 'mixed') ? 8192 : 4096;
    final reply = await ApiService.callAI(
      [
        {'role': 'user', 'content': '请出题'}
      ],
      systemPrompt,
      config: apiConfig,
      maxTokens: maxTokens,
    );

    generating = false;
    if (reply != null) {
      final list = ApiService.extractJsonArray(reply);
      if (list != null && list.isNotEmpty) {
        generatedQuestions = list
            .map((q) {
              // mixed 模式：根据每道题的 type 字段分别规范化
              if (selectedType == 'mixed' && q['type'] != null) {
                final subType = qTypeFrom(q['type'] as String);
                return normalizeGeneratedQuestion(q, subType, selectedLevel);
              }
              return normalizeGeneratedQuestion(q, qTypeFrom(selectedType), selectedLevel);
            })
            .toList();
        generatedQuestionIdx = 0;
        loadGeneratedQuestion();
        notifyListeners();
        return true;
      }
    }
    notifyListeners();
    return false;
  }

  /// 将 AI 返回的原始题目按题型规范化
  Question normalizeGeneratedQuestion(Map<String, dynamic> raw, QType type, String level) {
    if (type == QType.reading) {
      final subs = (raw['questions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final questions = subs.map((sub) {
        final idx = parseAnswerIdx(sub['answer']);
        return ReadingSubQ(
          question: (sub['question'] ?? sub['q'] ?? '') as String,
          options: normalizeOptions(sub['options']),
          answerIdx: idx,
          answerLetter: (sub['answer'] ?? '') as String,
          analysis: (sub['analysis'] ?? sub['explain'] ?? '') as String,
          knowledge: (sub['knowledge'] as List?)?.cast<String>() ?? [],
        );
      }).toList();
      final passage = (raw['passage'] ?? raw['english'] ?? '') as String;
      return Question(
        type: QType.reading,
        level: level,
        passage: passage,
        questions: questions,
        text: '阅读下面的短文，回答后面的问题。',
        chinese: passage,
        english: passage,
        correctAnswer: passage,
        userAnswers: List.filled(questions.length, null),
      );
    }
    if (type == QType.choice) {
      final options = normalizeOptions(raw['options']);
      final answerIdx = parseAnswerIdx(raw['answer']);
      final questionText = (raw['question'] ?? raw['chinese'] ?? raw['text'] ?? '') as String;
      return Question(
        type: QType.choice,
        level: level,
        question: questionText,
        text: questionText,
        chinese: questionText,
        english: options.join(' | '),
        options: options,
        answerIdx: answerIdx,
        answerLetter: (raw['answer'] ?? (answerIdx >= 0 ? 'ABCDEFGH'[answerIdx] : '')) as String,
        analysis: (raw['analysis'] ?? raw['explain'] ?? '') as String,
        knowledge: (raw['knowledge'] as List?)?.cast<String>() ?? [],
        userAnswerIdx: null,
      );
    }
    // 翻译 / 语法 / 写作
    return Question(
      type: type,
      level: level,
      chinese: (raw['chinese'] ?? raw['text'] ?? '') as String,
      english: (raw['english'] ?? raw['correctAnswer'] ?? '') as String,
      text: (raw['chinese'] ?? raw['text'] ?? '') as String,
      correctAnswer: (raw['english'] ?? raw['correctAnswer'] ?? '') as String,
      knowledge: (raw['knowledge'] as List?)?.cast<String>() ?? [],
    );
  }

  List<String> normalizeOptions(Object? options) {
    if (options is! List) return [];
    final out = <String>[];
    for (final o in options) {
      String t;
      if (o is String) {
        t = o;
      } else if (o is Map) {
        t = (o['text'] ?? o['content'] ?? '') as String;
      } else {
        t = o?.toString() ?? '';
      }
      // 剥离选项文本开头的字母序号（如 "A. xxx" / "B、xxx"）
      out.add(t.replaceFirst(RegExp(r'^[A-Ha-h]\s*[.、:：)]\s*'), '').trim());
    }
    return out;
  }

  /// 解析答案字母/数字 → 选项索引
  int parseAnswerIdx(Object? answer) {
    if (answer == null) return -1;
    if (answer is num) return answer.toInt();
    final s = answer.toString().trim();
    if (s.isEmpty) return -1;
    final m = RegExp(r'^([A-H])').firstMatch(s);
    if (m != null) return m.group(1)!.toUpperCase().codeUnitAt(0) - 65;
    final n = int.tryParse(s);
    if (n != null) return n;
    return -1;
  }

  void loadGeneratedQuestion() {
    if (generatedQuestionIdx >= generatedQuestions.length) return;
    final q = generatedQuestions[generatedQuestionIdx];
    direction = 'zh2en';
    loadQuestion(q);
  }

  // ===== 判分 =====
  bool submitting = false;

  Future<void> submitCurrent() async {
    final q = currentQuestion;
    if (q.type == QType.choice && q.hasOptions) {
      gradeChoice();
      return;
    }
    if (q.type == QType.reading && q.hasReading) {
      gradeReading();
      return;
    }
    await gradeText();
  }

  String get currentUserAnswer {
    final q = currentQuestion;
    if (q.type == QType.choice && q.hasOptions && q.userAnswerIdx != null) {
      final idx = q.userAnswerIdx!;
      final letter = idx >= 0 && idx < 8 ? 'ABCDEFGH'[idx] : '';
      final opt = idx >= 0 && idx < q.options.length ? q.options[idx] : '';
      return letter.isEmpty ? opt : '$letter. $opt';
    }
    if (q.type == QType.reading && q.hasReading) {
      final lines = <String>[];
      for (var i = 0; i < q.questions.length; i++) {
        final sel = q.userAnswers[i];
        if (sel == null) {
          lines.add('${i + 1}. 未作答');
        } else {
          final letter = sel >= 0 && sel < 8 ? 'ABCDEFGH'[sel] : '';
          final opt = sel >= 0 && sel < q.questions[i].options.length ? q.questions[i].options[sel] : '';
          lines.add('${i + 1}. ${letter.isNotEmpty ? '$letter. ' : ''}$opt');
        }
      }
      return lines.join('；');
    }
    return _textAnswerControllerValue;
  }

  // 文本作答内容（由 UI 层读写）
  String _textAnswerControllerValue = '';

  String get textAnswerValue => _textAnswerControllerValue;
  set textAnswerValue(String v) => _textAnswerControllerValue = v;

  void gradeChoice() {
    final q = currentQuestion;
    final idx = q.userAnswerIdx;
    if (idx == null || idx < 0) {
      return; // UI 提示
    }
    final correct = q.answerIdx == idx;
    final score = correct ? 100 : 0;
    final letterOf = (int i) => (i >= 0 && i < 8) ? 'ABCDEFGH'[i] : '';
    final correctText = q.answerIdx >= 0 ? '${letterOf(q.answerIdx)}. ${q.options[q.answerIdx]}' : q.answerLetter;
    final userText = '${letterOf(idx)}. ${q.options[idx]}';
    final errors = correct
        ? <ErrorItem>[]
        : [
            ErrorItem(
              item: '你选择了 $userText，正确答案是 $correctText',
              explain: q.analysis.isEmpty ? '参见解析。' : q.analysis,
            )
          ];
    final result = GradingResult(score: score, correctAnswer: correctText, errors: errors, knowledge: q.knowledge);
    currentQuestion = q.copyWith(
      score: score,
      correctAnswer: correctText,
      errors: errors,
      knowledge: q.knowledge,
    );
    _lastGrading = result;
    _lastChoiceCorrect = correct;
    _lastChoiceIdx = idx;
    handleGradingResult(result);
    notifyListeners();
  }

  GradingResult? _lastGrading;
  bool _lastChoiceCorrect = false;
  int _lastChoiceIdx = -1;

  bool get lastChoiceCorrect => _lastChoiceCorrect;
  int get lastChoiceIdx => _lastChoiceIdx;

  void gradeReading() {
    final q = currentQuestion;
    final letterOf = (int i) => (i >= 0 && i < 8) ? 'ABCDEFGH'[i] : '';
    var correctCount = 0;
    final correctLines = <String>[];
    final errors = <ErrorItem>[];
    final knowledgeSet = <String>{};
    for (var i = 0; i < q.questions.length; i++) {
      final sub = q.questions[i];
      final sel = q.userAnswers[i];
      final isCorrect = sub.answerIdx == sel;
      if (isCorrect) correctCount++;
      final correctText = sub.answerIdx >= 0 ? '${letterOf(sub.answerIdx)}. ${sub.options[sub.answerIdx]}' : sub.answerLetter;
      final userText = sel != null ? '${letterOf(sel)}. ${sel < sub.options.length ? sub.options[sel] : ''}' : '未作答';
      correctLines.add('${i + 1}. $correctText');
      if (!isCorrect) {
        errors.add(ErrorItem(
          item: '第${i + 1}题：你选择了 $userText，正确答案是 $correctText',
          explain: sub.analysis.isEmpty ? '参见解析。' : sub.analysis,
        ));
      }
      knowledgeSet.addAll(sub.knowledge);
    }
    final total = q.questions.length;
    final score = (correctCount / total * 100).round();
    final result = GradingResult(
      score: score,
      correctAnswer: correctLines.join('；'),
      errors: errors,
      knowledge: knowledgeSet.toList(),
    );
    currentQuestion = q.copyWith(
      score: score,
      correctAnswer: correctLines.join('；'),
      errors: errors,
      knowledge: knowledgeSet.toList(),
    );
    _lastGrading = result;
    handleGradingResult(result);
    notifyListeners();
  }

  bool get hasGrading => _lastGrading != null;
  GradingResult? get lastGrading => _lastGrading;

  Future<void> gradeText() async {
    final answer = _textAnswerControllerValue.trim();
    if (answer.isEmpty) return;
    submitting = true;
    notifyListeners();
    final q = currentQuestion;
    final dirDesc = isZh2En ? '中译英' : '英译中';
    final systemPrompt = '你是一个英语批改专家。请根据以下信息批改学生的答案：\n' +
        '题目类型：${qTypeName(q.type)}（$dirDesc）\n' +
        '题目：${q.text}\n' +
        '学生答案：$answer\n' +
        '请用${isZh2En ? '英文' : '中文'}作为正确答案语言。\n\n' +
        '请以JSON格式返回批改结果，格式如下：\n' +
        '{\n  "score": 分数(0-100),\n  "correctAnswer": "正确答案",\n  "errors": [{"item": "错误描述", "explain": "解析"}],\n  "knowledge": ["知识点1", "知识点2"]\n}\n只返回JSON，不要其他内容。';
    final reply = await ApiService.callAI(
      [
        {'role': 'user', 'content': '请批改我的答案'}
      ],
      systemPrompt,
      config: apiConfig,
    );
    submitting = false;
    if (reply != null) {
      final obj = ApiService.extractJsonObject(reply);
      if (obj != null) {
        final result = GradingResult.fromJson(obj);
        currentQuestion = q.copyWith(
          score: result.score,
          correctAnswer: result.correctAnswer,
          errors: result.errors,
          knowledge: result.knowledge,
        );
        _lastGrading = result;
        handleGradingResult(result);
        notifyListeners();
        return;
      }
    }
    notifyListeners();
  }

  // ===== 学习记录 / 错题本 =====
  void handleGradingResult(GradingResult result) {
    recordStudy(result.score);
    if (result.score < 70) {
      addToWrongBook();
    } else {
      final key = wrongKey(currentQuestion);
      if (wrongQuestions.any((w) => wrongKey(w.question) == key)) {
        // 已达标提示由 UI 处理
      }
    }
  }

  String wrongKey(Question q) => (q.chinese.isNotEmpty ? q.chinese : q.text).trim();

  void recordStudy(int score) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dur = questionStartTime > 0 ? max(0, ((now - questionStartTime) / 1000).round()) : 0;
    final q = currentQuestion;
    studyRecords.insert(0, StudyRecord(
          timestamp: now,
          type: q.type,
          level: q.level,
          direction: direction,
          text: (q.text.isEmpty ? q.chinese : q.text).substring(0, min(80, (q.text.isEmpty ? q.chinese : q.text).length)),
          score: score,
          isWrong: score < 70,
          duration: dur,
        ));
    if (studyRecords.length > 1000) studyRecords.removeRange(1000, studyRecords.length);
    Storage.saveStudyRecords(studyRecords);
    questionStartTime = now;
  }

  void addToWrongBook() {
    final q = currentQuestion;
    final key = wrongKey(q);
    if (key.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingIdx = wrongQuestions.indexWhere((w) => wrongKey(w.question) == key);
    if (existingIdx >= 0) {
      final w = wrongQuestions[existingIdx];
      wrongQuestions[existingIdx] = WrongItem(
        id: w.id,
        question: q,
        userAnswer: currentUserAnswer,
        correctAnswer: q.correctAnswer,
        score: q.score ?? 0,
        wrongCount: w.wrongCount + 1,
        firstWrongTime: w.firstWrongTime,
        lastWrongTime: now,
        mastered: false,
        direction: direction,
      );
    } else {
      wrongQuestions.insert(0, WrongItem(
            id: '${now}_${Random().toString().substring(2, 7)}',
            question: q,
            userAnswer: currentUserAnswer,
            correctAnswer: q.correctAnswer,
            score: q.score ?? 0,
            wrongCount: 1,
            firstWrongTime: now,
            lastWrongTime: now,
            direction: direction,
          ));
    }
    Storage.saveWrongQuestions(wrongQuestions);
    notifyListeners();
  }

  void removeWrong(String id) {
    wrongQuestions.removeWhere((w) => w.id == id);
    Storage.saveWrongQuestions(wrongQuestions);
    notifyListeners();
  }

  void toggleMastered(String id) {
    final idx = wrongQuestions.indexWhere((w) => w.id == id);
    if (idx >= 0) {
      final w = wrongQuestions[idx];
      wrongQuestions[idx] = WrongItem(
        id: w.id,
        question: w.question,
        userAnswer: w.userAnswer,
        correctAnswer: w.correctAnswer,
        score: w.score,
        wrongCount: w.wrongCount,
        firstWrongTime: w.firstWrongTime,
        lastWrongTime: w.lastWrongTime,
        mastered: !w.mastered,
        direction: w.direction,
      );
      Storage.saveWrongQuestions(wrongQuestions);
      notifyListeners();
    }
  }

  void retryWrong(WrongItem w) {
    direction = w.direction.isEmpty ? 'zh2en' : w.direction;
    loadQuestion(w.question);
  }

  // ===== 收藏 =====
  List<Favorite> favorites = [];

  void loadFavorites() {
    favorites = Storage.loadFavorites();
    notifyListeners();
  }

  bool get isCurrentFavorite {
    final key = wrongKey(currentQuestion);
    return favorites.any((f) => (f.chinese.isNotEmpty ? f.chinese : f.text) == key);
  }

  void toggleFavorite() {
    final q = currentQuestion;
    final key = wrongKey(q);
    if (key.isEmpty) return;
    final idx = favorites.indexWhere((f) => (f.chinese.isNotEmpty ? f.chinese : f.text) == key);
    if (idx >= 0) {
      favorites.removeAt(idx);
    } else {
      favorites.insert(0, Favorite(
            text: q.text,
            chinese: q.chinese,
            english: q.english,
            type: q.type,
            level: q.level,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
    }
    Storage.saveFavorites(favorites);
    notifyListeners();
  }

  // ===== 答题记录（单词记录本） =====
  Map<String, RecordedWord> recordedWords = {};

  void loadRecordedWords() {
    recordedWords = Storage.loadRecordedWords();
    notifyListeners();
  }

  Set<String> recordsSelected = {};

  void loadRecordsSelected() {
    recordsSelected = Storage.loadRecordsSelected();
    notifyListeners();
  }

  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did',
    'will', 'would', 'shall', 'should', 'may', 'might', 'can', 'could', 'must', 'need', 'dare', 'to', 'of', 'in', 'on',
    'at', 'for', 'with', 'by', 'from', 'up', 'down', 'out', 'off', 'over', 'under', 'again', 'further', 'then', 'once',
    'here', 'there', 'when', 'where', 'why', 'how', 'all', 'each', 'every', 'both', 'few', 'more', 'most', 'other',
    'some', 'such', 'no', 'nor', 'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very', 'just', 'because', 'as',
    'until', 'while', 'about', 'between', 'into', 'through', 'during', 'before', 'after', 'above', 'below', 'and',
    'but', 'or', 'if', 'this', 'that', 'these', 'those', 'i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him',
    'her', 'us', 'them', 'my', 'your', 'his', 'its', 'our', 'their', 'mine', 'yours', 'hers', 'ours', 'theirs', 'am',
    'which', 'what', 'who', 'whom', 'whose', 'im', 'youre', 'hes', 'shes', 'theyre', 'ive', 'youve', 'weve',
    'theyve', 'lets', 'theres', 'heres', 'whos', 'thats', 'whats', 'id', 'youd', 'hed', 'wed', 'theyd', 'ill',
    'youll', 'hell', 'well', 'theyll', 'dont', 'doesnt', 'isnt', 'arent', 'wasnt', 'werent', 'hasnt', 'havent',
    'hadnt', 'didnt', 'couldnt', 'wouldnt', 'shouldnt', 'cant', 'wont', 'nt'
  };

  List<String> wordsFromText(String text) {
    if (text.isEmpty) return [];
    final words = RegExp(r"\b[a-z]+(?:'[a-z]+)?\b").allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
    final seen = <String>{};
    final out = <String>[];
    for (final w in words) {
      if (w.length >= 2 && !_stopWords.contains(w) && !seen.contains(w)) {
        seen.add(w);
        out.add(w);
      }
    }
    return out;
  }

  /// 从当前题目提取并记录单词，返回记录结果
  ({int total, int newCount})? recordWordsFromQuestion() {
    final q = currentQuestion;
    if (q.type == QType.dictation && q.english.isNotEmpty) {
      // 默写题由默写流程单独处理
    }
    final enText = [q.english, q.correctAnswer, q.text, _textAnswerControllerValue]
        .where((s) => s.isNotEmpty)
        .join(' ');
    final words = wordsFromText(enText);
    if (words.isEmpty) return null;
    final questionKey = (q.chinese.isNotEmpty ? q.chinese : q.text).substring(0, min(50, (q.chinese.isNotEmpty ? q.chinese : q.text).length));
    var newCount = 0;
    for (final w in words) {
      final existing = recordedWords[w];
      if (existing == null) {
        recordedWords[w] = RecordedWord(count: 1, lastSeen: DateTime.now().millisecondsSinceEpoch, firstSeen: DateTime.now().millisecondsSinceEpoch, sources: [questionKey]);
        newCount++;
      } else {
        recordedWords[w] = RecordedWord(
          count: existing.count + 1,
          lastSeen: DateTime.now().millisecondsSinceEpoch,
          firstSeen: existing.firstSeen,
          sources: existing.sources.contains(questionKey) ? existing.sources : [...existing.sources, questionKey].take(10).toList(),
        );
      }
    }
    Storage.saveRecordedWords(recordedWords);
    notifyListeners();
    return (total: words.length, newCount: newCount);
  }

  bool get isCurrentRecorded {
    final q = currentQuestion;
    if (q.type == QType.dictation) return false;
    final key = (q.chinese.isNotEmpty ? q.chinese : q.text).substring(0, min(50, (q.chinese.isNotEmpty ? q.chinese : q.text).length));
    return recordedWords.values.any((v) => v.sources.contains(key));
  }

  void clearRecords() {
    recordedWords = {};
    recordsSelected = {};
    Storage.saveRecordedWords(recordedWords);
    Storage.saveRecordsSelected(recordsSelected);
    notifyListeners();
  }

  // ===== 词汇剖析 =====
  bool analyzing = false;

  Future<void> analyzeWords(String text, {bool force = false}) async {
    if (text.isEmpty) return;
    analyzing = true;
    analysisTokens = [];
    notifyListeners();
    final cacheKey = '${ApiService.simpleHash('$text|${isZh2En ? 'z' : 'e'}')}';
    if (!force) {
      final cached = Storage.readAnalysisCache(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        analysisTokens = cached;
        analyzing = false;
        notifyListeners();
        return;
      }
    }
    // 本地切词
    var tokens = DictService.fallbackTokens(text, isZh2En);

    // 第一步：全部本地词库查找（纯内存，极快）
    final missingIdx = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.isMissing && t.type != 'other' && !RegExp(r'^[\s\p{P}]+$', unicode: true).hasMatch(t.text)) {
        missingIdx.add(i);
      }
    }

    // 全部命中，直接完成
    if (missingIdx.isEmpty) {
      analysisTokens = tokens;
      Storage.writeAnalysisCache(cacheKey, tokens);
      analyzing = false;
      notifyListeners();
      return;
    }

    // 渐进式渲染：先显示已有结果 + "分析中..."
    for (final i in missingIdx) {
      tokens[i] = WordToken(text: tokens[i].text, type: tokens[i].type, word: tokens[i].word, pos: tokens[i].pos, translation: '分析中...', other: tokens[i].other);
    }
    analysisTokens = tokens;
    notifyListeners();

    // 无 API 配置，标记缺失词
    if (!apiConfig.ready) {
      for (final i in missingIdx) {
        tokens[i] = WordToken(text: tokens[i].text, type: tokens[i].type, word: tokens[i].word, pos: tokens[i].pos, translation: '暂无释义');
      }
      analysisTokens = tokens;
      analyzing = false;
      notifyListeners();
      return;
    }

    // 第二步：缺失词分批并行请求 AI（每批最多 30 词，最多 3 批并行）
    final batchSize = 30;
    final batches = <List<String>>[];
    for (var i = 0; i < missingIdx.length; i += batchSize) {
      final end = (i + batchSize > missingIdx.length) ? missingIdx.length : i + batchSize;
      final batch = missingIdx.sublist(i, end).map((idx) => tokens[idx].text.toLowerCase().trim()).where((t) => t.isNotEmpty).toList();
      if (batch.isNotEmpty) batches.add(batch);
    }

    // 并行请求所有批次
    final futures = batches.map((batch) {
      final prompt = '你是英语词汇专家。请为以下单词/词组提供词性和中文释义，返回JSON数组：\n' +
          '[{"word":"单词","pos":"词性","translation":"中文释义","other":"补充说明(可空)"}]\n' +
          '单词列表：${batch.join('、')}\n只返回JSON数组，不要其他内容。';
      return ApiService.callAI(
        [{'role': 'user', 'content': '请解释这些单词'}],
        prompt,
        config: apiConfig,
        maxTokens: 2048,
      );
    }).toList();

    final replies = await Future.wait(futures);

    // 合并所有 AI 返回结果
    final wordMap = <String, WordToken>{};
    for (final reply in replies) {
      if (reply == null || reply.isEmpty) continue;
      final list = ApiService.extractJsonArray(reply);
      if (list == null) continue;
      for (final e in list) {
        final w = ((e['word'] ?? '') as String).toLowerCase().trim();
        if (w.isEmpty) continue;
        wordMap[w] = WordToken(
          text: (e['word'] ?? '') as String,
          type: 'word',
          word: (e['word'] ?? '') as String,
          pos: (e['pos'] ?? '') as String,
          translation: (e['translation'] ?? '') as String,
          other: (e['other'] ?? '') as String,
        );
      }
    }

    // 用 AI 结果填充缺失词
    for (final i in missingIdx) {
      final key = tokens[i].text.toLowerCase().trim();
      final hit = wordMap[key];
      if (hit != null) {
        tokens[i] = WordToken(text: tokens[i].text, type: tokens[i].type, word: tokens[i].text, pos: hit.pos, translation: hit.translation, other: hit.other);
      } else {
        tokens[i] = WordToken(text: tokens[i].text, type: tokens[i].type, word: tokens[i].text, pos: tokens[i].pos, translation: '暂无释义');
      }
    }

    analysisTokens = tokens;
    Storage.writeAnalysisCache(cacheKey, tokens);
    analyzing = false;
    notifyListeners();
  }

  /// 校验 AI 返回的 tokens 是否覆盖原文（去空白标点后比对，覆盖率 >= 80% 视为有效）
  bool _aiTokensCoverText(List<WordToken> aiTokens, String text) {
    String strip(String s) => s.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
    final a = strip(aiTokens.map((t) => t.text).join());
    final b = strip(text);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final cover = _lcsLength(a, b) / b.length;
    return cover >= 0.8;
  }

  /// 最长公共子序列长度（用于计算覆盖率）
  int _lcsLength(String a, String b) {
    final m = a.length, n = b.length;
    if (m == 0 || n == 0) return 0;
    final dp = List.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      var prev = 0;
      for (var j = 1; j <= n; j++) {
        final tmp = dp[j];
        dp[j] = a[i - 1] == b[j - 1] ? prev + 1 : (dp[j] > dp[j - 1] ? dp[j] : dp[j - 1]);
        prev = tmp;
      }
    }
    return dp[n];
  }

  /// 用本地词库补全 AI 返回中仍缺失释义的 token（保留 type 不变，词组也可补）
  void _backfillFromDict(List<WordToken> tokens) {
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.type == 'other') continue;
      if (t.translation.isEmpty || t.translation == '暂无释义') {
        final key = (t.word.isNotEmpty ? t.word : t.text).toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');
        if (key.isEmpty) continue;
        final entry = DictService.lookup(key);
        if (entry != null) {
          tokens[i] = WordToken(
            text: t.text,
            type: t.type,
            word: t.word,
            pos: t.pos.isEmpty ? entry.pos : t.pos,
            translation: entry.translation,
            other: entry.other,
          );
        }
      }
    }
  }

  // ===== 对话助手 =====
  bool chatSending = false;
  final ValueNotifier<int> chatUpdateNotifier = ValueNotifier<int>(0);
  int _chatThrottleTimer = 0;

  void _notifyChatUpdate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _chatThrottleTimer < 50) return; // 50ms 节流
    _chatThrottleTimer = now;
    chatUpdateNotifier.value++;
  }

  Future<String> sendChat(
    String text, {
    void Function(String chunk)? onReasoning,
    void Function(String chunk)? onDelta,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || chatSending) return '';
    chatSending = true;
    notifyListeners();
    chatHistory.add(ChatMessage(role: 'user', content: trimmed));
    _notifyChatUpdate();
    final q = currentQuestion;
    final dirDesc = isZh2En ? '中译英' : '英译中';
    final userAnswer = currentUserAnswer;
    final prompt = '你是一个专业的英语学习助手，必须紧密围绕"当前题目"回答用户的问题，不要偏离题目主题。\n\n' +
        '【当前题目信息】\n' +
        '题目类型：${qTypeName(q.type)}（$dirDesc）\n' +
        '难度：${levelName(q.level)}\n' +
        '题目内容：${q.text}\n' +
        (q.chinese.isNotEmpty ? '中文原文：${q.chinese}\n' : '') +
        (q.english.isNotEmpty ? '英文原文：${q.english}\n' : '') +
        (userAnswer.isNotEmpty ? '用户当前作答：$userAnswer\n' : '') +
        (q.correctAnswer.isNotEmpty ? '参考答案：${q.correctAnswer}\n' : '') +
        (q.knowledge.isNotEmpty ? '核心知识点：${q.knowledge.join('、')}\n' : '');
    final history = chatHistory
        .where((m) => m.role != 'system')
        .map((m) => {'role': m.role == 'ai' ? 'assistant' : 'user', 'content': m.content})
        .toList();

    String reply = '';
    final showReasoning = chatShowReasoning;
    if (chatStream && effectiveChatConfig.ready) {
      final msg = ChatMessage(role: 'ai', content: '', showReasoning: true, reasoning: '');
      chatHistory.add(msg);
      _notifyChatUpdate();
      String rawReasoning = '';
      String fullContent = '';
      reply = await ApiService.streamChat(
        history,
        prompt,
        config: effectiveChatConfig,
        onReasoning: (chunk) {
          rawReasoning += chunk;
          msg.reasoning = rawReasoning;
          _notifyChatUpdate();
        },
        onDelta: (chunk) {
          fullContent += chunk;
          msg.content = fullContent;
          if (onDelta != null) onDelta(chunk);
          _notifyChatUpdate();
        },
      );
      if (reply.isEmpty && msg.content.isEmpty) {
        reply = fallbackReply(trimmed);
        msg.content = reply;
      } else {
        msg.content = reply.isNotEmpty ? reply : msg.content;
      }
      _notifyChatUpdate();
    } else {
      final r = await ApiService.callAI(history, prompt, config: effectiveChatConfig);
      reply = (r == null || r.isEmpty) ? fallbackReply(trimmed) : r;
      chatHistory.add(ChatMessage(role: 'ai', content: reply));
      _notifyChatUpdate();
    }
    chatSending = false;
    notifyListeners();
    _notifyChatUpdate();
    return reply;
  }

  /// 未配置 API 时的兜底回复
  String fallbackReply(String text) {
    final q = currentQuestion;
    final userAnswer = _textAnswerControllerValue.trim();
    if (text.contains('答案') || text.contains('怎么翻') || text.contains('怎么译') || text.contains('正确')) {
      if (q.correctAnswer.isNotEmpty) {
        return '这道题的参考答案是：\n<code>${q.correctAnswer}</code>\n\n需要注意其中的关键表达，你对比一下自己的翻译，看看有哪些可以改进的地方。';
      }
      return '这道题建议你先尝试自己翻译，然后点击"提交答案"让 AI 批改，我会给出参考答案和详细解析。';
    }
    if (text.contains('对吗') || text.contains('对不对') || text.contains('正确吗') || text.contains('可以吗') || text.contains('好吗')) {
      if (userAnswer.isNotEmpty) {
        return '你目前的作答是：<code>$userAnswer</code>\n\n建议你点击"提交答案"按钮，我可以给出准确的得分和逐项错误分析。不过从表达上看，可以对照参考答案 <code>${q.correctAnswer}</code> 看看用词和语序是否一致。';
      }
      return '你还没有输入答案哦，先在作答区写下你的${isZh2En ? '英文' : '中文'}翻译吧。';
    }
    if (text.contains('分析') || text.contains('讲解') || text.contains('解释') || text.contains('理解') || text.contains('帮助') || text.contains('为什么')) {
      var reply = '好的，我来帮你分析这道题：\n\n题目：<code>${q.text}</code>\n';
      if (q.correctAnswer.isNotEmpty) {
        reply += '参考答案：<code>${q.correctAnswer}</code>\n\n';
      }
      if (q.knowledge.isNotEmpty) {
        reply += '**核心知识点：**\n${q.knowledge.map((k) => '- $k').join('\n')}\n';
      }
      if (q.errors.isNotEmpty) {
        reply += '**常见错误：**\n${q.errors.map((e) => '- ${e.item} —— ${e.explain}').join('\n')}\n';
      }
      reply += '你还有哪个部分不清楚？可以具体问问。';
      return reply;
    }
    var reply = '关于这道题（<code>${q.text}</code>），我可以帮你：\n- 分析题目考查的语法点和词汇\n- 讲解参考答案的翻译思路\n- 指出你作答中的问题并给出改进建议\n';
    if (userAnswer.isNotEmpty) {
      reply += '你目前的作答是：<code>$userAnswer</code>，请点击"提交答案"获取详细批改，或直接问我具体的问题。';
    } else {
      reply += '你可以先尝试翻译，或者直接问我关于这道题的任何问题。';
    }
    return reply;
  }

  void clearChat() {
    chatHistory = [];
    notifyListeners();
    _notifyChatUpdate();
  }

  // ===== 默写 =====
  void startDictation(String mode, int count) {
    dictationMode = mode;
    final words = DictService.zsbWords();
    if (words.isEmpty) return;
    words.shuffle(Random());
    final picked = words.take(count).toList();
    dictationQueue = picked.map((w) {
      final e = DictService.zsbLookup(w);
      return WordToken(text: w, type: 'word', word: w, pos: e?.pos ?? '', translation: e?.translation ?? '', other: e?.other ?? '');
    }).toList();
    dictationIdx = 0;
    dictationTotal = 0;
    dictationCorrect = 0;
    notifyListeners();
  }

  WordToken? get currentDictationWord {
    if (dictationQueue.isEmpty || dictationIdx >= dictationQueue.length) return null;
    return dictationQueue[dictationIdx];
  }

  bool get dictationFinished => dictationQueue.isNotEmpty && dictationIdx >= dictationQueue.length;

  /// 批改默写答案，返回是否答对
  /// [advance] 为 false 时只批改不推进索引（由调用方控制何时下一题）
  bool checkDictationAnswer(String answer, {bool advance = true}) {
    final w = currentDictationWord;
    if (w == null) return false;
    final ans = answer.trim();
    bool correct;
    if (dictationMode == 'zh2en') {
      correct = ans.toLowerCase() == w.word.toLowerCase();
    } else {
      final ref = w.translation.replaceAll(RegExp(r'[；;，,。.、/]'), ' ').split(' ').where((s) => s.length >= 2).toList();
      final keyRef = ref.isEmpty ? w.translation : ref.join(' ');
      correct = keyRef.contains(ans) || ans.isNotEmpty && ref.any((r) => ans.contains(r) || r.contains(ans));
    }
    dictationTotal++;
    if (correct) dictationCorrect++;
    if (!correct) {
      final q = Question(
        type: QType.dictation,
        level: 'zsb',
        chinese: w.translation,
        english: w.word,
        text: dictationMode == 'zh2en' ? w.translation : w.word,
        correctAnswer: dictationMode == 'zh2en' ? w.word : w.translation,
        score: 0,
      );
      final now2 = DateTime.now().millisecondsSinceEpoch;
      wrongQuestions.insert(0, WrongItem(
            id: '${now2}_${Random().toString().substring(2, 7)}',
            question: q,
            userAnswer: ans,
            correctAnswer: q.correctAnswer,
            score: 0,
            wrongCount: 1,
            firstWrongTime: now2,
            lastWrongTime: now2,
            direction: dictationMode,
          ));
      Storage.saveWrongQuestions(wrongQuestions);
    }
    if (advance) {
      dictationIdx++;
      notifyListeners();
    }
    return correct;
  }

  /// 推进到下一道默写题
  void nextDictationQuestion() {
    dictationIdx++;
    notifyListeners();
  }

  void skipDictation() {
    final w = currentDictationWord;
    if (w == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final q = Question(
      type: QType.dictation,
      level: 'zsb',
      chinese: w.translation,
      english: w.word,
      text: dictationMode == 'zh2en' ? w.translation : w.word,
      correctAnswer: dictationMode == 'zh2en' ? w.word : w.translation,
      score: 0,
    );
    wrongQuestions.insert(0, WrongItem(
          id: '${now}_${Random().toString().substring(2, 7)}',
          question: q,
          userAnswer: '（跳过）',
          correctAnswer: q.correctAnswer,
          score: 0,
          wrongCount: 1,
          firstWrongTime: now,
          lastWrongTime: now,
          direction: dictationMode,
        ));
    Storage.saveWrongQuestions(wrongQuestions);
    dictationIdx++;
    dictationTotal++;
    notifyListeners();
  }

  // ===== 生词本 =====
  List<WordBookItem> wordbook = [];

  void loadWordBook() {
    wordbook = Storage.loadWordBook();
    notifyListeners();
  }

  void addToWordBook(String word, String translation) {
    final idx = wordbook.indexWhere((e) => e.word == word);
    if (idx >= 0) return;
    wordbook.insert(0, WordBookItem(
          word: word,
          translation: translation,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    Storage.saveWordBook(wordbook);
    notifyListeners();
  }

  void removeFromWordBook(String word) {
    wordbook.removeWhere((e) => e.word == word);
    Storage.saveWordBook(wordbook);
    notifyListeners();
  }

  void clearWordBook() {
    wordbook = [];
    Storage.saveWordBook(wordbook);
    notifyListeners();
  }

  // ===== 学习报告数据 =====
  List<StudyRecord> studyRecords = [];
  List<WrongItem> wrongQuestions = [];

  void loadStudyRecords() {
    studyRecords = Storage.loadStudyRecords();
    notifyListeners();
  }

  void loadWrongQuestions() {
    wrongQuestions = Storage.loadWrongQuestions();
    notifyListeners();
  }

  void clearStudyRecords() {
    studyRecords = [];
    Storage.saveStudyRecords(studyRecords);
    notifyListeners();
  }

  void clearWrongQuestions() {
    wrongQuestions = [];
    Storage.saveWrongQuestions(wrongQuestions);
    notifyListeners();
  }

  // ===== 设置 =====
  void saveApiConfig(ApiConfig c) {
    apiConfig = c;
    Storage.saveApiConfig(c);
    notifyListeners();
  }

  void saveChatSettings({required bool independent, required ApiConfig config, required bool showReasoning, required bool stream}) {
    chatApiIndependent = independent;
    chatApiConfig = config;
    chatShowReasoning = showReasoning;
    chatStream = stream;
    Storage.saveChatIndependent(independent);
    Storage.saveChatConfig(config);
    Storage.saveChatShowReasoning(showReasoning);
    Storage.saveChatStream(stream);
    notifyListeners();
  }

  void toggleDarkMode(bool v) {
    darkMode = v;
    Storage.saveDarkMode(v);
    notifyListeners();
  }

  void toggleFullscreen(bool v) {
    fullscreen = v;
    Storage.saveFullscreen(v);
    notifyListeners();
  }

  void togglePowerSavingMode(bool v) {
    powerSavingMode = v;
    Storage.savePowerSavingMode(v);
    notifyListeners();
  }

  void setUiMode(String mode) {
    uiMode = mode;
    Storage.saveUiMode(mode);
    notifyListeners();
  }

  // ===== 备份 / 导入 =====
  String buildBackupJson() => Storage.buildBackupJson();

  bool importBackup(String content) {
    final ok = Storage.importBackup(content);
    if (ok) {
      apiConfig = Storage.loadApiConfig();
      loadFavorites();
      loadWrongQuestions();
      loadStudyRecords();
      loadWordBook();
      loadRecordedWords();
      loadRecordsSelected();
      notifyListeners();
    }
    return ok;
  }
  /// 供 UI 调用的刷新入口（等价于 notifyListeners）
  void touch() => notifyListeners();
}
