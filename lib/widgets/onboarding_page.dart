/// 首次启动引导向导（Codex / Trae 风格：固定中性底、窄列居中、实底细边卡片、
/// 单主按钮推进、顶部细进度线；弃用毛玻璃/渐变/光斑/大圆角/圆点指示器）
library;

import 'package:flutter/material.dart';
import '../models.dart';
import '../state.dart';
import '../theme_colors.dart';

// ===== 中性色板常量（不带主题色调） =====
const Color _kBgDark = Color(0xFF121316);
const Color _kBgLight = Color(0xFFFAFAFA);
const Color _kCardDark = Color(0xFF1A1C20);
const Color _kCardLight = Color(0xFFFFFFFF);
/// 引导期固定单一低饱和强调色（靛蓝）：选中边框、勾选点、进度线、焦点态、链接
const Color _kAccent = Color(0xFF6B7CFF);
const Color _kBorderDark = Color(0x14FFFFFF); // rgba(255,255,255,0.08)
const Color _kBorderLight = Color(0x14000000); // rgba(0,0,0,0.08)

/// 排版四级灰度（深底/浅底两套）
class _Pal {
  final bool dark;
  const _Pal(this.dark);

  Color get bg => dark ? _kBgDark : _kBgLight;
  Color get card => dark ? _kCardDark : _kCardLight;

  /// 选中卡底色：卡片底色提亮约 4%
  Color get cardSelected => Color.lerp(card, _kAccent, 0.04)!;
  Color get border => dark ? _kBorderDark : _kBorderLight;
  Color get h1 => dark ? const Color(0xFFF5F6F7) : const Color(0xFF1A1D21);
  Color get sub => dark ? const Color(0xFFA0A4AB) : const Color(0xFF6B7280);
  Color get body => dark ? const Color(0xFFE8EAED) : const Color(0xFF1F2328);
  Color get dim => dark ? const Color(0xFF6B7076) : const Color(0xFF9CA3AF);
  // 主按钮：深底近白反转式，浅底深色底白字
  Color get btnBg => dark ? const Color(0xFFF5F6F7) : const Color(0xFF1A1D21);
  Color get btnText => dark ? const Color(0xFF121316) : Colors.white;
}

class OnboardingPage extends StatefulWidget {
  final AppState state;
  const OnboardingPage({super.key, required this.state});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const _totalSteps = 4;
  final PageController _pageCtrl = PageController();
  /// 翻页过渡层的全局 key：滚动时只局部重建这四层，不重建 PageView 本体
  final List<GlobalKey> _pageKeys = List.generate(_totalSteps, (_) => GlobalKey());
  /// 当前连续页位置（仅翻页动画期间更新；未 attach 时禁止读 controller.page，会触发 assert）
  double _pos = 0;
  int _step = 0;

  // 第 2 页 API 表单（预填现有配置）
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: s.apiConfig.url);
    _keyCtrl = TextEditingController(text: s.apiConfig.key);
    _modelCtrl = TextEditingController(text: s.apiConfig.model);
    s.addListener(_onState);
    // 监听翻页位移：PageController 是 ChangeNotifier，滚动/动画期间逐帧通知。
    // 此处必须用 hasClients 守卫：controller 未 attach 到 viewport 前读 .page 会
    // 触发 "cannot be accessed before a PageView is built with it" assert（启动即崩）
    _pageCtrl.addListener(_onPageScroll);
  }

  void _onPageScroll() {
    if (!_pageCtrl.hasClients) return;
    final p = _pageCtrl.page;
    if (p == null || (p - _pos).abs() < 0.001) return;
    _pos = p;
    // 只重建四个过渡层（Opacity/Transform），PageView 本体不动，避免逐帧重建输入框
    for (final k in _pageKeys) {
      (k.currentState as _PageFxState?)?.apply(_pos);
    }
  }

  void _onState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    // 先摘除滚动监听再 dispose，避免销毁竞态中回调访问已释放的 controller
    _pageCtrl.removeListener(_onPageScroll);
    _pageCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  void _goTo(int idx) {
    if (idx < 0 || idx >= _totalSteps) return;
    if (_step == 1) _saveApiIfFilled(); // 离开 API 页（任意方向）均尝试保存
    _pageCtrl.animateToPage(idx, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  /// API 配置保存（三个都填才写入）
  void _saveApiIfFilled() {
    final url = _urlCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    if (url.isNotEmpty && key.isNotEmpty && model.isNotEmpty) {
      s.saveApiConfig(ApiConfig(url: url, key: key, model: model, fullUrl: s.apiConfig.fullUrl));
    }
  }

  void _skipAll() {
    if (_step == 1) _saveApiIfFilled();
    s.completeOnboarding();
  }

  void _showApiKeyHelp(_Pal pal) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: pal.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: pal.border)),
        title: Text('如何获取 API Key?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: pal.h1)),
        content: SizedBox(
          width: 380,
          child: Text(
            '在模型服务商官网的控制台获取 API Key，本应用支持 OpenAI 兼容接口（如 OpenAI、DeepSeek、通义千问、Moonshot、智谱等）。\n\n获取后填入输入框，并配置对应的 API 地址与模型名称即可。',
            style: TextStyle(fontSize: 13, color: pal.sub, height: 1.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = _Pal(s.darkMode); // 深空黑 → 深色向导；其余五套 → 浅色向导
    return Scaffold(
      backgroundColor: pal.bg,
      body: SafeArea(
        child: Column(children: [
          _buildProgress(pal),
          _buildTopBar(pal),
          Expanded(child: _buildPages(pal)),
          _buildBottomBar(pal),
        ]),
      ),
    );
  }

  // ===== 顶部 2px 细进度线（填充 = 当前页/4，200ms 动画）+ 1 / 4 计数 =====
  Widget _buildProgress(_Pal pal) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 16, 48, 0),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 2,
            child: Stack(children: [
              Positioned.fill(child: Container(color: pal.border)),
              Align(
                alignment: Alignment.centerLeft,
                child: AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  widthFactor: (_step + 1) / _totalSteps,
                  child: Container(color: _kAccent),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
        Text('${_step + 1} / $_totalSteps', style: TextStyle(fontSize: 12, color: pal.dim)),
      ]),
    );
  }

  // ===== 右上角“跳过引导”（dim 文字链接，第 4 页不显示） =====
  Widget _buildTopBar(_Pal pal) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 32, top: 8),
        child: _step < _totalSteps - 1
            ? TextButton(
                onPressed: _skipAll,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 32)),
                child: Text('跳过引导', style: TextStyle(fontSize: 12, color: pal.dim)),
              )
            : const SizedBox(height: 32),
      ),
    );
  }

  // ===== 四页 PageView：翻页淡入淡出 + 24px 水平位移 =====
  // PageView 本体只建一次；滚动时通过 listener + 过渡层局部 setState 驱动动效，
  // 不在 build 期间访问 controller.page（未 attach 前读会崩）
  Widget _buildPages(_Pal pal) {
    final pages = [
      _buildStepTheme(pal),
      _buildStepApi(pal),
      _buildStepMode(pal),
      _buildStepWelcome(pal),
    ];
    return PageView(
      controller: _pageCtrl,
      physics: const ClampingScrollPhysics(),
      onPageChanged: (i) {
        if (_step == 1) _saveApiIfFilled();
        setState(() => _step = i);
      },
      children: [
        for (var i = 0; i < _totalSteps; i++) _PageFx(key: _pageKeys[i], index: i, child: pages[i]),
      ],
    );
  }

  /// 单页布局：内容列宽固定 560 居中，左右安全边距 48
  Widget _pageShell(Widget content) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(48, 24, 48, 48),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: content),
      ),
    );
  }

  /// 页标题（26px w600），可选副标题（14px）；间距 12；底部→内容区 32
  Widget _pageHead(_Pal pal, String title, [String? subtitle]) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: pal.h1)),
      if (subtitle != null) ...[
        const SizedBox(height: 12),
        Text(subtitle, style: TextStyle(fontSize: 14, color: pal.sub)),
      ],
      const SizedBox(height: 32),
    ]);
  }

  // ===== 第 1 页：选择外观模式（参考 Trae 引导页风格：带 UI 预览缩略图） =====
  Widget _buildStepTheme(_Pal pal) {
    return _pageShell(_StaggeredFadeIn(children: [
      _pageHead(pal, '选择外观模式'),
      Row(children: [
        Expanded(child: SizedBox(
          height: 220,
          child: _ModeCard(
            title: '白色模式',
            subtitle: 'Light',
            selected: !s.darkMode,
            pal: pal,
            isDark: false,
            onTap: () => s.toggleDarkMode(false),
          ),
        )),
        const SizedBox(width: 16),
        Expanded(child: SizedBox(
          height: 220,
          child: _ModeCard(
            title: '深色模式',
            subtitle: 'Dark',
            selected: s.darkMode,
            pal: pal,
            isDark: true,
            onTap: () => s.toggleDarkMode(true),
          ),
        )),
      ]),
    ]));
  }

  // ===== 第 2 页：设置 API（可跳过） =====
  Widget _buildStepApi(_Pal pal) {
    return _pageShell(_StaggeredFadeIn(children: [
      _pageHead(pal, '设置 API', '连接 AI 服务，获取更智能的学习体验。此步骤可跳过。'),
      // API Key
      _fieldLabel(pal, 'API Key'),
      _input(pal, _keyCtrl, 'sk-...'),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: () => _showApiKeyHelp(pal),
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
          child: const Text('如何获取 API Key?', style: TextStyle(fontSize: 12, color: _kAccent)),
        ),
      ),
      const SizedBox(height: 14),
      // API 地址
      _fieldLabel(pal, 'API 地址'),
      _input(pal, _urlCtrl, 'https://api.openai.com/v1'),
      const SizedBox(height: 6),
      // 完整 URL 开关
      Row(children: [
        SizedBox(
          height: 20,
          child: Checkbox(
            value: s.apiConfig.fullUrl,
            onChanged: (v) {
              s.saveApiConfig(ApiConfig(
                url: s.apiConfig.url,
                key: s.apiConfig.key,
                model: s.apiConfig.model,
                temperature: s.apiConfig.temperature,
                vision: s.apiConfig.vision,
                fullUrl: v ?? false,
              ));
            },
            side: BorderSide(color: pal.border, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 6),
        Text('完整 URL', style: TextStyle(fontSize: 12, color: pal.body)),
        const SizedBox(width: 6),
        Expanded(child: Text('关闭时自动在地址后添加 /chat/completions', style: TextStyle(fontSize: 11, color: pal.dim))),
      ]),
      const SizedBox(height: 14),
      // 模型
      _fieldLabel(pal, '模型'),
      _input(pal, _modelCtrl, 'gpt-4o'),
      const SizedBox(height: 24),
      Row(children: [
        TextButton(
          onPressed: () {
            // 与“下一步”保存行为一致：已填完整的配置不因跳过而丢失
            _saveApiIfFilled();
            _goTo(2);
          },
          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
          child: Text('跳过此步骤', style: TextStyle(fontSize: 12, color: pal.dim)),
        ),
        const Spacer(),
        Text('你可以在设置中随时修改', style: TextStyle(fontSize: 12, color: pal.dim)),
      ]),
    ]));
  }

  /// 字段标签（12px，dim 色，输入框上方 6px）
  Widget _fieldLabel(_Pal pal, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: TextStyle(fontSize: 12, color: pal.dim)),
    );
  }

  /// 单行输入框：高 40、圆角 8、同卡片边框，聚焦变强调色
  Widget _input(_Pal pal, TextEditingController ctrl, String hint) {
    return SizedBox(
      height: 40,
      child: TextField(
        controller: ctrl,
        style: TextStyle(fontSize: 13, color: pal.body),
        decoration: InputDecoration(
          filled: true,
          fillColor: pal.card,
          isCollapsed: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          hintText: hint,
          hintStyle: TextStyle(fontSize: 13, color: pal.dim),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: pal.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: pal.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _kAccent, width: 1.2)),
        ),
      ),
    );
  }

  // ===== 第 3 页：选择词汇剖析强度（三张结构相同的选项卡） =====
  Widget _buildStepMode(_Pal pal) {
    return _pageShell(_StaggeredFadeIn(children: [
      _pageHead(pal, '选择词汇剖析强度', 'AI 将根据你的选择提供不同深度的解析，之后可随时更换。'),
      _OptionCard(
        title: '快速模式',
        desc: '简要释义，核心词义速记',
        selected: s.analysisMode == 'fast',
        pal: pal,
        onTap: () => s.setAnalysisMode('fast'),
      ),
      const SizedBox(height: 12),
      _OptionCard(
        title: '正常模式',
        desc: '详细释义，常用例句与搭配',
        subtitle: '需配置 API 才可正常使用',
        selected: s.analysisMode == 'normal',
        pal: pal,
        onTap: () => s.setAnalysisMode('normal'),
      ),
      const SizedBox(height: 12),
      _OptionCard(
        title: '深度模式',
        desc: '全面剖析，词源、用法与文化背景',
        subtitle: '需配置 API 才可正常使用',
        selected: s.analysisMode == 'deep',
        pal: pal,
        onTap: () => s.setAnalysisMode('deep'),
      ),
    ]));
  }

  // ===== 第 4 页：欢迎语 =====
  Widget _buildStepWelcome(_Pal pal) {
    return _pageShell(_StaggeredFadeIn(children: [
      const SizedBox(height: 56),
      Text('欢迎使用', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: pal.h1, letterSpacing: 2)),
      const SizedBox(height: 16),
      Text(
        s.apiConfig.ready ? '一切就绪，开始你的词汇学习之旅。' : '初始配置已完成，AI 接口可稍后在设置中补充。',
        style: TextStyle(fontSize: 14, color: pal.sub),
      ),
    ]));
  }

  // ===== 底部：单主按钮（第 2/3 页附"上一步"文字链接） =====
  Widget _buildBottomBar(_Pal pal) {
    final isLast = _step == _totalSteps - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 0, 48, 28),
      child: Row(children: [
        // 上一步：纯文字 + 箭头，无边框无底色，第 1/4 页不显示
        if (_step > 0 && !isLast)
          TextButton.icon(
            onPressed: () => _goTo(_step - 1),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 40)),
            icon: Icon(Icons.arrow_back_rounded, size: 15, color: pal.sub),
            label: Text('上一步', style: TextStyle(fontSize: 14, color: pal.sub)),
          ),
        const Spacer(),
        SizedBox(
          height: 40,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: pal.btnBg,
              foregroundColor: pal.btnText,
              elevation: 0,
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            onPressed: isLast ? () => s.completeOnboarding() : () => _goTo(_step + 1),
            child: Text(isLast ? '开始使用' : '下一步'),
          ),
        ),
      ]),
    );
  }
}

// ===== 翻页过渡层：淡入淡出 + 24px 水平位移（由滚动监听驱动局部 setState） =====
class _PageFx extends StatefulWidget {
  final int index;
  final Widget child;
  const _PageFx({super.key, required this.index, required this.child});

  @override
  State<_PageFx> createState() => _PageFxState();
}

class _PageFxState extends State<_PageFx> {
  double _pos = 0;

  /// 由父级滚动监听调用：pos 为 PageView 当前连续页位置
  void apply(double pos) {
    if (!mounted || (pos - _pos).abs() < 0.001) return;
    setState(() => _pos = pos);
  }

  @override
  Widget build(BuildContext context) {
    final delta = (_pos - widget.index).clamp(-1.0, 1.0);
    final opacity = (1 - delta.abs()).clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: opacity < 0.6,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(offset: Offset(-24 * delta, 0), child: widget.child),
      ),
    );
  }
}

// ===== 外观模式卡（参考 Trae 引导页：带迷你 UI 预览缩略图） =====
class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final _Pal pal;
  final bool isDark;
  final VoidCallback onTap;
  const _ModeCard({required this.title, required this.subtitle, required this.selected, required this.pal, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF0F0F5);
    final sidebarBg = isDark ? const Color(0xFF252538) : const Color(0xFFE8E8F0);
    final lineColor = isDark ? const Color(0xFF3A3A55) : const Color(0xFFD8D8E2);
    final textColor = isDark ? const Color(0xFFC8C8D8) : const Color(0xFF4A4A5A);
    final accentColor = isDark ? const Color(0xFF7B7BFF) : const Color(0xFF6B6BFF);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: selected ? pal.cardSelected : pal.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _kAccent : pal.border, width: selected ? 2 : 1),
        ),
        child: Column(children: [
          // 迷你 UI 预览缩略图
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              child: Container(
                color: cardBg,
                padding: const EdgeInsets.all(8),
                child: Column(children: [
                  // 顶部标题栏
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: sidebarBg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(children: [
                      Container(width: 5, height: 5, decoration: BoxDecoration(color: const Color(0xFFFF5F57), shape: BoxShape.circle)),
                      const SizedBox(width: 3),
                      Container(width: 5, height: 5, decoration: BoxDecoration(color: const Color(0xFFFFBD2E), shape: BoxShape.circle)),
                      const SizedBox(width: 3),
                      Container(width: 5, height: 5, decoration: BoxDecoration(color: const Color(0xFF28C840), shape: BoxShape.circle)),
                      const Spacer(),
                      Container(width: 24, height: 6, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(2))),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Row(children: [
                      // 左侧导航栏
                      Container(
                        width: 28,
                        decoration: BoxDecoration(
                          color: sidebarBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: Column(children: [
                          for (var i = 0; i < 5; i++) ...[
                            Container(
                              height: 4,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: i == 0 ? accentColor : lineColor,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 5),
                          ],
                        ]),
                      ),
                      const SizedBox(width: 6),
                      // 右侧内容区
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(height: 6, width: 40, decoration: BoxDecoration(color: textColor.withOpacity(0.6), borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 5),
                            Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 3),
                            Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 3),
                            Container(height: 4, width: 80, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 6),
                            Container(height: 4, width: double.infinity, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(2))),
                            const SizedBox(height: 3),
                            Container(height: 4, width: 60, decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(2))),
                          ]),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          // 底部标签
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? pal.cardSelected : pal.card,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
            ),
            child: Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: pal.body)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 11, color: pal.dim)),
              ]),
              const Spacer(),
              if (selected)
                Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _kAccent),
                  child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ===== 选项卡（第 3 页：标题 + 一行 dim 说明，形态与主题卡一致） =====
class _OptionCard extends StatelessWidget {
  final String title;
  final String desc;
  final String? subtitle;
  final bool selected;
  final _Pal pal;
  final VoidCallback onTap;
  const _OptionCard({required this.title, required this.desc, this.subtitle, required this.selected, required this.pal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? pal.cardSelected : pal.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _kAccent : pal.border, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: pal.body)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(fontSize: 12, color: pal.dim)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(subtitle!, style: TextStyle(fontSize: 10.5, color: pal.dim.withValues(alpha: 0.6))),
                ),
            ]),
          ),
          if (selected)
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: _kAccent),
              child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
            ),
        ]),
      ),
    );
  }
}

/// 交错渐显动画：子元素依次从下方滑入并淡出
/// - 节奏：基础 350ms + 每子元素 60ms（比 150+80n 更慢更柔和）
/// - 曲线：easeOut（减速更平缓，避免 easeOutCubic 的急停感）
/// - 位移：10px（比 20px 更细腻，避免大跨度生硬感）
/// - 隔离：每个子元素包 RepaintBoundary，防止动画期间重绘扩散到兄弟节点
class _StaggeredFadeIn extends StatefulWidget {
  final List<Widget> children;
  const _StaggeredFadeIn({required this.children});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    final count = widget.children.length;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 350 + count * 60),
    );

    // 交错步长 5%、单元素跨度 45%：相邻元素衔接更连续，避免“一个一个蹦”的割裂感
    const staggerStep = 0.05;
    const animSpan = 0.45;
    _animations = List.generate(count, (i) {
      final start = (i * staggerStep).clamp(0.0, 0.9);
      final end = (start + animSpan).clamp(start + 0.1, 1.0);
      return CurvedAnimation(
        parent: _controller,
        curve: Interval(start, end, curve: Curves.easeOut),
      );
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(widget.children.length, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (context, child) {
            final t = _animations[i].value;
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 10),
                child: child,
              ),
            );
          },
          // RepaintBoundary：动画期间每帧重绘只局限在当前子元素，
          // 不扩散到兄弟节点（如其他选项卡），显著降低第3页（多卡片）重绘开销
          child: RepaintBoundary(child: widget.children[i]),
        );
      }),
    );
  }
}
