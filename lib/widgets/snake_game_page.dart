/// 贪吃蛇小游戏：全屏沉浸式页面
/// 架构：Dart 负责 UI（棋盘/蛇身/食物/方向键/设置菜单渲染），
///       C++（snake_logic 库）负责游戏逻辑（方向队列/碰撞/得分/速度），
///       通过 dart:ffi 每帧驱动逻辑并读取状态快照进行渲染。
/// - 电脑端：仅键盘操作（方向键 / WASD），不显示屏幕方向键
/// - 手机端：显示 D-pad 方向键，支持触屏操作
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../services/snake_logic.dart' show SnakeLogic, SnakeSnapshot;
import '../services/storage.dart';
import '../state.dart' show AppScope;
import '../theme_colors.dart' show AppColors;

/// 更多功能选择页索引（与 main.dart 中的 _morePageIndex 对应）
const _morePageIndex = 9;

class SnakeGamePage extends StatefulWidget {
  const SnakeGamePage({super.key});

  @override
  State<SnakeGamePage> createState() => _SnakeGamePageState();
}

class _SnakeGamePageState extends State<SnakeGamePage>
    with SingleTickerProviderStateMixin {
  static const int _cols = 20; // 网格列数
  static const int _rows = 20; // 网格行数

  // ===== C++ 逻辑库（蛇的状态/移动/碰撞/得分全在 C++ 中） =====
  SnakeLogic? _logic;
  bool _logicError = false; // 库加载失败标记

  // ===== 渲染用数据（每帧从 C++ 快照同步） =====
  // 零拷贝 int 视图（asTypedList），避免每帧分配 Offset 列表
  List<int> _curX = const [], _curY = const [];
  List<int> _prevX = const [], _prevY = const [];
  int _snakeLen = 0; // 蛇身节数（头在 0）
  final List<Offset> _renderPts = <Offset>[]; // 复用缓冲：插值后的渲染坐标
  int _frameVersion = 0; // 帧版本号：驱动 Painter shouldRepaint 精确判断
  Offset _food = const Offset(8, 8);
  double _moveProgress = 1.0; // 本次移动插值进度 0~1

  // ===== 方向即时反馈（Dart 侧镜像 C++ 方向队列，仅用于渲染头部朝向） =====
  // 目的：缩短“按键 → 可见反馈”的体感延迟。C++ 仍负责真正的方向队列 /
  // 反向检测 / 移动，Dart 不干预逻辑，只在本地记录“下一步将采用的方向”，
  // 让蛇头眼睛在按键后立即朝目标方向，提供“输入已被接收”的即时视觉确认。
  // 镜像队列以 C++ 的 dir 变化为消费信号（见 _syncFromLogic），与 C++ 队列保持同步，
  // 深度与 C++ 一致（=2），不接受反向/同向，故不会出现眼睛方向与真实移动不一致。
  Offset _renderDir = const Offset(1, 0); // 当前实际移动方向（来自 snapshot.dir）
  Offset _pendingDir = const Offset(1, 0); // 下一格方向（无 pending 时等于 _renderDir）
  final List<Offset> _pendingQueue = <Offset>[]; // 镜像队列（深度 = 2）

  // ===== UI 状态（从快照同步） =====
  bool _playing = false;
  bool _paused = false;
  bool _over = false;
  bool _invincible = false; // 复活无敌中（闪烁视觉）
  int _score = 0;
  int _highScore = 0;
  bool _lastSyncPaused = false;
  bool _lastSyncOver = false;
  int _lastSyncScore = -1;

  // ===== 自动玩（内置 AI）：安全路径 BFS + 追尾保命 =====
  bool _auto = false; // 开启后 AI 每一逻辑 tick 决策转向
  static const List<(int, int)> _autoDirs = [
    (0, -1),
    (1, 0),
    (0, 1),
    (-1, 0),
  ];
  // 已规划到食物的最短路径（坐标序列，不含蛇头、含食物格）；重开时清零
  List<(int, int)> _nextPath = [];

  // ===== 渲染循环 =====
  late final Ticker _ticker;
  Duration? _lastFrameTime; // 上一帧时间（用于计算帧间隔）
  // FPS 统计
  int _frames = 0;
  Duration _fpsAccum = Duration.zero;
  double _fps = 0;
  // 性能：帧信号仅驱动棋盘区域重建（避免整页 setState 拖累帧率）
  final ValueNotifier<int> _frameSignal = ValueNotifier<int>(0);
  final ValueNotifier<double> _fpsNotifier = ValueNotifier<double>(0);
  int _pulseTime = 0; // 食物脉动累计时间（微秒）

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _highScore = Storage.loadSnakeHighScore();
    try {
      _logic = SnakeLogic(_highScore);
      _syncFromLogic(); // 初始快照
      _updateRenderPts(); // 初始渲染坐标
    } catch (_) {
      _logicError = true;
    }
    _ticker = createTicker(_onFrame);
  }

  @override
  void dispose() {
    _logic?.dispose();
    _ticker.dispose();
    _frameSignal.dispose();
    _fpsNotifier.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 从 C++ 快照同步渲染数据与 UI 状态（每帧调用）
  void _syncFromLogic() {
    final logic = _logic;
    if (logic == null) return;
    final SnakeSnapshot s = logic.snapshot();
    _moveProgress = s.moveProgress;
    _food = Offset(s.foodX.toDouble(), s.foodY.toDouble());

    // —— 同步镜像方向队列：以 C++ dir 变化为“已消费一个方向”的信号 ——
    // 当 C++ 在 step() 里真正采用了新方向（snapshot.dir 改变），这里同步弹出一个
    // 镜像元素，保证 _pendingQueue 与 C++ 的 dirQueue 始终一一对应，
    // 从而 _pendingDir 精确反映“下一格将采用的方向”。
    final Offset newDir = Offset(s.dirX.toDouble(), s.dirY.toDouble());
    if (_renderDir != newDir) {
      if (_pendingQueue.isNotEmpty) _pendingQueue.removeAt(0);
      _renderDir = newDir;
    }
    _pendingDir = _pendingQueue.isEmpty ? _renderDir : _pendingQueue.first;

    // 零拷贝视图（asTypedList 直接映射 C++ 数组，不分配）
    final (cx, cy, px, py) = logic.snakePos(s.snakeLen);
    _curX = cx;
    _curY = cy;
    _prevX = px;
    _prevY = py;
    _snakeLen = s.snakeLen;

    // 状态变化检测（仅变化时 setState，避免整页每帧重建）
    final scoreChanged = s.score != _lastSyncScore;
    final pausedChanged = (s.paused == 1) != _lastSyncPaused;
    final overChanged = (s.over == 1) != _lastSyncOver;
    _score = s.score;
    _playing = s.playing == 1;
    _paused = s.paused == 1;
    _over = s.over == 1;
    _invincible = s.invincible == 1;
    _highScore = s.highScore;
    _lastSyncScore = s.score;
    _lastSyncPaused = _paused;
    _lastSyncOver = _over;

    // 游戏结束：停止渲染循环并持久化最高分
    if (overChanged && _over) {
      _ticker.stop();
      Storage.saveSnakeHighScore(_highScore);
      setState(() {});
      return;
    }
    if (scoreChanged || pausedChanged) setState(() {});
  }

  void _start() {
    final logic = _logic;
    if (logic == null) return;
    // 重开：清空方向镜像队列，dir 回到初始（与 C++ reset 一致），避免残影
    _pendingQueue.clear();
    _nextPath.clear();
    _renderDir = const Offset(1, 0);
    _pendingDir = const Offset(1, 0);
    logic.start();
    _syncFromLogic();
    _updateRenderPts(); // 重开：立即刷新渲染坐标，避免一帧旧画面
    setState(() {});
    _focusNode.requestFocus();
    _lastFrameTime = null;
    if (!_ticker.isActive) _ticker.start();
  }

  /// 原地复活：保留当前蛇身/分数/食物，进入短暂无敌，1.1 秒后恢复正常
  void _revive() {
    final logic = _logic;
    if (logic == null || !_over) return;
    // 复活前清空方向镜像队列与自动玩路径，方向由玩家重新接管
    _pendingQueue.clear();
    _nextPath.clear();
    _renderDir = const Offset(1, 0);
    _pendingDir = const Offset(1, 0);
    logic.revive();
    _syncFromLogic();
    _updateRenderPts();
    setState(() {});
    _focusNode.requestFocus();
    _lastFrameTime = null;
    if (!_ticker.isActive) _ticker.start();
  }

  void _togglePause() {
    final logic = _logic;
    if (logic == null || !_playing || _over) return;
    logic.togglePause();
    _syncFromLogic();
    setState(() {});
    if (_paused) {
      _ticker.stop();
    } else {
      _lastFrameTime = null;
      _ticker.start();
      _focusNode.requestFocus();
    }
  }

  /// 每帧回调：驱动 C++ 逻辑步进 + 同步状态渲染（跟随屏幕刷新率）
  void _onFrame(Duration elapsed) {
    final dt = _lastFrameTime == null
        ? Duration.zero
        : elapsed - _lastFrameTime!;
    _lastFrameTime = elapsed;

    // FPS 统计（每秒更新一次，仅重建 FPS 角标）
    _frames++;
    _fpsAccum += dt;
    if (_fpsAccum >= const Duration(seconds: 1)) {
      final s = _fpsAccum.inMicroseconds / 1000000.0;
      _fps = _frames / s;
      _frames = 0;
      _fpsAccum = Duration.zero;
      _fpsNotifier.value = _fps;
    }

    if (_logic == null) return;
    if (_playing && !_paused && !_over) {
      // 食物脉动时间（与旧版一致的累计式相位）
      _pulseTime += dt.inMicroseconds;
      // 将帧间隔传给 C++ 逻辑，内部累积步进
      _logic!.advance(dt.inMicroseconds / 1000.0);
      _syncFromLogic();
      if (_playing && !_paused && !_over) {
        _updateRenderPts(); // 复用缓冲写入插值坐标
        _frameSignal.value++; // 仅重建棋盘区域
      }
    }
    // 自动玩：AI 决策转向；结束后自动重开以便持续观看
    if (_auto) {
      if (_over) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_auto && _over) _start();
        });
      } else if (_playing && !_paused) {
        _autoDecide();
      }
    }
  }

  /// 把插值后的渲染坐标写入复用缓冲（避免每帧 List.generate 分配）
  void _updateRenderPts() {
    final n = _snakeLen;
    if (_renderPts.length < n) {
      _renderPts.addAll(List.filled(n - _renderPts.length, Offset.zero));
    }
    final t = Curves.easeOut.transform(_moveProgress);
    for (var i = 0; i < n; i++) {
      final cx = _curX[i].toDouble();
      final cy = _curY[i].toDouble();
      // prev 数组在 C++ 侧已按 snakeLen 补齐（新增长段 prev = cur，不移动）
      final px = i < _prevX.length ? _prevX[i].toDouble() : cx;
      final py = i < _prevY.length ? _prevY[i].toDouble() : cy;
      _renderPts[i] = (px == cx && py == cy)
          ? Offset(cx, cy)
          : Offset(px + (cx - px) * t, py + (cy - py) * t);
    }
    _frameVersion++; // 帧版本号：供 Painter shouldRepaint 精确判断
  }

  /// 转向（由 C++ 内部做方向队列缓冲与反向检测）
  void _turn(Offset newDir) {
    final dx = newDir.dx.round();
    final dy = newDir.dy.round();
    // —— Dart 侧镜像 C++ 方向队列（仅用于即时渲染头部朝向，不干预逻辑） ——
    // 与 C++ snake_turn 的接受规则完全一致：仅在游戏进行中（playing 且非暂停/结束）、
    // 队列深度上限 2、拒绝反向、拒绝同向。这样按键后 _pendingDir 立即更新，
    // 蛇头眼睛在下一帧（≤16ms）即转向目标方向，比“等下一个 tick 才在 snapshot.dir
    // 中体现”更早给出输入反馈；且与 C++ 严格对齐，避免暂停/未开始时积累无效方向。
    if (_playing && !_paused && !_over && _pendingQueue.length < 2) {
      final Offset last =
          _pendingQueue.isEmpty ? _renderDir : _pendingQueue.last;
      final bool isOpposite = dx == -last.dx && dy == -last.dy;
      final bool isSame = dx == last.dx && dy == last.dy;
      if (!isOpposite && !isSame) {
        _pendingQueue.add(Offset(dx.toDouble(), dy.toDouble()));
      }
    }
    final logic = _logic;
    if (logic == null) return;
    logic.turn(dx, dy);
    // 即时反馈：按键后在本事件内立即刷新头部朝向（下一帧 Ticker 也会刷新），
    // 把眼睛转向延迟从“≤一帧 VSync（≤16ms）”进一步降到“按键即时”，无需等待下一帧。
    if (_playing && !_paused && !_over && _pendingQueue.isNotEmpty) {
      _pendingDir = _pendingQueue.first;
      _frameSignal.value++;
    }
  }

  /// BFS 求 from→to 的最短步数（查找路径时除尾格外蛇身视为障碍，尾格可通行）。
  /// 不可达返回 -1。格子索引 id = y*_cols+x。
  int _bfsPathLen(int sx, int sy, int tx, int ty, List<int> bx, List<int> by,
      int n) {
    if (sx == tx && sy == ty) return 0;
    final blocked = List<int>.filled(_cols * _rows, 0);
    for (var i = 0; i < n - 1; i++) {
      blocked[by[i] * _cols + bx[i]] = 1; // 除尾格(n-1)外其余身段为障碍
    }
    final start = sy * _cols + sx;
    final dist = List<int>.filled(_cols * _rows, -1);
    final q = <int>[start];
    dist[start] = 0;
    var headQ = 0;
    while (headQ < q.length) {
      final cur = q[headQ++];
      final cx = cur % _cols, cy = cur ~/ _cols;
      for (final (dx, dy) in _autoDirs) {
        final nx = cx + dx, ny = cy + dy;
        if (nx < 0 || nx >= _cols || ny < 0 || ny >= _rows) continue;
        final id = ny * _cols + nx;
        if (blocked[id] == 1 || dist[id] != -1) continue;
        if (nx == tx && ny == ty) return dist[cur] + 1;
        dist[id] = dist[cur] + 1;
        q.add(id);
      }
    }
    return -1;
  }

  /// BFS 求 (sx,sy)→(tx,ty) 的最短路径（障碍=蛇身除尾格，目标格可通行），
  /// 返回路径坐标（不含起点、含目标）。不可达返回空列表。
  List<(int, int)> _bfsPath(int sx, int sy, int tx, int ty) {
    if (_snakeLen == 0) return const [];
    if (sx == tx && sy == ty) return const [];
    final blocked = List<int>.filled(_cols * _rows, 0);
    for (var i = 0; i < _snakeLen - 1; i++) {
      blocked[_curY[i] * _cols + _curX[i]] = 1; // 除尾格外其余身段为障碍
    }
    final prev = List<int>.filled(_cols * _rows, -1);
    final start = sy * _cols + sx;
    prev[start] = -2; // 起点标记
    final q = <int>[start];
    var hq = 0;
    var found = -1;
    while (hq < q.length) {
      final cur = q[hq++];
      final cx = cur % _cols, cy = cur ~/ _cols;
      if (cx == tx && cy == ty) {
        found = cur;
        break;
      }
      for (final (dx, dy) in _autoDirs) {
        final nx = cx + dx, ny = cy + dy;
        if (nx < 0 || nx >= _cols || ny < 0 || ny >= _rows) continue;
        final id = ny * _cols + nx;
        if (blocked[id] == 1 || prev[id] != -1) continue;
        prev[id] = cur;
        q.add(id);
      }
    }
    if (found < 0) return const [];
    // 回溯重建（不含起点自身）
    final path = <(int, int)>[];
    var idx = found;
    while (idx != start) {
      path.add((idx % _cols, idx ~/ _cols));
      idx = prev[idx];
    }
    return path.reversed.toList();
  }

  /// 从 a 到相邻 b 的方向；不相邻返回 null。
  (int, int)? _dirTo((int, int) a, (int, int) b) {
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    if (dx == 0 && dy == 0) return null;
    if (dx.abs() + dy.abs() != 1) return null;
    return (dx, dy);
  }

  /// 追尾安全闸：蛇头沿 dir 走一格后，新蛇头仍能沿空位追到新蛇尾（不会自困）。
  /// 这是“最快吃球”与“基本不出错”之间的保险丝。
  bool _isHeadDirSafe(int hx, int hy, int dx, int dy, int fx, int fy, int len) {
    final nx = hx + dx, ny = hy + dy;
    if (nx < 0 || nx >= _cols || ny < 0 || ny >= _rows) return false;
    final eat = (nx == fx && ny == fy);
    var hit = false;
    for (var i = 0; i < len - 1; i++) {
      if (_curX[i] == nx && _curY[i] == ny) {
        hit = true;
        break;
      }
    }
    if (eat && _curX[len - 1] == nx && _curY[len - 1] == ny) hit = true;
    if (hit) return false;

    // 推理步进后的新蛇身，验证新头能否追到新尾
    final nbX = <int>[nx], nbY = <int>[ny];
    for (var i = 0; i < len - (eat ? 0 : 1) && i < len; i++) {
      nbX.add(_curX[i]);
      nbY.add(_curY[i]);
    }
    final nbLen = eat ? len + 1 : len;
    return _bfsPathLen(nx, ny, nbX[nbLen - 1], nbY[nbLen - 1], nbX, nbY, nbLen) >= 0;
  }

  /// 兜底：挑一个“连得到尾巴 + 尽量贴近食物”的安全方向，绕圈保命等待机会。
  (int, int)? _tailChase(int hx, int hy, int fx, int fy) {
    (int, int)? best;
    var bestDist = 1 << 30;
    for (final (dx, dy) in _autoDirs) {
      if (!_isHeadDirSafe(hx, hy, dx, dy, fx, fy, _snakeLen)) continue;
      final nx = hx + dx, ny = hy + dy;
      final d = (nx - fx).abs() + (ny - fy).abs();
      if (d < bestDist) {
        bestDist = d;
        best = (dx, dy);
      }
    }
    return best;
  }

  /// 判断指定蛇身里，蛇头能否沿空位追到蛇尾（障碍=身段中间部分，尾格可通行）。
  /// 这是"下一步之后还能不能活下去"的经典判据。
  bool _canReachTailList(List<int> bx, List<int> by, int len) {
    if (len <= 1) return true;
    final hx = bx[0], hy = by[0], tx = bx[len - 1], ty = by[len - 1];
    if (hx == tx && hy == ty) return true;
    final blocked = List<int>.filled(_cols * _rows, 0);
    for (var i = 1; i < len - 1; i++) {
      blocked[by[i] * _cols + bx[i]] = 1; // 头(0)与尾(len-1)可通行
    }
    final dist = List<int>.filled(_cols * _rows, -1);
    final start = hy * _cols + hx;
    dist[start] = 0;
    final q = <int>[start];
    var hq = 0;
    while (hq < q.length) {
      final cur = q[hq++];
      final cx = cur % _cols, cy = cur ~/ _cols;
      for (final (dx, dy) in _autoDirs) {
        final nx = cx + dx, ny = cy + dy;
        if (nx < 0 || nx >= _cols || ny < 0 || ny >= _rows) continue;
        final id = ny * _cols + nx;
        if (blocked[id] == 1 || dist[id] != -1) continue;
        if (nx == tx && ny == ty) return true;
        dist[id] = dist[cur] + 1;
        q.add(id);
      }
    }
    return false;
  }

  /// 整条吃球路线安全验证（Eat-safe path）：
  /// 把从蛇头到食物的整条路径在脑内模拟走完（吃到球、身体随之变化），
  /// 最终确认"新蛇头仍能追到新蛇尾"才放行——否则这颗球吃了会把自己困死。
  bool _eatsSafely(List<(int, int)> path) {
    if (path.isEmpty) return false;
    final bx = <int>[..._curX.take(_snakeLen)];
    final by = <int>[..._curY.take(_snakeLen)];
    final fxp = _food.dx.round(), fyp = _food.dy.round();
    for (final (px, py) in path) {
      final eat = (px == fxp && py == fyp);
      bx.insert(0, px);
      by.insert(0, py);
      if (!eat && bx.length > 1) {
        bx.removeLast(); // 不吃：尾前移一格
        by.removeLast();
      }
    }
    return _canReachTailList(bx, by, bx.length);
  }

  /// 当前真实蛇身的"头能追到尾"快捷判断。
  bool _canReachTailNow() =>
      _snakeLen <= 1 ||
      _canReachTailList(
          _curX.take(_snakeLen).toList(),
          _curY.take(_snakeLen).toList(),
          _snakeLen);

  /// 自动玩决策（确定性守局大师）：
  /// 1. 主：沿“到食物的最短 BFS 路径”直冲——最快吃到球；
  /// 2. 捷径：利用 C++ 双步方向队列一次连发两个方向键，蛇在连续两个 tick 内
  ///    完成紧凑转向，视觉上“斜着爬过去”紧贴路径；
  /// 3. 守局：食物被围时切换为“沿 BFS 蛇头→蛇尾最短路径”，绕大圈保命逼近满盘；
  /// 4. 超兜底：仅当 BFS 也找不到时，走贪心跳转。
  ///
  /// 统一策略：始终缓存并逐格执行某条最短安全路径（_nextPath），每一步都过
  /// 追尾安全闸，路径失效即重算——这就是“最快吃球 + 基本不出错”的关键。
  void _autoDecide() {
    final logic = _logic;
    if (logic == null || _snakeLen == 0) return;
    final hx = _curX[0], hy = _curY[0];
    final fx = _food.dx.round(), fy = _food.dy.round();

    // —— 消费已到达的路径格 ——
    while (_nextPath.isNotEmpty &&
        _nextPath.first.$1 == hx &&
        _nextPath.first.$2 == hy) {
      _nextPath.removeAt(0);
    }

    // —— 沿已规划路径前进（成功则返回） ——
    if (_stepPath(hx, hy, fx, fy)) return;
    _nextPath = const []; // 当前路径失效，重新规划

    // —— 主：到食物的最短安全路径（整条吃球路线必须"吃完仍追得到尾"） ——
    _nextPath = _bfsPath(hx, hy, fx, fy);
    if (_nextPath.isNotEmpty &&
        _eatsSafely(_nextPath) &&
        _stepPath(hx, hy, fx, fy)) {
      return;
    }
    // 吃不安全 → 不硬冲，放手去守局
    _nextPath = const [];

    // —— 守局：追尾路径（食物被围时沿最有效路线绕大圈逼近满盘） ——
    final tx = _curX[_snakeLen - 1], ty = _curY[_snakeLen - 1];
    if ((tx != hx || ty != hy) && _canReachTailNow()) {
      // 仅当头仍能追到自己的尾时，追尾才是安全的保命圈
      _nextPath = _bfsPath(hx, hy, tx, ty);
      if (_nextPath.isNotEmpty && _stepPath(hx, hy, fx, fy)) return;
    }
    _nextPath = const [];

    // —— 超兜底：贪心跳转（几乎不会触发） ——
    final chase = _tailChase(hx, hy, fx, fy);
    if (chase == null) return;
    logic.turn(chase.$1, chase.$2);
  }

  /// 沿 _nextPath 前进一格，并尝试双键位连发实现紧凑转向。
  /// 返回是否成功走了一步。
  bool _stepPath(int hx, int hy, int fx, int fy) {
    final logic = _logic;
    if (logic == null || _nextPath.isEmpty) return false;
    final d0 = _dirTo((hx, hy), _nextPath.first);
    if (d0 == null ||
        !_isHeadDirSafe(hx, hy, d0.$1, d0.$2, fx, fy, _snakeLen)) {
      return false;
    }
    logic.turn(d0.$1, d0.$2);
    if (_nextPath.length >= 2) {
      final d1 = _dirTo(_nextPath[0], _nextPath[1]);
      if (d1 != null && (d1.$1 != d0.$1 || d1.$2 != d0.$2)) {
        logic.turn(d1.$1, d1.$2); // 第二键位提前入队 → 紧凑斜切
      }
    }
    return true;
  }

  /// 切换自动玩：开启时自动开始，结束后自动重开，方便挂机观看。
  void _toggleAuto() {
    setState(() {
      _auto = !_auto;
    });
    if (_auto) {
      if (!_playing || _over) {
        _start();
      } else if (_paused) {
        _togglePause();
      }
      _focusNode.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.keyW:
        _turn(const Offset(0, -1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.keyS:
        _turn(const Offset(0, 1));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyA:
        _turn(const Offset(-1, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyD:
        _turn(const Offset(1, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.space:
        if (!_playing) {
          _start();
        } else {
          _togglePause();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _start();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    // 电脑端：隐藏屏幕方向键，仅键盘操作；手机端：显示 D-pad
    final isMobile = AppScope.of(context).uiMode == 'mobile';
    final gridMax = isMobile ? 360.0 : 620.0;

    return Scaffold(
      backgroundColor: c.bg,
      body: _logicError
          ? Center(
              child: Text('游戏逻辑库加载失败',
                  style: TextStyle(fontSize: 14, color: c.textTertiary)),
            )
          : Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: _onKey,
              child: SafeArea(
                child: Column(
                  children: [
                    // 顶部栏：返回 + 标题 + FPS(游戏中) + 得分 + 最高分/设置
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () =>
                                AppScope.of(context).setPage(_morePageIndex),
                            icon: Icon(Icons.arrow_back_rounded,
                                size: 22, color: c.textSecondary),
                            tooltip: '返回',
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                          Text('贪吃蛇',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: c.text)),
                          const Spacer(),
                          // 自动玩：AI 接管（两平台均显示）
                          GestureDetector(
                            onTap: _toggleAuto,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _auto
                                    ? (isLight
                                        ? const Color(0xFFE6F9EC)
                                        : const Color(0xFF1F3D29))
                                    : c.cardAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: _auto
                                        ? (isLight
                                            ? const Color(0xFF34C759)
                                            : const Color(0xFF2ECC71))
                                        : (isLight
                                            ? const Color(0xFFE5E7EB)
                                            : const Color(0xFF3D3D45))),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      _auto
                                          ? Icons.smart_toy_rounded
                                          : Icons.smart_toy_outlined,
                                      size: 16,
                                      color: _auto
                                          ? (isLight
                                              ? const Color(0xFF16A34A)
                                              : const Color(0xFF4ADE80))
                                          : c.textSecondary),
                                  const SizedBox(width: 5),
                                  Text(_auto ? '自动玩中' : '自动玩',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: _auto
                                              ? (isLight
                                                  ? const Color(0xFF16A34A)
                                                  : const Color(0xFF4ADE80))
                                              : c.textSecondary)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // FPS：位于“当前得分”左侧
                          if (_playing) ...[
                            ValueListenableBuilder<double>(
                              valueListenable: _fpsNotifier,
                              builder: (ctx, fps, _) =>
                                  _fpsChip(c, isLight, fps, compact: isMobile),
                            ),
                            const SizedBox(width: 10),
                          ],
                          _scoreChip(c, '当前得分', '$_score', isLight),
                          // 电脑端：保留最高纪录与暂停按钮
                          if (!isMobile) ...[
                            const SizedBox(width: 10),
                            _scoreChip(c, '最高纪录', '$_highScore', isLight,
                                highlight:
                                    _score >= _highScore && _score > 0),
                            if (_playing) ...[
                              const SizedBox(width: 6),
                              TextButton.icon(
                                onPressed: _togglePause,
                                icon: Icon(
                                    _paused
                                        ? Icons.play_arrow_rounded
                                        : Icons.pause_rounded,
                                    size: 18),
                                label: Text(_paused ? '继续' : '暂停'),
                              ),
                            ],
                          ],
                          // 手机端：暂停/重来合并为顶部设置按钮
                          if (isMobile)
                            _SettingsMenu(
                              c: c,
                              playing: _playing,
                              paused: _paused,
                              onTogglePause: _togglePause,
                              onRestart: _start,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 网格地图（居中，限制最大尺寸以适配大屏/小屏）
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: gridMax, maxHeight: gridMax),
                          child: AspectRatio(
                            aspectRatio: _cols / _rows,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isLight
                                    ? const Color(0xFFF2F4F7)
                                    : const Color(0xFF242429),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: isLight
                                        ? const Color(0xFFE5E7EB)
                                        : const Color(0xFF3D3D45)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                        alpha: isLight ? 0.06 : 0.3),
                                    blurRadius: 30,
                                    offset: const Offset(0, 10),
                                    spreadRadius: -8,
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: LayoutBuilder(
                                builder: (ctx, cons) {
                                  final cw = cons.maxWidth / _cols;
                                  final ch = cons.maxHeight / _rows;
                                  Rect cellRect(Offset cell) => Rect.fromLTWH(
                                      cell.dx * cw, cell.dy * ch, cw, ch);
                                  return ValueListenableBuilder<int>(
                                    valueListenable: _frameSignal,
                                    builder: (context, _, __) {
                                      // 食物脉动（与旧版一致的时间累计式）
                                      final pulse = (_playing &&
                                              !_paused && !_over)
                                          ? 0.5 +
                                              0.5 *
                                                  math.sin(_pulseTime /
                                                      180000 *
                                                      math.pi)
                                          : 1.0;
                                      // 无敌闪烁：复活后蛇身在 0.4~1.0 之间快速脉动透明度
                                      final invincibleAlpha = _invincible
                                          ? 0.4 +
                                              0.6 *
                                                  (0.5 +
                                                      0.5 *
                                                          math.sin(
                                                              _pulseTime /
                                                                  32000 *
                                                                  math.pi))
                                          : 1.0;
                                      return Stack(
                                        children: [
                                          RepaintBoundary(
                                            child: CustomPaint(
                                                painter: _GridPainter(
                                                    c: c,
                                                    cols: _cols,
                                                    rows: _rows),
                                                size: Size.infinite),
                                          ),
                                          // RepaintBoundary 隔离食物脉动重绘，
                                          // 避免每帧弄脏整层棋盘
                                          Positioned.fromRect(
                                            rect: cellRect(_food),
                                            child: RepaintBoundary(
                                              child: _FoodDot(
                                                  isLight: isLight,
                                                  pulse: pulse),
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: RepaintBoundary(
                                              child: CustomPaint(
                                                painter: _SnakePainter(
                                                  points: _renderPts,
                                                  len: _snakeLen,
                                                  frame: _frameVersion,
                                                  cw: cw,
                                                  ch: ch,
                                                  isLight: isLight,
                                                  pendingDir: _pendingDir,
                                                  invincibleAlpha:
                                                      invincibleAlpha,
                                                ),
                                                size: Size.infinite,
                                              ),
                                            ),
                                          ),
                                          if (!_playing || _paused || _over)
                                            Positioned.fill(
                                              child: _Overlay(
                                                c: c,
                                                isLight: isLight,
                                                state: _over
                                                    ? 'over'
                                                    : (_paused
                                                        ? 'paused'
                                                        : 'idle'),
                                                score: _score,
                                                highScore: _highScore,
                                                onStart: _start,
                                                onResume: _togglePause,
                                                onRevive: _revive,
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
                      ),
                    ),
                    // 底部：手机端显示方向键，电脑端不显示
                    if (isMobile)
                      _Dpad(
                        c: c,
                        enabled: _playing && !_paused && !_over,
                        onTurn: _turn,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      isMobile
                          ? '方向键控制移动 · 右上角设置可暂停/重开'
                          : '键盘方向键 / WASD 控制移动 · 空格暂停 · R 重新开始',
                      style: TextStyle(fontSize: 11, color: c.textTertiary),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _fpsChip(AppColors c, bool isLight, double fps,
      {bool compact = false}) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: compact ? 7 : 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isLight ? const Color(0xFFE5E7EB) : const Color(0xFF3D3D45)),
      ),
      child: Text(compact ? '${fps.round()}fps' : '${fps.round()} FPS',
          style: TextStyle(
              fontSize: compact ? 9 : 10,
              fontWeight: FontWeight.w700,
              color: c.textSecondary)),
    );
  }

  Widget _scoreChip(AppColors c, String label, String value, bool isLight,
      {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: highlight
            ? (isLight ? const Color(0xFFFFF3E0) : const Color(0xFF4A3A18))
            : c.cardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: highlight
                ? (isLight
                    ? const Color(0xFFFFD28A)
                    : const Color(0xFF7A6A30))
                : (isLight
                    ? const Color(0xFFE5E7EB)
                    : const Color(0xFF3D3D45))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: c.textTertiary)),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: highlight
                      ? (isLight
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFFBBF24))
                      : c.text)),
        ],
      ),
    );
  }
}

/// 网格背景线
class _GridPainter extends CustomPainter {
  final AppColors c;
  final int cols;
  final int rows;
  _GridPainter({required this.c, this.cols = 20, this.rows = 20});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = c.isLight
          ? const Color(0x0A000000)
          : Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final stepX = size.width / cols;
    final stepY = size.height / rows;
    for (var i = 1; i < cols; i++) {
      canvas.drawLine(
          Offset(stepX * i, 0), Offset(stepX * i, size.height), paint);
    }
    for (var j = 1; j < rows; j++) {
      canvas.drawLine(
          Offset(0, stepY * j), Offset(size.width, stepY * j), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.c.isLight != c.isLight;
}

/// 蛇身绘制：连续圆滑蛇身（圆角拐弯），头部圆点 + 眼睛指示朝向
class _SnakePainter extends CustomPainter {
  final List<Offset> points; // 渲染坐标缓冲（复用，前 len 个有效）
  final int len; // 有效节数
  final int frame; // 帧版本号（每次逻辑/插值更新递增）
  final double cw; // 每格宽（像素）
  final double ch; // 每格高（像素）
  final bool isLight;
  final Offset pendingDir; // 下一格方向（无 pending 时等于当前方向）
  final double invincibleAlpha; // 无敌时蛇身透明度（1.0 = 正常；闪烁时 < 1.0）
  _SnakePainter({
    required this.points,
    required this.len,
    required this.frame,
    required this.cw,
    required this.ch,
    required this.isLight,
    required this.pendingDir,
    this.invincibleAlpha = 1.0,
  });

  Offset _px(Offset p) => Offset(p.dx * cw + cw / 2, p.dy * ch + ch / 2);

  @override
  void paint(Canvas canvas, Size size) {
    if (len == 0 || points.isEmpty) return;
    final bodyW = math.min(cw, ch) * 0.8; // 蛇身粗度
    final path = Path()..moveTo(_px(points[len - 1]).dx, _px(points[len - 1]).dy);
    // 从尾到头连线，圆角连接消除转弯处的方形棱角
    for (var i = len - 2; i >= 0; i--) {
      final p = _px(points[i]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bodyW
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = (isLight ? const Color(0xFF5CE07D) : const Color(0xFF27AE60))
            .withValues(alpha: invincibleAlpha),
    );
    // 头部
    final head = _px(points.first);
    final headR = bodyW / 2;
    canvas.drawCircle(
      head,
      headR,
      Paint()
        ..color =
            (isLight ? const Color(0xFF34C759) : const Color(0xFF2ECC71))
                .withValues(alpha: invincibleAlpha),
    );
    // 无敌光环：蛇身闪烁越透明，头部金色光圈越醒目（互补相位）
    if (invincibleAlpha < 1.0) {
      canvas.drawCircle(
        head,
        headR + 3.0,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color =
              const Color(0xFFFF9500).withValues(alpha: 1.0 - invincibleAlpha),
      );
    }
    // 眼睛：优先用 pendingDir —— 按键后（即使蛇身尚未移动）蛇头立即朝目标方向，
    // 提供“输入已被接收”的即时视觉反馈；无 pending 时 pendingDir == 当前方向，行为不变。
    final dir = pendingDir;
    final lenSq = dir.dx * dir.dx + dir.dy * dir.dy;
    final d = lenSq > 0
        ? Offset(dir.dx / math.sqrt(lenSq), dir.dy / math.sqrt(lenSq))
        : const Offset(1, 0);
    final n = Offset(-d.dy, d.dx);
    final eyeWhite = isLight ? Colors.white : const Color(0xFFE8F5E9);
    for (final s in [1.0, -1.0]) {
      final center = head + n * (headR * 0.5) * s + d * (headR * 0.4);
      canvas.drawCircle(center, headR * 0.32, Paint()..color = eyeWhite);
      canvas.drawCircle(
          center + d * (headR * 0.12),
          headR * 0.16,
          Paint()..color = const Color(0xFF1B5E20));
    }
  }

  @override
  bool shouldRepaint(covariant _SnakePainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.len != len ||
      oldDelegate.cw != cw ||
      oldDelegate.ch != ch ||
      oldDelegate.isLight != isLight ||
      oldDelegate.pendingDir != pendingDir ||
      oldDelegate.invincibleAlpha != invincibleAlpha;
}

/// 食物点（脉动动画）
class _FoodDot extends StatelessWidget {
  final bool isLight;
  final double pulse; // 0~1 脉动相位
  const _FoodDot({required this.isLight, this.pulse = 1.0});

  @override
  Widget build(BuildContext context) {
    final color = isLight ? const Color(0xFFFF6B6B) : const Color(0xFFE74C3C);
    return Transform.scale(
      scale: 0.82 + 0.18 * pulse,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 中央遮罩层：开始 / 暂停 / 结束
class _Overlay extends StatelessWidget {
  final AppColors c;
  final bool isLight;
  final String state; // idle / paused / over
  final int score;
  final int highScore;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onRevive;
  const _Overlay({
    required this.c,
    required this.isLight,
    required this.state,
    required this.score,
    required this.highScore,
    required this.onStart,
    required this.onResume,
    required this.onRevive,
  });

  @override
  Widget build(BuildContext context) {
    final (title, sub) = switch (state) {
      'paused' => ('已暂停', '按空格或点击继续'),
      'over' => ('游戏结束', '本局得分 $score · 最高纪录 $highScore'),
      _ => ('贪吃蛇', '吃掉食物成长，撞墙或撞到自己即结束'),
    };

    return Container(
      color: isLight
          ? Colors.white.withValues(alpha: 0.78)
          : const Color(0xFF1A1A1E).withValues(alpha: 0.8),
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
            // 结束：复活 + 再来一局 两个选项；暂停/开始：单个按钮
            if (state == 'over')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: onRevive,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('复活'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLight
                          ? const Color(0xFFFF9500)
                          : const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('再来一局'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      side: BorderSide(
                          color: isLight
                              ? const Color(0xFFE5E7EB)
                              : const Color(0xFF3D3D45)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              )
            else
              ElevatedButton.icon(
                onPressed: state == 'paused' ? onResume : onStart,
                icon: Icon(
                    state == 'paused'
                        ? Icons.play_arrow_rounded
                        : Icons.restart_alt_rounded,
                    size: 18),
                label: Text(state == 'paused' ? '继续游戏' : '开始游戏'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLight
                      ? const Color(0xFF34C759)
                      : const Color(0xFF2ECC71),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 屏幕方向键（仅手机端显示）：十字布局，间距更合理
class _Dpad extends StatelessWidget {
  final AppColors c;
  final bool enabled;
  final ValueChanged<Offset> onTurn;
  const _Dpad({
    required this.c,
    required this.enabled,
    required this.onTurn,
  });

  @override
  Widget build(BuildContext context) {
    const btnSize = 56.0;
    Widget arrow(IconData icon, Offset dir) {
      return GestureDetector(
        onTap: enabled ? () => onTurn(dir) : null,
        child: Container(
          width: btnSize,
          height: btnSize,
          decoration: BoxDecoration(
            color: enabled
                ? (c.isLight
                    ? const Color(0xFFF0F2F5)
                    : const Color(0xFF33333A))
                : c.cardAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: c.isLight
                    ? const Color(0xFFE5E7EB)
                    : const Color(0xFF3D3D45)),
          ),
          child: Icon(icon,
              size: 28,
              color: enabled ? c.textSecondary : c.textTertiary),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        arrow(Icons.keyboard_arrow_up_rounded, const Offset(0, -1)),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            arrow(Icons.keyboard_arrow_left_rounded, const Offset(-1, 0)),
            const SizedBox(width: 44),
            arrow(Icons.keyboard_arrow_right_rounded, const Offset(1, 0)),
          ],
        ),
        const SizedBox(height: 14),
        arrow(Icons.keyboard_arrow_down_rounded, const Offset(0, 1)),
      ],
    );
  }
}

/// 手机端顶部设置菜单：暂停/继续 + 重新开始
class _SettingsMenu extends StatelessWidget {
  final AppColors c;
  final bool playing;
  final bool paused;
  final VoidCallback onTogglePause;
  final VoidCallback onRestart;
  const _SettingsMenu({
    required this.c,
    required this.playing,
    required this.paused,
    required this.onTogglePause,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '设置',
      color: c.cardAlt,
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == 'pause') onTogglePause();
        if (v == 'restart') onRestart();
      },
      itemBuilder: (ctx) => [
        if (playing)
          PopupMenuItem(
            value: 'pause',
            height: 44,
            child: Row(
              children: [
                Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 18, color: c.textSecondary),
                const SizedBox(width: 10),
                Text(paused ? '继续' : '暂停',
                    style: TextStyle(fontSize: 14, color: c.text)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'restart',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.replay_rounded, size: 18, color: c.textSecondary),
              const SizedBox(width: 10),
              Text('重新开始',
                  style: TextStyle(fontSize: 14, color: c.text)),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child:
            Icon(Icons.settings_outlined, size: 22, color: c.textSecondary),
      ),
    );
  }
}
