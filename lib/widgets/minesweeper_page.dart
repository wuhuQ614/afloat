/// 扫雷：一比一复刻微软经典扫雷（Windows Minesweeper）
/// - 难度：初级 9×9/10、中级 16×16/40、高级 16×30/99、自定义
/// - 规则：首次点击永不踩雷（首击格及其 8 邻域不布雷）、左键翻开、
///   右键 旗→问号→空 循环、空白格自动展开、数字格和弦展开（chord）、
///   踩雷显示所有雷并标记错误旗、胜利自动为剩余雷插旗
/// - 面板：LED 剩余雷数（3 位，可为负）、笑脸重置、计时器（首击起算，上限 999）
/// - 页面自成一屏：顶部仅保留与游戏相关的标题、设置、退出
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state.dart' show AppScope;
import '../theme_colors.dart' show AppColors;

/// 更多功能选择页索引（与 main.dart 的 _morePageIndex 对应）
const _morePageIndex = 9;

/// 格子状态
enum _CellState { hidden, revealed, flagged, question }

/// 难度预设：(名称, 行, 列, 雷数)
enum _Level { beginner, intermediate, expert, custom }

class MinesweeperPage extends StatefulWidget {
  const MinesweeperPage({super.key});

  @override
  State<MinesweeperPage> createState() => _MinesweeperPageState();
}

class _MinesweeperPageState extends State<MinesweeperPage> {
  // ===== 棋盘数据 =====
  late int _rows, _cols, _mines;
  late List<bool> _mine; // 是否雷
  late List<int> _adj; // 周围雷数
  late List<_CellState> _state;
  bool _started = false; // 首次点击后开始（布雷 + 计时）
  bool _over = false; // 结束（胜/负）
  bool _won = false;
  int _revealedCount = 0;
  int _boomIndex = -1; // 踩中的雷
  int _seconds = 0;
  Timer? _timer;

  _Level _level = _Level.beginner;
  int _customRows = 16, _customCols = 16, _customMines = 40;
  bool _useQuestion = true; // 是否启用问号标记（经典默认开启）

  // 最佳时间（秒；0 表示无记录）
  final Map<_Level, int> _best = {
    _Level.beginner: 0,
    _Level.intermediate: 0,
    _Level.expert: 0,
    _Level.custom: 0,
  };

  static const _cellSize = 26.0;
  static const _boardPad = 6.0;

  @override
  void initState() {
    super.initState();
    _applyLevel(_Level.beginner);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ===== 难度 =====
  void _applyLevel(_Level lv, {int? rows, int? cols, int? mines}) {
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
    _reset();
  }

  void _reset() {
    _timer?.cancel();
    final n = _rows * _cols;
    _mine = List<bool>.filled(n, false);
    _adj = List<int>.filled(n, 0);
    _state = List<_CellState>.filled(n, _CellState.hidden);
    _started = false;
    _over = false;
    _won = false;
    _revealedCount = 0;
    _boomIndex = -1;
    _seconds = 0;
    setState(() {});
  }

  int _index(int r, int c) => r * _cols + c;
  bool _inBoard(int r, int c) => r >= 0 && r < _rows && c >= 0 && c < _cols;

  Iterable<int> _neighbors(int r, int c) sync* {
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dr == 0 && dc == 0) continue;
        final nr = r + dr, nc = c + dc;
        if (_inBoard(nr, nc)) yield _index(nr, nc);
      }
    }
  }

  /// 布雷：[safeIdx] 首次点击格，其 8 邻域也排除（保证首击展开空白区）
  void _placeMines(int safeIdx) {
    final safe = <int>{safeIdx, ..._neighbors(safeIdx ~/ _cols, safeIdx % _cols)};
    final total = _rows * _cols;
    final candidates = <int>[];
    for (var i = 0; i < total; i++) {
      if (!safe.contains(i)) candidates.add(i);
    }
    if (candidates.length < _mines) {
      // 极端情况（雷数过多）：回退为仅排除首击格
      candidates
        ..clear()
        ..addAll(List<int>.generate(total, (i) => i).where((i) => i != safeIdx));
    }
    final rnd = math.Random();
    candidates.shuffle(rnd);
    for (var k = 0; k < _mines && k < candidates.length; k++) {
      _mine[candidates[k]] = true;
    }
    for (var i = 0; i < total; i++) {
      var count = 0;
      for (final n in _neighbors(i ~/ _cols, i % _cols)) {
        if (_mine[n]) count++;
      }
      _adj[i] = count;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _over) return;
      if (_seconds < 999) {
        setState(() => _seconds++);
      }
    });
  }

  int get _flags => _state.where((s) => s == _CellState.flagged).length;
  int get _remain => _mines - _flags;

  /// 左键：翻开
  void _reveal(int idx) {
    if (_over) return;
    final st = _state[idx];
    if (st == _CellState.revealed || st == _CellState.flagged) return;
    if (!_started) {
      _placeMines(idx);
      _started = true;
      _startTimer();
    }
    if (_mine[idx]) {
      _boomIndex = idx;
      _over = true;
      _won = false;
      _timer?.cancel();
      setState(() {});
      return;
    }
    _floodReveal(idx);
    _checkWin();
  }

  void _floodReveal(int start) {
    final stack = <int>[start];
    final seen = <int>{};
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      if (!seen.add(i)) continue;
      // 仅展开未标记的格子：旗与问号格保留（与 Windows 一致）
      if (_state[i] == _CellState.revealed ||
          _state[i] == _CellState.flagged ||
          _state[i] == _CellState.question) {
        continue;
      }
      _state[i] = _CellState.revealed;
      _revealedCount++;
      if (_adj[i] == 0) {
        for (final n in _neighbors(i ~/ _cols, i % _cols)) {
          if (_state[n] == _CellState.hidden && !_mine[n]) stack.add(n);
        }
      }
    }
  }

  /// 右键：旗 → 问号 → 空
  void _toggleMark(int idx) {
    if (_over) return;
    if (_state[idx] == _CellState.revealed) return;
    setState(() {
      switch (_state[idx]) {
        case _CellState.hidden:
          _state[idx] = _CellState.flagged;
        case _CellState.flagged:
          _state[idx] = _useQuestion ? _CellState.question : _CellState.hidden;
        case _CellState.question:
          _state[idx] = _CellState.hidden;
        case _CellState.revealed:
          break;
      }
    });
  }

  /// 和弦：数字格上按下（中键/双击）—— 周围旗数 == 数字则翻开其余邻格
  void _chord(int idx) {
    if (_over || _state[idx] != _CellState.revealed || _adj[idx] == 0) return;
    var flags = 0;
    for (final n in _neighbors(idx ~/ _cols, idx % _cols)) {
      if (_state[n] == _CellState.flagged) flags++;
    }
    if (flags != _adj[idx]) return;
    for (final n in _neighbors(idx ~/ _cols, idx % _cols)) {
      if (_state[n] == _CellState.hidden || _state[n] == _CellState.question) {
        _reveal(n);
        if (_over) return;
      }
    }
  }

  void _checkWin() {
    if (_revealedCount != _rows * _cols - _mines) return;
    _over = true;
    _won = true;
    _timer?.cancel();
    // 胜利：剩余雷自动插旗
    for (var i = 0; i < _mine.length; i++) {
      if (_mine[i] && _state[i] != _CellState.revealed) {
        _state[i] = _CellState.flagged;
      }
    }
    final prev = _best[_level] ?? 0;
    if (prev == 0 || _seconds < prev) _best[_level] = _seconds;
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
          // 顶部栏：标题 + 设置（含退出）
          _buildTopBar(c, isLight),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // 经典外框：三边凹陷容器
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isLight ? const Color(0xFFC0C0C0) : const Color(0xFF3A3A42),
                      border: Border(
                        top: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF55555F), width: 3),
                        left: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF55555F), width: 3),
                        right: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
                        bottom: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
                      ),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // 面板：雷数 / 笑脸 / 计时
                      _buildPanel(isLight),
                      const SizedBox(height: 6),
                      // 棋盘
                      Container(
                        width: boardW,
                        height: boardH,
                        padding: const EdgeInsets.all(_boardPad - 3),
                        decoration: BoxDecoration(
                          color: isLight ? const Color(0xFFC0C0C0) : const Color(0xFF3A3A42),
                          border: Border(
                            top: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
                            left: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 3),
                            right: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF55555F), width: 3),
                            bottom: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF55555F), width: 3),
                          ),
                        ),
                        child: Listener(
                          onPointerDown: (e) => _onPointerDown(e, boardW, boardH),
                          child: CustomPaint(
                            painter: _BoardPainter(
                              rows: _rows,
                              cols: _cols,
                              mine: _mine,
                              adj: _adj,
                              state: _state,
                              over: _over,
                              won: _won,
                              boomIndex: _boomIndex,
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

  Widget _buildTopBar(AppColors c, bool isLight) {
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
          onSelected: (v) => _onMenu(v),
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
        _applyLevel(_Level.beginner);
      case 'intermediate':
        _applyLevel(_Level.intermediate);
      case 'expert':
        _applyLevel(_Level.expert);
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
                _applyLevel(_Level.custom, rows: r, cols: cc, mines: m);
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
          right: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF55555F), width: 2),
          bottom: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF55555F), width: 2),
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

  /// 3 位 LED 数码（支持负数：-NN 显示为 3 位内）
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
            top: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF6A6A76), width: 2),
            left: BorderSide(color: isLight ? const Color(0xFFFFFFFF) : const Color(0xFF6A6A76), width: 2),
            right: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 2),
            bottom: BorderSide(color: isLight ? const Color(0xFF808080) : const Color(0xFF141418), width: 2),
          ),
        ),
        child: CustomPaint(painter: _FacePainter(over: _over, won: _won)),
      ),
    );
  }

  // ===== 输入：左键/右键/中键/双击 =====
  void _onPointerDown(e, double w, double h) {
    if (_over) return;
    final dx = e.localPosition.dx - _boardPad;
    final dy = e.localPosition.dy - _boardPad;
    if (dx < 0 || dy < 0) return;
    final col = (dx / _cellSize).floor();
    final row = (dy / _cellSize).floor();
    if (!_inBoard(row, col)) return;
    final idx = _index(row, col);
    // Flutter: 1=左 2=右 4=中
    if (e.buttons == 2) {
      _toggleMark(idx);
    } else if (e.buttons == 4) {
      _chord(idx);
    } else {
      // 左键：已翻开的数字格上再点 = 和弦（等价中键）
      if (_state[idx] == _CellState.revealed && _adj[idx] > 0) {
        _chord(idx);
      } else {
        _reveal(idx);
      }
    }
  }
}

/// 笑脸（正常 / 踩雷 / 胜利戴墨镜）
class _FacePainter extends CustomPainter {
  final bool over;
  final bool won;
  _FacePainter({required this.over, required this.won});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(size.width, size.height) / 2 - 3;
    final paint = Paint()..color = const Color(0xFFFFE000);
    canvas.drawCircle(Offset(cx, cy), r, paint);
    final black = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.4;
    // 眼睛
    if (won) {
      // 墨镜
      final glass = Paint()..color = Colors.black;
      canvas.drawRect(Rect.fromLTWH(cx - r * 0.75, cy - r * 0.35, r * 1.5, r * 0.34), glass);
    } else if (over) {
      canvas.drawLine(Offset(cx - r * 0.5, cy - r * 0.45), Offset(cx - r * 0.12, cy - r * 0.1), black);
      canvas.drawLine(Offset(cx - r * 0.5, cy - r * 0.1), Offset(cx - r * 0.12, cy - r * 0.45), black);
      canvas.drawLine(Offset(cx + r * 0.12, cy - r * 0.45), Offset(cx + r * 0.5, cy - r * 0.1), black);
      canvas.drawLine(Offset(cx + r * 0.12, cy - r * 0.1), Offset(cx + r * 0.5, cy - r * 0.45), black);
    } else {
      canvas.drawCircle(Offset(cx - r * 0.35, cy - r * 0.25), 1.5, black);
      canvas.drawCircle(Offset(cx + r * 0.35, cy - r * 0.25), 1.5, black);
    }
    // 嘴
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
class _BoardPainter extends CustomPainter {
  final int rows, cols;
  final List<bool> mine;
  final List<int> adj;
  final List<_CellState> state;
  final bool over, won, light;
  final int boomIndex;
  final double cell;

  _BoardPainter({
    required this.rows,
    required this.cols,
    required this.mine,
    required this.adj,
    required this.state,
    required this.over,
    required this.won,
    required this.boomIndex,
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
        final x = cIdx * cell;
        final y = r * cell;
        final rect = Rect.fromLTWH(x, y, cell, cell);
        final st = state[i];
        final revealed = st == _CellState.revealed;

        if (revealed) {
          // 已翻开：平面 + 网格线
          canvas.drawRect(rect, Paint()..color = light ? const Color(0xFFC0C0C0) : const Color(0xFF3A3A42));
          canvas.drawRect(rect, Paint()
            ..color = grid
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
          if (mine[i]) {
            if (i == boomIndex) {
              canvas.drawRect(rect, Paint()..color = Colors.red);
            }
            _drawMine(canvas, rect);
          } else if (adj[i] > 0) {
            _drawNumber(canvas, rect, adj[i]);
          }
          continue;
        }

        // 未翻开：凸起 3D 块（踩雷后仍保留凸起，雷由后续绘制）
        var bg = face;
        if (i == boomIndex) bg = Colors.red;
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

        if (st == _CellState.flagged) {
          _drawFlag(canvas, rect);
          // 游戏结束：错误旗画 X
          if (over && !mine[i]) _drawCross(canvas, rect);
        } else if (st == _CellState.question) {
          _drawText(canvas, rect, '?', Colors.black);
        } else if (over && mine[i] && !won) {
          // 踩雷后显示未标记的雷
          _drawMine(canvas, rect);
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
