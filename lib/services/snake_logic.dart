/// 贪吃蛇游戏逻辑 —— C++ 逻辑库的 Dart FFI 绑定。
/// 逻辑（方向队列/碰撞/得分/速度）全部在 C++（snake_logic）中实现，
/// Dart 仅通过本文件驱动逻辑并读取状态快照用于渲染。
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// C++ 侧状态快照结构体（字段顺序与 snake_logic.h 的 SnakeSnapshot 一致）。
///
/// 布局说明：moveProgress(@Float) 与 tickMs(@Double) 之间，Dart FFI 与
/// C++（默认 ABI 对齐）都会插入相同的 4 字节填充，两侧一致，无需手动
/// 保留字段——勿改动字段顺序/类型。
final class SnakeSnapshot extends Struct {
  @Int32()
  external int score;

  @Int32()
  external int highScore;

  @Int32()
  external int playing;

  @Int32()
  external int paused;

  @Int32()
  external int over;

  @Int32()
  external int snakeLen;

  @Int32()
  external int dirX;

  @Int32()
  external int dirY;

  @Int32()
  external int foodX;

  @Int32()
  external int foodY;

  @Float()
  external double moveProgress;

  @Double()
  external double tickMs;

  @Int32()
  external int invincible;
}

/// C++ 逻辑库句柄
class SnakeLogic {
  /// 加载动态库：Android → libsnake_logic.so；Windows → snake_logic.dll
  static final DynamicLibrary _lib = _loadLibrary();

  static DynamicLibrary _loadLibrary() {
    if (kIsWeb) {
      throw UnsupportedError('SnakeLogic is not supported on web');
    }
    if (Platform.isAndroid) return DynamicLibrary.open('libsnake_logic.so');
    if (Platform.isWindows) return DynamicLibrary.open('snake_logic.dll');
    if (Platform.isLinux) return DynamicLibrary.open('libsnake_logic.so');
    if (Platform.isMacOS) return DynamicLibrary.open('libsnake_logic.dylib');
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  late final void Function(Pointer<Void>) _destroy;
  late final void Function(Pointer<Void>) _start;
  late final void Function(Pointer<Void>) _revive;
  late final void Function(Pointer<Void>) _togglePause;
  late final void Function(Pointer<Void>, int, int) _turn;
  late final void Function(Pointer<Void>, double) _advance;
  late final void Function(Pointer<Void>, Pointer<SnakeSnapshot>) _snapshot;
  late final Pointer<Int32> Function(Pointer<Void>) _curX;
  late final Pointer<Int32> Function(Pointer<Void>) _curY;
  late final Pointer<Int32> Function(Pointer<Void>) _prevX;
  late final Pointer<Int32> Function(Pointer<Void>) _prevY;
  late final void Function(Pointer<Void>, int) _setHighScore;

  final Pointer<Void> _state;
  final Pointer<SnakeSnapshot> _snapPtr;

  /// 构造并创建 C++ 游戏状态
  SnakeLogic(int highScore)
      : _state = _lib.lookupFunction<
                Pointer<Void> Function(Int32),
                Pointer<Void> Function(int)>('snake_create')(highScore),
        _snapPtr = calloc<SnakeSnapshot>() {
    _destroy = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('snake_destroy');
    _start = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('snake_start');
    _revive = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('snake_revive');
    _togglePause = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('snake_toggle_pause');
    _turn = _lib.lookupFunction<Void Function(Pointer<Void>, Int32, Int32),
        void Function(Pointer<Void>, int, int)>('snake_turn');
    _advance = _lib.lookupFunction<Void Function(Pointer<Void>, Double),
        void Function(Pointer<Void>, double)>('snake_advance');
    _snapshot = _lib.lookupFunction<
        Void Function(Pointer<Void>, Pointer<SnakeSnapshot>),
        void Function(Pointer<Void>, Pointer<SnakeSnapshot>)>('snake_snapshot');
    _curX = _lib.lookupFunction<Pointer<Int32> Function(Pointer<Void>),
        Pointer<Int32> Function(Pointer<Void>)>('snake_snake_cur_x');
    _curY = _lib.lookupFunction<Pointer<Int32> Function(Pointer<Void>),
        Pointer<Int32> Function(Pointer<Void>)>('snake_snake_cur_y');
    _prevX = _lib.lookupFunction<Pointer<Int32> Function(Pointer<Void>),
        Pointer<Int32> Function(Pointer<Void>)>('snake_snake_prev_x');
    _prevY = _lib.lookupFunction<Pointer<Int32> Function(Pointer<Void>),
        Pointer<Int32> Function(Pointer<Void>)>('snake_snake_prev_y');
    _setHighScore = _lib.lookupFunction<Void Function(Pointer<Void>, Int32),
        void Function(Pointer<Void>, int)>('snake_set_high_score');
  }

  /// 重新开始
  void start() => _start(_state);

  /// 复活（原地复活，短暂无敌）
  void revive() => _revive(_state);

  /// 暂停/继续
  void togglePause() => _togglePause(_state);

  /// 转向
  void turn(int dx, int dy) => _turn(_state, dx, dy);

  /// 前进逻辑时间（毫秒）
  void advance(double dtMs) => _advance(_state, dtMs);

  /// 读取状态快照
  SnakeSnapshot snapshot() {
    _snapshot(_state, _snapPtr);
    return _snapPtr.ref;
  }

  /// 蛇身坐标（头在 0）。返回 (curX, curY, prevX, prevY) 四组列表。
  ///
  /// 安全说明：C++ 侧数组容量为 SNAKE_MAX_LEN(=COLS*ROWS=400)，且指针在
  /// 下一次 advance/turn/dispose 后可能失效。这里对 n 做容量钳制并
  /// **立即拷贝**到 Dart 自有内存，杜绝 asTypedList 零拷贝视图带来的
  /// 越界读与 use-after-free 风险。
  (List<int>, List<int>, List<int>, List<int>) snakePos(int len) {
    if (_disposed) return (<int>[], <int>[], <int>[], <int>[]);
    final cx = _curX(_state);
    final cy = _curY(_state);
    final px = _prevX(_state);
    final py = _prevY(_state);
    if (cx == nullptr || cy == nullptr || px == nullptr || py == nullptr) {
      return (<int>[], <int>[], <int>[], <int>[]);
    }
    // 权威长度：以 C++ 快照中的 snake_len 为准，并与传入值、数组容量取最小
    _snapshot(_state, _snapPtr);
    final cap = _snapPtr.ref.snakeLen;
    var n = len < 0 ? 0 : len;
    if (n > cap) n = cap;
    if (n > _maxLen) n = _maxLen;
    // 拷贝为 Dart 自有列表（asTypedList 仅是 C++ 内存的临时视图，不可跨帧持有）
    return (
      cx.asTypedList(_maxLen).sublist(0, n),
      cy.asTypedList(_maxLen).sublist(0, n),
      px.asTypedList(_maxLen).sublist(0, n),
      py.asTypedList(_maxLen).sublist(0, n),
    );
  }

  /// C++ 侧坐标数组容量（SNAKE_MAX_LEN = COLS*ROWS = 400）
  static const int _maxLen = 20 * 20;

  /// 回写最高分（Dart 持久化后同步给 C++）
  void setHighScore(int hs) => _setHighScore(_state, hs);

  /// 释放 C++ 状态（幂等：重复调用安全返回）
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_state);
    calloc.free(_snapPtr);
  }
}
