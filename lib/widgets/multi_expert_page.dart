/// 多专家团模式：纯对话，多角色按序协作。
///
/// 角色链：思路解析者（1~3 位）→ 执行者（1 位）→ 验证者（0~2 位，串行）→ 二次验证者（0~1 位）。
/// 必选：思路解析者 + 执行者。每个职位独立选择已配置的 API，可重复选用同一个。
/// UI 约定：全页不使用任何图标，AI 身份靠内置品牌头像 + 模型名 + 角色名区分。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../state.dart';
import '../theme_colors.dart';
import '../services/multi_agent_service.dart';
import '../services/storage.dart';
import 'ai_avatar.dart';
import 'markdown_renderer.dart';

class MultiExpertPage extends StatefulWidget {
  const MultiExpertPage({super.key});

  @override
  State<MultiExpertPage> createState() => _MultiExpertPageState();
}

class _MultiExpertPageState extends State<MultiExpertPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 职位列表（固定顺序：解析1/解析2/解析3 → 执行 → 验证1/验证2 → 二次验证）
  late List<AgentSeat> _seats;
  final List<AgentTurn> _turns = [];
  bool _running = false;
  bool _abort = false;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _seats = _defaultSeats();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 读取已保存配置依赖 AppScope，必须等依赖就绪后再加载（initState 阶段不可用）
    if (!_loaded) {
      _loaded = true;
      _load();
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<AgentSeat> _defaultSeats() => [
        AgentSeat(kind: AgentRoleKind.analyzer, index: 1),
        AgentSeat(kind: AgentRoleKind.analyzer, index: 2),
        AgentSeat(kind: AgentRoleKind.analyzer, index: 3),
        AgentSeat(kind: AgentRoleKind.executor, index: 1),
        AgentSeat(kind: AgentRoleKind.verifier, index: 1),
        AgentSeat(kind: AgentRoleKind.verifier, index: 2),
        AgentSeat(kind: AgentRoleKind.reverifier, index: 1),
      ];

  /// 恢复上次配置：按 kind+index 匹配（不按下标，避免顺序变动错位）
  void _load() {
    final raw = Storage.loadExpertSeats();
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List?;
      if (list == null) return;
      for (final e in list) {
        final seat = AgentSeat.fromJson(e as Map<String, dynamic>);
        final i = _seats.indexWhere((s) => s.kind == seat.kind && s.index == seat.index);
        if (i >= 0) _seats[i] = seat;
      }
    } catch (_) {}
  }

  void _save() {
    Storage.saveExpertSeats(jsonEncode(_seats.map((e) => e.toJson()).toList()));
  }

  /// 可选 API 来源：设置「模型设置」里保存的预设配置库（apiProfiles）；
  /// 主设置为空时回退到对话助手的独立配置（chatProfiles），保证一定能选到模型
  List<ApiProfile> get _profiles {
    final s = AppScope.of(context);
    return s.apiProfiles.isNotEmpty ? s.apiProfiles : s.chatProfiles;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _run() async {
    final text = _input.text.trim();
    if (text.isEmpty || _running) return;
    final hasAnalyzer = _seats.any((s) => s.kind == AgentRoleKind.analyzer && s.enabled);
    final hasExecutor = _seats.any((s) => s.kind == AgentRoleKind.executor && s.enabled);
    if (!hasAnalyzer || !hasExecutor) {
      setState(() => _error = '思路解析者与执行者为必选项，请先为它们选择 API');
      return;
    }
    setState(() {
      _running = true;
      _abort = false;
      _error = null;
      _turns.clear();
    });
    _input.clear();

    void onStart(AgentTurn t) => setState(() => _turns.add(t));
    // 增量内容已写入 turn.content，这里只触发重建让文本刷新到界面
    void onDelta(AgentTurn _, String __) {
      if (mounted) setState(() {});
    }

    void onEnd(AgentTurn _) {
      if (mounted) setState(() {});
      _scrollToEnd();
    }

    try {
      await MultiAgentService.runExpertTeam(
        userInput: text,
        seats: _seats,
        onTurnStart: onStart,
        onDelta: onDelta,
        onTurnEnd: onEnd,
        isAborted: () => _abort,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(children: [
      _buildSetupBar(c, dark),
      const Divider(height: 1),
      Expanded(child: _buildTurnList(c, dark)),
      if (_error != null) _buildErrorBar(c),
      _buildInputBar(c, dark),
    ]);
  }

  // ===== 顶部：职位配置（纯文字，无图标） =====
  Widget _buildSetupBar(AppColors c, bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('多专家团',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(width: 8),
          Text('思路解析 → 执行 → 验证 → 二次验证',
              style: TextStyle(fontSize: 11, color: c.textTertiary)),
          const Spacer(),
          Text('上下文上限 200K',
              style: TextStyle(fontSize: 11, color: c.textTertiary)),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final seat in _seats) ...[
              _seatChip(seat, c, dark),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      ]),
    );
  }

  /// 单个职位选择块：角色名 + 下拉选择 API
  Widget _seatChip(AgentSeat seat, AppColors c, bool dark) {
    final profiles = _profiles;
    final enabled = seat.enabled;
    final required = seat.kind == AgentRoleKind.analyzer && seat.index == 1 ||
        seat.kind == AgentRoleKind.executor;
    final label = (seat.kind == AgentRoleKind.analyzer || seat.kind == AgentRoleKind.verifier)
        ? '${agentRoleName(seat.kind)} ${seat.index}'
        : agentRoleName(seat.kind);
    // 下拉项：0=未启用，其后为设置里保存的各预设（主行显示模型名，副行显示配置名）
    final items = <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(value: -1, child: Text('未启用', style: TextStyle(fontSize: 12))),
      for (var i = 0; i < profiles.length; i++)
        DropdownMenuItem<int>(
          value: i,
          child: Row(children: [
            AiAvatar(model: profiles[i].config.model, size: 20, dark: dark),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(profiles[i].config.model,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  if (profiles[i].name.isNotEmpty && profiles[i].name != profiles[i].config.model)
                    Text(profiles[i].name,
                        style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),
        ),
    ];
    // 收起态只显示模型名（保持职位块紧凑）
    final selectedItems = <Widget>[
      const Align(
        alignment: Alignment.centerLeft,
        child: Text('未启用', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ),
      for (final p in profiles)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(p.config.model,
              style: TextStyle(fontSize: 12, color: c.text), overflow: TextOverflow.ellipsis),
        ),
    ];
    final currentIdx = seat.config == null
        ? -1
        : profiles.indexWhere((p) => p.config.url == seat.config!.url && p.config.key == seat.config!.key);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: enabled ? c.inputFill : c.chipUnselected,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? c.primary.withValues(alpha: 0.45)
              : (required ? kDanger.withValues(alpha: 0.5) : c.border),
          width: required && !enabled ? 1.4 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: enabled ? c.text : c.textTertiary)),
          if (required)
            const Text(' 必选', style: TextStyle(fontSize: 10, color: kDanger)),
        ]),
        const SizedBox(height: 2),
        SizedBox(
          width: 156,
          height: 30,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: currentIdx < 0 ? -1 : currentIdx,
              items: items,
              selectedItemBuilder: (_) => selectedItems,
              isDense: true,
              isExpanded: true,
              style: TextStyle(fontSize: 12, color: c.text),
              dropdownColor: c.cardSolid,
              onChanged: _running
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        if (v < 0) {
                          seat.config = null;
                          seat.profileName = '';
                        } else {
                          seat.config = profiles[v].config;
                          seat.profileName = profiles[v].name;
                        }
                        _error = null;
                      });
                      _save();
                    },
            ),
          ),
        ),
      ]),
    );
  }

  // ===== 消息流 =====
  Widget _buildTurnList(AppColors c, bool dark) {
    if (_turns.isEmpty && !_running) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('配置好各职位后，输入你的问题',
                style: TextStyle(fontSize: 14, color: c.textSecondary)),
            const SizedBox(height: 6),
            Text('思路解析者会先拆解步骤，执行者按步骤执行，验证者逐条核对',
                style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
          ]),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      itemCount: _turns.length,
      itemBuilder: (ctx, i) => _turnCard(_turns[i], c, dark),
    );
  }

  Widget _turnCard(AgentTurn t, AppColors c, bool dark) {
    final (b1, _) = aiBrandColorsFor(t.model);
    final accent = dark ? Color.lerp(b1, Colors.white, 0.35)! : b1;
    final roleLabel = switch (t.kind) {
      AgentRoleKind.analyzer => '思路解析者 ${t.index}',
      AgentRoleKind.executor => '执行者',
      AgentRoleKind.verifier => '验证者 ${t.index}',
      AgentRoleKind.reverifier => '二次验证者',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AiAvatar(model: t.model, size: 24, dark: dark),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t.model,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.text),
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(roleLabel,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: accent)),
          ),
        ]),
        const SizedBox(height: 8),
        if (t.content.isEmpty && t.streaming)
          Text('正在生成…', style: TextStyle(fontSize: 13, color: c.textTertiary))
        else
          SelectableText.rich(
            MarkdownRenderer.parse(t.content, c.text),
            style: TextStyle(fontSize: 13, height: 1.55, color: c.text),
          ),
        if (t.error != null) ...[
          const SizedBox(height: 6),
          Text('出错：${t.error}', style: const TextStyle(fontSize: 11.5, color: kDanger)),
        ],
      ]),
    );
  }

  Widget _buildErrorBar(AppColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: kDanger.withValues(alpha: 0.1),
      child: Text(_error!, style: const TextStyle(fontSize: 12, color: kDanger)),
    );
  }

  // ===== 输入栏 =====
  Widget _buildInputBar(AppColors c, bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 5,
            enabled: !_running,
            style: TextStyle(fontSize: 13.5, color: c.text),
            decoration: InputDecoration(
              hintText: '输入你要解决的问题…',
              hintStyle: TextStyle(fontSize: 13, color: c.hintText),
              filled: true,
              fillColor: c.inputFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.primary),
              ),
            ),
            onSubmitted: (_) => _run(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: TextButton(
            onPressed: _running ? () => setState(() => _abort = true) : _run,
            style: TextButton.styleFrom(
              backgroundColor: _running ? c.chipUnselected : c.primary,
              foregroundColor: _running ? c.textSecondary : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(_running ? '中止' : '开始', style: const TextStyle(fontSize: 13.5)),
          ),
        ),
      ]),
    );
  }
}
