/// 数据模型：与网页版 index.html 中的数据结构保持一致
library;

/// 题型
enum QType { translation, choice, reading, grammar, writing, dictation }

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

  const DictEntry({this.pos = '', this.translation = '', this.other = ''});

  factory DictEntry.fromJson(Map<String, dynamic> j) => DictEntry(
        pos: (j['pos'] ?? '') as String,
        translation: (j['translation'] ?? '') as String,
        other: (j['other'] ?? '') as String,
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

/// 词汇剖析 token
class WordToken {
  final String text;
  final String type; // word / phrase / other
  final String word;
  final String pos;
  final String translation;
  final String other;

  const WordToken({
    required this.text,
    this.type = 'other',
    this.word = '',
    this.pos = '',
    this.translation = '',
    this.other = '',
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'type': type,
        'word': word,
        'pos': pos,
        'translation': translation,
        'other': other,
      };

  factory WordToken.fromJson(Map<String, dynamic> j) => WordToken(
        text: (j['text'] ?? '') as String,
        type: (j['type'] ?? 'other') as String,
        word: (j['word'] ?? '') as String,
        pos: (j['pos'] ?? '') as String,
        translation: (j['translation'] ?? '') as String,
        other: (j['other'] ?? '') as String,
      );

  bool get isMissing => type != 'other' && (translation.isEmpty || translation == '暂无释义');
}

/// API 配置
class ApiConfig {
  String url;
  String key;
  String model;
  String temperature;

  ApiConfig({this.url = '', this.key = '', this.model = 'gpt-5.1', this.temperature = 'default'});

  bool get ready => url.isNotEmpty && key.isNotEmpty;

  Map<String, dynamic> toJson() => {'url': url, 'key': key, 'model': model, 'temperature': temperature};

  factory ApiConfig.fromJson(Map<String, dynamic> j) => ApiConfig(
        url: (j['url'] ?? '') as String,
        key: (j['key'] ?? '') as String,
        model: (j['model'] ?? 'gpt-5.1') as String,
        temperature: (j['temperature'] ?? 'default') as String,
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
