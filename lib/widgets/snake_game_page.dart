/// 贪吃蛇小游戏：全屏沉浸式页面
/// - 电脑端：仅键盘操作（方向键 / WASD），不显示屏幕方向键
/// - 手机端：显示 D-pad 方向键，支持触屏操作
/// - 渲染：Ticker 驱动（跟随屏幕刷新率，120Hz 显示器即 120 帧），蛇身平滑插值移动
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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

  // 逻辑蛇（头在 index 0，整格坐标）
  final List<Offset> _snake = [];
  // 上一次逻辑步进的蛇（用于两次步进之间插值，实现 120fps 平滑移动）
  final List<Offset> _prevSnake = [];
  Offset _food = const Offset(8, 8);
  Offset _dir = const Offset(1, 0); // 当前移动方向
  Offset _pendingDir = const Offset(1, 0); // 缓冲方向（防止一帧内连续反向）
  bool _playing = false; // 进行中
  bool _paused = false;
  bool _over = false;
  int _score = 0;
  int _highScore = 0;
  Duration _tick = const Duration(milliseconds: 180); // 逻辑步进间隔

  // ===== 120fps 渲染 =====
  late final Ticker _ticker;
  Duration? _lastFrameTime; // 上一帧时间（用于计算帧间隔）
  Duration _logicElapsed = Duration.zero; // 距上次逻辑步进的累积时间
  double _moveProgress = 1.0; // 本次移动插值进度 0~1
  // FPS 统计
  int _frames = 0;
  Duration _fpsAccum = Duration.zero;
  double _fps = 0;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _highScore = Storage.loadSnakeHighScore();
    _resetSnake();
    _ticker = createTicker(_onFrame); // 游戏开始时 start
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetSnake() {
    _snake
      ..clear()
      ..addAll([const Offset(10, 10), const Offset(9, 10), const Offset(8, 10)]);
    _dir = const Offset(1, 0);
    _pendingDir = const Offset(1, 0);
    _score = 0;
    _tick = const Duration(milliseconds: 180);
    _food = _randomFreeCell();
    _over = false;
    _paused = false;
    _moveProgress = 1.0;
    _logicElapsed = Duration.zero;
  }

  /// 在非蛇身位置随机生成食物
  Offset _randomFreeCell() {
    final occupied = _snake.toSet();
    final free = <Offset>[];
    for (var x = 0; x < _cols; x++) {
      for (var y = 0; y < _rows; y++) {
        final p = Offset(x.toDouble(), y.toDouble());
        if (!occupied.contains(p)) free.add(p);
      }
    }
    if (free.isEmpty) return const Offset(0, 0);
    return free[math.Random().nextInt(free.length)];
  }

  void _start() {
    _resetSnake();
    setState(() => _playing = true);
    _focusNode.requestFocus();
    _lastFrameTime = null;
    if (!_ticker.isActive) _ticker.start();
  }

  void _togglePause() {
    if (!_playing || _over) return;
    setState(() => _paused = !_paused);
    if (_paused) {
      _ticker.stop();
    } else {
      _lastFrameTime = null;
      _ticker.start();
      _focusNode.requestFocus();
    }
  }

  /// 每帧回调：驱动逻辑步进 + 插值渲染（跟随屏幕刷新率）
  void _onFrame(Duration elapsed) {
    final dt = _lastFrameTime == null
        ? Duration.zero
        : elapsed - _lastFrameTime!;
    _lastFrameTime = elapsed;

    // FPS 统计（每秒更新一次）
    _frames++;
    _fpsAccum += dt;
    if (_fpsAccum >= const Duration(seconds: 1)) {
      final s = _fpsAccum.inMicroseconds / 1000000.0;
      setState(() {
        _fps = _frames / s;
        _frames = 0;
        _fpsAccum = Duration.zero;
      });
    }

    if (!_playing || _paused || _over) return;

    // 累积逻辑时间，满足步进间隔则执行一步
    _logicElapsed += dt;
    while (_logicElapsed >= _tick) {
      _logicElapsed -= _tick;
      _stepLogic();
      if (_over) break;
    }
    if (_playing && !_paused && !_over) {
      setState(() {
        _moveProgress =
            (_logicElapsed.inMicroseconds / _tick.inMicroseconds).clamp(0.0, 1.0);
      });
    }
  }

  /// 一步逻辑移动（纯逻辑，渲染由 _onFrame 驱动）
  void _stepLogic() {
    _prevSnake
      ..clear()
      ..addAll(_snake);
    _dir = _pendingDir;
    final head = _snake.first + _dir;
    // 撞墙
    if (head.dx < 0 || head.dx >= _cols || head.dy < 0 || head.dy >= _rows) {
      _gameOver();
      return;
    }
    // 撞自己（尾巴即将移开时不算撞）
    final willMove = !(head == _snake.last);
    if (willMove && _snake.sublist(0, _snake.length - 1).contains(head)) {
      _gameOver();
      return;
    }
    _snake.insert(0, head);
    if (head == _food) {
      _score += 10;
      // 速度随得分提升
      if (_score % 50 == 0 && _tick > const Duration(milliseconds: 90)) {
        _tick = Duration(milliseconds: math.max(90, 180 - _score ~/ 10 * 6));
      }
      _food = _randomFreeCell();
    } else {
      _snake.removeLast();
    }
  }

  void _gameOver() {
    _playing = false;
    _over = true;
    _ticker.stop();
    if (_score > _highScore) {
      _highScore = _score;
      Storage.saveSnakeHighScore(_highScore);
    }
    setState(() {});
  }

  /// 第 i 节的渲染位置（在两次逻辑步进之间做平滑插值）
  Offset _renderPos(int i) {
    final cur = _snake[i];
    final prev = i < _prevSnake.length ? _prevSnake[i] : cur;
    final t = Curves.easeOut.transform(_moveProgress);
    return Offset.lerp(prev, cur, t) ?? cur;
  }

  /// 键盘/方向按键：转换为移动方向（禁止直接反向）
  void _turn(Offset newDir) {
    if (!_playing || _paused || _over) return;
    // 反向检测：_dir 是当前实际方向
    if (newDir == -_dir) return;
    // 同一方向忽略
    if (newDir == _pendingDir) return;
    setState(() => _pendingDir = newDir);
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
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏：返回 + 标题 + FPS(仅电脑端游戏中) + 得分/最高分 + 暂停
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 16, 4),
                child: Row(
                  children: [
                    // 返回按钮（回到更多功能）
                    IconButton(
                      onPressed: () => AppScope.of(context).setPage(_morePageIndex),
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
                    if (_playing && !isMobile) ...[
                      _fpsChip(c, isLight),
                      const SizedBox(width: 10),
                    ],
                    _scoreChip(c, '当前得分', '$_score', isLight),
                    const SizedBox(width: 10),
                    _scoreChip(c, '最高纪录', '$_highScore', isLight,
                        highlight: _score >= _highScore && _score > 0),
                    if (_playing && !isMobile) ...[
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
                              color: Colors.black
                                  .withValues(alpha: isLight ? 0.06 : 0.3),
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
                            // 食物脉动（仅游戏中）
                            final pulse =
                                (_playing && !_paused && !_over)
                                    ? 0.5 +
                                        0.5 *
                                            math.sin(_logicElapsed.inMicroseconds /
                                                180000 *
                                                math.pi)
                                    : 1.0;
                            return Stack(
                              children: [
                                // 网格线（静态，RepaintBoundary 隔离避免每帧重绘）
                                RepaintBoundary(
                                  child: CustomPaint(
                                      painter: _GridPainter(
                                          c: c, cols: _cols, rows: _rows),
                                      size: Size.infinite),
                                ),
                                // 食物
                                Positioned.fromRect(
                                  rect: cellRect(_food),
                                  child: _FoodDot(
                                      isLight: isLight, pulse: pulse),
                                ),
                                // 蛇身（插值位置实现 120fps 平滑移动）
                                for (var i = 0; i < _snake.length; i++)
                                  Positioned.fromRect(
                                    rect: cellRect(_renderPos(i)),
                                    child: Padding(
                                      padding: const EdgeInsets.all(1.2),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: i == 0
                                              ? (isLight
                                                  ? const Color(0xFF34C759)
                                                  : const Color(0xFF2ECC71))
                                              : (isLight
                                                  ? const Color(0xFF5CE07D)
                                                  : const Color(0xFF27AE60)),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                // 遮罩：未开始 / 暂停 / 结束
                                if (!_playing || _paused || _over)
                                  Positioned.fill(
                                    child: _Overlay(
                                      c: c,
                                      isLight: isLight,
                                      state: _over
                                          ? 'over'
                                          : (_paused ? 'paused' : 'idle'),
                                      score: _score,
                                      highScore: _highScore,
                                      onStart: _start,
                                      onResume: _togglePause,
                                    ),
                                  ),
                              ],
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
                  onTogglePause: _togglePause,
                  onRestart: _start,
                ),
              const SizedBox(height: 10),
              Text(
                isMobile
                    ? '方向键控制移动 · 中间按钮暂停/重开'
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

  Widget _fpsChip(AppColors c, bool isLight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.cardAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isLight ? const Color(0xFFE5E7EB) : const Color(0xFF3D3D45)),
      ),
      child: Text('${_fps.round()} FPS',
          style: TextStyle(
              fontSize: 10,
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
      canvas.drawLine(Offset(stepX * i, 0), Offset(stepX * i, size.height), paint);
    }
    for (var j = 1; j < rows; j++) {
      canvas.drawLine(Offset(0, stepY * j), Offset(size.width, stepY * j), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      oldDelegate.c.isLight != c.isLight;
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
            Icon(Icons.sports_esports_outlined, size: 40, color: c.textTertiary),
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
                  state == 'paused' ? Icons.play_arrow_rounded : Icons.restart_alt_rounded,
                  size: 18),
              label: Text(btnLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: isLight
                    ? const Color(0xFF34C759)
                    : const Color(0xFF2ECC71),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
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

/// 屏幕方向键（仅手机端显示）
class _Dpad extends StatelessWidget {
  final AppColors c;
  final bool enabled;
  final ValueChanged<Offset> onTurn;
  final VoidCallback onTogglePause;
  final VoidCallback onRestart;
  const _Dpad({
    required this.c,
    required this.enabled,
    required this.onTurn,
    required this.onTogglePause,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    const btnSize = 52.0;
    Widget btn(IconData icon, VoidCallback cb, {Color? bg}) {
      return GestureDetector(
        onTap: enabled ? cb : null,
        child: Container(
          width: btnSize,
          height: btnSize,
          decoration: BoxDecoration(
            color: enabled
                ? (bg ??
                    (c.isLight
                        ? const Color(0xFFF0F2F5)
                        : const Color(0xFF33333A)))
                : c.cardAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: c.isLight
                    ? const Color(0xFFE5E7EB)
                    : const Color(0xFF3D3D45)),
          ),
          child: Icon(icon,
              size: 24,
              color: enabled ? c.textSecondary : c.textTertiary),
        ),
      );
    }

    return Column(
      children: [
        btn(Icons.keyboard_arrow_up_rounded, () => onTurn(const Offset(0, -1))),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.keyboard_arrow_left_rounded, () => onTurn(const Offset(-1, 0))),
            const SizedBox(width: 8),
            btn(Icons.replay_rounded, onRestart, bg: c.primaryLight),
            const SizedBox(width: 8),
            btn(
              Icons.pause_rounded,
              onTogglePause,
              bg: c.primaryLight,
            ),
            const SizedBox(width: 8),
            btn(Icons.keyboard_arrow_right_rounded, () => onTurn(const Offset(1, 0))),
          ],
        ),
        const SizedBox(height: 8),
        btn(Icons.keyboard_arrow_down_rounded, () => onTurn(const Offset(0, 1))),
      ],
    );
  }
}
