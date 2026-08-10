/// 暴力工具音效服务：一比一复刻参考项目 audio.js 的振荡器音效。
///
/// 参考项目用 Web Audio OscillatorNode 合成音调，参数如下：
/// - playWheelTick: 1200Hz sine 0.02s 音量0.03（转盘转动每格）
/// - playTick:      800Hz  sine 0.05s 音量0.05（随机数开始）
/// - playDing/playNumberDing: 440Hz sine 0.15s 音量0.08，延迟120ms后 554Hz sine 0.2s 音量0.06
/// 包络为指数衰减到 0.01。
///
/// 这里将正弦波合成为 16bit PCM WAV 字节流，用 audioplayers 播放，
/// 听感与参考项目一致，且无需额外音频资源文件。
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class ToolsAudio {
  ToolsAudio._();
  static final ToolsAudio instance = ToolsAudio._();

  static const int _sampleRate = 22050;
  final AudioPlayer _player = AudioPlayer();

  // 缓存已合成的 WAV 字节，避免重复合成
  Uint8List? _wheelTickWav;
  Uint8List? _tickWav;
  Uint8List? _dingWav;

  /// 合成单个正弦音 WAV（指数衰减包络，对齐 audio.js 的 exponentialRamp）
  static Uint8List _toneWav({
    required double freq,
    required double duration,
    required double volume,
  }) {
    final n = (_sampleRate * duration).round();
    final samples = Int16List(n);
    for (var i = 0; i < n; i++) {
      final t = i / _sampleRate;
      // 指数衰减：volume → 0.01（对齐 exponentialRampToValueAtTime(0.01)）
      final env = volume * math.pow(0.01 / volume, t / duration);
      final v = math.sin(2 * math.pi * freq * t) * env;
      samples[i] = (v * 32767).round().clamp(-32768, 32767);
    }
    return _wavBytes(samples);
  }

  /// 两段音（间隔 delay 秒）合成一个 WAV（对应 playDing 的 440→554Hz）
  static Uint8List _twoToneWav({
    required double freq1,
    required double dur1,
    required double vol1,
    required double freq2,
    required double dur2,
    required double vol2,
    required double delay,
  }) {
    final n1 = (_sampleRate * dur1).round();
    final gap = (_sampleRate * delay).round();
    final n2 = (_sampleRate * dur2).round();
    final total = n1 + gap + n2;
    final samples = Int16List(total);
    for (var i = 0; i < n1; i++) {
      final t = i / _sampleRate;
      final env = vol1 * math.pow(0.01 / vol1, t / dur1);
      samples[i] = (math.sin(2 * math.pi * freq1 * t) * env * 32767)
          .round()
          .clamp(-32768, 32767);
    }
    for (var i = 0; i < n2; i++) {
      final t = i / _sampleRate;
      final env = vol2 * math.pow(0.01 / vol2, t / dur2);
      samples[n1 + gap + i] = (math.sin(2 * math.pi * freq2 * t) * env * 32767)
          .round()
          .clamp(-32768, 32767);
    }
    return _wavBytes(samples);
  }

  /// 构造最小 WAV 文件头 + PCM 数据
  static Uint8List _wavBytes(Int16List samples) {
    final dataSize = samples.length * 2;
    final bd = ByteData(44 + dataSize);
    // RIFF header
    bd.setUint8(0, 0x52); // R
    bd.setUint8(1, 0x49); // I
    bd.setUint8(2, 0x46); // F
    bd.setUint8(3, 0x46); // F
    bd.setUint32(4, 36 + dataSize, Endian.little);
    bd.setUint8(8, 0x57); // W
    bd.setUint8(9, 0x41); // A
    bd.setUint8(10, 0x56); // V
    bd.setUint8(11, 0x45); // E
    // fmt chunk
    bd.setUint8(12, 0x66); // f
    bd.setUint8(13, 0x6D); // m
    bd.setUint8(14, 0x74); // t
    bd.setUint8(15, 0x20); // ' '
    bd.setUint32(16, 16, Endian.little); // fmt chunk size
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, 1, Endian.little); // mono
    bd.setUint32(24, _sampleRate, Endian.little);
    bd.setUint32(28, _sampleRate * 2, Endian.little); // byte rate
    bd.setUint16(32, 2, Endian.little); // block align
    bd.setUint16(34, 16, Endian.little); // bits per sample
    // data chunk
    bd.setUint8(36, 0x64); // d
    bd.setUint8(37, 0x61); // a
    bd.setUint8(38, 0x74); // t
    bd.setUint8(39, 0x61); // a
    bd.setUint32(40, dataSize, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      bd.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bd.buffer.asUint8List();
  }

  Future<void> _play(Uint8List wav) async {
    try {
      await _player.stop();
      await _player.play(BytesSource(wav));
    } catch (_) {
      // 音频失败不影响功能
    }
  }

  /// 转盘转动每格（1200Hz 0.02s）
  Future<void> playWheelTick() async {
    _wheelTickWav ??= _toneWav(freq: 1200, duration: 0.02, volume: 0.03);
    await _play(_wheelTickWav!);
  }

  /// 随机数开始（800Hz 0.05s）
  Future<void> playTick() async {
    _tickWav ??= _toneWav(freq: 800, duration: 0.05, volume: 0.05);
    await _play(_tickWav!);
  }

  /// 转盘停止 / 随机数定格（440→554Hz 双音）
  Future<void> playDing() async {
    _dingWav ??= _twoToneWav(
      freq1: 440,
      dur1: 0.15,
      vol1: 0.08,
      freq2: 554,
      dur2: 0.2,
      vol2: 0.06,
      delay: 0.12,
    );
    await _play(_dingWav!);
  }

  /// 炸弹爆炸音（参考项目 playThud 与 playDing 相同：440→554Hz 双音）
  Future<void> playThud() => playDing();

  /// 数字定格音（参考项目 playNumberDing 与 playDing 相同：440→554Hz 双音）
  Future<void> playNumberDing() => playDing();
}
