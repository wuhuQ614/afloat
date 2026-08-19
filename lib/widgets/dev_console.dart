/// 全局开发者控制台：在开发者模式下，右下角提供入口按钮，点击展开全屏
/// 终端风格的日志浮层，实时展示 AI 后台出题的思维链（reasoning_content）与输出文本。
/// 放置于 main.dart 根层 Stack，可覆盖答题/翻译题、单词查询、词汇剖析、考场等所有页面。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state.dart';

/// 开发者控制台入口（右下角按钮 + 全屏日志浮层）。
/// 非开发者模式下返回空组件，不影响任何正常 UI。
class DevConsoleEntry extends StatefulWidget {
  final AppState state;
  const DevConsoleEntry({super.key, required this.state});

  @override
  State<DevConsoleEntry> createState() => _DevConsoleEntryState();
}

class _DevConsoleEntryState extends State<DevConsoleEntry> {
  AppState get state => widget.state;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      if (_open) Positioned.fill(child: _DevConsoleOverlay(state: state, onClose: () => setState(() => _open = false))),
      Positioned(right: 16, bottom: 16, child: _fab()),
    ]);
  }

  /// 右下角小按钮（不占用正常界面空间）
  Widget _fab() {
    return Material(
      color: Colors.black.withValues(alpha: 0.75),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        borderRadius: BorderRadius.circular(30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              _open ? Icons.close_rounded : Icons.bug_report_rounded,
              size: 16,
              color: const Color(0xFF8AB4F8),
            ),
            const SizedBox(width: 6),
            Text(
              _open ? '关闭' : '开发者控制台',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 全屏开发者控制台浮层（深色终端风格）
class _DevConsoleOverlay extends StatelessWidget {
  final AppState state;
  final VoidCallback onClose;
  const _DevConsoleOverlay({required this.state, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final log = state.devLog;
        final isEmpty = log.isEmpty;
        return Container(
          color: const Color(0xF2000000),
          child: SafeArea(
            child: Column(children: [
              // 头部工具栏
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                color: const Color(0xFF111318),
                child: Row(children: [
                  const Icon(Icons.bug_report_rounded, size: 18, color: Color(0xFF8AB4F8)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('开发者控制台 · AI 思维链', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  _toolBtn(context, Icons.delete_sweep_outlined, '清空', () => state.devLogClear()),
                  const SizedBox(width: 6),
                  _toolBtn(context, Icons.copy_rounded, '复制', () => _copyAll(context, log.join('\n'))),
                  const SizedBox(width: 6),
                  _toolBtn(context, Icons.close_rounded, '关闭', onClose),
                ]),
              ),
              // 日志区（reverse 列表自动吸附最新日志）
              Expanded(
                child: isEmpty
                    ? const Center(child: Text('暂无日志…', style: TextStyle(color: Colors.white38, fontSize: 13)))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(12),
                        itemCount: log.length,
                        itemBuilder: (context, i) {
                          final line = log[log.length - 1 - i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SelectableText(
                              line,
                              style: const TextStyle(
                                color: Color(0xFFD6E2F2),
                                fontSize: 12.5,
                                height: 1.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _toolBtn(BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: const Color(0xFF2A2F3A),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: const Color(0xFF8AB4F8)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  Future<void> _copyAll(BuildContext context, String text) async {
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制全部日志'), duration: Duration(seconds: 1)),
    );
  }
}
