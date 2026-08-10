/// 中国象棋 AI 逻辑：一比一复刻参考项目 ChineseChessGame.jsx。
///
/// 严格对齐参考实现：
/// - 10行×9列，正数红方/负数黑方，帅=±1 仕=±2 相=±3 马=±4 车=±5 炮=±6 兵=±7
/// - 子力价值 PIECE_VALUES：帅10000 仕120 相120 马280 车600 炮300 兵80（过河150）
/// - 7 种棋子完整走法（九宫/塞象眼/蹩马腿/炮翻山/兵过河/将帅照面/禁止送将）
/// - minimax + alpha-beta：easy 深度2（Top3随机），normal 深度3
library;

import 'dart:math' as math;

const int kRows = 10;
const int kCols = 9;
const int kEmpty = 0;

/// 棋子名称（红正黑负）
const Map<int, String> kPieceNames = {
  1: '帅', -1: '将',
  2: '仕', -2: '士',
  3: '相', -3: '象',
  4: '馬', -4: '马',
  5: '車', -5: '车',
  6: '砲', -6: '炮',
  7: '兵', -7: '卒',
};

/// 子力价值表
const Map<int, int> kPieceValues = {1: 10000, 2: 120, 3: 120, 4: 280, 5: 600, 6: 300, 7: 80};

typedef Board = List<List<int>>;

Board createInitialBoard() {
  final board = List.generate(kRows, (_) => List<int>.filled(kCols, kEmpty));
  board[0] = [-5, -4, -3, -2, -1, -2, -3, -4, -5];
  board[2][1] = -6;
  board[2][7] = -6;
  board[3] = [-7, 0, -7, 0, -7, 0, -7, 0, -7];
  board[6] = [7, 0, 7, 0, 7, 0, 7, 0, 7];
  board[7][1] = 6;
  board[7][7] = 6;
  board[9] = [5, 4, 3, 2, 1, 2, 3, 4, 5];
  return board;
}

bool isRed(int piece) => piece > 0;
bool sameSide(int p1, int p2) => (p1 > 0 && p2 > 0) || (p1 < 0 && p2 < 0);

Board cloneBoard(Board board) => board.map((row) => List<int>.of(row)).toList();

/// 找王位置，返回 [r, c]，不存在返回 null
List<int>? findKing(Board board, bool red) {
  for (var r = 0; r < kRows; r++) {
    for (var c = 0; c < kCols; c++) {
      if (red && board[r][c] == 1) return [r, c];
      if (!red && board[r][c] == -1) return [r, c];
    }
  }
  return null;
}

/// 将帅照面检测
bool kingsExposed(Board board) {
  final rk = findKing(board, true);
  final bk = findKing(board, false);
  if (rk == null || bk == null) return false;
  if (rk[1] != bk[1]) return false;
  final minR = math.min(rk[0], bk[0]);
  final maxR = math.max(rk[0], bk[0]);
  for (var r = minR + 1; r < maxR; r++) {
    if (board[r][rk[1]] != kEmpty) return false;
  }
  return true;
}

bool isInPalace(int r, int c, bool red) {
  if (c < 3 || c > 5) return false;
  return red ? (r >= 7 && r <= 9) : (r >= 0 && r <= 2);
}

/// 原始走法（未过滤送将）
List<List<int>> getRawMoves(Board board, int r, int c) {
  final piece = board[r][c];
  if (piece == kEmpty) return [];
  final moves = <List<int>>[];
  final absVal = piece.abs();
  final red = piece > 0;

  if (absVal == 1) {
    // 帅/将：九宫内一步直行
    const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (final d in dirs) {
      final nr = r + d[0], nc = c + d[1];
      if (nr >= 0 && nr < kRows && nc >= 0 && nc < kCols && isInPalace(nr, nc, red)) {
        final target = board[nr][nc];
        if (target == kEmpty || !sameSide(piece, target)) {
          moves.add([nr, nc]);
        }
      }
    }
  } else if (absVal == 2) {
    // 仕/士：九宫内斜走一步
    const dirs = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
    for (final d in dirs) {
      final nr = r + d[0], nc = c + d[1];
      if (nr >= 0 && nr < kRows && nc >= 0 && nc < kCols && isInPalace(nr, nc, red)) {
        final target = board[nr][nc];
        if (target == kEmpty || !sameSide(piece, target)) {
          moves.add([nr, nc]);
        }
      }
    }
  } else if (absVal == 3) {
    // 相/象：田字，塞象眼，不过河
    const dirs = [[-2, -2], [-2, 2], [2, -2], [2, 2]];
    const blocks = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
    for (var i = 0; i < 4; i++) {
      final nr = r + dirs[i][0], nc = c + dirs[i][1];
      final br = r + blocks[i][0], bc = c + blocks[i][1];
      if (nr < 0 || nr >= kRows || nc < 0 || nc >= kCols) continue;
      if (red && nr < 5) continue;
      if (!red && nr > 4) continue;
      if (board[br][bc] != kEmpty) continue;
      final target = board[nr][nc];
      if (target == kEmpty || !sameSide(piece, target)) {
        moves.add([nr, nc]);
      }
    }
  } else if (absVal == 4) {
    // 马：日字，蹩马腿
    const jumps = [[-2, -1], [-2, 1], [-1, -2], [-1, 2], [1, -2], [1, 2], [2, -1], [2, 1]];
    const legBlock = [[-1, 0], [-1, 0], [0, -1], [0, -1], [0, 1], [0, 1], [1, 0], [1, 0]];
    for (var i = 0; i < 8; i++) {
      final nr = r + jumps[i][0], nc = c + jumps[i][1];
      final lr = r + legBlock[i][0], lc = c + legBlock[i][1];
      if (nr < 0 || nr >= kRows || nc < 0 || nc >= kCols) continue;
      if (board[lr][lc] != kEmpty) continue;
      final target = board[nr][nc];
      if (target == kEmpty || !sameSide(piece, target)) {
        moves.add([nr, nc]);
      }
    }
  } else if (absVal == 5) {
    // 车：直线滑行
    const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (final d in dirs) {
      var nr = r + d[0], nc = c + d[1];
      while (nr >= 0 && nr < kRows && nc >= 0 && nc < kCols) {
        final target = board[nr][nc];
        if (target == kEmpty) {
          moves.add([nr, nc]);
        } else {
          if (!sameSide(piece, target)) moves.add([nr, nc]);
          break;
        }
        nr += d[0];
        nc += d[1];
      }
    }
  } else if (absVal == 6) {
    // 炮：直线移动，隔一子吃
    const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1]];
    for (final d in dirs) {
      var nr = r + d[0], nc = c + d[1];
      var jumped = false;
      while (nr >= 0 && nr < kRows && nc >= 0 && nc < kCols) {
        final target = board[nr][nc];
        if (!jumped) {
          if (target == kEmpty) {
            moves.add([nr, nc]);
          } else {
            jumped = true;
          }
        } else {
          if (target != kEmpty) {
            if (!sameSide(piece, target)) moves.add([nr, nc]);
            break;
          }
        }
        nr += d[0];
        nc += d[1];
      }
    }
  } else if (absVal == 7) {
    // 兵/卒：过河前只前进，过河后可横走
    final forward = red ? -1 : 1;
    final crossed = red ? r <= 4 : r >= 5;
    final nr = r + forward;
    if (nr >= 0 && nr < kRows) {
      final target = board[nr][c];
      if (target == kEmpty || !sameSide(piece, target)) {
        moves.add([nr, c]);
      }
    }
    if (crossed) {
      for (final dc in const [-1, 1]) {
        final nc = c + dc;
        if (nc >= 0 && nc < kCols) {
          final target = board[r][nc];
          if (target == kEmpty || !sameSide(piece, target)) {
            moves.add([r, nc]);
          }
        }
      }
    }
  }
  return moves;
}

/// (r,c) 是否被 byRed 一方攻击
bool isUnderAttack(Board board, int r, int c, bool byRed) {
  for (var rr = 0; rr < kRows; rr++) {
    for (var cc = 0; cc < kCols; cc++) {
      final p = board[rr][cc];
      if (p == kEmpty) continue;
      if (byRed && p <= 0) continue;
      if (!byRed && p >= 0) continue;
      final moves = getRawMoves(board, rr, cc);
      if (moves.any((m) => m[0] == r && m[1] == c)) return true;
    }
  }
  return false;
}

/// red 一方是否被将军（含将帅照面）
bool isInCheck(Board board, bool red) {
  final king = findKing(board, red);
  if (king == null) return true;
  return isUnderAttack(board, king[0], king[1], !red) || kingsExposed(board);
}

/// 合法走法（过滤送将）
List<List<int>> getLegalMoves(Board board, int r, int c) {
  final piece = board[r][c];
  if (piece == kEmpty) return [];
  final red = piece > 0;
  final raw = getRawMoves(board, r, c);
  final legal = <List<int>>[];
  for (final m in raw) {
    final nb = cloneBoard(board);
    nb[m[0]][m[1]] = piece;
    nb[r][c] = kEmpty;
    if (!isInCheck(nb, red)) {
      legal.add(m);
    }
  }
  return legal;
}

/// 一方全部合法走法
List<({List<int> from, List<int> to})> getAllMoves(Board board, bool red) {
  final moves = <({List<int> from, List<int> to})>[];
  for (var r = 0; r < kRows; r++) {
    for (var c = 0; c < kCols; c++) {
      final p = board[r][c];
      if (p == kEmpty) continue;
      if (red && p <= 0) continue;
      if (!red && p >= 0) continue;
      final legal = getLegalMoves(board, r, c);
      for (final m in legal) {
        moves.add((from: [r, c], to: m));
      }
    }
  }
  return moves;
}

/// 将死判定（无合法走法）
bool isCheckmate(Board board, bool red) => getAllMoves(board, red).isEmpty;

// ==================== 位置加成表（10×9，红方视角） ====================
const List<List<int>> _posBonusKing = [
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,9,9,9,0,0,0],
  [0,0,0,8,8,8,0,0,0],
  [0,0,0,9,9,9,0,0,0],
];

const List<List<int>> _posBonusAdvisor = [
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,20,0,20,0,0,0],
  [0,0,0,0,23,0,0,0,0],
  [0,0,0,20,0,20,0,0,0],
];

const List<List<int>> _posBonusElephant = [
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,20,0,0,0,20,0,0],
  [0,0,0,0,0,0,0,0,0],
  [18,0,0,0,23,0,0,0,18],
  [0,0,0,0,0,0,0,0,0],
  [0,0,20,0,0,0,20,0,0],
];

const List<List<int>> _posBonusHorse = [
  [90,90,90,96,90,96,90,90,90],
  [90,96,103,97,94,97,103,96,90],
  [92,98,99,103,99,103,99,98,92],
  [93,108,100,107,100,107,100,108,93],
  [90,100,99,103,104,103,99,100,90],
  [90,98,101,102,103,102,101,98,90],
  [92,94,98,95,98,95,98,94,92],
  [93,92,94,95,92,95,94,92,93],
  [85,90,92,93,78,93,92,90,85],
  [88,85,90,88,90,88,90,85,88],
];

const List<List<int>> _posBonusRook = [
  [206,208,207,213,214,213,207,208,206],
  [206,212,209,216,233,216,209,212,206],
  [206,208,207,214,216,214,207,208,206],
  [206,213,213,216,216,216,213,213,206],
  [208,211,211,214,215,214,211,211,208],
  [208,212,212,214,215,214,212,212,208],
  [204,209,204,212,214,212,204,209,204],
  [198,208,204,212,212,212,204,208,198],
  [200,208,206,212,200,212,206,208,200],
  [194,206,204,212,200,212,204,206,194],
];

const List<List<int>> _posBonusCannon = [
  [100,100,96,91,90,91,96,100,100],
  [98,98,96,92,89,92,96,98,98],
  [97,97,96,91,92,91,96,97,97],
  [96,99,99,98,100,98,99,99,96],
  [96,96,96,96,100,96,96,96,96],
  [95,96,99,96,100,96,99,96,95],
  [96,96,96,96,96,96,96,96,96],
  [97,96,100,99,101,99,100,96,97],
  [96,97,98,98,98,98,98,97,96],
  [96,96,97,99,99,99,97,96,96],
];

const List<List<int>> _posBonusSoldierRed = [
  [9,9,9,11,13,11,9,9,9],
  [19,24,34,42,44,42,34,24,19],
  [19,24,32,37,37,37,32,24,19],
  [19,23,27,29,30,29,27,23,19],
  [14,18,20,27,29,27,20,18,14],
  [7,0,13,0,16,0,13,0,7],
  [7,0,7,0,15,0,7,0,7],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
  [0,0,0,0,0,0,0,0,0],
];

// 黑方兵表 = 红方兵表上下翻转
final List<List<int>> _posBonusSoldierBlack =
    List.of(_posBonusSoldierRed.reversed).map((r) => List<int>.of(r)).toList();

int getPosBonus(int piece, int r, int c) {
  final absVal = piece.abs();
  final red = piece > 0;
  if (absVal == 1) return _posBonusKing[r][c];
  if (absVal == 2) return _posBonusAdvisor[r][c];
  if (absVal == 3) return _posBonusElephant[r][c];
  if (absVal == 4) return _posBonusHorse[r][c];
  if (absVal == 5) return _posBonusRook[r][c];
  if (absVal == 6) return _posBonusCannon[r][c];
  if (absVal == 7) return red ? _posBonusSoldierRed[r][c] : _posBonusSoldierBlack[r][c];
  return 0;
}

/// 局面评估（红正黑负）
int evaluateBoard(Board board) {
  var score = 0;
  for (var r = 0; r < kRows; r++) {
    for (var c = 0; c < kCols; c++) {
      final p = board[r][c];
      if (p == kEmpty) continue;
      final absVal = p.abs();
      var val = kPieceValues[absVal] ?? 0;
      if (absVal == 7) {
        final crossed = (p > 0 && r <= 4) || (p < 0 && r >= 5);
        if (crossed) val = 150;
      }
      val += getPosBonus(p, r, c);
      score += p > 0 ? val : -val;
    }
  }
  return score;
}

/// 胜率（sigmoid，scale=800）
int getWinRate(Board board) {
  final score = evaluateBoard(board);
  const scale = 800;
  final redRate = 1 / (1 + math.exp(-score / scale));
  return (redRate * 100).round();
}

/// minimax + alpha-beta
int minimax(Board board, int depth, int alpha, int beta, bool isMaximizing) {
  if (depth == 0) return evaluateBoard(board);
  final red = isMaximizing;
  final moves = getAllMoves(board, red);
  if (moves.isEmpty) {
    return isMaximizing ? -99999 : 99999;
  }
  if (isMaximizing) {
    var maxEval = -999999;
    for (final move in moves) {
      final nb = cloneBoard(board);
      nb[move.to[0]][move.to[1]] = nb[move.from[0]][move.from[1]];
      nb[move.from[0]][move.from[1]] = kEmpty;
      final ev = minimax(nb, depth - 1, alpha, beta, false);
      if (ev > maxEval) maxEval = ev;
      if (ev > alpha) alpha = ev;
      if (beta <= alpha) break;
    }
    return maxEval;
  } else {
    var minEval = 999999;
    for (final move in moves) {
      final nb = cloneBoard(board);
      nb[move.to[0]][move.to[1]] = nb[move.from[0]][move.from[1]];
      nb[move.from[0]][move.from[1]] = kEmpty;
      final ev = minimax(nb, depth - 1, alpha, beta, true);
      if (ev < minEval) minEval = ev;
      if (ev < beta) beta = ev;
      if (beta <= alpha) break;
    }
    return minEval;
  }
}

/// AI 走棋（黑方）。
/// - easy（简单）：depth 2，从 Top5 最优解中随机选一个 → 时常走欠佳着法
/// - normal（正常）：depth 3，从 Top2 最优解中随机选 → 稳定但偶尔有变化
/// - hard（困难）：depth 4，恒取绝对最优兼更深推演 → 尽最大努力
({List<int> from, List<int> to})? getAiMove(Board board, String difficulty) {
  final depth = difficulty == 'easy'
      ? 2
      : difficulty == 'normal'
          ? 3
          : 4;
  final moves = getAllMoves(board, false);
  if (moves.isEmpty) return null;
  final scored = <({({List<int> from, List<int> to}) move, int score})>[];
  for (final move in moves) {
    final nb = cloneBoard(board);
    nb[move.to[0]][move.to[1]] = nb[move.from[0]][move.from[1]];
    nb[move.from[0]][move.from[1]] = kEmpty;
    final score = minimax(nb, depth - 1, -999999, 999999, true);
    scored.add((move: move, score: score));
  }
  scored.sort((a, b) => a.score.compareTo(b.score));
  if (difficulty == 'easy') {
    final top = scored.sublist(0, math.min(5, scored.length));
    return top[math.Random().nextInt(top.length)].move;
  }
  if (difficulty == 'normal') {
    final top = scored.sublist(0, math.min(2, scored.length));
    return top[math.Random().nextInt(top.length)].move;
  }
  return scored[0].move;
}
