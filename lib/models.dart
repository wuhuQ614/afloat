/// 数据模型：与网页版 index.html 中的数据结构保持一致
library;

/// 题型
enum QType {
  translation,
  choice,
  reading,
  grammar,
  writing,
  dictation,
  cloze,
  dialogue,
  bankedCloze,
  en2zh5,
}

QType qTypeFrom(String s) {
  switch (s) {
    case 'choice':
      return QType.choice;
    case 'reading':
      return QType.reading;
    case 'grammar':
      return QType.grammar;
    case 'writing':
      return QType.writing;
    case 'dictation':
      return QType.dictation;
    case 'cloze':
    case '完型填空':
    case '完形填空':
      return QType.cloze;
    case 'dialogue':
    case '补全对话':
      return QType.dialogue;
    case 'bankedCloze':
    case '选词填空':
      return QType.bankedCloze;
    case 'en2zh5':
    case '英译汉':
      return QType.en2zh5;
    default:
      return QType.translation;
  }
}

String qTypeName(QType t) {
  switch (t) {
    case QType.translation:
      return '翻译题';
    case QType.choice:
      return '选择题';
    case QType.reading:
      return '阅读理解';
    case QType.grammar:
      return '语法填空';
    case QType.writing:
      return '写作题';
    case QType.dictation:
      return '默写题';
    case QType.cloze:
      return '完形填空';
    case QType.dialogue:
      return '补全对话';
    case QType.bankedCloze:
      return '选词填空';
    case QType.en2zh5:
      return '英译汉';
  }
}

String levelName(String l) {
  switch (l) {
    case 'cet4':
      return '四级';
    case 'zsb':
      return '专升本';
    case 'easy':
      return '简单';
    case 'hard':
      return '困难';
    default:
      return '中等';
  }
}

/// 词典条目
class DictEntry {
  final String pos;
  final String translation;
  final String other;
  final String phonetic;

  const DictEntry({this.pos = '', this.translation = '', this.other = '', this.phonetic = ''});

  factory DictEntry.fromJson(Map<String, dynamic> j) => DictEntry(
        pos: (j['pos'] ?? '') as String,
        translation: (j['translation'] ?? '') as String,
        other: (j['other'] ?? '') as String,
        phonetic: (j['phonetic'] ?? '') as String,
      );
}

/// 阅读理解的子题
class ReadingSubQ {
  String question;
  List<String> options;
  int answerIdx;
  String answerLetter;
  String analysis;
  List<String> knowledge;

  ReadingSubQ({
    this.question = '',
    List<String>? options,
    this.answerIdx = -1,
    this.answerLetter = '',
    this.analysis = '',
    List<String>? knowledge,
  })  : options = options ?? [],
        knowledge = knowledge ?? [];

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'answerIdx': answerIdx,
        'answerLetter': answerLetter,
        'analysis': analysis,
        'knowledge': knowledge,
      };

  factory ReadingSubQ.fromJson(Map<String, dynamic> j) => ReadingSubQ(
        question: (j['question'] ?? '') as String,
        options: (j['options'] as List?)?.cast<String>() ?? [],
        answerIdx: ((j['answerIdx'] ?? -1) as num).toInt(),
        answerLetter: (j['answerLetter'] ?? '') as String,
        analysis: (j['analysis'] ?? '') as String,
        knowledge: (j['knowledge'] as List?)?.cast<String>() ?? [],
      );
}

/// 题目（兼容翻译/选择/阅读/语法/写作）
class Question {
  QType type;
  String level;
  String text; // 展示文本
  String chinese;
  String english;

  // 选择题
  String question;
  List<String> options;
  int answerIdx;
  String answerLetter;
  String analysis;

  // 阅读理解
  String passage;
  List<ReadingSubQ> questions;

  // 通用
  List<String> knowledge;
  List<ErrorItem> errors;
  int? score;
  String correctAnswer;
  int? bankIdx;
  String src;
  String gtype;

  // 作答状态（不持久化到题库）
  int? userAnswerIdx;
  List<int?> userAnswers;

  Question({
    this.type = QType.translation,
    this.level = 'medium',
    this.text = '',
    this.chinese = '',
    this.english = '',
    this.question = '',
    List<String>? options,
    this.answerIdx = -1,
    this.answerLetter = '',
    this.analysis = '',
    this.passage = '',
    List<ReadingSubQ>? questions,
    List<String>? knowledge,
    List<ErrorItem>? errors,
    this.score,
    this.correctAnswer = '',
    this.bankIdx,
    this.src = '',
    this.gtype = '',
    this.userAnswerIdx,
    List<int?>? userAnswers,
  })  : options = options ?? [],
        questions = questions ?? [],
        knowledge = knowledge ?? [],
        errors = errors ?? [],
        userAnswers = userAnswers ?? [];

  Question copyWith({
    String? text,
    String? chinese,
    String? english,
    String? question,
    List<String>? options,
    int? answerIdx,
    String? answerLetter,
    String? analysis,
    String? passage,
    int? score,
    String? correctAnswer,
    List<ErrorItem>? errors,
    List<String>? knowledge,
    int? userAnswerIdx,
    List<int?>? userAnswers,
  }) =>
      Question(
        type: type,
        level: level,
        text: text ?? this.text,
        chinese: chinese ?? this.chinese,
        english: english ?? this.english,
        question: question ?? this.question,
        options: options ?? List.of(this.options),
        answerIdx: answerIdx ?? this.answerIdx,
        answerLetter: answerLetter ?? this.answerLetter,
        analysis: analysis ?? this.analysis,
        passage: passage ?? this.passage,
        questions: questions,
        knowledge: knowledge ?? this.knowledge,
        errors: errors ?? this.errors,
        score: score ?? this.score,
        correctAnswer: correctAnswer ?? this.correctAnswer,
        bankIdx: bankIdx,
        src: src,
        gtype: gtype,
        userAnswerIdx: userAnswerIdx ?? this.userAnswerIdx,
        userAnswers: userAnswers ?? this.userAnswers,
      );

  /// 是否有完整的选项结构（选择题）
  bool get hasOptions => options.isNotEmpty;

  /// 是否有完整的阅读结构
  bool get hasReading => passage.isNotEmpty && questions.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'level': level,
        'text': text,
        'chinese': chinese,
        'english': english,
        'question': question,
        'options': options,
        'answerIdx': answerIdx,
        'answerLetter': answerLetter,
        'analysis': analysis,
        'passage': passage,
        'questions': questions.map((e) => e.toJson()).toList(),
        'knowledge': knowledge,
        'score': score,
        'correctAnswer': correctAnswer,
        'src': src,
        'gtype': gtype,
        'errors': errors.map((e) => e.toJson()).toList(),
      };

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        type: qTypeFrom((j['type'] ?? 'translation') as String),
        level: (j['level'] ?? 'medium') as String,
        text: (j['text'] ?? '') as String,
        chinese: (j['chinese'] ?? '') as String,
        english: (j['english'] ?? '') as String,
        question: (j['question'] ?? '') as String,
        options: (j['options'] as List?)?.cast<String>() ?? [],
        answerIdx: ((j['answerIdx'] ?? -1) as num).toInt(),
        answerLetter: (j['answerLetter'] ?? '') as String,
        analysis: (j['analysis'] ?? '') as String,
        passage: (j['passage'] ?? '') as String,
        questions: (j['questions'] as List?)?.map((e) => ReadingSubQ.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        knowledge: (j['knowledge'] as List?)?.cast<String>() ?? [],
        errors: (j['errors'] as List?)?.map((e) => ErrorItem.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        score: (j['score'] as num?)?.toInt(),
        correctAnswer: (j['correctAnswer'] ?? '') as String,
        src: (j['src'] ?? '') as String,
        gtype: (j['gtype'] ?? '') as String,
      );

  /// 题库题目（questions.json）解析
  factory Question.fromBank(Map<String, dynamic> j, int idx) => Question(
        type: qTypeFrom((j['type'] ?? 'translation') as String),
        level: (j['level'] ?? 'medium') as String,
        text: (j['text'] ?? '') as String,
        chinese: (j['text'] ?? '') as String,
        english: (j['en'] ?? '') as String,
        src: (j['src'] ?? '') as String,
        gtype: (j['gtype'] ?? '') as String,
        correctAnswer: (j['en'] ?? '') as String,
        bankIdx: idx,
      );
}

/// 批改错误条目
class ErrorItem {
  final String item;
  final String explain;

  ErrorItem({required this.item, this.explain = ''});

  Map<String, dynamic> toJson() => {'item': item, 'explain': explain};

  factory ErrorItem.fromJson(Map<String, dynamic> j) => ErrorItem(
        item: (j['item'] ?? '') as String,
        explain: (j['explain'] ?? '') as String,
      );
}

/// AI 批改结果
class GradingResult {
  int score;
  String correctAnswer;
  List<ErrorItem> errors;
  List<String> knowledge;

  GradingResult({
    this.score = 0,
    this.correctAnswer = '',
    List<ErrorItem>? errors,
    List<String>? knowledge,
  })  : errors = errors ?? [],
        knowledge = knowledge ?? [];

  factory GradingResult.fromJson(Map<String, dynamic> j) => GradingResult(
        score: ((j['score'] ?? 0) as num).toInt(),
        correctAnswer: (j['correctAnswer'] ?? '') as String,
        errors: (j['errors'] as List?)
                ?.map((e) => ErrorItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        knowledge: (j['knowledge'] as List?)?.cast<String>() ?? [],
      );
}

/// 词组信息（用于深度模式下展示词组翻译）
class PhraseInfo {
  final String text; // 词组原文，如 "points out"
  final String translation; // 词组翻译
  /// 词组中每个单词的独立翻译（按顺序对应 text 中的单词）
  final List<String> wordTranslations;

  const PhraseInfo({
    required this.text,
    required this.translation,
    this.wordTranslations = const [],
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'translation': translation,
        'wordTranslations': wordTranslations,
      };

  factory PhraseInfo.fromJson(Map<String, dynamic> j) => PhraseInfo(
        text: (j['text'] ?? '') as String,
        translation: (j['translation'] ?? '') as String,
        wordTranslations: (j['wordTranslations'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

/// 词汇剖析 token
class WordToken {
  final String text;
  final String type; // word / phrase / other
  final String word;
  final String pos;
  final String translation;
  final String other;
  final String contextTranslation; // 深度模式：AI 给出的当前语境释义
  /// 深度模式下，该单词所属的词组列表（含词组翻译和独立单词翻译）
  final List<PhraseInfo> phrases;
  /// 该 token 所属的词组原文（如 "points out"），用于 UI 渲染红色下划线和优先展示词组翻译
  final String phraseGroup;

  const WordToken({
    required this.text,
    this.type = 'other',
    this.word = '',
    this.pos = '',
    this.translation = '',
    this.other = '',
    this.contextTranslation = '',
    this.phrases = const [],
    this.phraseGroup = '',
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'type': type,
        'word': word,
        'pos': pos,
        'translation': translation,
        'other': other,
        'contextTranslation': contextTranslation,
        'phrases': phrases.map((p) => p.toJson()).toList(),
        'phraseGroup': phraseGroup,
      };

  factory WordToken.fromJson(Map<String, dynamic> j) => WordToken(
        text: (j['text'] ?? '') as String,
        type: (j['type'] ?? 'other') as String,
        word: (j['word'] ?? '') as String,
        pos: (j['pos'] ?? '') as String,
        translation: (j['translation'] ?? '') as String,
        other: (j['other'] ?? '') as String,
        contextTranslation: (j['contextTranslation'] ?? '') as String,
        phrases: (j['phrases'] as List?)
                ?.map((e) => PhraseInfo.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        phraseGroup: (j['phraseGroup'] ?? '') as String,
      );

  bool get isMissing => type != 'other' && (translation.isEmpty || translation == '暂无释义');

  /// 该 token 是否属于某个词组
  bool get isPartOfPhrase => phraseGroup.isNotEmpty;

  /// 复制并替换 phrases
  WordToken copyWithPhrases(List<PhraseInfo> phrases) => WordToken(
        text: text,
        type: type,
        word: word,
        pos: pos,
        translation: translation,
        other: other,
        contextTranslation: contextTranslation,
        phrases: phrases,
        phraseGroup: phraseGroup,
      );

  /// 复制并设置 phraseGroup
  WordToken copyWithPhraseGroup(String phraseGroup) => WordToken(
        text: text,
        type: type,
        word: word,
        pos: pos,
        translation: translation,
        other: other,
        contextTranslation: contextTranslation,
        phrases: phrases,
        phraseGroup: phraseGroup,
      );
}

/// API 配置
class ApiConfig {
  String url;
  String key;
  String model;
  String temperature;
  /// 图形能力：是否支持图片/视觉输入。关闭时上传的图片在对话中显示为黑色占位
  bool vision;
  /// 完整 URL：开启时 url 为完整地址（含 /chat/completions），关闭时自动拼接 /chat/completions
  bool fullUrl;
  /// 出题策略：auto=JSON优先（失败自动回退文本行格式） / json=仅JSON / text=仅文本行格式
  String questionMode;
  /// 出题速度：fast=快速（关闭AI思考，直出） / normal=正常（允许AI深度思考）
  String questionSpeed;

  ApiConfig({this.url = '', this.key = '', this.model = 'gpt-5.1', this.temperature = 'default', this.vision = true, this.fullUrl = false, this.questionMode = 'auto', this.questionSpeed = 'fast'});

  bool get ready => url.isNotEmpty && key.isNotEmpty;

  /// 获取实际请求地址：fullUrl 关闭时自动拼接 /chat/completions
  String get effectiveUrl {
    if (fullUrl) return url;
    final trimmed = url.trimRight();
    if (trimmed.endsWith('/chat/completions')) return trimmed;
    return '$trimmed/chat/completions';
  }

  Map<String, dynamic> toJson() => {'url': url, 'key': key, 'model': model, 'temperature': temperature, 'vision': vision, 'fullUrl': fullUrl, 'questionMode': questionMode, 'questionSpeed': questionSpeed};

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
        url: (j['url'] ?? '') as String,
        key: (j['key'] ?? '') as String,
        model: (j['model'] ?? 'gpt-5.1') as String,
        temperature: (j['temperature'] ?? 'default') as String,
        vision: (j['vision'] ?? true) as bool,
        fullUrl: (j['fullUrl'] ?? false) as bool,
        questionMode: (j['questionMode'] ?? 'auto') as String,
        questionSpeed: (j['questionSpeed'] ?? 'fast') as String,
      );
}

/// 已保存的 API 配置（多配置记忆：全局/对话助手可保存多套，随时切换）
class ApiProfile {
  String name;
  ApiConfig config;

  ApiProfile({required this.name, required this.config});

  String get label => name.isEmpty ? config.model : name;

  Map<String, dynamic> toJson() => {'name': name, 'config': config.toJson()};

  factory ApiProfile.fromJson(Map<String, dynamic> j) => ApiProfile(
        name: (j['name'] ?? '') as String,
        config: ApiConfig.fromJson((j['config'] ?? {}) as Map<String, dynamic>),
      );
}

/// 学习记录
class StudyRecord {
  int timestamp;
  QType type;
  String level;
  String direction;
  String text;
  int score;
  bool isWrong;
  int duration;

  StudyRecord({
    required this.timestamp,
    required this.type,
    this.level = 'medium',
    this.direction = 'zh2en',
    this.text = '',
    this.score = 0,
    this.isWrong = false,
    this.duration = 0,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'type': type.name,
        'level': level,
        'direction': direction,
        'text': text,
        'score': score,
        'isWrong': isWrong,
        'duration': duration,
      };

  factory StudyRecord.fromJson(Map<String, dynamic> j) => StudyRecord(
        timestamp: ((j['timestamp'] ?? 0) as num).toInt(),
        type: qTypeFrom((j['type'] ?? 'translation') as String),
        level: (j['level'] ?? 'medium') as String,
        direction: (j['direction'] ?? 'zh2en') as String,
        text: (j['text'] ?? '') as String,
        score: ((j['score'] ?? 0) as num).toInt(),
        isWrong: (j['isWrong'] ?? false) as bool,
        duration: ((j['duration'] ?? 0) as num).toInt(),
      );
}

/// 错题条目（可完整还原题目）
class WrongItem {
  String id;
  Question question;
  String userAnswer;
  String correctAnswer;
  int score;
  int wrongCount;
  int firstWrongTime;
  int lastWrongTime;
  bool mastered;
  String direction;

  WrongItem({
    required this.id,
    required this.question,
    this.userAnswer = '',
    this.correctAnswer = '',
    this.score = 0,
    this.wrongCount = 1,
    required this.firstWrongTime,
    required this.lastWrongTime,
    this.mastered = false,
    this.direction = 'zh2en',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question.toJson(),
        'userAnswer': userAnswer,
        'correctAnswer': correctAnswer,
        'score': score,
        'wrongCount': wrongCount,
        'firstWrongTime': firstWrongTime,
        'lastWrongTime': lastWrongTime,
        'mastered': mastered,
        'direction': direction,
      };

  factory WrongItem.fromJson(Map<String, dynamic> j) => WrongItem(
        id: (j['id'] ?? '') as String,
        question: Question.fromJson((j['question'] ?? {}) as Map<String, dynamic>),
        userAnswer: (j['userAnswer'] ?? '') as String,
        correctAnswer: (j['correctAnswer'] ?? '') as String,
        score: ((j['score'] ?? 0) as num).toInt(),
        wrongCount: ((j['wrongCount'] ?? 1) as num).toInt(),
        firstWrongTime: ((j['firstWrongTime'] ?? 0) as num).toInt(),
        lastWrongTime: ((j['lastWrongTime'] ?? 0) as num).toInt(),
        mastered: (j['mastered'] ?? false) as bool,
        direction: (j['direction'] ?? 'zh2en') as String,
      );
}

/// 收藏题目
class Favorite {
  String text;
  String chinese;
  String english;
  QType type;
  String level;
  int timestamp;

  Favorite({
    this.text = '',
    this.chinese = '',
    this.english = '',
    this.type = QType.translation,
    this.level = 'medium',
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'chinese': chinese,
        'english': english,
        'type': type.name,
        'level': level,
        'timestamp': timestamp,
      };

  factory Favorite.fromJson(Map<String, dynamic> j) => Favorite(
        text: (j['text'] ?? '') as String,
        chinese: (j['chinese'] ?? '') as String,
        english: (j['english'] ?? '') as String,
        type: qTypeFrom((j['type'] ?? 'translation') as String),
        level: (j['level'] ?? 'medium') as String,
        timestamp: ((j['timestamp'] ?? 0) as num).toInt(),
      );
}

/// 记录本单词
class RecordedWord {
  int count;
  int lastSeen;
  int firstSeen;
  List<String> sources;

  RecordedWord({this.count = 0, int? lastSeen, int? firstSeen, List<String>? sources})
      : lastSeen = lastSeen ?? 0,
        firstSeen = firstSeen ?? 0,
        sources = sources ?? [];

  Map<String, dynamic> toJson() => {'count': count, 'lastSeen': lastSeen, 'firstSeen': firstSeen, 'sources': sources};

  factory RecordedWord.fromJson(Map<String, dynamic> j) => RecordedWord(
        count: ((j['count'] ?? 0) as num).toInt(),
        lastSeen: ((j['lastSeen'] ?? 0) as num).toInt(),
        firstSeen: ((j['firstSeen'] ?? 0) as num).toInt(),
        sources: (j['sources'] as List?)?.cast<String>() ?? [],
      );
}

/// 生词本条目
class WordBookItem {
  String word;
  String translation;
  int reviewCount;
  int lastReview;
  int addedAt;

  WordBookItem({
    required this.word,
    this.translation = '',
    this.reviewCount = 0,
    int? lastReview,
    int? addedAt,
  })  : lastReview = lastReview ?? 0,
        addedAt = addedAt ?? 0;

  Map<String, dynamic> toJson() => {'word': word, 'translation': translation, 'reviewCount': reviewCount, 'lastReview': lastReview, 'addedAt': addedAt};

  factory WordBookItem.fromJson(Map<String, dynamic> j) => WordBookItem(
        word: (j['word'] ?? '') as String,
        translation: (j['translation'] ?? '') as String,
        reviewCount: ((j['reviewCount'] ?? 0) as num).toInt(),
        lastReview: ((j['lastReview'] ?? 0) as num).toInt(),
        addedAt: ((j['addedAt'] ?? 0) as num).toInt(),
      );
}

// ============ 全卷模拟考试模型 ============

/// 全卷考试分区：对应四川专升本 2024/2025 改革后 150 分制 7 大题型
enum ExamSection {
  vocab,
  reading,
  cloze,
  dialogue,
  bankedCloze,
  en2zh5,
  writing,
}

extension ExamSectionX on ExamSection {
  String get label {
    switch (this) {
      case ExamSection.vocab:
        return '词汇与语法结构';
      case ExamSection.reading:
        return '阅读理解';
      case ExamSection.cloze:
        return '完形填空';
      case ExamSection.dialogue:
        return '补全对话';
      case ExamSection.bankedCloze:
        return '选词填空';
      case ExamSection.en2zh5:
        return '英译汉';
      case ExamSection.writing:
        return '写作';
    }
  }

  String get shortLabel {
    switch (this) {
      case ExamSection.vocab:
        return '一、词汇语法';
      case ExamSection.reading:
        return '二、阅读';
      case ExamSection.cloze:
        return '三、完形填空';
      case ExamSection.dialogue:
        return '四、补全对话';
      case ExamSection.bankedCloze:
        return '五、选词填空';
      case ExamSection.en2zh5:
        return '六、英译汉';
      case ExamSection.writing:
        return '七、写作';
    }
  }

  /// 每题分值（总分 150，严格依据四川专升本 2024/2025 真题给分）
  int get scorePerQuestion {
    switch (this) {
      case ExamSection.vocab:
        return 1;   // 20题×1=20
      case ExamSection.reading:
        return 2;   // 20题(4篇×5)×2=40
      case ExamSection.cloze:
        return 1;   // 15题×1=15
      case ExamSection.dialogue:
        return 2;   // 5题×2=10
      case ExamSection.bankedCloze:
        return 1;   // 10题×1=10 (15选10)
      case ExamSection.en2zh5:
        return 4;   // 5句×4=20
      case ExamSection.writing:
        return 35;  // 1题×35=35
    }
  }

  /// 该分区题量
  int get questionCount {
    switch (this) {
      case ExamSection.vocab:
        return 20;
      case ExamSection.reading:
        return 20; // 4篇×5题
      case ExamSection.cloze:
        return 15;
      case ExamSection.dialogue:
        return 5;
      case ExamSection.bankedCloze:
        return 10;
      case ExamSection.en2zh5:
        return 5;
      case ExamSection.writing:
        return 1;
    }
  }

  /// 分区总满分
  int get totalScore => scorePerQuestion * questionCount;

  /// 分区在全卷中的起始题号（1-based）
  int get startIndex {
    var s = 1;
    for (final sec in ExamSection.values) {
      if (sec == this) return s;
      s += sec.questionCount;
    }
    return s;
  }

  int get endIndex => startIndex + questionCount - 1;

  /// 分区对应的题号区间是否包含某题（1-based）
  bool containsQuestion(int idx1) => idx1 >= startIndex && idx1 <= endIndex;
}

/// 完形填空小题：一篇文章下的每道选择题
class ClozeSubQ {
  int blankIdx; // 空格编号 1-based
  String sentence; // 该空所在上下文句
  List<String> options; // A-D 4选项
  int answerIdx; // 0-3
  String answerLetter;
  String analysis;
  ClozeSubQ({
    required this.blankIdx,
    this.sentence = '',
    List<String>? options,
    this.answerIdx = -1,
    this.answerLetter = '',
    this.analysis = '',
  }) : options = options ?? [];

  Map<String, dynamic> toJson() => {
        'blankIdx': blankIdx,
        'sentence': sentence,
        'options': options,
        'answerIdx': answerIdx,
        'answerLetter': answerLetter,
        'analysis': analysis,
      };

  factory ClozeSubQ.fromJson(Map<String, dynamic> j) => ClozeSubQ(
        blankIdx: ((j['blankIdx'] ?? j['idx'] ?? 1) as num).toInt(),
        sentence: (j['sentence'] ?? j['context'] ?? '') as String,
        options: (j['options'] as List?)?.cast<String>() ?? [],
        answerIdx: ((j['answerIdx'] ?? -1) as num).toInt(),
        answerLetter: (j['answerLetter'] ?? j['answer'] ?? '') as String,
        analysis: (j['analysis'] ?? j['explain'] ?? '') as String,
      );
}

/// 补全对话：情景 + 5道选择（A-G 7选项选5）
class DialogueEntry {
  String scenario; // 对话场景说明
  List<String> dialogueLines; // 对话原文（含空格占位）
  List<String> options; // A-G 7个待选句子
  List<String> answerLetters; // 5空对应答案字母，e.g. ["C","A","G","D","F"]
  List<String> analyses; // 每道题解析
  DialogueEntry({
    this.scenario = '',
    List<String>? dialogueLines,
    List<String>? options,
    List<String>? answerLetters,
    List<String>? analyses,
  })  : dialogueLines = dialogueLines ?? [],
        options = options ?? [],
        answerLetters = answerLetters ?? [],
        analyses = analyses ?? [];

  Map<String, dynamic> toJson() => {
        'scenario': scenario,
        'dialogueLines': dialogueLines,
        'options': options,
        'answerLetters': answerLetters,
        'analyses': analyses,
      };

  factory DialogueEntry.fromJson(Map<String, dynamic> j) => DialogueEntry(
        scenario: (j['scenario'] ?? '') as String,
        dialogueLines: (j['dialogueLines'] as List?)?.cast<String>() ?? (j['dialogue'] as List?)?.cast<String>() ?? [],
        options: (j['options'] as List?)?.cast<String>() ?? [],
        answerLetters: (j['answerLetters'] as List?)?.cast<String>() ?? (j['answers'] as List?)?.cast<String>() ?? [],
        analyses: (j['analyses'] as List?)?.cast<String>() ?? [],
      );
}

/// 选词填空：15选10
class BankedClozeEntry {
  String passage; // 含 10 个空格（____1____ 等或纯 ____）的文章
  List<String> wordBank; // 15个单词
  List<String> answerWords; // 10空对应单词
  List<String> analyses; // 每空解析
  BankedClozeEntry({
    this.passage = '',
    List<String>? wordBank,
    List<String>? answerWords,
    List<String>? analyses,
  })  : wordBank = wordBank ?? [],
        answerWords = answerWords ?? [],
        analyses = analyses ?? [];

  Map<String, dynamic> toJson() => {
        'passage': passage,
        'wordBank': wordBank,
        'answerWords': answerWords,
        'analyses': analyses,
      };

  factory BankedClozeEntry.fromJson(Map<String, dynamic> j) => BankedClozeEntry(
        passage: (j['passage'] ?? '') as String,
        wordBank: (j['wordBank'] as List?)?.cast<String>() ?? (j['words'] as List?)?.cast<String>() ?? [],
        answerWords: (j['answerWords'] as List?)?.cast<String>() ?? (j['answers'] as List?)?.cast<String>() ?? [],
        analyses: (j['analyses'] as List?)?.cast<String>() ?? [],
      );
}

/// 英译汉 5 句
class En2zh5Entry {
  List<String> sentences; // 5 个英文句子
  List<String> answers; // 对应中文参考翻译
  En2zh5Entry({List<String>? sentences, List<String>? answers})
      : sentences = sentences ?? [],
        answers = answers ?? [];

  Map<String, dynamic> toJson() => {'sentences': sentences, 'answers': answers};

  factory En2zh5Entry.fromJson(Map<String, dynamic> j) => En2zh5Entry(
        sentences: (j['sentences'] as List?)?.cast<String>() ?? [],
        answers: (j['answers'] as List?)?.cast<String>() ?? [],
      );
}

/// 写作题
class WritingEntry {
  String topic; // 题目（中文要求）
  String reference; // 参考范文（英文）
  WritingEntry({this.topic = '', this.reference = ''});

  Map<String, dynamic> toJson() => {'topic': topic, 'reference': reference};

  factory WritingEntry.fromJson(Map<String, dynamic> j) => WritingEntry(
        topic: (j['topic'] ?? j['chinese'] ?? '') as String,
        reference: (j['reference'] ?? j['english'] ?? j['sample'] ?? '') as String,
      );
}

/// 全卷考试数据包
class FullExamPaper {
  int totalTimeMin; // 总时长（分钟）
  String title; // 如 "2025年专升本综合模拟全卷"
  // 第一部分：词汇与语法 20 道单选
  List<Question> vocab;
  // 第二部分：阅读理解 4 篇（每篇 ReadingSubQ）
  List<Question> readings; // 每篇是一个 QType.reading 题
  // 第三部分：完形填空 1 篇
  List<Question> cloze; // 约定只取第一个（为兼容现有 Question 容器保留 List）
  List<ClozeSubQ>? clozeSubs;
  // 第四部分：补全对话 1 篇
  DialogueEntry? dialogue;
  // 第五部分：选词填空 1 篇
  BankedClozeEntry? bankedCloze;
  // 第六部分：英译汉 5 句
  En2zh5Entry? en2zh5;
  // 第七部分：写作
  WritingEntry? writing;

  FullExamPaper({
    this.totalTimeMin = 120,
    this.title = '专升本综合模拟全卷',
    List<Question>? vocab,
    List<Question>? readings,
    List<Question>? cloze,
    this.clozeSubs,
    this.dialogue,
    this.bankedCloze,
    this.en2zh5,
    this.writing,
  })  : vocab = vocab ?? [],
        readings = readings ?? [],
        cloze = cloze ?? [];

  /// 全卷总题量
  int get totalQuestions {
    var sum = vocab.length;
    for (final r in readings) {
      sum += r.questions.length;
    }
    sum += clozeSubs?.length ?? 0;
    sum += dialogue?.answerLetters.length ?? 0;
    sum += bankedCloze?.answerWords.length ?? 0;
    sum += en2zh5?.sentences.length ?? 0;
    sum += writing != null ? 1 : 0;
    return sum;
  }

  Map<String, dynamic> toJson() => {
        'totalTimeMin': totalTimeMin,
        'title': title,
        'vocab': vocab.map((e) => e.toJson()).toList(),
        'readings': readings.map((e) => e.toJson()).toList(),
        'cloze': cloze.map((e) => e.toJson()).toList(),
        'clozeSubs': clozeSubs?.map((e) => e.toJson()).toList(),
        'dialogue': dialogue?.toJson(),
        'bankedCloze': bankedCloze?.toJson(),
        'en2zh5': en2zh5?.toJson(),
        'writing': writing?.toJson(),
      };

  factory FullExamPaper.fromJson(Map<String, dynamic> j) => FullExamPaper(
        totalTimeMin: ((j['totalTimeMin'] ?? 120) as num).toInt(),
        title: (j['title'] ?? '专升本综合模拟全卷') as String,
        vocab: (j['vocab'] as List?)?.map((e) => Question.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        readings: (j['readings'] as List?)?.map((e) => Question.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        cloze: (j['cloze'] as List?)?.map((e) => Question.fromJson(e as Map<String, dynamic>)).toList() ?? [],
        clozeSubs: (j['clozeSubs'] as List?)?.map((e) => ClozeSubQ.fromJson(e as Map<String, dynamic>)).toList(),
        dialogue: j['dialogue'] == null ? null : DialogueEntry.fromJson(j['dialogue'] as Map<String, dynamic>),
        bankedCloze: j['bankedCloze'] == null ? null : BankedClozeEntry.fromJson(j['bankedCloze'] as Map<String, dynamic>),
        en2zh5: j['en2zh5'] == null ? null : En2zh5Entry.fromJson(j['en2zh5'] as Map<String, dynamic>),
        writing: j['writing'] == null ? null : WritingEntry.fromJson(j['writing'] as Map<String, dynamic>),
      );
}

/// 全卷考试用户作答记录
class ExamAnswerSheet {
  // 分区作答（列表长度与分区题量严格一致；未作答为 null）
  List<int?> vocab; // 20 项，-1/0-3 选项索引
  List<List<int?>> reading; // 4 篇，每篇 5 项
  List<int?> cloze; // 15 项
  List<int?> dialogue; // 5 项，索引对应 options（A=0..G=6）
  List<int?> bankedCloze; // 10 项，索引对应 wordBank
  List<String> en2zh5; // 5 项，用户翻译文本
  String writing; // 写作作文

  ExamAnswerSheet({
    List<int?>? vocab,
    List<List<int?>>? reading,
    List<int?>? cloze,
    List<int?>? dialogue,
    List<int?>? bankedCloze,
    List<String>? en2zh5,
    this.writing = '',
  })  : vocab = vocab ?? List.filled(20, null),
        reading = reading ?? List.generate(4, (_) => List.filled(5, null)),
        cloze = cloze ?? List.filled(15, null),
        dialogue = dialogue ?? List.filled(5, null),
        bankedCloze = bankedCloze ?? List.filled(10, null),
        en2zh5 = en2zh5 ?? List.filled(5, '');

  Map<String, dynamic> toJson() => {
        'vocab': vocab,
        'reading': reading,
        'cloze': cloze,
        'dialogue': dialogue,
        'bankedCloze': bankedCloze,
        'en2zh5': en2zh5,
        'writing': writing,
      };

  factory ExamAnswerSheet.fromJson(Map<String, dynamic> j) => ExamAnswerSheet(
        vocab: _intList(j['vocab'], 20),
        reading: ((j['reading'] as List?) ?? [])
            .map((e) => _intList(e, 5))
            .toList(),
        cloze: _intList(j['cloze'], 15),
        dialogue: _intList(j['dialogue'], 5),
        bankedCloze: _intList(j['bankedCloze'], 10),
        en2zh5: ((j['en2zh5'] as List?) ?? []).map((e) => (e ?? '') as String).toList(),
        writing: (j['writing'] ?? '') as String,
      );

  /// 容错读取可空 int 列表（长度不足时补齐 null）
  static List<int?> _intList(dynamic raw, int expectLen) {
    final src = (raw as List?) ?? [];
    final out = src.map<int?>((e) => e == null ? null : (e as num).toInt()).toList();
    while (out.length < expectLen) {
      out.add(null);
    }
    return out;
  }
}

/// 全卷考试成绩结果
class ExamResult {
  FullExamPaper paper;
  ExamAnswerSheet answers;
  int durationSec; // 实耗秒数
  int totalScore; // 总分
  int maxScore; // 满分
  Map<ExamSection, int> sectionScores; // 每分区实得分
  Map<ExamSection, int> sectionMax; // 每分区满分
  Map<ExamSection, int> sectionCorrect; // 每分区做对题数
  Map<ExamSection, int> sectionTotal; // 每分区作答总数
  String writingScore; // 写作得分评价（文字）
  int writingScoreNum; // 写作得分数值 0-20
  int submittedAt; // 交卷时间戳（ms），持久化用
  bool aiGrading; // AI 批改进行中（英译汉+写作）
  bool aiGraded; // 已完成 AI 批改（false=本地启发式点评）
  List<String> en2zh5AiComments; // 英译汉逐句 AI 评语（与 sentences 对齐，缺省空串）
  String writingAiSuggestion; // 写作 AI 改进建议
  ExamResult({
    required this.paper,
    required this.answers,
    this.durationSec = 0,
    this.totalScore = 0,
    this.maxScore = 150,
    Map<ExamSection, int>? sectionScores,
    Map<ExamSection, int>? sectionMax,
    Map<ExamSection, int>? sectionCorrect,
    Map<ExamSection, int>? sectionTotal,
    this.writingScore = '',
    this.writingScoreNum = 0,
    this.submittedAt = 0,
    this.aiGrading = false,
    this.aiGraded = false,
    List<String>? en2zh5AiComments,
    this.writingAiSuggestion = '',
  })  : sectionScores = sectionScores ?? {},
        sectionMax = sectionMax ?? {},
        sectionCorrect = sectionCorrect ?? {},
        sectionTotal = sectionTotal ?? {},
        en2zh5AiComments = en2zh5AiComments ?? [];

  double get percentage => maxScore == 0 ? 0 : totalScore / maxScore;
  String get rank {
    final p = percentage * 100;
    if (p >= 85) return 'A';
    if (p >= 70) return 'B';
    if (p >= 60) return 'C';
    if (p >= 40) return 'D';
    return 'E';
  }

  Map<String, dynamic> toJson() => {
        'paper': paper.toJson(),
        'answers': answers.toJson(),
        'durationSec': durationSec,
        'totalScore': totalScore,
        'maxScore': maxScore,
        'sectionScores': _secMapToJson(sectionScores),
        'sectionMax': _secMapToJson(sectionMax),
        'sectionCorrect': _secMapToJson(sectionCorrect),
        'sectionTotal': _secMapToJson(sectionTotal),
        'writingScore': writingScore,
        'writingScoreNum': writingScoreNum,
        'submittedAt': submittedAt,
        'aiGrading': aiGrading,
        'aiGraded': aiGraded,
        'en2zh5AiComments': en2zh5AiComments,
        'writingAiSuggestion': writingAiSuggestion,
      };

  static Map<String, int> _secMapToJson(Map<ExamSection, int> m) =>
      m.map((k, v) => MapEntry(k.name, v));

  static Map<ExamSection, int> _secMapFromJson(dynamic raw) {
    final out = <ExamSection, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final sec = ExamSection.values.where((e) => e.name == k).firstOrNull;
        if (sec != null) out[sec] = ((v ?? 0) as num).toInt();
      });
    }
    return out;
  }

  factory ExamResult.fromJson(Map<String, dynamic> j) => ExamResult(
        paper: FullExamPaper.fromJson((j['paper'] ?? {}) as Map<String, dynamic>),
        answers: ExamAnswerSheet.fromJson((j['answers'] ?? {}) as Map<String, dynamic>),
        durationSec: ((j['durationSec'] ?? 0) as num).toInt(),
        totalScore: ((j['totalScore'] ?? 0) as num).toInt(),
        maxScore: ((j['maxScore'] ?? 150) as num).toInt(),
        sectionScores: _secMapFromJson(j['sectionScores']),
        sectionMax: _secMapFromJson(j['sectionMax']),
        sectionCorrect: _secMapFromJson(j['sectionCorrect']),
        sectionTotal: _secMapFromJson(j['sectionTotal']),
        writingScore: (j['writingScore'] ?? '') as String,
        writingScoreNum: ((j['writingScoreNum'] ?? 0) as num).toInt(),
        submittedAt: ((j['submittedAt'] ?? 0) as num).toInt(),
        aiGrading: (j['aiGrading'] ?? false) as bool,
        aiGraded: (j['aiGraded'] ?? false) as bool,
        en2zh5AiComments: ((j['en2zh5AiComments'] as List?) ?? []).map((e) => (e ?? '') as String).toList(),
        writingAiSuggestion: (j['writingAiSuggestion'] ?? '') as String,
      );
}

/// 考试成绩历史摘要（仅存关键指标，最多保留最近 10 条）
class ExamHistoryEntry {
  int submittedAt;
  String title;
  int totalScore;
  int maxScore;
  String rank;
  int durationSec;

  ExamHistoryEntry({
    required this.submittedAt,
    this.title = '',
    this.totalScore = 0,
    this.maxScore = 150,
    this.rank = 'E',
    this.durationSec = 0,
  });

  Map<String, dynamic> toJson() => {
        'submittedAt': submittedAt,
        'title': title,
        'totalScore': totalScore,
        'maxScore': maxScore,
        'rank': rank,
        'durationSec': durationSec,
      };

  factory ExamHistoryEntry.fromJson(Map<String, dynamic> j) => ExamHistoryEntry(
        submittedAt: ((j['submittedAt'] ?? 0) as num).toInt(),
        title: (j['title'] ?? '') as String,
        totalScore: ((j['totalScore'] ?? 0) as num).toInt(),
        maxScore: ((j['maxScore'] ?? 150) as num).toInt(),
        rank: (j['rank'] ?? 'E') as String,
        durationSec: ((j['durationSec'] ?? 0) as num).toInt(),
      );
}

// ===== 语法学习（分层课程 + 随堂练习） =====

/// 语法随堂练习题（四选一单选）
class GrammarQuiz {
  String question;
  List<String> options;
  /// 正确答案字母（'A'~'D'）
  String answer;
  String analysis;

  GrammarQuiz({
    this.question = '',
    List<String>? options,
    this.answer = 'A',
    this.analysis = '',
  }) : options = options ?? [];

  /// 正确答案索引（0~3，非法时为 0）
  int get answerIdx {
    final i = answer.toUpperCase().codeUnitAt(0) - 'A'.codeUnitAt(0);
    return (i >= 0 && i < options.length) ? i : 0;
  }

  Map<String, dynamic> toJson() => {
        'question': question,
        'options': options,
        'answer': answer,
        'analysis': analysis,
      };

  factory GrammarQuiz.fromJson(Map<String, dynamic> j) {
    final opts = ((j['options'] as List?) ?? [])
        .map((e) => (e ?? '').toString())
        .toList();
    // answer 容错：支持字母（大小写）或数字索引
    final raw = (j['answer'] ?? 'A').toString().trim();
    String letter;
    if (raw.length == 1 && RegExp(r'[A-Da-d]').hasMatch(raw)) {
      letter = raw.toUpperCase();
    } else {
      final n = int.tryParse(raw);
      letter = (n != null && n >= 1 && n <= 4)
          ? String.fromCharCode('A'.codeUnitAt(0) + n - 1)
          : 'A';
    }
    return GrammarQuiz(
      question: (j['question'] ?? '') as String,
      options: opts,
      answer: letter,
      analysis: (j['analysis'] ?? '') as String,
    );
  }
}

/// 语法例句
class GrammarExample {
  String en;
  String zh;
  String point;

  GrammarExample({this.en = '', this.zh = '', this.point = ''});

  Map<String, dynamic> toJson() => {'en': en, 'zh': zh, 'point': point};

  factory GrammarExample.fromJson(Map<String, dynamic> j) => GrammarExample(
        en: (j['en'] ?? '') as String,
        zh: (j['zh'] ?? '') as String,
        point: (j['point'] ?? '') as String,
      );
}

/// 语法知识点
class GrammarTopic {
  String id;
  String name;
  /// 考纲条目编号（一个知识点可对应多个考纲项）
  List<int> syllabusRef;
  /// 考频权重：'high' | 'mid' | 'low'
  String weight;
  String intro;
  String formula;
  List<GrammarExample> examples;
  List<String> pitfalls;
  List<GrammarQuiz> quiz;

  GrammarTopic({
    this.id = '',
    this.name = '',
    List<int>? syllabusRef,
    this.weight = 'mid',
    this.intro = '',
    this.formula = '',
    List<GrammarExample>? examples,
    List<String>? pitfalls,
    List<GrammarQuiz>? quiz,
  })  : syllabusRef = syllabusRef ?? [],
        examples = examples ?? [],
        pitfalls = pitfalls ?? [],
        quiz = quiz ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'syllabusRef': syllabusRef,
        'weight': weight,
        'intro': intro,
        'formula': formula,
        'examples': examples.map((e) => e.toJson()).toList(),
        'pitfalls': pitfalls,
        'quiz': quiz.map((e) => e.toJson()).toList(),
      };

  /// syllabusRef 容错解析：兼容 int / List / null（异常时返回空列表）
  static List<int> _syllabusRefFrom(Object? raw) {
    if (raw is num) return [raw.toInt()];
    if (raw is List) {
      return raw
          .where((e) => e is num || int.tryParse('$e') != null)
          .map((e) => e is num ? e.toInt() : int.parse('$e'))
          .toList();
    }
    return [];
  }

  factory GrammarTopic.fromJson(Map<String, dynamic> j) => GrammarTopic(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        syllabusRef: _syllabusRefFrom(j['syllabusRef']),
        weight: (j['weight'] ?? 'mid') as String,
        intro: (j['intro'] ?? '') as String,
        formula: (j['formula'] ?? '') as String,
        examples: ((j['examples'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(GrammarExample.fromJson)
            .toList(),
        pitfalls: ((j['pitfalls'] as List?) ?? [])
            .map((e) => (e ?? '').toString())
            .toList(),
        quiz: ((j['quiz'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(GrammarQuiz.fromJson)
            .toList(),
      );
}

/// 语法课程层级
class GrammarLevel {
  String id;
  String name;
  String desc;
  List<GrammarTopic> topics;

  GrammarLevel({
    this.id = '',
    this.name = '',
    this.desc = '',
    List<GrammarTopic>? topics,
  }) : topics = topics ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': desc,
        'topics': topics.map((e) => e.toJson()).toList(),
      };

  factory GrammarLevel.fromJson(Map<String, dynamic> j) => GrammarLevel(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        desc: (j['desc'] ?? '') as String,
        topics: ((j['topics'] as List?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(GrammarTopic.fromJson)
            .toList(),
      );
}

/// 语法学习进度（按 topicId 存储）
class GrammarProgress {
  bool learned;
  /// 最佳正确率（0~100）
  int best;
  int attempts;

  GrammarProgress({this.learned = false, this.best = 0, this.attempts = 0});

  Map<String, dynamic> toJson() => {
        'learned': learned,
        'best': best,
        'attempts': attempts,
      };

  factory GrammarProgress.fromJson(Map<String, dynamic> j) => GrammarProgress(
        learned: (j['learned'] ?? false) as bool,
        best: ((j['best'] ?? 0) as num).toInt(),
        attempts: ((j['attempts'] ?? 0) as num).toInt(),
      );
}
