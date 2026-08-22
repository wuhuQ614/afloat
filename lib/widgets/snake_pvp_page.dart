/// 双人对战贪吃蛇：全屏沉浸式页面
/// 纯 Dart 实现（不依赖 C++ / FFI），逻辑、渲染均在本文件内。
/// 游戏模式：
///   - 双人：P1 用 WASD，P2 用方向键，同场竞技抢食；
///   - 人机：P2 由内置 AI（BFS 冲食 + 追尾保命）控制。
/// 网格 40×40，两条蛇共享一个食物，任一蛇头吃到即加分并重设食物。
/// 碰撞规则：撞墙、撞到任一蛇身体（含对方）即判死；头撞对方“正在移开的
/// 尾巴格”不算死。当两条蛇都死亡时游戏结束，存活更久的一方胜。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../state.dart' show AppScope;
import '../theme_colors.dart' show AppColors, kDarkBg, kDarkBorder, kDarkCard;

/// 枚举：游戏模式（人机 / 本地双人）
enum _PvpMode { ai, vs }

/// 枚举：人机难度
///  - 保守：最保守，几乎不死（最难的对手）
///  - 激进：疯狂抢食，容易撞死（最简单的对手）
enum _PvpDifficulty { conserve, aggro }

/// 一个玩家的运行时状态（蛇身 / 方向 / 积分 / 存活）
class _SnakeP {
  /// 蛇身坐标，头在 index 0
  final List<int> xs = <int>[];
  final List<int> ys = <int>[];

  /// 上一轮（本轮移动前）的坐标：用于两格之间平滑插值渲染，
  /// 让蛇从“一格一格瞬移”变成连续滑动（解决高帧率下仍觉卡顿的设计问题）。
  final List<int> prevXs = <int>[];
  final List<int> prevYs = <int>[];

  /// 当前朝向
  int dx = 1;
  int dy = 0;

  /// 方向缓冲队列（最多 2 步，防反向自杀）
  final List<(int, int)> pending = <(int, int)>[];

  int score = 0;
  bool alive = true;

  /// 死亡所在的逻辑步数（用于“存活更久”判定）
  int deathTick = 0;

  /// 蛇身长度
  int get len => xs.length;
  (int, int) get head => (xs[0], ys[0]);
  (int, int) get tail => (xs[len - 1], ys[len - 1]);
}

/// 双人对战贪吃蛇页面
class SnakePvpPage extends StatefulWidget {
  const SnakePvpPage({super.key});

  @override
  State<SnakePvpPage> createState() => _SnakePvpPageState();
}

class _SnakePvpPageState extends State<SnakePvpPage>
    with SingleTickerProviderStateMixin {
  static const int _cols = 40; // 网格列数
  static const int _rows = 40; // 网格行数
  static const int _total = _cols * _rows;

  /// 固定移动间隔（毫秒），两条蛇同步推进
  static const int _tickMs = 110;

  /// 游戏阶段
  static const _idle = 0;
  static const _playing = 1;
  static const _paused = 2;
  static const _over = 3;

  _PvpMode _mode = _PvpMode.vs; // 默认本地双人
  _PvpDifficulty _diff = _PvpDifficulty.conserve; // 默认最难（保守）
  int _phase = _idle; // 当前阶段

  _SnakeP _p1 = _SnakeP();
  _SnakeP _p2 = _SnakeP();

  (int, int) _food = (20, 20); // 共享食物

  int _stepCount = 0; // 单调逻辑步数（用于存活时间判定）
  int _accumMs = 0; // 逻辑累计毫秒
  int _animMs = 0; // 动画累计毫秒（食物脉动等）

  /// 当前这格到下一格的插值进度 0~1，用于平滑滑动渲染
  double _interpP = 0.0;

  // ==================== 帧驱动 ====================
  // 用 Ticker（与屏幕刷新对齐）：帧率 = 显示器刷新率，不人为锁到固定值，
  // 有高刷屏（120/144Hz）时自然跑满更高帧率。相比“自调度无限循环”会
  // 每帧重建棋盘 Widget 树拖垮渲染，Ticker 让 UI 稳定不卡。
  final ValueNotifier<int> _frameSignal = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration? _lastFrameTime;

  // FPS 与波形图数据
  double _fps = 0.0; // 平滑后的帧率（回调频率，帧/s）
  double _fpsSampleAcc = 0.0; // 波形采样累计（毫秒）
  final List<double> _fpsWave = <double>[]; // 波形缓冲（最近 ~32 次采样）

  /// 重绘节流：Ticker 回调频率可能远高于绘制能承受的上限（无 vsync 时每秒几百次）。
  /// 若每次都重绘整张 40×40 棋盘，绘制线程跟不上就会丢帧、造成“FPS 高却卡”。
  /// 这里把真正重绘限制在最多 ~60FPS（或蛇每走一格即时刷），FPS 读数仍按无上限的回调测量。
  int? _lastRepaintMs;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _initPlayers();
    _ticker = createTicker(_onFrame);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frameSignal.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// (初始化) 重设两条蛇与食物
  void _initPlayers() {
    _p1 = _SnakeP()
      ..dx = 1
      ..dy = 0
      ..xs.addAll(const [17, 16, 15, 14, 13]) // 中偏左，向右
      ..ys.addAll(const [20, 20, 20, 20, 20]);
    _p2 = _SnakeP()
      ..dx = -1
      ..dy = 0
      ..xs.addAll(const [22, 23, 24, 25, 26]) // 中偏右，向左
      ..ys.addAll(const [20, 20, 20, 20, 20]);
    _food = _randomFree();
  }

  /// 在空位随机生成食物
  (int, int) _randomFree() {
    final free = <int>[];
    final occ = Uint8List(_total);
    for (final p in [_p1, _p2]) {
      for (var i = 0; i < p.len; i++) {
        occ[_id(p.ys[i], p.xs[i])] = 1;
      }
    }
    for (var i = 0; i < _total; i++) {
      if (occ[i] == 0) free.add(i);
    }
    if (free.isEmpty) return (0, 0); // 满盘（几乎不会出现）
    final c = free[math.Random().nextInt(free.length)];
    return (c % _cols, c ~/ _cols);
  }

  /// 格子索引
  static int _id(int y, int x) => y * _cols + x;

  /// 开始新一局
  void _start() {
    _initPlayers();
    _stepCount = 0;
    _accumMs = 0;
    setState(() {
      _phase = _playing;
    });
    _focusNode.requestFocus();
    _lastFrameTime = null;
    if (!_ticker.isActive) _ticker.start();
    _frameSignal.value++; // 立即刷新棋盘
  }

  /// 暂停 / 继续
  void _togglePause() {
    if (_phase == _over) return;
    if (_phase == _idle) {
      _start();
      return;
    }
    setState(() {
      _phase = _phase == _playing ? _paused : _playing;
    });
    _lastFrameTime = null;
    if (_phase == _playing) {
      // 恢复播放：_onFrame 在暂停/结束时会自停 Ticker，这里必须重启
      if (!_ticker.isActive) _ticker.start();
      _focusNode.requestFocus();
    }
  }

  /// 切换模式（人机 / 双人），切换即重开
  void _toggleMode() {
    setState(() {
      _mode = _mode == _PvpMode.vs ? _PvpMode.ai : _PvpMode.vs;
    });
    _start();
  }

  /// 切换人机难度（保守=最难 / 激进=简单）
  void _toggleDifficulty() {
    setState(() {
      _diff = _diff == _PvpDifficulty.conserve
          ? _PvpDifficulty.aggro
          : _PvpDifficulty.conserve;
    });
  }

  /// 返回
  void _close() {
    Navigator.of(context).maybePop();
  }

  // ==================== 每帧驱动（Ticker，帧率 = 显示器刷新率） ====================

  void _onFrame(Duration elapsed) {
    // 非播放态（暂停/结束/未开始）自停渲染循环，避免满帧空转（对齐单机版做法）。
    // 恢复播放的路径（_start/_togglePause）会重新 start
    if (_phase != _playing) {
      _ticker.stop();
      _lastFrameTime = null;
      return;
    }
    final dtMs = _lastFrameTime == null
        ? 0
        : (elapsed - _lastFrameTime!).inMicroseconds ~/ 1000;
    _lastFrameTime = elapsed;
    if (dtMs <= 0) return;

    // —— FPS 统计与波形采样（按无上限的回调频率测量，不重绘也照常累加） ——
    final inst = 1000.0 / dtMs;
    _fps = _fps <= 0 ? inst : _fps * 0.9 + inst * 0.1;
    _fpsSampleAcc += 1.0 * dtMs;
    if (_fpsSampleAcc >= 40) {
      _fpsSampleAcc = 0;
      _fpsWave.add(_fps);
      if (_fpsWave.length > 32) _fpsWave.removeAt(0);
    }

    final nowMs = elapsed.inMilliseconds;
    _lastRepaintMs ??= nowMs;

    var stepped = false;
    if (_phase == _playing) {
      _animMs = (_animMs + dtMs) & 0x7fffffff; // 累加动画时间（防溢出取模）
      // 固定间隔推进逻辑；两条蛇同步走一步（与帧率解耦）
      _accumMs += dtMs;
      var guard = 0;
      while (_accumMs >= _tickMs && guard < 8) {
        guard++;
        _accumMs -= _tickMs;
        _step();
        stepped = true;
        if (_phase != _playing) break; // 一局内双亡即结束，停步
      }
    }

    // —— 真正重绘节流：蛇挪动时即时刷；否则最多每 ~16ms 刷一次 ——
    if (stepped || (nowMs - _lastRepaintMs!) >= 16) {
      _lastRepaintMs = nowMs;
      _interpP = (_accumMs / _tickMs).clamp(0.0, 1.0);
      _frameSignal.value++; // 仅重绘棋盘层与 FPS 表头
    }
  }

  /// 单步推进：人机决策 → 消费方向队列 → 同步碰撞判定 → 应用移动
  void _step() {
    _stepCount++;

    // —— 人机决策：为 P2 规划方向 ——
    if (_mode == _PvpMode.ai && _p2.alive) _aiDecideP2();

    // —— 消费方向队列获得本步方向 ——
    final dirs = <(int, int)?>[null, null];
    final players = [_p1, _p2];
    for (var i = 0; i < 2; i++) {
      final p = players[i];
      if (!p.alive) continue;
      if (p.pending.isNotEmpty) {
        final d = p.pending.removeAt(0);
        p.dx = d.$1;
        p.dy = d.$2;
      }
      dirs[i] = (p.dx, p.dy);
    }

    // —— 计算新头 + 是否吃食 + 持久占用格 ——
    final nx = <int?>[null, null];
    final ny = <int?>[null, null];
    final eatHere = <bool>[false, false];
    for (var i = 0; i < 2; i++) {
      final p = players[i];
      if (!p.alive) continue;
      final d = dirs[i]!;
      final hx = p.xs[0] + d.$1;
      final hy = p.ys[0] + d.$2;
      nx[i] = hx;
      ny[i] = hy;
      if (hx == _food.$1 && hy == _food.$2) eatHere[i] = true;
    }

    // —— 碰撞判定（同步） ——
    final colli = <bool>[false, false];
    for (var i = 0; i < 2; i++) {
      final p = players[i];
      if (!p.alive) continue;
      final hx = nx[i]!, hy = ny[i]!;
      // 1. 撞墙
      if (hx < 0 || hx >= _cols || hy < 0 || hy >= _rows) {
        colli[i] = true;
        continue;
      }
      // 2. 撞到自己（不含正在移开的尾巴；吃到则尾巴保留，次格不空）
      final selfEnd = eatHere[i] ? p.len : p.len - 1; // 停留的自身段数
      for (var s = 0; s < selfEnd; s++) {
        if (p.xs[s] == hx && p.ys[s] == hy) {
          colli[i] = true;
          break;
        }
      }
      if (colli[i]) continue;
      // 3. 撞到对方身体（对方旧头与未吃时尾巴都会移开，可进入 → 从索引 1 起判）
      final other = players[1 - i];
      if (other.alive) {
        final otherEnd = eatHere[1 - i] ? other.len : other.len - 1;
        for (var s = 1; s < otherEnd; s++) {
          if (other.xs[s] == hx && other.ys[s] == hy) {
            colli[i] = true;
            break;
          }
        }
        // 4. 头对头顶死（双龙头入同一格）
        if (!colli[i] && nx[1 - i] == hx && ny[1 - i] == hy) {
          colli[i] = true;
        }
      }
    }

    // —— 处理死亡 ——
    for (var i = 0; i < 2; i++) {
      if (colli[i] && players[i].alive) {
        players[i].alive = false;
        players[i].deathTick = _stepCount;
      }
    }

    // —— 快照本轮移动前的坐标，用于平滑插值渲染 ——
    for (final p in players) {
      if (!p.alive) continue;
      p.prevXs
        ..clear()
        ..addAll(p.xs);
      p.prevYs
        ..clear()
        ..addAll(p.ys);
    }

    // —— 应用存活蛇的移动 ——
    for (var i = 0; i < 2; i++) {
      final p = players[i];
      if (!p.alive) continue;
      p.xs.insert(0, nx[i]!);
      p.ys.insert(0, ny[i]!);
      if (!eatHere[i]) {
        p.xs.removeLast();
        p.ys.removeLast();
      }
    }

    // —— 吃食加分 + 重设食物 ——
    for (var i = 0; i < 2; i++) {
      if (eatHere[i] && players[i].alive) players[i].score += 10;
    }
    if (eatHere.any((e) => e)) {
      _food = _randomFree();
      setState(() {}); // 分数变化 → 刷新顶栏
    }

    // —— 两蛇皆亡则结算 ——
    if (!_p1.alive && !_p2.alive) {
      setState(() {
        _phase = _over;
      });
    }
  }

  // ==================== 键盘输入 ====================

  /// 玩家转向队列（反向检测 + 最多缓冲 2 步）
  void _queueTurn(_SnakeP p, int dx, int dy) {
    if (_phase != _playing || !p.alive) return;
    if (p.pending.length >= 2) return;
    final (lastX, lastY) =
        p.pending.isEmpty ? (p.dx, p.dy) : p.pending.last;
    final isOpposite = (dx == -lastX && dy == -lastY);
    final isSame = (dx == lastX && dy == lastY);
    if (isOpposite || isSame) return;
    p.pending.add((dx, dy));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    // 桌面优先用 logicalKey；Android/iOS 无实体键盘可轮空。
    // 这里统一用 logicalKey，能在桌面（Windows/Linux/macOS）可靠映射 WASD 与方向键。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyW:
      case LogicalKeyboardKey.keyI:
        _queueTurn(_p1, 0, -1); // P1 上
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
      case LogicalKeyboardKey.keyK:
        _queueTurn(_p1, 0, 1); // P1 下
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA:
      case LogicalKeyboardKey.keyJ:
        _queueTurn(_p1, -1, 0); // P1 左
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD:
      case LogicalKeyboardKey.keyL:
        _queueTurn(_p1, 1, 0); // P1 右
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _queueTurn(_p2, 0, -1); // P2 上
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _queueTurn(_p2, 0, 1); // P2 下
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _queueTurn(_p2, -1, 0); // P2 左
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _queueTurn(_p2, 1, 0); // P2 右
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        _togglePause();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _start();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ==================== AI（P2 人机策略） ====================

  /// 构建棋盘障碍图：两条蛇身体除各自尾巴 均为障碍
  Uint8List _boardBlocks() {
    final g = Uint8List(_total);
    for (final p in [_p1, _p2]) {
      if (!p.alive) continue;
      for (var i = 0; i < p.len - 1; i++) {
        g[_id(p.ys[i], p.xs[i])] = 1; // 尾巴格可通行
      }
    }
    return g;
  }

  /// BFS：从 (sx,sy) 到 (tx,ty) 的最短路径（含目标、不含起点）。
  /// 传入的 blocked 在内部会把起点/终点清零以放行。不可达返回空列表。
  List<(int, int)> _bfsPath(int sx, int sy, int tx, int ty, Uint8List base) {
    if (sx == tx && sy == ty) return const [];
    final blocked = Uint8List.fromList(base);
    blocked[_id(sy, sx)] = 0; // 起点放行
    blocked[_id(ty, tx)] = 0; // 终点放行
    final prev = Int32List(_total)..fillRange(0, _total, -1);
    final start = _id(sy, sx);
    prev[start] = -2;
    final q = <int>[start];
    var hq = 0;
    var found = -1;
    const dirs = <(int, int)>[(0, -1), (1, 0), (0, 1), (-1, 0)];
    while (hq < q.length) {
      final cur = q[hq++];
      final cx = cur % _cols;
      final cy = cur ~/ _cols;
      if (cx == tx && cy == ty) {
        found = cur;
        break;
      }
      for (final (dx, dy) in dirs) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx < 0 || nx >= _cols || ny < 0 || ny >= _rows) continue;
        final idn = _id(ny, nx);
        if (blocked[idn] == 1 || prev[idn] != -1) continue;
        prev[idn] = cur;
        q.add(idn);
      }
    }
    if (found < 0) return const [];
    final path = <(int, int)>[];
    var idx = found;
    while (idx != start) {
      path.add((idx % _cols, idx ~/ _cols));
      idx = prev[idx];
    }
    return path.reversed.toList();
  }

  /// 判断一条蛇（模拟后的身体）能否追到自己尾巴。
  /// selfBody 为模拟后的蛇身；其余格子（对方身体除尾巴）作为附加障碍。
  bool _reachTailSim(List<int> bx, List<int> by, int len, _SnakeP other) {
    if (len <= 1) return true;
    final hx = bx[0], hy = by[0];
    final tx = bx[len - 1], ty = by[len - 1];
    if (hx == tx && hy == ty) return true;
    final blocked = Uint8List(_total);
    for (var i = 1; i < len - 1; i++) {
      blocked[_id(by[i], bx[i])] = 1; // 自身中段为障碍
    }
    if (other.alive) {
      for (var i = 0; i < other.len - 1; i++) {
        blocked[_id(other.ys[i], other.xs[i])] = 1; // 对方身体除尾巴
      }
    }
    blocked[_id(hy, hx)] = 0;
    blocked[_id(ty, tx)] = 0;
    const dirs = <(int, int)>[(0, -1), (1, 0), (0, 1), (-1, 0)];
    final dist = Int32List(_total)..fillRange(0, _total, -1);
    final start = _id(hy, hx);
    dist[start] = 0;
    final q = <int>[start];
    var hq = 0;
    while (hq < q.length) {
      final cur = q[hq++];
      final cx = cur % _cols;
      final cy = cur ~/ _cols;
      if (cx == tx && cy == ty) return true;
      for (final (dx, dy) in dirs) {
        final nx = cx + dx;
        final ny = cy + dy;
        if (nx < 0 || nx >= _cols || ny < 0 || ny >= _rows) continue;
        final idn = _id(ny, nx);
        if (blocked[idn] == 1 || dist[idn] != -1) continue;
        dist[idn] = dist[cur] + 1;
        q.add(idn);
      }
    }
    return false;
  }

  /// 判断 P2 沿 path 走完（吃到食物）后蛇能否继续活下去（追得到尾）
  bool _p2EatsSafely(List<(int, int)> path) {
    if (path.isEmpty) return false;
    final bx = <int>[..._p2.xs];
    final by = <int>[..._p2.ys];
    for (final (px, py) in path) {
      bx.insert(0, px);
      by.insert(0, py);
      if (!(px == _food.$1 && py == _food.$2)) {
        bx.removeLast();
        by.removeLast();
      }
    }
    return _reachTailSim(bx, by, bx.length, _p1);
  }

  /// P2 AI 决策：为 P2 设定下一步方向（直接写 dx/dy）
  void _aiDecideP2() {
    final p = _p2;
    if (!p.alive) return;
    p.pending.clear(); // AI 全权接管，清空手动缓冲
    final hx = p.xs[0], hy = p.ys[0];
    final fx = _food.$1, fy = _food.$2;
    final tx = p.xs[p.len - 1], ty = p.ys[p.len - 1];
    final blocks = _boardBlocks();

    // —— 简单（激进）：最短路径直接抢食，不判安全，容易撞死 ——
    if (_diff == _PvpDifficulty.aggro) {
      final toFood = _bfsPath(hx, hy, fx, fy, blocks);
      if (toFood.isNotEmpty) {
        p.dx = toFood.first.$1 - hx;
        p.dy = toFood.first.$2 - hy;
        return;
      }
      // 兜底：挑一个安全方向中最贴近食物的
      final best = _closestSafeDir(hx, hy, fx, fy, blocks);
      if (best != null) {
        p.dx = best.$1;
        p.dy = best.$2;
      }
      return;
    }

    // —— 最难（保守·几乎不死）：吃完还能追尾才吃，否则绕圈保命 ——
    final toFood = _bfsPath(hx, hy, fx, fy, blocks);
    if (toFood.isNotEmpty && _p2EatsSafely(toFood)) {
      p.dx = toFood.first.$1 - hx;
      p.dy = toFood.first.$2 - hy;
      return;
    }
    // 守局：沿 头→自身尾 的最短安全路径绕圈保命
    final toTail = _bfsPath(hx, hy, tx, ty, blocks);
    if (toTail.isNotEmpty) {
      p.dx = toTail.first.$1 - hx;
      p.dy = toTail.first.$2 - hy;
      return;
    }
    // 兜底：挑一个安全方向中最贴近食物的
    final best = _closestSafeDir(hx, hy, fx, fy, blocks);
    if (best != null) {
      p.dx = best.$1;
      p.dy = best.$2;
    }
    // 无可用方向：维持原向，下一格碰撞即死（死路）
  }

  /// 从蛇头安全方向中挑一个最贴近食物的方向
  (int, int)? _closestSafeDir(int hx, int hy, int fx, int fy, Uint8List blocks) {
    const dirs = <(int, int)>[(0, -1), (1, 0), (0, 1), (-1, 0)];
    (int, int)? best;
    var bestDist = 1 << 30;
    for (final (dx, dy) in dirs) {
      final nx0 = hx + dx, ny0 = hy + dy;
      if (nx0 < 0 || nx0 >= _cols || ny0 < 0 || ny0 >= _rows) continue;
      if (blocks[_id(ny0, nx0)] == 1) continue; // 障碍
      final d = (nx0 - fx).abs() + (ny0 - fy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = (dx, dy);
      }
    }
    return best;
  }

  // ==================== 结算 ====================

  /// 判定获胜方编号（1 / 2）
  int _winner() {
    if (_p1.deathTick != _p2.deathTick) {
      // 存活更久（= 较晚死亡）者胜
      return _p1.deathTick > _p2.deathTick ? 1 : 2;
    }
    if (_p1.score != _p2.score) {
      return _p1.score > _p2.score ? 1 : 2;
    }
    return 1; // 三者相同 → 1P 胜
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    final isMobile = AppScope.of(context).uiMode == 'mobile';

    return Scaffold(
      backgroundColor: c.bg,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Column(
            children: [
              _buildToolbar(c, isLight),
              // 棋盘占满剩余全部页面（工具条很薄），地图占比 ≈ 100%，
              // 边缘留白全部让给游戏，尽量沉浸。
              Expanded(
                child: Padding(
                  padding: isMobile
                      ? const EdgeInsets.fromLTRB(6, 0, 6, 6)
                      : const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isLight
                          ? const Color(0xFFF2F4F7)
                          : kDarkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isLight
                              ? const Color(0xFFE5E7EB)
                              : kDarkBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: LayoutBuilder(
                      builder: (ctx, cons) {
                        final cw = cons.maxWidth / _cols;
                        final ch = cons.maxHeight / _rows;
                        return ValueListenableBuilder<int>(
                          valueListenable: _frameSignal,
                          builder: (context, _, __) {
                            return Stack(
                              children: [
                                RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _PvpPainter(
                                      p1: _p1,
                                      p2: _p2,
                                      food: _food,
                                      animMs: _animMs,
                                      playing: _phase == _playing,
                                      cw: cw,
                                      ch: ch,
                                      interpP: _interpP,
                                      isLight: isLight,
                                    ),
                                    size: Size.infinite,
                                  ),
                                ),
                                // 帧率读数 + FPS 波形图（棋盘左上角，常驻显示）
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: _FpsGauge(
                                    c: c,
                                    isLight: isLight,
                                    fps: _fps.round(),
                                    wave: _fpsWave,
                                  ),
                                ),
                                if (_phase != _playing)
                                  Positioned.fill(
                                    child: _OverlayPanel(
                                      c: c,
                                      isLight: isLight,
                                      phase: _phase,
                                      mode: _mode,
                                      diff: _diff,
                                      s1: _p1.score,
                                      s2: _p2.score,
                                      winner: _phase == _over ? _winner() : 0,
                                      liveTile: _liveTile(),
                                      onStart: _start,
                                      onResume: _togglePause,
                                      onRestart: _start,
                                      onClose: _close,
                                    ),
                                  ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部工具条：模式切换 + 当前比分 + 暂停 + 重开 + 返回
  Widget _buildToolbar(AppColors c, bool isLight) {
    final isAI = _mode == _PvpMode.ai;
    // 存活蛇数量用于状态文字
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          // 返回 / 关闭入口
          IconButton(
            onPressed: _close,
            icon: Icon(Icons.arrow_back_rounded,
                size: 22, color: c.textSecondary),
            tooltip: '返回',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Text('双人对战',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c.text)),
          const Spacer(),
          // 模式切换：人机 / 双人
          GestureDetector(
            onTap: _toggleMode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.cardAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isLight
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFF3D3D45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      isAI ? Icons.smart_toy_rounded : Icons.group_outlined,
                      size: 15,
                      color: c.textSecondary),
                  const SizedBox(width: 5),
                  Text(isAI ? '人机' : '双人',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 人机难度：保守（最难）/ 激进（简单），任何模式都可预先选好
          GestureDetector(
            onTap: _toggleDifficulty,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.cardAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: isLight
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFF3D3D45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      _diff == _PvpDifficulty.conserve
                          ? Icons.shield_rounded
                          : Icons.bolt_rounded,
                      size: 15,
                      color: _diff == _PvpDifficulty.conserve
                          ? const Color(0xFF27AE60)
                          : const Color(0xFFE67E22)),
                  const SizedBox(width: 5),
                  Text(_diff == _PvpDifficulty.conserve ? '保守' : '激进',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.textSecondary)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 比分
          _scoreChip(c, isLight, 'P1', _p1.score, _p2.score, 'P2'),
          const SizedBox(width: 8),
          // 暂停 / 继续
          TextButton.icon(
            onPressed: _togglePause,
            icon: Icon(
                _phase == _paused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 18),
            label: Text(_phase == _paused ? '继续' : '暂停'),
          ),
          // 重新开始
          IconButton(
            onPressed: _start,
            icon: Icon(Icons.replay_rounded, size: 22, color: c.textSecondary),
            tooltip: '重新开始',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _scoreChip(AppColors c, bool isLight, String l1, int s1, int s2,
      String l2) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.cardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isLight
                ? const Color(0xFFE5E7EB)
                : const Color(0xFF3D3D45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l1,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF27AE60))),
          const SizedBox(width: 6),
          Text('$s1',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                  color: c.text)),
          Text(' : ',
              style: TextStyle(fontSize: 14, color: c.textTertiary)),
          Text('$s2',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                  color: c.text)),
          const SizedBox(width: 6),
          Text(l2,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFF39C12))),
        ],
      ),
    );
  }

  String _liveTile() => 'P1 ${_p1.score} : ${_p2.score} P2';
}

/// 棋盘绘制：网格线 + 双蛇（圆角段 + 带眼睛的头）+ 脉动发光食物
class _PvpPainter extends CustomPainter {
  final _SnakeP p1;
  final _SnakeP p2;
  final (int, int) food;
  final int animMs;
  final bool playing;
  final double cw;
  final double ch;
  final double interpP;
  final bool isLight;

  _PvpPainter({
    required this.p1,
    required this.p2,
    required this.food,
    required this.animMs,
    required this.playing,
    required this.cw,
    required this.ch,
    required this.interpP,
    required this.isLight,
  });

  Offset _px(num x, num y) => Offset(x * cw + cw / 2, y * ch + ch / 2);

  /// 第 i 节的渲染坐标：在“上一轮位置→当前位置”之间按进度插值，实现连续滑动
  Offset _segPos(_SnakeP p, int i) {
    final cx = p.xs[i], cy = p.ys[i];
    final hasPrev = i < p.prevXs.length;
    final px = hasPrev ? p.prevXs[i] : cx;
    final py = hasPrev ? p.prevYs[i] : cy;
    final t = interpP;
    return _px(px + (cx - px) * t, py + (cy - py) * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 网格线
    final gridPaint = Paint()
      ..color = isLight
          ? const Color(0x14000000)
          : Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (var i = 1; i < _SnakePvpPageState._cols; i++) {
      canvas.drawLine(Offset(i * cw, 0), Offset(i * cw, size.height),
          gridPaint);
    }
    for (var j = 1; j < _SnakePvpPageState._rows; j++) {
      canvas.drawLine(
          Offset(0, j * ch), Offset(size.width, j * ch), gridPaint);
    }

    // 食物（发光脉动）
    _paintFood(canvas);

    // 两条蛇
    _paintSnake(canvas, p1, const Color(0xFF27AE60), const Color(0xFF1ABC9C));
    _paintSnake(canvas, p2, const Color(0xFFE67E22), const Color(0xFFE91E63));
  }

  void _paintFood(Canvas canvas) {
    final center = _px(food.$1, food.$2);
    final base = math.min(cw, ch);
    final phase = playing
        ? (math.sin(animMs * math.pi / 90000) * 0.5 + 0.5)
        : 0.5;
    const color = Color(0xFFE74C3C);
    // 发光光环
    canvas.drawCircle(
        center,
        base * (0.30 + 0.10 * phase),
        Paint()
          ..color = color.withValues(alpha: 0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(
        center,
        base * (0.22 + 0.05 * phase),
        Paint()..color = color);
  }

  void _paintSnake(Canvas canvas, _SnakeP p, Color body, Color headC) {
    if (!p.alive || p.len == 0) return;
    final bodyW = math.min(cw, ch) * 0.62;

    // 圆角蛇身（从尾连接到头的路径，round）→ 圆角段；坐标用插值实现连续滑动
    final path = Path();
    final tail = _segPos(p, p.len - 1);
    path.moveTo(tail.dx, tail.dy);
    for (var i = p.len - 2; i >= 0; i--) {
      final pt = _segPos(p, i);
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = body,
    );

    // 头（球状 + 眼睛朝向）
    final head = _segPos(p, 0);
    final headR = math.min(cw, ch) * 0.42;
    canvas.drawCircle(head, headR, Paint()..color = headC);
    // 眼睛沿当前方向分布
    final lenSq = p.dx * p.dx + p.dy * p.dy;
    final d = lenSq > 0
        ? Offset(p.dx / math.sqrt(lenSq), p.dy / math.sqrt(lenSq))
        : const Offset(1, 0);
    final n = Offset(-d.dy, d.dx); // 垂直向量
    final eyeWhite = isLight ? Colors.white : const Color(0xFFF5F5F5);
    for (final s in [1.0, -1.0]) {
      final ctr = head + n * (headR * 0.45) * s + d * (headR * 0.38);
      canvas.drawCircle(ctr, headR * 0.30, Paint()..color = eyeWhite);
      canvas.drawCircle(ctr + d * (headR * 0.12), headR * 0.15,
          Paint()..color = const Color(0xFF17201A));
    }
  }

  @override
  bool shouldRepaint(covariant _PvpPainter oldDelegate) =>
      oldDelegate.animMs != animMs ||
      oldDelegate.playing != playing ||
      oldDelegate.interpP != interpP ||
      oldDelegate.isLight != isLight ||
      oldDelegate.cw != cw ||
      oldDelegate.ch != ch ||
      oldDelegate.p1.xs.length != p1.xs.length ||
      oldDelegate.p1.ys.length != p1.ys.length ||
      oldDelegate.p1.xs[0] != p1.xs[0] ||
      oldDelegate.p1.ys[0] != p1.ys[0] ||
      oldDelegate.p2.xs.length != p2.xs.length ||
      oldDelegate.food != food;
}

/// 中央叠层：开始 / 暂停 / 结算
class _OverlayPanel extends StatelessWidget {
  final AppColors c;
  final bool isLight;
  final int phase; // idle/paused/over
  final _PvpMode mode;
  final _PvpDifficulty diff;
  final int s1;
  final int s2;
  final int winner; // 获胜方编号：1/2；非结束阶段时为 0
  final String liveTile;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onClose;

  const _OverlayPanel({
    required this.c,
    required this.isLight,
    required this.phase,
    required this.mode,
    required this.diff,
    required this.s1,
    required this.s2,
    required this.winner,
    required this.liveTile,
    required this.onStart,
    required this.onResume,
    required this.onRestart,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final String title;
    final String sub;
    Widget actions;

    if (phase == _SnakePvpPageState._over) {
      final isAI = mode == _PvpMode.ai;
      title = '游戏结束';
      sub = '比分为 P1 $s1  :  $s2 P2\n'
          '${isAI ? '（人机模式）' : '（双人模式）'} · 获胜：$winner P';
      actions = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            onPressed: onRestart,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('再来一局'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isLight ? const Color(0xFF34C759) : const Color(0xFF2ECC71),
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('返回'),
          ),
        ],
      );
    } else if (phase == _SnakePvpPageState._paused) {
      title = '已暂停';
      sub = liveTile;
      actions = ElevatedButton.icon(
        onPressed: onResume,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('继续游戏'),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isLight ? const Color(0xFF34C759) : const Color(0xFF2ECC71),
          foregroundColor: Colors.white,
        ),
      );
    } else {
      title = '双人对战贪吃蛇';
      final diffLabel =
          diff == _PvpDifficulty.conserve ? '人机·保守(最难)' : '人机·激进(简单)';
      sub = mode == _PvpMode.ai
          ? 'P2 由人机控制（$diffLabel），P1 用 WASD 挑战'
          : 'P1 用 WASD · P2 用方向键 · 抢食加分，活到最后者胜，帧率不设上限';
      actions = ElevatedButton.icon(
        onPressed: onStart,
        icon: const Icon(Icons.play_arrow_rounded, size: 18),
        label: const Text('开始游戏'),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isLight ? const Color(0xFF34C759) : const Color(0xFF2ECC71),
          foregroundColor: Colors.white,
        ),
      );
    }

    return Container(
      color: isLight
          ? Colors.white.withValues(alpha: 0.78)
          : kDarkBg.withValues(alpha: 0.82),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_esports_outlined,
                size: 40, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.text)),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.textTertiary)),
            const SizedBox(height: 18),
            actions,
          ],
        ),
      ),
    );
  }
}

/// 左上角帧率读数 + FPS 波形图（常驻显示，随无限制帧率循环实时刷新）
class _FpsGauge extends StatelessWidget {
  final AppColors c;
  final bool isLight;
  final int fps;
  final List<double> wave;

  const _FpsGauge({
    required this.c,
    required this.isLight,
    required this.fps,
    required this.wave,
  });

  @override
  Widget build(BuildContext context) {
    final Color fpsColor = fps >= 120
        ? const Color(0xFF2ECC71)
        : (fps >= 60
            ? const Color(0xFFF1C40F)
            : const Color(0xFFE74C3C));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: (isLight ? Colors.white : kDarkBg).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isLight ? const Color(0x33555555) : const Color(0xFF3D3D45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'FPS $fps',
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: fpsColor),
          ),
          const SizedBox(width: 6),
          CustomPaint(
            size: const Size(80, 22),
            painter: _FpsWavePainter(
              wave: wave,
              line: fpsColor,
              stroke: isLight
                  ? const Color(0x22555555)
                  : const Color(0xFF3D3D45),
            ),
          ),
        ],
      ),
    );
  }
}

/// FPS 波形图绘制：左侧为最新采样，向右滚动
class _FpsWavePainter extends CustomPainter {
  final List<double> wave;
  final Color line;
  final Color stroke;

  _FpsWavePainter({
    required this.wave,
    required this.line,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 背景
    final bg = Paint()..color = stroke.withValues(alpha: 0.35);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(3)),
        bg);

    final n = wave.length;
    if (n < 2) return;

    // 纵轴按“当前采样最大值”自适应，并留一定余量，至少 40fps 跨度避免抖动到底
    var maxV = 40.0;
    for (final v in wave) {
      if (v > maxV) maxV = v;
    }
    maxV *= 1.1;
    if (maxV <= 0) maxV = 1;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = line;

    final step = size.width / (n - 1);
    final path = Path();
    for (var i = 0; i < n; i++) {
      final ratio = (wave[i] / maxV).clamp(0.0, 1.0);
      final x = i * step;
      final y = size.height - ratio * (size.height - 2) - 1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FpsWavePainter oldDelegate) => true;
}