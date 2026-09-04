/// 多智能体编排服务：多专家团 / 辩论模式。
///
/// 两种模式都是纯对话，不调用任何工具，只做「按角色依次生成 + 上下文裁剪」。
/// - 多专家团：思路解析 → 执行 → 验证 → 二次验证，上下文上限 200K tokens
/// - 辩论模式：两个 API 交替发言若干轮，上下文上限 1M tokens
library;

import '../models.dart';
import 'api_service.dart';

/// 专家角色类型
enum AgentRoleKind {
  /// 思路解析者（必选）：拆解问题、给出可执行步骤
  analyzer,
  /// 执行者（必选）：按解析出的步骤产出最终结果
  executor,
  /// 验证者（可选，最多 2 位，串行）：只验证执行者是否符合思路解析的步骤
  verifier,
  /// 二次验证者（可选，最多 1 位）：复核从思路解析者到验证者的全部上下文
  reverifier,
}

/// 角色显示名
String agentRoleName(AgentRoleKind k) {
  switch (k) {
    case AgentRoleKind.analyzer:
      return '思路解析者';
    case AgentRoleKind.executor:
      return '执行者';
    case AgentRoleKind.verifier:
      return '验证者';
    case AgentRoleKind.reverifier:
      return '二次验证者';
  }
}

/// 一个「职位」：角色 + 该角色内的序号 + 使用的 API 配置。
/// 多个职位可以指向同一个 API（config 相同），靠 role/index 区分身份。
class AgentSeat {
  final AgentRoleKind kind;
  /// 同角色内序号，从 1 开始（验证者 1 / 验证者 2，解析者 1 / 2 / 3）
  final int index;
  /// 使用的 API 配置（null = 该职位未启用）
  ApiConfig? config;
  /// 配置名称（UI 下拉展示用）
  String profileName;

  AgentSeat({required this.kind, required this.index, this.config, this.profileName = ''});

  bool get enabled => config != null && config!.ready;

  /// 模型名（头像/标题用）
  String get model => config?.model ?? '未配置';

  /// 说话人名：「思路解析者 1 · gpt-5.1」
  String get speaker {
    final base = agentRoleName(kind);
    final needIdx = (kind == AgentRoleKind.analyzer || kind == AgentRoleKind.verifier);
    final label = needIdx ? '$base $index' : base;
    return '$label · ${config?.model ?? '未配置'}';
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'index': index,
        'profileName': profileName,
        'url': config?.url ?? '',
        'key': config?.key ?? '',
        'model': config?.model ?? '',
        'temperature': config?.temperature ?? '',
        'fullUrl': config?.fullUrl ?? false,
        'contextLength': config?.contextLength ?? 200000,
      };

  static AgentSeat fromJson(Map<String, dynamic> j) {
    final kind = AgentRoleKind.values.firstWhere(
      (e) => e.name == (j['kind'] ?? ''),
      orElse: () => AgentRoleKind.analyzer,
    );
    final url = (j['url'] ?? '') as String;
    final key = (j['key'] ?? '') as String;
    final cfg = (url.isEmpty || key.isEmpty)
        ? null
        : ApiConfig(
            url: url,
            key: key,
            model: (j['model'] ?? 'gpt-5.1') as String,
            temperature: (j['temperature'] ?? '0.3') as String,
            fullUrl: j['fullUrl'] == true,
            contextLength: (j['contextLength'] as num?)?.toInt() ?? 200000,
          );
    return AgentSeat(
      kind: kind,
      index: ((j['index'] ?? 1) as num).toInt(),
      config: cfg,
      profileName: (j['profileName'] ?? '') as String,
    );
  }
}

/// 一次发言（流式增量写入 content）
class AgentTurn {
  final AgentRoleKind kind;
  final int index;
  final String speaker;
  final String model;
  final StringBuffer _buf = StringBuffer();
  bool done = false;
  bool streaming = false;
  String? error;
  DateTime? startAt;
  DateTime? endAt;

  AgentTurn({required this.kind, required this.index, required this.speaker, required this.model});

  String get content => _buf.toString();
  void append(String s) => _buf.write(s);

  /// 辩论模式下的辩方标记（'pro' / 'con'），多专家团恒为空
  String side = '';
  /// 辩论模式下的轮次（从 1 开始）
  int round = 0;
}

/// 上下文上限
const int kExpertContextLimit = 200000;
const int kDebateContextLimit = 1000000;

/// 粗略估算 token 数：CJK 字符按 1 字 1 token，其余按 4 字符 1 token。
/// 只用于裁剪判断，不追求与真实分词一致。
int estimateTokens(String s) {
  if (s.isEmpty) return 0;
  var cjk = 0;
  for (final cu in s.runes) {
    if (cu >= 0x4E00 && cu <= 0x9FFF) cjk++;
  }
  final other = s.length - cjk;
  return cjk + (other / 4).ceil();
}

/// 把 messages 裁剪到 token 上限内：
/// 始终保留第一条（用户原始问题）与最后若干条最新内容，超限从中间最早处丢弃。
List<Map<String, dynamic>> trimMessages(List<Map<String, dynamic>> messages, int limit) {
  int total = 0;
  for (final m in messages) {
    total += estimateTokens((m['content'] ?? '').toString()) + 4;
  }
  if (total <= limit || messages.length <= 2) return messages;
  final kept = <Map<String, dynamic>>[messages.first];
  // 从最新往回保留，直到预算用尽
  var used = estimateTokens((messages.first['content'] ?? '').toString()) + 4;
  for (var i = messages.length - 1; i >= 1; i--) {
    final cost = estimateTokens((messages[i]['content'] ?? '').toString()) + 4;
    if (used + cost > limit) break;
    kept.insert(1, messages[i]);
    used += cost;
  }
  return kept;
}

class MultiAgentService {
  // ===== 角色系统提示词 =====

  /// 输出格式补充（追加到各角色提示词）：界面支持 Markdown 与 LaTeX 公式渲染
  static const String _formatHint = '\n\n输出格式：支持 Markdown（标题/列表/表格/代码块）；'
      '涉及数学内容时用 LaTeX 公式表达——行内公式用 \$...\$，独立公式用 \$\$...\$\$，系统会正确渲染。';

  static String _analyzerPrompt(int idx, int total) => total >= 2
      ? '你是【思路解析者 $idx】（共 $total 位解析者，你们各自独立解析，最终会被整合或一并交给执行者）。\n'
          '职责：把用户的问题拆解成清晰、有序、可执行的步骤。\n'
          '要求：\n'
          '1. 只做思路拆解，不要直接给出最终答案；\n'
          '2. 步骤编号排列，每步说明「做什么」和「为什么」；\n'
          '3. 指出关键难点与易错点；\n'
          '4. 使用中文，结构清晰。$_formatHint'
      : '你是【思路解析者】。\n'
          '职责：把用户的问题拆解成清晰、有序、可执行的步骤。\n'
          '要求：\n'
          '1. 只做思路拆解，不要直接给出最终答案；\n'
          '2. 步骤编号排列，每步说明「做什么」和「为什么」；\n'
          '3. 指出关键难点与易错点；\n'
          '4. 使用中文，结构清晰。$_formatHint';

  static const String _analyzerMergePrompt = '你是【思路解析整合者】（第三位解析者）。\n'
      '已有两位解析者各自给出了独立的思路解析。你的职责是整合这两份思路，'
      '取长补短、消除分歧，输出一份最终完整的思路解析，交给执行者执行。\n'
      '要求：\n'
      '1. 保留两份解析中一致且正确的部分；\n'
      '2. 对冲突之处给出明确取舍并说明理由；\n'
      '3. 输出统一的编号步骤，步骤必须具体可执行；\n'
      '4. 只输出整合后的最终解析，不要复述两份原文。$_formatHint';

  static const String _executorPrompt = '你是【执行者】。\n'
      '你会收到用户的问题和思路解析者给出的步骤。你的职责是严格按照这些步骤执行，产出最终结果。\n'
      '要求：\n'
      '1. 严格遵循思路解析的步骤顺序，不要跳步或自行改变方案；\n'
      '2. 逐步执行并给出每一步的实际产物，最后给出完整结论；\n'
      '3. 若某一步无法执行，明确指出并说明原因，不要静默略过；\n'
      '4. 使用中文。$_formatHint';

  static String _verifierPrompt(int idx) => idx == 1
      ? '你是【验证者 1】。\n'
          '职责：只验证执行者的产出是否严格符合思路解析者提出的步骤，不做额外发挥。\n'
          '要求：\n'
          '1. 逐条对照思路解析的步骤，检查执行者是否按序完成、有无跳步/偏离/错误；\n'
          '2. 明确指出不符之处（引用具体步骤号）；\n'
          '3. 给出结论：通过 / 不通过（并列出必须修正的问题）；\n'
          '4. 不要重新解答问题，只做符合性验证。$_formatHint'
      : '你是【验证者 2】（在验证者 1 之后进行二次复核）。\n'
          '职责：独立检查执行者的产出是否符合思路解析的步骤，并参考验证者 1 的结论。\n'
          '要求：\n'
          '1. 独立逐条对照思路解析步骤，不要盲从验证者 1；\n'
          '2. 若与验证者 1 结论不一致，明确指出分歧点并说明你的判断依据；\n'
          '3. 给出最终结论：通过 / 不通过。$_formatHint';

  static const String _reverifierPrompt = '你是【二次验证者】。\n'
      '职责：检查从思路解析者到验证者的全部上下文，做全局终审。\n'
      '要求：\n'
      '1. 检查思路解析本身是否完整、有无遗漏关键步骤；\n'
      '2. 检查执行者是否严格按解析执行；\n'
      '3. 检查验证者的判断是否准确、有无误判或漏判；\n'
      '4. 给出最终结论，并简要说明整条链路的质量评价；\n'
      '5. 若发现任何环节有问题，指出具体环节与修正建议。$_formatHint';

  static String _debatePrompt(String side, String topic) {
    final stance = side == 'pro' ? '正方（支持）' : '反方（反对）';
    return '你是辩论的$stance。辩题：$topic\n'
        '要求：\n'
        '1. 立场鲜明，始终维护本方观点；\n'
        '2. 针对对方上一轮发言进行有力反驳，指出其逻辑漏洞或证据不足；\n'
        '3. 论证要有依据（事实、数据、逻辑推理）；\n'
        '4. 语言精炼有力，每次发言控制在 300 字以内；\n'
        '5. 不要复述对方观点，直接进入论证与反驳。$_formatHint';
  }

  // ===== 多专家团 =====

  /// 执行多专家团流程。
  /// [onTurnStart] 某职位开始发言，[onDelta] 流式增量，[onTurnEnd] 发言结束。
  /// [isAborted] 用户中止探测（流式期间每行检查）。
  /// 返回按发言顺序排列的 turn 列表。
  static Future<List<AgentTurn>> runExpertTeam({
    required String userInput,
    required List<AgentSeat> seats,
    required void Function(AgentTurn turn) onTurnStart,
    required void Function(AgentTurn turn, String delta) onDelta,
    required void Function(AgentTurn turn) onTurnEnd,
    bool Function()? isAborted,
  }) async {
    final turns = <AgentTurn>[];
    final analyzers = seats.where((s) => s.kind == AgentRoleKind.analyzer && s.enabled).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final executors = seats.where((s) => s.kind == AgentRoleKind.executor && s.enabled).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final verifiers = seats.where((s) => s.kind == AgentRoleKind.verifier && s.enabled).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final reverifiers = seats.where((s) => s.kind == AgentRoleKind.reverifier && s.enabled).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    if (analyzers.isEmpty || executors.isEmpty) {
      throw ArgumentError('思路解析者与执行者为必选项');
    }

    bool aborted() => isAborted?.call() ?? false;

    Future<AgentTurn> runSeat(
      AgentSeat seat,
      String systemPrompt,
      List<Map<String, dynamic>> messages, {
      double temperature = 0.3,
    }) async {
      final turn = AgentTurn(
        kind: seat.kind,
        index: seat.index,
        speaker: seat.speaker,
        model: seat.model,
      );
      turn.startAt = DateTime.now();
      turn.streaming = true;
      onTurnStart(turn);
      final msgs = trimMessages(messages, kExpertContextLimit);
      // 走 streamChatWithTools：只有它支持 isAborted（用户中止时毫秒级断开）
      final resp = await ApiService.streamChatWithTools(
        msgs,
        systemPrompt,
        config: seat.config,
        temperature: temperature,
        onDelta: (chunk) {
          turn.append(chunk);
          onDelta(turn, chunk);
        },
        isAborted: aborted,
      );
      final content = resp.content ?? '';
      // 流式回调可能漏掉末段（网关不回 [DONE] 等），以返回值为准补齐
      if (content.length > turn.content.length) {
        final tail = content.substring(turn.content.length);
        turn.append(tail);
        onDelta(turn, tail);
      }
      turn.streaming = false;
      turn.done = true;
      turn.endAt = DateTime.now();
      if (turn.content.trim().isEmpty) {
        turn.error = ApiService.lastError ?? '无响应';
      }
      onTurnEnd(turn);
      turns.add(turn);
      return turn;
    }

    Map<String, dynamic> userMsg(String text) => {'role': 'user', 'content': text};
    Map<String, dynamic> asstMsg(String text) => {'role': 'assistant', 'content': text};

    // ===== 阶段一：思路解析 =====
    String analysis = '';
    if (analyzers.length == 1) {
      final t = await runSeat(
        analyzers.first,
        _analyzerPrompt(1, 1),
        [userMsg(userInput)],
        temperature: 0.3,
      );
      if (aborted()) return turns;
      analysis = t.content;
    } else {
      // 第 1、2 位并行解析
      final parallel = analyzers.take(2).toList();
      final results = await Future.wait(parallel.map((seat) {
        final idx = seat.index;
        return runSeat(
          seat,
          _analyzerPrompt(idx, parallel.length),
          [userMsg(userInput)],
          temperature: 0.3,
        );
      }));
      if (aborted()) return turns;
      final a1 = results[0].content;
      final a2 = results.length > 1 ? results[1].content : '';
      final merger = analyzers.length >= 3 ? analyzers[2] : null;
      if (merger != null) {
        // 第 3 位整合前两位，产出最终解析
        final mergeMsgs = [
          userMsg(userInput),
          asstMsg('【解析者 ${parallel[0].index} 的思路】\n$a1'),
          asstMsg('【解析者 ${parallel[1].index} 的思路】\n$a2'),
          userMsg('请整合以上两份思路，输出最终完整的思路解析。'),
        ];
        final t = await runSeat(merger, _analyzerMergePrompt, mergeMsgs, temperature: 0.3);
        if (aborted()) return turns;
        analysis = t.content;
      } else {
        // 无整合者：两份解析一并交给执行者
        analysis = '【解析者 ${parallel[0].index} 的思路】\n$a1\n\n【解析者 ${parallel[1].index} 的思路】\n$a2';
      }
    }

    // ===== 阶段二：执行 =====
    final execMsgs = [
      userMsg(userInput),
      asstMsg('【思路解析结果】\n$analysis'),
      userMsg('请严格按照上述思路解析的步骤执行，给出最终结果。'),
    ];
    final execSeat = executors.first;
    final execTurn = await runSeat(execSeat, _executorPrompt, execMsgs, temperature: 0.3);
    if (aborted()) return turns;
    final execution = execTurn.content;

    // ===== 阶段三：验证（串行，后者可见前者结论） =====
    final verifyLog = <String>[];
    for (final seat in verifiers.take(2)) {
      final msgs = <Map<String, dynamic>>[
        userMsg(userInput),
        asstMsg('【思路解析结果】\n$analysis'),
        asstMsg('【执行者产出】\n$execution'),
      ];
      for (final v in verifyLog) {
        msgs.add(asstMsg(v));
      }
      msgs.add(userMsg('请验证执行者的产出是否符合思路解析提出的步骤。'));
      final t = await runSeat(seat, _verifierPrompt(seat.index), msgs, temperature: 0.2);
      if (aborted()) return turns;
      verifyLog.add('【${seat.speaker} 的结论】\n${t.content}');
    }

    // ===== 阶段四：二次验证（复核全链路） =====
    for (final seat in reverifiers.take(1)) {
      final msgs = <Map<String, dynamic>>[
        userMsg(userInput),
        asstMsg('【思路解析结果】\n$analysis'),
        asstMsg('【执行者产出】\n$execution'),
      ];
      for (final v in verifyLog) {
        msgs.add(asstMsg(v));
      }
      msgs.add(userMsg('请检查以上从思路解析到验证的全部上下文，给出最终审核结论。'));
      await runSeat(seat, _reverifierPrompt, msgs, temperature: 0.2);
      if (aborted()) return turns;
    }

    return turns;
  }

  // ===== 辩论模式 =====

  /// 执行辩论：正方先立论，反方驳论，之后交替进行 [rounds] 轮。
  static Future<List<AgentTurn>> runDebate({
    required String topic,
    required AgentSeat pro,
    required AgentSeat con,
    required int rounds,
    required void Function(AgentTurn turn) onTurnStart,
    required void Function(AgentTurn turn, String delta) onDelta,
    required void Function(AgentTurn turn) onTurnEnd,
    bool Function()? isAborted,
  }) async {
    final turns = <AgentTurn>[];
    bool aborted() => isAborted?.call() ?? false;
    final history = <Map<String, dynamic>>[];

    Future<AgentTurn> speak(AgentSeat seat, String side, int round) async {
      final turn = AgentTurn(
        kind: AgentRoleKind.executor, // 辩论模式不套用专家角色，仅用于承载数据
        index: side == 'pro' ? 0 : 1,
        speaker: seat.speaker,
        model: seat.model,
      );
      turn.side = side;
      turn.round = round;
      turn.startAt = DateTime.now();
      turn.streaming = true;
      onTurnStart(turn);
      final body = <Map<String, dynamic>>[
        {'role': 'user', 'content': '辩题：$topic'},
        ...history,
        {
          'role': 'user',
          'content': side == 'pro'
              ? (round == 1 ? '请作为正方进行开篇立论。' : '请作为正方，针对反方上一轮发言进行反驳。')
              : (round == 1 ? '请作为反方进行开篇驳论。' : '请作为反方，针对正方上一轮发言进行反驳。'),
        },
      ];
      final resp = await ApiService.streamChatWithTools(
        trimMessages(body, kDebateContextLimit),
        _debatePrompt(side, topic),
        config: seat.config,
        temperature: 0.6,
        onDelta: (chunk) {
          turn.append(chunk);
          onDelta(turn, chunk);
        },
        isAborted: aborted,
      );
      final content = resp.content ?? '';
      if (content.length > turn.content.length) {
        final tail = content.substring(turn.content.length);
        turn.append(tail);
        onDelta(turn, tail);
      }
      turn.streaming = false;
      turn.done = true;
      turn.endAt = DateTime.now();
      if (turn.content.trim().isEmpty) {
        turn.error = ApiService.lastError ?? '无响应';
      }
      onTurnEnd(turn);
      turns.add(turn);
      if (turn.content.trim().isNotEmpty) {
        history.add({
          'role': 'assistant',
          'content': '[${side == 'pro' ? '正方' : '反方'}·第 $round 轮] ${turn.content}',
        });
      }
      return turn;
    }

    for (var r = 1; r <= rounds; r++) {
      await speak(pro, 'pro', r);
      if (aborted()) break;
      await speak(con, 'con', r);
      if (aborted()) break;
    }
    return turns;
  }
}
