/// 辩论模式：选择 2 个 API 作为正反方，就一个辩题交替发言。
///
/// 纯对话，不调用工具。正方先立论，反方驳论，之后按轮次交替。
/// UI 约定：全页不使用图标，双方靠内置品牌头像 + 模型名 + 正方/反方色块区分。
/// 上下文上限 1M tokens。
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

class DebatePage extends StatefulWidget {
  const DebatePage({super.key});

  @override
  State<DebatePage> createState() => _DebatePageState();
}

class _DebatePageState extends State<DebatePage> {
  final TextEditingController _topic = TextEditingController();
  final ScrollController _scroll = ScrollController();

  ApiConfig? _pro;
  ApiConfig? _con;
  int _rounds = 3;
  final List<AgentTurn> _turns = [];
  bool _running = false;
  bool _abort = false;
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
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
    _topic.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 可选 API 来源：设置「模型设置」里保存的预设配置库（apiProfiles）；
  /// 主设置为空时回退到对话助手的独立配置（chatProfiles），保证一定能选到模型
  List<ApiProfile> get _profiles {
    final s = AppScope.of(context);
    return s.apiProfiles.isNotEmpty ? s.apiProfiles : s.chatProfiles;
  }

  void _load() {
    final raw = Storage.loadDebateSetup();
    if (raw.isEmpty) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _rounds = ((j['rounds'] ?? 3) as num).toInt().clamp(1, 10);
      final profiles = _profiles;
      if (profiles.isNotEmpty) {
        final pi = profiles.indexWhere((p) => p.name == (j['pro'] ?? ''));
        final ci = profiles.indexWhere((p) => p.name == (j['con'] ?? ''));
        if (pi >= 0) _pro = profiles[pi].config;
        if (ci >= 0) _con = profiles[ci].config;
      }
    } catch (_) {}
  }

  void _save() {
    final profiles = _profiles;
    String nameOf(ApiConfig? cfg) {
      if (cfg == null) return '';
      final i = profiles.indexWhere((p) => p.config.url == cfg.url && p.config.key == cfg.key);
      return i >= 0 ? profiles[i].name : '';
    }

    Storage.saveDebateSetup(jsonEncode({
      'pro': nameOf(_pro),
      'con': nameOf(_con),
      'rounds': _rounds,
    }));
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

  Future<void> _start() async {
    final topic = _topic.text.trim();
    if (topic.isEmpty || _running) return;
    if (_pro == null || _con == null) {
      setState(() => _error = '请分别为正方和反方选择 API');
      return;
    }
    setState(() {
      _running = true;
      _abort = false;
      _error = null;
      _turns.clear();
    });
    final proSeat = AgentSeat(
      kind: AgentRoleKind.executor,
      index: 0,
      config: _pro,
      profileName: '正方',
    );
    final conSeat = AgentSeat(
      kind: AgentRoleKind.executor,
      index: 1,
      config: _con,
      profileName: '反方',
    );
    try {
      await MultiAgentService.runDebate(
        topic: topic,
        pro: proSeat,
        con: conSeat,
        rounds: _rounds,
        onTurnStart: (t) => setState(() => _turns.add(t)),
        // 增量内容已写入 turn.content，这里只触发重建让文本刷新到界面
        onDelta: (_, __) {
          if (mounted) setState(() {});
        },
        onTurnEnd: (_) {
          if (mounted) setState(() {});
          _scrollToEnd();
        },
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
      if (_error != null) _buildErrorBar(),
      _buildTopicBar(c, dark),
    ]);
  }

  // ===== 顶部：正反方 + 轮次（纯文字，无图标） =====
  Widget _buildSetupBar(AppColors c, bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('辩论模式',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(width: 8),
          Text('正方立论 → 反方驳论 → 交替攻辩',
              style: TextStyle(fontSize: 11, color: c.textTertiary)),
          const Spacer(),
          Text('上下文上限 1M',
              style: TextStyle(fontSize: 11, color: c.textTertiary)),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _sideSelector('正方', _pro, c, dark, (v) {
              setState(() {
                _pro = v;
                _error = null;
              });
              _save();
            }),
            const SizedBox(width: 8),
            _sideSelector('反方', _con, c, dark, (v) {
              setState(() {
                _con = v;
                _error = null;
              });
              _save();
            }),
            const SizedBox(width: 8),
            _roundsSelector(c),
          ]),
        ),
      ]),
    );
  }

  Widget _sideSelector(String side, ApiConfig? current, AppColors c, bool dark, ValueChanged<ApiConfig?> onPick) {
    final profiles = _profiles;
    final currentIdx = current == null
        ? -1
        : profiles.indexWhere((p) => p.config.url == current.url && p.config.key == current.key);
    final accent = side == '正方' ? kSuccess : kDanger;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: current == null ? c.chipUnselected : c.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: current == null ? accent.withValues(alpha: 0.5) : accent.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(side,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
        const SizedBox(height: 2),
        SizedBox(
          width: 156,
          height: 30,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: currentIdx < 0 ? -1 : currentIdx,
              isDense: true,
              isExpanded: true,
              style: TextStyle(fontSize: 12, color: c.text),
              dropdownColor: c.cardSolid,
              items: [
                const DropdownMenuItem<int>(
                    value: -1, child: Text('选择 API', style: TextStyle(fontSize: 12))),
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
              ],
              // 收起态只显示模型名
              selectedItemBuilder: (_) => [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('选择 API', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ),
                for (final p in profiles)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(p.config.model,
                        style: TextStyle(fontSize: 12, color: c.text), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _running
                  ? null
                  : (v) => onPick(v == null || v < 0 ? null : profiles[v].config),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _roundsSelector(AppColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: c.chipUnselected,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('轮次', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.textSecondary)),
        const SizedBox(height: 2),
        SizedBox(
          height: 30,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rounds,
              isDense: true,
              style: TextStyle(fontSize: 12, color: c.text),
              dropdownColor: c.cardSolid,
              items: [
                for (final r in const [1, 2, 3, 4, 5, 6, 8, 10])
                  DropdownMenuItem<int>(value: r, child: Text('$r 轮', style: const TextStyle(fontSize: 12))),
              ],
              onChanged: _running
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _rounds = v);
                      _save();
                    },
            ),
          ),
        ),
      ]),
    );
  }

  // ===== 发言流：正方靠左、反方靠右 =====
  Widget _buildTurnList(AppColors c, bool dark) {
    if (_turns.isEmpty && !_running) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('选择正反方后输入辩题，开始辩论',
                style: TextStyle(fontSize: 14, color: c.textSecondary)),
            const SizedBox(height: 6),
            Text('双方各自保留立场，每轮针对对方上一轮发言反驳',
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
    final isPro = t.side == 'pro';
    final accent = isPro ? kSuccess : kDanger;
    return Align(
      alignment: isPro ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              AiAvatar(model: t.model, size: 22, dark: dark),
              const SizedBox(width: 7),
              Text(t.model,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${isPro ? '正方' : '反方'} · 第 ${t.round} 轮',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: accent)),
              ),
            ]),
            const SizedBox(height: 7),
            if (t.content.isEmpty && t.streaming)
              Text('正在发言…', style: TextStyle(fontSize: 13, color: c.textTertiary))
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
        ),
      ),
    );
  }

  Widget _buildErrorBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: kDanger.withValues(alpha: 0.1),
      child: Text(_error!, style: const TextStyle(fontSize: 12, color: kDanger)),
    );
  }

  // ===== 底部：辩题输入 =====
  Widget _buildTopicBar(AppColors c, bool dark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: TextField(
            controller: _topic,
            minLines: 1,
            maxLines: 4,
            enabled: !_running,
            style: TextStyle(fontSize: 13.5, color: c.text),
            decoration: InputDecoration(
              hintText: '输入辩题，例如：AI 是否会取代教师',
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
            onSubmitted: (_) => _start(),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: TextButton(
            onPressed: _running ? () => setState(() => _abort = true) : _start,
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
