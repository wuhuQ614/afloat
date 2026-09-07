/// 扫雷：一比一复刻微软经典扫雷（Windows Minesweeper）
/// 架构：Dart 负责 UI（棋盘/面板/设置菜单渲染），C++（minesweeper_logic）
///       通过 dart:ffi 负责全部游戏逻辑（布雷/翻开/标记/和弦/胜负/计时）。
/// - 难度：初级 9×9/10、中级 16×16/40、高级 16×30/99、自定义
/// - 规则：首次点击永不踩雷、左键翻开、右键 旗→问号→空、空白自动展开、
///   数字格和弦、踩雷显示全部雷并标记错误旗、胜利自动插旗
/// - 页面自成一屏：顶部仅保留与游戏相关的标题、设置、退出
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/minesweeper_logic.dart';
import '../state.dart' show AppScope;
import '../theme_colors.dart' show AppColors;

/// 更多功能选择页索引（与 main.dart 的 _morePageIndex 对应）
const _morePageIndex = 9;

/// 难度预设
enum _Level { beginner, intermediate, expert, custom }

class MinesweeperPage extends StatefulWidget {
  const MinesweeperPage({super.key});

  @override
  State<MinesweeperPage> createState() => _MinesweeperPageState();
}

class _MinesweeperPageState extends State<MinesweeperPage> {
  MinesweeperLogic? _logic;
  bool _logicError = false;

  int _rows = 9, _cols = 9, _mines = 10;
  _Level _level = _Level.beginner;
  int _customRows = 16, _customCols = 16, _customMines = 40;
  bool _useQuestion = true;

  bool _over = false, _won = false;
  int _seconds = 0, _remain = 0;
  Timer? _timer;

  static const _cellSize = 26.0;
  static const _boardPad = 6.0;

  @override
  void initState() {
    super.initState();
    _newGame(_Level.beginner);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logic?.dispose();
    super.dispose();
  }

  void _newGame(_Level lv, {int? rows, int? cols, int? mines}) {
    switch (lv) {
      case _Level.beginner:
        _rows = 9;
        _cols = 9;
        _mines = 10;
      case _Level.intermediate:
        _rows = 16;
        _cols = 16;
        _mines = 40;
      case _Level.expert:
        _rows = 16;
        _cols = 30;
        _mines = 99;
      case _Level.custom:
        _rows = rows ?? _customRows;
        _cols = cols ?? _customCols;
        _mines = mines ?? _customMines;
    }
    _level = lv;
    try {
      if (_logic == null) {
        _logic = MinesweeperLogic(_rows, _cols, _mines);
      } else {
        _logic!.resize(_rows, _cols, _mines);
      }
      _logic!.sync();
      _logicError = false;
    } on MsLoadException {
      _logicError = true;
    }
    _over = false;
    _won = false;
    _seconds = 0;
    _remain = _mines;
    _timer?.cancel();
    if (mounted) setState(() {});
  }

  void _reset() {
    _logic?.reset();
    _logic?.sync();
    _over = false;
    _won = false;
    _seconds = 0;
    _remain = _mines;
    _timer?.cancel();
    setState(() {});
  }

  void _syncState() {
    final g = _logic;
    if (g == null) return;
    g.sync();
    _over = g.over;
    _won = g.won;
    _seconds = g.seconds;
    _remain = g.remain;
    if (_over) _timer?.cancel();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final g = _logic;
      if (g == null || !mounted || g.over) return;
      g.tick();
      setState(() => _seconds = g.seconds);
    });
  }

  // ===== 输入 =====
  void _onPointerDown(PointerDownEvent e) {
    final g = _logic;
    if (g == null || g.over) return;
    final dx = e.localPosition.dx - _boardPad;
    final dy = e.localPosition.dy - _boardPad;
    if (dx < 0 || dy < 0) return;
    final col = (dx / _cellSize).floor();
    final row = (dy / _cellSize).floor();
    if (row < 0 || row >= _rows || col < 0 || col >= _cols) return;
    final idx = row * _cols + col;
    final wasStarted = g.started;
    // Flutter: 1=左 2=右 4=中
    if (e.buttons == 2) {
      g.toggleMark(idx);
    } else if (e.buttons == 4) {
      g.chord(idx);
    } else if (g.states[idx] == MsCell.revealed && g.adjs[idx] > 0) {
      g.chord(idx); // 已翻开数字格上左键 = 和弦
    } else {
      g.reveal(idx);
    }
    g.sync();
    _over = g.over;
    _won = g.won;
    _seconds = g.seconds;
    _remain = g.remain;
    if (!wasStarted && g.started) _startTimer();
    if (_over) _timer?.cancel();
    setState(() {});
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    final boardW = _cols * _cellSize + _boardPad * 2;
    final boardH = _rows * _cellSize + _boardPad * 2;

    return Scaffold(
      backgroundColor: isLight ? const Color(0xFFF2F3F5) : const Color(0xFF1B1B20),
      body: SafeArea(
        child: Column(children: [
          _buildTopBar(c),
          Expanded(
            child: _logicError
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.error_outline, size: 44, color: c.textTertiary),
                      const SizedBox(height: 12),
                      Text('扫雷逻辑库加载失败（minesweeper_logic.dll）',
                          style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                      const SizedBox(height: 6),
                      Text('请重新构建项目后再次进入', style: TextStyle(fontSize: 12, color: c.textTertiary)),
                    ]),
                  )
                : Center(
                    child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: _frameDeco(isLight, outer: true),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            _buildPanel(isLight),
                            const SizedBox(height: 6),
                            Container(
                              width: boardW,
                              height: boardH,
                              padding: const EdgeInsets.all(_boardPad - 3),
                              decoration: _frameDeco(isLight, outer: false),
                              child: Listener(
                                onPointerDown: _onPointerDown,
                                child: CustomPaint(
                                  painter: _BoardPainter(
                                    rows: _rows,
                                    cols: _cols,
                                    states: _logic?.states ?? const [],
                                    adjs: _logic?.adjs ?? const [],
                                    mines: _logic?.minesView ?? const [],
                                    boom: _logic?.boom ?? -1,
                                    light: isLight,
                                    cell: _cellSize,
                                  ),
                                  child: SizedBox(width: boardW - 6, height: boardH - 6),
                                ),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '左键翻开 · 右键标旗${_useQuestion ? '（再按变问号）' : ''} · 数字格双击/中键和弦展开',
                          style: TextStyle(fontSize: 11.5, color: c.textTertiary),
                        ),
                      ]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  BoxDecoration _frameDeco(bool isLight, {required bool outer}) {
    return BoxDecoration(
      color: isLight ? const Color(0xFFC0C0C0) : const Color(0xFF3A3A42),
      border: outer
          ? Border(
              top: BorderSide(color: isLight ? Colors.white : const Color(0xFF55555F), width: 3),
              left: BorderSide(color: isLight ? Colors.white : const Color(0xFF55555F), width: 3),
              right: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
              bottom: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
            )
          : Border(
              top: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
              left: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
              right: BorderSide(color: isLight ? Colors.white : const Color(0xFF55555F), width: 3),
              bottom: BorderSide(color: isLight ? Colors.white : const Color(0xFF55555F), width: 3),
            ),
    );
  }

  Widget _buildTopBar(AppColors c) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(Icons.grid_on_rounded, size: 20, color: c.textSecondary),
        const SizedBox(width: 8),
        Text('扫雷', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: '设置',
          icon: Icon(Icons.more_vert_rounded, color: c.textSecondary),
          onSelected: _onMenu,
          itemBuilder: (_) => [
            for (final e in [
              ('beginner', '初级 9×9 · 10 雷'),
              ('intermediate', '中级 16×16 · 40 雷'),
              ('expert', '高级 16×30 · 99 雷'),
              ('custom', '自定义...'),
            ])
              CheckedPopupMenuItem<String>(
                value: e.$1,
                checked: _levelName(_level) == e.$1,
                child: Text(e.$2),
              ),
            const PopupMenuDivider(),
            CheckedPopupMenuItem<String>(
              value: 'question',
              checked: _useQuestion,
              child: const Text('问号标记'),
            ),
            const PopupMenuItem<String>(value: 'restart', child: Text('重新开始')),
            const PopupMenuDivider(),
            const PopupMenuItem<String>(value: 'exit', child: Text('退出游戏')),
          ],
        ),
      ]),
    );
  }

  String _levelName(_Level lv) => switch (lv) {
        _Level.beginner => 'beginner',
        _Level.intermediate => 'intermediate',
        _Level.expert => 'expert',
        _Level.custom => 'custom',
      };

  void _onMenu(String v) async {
    switch (v) {
      case 'beginner':
        _newGame(_Level.beginner);
      case 'intermediate':
        _newGame(_Level.intermediate);
      case 'expert':
        _newGame(_Level.expert);
      case 'custom':
        await _showCustomDialog();
      case 'question':
        setState(() => _useQuestion = !_useQuestion);
      case 'restart':
        _reset();
      case 'exit':
        if (mounted) AppScope.of(context).setPage(_morePageIndex);
    }
  }

  Future<void> _showCustomDialog() async {
    final c = AppColors.of(context);
    final rowCtrl = TextEditingController(text: '$_customRows');
    final colCtrl = TextEditingController(text: '$_customCols');
    final mineCtrl = TextEditingController(text: '$_customMines');
    String? err;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          backgroundColor: c.cardSolid,
          title: const Text('自定义难度'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _numField('行数 (9-24)', rowCtrl),
            const SizedBox(height: 8),
            _numField('列数 (9-30)', colCtrl),
            const SizedBox(height: 8),
            _numField('雷数', mineCtrl),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final r = int.tryParse(rowCtrl.text) ?? 0;
                final cc = int.tryParse(colCtrl.text) ?? 0;
                final m = int.tryParse(mineCtrl.text) ?? 0;
                if (r < 9 || r > 24 || cc < 9 || cc > 30) {
                  setS(() => err = '行数 9-24，列数 9-30');
                  return;
                }
                if (m < 10 || m > r * cc - 9) {
                  setS(() => err = '雷数需在 10 ~ ${r * cc - 9} 之间');
                  return;
                }
                _customRows = r;
                _customCols = cc;
                _customMines = m;
                Navigator.pop(ctx);
                _newGame(_Level.custom, rows: r, cols: cc, mines: m);
              },
              child: const Text('开始'),
            ),
          ],
        );
      }),
    );
  }

  Widget _numField(String label, TextEditingController ctrl) {
    final c = AppColors.of(context);
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: 13, color: c.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 12, color: c.textTertiary),
        isDense: true,
        filled: true,
        fillColor: Colors.transparent,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
      ),
    );
  }

  /// 面板：剩余雷数 LED / 笑脸 / 计时 LED
  Widget _buildPanel(bool isLight) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isLight ? const Color(0xFFC0C0C0) : const Color(0xFF3A3A42),
        border: Border(
          top: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 2),
          left: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 2),
          right: BorderSide(color: isLight ? Colors.white : const Color(0xFF55555F), width: 2),
          bottom: BorderSide(color: isLight ? Colors.white : const Color(0xFF55555F), width: 2),
        ),
      ),
      child: Row(children: [
        _ledCounter(_remain, isLight),
        const Spacer(),
        _faceButton(isLight),
        const Spacer(),
        _ledCounter(_seconds, isLight),
      ]),
    );
  }

  /// 3 位 LED 数码（支持负数：-NN）
  Widget _ledCounter(int value, bool isLight) {
    final clamped = value.clamp(-99, 999);
    final text = clamped < 0
        ? '-${clamped.abs().toString().padLeft(2, '0')}'
        : clamped.toString().padLeft(3, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: Colors.black,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 23,
          height: 1.05,
          fontWeight: FontWeight.w700,
          color: Color(0xFFFF0000),
          fontFamily: 'monospace',
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _faceButton(bool isLight) {
    return GestureDetector(
      onTap: _reset,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isLight ? const Color(0xFFC0C0C0) : const Color(0xFF4A4A54),
          border: Border(
            top: BorderSide(color: isLight ? Colors.white : const Color(0xFF6A6A76), width: 2),
            left: BorderSide(color: isLight ? Colors.white : const Color(0xFF6A6A76), width: 2),
            right: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 2),
            bottom: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 2),
          ),
        ),
        child: CustomPaint(painter: _FacePainter(over: _over && !_won, won: _won)),
      ),
    );
  }
}

/// 笑脸（正常 / 踩雷哭脸 / 胜利戴墨镜）
class _FacePainter extends CustomPainter {
  final bool over;
  final bool won;
  _FacePainter({required this.over, required this.won});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(size.width, size.height) / 2 - 3;
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = const Color(0xFFFFE000));
    final black = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.4;
    if (won) {
      canvas.drawRect(Rect.fromLTWH(cx - r * 0.75, cy - r * 0.35, r * 1.5, r * 0.34), Paint()..color = Colors.black);
    } else if (over) {
      canvas.drawLine(Offset(cx - r * 0.5, cy - r * 0.45), Offset(cx - r * 0.12, cy - r * 0.1), black);
      canvas.drawLine(Offset(cx - r * 0.5, cy - r * 0.1), Offset(cx - r * 0.12, cy - r * 0.45), black);
      canvas.drawLine(Offset(cx + r * 0.12, cy - r * 0.45), Offset(cx + r * 0.5, cy - r * 0.1), black);
      canvas.drawLine(Offset(cx + r * 0.12, cy - r * 0.1), Offset(cx + r * 0.5, cy - r * 0.45), black);
    } else {
      canvas.drawCircle(Offset(cx - r * 0.35, cy - r * 0.25), 1.5, black);
      canvas.drawCircle(Offset(cx + r * 0.35, cy - r * 0.25), 1.5, black);
    }
    final mouth = Path();
    if (over && !won) {
      mouth.moveTo(cx - r * 0.45, cy + r * 0.5);
      mouth.quadraticBezierTo(cx, cy + r * 0.05, cx + r * 0.45, cy + r * 0.5);
    } else {
      mouth.moveTo(cx - r * 0.45, cy + r * 0.15);
      mouth.quadraticBezierTo(cx, cy + r * 0.6, cx + r * 0.45, cy + r * 0.15);
    }
    canvas.drawPath(mouth, Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) => old.over != over || old.won != won;
}

/// 棋盘绘制：凸起格（未开）/ 平面格（已开）/ 旗 / 问号 / 雷 / 数字
/// 数据来源：C++ 逻辑库批量拷贝的 Int32List（states/adjs/mines）
class _BoardPainter extends CustomPainter {
  final int rows, cols;
  final List<int> states, adjs, mines;
  final int boom;
  final bool light;
  final double cell;

  _BoardPainter({
    required this.rows,
    required this.cols,
    required this.states,
    required this.adjs,
    required this.mines,
    required this.boom,
    required this.light,
    required this.cell,
  });

  static const List<Color> _numColors = [
    Colors.transparent, // 0
    Color(0xFF0000FF), // 1
    Color(0xFF008000), // 2
    Color(0xFFFF0000), // 3
    Color(0xFF000080), // 4
    Color(0xFF800000), // 5
    Color(0xFF008080), // 6
    Color(0xFF000000), // 7
    Color(0xFF808080), // 8
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final face = light ? const Color(0xFFC0C0C0) : const Color(0xFF4A4A54);
    final hi = light ? Colors.white : const Color(0xFF6A6A76);
    final sh = light ? const Color(0xFF808080) : const Color(0xFF141418);
    final grid = light ? const Color(0xFF9A9A9A) : const Color(0xFF2C2C34);

    for (var r = 0; r < rows; r++) {
      for (var cIdx = 0; cIdx < cols; cIdx++) {
        final i = r * cols + cIdx;
        if (i >= states.length) break;
        final x = cIdx * cell;
        final y = r * cell;
        final rect = Rect.fromLTWH(x, y, cell, cell);
        final st = states[i];

        if (st == MsCell.revealed) {
          canvas.drawRect(rect, Paint()..color = face);
          canvas.drawRect(rect, Paint()
            ..color = grid
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
          if (mines[i] != 0) {
            if (i == boom) canvas.drawRect(rect, Paint()..color = Colors.red);
            _drawMine(canvas, rect);
          } else if (adjs[i] > 0) {
            _drawNumber(canvas, rect, adjs[i]);
          }
          continue;
        }

        // 未翻开：凸起 3D 块
        var bg = face;
        if (i == boom) bg = Colors.red;
        canvas.drawRect(rect, Paint()..color = bg);
        canvas.drawLine(Offset(x, y), Offset(x + cell, y), Paint()
          ..color = hi
          ..strokeWidth = 2);
        canvas.drawLine(Offset(x, y), Offset(x, y + cell), Paint()
          ..color = hi
          ..strokeWidth = 2);
        canvas.drawLine(Offset(x + cell - 1, y), Offset(x + cell - 1, y + cell), Paint()
          ..color = sh
          ..strokeWidth = 2);
        canvas.drawLine(Offset(x, y + cell - 1), Offset(x + cell, y + cell - 1), Paint()
          ..color = sh
          ..strokeWidth = 2);

        if (st == MsCell.flagged) {
          _drawFlag(canvas, rect);
          if (mines[i] == 0) _drawCross(canvas, rect); // 游戏结束：错误旗打 X
        } else if (st == MsCell.question) {
          _drawText(canvas, rect, '?', Colors.black);
        }
      }
    }
  }

  void _drawMine(Canvas canvas, Rect rect) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final r = rect.width * 0.26;
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Colors.black);
    final spike = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.6;
    for (var k = 0; k < 4; k++) {
      final a = k * math.pi / 4;
      canvas.drawLine(Offset(cx - r * math.cos(a), cy - r * math.sin(a)),
          Offset(cx + r * math.cos(a), cy + r * math.sin(a)), spike);
    }
    canvas.drawCircle(Offset(cx - r * 0.3, cy - r * 0.3), r * 0.22, Paint()..color = Colors.white);
  }

  void _drawFlag(Canvas canvas, Rect rect) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final pole = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.6;
    canvas.drawLine(Offset(cx - 2, cy + 6), Offset(cx - 2, cy - 6), pole);
    canvas.drawLine(Offset(cx - 7, cy + 6), Offset(cx + 3, cy + 6), pole);
    final cloth = Path()
      ..moveTo(cx - 2, cy - 6)
      ..lineTo(cx + 5, cy - 3)
      ..lineTo(cx - 2, cy)
      ..close();
    canvas.drawPath(cloth, Paint()..color = Colors.red);
  }

  void _drawCross(Canvas canvas, Rect rect) {
    final p = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    final pad = rect.width * 0.22;
    canvas.drawLine(Offset(rect.left + pad, rect.top + pad), Offset(rect.right - pad, rect.bottom - pad), p);
    canvas.drawLine(Offset(rect.right - pad, rect.top + pad), Offset(rect.left + pad, rect.bottom - pad), p);
  }

  void _drawNumber(Canvas canvas, Rect rect, int n) => _drawText(canvas, rect, '$n', _numColors[n]);

  void _drawText(Canvas canvas, Rect rect, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: cell * 0.62,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
