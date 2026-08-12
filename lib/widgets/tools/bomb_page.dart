/// 暴力翻牌（排雷炸弹）页面：一比一复刻参考项目 BombTab.jsx。
///
/// 玩法：2-8 人，卡牌数 = 人数+1，其中随机 1 张为炸弹💣。
/// 玩家轮流选一张盖住的卡，全部选完后点"开牌！"统一揭底。
/// - 炸弹被选中：playThud + 红字 "💥 玩家N 被炸了！"
/// - 炸弹未被选中：playDing + 绿字 "🎉无人伤亡，运气爆棚！"
///
/// 人数选择：按住"选择人数"按钮出现径向转盘（7 段，2-8 人），
/// 拖动经过分段时 playWheelTick，松手确认。
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';
import 'tools_audio.dart';

/// 玩家标识色板（对齐参考项目 playerColors）
const List<Color> _playerColors = [
  Color(0xFFEF4444),
  Color(0xFF3B82F6),
  Color(0xFF22C55E),
  Color(0xFFF59E0B),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
];

/// 人数转盘扇区色板（对齐参考项目 colors）
const List<Color> _wheelSegColors = [
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFF59E0B),
  Color(0xFF22C55E),
  Color(0xFF06B6D4),
  Color(0xFF3B82F6),
  Color(0xFF8B5CF6),
];

class BombTabPage extends StatefulWidget {
  const BombTabPage({super.key});

  @override
  State<BombTabPage> createState() => _BombTabPageState();
}

class _BombTabPageState extends State<BombTabPage> {
  static const String _storageKey = 'bombPlayerCount';

  /// 游戏状态机（对齐参考项目 gameState）
  String _gameState = 'setup'; // setup | playing | ready | revealed
  int _playerCount = 3;
  int _bombIndex = -1;
  int _currentPlayer = 1;
  final Map<int, int> _selections = {}; // 卡牌索引 → 玩家编号
  final Set<int> _flippedCards = {};
  /// P2-1：用 ValueNotifier 跟踪翻牌状态，仅卡牌区域重建，不重建整页
  final ValueNotifier<Set<int>> _flippedNotifier = ValueNotifier(<int>{});
  String _resultMessage = '';

  // 人数转盘
  bool _showWheel = false;
  int _hoverPlayerCount = 3;
  OverlayEntry? _wheelOverlay;
  Offset _wheelCenter = Offset.zero;
  int _lastHovered = 3;

  final ToolsAudio _audio = ToolsAudio.instance;

  @override
  void initState() {
    super.initState();
    _loadPlayerCount();
  }

  Future<void> _loadPlayerCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_storageKey);
      if (v != null && v >= 2 && v <= 8 && mounted) {
        setState(() {
          _playerCount = v;
          _hoverPlayerCount = v;
        });
      }
    } catch (_) {}
  }

  Future<void> _savePlayerCount(int v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageKey, v);
    } catch (_) {}
  }

  int get _totalCards => _playerCount + 1;

  void _startGame() {
    _audio.playTick();
    setState(() {
      _bombIndex = math.Random().nextInt(_totalCards);
      _currentPlayer = 1;
      _selections.clear();
      _flippedCards.clear();
      _gameState = 'playing';
      _resultMessage = '';
    });
  }

  void _selectCard(int index) {
    if (_gameState != 'playing' || _selections.containsKey(index)) return;
    _audio.playWheelTick();
    HapticFeedback.vibrate();
    setState(() {
      _selections[index] = _currentPlayer;
      if (_currentPlayer >= _playerCount) {
        _gameState = 'ready';
      } else {
        _currentPlayer++;
      }
    });
  }

  /// 开牌：300ms 后翻炸弹卡，再 400ms 后其余卡逐张翻开（每张间隔 100ms，对齐参考项目 stagger）
  /// P2-1：通过 ValueNotifier 隔离翻牌重建，仅卡牌区域重建，不重建整页
  void _revealCards() {
    setState(() => _gameState = 'revealed');
    final bombVictimId = _selections[_bombIndex];

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _flippedCards.add(_bombIndex);
      _flippedNotifier.value = Set.of(_flippedCards);

      // 炸弹卡翻开 400ms 后，其余卡逐张翻开（每张间隔 100ms）
      Future.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        final others = <int>[];
        for (var i = 0; i < _totalCards; i++) {
          if (i != _bombIndex) others.add(i);
        }
        for (var k = 0; k < others.length; k++) {
          Future.delayed(Duration(milliseconds: k * 100), () {
            if (!mounted) return;
            _flippedCards.add(others[k]);
            _flippedNotifier.value = Set.of(_flippedCards);
          });
        }
      });

      if (bombVictimId != null) {
        _audio.playThud();
        HapticFeedback.heavyImpact();
        setState(() => _resultMessage = '💥 玩家$bombVictimId 被炸了！');
      } else {
        _audio.playDing();
        HapticFeedback.lightImpact();
        setState(() => _resultMessage = '🎉无人伤亡，运气爆棚！');
      }
    });
  }

  void _resetGame() {
    _audio.playTick();
    setState(() {
      _gameState = 'setup';
      _selections.clear();
      _flippedCards.clear();
      _bombIndex = -1;
    });
  }

  // ==================== 人数转盘 ====================

  void _onWheelPressDown(Offset globalPos) {
    _wheelCenter = globalPos;
    setState(() {
      _showWheel = true;
      _hoverPlayerCount = _playerCount;
      _lastHovered = _playerCount;
    });
    _showWheelOverlay();
  }

  void _onWheelPressMove(Offset globalPos) {
    if (!_showWheel) return;
    final dx = globalPos.dx - _wheelCenter.dx;
    final dy = globalPos.dy - _wheelCenter.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 15) return;
    const players = [2, 3, 4, 5, 6, 7, 8];
    var angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += math.pi * 2;
    final seg = (math.pi * 2) / players.length;
    final idx = (((angle + seg / 2) % (math.pi * 2)) / seg).floor();
    final p = players[idx % players.length];
    if (p != _hoverPlayerCount) {
      setState(() => _hoverPlayerCount = p);
      _updateWheelOverlay();
    }
    if (p != _lastHovered) {
      _audio.playWheelTick();
      _lastHovered = p;
    }
  }

  void _onWheelPressEnd() {
    if (!_showWheel) return;
    setState(() => _showWheel = false);
    _removeWheelOverlay();
    if (_hoverPlayerCount != _playerCount) {
      _audio.playTick();
      setState(() => _playerCount = _hoverPlayerCount);
      _savePlayerCount(_hoverPlayerCount);
    }
  }

  void _showWheelOverlay() {
    _wheelOverlay = OverlayEntry(
      builder: (context) => _PlayerWheelOverlay(
        center: _wheelCenter,
        hovered: _hoverPlayerCount,
      ),
    );
    Overlay.of(context).insert(_wheelOverlay!);
  }

  void _updateWheelOverlay() => _wheelOverlay?.markNeedsBuild();

  void _removeWheelOverlay() {
    _wheelOverlay?.remove();
    _wheelOverlay = null;
  }

  @override
  void dispose() {
    _removeWheelOverlay();
    _flippedNotifier.dispose();
    super.dispose();
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448), // max-w-md
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (_gameState != 'setup') _buildStatusHeader(),
                  // P2-1：ValueListenableBuilder 隔离卡牌区域，翻牌时仅重建网格
                  Expanded(
                    child: ValueListenableBuilder<Set<int>>(
                      valueListenable: _flippedNotifier,
                      builder: (context, _, __) => _buildCardGrid(),
                    ),
                  ),
                  _buildBottomControls(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    Widget content;
    switch (_gameState) {
      case 'playing':
        content = Column(children: [
          const Text('轮到你了',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text('玩家$_currentPlayer 选一张',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _playerColors[(_currentPlayer - 1) % _playerColors.length])),
        ]);
      case 'ready':
        content = Column(children: const [
          Text('全部选好',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2)),
          SizedBox(height: 4),
          Text('点击按钮开牌！',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFBBF24))),
        ]);
      case 'revealed':
        final hasVictim = _selections[_bombIndex] != null;
        content = Text(_resultMessage,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: hasVictim ? const Color(0xFFEF4444) : const Color(0xFF34D399)));
      default:
        content = const SizedBox();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: content,
    );
  }

  Widget _buildCardGrid() {
    final cols = _totalCards > 4 ? 3 : 2;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320), // max-w-xs
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4 / 5,
          ),
          itemCount: _totalCards,
          itemBuilder: (context, i) => _buildCard(i),
        ),
      ),
    );
  }

  Widget _buildCard(int i) {
    final isSelected = _selections.containsKey(i);
    final selectorId = _selections[i];
    final isBomb = i == _bombIndex;
    final isRevealed = _gameState == 'revealed' && _flippedCards.contains(i);
    final tappable = _gameState == 'playing' && !isSelected;

    return _FlipCard(
      flipped: isRevealed,
      front: _buildCardFront(isSelected, selectorId, tappable),
      back: _buildCardBack(isBomb, selectorId),
      onTap: tappable ? () => _selectCard(i) : null,
    );
  }

  /// 卡牌正面：蓝底斜纹 + 问号；已选时显示玩家色圆标
  Widget _buildCardFront(bool isSelected, int? selectorId, bool tappable) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF818CF8) : const Color(0xFF93C5FD),
          width: 2,
        ),
        color: isSelected ? const Color(0xFFE0E7FF) : const Color(0xFFBFDBFE),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!isSelected)
              CustomPaint(painter: _DiagonalStripesPainter()),
            Center(
              child: isSelected && selectorId != null
                  ? Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _playerColors[(selectorId - 1) % _playerColors.length],
                      ),
                      alignment: Alignment.center,
                      child: Text('P$selectorId',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18)),
                    )
                  : const Text('?',
                      style: TextStyle(
                          fontSize: 60,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E40AF))),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡牌背面：炸弹红渐变💣 / 安全绿渐变✅
  Widget _buildCardBack(bool isBomb, int? selectorId) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isBomb ? const Color(0xFFEF4444) : const Color(0xFF34D399),
          width: 2,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isBomb
              ? [const Color(0xFFDC2626), const Color(0xFF991B1B)]
              : [const Color(0xFF10B981), const Color(0xFF047857)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(isBomb ? '💣' : '✅', style: const TextStyle(fontSize: 48)),
          if (selectorId != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('玩家$selectorId',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_gameState == 'setup') ...[
              _buildPlayerCountButton(),
              const SizedBox(height: 8),
              _actionButton(
                label: '生成炸弹',
                labelColor: Colors.black87,
                onTap: _startGame,
              ),
            ],
            if (_gameState == 'playing')
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.grey)),
                    SizedBox(width: 8),
                    Text('等待玩家选项…',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                  ],
                ),
              ),
            if (_gameState == 'ready')
              _actionButton(
                label: '开牌！',
                labelColor: Colors.white,
                // 对齐参考项目 from-red-600 via-pink-600 to-rose-600
                gradient: const [Color(0xFFDC2626), Color(0xFFDB2777), Color(0xFFE11D48)],
                onTap: _revealCards,
                pulse: true,
              ),
            if (_gameState == 'revealed')
              _actionButton(
                label: '🔄 再来一局',
                labelColor: const Color(0xFF2563EB),
                onTap: _resetGame,
              ),
          ],
        ),
      ),
    );
  }

  /// 人数选择按钮：按住拖出转盘
  Widget _buildPlayerCountButton() {
    return GestureDetector(
      onPanStart: (d) => _onWheelPressDown(d.globalPosition),
      onPanUpdate: (d) => _onWheelPressMove(d.globalPosition),
      onPanEnd: (_) => _onWheelPressEnd(),
      onPanCancel: _onWheelPressEnd,
      onTapDown: (d) => _onWheelPressDown(d.globalPosition),
      onTapUp: (_) => _onWheelPressEnd(),
      onTapCancel: _onWheelPressEnd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '选择人数：$_playerCount 人',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  /// 玻璃风格动作按钮
  Widget _actionButton({
    required String label,
    required Color labelColor,
    required VoidCallback onTap,
    bool pulse = false,
    List<Color>? gradient, // 渐变填充（开牌按钮用红色渐变）
  }) {
    final useGradient = gradient != null && gradient.length >= 2;
    Widget btn = GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: useGradient
              ? LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: useGradient ? null : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: useGradient ? null : Border.all(color: Colors.white.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: useGradient ? 0.25 : 0.1),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  // 渐变按钮用白字，否则用传入的颜色
                  color: useGradient ? Colors.white : labelColor)),
        ),
      ),
    );
    if (pulse) {
      btn = _Pulse(child: btn);
    }
    return btn;
  }
}

/// 卡牌 3D 翻转组件（rotateY，对齐参考项目 duration-700 + perspective 1000px）
class _FlipCard extends StatefulWidget {
  final bool flipped;
  final Widget front;
  final Widget back;
  final VoidCallback? onTap;

  const _FlipCard({
    required this.flipped,
    required this.front,
    required this.back,
    this.onTap,
  });

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    if (widget.flipped) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.flipped != old.flipped) {
      widget.flipped ? _ctrl.forward() : _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final angle = _anim.value * math.pi;
        final showFront = angle < math.pi / 2;
        return GestureDetector(
          onTap: widget.onTap,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective ≈ 1000px
              ..rotateY(angle),
            child: showFront ? widget.front : Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(math.pi),
              child: widget.back,
            ),
          ),
        );
      },
    );
  }
}

/// 卡牌正面蓝底斜纹（对齐 repeating-linear-gradient -45deg）
class _DiagonalStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.6)
      ..strokeWidth = 1;
    const step = 7.0; // 6px 透明 + 1px 线
    final diag = size.width + size.height;
    for (var d = -size.height; d < diag; d += step) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 开牌按钮脉冲动画（对齐 animate-pulse）
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: Tween<double>(begin: 1, end: 0.6).animate(_ctrl), child: widget.child);
  }
}

/// 人数选择径向转盘（Overlay 显示在按压位置）
class _PlayerWheelOverlay extends StatelessWidget {
  final Offset center;
  final int hovered;

  const _PlayerWheelOverlay({required this.center, required this.hovered});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - 112,
      top: center.dy - 112,
      child: IgnorePointer(
        child: Container(
          width: 224,
          height: 224,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xCCBFDBFE),
                Color(0xCC93C5FD),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 25,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: CustomPaint(painter: _WheelPainter(hovered: hovered)),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final int hovered;

  _WheelPainter({required this.hovered});

  static const List<int> _players = [2, 3, 4, 5, 6, 7, 8];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final segAngle = (math.pi * 2) / _players.length;
    const r1 = 35.0;
    const r2 = 80.0;
    final scale = size.width / 200; // 参考 SVG viewBox 200×200
    final sr1 = r1 * scale;
    final sr2 = r2 * scale;

    for (var i = 0; i < _players.length; i++) {
      final p = _players[i];
      // startAngle = -90° - seg/2（顶部扇区居中），顺时针
      final startAngle = -math.pi / 2 - segAngle / 2 + segAngle * i;
      final endAngle = startAngle + segAngle;
      final isHovered = hovered == p;

      final path = Path();
      path.arcTo(Rect.fromCircle(center: c, radius: sr1), startAngle, segAngle, false);
      path.arcTo(Rect.fromCircle(center: c, radius: sr2), endAngle, -segAngle, false);
      path.close();

      canvas.drawPath(
        path,
        Paint()..color = isHovered ? _wheelSegColors[i] : const Color(0xFFDBEAFE),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF93C5FD),
      );

      // 数字标签
      final midAngle = startAngle + segAngle / 2;
      final labelR = (sr1 + sr2) / 2;
      final lp = c + Offset(labelR * math.cos(midAngle), labelR * math.sin(midAngle));
      final tp = TextPainter(
        text: TextSpan(
          text: '$p',
          style: TextStyle(
            fontSize: 16 * scale,
            fontWeight: FontWeight.bold,
            color: isHovered ? Colors.white : const Color(0xFF3B82F6),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
    }

    // 中心圆
    canvas.drawCircle(
      c,
      32 * scale,
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      c,
      32 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.5),
    );

    // 中心文字：人数 + 数值
    _paintCenterText(canvas, c, '人数', 11 * scale, const Color(0xFF64748B), -8 * scale);
    _paintCenterText(canvas, c, '$hovered', 20 * scale, const Color(0xFF3B82F6), 12 * scale,
        weight: FontWeight.w900);
  }

  void _paintCenterText(Canvas canvas, Offset c, String text, double fontSize,
      Color color, double dy,
      {FontWeight weight = FontWeight.bold}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, color: color, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c + Offset(-tp.width / 2, dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => oldDelegate.hovered != hovered;
}
