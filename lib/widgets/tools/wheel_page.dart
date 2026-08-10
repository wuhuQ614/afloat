/// 暴力转盘页面：一比一复刻参考项目 WheelTab.jsx。
///
/// 关键参数（对齐参考实现）：
/// - 画布逻辑尺寸 320×320，圆心 160，半径 150
/// - 扇区 16 色循环（premiumColors）
/// - 旋转：easeOutCubic，总量 2160°+random(0,360)，时长 4000ms
/// - tick：每转过 360/max(n,8) 度触发一次
/// - 中奖判定：norm=target%360；angle=(360-norm+270)%360；按权重累加
library;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import '../../services/api_service.dart';
import '../../state.dart';
import '../../theme_colors.dart';
import 'tools_audio.dart';
import 'wheel_data.dart';
import 'wheel_models.dart';
import 'wheel_settings.dart';

class WheelTabPage extends StatefulWidget {
  final AppState state;
  const WheelTabPage({super.key, required this.state});

  @override
  State<WheelTabPage> createState() => _WheelTabPageState();
}

class _WheelTabPageState extends State<WheelTabPage>
    with SingleTickerProviderStateMixin {
  List<WheelCollection> _collections = [];
  String _activeId = '';
  bool _loaded = false;

  // 旋转状态
  double _rotation = 0; // 当前角度（度）
  bool _isSpinning = false;
  WheelItem? _result;
  int _resultIndex = -1;
  Timer? _animTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final (cols, active) = await WheelStorage.load();
    if (!mounted) return;
    setState(() {
      _collections = cols;
      _activeId = active;
      _loaded = true;
    });
  }

  WheelCollection? get _current {
    if (_collections.isEmpty) return null;
    return _collections.firstWhere((c) => c.id == _activeId,
        orElse: () => _collections.first);
  }

  Future<void> _save() async {
    await WheelStorage.save(_collections, _activeId);
  }

  // ==================== 旋转 ====================
  double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();

  void _spin() {
    if (_isSpinning) return;
    final items = _current?.items ?? [];
    if (items.isEmpty) return;

    setState(() {
      _isSpinning = true;
      _result = null;
      _resultIndex = -1;
    });
    ToolsAudio.instance.playTick();

    final start = _rotation;
    final target = start + 2160 + math.Random().nextDouble() * 360;
    const duration = 4000;
    final tickStep = 360 / math.max(items.length, 8);
    double lastTickAngle = start;
    final sw = Stopwatch()..start();

    _animTimer?.cancel();
    _animTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = sw.elapsedMilliseconds;
      final progress = math.min(elapsed / duration, 1.0);
      final cur = start + (target - start) * _easeOutCubic(progress);

      // tick 音效 + 振动（对齐参考项目 playWheelTick + vibrate(10)）
      if ((cur - lastTickAngle).abs() >= tickStep) {
        lastTickAngle = cur;
        ToolsAudio.instance.playWheelTick();
        HapticFeedback.selectionClick();
      }

      setState(() => _rotation = cur);

      if (progress >= 1) {
        timer.cancel();
        sw.stop();
        _finishSpin(target, items);
      }
    });
  }

  void _finishSpin(double target, List<WheelItem> items) {
    final norm = target % 360;
    final angle = (360 - norm + 270) % 360;
    final total = items.fold<double>(0, (s, i) => s + (i.weight <= 0 ? 1 : i.weight));
    double acc = 0;
    int found = -1;
    for (var i = 0; i < items.length; i++) {
      final w = items[i].weight <= 0 ? 1.0 : items[i].weight;
      acc += (w / total) * 360;
      if (angle <= acc) {
        found = i;
        break;
      }
    }
    if (found == -1) found = items.length - 1;
    ToolsAudio.instance.playNumberDing(); // 对齐参考项目 playNumberDing
    HapticFeedback.heavyImpact(); // 对齐参考项目 vibrate([50,50,100])
    setState(() {
      _isSpinning = false;
      _result = items[found];
      _resultIndex = found;
    });
  }

  // ==================== UI ====================
  OverlayEntry? _menuEntry;
  bool _provinceExpanded = false;
  final GlobalKey _pillKey = GlobalKey();

  @override
  void dispose() {
    _animTimer?.cancel();
    _menuEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final cur = _current;
    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 40),
                // 转盘
                SizedBox(
                  width: 320,
                  height: 320,
                  child: Stack(alignment: Alignment.center, children: [
                    Transform.rotate(
                      angle: _rotation * math.pi / 180,
                      child: CustomPaint(
                        size: const Size(320, 320),
                        painter: _WheelPainter(
                          items: cur?.items ?? [],
                          resultIndex: _resultIndex,
                          hasResult: _result != null && !_isSpinning,
                          isLight: c.isLight,
                        ),
                      ),
                    ),
                    // 指针（固定朝上）
                    const _Pointer(),
                  ]),
                ),
                const SizedBox(height: 24),
                // 结果
                SizedBox(
                  height: 48,
                  child: (_result != null && !_isSpinning)
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('结果：${_result!.label}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                        )
                      : const SizedBox(),
                ),
                const SizedBox(height: 16),
                // 底部双按钮（对齐参考项目：编辑项目 flex-1 + 暴力转 flex-2）
                SizedBox(
                  width: 320,
                  child: Row(children: [
                    // 编辑项目（flex-1，小字）
                    Expanded(
                      flex: 1,
                      child: GestureDetector(
                        onTap: _isSpinning ? null : _openSettings,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: c.isLight ? Colors.white : const Color(0xFF1F2937),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: c.isLight
                                    ? const Color(0xFFE5E7EB)
                                    : const Color(0xFF374151),
                                width: 2),
                          ),
                          child: const Center(
                            child: Text('编辑项目',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 暴力转（flex-2，大字）
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: _isSpinning ? null : _spin,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: _isSpinning
                                ? const Color(0xFF9CA3AF)
                                : (c.isLight ? Colors.white : const Color(0xFF1F2937)),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: _isSpinning
                                    ? Colors.transparent
                                    : (c.isLight
                                        ? const Color(0xFFE5E7EB)
                                        : const Color(0xFF374151)),
                                width: 2),
                            boxShadow: _isSpinning
                                ? null
                                : [
                                    BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2)),
                                  ],
                          ),
                          child: Center(
                            child: Text(
                              _isSpinning ? '狂转中...' : '暴力转',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: _isSpinning
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : (c.isLight
                                          ? const Color(0xFF374151)
                                          : const Color(0xFFE5E7EB))),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
        // 场景切换胶囊（对齐参考项目：右上角悬浮 rounded-full 胶囊按钮）
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ScenePillButton(
                key: _pillKey,
                sceneName: cur?.name ?? '—',
                isGlass: widget.state.uiStyle == 'glass',
                darkMode: !c.isLight,
                menuOpen: _menuEntry != null,
                onTap: _isSpinning ? null : _toggleMenu,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 场景下拉菜单（对齐参考项目：右上角胶囊 + 悬浮下拉） ====================
  void _toggleMenu() {
    if (_menuEntry != null) {
      _closeMenu();
      return;
    }
    _openMenu();
  }

  void _openMenu() {
    final box = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final c = AppColors.of(context);
    final overlay = Overlay.of(context);

    _menuEntry = OverlayEntry(
      builder: (ctx) {
        return Stack(children: [
          // 透明点击层：点击空白处关闭菜单
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeMenu,
              child: const SizedBox.expand(),
            ),
          ),
          // 菜单本体：右对齐于胶囊按钮下方
          Positioned(
            top: offset.dy + size.height + 8,
            right: MediaQuery.of(ctx).size.width - offset.dx - size.width,
            child: _SceneMenuCard(
              collections: _collections,
              activeId: _activeId,
              isGlass: widget.state.uiStyle == 'glass',
              darkMode: !c.isLight,
              provinceExpanded: _provinceExpanded,
              canDelete: _collections.length > 1,
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
              onToggleProvince: () {
                setState(() => _provinceExpanded = !_provinceExpanded);
                _menuEntry?.markNeedsBuild();
              },
              onSelect: (id) {
                setState(() {
                  _activeId = id;
                  _result = null;
                  _resultIndex = -1;
                });
                _save();
                _closeMenu();
              },
              onDelete: (id) {
                setState(() {
                  _collections.removeWhere((x) => x.id == id);
                  if (_activeId == id && _collections.isNotEmpty) {
                    _activeId = _collections.first.id;
                  }
                });
                _save();
                _menuEntry?.markNeedsBuild();
              },
              onCreateNew: () {
                final newId =
                    DateTime.now().millisecondsSinceEpoch.toString();
                setState(() {
                  _collections.add(WheelCollection(
                    id: newId,
                    name: '新决定',
                    items: [WheelItem(label: '选项', weight: 1)],
                  ));
                  _activeId = newId;
                  _result = null;
                  _resultIndex = -1;
                });
                _save();
                _closeMenu();
                _openSettings();
              },
              onAiCreate: () {
                _closeMenu();
                _openAiCreate();
              },
            ),
          ),
        ]);
      },
    );
    overlay.insert(_menuEntry!);
    _menuEntry!.markNeedsBuild();
  }

  void _closeMenu() {
    final entry = _menuEntry;
    if (entry == null) return;
    _menuEntry = null;
    _provinceExpanded = false;
    entry.remove();
  }

  // AI 智能创建场景（对齐参考项目 aiAdd：提取关键词 / AI 生成两种模式）
  void _openAiCreate() {
    final inputCtrl = TextEditingController();
    var action = 'extract'; // extract | generate
    var loading = false;
    var resultText = '';

    showDialog<void>(
      context: context,
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: Row(children: [
              const Icon(Icons.auto_awesome_outlined, size: 20),
              const SizedBox(width: 8),
              const Text('AI 智能创建', style: TextStyle(fontSize: 16)),
            ]),
            content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // 模式切换
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'extract', label: Text('提取关键词', style: TextStyle(fontSize: 12))),
                    ButtonSegment(
                        value: 'generate', label: Text('AI 生成', style: TextStyle(fontSize: 12))),
                  ],
                  selected: {action},
                  onSelectionChanged: (v) =>
                      setDlg(() => action = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: inputCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: action == 'generate'
                        ? '描述主题和数量，如：西安小吃转盘，50个项目'
                        : '输入内容，如：周末去打篮球还是踢足球',
                    hintStyle: const TextStyle(fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    isCollapsed: false,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE5E7EB), width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFF6366F1), width: 1.5),
                    ),
                  ),
                ),
                if (resultText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(resultText,
                        style: const TextStyle(fontSize: 11), maxLines: 6),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dlgCtx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: (loading || inputCtrl.text.trim().isEmpty)
                    ? null
                    : () async {
                        setDlg(() => loading = true);
                        final created = await _aiCreateCollection(
                          inputCtrl.text.trim(),
                          action,
                        );
                        if (created == null) {
                          setDlg(() {
                            loading = false;
                            resultText = '⚠️ 创建失败：请先在设置中配置 API，或稍后重试';
                          });
                          return;
                        }
                        setState(() {
                          _collections.add(created);
                          _activeId = created.id;
                          _result = null;
                          _resultIndex = -1;
                        });
                        _save();
                        if (dlgCtx.mounted) Navigator.of(dlgCtx).pop();
                      },
                child: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(action == 'generate' ? 'AI 生成场景' : 'AI 提取并创建'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 调用 AI 创建场景（复用项目已有 API 配置）。
  /// 提示词与参考项目一致：第一行为场景标题，其后为逗号分隔的项目名。
  Future<WheelCollection?> _aiCreateCollection(
      String text, String action) async {
    final systemPrompt = action == 'generate'
        ? '你是一个场景项目生成助手。用户会描述一个主题和需要的项目数量，你需要根据主题生成对应数量的具体项目名称。要求：1.项目名称要具体、真实、有代表性。2.根据主题生成一个简短的场景标题（2-4个字）。3.严格按照用户要求的数量生成项目，不多不少。输出格式：第一行为场景标题，第二行开始为生成的项目名称，每个名称用逗号分隔，不要换行。注意：只输出标题和项目名称，不要输出任何解释或多余文字。'
        : '你是一个关键词提取和分类助手。用户会给你一段文字，你需要：1.精准提炼出用户想要的词汇/项目名称。2.根据提取出的词汇类别生成一个简短的场景标题（2-4个字）。输出格式：第一行为场景标题，第二行开始为提取的词汇，每个词汇用逗号分隔。';
    final reply = await ApiService.callAI(
      [
        {'role': 'user', 'content': text}
      ],
      systemPrompt,
      config: widget.state.apiConfig,
      temperature: action == 'generate' ? 0.7 : 0.1,
      maxTokens: action == 'generate' ? 2000 : 500,
    );
    if (reply == null || reply.trim().isEmpty) return null;
    final lines = reply.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final sceneName = lines.length > 1 ? lines[0].trim() : '';
    final itemsText = lines.length > 1 ? lines.sublist(1).join(',') : reply;
    final names = itemsText
        .split(RegExp(r'[,，、\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (names.isEmpty) return null;
    return WheelCollection(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: sceneName.isNotEmpty
          ? sceneName
          : (text.length > 8 ? '${text.substring(0, 8)}...' : text),
      items: names.map((l) => WheelItem(label: l, weight: 1)).toList(),
    );
  }

  void _openSettings() {
    final cur = _current;
    if (cur == null) return;
    Navigator.of(context)
        .push(PageRouteBuilder<dynamic>(
      // 透明路由：消除默认黑色页面底，让设置页以覆盖层形式悬浮在转盘页之上
      opaque: false,
      barrierDismissible: false,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => WheelSettingsPage(
        collection: cur,
        darkMode: !AppColors.of(context).isLight,
        glassMode: widget.state.uiStyle == 'glass',
        canDelete: _collections.length > 1,
      ),
    ))
        .then((result) {
      if (result is Map && result['action'] == 'save') {
        final updated = result['collection'] as WheelCollection;
        setState(() {
          final idx = _collections.indexWhere((x) => x.id == cur.id);
          if (idx >= 0) _collections[idx] = updated;
        });
        _save();
      } else if (result is Map && result['action'] == 'delete') {
        setState(() {
          _collections.removeWhere((x) => x.id == cur.id);
          if (_collections.isNotEmpty) _activeId = _collections.first.id;
        });
        _save();
      }
    });
  }
}

/// 转盘绘制器
class _WheelPainter extends CustomPainter {
  final List<WheelItem> items;
  final int resultIndex;
  final bool hasResult;
  final bool isLight;

  _WheelPainter({
    required this.items,
    required this.resultIndex,
    required this.hasResult,
    required this.isLight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cx = 160.0, cy = 160.0, radius = 150.0;
    if (items.isEmpty) return;
    final total =
        items.fold<double>(0, (s, i) => s + (i.weight <= 0 ? 1 : i.weight));

    double curAngle = -math.pi / 2; // 从 12 点钟开始（参考 Canvas 0° 在 3 点，但整体旋转后由公式补偿；这里从顶部起画）
    for (var i = 0; i < items.length; i++) {
      final w = items[i].weight <= 0 ? 1.0 : items[i].weight;
      final sweep = (w / total) * 2 * math.pi;
      final color = Color(kSectorColors[i % kSectorColors.length]);

      final path = Path()
        ..moveTo(cx, cy)
        ..arcTo(
            Rect.fromCircle(center: const Offset(cx, cy), radius: radius),
            curAngle,
            sweep,
            false)
        ..close();
      canvas.drawPath(path, Paint()..color = color);

      // 非中奖扇区遮罩
      if (hasResult && i != resultIndex) {
        canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.55));
      }
      // 分割线
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = isLight
              ? Colors.white.withValues(alpha: 0.8)
              : Colors.black.withValues(alpha: 0.3),
      );

      // 文字（沿扇区角平分线，靠外）
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(curAngle + sweep / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: items[i].label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: (hasResult && i != resultIndex)
                ? Colors.white.withValues(alpha: 0.3)
                : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: radius - 26);
      // 右对齐：画在 (radius-18) 处
      tp.paint(canvas, Offset(radius - 18 - tp.width, -tp.height / 2));
      canvas.restore();

      curAngle += sweep;
    }

    // 整体遮罩
    if (hasResult) {
      canvas.drawCircle(
        const Offset(cx, cy),
        radius,
        Paint()..color = Colors.black.withValues(alpha: 0.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.items != items ||
      old.resultIndex != resultIndex ||
      old.hasResult != hasResult;
}

/// 水滴指针（固定朝上，位于转盘顶部中心）
class _Pointer extends StatelessWidget {
  const _Pointer();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(60, 60), painter: _PointerPainter());
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 对齐参考 SVG：M30 2 C44 16,46 24,46 30 A16 16 0 0 1 14 30 C14 24,16 16,30 2 Z
    final path = Path();
    path.moveTo(30, 2);
    path.cubicTo(44, 16, 46, 24, 46, 30);
    path.arcTo(const Rect.fromLTWH(14, 14, 32, 32), 0, math.pi, false);
    path.cubicTo(14, 24, 16, 16, 30, 2);
    path.close();
    canvas.drawPath(path, Paint()..color = Colors.white);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFD1D5DB),
    );
    canvas.drawCircle(const Offset(30, 30), 14, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(30, 30),
      8,
      Paint()..color = const Color(0xFFF3F4F6),
    );
  }

  @override
  bool shouldRepaint(covariant _PointerPainter old) => false;
}

/// 场景切换胶囊按钮（对齐参考项目 WheelTab.jsx:283-290）：
/// px-6 py-2.5 rounded-full shadow-lg，红色 ListIcon + "场景：名称" + 下拉箭头
class _ScenePillButton extends StatelessWidget {
  final String sceneName;
  final bool isGlass;
  final bool darkMode;
  final bool menuOpen;
  final VoidCallback? onTap;

  const _ScenePillButton({
    super.key,
    required this.sceneName,
    required this.isGlass,
    required this.darkMode,
    required this.onTap,
    this.menuOpen = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isGlass
        ? const Color(0xFF334155)
        : darkMode
            ? const Color(0xFFE5E7EB)
            : const Color(0xFF374151);
    final Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: isGlass
            ? Colors.white.withValues(alpha: 0.35)
            : darkMode
                ? const Color(0xFF1F2937)
                : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isGlass
              ? Colors.white.withValues(alpha: 0.3)
              : darkMode
                  ? const Color(0xFF374151)
                  : const Color(0xFFF3F4F6),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        // ListIcon（红色）
        CustomPaint(size: const Size(18, 18), painter: _ListIconPainter()),
        const SizedBox(width: 8),
        Text(
          '场景：$sceneName',
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w900, color: textColor),
        ),
        const SizedBox(width: 8),
        AnimatedRotation(
          turns: menuOpen ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(Icons.keyboard_arrow_down, size: 16, color: textColor),
        ),
      ]),
    );

    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// 红色列表图标（对齐参考项目 ListIcon，stroke 红色）
class _ListIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFEF4444);
    // 三横线 + 三个圆点（list 图标）
    canvas.drawLine(const Offset(8, 4), const Offset(17, 4), paint);
    canvas.drawLine(const Offset(8, 9), const Offset(17, 9), paint);
    canvas.drawLine(const Offset(8, 14), const Offset(17, 14), paint);
    canvas.drawCircle(const Offset(3, 4), 1.2, paint);
    canvas.drawCircle(const Offset(3, 9), 1.2, paint);
    canvas.drawCircle(const Offset(3, 14), 1.2, paint);
  }

  @override
  bool shouldRepaint(covariant _ListIconPainter old) => false;
}

/// 场景下拉菜单卡片（对齐参考项目 WheelTab.jsx:292-383）：
/// rounded-2xl shadow-2xl border，自定义场景（可删除）+ 全国大胃袋折叠组 +
/// 底部"创建新场景"（蓝）/"智能创建"（紫）
class _SceneMenuCard extends StatelessWidget {
  final List<WheelCollection> collections;
  final String activeId;
  final bool isGlass;
  final bool darkMode;
  final bool provinceExpanded;
  final bool canDelete;
  final double maxHeight;
  final VoidCallback onToggleProvince;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onDelete;
  final VoidCallback onCreateNew;
  final VoidCallback onAiCreate;

  const _SceneMenuCard({
    required this.collections,
    required this.activeId,
    required this.isGlass,
    required this.darkMode,
    required this.provinceExpanded,
    required this.canDelete,
    required this.maxHeight,
    required this.onToggleProvince,
    required this.onSelect,
    required this.onDelete,
    required this.onCreateNew,
    required this.onAiCreate,
  });

  // 主题色（对齐参考项目：glass slate / dark gray / light gray）
  Color get _textMain => isGlass
      ? const Color(0xFF475569)
      : darkMode
          ? const Color(0xFFD1D5DB)
          : const Color(0xFF4B5563);
  Color get _textSub => isGlass
      ? const Color(0xFF64748B)
      : darkMode
          ? const Color(0xFF9CA3AF)
          : const Color(0xFF6B7280);
  Color get _activeText => const Color(0xFFDC2626);
  Color get _activeBg => isGlass
      ? const Color(0xFFFEE2E2).withValues(alpha: 0.3)
      : darkMode
          ? const Color(0xFF7F1D1D).withValues(alpha: 0.2)
          : const Color(0xFFFEF2F2).withValues(alpha: 0.5);
  Color get _divider => isGlass
      ? Colors.white.withValues(alpha: 0.3)
      : darkMode
          ? const Color(0xFF374151)
          : const Color(0xFFF3F4F6);

  @override
  Widget build(BuildContext context) {
    final provIds = provinceIds();
    final customs = collections.where((c) => !provIds.contains(c.id)).toList();
    final provinces = collections.where((c) => provIds.contains(c.id)).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 260, maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: isGlass
              ? Colors.white.withValues(alpha: 0.95)
              : darkMode
                  ? const Color(0xFF1F2937)
                  : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isGlass
                ? Colors.white.withValues(alpha: 0.3)
                : darkMode
                    ? const Color(0xFF374151)
                    : const Color(0xFFF3F4F6),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 列表区（可滚动）
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 用户自定义场景（可删除）
                  for (final col in customs)
                    _menuItem(
                      label: col.name,
                      active: col.id == activeId,
                      trailing: canDelete && col.id != activeId
                          ? IconButton(
                              icon: Icon(Icons.delete_outline,
                                  size: 14, color: const Color(0xFFD1D5DB)),
                              hoverColor: const Color(0xFFFEE2E2),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                              onPressed: () => onDelete(col.id),
                            )
                          : null,
                      onTap: () => onSelect(col.id),
                    ),
                  // 全国大胃袋折叠组
                  InkWell(
                    onTap: onToggleProvince,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Text('全国大胃袋',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _textSub)),
                        ),
                        AnimatedRotation(
                          turns: provinceExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(Icons.keyboard_arrow_down,
                              size: 14, color: _textSub),
                        ),
                      ]),
                    ),
                  ),
                  if (provinceExpanded) ...[
                    for (final col in provinces)
                      _menuItem(
                        label: col.name,
                        active: col.id == activeId,
                        indent: true,
                        small: true,
                        onTap: () => onSelect(col.id),
                      ),
                  ],
                ],
              ),
            ),
          ),
          // 底部操作区
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _divider)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _menuItem(
                  label: '创建新场景',
                  labelColor: const Color(0xFF2563EB),
                  leading: const Icon(Icons.add,
                      size: 14, color: Color(0xFF2563EB)),
                  onTap: onCreateNew,
                ),
                _menuItem(
                  label: '智能创建',
                  labelColor: const Color(0xFF7C3AED),
                  onTap: onAiCreate,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// 单个菜单项（px-5 py-3 font-bold text-sm，激活态红字红底 + 勾选）
  Widget _menuItem({
    required String label,
    bool active = false,
    bool indent = false,
    bool small = false,
    Color? labelColor,
    Widget? leading,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active ? _activeBg : Colors.transparent,
        padding: EdgeInsets.only(
          left: indent ? 32 : 20,
          right: trailing != null ? 8 : 20,
          top: small ? 10 : 12,
          bottom: small ? 10 : 12,
        ),
        child: Row(children: [
          if (leading != null) ...[leading, const SizedBox(width: 8)],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: small ? 12 : 14,
                fontWeight: FontWeight.bold,
                color: labelColor ??
                    (active ? _activeText : _textMain),
              ),
            ),
          ),
          if (active)
            Icon(Icons.check, size: small ? 12 : 14, color: _activeText),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }
}

