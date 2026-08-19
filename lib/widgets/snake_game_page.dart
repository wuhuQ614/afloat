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
  List<Offset> _snake = []; // 当前格坐标（头在 0）
  List<Offset> _prevSnake = []; // 上一逻辑步坐标（用于插值）
  Offset _food = const Offset(8, 8);
  double _moveProgress = 1.0; // 本次移动插值进度 0~1

  // ===== UI 状态（从快照同步） =====
  bool _playing = false;
  bool _paused = false;
  bool _over = false;
  int _score = 0;
  int _highScore = 0;
  bool _lastSyncPaused = false;
  bool _lastSyncOver = false;
  int _lastSyncScore = -1;

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

    final (cx, cy, px, py) = logic.snakePos(s.snakeLen);
    _snake = List.generate(
        s.snakeLen, (i) => Offset(cx[i].toDouble(), cy[i].toDouble()));
    _prevSnake = List.generate(
        s.snakeLen, (i) => Offset(px[i].toDouble(), py[i].toDouble()));

    // 状态变化检测（仅变化时 setState，避免整页每帧重建）
    final scoreChanged = s.score != _lastSyncScore;
    final pausedChanged = (s.paused == 1) != _lastSyncPaused;
    final overChanged = (s.over == 1) != _lastSyncOver;
    _score = s.score;
    _playing = s.playing == 1;
    _paused = s.paused == 1;
    _over = s.over == 1;
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
    logic.start();
    _syncFromLogic();
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
        _frameSignal.value++; // 仅重建棋盘区域
      }
    }
  }

  /// 转向（由 C++ 内部做方向队列缓冲与反向检测）
  void _turn(Offset newDir) {
    final logic = _logic;
    if (logic == null) return;
    logic.turn(newDir.dx.round(), newDir.dy.round());
  }

  /// 第 i 节的渲染位置（在两次逻辑步进之间做平滑插值）
  Offset _renderPos(int i) {
    final cur = _snake[i];
    final prev = i < _prevSnake.length ? _prevSnake[i] : cur;
    final t = Curves.easeOut.transform(_moveProgress);
    return Offset.lerp(prev, cur, t) ?? cur;
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
                                          Positioned.fromRect(
                                            rect: cellRect(_food),
                                            child: _FoodDot(
                                                isLight: isLight,
                                                pulse: pulse),
                                          ),
                                          Positioned.fill(
                                            child: RepaintBoundary(
                                              child: CustomPaint(
                                                painter: _SnakePainter(
                                                  points: List.generate(
                                                      _snake.length,
                                                      (i) => _renderPos(i)),
                                                  cw: cw,
                                                  ch: ch,
                                                  isLight: isLight,
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
  final List<Offset> points; // 逻辑格坐标（含插值）
  final double cw; // 每格宽（像素）
  final double ch; // 每格高（像素）
  final bool isLight;
  _SnakePainter({
    required this.points,
    required this.cw,
    required this.ch,
    required this.isLight,
  });

  Offset _px(Offset p) => Offset(p.dx * cw + cw / 2, p.dy * ch + ch / 2);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final bodyW = math.min(cw, ch) * 0.8; // 蛇身粗度
    final path = Path()..moveTo(_px(points.last).dx, _px(points.last).dy);
    // 从尾到头连线，圆角连接消除转弯处的方形棱角
    for (var i = points.length - 2; i >= 0; i--) {
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
        ..color = isLight
            ? const Color(0xFF5CE07D)
            : const Color(0xFF27AE60),
    );
    // 头部
    final head = _px(points.first);
    final headR = bodyW / 2;
    canvas.drawCircle(
      head,
      headR,
      Paint()
        ..color = isLight ? const Color(0xFF34C759) : const Color(0xFF2ECC71),
    );
    // 眼睛：按头部朝向放置
    final dir = points.length >= 2 ? points[0] - points[1] : const Offset(1, 0);
    final len = math.sqrt(dir.dx * dir.dx + dir.dy * dir.dy);
    final d = len > 0 ? Offset(dir.dx / len, dir.dy / len) : const Offset(1, 0);
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
  bool shouldRepaint(covariant _SnakePainter oldDelegate) => true;
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
  const _Overlay({
    required this.c,
    required this.isLight,
    required this.state,
    required this.score,
    required this.highScore,
    required this.onStart,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final (title, sub, btnLabel, action) = switch (state) {
      'paused' => (
          '已暂停',
          '按空格或点击继续',
          '继续游戏',
          onResume as VoidCallback?
        ),
      'over' => (
          '游戏结束',
          '本局得分 $score · 最高纪录 $highScore',
          '再来一局',
          onStart as VoidCallback?
        ),
      _ => (
          '贪吃蛇',
          '吃掉食物成长，撞墙或撞到自己即结束',
          '开始游戏',
          onStart as VoidCallback?
        ),
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
            ElevatedButton.icon(
              onPressed: action,
              icon: Icon(
                  state == 'paused'
                      ? Icons.play_arrow_rounded
                      : Icons.restart_alt_rounded,
                  size: 18),
              label: Text(btnLabel),
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
