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
| "全卷/模拟考试/套卷/76题" | generate_full_exam |
| "xx什么意思/怎么读/怎么用"（xx是英文单词） | lookup_word |
| "剖析/分析单词/标注释义" | analyze_words |
| "这道题/当前题目是什么" | get_current_question |
| "换一道/下一题" | next_question |
| "收藏" | toggle_favorite |
| "进度/正确率/学得怎么样" | get_progress |

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
    final m = modelName.toLowerCase();
    // 已知不支持 tools 的模型（示例，按需补充）
    if (m.contains('deepseek-v4-flash')) return false;
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
