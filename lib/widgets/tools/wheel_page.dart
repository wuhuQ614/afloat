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
import 'dart:ui' as ui;
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

  // 旋转动画控制器（由 Flutter 渲染管线驱动，不触发全页重建）
  late final AnimationController _spinCtrl;
  double _rotation = 0; // 当前角度（度）
  double _spinStart = 0; // 本次旋转起始角度
  double _spinTarget = 0; // 本次旋转目标角度
  bool _isSpinning = false;
  WheelItem? _result;
  int _resultIndex = -1;

  // ==================== Image 预渲染缓存 ====================
  // 关键：转盘绘制为 ui.Image（GPU 纹理），旋转时每帧只做 drawImage（1 次 GPU 纹理复制），
  // 而非 drawPicture（回放 128 个绘制命令）。这是参考项目 CSS transform 的等价方案。
  ui.Picture? _wheelPicture; // 过渡用：toImage 完成前用 drawPicture 显示
  ui.Image? _wheelImage;     // 最终目标：GPU 纹理，旋转期间用它
  int _imageVersion = 0;     // 版本号：防止异步 toImage 竞态
  List<WheelItem>? _picItems;
  int _picResultIndex = -999;
  bool _picHasResult = false;
  bool _picIsLight = true;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    // 持久注册：避免每次 _spin 累积 listener
    _spinCtrl.addListener(_onSpinTick);
    _spinCtrl.addStatusListener(_onSpinStatus);
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

  /// 参考项目不做截断，直接使用全部 items
  List<WheelItem> get _displayItems {
    return _current?.items ?? const [];
  }

  Future<void> _save() async {
    await WheelStorage.save(_collections, _activeId);
  }

  // ==================== 旋转 ====================
  double _easeOutCubic(double t) => 1 - math.pow(1 - t, 3).toDouble();

  // tick 相关状态（持久 listener，不在 _spin 中重复添加）
  double _lastTickAngle = 0;
  double _tickStep = 45;
  // 节流：最小 60ms 间隔，避免高速旋转时平台通道风暴
  int _lastTickMs = 0;

  void _spin() {
    if (_isSpinning) return;
    final items = _displayItems;
    if (items.isEmpty) return;

    setState(() {
      _isSpinning = true;
      _result = null;
      _resultIndex = -1;
    });
    ToolsAudio.instance.playTick();

    _spinStart = _rotation;
    _spinTarget = _spinStart + 2160 + math.Random().nextDouble() * 360;
    _tickStep = 360 / math.max(items.length, 8);
    _lastTickAngle = _spinStart;
    _lastTickMs = DateTime.now().millisecondsSinceEpoch;

    _spinCtrl.forward(from: 0);
  }

  // 在 initState 中一次性注册，避免每次 _spin 都累积 listener
  void _onSpinTick() {
    final cur = _spinStart + (_spinTarget - _spinStart) * _easeOutCubic(_spinCtrl.value);
    if ((cur - _lastTickAngle).abs() >= _tickStep) {
      _lastTickAngle = cur;
      // 节流：高速旋转时跳过部分 tick 音效，避免平台通道风暴（每秒最多 ~16 次）
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastTickMs >= 60) {
        _lastTickMs = now;
        ToolsAudio.instance.playWheelTick();
        HapticFeedback.selectionClick();
      }
    }
  }

  void _onSpinStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _finishSpin(_spinTarget, _displayItems);
    }
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
    // 更新 _rotation 为最终角度，避免旋转结束后回弹
    _rotation = target;
    ToolsAudio.instance.playNumberDing();
    HapticFeedback.heavyImpact();
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
    _spinCtrl.removeListener(_onSpinTick);
    _spinCtrl.removeStatusListener(_onSpinStatus);
    _spinCtrl.dispose();
    _menuEntry?.remove();
    _wheelPicture?.dispose();
    _wheelImage?.dispose();
    super.dispose();
  }

  /// 重建转盘缓存：生成 ui.Picture（同步，立即显示）+ ui.Image（异步，GPU 纹理）
  /// [dpr] 设备像素比：按实际 DPR 光栅化纹理，避免高分屏放大模糊
  void _rebuildWheelPicture(
      List<WheelItem> items, int resultIndex, bool hasResult, bool isLight, double dpr) {
    if (items.isEmpty) {
      _wheelPicture?.dispose();
      _wheelPicture = null;
      _wheelImage?.dispose();
      _wheelImage = null;
      _picItems = items;
      _picResultIndex = resultIndex;
      _picHasResult = hasResult;
      _picIsLight = isLight;
      return;
    }
    // 内容完全一致则复用
    if (_wheelPicture != null &&
        _picResultIndex == resultIndex &&
        _picHasResult == hasResult &&
        _picIsLight == isLight &&
        _sameWheelItems(_picItems, items)) {
      return;
    }
    // 1. 同步生成 Picture（立即可用于显示）
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 320, 320));
    _drawWheel(canvas, const Size(320, 320), items, resultIndex, hasResult, isLight);
    final pic = recorder.endRecording();
    _wheelPicture?.dispose();
    _wheelPicture = pic;
    _picItems = items;
    _picResultIndex = resultIndex;
    _picHasResult = hasResult;
    _picIsLight = isLight;

    // 2. 异步转换为 Image（GPU 纹理，按设备像素比光栅化，解决高分屏模糊）
    _imageVersion++;
    final version = _imageVersion;
    final px = (320 * dpr).round().clamp(320, 960);
    pic.toImage(px, px).then((image) {
      if (version != _imageVersion || !mounted) {
        image.dispose();
        return;
      }
      _wheelImage?.dispose();
      _wheelImage = image;
      // 不调 setState：旋转期间不需要重建，下次 build 自然会用 Image
      // 非旋转状态需要刷新一次以切换到 Image 渲染
      if (!_isSpinning) setState(() {});
    });
  }

  /// 按内容比较两个 WheelItem 列表：长度相同且每项 label+weight 一致
  bool _sameWheelItems(List<WheelItem>? a, List<WheelItem>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label || a[i].weight != b[i].weight) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final cur = _current;
    final displayItems = _displayItems;
    final hasResult = _result != null && !_isSpinning;
    // 重建转盘缓存（旋转动画不会触发），按设备像素比光栅化避免模糊
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _rebuildWheelPicture(displayItems, _resultIndex, hasResult, c.isLight, dpr);
    // 改用 Column 布局，避免 Stack+Center+Positioned 导致的视觉偏移
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 顶部场景胶囊
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ScenePillButton(
                key: _pillKey,
                sceneName: cur?.name ?? '—',
                isGlass: widget.state.isGlassUI,
                darkMode: !c.isLight,
                menuOpen: _menuEntry != null,
                onTap: _isSpinning ? null : _toggleMenu,
              ),
            ],
          ),
        ),
        // 中间内容区（垂直居中）
        Expanded(
          child: Align(
            alignment: Alignment.center,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 转盘
                  // 性能优化：RepaintBoundary + SizedBox + Stack + _Pointer 都在
                  // AnimatedBuilder 外面，动画期间不重建。
                  // 旋转的转盘优先用 ui.Image（RawImage，GPU 纹理，1 次 drawImage）
                  // 其次用 ui.Picture（CustomPaint，回放绘制命令）
                  RepaintBoundary(
                    child: SizedBox(
                      width: 320,
                      height: 320,
                      child: Stack(alignment: Alignment.center, children: [
                        // 画布背景圆（对齐参考项目 canvas backgroundColor）
                        Container(
                          width: 320,
                          height: 320,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.isLight
                                ? const Color(0xFFF3F4F6)
                                : const Color(0xFF4B5563),
                          ),
                        ),
                        // 旋转的转盘（AnimatedBuilder 只重建 Transform.rotate）
                        if (_wheelImage != null)
                          AnimatedBuilder(
                            animation: _spinCtrl,
                            child: RawImage(
                              image: _wheelImage,
                              width: 320,
                              height: 320,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.medium,
                            ),
                            builder: (context, child) {
                              final curRotation = _isSpinning
                                  ? _spinStart + (_spinTarget - _spinStart) * _easeOutCubic(_spinCtrl.value)
                                  : _rotation;
                              return Transform.rotate(
                                angle: curRotation * math.pi / 180,
                                child: child,
                              );
                            },
                          )
                        else if (_wheelPicture != null)
                          AnimatedBuilder(
                            animation: _spinCtrl,
                            child: CustomPaint(
                              size: const Size(320, 320),
                              painter: _WheelPicturePainter(_wheelPicture!),
                            ),
                            builder: (context, child) {
                              final curRotation = _isSpinning
                                  ? _spinStart + (_spinTarget - _spinStart) * _easeOutCubic(_spinCtrl.value)
                                  : _rotation;
                              return Transform.rotate(
                                angle: curRotation * math.pi / 180,
                                child: child,
                              );
                            },
                          ),
                        // 指针（固定不动，不参与动画重建）
                        const _Pointer(),
                      ]),
                    ),
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
              isGlass: widget.state.isGlassUI,
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
        glassMode: widget.state.isGlassUI,
        canDelete: _collections.length > 1,
        highPerformance: widget.state.highPerformanceMode,
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

/// 转盘绘制核心：仅被 _rebuildWheelPicture 走 Picture 预渲染时调用
/// 完全复刻参考项目 WheelTab.jsx:169-228 的 Canvas 绘制逻辑
void _drawWheel(Canvas canvas, Size size, List<WheelItem> items,
    int resultIndex, bool hasResult, bool isLight) {
  const double cx = 160.0;
  const double cy = 160.0;
  const double radius = 150.0;
  if (items.isEmpty) return;
  final total =
      items.fold<double>(0, (s, i) => s + (i.weight <= 0 ? 1 : i.weight));

  // 画布尺寸与 320 不一致时（兜底），按比例缩放
  if (size.width != 320 || size.height != 320) {
    final scaleX = size.width / 320;
    final scaleY = size.height / 320;
    canvas.save();
    canvas.scale(scaleX, scaleY);
    _drawWheelCore(canvas, items, resultIndex, hasResult, isLight, total, cx, cy, radius);
    canvas.restore();
    return;
  }
  _drawWheelCore(canvas, items, resultIndex, hasResult, isLight, total, cx, cy, radius);
}

/// 复刻参考项目 Canvas 绘制（WheelTab.jsx:189-228）
void _drawWheelCore(
  Canvas canvas,
  List<WheelItem> items,
  int resultIndex,
  bool hasResult,
  bool isLight,
  double total,
  double cx,
  double cy,
  double radius,
) {
  // 参考项目：curAngle = 0（从 3 点钟方向开始）
  double curAngle = 0;
  for (var i = 0; i < items.length; i++) {
    final w = items[i].weight <= 0 ? 1.0 : items[i].weight;
    final sweep = (w / total) * 2 * math.pi;
    final color = Color(kSectorColors[i % kSectorColors.length]);

    final path = Path()
      ..moveTo(cx, cy)
      ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
          curAngle,
          sweep,
          false)
      ..close();
    // 填充扇区
    canvas.drawPath(path, Paint()..color = color);

    // 非中奖扇区柔化（轻量遮罩，保留扇区底色可辨，避免整盘发黑）
    if (hasResult && i != resultIndex) {
      canvas.drawPath(
          path, Paint()..color = Colors.black.withValues(alpha: 0.30));
    }

    // 分割线：固定 1.5 宽度
    // 参考项目：darkMode ? 'rgba(0,0,0,0.3)' : 'rgba(255,255,255,0.8)'
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = isLight
            ? Colors.white.withValues(alpha: 0.8)
            : Colors.black.withValues(alpha: 0.3),
    );

    // 文字：始终绘制，bold 11px，沿扇区角平分线靠外
    // 参考项目：textAlign='right', fillText(item.label, radius - 18, 4)
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(curAngle + sweep / 2);
    // 非中奖扇区文字适当降透明度（比旧版提亮，保持可读）
    final textAlpha = (hasResult && i != resultIndex) ? 0.55 : 1.0;
    final tp = TextPainter(
      text: TextSpan(
        text: items[i].label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isLight
              ? Colors.white.withValues(alpha: textAlpha)
              : Colors.white.withValues(alpha: textAlpha * 0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // 对齐参考项目：textAlign='right'，绘制在 radius-18 处
    tp.paint(canvas, Offset(radius - 18 - tp.width, -tp.height / 2 + 2));
    canvas.restore();

    curAngle += sweep;
  }

  // 不再叠加整体黑色遮罩：旧版 0.2 全盘压暗是"黑"的主因之一，
  // 仅靠非中奖扇区柔化即可形成中奖扇区高亮对比。
}

/// 预渲染图片绘制器：只画一张缓存好的 [ui.Picture]，旋转动画不再触发任何绘制
class _WheelPicturePainter extends CustomPainter {
  final ui.Picture picture;
  const _WheelPicturePainter(this.picture);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // 居中绘制：Picture 录制时基于 320×320 坐标
    final double scaleX = size.width / 320;
    final double scaleY = size.height / 320;
    if (scaleX != 1.0 || scaleY != 1.0) {
      canvas.scale(scaleX, scaleY);
    }
    canvas.drawPicture(picture);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WheelPicturePainter old) => !identical(old.picture, picture);
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

