/// 五子棋 AI 逻辑：一比一复刻参考项目 GomokuGame.jsx 的脚本 AI。
///
/// 参考实现要点（严格对齐）：
/// - 15×15 棋盘，board[y][x]：0 空 / 1 黑 / 2 白
/// - 评分表 SCORE_TABLE：5连=100万；4连 两头=10万 一头=1万；3连 两头=1万 一头=1000；
///   2连 两头=1000 一头=100；1连 两头=100 一头=10；openEnds==0 记 0
/// - 难度 DIFFICULTY_CONFIG：
///   easy   radius=1 attackW=1.0 defenseW=0.5 randomTop=5 delay=200ms
///   normal radius=2 attackW=1.1 defenseW=1.0 randomTop=1 delay=300ms
///   hard   radius=3 attackW=1.2 defenseW=1.5 randomTop=1 delay=400ms
/// - 候选点只取已有棋子周围 radius 格内的空位；空棋盘走天元(7,7)
/// - score = attack*attackW + defense*defenseW；easy 从 Top5 随机，其余取最高
library;

import 'dart:math' as math;

const int kBoardSize = 15;

/// 评分表（对齐 SCORE_TABLE）
const Map<int, Map<String, int>> _scoreTable = {
  5: {'both': 1000000, 'one': 1000000},
  4: {'both': 100000, 'one': 10000},
  3: {'both': 10000, 'one': 1000},
  2: {'both': 1000, 'one': 100},
  1: {'both': 100, 'one': 10},
};

int scoreFor(int count, int openEnds) {
  if (count >= 5) return _scoreTable[5]!['both']!;
  if (openEnds == 0) return 0;
  final t = _scoreTable[count];
  if (t == null) return 0;
  return openEnds == 2 ? t['both']! : t['one']!;
}

/// 评估在 (x,y) 落子后，player 在四个方向上的得分总和
int evaluateCellForPlayer(List<List<int>> board, int x, int y, int player) {
  const dirs = [
    [1, 0],
    [0, 1],
    [1, 1],
    [1, -1]
  ];
  var total = 0;
  for (final d in dirs) {
    final dx = d[0], dy = d[1];
    var count = 1, openEnds = 0;
    // 正方向
    for (var s = 1; s <= 4; s++) {
      final nx = x + dx * s, ny = y + dy * s;
      if (nx < 0 || nx >= kBoardSize || ny < 0 || ny >= kBoardSize) break;
      if (board[ny][nx] == player) {
        count++;
      } else {
        if (board[ny][nx] == 0) openEnds++;
        break;
      }
    }
    // 反方向
    for (var s = 1; s <= 4; s++) {
      final nx = x - dx * s, ny = y - dy * s;
      if (nx < 0 || nx >= kBoardSize || ny < 0 || ny >= kBoardSize) break;
      if (board[ny][nx] == player) {
        count++;
      } else {
        if (board[ny][nx] == 0) openEnds++;
        break;
      }
    }
    total += scoreFor(count, openEnds);
  }
  return total;
}

/// 难度配置（对齐 DIFFICULTY_CONFIG）
class GomokuDifficultyConfig {
  final int radius;
  final double attackW;
  final double defenseW;
  final int randomTop;
  final int delayMs;
  final String label;

  const GomokuDifficultyConfig({
    required this.radius,
    required this.attackW,
    required this.defenseW,
    required this.randomTop,
    required this.delayMs,
    required this.label,
  });
}

const Map<String, GomokuDifficultyConfig> kDifficultyConfig = {
  'easy': GomokuDifficultyConfig(
      radius: 1, attackW: 1.0, defenseW: 0.5, randomTop: 5, delayMs: 200, label: '简单'),
  'normal': GomokuDifficultyConfig(
      radius: 2, attackW: 1.1, defenseW: 1.0, randomTop: 1, delayMs: 300, label: '正常'),
  'hard': GomokuDifficultyConfig(
      radius: 3, attackW: 1.2, defenseW: 1.5, randomTop: 1, delayMs: 400, label: '难'),
};

class GomokuMove {
  final int x;
  final int y;
  const GomokuMove(this.x, this.y);
}

class _Candidate {
  final int x;
  final int y;
  final double score;
  _Candidate(this.x, this.y, this.score);
}

/// 寻找最佳落点（对齐 findBestMove）。aiPlayer/humanPlayer 为 1/2。
GomokuMove findBestMove(
  List<List<int>> board,
  int aiPlayer,
  int humanPlayer, {
  String difficulty = 'normal',
  math.Random? rng,
}) {
  final cfg = kDifficultyConfig[difficulty] ?? kDifficultyConfig['normal']!;

  // 空棋盘走天元
  var hasStones = false;
  outer:
  for (var r = 0; r < kBoardSize; r++) {
    for (var c = 0; c < kBoardSize; c++) {
      if (board[r][c] != 0) {
        hasStones = true;
        break outer;
      }
    }
  }
  if (!hasStones) return const GomokuMove(7, 7);

  final candidates = <_Candidate>[];
  for (var y = 0; y < kBoardSize; y++) {
    for (var x = 0; x < kBoardSize; x++) {
      if (board[y][x] != 0) continue;
      // 只评估已有棋子周围 radius 格内的空位
      var near = false;
      for (var dy = -cfg.radius; dy <= cfg.radius && !near; dy++) {
        for (var dx = -cfg.radius; dx <= cfg.radius && !near; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 &&
              nx < kBoardSize &&
              ny >= 0 &&
              ny < kBoardSize &&
              board[ny][nx] != 0) {
            near = true;
          }
        }
      }
      if (!near) continue;

      final attack = evaluateCellForPlayer(board, x, y, aiPlayer);
      final defense = evaluateCellForPlayer(board, x, y, humanPlayer);
      final score = attack * cfg.attackW + defense * cfg.defenseW;
      candidates.add(_Candidate(x, y, score));
    }
  }

  if (candidates.isEmpty) {
    // 兜底：任意空位
    for (var y = 0; y < kBoardSize; y++) {
      for (var x = 0; x < kBoardSize; x++) {
        if (board[y][x] == 0) return GomokuMove(x, y);
      }
    }
    return const GomokuMove(-1, -1);
  }

  candidates.sort((a, b) => b.score.compareTo(a.score));

  // easy：从前 randomTop 个候选中随机选一个
  final random = rng ?? math.Random();
  if (cfg.randomTop > 1 && candidates.length > 1) {
    final topN = math.min(cfg.randomTop, candidates.length);
    final pick = candidates[random.nextInt(topN)];
    return GomokuMove(pick.x, pick.y);
  }

  return GomokuMove(candidates[0].x, candidates[0].y);
}

/// 胜负判定：(x,y) 落子后 player 是否五连（对齐 checkWin）
bool checkWin(List<List<int>> board, int x, int y, int player) {
  const dirs = [
    [1, 0],
    [0, 1],
    [1, 1],
    [1, -1]
  ];
  bool inside(int xx, int yy) =>
      xx >= 0 && xx < kBoardSize && yy >= 0 && yy < kBoardSize;
  for (final d in dirs) {
    final dx = d[0], dy = d[1];
    var count = 1;
    for (var s = 1; s < 5; s++) {
      final nx = x + dx * s, ny = y + dy * s;
      if (!inside(nx, ny) || board[ny][nx] != player) break;
      count++;
    }
    for (var s = 1; s < 5; s++) {
      final nx = x - dx * s, ny = y - dy * s;
      if (!inside(nx, ny) || board[ny][nx] != player) break;
      count++;
    }
    if (count >= 5) return true;
  }
  return false;
}

/// 创建空棋盘
List<List<int>> emptyBoard() =>
    List.generate(kBoardSize, (_) => List<int>.filled(kBoardSize, 0));
