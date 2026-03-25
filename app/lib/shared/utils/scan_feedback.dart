import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class ScanFeedback {
  static final AudioPlayer _player = AudioPlayer();
  static Uint8List? _beepBytes;

  static Future<void> trigger({
    required bool sound,
    required bool vibration,
  }) async {
    if (vibration) {
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 80));
      HapticFeedback.heavyImpact();
    }
    if (sound) {
      _beepBytes ??= _buildBeepWav();
      try {
        await _player.play(BytesSource(_beepBytes!));
      } catch (_) {}
    }
  }

  // 880Hz 사인파 150ms WAV 생성 (외부 파일 없이)
  static Uint8List _buildBeepWav() {
    const sampleRate = 44100;
    const frequency = 880;
    const numSamples = sampleRate * 150 ~/ 1000;
    const dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);

    void setStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    setStr(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    setStr(8, 'WAVE');
    setStr(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    setStr(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final fade = 1.0 - i / numSamples;
      final sample =
          (sin(2 * pi * frequency * t) * 16000 * fade).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }
}
