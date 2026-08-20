/// 对话助手的「技能 / 模式 / 专家 / Agent 工具」能力定义。
/// 每个能力携带一段 system prompt 片段，选中后注入到对话的 system prompt，
/// 真正改变 AI 的行为，而不是仅做 UI 展示。
library;

import 'package:flutter/material.dart';

/// 技能：一组聚焦某类任务的预设指令。
/// 当 [toolName] 不为空时，表示这是一个内置 Agent 工具技能：
/// 选中后会在 system prompt 中注入"你总是主动调用该工具"的倾向提示，
/// 让 AI 在对应场景下优先调用此 Agent 工具。
class ChatSkill {
  final String id;
  final String name;
  final String description;
  final String prompt;
  final String? toolName;
  final IconData icon;
  const ChatSkill(this.id, this.name, this.description, this.prompt, {this.toolName, this.icon = Icons.auto_fix_high_rounded});
}

/// 对话模式：改变 AI 的回复策略
class ChatMode {
  final String id;
  final String name;
  final String description;
  final String prompt; // 空串表示默认自由问答
  final IconData icon;
  const ChatMode(this.id, this.name, this.description, this.prompt, {this.icon = Icons.auto_awesome_rounded});
}

/// 专家：预设角色，改变 AI 的人设与专业方向
class ChatExpert {
  final String id;
  final String name;
  final String description;
  final String prompt;
  final IconData icon;
  const ChatExpert(this.id, this.name, this.description, this.prompt, {this.icon = Icons.person_outline_rounded});
}

/// 内置通用技能库
const List<ChatSkill> kChatSkills = [
  ChatSkill('translate', '中英互译', '精准中英互译，必要时给出直译与意译', '你此刻以「专业翻译官」身份工作：专注中英互译，译文要准确、地道，符合目标语言习惯；对易混淆或有多重含义的句子，给出直译与意译两种版本并说明差异。', icon: Icons.translate_rounded),
  ChatSkill('grammar', '语法解析', '逐句拆解句子成分、时态与从句结构', '你此刻以「语法专家」身份工作：对用户提供的英文句子逐句拆解，讲清句子成分（主谓宾定状补）、时态、语态、从句结构，并结合例句说明易错点。', icon: Icons.menu_book_rounded),
  ChatSkill('writing', '作文批改', '批改英文作文并给出润色建议', '你此刻以「英语写作老师」身份工作：对用户提交的英文作文逐段批改，指出语法错误、用词不当、逻辑问题，给出润色建议，并按内容/语言/结构给出评分与提升方向。', icon: Icons.edit_note_rounded),
  ChatSkill('speaking', '口语陪练', '英文对话练习，纠正表达', '你此刻以「口语陪练」身份工作：用英文与用户进行日常对话练习，语气轻松自然，适时纠正用户的表达，并给出更地道的说法。', icon: Icons.record_voice_over_rounded),
  ChatSkill('vocab', '词汇讲解', '讲清单词音标、词性、词根与辨析', '你此刻以「词汇专家」身份工作：讲解单词的音标、词性、词根词缀、近义词辨析、常见搭配与例句，并给出记忆技巧。', icon: Icons.text_fields_rounded),
];

/// 内置 Agent 工具技能库。
/// 选中后会注入强倾向提示，让 AI 在相关场景主动调用对应工具。
const List<ChatSkill> kAgentToolSkills = [
  ChatSkill('tool_generate_questions', '出题练习', '从题库或 AI 生成练习题', '当用户想做题、出题、练习时，你总是主动调用 generate_questions 工具，把题目放入答题区；若用户明确说"AI出题/不要题库/新题"，则设置 useBank=false。', toolName: 'generate_questions', icon: Icons.format_list_numbered_rounded),
  ChatSkill('tool_submit_generated_questions', 'AI 出题', '直接生成完整题目内容', '当用户希望直接拿到完整题目内容（尤其是自定义题型、多道题、阅读理解/完形/对话等）时，你总是主动调用 submit_generated_questions 工具提交题目 JSON。', toolName: 'submit_generated_questions', icon: Icons.create_rounded),
  ChatSkill('tool_generate_full_exam', '全卷模拟', '生成 76 题专升本综合模拟卷', '当用户要求模拟考试、全卷、套卷时，你总是主动调用 generate_full_exam 工具生成完整试卷并进入考场。', toolName: 'generate_full_exam', icon: Icons.school_rounded),
  ChatSkill('tool_lookup_word', '查单词', '查询释义、音标与用法', '当用户询问某个英文单词的意思、读音或用法时，你总是主动调用 lookup_word 工具查询。', toolName: 'lookup_word', icon: Icons.search_rounded),
  ChatSkill('tool_analyze_words', '词汇剖析', '标注文本中每个单词释义', '当用户要求剖析、分析单词、标注释义时，你总是主动调用 analyze_words 工具，mode 默认用 normal。', toolName: 'analyze_words', icon: Icons.text_snippet_rounded),
  ChatSkill('tool_get_current_question', '当前题目', '获取答题区当前题目', '当用户问"这道题是什么"、"当前题目"时，你总是主动调用 get_current_question 工具获取并告知用户。', toolName: 'get_current_question', icon: Icons.help_outline_rounded),
  ChatSkill('tool_next_question', '下一道题', '切换到下一道已生成题目', '当用户说"换一道"、"下一题"时，你总是主动调用 next_question 工具切换题目。', toolName: 'next_question', icon: Icons.skip_next_rounded),
  ChatSkill('tool_toggle_favorite', '收藏题目', '收藏或取消当前题目', '当用户说"收藏"、"加入收藏"时，你总是主动调用 toggle_favorite 工具。', toolName: 'toggle_favorite', icon: Icons.star_border_rounded),
  ChatSkill('tool_get_progress', '学习进度', '查看答题与正确率统计', '当用户问"进度"、"正确率"、"学得怎么样"时，你总是主动调用 get_progress 工具获取统计。', toolName: 'get_progress', icon: Icons.trending_up_rounded),
  ChatSkill('tool_goto_page', '跳转页面', '前往指定功能页面', '当用户说"去学习/答题/学习报告/查询/题库/错题本/生词本/语法学习/墨墨词库"时，你总是主动调用 goto_page 工具跳转对应页面。', toolName: 'goto_page', icon: Icons.open_in_new_rounded),
  ChatSkill('tool_get_wrong_questions', '查看错题', '列出错题本概览', '当用户问"错题"、"错了几道"、"复习错题"时，你总是主动调用 get_wrong_questions 工具。', toolName: 'get_wrong_questions', icon: Icons.error_outline_rounded),
  ChatSkill('tool_get_favorites', '查看生词', '列出生词本概览', '当用户问"生词本"、"收藏了哪些"时，你总是主动调用 get_favorites 工具。', toolName: 'get_favorites', icon: Icons.bookmark_border_rounded),
  ChatSkill('tool_start_dictation', '单词默写', '启动听写练习', '当用户说"默写"、"听写"、"开始默写"时，你总是主动调用 start_dictation 工具启动默写。', toolName: 'start_dictation', icon: Icons.keyboard_rounded),
  ChatSkill('tool_sync_maimemo', '同步墨墨', '拉取今日墨墨学习单词', '当用户要求"同步墨墨"、"更新词库"时，你总是主动调用 sync_maimemo 工具。', toolName: 'sync_maimemo', icon: Icons.sync_rounded),
  ChatSkill('tool_get_study_report', '学习报告', '查看学习成果统计', '当用户问"学习报告"、"学习成果"、"统计"时，你总是主动调用 get_study_report 工具。', toolName: 'get_study_report', icon: Icons.insert_chart_outlined_rounded),
  ChatSkill('tool_config_settings', '修改设置', '读取或修改应用设置', '当用户要求查看或修改设置（模型、温度、主题、全屏、省电等）时，你总是主动调用 config_settings 工具。', toolName: 'config_settings', icon: Icons.tune_rounded),
  ChatSkill('tool_search_web', '联网搜索', '检索实时信息与新闻', '当用户问实时新闻、天气、最新事件，或需要联网核实时，你总是主动调用 search_web 工具（需用户开启联网搜索连接器）。', toolName: 'search_web', icon: Icons.travel_explore_rounded),
  ChatSkill('tool_backup_data', '备份数据', '导出全部数据到本地', '当用户要求"备份数据"、"导出备份"时，你总是主动调用 backup_data 工具。', toolName: 'backup_data', icon: Icons.cloud_download_rounded),
  ChatSkill('tool_operate_computer', '操作电脑', '打开文件/网页/执行命令', '当用户要求"打开某文件/文件夹/软件/网页"或"执行某条命令"时，你总是主动调用 operate_computer 工具（涉及 run_command 需用户开启完全访问）。', toolName: 'operate_computer', icon: Icons.computer_rounded),
];

/// 全部技能（通用 + Agent 工具）
const List<ChatSkill> kAllChatSkills = [...kChatSkills, ...kAgentToolSkills];

/// Agent 工具名 → 技能 ID 映射
final Map<String, String> kAgentToolNameToSkillId = {
  for (final s in kAgentToolSkills) if (s.toolName != null) s.toolName!: s.id,
};

/// 内置对话模式库
const List<ChatMode> kChatModes = [
  ChatMode('chat', '自由问答', '默认对话，自由提问', '', icon: Icons.chat_bubble_outline_rounded),
  ChatMode('study', '学习模式', '结合当前题目深入讲解、引导思考', '进入「学习模式」：结合当前题目与知识点，先讲解再给答案，引导用户自己思考，避免直接抛结论。', icon: Icons.lightbulb_outline_rounded),
  ChatMode('question', '出题模式', '优先调用工具为用户生成练习题', '进入「出题模式」：当用户想要练习时，优先调用 generate_questions 或 submit_generated_questions 工具直接生成练习题。', icon: Icons.quiz_outlined),
];

/// 内置专家库
const List<ChatExpert> kChatExperts = [
  ChatExpert('teacher', '英语老师', '耐心细致、循序渐进地教学', '你是一位经验丰富的英语老师，讲解耐心细致，善于循序渐进地引导学生，会用类比和例子帮助学生理解。', icon: Icons.school_outlined),
  ChatExpert('translator', '翻译官', '精通中英双语，译文信达雅', '你是一位资深翻译官，精通中英双语，译文力求信、达、雅，能准确把握原文的语气与风格。', icon: Icons.translate_rounded),
  ChatExpert('examiner', '命题专家', '熟悉专升本/四六级，侧重应试', '你是一位英语考试命题专家，熟悉专升本、四六级等考试题型与评分标准，讲解侧重应试技巧与高频考点。', icon: Icons.edit_calendar_outlined),
];
