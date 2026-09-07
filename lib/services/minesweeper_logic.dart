/// 扫雷游戏逻辑 —— C++ 逻辑库的 Dart FFI 绑定。
/// 逻辑（布雷/翻开/标记/和弦/胜负/计时）全部在 C++（minesweeper_logic）中实现，
/// Dart 仅通过本文件驱动逻辑并批量拷贝格子状态用于渲染。
library;

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 格子状态枚举值（与 C++ 侧 ms_copy_state 输出一致）
abstract final class MsCell {
  static const int hidden = 0;
  static const int revealed = 1;
  static const int flagged = 2;
  static const int question = 3;
}

/// 扫雷 C++ 逻辑库封装。用法：
/// ```dart
/// final game = MinesweeperLogic(9, 9, 10);
/// game.reveal(idx);
/// game.states; // Int32List 视图，painter 直接读
/// game.dispose();
/// ```
class MinesweeperLogic {
  static DynamicLibrary? _lib;

  static DynamicLibrary _open() {
    if (_lib != null) return _lib!;
    if (kIsWeb) throw const MsLoadException('Web 端不支持 C++ 逻辑库');
    if (Platform.isWindows) {
      _lib = DynamicLibrary.open('minesweeper_logic.dll');
    } else if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libminesweeper_logic.so');
    } else if (Platform.isLinux) {
      _lib = DynamicLibrary.open('libminesweeper_logic.so');
    } else {
      throw const MsLoadException('当前平台不支持 C++ 逻辑库');
    }
    return _lib!;
  }

  Pointer<Void> _handle = nullptr;
  int _rows;
  int _cols;
  int _mines;
  bool _disposed = false;

  late final Pointer<Int32> _stateBuf;
  late final Pointer<Int32> _adjBuf;
  late final Pointer<Int32> _mineBuf;
  late final Int32List _states;
  late final Int32List _adjs;
  late final Int32List _minesView;

  int get cells => _rows * _cols;

  MinesweeperLogic(this._rows, this._cols, this._mines) {
    final create = _open()
        .lookupFunction<Pointer<Void> Function(Int32, Int32, Int32),
            Pointer<Void> Function(int, int, int)>('ms_create');
    _handle = create(_rows, _cols, _mines);
    if (_handle == nullptr) {
      throw const MsLoadException('扫雷逻辑库初始化失败');
    }
    _allocBuffers();
  }

  void _allocBuffers() {
    final n = _rows * _cols;
    _stateBuf = malloc.allocate<Int32>(n * sizeOf<Int32>());
    _adjBuf = malloc.allocate<Int32>(n * sizeOf<Int32>());
    _mineBuf = malloc.allocate<Int32>(n * sizeOf<Int32>());
    _states = _stateBuf.asTypedList(n);
    _adjs = _adjBuf.asTypedList(n);
    _minesView = _mineBuf.asTypedList(n);
  }

  void _freeBuffers() {
    malloc.free(_stateBuf);
    malloc.free(_adjBuf);
    malloc.free(_mineBuf);
  }

  // ===== 函数绑定 =====
  late final _revealFn = _open()
      .lookupFunction<Void Function(Pointer<Void>, Int32), void Function(Pointer<Void>, int)>('ms_reveal');
  late final _toggleFn = _open()
      .lookupFunction<Void Function(Pointer<Void>, Int32), void Function(Pointer<Void>, int)>('ms_toggle_mark');
  late final _chordFn = _open()
      .lookupFunction<Void Function(Pointer<Void>, Int32), void Function(Pointer<Void>, int)>('ms_chord');
  late final _tickFn =
      _open().lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('ms_tick');
  late final _resetFn =
      _open().lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('ms_reset');
  late final _secondsFn =
      _open().lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('ms_seconds');
  late final _remainFn =
      _open().lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('ms_remain');
  late final _overFn =
      _open().lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('ms_over');
  late final _wonFn =
      _open().lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('ms_won');
  late final _startedFn =
      _open().lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('ms_started');
  late final _boomFn =
      _open().lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('ms_boom');
  late final _copyStateFn = _open()
      .lookupFunction<Void Function(Pointer<Void>, Pointer<Int32>), void Function(Pointer<Void>, Pointer<Int32>)>(
          'ms_copy_state');
  late final _copyAdjFn = _open()
      .lookupFunction<Void Function(Pointer<Void>, Pointer<Int32>), void Function(Pointer<Void>, Pointer<Int32>)>(
          'ms_copy_adj');
  late final _copyMineFn = _open()
      .lookupFunction<Void Function(Pointer<Void>, Pointer<Int32>), void Function(Pointer<Void>, Pointer<Int32>)>(
          'ms_copy_mine');
  late final _destroyFn =
      _open().lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('ms_destroy');

  // ===== 公开 API =====

  /// 格子状态视图（每次交互后调 sync() 刷新）
  Int32List get states => _states;
  Int32List get adjs => _adjs;
  Int32List get minesView => _minesView;

  int get seconds => _disposed ? 0 : _secondsFn(_handle);
  int get remain => _disposed ? 0 : _remainFn(_handle);
  bool get over => _disposed || _overFn(_handle) != 0;
  bool get won => !_disposed && _wonFn(_handle) != 0;
  bool get started => !_disposed && _startedFn(_handle) != 0;
  int get boom => _disposed ? -1 : _boomFn(_handle);

  void reveal(int idx) {
    if (!_disposed) _revealFn(_handle, idx);
  }

  void toggleMark(int idx) {
    if (!_disposed) _toggleFn(_handle, idx);
  }

  void chord(int idx) {
    if (!_disposed) _chordFn(_handle, idx);
  }

  /// 计时 +1s（Dart 每秒调用）
  void tick() {
    if (!_disposed) _tickFn(_handle);
  }

  /// 重置为同尺寸新局
  void reset() {
    if (!_disposed) _resetFn(_handle);
  }

  /// 改尺寸并重开
  void resize(int rows, int cols, int mines) {
    if (_disposed) return;
    _destroyFn(_handle);
    _freeBuffers();
    _rows = rows;
    _cols = cols;
    _mines = mines;
    _handle = _open()
        .lookupFunction<Pointer<Void> Function(Int32, Int32, Int32), Pointer<Void> Function(int, int, int)>(
            'ms_create')(rows, cols, mines);
    _allocBuffers();
  }

  /// 交互/计时后调用：把 C++ 侧状态批量拷贝到 Dart 视图
  void sync() {
    if (_disposed) return;
    _copyStateFn(_handle, _stateBuf);
    _copyAdjFn(_handle, _adjBuf);
    _copyMineFn(_handle, _mineBuf);
  }

  void dispose() {
    if (_disposed) return;
    _destroyFn(_handle);
    _freeBuffers();
    _disposed = true;
  }
}

class MsLoadException implements Exception {
  final String message;
  const MsLoadException(this.message);
  @override
  String toString() => message;
}
