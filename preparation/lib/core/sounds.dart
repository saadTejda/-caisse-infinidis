import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';

/// Sons de scan fabriqués à la volée (aucun fichier audio) + vibration.
class Sounds {
  Sounds._();

  static final _player = AudioPlayer();
  static final Map<String, Uint8List> _cache = {};

  /// Notes : [fréquence Hz, durée ms].
  static const _patterns = {
    'ok': [[1046, 90], [1568, 140]],
    'done': [[1046, 90], [1318, 90], [1568, 200]],
    'info': [[660, 130]],
    'warn': [[740, 120], [0, 60], [740, 120]],
    'error': [[220, 220], [0, 50], [160, 350]],
  };

  static Future<void> play(String kind) async {
    final pattern = _patterns[kind] ?? _patterns['error']!;
    if (kind == 'error' || kind == 'warn') {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    if (!AppState.instance.settings.sound) return;
    try {
      final bytes = _cache.putIfAbsent(kind, () => _wav(pattern));
      await _player.stop();
      await _player.play(BytesSource(bytes));
    } catch (_) {
      // Pas de son disponible : la vibration suffit.
    }
  }

  static Uint8List _wav(List<List<int>> notes) {
    const rate = 22050;
    final samples = <int>[];
    for (final note in notes) {
      final count = rate * note[1] ~/ 1000;
      for (var i = 0; i < count; i++) {
        if (note[0] == 0) {
          samples.add(0);
          continue;
        }
        final fade = min(1.0, min(i / 200.0, (count - i) / 400.0));
        samples.add((sin(2 * pi * note[0] * i / rate) * 12000 * fade).round());
      }
    }
    final data = ByteData(44 + samples.length * 2);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        data.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }
}
