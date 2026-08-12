/// 中国象棋页面：一比一复刻参考项目 ChineseChessGame.jsx。
///
/// 功能对齐：
/// - 人人对战 / 人机对战（脚本AI，easy 深度2 / normal 深度3，你执红 AI 执黑）
/// - 完整走子规则 + 将军/将死判定 + 悔棋（快照恢复）+ 重开
/// - 走子动画 220ms ease-out 抬升；选中/合法落点/上一步高亮
/// - 胜率条（sigmoid scale=800）；楷体棋子；木纹棋盘；楚河汉界
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme_colors.dart';
import 'chess_ai.dart';

const double _kBoardPad = 36;
const int _kAnimDurationMs = 220;

/// 走子历史快照
class _HistoryEntry {
  final Board board;
  final bool currentRed;
  final ({List<int> from, List<int> to})? lastMove;
  _HistoryEntry(this.board, this.currentRed, this.lastMove);
}

/// 走子动画状态
class _MovingPiece {
  final int piece;
  final List<int> from;
  final List<int> to;
  final DateTime start;
  final int durationMs;
  _MovingPiece(this.piece, this.from, this.to, this.start, this.durationMs);
}

class ChineseChessPage extends StatefulWidget {
  const ChineseChessPage({super.key});

  @override
  State<ChineseChessPage> createState() => _ChineseChessPageState();
}

class _ChineseChessPageState extends State<ChineseChessPage>
    with SingleTickerProviderStateMixin {
  // 界面：mode 模式选择 / opponent 选对手 / difficulty 选难度 / game 对局
  String _screen = 'mode';
  String? _mode; // 'pvp' | 'pve'
  String _difficulty = 'easy';

  Board _board = createInitialBoard();
  bool _currentRed = true;
  List<int>? _selected;
  List<List<int>> _validMoves = [];
  final List<_HistoryEntry> _history = [];
  String _statusMsg = '红方走棋';
  bool _gameOver = false;
  bool _aiThinking = false;
  ({List<int> from, List<int> to})? _lastMove;
  _MovingPiece? _moving;

  Timer? _aiTimer;
  Timer? _animTimer;
  late final AnimationController _animCtrl;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    // P1-1：移除 addListener+setState，改用 AnimatedBuilder 隔离动画重建范围
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kAnimDurationMs),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _aiTimer?.cancel();
    _animTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  Color get _statusColor {
    if (_statusMsg.contains('胜利')) return const Color(0xFFE74C3C);
    if (_statusMsg.contains('将军')) return const Color(0xFFE67E22);
    return AppColors.of(context).text;
  }

  // ==================== 走棋 ====================
  void _performMove(List<int> from, List<int> to, bool isAI) {
    final piece = _board[from[0]][from[1]];
    if (piece == kEmpty) return;

    // 记录历史快照
    _history.add(_HistoryEntry(cloneBoard(_board), _currentRed, _lastMove));
    setState(() {
      _selected = null;
      _validMoves = [];
      _moving = _MovingPiece(piece, from, to, DateTime.now(), _kAnimDurationMs);
    });

    _animCtrl.forward(from: 0);
    _animTimer?.cancel();
    _animTimer = Timer(const Duration(milliseconds: _kAnimDurationMs), () {
      if (_disposed) return;
      _applyMove(from, to, isAI);
    });
  }

  void _applyMove(List<int> from, List<int> to, bool isAI) {
    final newBoard = cloneBoard(_board);
    newBoard[to[0]][to[1]] = newBoard[from[0]][from[1]];
    newBoard[from[0]][from[1]] = kEmpty;
    final nextRed = !_currentRed;

    setState(() {
      _board = newBoard;
      _lastMove = (from: from, to: to);
      _currentRed = nextRed;
      _moving = null;
    });

    if (_mode == 'pve') {
      if (isAI) {
        // AI（黑）走完，轮到玩家（红）
        if (isCheckmate(newBoard, true)) {
          setState(() {
            _statusMsg = '黑方胜利！';
            _gameOver = true;
          });
          return;
        } else if (isInCheck(newBoard, true)) {
          setState(() => _statusMsg = '将军！红方走棋');
        } else {
          setState(() => _statusMsg = '红方走棋');
        }
      } else {
        // 玩家（红）走完，触发 AI（黑）
        if (isCheckmate(newBoard, false)) {
          setState(() {
            _statusMsg = '红方胜利！';
            _gameOver = true;
          });
          return;
        }
        if (isInCheck(newBoard, false)) {
          setState(() => _statusMsg = '将军！黑方思考中...');
        } else {
          setState(() => _statusMsg = '黑方思考中...');
        }
        setState(() => _aiThinking = true);
        _aiTimer?.cancel();
        final thinkMs = _difficulty == 'easy'
            ? 250
            : _difficulty == 'normal'
                ? 450
                : 650;
        _aiTimer = Timer(Duration(milliseconds: thinkMs), () {
          if (_disposed) return;
          final aiMove = getAiMove(newBoard, _difficulty);
          setState(() => _aiThinking = false);
          if (aiMove != null) {
            _performMove(aiMove.from, aiMove.to, true);
          }
        });
      }
    } else {
      // 人人对战
      if (isCheckmate(newBoard, nextRed)) {
        setState(() {
          _statusMsg = nextRed ? '黑方胜利！' : '红方胜利！';
          _gameOver = true;
        });
      } else if (isInCheck(newBoard, nextRed)) {
        setState(() => _statusMsg = nextRed ? '将军！红方走棋' : '将军！黑方走棋');
      } else {
        setState(() => _statusMsg = nextRed ? '红方走棋' : '黑方走棋');
      }
    }
  }

  void _onBoardTap(int r, int c) {
    if (_gameOver || _aiThinking || _moving != null) return;
    final piece = _board[r][c];

    if (_selected != null) {
      final sel = _selected!;
      if (_validMoves.any((m) => m[0] == r && m[1] == c)) {
        _performMove(sel, [r, c], false);
        return;
      } else {
        setState(() {
          _selected = null;
          _validMoves = [];
        });
      }
    }

    if (piece != kEmpty) {
      final isPieceRed = piece > 0;
      if (_mode == 'pve' && !_currentRed) return;
      if (isPieceRed == _currentRed || _mode == 'pvp') {
        if (_mode == 'pvp' && isPieceRed != _currentRed) return;
        setState(() {
          _selected = [r, c];
          _validMoves = getLegalMoves(_board, r, c);
        });
      }
    }
  }

  void _handleRestart() {
    _aiTimer?.cancel();
    _animTimer?.cancel();
    _animCtrl.stop();
    setState(() {
      _board = createInitialBoard();
      _currentRed = true;
      _selected = null;
      _validMoves = [];
      _history.clear();
      _lastMove = null;
      _gameOver = false;
      _aiThinking = false;
      _moving = null;
      _statusMsg = '红方走棋';
    });
  }

  void _handleUndo() {
    if (_history.isEmpty || _aiThinking || _moving != null) return;
    final prev = _history.removeLast();
    setState(() {
      _board = prev.board;
      _currentRed = prev.currentRed;
      _lastMove = prev.lastMove;
      _selected = null;
      _validMoves = [];
      _gameOver = false;
      _statusMsg = _mode == 'pve'
          ? '红方走棋'
          : (prev.currentRed ? '红方走棋' : '黑方走棋');
    });
  }

  void _startGame(String mode) {
    _handleRestart();
    setState(() {
      _mode = mode;
      _screen = 'game';
    });
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_screen == 'mode') return _buildModeScreen(c);
    if (_screen == 'difficulty') return _buildDifficultyScreen(c);
    return _buildGameScreen(c);
  }

  Widget _buildModeScreen(AppColors c) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 眉标 + 大标题（简约高级：无彩色图标块）
                const SizedBox(height: 8),
                Text('CHINESE CHESS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600,
                        color: c.textTertiary)),
                const SizedBox(height: 10),
                Text('中国象棋',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: c.text)),
                const SizedBox(height: 8),
                Text('本地对弈 · 无需网络',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.textTertiary)),
                const SizedBox(height: 40),
                _modeCard(
                  c: c,
                  title: '双人游戏',
                  subtitle: '两人轮流走子，本地对弈',
                  onTap: () => _startGame('pvp'),
                ),
                const SizedBox(height: 12),
                _modeCard(
                  c: c,
                  title: '人机对战',
                  subtitle: '与本地 AI 对战，选择合适难度',
                  onTap: () => setState(() => _screen = 'difficulty'),
                ),
              ]),
        ),
      ),
    );
  }

  /// 简约高级模式卡片：纯文字 + 箭头（无图标无 emoji）
  Widget _modeCard({
    required AppColors c,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            color: c.chatBubbleAi,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: c.text)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12.5, color: c.textTertiary)),
                  ]),
            ),
            Icon(Icons.chevron_right, color: c.textTertiary, size: 22),
          ]),
        ),
      ),
    );
  }

  Widget _buildDifficultyScreen(AppColors c) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 返回 + 标题
                Row(children: [
                  IconButton(
                    onPressed: () => setState(() => _screen = 'mode'),
                    style: IconButton.styleFrom(
                        backgroundColor: c.inputFill,
                        foregroundColor: c.text),
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('选择难度',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: c.text)),
                    const SizedBox(height: 2),
                    Text('选择 AI 的强度，越难思考越深入',
                        style: TextStyle(fontSize: 12, color: c.textTertiary)),
                  ]),
                ]),
                const SizedBox(height: 28),
                _difficultyCard(
                  c: c,
                  title: '简单',
                  subtitle: '基础走法，适合新手',
                  tag: '深度 2',
                  selected: _difficulty == 'easy',
                  onTap: () {
                    _difficulty = 'easy';
                    _startGame('pve');
                  },
                ),
                const SizedBox(height: 12),
                _difficultyCard(
                  c: c,
                  title: '正常',
                  subtitle: '均衡思考，稳定发挥',
                  tag: '深度 3',
                  selected: _difficulty == 'normal',
                  onTap: () {
                    _difficulty = 'normal';
                    _startGame('pve');
                  },
                ),
                const SizedBox(height: 12),
                _difficultyCard(
                  c: c,
                  title: '困难',
                  subtitle: '深度推演，颇具挑战',
                  tag: '深度 4',
                  selected: _difficulty == 'hard',
                  onTap: () {
                    _difficulty = 'hard';
                    _startGame('pve');
                  },
                ),
                const SizedBox(height: 20),
                Text('你将执红先行，AI 执黑',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: c.textTertiary)),
              ]),
        ),
      ),
    );
  }

  /// 难度选择卡片（简约：纯文字 + 主题色选中态）
  Widget _difficultyCard({
    required AppColors c,
    required String title,
    required String subtitle,
    required String tag,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = c.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : c.chatBubbleAi,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? accent : c.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: c.text)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tag,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: accent)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 12, color: c.textTertiary)),
                ]),
          ),
          if (selected) Icon(Icons.check_circle, color: accent, size: 20),
        ]),
      ),
    );
  }

  Widget _buildGameScreen(AppColors c) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 顶栏：返回 / 状态 / 悔棋 / 重开
          Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: c.isLight ? Colors.white : const Color(0xFF1E1E3C),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: c.isLight ? 0.1 : 0.4),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(children: [
              Row(children: [
                OutlinedButton(
                  onPressed: () {
                    _handleRestart();
                    setState(() {
                      _screen = 'mode';
                      _mode = null;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  ),
                  child: const Text('← 返回', style: TextStyle(fontSize: 13)),
                ),
                const Spacer(),
                Row(children: [
                  if (_aiThinking)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE67E22)),
                      ),
                    ),
                  Text(_statusMsg,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _statusColor)),
                ]),
                const Spacer(),
                OutlinedButton(
                  onPressed: _history.isEmpty || _aiThinking || _moving != null
                      ? null
                      : _handleUndo,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: const Text('悔棋', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  onPressed: _handleRestart,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  child: const Text('重开', style: TextStyle(fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 12),
              // 棋盘
              LayoutBuilder(builder: (ctx, cons) {
                // 可用宽度取容器宽度，高度按 9:10 比例
                final availW = cons.maxWidth;
                final cellByW = (availW - 2 * _kBoardPad) / (kCols - 1);
                final cell = math.max(20.0, cellByW);
                final boardW = 2 * _kBoardPad + (kCols - 1) * cell;
                final boardH = 2 * _kBoardPad + (kRows - 1) * cell;
                return GestureDetector(
                  onTapUp: (d) {
                    final cc = ((d.localPosition.dx - _kBoardPad) / cell).round();
                    final rr = ((d.localPosition.dy - _kBoardPad) / cell).round();
                    if (rr >= 0 && rr < kRows && cc >= 0 && cc < kCols) {
                      _onBoardTap(rr, cc);
                    }
                  },
                  // P1-1：AnimatedBuilder 隔离动画重建，仅棋盘区域随帧重绘
                  child: AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (context, _) => CustomPaint(
                      size: Size(boardW, boardH),
                      painter: _ChessBoardPainter(
                        board: _board,
                        cell: cell,
                        selected: _selected,
                        validMoves: _validMoves,
                        lastMove: _lastMove,
                        moving: _moving,
                        animProgress: _animCtrl.value,
                      ),
                    ),
                  ),
                );
              }),
              // 模式提示
              if (_mode == 'pve') ...[
                const SizedBox(height: 10),
                Text(
                  _difficulty == 'easy'
                      ? '简单模式 · AI 深度 2'
                      : _difficulty == 'normal'
                          ? '正常模式 · AI 深度 3'
                          : '困难模式 · AI 深度 4',
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 棋盘绘制器
class _ChessBoardPainter extends CustomPainter {
  final Board board;
  final double cell;
  final List<int>? selected;
  final List<List<int>> validMoves;
  final ({List<int> from, List<int> to})? lastMove;
  final _MovingPiece? moving;
  final double animProgress;

  _ChessBoardPainter({
    required this.board,
    required this.cell,
    this.selected,
    this.validMoves = const [],
    this.lastMove,
    this.moving,
    this.animProgress = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = _kBoardPad;

    // 木纹背景（对齐 #e8c38f → #ddb878 → #dca96e）
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8C38F), Color(0xFFDDB878), Color(0xFFDCA96E)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(bgRect),
    );

    final linePaint = Paint()
      ..color = const Color(0xFF5C3D2E)
      ..strokeWidth = 1;

    // 横线
    for (var r = 0; r < kRows; r++) {
      canvas.drawLine(Offset(pad, pad + r * cell),
          Offset(pad + 8 * cell, pad + r * cell), linePaint);
    }
    // 竖线（中间列在河界断开）
    for (var c = 0; c < kCols; c++) {
      if (c == 0 || c == 8) {
        canvas.drawLine(Offset(pad + c * cell, pad),
            Offset(pad + c * cell, pad + 9 * cell), linePaint);
      } else {
        canvas.drawLine(Offset(pad + c * cell, pad),
            Offset(pad + c * cell, pad + 4 * cell), linePaint);
        canvas.drawLine(Offset(pad + c * cell, pad + 5 * cell),
            Offset(pad + c * cell, pad + 9 * cell), linePaint);
      }
    }
    // 九宫斜线
    canvas.drawLine(Offset(pad + 3 * cell, pad), Offset(pad + 5 * cell, pad + 2 * cell), linePaint);
    canvas.drawLine(Offset(pad + 5 * cell, pad), Offset(pad + 3 * cell, pad + 2 * cell), linePaint);
    canvas.drawLine(Offset(pad + 3 * cell, pad + 7 * cell), Offset(pad + 5 * cell, pad + 9 * cell), linePaint);
    canvas.drawLine(Offset(pad + 5 * cell, pad + 7 * cell), Offset(pad + 3 * cell, pad + 9 * cell), linePaint);

    // 楚河汉界文字
    _drawText(canvas, '楚 河', Offset(pad + 2 * cell, pad + 4.5 * cell), cell * 0.35);
    _drawText(canvas, '漢 界', Offset(pad + 6 * cell, pad + 4.5 * cell), cell * 0.35);

    // 炮/兵位置标记
    const markPositions = [
      [2, 1], [4, 1], [6, 1], [3, 2], [5, 2],
      [2, 7], [4, 7], [6, 7], [3, 6], [5, 6],
      [1, 3], [7, 3], [1, 5], [7, 5],
      [0, 3], [8, 3], [0, 5], [8, 5],
    ];
    final markLen = cell * 0.15;
    final markGap = cell * 0.08;
    for (final mp in markPositions) {
      final cc = mp[0], rr = mp[1];
      final cx = pad + cc * cell;
      final cy = pad + rr * cell;
      final dirs = <List<double>>[];
      if (cc > 0) {
        dirs.add([-1, -1]);
        dirs.add([-1, 1]);
      }
      if (cc < 8) {
        dirs.add([1, -1]);
        dirs.add([1, 1]);
      }
      for (final d in dirs) {
        final dx = d[0], dy = d[1];
        canvas.drawLine(Offset(cx + dx * markGap, cy + dy * markGap),
            Offset(cx + dx * markGap, cy + dy * (markGap + markLen)), linePaint);
        canvas.drawLine(Offset(cx + dx * markGap, cy + dy * markGap),
            Offset(cx + dx * (markGap + markLen), cy + dy * markGap), linePaint);
      }
    }

    // 上一步高亮（黄色）
    if (lastMove != null) {
      final fillPaint = Paint()..color = const Color(0x40FFC800);
      final fr = lastMove!.from[0], fc = lastMove!.from[1];
      final tr = lastMove!.to[0], tc = lastMove!.to[1];
      canvas.drawRect(
        Rect.fromLTWH(pad + fc * cell - cell * 0.4, pad + fr * cell - cell * 0.4, cell * 0.8, cell * 0.8),
        fillPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(pad + tc * cell - cell * 0.4, pad + tr * cell - cell * 0.4, cell * 0.8, cell * 0.8),
        fillPaint,
      );
    }

    // 选中高亮（绿色）
    if (selected != null) {
      final sr = selected![0], sc = selected![1];
      canvas.drawRect(
        Rect.fromLTWH(pad + sc * cell - cell * 0.4, pad + sr * cell - cell * 0.4, cell * 0.8, cell * 0.8),
        Paint()..color = const Color(0x4000B400),
      );
    }

    // 合法落点提示
    for (final m in validMoves) {
      final mr = m[0], mc = m[1];
      final mx = pad + mc * cell;
      final my = pad + mr * cell;
      if (board[mr][mc] != kEmpty) {
        // 可吃子：红圈
        canvas.drawCircle(Offset(mx, my), cell * 0.42,
            Paint()
              ..color = const Color(0xB4DC3232)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      } else {
        // 空位：绿点
        canvas.drawCircle(Offset(mx, my), cell * 0.12,
            Paint()..color = const Color(0x80009600));
      }
    }

    // 棋子（动画中的起点棋子不画，单独画在插值位置）
    for (var r = 0; r < kRows; r++) {
      for (var c = 0; c < kCols; c++) {
        final p = board[r][c];
        if (p == kEmpty) continue;
        if (moving != null && moving!.from[0] == r && moving!.from[1] == c) continue;
        _drawPiece(canvas, p, pad + c * cell, pad + r * cell, cell);
      }
    }

    // 动画中的棋子（ease-out 缓动 + 中段抬升）
    if (moving != null) {
      final t = animProgress.clamp(0.0, 1.0);
      final e = 1 - math.pow(1 - t, 3).toDouble();
      final fr = moving!.from[0], fc = moving!.from[1];
      final tr = moving!.to[0], tc = moving!.to[1];
      final fx = pad + fc * cell, fy = pad + fr * cell;
      final tx = pad + tc * cell, ty = pad + tr * cell;
      final cx = fx + (tx - fx) * e;
      final cy = fy + (ty - fy) * e;
      final lift = math.sin(t * math.pi) * cell * 0.25;
      _drawPiece(canvas, moving!.piece, cx, cy - lift, cell);
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF5C3D2E),
          fontFamily: 'serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawPiece(Canvas canvas, int p, double cx, double cy, double cell) {
    final red = p > 0;
    final pr = cell * 0.42;

    // 阴影
    canvas.drawCircle(
      Offset(cx + 2, cy + 2),
      pr,
      Paint()
        ..color = const Color(0x59000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // 棋子本体径向渐变（对齐 #fff8e8 → #f0deb0 → #c8a86e）
    final grad = RadialGradient(
      center: Alignment(-0.3, -0.3),
      radius: 1.3,
      colors: const [Color(0xFFFFF8E8), Color(0xFFF0DEB0), Color(0xFFC8A86E)],
      stops: const [0.0, 0.6, 1.0],
    );
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: pr);
    canvas.drawCircle(Offset(cx, cy), pr, Paint()..shader = grad.createShader(rect));

    // 外圈（红 #8b4513 / 黑 #2c2c2c）
    canvas.drawCircle(Offset(cx, cy), pr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = red ? const Color(0xFF8B4513) : const Color(0xFF2C2C2C));
    // 内圈（红 #a0522d / 黑 #3a3a3a）
    canvas.drawCircle(Offset(cx, cy), pr * 0.82,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = red ? const Color(0xFFA0522D) : const Color(0xFF3A3A3A));

    // 棋子文字（红 #c0392b / 黑 #2c3e50，楷体）
    final name = kPieceNames[p] ?? '';
    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: pr * 1.15,
          fontWeight: FontWeight.bold,
          color: red ? const Color(0xFFC0392B) : const Color(0xFF2C3E50),
          fontFamily: 'KaiTi',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2 + 1));
  }

  @override
  bool shouldRepaint(covariant _ChessBoardPainter old) => true;
}
