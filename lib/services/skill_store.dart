/// 技能商店：内置（资产）技能 + 用户自定义技能的统一注册表。
///
/// 懒加载设计（渐进式披露）：系统提示词只注入每个技能的
/// 「名称 + 一句话描述」目录（约 30 字/技能），完整指令正文
/// 仅在 AI 调用 `skill` / `load_skill` 工具命中时才进入上下文，
/// 避免几十个技能全文常驻造成上下文膨胀。
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'storage.dart';

/// 一个可被 AI 按需加载的技能
class AgentSkill {
  final String id;
  final String name;
  /// 触发场景 + 能力简述（进入系统提示词目录的仅有内容）
  final String description;
  /// 分组（技能管理 / 前端开发 / 开发工具 / 智谱 GLM / 生活服务 / 自定义）
  final String category;
  /// builtin = 资产内置（可禁用不可删）；custom = 用户添加（可删）
  final String source;
  /// 完整指令正文（Markdown）。内置技能启动时从资产读入。
  String content;
  /// 是否参与系统提示词目录与 skill 工具检索
  bool enabled;

  AgentSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.source,
    required this.content,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'source': source,
        'content': content,
      };

  factory AgentSkill.fromJson(Map<String, dynamic> j) => AgentSkill(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        category: (j['category'] as String?) ?? '自定义',
        source: (j['source'] as String?) ?? 'custom',
        content: (j['content'] as String?) ?? '',
      );
}

/// 内置技能资产文件清单（assets/skills/*.md，含 YAML frontmatter）
const List<String> kBundledSkillFiles = [
  'skill-creator',
  'frontend-design',
  'flutter-ui-ux',
  'github',
  'find-skill',
  'alipay-aipay',
  'glm-image-gen',
  'glmv-caption',
  'glmv-prompt-gen',
  'glmv-resume-screen',
  'glmv-grounding',
  'glmv-doc-based-writing',
  'glmv-pdf-to-ppt',
  'glmv-pdf-to-web',
  'glmv-stock-analyst',
  'glmv-prd-to-app',
  'glmv-web-replication',
  'glm-master-skill',
  'work-office-docs',
  'work-email-draft',
  'work-meeting-notes',
  'work-weekly-report',
  'work-data-analysis',
  'work-research-brief',
  'work-pro-translation',
];

/// 原生自带的学习技能（非资产 .md，由 Dart 内置，随应用能力绑定）。
/// 归类为「学习功能」，source = builtin（可查看/启用/禁用，不可删除）。
/// 每个技能对应一个或多个原生工具/功能页；正文描述触发时机与调用建议。
const List<Map<String, String>> kNativeLearningSkills = [
  {
    'id': 'native_analyze_words',
    'name': '词汇剖析',
    'category': '学习功能',
    'description': '对英文文本/题目逐词标注释义与词组，支持快速/正常/深度三种剖析模式。当用户要求剖析、分析单词、标注释义时使用。',
    'content': '# 词汇剖析（原生能力）\n\n## 触发时机\n- 用户要求「剖析/分析单词/标注释义」，给出英文文本（通常是题目原文或翻译题英文答案 q.english）。\n\n## 调用方式\n调用原生工具 `analyze_words`，参数：\n- `text`：要剖析的英文文本。\n- `mode`：`fast`(纯词典) / `normal`(词典+AI补充) / `deep`(AI语境分析+词组识别)，默认 `normal`。\n\n## 注意\n- 仅分析英文内容；翻译题请传英文答案而非中文题目。\n- 剖析结果会自动显示在答题区的剖析视图。',
  },
  {
    'id': 'native_lookup_word',
    'name': '单词查询',
    'category': '学习功能',
    'description': '查询英文单词的释义、音标、词性、用法与常见搭配。当用户问某词什么意思/怎么读/怎么用时使用。',
    'content': '# 单词查询（原生能力）\n\n## 触发时机\n- 用户询问某个英语单词的含义、读音、词性、用法。\n\n## 调用方式\n调用原生工具 `lookup_word`，参数：\n- `word`：要查询的英文单词。\n\n## 结果\n返回释义、音标、词性、用法、常见搭配与同义词，UI 以用户友好方式展示。',
  },
  {
    'id': 'native_generate_questions',
    'name': '出题 / 做题',
    'category': '学习功能',
    'description': '为用户生成英语练习题并放入答题区（翻译/单选/完形/阅读等题型）。当用户要求出题、练习、做题时使用。',
    'content': '# 出题 / 做题（原生能力）\n\n## 触发时机\n- 用户要求「出题/做题/练习/来一道」+ 题型/数量。\n\n## 调用方式\n调用原生工具 `generate_questions`，参数：\n- `type`：`translation`(翻译题)/`choice`(选择题) 等题型。\n- `useBank`：默认 `true` 从题库抽取；用户明确说「不要题库/AI出题/新题/用AI生成」时设为 `false` 强制 AI 生成。\n\n若你直接产出题目内容，用 `submit_generated_questions` 提交到答题区。\n\n## 注意\n- 综合模拟套卷（76 题/150 分/7 题型/120 分钟）需走全卷生成流程。「考场/模拟套卷」请调用 `native_exam` 技能。',
  },
  {
    'id': 'native_dictation',
    'name': '单词默写',
    'category': '学习功能',
    'description': '启动单词默写(听写)练习并进入默写页，可选方向、数量与词库。当用户要求默写、听写时使用。',
    'content': '# 单词默写（原生能力）\n\n## 触发时机\n- 用户要求「默写/听写/开始默写」。\n\n## 调用方式\n调用原生工具 `start_dictation`，参数：\n- `mode`：`zh2en`(看中文默写英文) / `en2zh`(看英文默写中文)，默认 `zh2en`。\n- `count`：单词数量(1-50)，默认 10。\n- `source`：`zsb`(专升本，默认) / `custom`(自定义) / `maimemo`(墨墨词库)。',
  },
  {
    'id': 'native_maimemo',
    'name': '墨墨词库',
    'category': '学习功能',
    'description': '同步墨墨背单词今日学习词库，评估词量并以词库出题。当用户提到墨墨、同步词库、用墨墨词库出题时使用。',
    'content': '# 墨墨词库（原生能力）\n\n## 触发时机\n- 用户要求「同步墨墨/更新词库」，或用墨墨今日所学词库出题。\n\n## 调用方式\n- 同步：调用原生工具 `sync_maimemo`。\n- 用词库出题：先在首页题目选项选择「墨墨」模式（MOE 模式，取词库 1/7 词汇给 AI 参考，题长与滑动条挂钩）；或进入词库功能生成全量题目。\n\n## 注意\n- 仅同步今日已学习(isFinished=true)的单词；需配置墨墨 API Token。',
  },
  {
    'id': 'native_study_report',
    'name': '学习报告',
    'category': '学习功能',
    'description': '获取学习进度与成果统计（累计答题、正确率、收藏、错题数）。当用户问学习报告、进度、统计时使用。',
    'content': '# 学习报告（原生能力）\n\n## 触发时机\n- 用户要求「学习报告/学习成果/统计/进度/正确率/学得怎么样」。\n\n## 调用方式\n- 调用原生工具 `get_study_report` 获取学习成果统计。\n- 调用 `get_progress` 获取进度统计（已答题数、正确率、收藏数、错题数）。',
  },
  {
    'id': 'native_grammar',
    'name': '语法学习',
    'category': '学习功能',
    'description': '进入语法学习页并解答语法知识点与练习题。当用户要求学习语法、讲解语法点时使用。',
    'content': '# 语法学习（原生能力）\n\n## 触发时机\n- 用户要求「学习语法/讲解某个语法点/语法练习」。\n\n## 调用方式\n- 调用原生工具 `goto_page`，`page=grammar` 进入语法学习页。\n- 结合当前语法内容讲解知识点并出题。\n\n## 注意\n- 语法学习入口位于「更多功能」中（主页不显示）。',
  },
  {
    'id': 'native_exam',
    'name': '综合模拟套卷 / 考场',
    'category': '学习功能',
    'description': '生成固定 76 题/150 分/7 题型/120 分钟的综合模拟套卷，并进入沉浸式考场全屏作答。当用户要求模拟考试、套卷、考场时使用。',
    'content': '# 综合模拟套卷 / 考场（原生能力）\n\n## 触发时机\n- 用户要求「模拟考试/综合套卷/模拟卷/考场」。\n\n## 调用方式\n- 走全卷生成流程 `generateFullExam()`（固定 76 题/150 分/7 题型/120 分钟）。\n- 生成成功后**直接进入沉浸考场**全屏作答，不再弹窗确认。\n- 考场内提供题目导航、题型分布明细、答题卡与考试计时器；AI 助手自动隐藏，考试中禁止退出/切换/使用 AI 协助。',
  },
  {
    'id': 'native_wrong',
    'name': '错题本',
    'category': '学习功能',
    'description': '获取错题本的错题数量与列表概览，协助复习错题。当用户问错题、复习错题时使用。',
    'content': '# 错题本（原生能力）\n\n## 触发时机\n- 用户要求「错题/错了几道/复习错题」。\n\n## 调用方式\n- 调用原生工具 `get_wrong_questions` 获取错题数量与列表概览。\n- 调用 `goto_page`，`page=wrong` 进入错题本页。',
  },
  {
    'id': 'native_favorites',
    'name': '生词本 / 收藏',
    'category': '学习功能',
    'description': '获取生词本(收藏)的单词数量与列表，收藏/取消收藏题目。当用户问生词本、收藏了哪些时使用。',
    'content': '# 生词本 / 收藏（原生能力）\n\n## 触发时机\n- 用户要求「生词本/收藏/收藏了哪些」。\n\n## 调用方式\n- 调用原生工具 `get_favorites` 获取收藏单词数量与列表。\n- 调用 `toggle_favorite` 收藏或取消收藏当前题目。\n- 调用 `goto_page`，`page=favorite` 进入生词本页。',
  },
];

class SkillStore {
  final List<AgentSkill> _bundled = [];
  final List<AgentSkill> _custom = [];
  /// 被禁用的技能 id（含内置与自定义）
  final Set<String> _disabled = {};
  bool _loaded = false;
  Future<void>? _loadFuture;

  bool get loaded => _loaded;

  /// 全部技能（内置 + 自定义）
  List<AgentSkill> get all => [..._bundled, ..._custom];

  /// 启用的技能（进入系统提示词目录 & skill 工具可检索）
  List<AgentSkill> get enabled => all.where((s) => s.enabled).toList();

  List<AgentSkill> get custom => List.unmodifiable(_custom);

  /// 启动时加载：内置资产 + 持久化的自定义技能与禁用名单。
  /// 缓存 Future：并发调用等待同一次加载完成——原先提前置位 _loaded 会让
  /// 窗口期内的并发调用直接返回，系统提示词拿到空技能目录
  Future<void> load() => _loadFuture ??= _loadCore();

  Future<void> _loadCore() async {
    for (final id in (Storage.loadSkillsDisabledIds())) {
      _disabled.add(id);
    }
    for (final f in kBundledSkillFiles) {
      try {
        final raw = await rootBundle.loadString('assets/skills/$f.md');
        final (meta, body) = parseSkillMd(raw);
        _bundled.add(AgentSkill(
          id: f,
          name: meta['name'] ?? f,
          description: meta['description'] ?? '',
          category: meta['category'] ?? '内置',
          source: meta['source'] ?? f,
          content: body,
          enabled: !_disabled.contains(f),
        ));
      } catch (_) {
        // 单个资产缺失不影响其余技能
      }
    }
    for (final j in Storage.loadCustomSkills()) {
      final s = AgentSkill.fromJson(j);
      s.enabled = !_disabled.contains(s.id);
      _custom.add(s);
    }
    // 原生自带的学习技能（Dart 内置，随应用能力绑定）
    for (final k in kNativeLearningSkills) {
      _bundled.add(AgentSkill(
        id: k['id'] ?? '',
        name: k['name'] ?? '',
        description: k['description'] ?? '',
        category: k['category'] ?? '学习功能',
        source: 'builtin', // 原生内置：可禁用不可删除
        content: k['content'] ?? '',
        enabled: !_disabled.contains(k['id']),
      ));
    }
    _loaded = true;
  }

  /// 解析 SKILL.md：YAML frontmatter（name/description/category/source）+ 正文
  static (Map<String, String>, String) parseSkillMd(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return (const {}, content);
    int endIdx = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        endIdx = i;
        break;
      }
    }
    if (endIdx < 0) return (const {}, content);
    final fm = <String, String>{};
    for (var i = 1; i < endIdx; i++) {
      final m = RegExp(r'^([a-zA-Z_-]+):\s*(.*)$').firstMatch(lines[i]);
      if (m != null) {
        final k = m.group(1) ?? '';
        var v = m.group(2) ?? '';
        if (k.isNotEmpty) {
          // 多行数组值（如示例列表）压成一行，避免 frontmatter 解析噪声
          v = v.trim().replaceAll(RegExp('^["\']|["\']\$'), '');
          if (v.length > 200) v = '${v.substring(0, 200)}…';
          fm[k] = v;
        }
      }
    }
    final body = lines.sublist(endIdx + 1).join('\n').trim();
    return (fm, body);
  }

  /// 系统提示词注入的技能目录（仅名称+描述，懒加载正文）
  String catalogPrompt() {
    final skills = enabled;
    if (skills.isEmpty) return '';
    final buf = StringBuffer();
    for (final s in skills) {
      final desc = s.description.length > 120 ? '${s.description.substring(0, 120)}…' : s.description;
      buf.writeln('- ${s.name}（id: ${s.id}）：$desc');
    }
    return buf.toString().trimRight();
  }

  /// 按 id / 名称（大小写不敏感）查找技能
  AgentSkill? find(String nameOrId) {
    final key = nameOrId.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final s in all) {
      if (s.id.toLowerCase() == key || s.name.toLowerCase() == key) return s;
    }
    // 模糊兜底：包含匹配
    for (final s in all) {
      if (s.name.toLowerCase().contains(key) || s.id.toLowerCase().contains(key)) return s;
    }
    return null;
  }

  /// 新增自定义技能（同名 id 覆盖旧的）
  void addCustom({required String name, required String description, required String category, required String content}) {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _custom.add(AgentSkill(id: id, name: name, description: description, category: category.isEmpty ? '自定义' : category, source: 'custom', content: content));
    _persist();
  }

  /// 删除自定义技能；内置技能不可删（返回 false）
  bool remove(String id) {
    final idx = _custom.indexWhere((s) => s.id == id);
    if (idx < 0) return false;
    _custom.removeAt(idx);
    _disabled.remove(id);
    _persist();
    return true;
  }

  /// 启用/禁用（内置与自定义均可）
  void setEnabled(String id, bool value) {
    for (final s in all) {
      if (s.id == id) s.enabled = value;
    }
    if (value) {
      _disabled.remove(id);
    } else {
      _disabled.add(id);
    }
    _persist();
  }

  void _persist() {
    Storage.saveCustomSkills(_custom.map((s) => s.toJson()).toList());
    Storage.saveSkillsDisabledIds(_disabled.toList());
  }

  /// 备份/恢复用：全部自定义技能 JSON
  String exportCustomJson() => jsonEncode(_custom.map((s) => s.toJson()).toList());
}
