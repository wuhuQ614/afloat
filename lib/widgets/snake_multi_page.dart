/// 贪吃蛇【多人模式】——全屏沉浸式竞技场
/// 纯 Dart + dart:io 实现（不依赖 C++/FFI），仅桌面端（Windows）展示。
///
/// 【玩法】
///  - 2~6 名玩家同场竞技，抢食成长，撞墙/撞己/撞他即死。
///  - 活到最后一条蛇获胜；全场只剩 1 条蛇游戏结束。
///  - 玩家数量与 P1~P6 名是否“真人”可自定义；真人最多 3 名，其余强制为人机。
///  - 每死一条蛇：5 秒后存活的蛇速度在基础速度上 +15%（可叠加），
///    倒计时显示在棋盘空白处。
///  - 开局蛇群按圆周均匀铺满，保证彼此不会挨得太近。
///
/// 【模式】
///  - 本地：1~3 名真人用键盘（P1=WASD，P2=方向键，P3=U/J/H/K），其余人机。
///  - 联机：创建房间(Host) 用 TCP 快照同步；加入房间(Client) 渲染远程画面。
///
/// 【Hybrid 键盘方案】
///  P1: W上 / A左 / S下 / D右
///  P2: ↑ / ← / ↓ / →
///  P3: U上 / H左 / J下 / K右
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../state.dart' show AppScope;
import '../theme_colors.dart' show AppColors, kDarkBg, kDarkBorder, kDarkCard;

// ============================ 皮肤与配色 ============================

/// 蛇的外貌样式（绘制变体）
enum _Skin { classic, striped, dotted, gradient, glow, duo }

const List<String> _skinLabels = ['经典', '条纹', '圆点', '渐变', '发光', '双色'];

/// 可选主色板（蛇身主线色 + 头部/点缀亮色）
class _Palette {
  final String name;
  final Color body;
  final Color accent;
  const _Palette(this.name, this.body, this.accent);
}

const List<_Palette> _palettes = [
  _Palette('翠玉', Color(0xFF27AE60), Color(0xFF2ECC71)),
  _Palette('炽焰', Color(0xFFE67E22), Color(0xFFF39C12)),
  _Palette('蓝晶', Color(0xFF2980B9), Color(0xFF5DADE2)),
  _Palette('紫电', Color(0xFF8E44AD), Color(0xFFB465F0)),
  _Palette('曜金', Color(0xFFD4AC0D), Color(0xFFF9CA24)),
  _Palette('玫粉', Color(0xFFE84393), Color(0xFFFD79A8)),
];

// ============================ 配置数据模型 ============================

/// 单个玩家槽位配置
class _SlotCfg {
  int skin = 0;
  int color = 0;
  bool human = false; // 真人（可键盘操作）
  bool remote = false; // 联机：该真人槽位等待远端的玩家加入控制
}

/// 一局游戏的配置
class _GameConfig {
  final int count; // 玩家数 2..6
  final int cols;
  final int rows;
  final double baseTickMs;
  final List<_SlotCfg> slots; // length == count
  _GameConfig({
    required this.count,
    required this.cols,
    required this.rows,
    required this.baseTickMs,
    required this.slots,
  });

  /// 3/4/5/6 人的地图按 2 人对战的指定倍数放大（边长 = 40 × 倍数）
  static double _mapMult(int count) => switch (count) {
        2 => 1.0,
        3 => 1.5,
        4 => 2.65,
        _ => 3.37,
      };

  /// 原正方形边长（仅用于面积/倍率计算）
  static int mapSide(int count) => (40 * _mapMult(count)).round();

  /// 地图尺寸（矩形）：面积 ≈ 2 人模式的指定倍数面积，
  /// 长宽比 ≈ 16:9（匹配宽窗口），格子仍保持正方形（cols≠rows 只是列数更多）。
  /// 返回 (cols, rows)。
  static (int, int) mapRect(int count) {
    final side = mapSide(count);
    // 保持与原正方形相同的总面积
    final area = side * side;
    const ratio = 16.0 / 9.0;
    // cols/rows = ratio, cols*rows = area  →  cols = sqrt(area*ratio), rows = area/cols
    final cols = (math.sqrt(area * ratio)).ceil();
    final rows = (area / cols).ceil();
    return (cols, rows);
  }

  static double baseTick(int count) => count >= 5 ? 120.0 : 110.0;
}

// ============================ 单条蛇运行时状态 ============================

class _SnakeM {
  final List<int> xs = <int>[];
  final List<int> ys = <int>[];
  final List<int> prevXs = <int>[];
  final List<int> prevYs = <int>[];
  int dx = 1;
  int dy = 0;
  final List<(int, int)> pending = <(int, int)>[];
  int score = 0;
  bool alive = true;
  int deathTick = 0;
  int get len => xs.length;
}

// ============================ 联机会话（TCP） ============================

enum _Mode { idle, local, host, client }

/// 一个联机消息（行分隔 JSON）
class _Net {
  /// 创建房间：返回已绑定的 ServerSocket
  static Future<ServerSocket> bind(int port) =>
      ServerSocket.bind(InternetAddress.anyIPv4, port);

  static void send(Socket s, Map<String, dynamic> obj) {
    try {
      s.add(utf8.encode(jsonEncode(obj) + '\n'));
    } catch (_) {}
  }

  static void sendRaw(Socket s, String line) {
    try {
      s.add(utf8.encode(line));
    } catch (_) {}
  }

  /// 从一个 socket 读取完整一行（以换行符分隔）
  static Future<Map<String, dynamic>?> readLine(Socket s) async {
    final sb = StringBuffer();
    await for (final buf in s) {
      final str = utf8.decode(buf, allowMalformed: true);
      for (var i = 0; i < str.length; i++) {
        final ch = str[i];
        if (ch == '\n') {
          if (sb.isNotEmpty) {
            try {
              return jsonDecode(sb.toString()) as Map<String, dynamic>;
            } catch (_) {
              sb.clear();
            }
          }
        } else {
          sb.write(ch);
        }
      }
    }
    return null;
  }
}

// ============================ 入口：多人模式页面（大厅） ============================

class SnakeMultiPage extends StatefulWidget {
  const SnakeMultiPage({super.key});
  @override
  State<SnakeMultiPage> createState() => _SnakeMultiPageState();
}

class _SnakeMultiPageState extends State<SnakeMultiPage> {
  int _count = 4;
  final List<_SlotCfg> _slots = List.generate(6, (_) => _SlotCfg());

  void _resetSlots(int n) {
    // 真人最多 3：保底让 n 中人机有剩余，这里不强制，交给 UI 限制
    for (var i = 0; i < n; i++) {
      _slots[i].skin = i;
      _slots[i].color = i % _palettes.length;
    }
  }

  int get _humanCount {
    var c = 0;
    for (var i = 0; i < _count; i++) {
      if (_slots[i].human) c++;
    }
    return c;
  }

  @override
  void initState() {
    super.initState();
    _resetSlots(_count);
  }

  void _startLocal() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _GameScreen(_buildConfig(true), mode: _Mode.local),
    ));
  }

  Future<void> _hostRoom() async {
    final cfg = _buildConfig(false);
    final anyRemote = cfg.slots.any((s) => s.remote);
    ServerSocket server;
    try {
      server = await _Net.bind(43210);
    } catch (e) {
      _toast('创建房间失败：${e.toString().split('\n').first}');
      return;
    }
    if (!mounted) {
      server.close();
      return;
    }
    final nav = Navigator.of(context);
    final dialogRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _StartingRoomDialog(slots: cfg.slots),
    );
    nav.push(dialogRoute);
    if (!mounted) return;
    nav
        .push(MaterialPageRoute(
          builder: (_) =>
              _GameScreen(cfg, mode: _Mode.host, server: server),
        ))
        .then((_) {
      server.close();
    });
    // 游戏页已压栈：移除其下方的启动提示框，
    // 避免对局结束返回大厅时提示框还在、需要二次关闭。
    nav.removeRoute(dialogRoute);
  }

  Future<void> _joinRoom() async {
    final res = await showDialog<_JoinInfo>(
      context: context,
      builder: (ctx) => const _JoinDialog(),
    );
    if (res == null || !mounted) return;
    Socket? sock;
    try {
      sock = await Socket.connect(res.host, res.port,
          timeout: const Duration(seconds: 6));
    } catch (e) {
      _toast('连接失败：${e.toString().split('\n').first}');
      return;
    }
    if (sock == null) return;
    // 向主机发起加入请求，等待握手配置
    _Net.send(sock, {'t': 'join'});
    final cfgMsg = await _Net.readLine(sock);
    if (!mounted || cfgMsg == null) {
      try {
        sock.close();
      } catch (_) {}
      _toast('未收到房间配置，可能已关闭');
      return;
    }
    final cfg = _cfgFromRemote(cfgMsg);
    if (cfg == null) {
      try {
        sock.close();
      } catch (_) {}
      _toast('房间配置无效');
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          _GameScreen(cfg, mode: _Mode.client, socket: sock),
    ));
  }

  void _toast(String msg) {
    if (!mounted) return;
    final b = ScaffoldMessenger.of(context);
    b.showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
    ));
  }

  _GameConfig _buildConfig(bool localOnly) {
    final (cols, rows) = _GameConfig.mapRect(_count);
    final slots = <_SlotCfg>[];
    for (var i = 0; i < _count; i++) {
      final s = _SlotCfg()
        ..skin = _slots[i].skin
        ..color = _slots[i].color
        ..human = _slots[i].human;
      // 联机模式下，若为真人槽位：前 3 个人类中本机可占最多 3 个，
      // 多出的“真人”槽位视为等待远端加入
      if (!localOnly && s.human) {
        // 本机局域网托管模式下，把真人槽位标记为远程待加入（简单可靠）
        s.remote = true;
        s.human = false;
      }
      slots.add(s);
    }
    return _GameConfig(
      count: _count,
      cols: cols,
      rows: rows,
      baseTickMs: _GameConfig.baseTick(_count),
      slots: slots,
    );
  }

  // 由远程握手消息构建客户端配置（cols/rows/players 来自主机）
  _GameConfig? _cfgFromRemote(Map<String, dynamic> msg) {
    if (msg['t'] != 'cfg') return null;
    final count = (msg['count'] as num).toInt();
    final cols = (msg['cols'] as num).toInt();
    final rows = (msg['rows'] as num).toInt();
    final players = msg['players'] as List;
    if (players.length != count) return null;
    final slots = <_SlotCfg>[];
    for (final e in players) {
      final m = e as Map<String, dynamic>;
      slots.add(_SlotCfg()
        ..skin = (m['skin'] as num).toInt()
        ..color = (m['color'] as num).toInt()
        ..human = m['human'] == true);
    }
    return _GameConfig(
      count: count,
      cols: cols,
      rows: rows,
      baseTickMs: (msg['base'] as num?)?.toDouble() ?? 110,
      slots: slots,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(c, isLight),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(c, isLight)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AppColors c, bool isLight) {
    final (cols, rows) = _GameConfig.mapRect(_count);
    return Row(children: [
      _iconBtn(c, Icons.arrow_back_rounded,
          () => Navigator.of(context).maybePop()),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('贪吃蛇 · 多人',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: c.text)),
            const SizedBox(height: 2),
            Text('$cols × $rows · 活到最后者胜',
                style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
          ],
        ),
      ),
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: c.cardAlt, borderRadius: BorderRadius.circular(20)),
        child: Text('真人 $_humanCount/$_count',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: c.textSecondary)),
      ),
    ]);
  }

  Widget _iconBtn(AppColors c, IconData ic, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: c.cardAlt, borderRadius: BorderRadius.circular(10)),
          child: Icon(ic, size: 18, color: c.textSecondary),
        ),
      );

  Widget _buildBody(AppColors c, bool isLight) {
    final (cols, rows) = _GameConfig.mapRect(_count);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 10),
      children: [
        _labelRow(c, '玩家人数', '$cols × $rows 地图'),
        const SizedBox(height: 8),
        _countSeg(c),
        const SizedBox(height: 20),
        _labelRow(c, '玩家阵容', '真人最多 3 名 · 其余人机'),
        const SizedBox(height: 8),
        ...List.generate(
          _count,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _slotCard(c, isLight, i),
          ),
        ),
        const SizedBox(height: 14),
        _startArea(c, isLight),
        const SizedBox(height: 12),
        Text(
            '联机：创建房间后在本机 43210 端口监听，将 IP 发给同局域网（或内网穿透映射）'
            '的另一台设备，对方选择「加入房间」即可。真人槽位由各端键盘操控。',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, color: c.textTertiary, height: 1.6)),
      ],
    );
  }

  /// 标签行：左侧主标签 + 右侧浅色说明
  Widget _labelRow(AppColors c, String l, String r) => Row(children: [
        Text(l,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.text)),
        const Spacer(),
        Text(r, style: TextStyle(fontSize: 11, color: c.textTertiary)),
      ]);

  /// 人数分段控件（iOS Segmented 风格：中性底 + 选中浮起白块）
  Widget _countSeg(AppColors c) {
    final isLight = c.isLight;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: c.cardAlt, borderRadius: BorderRadius.circular(11)),
      child: Row(children: [
        for (var n = 2; n <= 6; n++)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _count = n;
                _resetSlots(n);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: _count == n
                    ? BoxDecoration(
                        color: isLight ? Colors.white : const Color(0xFF45454F),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: isLight ? 0.06 : 0.28),
                              blurRadius: 4,
                              offset: const Offset(0, 1)),
                        ],
                      )
                    : null,
                alignment: Alignment.center,
                child: Text('$n',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: _count == n
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: _count == n ? c.text : c.textTertiary)),
              ),
            ),
          ),
      ]),
    );
  }

  /// 玩家行：第一行 肖像+编号+外观+人机/真人开关；第二行 色板+控制说明
  Widget _slotCard(AppColors c, bool isLight, int i) {
    final slot = _slots[i];
    final pal = _palettes[slot.color % _palettes.length];
    final human = slot.human;
    final selFill = isLight ? const Color(0xFF1A1A1E) : const Color(0xFFE4E4E8);
    final selText = isLight ? Colors.white : const Color(0xFF1A1A1E);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : kDarkCard,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: isLight ? const Color(0xFFECECEF) : kDarkBorder),
      ),
      child: Column(children: [
        Row(children: [
          SizedBox(
            width: 42,
            height: 26,
            child: CustomPaint(
              painter: _AvatarPainter(
                color: pal.body,
                accent: pal.accent,
                skin: _Skin.values[slot.skin % _Skin.values.length],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('P${i + 1}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.text)),
          const SizedBox(width: 10),
          _skinPicker(c, isLight, slot),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
                color: c.cardAlt, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              _seg(c, '人机', !human, selFill, selText,
                  () => setState(() => slot.human = false)),
              _seg(c, '真人', human, selFill, selText, () {
                if (!human && _humanCount >= 3) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('真人最多可选 3 名，其余请设为人机'),
                      behavior: SnackBarBehavior.floating));
                  return;
                }
                setState(() => slot.human = !human);
              }),
            ]),
          ),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          for (var pc = 0; pc < _palettes.length; pc++)
            GestureDetector(
              onTap: () => setState(() => slot.color = pc),
              child: Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _palettes[pc].body,
                  border: slot.color == pc
                      ? Border.all(
                          color: isLight ? Colors.white : kDarkCard, width: 2.5)
                      : null,
                  boxShadow: slot.color == pc
                      ? [
                          BoxShadow(
                              color: _palettes[pc]
                                  .body
                                  .withValues(alpha: 0.45),
                              blurRadius: 4)
                        ]
                      : null,
                ),
              ),
            ),
          const Spacer(),
          Text(human ? '键盘操控' : 'AI 自动',
              style: TextStyle(fontSize: 11, color: c.textTertiary)),
        ]),
      ]),
    );
  }

  /// 小分段按钮（黑/白中性选中）
  Widget _seg(AppColors c, String t, bool sel, Color fill, Color txt,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: sel
            ? BoxDecoration(
                color: fill, borderRadius: BorderRadius.circular(6))
            : null,
        child: Text(t,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: sel ? txt : c.textTertiary)),
      ),
    );
  }

  /// 外观选择：极简弹出菜单（无 emoji）
  Widget _skinPicker(AppColors c, bool isLight, _SlotCfg slot) {
    return PopupMenuButton<int>(
      initialValue: slot.skin,
      onSelected: (v) => setState(() => slot.skin = v),
      color: isLight ? Colors.white : kDarkCard,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.chipBorder)),
      constraints: const BoxConstraints(minWidth: 130),
      itemBuilder: (_) => [
        for (var s = 0; s < _skinLabels.length; s++)
          PopupMenuItem(
            value: s,
            height: 40,
            child: Text(_skinLabels[s],
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: slot.skin == s
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: c.text)),
          ),
      ],
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: c.cardAlt, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${_skinLabels[slot.skin]}外观',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary)),
          const SizedBox(width: 3),
          Icon(Icons.expand_more_rounded,
              size: 14, color: c.textTertiary),
        ]),
      ),
    );
  }

  /// 开始区：一个主 CTA（黑/白中性）+ 两个描边次级按钮 + 地图摘要
  Widget _startArea(AppColors c, bool isLight) {
    final (cols, rows) = _GameConfig.mapRect(_count);
    final area = cols * rows;
    final ratio = (area / (40 * 40)).toStringAsFixed(2);
    final fill =
        isLight ? const Color(0xFF1A1A1E) : const Color(0xFFE4E4E8);
    final txt = isLight ? Colors.white : const Color(0xFF1A1A1E);
    return Column(children: [
      // 主 CTA
      GestureDetector(
        onTap: _startLocal,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color:
                      Colors.black.withValues(alpha: isLight ? 0.12 : 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, size: 20, color: txt),
              const SizedBox(width: 4),
              Text('开始游戏',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: txt)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      // 次级：联机入口
      Row(children: [
        Expanded(
            child: _ghostBtn(c, isLight, Icons.router_rounded, '创建房间',
                _hostRoom)),
        const SizedBox(width: 8),
        Expanded(
            child: _ghostBtn(c, isLight, Icons.login_rounded, '加入房间',
                _joinRoom)),
      ]),
      const SizedBox(height: 12),
      Text(
        '地图 $cols × $rows · 面积为 2 人模式的 $ratio 倍 · 活到最后者胜',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: c.textTertiary),
      ),
    ]);
  }

  /// 描边幽灵按钮（次级操作）
  Widget _ghostBtn(AppColors c, bool isLight, IconData ic, String t,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : kDarkCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.chipBorder),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ic, size: 15, color: c.textSecondary),
            const SizedBox(width: 6),
            Text(t,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary)),
          ],
        ),
      ),
    );
  }

}

// ============================ 蛇头肖像绘制 ============================

class _AvatarPainter extends CustomPainter {
  final Color color;
  final Color accent;
  final _Skin skin;
  _AvatarPainter({required this.color, required this.accent, required this.skin});
  @override
  void paint(Canvas canvas, Size size) {
    final h = math.min(size.height, size.width * 1.2);
    final y = size.height / 2;
    // 小身体
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(
          Offset(size.width / 2 - i * h * 0.22, y), h * 0.16,
          Paint()..color = color);
    }
    // 头
    canvas.drawCircle(Offset(size.width / 2, y), h * 0.3,
        Paint()..color = accent);
    // 眼
    canvas.drawCircle(
        Offset(size.width / 2 + h * 0.1, y - h * 0.08), h * 0.07,
        Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(size.width / 2 + h * 0.13, y - h * 0.08), h * 0.035,
        Paint()..color = const Color(0xFF17201A));
  }

  @override
  bool shouldRepaint(covariant _AvatarPainter old) => true;
}

// ============================ 联机：创建房间提示 ============================

class _StartingRoomDialog extends StatelessWidget {
  final List<_SlotCfg> slots;
  const _StartingRoomDialog({required this.slots});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      backgroundColor: c.card,
      title: const Text('房间已创建'),
      content: Text('监听端口 43210。\n'
          '请让其他设备连接你：IP = 本机局域网IP : 43210。\n'
          '（提示：可配合内网穿透工具映射该端口供异地联机）',
          style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了')),
      ],
    );
  }
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();
  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinInfo {
  final String host;
  final int port;
  _JoinInfo(this.host, this.port);
}

class _JoinDialogState extends State<_JoinDialog> {
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '43210');
  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      backgroundColor: c.card,
      title: const Text('加入房间'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _host,
          decoration: const InputDecoration(labelText: '主机 IP / 域名'),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '端口'),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(
            onPressed: () {
              final host = _host.text.trim();
              final port = int.tryParse(_port.text.trim());
              if (host.isEmpty || port == null || port <= 0) return;
              Navigator.of(context).pop(_JoinInfo(host, port));
            },
            child: const Text('连接')),
      ],
    );
  }
}

// ============================ 游戏主界面 ============================

class _GameScreen extends StatefulWidget {
  final _GameConfig config;
  final _Mode mode; // local / host / client
  final ServerSocket? server; // host 模式
  final Socket? socket; // client 模式
  const _GameScreen(this.config,
      {required this.mode, this.server, this.socket});
  @override
  State<_GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<_GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // 棋盘尺寸（本机权威）
  late final int _cols = widget.config.cols;
  late final int _rows = widget.config.rows;
  late final int _total = _cols * _rows;
  late final double _baseTick = widget.config.baseTickMs;
  late final int _n = widget.config.count;

  late final List<_SnakeM> _snakes =
      List.generate(_n, (_) => _SnakeM());

  /// 食物球列表：每 2 个玩家生成 1 个球（2→1, 3→1, 4→2, 5→2, 6→3）
  final List<(int, int)> _food = <(int, int)>[];

  /// 黄球道具（一次性，等价吃 3 个红球）
  /// 位置由算法生成在距离 3 名玩家头部相同距离的等距点
  (int, int)? _bonusBall;
  /// 黄球下一次出现的等待毫秒（5~15s 随机），初始时为游戏开局后随机 5~15s
  int _bonusNextSpawnMs = 0;
  int _bonusClockMs = 0; // 距上次黄球事件（生成/被吃）的累计毫秒
  int _phase = 0; // 0 idle,1 playing,2 paused,3 over
  int _stepCount = 0;
  double _accumMs = 0;
  int _animMs = 0;
  double _interpP = 0.0;

  /// 死亡加速：每死一条蛇记录一个"5 秒后提速"的悬崖
  final List<int> _pendingBoosts = <int>[]; // 相对 _animMs 的到期时刻
  int _activeBoosts = 0;

  final List<int> _deathOrder = <int>[]; // 死亡顺序（记录胜者/名次）
  int _winner = -1;

  /// 帧率采样：每 0.5 秒一个数据点，最多保留 64 个点
  final List<double> _fpsSamples = <double>[];
  int _latestFps = 0;
  int _fpsLastSampleMs = 0;
  int _fpsFramesSinceSample = 0;

  // 独占专注
  final FocusNode _focusNode = FocusNode();
  final ValueNotifier<int> _frameSignal = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration? _lastFrameTime;
  int? _lastRepaintMs;

  final math.Random _rng = math.Random();

  // 联机
  _Mode get _mode => widget.mode;
  ServerSocket? _server;
  Socket? _clientSock;
  int _mySlot = -1; // client 控制的槽位
  final List<Socket> _clients = <Socket>[];
  bool _netInited = false;

  @override
  void initState() {
    super.initState();
    _placePlayers();
    for (var i = 0; i < (_n ~/ 2); i++) {
      _food.add(_randomFree());
    }
    _bonusBall = _randomFree();
    _ticker = createTicker(_onFrame);
    // Windows 全屏切换/最大化时强制重建，修复 LayoutBuilder 拿不到新尺寸导致
    // 棋盘停在旧尺寸的问题。用 WidgetsBindingObserver 而非改写 onMetricsChanged，
    // 避免覆盖引擎内部的窗口尺寸同步逻辑（覆盖会导致拉伸时画面消失）。
    WidgetsBinding.instance.addObserver(this);
    _initNet();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  Future<void> _initNet() async {
    if (_mode == _Mode.host) {
      _server = widget.server;
      _server!.listen(_onClientAccepted, onError: (_) {});
      // 作为主机，本机不自动占用任何真人槽——由加入者认领
      setState(() {});
    } else if (_mode == _Mode.client) {
      _clientSock = widget.socket;
      _mySlot = _claimFunction();
      _clientSock!.listen(_onClientData, onError: (_) {}, onDone: () {
        if (mounted) {
          setState(() {
            _phase = 3; // 连接断开，游戏结束
          });
        }
      });
      _netInited = true;
    }
  }

  /// 客户端占用一个真人槽位（从纯 host 约定的元数据里挑）
  int _claimFunction() {
    // 在握手阶段，client 还不知道自己的槽位（由 host 分配）。
    // 这里返回 -1，随后通过第一帧 host 下发的 cfg 里带上 yourSlot。
    return -1;
  }

  int _id(int y, int x) => y * _cols + x;

  /// 本机可键盘操控的真人槽位（按真人顺序映射键盘方案）
  /// local：所有 human 槽；host：human 且非 remote 槽
  List<int> _keySlots() {
    final out = <int>[];
    for (var i = 0; i < _n; i++) {
      if (_mode == _Mode.client) continue;
      if (_mode == _Mode.local && widget.config.slots[i].human) out.add(i);
      if (_mode == _Mode.host &&
          widget.config.slots[i].human &&
          !widget.config.slots[i].remote) {
        out.add(i);
      }
    }
    return out;
  }

  /// 开局将玩家们按圆周均匀铺在地图各处，互不靠近
  void _placePlayers() {
    final cx = _cols / 2;
    final cy = _rows / 2;
    final radius = math.min(_cols, _rows) / 2 - 4;
    for (var i = 0; i < _n; i++) {
      final p = _snakes[i];
      final ang = 2 * math.pi * i / _n + math.pi / 2;
      final hx = (cx + radius * math.cos(ang)).round().clamp(1, _cols - 2);
      final hy = (cy + radius * math.sin(ang)).round().clamp(1, _rows - 2);
      // 方向向外（尽量散开）
      final dx = (hx >= cx ? 1 : 0) == 1 ? 1 : -1;
      final dy = (hy >= cy ? 1 : 0) == 1 ? 1 : -1;
      // 让方向大致指向远离中心
      final odx = (hx - cx).sign.toInt() == 0 ? dx : (hx - cx).sign.toInt();
      final ody = (hy - cy).sign.toInt() == 0 ? dy : (hy - cy).sign.toInt();
      p
        ..xs.clear()
        ..ys.clear()
        ..prevXs.clear()
        ..prevYs.clear()
        ..pending.clear()
        ..score = 0
        ..alive = true
        ..deathTick = 0;
      // 身体从头部向反方向延伸 5 格
      final bx = odx == 0 ? 1 : odx;
      final by2 = ody == 0 ? 1 : ody;
      for (var k = 0; k < 5; k++) {
        p.xs.add(hx - bx * k);
        p.ys.add(hy - by2 * k);
      }
      p.dx = bx;
      p.dy = by2;
    }
  }

  (int, int) _randomFree() {
    final occ = Uint8List(_total);
    for (final p in _snakes) {
      if (!p.alive) continue;
      for (var i = 0; i < p.len; i++) {
        occ[_id(p.ys[i], p.xs[i])] = 1;
      }
    }
    if (_bonusBall != null) {
      occ[_id(_bonusBall!.$2, _bonusBall!.$1)] = 1;
    }
    final free = <int>[];
    for (var i = 0; i < _total; i++) {
      if (occ[i] == 0) free.add(i);
    }
    if (free.isEmpty) return (0, 0);
    final c = _rng.nextInt(free.length);
    return (free[c] % _cols, free[c] ~/ _cols);
  }

  /// 计算黄球位置：在距离 3 名玩家头部**相同距离**的位置
  /// 算法说明：从当前存活蛇中随机取 3 个头，构成三角形。
  /// 在 3 头几何中心周围找一点 P 使得 |PA|=|PB|=|PC|（外接圆圆心）。
  /// 若玩家数 < 3，则退化为"与各头平均距离相等的点"（即几何中心 + 同距环上随机角度）。
  (int, int)? _generateBonusPos() {
    final alive = <int>[];
    for (var i = 0; i < _n; i++) {
      if (_snakes[i].alive) alive.add(i);
    }
    if (alive.isEmpty) return null;
    // 随机挑 3 个（若不足 3 个就全用）
    alive.shuffle(_rng);
    final picks = alive.take(math.min(3, alive.length)).toList();
    if (picks.length == 1) {
      // 1 个玩家：在地图对侧生成
      final hx = _snakes[picks[0]].xs[0];
      final hy = _snakes[picks[0]].ys[0];
      final px = (_cols - 1 - hx).clamp(1, _cols - 2);
      final py = (_rows - 1 - hy).clamp(1, _rows - 2);
      return (px, py);
    }
    final heads = <(int, int)>[
      for (final i in picks) (_snakes[i].xs[0], _snakes[i].ys[0])
    ];
    // 3 头的几何中心
    double cx = 0, cy = 0;
    for (final h in heads) {
      cx += h.$1;
      cy += h.$2;
    }
    cx /= heads.length;
    cy /= heads.length;
    // 等距距离：取距几何中心最远头的距离（保证点在地图范围内）
    double maxR = 0;
    for (final h in heads) {
      final d = math.sqrt(math.pow(h.$1 - cx, 2) + math.pow(h.$2 - cy, 2));
      if (d > maxR) maxR = d;
    }
    if (maxR < 1) maxR = math.min(_cols, _rows) / 4;
    // 在等距环上随机一个方向，得到"距 3 头同距"的点
    final ang = _rng.nextDouble() * 2 * math.pi;
    var px = (cx + maxR * math.cos(ang)).round();
    var py = (cy + maxR * math.sin(ang)).round();
    px = px.clamp(1, _cols - 2);
    py = py.clamp(1, _rows - 2);
    // 落点不能压在蛇身上
    final occ = Uint8List(_total);
    for (final p in _snakes) {
      if (!p.alive) continue;
      for (var i = 0; i < p.len; i++) {
        occ[_id(p.ys[i], p.xs[i])] = 1;
      }
    }
    if (occ[_id(py, px)] == 0) return (px, py);
    // 退而求其次：在中心点周围按螺旋向外搜索一个空位
    for (var r = 1; r < math.min(_cols, _rows); r++) {
      for (var a = 0; a < 8; a++) {
        final aa = a * math.pi / 4;
        final tx = (cx + r * math.cos(aa)).round().clamp(1, _cols - 2);
        final ty = (cy + r * math.sin(aa)).round().clamp(1, _rows - 2);
        if (occ[_id(ty, tx)] == 0) return (tx, ty);
      }
    }
    return null;
  }

  void _start() {
    _placePlayers();
    _food.clear();
    for (var i = 0; i < (_n ~/ 2); i++) {
      _food.add(_randomFree());
    }
    // 黄球初始：随机 5~15 秒后第一次出现
    _bonusBall = null;
    _bonusNextSpawnMs = 5000 + _rng.nextInt(10001); // [5000, 15000]
    _bonusClockMs = 0;
    _phase = 1;
    _stepCount = 0;
    _accumMs = 0;
    _animMs = 0;
    _pendingBoosts.clear();
    _activeBoosts = 0;
    _deathOrder.clear();
    _winner = -1;
    _fpsSamples.clear();
    _fpsLastSampleMs = 0;
    _fpsFramesSinceSample = 0;
    _focusNode.requestFocus();
    _lastFrameTime = null;
    if (!_ticker.isActive) _ticker.start();
    _frameSignal.value++;
  }

  void _togglePause() {
    if (_mode == _Mode.client) return;
    if (_phase == 0) {
      _start();
      return;
    }
    if (_phase == 3) return;
    setState(() {
      _phase = _phase == 1 ? 2 : 1;
    });
    _lastFrameTime = null;
    if (_phase == 1) {
      // 恢复播放：_onFrame 在暂停/结束时会自停 Ticker，这里必须重启
      if (!_ticker.isActive) _ticker.start();
      _focusNode.requestFocus();
    }
  }

  void _close() {
    try {
      _server?.close();
    } catch (_) {}
    try {
      _clientSock?.close();
    } catch (_) {}
    Navigator.of(context).maybePop();
  }

  // ==================== 帧循环 ====================

  void _onFrame(Duration elapsed) {
    // 非播放态（暂停/结束/断开/未开始）自停渲染循环，避免满帧空转（对齐单机版做法）。
    // 恢复播放的路径（_start/_togglePause/客户端收到 cfg）会重新 start
    if (_phase != 1) {
      _ticker.stop();
      _lastFrameTime = null;
      return;
    }
    final dtMs = _lastFrameTime == null
        ? 0
        : (elapsed - _lastFrameTime!).inMicroseconds ~/ 1000;
    _lastFrameTime = elapsed;
    if (dtMs <= 0) return;

    final nowMs = elapsed.inMilliseconds;
    _lastRepaintMs ??= nowMs;
    var stepped = false;

    if (_phase == 1) {
      _animMs = (_animMs + dtMs) & 0x7fffffff;
      // 由当前活跃加速决定 tick 间隔
      final tick = _currentTick();
      _accumMs += dtMs;
      var guard = 0;
      // 服务端/本机模式自动推进逻辑；客户端模式由快照驱动（不发步）
      if (_mode != _Mode.client) {
        while (_accumMs >= tick && guard < 8) {
          guard++;
          _accumMs -= tick;
          _step();
          stepped = true;
          if (_phase != 1) break;
        }
      }
    }

    if (stepped || (nowMs - _lastRepaintMs!) >= 16) {
      _lastRepaintMs = nowMs;
      _interpP = _accumMs / _currentTick();
      if (_interpP > 1) _interpP = 1;
      // 帧率采样：每 500ms 统计一次
      _fpsFramesSinceSample++;
      if (_fpsLastSampleMs == 0) _fpsLastSampleMs = nowMs;
      final dt = nowMs - _fpsLastSampleMs;
      if (dt >= 500) {
        final fps = _fpsFramesSinceSample * 1000.0 / dt;
        _fpsSamples.add(fps.clamp(0, 240));
        if (_fpsSamples.length > 64) _fpsSamples.removeAt(0);
        _latestFps = fps.round();
        _fpsLastSampleMs = nowMs;
        _fpsFramesSinceSample = 0;
      }
      _frameSignal.value++;
    }
  }

  double _currentTick() {
    // 速度提升 = 基础速度上每死一条 +15%（作用于 interval 的倒数）
    final mult = 1 + 0.15 * _activeBoosts;
    return _baseTick / mult;
  }

  /// 剩余“下一次提速”的倒计时（毫秒），无则 -1
  int _nextBoostRemainMs() {
    if (_pendingBoosts.isEmpty) return -1;
    final deadline = _pendingBoosts.first;
    final remain = deadline - _animMs;
    return remain < 0 ? 0 : remain;
  }

  // ==================== 逻辑单步 ====================

  void _step() {
    _stepCount++;

    // —— AI 决策（对本机 AI 槽；真人与远程槽不做 AI） ——
    for (var i = 0; i < _n; i++) {
      bool isAi;
      if (_mode == _Mode.local) {
        isAi = !widget.config.slots[i].human;
      } else if (_mode == _Mode.host) {
        isAi = !widget.config.slots[i].human && !widget.config.slots[i].remote;
      } else {
        isAi = false;
      }
      if (isAi) _aiDecide(i);
    }

    // —— 消费方向（真人键盘缓冲 / AI 决策 / 远程客户端直入） ——
    final dirs = List<(int, int)?>.filled(_n, null);
    for (var i = 0; i < _n; i++) {
      final p = _snakes[i];
      if (!p.alive) continue;
      if (p.pending.isNotEmpty) {
        final d = p.pending.removeAt(0);
        p.dx = d.$1;
        p.dy = d.$2;
      }
      dirs[i] = (p.dx, p.dy);
    }

    // —— 新头 + 吃食标记 ——
    final nx = List<int?>.filled(_n, null);
    final ny = List<int?>.filled(_n, null);
    final eat = List<int>.filled(_n, 0); // 0=没吃 1=吃红球 2=吃黄球
    for (var i = 0; i < _n; i++) {
      final p = _snakes[i];
      if (!p.alive || dirs[i] == null) continue;
      final hx = p.xs[0] + dirs[i]!.$1;
      final hy = p.ys[0] + dirs[i]!.$2;
      nx[i] = hx;
      ny[i] = hy;
      // 红球：吃任意一个红球都算
      for (var k = 0; k < _food.length; k++) {
        if (hx == _food[k].$1 && hy == _food[k].$2) {
          eat[i] = 1;
          break;
        }
      }
      // 黄球：长度 ×3
      final bb = _bonusBall;
      if (eat[i] == 0 && bb != null && hx == bb.$1 && hy == bb.$2) {
        eat[i] = 2;
      }
    }

    // —— 碰撞判定（本机权威） ——
    final kill = List<bool>.filled(_n, false);
    for (var i = 0; i < _n; i++) {
      final p = _snakes[i];
      if (!p.alive || nx[i] == null) continue;
      final hx = nx[i]!, hy = ny[i]!;
      // 撞墙
      if (hx < 0 || hx >= _cols || hy < 0 || hy >= _rows) {
        kill[i] = true;
        continue;
      }
      // 撞自己
      final selfEnd = eat[i] > 0 ? p.len : p.len - 1;
      for (var s = 0; s < selfEnd; s++) {
        if (p.xs[s] == hx && p.ys[s] == hy) {
          kill[i] = true;
          break;
        }
      }
      if (kill[i]) continue;
      // 撞其他蛇身体
      for (var j = 0; j < _n; j++) {
        if (j == i) continue;
        final q = _snakes[j];
        if (!q.alive) continue;
        final qEnd = eat[j] > 0 ? q.len : q.len - 1;
        for (var s = 1; s < qEnd; s++) {
          if (q.xs[s] == hx && q.ys[s] == hy) {
            kill[i] = true;
            break;
          }
        }
        // 头撞头：两者皆死（各自被标记）
        if (!kill[i] && nx[j] != null && nx[j] == hx && ny[j] == hy) {
          kill[i] = true;
          // 也把对方标记（本循环处理到 j 时会因自身判断覆盖，这里直接处理）
        }
        if (kill[i]) break;
      }
    }
    // 头撞头结算：两条同时进同一格互撞——逐个处理即可（上面已把对方撞上）

    // —— 标记死亡 ——
    var anyDeath = false;
    for (var i = 0; i < _n; i++) {
      if (kill[i] && _snakes[i].alive) {
        _snakes[i].alive = false;
        _snakes[i].deathTick = _stepCount;
        _deathOrder.add(i);
        anyDeath = true;
      }
    }

    bool gameOver = false;
    final alive = _aliveCount();
    if (alive <= 1) {
      gameOver = true;
    } else if (anyDeath) {
      // 有人死：5 秒后提速（若 4 秒内没人死或本步就结束，则永不再提）
      _pendingBoosts.add(_animMs + 5000);
    }
    // 清理已过期的 pending（活跃计数）
    while (_pendingBoosts.isNotEmpty && _pendingBoosts.first <= _animMs) {
      _activeBoosts++;
      _pendingBoosts.removeAt(0);
    }

    // —— 快照移动前坐标 ——
    for (var i = 0; i < _n; i++) {
      final p = _snakes[i];
      p.prevXs
        ..clear()
        ..addAll(p.xs);
      p.prevYs
        ..clear()
        ..addAll(p.ys);
    }

    // —— 应用移动 ——
    for (var i = 0; i < _n; i++) {
      final p = _snakes[i];
      if (!p.alive || nx[i] == null) continue;
      p.xs.insert(0, nx[i]!);
      p.ys.insert(0, ny[i]!);
      if (eat[i] == 0) {
        p.xs.removeLast();
        p.ys.removeLast();
      }
    }

    // —— 吃食结算 ——
    var ateRed = false;
    for (var i = 0; i < _n; i++) {
      if (!_snakes[i].alive) continue;
      if (eat[i] == 1) {
        _snakes[i].score += 10;
        ateRed = true;
      } else if (eat[i] == 2) {
        // 黄球 = 吃 3 个红球的效果（身体 +3 节，等价一次吃 3 个红球）
        final p = _snakes[i];
        final tailX = p.xs.last;
        final tailY = p.ys.last;
        for (var k = 0; k < 3; k++) {
          p.xs.add(tailX);
          p.ys.add(tailY);
        }
        _snakes[i].score += 30;
        _bonusBall = null;
        // 被吃后：开始新一轮 5~15s 随机等待
        _bonusNextSpawnMs = 5000 + _rng.nextInt(10001);
        _bonusClockMs = 0;
      }
    }
    if (ateRed) {
      // 找到被吃掉的那个球并替换为新球，保持红球总数 = N/2
      for (var k = 0; k < _food.length; k++) {
        bool consumed = false;
        for (var i = 0; i < _n; i++) {
          if (eat[i] == 1 && _food[k].$1 == nx[i] && _food[k].$2 == ny[i]) {
            consumed = true;
            break;
          }
        }
        if (consumed) {
          _food[k] = _randomFree();
          break;
        }
      }
    }

    // —— 黄球补给：每 5~15 秒随机刷新（被吃后或初始等待） ——
    if (_bonusBall == null) {
      _bonusClockMs += _currentTick().toInt();
      if (_bonusClockMs >= _bonusNextSpawnMs) {
        final pos = _generateBonusPos();
        if (pos != null) {
          _bonusBall = pos;
          _bonusClockMs = 0;
        }
      }
    }

    // —— 联机广播快照 ——
    if (_mode == _Mode.host) _broadcastSnapshot();

    // —— 判定结束 ——
    if (gameOver) {
      if (_deathOrder.isNotEmpty) {
        _winner = _deathOrder.last; // 最后死的人即失败者，最后相对幸存者是 win
        // 重新算：活到最后者
        _winner = -1;
        for (var i = 0; i < _n; i++) {
          if (_snakes[i].alive) {
            _winner = i;
            break;
          }
        }
      }
      setState(() {
        _phase = 3;
      });
    }
  }

  int _aliveCount() {
    var c = 0;
    for (var i = 0; i < _n; i++) {
      if (_snakes[i].alive) c++;
    }
    return c;
  }

  // ==================== AI ====================

  Uint8List _boardBlocks() {
    final g = Uint8List(_total);
    for (final p in _snakes) {
      if (!p.alive) continue;
      for (var i = 0; i < p.len - 1; i++) {
        g[_id(p.ys[i], p.xs[i])] = 1;
      }
    }
    return g;
  }

  List<(int, int)> _bfsPath(int sx, int sy, int tx, int ty, Uint8List base) {
    if (sx == tx && sy == ty) return const [];
    final blocked = Uint8List.fromList(base);
    blocked[_id(sy, sx)] = 0;
    blocked[_id(ty, tx)] = 0;
    final prev = Int32List(_total)..fillRange(0, _total, -1);
    final start = _id(sy, sx);
    prev[start] = -2;
    final q = <int>[start];
    var hq = 0;
    const dirs = <(int, int)>[(0, -1), (1, 0), (0, 1), (-1, 0)];
    var found = -1;
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

  void _aiDecide(int i) {
    final p = _snakes[i];
    if (!p.alive) return;
    p.pending.clear();
    final hx = p.xs[0], hy = p.ys[0];
    final tx = p.xs[p.len - 1], ty = p.ys[p.len - 1];
    final blocks = _boardBlocks();
    // 目标候选：所有红球 + 黄球（黄球奖励=3 红球，同等距离下优先）
    final targets = <(int x, int y, bool bonus)>[
      for (final f in _food) (f.$1, f.$2, false),
      if (_bonusBall != null) (_bonusBall!.$1, _bonusBall!.$2, true),
    ];
    if (targets.isEmpty) {
      p.dx = 1;
      p.dy = 0;
      return;
    }
    // 选 BFS 可达中加权最优（黄球价值高 → 弯路容忍度更大）
    (int, int, bool) chosen = targets.first;
    // bonus 的奖励权重：吃 3 个红球，故允许为其多走些路
    // 代价 = 路径长度 - (bonus ? 黄球额外收益折算 : 0)
    const bonusExtra = 10;
    List<(int, int)>? bestPath;
    var bestCost = 1 << 30;
    for (final t in targets) {
      final path = _bfsPath(hx, hy, t.$1, t.$2, blocks);
      if (path.isEmpty) continue;
      final cost = path.length - (t.$3 ? bonusExtra : 0);
      if (cost < bestCost) {
        bestCost = cost;
        bestPath = path;
        chosen = t;
      }
    }
    if (bestPath != null) {
      p.dx = bestPath.first.$1 - hx;
      p.dy = bestPath.first.$2 - hy;
      return;
    }
    // 都不可达 → 选曼哈顿最近的目标（同样偏向黄球）
    var bestD = 1 << 30;
    for (final t in targets) {
      final d = (t.$1 - hx).abs() + (t.$2 - hy).abs() - (t.$3 ? bonusExtra : 0);
      if (d < bestD) {
        bestD = d;
        chosen = t;
      }
    }
    final toTail = _bfsPath(hx, hy, tx, ty, blocks);
    if (toTail.isNotEmpty) {
      p.dx = toTail.first.$1 - hx;
      p.dy = toTail.first.$2 - hy;
      return;
    }
    final best = _closestSafeDir(hx, hy, chosen.$1, chosen.$2, blocks);
    if (best != null) {
      p.dx = best.$1;
      p.dy = best.$2;
    }
  }

  (int, int)? _closestSafeDir(int hx, int hy, int fx, int fy, Uint8List blocks) {
    const dirs = <(int, int)>[(0, -1), (1, 0), (0, 1), (-1, 0)];
    (int, int)? best;
    var bestD = 1 << 30;
    for (final (dx, dy) in dirs) {
      final nx = hx + dx, ny = hy + dy;
      if (nx < 0 || nx >= _cols || ny < 0 || ny >= _rows) continue;
      if (blocks[_id(ny, nx)] == 1) continue;
      final d = (nx - fx).abs() + (ny - fy).abs();
      if (d < bestD) {
        bestD = d;
        best = (dx, dy);
      }
    }
    return best;
  }

  // ==================== 键盘输入 ====================

  void _queueTurn(int i, int dx, int dy) {
    if (_phase != 1) return;
    final p = _snakes[i];
    if (!p.alive) return;
    if (p.pending.length >= 2) return;
    final (lx, ly) = p.pending.isEmpty ? (p.dx, p.dy) : p.pending.last;
    if ((dx == -lx && dy == -ly) || (dx == lx && dy == ly)) return;
    p.pending.add((dx, dy));
    // 联机客户端：把方向上报给主机
    if (_mode == _Mode.client && i == _mySlot) {
      _Net.send(_clientSock!, {'t': 'dir', 'dx': dx, 'dy': dy});
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    // 通用快捷键
    if (k == LogicalKeyboardKey.space) {
      _togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyR) {
      _start();
      return KeyEventResult.handled;
    }
    // 联机客户端：本地只管 mySlot（WASD / 方向键 / UJHK 皆可）
    if (_mode == _Mode.client) {
      if (_mySlot < 0 || _mySlot >= _n) return KeyEventResult.handled;
      if (k == LogicalKeyboardKey.keyW ||
          k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.keyU) {
        _queueTurn(_mySlot, 0, -1);
      } else if (k == LogicalKeyboardKey.keyS ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.keyJ) {
        _queueTurn(_mySlot, 0, 1);
      } else if (k == LogicalKeyboardKey.keyA ||
          k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.keyH) {
        _queueTurn(_mySlot, -1, 0);
      } else if (k == LogicalKeyboardKey.keyD ||
          k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.keyK) {
        _queueTurn(_mySlot, 1, 0);
      }
      return KeyEventResult.handled;
    }
    // 本机：P1=WASD / P2=方向键 / P3=UJHK，映射到真人槽顺序
    final ks = _keySlots();
    int s(int idx) => idx < ks.length ? ks[idx] : -1;
    final s0 = s(0), s1 = s(1), s2 = s(2);
    switch (k) {
      case LogicalKeyboardKey.keyW:
      case LogicalKeyboardKey.keyI:
        if (s0 >= 0) _queueTurn(s0, 0, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA:
        if (s0 >= 0) _queueTurn(s0, -1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
      case LogicalKeyboardKey.keyK:
        if (s0 >= 0) _queueTurn(s0, 0, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD:
      case LogicalKeyboardKey.keyL:
        if (s0 >= 0) _queueTurn(s0, 1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (s1 >= 0) _queueTurn(s1, 0, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (s1 >= 0) _queueTurn(s1, 0, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (s1 >= 0) _queueTurn(s1, -1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (s1 >= 0) _queueTurn(s1, 1, 0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyU:
        if (s2 >= 0) _queueTurn(s2, 0, -1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyJ:
        if (s2 >= 0) _queueTurn(s2, 0, 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyH:
        if (s2 >= 0) _queueTurn(s2, -1, 0);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ==================== 联机：Host ====================

  void _onClientAccepted(Socket sock) {
    _clients.add(sock);
    // 分配一个空闲的 remote 真人槽位
    int slot = -1;
    for (var i = 0; i < _n; i++) {
      if (_mode == _Mode.host &&
          widget.config.slots[i].remote &&
          !_assignedslot.contains(i)) {
        slot = i;
        break;
      }
    }
    if (slot < 0) {
      // 没有多余槽位：拒绝
      _Net.send(sock, {
        't': 'full'
      });
      try {
        sock.close();
      } catch (_) {}
      return;
    }
    _assignedslot.add(slot);
    // 下发配置 + yourSlot
    _Net.send(sock, {
      't': 'cfg',
      'count': _n,
      'cols': _cols,
      'rows': _rows,
      'base': _baseTick,
      'players': [
        for (var i = 0; i < _n; i++)
          {
            'skin': widget.config.slots[i].skin,
            'color': widget.config.slots[i].color,
            'human': widget.config.slots[i].remote,
          }
      ],
      'yourSlot': slot,
    });
    sock.listen((buf) {
      // 只处理 dir 指令；忽略其他
      try {
        final str = utf8.decode(buf, allowMalformed: true);
        final lines = str.split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final m = jsonDecode(line.trim()) as Map<String, dynamic>;
          if (m['t'] == 'dir') {
            final dx = (m['dx'] as num).toInt();
            final dy = (m['dy'] as num).toInt();
            _queueTurn(slot, dx, dy);
          }
        }
      } catch (_) {}
    }, onDone: () {
      _clients.remove(sock);
      _assignedslot.remove(slot);
      try {
        sock.close();
      } catch (_) {}
    }, onError: (_) {});
  }

  final Set<int> _assignedslot = <int>{};

  void _broadcastSnapshot() {
    final snap = jsonEncode({
      't': 's',
      'step': _stepCount,
      'phase': _phase,
      'food': [for (final f in _food) [f.$1, f.$2]],
      'bonus': _bonusBall == null ? null : [_bonusBall!.$1, _bonusBall!.$2],
      'pendingBoostMs': _nextBoostRemainMs(),
      'activeBoosts': _activeBoosts,
      'winner': _winner,
      'snakes': [
        for (var i = 0; i < _n; i++)
          {
            'x': _snakes[i].xs,
            'y': _snakes[i].ys,
            'alive': _snakes[i].alive,
            'score': _snakes[i].score,
          }
      ],
    }) +
        '\n';
    for (var i = _clients.length - 1; i >= 0; i--) {
      try {
        _clients[i].add(utf8.encode(snap));
      } catch (_) {
        _clients.removeAt(i);
      }
    }
  }

  // ==================== 联机：Client ====================

  // 客户端渲染缓冲（由快照驱动）
  final List<List<int>> _cxs = <List<int>>[];
  final List<List<int>> _cys = <List<int>>[];
  final List<bool> _calive = <bool>[];
  final List<int> _cscore = <int>[];
  final List<(int, int)> _cfood = <(int, int)>[];
  (int, int)? _cbonus;
  int _cpendingBoostMs = -1;
  int _cactiveBoosts = 0;
  bool _clientHasCfg = false;

  void _onClientData(Uint8List buf) {
    try {
      final str = utf8.decode(buf, allowMalformed: true);
      final lines = str.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final m = jsonDecode(line.trim()) as Map<String, dynamic>;
        if (m['t'] == 'cfg') {
          final ys = (m['yourSlot'] as num).toInt();
          // 重设客户端槽位
          _mySlot = ys;
          _clientHasCfg = true;
          // 收到配置即进入播放态并启动渲染循环（原逻辑在 build() 里改 _phase，
          // 违反构建纯函数约定，且可能不触发重绘）
          _phase = 1;
          _lastFrameTime = null;
          if (!_ticker.isActive) _ticker.start();
          final n = (m['count'] as num).toInt();
          while (_cxs.length < n) {
            _cxs.add(<int>[]);
            _cys.add(<int>[]);
            _calive.add(true);
            _cscore.add(0);
          }
          setState(() {});
        } else if (m['t'] == 's') {
          if (!_clientHasCfg) continue;
          final snakes = m['snakes'] as List;
          _cscore.clear();
          _calive.clear();
          for (var i = 0; i < snakes.length; i++) {
            final e = snakes[i] as Map<String, dynamic>;
            final x = (e['x'] as List).cast<num>().cast<int>();
            final y = (e['y'] as List).cast<num>().cast<int>();
            if (_cxs.length <= i) {
              _cxs.add(<int>[]);
              _cys.add(<int>[]);
            }
            _cxs[i] = x;
            _cys[i] = y;
            _calive.add(e['alive'] == true);
            _cscore.add((e['score'] as num).toInt());
          }
          final f = m['food'] as List;
          _cfood
            ..clear()
            ..addAll(f.map((e) {
              final p = e as List;
              return ((p[0] as num).toInt(), (p[1] as num).toInt());
            }));
          final bb = m['bonus'] as List?;
          if (bb == null) {
            _cbonus = null;
          } else {
            _cbonus = ((bb[0] as num).toInt(), (bb[1] as num).toInt());
          }
          _cpendingBoostMs = (m['pendingBoostMs'] as num?)?.toInt() ?? -1;
          _cactiveBoosts = (m['activeBoosts'] as num?)?.toInt() ?? 0;
          final ph = (m['phase'] as num?)?.toInt() ?? 1;
          if (ph == 3 && _phase != 3) {
            _winner = (m['winner'] as num?)?.toInt() ?? -1;
            setState(() => _phase = 3);
          } else {
            _frameSignal.value++;
          }
        }
      }
    } catch (_) {}
  }

  // ==================== UI ====================

  @override
  void dispose() {
    try {
      _server?.close();
    } catch (_) {}
    try {
      _clientSock?.close();
    } catch (_) {}
    // 主机模式：关闭所有已接受的客户端连接，避免对局结束泄漏 socket 至 GC
    for (final c in _clients) {
      try {
        c.close();
      } catch (_) {}
    }
    _clients.clear();
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frameSignal.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    // 注：客户端模式的播放态切换已移至 _onClientData 收到 cfg 时处理，
    // 不在 build 中改业务状态（构建须为纯函数）

    return Scaffold(
      backgroundColor: c.bg,
      body: Focus(
        focusNode: _focusNode,
        autofocus: true,
        canRequestFocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: Column(children: [
            _toolbar(c, isLight),
            // 棋盘占满全屏（地图占比 ≥85%：顶部仅一条细工具条，棋盘占满剩余空间）
            Expanded(
              child: Container(
                // 整个窗口统一为棋盘深色基调：正方形地图在宽窗口下左右存在边界空位，
                // 同色让整屏呈现"完整游戏画面"，紫色边框标出可玩区
                color: isLight ? const Color(0xFF36363D) : const Color(0xFF15151A),
                child: Center(
                  child: LayoutBuilder(
                    builder: (ctx, cons) {
                      // 以布局短边为基准计算正方形格子（地图完整可见、边界清晰）
                      final cell =
                          math.min(cons.maxWidth / _cols, cons.maxHeight / _rows);
                      final cw = cell;
                      final ch = cell;
                      final boardW = cw * _cols;
                      final boardH = ch * _rows;
                      return ValueListenableBuilder<int>(
                        valueListenable: _frameSignal,
                        builder: (context, _, __) {
                          return Stack(children: [
                            // 正方形棋盘：完整铺满短边方向，随窗口 resize 等比缩放
                            Center(
                              child: Container(
                                width: boardW,
                                height: boardH,
                                decoration: BoxDecoration(
                                  color: isLight
                                      ? const Color(0xFF202024)
                                      : const Color(0xFF101014),
                                  border: Border.all(
                                    color: isLight
                                        ? const Color(0xFF7C3AED)
                                        : const Color(0xFFA78BFA),
                                    width: 4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (isLight
                                              ? const Color(0xFF7C3AED)
                                              : const Color(0xFFA78BFA))
                                          .withValues(alpha: 0.25),
                                      blurRadius: 20,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: _buildBoard(c, isLight, cw, ch),
                              ),
                            ),
                            // 帧率数字：浮在棋盘**内**的左上角紫色描边处
                            // 不渲染波形图，仅显示当前 FPS
                            Positioned(
                              left: 16,
                              top: 16,
                              child: IgnorePointer(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: (isLight
                                              ? const Color(0xFF7C3AED)
                                              : const Color(0xFFA78BFA))
                                          .withValues(alpha: 0.6),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    'FPS $_latestFps',
                                    style: TextStyle(
                                      color: isLight
                                          ? const Color(0xFFE4D9FF)
                                          : const Color(0xFFC4B5FD),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ]);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildBoard(AppColors c, bool isLight, double cw, double ch) {
    final over = _phase == 3;
    // 客户端用缓冲区；本机/主机用引擎
    final paintSnakes = _mode == _Mode.client ? _clientSnakes() : _tsnakes();
    final foodUsed = _mode == _Mode.client ? _cfood : _food;
    final boostRemain =
        _mode == _Mode.client ? _cpendingBoostMs : _nextBoostRemainMs();
    final activeBoost =
        _mode == _Mode.client ? _cactiveBoosts : _activeBoosts;

    final bonusUsed = _mode == _Mode.client ? _cbonus : _bonusBall;

    return Stack(children: [
      RepaintBoundary(
        child: CustomPaint(
          painter: _MultiPainter(
            snakes: paintSnakes,
            food: foodUsed,
            bonus: bonusUsed,
            animMs: _animMs,
            playing: _phase == 1,
            cw: cw,
            ch: ch,
            cols: _cols,
            rows: _rows,
            interpP: _mode == _Mode.client ? 1.0 : _interpP,
            isLight: isLight,
          ),
          size: Size.infinite,
        ),
      ),
      // 加速倒计时显示（棋盘空白处）
      if (boostRemain > 0)
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: (isLight ? Colors.white : kDarkBg)
                      .withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.chipBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded,
                        size: 16, color: const Color(0xFFF59E0B)),
                    const SizedBox(width: 5),
                    Text(
                        '加速倒计时 ${(boostRemain / 1000).toStringAsFixed(1)} 秒',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFF59E0B))),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (activeBoost > 0)
        Positioned(
          top: 40,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('全场加速 ×${(1 + 0.15 * activeBoost).toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFF59E0B))),
              ),
            ),
          ),
        ),
      // 联机状态角标
      if (_mode != _Mode.local && _clients.isNotEmpty)
        Positioned(bottom: 8, left: 8, child: _netBadge(c, '已连接 ${_clients.length} 台')),
      if (_mode == _Mode.client)
        Positioned(
            bottom: 8,
            left: 8,
            child: _netBadge(
                c,
                '远程·P${(_mySlot >= 0 && _mySlot < _n) ? _mySlot + 1 : '-'}')),
      if (_phase != 1)
        Positioned.fill(
          child: _Overlay(
            c: c,
            isLight: isLight,
            phase: _phase,
            mode: _mode,
            winner: over ? _winner : -1,
            n: _n,
            onStart: _start,
            onResume: _togglePause,
            onClose: _close,
          ),
        ),
    ]);
  }

  Widget _netBadge(AppColors c, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (c.isLight ? Colors.white : kDarkBg).withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.chipBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi, size: 13, color: const Color(0xFF27AE60)),
          const SizedBox(width: 4),
          Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c.textSecondary)),
        ]),
      );

  List<_RenderSnake> _tsnakes() => [
        for (var i = 0; i < _n; i++)
          _RenderSnake(
            xs: _snakes[i].xs,
            ys: _snakes[i].ys,
            prevXs: _snakes[i].prevXs,
            prevYs: _snakes[i].prevYs,
            dx: _snakes[i].dx,
            dy: _snakes[i].dy,
            alive: _snakes[i].alive,
            color: _palettes[widget.config.slots[i].color % _palettes.length],
            skin: _Skin.values[widget.config.slots[i].skin % _Skin.values.length],
          ),
      ];

  List<_RenderSnake> _clientSnakes() => [
        for (var i = 0; i < _cxs.length; i++)
          _RenderSnake(
            xs: _cxs[i],
            ys: _cys[i],
            prevXs: _cxs[i],
            prevYs: _cys[i],
            dx: 1,
            dy: 0,
            alive: i < _calive.length ? _calive[i] : false,
            color: _palettes[widget.config.slots[i].color % _palettes.length],
            skin: _Skin.values[widget.config.slots[i].skin % _Skin.values.length],
          ),
      ];

  Widget _toolbar(AppColors c, bool isLight) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 4),
      child: Row(children: [
        IconButton(
          onPressed: _close,
          icon: Icon(Icons.arrow_back_rounded, color: c.textSecondary),
          tooltip: '返回',
        ),
        Text(_mode == _Mode.client
            ? '贪吃蛇多人-联机'
            : (_mode == _Mode.host ? '贪吃蛇多人-房间' : '贪吃蛇多人'),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
        const Spacer(),
        if (_mode != _Mode.client)
          TextButton.icon(
            onPressed: _togglePause,
            icon: Icon(_phase == 2 ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 17),
            label: Text(_phase == 2 ? '继续' : '暂停'),
          ),
        IconButton(
          onPressed: _start,
          icon: Icon(Icons.replay_rounded, color: c.textSecondary),
          tooltip: '重新开始',
        ),
      ]),
    );
  }
}

// ============================ 渲染输入 ============================

class _RenderSnake {
  final List<int> xs, ys, prevXs, prevYs;
  final bool alive;
  final _Palette color;
  final _Skin skin;
  final int dx, dy;
  _RenderSnake({
    required this.xs,
    required this.ys,
    required this.prevXs,
    required this.prevYs,
    required this.alive,
    required this.color,
    required this.skin,
    this.dx = 1,
    this.dy = 0,
  });
}

// ============================ 棋盘绘制 ============================

class _MultiPainter extends CustomPainter {
  final List<_RenderSnake> snakes;
  final List<(int, int)> food;
  final (int, int)? bonus;
  final int animMs;
  final bool playing;
  final double cw, ch, interpP;
  final int cols, rows;
  final bool isLight;
  _MultiPainter({
    required this.snakes,
    required this.food,
    required this.bonus,
    required this.animMs,
    required this.playing,
    required this.cw,
    required this.ch,
    required this.cols,
    required this.rows,
    required this.interpP,
    required this.isLight,
  });

  Offset _px(num x, num y) => Offset(x * cw + cw / 2, y * ch + ch / 2);

  Offset _pos(_RenderSnake s, int i) {
    final cx = s.xs[i], cy = s.ys[i];
    final hasPrev = i < s.prevXs.length;
    final px = hasPrev ? s.prevXs[i] : cx;
    final py = hasPrev ? s.prevYs[i] : cy;
    final t = interpP;
    return _px(px + (cx - px) * t, py + (cy - py) * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF9AA0A6)
          .withValues(alpha: isLight ? 0.30 : 0.22);
    for (var i = 1; i < cols; i++) {
      canvas.drawLine(Offset(i * cw, 0), Offset(i * cw, size.height), grid);
    }
    for (var j = 1; j < rows; j++) {
      canvas.drawLine(Offset(0, j * ch), Offset(size.width, j * ch), grid);
    }
    _paintFood(canvas);
    for (final s in snakes) {
      _paintSnake(canvas, s);
    }
  }

  void _paintFood(Canvas canvas) {
    final base = math.min(cw, ch);
    final ph = playing
        ? (math.sin(animMs * math.pi / 90000) * 0.5 + 0.5)
        : 0.5;
    const col = Color(0xFFE74C3C);
    for (final f in food) {
      final c = _px(f.$1, f.$2);
      canvas.drawCircle(
          c, base * (0.30 + 0.10 * ph),
          Paint()
            ..color = col.withValues(alpha: 0.30)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawCircle(c, base * (0.21 + 0.05 * ph), Paint()..color = col);
    }
    // 黄球道具（脉冲+星形描边）
    final b = bonus;
    if (b != null) {
      final c = _px(b.$1, b.$2);
      final pulse = (math.sin(animMs * math.pi / 60000) * 0.5 + 0.5);
      const col2 = Color(0xFFF1C40F);
      canvas.drawCircle(
          c, base * (0.45 + 0.15 * pulse),
          Paint()
            ..color = col2.withValues(alpha: 0.40)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(c, base * (0.30 + 0.06 * pulse),
          Paint()..color = col2);
      // 内部亮点
      canvas.drawCircle(
          c, base * 0.10, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
  }

  void _paintSnake(Canvas canvas, _RenderSnake s) {
    if (!s.alive || s.xs.isEmpty) return;
    final bodyW = math.min(cw, ch) * 0.62;
    final path = Path();
    final tail = _pos(s, s.xs.length - 1);
    path.moveTo(tail.dx, tail.dy);
    for (var i = s.xs.length - 2; i >= 0; i--) {
      final pt = _pos(s, i);
      path.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = bodyW
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = s.color.body);
    // 皮肤装饰
    if (s.skin == _Skin.striped || s.skin == _Skin.dotted) {
      _decorate(canvas, s, bodyW);
    }
    // 头像
    final head = _pos(s, 0);
    final headR = math.min(cw, ch) * 0.44;
    canvas.drawCircle(head, headR, Paint()..color = s.color.accent);
    if (s.skin == _Skin.glow) {
      canvas.drawCircle(
          head,
          headR + 2.5,
          Paint()
            ..color = s.color.accent.withValues(alpha: 0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }
    // 眼睛
    final len = math.sqrt(s.dx * s.dx + s.dy * s.dy);
    final d = len > 0 ? Offset(s.dx / len, s.dy / len) : const Offset(1, 0);
    final n = Offset(-d.dy, d.dx);
    final eyeWhite = isLight ? Colors.white : const Color(0xFFF5F5F5);
    for (final side in [1.0, -1.0]) {
      final ctr = head + n * (headR * 0.45) * side + d * (headR * 0.4);
      canvas.drawCircle(ctr, headR * 0.30, Paint()..color = eyeWhite);
      canvas.drawCircle(ctr + d * (headR * 0.13), headR * 0.16,
          Paint()..color = const Color(0xFF17201A));
    }
  }

  void _decorate(Canvas canvas, _RenderSnake s, double bodyW) {
    if (s.skin == _Skin.dotted) {
      for (var i = 0; i < s.xs.length; i += 2) {
        if (i == 0) continue;
        canvas.drawCircle(_pos(s, i), bodyW * 0.16,
            Paint()..color = Colors.white.withValues(alpha: 0.6));
      }
    } else if (s.skin == _Skin.striped) {
      for (var i = 0; i < s.xs.length; i += 3) {
        if (i == 0) continue;
        canvas.drawCircle(_pos(s, i), bodyW * 0.20,
            Paint()..color = Colors.black.withValues(alpha: 0.15));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MultiPainter old) => true;
}

// ============================ 中央叠层 ============================

class _Overlay extends StatelessWidget {
  final AppColors c;
  final bool isLight;
  final int phase; // 0 idle,1 playing,2 paused,3 over
  final _Mode mode;
  final int winner;
  final int n;
  final VoidCallback onStart;
  final VoidCallback onResume;
  final VoidCallback onClose;
  const _Overlay({
    required this.c,
    required this.isLight,
    required this.phase,
    required this.mode,
    required this.winner,
    required this.n,
    required this.onStart,
    required this.onResume,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final bool over = phase == 3;
    final bool paused = phase == 2;
    final String title;
    final String sub;
    if (over) {
      title = '游戏结束';
      sub = winner >= 0
          ? 'P${winner + 1} 活到了最后，赢得胜利！'
          : '没有幸存者';
    } else if (paused) {
      title = '已暂停';
      sub = '空格继续';
    } else {
      title = '贪吃蛇多人';
      sub = '活到最后者胜 · 死亡后全场加速 · '
          'P1:WASD / P2:方向键 / P3:U J H K';
    }
    return Container(
      color: isLight
          ? Colors.white.withValues(alpha: 0.72)
          : kDarkBg.withValues(alpha: 0.82),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined, size: 40, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: c.text)),
            const SizedBox(height: 6),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: c.textTertiary)),
            const SizedBox(height: 20),
            if (!over && !paused)
              ElevatedButton.icon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始游戏'),
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isLight ? const Color(0xFF34C759) : const Color(0xFF2ECC71),
                    foregroundColor: Colors.white),
              )
            else if (paused)
              ElevatedButton.icon(
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('继续'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2ECC71), foregroundColor: Colors.white),
              )
            else
              Row(mainAxisSize: MainAxisSize.min, children: [
                ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('再来一局'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isLight ? const Color(0xFF34C759) : const Color(0xFF2ECC71),
                      foregroundColor: Colors.white),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                    onPressed: onClose,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回')),
              ]),
            if (mode == _Mode.host)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text('正在监听 43210 端口，等待玩家加入…',
                    style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================ 帧率波形图（已移除：改为棋盘内纯数字 FPS 显示） ============================
