// 复刻 deepseek-harness 的 Agent 对话行样式：
// 思考(Think / ReasoningRow)、工具调用(ToolRow + IN/OUT 卡片)、
// 命令执行(TerminalBlock：提示符行 + 状态点 + 退出码)、
// 以及进行中的 "深入分析中…" 回合状态(TurnStatus)。
//
// 关键设计点（与 deepseek-harness 一致）：
//   1) 行是"无容器的纯单行"： [16 leading] gap6 [标题 14/24] gap8 [2x2 分隔点]
//      gap8 [摘要 tertiary 省略] [chevron]，行高 24，不套边框、不套背景盒。
//   2) 运行中：一条渐变亮片从左到右掠过行内容（2.6s ease-out infinite）。
//   3) 思考行：运行中摘要跟随最新一行；完成后显示第一行，可点击展开全文
//      （展开体缩进 22px + tertiary 14/24）。
//   4) 工具行：运行/完成保留工具图标；失败时 leading 换红色 StateDot、摘要变红。
//      展开后为 IN/OUT 卡片（code-block 底色、12px 圆角、l1 边框、12/18 等宽字）。
//   5) 命令执行用 TerminalBlock：左侧状态点 + "~ ❯ 命令" 提示符行（等宽、不换行
//      可横向滚动），运行中蓝色像素追逐点 + "运行中"；失败红色点 + "退出码 N"；
//      成功绿色点。输出区 maxHeight 224，白底 pre 文本。
//   6) StateDot：10x10（10% 光晕 + 6x6 实心核），ongoing 为 3x3 像素环追逐动画。
//
// 色彩用 harness design-platform.css 的 bluish 灰阶色板，随明暗主题切换。

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math' as math;
import '../state.dart'
    show
        AppScope,
        AskUserQuestion,
        ChatMessage,
        PlanSubmission,
        TodoItem;
import 'source_viewer_page.dart';

/// deepseek-harness 的 bluish 中性灰阶色板（对应 design-platform.css 静态色）
class _Ds {
  _Ds(this.light);
  final bool light;
  static Color _rgb(int r, int g, int b) => Color.fromARGB(255, r, g, b);

  /// label-primary
  Color get primary => light ? _rgb(15, 17, 21) : _rgb(249, 250, 251);
  /// label-secondary
  Color get secondary => light ? _rgb(97, 102, 107) : _rgb(207, 211, 214);
  /// label-tertiary
  Color get tertiary => light ? _rgb(129, 133, 140) : _rgb(173, 178, 184);
  /// label-caption
  Color get caption => light ? _rgb(173, 178, 184) : _rgb(129, 133, 140);
  /// bg-base（用于运行亮片 wash）
  Color get bgBase => light ? _rgb(255, 255, 255) : _rgb(21, 21, 23);
  /// markdown-code-block（终端/IN-OUT 卡片底色）
  Color get codeBlock => light ? _rgb(249, 250, 251) : _rgb(27, 27, 28);
  /// 卡片 1px 边框（border-l1）
  Color get border => light ? _rgb(228, 229, 233) : _rgb(46, 47, 54);
  /// 分隔线（border-l2）
  Color get borderL2 => light ? const Color(0x1A000000) : const Color(0x1FFFFFFF);
  /// state-error-primary
  Color get error => light ? _rgb(236, 19, 19) : _rgb(242, 90, 90);
  /// state-success-primary
  Color get success => const Color(0xFF22C55E);
  /// state-warn-primary（stopped）
  Color get warn => const Color(0xFFF59E0B);
  /// ongoing 蓝（deepseek-450）
  Color get ongoing => const Color(0xFF5686FE);
}

/// 等宽字体（终端 / IN-OUT 卡片）：12/18，对齐 harness markdown-code-block-small
TextStyle _mono(_Ds d, {Color? color}) => TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const ['Courier New', 'Microsoft YaHei'],
      fontSize: 12,
      height: 18 / 12,
      color: color ?? d.secondary,
    );

/// 运行亮片：渐变带从左掠过行内容（2.6s ease-out，clip 边界之外不可见）
Widget _sweepBand(Color bg, double progress, double width) {
  final bandW = math.min(300.0, math.max(80.0, width * 0.35));
  final t = Curves.easeOut.transform(progress);
  final x = -bandW + (t * (width + 2 * bandW));
  return Positioned(
    top: 0,
    bottom: 0,
    left: x,
    width: bandW,
    child: IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.6), bg.withValues(alpha: 0)],
          ),
        ),
      ),
    ),
  );
}

/// 带可选运行亮片的单行承载器（行高 24）
Widget _rowShell({required Widget child, required bool running, required AnimationController ctrl, required _Ds d}) {
  final base = SizedBox(height: 24, width: double.infinity, child: child);
  if (!running) return base;
  return LayoutBuilder(builder: (ctx, cons) {
    final w = cons.maxWidth;
    return SizedBox(
      height: 24,
      width: w,
      child: ClipRect(
        child: Stack(children: [
          Positioned.fill(child: child),
          AnimatedBuilder(animation: ctrl, builder: (_, __) => _sweepBand(d.bgBase, ctrl.value, w)),
        ]),
      ),
    );
  });
}

/// 行首折叠箭头
Widget _chevron(bool open, _Ds d) =>
    Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 16, color: d.caption);

/// 2x2 分隔点
Widget _sepDot(_Ds d) => Container(
      width: 2,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(shape: BoxShape.circle, color: d.caption),
    );

// ---------------------------------------------------------------------------
// StateDot：10x10 状态点（ongoing=蓝色像素追逐 / done=绿 / error=红 / warning=琥珀）
// ---------------------------------------------------------------------------

/// 3x3 像素环（外圈 8 格）追逐动画画笔
class _PixelChasePainter extends CustomPainter {
  _PixelChasePainter(this.t, this.color);
  final double t;
  final Color color;
  // 外圈 8 格，顺时针
  static const _xs = [0, 1, 2, 2, 2, 1, 0, 0];
  static const _ys = [0, 0, 0, 1, 2, 2, 2, 1];

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 2.0;
    const gap = 1.0;
    for (var i = 0; i < 8; i++) {
      final lit = ((t * 8) - i) % 8;
      final a = (1 - lit / 4).clamp(0.15, 1.0);
      canvas.drawRect(
        Offset(_xs[i] * (cell + gap), _ys[i] * (cell + gap)) & const Size(cell, cell),
        Paint()..color = color.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(_PixelChasePainter old) => old.t != t || old.color != color;
}

/// 仿 harness StateDot。[state]：ongoing / done / error / warning
class AgentStateDot extends StatefulWidget {
  final String state;
  final bool light;
  const AgentStateDot({super.key, required this.state, required this.light});
  @override
  State<AgentStateDot> createState() => _AgentStateDotState();
}

class _AgentStateDotState extends State<AgentStateDot> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  @override
  void initState() {
    super.initState();
    if (widget.state == 'ongoing') {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AgentStateDot old) {
    super.didUpdateWidget(old);
    if (widget.state == 'ongoing' && _c == null) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();
    } else if (widget.state != 'ongoing' && _c != null) {
      _c!.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _Ds(widget.light);
    if (widget.state == 'ongoing') {
      return SizedBox(
        width: 10,
        height: 10,
        child: Center(
          child: SizedBox(
            width: 8,
            height: 8,
            child: AnimatedBuilder(
              animation: _c!,
              builder: (_, __) => CustomPaint(painter: _PixelChasePainter(_c!.value, d.ongoing)),
            ),
          ),
        ),
      );
    }
    final c = switch (widget.state) {
      'error' => d.error,
      'warning' => d.warn,
      _ => d.success,
    };
    return SizedBox(
      width: 10,
      height: 10,
      child: Stack(children: [
        Positioned.fill(
          child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.10))),
        ),
        Positioned(
          left: 2,
          top: 2,
          width: 6,
          height: 6,
          child: Container(decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 思考行（ReasoningRow / "Think"）
// ---------------------------------------------------------------------------

/// 思考行：图标 + 标题"思考" + 分隔点 + 摘要(省略) + 折叠展开。
/// 运行中摘要跟随最新一行并播放亮片；完成后显示第一行，可展开全文。
class AgentThinkRow extends StatefulWidget {
  final String text;
  final bool running;
  final bool light;
  const AgentThinkRow({super.key, required this.text, required this.running, required this.light});
  @override
  State<AgentThinkRow> createState() => _AgentThinkRowState();
}

class _AgentThinkRowState extends State<AgentThinkRow> with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    _sync();
  }

  @override
  void didUpdateWidget(covariant AgentThinkRow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.running) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _firstLine() {
    final i = widget.text.indexOf('\n');
    return i == -1 ? widget.text : widget.text.substring(0, i);
  }

  String _latestLine() {
    final visible = widget.text.trimRight();
    final i = visible.lastIndexOf('\n');
    return i == -1 ? visible : visible.substring(i + 1);
  }

  @override
  Widget build(BuildContext context) {
    final d = _Ds(widget.light);
    final summary = widget.running ? _latestLine() : _firstLine();
    final header = Row(children: [
      Text('思考', style: TextStyle(fontSize: 14, height: 24 / 14, color: d.secondary)),
      _sepDot(d),
      Expanded(
        child: Text(
          summary,
          style: TextStyle(fontSize: 14, height: 24 / 14, color: d.tertiary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 4),
      _chevron(_open, d),
    ]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rowShell(child: header, running: widget.running, ctrl: _c, d: d),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
              child: Text(
                widget.text,
                style: TextStyle(fontSize: 14, height: 24 / 14, color: d.tertiary),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 工具调用行（ToolRow + IN/OUT 卡片）
// ---------------------------------------------------------------------------

/// 按工具名取图标（仿 harness 每工具独立图标）
IconData _toolIcon(String name) => switch (name) {
      'generate_questions' => Icons.edit_note_rounded,
      'submit_generated_questions' => Icons.playlist_add_check_rounded,
      'generate_full_exam' => Icons.description_rounded,
      'lookup_word' => Icons.search_rounded,
      'analyze_words' => Icons.spellcheck_rounded,
      'get_current_question' => Icons.visibility_rounded,
      'next_question' => Icons.skip_next_rounded,
      'toggle_favorite' => Icons.star_rounded,
      'get_progress' => Icons.query_stats_rounded,
      'goto_page' => Icons.open_in_new_rounded,
      'get_wrong_questions' => Icons.list_alt_rounded,
      'get_favorites' => Icons.bookmark_rounded,
      'start_dictation' => Icons.edit_rounded,
      'sync_maimemo' => Icons.sync_rounded,
      'get_study_report' => Icons.assessment_rounded,
      'config_settings' => Icons.settings_rounded,
      'search_web' => Icons.public_rounded,
      'backup_data' => Icons.cloud_upload_rounded,
      'operate_computer' => Icons.terminal_rounded,
      'read_file' => Icons.description_outlined,
      'write_file' => Icons.note_add_rounded,
      'edit_file' => Icons.drive_file_rename_outline_rounded,
      'list_dir' => Icons.folder_open_rounded,
      'bash' => Icons.terminal_rounded,
      'str_replace_editor' => Icons.data_object_rounded,
      'run_code' => Icons.code_rounded,
      'todo' => Icons.checklist_rounded,
      'skill' => Icons.auto_awesome_rounded,
      'load_skill' => Icons.auto_awesome_outlined,
      'list_user_skills' => Icons.library_books_outlined,
      'web_fetch' => Icons.language_rounded,
      'session_query' => Icons.history_rounded,
      'spawn_subagent' => Icons.account_tree_rounded,
      'list_mcp_tools' => Icons.hub_outlined,
      'call_mcp_tool' => Icons.hub_rounded,
      'ask_user_question' => Icons.help_outline_rounded,
      'compact_conversation' => Icons.compress_rounded,
      'submit_plan' => Icons.fact_check_outlined,
      'run_background_job' => Icons.play_circle_outline_rounded,
      'job_output' => Icons.output_rounded,
      'job_kill' => Icons.stop_circle_outlined,
      'check_repeat' => Icons.repeat_rounded,
      _ => Icons.build_rounded,
    };

/// IN/OUT 卡片内的一个分区
Widget _ioSection(String tag, String text, Color color, _Ds d) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tag, style: TextStyle(fontSize: 12, height: 1.5, color: d.caption)),
      const SizedBox(height: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 150),
        child: SingleChildScrollView(child: Text(text, style: _mono(d, color: color))),
      ),
    ]),
  );
}

/// 工具调用行：[工具图标] + 工具名 + 分隔点 + 摘要 + 折叠箭头。
/// 运行中播放亮片；失败时 leading 换红色 StateDot、摘要变红。
/// 展开后呈现 IN（入参）/ OUT（返回）卡片。
///
/// 文件类工具（read_file/write_file/str_view 等）若带路径，会在行下方渲染
/// 一个可点击的「打开源码」链接，直接以该文件 + 行号区间跳转源码查看器。
/// （源码查看入口走这里，不再放在「更多功能」。）
class AgentToolRow extends StatefulWidget {
  final String name;
  final String label;
  final bool running;
  final bool done;
  final bool failed;
  final String? input;
  final String? output;
  final bool light;
  const AgentToolRow({
    super.key,
    required this.name,
    required this.label,
    required this.running,
    required this.done,
    required this.failed,
    this.input,
    this.output,
    required this.light,
  });
  @override
  State<AgentToolRow> createState() => _AgentToolRowState();
}

class _AgentToolRowState extends State<AgentToolRow> with SingleTickerProviderStateMixin {
  bool _open = false;
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    _sync();
  }

  @override
  void didUpdateWidget(covariant AgentToolRow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.running) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _notEmpty(String? s) => s != null && s.trim().isNotEmpty;
  bool get _expandable => _notEmpty(widget.input) || _notEmpty(widget.output);

  // ============ 源码引用检测（文件工具 + 路径 + 行区间 → 可点击跳转） ============

  String? _toolPath() {
    const fileTools = {
      'read_file',
      'write_file',
      'edit_file',
      'str_write_to_file',
      'str_replace_editor',
      'str_view',
      'view_file',
      'list_file',
    };
    if (!fileTools.contains(widget.name)) return null;
    final input = widget.input ?? '';
    if (input.trim().isEmpty) return null;
    try {
      final map = jsonDecode(input);
      if (map is Map) {
        final p = map['file_path'] ?? map['path'];
        if (p is String && p.trim().isNotEmpty) return p.trim();
      }
    } catch (_) {}
    return null;
  }

  /// 解析行区间：[from, to]（1 起）。优先取入参 view_range，其次正则兜底。
  (int?, int?) _toolRange() {
    final input = widget.input ?? '';
    try {
      final map = jsonDecode(input);
      if (map is Map && map['view_range'] is List) {
        final l = map['view_range'] as List;
        if (l.isNotEmpty && l.first is num) {
          final f = (l.first as num).round();
          final t = l.length > 1 && l[1] is num ? (l[1] as num).round() : f;
          return (f < 1 ? 1 : f, t >= f ? t : f);
        }
      }
    } catch (_) {}
    // 兜底：从 label/output 里找 "X-Y 行" 或 "L123" 或 "第 X 行"
    final hay = '${widget.label}\n${widget.output ?? ''}';
    final dash = RegExp(r'(\d+)\s*[-–—]\s*(\d+)').firstMatch(hay);
    if (dash != null) {
      final f = int.tryParse(dash.group(1) ?? '');
      final t = int.tryParse(dash.group(2) ?? '');
      if (f != null) {
        final start = f < 1 ? 1 : f;
        final end = (t == null || t < start) ? start : t;
        return (start, end);
      }
    }
    final li = RegExp(r'L(\d+)', caseSensitive: false).firstMatch(hay);
    if (li != null) {
      final f = int.tryParse(li.group(1) ?? '');
      if (f != null) return (f < 1 ? 1 : f, f);
    }
    return (null, null);
  }

  /// 相对路径→绝对路径（无盘符时基于工作区根目录解析），与文件工具保持一致
  String _viewerPath(String p) {
    if (p.contains(':')) return p.replaceAll('/', '\\');
    final rel = p.replaceAll('/', '\\').replaceFirst(RegExp(r'^\\+'), '');
    final ws = AppScope.of(context).workspacePath.trim();
    return ws.isEmpty ? rel : '$ws\\$rel';
  }

  Widget _buildSourceLink(d) {
    final path = _toolPath();
    if (path == null) return const SizedBox.shrink();
    final (from, to) = _toolRange();
    final absolute = _viewerPath(path);
    final basename = absolute.split(RegExp(r'[\\/]')).last;
    final rangeTxt = from != null ? ' · L$from${(to ?? from) > from ? '-$to' : ''}' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 3, 8, 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SourceViewerPage(
              initialPath: absolute,
              lineFrom: from,
              lineTo: to,
            ),
          ));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: d.codeBlock,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: d.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.code_rounded, size: 13, color: d.ongoing),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '打开源码 · $basename$rangeTxt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: d.ongoing),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 12, color: d.ongoing),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _Ds(widget.light);
    final header = Row(children: [
      SizedBox(
        width: 16,
        height: 16,
        child: widget.failed
            ? Center(child: AgentStateDot(state: 'error', light: widget.light))
            : Icon(_toolIcon(widget.name), size: 14, color: d.secondary),
      ),
      const SizedBox(width: 6),
      Text(
        widget.name.isEmpty ? '工具' : widget.name.replaceAll('_', ' '),
        style: TextStyle(fontSize: 14, height: 24 / 14, color: d.secondary),
      ),
      _sepDot(d),
      Expanded(
        child: Text(
          widget.label,
          style: TextStyle(fontSize: 14, height: 24 / 14, color: widget.failed ? d.error : d.tertiary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (_expandable) ...[
        const SizedBox(width: 4),
        _chevron(_open, d),
      ],
    ]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _expandable ? () => setState(() => _open = !_open) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rowShell(child: header, running: widget.running, ctrl: _c, d: d),
          if (_toolPath() != null) _buildSourceLink(d),
          if (_open && _expandable)
            Container(
              margin: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: d.codeBlock,
                border: Border.all(color: d.border),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (_notEmpty(widget.input)) _ioSection('IN', widget.input!, d.secondary, d),
                if (_notEmpty(widget.input) && _notEmpty(widget.output))
                  Divider(height: 1, thickness: 1, color: d.borderL2),
                if (_notEmpty(widget.output))
                  _ioSection('OUT', widget.output!, widget.failed ? d.error : d.secondary, d),
              ]),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 子 Agent 派发卡片（仿 dsh ui-subagent：StateDot 状态 + 任务头 + 事件流）
// ---------------------------------------------------------------------------

/// spawn_subagent 的专属卡片：头部（类型徽章 + 任务摘要 + 状态点），
/// 展开后是子 Agent 的工具调用事件流与最终报告。
class AgentSubagentCard extends StatefulWidget {
  final String type; // general / research / coder
  final String task;
  final String label; // 进度摘要（"子 Agent 执行中 · 第 N 步" / 完成文案）
  final bool running;
  final bool done;
  final bool failed;
  final List<Map<String, dynamic>> events;
  final String? output; // OUT 卡片内容（最终报告等）
  final bool light;
  const AgentSubagentCard({
    super.key,
    required this.type,
    required this.task,
    required this.label,
    required this.running,
    required this.done,
    required this.failed,
    required this.events,
    this.output,
    required this.light,
  });
  @override
  State<AgentSubagentCard> createState() => _AgentSubagentCardState();
}

class _AgentSubagentCardState extends State<AgentSubagentCard> with SingleTickerProviderStateMixin {
  bool _open = true;
  late final AnimationController _c;
  static const _maxVisibleEvents = 8;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    _sync();
  }

  @override
  void didUpdateWidget(covariant AgentSubagentCard old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.running) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _typeLabel => switch (widget.type) {
        'research' => '研究',
        'coder' => '编码',
        _ => '通用',
      };

  IconData get _typeIcon => switch (widget.type) {
        'research' => Icons.travel_explore_rounded,
        'coder' => Icons.code_rounded,
        _ => Icons.smart_toy_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final d = _Ds(widget.light);
    final toolEvents = widget.events.where((e) => e['type'] == 'tool').toList();
    final visible = toolEvents.length > _maxVisibleEvents ? toolEvents.sublist(toolEvents.length - _maxVisibleEvents) : toolEvents;
    final taskBrief = widget.task.length > 60 ? '${widget.task.substring(0, 60)}…' : widget.task;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 头部行：图标 + 类型徽章 + 任务摘要 + 状态
      _rowShell(
        ctrl: _c,
        d: d,
        running: widget.running,
        child: Row(children: [
          SizedBox(
            width: 16,
            height: 16,
            child: widget.failed
                ? Center(child: AgentStateDot(state: 'error', light: widget.light))
                : widget.done
                    ? Center(child: AgentStateDot(state: 'done', light: widget.light))
                    : Icon(_typeIcon, size: 14, color: d.ongoing),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: widget.failed ? d.error.withValues(alpha: 0.08) : d.ongoing.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text('子 Agent · $_typeLabel', style: TextStyle(fontSize: 10.5, height: 1.4, fontWeight: FontWeight.w600, color: widget.failed ? d.error : d.ongoing)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.running ? (widget.label.isEmpty ? '执行中…' : widget.label) : widget.label,
              style: TextStyle(fontSize: 13, height: 24 / 13, color: widget.failed ? d.error : d.secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          _chevron(_open, d),
        ]),
      ),
      // 任务描述 + 事件流卡片
      if (_open)
        Container(
          margin: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
          decoration: BoxDecoration(
            color: d.codeBlock,
            border: Border.all(color: d.border),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 任务
            if (taskBrief.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(taskBrief, style: TextStyle(fontSize: 12, height: 1.6, color: d.tertiary)),
              ),
            // 事件流：最近 N 条工具调用（运行中的带追逐点）
            if (visible.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('执行轨迹${toolEvents.length > _maxVisibleEvents ? '（最近 $_maxVisibleEvents / 共 ${toolEvents.length} 步）' : '（${toolEvents.length} 步）'}', style: TextStyle(fontSize: 11, height: 1.5, color: d.caption)),
              ),
              for (var i = 0; i < visible.length; i++)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: AgentStateDot(
                        state: visible[i]['status'] == 'running' ? 'ongoing' : (visible[i]['status'] == 'fail' ? 'error' : 'done'),
                        light: widget.light,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${visible[i]['name']} · ${visible[i]['label'] ?? ''}',
                        style: TextStyle(fontSize: 12, height: 1.6, color: visible[i]['status'] == 'fail' ? d.error : d.secondary),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
            ],
            // 最终报告
            if ((widget.output ?? '').trim().isNotEmpty) ...[
              Divider(height: 1, thickness: 1, color: d.borderL2),
              _ioSection('报告', widget.output!, widget.failed ? d.error : d.secondary, d),
            ],
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 命令执行块（TerminalBlock）
// ---------------------------------------------------------------------------

/// AI 提问卡片（dsh-tool-ask-user）：让用户从 2-4 个选项中选择
class AgentAskUserPanel extends StatefulWidget {
  final List<AskUserQuestion> questions;
  final Map<String, List<String>> answers;
  final ChatMessage msgRef;
  final bool light;
  const AgentAskUserPanel({super.key, required this.questions, required this.answers, required this.msgRef, this.light = false});

  @override
  State<AgentAskUserPanel> createState() => _AgentAskUserPanelState();
}

class _AgentAskUserPanelState extends State<AgentAskUserPanel> {
  void _toggle(AskUserQuestion q, String label) {
    setState(() {
      final current = List<String>.from(widget.answers[q.id] ?? const <String>[]);
      if (q.multiSelect) {
        if (current.contains(label)) {
          current.remove(label);
        } else {
          current.add(label);
        }
      } else {
        current
          ..clear()
          ..add(label);
      }
      widget.answers[q.id] = current;
      widget.msgRef.askAnswers = Map<String, List<String>>.from(widget.answers);
    });
  }

  void _confirmAll() {
    final summary = <String>[];
    for (final q in widget.questions) {
      final sel = widget.answers[q.id] ?? const <String>[];
      summary.add('${q.id}: ${sel.isEmpty ? "(未选)" : sel.join(", ")}');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已选择：${summary.join(" | ")}', style: const TextStyle(fontSize: 12)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.light ? const Color(0xFF7C3AED) : const Color(0xFFA78BFA);
    final textPrimary = widget.light ? const Color(0xFF1F2937) : const Color(0xFFE4E4E8);
    final textSecondary = widget.light ? const Color(0xFF6B7280) : const Color(0xFFADADB8);
    final borderColor = widget.light ? const Color(0xFFE5E7EB) : const Color(0xFF3D3D45);
    final cardBg = widget.light ? const Color(0xFFF7F8FA) : const Color(0xFF26262C);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final q in widget.questions) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(q.header ?? '提问', style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(q.question, style: TextStyle(fontSize: 13, color: textPrimary, fontWeight: FontWeight.w600, height: 1.4)),
                ),
                if (q.multiSelect)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('多选', style: TextStyle(fontSize: 9, color: Color(0xFFADADB8))),
                  ),
              ]),
            ),
            for (final opt in q.options)
              InkWell(
                onTap: () => _toggle(q, opt.label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: (widget.answers[q.id] ?? const []).contains(opt.label) ? accent : Colors.transparent,
                        border: Border.all(color: (widget.answers[q.id] ?? const []).contains(opt.label) ? accent : borderColor, width: 1.4),
                        borderRadius: BorderRadius.circular(q.multiSelect ? 3 : 7),
                      ),
                      child: (widget.answers[q.id] ?? const []).contains(opt.label)
                          ? Icon(Icons.check_rounded, size: 10, color: Colors.white)
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(opt.label, style: TextStyle(fontSize: 13, color: textPrimary)),
                        if (opt.description != null && opt.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(opt.description!, style: TextStyle(fontSize: 11, color: textSecondary, height: 1.4)),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
          ],
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: _confirmAll,
              child: const Text('已选择', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// AI 计划卡片（dsh-plan-mode）：标题 + 步骤列表 + 批准/拒绝按钮
class AgentPlanPanel extends StatefulWidget {
  final PlanSubmission plan;
  final bool light;
  const AgentPlanPanel({super.key, required this.plan, this.light = false});

  @override
  State<AgentPlanPanel> createState() => _AgentPlanPanelState();
}

class _AgentPlanPanelState extends State<AgentPlanPanel> {
  bool _decided = false;

  void _decide(String status, [String? note]) {
    setState(() {
      widget.plan.status = status;
      widget.plan.userNote = note;
      _decided = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('计划已${status == 'approved' ? '批准' : status == 'rejected' ? '拒绝' : '修改'}', style: const TextStyle(fontSize: 12)),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.light ? const Color(0xFF7C3AED) : const Color(0xFFA78BFA);
    final textPrimary = widget.light ? const Color(0xFF1F2937) : const Color(0xFFE4E4E8);
    final textSecondary = widget.light ? const Color(0xFF6B7280) : const Color(0xFFADADB8);
    final cardBg = widget.light ? const Color(0xFFF7F8FA) : const Color(0xFF26262C);
    final borderColor = widget.light ? const Color(0xFFE5E7EB) : const Color(0xFF3D3D45);
    final accent2 = widget.plan.status == 'approved'
        ? const Color(0xFF10B981)
        : widget.plan.status == 'rejected'
            ? const Color(0xFFEF4444)
            : accent;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent2.withValues(alpha: 0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            Icon(Icons.assignment_outlined, size: 14, color: accent2),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.plan.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textPrimary))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: accent2.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
              child: Text(_decided ? widget.plan.status : '待审批', style: TextStyle(fontSize: 10, color: accent2, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        if (widget.plan.summary != null && widget.plan.summary!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text(widget.plan.summary!, style: TextStyle(fontSize: 12, color: textSecondary, height: 1.4)),
          ),
        for (final s in widget.plan.steps)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
                child: Text('${s.step}', style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.action, style: TextStyle(fontSize: 13, color: textPrimary, height: 1.4)),
                  if (s.tools.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(spacing: 4, runSpacing: 4, children: s.tools.map((t) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(border: Border.all(color: borderColor), borderRadius: BorderRadius.circular(3)),
                          child: Text(t, style: TextStyle(fontSize: 10, color: textSecondary)),
                        );
                      }).toList()),
                    ),
                  if (s.output != null && s.output!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('→ ${s.output}', style: TextStyle(fontSize: 11, color: textSecondary, fontStyle: FontStyle.italic)),
                    ),
                ]),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (!_decided) ...[
              TextButton(onPressed: () => _decide('rejected'), child: const Text('拒绝', style: TextStyle(fontSize: 12, color: Color(0xFFEF4444)))),
              const SizedBox(width: 4),
              TextButton(onPressed: () => _decide('modified', '需要调整'), child: const Text('需修改', style: TextStyle(fontSize: 12))),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () => _decide('approved'),
                style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6)),
                child: const Text('批准并执行', style: TextStyle(fontSize: 12)),
              ),
            ] else
              Text(
                widget.plan.userNote != null ? '你的意见：${widget.plan.userNote}' : '',
                style: TextStyle(fontSize: 11, color: textSecondary, fontStyle: FontStyle.italic),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// 任务清单块（dsh-tool-todo）：○/●/✓ + content，in_progress 高亮，completed 划掉
class AgentTodoList extends StatelessWidget {
  final List<TodoItem> items;
  final bool light;
  const AgentTodoList({super.key, required this.items, this.light = false});

  @override
  Widget build(BuildContext context) {
    final accent = light ? const Color(0xFF7C3AED) : const Color(0xFFA78BFA);
    final textPrimary = light ? const Color(0xFF1F2937) : const Color(0xFFE4E4E8);
    final textTertiary = light ? const Color(0xFF6B7280) : const Color(0xFF85859A);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((t) {
          final done = t.status == 'completed';
          final active = t.status == 'in_progress';
          return Padding(
            padding: const EdgeInsets.only(left: 0, top: 1, bottom: 1),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: done
                        ? accent.withValues(alpha: 0.18)
                        : (active ? accent.withValues(alpha: 0.12) : Colors.transparent),
                    shape: BoxShape.circle,
                    border: Border.all(color: done || active ? accent : textTertiary, width: 1.4),
                  ),
                  child: done
                      ? Icon(Icons.check_rounded, size: 10, color: accent)
                      : active
                          ? null
                          : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.content,
                  style: TextStyle(
                    fontSize: 13,
                    color: done ? textTertiary : textPrimary,
                    height: 1.4,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: textTertiary,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

/// 终端命令执行块：[状态点] "~ ❯ 命令" 提示符行 + 输出区。
/// 运行中：蓝色像素追逐点 + "运行中"；失败：红点 + "退出码 N"；成功：绿点。
class AgentTerminalBlock extends StatelessWidget {
  final String command;
  final bool running;
  final bool failed;
  final int? exitCode;
  final String? output;
  final bool light;
  const AgentTerminalBlock({
    super.key,
    required this.command,
    required this.running,
    required this.failed,
    this.exitCode,
    this.output,
    required this.light,
  });

  @override
  Widget build(BuildContext context) {
    final d = _Ds(light);
    final dotState = running ? 'ongoing' : (failed ? 'error' : 'done');
    final hasOut = output != null && output!.trim().isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      decoration: BoxDecoration(
        color: d.codeBlock,
        border: Border.all(color: d.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 提示符行：状态点 + "~ ❯ 命令"（等宽、不换行可横向滚动）+ 状态文案
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
          child: Row(children: [
            AgentStateDot(state: dotState, light: light),
            const SizedBox(width: 8),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '~ ❯ ', style: _mono(d, color: d.tertiary)),
                  TextSpan(text: command, style: _mono(d, color: d.primary)),
                ])),
              ),
            ),
            if (running) ...[
              const SizedBox(width: 8),
              Text('运行中', style: TextStyle(fontSize: 11, color: d.caption)),
            ] else if (failed) ...[
              const SizedBox(width: 8),
              Text(
                exitCode != null ? '退出码 $exitCode' : '执行失败',
                style: TextStyle(fontSize: 11, color: d.error),
              ),
            ],
          ]),
        ),
        if (hasOut && !running) Divider(height: 1, thickness: 1, color: d.borderL2),
        if (hasOut)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 224),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(30, 12, 14, 12),
                  child: Text(output!, style: _mono(d, color: d.secondary)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// 回合状态行（TurnStatus）—— 已移除"深入分析中…"纯文本标签，
// 实际 agent 循环中的进度完全由气泡下方 ToolStep 行 / Reasoning 行承担。
// 这里保留一个最小占位（高 4），方便以后需要动画时直接接回。
// ---------------------------------------------------------------------------

/// 回合收尾的小间距占位（取代旧的"深入分析中…"文字行）
class AgentDeepDivingRow extends StatelessWidget {
  final Color accent;
  final bool light;
  const AgentDeepDivingRow({super.key, required this.accent, required this.light});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 4);
  }
}
