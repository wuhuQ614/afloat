// 复刻 deepseek-harness 的 Agent 对话行样式：
// 思考(Think / ReasoningRow)、工具调用(ToolRow)、命令/终端(IN-OUT 卡片)、
// 以及进行中的 "深入分析中…" 回合状态(TurnStatus)。
//
// 关键设计点（与 deepseek-harness 完全一致）：
//   1) 行是"无容器的纯单行"： [16 leading] gap6 [标题 14/24] gap8 [2x2 分隔点]
//      gap8 [摘要 tertiary 省略] [chevron]，行高 24，不套边框、不套背景盒。
//   2) 运行中：一行 60% 的背景亮片从左到右掠过行内容（2.6s ease-out）。
//   3) 展开体：思考体缩进 22px + tertiary；工具体为终端/IN-OUT 卡片
//      （code-block 底色、12px 圆角、l1 边框、等宽文本）。
//
// 色彩直接用目标文件的 bluish 灰阶色板，随明暗主题切换，与主 App 隔离。

import 'package:flutter/material.dart';
import 'dart:async' show Timer;

/// deepseek-harness 的 bluish 中性灰阶色板（对应 design-platform.css 静态色）
class _Ds {
  _Ds(this.light);
  final bool light;
  static Color _rgb(int r, int g, int b) => Color.fromARGB(255, r, g, b);

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
  /// 卡片 1px 边框
  Color get border => light ? _rgb(228, 229, 233) : _rgb(46, 47, 54);
  /// state-error-primary
  Color get error => light ? _rgb(236, 19, 19) : _rgb(242, 90, 90);
  /// 成功对勾
  Color get success => const Color(0xFF22C55E);
}

/// 运行亮片：60% bg-base 的渐变带从左掠过行内容（clip 边界之外不可见）。
Widget _sweepBand(Color bg, double progress, double width) {
  const bandW = 80.0;
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

/// 带可选运行亮片 + 只读点击透明的单行承载器（行高 24）
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

/// 思考行（ReasoningRow / "Think"）：标题 + 分隔点 + 摘要(省略) + 折叠展开。
/// 运行中摘要跟随最新一行并播放亮片。
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
      SizedBox(
        width: 16,
        height: 16,
        child: Icon(Icons.psychology_alt_outlined, size: 15, color: d.tertiary),
      ),
      const SizedBox(width: 6),
      Text('思考', style: TextStyle(fontSize: 14, height: 24 / 14, color: d.secondary)),
      Container(
        width: 2,
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: d.caption),
      ),
      Expanded(
        child: Text(
          summary,
          style: TextStyle(fontSize: 14, height: 24 / 14, color: d.tertiary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 4),
      Icon(_open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: d.secondary),
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

/// 工具调用行（ToolRow）：wrench + 函数名 + 分隔点 + 摘要 + 状态点 + 折叠。
/// 运行中播放亮片；命令/联网工具展开后呈现终端(IN-OUT)卡片。
class AgentToolRow extends StatefulWidget {
  final String name;
  final String label;
  final bool running;
  final bool done;
  final bool failed;
  final String? output;
  final Color accent;
  final bool light;
  const AgentToolRow({
    super.key,
    required this.name,
    required this.label,
    required this.running,
    required this.done,
    required this.failed,
    this.output,
    required this.accent,
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
    // 工具完成后停止亮片
    if (!widget.running && _c.isAnimating) {
      _c.stop();
      _c.value = 1.0;
    } else if (widget.running && !_c.isAnimating) {
      _c.repeat();
    }
  }
  void _sync() {
    if (!_c.isAnimating) _c.repeat();
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _hasBody => widget.output != null && widget.output!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final d = _Ds(widget.light);
    final iconColor = widget.failed ? d.error : widget.accent;
    final summaryColor = widget.failed ? d.error : d.tertiary;
    final header = Row(children: [
      SizedBox(
        width: 16,
        height: 16,
        child: Icon(Icons.build, size: 14, color: iconColor),
      ),
      const SizedBox(width: 6),
      Text(widget.name.isEmpty ? '工具' : widget.name,
          style: TextStyle(fontSize: 14, height: 24 / 14, color: d.secondary)),
      Container(
        width: 2,
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(shape: BoxShape.circle, color: d.caption),
      ),
      Expanded(
        child: Text(
          widget.label,
          style: TextStyle(fontSize: 14, height: 24 / 14, color: summaryColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      // 状态点
      if (widget.running)
        const SizedBox(width: 12, height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
      else if (widget.failed)
        Icon(Icons.error_rounded, size: 14, color: d.error)
      else if (widget.done)
        Icon(Icons.check_circle_rounded, size: 14, color: d.success),
      if (widget.running) const SizedBox(width: 4),
      if (_hasBody) ...[
        const SizedBox(width: 4),
        Icon(_open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 18, color: d.secondary),
      ],
    ]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _hasBody ? () => setState(() => _open = !_open) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _rowShell(child: header, running: widget.running, ctrl: _c, d: d),
          // 展开的终端 / IN-OUT 卡片
          if (_open && _hasBody)
            Container(
              margin: const EdgeInsets.only(left: 22, top: 4, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: d.codeBlock,
                border: Border.all(color: d.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    widget.output!,
                    style: TextStyle(
                      fontSize: 12,
                      height: 22 / 12,
                      color: widget.failed ? d.error : d.secondary,
                      fontFamily: 'Courier New',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 对话进行中（正在生成/思考/调用工具）时消息流底部的回合状态行。
/// 仿 deepseek-harness `TurnStatus`：流光标题 + 超过 15s 显示已用时长。
class AgentDeepDivingRow extends StatefulWidget {
  final Color accent;
  final bool light;
  const AgentDeepDivingRow({super.key, required this.accent, required this.light});
  @override
  State<AgentDeepDivingRow> createState() => _AgentDeepDivingRowState();
}

class _AgentDeepDivingRowState extends State<AgentDeepDivingRow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _elapsed++));
  }
  @override
  void dispose() {
    _ctrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  String get _clock {
    final s = _elapsed % 60;
    final m = (_elapsed ~/ 60).clamp(0, 99);
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _Ds(widget.light);
    final base = widget.accent.withValues(alpha: 0.45);
    final shimmer = AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = _ctrl.value;
        final start = -1.0 + (t * 2.0);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(start, 0),
            end: Alignment(start + 0.7, 0),
            colors: [base, widget.accent, base],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(bounds),
          child: Text(
            '深入分析中…',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: widget.accent),
          ),
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(children: [
        SizedBox(
          width: 7,
          height: 7,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: widget.accent),
        ),
        const SizedBox(width: 8),
        shimmer,
        if (_elapsed >= 15) ...[
          const SizedBox(width: 8),
          Text(_clock,
              style: TextStyle(fontSize: 11.5, color: d.caption, fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ]),
    );
  }
}