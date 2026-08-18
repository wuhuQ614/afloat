/// Agent 服务：定义 AI 助手可调用的工具（Function Calling）。
/// 工具执行由 AppState.executeTool 分发，循环逻辑由 AppState._runAgentLoop 驱动。
library;

import 'api_service.dart';

/// 工具执行结果
class ToolExecResult {
  /// 返回给 AI 的文本内容（JSON 字符串或纯文本）
  final String content;
  /// 是否执行成功（失败时 content 为错误说明）
  final bool ok;
  /// UI 展示用的动作描述（如"已为你生成 3 道翻译题"）
  final String actionLabel;
  const ToolExecResult({required this.content, required this.ok, this.actionLabel = ''});
}

class AgentService {
  /// OpenAI Function Calling 格式的工具定义
  static List<Map<String, dynamic>> toolDefinitions() => [
        {
          'type': 'function',
          'function': {
            'name': 'generate_questions',
            'description': '为用户生成英语练习题并放入答题区。当用户要求出题、练习、做题时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'enum': [
                    'translation',
                    'choice',
                    'reading',
                    'grammar',
                    'writing',
                    'cloze',
                    'dialogue',
                    'bankedCloze',
                    'en2zh5',
                  ],
                  'description': '题型：translation=翻译题, choice=选择题, reading=阅读理解, grammar=语法填空, writing=写作题, cloze=完形填空, dialogue=补全对话, bankedCloze=选词填空, en2zh5=英译汉',
                },
                'level': {
                  'type': 'string',
                  'enum': ['easy', 'medium', 'hard', 'cet4', 'zsb'],
                  'description': '难度：easy=简单, medium=中等, hard=困难, cet4=四级, zsb=专升本。未指定时默认 zsb',
                },
                'count': {
                  'type': 'integer',
                  'description': '题目数量（1-10），默认 1',
                  'minimum': 1,
                  'maximum': 10,
                },
                'useBank': {
                  'type': 'boolean',
                  'description': '是否使用题库（true=从题库抽取，false=用AI全新生成）。用户明确说"不要题库"/"AI出题"/"新题"时设为false，否则默认true',
                },
              },
              'required': ['type', 'count'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'submit_generated_questions',
            'description':
                '由 AI 直接生成全部类型的英语题目，并把题目内容以 JSON 数组形式提交到答题区供用户作答。'
                '当用户要求"出题/做题/练习"且你希望直接产出题目内容（而非调用题库）时，由你自己编写题目并用这个工具提交。'
                '题目内容必须符合各题型要求的 JSON 结构；系统会自动校验并修复格式，低参数模型输出不规范也会被归一化。',
            'parameters': {
              'type': 'object',
              'properties': {
                'type': {
                  'type': 'string',
                  'enum': [
                    'translation',
                    'choice',
                    'reading',
                    'grammar',
                    'writing',
                    'cloze',
                    'dialogue',
                    'bankedCloze',
                    'en2zh5',
                  ],
                  'description': '题型（缺省为每道题目自身的 type 字段）。translation=翻译题, choice=选择题, reading=阅读理解, grammar=语法填空, writing=写作题, cloze=完形填空, dialogue=补全对话, bankedCloze=选词填空, en2zh5=英译汉',
                },
                'level': {
                  'type': 'string',
                  'enum': ['easy', 'medium', 'hard', 'cet4', 'zsb'],
                  'description': '难度：easy=简单, medium=中等, hard=困难, cet4=四级, zsb=专升本。默认 zsb',
                },
                'questions': {
                  'type': 'array',
                  'description': '题目内容数组。每道题是一个 JSON 对象，可含有：type(可选,缺省用外层 type)/level/chinese/english/question/passage/options/answer/analysis/knowledge 等字段。你必须依据题目类型按下面"提交题型 JSON 结构"约定的字段生成。',
                  'items': {
                    'type': 'object',
                    'additionalProperties': true,
                  },
                },
              },
              'required': ['questions'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'generate_full_exam',
            'description': '生成完整的专升本综合模拟全卷（76题/7题型/150分/120分钟）并进入考场。当用户要求生成全卷、模拟考试、套卷时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'level': {
                  'type': 'string',
                  'enum': ['zsb', 'cet4'],
                  'description': '级别，默认 zsb（专升本）',
                },
              },
              'required': [],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'lookup_word',
            'description': '查询英文单词的释义、音标、词性、用法。当用户问某个单词什么意思、怎么读、怎么用时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'word': {
                  'type': 'string',
                  'description': '要查询的英文单词',
                },
              },
              'required': ['word'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'analyze_words',
            'description': '对指定英文文本进行词汇剖析（标注每个单词的释义）。当用户要求剖析、分析单词、标注释义时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'text': {
                  'type': 'string',
                  'description': '要剖析的英文文本（通常是题目原文）',
                },
                'mode': {
                  'type': 'string',
                  'enum': ['fast', 'normal', 'deep'],
                  'description': '剖析模式：fast=快速（纯词典）, normal=正常（词典+AI补充）, deep=深度（AI语境分析+词组识别）。默认 normal',
                },
              },
              'required': ['text'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_current_question',
            'description': '获取当前答题区显示的题目信息（题型、难度、内容、参考答案、用户作答）。当用户问"这道题"、"当前题目"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'next_question',
            'description': '切换到下一道题（当已生成多道题时）。当用户说"换一道"、"下一题"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'toggle_favorite',
            'description': '收藏或取消收藏当前题目。当用户说"收藏"、"加入收藏"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_progress',
            'description': '获取用户的学习进度统计（已答题数、正确率、收藏数、错题数）。当用户问"进度"、"正确率"、"学得怎么样"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'goto_page',
            'description': '跳转到应用的某个功能页面。当用户说"去学习/答题/学习报告/查询/题库/错题本/生词本/默写/语法学习/墨墨词库"时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'page': {
                  'type': 'string',
                  'enum': ['learn', 'answer', 'report', 'search', 'bank', 'wrong', 'favorite', 'dictation', 'grammar', 'maimemo'],
                  'description': '目标页面：learn=学习页, answer=答题页, report=学习报告, search=单词查询, bank=题库, wrong=错题本, favorite=生词本(收藏), dictation=默写, grammar=语法学习, maimemo=墨墨词库',
                },
              },
              'required': ['page'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_wrong_questions',
            'description': '获取错题本的错题数量与列表概览。当用户问"错题"、"错了几道"、"复习错题"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_favorites',
            'description': '获取生词本（收藏）的单词数量与列表。当用户问"生词本"、"收藏"、"收藏了哪些"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'start_dictation',
            'description': '启动单词默写（听写）练习并进入默写页。当用户要求"默写"、"听写"、"开始默写"时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'mode': {
                  'type': 'string',
                  'enum': ['zh2en', 'en2zh'],
                  'description': '默写方向：zh2en=看中文默写英文, en2zh=看英文默写中文。默认 zh2en',
                },
                'count': {
                  'type': 'integer',
                  'description': '默写单词数量（1-50），默认 10',
                  'minimum': 1,
                  'maximum': 50,
                },
                'source': {
                  'type': 'string',
                  'enum': ['zsb', 'custom', 'maimemo'],
                  'description': '词库来源：zsb=专升本词库, custom=自定义词库, maimemo=墨墨词库。默认 zsb',
                },
              },
              'required': ['count'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'sync_maimemo',
            'description': '同步墨墨背单词词库（拉取今日已学习单词）。当用户要求"同步墨墨"、"更新词库"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'get_study_report',
            'description': '获取学习报告（学习记录、累计答题、正确率等学习成果统计）。当用户问"学习报告"、"学习成果"、"统计"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'config_settings',
            'description': '读取或修改应用的设置选项。当用户要求查看或修改设置（如模型、温度、图形能力、主题、深色模式、导航样式、界面模式、全屏、省电、高性能、墨墨Token）时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'action': {
                  'type': 'string',
                  'enum': ['get', 'set'],
                  'description': 'get=读取全部设置；set=修改指定设置',
                },
                'key': {
                  'type': 'string',
                  'enum': ['model', 'temperature', 'vision', 'fullUrl', 'uiMode', 'theme', 'navIndicator', 'fullscreen', 'powerSaving', 'highPerformance', 'maimemoToken'],
                  'description': '要读取或修改的设置项。是否已配置敏感项（如 Key）get 时只返回已配置与否。',
                },
                'value': {
                  'type': 'string',
                  'description': '要设置的值（action=set 时需一并提供 key 与 value）。model=模型名；temperature=default/0/0.3/0.7/1.0；vision、fullUrl、fullscreen、powerSaving、highPerformance=true 或 false；uiMode=desktop 或 mobile；theme=classic 或 glass 或 dark；navIndicator=underline 或 pill；maimemoToken=墨墨 API Token',
                },
              },
              'required': ['action'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'search_web',
            'description': '联网搜索，获取全网实时信息并返回参考链接。当用户问实时新闻、天气、最新事件，或需要联网核实信息时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'query': {
                  'type': 'string',
                  'description': '要搜索的关键词或问题，尽量精炼准确',
                },
              },
              'required': ['query'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'backup_data',
            'description': '备份全部数据（API 配置、收藏、错题本、学习记录、生词本等）到电脑下载目录或手机默认文件夹。当用户要求"备份数据"、"导出备份"时调用。',
            'parameters': {'type': 'object', 'properties': {}, 'required': []},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'operate_computer',
            'description': '直接操控用户的电脑（仅桌面端）：打开文件/文件夹、用默认程序打开网址、启动应用、执行系统命令。当用户要求"打开某个文件/文件夹/软件/网页"或"帮我执行一条命令"时调用。',
            'parameters': {
              'type': 'object',
              'properties': {
                'operation': {
                  'type': 'string',
                  'enum': ['open_file', 'open_folder', 'open_url', 'launch_app', 'run_command'],
                  'description': '操作类型：open_file=用默认程序打开文件, open_folder=在资源管理器中打开文件夹, open_url=用默认浏览器打开网址, launch_app=启动应用程序, run_command=执行系统命令',
                },
                'target': {
                  'type': 'string',
                  'description': '目标：文件/文件夹的完整路径，或应用名，或完整网址（open_url 时需带 http/https），或待执行的命令（run_command 时）。',
                },
              },
              'required': ['operation', 'target'],
            },
          },
        },
      ];

  /// Agent 系统 prompt（动态生成，注入当前题目上下文，避免 AI 凭空猜测）
  static String buildSystemPrompt({
    required String qType,
    required String qLevel,
    required String qText,
    required String dirDesc,
  }) {
    return '''你是 AFloat，一个英语学习 Agent 助手。你能通过工具调用直接帮用户执行操作，也能回答英语问题。

## 工具使用决策（关键）
判断用户意图后，**果断调用工具**，不要只给文字建议：

| 用户说的话 | 应调用的工具 |
|-----------|-------------|
| "出题/做题/练习/来一道" + 题型/数量 | generate_questions（useBank=true 默认走题库） |
| "出题/做题" + "不要题库/AI出题/新题/用AI生成" | generate_questions（useBank=false 强制AI生成） |
| 需要即时拿到用户自定义题型效果（翻译/选择/阅读/语法/写作/完形/对话/选词/英译汉），或 AI 直接产出多道题 | submit_generated_questions |
| "全卷/模拟考试/套卷/76题" | generate_full_exam |
| "xx什么意思/怎么读/怎么用"（xx是英文单词） | lookup_word |
| "剖析/分析单词/标注释义" | analyze_words |
| "这道题/当前题目是什么" | get_current_question |
| "换一道/下一题" | next_question |
| "收藏" | toggle_favorite |
| "进度/正确率/学得怎么样" | get_progress |
| "去学习/答题/学习报告/查询/题库/错题本/生词本/语法学习/墨墨" | goto_page |
| "错题/错了几道/复习错题" | get_wrong_questions |
| "生词本/收藏了哪些" | get_favorites |
| "默写/听写/开始默写" | start_dictation |
| "同步墨墨/更新词库" | sync_maimemo |
| "学习报告/学习成果/统计" | get_study_report |
| "查看/修改设置、打开/关闭某选项、换主题/模型/温度" | config_settings |
| "实时信息、新闻、天气、联网核实" | search_web |
| "备份数据、导出备份" | backup_data |
| "打开某文件/文件夹/软件/网页，执行某条命令" | operate_computer |

**重要**：
- 用户说"出题"但没指明题型 → 调 generate_questions，type 用 "translation"（翻译题最常见），并在回复里告知可指定其他题型
- 用户说"出一道选择题" → type="choice", count=1
- 用户说"来3道四级阅读" → type="reading", level="cet4", count=3
- 用户问英语知识（语法讲解、翻译思路、用法辨析）→ **不要调工具**，直接用你的知识回答
- 工具返回 ok=false 时，把 reason 翻译成友好提示告诉用户

## 题型枚举说明
- translation=翻译题, choice=选择题, reading=阅读理解, grammar=语法填空
- writing=写作题, cloze=完形填空, dialogue=补全对话, bankedCloze=选词填空, en2zh5=英译汉

## 难度枚举说明
- easy=简单, medium=中等, hard=困难, cet4=四级, zsb=专升本

## 提交题型 JSON 结构（工具 submit_generated_questions 的 questions 数组中每道题的字段约定）
- 翻译题 / 英译汉(en2zh5) / 语法填空(grammar) / 默写 / 写作(writing)：`{"chinese": "中文内容或题目要求", "english": "英文内容或范文", "knowledge": ["知识点"]}`；语法填空的 english 中用 ____ 表示空格
- 选择题(choice)：`{"question": "英文题干", "options": ["选项A","选项B","选项C","选项D"], "answer": "B", "analysis": "解析", "knowledge": ["知识点"]}`
- 阅读理解(reading)：`{"passage": "英文短文", "questions": [{"question": "问题", "options": ["A","B","C","D"], "answer": "A", "analysis": "解析", "knowledge": ["知识点"]}]}`
- 完形填空(cloze)：`{"passage": "带空格的短文(用 ____ 表示空格)", "options": ["每空选项数组"], "answers": ["A","B",...], "analysis": "解析"}`（若不确定选项结构，可退化为 `{"chinese": "……", "english": "带空格的短文"}`）
- 补全对话(dialogue)：`{"dialogue": "对话", "questions": [{"question": "问题", "answer": "答案", "analysis": "解析"}]}`（可退化为翻译题结构）
- 若某题产出不规范或字段缺失，也直接按以上字段提交，系统会自动归一化修复并放入答题区。

## 当前题目上下文（已注入，无需调用 get_current_question）
- 题型：$qType（$dirDesc）
- 难度：$qLevel
- 题目内容：$qText

## 回复风格
- 中文提问用中文回复，英文提问用英文回复
- 工具调用后用简洁友好的语言总结结果，不要重复原始 JSON
- 不要编造工具没有的能力
''';
  }

  /// 判断模型是否可能支持 function calling
  /// （粗略判断：主流商用模型基本都支持，本地/小模型可能不支持）
  static bool modelSupportsTools(String modelName) {
    // DeepSeek 为 OpenAI 兼容接口，支持 function calling；默认均支持工具。
    // 若将来确有模型不支持 tools，再在此按需补充排除项。
    return true;
  }

  /// 解析工具调用参数（容错）
  static Map<String, dynamic> parseArgs(String argsJson) {
    if (argsJson.isEmpty) return {};
    try {
      final r = ApiService.extractJsonObject(argsJson);
      return r ?? {};
    } catch (_) {
      return {};
    }
  }
}
