import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/sounds.dart';
import 'package:uptimer/services/audio_service.dart';

int _u32(Uint8List bytes, int offset) =>
    ByteData.sublistView(bytes).getUint32(offset, Endian.little);

double _peakAmplitude(Uint8List bytes) {
  final samples = ByteData.sublistView(bytes, 44);
  var peak = 0;
  for (var offset = 0; offset < samples.lengthInBytes; offset += 2) {
    final value = samples.getInt16(offset, Endian.little).abs();
    if (value > peak) peak = value;
  }
  return peak / 32767;
}

void main() {
  group('运行时合成音色', () {
    test('生成标准单声道 16-bit PCM WAV', () {
      final bytes = renderSoundWav(SoundName.tick, sampleRate: 8000);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(_u32(bytes, 24), 8000);
      expect(ByteData.sublistView(bytes).getUint16(34, Endian.little), 16);
      expect(_u32(bytes, 40), bytes.length - 44);
      expect(bytes.length, greaterThan(44));
    });

    test('延迟振荡器会延长完整音效且内容不是静音', () {
      final bytes = renderSoundWav(SoundName.complete, sampleRate: 4000);
      expect(bytes.length, greaterThan(44 + 6 * 4000 * 2));
      final samples = ByteData.sublistView(bytes, 44);
      var nonzero = false;
      for (var offset = 0; offset < samples.lengthInBytes; offset += 2) {
        if (samples.getInt16(offset, Endian.little) != 0) {
          nonzero = true;
          break;
        }
      }
      expect(nonzero, isTrue);
    });

    test('所有数据驱动音色都能渲染', () {
      for (final name in SoundName.values) {
        expect(
          () => renderSoundWav(name, sampleRate: 2000),
          returnsNormally,
          reason: name.name,
        );
      }
    });

    test('暂停音使用柔和错峰纯音且默认以 CD 采样率渲染', () {
      final pause = soundSpecs[SoundName.pauseLow]!;
      final highest = pause
          .expand((spec) => [spec.f0, spec.f1 ?? spec.f0])
          .reduce((a, b) => a > b ? a : b);

      expect(pause, hasLength(greaterThanOrEqualTo(3)));
      expect(pause.every((spec) => spec.wave == WaveShape.sine), isTrue);
      expect(pause.any((spec) => spec.at > 0), isTrue);
      expect(pause.every((spec) => spec.attackSec >= 0.025), isTrue);
      expect(highest, lessThanOrEqualTo(900));

      final bytes = renderSoundWav(SoundName.pauseLow);
      expect(_u32(bytes, 24), 44100);
    });

    test('完成音保留峰值余量并以错峰缓起音收束', () {
      final complete = soundSpecs[SoundName.complete]!;
      final starts = complete.map((spec) => spec.at).toSet();
      final highest = complete
          .expand((spec) => [spec.f0, spec.f1 ?? spec.f0])
          .reduce((a, b) => a > b ? a : b);

      expect(complete.every((spec) => spec.wave == WaveShape.sine), isTrue);
      expect(complete.every((spec) => spec.attackSec >= 0.035), isTrue);
      expect(starts.length, greaterThanOrEqualTo(4));
      expect(
        complete.fold<double>(0, (sum, spec) => sum + spec.gain),
        lessThan(0.32),
      );
      expect(highest, lessThanOrEqualTo(2800));
      expect(
        _peakAmplitude(renderSoundWav(SoundName.complete)),
        lessThan(0.34),
      );
    });
  });
}
