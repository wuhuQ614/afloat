/// 词典服务：加载 dict.json / zsb-dict.json，提供查询与切词
library;

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models.dart';

class DictService {
  static Map<String, DictEntry>? _dict; // 合并词库
  static Map<String, DictEntry>? _zsb; // 专升本词库
  static bool _dictLoaded = false;
  static bool _zsbLoaded = false;

  static Future<void> loadExternalDict() async {
    if (_dictLoaded) return;
    _dictLoaded = true;
    try {
      final raw = await rootBundle.loadString('assets/dict.json');
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, DictEntry>{};
      obj.forEach((k, v) => map[k.toLowerCase()] = DictEntry.fromJson(v as Map<String, dynamic>));
      _dict = map;
    } catch (_) {
      _dict = {};
    }
  }

  static Future<void> loadZsbDict() async {
    if (_zsbLoaded) return;
    _zsbLoaded = true;
    try {
      final raw = await rootBundle.loadString('assets/zsb-dict.json');
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, DictEntry>{};
      obj.forEach((k, v) => map[k.toLowerCase()] = DictEntry.fromJson(v as Map<String, dynamic>));
      _zsb = map;
    } catch (_) {
      _zsb = {};
    }
  }

  static bool get zsbReady => _zsb != null && _zsb!.isNotEmpty;

  /// 查询英文单词（合并词库优先，回退专升本词库，再回退内建高频词库）
  static DictEntry? lookup(String word) {
    final w = word.toLowerCase();
    final d = _dict;
    if (d != null && d.containsKey(w)) return d[w];
    final z = _zsb;
    if (z != null && z.containsKey(w)) return z[w];
    final inline = _inlineDict[w];
    return inline;
  }

  static List<String> zsbWords() => _zsb?.keys.toList() ?? [];

  static DictEntry? zsbLookup(String word) => _zsb?[word.toLowerCase()];

  /// 内建高频词库（约 100 个常用词，始终可用）
  static const Map<String, DictEntry> _inlineDict = {
    'the': DictEntry(pos: 'art.', translation: '这/那', other: '定冠词'),
    'a': DictEntry(pos: 'art.', translation: '一个', other: '不定冠词'),
    'an': DictEntry(pos: 'art.', translation: '一个', other: '不定冠词（元音前）'),
    'i': DictEntry(pos: 'pron.', translation: '我', other: '第一人称主格'),
    'you': DictEntry(pos: 'pron.', translation: '你/你们', other: '第二人称'),
    'he': DictEntry(pos: 'pron.', translation: '他', other: '第三人称主格'),
    'she': DictEntry(pos: 'pron.', translation: '她', other: '第三人称主格'),
    'it': DictEntry(pos: 'pron.', translation: '它', other: '第三人称主格'),
    'we': DictEntry(pos: 'pron.', translation: '我们', other: '第一人称复数主格'),
    'they': DictEntry(pos: 'pron.', translation: '他们/她们/它们', other: '第三人称复数'),
    'me': DictEntry(pos: 'pron.', translation: '我（宾格）', other: '宾格'),
    'him': DictEntry(pos: 'pron.', translation: '他（宾格）', other: '宾格'),
    'her': DictEntry(pos: 'pron.', translation: '她（宾格）/她的', other: '宾格/所有格'),
    'us': DictEntry(pos: 'pron.', translation: '我们（宾格）', other: '宾格'),
    'them': DictEntry(pos: 'pron.', translation: '他们（宾格）', other: '宾格'),
    'my': DictEntry(pos: 'pron.', translation: '我的', other: '形容词性所有格'),
    'your': DictEntry(pos: 'pron.', translation: '你的/你们的', other: '形容词性所有格'),
    'his': DictEntry(pos: 'pron.', translation: '他的', other: '所有格'),
    'its': DictEntry(pos: 'pron.', translation: '它的', other: '所有格'),
    'our': DictEntry(pos: 'pron.', translation: '我们的', other: '所有格'),
    'their': DictEntry(pos: 'pron.', translation: '他们的', other: '所有格'),
    'this': DictEntry(pos: 'pron.', translation: '这个', other: '指示代词'),
    'that': DictEntry(pos: 'pron.', translation: '那个', other: '指示代词/连词'),
    'these': DictEntry(pos: 'pron.', translation: '这些', other: 'this 的复数'),
    'those': DictEntry(pos: 'pron.', translation: '那些', other: 'that 的复数'),
    'who': DictEntry(pos: 'pron.', translation: '谁', other: '疑问代词/关系代词'),
    'what': DictEntry(pos: 'pron.', translation: '什么', other: '疑问代词'),
    'which': DictEntry(pos: 'pron.', translation: '哪一个', other: '疑问代词/关系代词'),
    'where': DictEntry(pos: 'adv.', translation: '在哪里', other: '疑问副词/关系副词'),
    'when': DictEntry(pos: 'adv.', translation: '什么时候', other: '疑问副词/连词'),
    'why': DictEntry(pos: 'adv.', translation: '为什么', other: '疑问副词'),
    'how': DictEntry(pos: 'adv.', translation: '怎样/多么', other: '疑问副词'),
    'of': DictEntry(pos: 'prep.', translation: '...的', other: '表示所属关系'),
    'in': DictEntry(pos: 'prep.', translation: '在...里', other: '在...内、用（语言）'),
    'on': DictEntry(pos: 'prep.', translation: '在...上', other: '关于、在...方面'),
    'at': DictEntry(pos: 'prep.', translation: '在（某点）', other: '以（价格/速度）'),
    'to': DictEntry(pos: 'prep.', translation: '到、向', other: '动词不定式标志'),
    'for': DictEntry(pos: 'prep.', translation: '为了、对于', other: '因为（并列）'),
    'from': DictEntry(pos: 'prep.', translation: '从', other: '来自'),
    'by': DictEntry(pos: 'prep.', translation: '通过、由', other: '在...旁边、截止到'),
    'with': DictEntry(pos: 'prep.', translation: '和...一起/随着', other: '用（工具）'),
    'without': DictEntry(pos: 'prep.', translation: '没有', other: '如果没有'),
    'about': DictEntry(pos: 'prep.', translation: '关于', other: '大约'),
    'as': DictEntry(pos: 'prep.', translation: '作为', other: '像...一样、当...时'),
    'than': DictEntry(pos: 'conj.', translation: '比', other: '比较级标志'),
    'and': DictEntry(pos: 'conj.', translation: '和', other: '并列连词'),
    'or': DictEntry(pos: 'conj.', translation: '或者', other: '选择连词'),
    'but': DictEntry(pos: 'conj.', translation: '但是', other: '转折连词'),
    'so': DictEntry(pos: 'conj.', translation: '所以', other: '如此、这么'),
    'if': DictEntry(pos: 'conj.', translation: '如果', other: '是否'),
    'because': DictEntry(pos: 'conj.', translation: '因为', other: '表原因'),
    'not': DictEntry(pos: 'adv.', translation: '不', other: '否定副词'),
    'no': DictEntry(pos: 'adv.', translation: '不/没有', other: '形容词：没有的'),
    'very': DictEntry(pos: 'adv.', translation: '非常', other: '形容词：正是的'),
    'too': DictEntry(pos: 'adv.', translation: '也/太', other: 'too...to 太...而不能'),
    'also': DictEntry(pos: 'adv.', translation: '也', other: '此外'),
    'only': DictEntry(pos: 'adv.', translation: '仅仅', other: '形容词：唯一的'),
    'just': DictEntry(pos: 'adv.', translation: '刚刚/只是', other: '公平的'),
    'now': DictEntry(pos: 'adv.', translation: '现在', other: '如今'),
    'today': DictEntry(pos: 'adv.', translation: '今天', other: '名词：今日'),
    'more': DictEntry(pos: 'adv.', translation: '更', other: '更多（many/much 比较级）'),
    'most': DictEntry(pos: 'adv.', translation: '最', other: '大多数（many/much 最高级）'),
    'often': DictEntry(pos: 'adv.', translation: '经常', other: '频率副词'),
    'always': DictEntry(pos: 'adv.', translation: '总是', other: '频率副词'),
    'never': DictEntry(pos: 'adv.', translation: '从不', other: '频率副词'),
    'sometimes': DictEntry(pos: 'adv.', translation: '有时', other: '频率副词'),
    'together': DictEntry(pos: 'adv.', translation: '一起', other: '共同'),
    'here': DictEntry(pos: 'adv.', translation: '这里', other: '在这里'),
    'there': DictEntry(pos: 'adv.', translation: '那里', other: 'there be 句型'),
    'then': DictEntry(pos: 'adv.', translation: '然后', other: '那时'),
    'again': DictEntry(pos: 'adv.', translation: '再次', other: '又'),
    'already': DictEntry(pos: 'adv.', translation: '已经', other: '完成时标志'),
    'still': DictEntry(pos: 'adv.', translation: '仍然', other: '形容词：静止的'),
    'enough': DictEntry(pos: 'adv.', translation: '足够地', other: '形容词/代词：足够的'),
    'is': DictEntry(pos: 'v.', translation: '是', other: 'be 动词第三人称单数'),
    'are': DictEntry(pos: 'v.', translation: '是', other: 'be 动词复数'),
    'am': DictEntry(pos: 'v.', translation: '是', other: 'be 动词第一人称'),
    'was': DictEntry(pos: 'v.', translation: '是（过去）', other: 'be 动词过去式'),
    'were': DictEntry(pos: 'v.', translation: '是（过去）', other: 'be 动词过去式复数'),
    'been': DictEntry(pos: 'v.', translation: '被/是（完成）', other: 'be 的过去分词'),
    'being': DictEntry(pos: 'v.', translation: '是（进行）', other: 'be 的现在分词'),
    'do': DictEntry(pos: 'v.', translation: '做', other: '助动词'),
    'does': DictEntry(pos: 'v.', translation: '做（三单）', other: '助动词'),
    'did': DictEntry(pos: 'v.', translation: '做（过去）', other: '助动词'),
    'have': DictEntry(pos: 'v.', translation: '有', other: '助动词（完成时）'),
    'has': DictEntry(pos: 'v.', translation: '有（三单）', other: '助动词'),
    'had': DictEntry(pos: 'v.', translation: '有（过去）', other: '助动词'),
    'get': DictEntry(pos: 'v.', translation: '得到、变得', other: 'get up 起床'),
    'go': DictEntry(pos: 'v.', translation: '去', other: 'go on 继续'),
    'went': DictEntry(pos: 'v.', translation: '去（过去）', other: 'go 的过去式'),
    'come': DictEntry(pos: 'v.', translation: '来', other: 'come on 快点'),
    'take': DictEntry(pos: 'v.', translation: '拿、花费', other: 'take part in 参加'),
    'make': DictEntry(pos: 'v.', translation: '制作、使', other: 'make friends 交朋友'),
    'give': DictEntry(pos: 'v.', translation: '给', other: 'give up 放弃'),
    'see': DictEntry(pos: 'v.', translation: '看见', other: 'see off 送行'),
    'know': DictEntry(pos: 'v.', translation: '知道、认识', other: 'know about 了解'),
    'think': DictEntry(pos: 'v.', translation: '认为、思考', other: 'think of 想起'),
    'want': DictEntry(pos: 'v.', translation: '想要', other: 'want to do 想做'),
    'need': DictEntry(pos: 'v.', translation: '需要', other: 'need to do 需要做'),
    'use': DictEntry(pos: 'v.', translation: '使用', other: 'used to 过去常常'),
    'find': DictEntry(pos: 'v.', translation: '找到、发现', other: 'find out 查明'),
    'tell': DictEntry(pos: 'v.', translation: '告诉', other: 'tell a story 讲故事'),
    'ask': DictEntry(pos: 'v.', translation: '问、请求', other: 'ask for 要求'),
    'answer': DictEntry(pos: 'v.', translation: '回答', other: '名词：答案'),
    'help': DictEntry(pos: 'v.', translation: '帮助', other: 'help sb. with 帮助某人做'),
    'learn': DictEntry(pos: 'v.', translation: '学习', other: 'learn from 向...学习'),
    'study': DictEntry(pos: 'v.', translation: '学习/研究', other: '名词：书房'),
    'read': DictEntry(pos: 'v.', translation: '读', other: 'read a book 读书'),
    'write': DictEntry(pos: 'v.', translation: '写', other: 'write down 写下'),
    'speak': DictEntry(pos: 'v.', translation: '说', other: 'speak English 说英语'),
    'listen': DictEntry(pos: 'v.', translation: '听', other: 'listen to 听...'),
    'like': DictEntry(pos: 'v.', translation: '喜欢', other: '介词：像'),
    'love': DictEntry(pos: 'v.', translation: '爱', other: '名词：爱'),
    'work': DictEntry(pos: 'v.', translation: '工作', other: '名词：工作'),
    'play': DictEntry(pos: 'v.', translation: '玩/演奏', other: 'play football 踢足球'),
    'run': DictEntry(pos: 'v.', translation: '跑', other: 'run out 用完'),
    'walk': DictEntry(pos: 'v.', translation: '走', other: '名词：散步'),
    'talk': DictEntry(pos: 'v.', translation: '交谈', other: 'talk about 谈论'),
    'look': DictEntry(pos: 'v.', translation: '看', other: 'look at 看...'),
    'watch': DictEntry(pos: 'v.', translation: '观看', other: 'watch TV 看电视'),
    'good': DictEntry(pos: 'adj.', translation: '好的', other: 'good at 擅长'),
    'bad': DictEntry(pos: 'adj.', translation: '坏的', other: 'be bad for 对...有害'),
    'big': DictEntry(pos: 'adj.', translation: '大的', other: '比较级 bigger'),
    'small': DictEntry(pos: 'adj.', translation: '小的', other: '比较级 smaller'),
    'new': DictEntry(pos: 'adj.', translation: '新的', other: 'new year 新年'),
    'old': DictEntry(pos: 'adj.', translation: '旧的/老的', other: 'old man 老人'),
    'young': DictEntry(pos: 'adj.', translation: '年轻的', other: 'young people 年轻人'),
    'happy': DictEntry(pos: 'adj.', translation: '快乐的', other: 'happy birthday 生日快乐'),
    'sad': DictEntry(pos: 'adj.', translation: '伤心的', other: '名词 sadness'),
    'easy': DictEntry(pos: 'adj.', translation: '容易的', other: '副词 easily'),
    'hard': DictEntry(pos: 'adj.', translation: '困难的/硬的', other: '副词：努力地'),
    'important': DictEntry(pos: 'adj.', translation: '重要的', other: 'importance 名词'),
    'different': DictEntry(pos: 'adj.', translation: '不同的', other: 'difference 名词'),
    'same': DictEntry(pos: 'adj.', translation: '相同的', other: 'the same as 与...相同'),
    'first': DictEntry(pos: 'num.', translation: '第一', other: 'at first 起初'),
    'last': DictEntry(pos: 'adj.', translation: '最后的', other: 'at last 终于'),
    'next': DictEntry(pos: 'adj.', translation: '下一个', other: 'next to 紧邻'),
    'man': DictEntry(pos: 'n.', translation: '男人/人类', other: '复数 men'),
    'woman': DictEntry(pos: 'n.', translation: '女人', other: '复数 women'),
    'child': DictEntry(pos: 'n.', translation: '孩子', other: '复数 children'),
    'people': DictEntry(pos: 'n.', translation: '人们', other: 'person 的单数'),
    'friend': DictEntry(pos: 'n.', translation: '朋友', other: 'make friends 交朋友'),
    'family': DictEntry(pos: 'n.', translation: '家庭', other: '复数 families'),
    'school': DictEntry(pos: 'n.', translation: '学校', other: 'go to school 上学'),
    'student': DictEntry(pos: 'n.', translation: '学生', other: '复数 students'),
    'teacher': DictEntry(pos: 'n.', translation: '老师', other: '复数 teachers'),
    'book': DictEntry(pos: 'n.', translation: '书', other: 'read books 读书'),
    'time': DictEntry(pos: 'n.', translation: '时间/次数', other: 'on time 准时'),
    'day': DictEntry(pos: 'n.', translation: '天', other: 'every day 每天'),
    'year': DictEntry(pos: 'n.', translation: '年', other: 'new year 新年'),
    'world': DictEntry(pos: 'n.', translation: '世界', other: 'in the world 在世界上'),
    'life': DictEntry(pos: 'n.', translation: '生活/生命', other: '复数 lives'),
    'water': DictEntry(pos: 'n.', translation: '水', other: '动词：浇水'),
    'food': DictEntry(pos: 'n.', translation: '食物', other: 'fast food 快餐'),
    'money': DictEntry(pos: 'n.', translation: '钱', other: 'make money 赚钱'),
    'city': DictEntry(pos: 'n.', translation: '城市', other: '复数 cities'),
    'home': DictEntry(pos: 'n.', translation: '家', other: 'at home 在家'),
    'house': DictEntry(pos: 'n.', translation: '房子', other: '复数 houses'),
    'hand': DictEntry(pos: 'n.', translation: '手', other: 'hand in 上交'),
    'head': DictEntry(pos: 'n.', translation: '头', other: '用 head 思考'),
    'eye': DictEntry(pos: 'n.', translation: '眼睛', other: '复数 eyes'),
    'face': DictEntry(pos: 'n.', translation: '脸', other: 'face to face 面对面'),
  };

  // ===== 切词（词汇剖析用） =====

  /// 中文演示短语词典（与网页版一致，作为中文切词的兜底）
  static const Map<String, WordToken> _zhPhraseDict = {
    '人工智能': WordToken(text: '人工智能', type: 'phrase', word: '人工智能', pos: '名词', translation: 'AI，由计算机模拟的智能', other: '指机器具备类人智能的能力'),
    '正在': WordToken(text: '正在', type: 'phrase', word: '正在', pos: '副词', translation: '表示动作进行中', other: 'be + doing 结构的标志'),
    '改变': WordToken(text: '改变', type: 'word', word: '改变', pos: '动词', translation: 'change / transform', other: 'alter, modify'),
    '我们': WordToken(text: '我们', type: 'word', word: '我们', pos: '代词', translation: 'we / our', other: '第一人称复数'),
    '的': WordToken(text: '的', type: 'other', word: '的', pos: '助词', translation: '所属标记'),
    '学习方式': WordToken(text: '学习方式', type: 'phrase', word: '学习方式', pos: '名词', translation: 'the way we learn', other: 'learning method'),
    '和': WordToken(text: '和', type: 'other', word: '和', pos: '连词', translation: 'and'),
    '生活方式': WordToken(text: '生活方式', type: 'phrase', word: '生活方式', pos: '名词', translation: 'the way we live', other: 'lifestyle'),
  };

  static const String _zhPunct = '，。！？、；：\u201C\u201D\u2018\u2019（）,.!?;:';

  /// 中文切词：最长优先匹配演示短语，否则单字
  static List<WordToken> _zhTokens(String text) {
    final tokens = <WordToken>[];
    var remaining = text;
    while (remaining.isNotEmpty) {
      var matched = false;
      for (var len = (remaining.length < 6 ? remaining.length : 6); len >= 2; len--) {
        final seg = remaining.substring(0, len);
        if (_zhPhraseDict.containsKey(seg)) {
          tokens.add(_zhPhraseDict[seg]!);
          remaining = remaining.substring(len);
          matched = true;
          break;
        }
      }
      if (!matched) {
        final ch = remaining[0];
        if (_zhPunct.contains(ch)) {
          tokens.add(WordToken(text: ch, type: 'other'));
        } else if (_zhPhraseDict.containsKey(ch)) {
          tokens.add(_zhPhraseDict[ch]!);
        } else {
          tokens.add(WordToken(text: ch, type: 'other'));
        }
        remaining = remaining.substring(1);
      }
    }
    return tokens;
  }

  /// 英文切词：按空格与标点切分 + 词库匹配
  static List<WordToken> _enTokens(String text) {
    final tokens = <WordToken>[];
    // 匹配英文单词（含撇号）、空白、标点符号，保持原顺序
    final re = RegExp(r"[A-Za-z']+|\s+|[.,!?;:'\-—]+");
    for (final m in re.allMatches(text)) {
      final part = m.group(0)!;
      if (RegExp(r'^\s+$').hasMatch(part) || RegExp(r"^[.,!?;:'\-—]+$").hasMatch(part)) {
        tokens.add(WordToken(text: part, type: 'other'));
      } else {
        final lower = part.toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');
        final entry = lookup(lower);
        tokens.add(WordToken(
          text: part,
          type: 'word',
          word: part,
          pos: entry?.pos ?? '',
          translation: entry?.translation ?? '',
          other: entry?.other ?? '',
        ));
      }
    }
    return tokens;
  }

  /// 与网页版 getFallbackTokens 一致
  static List<WordToken> fallbackTokens(String text, bool isZh2En) {
    return isZh2En ? _zhTokens(text) : _enTokens(text);
  }
}
