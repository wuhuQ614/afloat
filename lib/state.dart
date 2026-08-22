/// 全局状态与核心业务逻辑（对应网页版 index.html 中的 state 与各函数）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, HttpClient, Platform, Process, systemEncoding;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, SystemUiMode, SystemUiOverlayStyle;
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'theme_colors.dart' show AppColors;
import 'services/api_service.dart';
import 'services/maimemo_service.dart';
import 'services/storage.dart';
import 'services/dict_service.dart';
import 'services/agent_service.dart';
import 'services/chat_capabilities.dart';
import 'services/mcp_client.dart';
import 'services/skill_store.dart';

/// 单词跨度信息（用于词组匹配）
class _WordSpan {
  final String text;
  final int start;
  final int end;
  const _WordSpan({required this.text, required this.start, required this.end});
}

/// Agent 单次工具调用步骤（用于在 AI 气泡上方单独展示，仿 deepseek ToolRow）
class ToolStep {
  /// 工具函数名（如 "search_web"、"operate_computer"）
  String name;
  /// 展示文案，如 "生成 3 道翻译题"、"查询单词 hello"
  String label;
  /// 是否执行中（显示加载动画）
  bool running;
  /// 是否执行成功（显示对勾）
  bool done;
  /// 是否执行失败（显示错误）
  bool failed;
  /// 工具入参摘要（IN 卡片展示用，可为空）
  String? input;
  /// 命令/工具执行的返回内容（OUT 卡片 / 终端输出展示用，可为空）
  String? output;
  /// 是否以终端块（TerminalBlock）样式展示（operate_computer 的 run_command）
  bool terminal;
  /// 终端块展示的命令行
  String? command;
  /// 终端命令退出码（失败时展示 "退出码 N"）
  int? exitCode;
  /// 子 Agent 派发（spawn_subagent）专属：子任务类型 general/research/coder
  String? subType;
  /// 子 Agent 派发专属：子任务描述（卡片头部展示）
  String? subTask;
  /// 子 Agent 派发专属：子 Agent 的执行事件流
  /// 每项 {type: 'tool', name, label, status: running|done|fail} 或 {type: 'round', n}
  List<Map<String, dynamic>> subEvents = [];
  ToolStep({
    required this.name,
    required this.label,
    this.running = true,
    this.done = false,
    this.failed = false,
    this.input,
    this.output,
    this.terminal = false,
    this.command,
    this.exitCode,
    this.subType,
    this.subTask,
  });
}

/// AI 任务清单（dsh-tool-todo 风格）
class TodoItem {
  final String content;
  final String status; // pending / in_progress / completed
  const TodoItem({required this.content, required this.status});
  Map<String, dynamic> toJson() => {'content': content, 'status': status};
}

/// dsh-tool-ask-user 问题
class AskUserQuestion {
  final String id;
  final String question;
  final String? header;
  final List<AskUserOption> options;
  final bool multiSelect;
  const AskUserQuestion({
    required this.id,
    required this.question,
    this.header,
    required this.options,
    this.multiSelect = false,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'question': question,
        if (header != null) 'header': header,
        'options': options.map((o) => o.toJson()).toList(),
        'multi_select': multiSelect,
      };
}

class AskUserOption {
  final String label;
  final String? description;
  const AskUserOption({required this.label, this.description});
  Map<String, dynamic> toJson() => {'label': label, if (description != null) 'description': description};
}

/// dsh-plan-mode 计划步骤
class PlanStep {
  final int step;
  final String action;
  final List<String> tools;
  final String? output;
  const PlanStep({
    required this.step,
    required this.action,
    this.tools = const [],
    this.output,
  });
  Map<String, dynamic> toJson() => {
        'step': step,
        'action': action,
        'tools': tools,
        if (output != null) 'output': output,
      };
}

/// dsh-plan-mode 完整计划
class PlanSubmission {
  final String title;
  final String? summary;
  final List<PlanStep> steps;
  String status = 'pending'; // pending / approved / rejected / modified
  String? userNote;
  PlanSubmission({required this.title, this.summary, required this.steps});
  Map<String, dynamic> toJson() => {
        'title': title,
        if (summary != null) 'summary': summary,
        'steps': steps.map((s) => s.toJson()).toList(),
        'status': status,
        if (userNote != null) 'userNote': userNote,
      };
}

/// dsh-tool-jobs 后台任务
class BackgroundJob {
  final String jobId;
  final String command;
  final String description;
  final DateTime startedAt;
  bool finished = false;
  int? exitCode;
  String stdout = '';
  String stderr = '';
  /// 真实进程引用：job_kill 时能真正终止，而不是只改标志位
  Process? process;
  /// 已被 kill：完成回调不得再覆写 stdout/stderr/finished（否则反向覆盖 kill 标记）
  bool killed = false;
  BackgroundJob({
    required this.jobId,
    required this.command,
    required this.description,
    required this.startedAt,
  });
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
  /// 本条 AI 消息使用的模型名（用于气泡上方显示）。Auto 模式时由本次 sendChat 选定。
  String? modelLabel;
  /// todo 工具调用产生的任务清单（dsh-tool-todo 风格）
  List<TodoItem> todoList = [];
  /// ask_user_question 工具产生的问题（dsh-tool-ask-user 风格）
  List<AskUserQuestion> askQuestions = [];
  /// 用户对 askQuestions 的实际回答
  Map<String, List<String>> askAnswers = {};
  /// submit_plan 工具提交的计划（dsh-plan-mode 风格）
  PlanSubmission? plan;
  /// 运行中的一句话进度（如"思考下一步（第 2 轮）…"），仅在消息生成期间展示；
  /// 工具步骤卡片出现或正文开始输出后应置 null，避免与步骤卡片重复。
  String? statusLabel;

  ChatMessage({required this.role, required this.content, this.showReasoning = false, this.reasoningExpanded = true, this.reasoning, this.imageData, this.imageDark = false, this.modelLabel});

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

/// 上下文 token 分布（用于 UI 展示，非精确值）
class ChatTokenBreakdown {
  final int system;
  final int tools;
  final int messages;
  final int connectors;
  final int skills;
  final int maxTokens;

  const ChatTokenBreakdown({
    required this.system,
    required this.tools,
    required this.messages,
    required this.connectors,
    required this.skills,
    required this.maxTokens,
  });

  int get used => system + tools + messages + connectors + skills;
  double get usedPct => maxTokens == 0 ? 0 : (used / maxTokens).clamp(0.0, 1.0);
  double pctOf(int value) => maxTokens == 0 ? 0 : (value / maxTokens).clamp(0.0, 1.0);

  String formatK(int value) => '${(value / 1000).toStringAsFixed(1)}K';

  /// 当前占总容量百分比字符串（保留 1 位小数）
  String formatUsedPct() => '${(usedPct * 100).toStringAsFixed(1)}%';

  /// 各分类占总容量百分比字符串
  String formatPctOf(int value) => maxTokens == 0 ? '0.0%' : '${(pctOf(value) * 100).toStringAsFixed(1)}%';

  /// 各分类占"已用"比例（适合「系统提示词占 1.3%」这种行内展示）
  String formatPctOfUsed(int value) {
    if (used == 0) return '0.0%';
    return '${(value / used * 100).toStringAsFixed(1)}%';
  }
}

/// 根据模型名估算上下文窗口大小（token 数）。返回约值，用于 UI 展示。
int estimateContextWindowByModel(String model) {
  final m = model.toLowerCase();
  if (m.contains('qwen3') || m.contains('qwen3-coder')) return 1000000; // 1M
  if (m.contains('kimi') || m.contains('claude')) return 200000; // 200K
  if (m.contains('gemini')) return 1000000;
  if (m.contains('gpt-4')) return 128000;
  if (m.contains('gpt-5')) return 256000;
  if (m.contains('deepseek')) return 128000;
  if (m.contains('glm') || m.contains('chatglm')) return 128000;
  if (m.contains('qwen')) return 32000; // 普通 qwen 默认 32K
  return 256000; // 默认 256K
}

/// Max 模式下扩展后的上下文窗口（token 数）
const int kMaxModeContextWindow = 1000000; // 1M

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
  List<String>? lastMaimemoWords; // 墨墨词库模式：供「换一道」重生成时复用

  /// 墨墨出题参考词抽取：总量 <=500 取全部，>500 取 500+总量/7（结果不超过总量）
  List<String> maimemoRefWords() {
    final words = maimemoWordbook.map((w) => w.word).toList()..shuffle(Random());
    if (words.length <= 500) return words;
    final x = 500 + (words.length / 7).ceil();
    return words.take(x < words.length ? x : words.length).toList();
  }
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
  /// 对话助手权限范围：false=默认权限（沙箱内），true=允许完全访问
  bool chatFullAccess = false;
  /// 当前选中的技能 id（空串 = 无技能）
  String activeSkill = '';
  /// 当前对话模式 id
  String chatMode = 'chat';
  /// 当前专家角色 id（空串 = 默认）
  String activeExpert = '';
  /// 联网搜索连接器开关（关闭后 search_web 工具不可用）
  bool searchEnabled = true;
  /// 联网搜索服务配置（百度千帆 AI 搜索组件）
  String searchUrl = 'https://qianfan.baidubce.com/v2/ai_search/chat/completions';
  String searchKey = '';

  // ===== 开发者模式 =====
  /// 开发者模式：开启后在考场加载页/浮层展示 AI 出题思维链与输出文本
  bool devMode = false;
  /// 开发者日志缓冲区（最近保留 [devLogLimit] 条）
  static const int devLogLimit = 2000;
  final List<String> devLog = [];

  /// 追加一条开发者日志（自动保留最近 [devLogLimit] 条）
  void devLogAdd(String line) {
    if (!devMode) return;
    if (devLog.length >= devLogLimit) devLog.removeAt(0);
    devLog.add(line);
    notifyListeners();
  }

  /// 清空开发者日志
  void devLogClear() {
    if (devLog.isEmpty) return;
    devLog.clear();
    notifyListeners();
  }

  /// 开启/关闭开发者模式（持久化到本地）
  void setDevMode(bool v) {
    if (devMode == v) return;
    devMode = v;
    Storage.saveDevMode(v);
    devLogClear();
    notifyListeners();
  }

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
    debugPrint('NAV setPage: $page -> $p');
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
    chatFullAccess = Storage.loadChatFullAccess();
    workspacePath = Storage.loadWorkspacePath();
    activeSkill = Storage.loadActiveSkill();
    mcpConfigJson = Storage.loadMcpConfigJson();
    chatMode = Storage.loadChatMode();
    activeExpert = Storage.loadActiveExpert();
    // 异步：加载技能商店（内置资产 + 自定义）并连接 MCP server
    () async {
      try {
        await skillStore.load();
        notifyListeners();
      } catch (_) {}
      try {
        await _reconnectMcp();
      } catch (_) {}
    }();
    searchEnabled = Storage.loadSearchEnabled();
    searchUrl = Storage.loadSearchUrl();
    searchKey = Storage.loadSearchKey();
    devMode = Storage.loadDevMode();
    // 开发者模式：将 AI 请求日志写入 devLog 缓冲区
    ApiService.devLogSink = devLogAdd;
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
    // Auto 模式临时覆写：仅本次 sendChat 有效，不持久化
    if (_effectiveChatConfigOverride != null) {
      return _effectiveChatConfigOverride!;
    }
    if (chatApiIndependent) {
      if (chatProfiles.isNotEmpty && chatProfileIdx >= 0 && chatProfileIdx < chatProfiles.length) {
        return chatProfiles[chatProfileIdx].config;
      }
      return chatApiConfig;
    }
    return apiConfig;
  }

  /// Auto 模式下的临时配置覆写；每次 sendChat 入口设置，结束后清理
  ApiConfig? _effectiveChatConfigOverride;
  set effectiveChatConfigOverride(ApiConfig? c) {
    _effectiveChatConfigOverride = c;
  }
  ApiConfig? get effectiveChatConfigOverrideValue => _effectiveChatConfigOverride;

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

  // ===== 公共 setter（供 Agent 工具调用） =====
  /// 设置出题页面"题型"选项
  void setSelectedType(String t) {
    selectedType = t;
    notifyListeners();
  }

  /// 设置出题页面"难度"选项（含 maimemo）
  void setSelectedLevel(String l) {
    selectedLevel = l;
    notifyListeners();
  }

  /// 设置题量（1-50）—— 实际 UI 滑块位于 LearnPageState，这里只更新下次出题使用的值
  void setCount(int n) {
    final v = n.clamp(1, 50);
    lastQuestionCount = v;
    notifyListeners();
  }

  /// 设置每题目标词数（30-300）—— 仅更新下次出题使用的值
  void setWordCount(int n) {
    final v = n.clamp(30, 300);
    lastWordCount = v;
    notifyListeners();
  }

  /// 设置自定义要求文本
  void setCustomReq(String s) {
    lastCustomReq = s;
    notifyListeners();
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
        maimemoWords: lastMaimemoWords,
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

  Future<bool> generateQuestions({required int count, required String customReq, int wordCount = 80, List<String>? maimemoWords}) async {
    generating = true;
    notifyListeners();
    // 记录本次 AI 生成参数，供「换一道」重生成时复用
    lastQuestionSource = 'ai';
    lastCustomReq = customReq;
    lastWordCount = wordCount;
    lastQuestionCount = count;
    if (maimemoWords != null && maimemoWords.isNotEmpty) lastMaimemoWords = maimemoWords;
    final levelNames = {
      'cet4': '大学英语四级（CET-4）',
      'zsb': '专升本英语',
      'easy': '简单',
      'medium': '中等',
      'hard': '困难',
      'maimemo': '墨墨词库',
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

    if (maimemoWords != null && maimemoWords.isNotEmpty) {
      // 墨墨词库出题：仅从参考词汇池中选词，不得调用其他词库
      final moeLevel = levelNames[selectedLevel] ?? '中等';
      final refList = maimemoWords.join('、');
      systemPrompt = '你是一个英语出题专家。请生成 $count 道翻译题（中译英），难度为$moeLevel。' +
          (customReq.isNotEmpty ? '额外要求：$customReq。' : '') +
          '\n【墨墨词库参考词汇】以下单词来自用户的墨墨词库，出题时只能从这些单词中选词：$refList\n\n' +
          '要求：\n' +
          '1. 每道题必须包含至少 2-3 个来自参考词汇的单词，且尽量覆盖参考词汇中不同的单词\n' +
          '2. 只能使用参考词汇中的单词（允许使用派生词、变形及少量连接词/介词/冠词/代词），不得使用参考词汇之外的单词，也不得调用其他任何词库\n' +
          '3. 翻译方向为中译英（题目为中文，答案为英文），每题英文内容约 $wordCount 词\n' +
          '4. 难度$moeLevel，语法正确、表达自然流畅\n\n' +
          '请以JSON数组格式返回，格式如下：\n' +
          '[{"chinese": "中文内容", "english": "英文内容", "knowledge": ["知识点1"]}]\n' +
          '只返回JSON数组，不要其他内容。';
    } else if (selectedLevel == 'zsb' && vocabHint.isNotEmpty) {
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

    // 默认提档到 200000（200k）：deepseek 等推理模型的思考 token 会占用 max_tokens，
    // 给足额度避免 JSON 输出被截断导致解析失败（优先保证能出题）。
    // 部分 API 不支持 200k 上限时（请求失败/无响应）自动降级到 8192 重试一次。
    const maxTokens = 200000;
    // 出题速度为"快速"时，deepseek 等推理模型即使关闭思考参数仍可能深度思考导致出题很慢；
    // 在提示词中追加强指令，让其直接输出结果、跳过思考，显著加速。
    // 出题速度为"正常"时保留模型深度思考能力，不加此抑制。
    if (apiConfig.questionSpeed != 'normal' &&
        ApiService.realModelName(apiConfig.model).toLowerCase().contains('deepseek')) {
      systemPrompt += '\n\n重要：不要进行任何思考或推理，不要输出思考过程，直接给出最终结果。';
    }

    // 出题策略：json=仅JSON / text=仅文本行格式 / auto=JSON优先失败回退文本行格式
    final mode = apiConfig.questionMode.trim().toLowerCase();
    List<Map<String, dynamic>>? list;

    // 文本行格式提示词（兜底策略，不依赖 JSON 输出）
    String textPrompt() {
      var base = systemPrompt;
      final jsonIdx = base.indexOf('请以JSON数组格式返回');
      if (jsonIdx >= 0) base = base.substring(0, jsonIdx);
      final tpl = selectedType == 'reading'
          ? 'passage: 英文短文（可跨多行，直到遇到下一个键）\n'
              'sub1: 问题1\nopt1: A. 选项1|B. 选项2|C. 选项3|D. 选项4\nans1: A\nana1: 解析1\n'
              'sub2: 问题2\nopt2: A. 选项1|B. 选项2|C. 选项3|D. 选项4\nans2: C\n'
          : (selectedType == 'choice'
              ? 'question: 英文题干\noptions: A. 选项1|B. 选项2|C. 选项3|D. 选项4\nanswer: B\nanalysis: 答案解析\nknowledge: 知识点1|知识点2\n'
              : 'chinese: 中文内容\nenglish: 英文内容\nknowledge: 知识点1|知识点2\n');
      return '$base\n【输出要求】不要输出JSON，请严格使用以下文本行格式输出（每行"键: 值"，题目之间用空行分隔）：\n$tpl';
    }

    if (mode == 'text') {
      // 仅文本行格式：直接请求文本格式
      var reply = await ApiService.callAI(
        [
          {'role': 'user', 'content': '请出题'}
        ],
        textPrompt(),
        config: apiConfig,
        maxTokens: maxTokens,
        extraParams: _questionParams(),
      );
      // 部分 API 不支持 200k 上限：失败时降级到 8192 重试一次
      if (reply == null && maxTokens > 8192) {
        reply = await ApiService.callAI(
          [
            {'role': 'user', 'content': '请出题'}
          ],
          textPrompt(),
          config: apiConfig,
          maxTokens: 8192,
          extraParams: _questionParams(),
        );
      }
      generating = false;
      if (reply != null) list = ApiService.parseTextQuestions(reply);
    } else {
      // 默认 JSON 优先
      var reply = await ApiService.callAI(
        [
          {'role': 'user', 'content': '请出题'}
        ],
        systemPrompt,
        config: apiConfig,
        maxTokens: maxTokens,
        extraParams: _questionParams(),
      );
      // 部分 API 不支持 200k 上限：失败时降级到 8192 重试一次
      if (reply == null && maxTokens > 8192) {
        reply = await ApiService.callAI(
          [
            {'role': 'user', 'content': '请出题'}
          ],
          systemPrompt,
          config: apiConfig,
          maxTokens: 8192,
          extraParams: _questionParams(),
        );
      }
      generating = false;
      if (reply != null) list = ApiService.extractJsonArray(reply);
      // auto 兜底：JSON 解析失败时改用文本行格式重新生成，保证能出上题
      if ((list == null || list.isEmpty) && mode != 'json') {
        final reply2 = await ApiService.callAI(
          [
            {'role': 'user', 'content': '请出题'}
          ],
          textPrompt(),
          config: apiConfig,
          maxTokens: maxTokens,
          extraParams: _questionParams(),
        );
        if (reply2 != null) list = ApiService.parseTextQuestions(reply2);
      }
    }

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
        // 竞态防护：批改 await 期间用户切换了题目，则丢弃旧题成绩，
        // 避免旧题的批改结果顶掉新题（对照：考试 AI 批改有 submittedAt 校验）
        if (!identical(currentQuestion, q)) {
          notifyListeners();
          return;
        }
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
    // DeepSeek V4 系列（deepseek-v4-pro / deepseek-v4-flash）：默认开启思考，
    // 官方正确关闭方式为 "thinking": {"type": "disabled"}；
    // 布尔值 enable_thinking 对 V4 无效（返回 400 或被忽略），故不再发送。
    if (m.contains('deepseek') && m.contains('v4')) {
      p['thinking'] = {'type': 'disabled'};
      return p;
    }
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

  /// 出题参数：根据「出题速度」配置决定是否开启模型深度思考。
  /// fast（快速，默认）= 关闭思考直出；normal（正常）= 允许模型深度思考。
  Map<String, dynamic> _questionParams() {
    if (apiConfig.questionSpeed == 'normal') {
      return ApiService.thinkingParams(apiConfig.model);
    }
    return _noThinkingParams();
  }

  Future<void> analyzeWords(String text, {bool force = false}) async {
    try {
      await _analyzeWordsImpl(text, force: force);
    } finally {
      // 兜底：任何异常路径都要复位，否则 analyzing 永久卡 true，
      // 剖析入口被重入保护静默吞掉（后续请求全部无效）
      if (analyzing) {
        analyzing = false;
        notifyListeners();
      }
    }
  }

  Future<void> _analyzeWordsImpl(String text, {bool force = false}) async {
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
        maxTokens: 200000, // 默认 200k，避免批量剖析输出被截断
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
  /// 用户在发送按钮上再点一次时设置；agent 循环每轮检查后正常退出。
  bool _chatAbortRequested = false;
  final ValueNotifier<int> chatUpdateNotifier = ValueNotifier<int>(0);
  int _chatThrottleTimer = 0;

  /// 当前会话在「Auto」模式下选中的 profile 索引（仅当 useAutoModel=true 时有效）。
  /// _pickAutoModel 在 sendChat 时按千问>deepseek>其他优先级抽取。
  int autoSelectedProfileIdx = 0;
  /// 是否处于 Auto 模式（用户从模型浮层选 Auto 项）
  bool useAutoModel = false;
  /// AI 助手本地工作目录。harness 工具（read/write/edit/list_dir/bash）只能在该目录及其子目录下读写。
  /// 空字符串 = 使用默认 C:\Users 下任意位置。
  String workspacePath = '';
  /// 会话快照（dsh-tool-session-query 使用）：最近 50 个会话的 id/title/createdAt/messageCount + 完整消息。
  /// 每次 clearChat 时把当前 chatHistory 持久化成一条快照。
  List<Map<String, dynamic>> chatSessions = [];
  List<List<Map<String, dynamic>>> chatSessionMessages = []; // 每个会话的完整消息（content + role + 时间）
  static const int _kMaxSessions = 50;
  /// MCP server 配置（dsh-mcp-client）：用户可在设置中编辑 JSON 配置后保存。
  String mcpConfigJson = '[]';
  /// MCP 工具列表（启动时从所有 server 拉取）
  List<McpTool> mcpTools = [];
  final McpRegistry mcpRegistry = McpRegistry();
  /// 技能商店：内置（ModelScope 23 技能）+ 用户自定义，渐进式披露
  final SkillStore skillStore = SkillStore();
  /// dsh-tool-jobs 后台任务表
  final Map<String, BackgroundJob> backgroundJobs = {};
  /// dsh-tool-skill-filesystem 用户技能缓存（按 name → 正文）
  final Map<String, String> userSkillsCache = {};
  /// dsh-tool-skill-filesystem 用户技能描述缓存
  final Map<String, String> userSkillDescriptions = {};
  /// dsh-guard 重复工具调用历史（最近 20 条）
  final List<Map<String, dynamic>> recentToolCalls = [];
  /// R13: 同一命令连续失败计数（命令文本 → 连续失败次数），每次对话开始清零
  final Map<String, int> _cmdFailStreak = {};
  /// ask_user_question 挂起的回答 Completer（工具 await 用户在 UI 点确认）
  final Map<String, Completer<Map<String, List<String>>>> _askCompleters = {};
  /// ask completer 自增序号（仅作 key 用）
  int _askSeq = 0;

  /// UI 层用户点"确认"后回填答案，唤醒挂起的 ask_user_question 工具调用
  void completeAskAnswers(Map<String, List<String>> answers) {
    final entries = _askCompleters.entries.toList();
    _askCompleters.clear();
    for (final e in entries) {
      if (!e.value.isCompleted) e.value.complete(answers);
    }
    _notifyChatUpdate();
  }

  void _notifyChatUpdate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _chatThrottleTimer < 50) return; // 50ms 节流
    _chatThrottleTimer = now;
    chatUpdateNotifier.value++;
  }

  /// 进入 Auto 模式（用户从模型浮层选 Auto）
  void enableAutoModel() {
    useAutoModel = true;
    notifyListeners();
  }

  /// 退出 Auto 模式（用户手动选了具体 profile）
  void disableAutoModel() {
    useAutoModel = false;
    notifyListeners();
  }

  /// Auto 优先级：千问 > deepseek > 其他 > 随机
  /// 返回应该用于本次对话的 profile 索引；若无任何 profile 则返回 -1。
  /// 同时更新 autoSelectedProfileIdx 供 UI 显示。
  int pickAutoProfileIdx({int? seed}) {
    final profiles = apiProfiles;
    if (profiles.isEmpty) {
      autoSelectedProfileIdx = -1;
      return -1;
    }
    final r = (seed ?? DateTime.now().millisecondsSinceEpoch) ^ 0xDEADBEEF;
    int tier1 = profiles.indexWhere((p) {
      final m = p.config.model.toLowerCase();
      return m.contains('qwen') || m.contains('tongyi') || m.contains('dashscope');
    });
    if (tier1 < 0) tier1 = profiles.indexWhere((p) => p.config.model.toLowerCase().contains('deepseek'));
    // 优先级权重：千问 0.55 / deepseek 0.30 / 其他 0.15
    int pick;
    final otherIdxs = [for (var i = 0; i < profiles.length; i++) if (i != tier1 && !profiles[i].config.model.toLowerCase().contains('deepseek')) i];
    final deepseekIdxs = [for (var i = 0; i < profiles.length; i++) if (i != tier1 && profiles[i].config.model.toLowerCase().contains('deepseek')) i];

    final rnd = Random(r);
    if (rnd.nextDouble() < 0.55 && tier1 >= 0) {
      pick = tier1;
    } else if (deepseekIdxs.isNotEmpty && rnd.nextDouble() < 0.30 / (0.30 + 0.15)) {
      pick = deepseekIdxs[rnd.nextInt(deepseekIdxs.length)];
    } else if (otherIdxs.isNotEmpty) {
      pick = otherIdxs[rnd.nextInt(otherIdxs.length)];
    } else if (tier1 >= 0) {
      pick = tier1;
    } else if (deepseekIdxs.isNotEmpty) {
      pick = deepseekIdxs[rnd.nextInt(deepseekIdxs.length)];
    } else {
      pick = rnd.nextInt(profiles.length);
    }
    autoSelectedProfileIdx = pick;
    return pick;
  }

  Future<String> sendChat(
    String text, {
    String? imageData,
    String? attachmentText,
    void Function(String chunk)? onReasoning,
    void Function(String chunk)? onDelta,
  }) async {
    final trimmed = text.trim();
    final attachContent = (attachmentText ?? '').trim();
    final hasAttachment = attachContent.isNotEmpty;
    if ((trimmed.isEmpty && !hasAttachment) || chatSending) return '';
    chatSending = true;
    // 开始新一轮发送：清零 abort 标志
    _chatAbortRequested = false;
    // 新一轮对话：清零 bash 命令熔断计数（兑现字段注释承诺）。
    // 否则被熔断的命令没有执行机会、永远不会成功复位，进程内永久封禁
    _cmdFailStreak.clear();
    notifyListeners();
    // Auto 模式：发送时按优先级挑选 profile，把 effectiveChatConfig 切到所选 profile（不持久化到 global apiConfig）
    if (useAutoModel) {
      final idx = pickAutoProfileIdx();
      if (idx >= 0 && idx < apiProfiles.length) {
        effectiveChatConfigOverride = apiProfiles[idx].config;
      }
    }
    final cfg = effectiveChatConfig;
    final hasImage = imageData != null && imageData.isNotEmpty;
    final hasVision = hasImage && cfg.vision;
    // 真正发送给 AI 的文本：附加文件内容拼接在用户输入之后
    var sendText = hasAttachment
        ? (trimmed.isEmpty
            ? '[用户附加了文件内容]\n$attachContent'
            : '$trimmed\n\n[用户附加的文件内容]\n$attachContent')
        : trimmed;
    // 若已选择技能，在 API 文本前加上技能名前缀，强化模型感知
    final skillPrefix = activeSkillName;
    if (skillPrefix.isNotEmpty && !sendText.startsWith('[$skillPrefix]')) {
      sendText = '[$skillPrefix] $sendText';
    }
    // 模型无图形能力时图片不发送（仅保留黑色占位），有图形能力时以多模态发送
    chatHistory.add(ChatMessage(
      role: 'user',
      content: trimmed.isEmpty && hasAttachment ? '[附加了文件]' : trimmed,
      imageData: hasVision ? imageData : null,
      imageDark: hasImage && !hasVision,
    ));
    _notifyChatUpdate();

    // 优先尝试 Agent（Function Calling）路径
    // 注意：_runAgentLoop 内部会创建占位消息并实时更新，成功后占位消息即为最终回复
    final agentResult = await _runAgentLoop(sendText, imageData: imageData);
    _releaseAutoOverride();
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
        (q.knowledge.isNotEmpty ? '核心知识点：${q.knowledge.join('、')}\n' : '') +
        buildChatContextPrompt();
    final history = chatHistory
        // 排除系统消息，但保留【早期对话摘要】（压缩工具写入的上下文，
        // 否则模型下一轮完全失忆、压缩对模型无效）
        .where((m) => m.role != 'system' || m.content.startsWith('【早期对话摘要】'))
        .map((m) {
          var content = (m.role == 'user' && m.imageData != null && m.imageData!.isNotEmpty)
              ? ApiService.buildContent(m.content, m.imageData)
              : m.content;
          // 最后一条用户消息若有附件，把文件内容拼到消息正文里
          if (m == chatHistory.last && hasAttachment) {
            content = '$content\n\n[用户附加的文件内容]\n$attachContent';
          }
          // 最后一条用户消息若已选择技能，追加技能名前缀强化模型感知
          if (content is String && m == chatHistory.last && skillPrefix.isNotEmpty && !content.startsWith('[$skillPrefix]')) {
            content = '[$skillPrefix] $content';
          }
          return {
            'role': m.role == 'ai' ? 'assistant' : 'user',
            'content': content,
          };
        })
        .toList();

    String reply = '';
    final showReasoning = chatShowReasoning;
    final thinkingParams = chatThinking
        ? ApiService.thinkingParams(effectiveChatConfig.model)
        : ApiService.noThinkingParams(effectiveChatConfig.model);
    if (chatStream && effectiveChatConfig.ready) {
      final msg = ChatMessage(role: 'ai', content: '', showReasoning: showReasoning, reasoning: '', modelLabel: cfg.model);
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
      chatHistory.add(ChatMessage(role: 'ai', content: reply, modelLabel: cfg.model));
      _notifyChatUpdate();
    }
    chatSending = false;
    notifyListeners();
    _notifyChatUpdate();
    return reply;
  }

  /// 用户在发送按钮上再次点击时调用：请求中止当前正在跑的 agent 循环。
  /// agent 循环每轮开头检查 `_chatAbortRequested`，被请求后立即退出并保留已有占位。
  void cancelChat() {
    if (!chatSending) return;
    _chatAbortRequested = true;
    notifyListeners();
  }

  /// sendChat 收尾：清理 Auto 模式临时覆写，避免下次 sendChat 仍沿用
  void _releaseAutoOverride() {
    if (_effectiveChatConfigOverride != null) {
      _effectiveChatConfigOverride = null;
    }
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
    // 在清空前保存一份会话快照（dsh-tool-session-query 用）
    if (chatHistory.isNotEmpty) {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final title = chatHistory.firstWhere((m) => m.role == 'user' && m.content.isNotEmpty, orElse: () => ChatMessage(role: 'user', content: '(空)')).content.replaceAll('\n', ' ').trim();
      chatSessions.insert(0, {
        'id': id,
        'title': title.length > 40 ? '${title.substring(0, 40)}...' : title,
        'createdAt': DateTime.now().toIso8601String(),
        'messageCount': chatHistory.length,
      });
      chatSessionMessages.insert(0, chatHistory.map((m) => {'role': m.role, 'content': m.content}).toList());
      if (chatSessions.length > _kMaxSessions) {
        chatSessions.removeRange(_kMaxSessions, chatSessions.length);
        chatSessionMessages.removeRange(_kMaxSessions, chatSessionMessages.length);
      }
      Storage.saveChatSessions(jsonEncode(chatSessions));
      Storage.saveChatSessionMessages(jsonEncode(chatSessionMessages));
    }
    chatHistory = [];
    notifyListeners();
    _notifyChatUpdate();
  }

  // ===== Agent 出题工具统一接管 =====
  // 历史版本曾在本类内用正则解析用户文本并直接调 `pickQuestionsFromBank` /
  // `generateQuestions` / `generateFullExam`，导致对话消息绕过 Agent Function Calling
  // 流程直接出题。现已删除：一切出题/题库抽取/套卷生成都必须由 Agent 调用
  // `generate_questions` / `submit_generated_questions` / `generate_full_exam` 工具。

  /// 出题成功后切换到答题页并重置作答内容
  void _gotoAnswerPage() {
    textAnswerValue = '';
    page = 1;
    notifyListeners();
  }

  // ===== Agent（Function Calling）=====

  /// 执行单个工具调用，返回结果给 AI。所有工具都在这里分发。
  /// 判断工具是否属于「危险操作」，默认权限（沙箱）下需要完全访问
  bool _isDangerousTool(String name, Map<String, dynamic> args) {
    // 直接操控电脑属于危险操作（打开文件/文件夹/应用/网址/执行命令）
    if (name == 'operate_computer') return true;
    // harness 风格的文件/命令工具都需要「完全访问」
    if (name == 'write_file' || name == 'edit_file' || name == 'bash') return true;
    // 修改设置（config_settings 的 set）需要完全访问
    if (name == 'config_settings' && (args['action'] as String?) == 'set') return true;
    return false;
  }

  /// harness 工具允许工作的根目录白名单。
  /// 若 workspacePath 已设置，则路径必须以该路径为前缀；否则使用默认 C:\Users 兜底。
  String _fsRoot() {
    final ws = workspacePath.trim();
    if (ws.isEmpty) return r'c:\users';
    return ws.replaceAll('/', '\\').toLowerCase();
  }

  bool _isPathUnderFsRoot(String path) {
    final p = path.replaceAll('/', '\\').toLowerCase();
    return p.startsWith('${_fsRoot()}\\') && !p.contains('..');
  }

  /// 路径不是绝对路径（无盘符）时，基于工作区根目录解析为绝对路径。
  /// 模型因此可以直接用 "src/game.ts" 这类相对路径，不必猜测完整路径，
  /// 从而避免反复"路径越界"试探浪费轮次。含 .. 的路径原样返回，由越界检查拦截。
  String _resolveFsPath(String raw) {
    final p = raw.trim();
    if (p.isEmpty || p.contains(':')) return p;
    final rel = p.replaceAll('/', r'\').replaceFirst(RegExp(r'^\\+'), '');
    return '${_fsRoot()}\\$rel';
  }

  /// 执行一个工具。[onProgress] 供长任务（如子 Agent 派发）实时上报进度事件。
  Future<ToolExecResult> executeTool(String name, Map<String, dynamic> args, {void Function(Map<String, dynamic> event)? onProgress}) async {
    try {
      // 记录工具调用（dsh-guard 用）：仅保留最近 20 条
      recentToolCalls.add({'name': name, 'args': args, 'at': DateTime.now().toIso8601String()});
      if (recentToolCalls.length > 20) recentToolCalls.removeRange(0, recentToolCalls.length - 20);
      // 联网搜索连接器关闭时，拦截 search_web
      if (name == 'search_web' && !searchEnabled) {
        return ToolExecResult(
          content: '{"ok":false,"reason":"search_disabled"}',
          ok: false,
          actionLabel: '联网搜索未开启，请在「连接器」中启用',
        );
      }
      // 权限控制：默认权限（沙箱）下拦截危险操作，需用户开启「完全访问」才放行
      if (!chatFullAccess && _isDangerousTool(name, args)) {
        return ToolExecResult(
          content: '{"ok":false,"reason":"permission_denied"}',
          ok: false,
          actionLabel: '需要「完全访问」权限才能执行该操作',
        );
      }
      if (name == 'spawn_subagent') {
        return await _toolSpawnSubagent(args, onProgress: onProgress);
      }
      switch (name) {
        case 'generate_questions':
          return await _toolGenerateQuestions(args);
        case 'generate_full_exam':
          return await _toolGenerateFullExam(args);
        case 'submit_generated_questions':
          return _toolSubmitGeneratedQuestions(args);
        case 'lookup_word':
          return _toolLookupWord(args);
        case 'analyze_words':
          return await _toolAnalyzeWords(args);
        case 'get_current_question':
          return _toolGetCurrentQuestion();
        case 'next_question':
          return await _toolNextQuestion();
        case 'toggle_favorite':
          return _toolToggleFavorite();
        case 'get_progress':
          return _toolGetProgress();
        case 'goto_page':
          return _toolGotoPage(args);
        case 'get_wrong_questions':
          return _toolGetWrongQuestions();
        case 'get_favorites':
          return _toolGetFavorites();
        case 'start_dictation':
          return _toolStartDictation(args);
        case 'sync_maimemo':
          return await _toolSyncMaimemo();
        case 'get_study_report':
          return _toolGetStudyReport();
        case 'config_settings':
          return _toolConfigSettings(args);
        case 'search_web':
          return await _toolSearchWeb(args);
        case 'backup_data':
          return await _toolBackupData();
        case 'operate_computer':
          return _toolOperateComputer(args);
        // ========== harness 工具：本地文件 & shell ==========
        case 'read_file':
          return await _toolReadFile(args);
        case 'write_file':
          return await _toolWriteFile(args);
        case 'edit_file':
          return await _toolEditFile(args);
        case 'list_dir':
          return await _toolListDir(args);
        case 'bash':
          return await _toolBash(args);
        case 'str_replace_editor':
          return await _toolStrReplaceEditor(args);
        case 'run_code':
          return await _toolRunCode(args);
        // ========== dsh 移植工具 ==========
        case 'todo':
          return await _toolTodo(args);
        case 'skill':
          return await _toolSkill(args);
        case 'web_fetch':
          return await _toolWebFetch(args);
        case 'session_query':
          return await _toolSessionQuery(args);
        case 'list_mcp_tools':
          return await _toolListMcpTools();
        case 'call_mcp_tool':
          return await _toolCallMcpTool(args);
        case 'ask_user_question':
          return await _toolAskUserQuestion(args);
        case 'compact_conversation':
          return await _toolCompactConversation(args);
        case 'list_user_skills':
          return await _toolListUserSkills();
        case 'load_skill':
          return await _toolLoadSkill(args);
        case 'submit_plan':
          return await _toolSubmitPlan(args);
        case 'run_background_job':
          return await _toolRunBackgroundJob(args);
        case 'job_output':
          return await _toolJobOutput(args);
        case 'job_kill':
          return await _toolJobKill(args);
        case 'check_repeat':
          return await _toolCheckRepeat();
        default:
          if (name.startsWith('mcp__')) {
          final toolName = name.substring(5);
          // 通过 toolName 反查 server
          for (final client in mcpRegistry.clients) {
            for (final t in client.tools) {
              if (t.name == toolName || t.name.replaceAll(' ', '_') == toolName) {
                return await _toolCallMcpTool({
                  'server_name': client.name,
                  'tool_name': t.name,
                  'arguments': args,
                });
              }
            }
          }
          return ToolExecResult(content: '{"ok":false,"reason":"mcp_tool_not_found"}', ok: false, actionLabel: '未找到 MCP 工具：$toolName');
        }
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
    if (count > 50) count = 50;
    final useBank = (args['useBank'] as bool?) ?? true;
    final wordCount = (args['wordCount'] as num?)?.toInt() ?? 0; // 0 表示使用现有设置
    final direction = (args['direction'] as String?) ?? '';
    final mode = (args['mode'] as String?) ?? '';
    final customReq = (args['customReq'] as String?) ?? '';

    if (generating) {
      return const ToolExecResult(content: '正在生成中，请稍候', ok: false);
    }

    // 0) 综合模拟全卷：直接走 generateFullExam
    if (type == 'mixed') {
      if (!apiConfig.ready) {
        return const ToolExecResult(content: '{"ok":false,"reason":"api_not_configured"}', ok: false);
      }
      if (examGeneratingBatch) {
        return const ToolExecResult(content: '{"ok":false,"reason":"already_generating"}', ok: false);
      }
      selectedLevel = (level == 'maimemo' || level == 'medium') ? 'zsb' : level;
      if (wordCount > 0) lastWordCount = wordCount.clamp(30, 300);
      if (customReq.isNotEmpty) lastCustomReq = customReq;
      if (mode.isNotEmpty) analysisMode = mode;
      examGeneratingBatch = true;
      try {
        final ok = await generateFullExam(customReq: lastCustomReq);
        return ToolExecResult(
          content: '{"ok":$ok,"type":"mixed","level":"$level"}',
          ok: ok,
          actionLabel: ok ? '已生成综合模拟全卷（76题/7题型/120分钟）' : '生成全卷失败',
        );
      } finally {
        examGeneratingBatch = false;
      }
    }

    // 1) 墨墨词库模式：从墨墨今日已学单词随机抽取 + AI 出题
    if (level == 'maimemo') {
      if (maimemoWordbook.isEmpty) {
        return const ToolExecResult(
            content: '{"ok":false,"reason":"maimemo_empty"}', ok: false,
            actionLabel: '墨墨词库为空，请先在"更多功能 → 墨墨词库"中同步');
      }
      if (!apiConfig.ready) {
        return const ToolExecResult(content: '{"ok":false,"reason":"api_not_configured"}', ok: false);
      }
      final refWords = maimemoRefWords();
      selectedType = type;
      selectedLevel = 'maimemo';
      if (wordCount > 0) lastWordCount = wordCount.clamp(30, 300);
      if (customReq.isNotEmpty) lastCustomReq = customReq;
      if (mode.isNotEmpty) analysisMode = mode;
      if (direction == 'zh2en' || direction == 'en2zh') {
        setDirection(direction);
      }
      final actualCount = count.clamp(1, refWords.isEmpty ? 1 : (refWords.length > 50 ? 50 : refWords.length));
      final ok = await generateQuestions(
        count: actualCount,
        customReq: lastCustomReq,
        wordCount: lastWordCount,
        maimemoWords: refWords,
      );
      if (ok) {
        _gotoAnswerPage();
        return ToolExecResult(
          content: '{"ok":true,"count":${generatedQuestions.length},"type":"$type","level":"maimemo","source":"ai"}',
          ok: true,
          actionLabel: '已基于墨墨词库（${refWords.length} 个参考词）生成 ${generatedQuestions.length} 道${qTypeName(qTypeFrom(type))}',
        );
      }
      return const ToolExecResult(content: '{"ok":false,"reason":"generate_failed"}', ok: false);
    }

    // 2) 翻译题优先走题库（除非用户明确说不要题库）
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
        if (wordCount > 0) lastWordCount = wordCount.clamp(30, 300);
        if (customReq.isNotEmpty) lastCustomReq = customReq;
        if (mode.isNotEmpty) analysisMode = mode;
        if (direction == 'zh2en' || direction == 'en2zh') {
          setDirection(direction);
        }
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
    if (wordCount > 0) lastWordCount = wordCount.clamp(30, 300);
    if (customReq.isNotEmpty) lastCustomReq = customReq;
    if (mode.isNotEmpty) analysisMode = mode;
    if (direction == 'zh2en' || direction == 'en2zh') {
      setDirection(direction);
    }
    final ok = await generateQuestions(
      count: count,
      customReq: lastCustomReq,
      wordCount: lastWordCount,
    );
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

  /// 将 AI 直接提交的题目内容（可能是 list / JSON 字符串 / 对象）自愈并归一化为 Question 列表。
  /// 针对低参数模型输出的 malformed JSON，尽量提取可用的题目对象并纠正结构。
  List<Question> _healSubmittedQuestions(dynamic raw, String defaultType, String defaultLevel) {
    List<Map<String, dynamic>> items = [];
    // 1) 字符串：可能是被模型当成字符串包住的 JSON
    if (raw is String) {
      final s = raw.trim();
      if (s.isNotEmpty) {
        final arr = ApiService.extractJsonArray(s);
        if (arr != null) {
          items = arr;
        } else {
          final obj = ApiService.extractJsonObject(s);
          if (obj != null) {
            final nested = obj['questions'] ?? obj['data'] ?? obj['items'];
            if (nested is List) {
              items = nested.whereType<Map<String, dynamic>>().toList();
            } else if (nested is String) {
              items = ApiService.extractJsonArray(nested) ?? [];
            } else {
              items = [obj];
            }
          }
        }
      }
    } else if (raw is Map) {
      final nested = raw['questions'] ?? raw['data'] ?? raw['items'];
      if (nested is List) {
        items = nested.whereType<Map<String, dynamic>>().toList();
      } else if (nested is String) {
        items = ApiService.extractJsonArray(nested) ?? [];
      } else {
        items = [Map<String, dynamic>.from(raw)];
      }
    } else if (raw is List) {
      items = raw.whereType<Map<String, dynamic>>().toList();
    }

    final out = <Question>[];
    for (final item in items) {
      // 每道题可自带 type，缺省用外层 type
      final type = qTypeFrom((item['type'] ?? defaultType).toString());
      final level = (item['level'] as String?)?.isNotEmpty == true ? (item['level'] as String) : defaultLevel;
      try {
        final q = normalizeGeneratedQuestion(item, type, level);
        // 判定是否有可用内容（避免全部字段为空的废题）
        final hasContent = q.text.isNotEmpty ||
            q.chinese.isNotEmpty ||
            q.english.isNotEmpty ||
            q.passage.isNotEmpty ||
            q.question.isNotEmpty ||
            (q.type == QType.choice && q.hasOptions) ||
            (q.type == QType.reading && q.hasReading);
        if (hasContent) out.add(q);
      } catch (_) {
        // 跳过无法解析的单题，尽量保留其余题目
      }
    }
    return out;
  }

  Future<ToolExecResult> _toolSubmitGeneratedQuestions(Map<String, dynamic> args) async {
    final defaultType = (args['type'] as String?) ?? 'translation';
    final defaultLevel = (args['level'] as String?) ?? 'zsb';
    final direction = (args['direction'] as String?) ?? '';
    final raw = args['questions'];
    if (raw == null) {
      return const ToolExecResult(content: '{"ok":false,"reason":"empty_questions"}', ok: false);
    }
    final healed = _healSubmittedQuestions(raw, defaultType, defaultLevel);
    if (healed.isEmpty) {
      return const ToolExecResult(
        content: '{"ok":false,"reason":"invalid_questions"}',
        ok: false,
        actionLabel: '题目内容无法解析，请检查输出格式',
      );
    }
    selectedType = defaultType;
    selectedLevel = defaultLevel;
    if (direction == 'zh2en' || direction == 'en2zh') {
      setDirection(direction);
    }
    generatedQuestions = healed;
    generatedQuestionIdx = 0;
    lastQuestionSource = 'ai';
    lastCustomReq = '';
    lastQuestionCount = healed.length;
    loadGeneratedQuestion();
    _gotoAnswerPage();
    notifyListeners();
    return ToolExecResult(
      content: '{"ok":true,"count":${healed.length},"type":"$defaultType","level":"$defaultLevel","source":"ai_submit"}',
      ok: true,
      actionLabel: '已生成 ${healed.length} 道${levelName(defaultLevel)}${qTypeName(qTypeFrom(defaultType))}，已放入答题区',
    );
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

  Future<ToolExecResult> _toolNextQuestion() async {
    if (generatedQuestions.length <= 1) {
      return const ToolExecResult(content: '{"ok":false,"reason":"no_more_questions"}', ok: false);
    }
    // nextQuestion 在 AI 来源时会重新生成题目（耗时网络请求），
    // 必须 await 后再读索引，否则返回的是切换前的旧索引
    await nextQuestion();
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

  /// 页面导航：page 枚举 → 页面索引
  static const Map<String, int> _pageIndexByKey = {
    'learn': 0, 'answer': 1, 'report': 2, 'search': 3,
    'bank': 4, 'wrong': 5, 'favorite': 6, 'dictation': 8,
    'grammar': 12, 'maimemo': 18,
  };

  ToolExecResult _toolGotoPage(Map<String, dynamic> args) {
    final key = (args['page'] as String?) ?? '';
    final idx = _pageIndexByKey[key];
    if (idx == null) {
      return const ToolExecResult(content: '{"ok":false,"reason":"unknown_page"}', ok: false);
    }
    setPage(idx);
    return ToolExecResult(
      content: '{"ok":true,"page":"$key","index":$idx}',
      ok: true,
      actionLabel: '已跳转到「$key」',
    );
  }

  ToolExecResult _toolGetWrongQuestions() {
    final total = wrongQuestions.fold<int>(0, (s, w) => s + w.wrongCount);
    final brief = wrongQuestions.take(8).map((w) => w.question.text).toList();
    return ToolExecResult(
      content: '{"ok":true,"count":${wrongQuestions.length},"totalWrong":$total,"samples":${jsonEncode(brief)}}',
      ok: true,
      actionLabel: '读取错题本（${wrongQuestions.length} 道）',
    );
  }

  ToolExecResult _toolGetFavorites() {
    final brief = favorites.take(8).map((f) => f.text).toList();
    return ToolExecResult(
      content: '{"ok":true,"count":${favorites.length},"samples":${jsonEncode(brief)}}',
      ok: true,
      actionLabel: '读取生词本（${favorites.length} 个）',
    );
  }

  ToolExecResult _toolStartDictation(Map<String, dynamic> args) {
    final mode = (args['mode'] as String?) == 'en2zh' ? 'en2zh' : 'zh2en';
    final count = ((args['count'] as num?)?.toInt() ?? 10).clamp(1, 50);
    final source = (args['source'] as String?) ?? 'zsb';
    // 校验词库非空
    bool hasWords() {
      if (source == 'custom') return customWordbook.isNotEmpty;
      if (source == 'maimemo') return maimemoWordbook.isNotEmpty;
      return DictService.zsbWords().isNotEmpty;
    }
    if (!hasWords()) {
      return ToolExecResult(content: '{"ok":false,"reason":"empty_wordbook"}', ok: false);
    }
    startDictation(mode, count, source: source);
    setPage(8);
    return ToolExecResult(
      content: '{"ok":true,"mode":"$mode","count":$count,"source":"$source"}',
      ok: true,
      actionLabel: '已开始 ${count} 个单词的默写',
    );
  }

  Future<ToolExecResult> _toolSyncMaimemo() async {
    if (maimemoToken.trim().isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"token_not_configured"}', ok: false);
    }
    if (maimemoSyncing) {
      return const ToolExecResult(content: '{"ok":false,"reason":"syncing"}', ok: false);
    }
    try {
      final count = await syncMaimemoWords();
      return ToolExecResult(
        content: '{"ok":true,"synced":$count,"total":${maimemoWordbook.length}}',
        ok: true,
        actionLabel: '已同步墨墨词库（共 ${maimemoWordbook.length} 个单词）',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"sync_failed"}', ok: false);
    }
  }

  ToolExecResult _toolGetStudyReport() {
    final total = studyRecords.length;
    final correct = studyRecords.where((r) => !r.isWrong).length;
    final rate = total == 0 ? 0 : (correct / total * 100).round();
    return ToolExecResult(
      content: '{"ok":true,"records":$total,"correct":$correct,"accuracy":$rate,"wrong":${total - correct}}',
      ok: true,
      actionLabel: '读取学习报告（正确率 $rate%）',
    );
  }

  /// 读取或修改应用设置。action=get 返回全部设置；action=set 修改指定项。
  ToolExecResult _toolConfigSettings(Map<String, dynamic> args) {
    final action = (args['action'] as String?) ?? 'get';
    if (action == 'get') {
      return ToolExecResult(
        content: jsonEncode({
          'ok': true,
          'settings': {
            'model': apiConfig.model,
            'temperature': apiConfig.temperature.isEmpty ? 'default' : apiConfig.temperature,
            'vision': apiConfig.vision,
            'fullUrl': apiConfig.fullUrl,
            'apiUrl': apiConfig.url,
            'apiKeyConfigured': apiConfig.key.isNotEmpty,
            'uiMode': uiMode.isEmpty ? 'desktop' : uiMode,
            'theme': darkMode ? 'dark' : uiStyle,
            'navIndicator': navIndicator,
            'fullscreen': fullscreen,
            'powerSaving': powerSavingMode,
            'highPerformance': highPerformanceMode,
            'maimemoTokenConfigured': maimemoToken.isNotEmpty,
          },
        }),
        ok: true,
        actionLabel: '读取当前设置',
      );
    }

    final key = (args['key'] as String?) ?? '';
    final value = (args['value'] as String?) ?? '';
    bool ok = true;
    switch (key) {
      case 'model':
        final c = ApiConfig(
          url: apiConfig.url, key: apiConfig.key, model: value.isEmpty ? apiConfig.model : value,
          temperature: apiConfig.temperature, vision: apiConfig.vision, fullUrl: apiConfig.fullUrl,
        );
        saveApiConfig(c);
        break;
      case 'temperature':
        final t = const ['default', '0', '0.3', '0.7', '1.0'].contains(value) ? value : apiConfig.temperature;
        final c = ApiConfig(
          url: apiConfig.url, key: apiConfig.key, model: apiConfig.model,
          temperature: t, vision: apiConfig.vision, fullUrl: apiConfig.fullUrl,
        );
        saveApiConfig(c);
        break;
      case 'vision':
        if (value == 'true' || value == 'false') {
          final c = ApiConfig(
            url: apiConfig.url, key: apiConfig.key, model: apiConfig.model,
            temperature: apiConfig.temperature, vision: value == 'true', fullUrl: apiConfig.fullUrl,
          );
          saveApiConfig(c);
        } else { ok = false; }
        break;
      case 'fullUrl':
        if (value == 'true' || value == 'false') {
          final c = ApiConfig(
            url: apiConfig.url, key: apiConfig.key, model: apiConfig.model,
            temperature: apiConfig.temperature, vision: apiConfig.vision, fullUrl: value == 'true',
          );
          saveApiConfig(c);
        } else { ok = false; }
        break;
      case 'uiMode':
        setUiMode(value == 'mobile' ? 'mobile' : 'desktop');
        break;
      case 'theme':
        if (const ['classic', 'glass', 'dark'].contains(value)) {
          setThemeStyle(value);
        } else {
          ok = false;
        }
        break;
      case 'navIndicator':
        setNavIndicator(value == 'pill' ? 'pill' : 'underline');
        break;
      case 'fullscreen':
        if (value == 'true' || value == 'false') {
          toggleFullscreen(value == 'true');
        } else {
          ok = false;
        }
        break;
      case 'powerSaving':
        if (value == 'true' || value == 'false') {
          togglePowerSavingMode(value == 'true');
        } else {
          ok = false;
        }
        break;
      case 'highPerformance':
        if (value == 'true' || value == 'false') {
          toggleHighPerformanceMode(value == 'true');
        } else {
          ok = false;
        }
        break;
      case 'maimemoToken':
        setMaimemoToken(value);
        break;
      default:
        ok = false;
    }
    if (!ok) {
      return ToolExecResult(content: '{"ok":false,"reason":"invalid_key_or_value"}', ok: false);
    }
    return ToolExecResult(
      content: '{"ok":true,"key":"$key","value":"$value"}',
      ok: true,
      actionLabel: '已设置「$key」',
    );
  }

  /// 联网搜索：调用百度千帆 AI 搜索组件，返回 answer + references。
  Future<ToolExecResult> _toolSearchWeb(Map<String, dynamic> args) async {
    if (searchKey.trim().isEmpty) {
      return ToolExecResult(
        content: '{"ok":false,"reason":"请先在设置中配置联网搜索服务的 API Key"}',
        ok: false,
      );
    }
    final query = (args['query'] as String? ?? '').trim();
    if (query.isEmpty) {
      return ToolExecResult(content: '{"ok":false,"reason":"搜索关键词为空"}', ok: false);
    }
    try {
      final result = await ApiService.searchWeb(url: searchUrl, key: searchKey, query: query);
      return ToolExecResult(
        content: jsonEncode({'ok': true, ...result}),
        ok: true,
        actionLabel: '已联网搜索"$query"',
      );
    } catch (e) {
      return ToolExecResult(
        content: '{"ok":false,"reason":"${e.toString()}"}',
        ok: false,
        actionLabel: '联网搜索失败',
      );
    }
  }

  /// 备份数据：将全部数据（API 配置、收藏、错题、学习记录、生词本等）导出到电脑下载/手机默认文件夹。
  Future<ToolExecResult> _toolBackupData() async {
    try {
      final path = await backupData();
      return ToolExecResult(
        content: '{"ok":true,"path":"$path","tip":"备份已保存到 $path"}',
        ok: true,
        actionLabel: '已完成数据备份',
      );
    } catch (e) {
      return ToolExecResult(
        content: '{"ok":false,"reason":"${e.toString()}"}',
        ok: false,
        actionLabel: '备份失败',
      );
    }
  }

  // ============== harness 工具实现 ==============

  /// 拒绝 harness 工具：路径不在当前工作区内或包含 .. 试图跳出根目录
  ToolExecResult _fsPermissionDenied(String reason) {
    final root = _fsRoot();
    return ToolExecResult(
      content: '{"ok":false,"reason":"$reason"}',
      ok: false,
      actionLabel: '路径越界：仅能访问 $root 下的文件',
    );
  }

  Future<ToolExecResult> _toolReadFile(Map<String, dynamic> args) async {
    final raw = _resolveFsPath((args['path'] as String?)?.trim() ?? '');
    if (raw.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_path"}', ok: false, actionLabel: '缺少文件路径');
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    try {
      final f = File(raw);
      if (!await f.exists()) return ToolExecResult(content: '{"ok":false,"reason":"not_found"}', ok: false, actionLabel: '文件不存在：$raw');
      final size = await f.length();
      const cap = 256 * 1024; // 256 KB 上限
      final bytes = await f.openRead(0, cap > size ? size : cap).fold<List<int>>(<int>[], (acc, c) => acc..addAll(c));
      final text = utf8.decode(bytes, allowMalformed: true);
      final truncated = size > cap;
      final body = jsonEncode({
        'ok': true,
        'path': raw,
        'size': size,
        'truncated': truncated,
        'content': text,
      });
      return ToolExecResult(
        content: body,
        ok: true,
        actionLabel: truncated ? '已读取 ${_humanSize(size)} (已截断到 256KB)' : '已读取 ${_humanSize(size)}',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"read_failed: $e"}', ok: false);
    }
  }

  Future<ToolExecResult> _toolWriteFile(Map<String, dynamic> args) async {
    final raw = _resolveFsPath((args['path'] as String?)?.trim() ?? '');
    final content = (args['content'] as String?) ?? '';
    if (raw.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_path"}', ok: false, actionLabel: '缺少文件路径');
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    try {
      final f = File(raw);
      if (!await f.parent.exists()) {
        await f.parent.create(recursive: true);
      }
      await f.writeAsString(content, flush: true);
      final bytes = utf8.encode(content).length;
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'path': raw, 'bytes': bytes}),
        ok: true,
        actionLabel: '已写入 ${_humanSize(bytes)} 到 $raw',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"write_failed: $e"}', ok: false);
    }
  }

  Future<ToolExecResult> _toolEditFile(Map<String, dynamic> args) async {
    final raw = _resolveFsPath((args['path'] as String?)?.trim() ?? '');
    final oldText = (args['old_text'] as String?) ?? '';
    final newText = (args['new_text'] as String?) ?? '';
    if (raw.isEmpty || oldText.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"missing_args"}', ok: false, actionLabel: '需要 path 和 old_text');
    }
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    try {
      final f = File(raw);
      if (!await f.exists()) return ToolExecResult(content: '{"ok":false,"reason":"not_found"}', ok: false, actionLabel: '文件不存在：$raw');
      final text = await f.readAsString();
      final idx = text.indexOf(oldText);
      if (idx < 0) {
        return ToolExecResult(content: '{"ok":false,"reason":"old_text_not_found"}', ok: false, actionLabel: '未找到要替换的旧文本');
      }
      final replaced = text.substring(0, idx) + newText + text.substring(idx + oldText.length);
      await f.writeAsString(replaced, flush: true);
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'path': raw, 'offset': idx, 'old_len': oldText.length, 'new_len': newText.length}),
        ok: true,
        actionLabel: '已在 ${_basename(raw)} 替换 $idx 开始处的 ${oldText.length} 字符',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"edit_failed: $e"}', ok: false);
    }
  }

  // ============== str_replace_editor（仿 dsh-tool-str-replace-editor） ==============

  /// 计算字符串在某文本中的所有偏移
  List<int> _allMatchOffsets(String content, String search) {
    final offsets = <int>[];
    var offset = 0;
    while (true) {
      final idx = content.indexOf(search, offset);
      if (idx < 0) break;
      offsets.add(idx);
      offset = idx + search.length;
    }
    return offsets;
  }

  /// 行号定位：给定偏移列表返回每处所在行号（1 起）
  List<int> _lineNumbersAt(String content, List<int> offsets) {
    var line = 1;
    var cursor = 0;
    return offsets.map((off) {
      while (cursor < off) {
        if (content[cursor] == '\n') line += 1;
        cursor += 1;
      }
      return line;
    }).toList();
  }

  /// 取文件某行区间的内容（view_range：[start, end]，end=-1 表示到文件末尾；行号 1 起）
  String _sliceByLines(String content, int start, int end) {
    final lines = content.split('\n');
    if (start < 1) start = 1;
    final from = start - 1;
    final to = (end == -1 || end > lines.length) ? lines.length : end;
    if (from >= lines.length) return '';
    return lines.sublist(from, to).join('\n');
  }

  /// 给文本加行号（cat -n 风格，行号占 6 位右对齐 + tab）
  String _numberLines(String text) {
    final lines = text.split('\n');
    final width = lines.length.toString().length.clamp(2, 6);
    final buf = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      final n = (i + 1).toString().padLeft(width);
      buf.writeln('$n\t${lines[i]}');
    }
    return buf.toString();
  }

  /// 简易 diff：返回统一 diff 字符串（- 删除 / + 新增 / 上下文 3 行）
  String _simpleDiff(String oldText, String newText) {
    final oldLines = oldText.split('\n');
    final newLines = newText.split('\n');
    final out = StringBuffer();
    var i = 0, j = 0;
    while (i < oldLines.length || j < newLines.length) {
      if (i < oldLines.length && j < newLines.length && oldLines[i] == newLines[j]) {
        out.writeln(' ${oldLines[i]}');
        i++;
        j++;
      } else {
        var matched = false;
        // 尝试在 old 中找 newLines[j]
        for (var k = i + 1; k < oldLines.length && k <= i + 8; k++) {
          if (oldLines[k] == newLines[j]) {
            for (var d = i; d < k; d++) {
              out.writeln('-${oldLines[d]}');
            }
            i = k;
            matched = true;
            break;
          }
        }
        if (!matched) {
          // 尝试在 new 中找 oldLines[i]
          var found = false;
          for (var k = j + 1; k < newLines.length && k <= j + 8; k++) {
            if (newLines[k] == oldLines[i]) {
              for (var d = j; d < k; d++) {
                out.writeln('+${newLines[d]}');
              }
              j = k;
              found = true;
              break;
            }
          }
          if (!found) {
            if (i < oldLines.length) out.writeln('-${oldLines[i]}');
            if (j < newLines.length) out.writeln('+${newLines[j]}');
            i++;
            j++;
          }
        }
      }
    }
    return out.toString();
  }

  /// 查看文件/目录（view 命令：文件带 cat -n 行号，目录列 2 层）
  Future<ToolExecResult> _editorView(String raw, List<int>? range) async {
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    final f = File(raw);
    final d = Directory(raw);
    try {
      if (await f.exists()) {
        final text = await f.readAsString();
        String shown = text;
        if (range != null && range.length == 2) {
          shown = _sliceByLines(text, range[0], range[1]);
          final endNote = (range[1] == -1 || range[1] > text.split('\n').length) ? '（到文件末尾）' : '';
          return ToolExecResult(
            content: jsonEncode({
              'ok': true,
              'path': raw,
              'command': 'view',
              'range': range,
              'range_note': '显示第 ${range[0]} 行至第 ${range[1]} 行$endNote',
              'content': _numberLines(shown),
            }),
            ok: true,
            actionLabel: '查看 ${_basename(raw)} 第 ${range[0]}-${range[1]} 行',
          );
        }
        return ToolExecResult(
          content: jsonEncode({'ok': true, 'path': raw, 'command': 'view', 'content': _numberLines(shown)}),
          ok: true,
          actionLabel: '已查看 ${_basename(raw)}（${shown.split('\n').length} 行）',
        );
      }
      if (await d.exists()) {
        // 列出非隐藏项，最多 2 层
        final buf = StringBuffer();
        var count = 0;
        await for (final ent in d.list()) {
          final name = _basename(ent.path);
          if (name.startsWith('.')) continue;
          if (ent is Directory) {
            buf.writeln('$name/');
            count++;
            if (count > 200) break;
            var sub = 0;
            await for (final subEnt in ent.list()) {
              final subName = _basename(subEnt.path);
              if (subName.startsWith('.')) continue;
              buf.writeln('  $subName${subEnt is Directory ? '/' : ''}');
              sub++;
              if (sub > 100) {
                buf.writeln('  ...（更多子项未显示）');
                break;
              }
            }
          } else {
            buf.writeln(name);
          }
          count++;
          if (count > 500) {
            buf.writeln('...（更多条目未显示）');
            break;
          }
        }
        return ToolExecResult(
          content: jsonEncode({'ok': true, 'path': raw, 'command': 'view', 'is_dir': true, 'content': buf.toString()}),
          ok: true,
          actionLabel: '已列出目录 ${_basename(raw)}',
        );
      }
      return ToolExecResult(content: '{"ok":false,"reason":"not_found"}', ok: false, actionLabel: '路径不存在：$raw');
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"view_failed: $e"}', ok: false);
    }
  }

  /// create 命令：新建文件（已存在则拒绝）
  Future<ToolExecResult> _editorCreate(String raw, String fileText) async {
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    try {
      final f = File(raw);
      if (await f.exists()) {
        return ToolExecResult(
          content: '{"ok":false,"reason":"file_exists","hint":"目标文件已存在，create 命令无法覆盖。请改用 str_replace 修改内容。"}',
          ok: false,
          actionLabel: '文件已存在，无法 create',
        );
      }
      await f.parent.create(recursive: true);
      await f.writeAsString(fileText, flush: true);
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'path': raw, 'command': 'create', 'bytes': utf8.encode(fileText).length}),
        ok: true,
        actionLabel: '已创建 ${_basename(raw)}',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"create_failed: $e"}', ok: false);
    }
  }

  /// str_replace 命令：old_str 必须唯一匹配，否则拒绝
  Future<ToolExecResult> _editorStrReplace(String raw, String oldStr, String newStr) async {
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    try {
      final f = File(raw);
      if (!await f.exists()) return ToolExecResult(content: '{"ok":false,"reason":"not_found"}', ok: false, actionLabel: '文件不存在：$raw');
      final text = await f.readAsString();
      final offsets = _allMatchOffsets(text, oldStr);
      if (offsets.isEmpty) {
        return ToolExecResult(
          content: jsonEncode({
            'ok': false,
            'reason': 'old_str_not_found',
            'hint': 'old_str 未在文件中找到。注意空白字符！建议先 view 查看实际内容。',
          }),
          ok: false,
          actionLabel: '未找到 old_str',
        );
      }
      if (offsets.length > 1) {
        final lineNos = _lineNumbersAt(text, offsets);
        return ToolExecResult(
          content: jsonEncode({
            'ok': false,
            'reason': 'old_str_not_unique',
            'matches': offsets.length,
            'lines': lineNos,
            'hint': 'old_str 在文件中出现 ${offsets.length} 次（第 ${lineNos.join("、")} 行），不唯一。请带上更多上下文使 old_str 唯一匹配。',
          }),
          ok: false,
          actionLabel: 'old_str 不唯一（${offsets.length} 处匹配）',
        );
      }
      final idx = offsets.first;
      final replaced = text.substring(0, idx) + newStr + text.substring(idx + oldStr.length);
      await f.writeAsString(replaced, flush: true);
      final lineNo = _lineNumbersAt(text, [idx]).first;
      return ToolExecResult(
        content: jsonEncode({
          'ok': true,
          'path': raw,
          'command': 'str_replace',
          'line': lineNo,
          'diff': _simpleDiff(oldStr, newStr),
        }),
        ok: true,
        actionLabel: '已替换 ${_basename(raw)} 第 $lineNo 行附近文本',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"replace_failed: $e"}', ok: false);
    }
  }

  /// insert 命令：在 insert_line 之后插入 new_str
  Future<ToolExecResult> _editorInsert(String raw, int insertLine, String newStr) async {
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    try {
      final f = File(raw);
      if (!await f.exists()) return ToolExecResult(content: '{"ok":false,"reason":"not_found"}', ok: false, actionLabel: '文件不存在：$raw');
      final text = await f.readAsString();
      final lines = text.split('\n');
      final insertIdx = insertLine.clamp(0, lines.length);
      lines.insert(insertIdx, newStr);
      await f.writeAsString(lines.join('\n'), flush: true);
      return ToolExecResult(
        content: jsonEncode({
          'ok': true,
          'path': raw,
          'command': 'insert',
          'insert_after_line': insertLine,
          'inserted': newStr,
        }),
        ok: true,
        actionLabel: '已在 ${_basename(raw)} 第 $insertLine 行后插入内容',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"insert_failed: $e"}', ok: false);
    }
  }

  /// str_replace_editor 工具总入口
  Future<ToolExecResult> _toolStrReplaceEditor(Map<String, dynamic> args) async {
    final cmd = (args['command'] as String?)?.trim() ?? '';
    final raw = _resolveFsPath((args['path'] as String?)?.trim() ?? '');
    if (raw.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_path"}', ok: false, actionLabel: '缺少 path');
    switch (cmd) {
      case 'view':
        final rangeRaw = args['view_range'];
        List<int>? range;
        if (rangeRaw is List && rangeRaw.length == 2) {
          range = [((rangeRaw[0] as num?) ?? 1).toInt(), ((rangeRaw[1] as num?) ?? -1).toInt()];
        }
        return _editorView(raw, range);
      case 'create':
        final fileText = (args['file_text'] as String?) ?? '';
        if (fileText.isEmpty) {
          return const ToolExecResult(content: '{"ok":false,"reason":"missing_file_text"}', ok: false, actionLabel: 'create 需要 file_text');
        }
        return _editorCreate(raw, fileText);
      case 'str_replace':
        final oldStr = (args['old_str'] as String?) ?? '';
        final newStr = (args['new_str'] as String?) ?? '';
        if (oldStr.isEmpty) {
          return const ToolExecResult(content: '{"ok":false,"reason":"missing_old_str"}', ok: false, actionLabel: 'str_replace 需要 old_str');
        }
        return _editorStrReplace(raw, oldStr, newStr);
      case 'insert':
        final insertLine = (args['insert_line'] as num?)?.toInt() ?? 1;
        final newStr = (args['new_str'] as String?) ?? '';
        if (newStr.isEmpty) {
          return const ToolExecResult(content: '{"ok":false,"reason":"missing_new_str"}', ok: false, actionLabel: 'insert 需要 new_str');
        }
        return _editorInsert(raw, insertLine, newStr);
      default:
        return ToolExecResult(
          content: '{"ok":false,"reason":"unknown_command","hint":"允许的命令：view / create / str_replace / insert"}',
          ok: false,
          actionLabel: '未知命令：$cmd',
        );
    }
  }

  Future<ToolExecResult> _toolListDir(Map<String, dynamic> args) async {
    final raw = _resolveFsPath((args['path'] as String?)?.trim() ?? '');
    if (raw.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_path"}', ok: false, actionLabel: '缺少目录路径');
    if (!_isPathUnderFsRoot(raw)) return _fsPermissionDenied('path outside fs root');
    try {
      final dir = Directory(raw);
      if (!await dir.exists()) return ToolExecResult(content: '{"ok":false,"reason":"not_found"}', ok: false, actionLabel: '目录不存在：$raw');
      final entries = <Map<String, dynamic>>[];
      await for (final ent in dir.list()) {
        final stat = await ent.stat();
        entries.add({
          'name': _basename(ent.path),
          'type': ent is Directory ? 'dir' : 'file',
          'size': ent is Directory ? null : stat.size,
          'modified': stat.modified.toIso8601String(),
        });
        if (entries.length >= 200) break; // 限制返回数量
      }
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'path': raw, 'count': entries.length, 'entries': entries}),
        ok: true,
        actionLabel: '已列出 $raw 下的 ${entries.length} 项',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"list_failed: $e"}', ok: false);
    }
  }

  Future<ToolExecResult> _toolBash(Map<String, dynamic> args) async {
    final cmd = (args['command'] as String?)?.trim() ?? '';
    if (cmd.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_command"}', ok: false, actionLabel: '缺少命令');
    // R13: 同一条命令连续失败 2 次后直接熔断，避免重复执行烧光工具轮次
    final streak = _cmdFailStreak[cmd] ?? 0;
    if (streak >= 2) {
      return ToolExecResult(
        content: jsonEncode({
          'ok': false,
          'reason': 'repeat_failure_blocked',
          'hint': '这条命令已连续失败 $streak 次，本次未再执行。请更换思路：改用其他命令、'
              '检查 PATH/完整路径/参数写法，或直接向用户说明该操作在本机无法完成。',
        }),
        ok: false,
        actionLabel: '重复失败命令已拦截',
      );
    }
    var timeoutMs = (args['timeout_ms'] as num?)?.toInt() ?? 30000;
    if (timeoutMs < 1000) timeoutMs = 1000;
    if (timeoutMs > 60000) timeoutMs = 60000;
    try {
      // 默认在工作区根目录执行，让 `dir src`、`tsc` 等相对命令直接可用；
      // 否则默认 cwd 是系统目录，模型用相对路径的命令会全部失败（退出码 1）。
      // 若工作区目录不存在（被删等），回退系统默认 cwd，不阻断命令执行。
      final wd = Directory(_fsRoot()).existsSync() ? _fsRoot() : null;
      final result = await Process.run(
        'cmd',
        ['/c', cmd],
        runInShell: false,
        workingDirectory: wd,
      ).timeout(Duration(milliseconds: timeoutMs));
      // R13 修复：失败连击此前只读不写，熔断从未生效（模型可无限重试同一条
      // 失败命令烧光工具轮次）。现在成功清零、失败累加，连败 2 次后拦截。
      if (result.exitCode == 0) {
        _cmdFailStreak.remove(cmd);
      } else {
        _cmdFailStreak[cmd] = streak + 1;
      }
      final out = result.stdout.toString();
      final err = result.stderr.toString();
      final body = out.length > 32 * 1024 ? out.substring(0, 32 * 1024) + '\n... [输出已截断]' : out;
      final errBody = err.length > 32 * 1024 ? err.substring(0, 32 * 1024) + '\n... [输出已截断]' : err;
      final payload = <String, dynamic>{
        'ok': result.exitCode == 0,
        'exit_code': result.exitCode,
        'stdout': body,
        'stderr': errBody,
      };
      final hint = _windowsCmdHint(result.exitCode, err);
      if (hint.isNotEmpty) payload['hint'] = hint;
      // R14: 命令不存在（9009）时主动解析首 token 的真实路径给模型。
      // GUI 启动的应用可能拿不到登录后才新增的 PATH 项（装了 node 仍 9009），
      // 光说"改用完整路径"模型并不知道路径是什么，只会反复换写法空转。
      final notFound = result.exitCode == 9009 ||
          err.contains('不是内部或外部命令') ||
          err.toLowerCase().contains('is not recognized');
      if (notFound) {
        final resolved = await _resolveCmdPathHint(cmd);
        if (resolved.isNotEmpty) payload['path_hint'] = resolved;
      }
      return ToolExecResult(
        content: jsonEncode(payload),
        ok: result.exitCode == 0,
        actionLabel: result.exitCode == 0 ? '已执行命令' : '命令退出码 ${result.exitCode}',
        exitCode: result.exitCode,
        terminalOutput: [if (out.isNotEmpty) out, if (err.isNotEmpty) 'STDERR: $err'].join('\n'),
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"exec_failed: $e"}', ok: false, actionLabel: '命令执行失败');
    }
  }

  /// R14: 9009（命令不存在）时解析命令首 token 的真实路径：
  /// 先 `where` 查 PATH，再探测 node/npm/npx/git 的常见安装目录（绕过 PATH，
  /// 应对"已安装但 GUI 应用拿不到新 PATH"的场景）。找到就把完整路径直接给
  /// 模型；找不到则明确告知不可用、禁止再试，避免一轮轮撞同一堵墙。
  Future<String> _resolveCmdPathHint(String cmd) async {
    final first = cmd.split(RegExp(r'[\s&|<>]+')).first.trim();
    if (first.isEmpty || first.length > 64) return '';
    try {
      final r = await Process.run('cmd', ['/c', 'where $first'])
          .timeout(const Duration(seconds: 5));
      final out = r.stdout.toString().trim();
      if (r.exitCode == 0 && out.isNotEmpty) {
        final path = out.split('\n').first.trim();
        return '已定位「$first」的实际路径：$path。请直接用该完整路径调用'
            '（路径含空格时用双引号包裹整段路径），不要再用裸命令名重试。';
      }
    } catch (_) {}
    // 常见安装位置探测
    final probeDirs = <String>[
      r'C:\Program Files\nodejs',
      r'C:\Program Files (x86)\nodejs',
      r'C:\Program Files\Git\cmd',
      r'C:\Program Files\Git\bin',
    ];
    final local = Platform.environment['LOCALAPPDATA'] ?? '';
    if (local.isNotEmpty) probeDirs.add('$local\\Programs\\nodejs');
    for (final d in probeDirs) {
      for (final name in <String>['$first.exe', '$first.cmd', '$first.bat']) {
        final p = '$d\\$name';
        if (File(p).existsSync()) {
          return '已定位「$first」的实际路径：$p。请直接用该完整路径调用'
              '（路径含空格时用双引号包裹整段路径），不要再用裸命令名重试。';
        }
      }
    }
    return '「$first」在本机不可用（PATH 与常见安装目录均未找到）。'
        '请改用其他方式完成该步骤（如应用内置工具或 PowerShell 命令），不要再重试该命令。';
  }

  /// R12: Windows 命令失败的纠正性提示（写入 tool 结果，引导模型换正确写法）
  String _windowsCmdHint(int exitCode, String err) {
    if (exitCode == 0) return '';
    final e = err.toLowerCase();
    if (exitCode == 9009 || e.contains('不是内部或外部命令') || e.contains('is not recognized')) {
      return '命令不存在（退出码 9009）。本机是 Windows cmd 环境，常见原因与正确写法：'
          '• 误用了 Linux 命令：ls→dir，cat→type，touch→type nul>文件，rm→del，cp→copy，mv→move，grep→findstr，pwd→cd，which→where，ps→tasklist；'
          '• 程序未加入 PATH：请改用完整路径调用，或先用 where 确认；'
          '• 不要重复执行同一条失败命令，先换正确写法。';
    }
    if (e.contains('语法不正确') || e.contains('the syntax of the command is incorrect')) {
      return 'cmd 语法错误：Windows 命令行不支持 Linux shell 语法（; 连接、单引号、重定向写法不同），请改用 cmd 兼容写法。';
    }
    return '';
  }

  String _basename(String path) {
    final sep = path.contains(r'\') ? r'\' : '/';
    final idx = path.lastIndexOf(sep);
    return idx < 0 ? path : path.substring(idx + 1);
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  // ============== dsh 移植工具实现（第二轮 6 个） ==============

  /// dsh-tool-ask-user: 让用户从选项中选
  Future<ToolExecResult> _toolAskUserQuestion(Map<String, dynamic> args) async {
    final raw = args['questions'];
    if (raw is! List || raw.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"missing_questions"}', ok: false, actionLabel: '缺少 questions');
    }
    final qs = <AskUserQuestion>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final id = ((e['id'] as String?) ?? '').trim();
      final q = ((e['question'] as String?) ?? '').trim();
      if (id.isEmpty || q.isEmpty) continue;
      final header = (e['header'] as String?)?.trim();
      final opts = <AskUserOption>[];
      final rawOpts = e['options'];
      if (rawOpts is List) {
        for (final o in rawOpts) {
          if (o is! Map) continue;
          final lbl = ((o['label'] as String?) ?? '').trim();
          if (lbl.isEmpty) continue;
          opts.add(AskUserOption(label: lbl, description: (o['description'] as String?)?.trim()));
        }
      }
      final multi = e['multi_select'] == true;
      qs.add(AskUserQuestion(id: id, question: q, header: header, options: opts, multiSelect: multi));
    }
    if (qs.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"no_valid_questions"}', ok: false, actionLabel: '没有有效问题');
    }
    for (var i = chatHistory.length - 1; i >= 0; i--) {
      if (chatHistory[i].role == 'ai') {
        chatHistory[i].askQuestions = qs;
        chatHistory[i].askAnswers = {};
        break;
      }
    }
    _notifyChatUpdate();
    // 挂起等待用户在 UI 选择并点"确认"（completeAskAnswers 唤醒），
    // 最多等 5 分钟，超时按当前已选（可能为空）返回
    final key = 'ask_${_askSeq++}';
    final completer = Completer<Map<String, List<String>>>();
    _askCompleters[key] = completer;
    Map<String, List<String>> answers = {};
    try {
      answers = await completer.future.timeout(const Duration(minutes: 5), onTimeout: () => {});
    } catch (_) {}
    _askCompleters.remove(key);
    final answerList = <Map<String, dynamic>>[];
    for (final q in qs) {
      final sel = answers[q.id] ?? const <String>[];
      answerList.add({'id': q.id, 'selected': sel, 'custom': null});
    }
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'answers': answerList, 'pending': false}),
      ok: true,
      actionLabel: answers.isEmpty ? '用户未作答（超时）' : '已收到用户回答',
    );
  }

  /// dsh-tool-compaction: 总结早期消息
  Future<ToolExecResult> _toolCompactConversation(Map<String, dynamic> args) async {
    final focus = (args['focus'] as String?)?.trim() ?? '';
    var keepRecent = (args['keep_recent'] as num?)?.toInt() ?? 8;
    if (keepRecent < 4) keepRecent = 4;
    if (keepRecent > chatHistory.length) keepRecent = chatHistory.length ~/ 2;
    if (chatHistory.length <= keepRecent + 2) {
      return const ToolExecResult(content: '{"ok":false,"reason":"too_short"}', ok: false, actionLabel: '对话太短，无需压缩');
    }
    final cut = chatHistory.length - keepRecent;
    final toCompact = chatHistory.sublist(0, cut);
    final summary = await _summarizeMessages(toCompact, focus: focus);
    final summaryMsg = ChatMessage(role: 'system', content: '【早期对话摘要】$summary');
    chatHistory = [summaryMsg, ...chatHistory.sublist(cut)];
    _notifyChatUpdate();
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'compacted': toCompact.length, 'kept_recent': keepRecent, 'summary': summary}),
      ok: true,
      actionLabel: '已压缩 $cut 条消息为摘要',
    );
  }

  Future<String> _summarizeMessages(List<ChatMessage> msgs, {String focus = ''}) async {
    final cfg = effectiveChatConfig;
    if (!cfg.ready) return '（AI 未配置，跳过摘要）';
    final buf = StringBuffer();
    for (final m in msgs) {
      buf.writeln('${m.role == "user" ? "用户" : "AI"}: ${m.content}');
    }
    final sysHint = focus.isNotEmpty
        ? '你是对话压缩助手。总结以下对话，重点保留：$focus。输出简洁中文，500字以内。'
        : '你是对话压缩助手。总结以下对话的关键事实、用户偏好、已完成工作、未解决问题。输出简洁中文，500字以内。';
    final reply = await ApiService.callAI([
      {'role': 'system', 'content': sysHint},
      {'role': 'user', 'content': buf.toString()},
    ], sysHint, config: cfg, extraParams: ApiService.noThinkingParams(cfg.model));
    return reply ?? '（摘要生成失败）';
  }

  /// dsh-tool-skill-filesystem
  /// 候选技能根目录：用户工作区 > 默认 C:\Users > 应用当前目录 > exe 所在目录
  List<String> _skillRoots() {
    final roots = <String>[];
    final ws = workspacePath.trim();
    if (ws.isNotEmpty) roots.add(ws);
    if (ws.toLowerCase() != r'c:\users') roots.add(r'C:\Users');
    try {
      roots.add(Directory.current.path);
      roots.add(Platform.resolvedExecutable.isNotEmpty ? Directory(Platform.resolvedExecutable).parent.path : '');
    } catch (_) {}
    return roots.where((r) => r.isNotEmpty).toSet().toList();
  }

  Future<ToolExecResult> _toolListUserSkills() async {
    final skills = <Map<String, String>>[];
    final scannedDirs = <String>[];
    for (final root in _skillRoots()) {
      final dir = Directory('$root\\.dsh\\skills');
      if (!await dir.exists()) continue;
      scannedDirs.add(dir.path);
      await for (final ent in dir.list()) {
        if (ent is! File) continue;
        if (!ent.path.toLowerCase().endsWith('.md')) continue;
        try {
          final content = await ent.readAsString();
          final (meta, body) = _parseSkillMd(content);
          final name = meta['name'] ?? _basename(ent.path).replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
          final desc = meta['description'] ?? '';
          // 后扫描的目录不覆盖已存在的同名技能（工作区优先）
          if (userSkillsCache.containsKey(name)) continue;
          userSkillsCache[name] = body;
          userSkillDescriptions[name] = desc;
          skills.add({'name': name, 'description': desc, 'file': ent.path});
        } catch (_) {}
      }
    }
    if (skills.isEmpty && skillStore.enabled.isEmpty) {
      final rootsHint = _skillRoots().map((r) => r).join('；');
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'count': 0, 'skills': [], 'hint': '在任意候选根目录的 .dsh\\skills 下放 *.md 文件即可（候选：$rootsHint）；也可在设置 → 技能管理中添加自定义技能'}),
        ok: true,
        actionLabel: '未发现用户技能（已扫描 ${scannedDirs.length} 个目录）',
      );
    }
    // 技能商店（内置 + 自定义）也一并列出，供 load_skill / skill 检索
    for (final s in skillStore.enabled) {
      skills.add({'name': s.name, 'description': s.description, 'file': 'skill-store:${s.id}', 'category': s.category});
    }
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'count': skills.length, 'skills': skills}),
      ok: true,
      actionLabel: '发现 ${skills.length} 个可用技能',
    );
  }

  (Map<String, String>, String) _parseSkillMd(String content) {
    final lines = content.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') return (const {}, content);
    int endIdx = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        endIdx = i;
        break;
      }
    }
    if (endIdx < 0) return (<String, String>{}, content);
    final fm = <String, String>{};
    for (var i = 1; i < endIdx; i++) {
      final m = RegExp(r'^([a-zA-Z_-]+):\s*(.*)$').firstMatch(lines[i]);
      if (m != null) {
        final k = m.group(1) ?? '';
        final v = m.group(2) ?? '';
        if (k.isNotEmpty) {
          final cleaned = v.trim().replaceAll(RegExp('^["\']|["\']\$'), '');
          fm[k] = cleaned;
        }
      }
    }
    final body = lines.sublist(endIdx + 1).join('\n').trim();
    return (fm, body);
  }

  Future<ToolExecResult> _toolLoadSkill(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_name"}', ok: false, actionLabel: '缺少 name');
    // 优先技能商店（内置 + 自定义）
    final storeSkill = skillStore.find(name);
    if (storeSkill != null && storeSkill.enabled) {
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'name': storeSkill.name, 'description': storeSkill.description, 'instructions': storeSkill.content}),
        ok: true,
        actionLabel: '已加载技能「${storeSkill.name}」',
      );
    }
    if (!userSkillsCache.containsKey(name)) {
      await _toolListUserSkills();
    }
    final body = userSkillsCache[name];
    if (body == null) {
      return ToolExecResult(
        content: jsonEncode({'ok': false, 'reason': 'skill_not_found', 'available': userSkillsCache.keys.toList()}),
        ok: false,
        actionLabel: '未找到用户技能：$name',
      );
    }
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'name': name, 'description': userSkillDescriptions[name] ?? '', 'instructions': body}),
      ok: true,
      actionLabel: '已加载用户技能「$name」',
    );
  }

  /// dsh-plan-mode
  Future<ToolExecResult> _toolSubmitPlan(Map<String, dynamic> args) async {
    final title = (args['title'] as String?)?.trim() ?? '执行计划';
    final summary = (args['summary'] as String?)?.trim();
    final rawSteps = args['steps'];
    final steps = <PlanStep>[];
    if (rawSteps is List) {
      for (final e in rawSteps) {
        if (e is! Map) continue;
        final step = (e['step'] as num?)?.toInt() ?? (steps.length + 1);
        final action = ((e['action'] as String?) ?? '').trim();
        if (action.isEmpty) continue;
        final tools = (e['tools'] is List) ? (e['tools'] as List).map((x) => x.toString()).toList() : <String>[];
        final output = (e['output'] as String?)?.trim();
        steps.add(PlanStep(step: step, action: action, tools: tools, output: output));
      }
    }
    if (steps.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"no_steps"}', ok: false, actionLabel: '计划必须包含至少一个步骤');
    }
    final plan = PlanSubmission(title: title, summary: summary, steps: steps);
    for (var i = chatHistory.length - 1; i >= 0; i--) {
      if (chatHistory[i].role == 'ai') {
        chatHistory[i].plan = plan;
        break;
      }
    }
    _notifyChatUpdate();
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'plan': plan.toJson(), 'pending': true}),
      ok: true,
      actionLabel: '已提交计划，等待用户审批',
    );
  }

  /// dsh-tool-jobs
  Future<ToolExecResult> _toolRunBackgroundJob(Map<String, dynamic> args) async {
    final cmd = (args['command'] as String?)?.trim() ?? '';
    final desc = (args['description'] as String?)?.trim() ?? '';
    if (cmd.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_command"}', ok: false, actionLabel: '缺少命令');
    final jobId = DateTime.now().millisecondsSinceEpoch.toString();
    final job = BackgroundJob(jobId: jobId, command: cmd, description: desc, startedAt: DateTime.now());
    backgroundJobs[jobId] = job;
    () async {
      try {
        // Process.start 保留进程引用，job_kill 可真正终止；
        // Process.run 无法拿到 Process 对象，kill 只能改标志位（旧缺陷）
        final proc = await Process.start('cmd', ['/c', cmd], runInShell: false);
        job.process = proc;
        // kill 恰好发生在 start 与赋值之间的竞态窗口：立即补杀
        if (job.killed) proc.kill();
        final outBuf = StringBuffer();
        final errBuf = StringBuffer();
        // Windows cmd 输出为系统码页，用 systemEncoding 解码避免中文乱码
        proc.stdout.transform(systemEncoding.decoder).listen(
              outBuf.write,
              onError: (Object e) {},
              cancelOnError: false,
            );
        proc.stderr.transform(systemEncoding.decoder).listen(
              errBuf.write,
              onError: (Object e) {},
              cancelOnError: false,
            );
        final code = await proc.exitCode;
        // 已被 kill 的任务：保留 kill 时写入的（用户已取消）文案，不反向覆写
        if (!job.killed) {
          job.stdout = outBuf.toString();
          job.stderr = errBuf.toString();
          job.exitCode = code;
        }
        job.finished = true;
      } catch (e) {
        if (!job.killed) {
          job.stderr = '$e';
          job.exitCode = -1;
        }
        job.finished = true;
      }
      notifyListeners();
    }();
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'job_id': jobId, 'started_at': job.startedAt.toIso8601String()}),
      ok: true,
      actionLabel: '已启动后台任务 $jobId',
    );
  }

  Future<ToolExecResult> _toolJobOutput(Map<String, dynamic> args) async {
    final jobId = (args['job_id'] as String?)?.trim() ?? '';
    final wait = args['wait'] != false;
    var timeoutMs = (args['timeout_ms'] as num?)?.toInt() ?? 5000;
    if (timeoutMs < 100) timeoutMs = 100;
    if (timeoutMs > 60000) timeoutMs = 60000;
    final job = backgroundJobs[jobId];
    if (job == null) {
      return ToolExecResult(content: jsonEncode({'ok': false, 'reason': 'job_not_found'}), ok: false, actionLabel: '未找到任务 $jobId');
    }
    if (wait && !job.finished) {
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (!job.finished && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return ToolExecResult(
      content: jsonEncode({
        'ok': true,
        'job_id': jobId,
        'finished': job.finished,
        'exit_code': job.exitCode,
        'stdout': job.stdout,
        'stderr': job.stderr,
      }),
      ok: true,
      actionLabel: job.finished ? '任务已结束' : '任务进行中',
    );
  }

  Future<ToolExecResult> _toolJobKill(Map<String, dynamic> args) async {
    final jobId = (args['job_id'] as String?)?.trim() ?? '';
    final job = backgroundJobs[jobId];
    if (job == null) {
      return ToolExecResult(content: jsonEncode({'ok': false, 'reason': 'job_not_found'}), ok: false, actionLabel: '未找到任务 $jobId');
    }
    // 真正终止进程（而非只改标志位），并标记 killed 防止完成回调反向覆写
    job.killed = true;
    job.finished = true;
    job.stderr = '（用户已取消）';
    job.process?.kill();
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'job_id': jobId, 'killed': true}),
      ok: true,
      actionLabel: '已终止任务 $jobId',
    );
  }

  /// dsh-guard
  Future<ToolExecResult> _toolCheckRepeat() async {
    if (recentToolCalls.length < 2) {
      return const ToolExecResult(content: '{"ok":true,"has_repeat":false}', ok: true, actionLabel: '无重复调用');
    }
    final last = recentToolCalls.last;
    final lastKey = '${last['name']}|${jsonEncode(last['args'])}';
    final repeats = <Map<String, dynamic>>[];
    for (var i = recentToolCalls.length - 2; i >= 0; i--) {
      final key = '${recentToolCalls[i]['name']}|${jsonEncode(recentToolCalls[i]['args'])}';
      if (key == lastKey) {
        repeats.add(recentToolCalls[i]);
      }
    }
    if (repeats.isEmpty) {
      return const ToolExecResult(content: '{"ok":true,"has_repeat":false}', ok: true, actionLabel: '最近工具调用无重复');
    }
    return ToolExecResult(
      content: jsonEncode({
        'ok': true,
        'has_repeat': true,
        'repeat_count': repeats.length + 1,
        'message': '你最近 ${repeats.length + 1} 次调用了同一个工具+参数。请基于已有结果继续，不要再重复调用。',
      }),
      ok: true,
      actionLabel: '检测到 ${repeats.length + 1} 次重复调用',
    );
  }

  // ============== dsh 移植工具实现 ==============

  /// 把 JS 对象字面量转成 JSON（键补引号、单引号值转双引号）：{path: "a", n: 1} → {"path":"a","n":1}
  String _jsObjectToJson(String expr) {
    // 简化：匹配 { ... }，把里面的裸键（前面是 { 或 , 后面是 :）加引号
    var s = expr.trim();
    if (!s.startsWith('{')) {
      // 可能是普通字符串/数字，包成 value
      return jsonEncode(_parseJsScalar(s));
    }
    final buf = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if ((ch == '{' || ch == ',') && i + 1 < s.length) {
        buf.write(ch);
        i++;
        // 跳过空白
        while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\t')) {
          buf.write(s[i]);
          i++;
        }
        // 如果下一个不是引号，则是裸键 → 加引号
        if (i < s.length && s[i] != '"' && s[i] != "'" && s[i] != '}' && s[i] != ',') {
          final keyStart = i;
          while (i < s.length && s[i] != ':' && s[i] != ',' && s[i] != '}' && s[i] != ' ' && s[i] != '\n') {
            i++;
          }
          final key = s.substring(keyStart, i).trim();
          buf.write('"$key"');
          continue;
        }
        buf.write(ch == ',' ? ',' : ' ');
        continue;
      }
      buf.write(ch);
      i++;
    }
    var out = buf.toString();
    // 单引号字符串值 → 双引号（容错模型输出 {name: 'qwen'} 这类）
    out = out.replaceAllMapped(RegExp(r":\s*'((?:[^'\\]|\\.)*)'"), (m) => ': "${m.group(1)!.replaceAll('"', r'\"')}"');
    // 裸字符串值（: hello）→ 加引号
    out = out.replaceAllMapped(RegExp(r":\s*([A-Za-z_][A-Za-z0-9_.\-/\\]*)([,}])"), (m) => ': "${m.group(1)}"${m.group(2)}');
    return out;
  }

  dynamic _parseJsScalar(String v) {
    final t = v.trim();
    if (t == 'true') return true;
    if (t == 'false') return false;
    if (t == 'null') return null;
    if (t.startsWith('"') && t.endsWith('"') && t.length >= 2) return t.substring(1, t.length - 1);
    if (t.startsWith("'") && t.endsWith("'") && t.length >= 2) return t.substring(1, t.length - 1);
    final n = num.tryParse(t);
    if (n != null) return n;
    return t;
  }

  /// 解析 `tools.<name>(<args>)` 调用，返回 (工具名, 参数Map) 列表
  List<({String name, Map<String, dynamic> args})> _parseRunCodeCalls(String code) {
    final calls = <({String name, Map<String, dynamic> args})>[];
    // 匹配 tools.xxx({...}) 或 tools.xxx({...}).xxx 等
    final re = RegExp(r'tools\.([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\s*(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*)\s*\)');
    for (final m in re.allMatches(code)) {
      final name = m.group(1)!;
      final rawArgs = m.group(2)!;
      Map<String, dynamic> args = {};
      try {
        final jsonStr = _jsObjectToJson(rawArgs);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map) {
          args = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (_) {
        // 解析失败：尝试裸值
        try {
          final v = _parseJsScalar(rawArgs);
          args = {'value': v};
        } catch (_2) {
          args = {};
        }
      }
      calls.add((name: name, args: args));
    }
    return calls;
  }

  /// Code Mode 执行器：解析并执行 model 编写的工具调用序列，聚合结果
  Future<ToolExecResult> _toolRunCode(Map<String, dynamic> args) async {
    final code = (args['code'] as String?) ?? '';
    final desc = (args['description'] as String?)?.trim() ?? '';
    if (code.trim().isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"missing_code"}', ok: false, actionLabel: '缺少 code');
    }
    // 不支持的工具列表（防递归/循环）
    const forbidden = {'run_code', 'ask_user_question', 'submit_plan', 'spawn_subagent', 'compact_conversation'};
    final calls = _parseRunCodeCalls(code);
    if (calls.isEmpty) {
      return ToolExecResult(
        content: jsonEncode({
          'ok': false,
          'reason': 'no_tool_calls_parsed',
          'hint': '代码里没有解析到 tools.<工具名>({...}) 调用。示例：const r = await tools.read_file({path: "C:/Users/x/a.txt"}); return r.content;',
        }),
        ok: false,
        actionLabel: '未解析到工具调用',
      );
    }
    final results = <Map<String, dynamic>>[];
    var allOk = true;
    for (final call in calls) {
      if (forbidden.contains(call.name)) {
        results.add({'tool': call.name, 'ok': false, 'error': 'run_code 内不允许调用 $call.name'});
        allOk = false;
        continue;
      }
      try {
        final res = await executeTool(call.name, call.args);
        results.add({'tool': call.name, 'ok': res.ok, 'label': res.actionLabel, 'result': res.content});
        if (!res.ok) allOk = false;
      } catch (e) {
        results.add({'tool': call.name, 'ok': false, 'error': '$e'});
        allOk = false;
      }
    }
    // 尝试解析 return 语句，若代码里有 return <表达式> 且表达式是字面量，附加到输出
    String? returnNote;
    final returnRe = RegExp(r'return\s+(.+?)\s*;?\s*$', multiLine: true);
    final rm = returnRe.firstMatch(code);
    if (rm != null) {
      final v = rm.group(1)!.trim();
      if (!v.startsWith('await') && !v.startsWith('tools.') && !v.startsWith('{') && !v.startsWith('const')) {
        returnNote = v;
      }
    }
    final summary = results.map((r) {
      final label = (r['label'] as String?) ?? r['tool'];
      final ok = r['ok'] == true;
      return '${ok ? "✅" : "❌"} ${r['tool']}: $label';
    }).join('\n');
    return ToolExecResult(
      content: jsonEncode({
        'ok': allOk,
        'steps': results.length,
        'description': desc,
        'results': results,
        if (returnNote != null) 'return_value': returnNote,
      }),
      ok: allOk,
      actionLabel: allOk ? 'run_code 完成 ${results.length} 步' : 'run_code 完成 ${results.length} 步（有失败）',
    );
  }

  /// dsh-tool-todo: 任务清单管理
  Future<ToolExecResult> _toolTodo(Map<String, dynamic> args) async {
    final raw = args['todos'];
    if (raw is! List) {
      return const ToolExecResult(content: '{"ok":false,"reason":"missing_todos"}', ok: false, actionLabel: '缺少 todos 数组');
    }
    final items = <TodoItem>[];
    for (final e in raw) {
      if (e is Map) {
        final content = ((e['content'] as String?) ?? '').trim();
        final status = ((e['status'] as String?) ?? 'pending').trim();
        if (content.isEmpty) continue;
        items.add(TodoItem(content: content, status: status));
      }
    }
    if (items.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"empty_todos"}', ok: false, actionLabel: 'todos 数组为空');
    }
    // 单 active in_progress 校验
    final inProgressCount = items.where((t) => t.status == 'in_progress').length;
    if (inProgressCount > 1) {
      return ToolExecResult(
        content: '{"ok":false,"reason":"multiple_in_progress"}',
        ok: false,
        actionLabel: '同一时刻只能有一个 in_progress，当前 $inProgressCount 个',
      );
    }
    // 找到最近一条 AI 消息，把 todoList 写进去
    for (var i = chatHistory.length - 1; i >= 0; i--) {
      if (chatHistory[i].role == 'ai') {
        chatHistory[i].todoList = items;
        break;
      }
    }
    _notifyChatUpdate();
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'count': items.length, 'todos': items.map((t) => t.toJson()).toList()}),
      ok: true,
      actionLabel: '已更新任务清单（${items.length} 项，$inProgressCount 进行中）',
    );
  }

  /// dsh-tool-skill: 加载技能完整指令
  Future<ToolExecResult> _toolSkill(Map<String, dynamic> args) async {
    final name = (args['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_name"}', ok: false, actionLabel: '缺少技能名');
    // 1) 技能商店（内置 ModelScope 技能 + 用户自定义）
    final storeSkill = skillStore.find(name);
    if (storeSkill != null) {
      if (!storeSkill.enabled) {
        return ToolExecResult(
          content: jsonEncode({'ok': false, 'reason': 'skill_disabled', 'name': storeSkill.name}),
          ok: false,
          actionLabel: '技能「${storeSkill.name}」已被禁用',
        );
      }
      return ToolExecResult(
        content: jsonEncode({
          'ok': true,
          'name': storeSkill.name,
          'id': storeSkill.id,
          'description': storeSkill.description,
          'instructions': storeSkill.content,
        }),
        ok: true,
        actionLabel: '已加载技能「${storeSkill.name}」',
      );
    }
    // 2) 内置对话技能（ChatSkill）
    ChatSkill? found;
    for (final s in kAllChatSkills) {
      if (s.id == name || s.name == name) {
        found = s;
        break;
      }
    }
    if (found == null) {
      final names = [
        ...skillStore.enabled.map((s) => s.name),
        ...kAllChatSkills.map((s) => s.name),
      ].take(30).join('、');
      return ToolExecResult(
        content: '{"ok":false,"reason":"skill_not_found","available":"$names..."}',
        ok: false,
        actionLabel: '未找到技能：$name',
      );
    }
    return ToolExecResult(
      content: jsonEncode({
        'ok': true,
        'name': found.name,
        'description': found.description,
        'instructions': found.prompt,
        'toolName': found.toolName,
      }),
      ok: true,
      actionLabel: '已加载技能「${found.name}」',
    );
  }

  /// dsh-tool-web (web_fetch 部分): 抓取并清理 HTML
  Future<ToolExecResult> _toolWebFetch(Map<String, dynamic> args) async {
    final url = (args['url'] as String?)?.trim() ?? '';
    if (url.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_url"}', ok: false, actionLabel: '缺少 URL');
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      return const ToolExecResult(content: '{"ok":false,"reason":"bad_scheme"}', ok: false, actionLabel: 'URL 必须以 http:// 或 https:// 开头');
    }
    var maxChars = (args['max_chars'] as num?)?.toInt() ?? 200000;
    if (maxChars < 1000) maxChars = 1000;
    if (maxChars > 200000) maxChars = 200000;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Afloat/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode >= 400) {
        return ToolExecResult(content: jsonEncode({'ok': false, 'status': resp.statusCode}), ok: false, actionLabel: 'HTTP ${resp.statusCode}');
      }
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      // 简易 HTML → 文本：去 script/style、tag、合并空白
      var text = body
          .replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'")
          .replaceAll(RegExp(r'\s+'), ' ');
      final truncated = text.length > maxChars;
      if (truncated) text = text.substring(0, maxChars);
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'url': url, 'length': text.length, 'truncated': truncated, 'text': text}),
        ok: true,
        actionLabel: truncated ? '已抓取 ${(text.length / 1024).toStringAsFixed(1)}KB (已截断)' : '已抓取 ${(text.length / 1024).toStringAsFixed(1)}KB',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"fetch_failed: $e"}', ok: false, actionLabel: '抓取失败');
    }
  }

  /// dsh-tool-session-query: 跨会话查历史
  Future<ToolExecResult> _toolSessionQuery(Map<String, dynamic> args) async {
    final op = (args['operation'] as String?)?.trim() ?? '';
    final query = (args['query'] as String?)?.trim() ?? '';
    final sessionId = (args['session_id'] as String?)?.trim() ?? '';
    var limit = (args['limit'] as num?)?.toInt() ?? 20;
    if (limit < 1) limit = 1;
    if (limit > 100) limit = 100;
    switch (op) {
      case 'list_sessions':
        var list = List<Map<String, dynamic>>.from(chatSessions);
        if (query.isNotEmpty) {
          list = list.where((s) => ((s['title'] as String?) ?? '').contains(query)).toList();
        }
        if (list.length > limit) list = list.sublist(0, limit);
        return ToolExecResult(
          content: jsonEncode({'ok': true, 'count': list.length, 'sessions': list}),
          ok: true,
          actionLabel: '列出最近 ${list.length} 个会话',
        );
      case 'search_history':
        if (query.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_query"}', ok: false, actionLabel: 'search_history 需要 query');
        final idx = chatSessions.indexWhere((s) => s['id'] == sessionId);
        if (idx < 0) return ToolExecResult(content: '{"ok":false,"reason":"session_not_found"}', ok: false, actionLabel: '未找到会话 $sessionId');
        final messages = (idx < chatSessionMessages.length) ? chatSessionMessages[idx] : <Map<String, dynamic>>[];
        final hits = <Map<String, dynamic>>[];
        for (var i = 0; i < messages.length; i++) {
          final content = (messages[i]['content'] as String?) ?? '';
          if (content.contains(query)) {
            hits.add({'index': i, 'role': messages[i]['role'], 'snippet': content.length > 200 ? '${content.substring(0, 200)}...' : content});
            if (hits.length >= limit) break;
          }
        }
        return ToolExecResult(
          content: jsonEncode({'ok': true, 'sessionId': sessionId, 'hits': hits.length, 'matches': hits}),
          ok: true,
          actionLabel: '在会话内找到 ${hits.length} 条命中',
        );
      case 'get_session':
        if (sessionId.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_session_id"}', ok: false, actionLabel: 'get_session 需要 session_id');
        final idx = chatSessions.indexWhere((s) => s['id'] == sessionId);
        if (idx < 0) return ToolExecResult(content: '{"ok":false,"reason":"session_not_found"}', ok: false, actionLabel: '未找到会话 $sessionId');
        final messages = (idx < chatSessionMessages.length) ? chatSessionMessages[idx] : <Map<String, dynamic>>[];
        return ToolExecResult(
          content: jsonEncode({'ok': true, 'sessionId': sessionId, 'messageCount': messages.length, 'messages': messages}),
          ok: true,
          actionLabel: '已获取会话（${messages.length} 条消息）',
        );
      default:
        return ToolExecResult(content: '{"ok":false,"reason":"unknown_op:$op"}', ok: false, actionLabel: '未知操作：$op');
    }
  }

  /// dsh-tool-subagent: 派生子 Agent
  /// 子 Agent 可调用的工具白名单（文件/命令/检索类；避免子 Agent 再派生子 Agent 或改动应用状态）
  static const Set<String> _subagentTools = {
    'read_file',
    'write_file',
    'edit_file',
    'list_dir',
    'bash',
    'str_replace_editor',
    'web_fetch',
    'search_web',
    'todo',
    'load_skill',
    'skill',
    'list_user_skills',
  };

  /// dsh-tool-subagent：派发隔离的子 Agent（多轮工具循环，独立上下文）。
  /// [onProgress] 把子 Agent 的每一步实时上报给 UI（AgentSubagentCard 事件流）。
  Future<ToolExecResult> _toolSpawnSubagent(Map<String, dynamic> args, {void Function(Map<String, dynamic> event)? onProgress}) async {
    final task = (args['task'] as String?)?.trim() ?? '';
    if (task.isEmpty) return const ToolExecResult(content: '{"ok":false,"reason":"missing_task"}', ok: false, actionLabel: '缺少 task');
    final type = (args['type'] as String?)?.trim() ?? 'general';
    final ctx = (args['context'] as String?)?.trim() ?? '';
    void emit(Map<String, dynamic> e) => onProgress?.call(e);
    try {
      final cfg = effectiveChatConfig;
      if (!cfg.ready) return const ToolExecResult(content: '{"ok":false,"reason":"api_not_ready"}', ok: false, actionLabel: 'AI 未配置');
      final sysHint = switch (type) {
        'research' => '你是研究型子 Agent。专注联网检索与综合，给出有据可查的结论。',
        'coder' => '你是编码子 Agent。直接给可运行代码，必要时分块；完成后总结改动文件。',
        _ => '你是通用子 Agent。聚焦子任务，可调用文件/命令/检索工具多轮完成它，最后给出简洁完整的报告。',
      };
      final sys = '$sysHint\n\n'
          '你是一个隔离的子 Agent，负责独立完成以下子任务并把中间过程对主 Agent 透明化。\n'
          '规则：\n'
          '- 需要读文件、写文件、执行命令、联网检索时就直接调用对应工具，不要请求许可\n'
          '- 每轮只做当前最必要的一步；工具返回后根据结果决定下一步\n'
          '- 全部完成后输出最终报告（Markdown），包含：做了什么、关键产出/结论、文件路径（如有）\n'
          '- 不要反问用户（你无法与用户对话），缺信息时基于合理假设继续并注明假设\n'
          '${ctx.isNotEmpty ? '\n背景信息：\n$ctx\n' : ''}\n## 子任务\n$task';
      final messages = <Map<String, dynamic>>[
        {'role': 'user', 'content': task},
      ];
      // 子 Agent 工具定义（白名单过滤）
      final tools = AgentService.toolDefinitions(mcpTools: const [])
          .where((t) => _subagentTools.contains((t['function'] as Map)['name']))
          .toList();
      final steps = <Map<String, dynamic>>[];
      String? lastError;
      // 轮次耗尽 / 用户中止时的尽力报告
      String partialReport() =>
          steps.isNotEmpty ? steps.map((s) => '${s['ok'] == true ? '✓' : '✗'} ${s['label']}').join('\n') : '（无）';

      // 最多 8 轮工具循环
      for (var round = 0; round < 8; round++) {
        // 用户在主对话点了暂停：子 Agent 立即收工，返回部分报告（不让主循环干等）
        if (_chatAbortRequested) {
          emit({'type': 'aborted'});
          return ToolExecResult(
            content: jsonEncode({'ok': false, 'reason': 'user_aborted', 'type': type, 'steps': steps, 'partial': partialReport()}),
            ok: false,
            actionLabel: '子 Agent 已随主任务暂停',
          );
        }
        emit({'type': 'round', 'n': round + 1});
        final resp = await ApiService.callAIWithTools(
          messages,
          sys,
          config: cfg,
          tools: tools,
          maxTokens: 8192,
          extraParams: ApiService.noThinkingParams(cfg.model),
        );
        if (_chatAbortRequested) {
          emit({'type': 'aborted'});
          return ToolExecResult(
            content: jsonEncode({'ok': false, 'reason': 'user_aborted', 'type': type, 'steps': steps, 'partial': partialReport()}),
            ok: false,
            actionLabel: '子 Agent 已随主任务暂停',
          );
        }
        if (resp.content == null && resp.toolCalls.isEmpty) {
          lastError = ApiService.lastError ?? 'empty_response';
          break;
        }
        // 纯文本回复 = 子任务结束
        if (resp.toolCalls.isEmpty) {
          final reply = resp.content ?? '';
          if (reply.trim().isEmpty) {
            lastError = 'empty_reply';
            break;
          }
          return ToolExecResult(
            content: jsonEncode({'ok': true, 'type': type, 'reply': reply, 'steps': steps}),
            ok: true,
            actionLabel: '子 Agent ($type) 已完成 ${steps.length} 步',
          );
        }
        // 工具调用：逐个执行并回喂
        messages.add({'role': 'assistant', 'content': resp.content ?? '', 'tool_calls': [
              for (final tc in resp.toolCalls) {'id': tc.id, 'type': 'function', 'function': {'name': tc.name, 'arguments': tc.arguments}},
            ]});
        for (final tc in resp.toolCalls) {
          // 暂停：内部工具粒度检查，点暂停后不再发起新的工具调用
          if (_chatAbortRequested) {
            emit({'type': 'aborted'});
            return ToolExecResult(
              content: jsonEncode({'ok': false, 'reason': 'user_aborted', 'type': type, 'steps': steps, 'partial': partialReport()}),
              ok: false,
              actionLabel: '子 Agent 已随主任务暂停',
            );
          }
          final toolArgs = AgentService.parseArgs(tc.arguments);
          final label = _toolRunningLabel(tc.name, toolArgs).isEmpty ? _toolDefaultLabel(tc.name) : _toolRunningLabel(tc.name, toolArgs);
          emit({'type': 'tool', 'name': tc.name, 'label': label, 'status': 'running'});
          final result = await executeTool(tc.name, toolArgs);
          steps.add({'tool': tc.name, 'label': result.actionLabel.isNotEmpty ? result.actionLabel : label, 'ok': result.ok});
          emit({'type': 'tool', 'name': tc.name, 'label': result.actionLabel.isNotEmpty ? result.actionLabel : label, 'status': result.ok ? 'done' : 'fail'});
          messages.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'name': tc.name,
            'content': result.content.length > 8000 ? '${result.content.substring(0, 8000)}\n…(已截断)' : result.content,
          });
        }
      }
      // 轮次耗尽：收集已有信息给出尽力报告
      return ToolExecResult(
        content: jsonEncode({'ok': false, 'reason': 'rounds_exhausted:$lastError', 'type': type, 'steps': steps, 'partial': partialReport()}),
        ok: false,
        actionLabel: '子 Agent 达到轮次上限（已执行 ${steps.length} 步）',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"$e"}', ok: false, actionLabel: '子 Agent 失败');
    }
  }

  /// dsh-mcp-client: list_mcp_tools
  Future<ToolExecResult> _toolListMcpTools() async {
    if (mcpRegistry.clients.isEmpty) {
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'servers': [], 'hint': '请在设置 → MCP 中配置 server 后重启对话'}),
        ok: true,
        actionLabel: 'MCP server 未连接',
      );
    }
    final servers = mcpRegistry.clients.map((c) {
      return {
        'name': c.name,
        'serverInfo': c.serverInfo,
        'tools': c.tools.map((t) => {'name': t.name, 'description': t.description}).toList(),
      };
    }).toList();
    return ToolExecResult(
      content: jsonEncode({'ok': true, 'servers': servers}),
      ok: true,
      actionLabel: '已连接 ${servers.length} 个 MCP server，${mcpTools.length} 个工具',
    );
  }

  /// dsh-mcp-client: call_mcp_tool
  Future<ToolExecResult> _toolCallMcpTool(Map<String, dynamic> args) async {
    final server = (args['server_name'] as String?)?.trim() ?? '';
    final tool = (args['tool_name'] as String?)?.trim() ?? '';
    final arguments = (args['arguments'] as Map?)?.cast<String, dynamic>() ?? {};
    if (server.isEmpty || tool.isEmpty) {
      return const ToolExecResult(content: '{"ok":false,"reason":"missing_args"}', ok: false, actionLabel: '需要 server_name + tool_name + arguments');
    }
    final client = mcpRegistry.clientForServer(server);
    if (client == null) {
      return ToolExecResult(
        content: jsonEncode({'ok': false, 'reason': 'server_not_connected', 'server': server}),
        ok: false,
        actionLabel: 'MCP server $server 未连接',
      );
    }
    try {
      final result = await client.callTool(tool, arguments);
      return ToolExecResult(
        content: jsonEncode(result),
        ok: result['ok'] == true,
        actionLabel: result['ok'] == true ? '已调用 $server.$tool' : '$server.$tool 返回错误',
      );
    } catch (e) {
      return ToolExecResult(content: '{"ok":false,"reason":"$e"}', ok: false, actionLabel: '调用失败');
    }
  }

  /// 直接操控电脑（仅桌面端生效）：
  ///   operation: open_file / open_folder / open_url / launch_app / run_command
  ///   target: 本地路径、应用名、网址或待执行命令
  Future<ToolExecResult> _toolOperateComputer(Map<String, dynamic> args) async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return ToolExecResult(
        content: '{"ok":false,"reason":"手机端暂不支持直接操控电脑"}',
        ok: false,
        actionLabel: '操控失败',
      );
    }
    final op = ((args['operation'] as String?) ?? '').trim();
    final target = ((args['target'] as String?) ?? '').trim();
    if (target.isEmpty) {
      return ToolExecResult(content: '{"ok":false,"reason":"缺少目标路径/应用/命令"}', ok: false);
    }
    final opLabel = switch (op) {
      'open_file' => '打开文件',
      'open_folder' => '打开文件夹',
      'open_url' => '打开网址',
      'launch_app' => '启动应用',
      'run_command' => '运行命令',
      _ => '操作电脑',
    };
    try {
      String detail;
      switch (op) {
        case 'open_file':
        case 'open_folder':
        case 'open_url':
          if (Platform.isWindows) {
            final r = await Process.run('cmd', ['/c', 'start', '', target]);
            detail = r.exitCode == 0 ? '已用默认程序打开 $target' : '打开失败：${r.stderr}';
          } else if (Platform.isMacOS) {
            final r = await Process.run('open', [target]);
            detail = r.exitCode == 0 ? '已打开 $target' : '打开失败：${r.stderr}';
          } else {
            final r = await Process.run('xdg-open', [target]);
            detail = r.exitCode == 0 ? '已打开 $target' : '打开失败：${r.stderr}';
          }
        case 'launch_app':
          if (Platform.isWindows) {
            final r = await Process.run('cmd', ['/c', 'start', '', target]);
            detail = r.exitCode == 0 ? '已启动应用 $target' : '启动失败：${r.stderr}';
          } else if (Platform.isMacOS) {
            final r = await Process.run('open', ['-a', target]);
            detail = r.exitCode == 0 ? '已启动应用 $target' : '启动失败：${r.stderr}';
          } else {
            final r = await Process.run(target, const []);
            detail = r.exitCode == 0 ? '已启动应用 $target' : '启动失败：${r.stderr}';
          }
        case 'run_command':
          final r = Platform.isWindows
              ? await Process.run('cmd', ['/c', target])
              : await Process.run('/bin/sh', ['-c', target]);
          final out = r.stdout.toString().trim();
          final err = r.stderr.toString().trim();
          detail = r.exitCode == 0
              ? '命令执行成功${out.isEmpty ? '' : '：\n$out'}'
              : '命令执行失败（退出码 ${r.exitCode}）${err.isEmpty ? '' : '：\n$err'}';
          return ToolExecResult(
            content: jsonEncode({'ok': r.exitCode == 0, 'operation': op, 'target': target, 'detail': detail}),
            ok: r.exitCode == 0,
            actionLabel: r.exitCode == 0 ? '已运行命令' : '命令异常退出（退出码 ${r.exitCode}）',
            exitCode: r.exitCode,
            terminalOutput: [if (out.isNotEmpty) out, if (err.isNotEmpty) err].join('\n'),
          );
        default:
          return ToolExecResult(content: '{"ok":false,"reason":"不支持的操作 $op"}', ok: false);
      }
      return ToolExecResult(
        content: jsonEncode({'ok': true, 'operation': op, 'target': target, 'detail': detail}),
        ok: true,
        actionLabel: '已完成$opLabel',
      );
    } catch (e) {
      return ToolExecResult(
        content: '{"ok":false,"reason":"${e.toString()}"}',
        ok: false,
        actionLabel: '$opLabel失败',
      );
    }
  }

  /// Agent 循环：发送用户消息 → AI 返回 tool_calls → 执行工具 → 把结果喂回 AI → 直到 AI 返回纯文本
  /// 返回最终回复内容；如果 agent 不可用或失败，返回 null，调用方回退到原流程。
  /// 带 UI 实时反馈：占位消息显示“正在思考→正在出题→流式输出回复”。
  Future<({String reply, List<String> actions})?> _runAgentLoop(String text, {String? imageData}) async {
    final cfg = effectiveChatConfig;
    if (!cfg.ready) return null;
    if (!AgentService.modelSupportsTools(cfg.model)) return null;
  
    // 创建占位 AI 消息，实时更新（让用户看到 Agent 在做什么）
    // 思考过程是否显示跟随"显示思考过程"开关，关闭时不再展示思考链
    final placeholder = ChatMessage(role: 'ai', content: '', showReasoning: chatShowReasoning, reasoning: '', modelLabel: cfg.model);
    chatHistory.add(placeholder);
    _notifyChatUpdate();
  
    final tools = AgentService.toolDefinitions(
      mcpTools: mcpTools
          .map((t) => {
                'type': 'function',
                'function': {
                  'name': 'mcp__${t.name.replaceAll(' ', '_')}',
                  'description': '[MCP] ${t.description ?? t.name}',
                  'parameters': t.inputSchema,
                },
              })
          .toList(),
    );
    final actions = <String>[];
    // R15: 本轮循环中执行失败的 bash 命令清单（去重）。轮次耗尽时写进最终回复，
    // 让用户"继续"后的下一轮能看到哪些路走不通，而不是原样重撞同一堵墙。
    final failedCmds = <String>[];

    // R8/R9: 跨轮记住"上一轮调用过的所有工具名"（含 helper），用于在下一轮纯文本回复时
    // 判断模型是否"调完工具就草草收尾"（假完成）。helper 工具（load_skill 等）不算完成任务，
    // 核心工具调完后只回"操作已完成"等短句也算没真正作答，两种情况都强制继续。
    const _helperTools = <String>{
      'load_skill',
      'list_user_skills',
      'list_mcp_tools',
      'session_query',
      'compact_conversation',
      'check_repeat',
    };
    List<String> lastRoundTools = <String>[];
    // R8/R9 的"强制继续"提醒计数：最多追加 2 次。提醒语反复堆积会污染上下文，
    // 且模型若确实只想收尾，硬逼满 12 轮最终也只会落到"操作已完成"兜底，不如接受其文本回答。
    var nudgeCount = 0;
    // "参数不完整请重新调用"的重试计数：最多 2 次，防止残缺参数反复重发空转满 12 轮
    var brokenRetry = 0;
    // R11：todo 仍有未完成项时的强制继续计数。todo 状态是权威信号（比文本猜测可靠），
    // 单独给 3 次额度；配合 12 轮循环上限兜底，不会无限空转。
    var todoNudge = 0;
    
  
    // 动态 system prompt：技能设定放在最前，确保覆盖 Agent 默认决策表；
    // 当前题目不再注入提示词（已技能化：load_skill('exam-context') 获取）
    // 技能商店目录（渐进式披露：仅名称+触发描述，正文由 skill 工具按需加载）
    final contextPrompt = buildChatContextPrompt();
    final sysPrompt = (contextPrompt.isNotEmpty ? '$contextPrompt\n\n' : '') +
        AgentService.buildSystemPrompt(skillCatalog: skillStore.loaded ? skillStore.catalogPrompt() : null);
  
    // 构建 messages：从 chatHistory 读历史，但排除最后一条（刚加的 user 消息，避免重复）
    // R4 请求体瘦身：只保留最近约 16 条历史，较早消息剥离 imageData
    final historyLen = chatHistory.length;
    const maxHistory = 16;
    final allHistory = chatHistory
        .getRange(0, historyLen - 1)
        // 排除系统消息，但保留【早期对话摘要】（压缩工具写入的上下文）
        .where((m) => m.role != 'system' || m.content.startsWith('【早期对话摘要】'))
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
      // 用户请求暂停后的统一收尾：保留占位消息，汇报已完成动作并提示可"继续"
      ({String reply, List<String> actions}) finishAbort() {
        _chatAbortRequested = false;
        placeholder.statusLabel = null;
        final doneTxt = actions.isEmpty ? '' : '\n\n已完成：${actions.join("、")}。回复"继续"，我会接着完成剩余部分。';
        if (placeholder.content.trim().isEmpty) {
          placeholder.content = '已按你的要求暂停。$doneTxt'.trim();
        } else {
          placeholder.content = '${placeholder.content}$doneTxt';
        }
        // 未完成的步骤卡片标记为暂停态
        for (final s in placeholder.toolSteps) {
          if (s.running) {
            s.running = false;
            s.label = '已暂停';
          }
        }
        _notifyChatUpdate();
        chatSending = false;
        notifyListeners();
        return (reply: '已暂停', actions: actions);
      }

      // 最多循环 12 轮（比原先 5 轮放宽，复杂多步任务不会因轮次耗尽提前收尾）
      for (var round = 0; round < 12; round++) {
        // R10: 用户点了发送按钮的"中止"——立即跳出循环，保留已有占位消息
        if (_chatAbortRequested) {
          return finishAbort();
        }
        // R8: 每轮清零本轮工具名，本轮执行工具后填充，末尾赋给 lastRoundTools 供下轮判断
        final roundTools = <String>{};
        // 正文累积保留：模型每轮流式吐出的文字都"不被撤回"。
        // 之前每轮开头会 placeholder.content='' 清空正文，导致用户只看到最后一轮的
        // 一句话总结（中间步骤/边想边说的内容全部消失）——这正是"agent 的话被撤掉
        // 只剩一句"的来源。现在不清空，始终在已有正文上继续累加。
        final contentPrefix = placeholder.content;

        // 流式决策期间给出一句话进度（正文/步骤卡片出现后清除）
        placeholder.statusLabel = round == 0 ? '正在分析请求…' : '思考下一步（第 ${round + 1} 轮）…';
        _notifyChatUpdate();
  
        // R1: 所有轮次全部用流式调用（streamChatWithTools 现在返回 AIResponse 含 tool_calls）
        // R2: 决策轮关闭思考以加速
        String rawReasoning = '';
        String streamContent = contentPrefix;
        final resp = await ApiService.streamChatWithTools(
          messages,
          sysPrompt,
          config: cfg,
          tools: tools,
          // 思考模式开关：开启时显式请求思考过程，关闭时强制关闭以加速
          extraParams: chatThinking
              ? ApiService.thinkingParams(cfg.model)
              : ApiService.noThinkingParams(cfg.model),
          // R7: 输出上限联动上下文窗口（Max 模式 1M → 128K；普通 200K → 16K），
          // 思考模式下 reasoning 会占用输出预算，已包含在联动上限中
          maxTokens: effectiveOutputLimit,
          // 暂停按钮：流式期间逐行探测，命中立即断开
          isAborted: () => _chatAbortRequested,
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
        // 流式期间用户点了暂停：isAborted 已断开流，这里立即收尾，不再执行任何工具
        if (_chatAbortRequested) {
          return finishAbort();
        }
        placeholder.statusLabel = null;

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

        // R7: 输出被 max_tokens 截断（finish_reason='length'）且没有完整工具调用：
        // 把已输出的内容作为 assistant 消息入历史，再追加"继续"指令自动续跑，
        // 避免长任务因输出预算耗尽而"干一半就结束"。
        // 注意：思考模式下 reasoning 可能占满预算导致 content 为空，此时也要继续，
        // 让模型"不要再重复思考，直接输出正文"，而不是直接判失败。
        if (resp.finishReason == 'length' && resp.toolCalls.isEmpty) {
          messages.add({
            'role': 'assistant',
            'content': resp.content ?? '',
          });
          messages.add({
            'role': 'user',
            'content': '（你的回复因输出长度限制被截断。请不要再重复之前的思考过程，'
                '直接从中断处继续输出剩余内容或结论；如果尚未完成任务，继续调用必要的工具完成剩余步骤。）',
          });
          // 占位正文已=累积的 streamContent，直接续跑（正文本就累积保留，无需标志）
          placeholder.content = streamContent;
          _notifyChatUpdate();
          continue;
        }

        // R8/R9: "纯文本回复"分支前先检测——上一轮如果调了工具就停下，多半是假完成。
        if (resp.toolCalls.isEmpty) {
          final replyText = (resp.content ?? '').trim();

          // R8: 上一轮只调了辅助工具（load_skill/list_user_skills 等）就停 → 强制继续
          // 提醒最多追加 2 次，避免同一提醒反复堆积污染上下文、空转满 12 轮后仍落到兜底
          if (nudgeCount < 2 &&
              lastRoundTools.isNotEmpty &&
              lastRoundTools.every((n) => _helperTools.contains(n))) {
            nudgeCount++;
            messages.add({
              'role': 'user',
              'content': '（你上一轮只调用了辅助类工具（${lastRoundTools.join(", ")}），'
                  '这只是加载/查询操作，不算完成用户的请求。'
                  '请根据加载结果继续调用核心工具完成任务，例如：'
                  '• 「这道题怎么做」→ 立刻调用 get_current_question 获取题目，再基于题目作答；'
                  '• 出题相关 → 调用 generate_questions；'
                  '• 文件/代码相关 → 调用 read_file / str_replace_editor / run_code 等；'
                  '你必须真正做完实际工作并给出实质性回答后，再输出最终总结。'
                  '禁止仅以「已完成：…」开头的总结作为最终回复。）',
            });
            _notifyChatUpdate();
            continue;
          }

          // R9: 上一轮调过核心工具，但本轮只给了兜底短语 → 强制继续作答。
          // 注意：不能只按长度判定（< 60 字）——简短的正常回答（如单词释义）会被误伤，
          // 导致模型被反复追问；只有命中兜底短语特征才算假完成。
          final hasCoreTool = lastRoundTools.any((n) => !_helperTools.contains(n));
          if (hasCoreTool) {
            final looksLikeStub = replyText.startsWith('操作已完成') ||
                replyText.startsWith('已完成') ||
                replyText.startsWith('已搞定') ||
                (replyText.length < 60 &&
                    (replyText.contains('完成') || replyText.contains('搞定')));
            if (looksLikeStub && nudgeCount < 2) {
              nudgeCount++;
              messages.add({
                'role': 'user',
                'content': '（你上一轮调用的核心工具（${lastRoundTools.join(", ")}）已经返回了真实结果，'
                    '但你这次的回复仅 " $replyText "，像兜底总结。'
                    '请基于工具的真实返回内容，给用户一个完整、详细、自然的回答；'
                    '禁止用"操作已完成/已完成/已搞定"等短语作为最终回复。）',
              });
              _notifyChatUpdate();
              continue;
            }
          }

          // R11: 任务清单（todo）仍有未完成项时，"说完一句就停"属于进行到一半的中断，
          // 用 todo 状态作为权威信号强制继续，不依赖文本特征猜测。
          // 先把模型这句未完工的陈述记入历史，避免下一轮上下文相同而重复同样的话。
          final pendingTodos = placeholder.todoList
              .where((t) => t.status != 'completed')
              .map((t) => t.content)
              .toList();
          if (pendingTodos.isNotEmpty && replyText.isNotEmpty && todoNudge < 3) {
            todoNudge++;
            messages.add({
              'role': 'assistant',
              'content': replyText,
            });
            messages.add({
              'role': 'user',
              'content': '（任务清单中仍有 ${pendingTodos.length} 项未完成：${pendingTodos.join("；")}。'
                  '你刚才说 "$replyText" 就停了，工作尚未做完。'
                  '请立即继续调用工具完成剩余事项，全部完成前不要输出总结性收尾。）',
            });
            _notifyChatUpdate();
            continue;
          }

          // 真正的纯文本答复 → 当作任务完成返回
          final reply = (resp.content ?? '').trim();
          // 气泡展示用累积正文（含中间步骤/边想边说的文字），
          // 不用仅"最后一轮的 reply"覆盖，避免把中间已吐出的内容"撤回"。
          await _simulateStreamOutput(
              placeholder, streamContent.trim().isEmpty ? reply : streamContent, actions);
          return (reply: reply, actions: actions);
        }
        // 有工具调用：把 assistant 的 tool_calls 消息加入历史
        // R7: 过滤掉"只有名字没有参数"的残缺 tool_call（流被截断时常见），
        // 完整调用正常执行；残缺的不执行而是提示模型重新发起。
        // 注意：空对象 {} 是「无参数工具」（get_current_question / next_question /
        // toggle_favorite / get_progress / check_repeat / list_user_skills 等）的合法调用，
        // 绝不能当作残缺调用丢弃，否则这些工具永远无法执行、循环空转直至兜底"操作已完成"。
        // 反过来，截断的 JSON（以 { 开头但不闭合）也不能放行：parseArgs 底层的截断修复
        // 会把它补成"半个对象"去执行，导致执行结果与用户意图不符。
        bool _argsComplete(String argsJson) {
          final t = argsJson.trim();
          if (t == '{}') return true;
          if (!t.startsWith('{') || !t.endsWith('}')) return false;
          try {
            final r = jsonDecode(t);
            return r is Map<String, dynamic>;
          } catch (_) {
            return false;
          }
        }

        final validCalls =
            resp.toolCalls.where((tc) => tc.name.isNotEmpty && _argsComplete(tc.arguments)).toList();
        final brokenCalls = resp.toolCalls.length - validCalls.length;

        if (validCalls.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'content': resp.content,
            'tool_calls': validCalls
                .map((tc) => {
                      'id': tc.id,
                      'type': 'function',
                      'function': {'name': tc.name, 'arguments': tc.arguments},
                    })
                .toList(),
          });
        } else if (brokenCalls > 0) {
          // 没有任何可执行的工具调用：若模型同时输出了文字，先把文字记入历史，
          // 否则下一轮模型看到的上下文与本轮完全相同，会重复同样的输出（上下文污染）。
          final attachedText = (resp.content ?? '').trim();
          if (attachedText.isNotEmpty) {
            messages.add({
              'role': 'assistant',
              'content': attachedText,
            });
          }
          if (brokenRetry < 2) {
            // 直接提示模型参数不完整，让它重新发起（最多重试 2 次）
            brokenRetry++;
            messages.add({
              'role': 'user',
              'content': '（你发起的工具调用参数不完整（缺少必要的参数），请重新调用工具，'
                  '务必填全所有必需参数后再执行。不要回复总结性文字。）',
            });
            continue;
          }
          // 重试 2 次仍残缺：如实告知用户，不再谎报"操作已完成"
          placeholder.content = '抱歉，工具调用多次失败（参数不完整），这次没能完成你的请求。请再试一次或换个说法。';
          _notifyChatUpdate();
          chatSending = false;
          notifyListeners();
          return (reply: placeholder.content, actions: actions);
        }
        if (brokenCalls > 0 && validCalls.isNotEmpty) {
          // 部分残缺：在 tool 结果里附注，让模型知道有调用未执行
          messages.add({
            'role': 'tool',
            'tool_call_id': validCalls.first.id,
            'name': validCalls.first.name,
            'content': '（注意：你有 ${brokenCalls} 个工具调用因参数不完整未被执行，'
                '如仍有需要请重新发起完整调用。）',
          });
        }
        // 执行每个工具调用，实时更新占位消息
        for (final tc in validCalls) {
          // 暂停检查（工具粒度）：长任务里点暂停不必等当前工具整轮跑完。
          // 已发起未执行的 tool_calls 必须补上结果消息，否则 assistant 消息与
          // tool 结果数量不匹配，下一轮请求会因协议不完整被服务端拒绝。
          if (_chatAbortRequested) {
            final executedCount = validCalls.indexOf(tc);
            for (final rest in validCalls.skip(executedCount)) {
              messages.add({
                'role': 'tool',
                'tool_call_id': rest.id,
                'name': rest.name,
                'content': '（用户已暂停：本次调用未执行）',
              });
            }
            return finishAbort();
          }
          roundTools.add(tc.name);
          final args = AgentService.parseArgs(tc.arguments);
          // 工具执行前：在气泡上方添加"调用工具"步骤卡片（运行中）
          final runningLabel = _toolRunningLabel(tc.name, args);
          // bash 与 operate_computer(run_command) 一样以终端块呈现：
          // 命令、原始输出、退出码全程可见，而不是一行"执行命令"
          final isTerminal = (tc.name == 'operate_computer' && (args['operation'] as String?) == 'run_command') || tc.name == 'bash';
          final isSubagent = tc.name == 'spawn_subagent';
          final step = ToolStep(
            name: tc.name,
            label: runningLabel.isEmpty ? _toolDefaultLabel(tc.name) : runningLabel,
            input: _toolInputSummary(tc.name, args),
            terminal: isTerminal,
            command: isTerminal
                ? (tc.name == 'bash' ? ((args['command'] as String?) ?? '') : ((args['target'] as String?) ?? ''))
                : null,
            subType: isSubagent ? ((args['type'] as String?) ?? 'general') : null,
            subTask: isSubagent ? ((args['task'] as String?) ?? '') : null,
          );
          placeholder.toolSteps.add(step);
          _notifyChatUpdate();
          // 子 Agent：把执行事件实时汇入步骤卡片（AgentSubagentCard 事件流）
          final result = await executeTool(
            tc.name,
            args,
            onProgress: isSubagent
                ? (event) {
                    step.subEvents.add(event);
                    if (event['type'] == 'tool') {
                      final n = step.subEvents.where((e) => e['type'] == 'tool').length;
                      step.label = '子 Agent · 第 $n 步 · ${event['label'] ?? ''}';
                    }
                    _notifyChatUpdate();
                  }
                : null,
          );
          // 命令执行：保存退出码与原始输出，供终端块展示
          if (isTerminal) {
            step.exitCode = result.exitCode;
            final raw = result.terminalOutput ?? '';
            if (raw.isNotEmpty) step.output = raw.length > 4000 ? '${raw.substring(0, 4000)}\n…(已截断)' : raw;
          } else if (isSubagent) {
            // 子 Agent：从结果 JSON 提取最终报告，展示在卡片"报告"区
            try {
              final data = jsonDecode(result.content) as Map<String, dynamic>;
              final reply = (data['reply'] as String?) ?? (data['partial'] as String?) ?? '';
              if (reply.isNotEmpty) step.output = reply.length > 4000 ? '${reply.substring(0, 4000)}\n…(已截断)' : reply;
            } catch (_) {}
          } else {
            // 其余工具：统一提取人类可读的输出预览进 OUT 卡片
            // （此前 JSON 结果一律不展示，用户看不到读了什么文件/写了什么内容）
            final preview = _toolOutputPreview(result.content);
            if (preview.isNotEmpty) step.output = preview;
          }
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
          // R15: 记录失败的 bash 命令，供轮次耗尽时的"如实进度报告"使用
          if (tc.name == 'bash' && !result.ok) {
            final c = (args['command'] as String?) ?? '';
            if (c.isNotEmpty && !failedCmds.contains(c)) failedCmds.add(c);
          }
          _notifyChatUpdate();
          messages.add({
            'role': 'tool',
            'tool_call_id': tc.id,
            'name': tc.name,
            'content': result.content,
          });
        }
        // 记录本轮调用的所有工具名（含 helper），供下一轮判断"是否调完工具就草草收尾"
        lastRoundTools = roundTools.toList();
      }
      // 超过最大轮次的兜底：
      // 1) 占位消息里若已有模型流式输出的真实内容（如末轮回复了文本但未走 return 分支），
      //    直接保留，绝不能用"操作已完成"覆盖——这正是用户反馈"只会说操作已完成"的直接来源；
      // 2) R15: todo 未清空或有失败命令时，说明任务只做到一半——必须如实报告进度
      //    （已完成项 + 待办项 + 失败命令），并写入最终回复进入 chatHistory，
      //    这样用户回复"继续"后下一轮能看到完整进度，而不是失忆地重来；
      // 3) 只有 todo 已清空且无失败命令时才可以说"已完成"。
      final pendingTodos = placeholder.todoList
          .where((t) => t.status != 'completed')
          .map((t) => t.content)
          .toList();
      final existing = placeholder.content.trim();
      final String reply;
      if (existing.isNotEmpty) {
        reply = existing;
      } else if (pendingTodos.isNotEmpty || failedCmds.isNotEmpty) {
        final sb = StringBuffer('本轮步数已用完，任务还没做完。');
        sb.write('已完成：${actions.isEmpty ? "无" : actions.join("、")}。');
        if (pendingTodos.isNotEmpty) {
          sb.write('任务清单还有 ${pendingTodos.length} 项未完成：${pendingTodos.join("；")}。');
        }
        if (failedCmds.isNotEmpty) {
          sb.write('以下命令执行失败（请换思路，不要原样重试）：${failedCmds.take(5).join("；")}。');
        }
        sb.write('回复“继续”我会接着完成剩余部分。');
        reply = sb.toString();
      } else if (actions.isNotEmpty) {
        reply = '已完成：${actions.join("、")}。';
      } else {
        reply = '抱歉，这次处理用尽了步数仍未完成你的请求。请把需求说得更具体一些（例如指明题型、文件或页面），或再试一次。';
      }
      await _simulateStreamOutput(placeholder, reply, actions);
      return (reply: reply, actions: actions);
    } catch (e) {
      // 异常时移除占位消息，回退
      chatHistory.remove(placeholder);
      _notifyChatUpdate();
      return null;
    }
  }

  /// 工具结果的人类可读预览（OUT 卡片用）。
  /// JSON 结果按常见字段优先级提取（stdout/stderr → content → reply/summary），
  /// 提取不到就压成单行 JSON 预览；纯文本直接截断。上限 1200 字符。
  String _toolOutputPreview(String content) {
    final raw = content.trim();
    if (raw.isEmpty) return '';
    // 纯文本（skill 正文、错误说明等）：直接截断展示
    if (!raw.startsWith('{') && !raw.startsWith('[')) {
      return raw.length > 1200 ? '${raw.substring(0, 1200)}\n…(已截断)' : raw;
    }
    try {
      final obj = jsonDecode(raw);
      if (obj is Map) {
        // 命令类结果：stdout + stderr
        final stdout = (obj['stdout'] as String?) ?? '';
        final stderr = (obj['stderr'] as String?) ?? '';
        if (stdout.isNotEmpty || stderr.isNotEmpty) {
          final parts = [if (stdout.isNotEmpty) stdout, if (stderr.isNotEmpty) 'STDERR: $stderr'];
          final joined = parts.join('\n');
          return joined.length > 1200 ? '${joined.substring(0, 1200)}\n…(已截断)' : joined;
        }
        // 文件类结果：content 字段
        final fileContent = obj['content'];
        if (fileContent is String && fileContent.isNotEmpty) {
          return fileContent.length > 1200 ? '${fileContent.substring(0, 1200)}\n…(已截断)' : fileContent;
        }
        // 目录列举 / 技能清单等数组字段
        for (final key in ['entries', 'files', 'items', 'skills', 'results']) {
          final list = obj[key];
          if (list is List && list.isNotEmpty) {
            final names = list.take(12).map((e) {
              if (e is Map) return (e['name'] ?? e['id'] ?? e.toString()).toString();
              return e.toString();
            }).join('、');
            final more = list.length > 12 ? ' …等 ${list.length} 项' : '';
            return '$names$more';
          }
        }
        // 通用兜底：单行压缩 JSON
        final line = raw.replaceAll('\n', ' ');
        return line.length > 400 ? '${line.substring(0, 400)}…' : line;
      }
      if (obj is List) {
        final line = jsonEncode(obj);
        return line.length > 600 ? '${line.substring(0, 600)}…' : line;
      }
    } catch (_) {}
    final line = raw.replaceAll('\n', ' ');
    return line.length > 400 ? '${line.substring(0, 400)}…' : line;
  }

  /// 工具入参摘要（ToolRow 展开后的 IN 卡片），key: value 逐行排列
  String _toolInputSummary(String name, Map<String, dynamic> args) {
    if (args.isEmpty) return '';
    final sb = StringBuffer();
    args.forEach((k, v) {
      String val;
      if (v == null) {
        val = '';
      } else if (v is String) {
        val = v;
      } else if (v is List) {
        val = '[${v.length} 项]';
      } else if (v is Map) {
        val = '{${v.length} 项}';
      } else {
        val = v.toString();
      }
      if (val.length > 240) val = '${val.substring(0, 240)}…';
      sb.writeln('$k: $val');
    });
    return sb.toString().trimRight();
  }

  /// 工具执行中的进度文案
  String _toolRunningLabel(String name, Map<String, dynamic> args) {
    /// 取路径的最后一段（文件名/目录名），让"写入文件"变成"写入 report.md"
    String base(String? p) {
      final t = (p ?? '').trim().replaceAll('/', r'\');
      if (t.isEmpty) return '';
      return t.split(r'\').where((s) => s.isNotEmpty).last;
    }

    String clip(String s, int n) => s.length > n ? '${s.substring(0, n)}…' : s;

    switch (name) {
      case 'generate_questions':
        final type = (args['type'] as String?) ?? 'translation';
        final count = (args['count'] as num?)?.toInt() ?? 1;
        return '正在生成 $count 道${qTypeName(qTypeFrom(type))}';
      case 'submit_generated_questions':
        final qArgs = args['questions'];
        final n = qArgs is List
            ? qArgs.length
            : (qArgs is Map && qArgs['questions'] is List ? (qArgs['questions'] as List).length : 0);
        return n > 0 ? '正在整理并提交 $n 道题' : '正在生成题目';
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
      case 'goto_page':
        return '正在跳转页面';
      case 'get_wrong_questions':
        return '正在读取错题本';
      case 'get_favorites':
        return '正在读取生词本';
      case 'start_dictation':
        return '正在准备默写';
      case 'sync_maimemo':
        return '正在同步墨墨词库';
      case 'get_study_report':
        return '正在读取学习报告';
      case 'config_settings':
        final action = (args['action'] as String?) ?? 'get';
        final key = (args['key'] as String?) ?? '';
        return action == 'set' ? '正在修改设置${key.isEmpty ? '' : ' · $key'}' : '正在读取设置';
      case 'search_web':
        final q = ((args['query'] as String?) ?? '').trim();
        return q.isEmpty ? '正在联网搜索' : '正在搜索「${clip(q, 24)}」';
      case 'web_fetch':
        final url = (args['url'] as String?) ?? '';
        var host = url;
        try {
          final u = Uri.parse(url);
          host = '${u.host}${u.path == '/' || u.path.isEmpty ? '' : clip(u.path, 24)}';
        } catch (_) {}
        return host.isEmpty ? '正在抓取网页' : '正在读取 $host';
      case 'backup_data':
        return '正在备份数据';
      case 'operate_computer':
        final op = (args['operation'] as String?) ?? '';
        final target = (args['target'] as String?) ?? '';
        final desc = switch (op) {
          'open_file' => '打开文件 ${target.isNotEmpty ? '"$target"' : ''}',
          'open_folder' => '打开文件夹 ${target.isNotEmpty ? '"$target"' : ''}',
          'launch_app' => '启动应用 ${target.isNotEmpty ? '"$target"' : ''}',
          'open_url' => '打开网址 $target',
          'run_command' => '运行命令 ${target.isNotEmpty ? '"$target"' : ''}',
          _ => '正在操作电脑',
        };
        return desc.trim();
      // ===== 工作类工具：让用户一眼看出在操作哪个文件/跑什么命令 =====
      case 'bash':
        final cmd = ((args['command'] as String?) ?? '').trim().replaceAll('\n', ' ');
        final desc = ((args['description'] as String?) ?? '').trim();
        if (cmd.isNotEmpty) return clip(cmd, 56);
        if (desc.isNotEmpty) return '正在执行：$desc';
        return '正在执行命令';
      case 'run_background_job':
        final cmd = ((args['command'] as String?) ?? '').trim();
        return cmd.isEmpty ? '正在启动后台任务' : '后台任务 · ${clip(cmd, 48)}';
      case 'job_output':
        return '正在查看后台任务输出';
      case 'job_kill':
        return '正在终止后台任务';
      case 'read_file':
        final b = base(args['path'] as String?);
        return b.isEmpty ? '正在读取文件' : '正在读取 $b';
      case 'write_file':
        final b = base(args['path'] as String?);
        return b.isEmpty ? '正在写入文件' : '正在写入 $b';
      case 'edit_file':
        final b = base(args['path'] as String?);
        return b.isEmpty ? '正在编辑文件' : '正在编辑 $b';
      case 'list_dir':
        final p = base(args['path'] as String?);
        return p.isEmpty ? '正在查看目录' : '正在查看目录 $p';
      case 'str_replace_editor':
        final cmd = (args['command'] as String?) ?? '';
        final b = base(args['path'] as String?);
        final verb = switch (cmd) {
          'view' => '查看',
          'create' => '创建',
          'str_replace' => '替换',
          'insert' => '插入',
          _ => '编辑',
        };
        return b.isEmpty ? '正在$verb代码' : '正在$verb $b';
      case 'run_code':
        final d = ((args['description'] as String?) ?? '').trim();
        return d.isEmpty ? '正在执行批量操作' : '正在$d';
      case 'skill':
      case 'load_skill':
        final n = ((args['name'] as String?) ?? '').trim();
        return n.isEmpty ? '正在加载技能' : '正在加载技能「${clip(n, 20)}」';
      case 'list_user_skills':
        return '正在列出工作区技能';
      case 'session_query':
        return '正在检索历史会话';
      case 'compact_conversation':
        return '正在压缩对话上下文';
      case 'check_repeat':
        return '正在检查重复调用';
      case 'list_mcp_tools':
        return '正在查询 MCP 工具清单';
      case 'call_mcp_tool':
        final server = (args['server_name'] as String?) ?? '';
        final tool = (args['tool_name'] as String?) ?? '';
        return '$server · $tool'.isEmpty ? '正在调用 MCP 工具' : '正在调用 $server.$tool';
      case 'ask_user_question':
        return '等待你的选择…';
      case 'submit_plan':
        final t = ((args['title'] as String?) ?? '').trim();
        return t.isEmpty ? '已提交计划待审批' : '计划待审批：${clip(t, 24)}';
      case 'spawn_subagent':
        final type = (args['type'] as String?) ?? 'general';
        final label = switch (type) {
          'research' => '研究型子 Agent 出动',
          'coder' => '编码子 Agent 出动',
          _ => '通用子 Agent 出动',
        };
        final task = ((args['task'] as String?) ?? '').trim();
        return task.isEmpty ? label : '$label · ${clip(task, 28)}';
      default:
        return '正在处理';
    }
  }

  /// 工具的默认展示标签（无参数时兜底）
  String _toolDefaultLabel(String name) {
    switch (name) {
      case 'generate_questions':
        return '生成练习题';
      case 'submit_generated_questions':
        return '生成题目';
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
      case 'goto_page':
        return '跳转页面';
      case 'get_wrong_questions':
        return '读取错题本';
      case 'get_favorites':
        return '读取生词本';
      case 'start_dictation':
        return '开始默写';
      case 'sync_maimemo':
        return '同步墨墨词库';
      case 'get_study_report':
        return '读取学习报告';
      case 'config_settings':
        return '读取设置';
      case 'search_web':
        return '联网搜索';
      case 'backup_data':
        return '备份数据';
      case 'operate_computer':
        return '操控电脑';
      case 'spawn_subagent':
        return '子 Agent 执行中…';
      case 'skill':
        return '加载技能';
      case 'load_skill':
        return '加载用户技能';
      case 'list_user_skills':
        return '列出可用技能';
      case 'web_fetch':
        return '抓取网页';
      case 'read_file':
        return '读取文件';
      case 'write_file':
        return '写入文件';
      case 'edit_file':
        return '编辑文件';
      case 'list_dir':
        return '列出目录';
      case 'bash':
        return '执行命令';
      case 'str_replace_editor':
        return '编辑代码';
      case 'run_code':
        return '执行代码';
      case 'todo':
        return '更新任务清单';
      case 'session_query':
        return '查询历史会话';
      case 'list_mcp_tools':
        return '列出 MCP 工具';
      case 'call_mcp_tool':
        return '调用 MCP 工具';
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

  // ===== 联网搜索服务配置（百度千帆 AI 搜索组件） =====
  void setSearchConfig(String url, String key) {
    searchUrl = url.trim().isEmpty ? 'https://qianfan.baidubce.com/v2/ai_search/chat/completions' : url.trim();
    searchKey = key.trim();
    Storage.saveSearchUrl(searchUrl);
    Storage.saveSearchKey(searchKey);
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

  void saveChatSettings({required bool independent, required ApiConfig config, required bool showReasoning, required bool stream, required bool thinking, bool? fullAccess}) {
    chatApiIndependent = independent;
    chatApiConfig = config;
    chatShowReasoning = showReasoning;
    chatStream = stream;
    chatThinking = thinking;
    if (fullAccess != null) chatFullAccess = fullAccess;
    Storage.saveChatIndependent(independent);
    Storage.saveChatConfig(config);
    Storage.saveChatShowReasoning(showReasoning);
    Storage.saveChatStream(stream);
    Storage.saveChatThinking(thinking);
    Storage.saveChatFullAccess(chatFullAccess);
    notifyListeners();
  }

  /// 切换对话助手权限范围
  void setChatFullAccess(bool v) {
    if (chatFullAccess == v) return;
    chatFullAccess = v;
    Storage.saveChatFullAccess(v);
    notifyListeners();
  }

  /// 设置当前技能（空串 = 清除技能）
  void setActiveSkill(String id) {
    activeSkill = id;
    Storage.saveActiveSkill(id);
    notifyListeners();
  }

  /// 设置对话模式
  void setChatMode(String id) {
    chatMode = id;
    Storage.saveChatMode(id);
    notifyListeners();
  }

  /// 设置对话思考模式（Max 模式）
  void setChatThinking(bool v) {
    chatThinking = v;
    Storage.saveChatThinking(v);
    notifyListeners();
  }

  /// 设置专家角色（空串 = 默认）
  void setActiveExpert(String id) {
    activeExpert = id;
    Storage.saveActiveExpert(id);
    notifyListeners();
  }

  /// 开关联网搜索连接器
  void setSearchEnabled(bool v) {
    searchEnabled = v;
    Storage.saveSearchEnabled(v);
    notifyListeners();
  }

  /// 设置 AI 助手工作目录（harness 工具 fs root）。
  /// 设置后所有本地文件/Shell 工具只能在该目录及其子目录下操作。
  /// 传空字符串恢复默认（C:\Users 下所有位置）。
  void setWorkspacePath(String path) {
    workspacePath = path.trim();
    Storage.saveWorkspacePath(workspacePath);
    notifyListeners();
  }

  /// 解析 mcpConfigJson 为配置列表
  List<McpServerConfig> parseMcpConfigs() {
    if (mcpConfigJson.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(mcpConfigJson);
      if (list is! List) return const [];
      return list.map((e) {
        if (e is Map) return McpServerConfig.fromJson(e.cast<String, dynamic>());
        return null;
      }).whereType<McpServerConfig>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// 重新连接所有 MCP server（异步、不阻塞 UI）
  Future<void> _reconnectMcp() async {
    final configs = parseMcpConfigs();
    if (configs.isEmpty) {
      mcpTools = [];
      return;
    }
    final tools = await mcpRegistry.connectAll(configs);
    mcpTools = tools;
    notifyListeners();
  }

  /// 用户编辑 MCP 配置 JSON 后调用，重新连接
  Future<void> setMcpConfigJson(String json) async {
    mcpConfigJson = json;
    Storage.saveMcpConfigJson(json);
    await _reconnectMcp();
    notifyListeners();
  }

  /// 当前选中的技能对象（可能为 null）。同时搜索通用技能与 Agent 工具技能。
  ChatSkill? get currentSkill {
    for (final s in kAllChatSkills) {
      if (s.id == activeSkill) return s;
    }
    return null;
  }

  /// 当前专家对象（可能为 null）
  ChatExpert? get currentExpert {
    for (final e in kChatExperts) {
      if (e.id == activeExpert) return e;
    }
    return null;
  }

  /// 拼接当前技能 / 模式 / 专家的 system prompt 片段（注入到对话 system prompt）
  String buildChatContextPrompt() {
    final parts = <String>[];
    // 工作区信息必须始终注入：模型若不知道工作区根目录，文件工具会反复"路径越界"
    // 靠试错探路，浪费大量轮次甚至把任务拖到中断。
    final root = _fsRoot();
    parts.add(
      '## 当前工作区\n'
      '- 工作区根目录（绝对路径）：$root\n'
      '- 文件工具（read_file / write_file / edit_file / list_dir / str_replace_editor）'
      '支持相对路径：不以盘符开头的路径会按工作区根目录解析，例如 "src/game.ts" 即 "$root\\src\\game.ts"。\n'
      '- 一切文件的创建与修改都必须落在该工作区内，不要猜测或试探工作区之外的路径。\n'
      '- bash 的默认工作目录即工作区根目录；如需切换目录，用 `cd /d <绝对路径> && <命令>`。',
    );
    final skill = currentSkill;
    final expert = currentExpert;
    for (final m in kChatModes) {
      if (m.id == chatMode && m.prompt.isNotEmpty) parts.add(m.prompt);
    }
    if (skill != null) {
      parts.add(
        '【强制启用技能：${skill.name}】\n'
        '当前用户已明确选择「${skill.name}」技能。无论用户输入什么，你都必须优先按该技能的设定执行，'
        '${skill.toolName != null ? '并主动调用工具 ${skill.toolName}。' : '。'}\n'
        '技能说明：${skill.description}\n'
        '技能指令：${skill.prompt}',
      );
    }
    if (expert != null) parts.add(expert.prompt);
    if (parts.isEmpty) return '';
    return '\n\n## 当前能力设定（最高优先级）\n${parts.join('\n\n')}';
  }

  /// 当前激活技能的显示名称（无技能返回空串）
  String get activeSkillName {
    final skill = currentSkill;
    return skill?.name ?? '';
  }

  /// 粗略估算当前对话已用 token 数（仅用于 UI 展示，非精确值）
  int estimateChatTokens() {
    var chars = 0;
    for (final m in chatHistory) {
      chars += m.content.length;
      if (m.reasoning != null) chars += m.reasoning!.length;
    }
    // 中文字符约 1:2，其他字符约 1:4，取加权估算
    final chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(chatHistory.map((m) => m.content + (m.reasoning ?? '')).join()).length;
    final other = chars - chinese;
    return (chinese / 2).ceil() + (other / 4).ceil();
  }

  /// 上下文 token 分布（用于 UI 展示，非精确值）。窗口大小按当前模型动态估算。
  /// 将字符数粗略换算为 token 数
  int _charsToTokens(String text) {
    final chinese = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
    final other = text.length - chinese;
    return (chinese / 2).ceil() + (other / 4).ceil();
  }

  /// 估算当前系统提示词 token 数
  int _estimateSystemPromptTokens() {
    return _charsToTokens(buildChatContextPrompt());
  }

  /// 估算工具定义 token 数
  int _estimateToolsTokens() {
    try {
      final json = jsonEncode(AgentService.toolDefinitions(
        mcpTools: mcpTools
            .map((t) => {
                  'type': 'function',
                  'function': {
                    'name': 'mcp__${t.name.replaceAll(' ', '_')}',
                    'description': '[MCP] ${t.description ?? t.name}',
                    'parameters': t.inputSchema,
                  },
                })
            .toList(),
      ));
      return _charsToTokens(json);
    } catch (_) {
      return 0;
    }
  }

  /// 估算连接器配置 token 数
  int _estimateConnectorTokens() {
    if (!searchEnabled) return 0;
    return _charsToTokens('联网搜索: $searchUrl');
  }

  /// 获取上下文用量分布（已使用各分类 token 数）。窗口大小根据用户设置 + Max 模式动态决定。
  ChatTokenBreakdown contextTokenBreakdown() {
    final system = _estimateSystemPromptTokens();
    final tools = _estimateToolsTokens();
    final messages = estimateChatTokens();
    final connectors = _estimateConnectorTokens();
    // 技能/专家 prompt 已包含在 system 中，这里单拆出来用于展示
    var skill = 0;
    final sk = currentSkill;
    if (sk != null) skill += _charsToTokens(sk.prompt);
    final ex = currentExpert;
    if (ex != null) skill += _charsToTokens(ex.prompt);
    for (final m in kChatModes) {
      if (m.id == chatMode && m.prompt.isNotEmpty) skill += _charsToTokens(m.prompt);
    }
    // 修正 system：剔除已单独统计的技能/模式/专家部分
    final systemPure = (system - skill).clamp(0, system);
    return ChatTokenBreakdown(
      system: systemPure,
      tools: tools,
      messages: messages,
      connectors: connectors,
      skills: skill,
      maxTokens: effectiveContextWindow,
    );
  }

  /// 当前生效的上下文窗口长度（token 数）：
  /// - Max 模式（chatThinking=true）→ 扩展到 1000K
  /// - 否则用用户设置 apiConfig.contextLength（默认 200K）
  int get effectiveContextWindow {
    if (chatThinking) return kMaxModeContextWindow;
    final userLen = apiConfig.contextLength;
    return userLen > 0 ? userLen : 200000;
  }

  /// 输出上限（max_tokens）联动上下文窗口：
  /// - 上下文 ≥ 1M（Max 模式）→ 128K 输出
  /// - 上下文 ≥ 500K → 64K 输出
  /// - 其余（默认 200K）→ 16K 输出
  int get effectiveOutputLimit {
    final ctx = effectiveContextWindow;
    if (ctx >= 1000000) return 128000;
    if (ctx >= 500000) return 64000;
    return 16000;
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
    // 手机端：开启全屏进入沉浸式（隐藏状态栏与导航栏），关闭时恢复基于 uiMode 的模式
    if (Platform.isAndroid || Platform.isIOS) {
      if (v) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
      } else {
        _applySystemUiMode();
      }
    }
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

  /// 一键备份：电脑保存到「下载」文件夹，手机保存到应用默认文件夹。
  /// 返回保存的文件路径；失败抛异常。
  Future<String> backupData() async {
    Directory? dir;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        dir = await getExternalStorageDirectory();
      } catch (_) {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
    } else {
      dir = await getDownloadsDirectory();
      dir ??= await getApplicationDocumentsDirectory();
    }
    final name = 'afloat-backup-${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.create(recursive: true);
    await file.writeAsString(buildBackupJson());
    return file.path;
  }

  bool importBackup(String content) {
    final ok = Storage.importBackup(content);
    if (ok) {
      apiConfig = Storage.loadApiConfig();
      chatApiIndependent = Storage.loadChatIndependent();
      chatApiConfig = Storage.loadChatConfig();
      chatShowReasoning = Storage.loadChatShowReasoning();
      chatStream = Storage.loadChatStream();
      chatThinking = Storage.loadChatThinking();
      chatFullAccess = Storage.loadChatFullAccess();
      activeSkill = Storage.loadActiveSkill();
      chatMode = Storage.loadChatMode();
      activeExpert = Storage.loadActiveExpert();
      searchEnabled = Storage.loadSearchEnabled();
      searchUrl = Storage.loadSearchUrl();
      searchKey = Storage.loadSearchKey();
      devMode = Storage.loadDevMode();
      maimemoToken = Storage.loadMaimemoToken();
      maimemoLastSync = Storage.loadMaimemoLastSync();
      maimemoSyncedCount = Storage.loadMaimemoSyncedCount();
      darkMode = Storage.loadDarkMode();
      analysisMode = Storage.loadAnalysisMode();
      fullscreen = Storage.loadFullscreen();
      powerSavingMode = Storage.loadPowerSavingMode();
      highPerformanceMode = Storage.loadHighPerformanceMode();
      AppColors.highPerformance = highPerformanceMode;
      uiMode = Storage.loadUiMode();
      uiStyle = Storage.loadUiStyle();
      navIndicator = Storage.loadNavIndicator();
      apiProfiles = Storage.loadApiProfiles();
      chatProfiles = Storage.loadChatProfiles();
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
    // 同步置位：闭合“检查→延迟回调才置位”的 TOCTOU 窗口，
    // 防止 300ms 内二次点击覆盖 currentExamPaper 产生双份生成竞态
    examGeneratingBatch = true;
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
    examGenerationDone = false;
    _examFailedBatches.clear();
    examGeneratingHint = '准备进入考场...';

    // 直接进入考场（page=10）
    page = 10;
    generatingFullExam = false;
    notifyListeners();

    // 稍等考场界面渲染完成后启动并行生成（不再逐批人为延迟）
    Future.delayed(const Duration(milliseconds: 300), () {
      if (currentExamPaper != null && page == 10) {
        _runExamGeneration(_fullExamBatchPlan(), customReq);
      } else {
        // 未启动生成（已离开考场/试卷被清空）：释放守卫，避免永久卡死
        examGeneratingBatch = false;
        notifyListeners();
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
    // 注：examGeneratingBatch 已由调用方（generateFullExam 同步置位）持有；
    // 此处只拦截空计划，并在各提前退出路径负责释放守卫。
    if (plan.isEmpty) {
      examGeneratingBatch = false;
      return;
    }
    final paper = currentExamPaper;
    if (paper == null) {
      examGeneratingBatch = false;
      return;
    }
    if (!apiConfig.ready) {
      examGeneratingHint = 'API未配置，无法生成题目，请先到“设置 → AI 接口”完成配置';
      examGenerationDone = true;
      examGeneratingBatch = false;
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
  /// 大题型首次 max_tokens 升档到 200000（200k）（API 不支持/请求失败则降回 8192 重试）；
  /// finish_reason=='length' 按截断处理：先用截断修复解析尽力救回，不完整则交拆分兜底；
  /// 重试时精简 prompt 缩减输出量。返回解析产物（可能为部分题目），彻底失败返回 null。
  Future<Object?> _requestSectionWithRetry(ExamBatchSpec spec, String customReq) async {
    const maxAttempts = 2;
    final big = spec.type == 'vocab' || spec.type == 'reading' || spec.type == 'cloze';
    Object? best; // 各次尝试中救回题目最多的部分产物
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (currentExamPaper == null) return best;
      final maxTokens = (big && attempt == 1) ? 200000 : 8192;
      AIResult? res;
      try {
        res = await ApiService.callAIResult(
          [
            {'role': 'user', 'content': '请生成专升本英语题目（${spec.label}），一次生成全部 ${spec.count} 题'}
          ],
          _buildBatchPrompt(spec, customReq, attempt),
          config: apiConfig,
          maxTokens: maxTokens,
          extraParams: _questionParams(),
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
    // 出题速度为"快速"时，deepseek 等推理模型深度思考会拖慢出题：追加"跳过思考直接输出"强指令；
    // 出题速度为"正常"时保留模型深度思考能力，不加此抑制。
    if (apiConfig.questionSpeed != 'normal' &&
        ApiService.realModelName(apiConfig.model).toLowerCase().contains('deepseek')) {
      sb.writeln('【重要】不要进行任何思考或推理，不要输出思考过程，直接给出最终 JSON 结果。');
    }
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

  /// 初始化答题卡，进入沉浸考场（全卷生成完成后直接调用）
  void enterFullExam() {
    if (currentExamPaper == null) return;
    currentExamAnswerSheet = ExamAnswerSheet();
    currentExamResult = null; // 重开考试时清除上一轮成绩，保证 setPage 考场守卫生效
    examRemainingSec = currentExamPaper!.totalTimeMin * 60;
    examStartTs = DateTime.now().millisecondsSinceEpoch;
    examCurrentQuestion = 1;
    page = 10; // 沉浸考场
    notifyListeners();
  }

  /// 交卷：自动判分（客观题直接判，英译汉和写作先用关键词打分），切换到成绩页。
  /// 试卷/答题卡缺失（生成失败或被并发清空）时返回 null 而非抛异常，
  /// 避免考场页在退化路径下崩溃。
  ExamResult? submitFullExam() {
    final paper = currentExamPaper;
    final ans = currentExamAnswerSheet;
    if (paper == null || ans == null) return null;
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
        sb.writeln('【写作】满分 35 分，请按内容切题、结构组织、语言准确性、词汇句式丰富度综合评分：');
        sb.writeln('题目要求：${ws.topic}');
        sb.writeln('学生作文：${ans.writing.trim()}');
      }
      final systemPrompt = '你是专升本英语考试阅卷老师，请批改以下主观题并只返回一个 JSON 对象（不要输出其他内容），格式：\n'
          '{"translation":[{"score":0到4整数,"comment":"该句中文点评(30字内)"},共$sentCount项按句序],'
          '"writing":{"score":0到35整数,"comment":"总体中文点评(60字内)","suggestion":"改进建议(60字内)"}}\n'
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
          scores.add(sc.toInt().clamp(0, 4));
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
        wScore = (wRaw['score'] as num).toInt().clamp(0, 35);
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
        r.writingScore = wComment.isNotEmpty ? wComment : '（$wScore/35）';
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
