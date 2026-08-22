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
  /// 终端命令退出码（仅 operate_computer 的 run_command 有值）
  final int? exitCode;
  /// 终端原始输出（stdout + stderr，供 UI 终端块展示）
  final String? terminalOutput;
  const ToolExecResult({
    required this.content,
    required this.ok,
    this.actionLabel = '',
    this.exitCode,
    this.terminalOutput,
  });
}

class AgentService {
  /// OpenAI Function Calling 格式的工具定义。原生工具 + MCP server 工具合并。
  static List<Map<String, dynamic>> toolDefinitions({List<Map<String, dynamic>> mcpTools = const []}) {
    return [..._nativeToolDefinitions(), ...mcpTools];
  }

  /// 仅返回内置工具（不含 MCP）
  static List<Map<String, dynamic>> _nativeToolDefinitions() => [
        {
          'type': 'function',
          'function': {
            'name': 'generate_questions',
            'description': '为用户生成英语练习题并放入答题区。当用户要求出题、练习、做题、生成综合模拟全卷时调用。',
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
                    'mixed',
                  ],
                  'description': '题型：translation=翻译题, choice=选择题, reading=阅读理解, grammar=语法填空, writing=写作题, cloze=完形填空, dialogue=补全对话, bankedCloze=选词填空, en2zh5=英译汉, mixed=综合模拟全卷（76题/7题型/120分钟/150分）',
                },
                'level': {
                  'type': 'string',
                  'enum': ['easy', 'medium', 'hard', 'cet4', 'zsb', 'maimemo'],
                  'description': '难度：easy=简单, medium=中等, hard=困难, cet4=四级, zsb=专升本, maimemo=墨墨词库（从墨墨今日已学习单词中抽取）。未指定时默认 zsb',
                },
                'count': {
                  'type': 'integer',
                  'description': '题目数量（1-50；mixed 全卷固定76题忽略此参数），默认 1',
                  'minimum': 1,
                  'maximum': 50,
                },
                'wordCount': {
                  'type': 'integer',
                  'description': '每题目标词数（30-300，主要影响翻译题长度），默认 80',
                  'minimum': 30,
                  'maximum': 300,
                },
                'useBank': {
                  'type': 'boolean',
                  'description': '是否使用题库（true=从题库抽取，false=用AI全新生成）。用户明确说"不要题库"/"AI出题"/"新题"时设为false，否则默认true',
                },
                'direction': {
                  'type': 'string',
                  'enum': ['zh2en', 'en2zh'],
                  'description': '翻译方向（仅 type=translation/en2zh5 有效）：zh2en=中译英（看中文写英文），en2zh=英译中（看英文写中文）。默认 zh2en',
                },
                'mode': {
                  'type': 'string',
                  'enum': ['fast', 'normal', 'deep'],
                  'description': '词汇剖析模式：fast=快速（纯词典）, normal=正常（词典+AI）, deep=深度（AI语境分析+词组识别）。默认 normal',
                },
                'customReq': {
                  'type': 'string',
                  'description': '用户的自定义要求（如话题、字数、文体等），会作为出题附加提示词',
                },
              },
              'required': ['type'],
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
                    'mixed',
                  ],
                  'description': '题型（缺省为每道题目自身的 type 字段）。translation=翻译题, choice=选择题, reading=阅读理解, grammar=语法填空, writing=写作题, cloze=完形填空, dialogue=补全对话, bankedCloze=选词填空, en2zh5=英译汉, mixed=综合模拟全卷',
                },
                'level': {
                  'type': 'string',
                  'enum': ['easy', 'medium', 'hard', 'cet4', 'zsb', 'maimemo'],
                  'description': '难度：easy=简单, medium=中等, hard=困难, cet4=四级, zsb=专升本, maimemo=墨墨词库。默认 zsb',
                },
                'direction': {
                  'type': 'string',
                  'enum': ['zh2en', 'en2zh'],
                  'description': '翻译方向（仅 type=translation/en2zh5 有效）。默认 zh2en',
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
        {
          'type': 'function',
          'function': {
            'name': 'str_replace_editor',
            'description':
                '自定义代码编辑工具（仿 Claude Code / dsh-tool-str-replace-editor）：查看、创建和编辑文件。'
                '命令：\n'
                '- view：查看文件（带 cat -n 行号）或目录（列 2 层）。文件可用 view_range: [start, end] 只看某行区间（end=-1 到末尾）。\n'
                '- create：创建新文件（path 已存在则拒绝）。\n'
                '- str_replace：精确替换文本。old_str 必须**唯一匹配**文件中的内容（出现 0 次或多次都会失败，需带足够上下文），替换后用 diff 展示变更。\n'
                '- insert：在 insert_line 行之后插入 new_str。\n'
                '写文件首选 view → str_replace / insert（精确改动），不要整文件重写。',
            'parameters': {
              'type': 'object',
              'properties': {
                'command': {
                  'type': 'string',
                  'enum': ['view', 'create', 'str_replace', 'insert'],
                  'description': '要执行的命令：view / create / str_replace / insert',
                },
                'path': {
                  'type': 'string',
                  'description': '文件或目录路径：绝对路径，或工作区内相对路径（如 "src/game.ts"，会按工作区根目录自动解析）。',
                },
                'file_text': {
                  'type': 'string',
                  'description': 'create 命令的必填参数：要创建的文件的完整内容。',
                },
                'insert_line': {
                  'type': 'integer',
                  'description': 'insert 命令的必填参数：new_str 将插入到 insert_line 行之后。',
                },
                'new_str': {
                  'type': 'string',
                  'description': 'str_replace 命令的新文本（可选，缺省不添加）；insert 命令的必填参数（要插入的内容）。',
                },
                'old_str': {
                  'type': 'string',
                  'description': 'str_replace 命令的必填参数：文件中要替换的旧文本，必须唯一匹配。',
                },
                'view_range': {
                  'type': 'array',
                  'items': {'type': 'integer'},
                  'description': 'view 命令可选：行号区间 [start, end]，1 起；[start, -1] 显示 start 行到文件末尾。',
                },
              },
              'required': ['command', 'path'],
            },
          },
        },
        // ========== Code Mode：run_code（仿 dsh-tools/src/code-mode.ts）==========
        {
          'type': 'function',
          'function': {
            'name': 'run_code',
            'description':
                '执行一个 TypeScript async 函数体，通过自动生成的 SDK 一次调用多个工具（Code Mode）。'
                '把原本需要多轮工具往返的操作合并成一轮：在 code 里写 async 函数体，用 `await tools.<工具名>(<参数对象>)` 调用'
                '（如 `await tools.read_file({path: "..."})`、`await tools.bash({command: "dir", description: "列出目录"})`、'
                '`await tools.str_replace_editor({command: "view", path: "..."})`）。'
                '支持顶层 await 与 return。只有你 print 或 return 的内容会返回给模型——请做精简：'
                '不要打印完整大文件，返回关键结果/摘要即可。'
                '参数对象是 JS 对象字面量：键不加引号、字符串值用双引号、数字/布尔/数组/对象直接写。',
            'parameters': {
              'type': 'object',
              'properties': {
                'code': {
                  'type': 'string',
                  'description': 'async 函数体（无 function 声明、无外层花括号），例如：`const f = await tools.read_file({path: "a.txt"}); return f.content.length;`',
                },
                'description': {
                  'type': 'string',
                  'description': '简洁说明这个程序做什么（5-10 词），如 "统计 TODO 标记数量"。',
                },
              },
              'required': ['code', 'description'],
            },
          },
        },
        // ========== harness 风格工具组（仿 deepseek-harness dsh-tool-fs / dsh-tool-bash）==========
        {
          'type': 'function',
          'function': {
            'name': 'read_file',
            'description':
                '读取本地文本文件的内容并返回。路径必须在当前工作区内（工作区根目录见系统提示"当前工作区"一节）；'
                '支持相对路径：不以盘符开头的路径会按工作区根目录自动解析，例如 "src/game.ts"。'
                '单次最多读取 256 KB，超出会被截断并提示"已截断"。',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {
                  'type': 'string',
                  'description': '待读取的文件路径：绝对路径或工作区内相对路径，例如 "src/game.ts"',
                },
              },
              'required': ['path'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'write_file',
            'description':
                '把给定内容写入本地文本文件（覆盖现有内容）。需要 "完全访问" 权限。'
                '路径必须在授权工作目录内；写入前会检查父目录是否存在，不存在则自动创建。',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {
                  'type': 'string',
                  'description': '目标文件路径：绝对路径或工作区内相对路径（如 "src/game.ts"）。',
                },
                'content': {
                  'type': 'string',
                  'description': '待写入的完整文件内容。',
                },
              },
              'required': ['path', 'content'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'edit_file',
            'description':
                '在本地文本文件中按 "旧文本 → 新文本" 做一次精确字符串替换（出现多次只替换第一次）。'
                '需要 "完全访问" 权限。常用于 "在 D:\\foo.txt 末尾追加一行 hello" 或 "把某段错误表述改成正确版本"。',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {
                  'type': 'string',
                  'description': '目标文件路径：绝对路径或工作区内相对路径。',
                },
                'old_text': {
                  'type': 'string',
                  'description': '文件中必须恰好存在（至少一次）的旧文本片段。',
                },
                'new_text': {
                  'type': 'string',
                  'description': '替换后的新文本片段。',
                },
              },
              'required': ['path', 'old_text', 'new_text'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'list_dir',
            'description':
                '列出指定目录下的直接子项（不递归），返回每一项的"类型 + 名称 + 大小"三件套。'
                '路径必须在授权工作目录内。',
            'parameters': {
              'type': 'object',
              'properties': {
                'path': {
                  'type': 'string',
                  'description': '目录路径：绝对路径或工作区内相对路径。',
                },
              },
              'required': ['path'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'bash',
            'description':
                '在 Windows 上通过 cmd.exe 执行一条 shell 命令并返回 stdout/stderr 与退出码。需要 "完全访问" 权限。'
                '每次调用都是新 shell，不保留 cwd/变量/函数——需要换工作目录请在命令前用 cd /d <dir> 一次性完成。'
                '命令执行阻塞最长 30 秒；后台任务请自行重写为更短的子命令。',
            'parameters': {
              'type': 'object',
              'properties': {
                'command': {
                  'type': 'string',
                  'description': '待在 cmd.exe 下执行的完整命令；不要使用交互式命令。',
                },
                'description': {
                  'type': 'string',
                  'description': '一句话说明这条命令要做什么，便于审计。',
                },
                'timeout_ms': {
                  'type': 'integer',
                  'description': '可选超时（毫秒），1-60000，默认 30000。',
                },
              },
              'required': ['command', 'description'],
            },
          },
        },
        // ========== dsh-tool-todo（仿 @deepseek-ai/dsh-tool-todo）==========
        {
          'type': 'function',
          'function': {
            'name': 'todo',
            'description':
                '记录和更新当前工作的结构化任务清单。**每次调用都提交完整列表**，会替换旧列表（不支持部分修改、单条编辑）。'
                '用于规划多步任务并向用户展示进度；为每一个具体步骤建立 todo 后再开始。'
                '**同一时刻只能有一个 todo 处于 in_progress**；一旦某项完成立刻标 completed，禁止批量完成。'
                'trivial 单步任务可跳过。'
                'statuses: pending（未开始）/ in_progress（进行中）/ completed（已完成）。',
            'parameters': {
              'type': 'object',
              'properties': {
                'todos': {
                  'type': 'array',
                  'description': '完整的 todo 列表。每条：{"content": "做什么", "status": "pending|in_progress|completed"}。必须重新提交整个列表，不是增量更新。',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'content': {'type': 'string'},
                      'status': {'type': 'string', 'enum': ['pending', 'in_progress', 'completed']},
                    },
                    'required': ['content', 'status'],
                  },
                },
              },
              'required': ['todos'],
            },
          },
        },
        // ========== dsh-tool-skill（仿 @deepseek-ai/dsh-tool-skill）==========
        {
          'type': 'function',
          'function': {
            'name': 'skill',
            'description':
                '从可用技能目录加载某个技能的完整指令（渐进式披露：系统提示词只含技能名称与触发描述，正文需通过本工具加载）。'
                '当用户任务命中系统提示词「可用技能目录」中任一技能的触发场景时，在做任何匹配该技能的工作前先调用它。'
                '使用准确的技能名或 id（如 skill-creator、frontend-design、native_analyze_words）。'
                '返回的是该技能在工作流中应使用的完整系统级指令。',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {
                  'type': 'string',
                  'description': '技能列表中的准确名称（中文 / 英文 / id 均可）。',
                },
              },
              'required': ['name'],
            },
          },
        },
        // ========== dsh-tool-web（web_fetch 仿 @deepseek-ai/dsh-tool-web）==========
        {
          'type': 'function',
          'function': {
            'name': 'web_fetch',
            'description':
                '抓取并解析一个 HTTP(S) URL 的正文，返回 Markdown/纯文本（去脚本/CSS）。最长 200KB；超时 30s。'
                '用于读取具体网页内容（文档、博客、API 描述）。不适合需要登录的页面。',
            'parameters': {
              'type': 'object',
              'properties': {
                'url': {
                  'type': 'string',
                  'description': '完整 http(s) URL，例如 https://example.com/article。',
                },
                'max_chars': {
                  'type': 'integer',
                  'description': '可选最大字符数（默认 200000，截断时附加 [已截断]）。',
                },
              },
              'required': ['url'],
            },
          },
        },
        // ========== dsh-tool-session-query（仿 @deepseek-ai/dsh-tool-session-query）==========
        {
          'type': 'function',
          'function': {
            'name': 'session_query',
            'description':
                '跨会话查询历史对话。操作：list_sessions（列出最近的会话简表）/ search_history（在指定会话内按关键词搜索消息）/ get_session（获取某会话的完整消息）。'
                '用于回顾之前与 AI 的对话、查找之前讨论过的题目或知识点。',
            'parameters': {
              'type': 'object',
              'properties': {
                'operation': {
                  'type': 'string',
                  'enum': ['list_sessions', 'search_history', 'get_session'],
                  'description': '操作类型',
                },
                'query': {
                  'type': 'string',
                  'description': 'search_history 时必填：关键词；list_sessions 时可选：按标题前缀过滤。',
                },
                'session_id': {
                  'type': 'string',
                  'description': 'get_session / search_history 时必填：会话标识（可从 list_sessions 的 id 字段拿到）。',
                },
                'limit': {
                  'type': 'integer',
                  'description': '返回条数上限，默认 20。',
                },
              },
              'required': ['operation'],
            },
          },
        },
        // ========== dsh-tool-subagent（仿 @deepseek-ai/dsh-tool-subagent）==========
        {
          'type': 'function',
          'function': {
            'name': 'spawn_subagent',
            'description':
                '派生一个隔离的子 Agent 处理子任务（办公、写文档、数据分析、写/改代码等重活优先派发）。'
                '子 Agent 拥有自己的对话历史和上下文，能多轮自主调用工具'
                '（read_file / write_file / edit_file / list_dir / bash / str_replace_editor / web_fetch / search_web / todo），'
                '直到完成子任务后返回最终报告。子 Agent 的中间过程不会污染主对话上下文。'
                'type=general 用于通用任务与办公；type=research 用于联网检索并汇总；type=coder 用于写/改代码。'
                '结果作为 JSON 字符串返回：{"reply": "...", "steps": [...]}。',
            'parameters': {
              'type': 'object',
              'properties': {
                'task': {
                  'type': 'string',
                  'description': '子任务的清晰描述，包括目标、输入、期望输出格式。写得越具体，子 Agent 完成得越好。',
                },
                'type': {
                  'type': 'string',
                  'enum': ['general', 'research', 'coder'],
                  'description': '子 Agent 类型。默认 general。',
                },
                'context': {
                  'type': 'string',
                  'description': '可选背景信息（被嵌入到子 Agent 的 system prompt 前）。',
                },
              },
              'required': ['task'],
            },
          },
        },
        // ========== dsh-mcp-client（仿 @deepseek-ai/dsh-mcp-client）==========
        // 用户在设置里填 mcp_servers，AppState 启动时拉起这些 server 并把它们的 tools 合并进来。
        // 这里仅注册一个空的 list_mcp_tools 占位（实际 MCP 工具列表是动态拼接的）。
        {
          'type': 'function',
          'function': {
            'name': 'list_mcp_tools',
            'description':
                '列出当前已连接的 MCP server 提供的所有工具。返回 {"servers": [{"name": "...", "tools": [{"name": "...", "description": "..."}]}]}。'
                '需要在设置中配置 MCP server 后才返回非空结果。',
            'parameters': {
              'type': 'object',
              'properties': {},
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'call_mcp_tool',
            'description':
                '调用某个 MCP server 上的工具。server_name 是 list_mcp_tools 返回的 server 名；tool_name 是该 server 暴露的工具名；arguments 是该工具的参数对象。',
            'parameters': {
              'type': 'object',
              'properties': {
                'server_name': {'type': 'string'},
                'tool_name': {'type': 'string'},
                'arguments': {
                  'type': 'object',
                  'description': '该 MCP 工具的参数对象，键值对。',
                  'additionalProperties': true,
                },
              },
              'required': ['server_name', 'tool_name', 'arguments'],
            },
          },
        },
        // ========== dsh-tool-ask-user（仿 @deepseek-ai/dsh-tool-ask-user）==========
        {
          'type': 'function',
          'function': {
            'name': 'ask_user_question',
            'description':
                '当你需要用户做选择、确认或补全缺失信息时调用，给用户一个或多个问题，每个问题带 2-4 个选项（推荐项放第一并加 "(Recommended)"）。'
                '返回 {"answers": [{id, selected: [...], custom}]}，selected 是选项 label 数组，custom 是用户自由文本（可选）。',
            'parameters': {
              'type': 'object',
              'properties': {
                'questions': {
                  'type': 'array',
                  'description': '要问用户的问题列表。',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'id': {'type': 'string', 'description': '问题唯一 id，会在答案里回显。'},
                      'question': {'type': 'string'},
                      'header': {'type': 'string', 'description': '短标题（如 "选择模式"）。'},
                      'options': {
                        'type': 'array',
                        'items': {
                          'type': 'object',
                          'properties': {
                            'label': {'type': 'string'},
                            'description': {'type': 'string'},
                          },
                        },
                      },
                      'multi_select': {'type': 'boolean', 'description': '是否可多选，默认 false。'},
                    },
                    'required': ['id', 'question'],
                  },
                },
              },
              'required': ['questions'],
            },
          },
        },
        // ========== dsh-tool-compaction（仿 @deepseek-ai/dsh-tool-compaction）==========
        {
          'type': 'function',
          'function': {
            'name': 'compact_conversation',
            'description':
                '把当前对话的早期消息压缩成一段简洁的摘要，保留关键事实（用户偏好、之前的结论、关键参数）。'
                '当消息列表变长、token 使用率接近上限（>80%）时主动调用。'
                '保留最近 N 条消息（默认 8），其余用一次模型调用总结。',
            'parameters': {
              'type': 'object',
              'properties': {
                'focus': {
                  'type': 'string',
                  'description': '要重点保留的信息，例如 "保留我的生词本偏好" / "保留代码改动列表"。',
                },
                'keep_recent': {
                  'type': 'integer',
                  'description': '保留最近 N 条消息原样（默认 8）。',
                },
              },
            },
          },
        },
        // ========== dsh-tool-skill-filesystem（仿 @deepseek-ai/dsh-skill-filesystem）==========
        {
          'type': 'function',
          'function': {
            'name': 'list_user_skills',
            'description':
                '列出当前工作区下 ".dsh/skills" 目录中的所有用户自定义技能（Markdown 文件，YAML frontmatter 含 name/description）。'
                '用于发现用户在文件系统里放的技能，然后可调用 load_skill 加载完整指令。',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'load_skill',
            'description':
                '加载一个用户自定义技能（来自 .dsh/skills/*.md）的完整指令正文（去掉 YAML frontmatter）。',
            'parameters': {
              'type': 'object',
              'properties': {
                'name': {'type': 'string', 'description': '技能的 name 或文件名（不含扩展名）。'},
              },
              'required': ['name'],
            },
          },
        },
        // ========== dsh-plan-mode（仿 @deepseek-ai/dsh-plan-mode）==========
        {
          'type': 'function',
          'function': {
            'name': 'submit_plan',
            'description':
                '提交一份完整计划让用户审批。计划是一组有序步骤，每步说明做什么、用什么工具、产出什么。'
                '用户看到完整计划后选择：批准 → AI 按计划执行 / 修改 → AI 根据反馈调整 / 拒绝 → AI 重新规划。',
            'parameters': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string', 'description': '计划标题。'},
                'summary': {'type': 'string', 'description': '一句话总结（50 字内）。'},
                'steps': {
                  'type': 'array',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'step': {'type': 'integer'},
                      'action': {'type': 'string', 'description': '这一步做什么。'},
                      'tools': {
                        'type': 'array',
                        'items': {'type': 'string'},
                        'description': '将用到的工具名列表。',
                      },
                      'output': {'type': 'string', 'description': '这一步的产出（如 "修改 foo.txt"、"生成 3 道题"）。'},
                    },
                    'required': ['step', 'action'],
                  },
                },
              },
              'required': ['title', 'steps'],
            },
          },
        },
        // ========== dsh-tool-jobs（仿 @deepseek-ai/dsh-tool-jobs）==========
        {
          'type': 'function',
          'function': {
            'name': 'run_background_job',
            'description':
                '把一个 bash 命令作为后台任务跑，立即返回 job_id。AI 后续用 job_output 看进度、job_kill 终止。'
                '适合长时间任务（编译、安装、训练）。',
            'parameters': {
              'type': 'object',
              'properties': {
                'command': {'type': 'string'},
                'description': {'type': 'string'},
              },
              'required': ['command', 'description'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'job_output',
            'description': '获取后台任务的最新输出（stdout + stderr + 退出码）。',
            'parameters': {
              'type': 'object',
              'properties': {
                'job_id': {'type': 'string'},
                'wait': {'type': 'boolean', 'description': '是否阻塞等待任务结束（默认 true）。'},
                'timeout_ms': {'type': 'integer', 'description': '阻塞最多多少毫秒（默认 5000）。'},
              },
              'required': ['job_id'],
            },
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'job_kill',
            'description': '终止一个后台任务。',
            'parameters': {
              'type': 'object',
              'properties': {'job_id': {'type': 'string'}},
              'required': ['job_id'],
            },
          },
        },
        // ========== dsh-guard（仿 @deepseek-ai/dsh-repeat-tool-reminder）==========
        {
          'type': 'function',
          'function': {
            'name': 'check_repeat',
            'description':
                '检查最近的工具调用是否有重复（同一工具+同一参数）。如果发现重复，会在响应里指出，'
                'AI 应该停止重复调用，转而基于已有结果继续。如果你的最近调用没有重复，可直接忽略返回。',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
      ];

  /// Agent 系统 prompt（动态生成，注入当前题目上下文，避免 AI 凭空猜测）
  /// [skillCatalog]：技能商店目录（每行「- 名称（id: xxx）：描述」），仅元数据不注入正文，
  /// 正文由 AI 调用 skill 工具按需加载（渐进式披露，节省上下文）。
  static String buildSystemPrompt({String? skillCatalog}) {
    final base = '''你是 AFloat，一个英语学习 Agent 助手。你能通过工具调用直接帮用户执行操作，也能回答英语问题。

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
| "这道题/当前题目是什么/这道题怎么做/考什么内容" | get_current_question（直接工具调用，永远可用）；如果工作区已加载 exam-context / 「当前题目」等相关技能，则 load_skill 按技能指引作答（技能可封装更丰富的应答策略） |
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
| "读/写/编辑本地文件，列目录，执行 shell 命令" | read_file / write_file / edit_file / list_dir / bash（需要"完全访问"） |
| "查看带行号的代码、创建文件、精确替换/插入（coding 场景优先）" | str_replace_editor（view/create/str_replace/insert） |
| "一次性连续执行多个工具（多步文件操作合并）" | run_code（Code Mode：`await tools.<工具名>({...})`） |
| "下一步拆解多步任务" | todo（按 dsh-tool-todo 规则：单 in_progress，每次提交完整列表） |
| "按某技能的具体指令工作" | skill（按下方「可用技能目录」匹配技能名，或直接传中文名；不要用 list_mcp_tools——那是 MCP 工具清单，不是技能目录） |
| "OCR/表格/手写/公式识别、文生图、股票分析、简历筛选、PDF转PPT/网页、GitHub操作等专项任务" | skill（按下方「可用技能目录」匹配技能名，加载完整指令后按其工作流执行） |
| "抓取网页内容（已去除脚本样式）" | web_fetch |
| "查找之前对话、列出会话清单" | session_query |
| "派生子 Agent 处理子任务（research/coder/general）" | spawn_subagent |
| "写周报/日报/会议纪要/邮件草稿/求职简历文案" | skill（「办公效率」类技能，如 work-weekly-report / work-meeting-notes / work-email-draft），产出必须写成文件交付 |
| "做 Word 文档/PPT/Excel 表格/PDF" | skill（work-office-docs）：Windows 下用 bash 跑 PowerShell 脚本生成真正的 Office 文件 |
| "分析这份数据/CSV/Excel/日志/给出结论" | skill（work-data-analysis）：read_file/list_dir 看数据 → bash(PowerShell) 统计 → 报告落盘 |
| "帮我调研 X/查资料汇总成报告" | skill（work-research-brief）：search_web/web_fetch 多源交叉核实 → 报告落盘；量大派 spawn_subagent(type=research) |
| "把这份材料翻译成中/英文（合同/论文/简历级）" | skill（work-pro-translation）：术语表 → 初译 → 润色 → 校对，双语对照落盘 |
| "办公、写文档、做数据分析、写/改代码等重活、多步骤独立任务" | spawn_subagent（优先派发子 Agent 隔离执行，避免污染主对话上下文；子 Agent 可自主调用文件/命令/搜索工具多轮完成） |
| "调用任意 MCP server 提供的工具（需先 list_mcp_tools）" | list_mcp_tools / call_mcp_tool |
| "需要用户做选择/确认/补全信息" | ask_user_question（先列 2-4 个选项，推荐项加 (Recommended)） |
| "对话太长，token 接近上限（>80%）" | compact_conversation（保留最近 N 条，旧的总结成摘要） |
| "用户想用工作区里的自定义技能（.dsh/skills/*.md）" | list_user_skills / load_skill |
| "复杂多步任务开始前" | submit_plan（先让用户审批整个计划） |
| "跑长时间命令（编译/训练/下载）" | run_background_job → job_output / job_kill |
| "怀疑自己在重复同一个工具调用" | check_repeat |

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

## 当前题目（工具优先，技能可选）
- **直接获取**（推荐）：调用 `get_current_question` 工具获取当前题目（type/level/text/direction），无需任何前置条件，永远可用。
- **技能包装**（可选）：工作区中如果加载了 exam-context / 「当前题目」等技能，可先 `list_user_skills` 检查是否命中，命中后 `load_skill` 按技能指引作答（技能可封装更细致的应答模板，但不可强依赖）。
- 任何情况下不要凭记忆编造题目内容；获取失败必须如实说明。

## 防提前收尾（关键）
- 多步任务中，**只要还有未完成的子任务，就必须继续调用工具，禁止输出总结性文字提前结束**。
- 每轮工具调用后重新评估进度：还有剩余工作 → 立即继续下一步工具调用；全部完成 → 才输出最终总结。
- 如果某次工具调用失败，修复参数重试或换工具，不要放弃。
- 当输出可能较长时，拆分为多轮完成，每轮聚焦一部分，避免一次性输出过长被截断。
- **辅助类工具（load_skill / list_user_skills / session_query / compact_conversation / check_repeat）不等于任务完成**。这些只是查询/加载动作，必须根据加载结果继续调用核心工具（如 get_current_question / read_file / 答题/出题工具），再基于真实数据作答。**绝对禁止**只调完辅助工具就输出"已完成：…"作为最终回复。
- 把"已完成：xxx"这种总结性文字作为最终回复前，**自检一遍**：用户提出的核心问题得到了实际执行工具的回答吗？纯粹"加载技能"不算已回答。

## 真实工作任务守则（办公/工作场景）
- **先锁定交付物再动手**：格式（docx/xlsx/pptx/md/csv/pdf）、保存位置、篇幅、受众、截止时间。信息不足时用 ask_user_question 一次性问清关键项（2-4 问），不要连环追问也不要擅自假设关键约束。
- **交付必须落盘**：文档/表格/报告/代码一律写成文件（write_file 或脚本生成），最终回复给出完整路径；桌面端再用 operate_computer(open_file) 帮用户直接打开。只把全文贴在聊天里不算交付。
- **PowerShell 脚本模式**：bash 是 cmd.exe（每轮全新 shell、默认 30 秒超时）。超过一行的系统操作先 write_file 写 .ps1 脚本，再执行 `powershell -NoProfile -ExecutionPolicy Bypass -File <脚本>.ps1`——避免 cmd 引号地狱与超长单命令。
- **中文编码陷阱**：PowerShell 5.1 把无 BOM 的 .ps1 按 ANSI 解析，脚本里的中文会乱码。做法：中文内容放独立 UTF-8 文本文件（write_file 写入），.ps1 内用 `Get-Content -Encoding UTF8` 读取；.ps1 本身只含 ASCII 字符。
- **生成真正的 Office 文件**：机器装了 Office 时优先 COM 自动化（`New-Object -ComObject Word.Application / Excel.Application / PowerPoint.Application`）；未装 Office 时降级 Markdown/CSV/HTML 并向用户说明原因。
- **多步任务先规划**：≥3 步的任务先 todo 列清单逐步推进；耗时的独立子任务派 spawn_subagent 隔离执行；方案需要用户拍板时先 submit_plan。
- **完成前自检**：文件写完后 read_file 读回抽查关键段落，或用脚本验证文件存在且非空；失败就修复重试，不要把半成品交给用户。

## 回复风格
你的工具使用习惯：
- 写文件首选 read_file → edit_file（精确替换），其次 write_file（整段覆盖）
- bash 每次都是新 shell，不要假设 cwd；需要时显式写 `cd /d <dir> && <cmd>`
- 中文提问用中文回复，英文提问用英文回复
- 工具调用后用简洁友好的语言总结结果，不要重复原始 JSON
- 不要编造工具没有的能力

## 可用技能目录（渐进式披露）
以下是当前启用的技能列表（仅名称与触发描述，完整指令未注入）。
当用户任务命中某技能的触发场景时，**先调用 skill 工具加载该技能的完整指令**，再严格按指令工作流执行。
技能正文只在需要时加载一次，不要为不相关的任务加载技能。
''';
    final catalog = (skillCatalog ?? '').trim();
    if (catalog.isEmpty) return base;
    return '$base\n$catalog';
  }

  /// 判断模型是否支持 function calling。
  /// 默认放行（主流 OpenAI 兼容模型均支持）；仅对已知不支持工具调用的
  /// 模型族返回 false——此时 Agent 循环自动降级为普通对话，
  /// 避免向模型发送 tools 触发 400 报错。
  static bool modelSupportsTools(String modelName) {
    final m = modelName.toLowerCase();
    // DeepSeek R1/reasoner：推理模型不支持 function calling
    if (m.contains('deepseek-reasoner') || m.contains('deepseek-r1')) return false;
    // 非对话类模型（嵌入/重排/语音/图像生成）
    const nonChat = [
      'embedding', 'embed', 'rerank', 'whisper', 'tts',
      'dall-e', 'stable-diffusion', 'sora',
    ];
    for (final k in nonChat) {
      if (m.contains(k)) return false;
    }
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
