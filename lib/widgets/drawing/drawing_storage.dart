/// 画板持久化：直接基于 shared_preferences，键名带 drawing_ 前缀对齐参考项目
///
/// 不使用现有 Storage 的私有 _get/_set（避免改动既有文件），直接持有
/// SharedPreferences 实例，并在需要时惰性获取。
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'drawing_models.dart';

class DrawingStorage {
  static SharedPreferences? _p;

  /// 惰性获取实例（容错：失败时返回 null，画板仍可进入，仅不持久化）
  static Future<SharedPreferences?> _get() async {
    if (_p != null) return _p;
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      _p = null;
    }
    return _p;
  }

  /// 显式初始化（进入画板模块时调用一次，保证后续同步读取有数据）
  static Future<void> init() async {
    await _get();
  }

  static String? getString(String key) {
    try {
      return _p?.getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setString(String key, String value) async {
    final p = await _get();
    try {
      await p?.setString(key, value);
    } catch (_) {}
  }

  static Future<void> _ensureInit() async {
    await _get();
  }

  // ===== 当前画布会话 =====
  static String? loadSessionCanvas() => getString('drawingCanvas');

  static Future<void> saveSessionCanvas(String? dataUrl) async {
    await _ensureInit();
    await setString('drawingCanvas', dataUrl ?? '');
  }

  static String? loadSessionCanvasWidth() => getString('drawingCanvasWidth');
  static Future<void> saveSessionCanvasWidth(int w) async {
    await _ensureInit();
    await setString('drawingCanvasWidth', '$w');
  }

  static String? loadSessionCanvasHeight() => getString('drawingCanvasHeight');
  static Future<void> saveSessionCanvasHeight(int h) async {
    await _ensureInit();
    await setString('drawingCanvasHeight', '$h');
  }

  static String? loadSessionLayers() => getString('drawingLayers');
  static Future<void> saveSessionLayers(String? json) async {
    await _ensureInit();
    await setString('drawingLayers', json ?? '');
  }

  // ===== 画作列表 =====
  static List<DrawingArtwork> loadArtworks() {
    final s = getString('drawing_artworks');
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => DrawingArtwork.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveArtworks(List<DrawingArtwork> list) async {
    await _ensureInit();
    await setString(
        'drawing_artworks', jsonEncode(list.map((e) => e.toJson()).toList()));
  }

  // ===== 手动保存 =====
  static List<DrawingArtwork> loadSavedCanvases() {
    final s = getString('drawing_saved_canvases');
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => _savedFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSavedCanvases(List<DrawingArtwork> list) async {
    await _ensureInit();
    await setString('drawing_saved_canvases',
        jsonEncode(list.map((e) => _savedToJson(e)).toList()));
  }

  // ===== 自动保存历史 =====
  static List<DrawingArtwork> loadAutoSaveHistory() {
    final s = getString('drawing_autosave_history');
    if (s == null || s.isEmpty) return [];
    try {
      return (jsonDecode(s) as List)
          .map((e) => _savedFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAutoSaveHistory(List<DrawingArtwork> list) async {
    await _ensureInit();
    await setString('drawing_autosave_history',
        jsonEncode(list.map((e) => _savedToJson(e)).toList()));
  }

  // ===== 用户设置 =====
  static bool loadDarkMode() => getString('drawing_dark_mode') == 'true';
  static Future<void> saveDarkMode(bool v) async {
    await _setStr('drawing_dark_mode', '$v');
  }

  static bool loadPressureMode() =>
      getString('drawing_pressure_mode') == 'true';
  static Future<void> savePressureMode(bool v) async {
    await _setStr('drawing_pressure_mode', '$v');
  }

  static bool loadTwoFingerUndo() =>
      getString('drawing_two_finger_undo') == 'true';
  static Future<void> saveTwoFingerUndo(bool v) async {
    await _setStr('drawing_two_finger_undo', '$v');
  }

  static bool loadOnionSkin() => getString('drawingOnionSkin') == 'true';
  static Future<void> saveOnionSkin(bool v) async {
    await _setStr('drawingOnionSkin', '$v');
  }

  static OnionSkinSettings loadOnionSkinSettings() {
    final s = getString('drawingOnionSkinSettings');
    if (s == null || s.isEmpty) return OnionSkinSettings();
    try {
      return OnionSkinSettings.fromJson(
          jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return OnionSkinSettings();
    }
  }

  static Future<void> saveOnionSkinSettings(OnionSkinSettings s) async {
    await _ensureInit();
    await setString('drawingOnionSkinSettings', jsonEncode(s.toJson()));
  }

  static Future<void> _setStr(String key, String v) async {
    await _ensureInit();
    try {
      await _p?.setString(key, v);
    } catch (_) {}
  }

  // ===== 内部工具方法 =====
  static Map<String, dynamic> _savedToJson(DrawingArtwork a) => {
        'name': a.name,
        'data': a.dataUrl,
        'thumb': a.thumbnail,
        'time': a.date,
        'timestamp': a.timestamp,
        'w': a.w,
        'h': a.h,
      };

  static DrawingArtwork _savedFromJson(Map<String, dynamic> j) => DrawingArtwork(
        id: 'saved_${(j['time'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString()}',
        name: (j['name'] as String?) ?? '画作',
        w: (j['w'] as num?)?.toInt() ?? 0,
        h: (j['h'] as num?)?.toInt() ?? 0,
        dataUrl: (j['data'] as String?),
        thumbnail: (j['thumb'] as String?),
        date: (j['time'] as String?) ?? '',
        timestamp: (j['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
        isSaved: true,
      );
}