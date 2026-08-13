/// 全局状态与核心业务逻辑（对应网页版 index.html 中的 state 与各函数）
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiMode, SystemUiOverlayStyle;
import 'models.dart';
import 'theme_colors.dart' show AppColors;
import 'services/api_service.dart';
import 'services/maimemo_service.dart';
import 'services/storage.dart';
import 'services/dict_service.dart';
import 'services/agent_service.dart';

/// 单词跨度信息（用于词组匹配）
class _WordSpan {
  final String text;
  final int start;
  final int end;
  const _WordSpan({required this.text, required this.start, required this.end});
}

/// Agent 单次工具调用步骤（用于在 AI 气泡上方单独展示，类似大厂 Agent UI）
class ToolStep {
  /// 展示文案，如 "生成 3 道翻译题"、"查询单词 hello"
  String label;
  /// 是否执行中（显示加载动画）
  bool running;
  /// 是否执行成功（显示对勾）
  bool done;
  /// 是否执行失败（显示错误）
  bool failed;
  ToolStep({required this.label, this.running = true, this.done = false, this.failed = false});
}

class ChatMessage {
  String role; // user / ai
  String content;
  bool showReasoning;
  bool reasoningExpanded;
  String? reasoning;
  /// Agent 工具调用步骤列表，在气泡上方单独展示（不混入对话文本）
  List<ToolStep> toolSteps = [];
  /// 用户消息携带的图片（base64 data URL），AI 消息为 null
  String? imageData;
  /// 缓存解码后的图片字节，避免每次重建都重新 base64Decode
  Uint8List? _imageBytes;
  /// 当前模型无图形能力时，图片显示为黑色占位
  bool imageDark;

  ChatMessage({required this.role, required this.content, this.showReasoning = false, this.reasoningExpanded = true, this.reasoning, this.imageData, this.imageDark = false});

  /// 获取解码后的图片字节（带缓存）
  Uint8List? get imageBytes {
    if (imageData == null) return null;
    if (_imageBytes != null) return _imageBytes;
    try {
      _imageBytes = base64Decode(imageData!.split(',').last);
    } catch (_) {}
    return _imageBytes;
  }
}

/// 全卷生成批次描述：题型 / 要求题量 / 在所属分区中的起始偏移 / 中文标签
class ExamBatchSpec {
  final int id; // 批次序号（本次计划内的合并排序依据）
  final String type; // vocab/reading/cloze/dialogue/bankedCloze/en2zh5/writing
  final int count; // 要求题量
  final int offset; // 在所属题型分区中的起始位置（保证乱序完成时按序合并）
  final String label; // 中文标签（UI 展示）
  const ExamBatchSpec(this.id, this.type, this.count, this.offset, this.label);
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
  // 上一次出题规则：'bank' = 题库选题 | 'ai' = AI 生成
  String lastQuestionSource = 'bank';
  String lastCustomReq = '';
  int lastWordCount = 80;
  int lastQuestionCount = 1;
  ApiConfig apiConfig = ApiConfig();
  bool chatApiIndependent = false;
  ApiConfig chatApiConfig = ApiConfig();
  /// 全局已保存配置库（多配置记忆）
  List<ApiProfile> apiProfiles = [];
  /// 对话助手已保存配置库（多配置记忆）
  List<ApiProfile> chatProfiles = [];
  /// 对话助手当前选中的配置索引（-1 表示未选中/回退到 chatApiConfig）
  int chatProfileIdx = -1;
  bool chatShowReasoning = false;
  bool chatStream = true;
  /// 对话助手"思考模式"：true 时显式开启模型深度思考（Agent 链路不再强制关闭）
  bool chatThinking = true;
  // ===== 墨墨背单词同步 =====
  /// 墨墨开放 API Token（墨墨 App「实验功能 → 开放 API」获取）
  String maimemoToken = '';
  /// 上次同步完成时间戳（毫秒，0 表示从未同步）
  int maimemoLastSync = 0;
  /// 累计成功同步的单词数
  int maimemoSyncedCount = 0;
  /// 同步进行中标志
  bool maimemoSyncing = false;
  /// 最近一次同步错误信息（null 表示成功）
  String? maimemoSyncError;
  /// 最近一次同步拉取到的今日学习进度（可空）
  MaimemoProgress? maimemoProgress;
  /// 剖析模式：'fast' = 快速(纯词典), 'normal' = 正常(词典+AI), 'deep' = 深度(仅AI+语境释义)
  String analysisMode = 'normal';
  /// 深色模式开关
  bool darkMode = false;
  bool fullscreen = false;
  bool powerSavingMode = false; // 省电模式，默认关闭，关闭时支持120帧
  /// 高性能模式：面向低配设备，关闭毛玻璃/半透明等重特效且不锁帧，功能不受影响
  bool highPerformanceMode = false;
  /// 首次启动快速引导是否已完成（false 时启动进入引导向导）
  bool onboardingDone = false;
  /// '' = 未选择（首次启动）, 'desktop' = 桌面端, 'mobile' = 手机端
  String uiMode = '';
  /// UI 风格：'classic' = 经典(不透明), 'glass' = 毛玻璃(半透明模糊)
  String uiStyle = 'classic';
  /// 是否为毛玻璃样式。深色模式是独立第三主题，
  /// 无论 uiStyle 为何都渲染为统一深色主题（不使用毛玻璃模糊），故深色下恒为 false。
  /// 高性能模式下同样恒为 false：关闭全部 BackdropFilter 模糊以获得最佳性能。
  bool get isGlassUI =>
      uiStyle == 'glass' && !darkMode && !highPerformanceMode;
  /// 导航指示器：'underline' = 灰色下划线 | 'pill' = 紫色渐变胶囊
  String navIndicator = 'underline';
  String selectedType = 'translation';
  String selectedLevel = 'zsb';
  int questionStartTime = 0;

  /// 当前页面索引（0 学习 1 答题 2 学习报告 3 查询 4-8 更多功能子页 9 更多功能选择页 10 沉浸考场 11 成绩解析页）
  /// 上提到 AppState，便于对话指令出题后直接切换到答题页
  int page = 0;

  /// 每次加载新题目（题库/AI 生成）时自增，供 AnswerPage 侦测换题并清空作答框
  int questionSeq = 0;

  /// 考试中切页拦截提示事件（UI 层监听后轻提示）
  final ValueNotifier<int> examNavBlockNotifier = ValueNotifier<int>(0);

  void setPage(int p) {
    if (page == p) return;
    // 考场进行中（page==10 且未交卷）锁定导航，防止误退出；
    // 交卷后 page==11 及 exitFullExam 等正规出口（直接赋 page）不受影响
    if (page == 10 && currentExamPaper != null && currentExamResult == null) {
      examNavBlockNotifier.value++;
      return;
    }
    page = p;
    notifyListeners();
  }

  // ===== 全卷模拟考试状态 =====
  /// AI 正在生成全卷
  bool generatingFullExam = false;
  FullExamPaper? currentExamPaper;
  ExamAnswerSheet? currentExamAnswerSheet;
  ExamResult? currentExamResult;
  int examRemainingSec = 0;
  int examStartTs = 0;
  int examCurrentQuestion = 1; // 1-based
  /// 全卷生成后待确认（对话助手处将弹出"是否进入模拟考试"）
  bool examPendingConfirm = false;
  /// 考场内AI逐批生成状态
  bool examGeneratingBatch = false;
  int examGeneratedCount = 0; // 已生成的题目数
  int examTotalQuestions = 76; // 总题数
  String examGeneratingHint = ''; // 当前生成提示
  /// 本轮全卷生成是否已结束（供 UI 展示完成/失败横幅）
  bool examGenerationDone = false;
  /// 重试与兜底后仍失败的批次（UI 提供“重新生成缺失部分”入口）
  final List<ExamBatchSpec> _examFailedBatches = [];
  /// 本轮卷的用户自定义出题要求（重发缺失大题时透传，避免丢失）
  String _examCustomReq = '';
  List<String> get examFailedSectionLabels =>
      _examFailedBatches.map((b) => b.label).toList();
  /// 考试成绩历史摘要（最近 10 条，新→旧，持久化）
  List<ExamHistoryEntry> examHistory = [];

  // 词汇剖析状态
  bool analysisLoading = false;
  List<WordToken> analysisTokens = [];
  /// Agent 通过聊天触发了剖析，答题区监听此标志自动打开剖析视图
  bool chatTriggeredAnalysis = false;

  // 默写状态
  List<WordToken> dictationQueue = [];
  int dictationIdx = 0;
  String dictationMode = 'zh2en';
  /// 默写词库来源：'custom' = 自定义词库 | 'zsb' = 专升本词库 | 'maimemo' = 墨墨词库
  String dictationSource = 'zsb';
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
    chatThinking = Storage.loadChatThinking();
    maimemoToken = Storage.loadMaimemoToken();
    maimemoLastSync = Storage.loadMaimemoLastSync();
    maimemoSyncedCount = Storage.loadMaimemoSyncedCount();
    // 深色模式：直接读取布尔值
    darkMode = Storage.loadDarkMode();
    analysisMode = Storage.loadAnalysisMode();
    fullscreen = Storage.loadFullscreen();
    powerSavingMode = Storage.loadPowerSavingMode();
    highPerformanceMode = Storage.loadHighPerformanceMode();
    AppColors.highPerformance = highPerformanceMode;
    onboardingDone = Storage.loadOnboardingDone();
    uiMode = Storage.loadUiMode();
    uiStyle = Storage.loadUiStyle();
    navIndicator = Storage.loadNavIndicator();
    // 手机端启动即进入沉浸式全屏（隐藏系统状态栏/导航栏），电脑端不受影响
    _applySystemUiMode();
    // 全卷模拟考试：恢复最近一次成绩与历史摘要（供学习报告展示）；
    // 不恢复考试进行中的现场（重启后不自动回考场，避免计时混乱），直接丢弃未交卷状态
    currentExamResult = Storage.loadLastExamResult();
    // 防残留：若上次退出时 AI 批改未完成，重置进行中标志；未完成且未批改过时尝试补批改（未配置 AI 时静默跳过）
    if (currentExamResult != null && currentExamResult!.aiGrading) {
      final r = currentExamResult!;
      final interrupted = !r.aiGraded;
      r.aiGrading = false;
      if (interrupted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => refineExamSubjectiveWithAI());
      }
    }
    examHistory = Storage.loadExamHistory();
    currentExamPaper = null;
    currentExamAnswerSheet = null;
    examPendingConfirm = false;
    // 多配置记忆：加载配置库；旧单配置数据迁移为默认配置
    apiProfiles = Storage.loadApiProfiles();
    chatProfiles = Storage.loadChatProfiles();
    chatProfileIdx = Storage.loadChatProfileIdx();
    if (apiProfiles.isEmpty && apiConfig.ready) {
      apiProfiles = [ApiProfile(name: '默认配置', config: apiConfig)];
      Storage.saveApiProfiles(apiProfiles);
    }
    if (chatProfiles.isEmpty && chatApiConfig.ready) {
      chatProfiles = [ApiProfile(name: '默认配置', config: chatApiConfig)];
      chatProfileIdx = 0;
      Storage.saveChatProfiles(chatProfiles);
      Storage.saveChatProfileIdx(chatProfileIdx);
    } else if (chatProfileIdx < 0 || chatProfileIdx >= chatProfiles.length) {
      chatProfileIdx = chatProfiles.isEmpty ? -1 : 0;
      Storage.saveChatProfileIdx(chatProfileIdx);
    }
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
    // 延迟加载词典，不阻塞启动
    DictService.loadExternalDict();
    DictService.loadZsbDict();
    // 启动时恢复词库数据（生词本/自定义词库/墨墨词库），否则重启后显示为空
    loadWordBook();
    loadCustomWordbook();
    loadMaimemoWordbook();
    notifyListeners();
  }

  /// 对话助手实际生效的配置：独立配置优先取配置库选中项，否则取旧独立配置；未开启独立时用全局配置
  ApiConfig get effectiveChatConfig {
    if (chatApiIndependent) {
      if (chatProfiles.isNotEmpty && chatProfileIdx >= 0 && chatProfileIdx < chatProfiles.length) {
        return chatProfiles[chatProfileIdx].config;
      }
      return chatApiConfig;
    }
    return apiConfig;
  }

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
      case QType.cloze:
        return '阅读下面的短文，从每题所给的四个选项中，选出可以填入空白处的最佳选项。';
      case QType.dialogue:
        return '从方框内的选项中选出能填入空白处的最佳选项（有两项多余）。';
      case QType.bankedCloze:
        return '从所给词中选择正确的词填入空白处（每词限用一次）。';
      case QType.en2zh5:
        return '将下列英文句子翻译成中文。';
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
    // 题库题：清空 AI 生成序列，标记来源为 bank
    generatedQuestions = [];
    generatedQuestionIdx = 0;
    lastQuestionSource = 'bank';
    direction = 'en2zh';
    currentQuestion = q.copyWith(userAnswerIdx: null, userAnswers: []);
    questionStartTime = DateTime.now().millisecondsSinceEpoch;
    questionSeq++;
    applyDirection();
    notifyListeners();
  }

  void loadQuestion(Question q) {
    currentQuestion = q.copyWith(userAnswerIdx: null, userAnswers: []);
    questionStartTime = DateTime.now().millisecondsSinceEpoch;
    questionSeq++;
    applyDirection();
    notifyListeners();
  }

  /// 「换一道」：按上次出题规则换题
  /// - AI 生成题（lastQuestionSource='ai'）：按同参数重新生成
  /// - 题库题（lastQuestionSource='bank'）：从题库随机选一道不同的题（优先同题型）
  Future<void> nextQuestion() async {
    if (lastQuestionSource == 'ai') {
      // AI 生成：按相同参数重新出题
      await generateQuestions(
        count: lastQuestionCount < 1 ? 1 : lastQuestionCount,
        customReq: lastCustomReq,
        wordCount: lastWordCount,
      );
      return;
    }

    // 默认 / Bank：从题库随机抽不同的题（优先同题型，若题库已空则静默返回）
    if (questions.isEmpty) return;
    final curBankIdx = currentQuestion.bankIdx;
    final curType = currentQuestion.type;
    final curDir = direction;

    // 先筛选：同题型且不是当前题
    var sameType = <int>[];
    var allOthers = <int>[];
    for (var i = 0; i < questions.length; i++) {
      if (curBankIdx != null && i == curBankIdx) continue;
      if (questions[i].type == curType) {
        sameType.add(i);
      } else {
        allOthers.add(i);
      }
    }
    final pool = sameType.isNotEmpty ? sameType : (allOthers.isNotEmpty ? allOthers : (curBankIdx != null ? [curBankIdx] : [0]));
    final idx = pool[Random().nextInt(pool.length)];
    final q = questions[idx];

    // 保持来源为 bank，方向沿用当前选择
    lastQuestionSource = 'bank';
    direction = curDir;
    currentQuestion = q.copyWith(userAnswerIdx: null, userAnswers: []);
    questionStartTime = DateTime.now().millisecondsSinceEpoch;
    questionSeq++;
    applyDirection();
    notifyListeners();
  }

  /// 题库抽题：按题型 + 难度池随机抽取 [count] 道不重复题目（供对话指令调用）。
  /// [levels] 为允许的难度值集合（题库仅有 easy/medium/hard）；
  /// 难度无匹配时退化为仅按题型过滤，题型也无匹配时返回空列表。
  List<Question> pickQuestionsFromBank(QType type, List<String> levels, int count) {
    var pool = <int>[];
    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      if (q.type != type) continue;
      if (levels.isNotEmpty && !levels.contains(q.level)) continue;
      pool.add(i);
    }
    if (pool.isEmpty && levels.isNotEmpty) {
      // 难度无匹配，退化为仅按题型过滤
      for (var i = 0; i < questions.length; i++) {
        if (questions[i].type == type) pool.add(i);
      }
    }
    if (pool.isEmpty) return [];
    pool.shuffle(Random());
    final n = min(count, pool.length);
    return List.generate(n, (i) => questions[pool[i]]);
  }

  // ===== 生成题目 =====
  bool generating = false;

  Future<bool> generateQuestions({required int count, required String customReq, int wordCount = 80}) async {
    generating = true;
    notifyListeners();
    // 记录本次 AI 生成参数，供「换一道」重生成时复用
    lastQuestionSource = 'ai';
    lastCustomReq = customReq;
    lastWordCount = wordCount;
    lastQuestionCount = count;
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
    } else {
      systemPrompt = '你是一个英语出题专家。请生成 $count 道$typeName，难度为${levelNames[selectedLevel]}。' +
          '翻译方向：$dirDesc。' +
          (customReq.isNotEmpty ? '额外要求：$customReq' : '') +
          '\n${levelGuides[selectedLevel]}\n\n' +
          '请以JSON数组格式返回，格式如下：\n' +
          '[{"chinese": "中文内容", "english": "英文内容", "knowledge": ["知识点1"]}]\n' +
          '只返回JSON数组，不要其他内容。';
    }

    final maxTokens = (selectedLevel == 'zsb' || selectedType == 'reading') ? 8192 : 4096;
    final reply = await ApiService.callAI(
      [
        {'role': 'user', 'content': '请出题'}
      ],
      systemPrompt,
      config: apiConfig,
      maxTokens: maxTokens,
      extraParams: _noThinkingParams(),
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
      extraParams: _noThinkingParams(),
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
    // 题库题标记为已作答
    _markBankAnswered(q.bankIdx);
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

  List<String> wordsFromText(String text, {bool filterStopWords = true}) {
    if (text.isEmpty) return [];
    // 匹配英文单词，支持：
    //  - 普通单词：hello
    //  - 缩写/所有格：don't, it's（兼容直撇号 ' 和弯撇号 ' '）
    //  - 连字符复合词：well-known, self-esteem
    final re = RegExp(r"[a-z]+(?:[''\-][a-z]+)*");
    final words = re.allMatches(text.toLowerCase()).map((m) => m.group(0)!).toList();
    final seen = <String>{};
    final out = <String>[];
    for (final w in words) {
      if (w.length >= 2 && !seen.contains(w)) {
        if (!filterStopWords) {
          // 记录模式：保留所有单词（含功能词），用户主动点击记录时应收集全部
          seen.add(w);
          out.add(w);
        } else {
          // 剖析模式：仅过滤纯字母停用词，保留复合词
          final isCompound = w.contains('-') || w.contains("'") || w.contains(''') || w.contains(''');
          if (isCompound || !_stopWords.contains(w)) {
            seen.add(w);
            out.add(w);
          }
        }
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
    // 收集所有可能包含英文的字段
    final textParts = <String>[
      q.english,            // 英文原文/答案
      q.correctAnswer,      // 正确答案
      q.text,               // 展示文本（英→中时为英文）
      q.question,           // 选择题题干（英文）
      q.passage,            // 阅读理解短文（英文）
      q.options.join(' '),  // 选择题选项（英文）
      _textAnswerControllerValue, // 用户作答
    ].where((s) => s.isNotEmpty).toList();
    final enText = textParts.join(' ');
    final words = wordsFromText(enText, filterStopWords: false);
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

  /// 关闭模型深度思考的请求参数：覆盖所有已知支持思考的模型。
  /// 仅用于 AI 出题与词汇剖析链路；对话助手由"显示思考过程"开关单独控制。
  Map<String, dynamic> _noThinkingParams() {
    final m = ApiService.realModelName(apiConfig.model).toLowerCase();
    final p = <String, dynamic>{};
    // enable_thinking: false 适用于多数国产模型
    if (m.contains('deepseek') ||
        m.contains('qwen') ||
        m.contains('glm') ||
        m.contains('kimi') ||
        m.contains('moonshot') ||
        m.contains('doubao') ||
        m.contains('hunyuan') ||
        m.contains('baichuan') ||
        m.contains('spark') ||
        m.contains('ernie') ||
        m.contains('wenxin') ||
        m.contains('step') ||
        m.contains('yi-') ||
        m.contains('minimax') ||
        m.contains('grok')) {
      p['enable_thinking'] = false;
    }
    // OpenAI o 系列使用 minimal 完全关闭推理
    if (m.startsWith('o1') || m.startsWith('o3') || m.startsWith('o4')) {
      p['reasoning_effort'] = 'minimal';
    }
    // Claude 系列禁用 extended thinking
    if (m.contains('claude')) {
      p['thinking'] = {'type': 'disabled'};
    }
    // Gemini 系列将 thinking budget 设为 0
    if (m.contains('gemini')) {
      p['thinking_config'] = {'thinking_budget': 0};
    }
    return p;
  }

  Future<void> analyzeWords(String text, {bool force = false}) async {
    if (text.isEmpty || analyzing) return; // 重入保护：剖析进行中不发起第二轮
    
    // 检查API配置（正常/深度模式需要API）
    if ((analysisMode == 'normal' || analysisMode == 'deep') && !apiConfig.ready) {
      analyzing = false;
      notifyListeners();
      throw Exception('API_NOT_CONFIGURED');
    }
    
    analyzing = true;
    analysisTokens = [];
    notifyListeners();
    final cacheKey = '${ApiService.simpleHash('$text|${isZh2En ? 'z' : 'e'}|$analysisMode')}';
    if (!force) {
      final cached = Storage.readAnalysisCache(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        analysisTokens = cached;
        analyzing = false;
        notifyListeners();
        return;
      }
    }
    // 确保本地词库已就绪（内部有一次性标志，已加载时近乎空操作）
    await DictService.loadExternalDict();
    await DictService.loadZsbDict();

    // 本地切词
    var tokens = DictService.fallbackTokens(text, isZh2En);

    if (analysisMode == 'fast') {
      // 快速模式：仅使用本地词库，不调用 AI
      for (var i = 0; i < tokens.length; i++) {
        final t = tokens[i];
        if (t.isMissing && t.type != 'other' && !RegExp(r'^[\s\p{P}]+$', unicode: true).hasMatch(t.text)) {
          tokens[i] = WordToken(text: t.text, type: t.type, word: t.word, pos: t.pos, translation: '暂无释义', other: '');
        }
      }
      analysisTokens = tokens;
      Storage.writeAnalysisCache(cacheKey, tokens);
      analyzing = false;
      notifyListeners();
      return;
    }

    // 第一步：确定待剖析词
    //  - 正常模式：词典优先，仅未命中词送 AI
    //  - 深度模式：跳过词典命中逻辑，全部实词 token 送 AI（虚词/标点/纯符号排除）
    final isDeep = analysisMode == 'deep';
    final missingIdx = <int>[];
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.type == 'other' || RegExp(r'^[\s\p{P}]+$', unicode: true).hasMatch(t.text)) continue;
      if (isDeep) {
        // 深度模式：不论词典是否命中，实词全部进 AI 批次；虚词排除
        final key = t.text.toLowerCase().trim();
        if (_stopWords.contains(key)) continue;
        missingIdx.add(i);
      } else if (t.isMissing) {
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

    // 第二步：缺失词分批并行请求 AI（每批最多 20 词）
    final batchSize = 20;
    final isZh = isZh2En;

    // 深度模式：注入当前题目原文语境，让 AI 判断语境义
    String deepContext() {
      final q = currentQuestion;
      final parts = <String>[];
      if (isZh) {
        if (q.text.isNotEmpty) parts.add(q.text);
        if (q.chinese.isNotEmpty && q.chinese != q.text) parts.add(q.chinese);
      } else {
        if (q.passage.isNotEmpty) parts.add(q.passage);
        if (q.english.isNotEmpty && q.english != q.passage) parts.add(q.english);
        if (q.text.isNotEmpty && q.text != q.english && q.text != q.passage) parts.add(q.text);
      }
      final joined = parts.join('\n');
      return joined.length > 600 ? joined.substring(0, 600) : joined;
    }

    // 构建一批词的剖析 prompt
    String buildPrompt(List<String> batch) {
      if (analysisMode == 'deep') {
        // 深度模式：注入题目语境，要求 AI 给出语境义 + 词典标准释义/其他含义
        // 同时识别词组并返回词组翻译
        final ctx = deepContext();
        final ctxBlock = ctx.isEmpty ? '' : '【当前题目原文语境】\n$ctx\n\n';
        return isZh
            ? '你是中文词汇剖析工具。请结合下方题目语境，分析以下中文词组在该特定语境中的含义，并给出 JSON 数组：\n' +
                ctxBlock +
                '[{"word":"中文词组","pos":"词性","translation":"当前语境中的含义（本句中最贴切的英文表达）","contextTranslation":"词典标准释义/其他含义","other":"用法剖析:包含常见搭配、例句或近义词(30字内)"}]\n' +
                '要求：translation 必须结合语境给出该词在当前句子中的实际含义；contextTranslation 给出词典中的标准释义及其他常见含义；other 给出用法信息。\n' +
                '词组列表：${batch.join('、')}\n只返回JSON数组，不要其他内容。'
            : '你是英语词汇剖析工具。请结合下方题目语境，分析以下单词/词组在该特定语境中的含义，并给出 JSON 数组：\n' +
                ctxBlock +
                '[{"word":"单词/词组","pos":"词性(如n./v./adj./adv./prep.)","translation":"当前语境中的含义（本句中最贴切的中文释义）","contextTranslation":"词典标准释义/其他含义","other":"用法剖析:包含常见搭配、例句、近义词或易混淆点(30字内)","phrases":[{"text":"词组原文(如 points out)","translation":"词组整体翻译","wordTranslations":["指出","表明"]}]}]\n' +
                '要求：\n' +
                '1. translation 必须结合语境给出该词在当前句子中的实际含义；\n' +
                '2. contextTranslation 给出词典中的标准释义及其他常见含义；\n' +
                '3. other 给出用法信息；\n' +
                '4. phrases 字段：如果该单词是某个固定词组/短语的一部分（如 "points out"、"negative effects"），请在 phrases 数组中列出该词组及其翻译，并在 wordTranslations 中按顺序给出词组中每个单词的独立中文释义；如果不是词组的一部分，phrases 留空数组 []。\n' +
                '单词列表：${batch.join('、')}\n只返回JSON数组，不要其他内容。';
      } else {
        // 正常模式：标准剖析
        return isZh
            ? '你是中文词汇剖析工具。快速给出以下中文词组的 JSON 数组，不要推理过程：\n' +
                '[{"word":"中文词组","pos":"词性(如名词/动词/形容词/副词/介词)","translation":"对应英文(简短,15字内)","other":"用法剖析:包含常见搭配、例句或近义词(30字内)"}]\n' +
                '要求：translation 给出对应的英文表达；other 必须给出实际用法信息，不能为空。\n' +
                '词组列表：${batch.join('、')}\n只返回JSON数组，不要其他内容。'
            : '你是英语词汇剖析工具。快速给出以下单词/词组的 JSON 数组（不是简单翻译），不要推理过程：\n' +
                '[{"word":"单词","pos":"词性(如n./v./adj./adv./prep.)","translation":"核心中文释义(简短,10字内)","other":"用法剖析:包含常见搭配、例句、近义词或易混淆点(30字内)"}]\n' +
                '要求：translation 只给最核心的1-2个中文释义；other 必须给出实际用法信息（如搭配、例句、近义词辨析等），不能为空。\n' +
                '单词列表：${batch.join('、')}\n只返回JSON数组，不要其他内容。';
      }
    }

    // 剖析链路关闭模型深度思考：按实际模型名添加非推理参数，未知模型不添加以避免 400
    // 请求一批词；仅当返回非空且长度接近输出上限（疑似截断）且词数 > 5 时，
    // 对半拆分各重试一次（仅重试一次）；拒答/空响应等其他失败不重试
    Future<List<WordToken>> requestBatch(List<String> batch, {bool retried = false}) async {
      final reply = await ApiService.callAI(
        [{'role': 'user', 'content': isZh ? '请剖析这些中文词组的用法' : '请剖析这些单词的用法'}],
        buildPrompt(batch),
        config: apiConfig,
        maxTokens: 4096,
        extraParams: _noThinkingParams(),
      );
      List<Map<String, dynamic>>? list;
      if (reply != null && reply.isNotEmpty) {
        list = ApiService.extractJsonArray(reply);
      }
      final looksTruncated = reply != null && reply.length > 2048; // 接近 maxTokens 输出预算
      if (list == null && !retried && batch.length > 5 && looksTruncated) {
        final mid = batch.length ~/ 2;
        final halves = await Future.wait([
          requestBatch(batch.sublist(0, mid), retried: true),
          requestBatch(batch.sublist(mid), retried: true),
        ]);
        return [...halves[0], ...halves[1]];
      }
      final result = <WordToken>[];
      if (list != null) {
        for (final e in list) {
          final w = ((e['word'] ?? '') as String).toLowerCase().trim();
          if (w.isEmpty) continue;
          // 解析 phrases 字段
          final phrasesList = <PhraseInfo>[];
          final phrasesJson = e['phrases'];
          if (phrasesJson is List) {
            for (final p in phrasesJson) {
              if (p is Map<String, dynamic>) {
                final pt = (p['text'] ?? '').toString().trim();
                final ptrans = (p['translation'] ?? '').toString().trim();
                final wordTrans = (p['wordTranslations'] as List?)
                    ?.map((w) => w.toString().trim())
                    .where((w) => w.isNotEmpty)
                    .toList() ?? const [];
                if (pt.isNotEmpty && ptrans.isNotEmpty) {
                  phrasesList.add(PhraseInfo(text: pt, translation: ptrans, wordTranslations: wordTrans));
                }
              }
            }
          }
          result.add(WordToken(
            text: (e['word'] ?? '') as String,
            type: 'word',
            word: (e['word'] ?? '') as String,
            pos: (e['pos'] ?? '') as String,
            translation: (e['translation'] ?? '') as String,
            other: (e['other'] ?? '') as String,
            contextTranslation: (e['contextTranslation'] ?? '') as String,
            phrases: phrasesList,
          ));
        }
      }
      return result;
    }

    // 把一批 AI 结果回填到 tokens 对应缺失索引，并立即刷新 UI（增量渲染）
    void applyBatchResult(List<int> idxList, List<WordToken> results) {
      final wordMap = <String, WordToken>{};
      for (final r in results) {
        wordMap[r.word.toLowerCase().trim()] = r;
      }
      for (final i in idxList) {
        final key = tokens[i].text.toLowerCase().trim();
        final hit = wordMap[key];
        if (hit != null) {
          tokens[i] = WordToken(text: tokens[i].text, type: tokens[i].type, word: tokens[i].text, pos: hit.pos, translation: hit.translation, other: hit.other, contextTranslation: hit.contextTranslation, phrases: hit.phrases);
        } else {
          tokens[i] = WordToken(text: tokens[i].text, type: tokens[i].type, word: tokens[i].text, pos: tokens[i].pos, translation: '暂无释义');
        }
      }
      analysisTokens = tokens;
      notifyListeners();
    }

    // 按批切分缺失词索引，各批全并行；每批完成立即增量提交，Future.wait 仅用于等待全部收尾
    final batchFutures = <Future<void>>[];
    for (var i = 0; i < missingIdx.length; i += batchSize) {
      final end = (i + batchSize > missingIdx.length) ? missingIdx.length : i + batchSize;
      final idxList = missingIdx.sublist(i, end);
      final batch = idxList.map((idx) => tokens[idx].text.toLowerCase().trim()).where((t) => t.isNotEmpty).toList();
      if (batch.isEmpty) continue;
      batchFutures.add(requestBatch(batch).then((results) {
        applyBatchResult(idxList, results);
      }).catchError((_) {
        // 单批失败不影响其他批次，失败词标记为暂无释义
        applyBatchResult(idxList, const <WordToken>[]);
      }));
    }
    await Future.wait(batchFutures);

    // 收尾：本地词库兜底仍为空释义的 token，再写缓存（缓存必须完整）
    // 深度模式完全不用词典，跳过兜底
    if (!isDeep) _backfillFromDict(tokens);

    // 深度模式：标记词组 token（将 AI 返回的 phrases 信息映射回原文 token）
    if (isDeep) _markPhraseTokens(tokens, text);

    analysisTokens = tokens;
    Storage.writeAnalysisCache(cacheKey, tokens);
    analyzing = false;
    notifyListeners();
  }

  /// 深度模式下，将 AI 返回的 phrases 信息映射回原文 token，
  /// 标记每个 token 所属的词组（phraseGroup），以便 UI 渲染红色下划线和优先展示词组翻译。
  void _markPhraseTokens(List<WordToken> tokens, String originalText) {
    // 收集所有 token 中携带的 phrases 信息，构建 phraseText -> phraseInfo 映射
    final phraseMap = <String, PhraseInfo>{};
    for (final t in tokens) {
      for (final p in t.phrases) {
        phraseMap[p.text.toLowerCase()] = p;
      }
    }
    if (phraseMap.isEmpty) return;

    // 将原文按单词拆分，记录每个单词 token 的索引范围
    final wordTokens = <_WordSpan>[];
    final re = RegExp(r"[A-Za-z']+");
    for (final m in re.allMatches(originalText)) {
      wordTokens.add(_WordSpan(text: m.group(0)!, start: m.start, end: m.end));
    }

    // 对每个 phrase，尝试在原文中匹配连续单词
    for (final entry in phraseMap.entries) {
      final phraseText = entry.key;
      final phraseInfo = entry.value;
      final phraseWords = phraseText.toLowerCase().split(RegExp(r'\s+'));
      if (phraseWords.length < 2) continue; // 至少两个单词才算词组

      // 在 wordTokens 中滑动窗口匹配
      for (var i = 0; i <= wordTokens.length - phraseWords.length; i++) {
        var match = true;
        for (var j = 0; j < phraseWords.length; j++) {
          if (wordTokens[i + j].text.toLowerCase() != phraseWords[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          // 找到匹配，标记这些 token 的 phraseGroup
          for (var j = 0; j < phraseWords.length; j++) {
            final idx = _findTokenIndex(tokens, wordTokens[i + j].text);
            if (idx >= 0 && tokens[idx].phraseGroup.isEmpty) {
              tokens[idx] = tokens[idx].copyWithPhraseGroup(phraseInfo.text);
            }
          }
          break; // 每个词组只标记第一次出现
        }
      }
    }
  }

  /// 在 tokens 中找到匹配指定单词文本的索引
  int _findTokenIndex(List<WordToken> tokens, String word) {
    final lower = word.toLowerCase();
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].text.toLowerCase() == lower && tokens[i].type != 'other') {
        return i;
      }
    }
    return -1;
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
    String? imageData,
    void Function(String chunk)? onReasoning,
    void Function(String chunk)? onDelta,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || chatSending) return '';
    // 出题指令（如“出一道专升本翻译题”）本地解析处理，不占用对话 API
    if (await _tryHandleQuestionCommand(trimmed)) return '';
    chatSending = true;
    notifyListeners();
    final cfg = effectiveChatConfig;
    final hasImage = imageData != null && imageData.isNotEmpty;
    final hasVision = hasImage && cfg.vision;
    // 模型无图形能力时图片不发送（仅保留黑色占位），有图形能力时以多模态发送
    chatHistory.add(ChatMessage(
      role: 'user',
      content: trimmed,
      imageData: hasVision ? imageData : null,
      imageDark: hasImage && !hasVision,
    ));
    _notifyChatUpdate();

    // 优先尝试 Agent（Function Calling）路径
    // 注意：_runAgentLoop 内部会创建占位消息并实时更新，成功后占位消息即为最终回复
    final agentResult = await _runAgentLoop(trimmed, imageData: imageData);
    if (agentResult != null) {
      // Agent 成功：占位消息已更新为最终回复，无需再添加
      chatSending = false;
      notifyListeners();
      _notifyChatUpdate();
      return agentResult.reply;
    }

    // 回退：原对话流程（流式 / 非流式）
    final q = currentQuestion;
    final dirDesc = isZh2En ? '中译英' : '英译中';
    final userAnswer = currentUserAnswer;
    final prompt = '你是一个专业的英语学习助手，可以回答任何关于英语的问题（语法、词汇、翻译、写作、阅读理解等）。\n\n' +
        '【当前题目信息】（仅供参考，用户可能问其他英语问题）\n' +
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
        .map((m) => {
              'role': m.role == 'ai' ? 'assistant' : 'user',
              'content': (m.role == 'user' && m.imageData != null && m.imageData!.isNotEmpty)
                  ? ApiService.buildContent(m.content, m.imageData)
                  : m.content,
            })
        .toList();

    String reply = '';
    final showReasoning = chatShowReasoning;
    final thinkingParams = chatThinking
        ? ApiService.thinkingParams(effectiveChatConfig.model)
        : ApiService.noThinkingParams(effectiveChatConfig.model);
    if (chatStream && effectiveChatConfig.ready) {
      final msg = ChatMessage(role: 'ai', content: '', showReasoning: showReasoning, reasoning: '');
      chatHistory.add(msg);
      _notifyChatUpdate();
      String rawReasoning = '';
      String fullContent = '';
      reply = await ApiService.streamChat(
        history,
        prompt,
        config: effectiveChatConfig,
        extraParams: thinkingParams,
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
      final r = await ApiService.callAI(history, prompt,
          config: effectiveChatConfig, extraParams: thinkingParams);
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

  // ===== 对话出题指令（“动手功能”：对话中直接要求出题） =====

  /// 出题指令触发词：必须含明确的出题意图动词（后接数量/量词），避免误伤普通问答
  /// （如“这道题是 AI 生成的吗？”“出题失败了怎么办？”）
  static final RegExp _cmdTriggerRe = RegExp(
      r'给我出|帮我出|考考我|来[一二两三几\d]*[道个份篇套]|出[一二两三几\d]*[道个份篇套]|做[一二两三几\d]+道|生成[一二两三几\d]*[道个份篇套]|模拟[卷题]');

  /// 疑问/求助句式：命中则视为普通问答，不作为出题指令
  static final RegExp _cmdQuestionRe = RegExp(r'[吗么？?]|怎么|为什么|如何|失败');

  /// 题型关键词 → selectedType 映射（按优先级排列，套卷/混合优先于单题型）
  static final List<(RegExp, String)> _cmdTypeMap = [
    (RegExp(r'套卷|模拟卷|混合|综合|模拟'), 'mixed'),
    (RegExp(r'阅读'), 'reading'),
    (RegExp(r'语法'), 'grammar'),
    (RegExp(r'选择|单选'), 'choice'),
    (RegExp(r'写作|作文'), 'writing'),
    (RegExp(r'翻译'), 'translation'),
  ];

  /// 难度关键词 → selectedLevel 映射（未提及时沿用当前 selectedLevel）
  static final List<(RegExp, String)> _cmdLevelMap = [
    (RegExp(r'专升本'), 'zsb'),
    (RegExp(r'四级|CET-?4|cet-?4'), 'cet4'),
    (RegExp(r'简单|容易|基础'), 'easy'),
    (RegExp(r'困难|较难|难'), 'hard'),
    (RegExp(r'中等|普通'), 'medium'),
  ];

  /// 数量：中文数字/多位阿拉伯数字/“几” + 量词（道/个/份/篇/套）；“几”视为 3
  static final RegExp _cmdCountRe = RegExp(r'([一两二三四五六七八九]+|\d+|几)\s*[道个份篇套]');

  static const Map<String, int> _cmdNumMap = {
    '一': 1, '两': 2, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '几': 3,
  };

  /// 解析出题指令；不构成指令时返回 null（走原有对话流程）
  ({String type, String? level, int count})? _parseQuestionCommand(String text) {
    // 疑问/求助句式（含“吗/？”“怎么”“失败”等）一律视为普通问答
    if (_cmdQuestionRe.hasMatch(text)) return null;
    if (!_cmdTriggerRe.hasMatch(text)) return null;
    String? type;
    for (final (re, t) in _cmdTypeMap) {
      if (re.hasMatch(text)) {
        type = t;
        break;
      }
    }
    // “题”字兜底：有出题意图但未指明题型时沿用当前题型；完全无“题/卷”字样则不视为出题指令
    if (type == null) {
      if (!text.contains('题') && !text.contains('卷')) return null;
      type = selectedType;
    }
    String? level;
    for (final (re, l) in _cmdLevelMap) {
      if (re.hasMatch(text)) {
        level = l;
        break;
      }
    }
    var count = 1;
    final m = _cmdCountRe.firstMatch(text);
    if (m != null) {
      final c = m.group(1)!;
      if (c == '几') {
        count = 3;
      } else {
        // 多位阿拉伯数字直接解析；单个中文数字查表；其余兜底 1
        count = int.tryParse(c) ?? _cmdNumMap[c] ?? 1;
      }
    }
    if (count < 1) count = 1;
    if (count > 10) count = 10;
    return (type: type, level: level, count: count);
  }

  /// 尝试以出题指令处理用户消息；命中返回 true，否则返回 false 由原对话流程接手
  Future<bool> _tryHandleQuestionCommand(String text) async {
    // 互斥：学习页/其他入口正在 AI 出题时不受理新指令，避免竞争 generatedQuestions
    if (generating) return false;
    final cmd = _parseQuestionCommand(text);
    if (cmd == null) return false;

    final type = cmd.type;
    final level = cmd.level ?? selectedLevel;
    final count = cmd.count;
    final typeLabel = type == 'mixed' ? '综合套卷' : qTypeName(qTypeFrom(type));
    final levelLabel = levelName(level);

    // 记录用户指令到对话历史
    chatHistory.add(ChatMessage(role: 'user', content: text));
    _notifyChatUpdate();

    // 分支零：综合全卷（76题/7题型）→ 走沉浸考场流程，不进入普通答题区
    if (type == 'mixed' || text.contains('全卷') || text.contains('专升本') && (text.contains('综合') || text.contains('76') || text.contains('套卷') || text.contains('模拟考试') || text.contains('考场'))) {
      selectedLevel = level;
      // 上一轮全卷仍在生成中：提示用户等待，避免重入导致新卷卡死在加载屏
      if (examGeneratingBatch) {
        _addChatAiReply('上一份全卷仍在生成中，请等它完成（或等失败横幅出现）后再次发起。');
        notifyListeners();
        return true;
      }
      if (!apiConfig.ready) {
        _addChatAiReply('专升本【综合模拟全卷】需要调用 AI 出题接口，但当前尚未完成 AI 配置。请在 设置 → AI 接口 中配置后重试。');
        notifyListeners();
        return true;
      }
      generatingFullExam = true;
      chatSending = true;
      notifyListeners();
      _addChatAiReply('正在为你生成一套完整的【专升本综合模拟全卷】（7大题型，76题，满分150分，考试时间120分钟）。出题时间较长（约40s~2min），请耐心等待…');
      final ok = await generateFullExam(customReq: '用户自定义要求：$text');
      generatingFullExam = false;
      chatSending = false;
      if (ok && currentExamPaper != null) {
        // 生成成功已置 examPendingConfirm=true，主界面监听到后弹出确认弹窗
        _addChatAiReply('✅ 全卷已生成完成！共 ${currentExamPaper!.totalQuestions} 题。请确认进入考场（弹窗已为你准备好）。');
      } else {
        _addChatAiReply('抱歉，全卷生成失败（AI 服务无响应或返回格式有误）。请稍后重试，或检查 API 接口是否可用。');
      }
      notifyListeners();
      return true;
    }

    // 分支一：翻译题优先从题库抽取（题库仅含 translation 题）
    if (type == 'translation') {
      // 题库难度值只有 easy/medium/hard：cet4 对标 medium+hard 池，zsb 对标 medium 池
      final bankLevels = switch (level) {
        'cet4' => const ['medium', 'hard'],
        'zsb' => const ['medium'],
        _ => [level],
      };
      final picked = pickQuestionsFromBank(QType.translation, bankLevels, count);
      if (picked.isNotEmpty) {
        selectedType = 'translation';
        selectedLevel = level;
        generatedQuestions = picked;
        generatedQuestionIdx = 0;
        loadGeneratedQuestion();
        _gotoAnswerPage();
        _addChatAiReply('已为你从题库抽取 ${picked.length} 道【$levelLabel 翻译题】，已放入答题区'
            '${picked.length > 1 ? '，点击“换一道”可做下一道' : ''}。开始作答吧，完成后点击“提交答案”我来批改！');
        return true;
      }
      // 题库无匹配时继续走下方 AI 生成
    }

    // 分支二：AI 生成（其他题型 / 题库无匹配 / 套卷）
    selectedType = type;
    selectedLevel = level;
    if (!apiConfig.ready) {
      _addChatAiReply('题库中暂无匹配的【$levelLabel $typeLabel】，且 AI 出题服务尚未配置，无法为你生成新题。请先在 设置 → AI 接口 中完成配置后再试。');
      return true;
    }
    chatSending = true;
    notifyListeners();
    _addChatAiReply('正在为你生成 $count 道【$levelLabel $typeLabel】，请稍候…');
    final ok = await generateQuestions(count: count, customReq: '');
    chatSending = false;
    if (ok) {
      _gotoAnswerPage();
      _addChatAiReply('已为你准备好 ${generatedQuestions.length} 道【$levelLabel $typeLabel】，已放入答题区'
          '${generatedQuestions.length > 1 ? '，点击“换一道”可做下一道' : ''}。加油！');
    } else {
      _addChatAiReply('抱歉，【$levelLabel $typeLabel】生成失败（AI 服务无响应或返回格式有误），请检查 API 配置后重试。');
    }
    notifyListeners();
    return true;
  }

  /// 出题成功后切换到答题页并重置作答内容
  void _gotoAnswerPage() {
    textAnswerValue = '';
    page = 1;
    notifyListeners();
  }

  /// 向对话历史追加一条助手回复并触发 UI 更新
  void _addChatAiReply(String content) {
    chatHistory.add(ChatMessage(role: 'ai', content: content));
    notifyListeners();
    _notifyChatUpdate();
  }

  // ===== Agent（Function Calling）=====

  /// 执行单个工具调用，返回结果给 AI。所有工具都在这里分发。
  Future<ToolExecResult> executeTool(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'generate_questions':
          return await _toolGenerateQuestions(args);
        case 'generate_full_exam':
          return await _toolGenerateFullExam(args);
        case 'lookup_word':
          return _toolLookupWord(args);
        case 'analyze_words':
          return await _toolAnalyzeWords(args);
        case 'get_current_question':
          return _toolGetCurrentQuestion();
        case 'next_question':
          return _toolNextQuestion();
        case 'toggle_favorite':
          return _toolToggleFavorite();
        case 'get_progress':
          return _toolGetProgress();
        default:
          return ToolExecResult(content: '未知工具：$name', ok: false);
      }
    } catch (e) {
      return ToolExecResult(content: '工具执行异常：$e', ok: false);
    }
  }

  Future<ToolExecResult> _toolGenerateQuestions(Map<String, dynamic> args) async {
    final type = (args['type'] as String?) ?? 'translation';
    final level = (args['level'] as String?) ?? 'zsb';
    var count = (args['count'] as num?)?.toInt() ?? 1;
    if (count < 1) count = 1;
    if (count > 10) count = 10;
    final useBank = (args['useBank'] as bool?) ?? true;
    if (generating) {
      return const ToolExecResult(content: '正在生成中，请稍候', ok: false);
    }
    // 翻译题优先走题库（除非用户明确说不要题库）
    if (type == 'translation' && useBank) {
      final bankLevels = switch (level) {
        'cet4' => const ['medium', 'hard'],
        'zsb' => const ['medium'],
        _ => [level],
      };
      final picked = pickQuestionsFromBank(QType.translation, bankLevels, count);
      if (picked.isNotEmpty) {
        selectedType = type;
        selectedLevel = level;
        generatedQuestions = picked;
        generatedQuestionIdx = 0;
        loadGeneratedQuestion();
        _gotoAnswerPage();
        return ToolExecResult(
          content: '{"ok":true,"count":${picked.length},"type":"$type","level":"$level","source":"bank"}',
          ok: true,
          actionLabel: '已从题库抽取 ${picked.length} 道${levelName(level)}翻译题',
        );
      }
    }
    if (!apiConfig.ready) {
      return const ToolExecResult(content: '{"ok":false,"reason":"api_not_configured"}', ok: false);
    }
    selectedType = type;
    selectedLevel = level;
    final ok = await generateQuestions(count: count, customReq: '');
    if (ok) {
      _gotoAnswerPage();
      return ToolExecResult(
        content: '{"ok":true,"count":${generatedQuestions.length},"type":"$type","level":"$level","source":"ai"}',
        ok: true,
        actionLabel: '已生成 ${generatedQuestions.length} 道${levelName(level)}${qTypeName(qTypeFrom(type))}',
      );
    }
    return const ToolExecResult(content: '{"ok":false,"reason":"generate_failed"}', ok: false);
  }

  Future<ToolExecResult> _toolGenerateFullExam(Map<String, dynamic> args) async {
    final level = (args['level'] as String?) ?? 'zsb';
    if (examGeneratingBatch) {
      return const ToolExecResult(content: '{"ok":false,"reason":"already_generating"}', ok: false);
    }
    if (!apiConfig.ready) {
      return const ToolExecResult(content: '{"ok":false,"reason":"api_not_configured"}', ok: false);
    }
    selectedLevel = level;
    generatingFullExam = true;
    final ok = await generateFullExam(customReq: '');
    generatingFullExam = false;
    if (ok && currentExamPaper != null) {
      return ToolExecResult(
        content: '{"ok":true,"totalQuestions":${currentExamPaper!.totalQuestions}}',
        ok: true,
        actionLabel: '已生成全卷（${currentExamPaper!.totalQuestions}题）',
      );
    }
    return const ToolExecResult(content: '{"ok":false,"reason":"generate_failed"}', ok: false);
  }

  ToolExecResult _toolLookupWord(Map<String, dynamic> args) {
    final word = ((args['word'] as String?) ?? '').trim().toLowerCase();
    if (word.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"empty_word"}', ok: false);
    }
    final e = DictService.lookup(word);
    if (e == null) {
      return ToolExecResult(
        content: '{"ok":false,"word":"$word","reason":"not_found"}',
        ok: false,
        actionLabel: '词典未收录：$word',
      );
    }
    return ToolExecResult(
      content: '{"ok":true,"word":"$word","pos":"${e.pos}","translation":"${e.translation}","phonetic":"${e.phonetic}","other":"${e.other}"}',
      ok: true,
      actionLabel: '查询：$word',
    );
  }

  Future<ToolExecResult> _toolAnalyzeWords(Map<String, dynamic> args) async {
    final text = (args['text'] as String?) ?? '';
    final mode = (args['mode'] as String?) ?? 'normal';
    if (text.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"empty_text"}', ok: false);
    }
    if ((mode == 'normal' || mode == 'deep') && !apiConfig.ready) {
      return const ToolExecResult(content: '{"ok":false,"reason":"api_not_configured"}', ok: false);
    }
    analysisMode = mode;
    await analyzeWords(text);
    chatTriggeredAnalysis = true;
    notifyListeners();
    final tokenCount = analysisTokens.where((t) => t.type == 'word' || t.type == 'phrase').length;
    return ToolExecResult(
      content: '{"ok":true,"mode":"$mode","wordCount":$tokenCount}',
      ok: true,
      actionLabel: '已剖析 $tokenCount 个单词（${mode == 'fast' ? '快速' : mode == 'normal' ? '正常' : '深度'}）',
    );
  }

  ToolExecResult _toolGetCurrentQuestion() {
    final q = currentQuestion;
    final userAnswer = currentUserAnswer;
    return ToolExecResult(
      content: '{"ok":true,"type":"${q.type.name}","level":"${q.level}","text":${jsonEncode(q.text)},"chinese":${jsonEncode(q.chinese)},"english":${jsonEncode(q.english)},"correctAnswer":${jsonEncode(q.correctAnswer)},"userAnswer":${jsonEncode(userAnswer)},"knowledge":${jsonEncode(q.knowledge)}}',
      ok: true,
      actionLabel: '读取当前题目',
    );
  }

  ToolExecResult _toolNextQuestion() {
    if (generatedQuestions.length <= 1) {
      return const ToolExecResult(content: '{"ok":false,"reason":"no_more_questions"}', ok: false);
    }
    nextQuestion();
    textAnswerValue = '';
    return ToolExecResult(
      content: '{"ok":true,"index":$generatedQuestionIdx,"total":${generatedQuestions.length}}',
      ok: true,
      actionLabel: '已切换下一题',
    );
  }

  ToolExecResult _toolToggleFavorite() {
    final wasFav = isCurrentFavorite;
    toggleFavorite();
    return ToolExecResult(
      content: '{"ok":true,"favorited":${!wasFav}}',
      ok: true,
      actionLabel: wasFav ? '已取消收藏' : '已收藏',
    );
  }

  ToolExecResult _toolGetProgress() {
    final total = wrongQuestions.fold<int>(0, (s, w) => s + w.wrongCount);
    return ToolExecResult(
      content: '{"ok":true,"favorites":${favorites.length},"wrongCount":${wrongQuestions.length},"wrongTotal":$total}',
      ok: true,
      actionLabel: '读取学习进度',
    );
  }

  /// Agent 循环：发送用户消息 → AI 返回 tool_calls → 执行工具 → 把结果喂回 AI → 直到 AI 返回纯文本
  /// 返回最终回复内容；如果 agent 不可用或失败，返回 null，调用方回退到原流程。
  /// 带 UI 实时反馈：占位消息显示“正在思考→正在出题→流式输出回复”。
  Future<({String reply, List<String> actions})?> _runAgentLoop(String text, {String? imageData}) async {
    final cfg = effectiveChatConfig;
    if (!cfg.ready) return null;
    if (!AgentService.modelSupportsTools(cfg.model)) return null;
  
    // 创建占位 AI 消息，实时更新（让用户看到 Agent 在做什么）
    final placeholder = ChatMessage(role: 'ai', content: '正在思考…', showReasoning: true, reasoning: '');
    chatHistory.add(placeholder);
    _notifyChatUpdate();
  
    final tools = AgentService.toolDefinitions();
    final actions = <String>[];
  
    // 动态 system prompt：注入当前题目上下文
    final q = currentQuestion;
    final dirDesc = isZh2En ? '中译英' : '英译中';
    final sysPrompt = AgentService.buildSystemPrompt(
      qType: qTypeName(q.type),
      qLevel: levelName(q.level),
      qText: q.text,
      dirDesc: dirDesc,
    );
  
    // 构建 messages：从 chatHistory 读历史，但排除最后一条（刚加的 user 消息，避免重复）
    // R4 请求体瘦身：只保留最近约 16 条历史，较早消息剥离 imageData
    final historyLen = chatHistory.length;
    const maxHistory = 16;
    final allHistory = chatHistory
        .getRange(0, historyLen - 1)
        .where((m) => m.role != 'system')
        .toList();
    final trimmedStart = allHistory.length > maxHistory ? allHistory.length - maxHistory : 0;
    final baseHistory = <Map<String, dynamic>>[];
    for (var i = trimmedStart; i < allHistory.length; i++) {
      final m = allHistory[i];
      // 较早的消息（非最后4条）剥离 imageData，替换为纯文本 + 占位
      final isRecent = i >= allHistory.length - 4;
      if (m.role == 'user' && !isRecent && m.imageData != null && m.imageData!.isNotEmpty) {
        baseHistory.add({'role': 'user', 'content': '[图片] ${m.content}'});
      } else if (m.role == 'user' && isRecent && m.imageData != null && m.imageData!.isNotEmpty) {
        baseHistory.add({'role': 'user', 'content': ApiService.buildContent(m.content, m.imageData)});
      } else {
        baseHistory.add({'role': m.role == 'ai' ? 'assistant' : 'user', 'content': m.content});
      }
    }
    // 追加当前用户消息
    baseHistory.add({
      'role': 'user',
      'content': imageData != null && imageData.isNotEmpty && cfg.vision
          ? ApiService.buildContent(text, imageData)
          : text,
    });
  
    final messages = List<Map<String, dynamic>>.from(baseHistory);
  
    try {
      // 最多循环 5 轮（防止死循环）
      for (var round = 0; round < 5; round++) {
        // 更新占位消息：思考中不显示工具步骤文本
        placeholder.content = '正在思考…';
        _notifyChatUpdate();
  
        // R1: 所有轮次全部用流式调用（streamChatWithTools 现在返回 AIResponse 含 tool_calls）
        // R2: 决策轮关闭思考以加速
        String rawReasoning = '';
        String streamContent = '';
        final resp = await ApiService.streamChatWithTools(
          messages,
          sysPrompt,
          config: cfg,
          tools: tools,
          // 思考模式开关：开启时显式请求思考过程，关闭时强制关闭以加速
          extraParams: chatThinking
              ? ApiService.thinkingParams(cfg.model)
              : ApiService.noThinkingParams(cfg.model),
          onReasoning: (chunk) {
            rawReasoning += chunk;
            placeholder.reasoning = rawReasoning;
            _notifyChatUpdate();
          },
          onDelta: (chunk) {
            streamContent += chunk;
            placeholder.content = streamContent;
            _notifyChatUpdate();
          },
        );
  
        if (resp.content == null && resp.toolCalls.isEmpty) {
          // API 失败，移除占位消息，回退
          chatHistory.remove(placeholder);
          _notifyChatUpdate();
          return null;
        }
        // 显示思考过程
        if (resp.reasoning.isNotEmpty) {
          placeholder.reasoning = resp.reasoning;
          _notifyChatUpdate();
        }
        if (resp.toolCalls.isEmpty) {
          // 纯文本回复，直接赋最终文本（R3: 删除假流式）
          final reply = resp.content ?? '';
          await _simulateStreamOutput(placeholder, reply, actions);
          return (reply: reply, actions: actions);
        }
        // 有工具调用：把 assistant 的 tool_calls 消息加入历史
        messages.add({
          'role': 'assistant',
          'content': resp.content,
          'tool_calls': resp.toolCalls
              .map((tc) => {
                    'id': tc.id,
                    'type': 'function',
                    'function': {'name': tc.name, 'arguments': tc.arguments},
                  })
              .toList(),
        });
        // 执行每个工具调用，实时更新占位消息
        for (final tc in resp.toolCalls) {
          final args = AgentService.parseArgs(tc.arguments);
          // 工具执行前：在气泡上方添加"调用工具"步骤卡片（运行中）
          final runningLabel = _toolRunningLabel(tc.name, args);
          final step = ToolStep(label: runningLabel.isEmpty ? _toolDefaultLabel(tc.name) : runningLabel);
          placeholder.toolSteps.add(step);
          _notifyChatUpdate();
          final result = await executeTool(tc.name, args);
          // 工具执行后：更新该步骤状态与文案
          step.running = false;
          if (result.ok && result.actionLabel.isNotEmpty) {
            step.label = result.actionLabel;
            step.done = true;
          } else if (result.ok) {
            step.done = true;
          } else {
            step.failed = true;
            if (result.actionLabel.isNotEmpty) step.label = result.actionLabel;
          }
          if (result.actionLabel.isNotEmpty) {
            actions.add(result.actionLabel);
          }
          _notifyChatUpdate();
          messages.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'name': tc.name,
            'content': result.content,
          });
        }
      }
      // 超过最大轮次，用动作兜底
      final reply = actions.isEmpty ? '操作已完成。' : '已完成：${actions.join("、")}。';
      await _simulateStreamOutput(placeholder, reply, actions);
      return (reply: reply, actions: actions);
    } catch (e) {
      // 异常时移除占位消息，回退
      chatHistory.remove(placeholder);
      _notifyChatUpdate();
      return null;
    }
  }

  /// 工具执行中的进度文案
  String _toolRunningLabel(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'generate_questions':
        final type = (args['type'] as String?) ?? 'translation';
        final count = (args['count'] as num?)?.toInt() ?? 1;
        return '正在生成 $count 道${qTypeName(qTypeFrom(type))}';
      case 'generate_full_exam':
        return '正在生成全卷（约1-2分钟）';
      case 'lookup_word':
        final w = (args['word'] as String?) ?? '';
        return '正在查询 "$w"';
      case 'analyze_words':
        return '正在剖析词汇';
      case 'next_question':
        return '正在切换题目';
      case 'toggle_favorite':
        return '正在收藏';
      case 'get_current_question':
        return '正在读取题目';
      case 'get_progress':
        return '正在读取进度';
      default:
        return '正在处理';
    }
  }

  /// 工具的默认展示标签（无参数时兜底）
  String _toolDefaultLabel(String name) {
    switch (name) {
      case 'generate_questions':
        return '生成练习题';
      case 'generate_full_exam':
        return '生成综合模拟全卷';
      case 'lookup_word':
        return '查询单词';
      case 'analyze_words':
        return '剖析词汇';
      case 'next_question':
        return '切换题目';
      case 'toggle_favorite':
        return '收藏题目';
      case 'get_current_question':
        return '读取当前题目';
      case 'get_progress':
        return '读取学习进度';
      default:
        return '调用工具';
    }
  }

  /// R3: 直接赋最终文本 + 一次通知（删除假流式，消除 O(n²) substring + 人为延迟）
  Future<void> _simulateStreamOutput(ChatMessage msg, String reply, List<String> actions) async {
    msg.content = reply;
    _notifyChatUpdate();
  }

  // ===== 默写 =====
  /// [source]：'custom' = 自定义词库 | 'zsb' = 专升本词库 | 'maimemo' = 墨墨词库
  void startDictation(String mode, int count, {String source = 'zsb'}) {
    dictationMode = mode;
    dictationSource = source;
    List<WordToken> all;
    if (source == 'custom') {
      all = customWordbook
          .map((e) => WordToken(text: e.word, type: 'word', word: e.word, pos: '', translation: e.translation, other: ''))
          .toList();
    } else if (source == 'maimemo') {
      all = maimemoWordbook
          .map((e) => WordToken(text: e.word, type: 'word', word: e.word, pos: '', translation: e.translation, other: ''))
          .toList();
    } else {
      all = DictService.zsbWords()
          .map((w) {
            final e = DictService.zsbLookup(w);
            return WordToken(text: w, type: 'word', word: w, pos: e?.pos ?? '', translation: e?.translation ?? '', other: e?.other ?? '');
          })
          .toList();
    }
    if (all.isEmpty) return;
    all.shuffle(Random());
    final picked = all.take(count).toList();
    dictationQueue = picked;
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

  /// 本地批改默写答案，返回是否答对
  /// [advance] 为 false 时只批改不推进索引（由调用方控制何时下一题）
  bool checkDictationAnswer(String answer, {bool advance = true}) {
    final w = currentDictationWord;
    if (w == null) return false;
    final ans = answer.trim();
    final correct = _judgeDictationLocal(w, ans);
    _commitDictationResult(w, ans, correct, advance: advance);
    return correct;
  }

  /// 本地判定：中文→英文要求拼写完全一致；英文→中文要求释义包含匹配
  bool _judgeDictationLocal(WordToken w, String ans) {
    if (dictationMode == 'zh2en') {
      return ans.toLowerCase() == w.word.toLowerCase();
    }
    final ref = w.translation.replaceAll(RegExp(r'[；;，,。.、/]'), ' ').split(' ').where((s) => s.length >= 2).toList();
    final keyRef = ref.isEmpty ? w.translation : ref.join(' ');
    return keyRef.contains(ans) || ans.isNotEmpty && ref.any((r) => ans.contains(r) || r.contains(ans));
  }

  /// 记录一次默写批改结果（计数 + 错题本 + 推进索引）
  void _commitDictationResult(WordToken w, String ans, bool correct, {bool advance = true}) {
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
  }

  /// AI 批改默写答案，返回 (是否答对, AI 点评)。
  /// 未配置 API 或 AI 调用失败时回退本地批改，并在点评中说明。
  Future<({bool correct, String comment})> checkDictationAnswerAI(String answer, {bool advance = true}) async {
    final w = currentDictationWord;
    if (w == null) return (correct: false, comment: '');
    final ans = answer.trim();
    if (!apiConfig.ready) {
      final correct = _judgeDictationLocal(w, ans);
      _commitDictationResult(w, ans, correct, advance: advance);
      return (correct: correct, comment: '未配置 API，已用本地批改');
    }
    final isZh2En = dictationMode == 'zh2en';
    final systemPrompt = '你是英语单词默写批改老师，请批改用户的默写答案。\n'
        '题目（${isZh2En ? '中文 → 英文' : '英文 → 中文'}）：${isZh2En ? w.translation : w.word}\n'
        '标准答案：${isZh2En ? w.word : w.translation}\n'
        '用户答案：$ans\n'
        '批改规则：\n'
        '- 中文→英文：拼写必须完全正确才算对（大小写不敏感，不允许拼写错误）；\n'
        '- 英文→中文：意思准确即可，同义词、近义表达都算对；\n'
        '只返回一个 JSON 对象，不要返回其他内容：{"correct": true或false, "comment": "一句话中文点评，点评用户答案与标准答案的差异"}';
    try {
      final reply = await ApiService.callAI(
        [
          {'role': 'user', 'content': '请批改'}
        ],
        systemPrompt,
        config: apiConfig,
        maxTokens: 256,
        extraParams: ApiService.noThinkingParams(apiConfig.model),
      );
      final obj = _extractDictationAiJson(reply);
      if (obj != null && obj['correct'] is bool) {
        final correct = obj['correct'] as bool;
        final comment = (obj['comment'] as String?)?.trim() ?? '';
        _commitDictationResult(w, ans, correct, advance: advance);
        return (correct: correct, comment: comment);
      }
    } catch (_) {}
    final correct = _judgeDictationLocal(w, ans);
    _commitDictationResult(w, ans, correct, advance: advance);
    return (correct: correct, comment: 'AI 批改失败，已用本地批改');
  }

  /// 从 AI 回复中提取 {"correct": bool, "comment": "..."} JSON 对象
  Map<String, dynamic>? _extractDictationAiJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final obj = jsonDecode(text.substring(start, end + 1));
      return obj is Map<String, dynamic> ? obj : null;
    } catch (_) {
      return null;
    }
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

  // ===== 自定义词库（默写用，用户手动创建） =====
  List<WordBookItem> customWordbook = [];

  void loadCustomWordbook() {
    customWordbook = Storage.loadCustomWordbook();
    notifyListeners();
  }

  void addToCustomWordbook(String word, String translation) {
    final key = word.trim().toLowerCase();
    if (key.isEmpty) return;
    if (customWordbook.any((e) => e.word.toLowerCase() == key)) return;
    customWordbook.insert(0, WordBookItem(
          word: word.trim(),
          translation: translation.trim(),
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    Storage.saveCustomWordbook(customWordbook);
    notifyListeners();
  }

  void removeFromCustomWordbook(String word) {
    customWordbook.removeWhere((e) => e.word.toLowerCase() == word.toLowerCase());
    Storage.saveCustomWordbook(customWordbook);
    notifyListeners();
  }

  void clearCustomWordbook() {
    customWordbook = [];
    Storage.saveCustomWordbook(customWordbook);
    notifyListeners();
  }

  // ===== 墨墨词库 =====
  List<WordBookItem> maimemoWordbook = [];

  void loadMaimemoWordbook() {
    maimemoWordbook = Storage.loadMaimemoWordbook();
    notifyListeners();
  }

  void addToMaimemoWordbook(String word, String translation) {
    final idx = maimemoWordbook.indexWhere((e) => e.word == word);
    if (idx >= 0) return;
    maimemoWordbook.insert(0, WordBookItem(
          word: word,
          translation: translation,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ));
    Storage.saveMaimemoWordbook(maimemoWordbook);
    notifyListeners();
  }

  void removeFromMaimemoWordbook(String word) {
    maimemoWordbook.removeWhere((e) => e.word == word);
    Storage.saveMaimemoWordbook(maimemoWordbook);
    notifyListeners();
  }

  void updateMaimemoWordbookItem(int index, WordBookItem item) {
    if (index < 0 || index >= maimemoWordbook.length) return;
    maimemoWordbook[index] = item;
    Storage.saveMaimemoWordbook(maimemoWordbook);
    notifyListeners();
  }

  void clearMaimemoWordbook() {
    maimemoWordbook = [];
    Storage.saveMaimemoWordbook(maimemoWordbook);
    notifyListeners();
  }

  // ===== 墨墨背单词同步 =====
  /// 保存墨墨 Token（空串表示清除）
  void setMaimemoToken(String token) {
    maimemoToken = token.trim();
    Storage.saveMaimemoToken(maimemoToken);
    if (maimemoToken.isEmpty) {
      maimemoLastSync = 0;
      maimemoSyncedCount = 0;
      maimemoSyncError = null;
      maimemoProgress = null;
      Storage.saveMaimemoLastSync(0);
      Storage.saveMaimemoSyncedCount(0);
    }
    notifyListeners();
  }

  /// 从墨墨拉取今日已学习单词并累加入墨墨词库。
  /// 词库是累计词汇库：已存在的单词保留（含用户编辑），
  /// 今日已学习的新单词追加到词库，历史数据不会清空。
  /// 返回本次新增的单词数；失败抛 MaimemoException。
  Future<int> syncMaimemoWords() async {
    if (maimemoSyncing) return 0;
    if (maimemoToken.trim().isEmpty) {
      throw const MaimemoException('尚未配置墨墨 API Token');
    }
    maimemoSyncing = true;
    maimemoSyncError = null;
    notifyListeners();
    try {
      // 1. 今日学习进度
      final progress = await MaimemoService.getStudyProgress(maimemoToken);
      // 2. 今日全部学习单词（含新词与复习；超 1000 时自动拆分去重合并）
      final allWords = await MaimemoService.fetchAllTodayWords(maimemoToken);
      // 3. 仅保留今日已学习（已点过认识/不认识）的单词，过滤掉仅规划未学习的
      final words = allWords.where((w) => w.isFinished).toList();
      // 4. 分批校验 token 与词条有效性（vocabulary/query 每次一批，避免超限）
      final spellings = words.map((w) => w.spelling).toList();
      for (var i = 0; i < spellings.length; i += 100) {
        final end = (i + 100) < spellings.length ? i + 100 : spellings.length;
        await MaimemoService.queryVocabulary(
          maimemoToken,
          spellings: spellings.sublist(i, end),
        );
      }
      // 5. 词库累积：已存在的单词保留，今日已学习的新单词追加到顶部
      final existing = {
        for (final e in maimemoWordbook) e.word.toLowerCase(): true,
      };
      var added = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final w in words) {
        final key = w.spelling.toLowerCase();
        if (existing[key] == true) continue;
        existing[key] = true;
        final entry = DictService.lookup(key);
        maimemoWordbook.insert(
          0,
          WordBookItem(
            word: w.spelling,
            translation: entry?.translation ?? '',
            addedAt: now,
          ),
        );
        added++;
      }
      Storage.saveMaimemoWordbook(maimemoWordbook);
      maimemoLastSync = DateTime.now().millisecondsSinceEpoch;
      maimemoSyncedCount += added;
      maimemoProgress = progress;
      Storage.saveMaimemoLastSync(maimemoLastSync);
      Storage.saveMaimemoSyncedCount(maimemoSyncedCount);
      return added;
    } catch (e) {
      maimemoSyncError = e.toString();
      rethrow;
    } finally {
      maimemoSyncing = false;
      notifyListeners();
    }
  }

  // ===== 学习报告数据 =====
  List<StudyRecord> studyRecords = [];
  List<WrongItem> wrongQuestions = [];
  Set<int> answeredBankIndices = <int>{};

  void loadStudyRecords() {
    studyRecords = Storage.loadStudyRecords();
    notifyListeners();
  }

  void loadWrongQuestions() {
    wrongQuestions = Storage.loadWrongQuestions();
    notifyListeners();
  }

  void loadAnsweredBankIndices() {
    answeredBankIndices = Storage.loadAnsweredBankIndices();
    notifyListeners();
  }

  void _markBankAnswered(int? idx) {
    if (idx == null) return;
    if (answeredBankIndices.add(idx)) {
      Storage.saveAnsweredBankIndices(answeredBankIndices);
    }
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
  /// 保存全局配置：更新当前生效配置，并同步到配置库（同名 URL+Key 覆盖，否则追加）
  void saveApiConfig(ApiConfig c) {
    apiConfig = c;
    Storage.saveApiConfig(c);
    final idx = apiProfiles.indexWhere((p) => p.config.url == c.url && p.config.key == c.key);
    if (idx >= 0) {
      apiProfiles[idx] = ApiProfile(name: apiProfiles[idx].name, config: c);
    } else {
      apiProfiles.add(ApiProfile(name: '配置${apiProfiles.length + 1}', config: c));
    }
    Storage.saveApiProfiles(apiProfiles);
    notifyListeners();
  }

  /// 保存全局配置库并切换当前使用的配置
  void saveApiProfiles(List<ApiProfile> profiles, int activeIdx) {
    apiProfiles = List.of(profiles);
    if (activeIdx >= 0 && activeIdx < apiProfiles.length) {
      apiConfig = apiProfiles[activeIdx].config;
      Storage.saveApiConfig(apiConfig);
    }
    Storage.saveApiProfiles(apiProfiles);
    notifyListeners();
  }

  /// 保存对话助手配置库并切换当前选中的配置
  void saveChatProfiles(List<ApiProfile> profiles, int idx) {
    chatProfiles = List.of(profiles);
    chatProfileIdx = (idx >= 0 && idx < chatProfiles.length) ? idx : (chatProfiles.isEmpty ? -1 : 0);
    if (chatProfileIdx >= 0 && chatProfileIdx < chatProfiles.length) {
      chatApiConfig = chatProfiles[chatProfileIdx].config;
      Storage.saveChatConfig(chatApiConfig);
    }
    Storage.saveChatProfiles(chatProfiles);
    Storage.saveChatProfileIdx(chatProfileIdx);
    notifyListeners();
  }

  /// 对话助手底层切换模型（index 为 chatProfiles 索引；-1 表示使用全局配置）
  void selectChatProfile(int index) {
    if (index >= 0 && index < chatProfiles.length) {
      chatApiIndependent = true;
      chatProfileIdx = index;
      chatApiConfig = chatProfiles[index].config;
      Storage.saveChatConfig(chatApiConfig);
      Storage.saveChatProfileIdx(index);
    } else {
      // 使用全局配置
      chatApiIndependent = false;
      chatProfileIdx = -1;
      Storage.saveChatIndependent(false);
      Storage.saveChatProfileIdx(-1);
    }
    notifyListeners();
  }

  /// 删除对话助手配置库中的配置；删除后自动切到剩余首个或全局
  void removeChatProfile(int index) {
    if (index < 0 || index >= chatProfiles.length) return;
    chatProfiles.removeAt(index);
    if (chatProfiles.isEmpty) {
      chatProfileIdx = -1;
      chatApiIndependent = false;
      Storage.saveChatIndependent(false);
      Storage.saveChatProfileIdx(-1);
    } else {
      chatProfileIdx = chatProfileIdx == index ? 0 : (chatProfileIdx > index ? chatProfileIdx - 1 : chatProfileIdx);
      if (chatApiIndependent && chatProfileIdx >= 0) {
        chatApiConfig = chatProfiles[chatProfileIdx].config;
        Storage.saveChatConfig(chatApiConfig);
      }
      Storage.saveChatProfileIdx(chatProfileIdx);
    }
    Storage.saveChatProfiles(chatProfiles);
    notifyListeners();
  }

  void saveChatSettings({required bool independent, required ApiConfig config, required bool showReasoning, required bool stream, required bool thinking}) {
    chatApiIndependent = independent;
    chatApiConfig = config;
    chatShowReasoning = showReasoning;
    chatStream = stream;
    chatThinking = thinking;
    Storage.saveChatIndependent(independent);
    Storage.saveChatConfig(config);
    Storage.saveChatShowReasoning(showReasoning);
    Storage.saveChatStream(stream);
    Storage.saveChatThinking(thinking);
    notifyListeners();
  }

  /// 切换深色模式
  void toggleDarkMode(bool v) {
    if (darkMode != v) {
      darkMode = v;
      Storage.saveDarkMode(v);
      notifyListeners();
    }
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

  /// 切换高性能模式：关闭毛玻璃/半透明模糊等重特效且不锁帧，
  /// 面向低配设备大幅提升流畅度；所有功能保持不变。
  void toggleHighPerformanceMode(bool v) {
    if (highPerformanceMode == v) return;
    highPerformanceMode = v;
    AppColors.highPerformance = v;
    Storage.saveHighPerformanceMode(v);
    notifyListeners();
  }

  void setUiMode(String mode) {
    uiMode = mode;
    Storage.saveUiMode(mode);
    _applySystemUiMode();
    notifyListeners();
  }

  void setUiStyle(String style) {
    if (uiStyle == style) return;
    uiStyle = style;
    Storage.saveUiStyle(style);
    notifyListeners();
  }

  /// 设置主题（第三大主题）：'classic' = 经典(浅色) | 'glass' = 毛玻璃(浅色) | 'dark' = 深色独立主题
  void setThemeStyle(String t) {
    if (t == 'dark') {
      toggleDarkMode(true);
    } else {
      toggleDarkMode(false);
      setUiStyle(t);
    }
  }

  void setNavIndicator(String type) {
    if (navIndicator == type) return;
    navIndicator = type;
    Storage.saveNavIndicator(type);
    notifyListeners();
  }

  /// 根据当前 uiMode 切换系统 UI 模式：手机端沉浸式全屏（隐藏状态栏与导航栏），
  /// 电脑端恢复常规显示。SystemChrome 在桌面平台为 no-op，不会影响 Windows 端。
  void _applySystemUiMode() {
    if (uiMode == 'mobile') {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Color(0x00000000),
        systemNavigationBarColor: Color(0x00000000),
      ));
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void setAnalysisMode(String mode) {
    analysisMode = mode;
    Storage.saveAnalysisMode(mode);
    notifyListeners();
  }

  /// 完成首次启动引导（写 Storage + 刷新 UI）
  void completeOnboarding() {
    onboardingDone = true;
    Storage.saveOnboardingDone(true);
    notifyListeners();
  }

  /// 重新触发引导（设置中“重新查看引导”入口）
  void resetOnboarding() {
    onboardingDone = false;
    Storage.saveOnboardingDone(false);
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
      loadCustomWordbook();
      loadMaimemoWordbook();
      loadRecordedWords();
      loadRecordsSelected();
      loadAnsweredBankIndices();
      notifyListeners();
    }
    return ok;
  }
  /// 供 UI 调用的刷新入口（等价于 notifyListeners）
  void touch() => notifyListeners();

  // ===== 全卷模拟考试：AI 生成 + 进入考场 + 交卷判分 =====

  /// 触发 AI 生成一套完整专升本模拟全卷（7大部分 76题）：直接进入考场，
  /// 每个大部分一次请求整段生成（受控并行 + 重试 + 降级拆分 + 本地兜底），全程不断链。
  Future<bool> generateFullExam({String customReq = ''}) async {
    // 重入守卫：上一轮整卷生成仍在进行时直接拒绝，
    // 避免新卷已建但 _runExamGeneration 被拦截导致永远卡在“加载中”
    if (examGeneratingBatch) return false;
    _examCustomReq = customReq;
    generatingFullExam = true;
    notifyListeners();

    // 创建空试卷结构（所有题型列表初始为空）
    final paper = FullExamPaper(
      title: '2025年专升本综合模拟全卷',
      totalTimeMin: 120,
      vocab: [],
      readings: [],
      cloze: [],
      clozeSubs: [],
      dialogue: null,
      bankedCloze: null,
      en2zh5: null,
      writing: null,
    );
    currentExamPaper = paper;
    currentExamAnswerSheet = ExamAnswerSheet();
    currentExamResult = null;
    examRemainingSec = paper.totalTimeMin * 60;
    examStartTs = DateTime.now().millisecondsSinceEpoch;
    examCurrentQuestion = 1;
    examGeneratedCount = 0;
    examGeneratingBatch = false;
    examGenerationDone = false;
    _examFailedBatches.clear();
    examGeneratingHint = '准备进入考场...';
    examPendingConfirm = false;

    // 直接进入考场（page=10）
    page = 10;
    generatingFullExam = false;
    notifyListeners();

    // 稍等考场界面渲染完成后启动并行生成（不再逐批人为延迟）
    Future.delayed(const Duration(milliseconds: 300), () {
      if (currentExamPaper != null && page == 10) {
        _runExamGeneration(_fullExamBatchPlan(), customReq);
      }
    });

    return true;
  }

  /// 全卷七大部分计划：每个大部分一次 AI 请求整段生成（不再按 10 题小批次拆分），
  /// 七个请求受控并行，完成后按大题顺序合并进试卷。
  List<ExamBatchSpec> _fullExamBatchPlan() => const [
        ExamBatchSpec(0, 'vocab', 20, 0, '词汇与语法结构'),
        ExamBatchSpec(1, 'reading', 4, 0, '阅读理解'),
        ExamBatchSpec(2, 'cloze', 15, 0, '完形填空'),
        ExamBatchSpec(3, 'dialogue', 5, 0, '补全对话'),
        ExamBatchSpec(4, 'bankedCloze', 10, 0, '选词填空'),
        ExamBatchSpec(5, 'en2zh5', 5, 0, '英译汉'),
        ExamBatchSpec(6, 'writing', 1, 0, '写作'),
      ];

  /// 受控并行（并发度2，大题型输出大避免打挂 API）执行七大部分生成计划：
  /// 每个大部分先整段请求（重试时升档 max_tokens / 精简 prompt），仍失败或只解析回
  /// 部分题目时自动拆小重发（对用户透明）；词汇/英译汉彻底失败用本地兜底；
  /// 剩余失败大题记入 _examFailedBatches 供“重新生成缺失部分”。
  Future<void> _runExamGeneration(List<ExamBatchSpec> plan, String customReq) async {
    if (examGeneratingBatch || plan.isEmpty) return;
    final paper = currentExamPaper;
    if (paper == null) return;
    if (!apiConfig.ready) {
      examGeneratingHint = 'API未配置，无法生成题目，请先到“设置 → AI 接口”完成配置';
      examGenerationDone = true;
      notifyListeners();
      return;
    }
    examGeneratingBatch = true;
    examGeneratingHint = '正在按大题并行生成试卷（共${plan.length}个大部分）…';
    notifyListeners();

    final buffer = <int, Object>{}; // 已完成待合并的大题产物（按 spec.id）
    final failed = <ExamBatchSpec>[]; // 重试与拆分兜底后仍失败的大题
    var sectionsDone = 0;

    void mergeAvailable() {
      if (buffer.isEmpty) return;
      final ids = buffer.keys.toList()..sort();
      for (final id in ids) {
        final spec = plan.firstWhere((b) => b.id == id);
        try {
          _mergeBatchPayload(paper, spec, buffer[id]!);
        } catch (e) {
          failed.add(spec); // 合并异常不再吞掉：计入失败大题，反映到 UI
        }
        buffer.remove(id);
      }
      _recomputeExamCount(paper);
    }

    final queue = List<ExamBatchSpec>.of(plan);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final spec = queue.removeAt(0);
        Object? payload;
        try {
          payload = await _generateSectionPayload(spec, customReq);
        } catch (e) {
          payload = null;
          examGeneratingHint = '${spec.label}生成异常：$e';
        }
        sectionsDone++;
        if (payload != null && _payloadCount(spec.type, payload) > 0) {
          buffer[spec.id] = payload;
        } else {
          failed.add(spec);
        }
        mergeAvailable();
        examGeneratingHint = '已生成 $sectionsDone/${plan.length} 个大部分（$examGeneratedCount/$examTotalQuestions 题）…';
        notifyListeners();
      }
    }

    await Future.wait(List.generate(2, (_) => worker()));

    // ===== 本地兜底：词汇大题 → 词库模板题；英译汉大题 → 真题库翻译题 =====
    if (failed.isNotEmpty) {
      final recovered = <ExamBatchSpec>[];
      for (final spec in failed) {
        Object? payload;
        try {
          if (spec.type == 'vocab') {
            payload = _buildLocalVocabBatch(spec.count);
          } else if (spec.type == 'en2zh5') {
            payload = _buildLocalEn2zh5Batch();
          }
        } catch (_) {
          payload = null;
        }
        if (payload != null) {
          buffer[spec.id] = payload;
          recovered.add(spec);
        }
      }
      failed.removeWhere(recovered.contains);
      mergeAvailable();
    }

    _examFailedBatches
      ..clear()
      ..addAll(failed);
    examGeneratingBatch = false;
    examGenerationDone = true;
    _recomputeExamCount(paper);
    if (failed.isEmpty) {
      examGeneratingHint = '全部题目已生成完毕！';
    } else {
      examGeneratingHint = '生成结束，但以下大题未能生成：${failed.map((f) => f.label).join('、')}。可点击上方“重新生成缺失部分”补齐。';
    }
    notifyListeners();
  }

  /// 单个大部分整段生成入口：先整段请求（带重试/max_tokens 升档），
  /// 失败或只回部分题目时自动拆小重发并合并为一个大题（对用户透明）。
  Future<Object?> _generateSectionPayload(ExamBatchSpec spec, String customReq) async {
    if (spec.type == 'vocab') return _generateVocabSection(spec.count, customReq);
    if (spec.type == 'reading') return _generateReadingSection(spec.count, customReq);
    if (spec.type == 'cloze') return _generateClozeSection(spec.count, customReq);
    // 对话 / 选词填空 / 英译汉 / 写作：单一结构，仅整段请求 + 重试（失败走本地兜底或横幅）
    return _requestSectionWithRetry(spec, customReq);
  }

  /// 词汇大题（20题）：整段请求失败/不全 → 对半拆小重发（20→10+10），
  /// 叶子层仍不足时用本地词库模板题补齐
  Future<List<Question>?> _generateVocabSection(int n, String customReq) async {
    final got = await _genVocabChunk(n, customReq);
    return got.isEmpty ? null : got;
  }

  Future<List<Question>> _genVocabChunk(int n, String customReq, {int depth = 0}) async {
    if (n <= 0 || currentExamPaper == null) return [];
    final res = await _requestSectionWithRetry(
      ExamBatchSpec(0, 'vocab', n, 0, n >= 20 ? '词汇与语法结构' : '词汇与语法(拆分$n题)'),
      customReq,
    );
    final got = (res is List<Question>) ? res.take(n).toList() : <Question>[];
    if (got.length >= n) return got;
    final need = n - got.length;
    if (depth >= 2 || need <= 3) {
      // 拆到底或零头：用本地词库模板题补齐，保证词汇大题完整
      final local = _buildLocalVocabBatch(need);
      return [...got, if (local != null) ...local];
    }
    final halves = _splitCounts(need); // 20→[10,10]，其余对半拆（每块≤10）
    final parts = await Future.wait(halves.map((c) => _genVocabChunk(c, customReq, depth: depth + 1)));
    return [...got, ...parts.expand((e) => e)];
  }

  /// 阅读大题（4篇×5题）：整段请求失败/不全 → 对半拆小（4→2+2→1篇/次）直到拿满或拆到底
  Future<List<Question>?> _generateReadingSection(int n, String customReq) async {
    final got = await _genReadingChunk(n, customReq);
    return got.isEmpty ? null : got;
  }

  Future<List<Question>> _genReadingChunk(int n, String customReq, {int depth = 0}) async {
    if (n <= 0 || currentExamPaper == null) return [];
    final res = await _requestSectionWithRetry(
      ExamBatchSpec(0, 'reading', n, 0, n >= 4 ? '阅读理解' : '阅读理解(拆分$n篇)'),
      customReq,
    );
    final got = (res is List<Question>) ? res.take(n).toList() : <Question>[];
    if (got.length >= n) return got;
    final need = n - got.length;
    if (need <= 0) return got;
    if (depth >= 2) return got; // 已拆到单篇粒度仍失败，放弃剩余篇目
    final halves = need == 1 ? [1] : _splitCounts(need);
    final parts = await Future.wait(halves.map((c) => _genReadingChunk(c, customReq, depth: depth + 1)));
    return [...got, ...parts.expand((e) => e)];
  }

  /// 完形大题（15空）：整段请求失败/不全 → 拆为 10空+5空 两篇并行重发，
  /// 成功后拼接短文并对第二篇空格重新编号，合并成一篇 15 空完形
  Future<Object?> _generateClozeSection(int n, String customReq) async {
    final spec = ExamBatchSpec(0, 'cloze', n, 0, '完形填空');
    final full = await _requestSectionWithRetry(spec, customReq);
    if (full != null && _payloadCount('cloze', full) >= n) return full;
    if (n >= 10) {
      final a = n - 5, b = 5; // 15 → 10 + 5
      final parts = await Future.wait([
        _requestSectionWithRetry(ExamBatchSpec(0, 'cloze', a, 0, '完形填空(拆分$a空)'), customReq),
        _requestSectionWithRetry(ExamBatchSpec(0, 'cloze', b, 0, '完形填空(拆分$b空)'), customReq),
      ]);
      final recs = parts
          .whereType<({String passage, List<ClozeSubQ> subs})>()
          .where((r) => r.passage.isNotEmpty && r.subs.isNotEmpty)
          .toList();
      if (recs.isNotEmpty) return _combineClozeRecs(recs);
    }
    return full;
  }

  /// 拼接多篇完形短文为一篇：短文顺序连接，后续篇空格编号整体顺延
  ({String passage, List<ClozeSubQ> subs}) _combineClozeRecs(
      List<({String passage, List<ClozeSubQ> subs})> recs) {
    final sb = StringBuffer();
    final subs = <ClozeSubQ>[];
    var off = 0;
    for (final r in recs) {
      if (sb.isNotEmpty) sb.write('\n\n');
      sb.write(_renumberBlanks(r.passage, off, r.subs.length));
      for (final s in r.subs) {
        subs.add(ClozeSubQ(
          blankIdx: s.blankIdx + off,
          sentence: s.sentence,
          options: s.options,
          answerIdx: s.answerIdx,
          answerLetter: s.answerLetter,
          analysis: s.analysis,
        ));
      }
      off += r.subs.length;
    }
    return (passage: sb.toString(), subs: subs);
  }

  /// 完形短文空格重编号：____k____ → ____(k+offset)____（倒序替换避免连环误伤）
  String _renumberBlanks(String passage, int offset, int count) {
    if (offset <= 0) return passage;
    var s = passage;
    for (var k = count; k >= 1; k--) {
      s = s.replaceAll('____${k}____', '____${k + offset}____');
    }
    return s;
  }

  /// 大题请求（整段一次出全部题目，首次 + 1 次重试）：
  /// 大题型首次 max_tokens 升档到 16000（API 不支持/请求失败则降回 8192 重试）；
  /// finish_reason=='length' 按截断处理：先用截断修复解析尽力救回，不完整则交拆分兜底；
  /// 重试时精简 prompt 缩减输出量。返回解析产物（可能为部分题目），彻底失败返回 null。
  Future<Object?> _requestSectionWithRetry(ExamBatchSpec spec, String customReq) async {
    const maxAttempts = 2;
    final big = spec.type == 'vocab' || spec.type == 'reading' || spec.type == 'cloze';
    Object? best; // 各次尝试中救回题目最多的部分产物
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (currentExamPaper == null) return best;
      final maxTokens = (big && attempt == 1) ? 16000 : 8192;
      AIResult? res;
      try {
        res = await ApiService.callAIResult(
          [
            {'role': 'user', 'content': '请生成专升本英语题目（${spec.label}），一次生成全部 ${spec.count} 题'}
          ],
          _buildBatchPrompt(spec, customReq, attempt),
          config: apiConfig,
          maxTokens: maxTokens,
          extraParams: _noThinkingParams(),
        );
      } catch (_) {
        res = null;
      }
      final reply = res?.content;
      String? failReason;
      if (res == null || reply == null || reply.isEmpty) {
        // 透传请求层失败原因（如超时、连接被拦截、HTTP 错误码），便于移动端排查
        final detail = ApiService.lastError;
        failReason = maxTokens > 8192
            ? '请求失败（降低max_tokens重试）${detail != null ? '：$detail' : ''}'
            : (detail ?? 'AI无响应或超时');
      } else {
        final truncated = res.finishReason == 'length';
        try {
          final payload = _parseBatchPayload(spec, reply);
          if (payload != null) {
            final have = _payloadCount(spec.type, payload);
            if (have >= spec.count) return payload;
            // 截断/不完整：记下部分产物，留待重试或拆分补齐
            best = _betterSectionPayload(spec.type, best, payload);
            failReason = truncated ? '输出被截断（已救回$have/${spec.count}）' : '题目不全（$have/${spec.count}）';
          } else {
            failReason = truncated ? '输出被截断且无法解析' : '返回格式无法解析';
          }
        } catch (e) {
          failReason = '解析异常：$e';
        }
      }
      examGeneratingHint = '${spec.label}第$attempt次生成失败（$failReason）${attempt < maxAttempts ? '，正在自动重试…' : ''}';
      notifyListeners();
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(milliseconds: 1200 * attempt));
      }
    }
    return best;
  }

  /// 统计大题产物包含的题目数（用于判断完整性与挑选更优的部分产物）
  int _payloadCount(String type, Object? payload) {
    if (payload == null) return 0;
    if (type == 'vocab' || type == 'reading') {
      return payload is List<Question> ? payload.length : 0;
    }
    if (type == 'cloze') {
      return payload is ({String passage, List<ClozeSubQ> subs}) ? payload.subs.length : 0;
    }
    if (type == 'dialogue') return payload is DialogueEntry ? payload.answerLetters.length : 0;
    if (type == 'bankedCloze') return payload is BankedClozeEntry ? payload.answerWords.length : 0;
    if (type == 'en2zh5') return payload is En2zh5Entry ? payload.sentences.length : 0;
    if (type == 'writing') return payload is WritingEntry && payload.topic.isNotEmpty ? 1 : 0;
    return 0;
  }

  /// 两个部分产物中保留题目数更多的一个
  Object? _betterSectionPayload(String type, Object? a, Object? b) {
    if (a == null) return b;
    if (b == null) return a;
    return _payloadCount(type, b) > _payloadCount(type, a) ? b : a;
  }

  /// 把 n 对半拆成两块（每块 ≤10）：20→[10,10]，15→[8,7]，4→[2,2]
  List<int> _splitCounts(int n) {
    if (n <= 10) return [n];
    final half = (n / 2).ceil();
    return [half, n - half];
  }

  /// 将某批解析产物按分区 offset 合并进试卷（乱序完成也能保持题目顺序）
  void _mergeBatchPayload(FullExamPaper paper, ExamBatchSpec spec, Object payload) {
    if (spec.type == 'vocab') {
      final items = payload as List<Question>;
      final at = spec.offset.clamp(0, paper.vocab.length);
      paper.vocab.insertAll(at, items);
    } else if (spec.type == 'reading') {
      final items = payload as List<Question>;
      final at = spec.offset.clamp(0, paper.readings.length);
      paper.readings.insertAll(at, items);
    } else if (spec.type == 'cloze') {
      final rec = payload as ({String passage, List<ClozeSubQ> subs});
      paper.cloze
        ..clear()
        ..add(Question(
          type: QType.cloze,
          level: 'zsb',
          passage: rec.passage,
          text: '',
          chinese: '',
          english: '',
          correctAnswer: '',
        ));
      paper.clozeSubs = rec.subs;
    } else if (spec.type == 'dialogue') {
      paper.dialogue = payload as DialogueEntry;
    } else if (spec.type == 'bankedCloze') {
      paper.bankedCloze = payload as BankedClozeEntry;
    } else if (spec.type == 'en2zh5') {
      paper.en2zh5 = payload as En2zh5Entry;
    } else if (spec.type == 'writing') {
      paper.writing = payload as WritingEntry;
    }
  }

  /// 按试卷实际内容重算进度计数（进度条随各批完成推进）
  void _recomputeExamCount(FullExamPaper paper) {
    var n = paper.vocab.length;
    for (final r in paper.readings) {
      n += r.questions.length;
    }
    n += paper.clozeSubs?.length ?? 0;
    n += paper.dialogue == null ? 0 : min(5, paper.dialogue!.answerLetters.length);
    n += paper.bankedCloze == null ? 0 : min(10, paper.bankedCloze!.answerWords.length);
    n += paper.en2zh5 == null ? 0 : min(5, paper.en2zh5!.sentences.length);
    n += paper.writing == null ? 0 : 1;
    examGeneratedCount = n;
  }

  /// “重新生成缺失部分”：仅重新调度仍失败的批次，成功后按原分区位置合并；
  /// 透传本轮卷的用户自定义出题要求，避免重发时丢失
  Future<void> regenerateFailedExamBatches() async {
    if (examGeneratingBatch || _examFailedBatches.isEmpty) return;
    final specs = List<ExamBatchSpec>.of(_examFailedBatches);
    _examFailedBatches.clear();
    final plan = <ExamBatchSpec>[
      for (var i = 0; i < specs.length; i++)
        ExamBatchSpec(i, specs[i].type, specs[i].count, specs[i].offset, specs[i].label),
    ];
    await _runExamGeneration(plan, _examCustomReq);
  }

  /// 构建单批出题 prompt：词汇约束样本抽自 zsb-dict.json；attempt>=2 时精简输出要求，
  /// 减少输出 token 以避免截断/超时
  String _buildBatchPrompt(ExamBatchSpec spec, String customReq, int attempt) {
    final sb = StringBuffer();
    sb.writeln('你是专升本英语专业出题专家。请严格按照以下要求生成题目。难度对标各省专升本英语真题。');
    if (customReq.isNotEmpty) sb.writeln('额外要求：$customReq');
    sb.writeln('');
    // 从专升本词库（zsb-dict.json）随机抽词作为考点词约束样本：大输出题型多抽一些
    final zsbWords = DictService.zsbWords();
    if (zsbWords.isNotEmpty) {
      final sampleN = spec.type == 'reading' ? 160 : (spec.type == 'vocab' ? 120 : 80);
      final sampled = List<String>.from(zsbWords)..shuffle(Random());
      final wordSample = sampled.take(min(sampleN, sampled.length)).join(', ');
      sb.writeln('【重要词汇约束】所有题目（题干/选项/短文）必须严格只使用以下专升本词汇表内的单词，不得超纲：');
      sb.writeln(wordSample);
      sb.writeln('');
    }
    final shorter = attempt >= 2;
    sb.writeln('【输出要求】只返回纯 JSON（不要 markdown 代码块，不要解释文字）；严格按模板输出，禁止输出模板之外的任何字段；选项尽量简短（≤8词）；每题 analysis 不超过20字且可为空字符串。');
    if (shorter) {
      sb.writeln('【重要】上一次生成失败，请大幅精简输出：短文更短、句子更简单、解析更简短。');
    }
    sb.writeln('');
    if (spec.type == 'vocab') {
      sb.writeln('【本次生成：词汇与语法结构 · 单项选择】共 ${spec.count} 题（1分/题）');
      sb.writeln('返回 JSON 数组：');
      sb.writeln('[{"question":"英文题干(含____空格)","options":["选项1","选项2","选项3","选项4"],"answer":"A","analysis":"不超20字","knowledge":["知识点"]}, ...共${spec.count}条]');
    } else if (spec.type == 'reading') {
      final wordRange = shorter ? '约120-160词' : '约150-220词';
      sb.writeln('【本次生成：阅读理解】共 ${spec.count} 篇短文，每篇5小题（2分/题）');
      sb.writeln('返回 JSON 数组：');
      sb.writeln('[{"passage":"英文短文($wordRange)","questions":[{"question":"问题","options":["选项1","选项2","选项3","选项4"],"answer":"A","analysis":"不超20字"}, ...共5条]}, ...共${spec.count}条]');
    } else if (spec.type == 'cloze') {
      final passageLen = shorter ? '不超过150词' : '约180-220词';
      sb.writeln('【本次生成：完形填空】共 ${spec.count} 空（1分/空）');
      sb.writeln('返回 JSON 对象：');
      sb.writeln('{"passage":"英文短文($passageLen，空格用____1____至____${spec.count}____标记)","blanks":[{"blankIdx":1,"sentence":"含该空的上下文句子","options":["选项1","选项2","选项3","选项4"],"answer":"A","analysis":"不超20字"}, ...共${spec.count}条]}');
    } else if (spec.type == 'dialogue') {
      sb.writeln('【本次生成：补全对话】共 5 空（2分/空，从A-G共7个句子选项中选5个填入）');
      sb.writeln('返回 JSON 对象：');
      sb.writeln('{"scenario":"场景说明","dialogueLines":["A: Hello, ___1___","B: ... ___2___", ...共8行],"options":["A. 句子1","B. 句子2","C. 句子3","D. 句子4","E. 句子5","F. 句子6(多余)","G. 句子7(多余)"],"answerLetters":["C","A","G","D","F"],"analyses":["不超20字", ...共5条]}');
    } else if (spec.type == 'bankedCloze') {
      sb.writeln('【本次生成：选词填空（15选10）】共 10 空（2分/空）');
      sb.writeln('返回 JSON 对象：');
      sb.writeln('{"passage":"英文短文(${shorter ? '约120词' : '约150-200词'}，空格用____1____到____10____标记)","wordBank":["单词1","单词2", ...共15个],"answerWords":["对应第1空的单词", ...共10个],"analyses":["不超20字", ...共10条]}');
    } else if (spec.type == 'en2zh5') {
      sb.writeln('【本次生成：英译汉】共 5 个英文句子翻译成中文（4分/句）');
      sb.writeln('返回 JSON 对象：');
      sb.writeln('{"sentences":["英文句子1", ...共5条],"answers":["中文参考翻译1", ...共5条]}');
    } else if (spec.type == 'writing') {
      sb.writeln('【本次生成：写作】共 1 篇英文写作（20分，不少于120词）');
      sb.writeln('返回 JSON 对象：');
      sb.writeln('{"topic":"中文写作题目要求（含文体、字数、提纲）","reference":"英文参考范文(${shorter ? '约120-150词' : '约150-200词'})"}');
    }
    return sb.toString();
  }

  /// 解析单批 AI 回复为对应数据结构；返回 null 表示解析失败（由调用方触发重试）
  Object? _parseBatchPayload(ExamBatchSpec spec, String reply) {
    if (spec.type == 'vocab') {
      final arr = ApiService.extractJsonArray(reply);
      if (arr == null || arr.isEmpty) return null;
      final rng = Random();
      var replaced = 0;
      final out = <Question>[];
      for (final item in arr) {
        if (item['question'] == null || item['options'] is! List) continue;
        final options = normalizeOptions(item['options']);
        if (options.isEmpty) continue;
        final idx = parseAnswerIdx(item['answer']);
        var q = Question(
          type: QType.choice,
          level: 'zsb',
          question: item['question'].toString(),
          text: item['question'].toString(),
          chinese: '',
          english: '',
          correctAnswer: '',
          options: options,
          answerIdx: idx,
          answerLetter: idx >= 0 && idx < options.length ? String.fromCharCode(65 + idx) : '',
          analysis: item['analysis']?.toString() ?? '',
          knowledge: (item['knowledge'] as List?)?.map((e) => e.toString()).toList() ?? [],
        );
        // 词库校验：题干/答案词出现超纲词时，用词库内模板题替换（每次最多替换8题）
        if (replaced < 8 && _isVocabQOutOfDict(q)) {
          final rep = _buildLocalVocabQuestion(rng);
          if (rep != null) {
            q = rep;
            replaced++;
          }
        }
        out.add(q);
      }
      return out.isEmpty ? null : out;
    }
    if (spec.type == 'reading') {
      final arr = ApiService.extractJsonArray(reply);
      if (arr == null || arr.isEmpty) return null;
      final out = <Question>[];
      for (final item in arr) {
        final passage = item['passage']?.toString() ?? '';
        final questionsRaw = (item['questions'] as List?) ?? [];
        if (passage.isEmpty || questionsRaw.isEmpty) continue;
        final subs = <ReadingSubQ>[];
        for (final q in questionsRaw) {
          final qm = q as Map<String, dynamic>;
          subs.add(ReadingSubQ(
            question: qm['question']?.toString() ?? '',
            options: normalizeOptions(qm['options']),
            answerIdx: parseAnswerIdx(qm['answer']),
            answerLetter: '',
            analysis: qm['analysis']?.toString() ?? '',
            knowledge: [],
          ));
        }
        if (subs.isEmpty) continue;
        out.add(Question(
          type: QType.reading,
          level: 'zsb',
          passage: passage,
          text: '阅读理解',
          chinese: '',
          english: '',
          correctAnswer: '',
          questions: subs,
        ));
      }
      return out.isEmpty ? null : out;
    }
    if (spec.type == 'cloze') {
      final obj = ApiService.extractJsonObject(reply);
      if (obj == null) return null;
      final passage = obj['passage']?.toString() ?? '';
      final blanks = (obj['blanks'] as List?) ?? [];
      if (passage.isEmpty || blanks.isEmpty) return null;
      final subs = <ClozeSubQ>[];
      for (var i = 0; i < blanks.length; i++) {
        final m = blanks[i] as Map<String, dynamic>;
        subs.add(ClozeSubQ(
          blankIdx: (m['blankIdx'] as num?)?.toInt() ?? (i + 1),
          sentence: m['sentence']?.toString() ?? '',
          options: normalizeOptions(m['options']),
          answerIdx: parseAnswerIdx(m['answer']),
          answerLetter: '',
          analysis: m['analysis']?.toString() ?? '',
        ));
      }
      return (passage: passage, subs: subs);
    }
    if (spec.type == 'dialogue') {
      final obj = ApiService.extractJsonObject(reply);
      if (obj == null) return null;
      final lines = (obj['dialogueLines'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final options = (obj['options'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (lines.isEmpty || options.isEmpty) return null;
      return DialogueEntry(
        scenario: obj['scenario']?.toString() ?? '',
        dialogueLines: lines,
        options: options,
        answerLetters: (obj['answerLetters'] as List?)?.map((e) => e.toString()).toList() ?? [],
        analyses: (obj['analyses'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
    }
    if (spec.type == 'bankedCloze') {
      final obj = ApiService.extractJsonObject(reply);
      if (obj == null) return null;
      final passage = obj['passage']?.toString() ?? '';
      final bank = (obj['wordBank'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (passage.isEmpty || bank.isEmpty) return null;
      return BankedClozeEntry(
        passage: passage,
        wordBank: bank,
        answerWords: (obj['answerWords'] as List?)?.map((e) => e.toString()).toList() ?? [],
        analyses: (obj['analyses'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
    }
    if (spec.type == 'en2zh5') {
      final obj = ApiService.extractJsonObject(reply);
      if (obj == null) return null;
      final sentences = (obj['sentences'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (sentences.isEmpty) return null;
      return En2zh5Entry(
        sentences: sentences,
        answers: (obj['answers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
    }
    if (spec.type == 'writing') {
      final obj = ApiService.extractJsonObject(reply);
      if (obj == null) return null;
      final topic = obj['topic']?.toString() ?? '';
      if (topic.isEmpty) return null;
      return WritingEntry(topic: topic, reference: obj['reference']?.toString() ?? '');
    }
    return null;
  }

  /// 词汇题词库校验：正确选项或题干中出现不在专升本词库的显著单词时判定超纲
  bool _isVocabQOutOfDict(Question q) {
    if (DictService.zsbWords().isEmpty) return false; // 词库未加载时跳过校验
    // 1) 正确选项中长度>=4的单词查不到词库 → 超纲
    if (q.answerIdx >= 0 && q.answerIdx < q.options.length) {
      final ansWords = _alphaTokens(q.options[q.answerIdx]).where((w) => w.length >= 4).toList();
      if (ansWords.isNotEmpty && ansWords.any((w) => !_inZsbDict(w))) return true;
    }
    // 2) 题干中长单词（>=5字母）有 3 个以上查不到词库 → 超纲
    final stemWords = _alphaTokens(q.question).where((w) => w.length >= 5).toList();
    if (stemWords.length >= 4) {
      final miss = stemWords.where((w) => !_inZsbDict(w)).length;
      if (miss >= 3) return true;
    }
    return false;
  }

  List<String> _alphaTokens(String text) =>
      RegExp(r"[A-Za-z']+").allMatches(text).map((m) => m.group(0)!.toLowerCase()).toList();

  /// 单词是否在专升本词库内（尝试去除常见屈折后缀后再次查询）
  bool _inZsbDict(String w) {
    if (DictService.zsbLookup(w) != null) return true;
    for (final suf in const ['ing', 'ed', 'es', 's', 'ly', 'er', 'd']) {
      if (w.length > suf.length + 2 && w.endsWith(suf)) {
        if (DictService.zsbLookup(w.substring(0, w.length - suf.length)) != null) return true;
      }
    }
    return false;
  }

  /// 本地兜底：用 zsb-dict.json 词库模板生成一批词汇单选题（AI 重试失败时保证试卷完整）
  List<Question>? _buildLocalVocabBatch(int count) {
    final rng = Random();
    final out = <Question>[];
    for (var i = 0; i < count; i++) {
      final q = _buildLocalVocabQuestion(rng);
      if (q == null) break;
      out.add(q);
    }
    return out.isEmpty ? null : out;
  }

  /// 单道词库模板题：随机选词作题干，其 translation 为正确选项，
  /// 另随机取 3 个词的 translation 作干扰项（保证选项唯一且不重复）
  Question? _buildLocalVocabQuestion(Random rng) {
    final words = DictService.zsbWords();
    if (words.length < 20) return null;
    for (var tries = 0; tries < 30; tries++) {
      final w = words[rng.nextInt(words.length)];
      final e = DictService.zsbLookup(w);
      final correct = e?.translation.trim() ?? '';
      if (correct.isEmpty) continue;
      final distractors = <String>[];
      var guard = 0;
      while (distractors.length < 3 && guard++ < 80) {
        final w2 = words[rng.nextInt(words.length)];
        if (w2 == w) continue;
        final t = DictService.zsbLookup(w2)?.translation.trim() ?? '';
        if (t.isEmpty || t == correct || distractors.contains(t)) continue;
        distractors.add(t);
      }
      if (distractors.length < 3) continue;
      final opts = <String>[correct, ...distractors]..shuffle(rng);
      final idx = opts.indexOf(correct);
      return Question(
        type: QType.choice,
        level: 'zsb',
        question: 'The word "$w" most probably means ____.',
        text: 'The word "$w" most probably means ____.',
        chinese: '',
        english: '',
        correctAnswer: '',
        options: opts,
        answerIdx: idx,
        answerLetter: String.fromCharCode(65 + idx),
        analysis: '本地词库兜底题：$w ${e!.phonetic} ${e.pos} $correct',
        knowledge: ['词汇（本地兜底）'],
      );
    }
    return null;
  }

  /// 本地兜底：从题库真题（questions.json，en=英文句 / text=中文参考译文，
  /// 与 En2zh5Entry 字段兼容）随机抽 5 道翻译题填充英译汉部分
  En2zh5Entry? _buildLocalEn2zh5Batch() {
    final zhRe = RegExp(r'[\u4e00-\u9fff]');
    final cand = questions.where((q) {
      final en = q.english.trim();
      final zh = q.text.trim();
      if (zh.isEmpty) return false;
      if (en.length < 15 || en.length > 240) return false;
      if (zhRe.hasMatch(en)) return false; // 英文句混入中文的脏数据不采用
      if (en.contains('/') || en.contains('____')) return false; // 多答案变体/残缺句不采用
      return true;
    }).toList();
    if (cand.length < 5) return null;
    cand.shuffle(Random());
    final picked = cand.take(5).toList();
    return En2zh5Entry(
      sentences: picked.map((q) => q.english.trim()).toList(),
      answers: picked.map((q) => q.text.trim()).toList(),
    );
  }

  /// 生成一套 mock 试卷（供 F7 快捷预览考场界面，不调用 AI）
  void loadMockExam() {
    final vocab = List.generate(20, (i) => Question(
      type: QType.choice,
      level: 'zsb',
      question: '第${i + 1}题：Choose the correct answer to fill in the blank.',
      text: '第${i + 1}题：Choose the correct answer to fill in the blank.',
      chinese: '',
      options: ['A. option one', 'B. option two', 'C. option three', 'D. option four'],
      answerIdx: 0,
      answerLetter: 'A',
      analysis: '解析：示例选项。',
      knowledge: ['语法'],
    ));
    final readings = List.generate(4, (pi) => Question(
      type: QType.reading,
      level: 'zsb',
      passage: 'This is a sample reading passage for passage ${pi + 1}. It is designed to let you preview the exam room interface. The actual content will be generated by AI when you start a real exam.',
      questions: List.generate(5, (qi) => ReadingSubQ(
        question: 'Question ${qi + 1} for passage ${pi + 1}: What is the main idea?',
        options: ['A. First option', 'B. Second option', 'C. Third option', 'D. Fourth option'],
        answerIdx: 0,
        answerLetter: 'A',
        analysis: '解析：示例。',
        knowledge: [],
      )),
      text: '阅读理解',
      chinese: '',
      english: '',
      correctAnswer: '',
      userAnswers: List.filled(5, null),
    ));
    final clozeSubs = List.generate(15, (i) => ClozeSubQ(
      blankIdx: i + 1,
      sentence: 'Sample sentence ${i + 1} with a ____ for cloze test.',
      options: ['A. first', 'B. second', 'C. third', 'D. fourth'],
      answerIdx: 0,
      answerLetter: 'A',
      analysis: '解析：示例。',
    ));
    final dialogue = DialogueEntry(
      scenario: '场景：打电话预订餐厅（示例对话）',
      dialogueLines: ['A: Hello, ___1___', 'B: Good evening! ___2___', 'A: I would like to book a table for four.', 'B: ___3___', 'A: At 7 PM.', 'B: Let me check. ___4___', 'A: Yes, that is correct.', 'B: ___5___ See you then.'],
      options: ['I would like to make a reservation.', 'How can I help you?', 'For what time?', 'Is that for this Friday?', 'Great, your table is booked.', 'F. Option F (extra).', 'G. Option G (extra).'],
      answerLetters: ['A', 'B', 'C', 'D', 'E'],
      analyses: ['解析1', '解析2', '解析3', '解析4', '解析5'],
    );
    final bankedCloze = BankedClozeEntry(
      passage: 'This is a sample passage for banked cloze. It contains 10 blanks (____1____ to ____10____) for you to preview the interface.',
      wordBank: List.generate(15, (i) => 'word${i + 1}'),
      answerWords: List.generate(10, (i) => 'word${i + 1}'),
      analyses: List.generate(10, (i) => '解析${i + 1}'),
    );
    final en2zh5 = En2zh5Entry(
      sentences: [
        'This is the first sample English sentence for translation.',
        'The second sentence is about previewing the exam interface.',
        'A third sentence to demonstrate the translation section.',
        'Here is the fourth sample sentence for you to translate.',
        'Finally, the fifth sentence completes this section.',
      ],
      answers: [
        '这是第一个示例英文句子的中文翻译。',
        '第二个句子关于预览考试界面。',
        '第三个句子展示翻译部分。',
        '这是第四个示例句子供你翻译。',
        '最后，第五个句子完成了这一部分。',
      ],
    );
    final writing = WritingEntry(
      topic: '写作题：请以"The Importance of Learning English"为题，写一篇不少于120词的英文短文。（示例题目）',
      reference: 'Learning English is of great importance in today\'s world...',
    );
    final paper = FullExamPaper(
      title: '【预览模式】专升本综合模拟全卷（示例数据）',
      totalTimeMin: 120,
      vocab: vocab,
      readings: readings,
      cloze: [Question(type: QType.cloze, level: 'zsb', passage: 'Sample cloze passage.', text: '', chinese: '', english: '', correctAnswer: '')],
      clozeSubs: clozeSubs,
      dialogue: dialogue,
      bankedCloze: bankedCloze,
      en2zh5: en2zh5,
      writing: writing,
    );
    currentExamPaper = paper;
    enterFullExam();
  }

  /// 用户在对话助手确认"进入考场"后调用：初始化答题卡，进入沉浸考场
  void enterFullExam() {
    if (currentExamPaper == null) return;
    examPendingConfirm = false;
    currentExamAnswerSheet = ExamAnswerSheet();
    currentExamResult = null; // 重开考试时清除上一轮成绩，保证 setPage 考场守卫生效
    examRemainingSec = currentExamPaper!.totalTimeMin * 60;
    examStartTs = DateTime.now().millisecondsSinceEpoch;
    examCurrentQuestion = 1;
    page = 10; // 沉浸考场
    notifyListeners();
  }

  /// 交卷：自动判分（客观题直接判，英译汉和写作先用关键词打分），切换到成绩页
  ExamResult submitFullExam() {
    final paper = currentExamPaper!;
    final ans = currentExamAnswerSheet!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final dur = ((now - examStartTs) / 1000).round();
    final durationSec = dur > 0 ? dur : (paper.totalTimeMin * 60 - examRemainingSec).clamp(0, paper.totalTimeMin * 60);

    final sectionScores = <ExamSection, int>{};
    final sectionMax = <ExamSection, int>{};
    final sectionCorrect = <ExamSection, int>{};
    final sectionTotal = <ExamSection, int>{};

    // 一、词汇与语法（20单选）
    {
      var correct = 0;
      var total = 0;
      for (var i = 0; i < 20; i++) {
        if (i < paper.vocab.length) {
          total++;
          final q = paper.vocab[i];
          final user = ans.vocab[i];
          if (user != null && user == q.answerIdx) correct++;
        }
      }
      final sc = correct * ExamSection.vocab.scorePerQuestion;
      sectionScores[ExamSection.vocab] = sc;
      sectionMax[ExamSection.vocab] = 20 * ExamSection.vocab.scorePerQuestion;
      sectionCorrect[ExamSection.vocab] = correct;
      sectionTotal[ExamSection.vocab] = total;
    }
    // 二、阅读理解 4篇 x 5
    {
      var correct = 0;
      var total = 0;
      for (var pi = 0; pi < 4; pi++) {
        if (pi >= paper.readings.length) continue;
        final r = paper.readings[pi];
        final userSheet = ans.reading[pi];
        for (var qi = 0; qi < 5; qi++) {
          if (qi >= r.questions.length) continue;
          total++;
          if (userSheet[qi] == r.questions[qi].answerIdx) correct++;
        }
      }
      final sc = correct * ExamSection.reading.scorePerQuestion;
      sectionScores[ExamSection.reading] = sc;
      sectionMax[ExamSection.reading] = 20 * ExamSection.reading.scorePerQuestion;
      sectionCorrect[ExamSection.reading] = correct;
      sectionTotal[ExamSection.reading] = total;
    }
    // 三、完形填空 15
    {
      var correct = 0;
      var total = 0;
      final subs = paper.clozeSubs ?? [];
      for (var i = 0; i < 15; i++) {
        if (i >= subs.length) continue;
        total++;
        if (ans.cloze[i] == subs[i].answerIdx) correct++;
      }
      final sc = correct * ExamSection.cloze.scorePerQuestion;
      sectionScores[ExamSection.cloze] = sc;
      sectionMax[ExamSection.cloze] = 15 * ExamSection.cloze.scorePerQuestion;
      sectionCorrect[ExamSection.cloze] = correct;
      sectionTotal[ExamSection.cloze] = total;
    }
    // 四、补全对话 5
    {
      var correct = 0;
      var total = 0;
      final dl = paper.dialogue;
      if (dl != null) {
        for (var i = 0; i < 5; i++) {
          if (i >= dl.answerLetters.length) continue;
          total++;
          final letter = dl.answerLetters[i].toUpperCase();
          final correctIdx = letter.isEmpty ? -1 : letter.codeUnitAt(0) - 65;
          if (ans.dialogue[i] == correctIdx && correctIdx >= 0) correct++;
        }
      }
      final sc = correct * ExamSection.dialogue.scorePerQuestion;
      sectionScores[ExamSection.dialogue] = sc;
      sectionMax[ExamSection.dialogue] = 5 * ExamSection.dialogue.scorePerQuestion;
      sectionCorrect[ExamSection.dialogue] = correct;
      sectionTotal[ExamSection.dialogue] = total;
    }
    // 五、选词填空 10
    {
      var correct = 0;
      var total = 0;
      final bc = paper.bankedCloze;
      if (bc != null) {
        for (var i = 0; i < 10; i++) {
          if (i >= bc.answerWords.length) continue;
          total++;
          final userIdx = ans.bankedCloze[i];
          if (userIdx != null &&
              userIdx >= 0 &&
              userIdx < bc.wordBank.length &&
              bc.wordBank[userIdx].toLowerCase().trim() == bc.answerWords[i].toLowerCase().trim()) {
            correct++;
          }
        }
      }
      final sc = correct * ExamSection.bankedCloze.scorePerQuestion;
      sectionScores[ExamSection.bankedCloze] = sc;
      sectionMax[ExamSection.bankedCloze] = 10 * ExamSection.bankedCloze.scorePerQuestion;
      sectionCorrect[ExamSection.bankedCloze] = correct;
      sectionTotal[ExamSection.bankedCloze] = total;
    }
    // 六、英译汉 5（关键词命中比例打分）
    {
      var sc = 0;
      var total = 0;
      final e5 = paper.en2zh5;
      if (e5 != null) {
        for (var i = 0; i < 5; i++) {
          if (i >= e5.answers.length || i >= ans.en2zh5.length) continue;
          total++;
          final ref = e5.answers[i];
          final user = ans.en2zh5[i];
          if (ref.isEmpty || user.isEmpty) continue;
          final tokens = ref.replaceAll(RegExp(r'[，。；：、\s]'), '').split('').where((c) => c.isNotEmpty).toList();
          final hit = tokens.where((t) => user.contains(t)).length;
          final pct = tokens.isEmpty ? 0.0 : hit / tokens.length;
          final one = min(ExamSection.en2zh5.scorePerQuestion, (pct * ExamSection.en2zh5.scorePerQuestion).round());
          sc += one;
        }
      }
      sectionScores[ExamSection.en2zh5] = sc;
      sectionMax[ExamSection.en2zh5] = 5 * ExamSection.en2zh5.scorePerQuestion;
      sectionCorrect[ExamSection.en2zh5] = sectionMax[ExamSection.en2zh5] == 0 ? 0 : (sc ~/ ExamSection.en2zh5.scorePerQuestion);
      sectionTotal[ExamSection.en2zh5] = total;
    }
    // 七、写作（字数 + 关键词启发式，满分 35，依据四川专升本 2024/2025 真题给分）
    const _wMax = 35;
    int wScoreNum = 0;
    String wScore = '';
    final w = paper.writing;
    if (w != null) {
      final u = ans.writing.trim();
      final words = u.split(RegExp(r'\s+')).where((w) => w.length > 0).length;
      final refWords = w.reference.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).length;
      // 关键词覆盖
      final kw = w.reference.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase().split(RegExp(r'\s+')).where((x) => x.length >= 5).toSet().toList().take(30).toList();
      var kwHit = 0;
      final uLow = u.toLowerCase();
      for (final k in kw) {
        if (uLow.contains(k)) kwHit++;
      }
      final kwRatio = kw.isEmpty ? 0.0 : kwHit / kw.length;
      final wordRatio = refWords == 0 ? 0.0 : words / refWords;
      // 基础分：字数达标 120 词给 17；关键词覆盖比例 * 11；书写表达 7（合计 35）
      final baseWords = words >= 120 ? 17 : (words / 120 * 17).round();
      final kwPart = (kwRatio * 11).round();
      final exprPart = (wordRatio * 7).clamp(0, 7).round();
      final totalW = (baseWords + kwPart + exprPart).clamp(0, _wMax);
      wScoreNum = totalW;
      if (totalW >= 30) {
        wScore = '优秀（$totalW/$_wMax）：文章结构完整，用词准确，句式多样，符合要求。';
      } else if (totalW >= 23) {
        wScore = '良好（$totalW/$_wMax）：内容切题，表达较清晰，有少量语法错误但不影响理解。';
      } else if (totalW >= 16) {
        wScore = '中等（$totalW/$_wMax）：内容基本切题，可使用更多高级词汇和复杂句型。';
      } else if (totalW >= 9) {
        wScore = '及格（$totalW/$_wMax）：字数或内容有缺失，句子错误较多，建议加强练习。';
      } else {
        wScore = '较低（$totalW/$_wMax）：内容薄弱，建议从写作模板和高频词汇入手练习。';
      }
    }
    sectionScores[ExamSection.writing] = wScoreNum;
    sectionMax[ExamSection.writing] = _wMax;
    sectionCorrect[ExamSection.writing] = wScoreNum;
    sectionTotal[ExamSection.writing] = _wMax;

    final totalScore = sectionScores.values.fold<int>(0, (a, b) => a + b);
    final maxScore = sectionMax.values.fold<int>(0, (a, b) => a + b);
    final result = ExamResult(
      paper: paper,
      answers: ans,
      durationSec: durationSec,
      totalScore: totalScore,
      maxScore: maxScore,
      sectionScores: sectionScores,
      sectionMax: sectionMax,
      sectionCorrect: sectionCorrect,
      sectionTotal: sectionTotal,
      writingScore: wScore,
      writingScoreNum: wScoreNum,
      submittedAt: now,
    );
    currentExamResult = result;
    // 持久化：最近一次试卷 + 成绩，并追加历史摘要（最多 10 条）
    Storage.saveLastExamPaper(paper);
    Storage.saveLastExamResult(result);
    examHistory.insert(
      0,
      ExamHistoryEntry(
        submittedAt: now,
        title: paper.title,
        totalScore: totalScore,
        maxScore: maxScore,
        rank: result.rank,
        durationSec: durationSec,
      ),
    );
    if (examHistory.length > 10) examHistory.removeRange(10, examHistory.length);
    Storage.saveExamHistory(examHistory);
    // 客观题错题写入错题本（英译汉/写作等主观题不写入）
    _writeExamWrongToBook(paper, ans);
    page = 11;
    notifyListeners();
    // 不阻塞交卷：成绩已即时呈现，异步发起主观题 AI 批改（未配置/失败静默回退）
    refineExamSubjectiveWithAI();
    return result;
  }

  /// 交卷落盘后异步对主观题（英译汉 5 句 + 写作）发起一次 AI 批改：
  /// - AI 未配置 / 请求失败 / 解析失败时静默回退，保留本地启发式分数与点评；
  /// - AI 返回合法得分时以 AI 分为准重算分区得分与总分（rank 为 getter 自动重算），
  ///   并再次落盘成绩与历史摘要（最近一条总分被修正时同步更新）。
  Future<void> refineExamSubjectiveWithAI() async {
    try {
      final r = currentExamResult;
      if (r == null || r.aiGraded || r.aiGrading) return;
      if (!apiConfig.ready) return; // 未配置 AI：静默保留本地启发式判分
      final paper = r.paper;
      final ans = r.answers;
      final e5 = paper.en2zh5;
      final w = paper.writing;
      final hasEn2zh = e5 != null && ans.en2zh5.any((s) => s.trim().isNotEmpty);
      final hasWriting = w != null && ans.writing.trim().isNotEmpty;
      final e5s = hasEn2zh ? e5 : null;
      final ws = hasWriting ? w : null;
      if (!hasEn2zh && !hasWriting) return; // 主观题无作答内容，无需批改
      final submittedAt = r.submittedAt; // 用于识别批改期间是否已切换/重考
      r.aiGrading = true;
      Storage.saveLastExamResult(r);
      notifyListeners();

      // 组装一次性请求：英译汉逐句（参考答案 + 用户译文）+ 写作（题目要求 + 用户作文）
      final sb = StringBuffer();
      int sentCount = 0;
      if (e5s != null) {
        sb.writeln('【英译汉】共 5 句，每句 0-3 分（0=未作答或完全错误，1=要点零星，2=要点基本完整，3=准确流畅）：');
        for (var i = 0; i < 5 && i < e5s.sentences.length; i++) {
          final user = i < ans.en2zh5.length ? ans.en2zh5[i].trim() : '';
          final ref = i < e5s.answers.length ? e5s.answers[i] : '';
          sb.writeln('第${i + 1}句 英文：${e5s.sentences[i]}');
          sb.writeln('参考译文：$ref');
          sb.writeln('学生译文：${user.isEmpty ? '（未作答）' : user}');
          sentCount++;
        }
      }
      if (ws != null) {
        sb.writeln('【写作】满分 20 分，请按内容切题、结构组织、语言准确性、词汇句式丰富度综合评分：');
        sb.writeln('题目要求：${ws.topic}');
        sb.writeln('学生作文：${ans.writing.trim()}');
      }
      final systemPrompt = '你是专升本英语考试阅卷老师，请批改以下主观题并只返回一个 JSON 对象（不要输出其他内容），格式：\n'
          '{"translation":[{"score":0到3整数,"comment":"该句中文点评(30字内)"},共$sentCount项按句序],'
          '"writing":{"score":0到20整数,"comment":"总体中文点评(60字内)","suggestion":"改进建议(60字内)"}}\n'
          '未作答给 0 分；评分客观公正，点评简洁。';
      final reply = await ApiService.callAI(
        [{'role': 'user', 'content': sb.toString()}],
        systemPrompt,
        config: apiConfig,
        maxTokens: 3072,
        extraParams: _noThinkingParams(),
      );
      final json = reply == null || reply.isEmpty ? null : ApiService.extractJsonObject(reply);
      if (json == null) {
        // 请求失败 / 解析失败：静默回退，保留本地启发式判分与文案
        if (currentExamResult == r && currentExamResult?.submittedAt == submittedAt) {
          r.aiGrading = false;
          Storage.saveLastExamResult(r);
          notifyListeners();
        }
        return;
      }

      // ===== 解析 AI 结果（任何异常均静默回退）=====
      List<int>? tScores;
      List<String>? tComments;
      final tRaw = json['translation'];
      if (hasEn2zh && tRaw is List && tRaw.isNotEmpty) {
        final scores = <int>[];
        final comments = <String>[];
        var valid = true;
        for (var i = 0; i < sentCount; i++) {
          final e = i < tRaw.length ? tRaw[i] : null;
          final sc = e is Map ? e['score'] : null;
          if (sc is! num) {
            valid = false;
            break;
          }
          scores.add(sc.toInt().clamp(0, 3));
          comments.add(e is Map ? (e['comment'] ?? '').toString() : '');
        }
        if (valid && scores.length == sentCount) {
          tScores = scores;
          tComments = comments;
        }
      }
      int? wScore;
      String wComment = '';
      String wSuggestion = '';
      final wRaw = json['writing'];
      if (hasWriting && wRaw is Map && wRaw['score'] is num) {
        wScore = (wRaw['score'] as num).toInt().clamp(0, 20);
        wComment = (wRaw['comment'] ?? '').toString();
        wSuggestion = (wRaw['suggestion'] ?? '').toString();
      }
      if (tScores == null && wScore == null) {
        // AI 返回结构不合法：静默回退
        if (currentExamResult == r && currentExamResult?.submittedAt == submittedAt) {
          r.aiGrading = false;
          Storage.saveLastExamResult(r);
          notifyListeners();
        }
        return;
      }

      // ===== 分数融合：以 AI 分为准重算分区得分 =====
      if (tScores != null) {
        final sum = tScores.fold<int>(0, (a, b) => a + b);
        r.sectionScores[ExamSection.en2zh5] = sum;
        r.sectionCorrect[ExamSection.en2zh5] = sum ~/ ExamSection.en2zh5.scorePerQuestion;
        r.en2zh5AiComments = List<String>.generate(
          5,
          (i) => i < tComments!.length ? tComments[i] : '',
          growable: false,
        );
      }
      if (wScore != null) {
        r.sectionScores[ExamSection.writing] = wScore;
        r.sectionCorrect[ExamSection.writing] = wScore;
        r.writingScoreNum = wScore;
        r.writingScore = wComment.isNotEmpty ? wComment : '（$wScore/20）';
        r.writingAiSuggestion = wSuggestion;
      }
      r.totalScore = r.sectionScores.values.fold<int>(0, (a, b) => a + b);
      r.aiGrading = false;
      r.aiGraded = true;

      // ===== 完成后再次落盘（与 Task #18 持久化时序兼容）=====
      if (currentExamResult == r && currentExamResult?.submittedAt == submittedAt) {
        Storage.saveLastExamResult(r);
        if (examHistory.isNotEmpty && examHistory.first.submittedAt == submittedAt) {
          examHistory.first.totalScore = r.totalScore;
          examHistory.first.rank = r.rank;
          Storage.saveExamHistory(examHistory);
        }
        notifyListeners();
      } else {
        // 批改期间用户已退出或重新开考：仅把批改结果写回存档，不干扰当前状态
        Storage.saveLastExamResult(r);
      }
    } catch (_) {
      // 任何异常静默回退：保留本地启发式判分，不弹错误
      final r = currentExamResult;
      if (r != null && r.aiGrading) {
        r.aiGrading = false;
        notifyListeners();
      }
    }
  }

  /// 选项索引 → 字母（越界时返回序号文本）
  String _examLetter(int idx) => idx >= 0 && idx < 8 ? 'ABCDEFGH'[idx] : '${idx + 1}';

  /// 交卷后把客观题错题（词汇语法/阅读/完形/补全对话/选词填空）写入错题本；
  /// 按题干去重（错题本已有同题干记录或本批重复均跳过），主观题不写入。
  void _writeExamWrongToBook(FullExamPaper paper, ExamAnswerSheet ans) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final pending = <WrongItem>[];
    final seen = <String>{};

    void tryAdd(Question q, String userAns, String correctAns) {
      final key = wrongKey(q);
      if (key.isEmpty || seen.contains(key)) return;
      if (wrongQuestions.any((w) => wrongKey(w.question) == key)) return;
      seen.add(key);
      pending.add(WrongItem(
        id: '${now}_${pending.length}_${Random().toString().substring(2, 7)}',
        question: q,
        userAnswer: userAns,
        correctAnswer: correctAns,
        score: 0,
        wrongCount: 1,
        firstWrongTime: now,
        lastWrongTime: now,
        direction: 'exam',
      ));
    }

    // 一、词汇与语法（单选）
    for (var i = 0; i < paper.vocab.length && i < ans.vocab.length; i++) {
      final q = paper.vocab[i];
      final u = ans.vocab[i];
      if (u == null || u == q.answerIdx) continue;
      tryAdd(q, _examLetter(u), q.answerLetter.isNotEmpty ? q.answerLetter : _examLetter(q.answerIdx));
    }
    // 二、阅读理解
    for (var pi = 0; pi < paper.readings.length && pi < ans.reading.length; pi++) {
      final r = paper.readings[pi];
      for (var qi = 0; qi < r.questions.length && qi < ans.reading[pi].length; qi++) {
        final sub = r.questions[qi];
        final u = ans.reading[pi][qi];
        if (u == null || u == sub.answerIdx) continue;
        final q = Question(
          type: QType.reading,
          level: 'zsb',
          text: '阅读第${pi + 1}篇·第${qi + 1}题：${sub.question}',
          passage: r.passage,
          options: sub.options,
          answerIdx: sub.answerIdx,
          answerLetter: sub.answerLetter,
          analysis: sub.analysis,
        );
        tryAdd(q, _examLetter(u), sub.answerLetter.isNotEmpty ? sub.answerLetter : _examLetter(sub.answerIdx));
      }
    }
    // 三、完形填空
    final subs = paper.clozeSubs ?? [];
    for (var i = 0; i < subs.length && i < ans.cloze.length; i++) {
      final sub = subs[i];
      final u = ans.cloze[i];
      if (u == null || u == sub.answerIdx) continue;
      final q = Question(
        type: QType.cloze,
        level: 'zsb',
        text: '完形填空第${sub.blankIdx}空：${sub.sentence}',
        options: sub.options,
        answerIdx: sub.answerIdx,
        answerLetter: sub.answerLetter,
        analysis: sub.analysis,
      );
      tryAdd(q, _examLetter(u), sub.answerLetter.isNotEmpty ? sub.answerLetter : _examLetter(sub.answerIdx));
    }
    // 四、补全对话
    final dl = paper.dialogue;
    if (dl != null) {
      for (var i = 0; i < dl.answerLetters.length && i < ans.dialogue.length; i++) {
        final u = ans.dialogue[i];
        final correctLetter = dl.answerLetters[i].toUpperCase();
        final correctIdx = correctLetter.isEmpty ? -1 : correctLetter.codeUnitAt(0) - 65;
        if (u == null || correctIdx < 0 || u == correctIdx) continue;
        final q = Question(
          type: QType.dialogue,
          level: 'zsb',
          text: '补全对话第${i + 1}空（${dl.scenario}）',
          options: dl.options,
          answerIdx: correctIdx,
          answerLetter: correctLetter,
          analysis: i < dl.analyses.length ? dl.analyses[i] : '',
        );
        tryAdd(q, _examLetter(u), correctLetter);
      }
    }
    // 五、选词填空
    final bc = paper.bankedCloze;
    if (bc != null) {
      for (var i = 0; i < bc.answerWords.length && i < ans.bankedCloze.length; i++) {
        final u = ans.bankedCloze[i];
        if (u == null) continue;
        final userWord = u >= 0 && u < bc.wordBank.length ? bc.wordBank[u] : '';
        final correctWord = bc.answerWords[i];
        if (userWord.toLowerCase().trim() == correctWord.toLowerCase().trim()) continue;
        final q = Question(
          type: QType.bankedCloze,
          level: 'zsb',
          text: '选词填空第${i + 1}空（从词库选词的正确形式填入）',
          options: bc.wordBank,
          correctAnswer: correctWord,
          analysis: i < bc.analyses.length ? bc.analyses[i] : '',
        );
        tryAdd(q, userWord, correctWord);
      }
    }

    if (pending.isEmpty) return;
    wrongQuestions.insertAll(0, pending);
    Storage.saveWrongQuestions(wrongQuestions);
  }

  /// 退出考场/成绩页返回主界面
  void exitFullExam() {
    page = 0;
    notifyListeners();
  }

  /// 把 1-based 题号映射到对应分区内的相对位置，
  /// 返回 (section, relativeIdx 0-based, reading passageIdx or -1)
  ({ExamSection section, int relIdx, int passageIdx}) resolveExamQuestion(int idx1) {
    if (ExamSection.vocab.containsQuestion(idx1)) {
      return (section: ExamSection.vocab, relIdx: idx1 - ExamSection.vocab.startIndex, passageIdx: -1);
    }
    if (ExamSection.reading.containsQuestion(idx1)) {
      final rel = idx1 - ExamSection.reading.startIndex; // 0..19
      return (section: ExamSection.reading, relIdx: rel % 5, passageIdx: rel ~/ 5);
    }
    if (ExamSection.cloze.containsQuestion(idx1)) {
      return (section: ExamSection.cloze, relIdx: idx1 - ExamSection.cloze.startIndex, passageIdx: -1);
    }
    if (ExamSection.dialogue.containsQuestion(idx1)) {
      return (section: ExamSection.dialogue, relIdx: idx1 - ExamSection.dialogue.startIndex, passageIdx: -1);
    }
    if (ExamSection.bankedCloze.containsQuestion(idx1)) {
      return (section: ExamSection.bankedCloze, relIdx: idx1 - ExamSection.bankedCloze.startIndex, passageIdx: -1);
    }
    if (ExamSection.en2zh5.containsQuestion(idx1)) {
      return (section: ExamSection.en2zh5, relIdx: idx1 - ExamSection.en2zh5.startIndex, passageIdx: -1);
    }
    return (section: ExamSection.writing, relIdx: 0, passageIdx: -1);
  }

  /// 考试倒计时心跳（UI 层每 1 秒调用一次）
  void tickExamTimer() {
    if (examRemainingSec <= 0) return;
    examRemainingSec--;
    notifyListeners();
    if (examRemainingSec == 0) {
      // 时间到，自动交卷
      submitFullExam();
    }
  }
}
