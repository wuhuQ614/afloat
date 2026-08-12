/// 五子棋页面：一比一复刻参考项目 GomokuGame.jsx。
///
/// 功能对齐：
/// - 15×15 棋盘，黑子(1)先手，人人对战 / 人机对战（脚本AI三档难度）
/// - 悔棋：人人模式撤一步；人机模式撤销玩家+AI各一步
/// - 交换先手：清空棋盘换先手；人机模式白子先手时 AI 自动走天元
/// - 棋盘绘制：木纹渐变底、星位(3/7/11)、棋子径向渐变带阴影、最后落子红点
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../theme_colors.dart';
import 'gomoku_ai.dart';

class GomokuPage extends StatefulWidget {
  const GomokuPage({super.key});

  @override
  State<GomokuPage> createState() => _GomokuPageState();
}

class _GomokuPageState extends State<GomokuPage> {
  // 游戏模式：null=模式选择页；'pvp'人人；'pve'人机
  String? _gameMode;
  String _difficulty = 'normal';

  List<List<int>> _board = emptyBoard();
  final List<GomokuMove> _history = [];
  int _currentPlayer = 1;
  int _firstPlayer = 1;
  bool _gameOver = false;
  String _winMessage = '';
  bool _aiThinking = false;
  Timer? _aiTimer;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _aiTimer?.cancel();
    super.dispose();
  }

  String get _statusText {
    if (_gameOver) return _winMessage;
    if (_aiThinking) return 'AI 思考中...';
    if (_gameMode == 'pve') {
      return _currentPlayer == 1 ? '黑子先手（你）' : '白子（AI）回合';
    }
    return _currentPlayer == 1 ? '轮到黑子' : '轮到白子';
  }

  String get _titleText {
    if (_gameMode == 'pve') {
      return '人机 · ${kDifficultyConfig[_difficulty]?.label ?? ''}';
    }
    return '人人对战';
  }

  // ==================== 落子 ====================
  void _placeStone(int x, int y, int player) {
    setState(() {
      _board[y][x] = player;
      _history.add(GomokuMove(x, y));
    });
    if (checkWin(_board, x, y, player)) {
      setState(() {
        _gameOver = true;
        if (_gameMode == 'pve') {
          _winMessage = player == 1 ? '你赢了！' : 'AI 获胜！';
        } else {
          _winMessage = player == 1 ? '黑子获胜！' : '白子获胜！';
        }
      });
      return;
    }
    // 平局判定
    if (_history.length >= kBoardSize * kBoardSize) {
      setState(() {
        _gameOver = true;
        _winMessage = '平局';
      });
      return;
    }
    setState(() => _currentPlayer = player == 1 ? 2 : 1);
    // 人机模式轮到 AI
    if (_gameMode == 'pve' && _currentPlayer == 2 && !_gameOver) {
      _scheduleAiMove();
    }
  }

  void _onTapBoard(int x, int y) {
    if (_gameOver || _aiThinking) return;
    if (_gameMode == 'pve' && _currentPlayer != 1) return;
    if (_board[y][x] != 0) return;
    _placeStone(x, y, _currentPlayer);
  }

  // ==================== AI ====================
  void _scheduleAiMove() {
    final delay = kDifficultyConfig[_difficulty]?.delayMs ?? 300;
    setState(() => _aiThinking = true);
    _aiTimer?.cancel();
    _aiTimer = Timer(Duration(milliseconds: delay), () {
      if (_disposed || _gameOver) return;
      final move = findBestMove(_board, 2, 1, difficulty: _difficulty);
      if (_disposed || move.x < 0) return;
      setState(() => _aiThinking = false);
      _placeStone(move.x, move.y, 2);
    });
  }

  // ==================== 重开 / 悔棋 / 交换先手 ====================
  void _restartGame() {
    _aiTimer?.cancel();
    setState(() {
      _board = emptyBoard();
      _history.clear();
      _currentPlayer = 1;
      _firstPlayer = 1;
      _gameOver = false;
      _winMessage = '';
      _aiThinking = false;
    });
  }

  void _undoMove() {
    if (_history.isEmpty || _aiThinking) return;
    _aiTimer?.cancel();
    setState(() {
      if (_gameOver) {
        _gameOver = false;
        _winMessage = '';
      }
      if (_gameMode == 'pve') {
        // 人机模式：撤销 AI 和玩家各一步
        if (_history.length >= 2) {
          final aiStep = _history.removeLast();
          _board[aiStep.y][aiStep.x] = 0;
          final playerStep = _history.removeLast();
          _board[playerStep.y][playerStep.x] = 0;
          _currentPlayer = 1;
        } else if (_history.length == 1) {
          final last = _history.removeLast();
          _board[last.y][last.x] = 0;
          _currentPlayer = 1;
        }
      } else {
        final last = _history.removeLast();
        _board[last.y][last.x] = 0;
        // 人人模式：回到被撤销那步的执棋方
        _currentPlayer = 3 - _currentPlayer;
      }
    });
  }

  void _swapFirstPlayer() {
    final newFirst = _firstPlayer == 1 ? 2 : 1;
    _aiTimer?.cancel();
    setState(() {
      _firstPlayer = newFirst;
      _board = emptyBoard();
      _history.clear();
      _currentPlayer = newFirst;
      _gameOver = false;
      _winMessage = '';
      _aiThinking = false;
    });
    // 人机模式白子先手：AI 先走天元
    if (_gameMode == 'pve' && newFirst == 2) {
      Timer(const Duration(milliseconds: 100), () {
        if (_disposed) return;
        setState(() {
          _board[7][7] = 1;
          _history.add(const GomokuMove(7, 7));
          _currentPlayer = 2;
        });
        _scheduleAiMove();
      });
    }
  }

  // ==================== UI ====================
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_gameMode == null) {
      return _buildModeSelect(c);
    }
    return _buildGame(c);
  }

  Widget _buildModeSelect(AppColors c) {
    const diffs = ['easy', 'normal', 'hard'];
    const tags = ['深度 2', '深度 3', '深度 4'];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 眉标 + 大标题（简约高级：无图标无 emoji）
                const SizedBox(height: 8),
                Text('GOMOKU',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600,
                        color: c.textTertiary)),
                const SizedBox(height: 10),
                Text('五子棋',
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
                // 双人游戏
                _ModeCard(
                  c: c,
                  title: '双人游戏',
                  subtitle: '两人轮流落子，本地对弈',
                  onTap: () => setState(() => _gameMode = 'pvp'),
                ),
                const SizedBox(height: 24),
                Text('人机对战',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary)),
                const SizedBox(height: 10),
                // 三档难度卡片
                Row(children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                            left: i == 0 ? 0 : 4, right: i == 2 ? 0 : 4),
                        child: _DifficultyCard(
                          c: c,
                          title: kDifficultyConfig[diffs[i]]!.label,
                          tag: tags[i],
                          selected: _difficulty == diffs[i],
                          onTap: () {
                            setState(() {
                              _difficulty = diffs[i];
                              _gameMode = 'pve';
                            });
                          },
                        ),
                      ),
                    ),
                ]),
              ]),
        ),
      ),
    );
  }

  Widget _buildGame(AppColors c) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 顶栏
        SizedBox(
          width: 440,
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: () => setState(() {
                _gameMode = null;
                _restartGame();
              }),
            ),
            Text(_titleText,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
            const Spacer(),
            Text(_statusText,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _gameOver ? const Color(0xFFEF4444) : c.textSecondary)),
          ]),
        ),
        const SizedBox(height: 8),
        // 棋盘
        SizedBox(
          width: 440,
          height: 440,
          child: LayoutBuilder(builder: (ctx, cons) {
            final size = math.min(cons.maxWidth, cons.maxHeight);
            final padding = size * 0.06;
            final cell = (size - padding * 2) / (kBoardSize - 1);
            return GestureDetector(
              onTapUp: (d) {
                final x = ((d.localPosition.dx - padding) / cell).round();
                final y = ((d.localPosition.dy - padding) / cell).round();
                if (x >= 0 && x < kBoardSize && y >= 0 && y < kBoardSize) {
                  _onTapBoard(x, y);
                }
              },
              child: CustomPaint(
                size: Size(size, size),
                painter: _GomokuBoardPainter(
                  board: _board,
                  lastMove: _history.isEmpty ? null : _history.last,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        // 底部按钮
        SizedBox(
          width: 440,
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _restartGame,
                child: const Text('重新开始', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _history.isEmpty || _aiThinking ? null : _undoMove,
                child: const Text('悔棋', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _aiThinking ? null : _swapFirstPlayer,
                child: const Text('交换先手', style: TextStyle(fontSize: 13)),
              ),
            ),
          ]),
        ),
        // 胜负提示
        if (_gameOver) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(_winMessage,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ]),
    );
  }
}

/// 简约高级模式卡片（五子棋模式选择：纯文字 + 箭头，无图标无 emoji）
class _ModeCard extends StatelessWidget {
  final AppColors c;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.c,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
}

/// 难度小卡片（五子棋，横排三选一：纯文字 + 主题色选中态）
class _DifficultyCard extends StatelessWidget {
  final AppColors c;
  final String title;
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  const _DifficultyCard({
    required this.c,
    required this.title,
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = c.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : c.chatBubbleAi,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : c.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: selected ? accent : c.text)),
          const SizedBox(height: 3),
          Text(tag,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected ? accent : c.textTertiary)),
        ]),
      ),
    );
  }
}

/// 棋盘绘制器
class _GomokuBoardPainter extends CustomPainter {
  final List<List<int>> board;
  final GomokuMove? lastMove;

  _GomokuBoardPainter({required this.board, this.lastMove});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    const paddingRatio = 0.06;
    const stoneRatio = 0.42;
    final padding = s * paddingRatio;
    final cell = (s - padding * 2) / (kBoardSize - 1);

    // 背景：木纹渐变（对齐 #e8c38f → #dca96e）
    final bgRect = Rect.fromLTWH(0, 0, s, s);
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE8C38F), Color(0xFFDCA96E)],
        ).createShader(bgRect),
    );
    // 高光叠加层（对齐 rgba(255,255,255,0.06) → rgba(0,0,0,0.04)）
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.04),
          ],
        ).createShader(bgRect),
    );

    // 网格线（对齐 rgba(90,55,20,0.72)）
    final linePaint = Paint()
      ..color = const Color(0xB85A3714) // 90,55,20 alpha 0.72
      ..strokeWidth = math.max(1.0, s * 0.0028);
    for (var i = 0; i < kBoardSize; i++) {
      final p = padding + i * cell;
      canvas.drawLine(Offset(padding, p), Offset(s - padding, p), linePaint);
      canvas.drawLine(Offset(p, padding), Offset(p, s - padding), linePaint);
    }

    // 星位（对齐 [3,7,11]，rgba(60,35,10,0.8)）
    final starPaint = Paint()..color = const Color(0xCC3C230A);
    for (final r in const [3, 7, 11]) {
      for (final col in const [3, 7, 11]) {
        canvas.drawCircle(
          Offset(padding + col * cell, padding + r * cell),
          s * 0.008,
          starPaint,
        );
      }
    }

    // 棋子
    for (var y = 0; y < kBoardSize; y++) {
      for (var x = 0; x < kBoardSize; x++) {
        final p = board[y][x];
        if (p == 0) continue;
        _drawStone(canvas, x, y, p, cell, padding, stoneRatio);
      }
    }
  }

  void _drawStone(Canvas canvas, int x, int y, int player, double cell,
      double padding, double stoneRatio) {
    final cx = padding + x * cell;
    final cy = padding + y * cell;
    final r = cell * stoneRatio;

    // 阴影（对齐 rgba(0,0,0,0.28)）
    canvas.drawCircle(
      Offset(cx, cy + cell * 0.04),
      r,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 棋子径向渐变（黑 #666→#050505；白 #ffffff→#d8d8d8）
    final gradient = RadialGradient(
      center: Alignment(-0.3, -0.3),
      radius: 1.2,
      colors: player == 1
          ? [const Color(0xFF666666), const Color(0xFF050505)]
          : [const Color(0xFFFFFFFF), const Color(0xFFD8D8D8)],
    );
    final stoneRect = Rect.fromCircle(center: Offset(cx, cy), radius: r);
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..shader = gradient.createShader(stoneRect),
    );
    // 描边（黑 rgba(255,255,255,0.08)；白 rgba(0,0,0,0.14)）
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, cell * 0.045)
        ..color = player == 1
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.14),
    );

    // 最后落子红点标记（对齐 rgba(255,59,48,0.95)，半径 r*0.18）
    if (lastMove != null && lastMove!.x == x && lastMove!.y == y) {
      canvas.drawCircle(
        Offset(cx, cy),
        r * 0.18,
        Paint()..color = const Color(0xF2FF3B30),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GomokuBoardPainter old) =>
      old.board != board || old.lastMove != lastMove;
}
