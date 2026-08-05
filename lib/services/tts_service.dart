/// TTS 发音服务：基于 flutter_tts（Windows 走系统 SAPI/UWP 语音）
library;

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  FlutterTts? _tts;
  Future<void>? _initFuture;
  bool _available = false;

  /// 系统是否具备可用的英语语音（无英文语音包时为 false，UI 据此隐藏发音按钮）
  bool get available => _available;

  /// 初始化（幂等）。全程容错：任何异常都降级为不可用。
  /// 缓存 Future：并发调用会等待同一个初始化流程完成后再返回。
  Future<void> init() => _initFuture ??= _initCore();

  Future<void> _initCore() async {
    try {
      final tts = FlutterTts();
      // 注意：flutter_tts 在 Windows 不支持 isLanguageAvailable，不要调用
      await tts.setLanguage('en-US');
      await tts.setSpeechRate(0.45);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      // 尝试挑选 en-US / en-GB 语音（部分平台无 getVoices/setVoice，容错处理）
      try {
        final voices = await tts.getVoices;
        if (voices is List && voices.isNotEmpty) {
          Map<String, String>? fallback;
          Map<String, String>? preferred;
          for (final v in voices) {
            if (v is! Map) continue;
            final m = v.map((k, val) => MapEntry(k.toString(), val.toString()));
            final locale = (m['locale'] ?? m['language'] ?? '').toLowerCase();
            if (!locale.startsWith('en')) continue;
            fallback ??= m;
            if (locale.startsWith('en-us') || locale.startsWith('en_us')) {
              preferred = m;
              break;
            }
            preferred ??= (locale.startsWith('en-gb') || locale.startsWith('en_gb')) ? m : preferred;
          }
          final pick = preferred ?? fallback;
          if (pick != null) {
            try {
              // setVoice 仅 Android/iOS/macOS 支持，Windows 上会抛异常，安全降级
              await tts.setVoice(pick);
            } catch (_) {}
          }
        }
      } catch (_) {
        // getVoices 在部分平台不可用，忽略即可
      }
      _tts = tts;
      _available = true;
    } catch (_) {
      _tts = null;
      _available = false;
    }
  }

  /// 朗读单词（先停止上一次朗读）
  Future<void> speakWord(String word) async {
    await init();
    final tts = _tts;
    final w = word.trim();
    if (tts == null || !_available || w.isEmpty) return;
    try {
      await tts.stop();
      // Windows 插件的 speak 在上一句尚未完全停止时会返回 0，重试几次
      for (var attempt = 0; attempt < 4; attempt++) {
        final r = await tts.speak(w);
        final ok = (r == null || r == 1 || r == true);
        if (ok) return;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    } catch (_) {}
  }

  /// 朗读完整句子（先停止上一次朗读）
  Future<void> speakText(String text) async {
    await init();
    final tts = _tts;
    final t = text.trim();
    if (tts == null || !_available || t.isEmpty) return;
    try {
      await tts.stop();
      for (var attempt = 0; attempt < 4; attempt++) {
        final r = await tts.speak(t);
        final ok = (r == null || r == 1 || r == true);
        if (ok) return;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    } catch (_) {}
  }

  /// 停止朗读
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
