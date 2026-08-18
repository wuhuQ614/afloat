/// 五子棋：15×15 棋盘，支持「人人对战」与「人机对战（简单/正常/难）」。
/// 完全使用 App 主题色系统，含悔棋 / 重新开始 / 交换先手。
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme_colors.dart' show AppColors;

/// 方向向量：横向、纵向、两对角线
const List<Offset> _dirs = [
  Offset(0, 1),
  Offset(1, 0),
  Offset(1, 1),
  Offset(1, -1),
];

/// 评分表：连续子数 + 开放端(both/one) → 分值
const Map<int, Map<String, int>> _scoreTable = {
  5: {'both': 1000000},
  4: {'both': 100000, 'one': 10000},
  3: {'both': 10000, 'one': 1000},
  2: {'both': 1000, 'one': 100},
  1: {'both': 100, 'one': 10},
};

/// 本地 AI 难度配置
class _AiConfig {
  final int radius;
  final double attackW;
  final double defenseW;
  final int randomTop;
  final int delay;
  const _AiConfig({
    required this.radius,
    required this.attackW,
    required this.defenseW,
    required this.randomTop,
    required this.delay,
  });
}

const Map<String, _AiConfig> _difficultyConfig = {
  'easy': _AiConfig(radius: 1, attackW: 1.0, defenseW: 0.5, randomTop: 5, delay: 200),
  'normal': _AiConfig(radius: 2, attackW: 1.1, defenseW: 1.0, randomTop: 1, delay: 300),
  'hard': _AiConfig(radius: 3, attackW: 1.2, defenseW: 1.5, randomTop: 1, delay: 400),
};

/// 候选棋步（空位 + 评分）
class _Candidate {
  final int x;
  final int y;
  final double score;
  const _Candidate(this.x, this.y, this.score);
}

class GomokuPage extends StatefulWidget {
  const GomokuPage({super.key});

  @override
  State<GomokuPage> createState() => _GomokuPageState();
}

class _GomokuPageState extends State<GomokuPage> {
  static const int size = 15; // 棋盘 15×15
  static const int black = 1; // 黑子
  static const int white = 2; // 白子
  static const int empty = 0;

  // ---- 界面流 ----
  String screen = 'mode'; // mode | difficulty | game
  String? mode; // null | pvp | pve
  String difficulty = 'normal'; // easy | normal | hard

  // ---- 对局状态 ----
  late List<List<int>> _board; // 0空/1黑/2白
  int _current = 1; // 当前执棋
  final List<(int, int, int)> _moves = []; // 落子记录 (x,y,player)
  int? _winPlayer; // 获胜方；null 进行中，3 平局
  List<(int, int)> _winLine = []; // 获胜连线
  bool _aiThinking = false; // AI 是否正在思考（禁用落子/悔棋/交换）
  int _firstStone = 1; // 本局先手颜色（pvp 交换先手时切换）
  int _playerStone = 1; // 人机模式下玩家执子颜色

  @override
  void initState() {
    super.initState();
    _resetBoard();
  }

  // ---------------- 基础操作 ----------------

  void _resetBoard() {
    _board = List.generate(size, (_) => List.filled(size, 0));
    _moves.clear();
    _winPlayer = null;
    _winLine.clear();
    _aiThinking = false;
    _current = _firstStone;
  }

  /// 在 (x,y) 落子（黑白交替、判胜负）
  void _placeStone(int x, int y, int player) {
    _board[y][x] = player;
    _moves.add((x, y, player));
    final line = _checkWin(x, y, player);
    if (line != null) {
      _winPlayer = player;
      _winLine = line;
    } else if (_moves.length == size * size) {
      _winPlayer = 3; // 平局
    } else {
      _current = player == 1 ? 2 : 1;
    }
  }

  /// 玩家点击落子入口
  void _onBoardTap(int x, int y) {
    if (screen != 'game') return;
    if (_aiThinking) return;
    if (_winPlayer != null) return;
    if (_board[y][x] != empty) return;
    if (mode == 'pve' && _current != _playerStone) return; // 还不是玩家回合
    setState(() => _placeStone(x, y, _current));
    if (_winPlayer == null && mode == 'pve') {
      setState(() => _aiThinking = true);
      _scheduleAi();
    }
  }

  /// 悔棋：人人撤一步；人机撤销 AI + 玩家各一步（不足则一步）
  void _undo() {
    if (screen != 'game') return;
    if (_aiThinking) return;
    if (_moves.isEmpty) return;
    setState(() {
      void popOne() {
        final m = _moves.removeLast();
        _board[m.$2][m.$1] = empty;
      }

      popOne();
      if (mode == 'pve' && _moves.isNotEmpty) {
        popOne();
      }
      _winPlayer = null;
      _winLine.clear();
      _current = _moves.isEmpty ? _firstStone : (_moves.last.$3 == 1 ? 2 : 1);
    });
  }

  /// 重新开始（保留模式/难度）
  void _restart() {
    if (screen != 'game') return;
    setState(() => _resetBoard());
    if (mode == 'pve' && _playerStone == white) {
      // 玩家执白时，AI（黑）先行
      setState(() => _aiThinking = true);
      _scheduleAi();
    }
  }

  /// 交换先手：重置棋盘，先手/玩家颜色互换
  void _swapFirst() {
    if (screen != 'game') return;
    if (_aiThinking) return;
    if (mode == 'pvp') {
      final nf = _firstStone == 1 ? 2 : 1;
      setState(() {
        _firstStone = nf;
        _resetBoard();
      });
    } else {
      setState(() {
        _resetBoard();
        _playerStone = _playerStone == 1 ? 2 : 1;
      });
      if (_playerStone == white) {
        setState(() => _aiThinking = true);
        _scheduleAi();
      }
    }
  }

  /// 人机模式下，调度 AI 延迟落子
  void _scheduleAi() {
    final cfg = _difficultyConfig[difficulty]!;
    Future.delayed(Duration(milliseconds: cfg.delay), () {
      if (!mounted || screen != 'game') return;
      if (!_aiThinking) return; // 已被重置/切换取消
      _performAiMove();
    });
  }

  void _performAiMove() {
    final ai = _current;
    final human = ai == black ? white : black;
    setState(() {
      final mv = findBestMove(_board, ai, human, difficulty);
      if (mv == null) {
        _aiThinking = false;
        return;
      }
      _placeStone(mv.$1, mv.$2, ai);
      _aiThinking = false;
    });
  }

  // ---------------- 屏切控制 ----------------

  void _goMode() {
    setState(() {
      screen = 'mode';
      mode = null;
      _aiThinking = false;
      _resetBoard();
    });
  }

  void _startPvp() {
    setState(() {
      screen = 'game';
      mode = 'pvp';
      _playerStone = black;
      _firstStone = black;
      _resetBoard();
    });
  }

  void _startPve(String diff) {
    setState(() {
      screen = 'game';
      mode = 'pve';
      difficulty = diff;
      _playerStone = black;
      _firstStone = black;
      _resetBoard();
    });
  }

  // ---------------- 胜负判定 ----------------

  /// 检查以 (x,y) 为端是否成五连，返回连线坐标
  List<(int, int)>? _checkWin(int x, int y, int player) {
    for (final d in _dirs) {
      final line = <(int, int)>[(x, y)];
      final dx = d.dx.round();
      final dy = d.dy.round();
      // 正方向
      for (var i = 1; i < 5; i++) {
        final nx = x + dx * i;
        final ny = y + dy * i;
        if (nx < 0 || nx >= size || ny < 0 || ny >= size) break;
        if (_board[ny][nx] != player) break;
        line.add((nx, ny));
      }
      if (line.length >= 5) return line;
      // 反方向
      final back = <(int, int)>[];
      for (var i = 1; i < 5; i++) {
        final nx = x - dx * i;
        final ny = y - dy * i;
        if (nx < 0 || nx >= size || ny < 0 || ny >= size) break;
        if (_board[ny][nx] != player) break;
        back.insert(0, (nx, ny));
      }
      final total = back + line;
      if (total.length >= 5) return total;
    }
    return null;
  }

  // ---------------- 本地 AI ----------------

  static bool _inBoard(int x, int y) => x >= 0 && x < size && y >= 0 && y < size;

  /// 对某空位 (x,y)、某方 player，四方向统计连续同色与开放端，按评分表计分
  static int _evaluatePoint(List<List<int>> board, int x, int y, int player) {
    var total = 0;
    for (final d in _dirs) {
      total += _countDirection(board, x, y, player, d);
    }
    return total;
  }

  static int _countDirection(
      List<List<int>> board, int x, int y, int player, Offset d) {
    final dx = d.dx.round();
    final dy = d.dy.round();
    var count = 1; // 假定该位置已落当前方
    var openEnds = 0;

    var nx = x + dx;
    var ny = y + dy;
    while (_inBoard(nx, ny) && board[ny][nx] == player) {
      count++;
      nx += dx;
      ny += dy;
    }
    if (_inBoard(nx, ny) && board[ny][nx] == empty) openEnds++;

    nx = x - dx;
    ny = y - dy;
    while (_inBoard(nx, ny) && board[ny][nx] == player) {
      count++;
      nx -= dx;
      ny -= dy;
    }
    if (_inBoard(nx, ny) && board[ny][nx] == empty) openEnds++;

    if (count >= 5) return _scoreTable[5]!['both']!;
    if (openEnds == 0) return 0;
    final key = openEnds == 2 ? 'both' : 'one';
    return _scoreTable[count.clamp(1, 4)]![key]!;
  }

  /// 空位是否在已有棋子的半径格内
  static bool _nearAny(List<List<int>> board, int x, int y, int radius) {
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final nx = x + dx;
        final ny = y + dy;
        if (_inBoard(nx, ny) && board[ny][nx] != empty) return true;
      }
    }
    return false;
  }

  /// 寻找最优落子位置；棋盘空时走天元 (7,7)
  static (int, int)? findBestMove(
      List<List<int>> board, int ai, int human, String difficulty) {
    final cfg = _difficultyConfig[difficulty]!;

    var occupied = 0;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (board[y][x] != empty) occupied++;
      }
    }
    if (occupied == 0) return (7, 7);

    final candidates = <_Candidate>[];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (board[y][x] != empty) continue;
        if (!_nearAny(board, x, y, cfg.radius)) continue;
        final attack = _evaluatePoint(board, x, y, ai);
        final defense = _evaluatePoint(board, x, y, human);
        final score = attack * cfg.attackW + defense * cfg.defenseW;
        candidates.add(_Candidate(x, y, score));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));

    // 若无候选（极端情况）退化为全盘扫描
    if (candidates.isEmpty) {
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if (board[y][x] == empty) candidates.add(_Candidate(x, y, 0));
        }
      }
      if (candidates.isEmpty) return null;
    }

    if (cfg.randomTop > 1 && candidates.length > 1) {
      final top = candidates.take(cfg.randomTop).toList();
      final pick = top[math.Random().nextInt(top.length)];
      return (pick.x, pick.y);
    }
    return (candidates.first.x, candidates.first.y);
  }

  // ---------------- UI 文案 ----------------

  String _stoneText(int stone) => stone == black ? '黑子' : '白子';

  String _statusText() {
    if (_winPlayer != null) {
      return _winPlayer == 3 ? '平局' : '${_stoneText(_winPlayer!)}胜利';
    }
    if (mode == 'pve') {
      if (_aiThinking) return 'AI 思考中…';
      return '轮到${_stoneText(_current)}（${_current == _playerStone ? '你' : 'AI'}）';
    }
    return '轮到${_stoneText(_current)}';
  }

  String get _modeTitle {
    if (mode == 'pve') {
      final dn = switch (difficulty) {
        'easy' => '简单',
        'hard' => '难',
        _ => '正常',
      };
      return '人机·$dn';
    }
    return '人人对战';
  }

  bool get _boardLight => AppColors.of(context).isLight;

  // ---------------- UI 构建 ----------------

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: switch (screen) {
            'mode' => _buildMode(context),
            'difficulty' => _buildDifficulty(context),
            _ => _buildGame(context),
          },
        ),
      ),
    );
  }

  // ---- 模式选择 ----
  Widget _buildMode(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '五子棋',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: c.primaryText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '选择对战模式',
          style: TextStyle(fontSize: 15, color: c.textSecondary),
        ),
        const SizedBox(height: 28),
        _ModeCard(
          icon: Icons.people_alt_outlined,
          title: '人人对战',
          subtitle: '和朋友一起下棋',
          onTap: _startPvp,
        ),
        const SizedBox(height: 16),
        _ModeCard(
          icon: Icons.smart_toy_outlined,
          title: '人机对战',
          subtitle: '挑战 AI 对手',
          onTap: () => setState(() => screen = 'difficulty'),
        ),
      ],
    );
  }

  // ---- 难度选择 ----
  Widget _buildDifficulty(BuildContext context) {
    final c = AppColors.of(context);
    final items = <(String, String, String)>[
      ('easy', '简单', 'AI 随机落子，适合新手'),
      ('normal', '正常', 'AI 会攻会守，有一定挑战'),
      ('hard', '难', 'AI 攻防兼备，全力出击'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _goMode,
              icon: const Icon(Icons.arrow_back),
              color: c.primary,
              tooltip: '返回',
            ),
            Text(
              '选择难度',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ModeCard(
              icon: it.$1 == 'easy'
                  ? Icons.sentiment_satisfied_alt_rounded
                  : (it.$1 == 'normal'
                      ? Icons.equalizer_rounded
                      : Icons.local_fire_department_rounded),
              title: it.$2,
              subtitle: it.$3,
              selected: difficulty == it.$1,
              onTap: () => _startPve(it.$1),
            ),
          ),
      ],
    );
  }

  // ---- 对局 ----
  Widget _buildGame(BuildContext context) {
    final c = AppColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部：返回 + 模式标题
        Row(
          children: [
            IconButton(
              onPressed: _goMode,
              icon: const Icon(Icons.arrow_back),
              color: c.primary,
              tooltip: '返回',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _modeTitle,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 状态条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.cardAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _statusText(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _winPlayer != null
                        ? ((_winPlayer == 3)
                            ? c.primaryText
                            : (_winPlayer == black ? Colors.black : Colors.white))
                        : c.text,
                  ),
                ),
              ),
              // 当前棋色圆点 + 文字
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _winPlayer != null
                      ? c.textTertiary
                      : (_current == black ? Colors.black : Colors.white),
                  border: Border.all(
                    color: _current == white || _winPlayer != null
                        ? Colors.grey.shade400
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _winPlayer != null
                    ? '结束'
                    : _stoneText(_current),
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // AI 思考胶囊
        if (_aiThinking && mode == 'pve')
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: c.primaryBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.primaryBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 思考中…',
                  style: TextStyle(
                    fontSize: 13,
                    color: c.primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        // 棋盘
        Center(
          child: Stack(
            children: [
              ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  gradient: c.isLight
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFEBC795), Color(0xFFDFB275)],
                        )
                      : null,
                  color: c.isLight ? null : const Color(0xFF2A2A30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: c.isLight
                        ? const Color(0xFFD9B078)
                        : const Color(0xFF3D3D45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (ctx, cons) {
                    final cell = cons.maxWidth / size;
                    return GestureDetector(
                      onTapDown: (d) {
                        final col = (d.localPosition.dx / cell).floor();
                        final row = (d.localPosition.dy / cell).floor();
                        if (col < 0 || col >= size || row < 0 || row >= size) {
                          return;
                        }
                        // 接近交叉点才落子
                        final cx = d.localPosition.dx / cell;
                        final cy = d.localPosition.dy / cell;
                        final near =
                            (cx - (col + 0.5)).abs() <= 0.3 &&
                            (cy - (row + 0.5)).abs() <= 0.3;
                        if (near) _onBoardTap(col, row);
                      },
                      child: CustomPaint(
                        size: Size(cons.maxWidth, cons.maxHeight),
                        painter: _GomokuPainter(
                          board: _board,
                          light: _boardLight,
                          winLine: _winLine,
                          lastMove: _moves.isEmpty
                              ? null
                              : (_moves.last.$1, _moves.last.$2),
                          cell: cell,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
              // 胜利遮罩
              if (_winPlayer != null)
                Positioned.fill(
                  child: GestureDetector(
                    onTap: null,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: Text(
                        _winPlayer == 3
                            ? '平局'
                            : '${_stoneText(_winPlayer!)}胜利',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 底部按钮排
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _GameButton(
              icon: Icons.refresh_rounded,
              label: '重新开始',
              onTap: _restart,
            ),
            const SizedBox(width: 12),
            _GameButton(
              icon: Icons.undo_rounded,
              label: '悔棋',
              onTap: _aiThinking ? null : _undo,
            ),
            const SizedBox(width: 12),
            _GameButton(
              icon: Icons.swap_horiz_rounded,
              label: '交换先手',
              onTap: _aiThinking ? null : _swapFirst,
            ),
          ],
        ),
      ],
    );
  }
}

/// 模式/难度大卡片按钮
class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final active = selected;
    return Material(
      color: active ? c.primaryBgStrong : c.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active ? c.primaryBorder : c.border,
              width: active ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: active ? c.primaryBgStrong : c.primaryBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: c.primary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底部操作按钮
class _GameButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _GameButton(
      {required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final disabled = onTap == null;
    return Material(
      color: disabled ? c.inputFill : c.primaryBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: disabled ? c.chipBorder : c.primaryBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 18, color: disabled ? c.textTertiary : c.primary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: disabled ? c.textTertiary : c.primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 棋盘画家：木色背景渐变 + 网格 + 星位 + 棋子（黑白渐变/高光）+ 最后一手红点 + 五连红线
class _GomokuPainter extends CustomPainter {
  final List<List<int>> board;
  final bool light;
  final List<(int, int)> winLine;
  final (int, int)? lastMove;
  final double cell;

  _GomokuPainter({
    required this.board,
    required this.light,
    required this.winLine,
    required this.lastMove,
    required this.cell,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const n = _GomokuPageState.size;
    final lineColor =
        light ? const Color(0xFFB08D60) : const Color(0xFF5A5A64);
    final gridPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    // 网格线
    for (var i = 0; i < n; i++) {
      final pos = cell * (i + 0.5);
      canvas.drawLine(Offset(cell / 2, pos), Offset(size.width - cell / 2, pos),
          gridPaint);
      canvas.drawLine(Offset(pos, cell / 2), Offset(pos, size.height - cell / 2),
          gridPaint);
    }

    // 星位（天元 + 四角）
    const stars = [3, 7, 11];
    final starPaint = Paint()..color = lineColor;
    for (final sx in stars) {
      for (final sy in stars) {
        canvas.drawCircle(
            Offset(cell * (sx + 0.5), cell * (sy + 0.5)), 3, starPaint);
      }
    }

    // 棋子
    final r = cell * 0.42;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final v = board[y][x];
        if (v == 0) continue;
        final center = Offset(cell * (x + 0.5), cell * (y + 0.5));
        if (v == 1) {
          // 黑子：径向渐变 + 高光
          canvas.drawCircle(
            center,
            r,
            Paint()
              ..shader = const RadialGradient(
                colors: [Color(0xFF55555C), Color(0xFF000000)],
                stops: [0.0, 1.0],
              ).createShader(Rect.fromCircle(center: center, radius: r)),
          );
          canvas.drawCircle(
              Offset(center.dx - r * 0.3, center.dy - r * 0.3),
              r * 0.22,
              Paint()..color = Colors.white24);
        } else {
          // 白子：浅色渐变 + 描边
          canvas.drawCircle(
            center,
            r,
            Paint()
              ..shader = const RadialGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFDCD6CC)],
                stops: [0.0, 1.0],
              ).createShader(Rect.fromCircle(center: center, radius: r)),
          );
          canvas.drawCircle(
              center,
              r,
              Paint()
                ..style = PaintingStyle.stroke
                ..color = Colors.grey.shade400
                ..strokeWidth = 1);
        }
      }
    }

    // 五连红线高亮
    if (winLine.length >= 2) {
      final ink = Paint()
        ..color = const Color(0xFFEF4444)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      final c1 = Offset(cell * (winLine.first.$1 + 0.5),
          cell * (winLine.first.$2 + 0.5));
      final c2 = Offset(cell * (winLine.last.$1 + 0.5),
          cell * (winLine.last.$2 + 0.5));
      canvas.drawLine(c1, c2, ink);
    }

    // 最后一手红点标记
    if (lastMove != null) {
      final dotPaint = Paint()..color = const Color(0xFFEF4444);
      canvas.drawCircle(
        Offset(cell * (lastMove!.$1 + 0.5), cell * (lastMove!.$2 + 0.5)),
        r * 0.22,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GomokuPainter oldDelegate) =>
      oldDelegate.board != board ||
      oldDelegate.light != light ||
      oldDelegate.winLine != winLine ||
      oldDelegate.lastMove != lastMove;
}