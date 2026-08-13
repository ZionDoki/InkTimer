import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../domain/sounds.dart';

/// 把 OscSpec 直接渲染为 PCM WAV。项目继续以数据描述音色，不引入音频资源文件。
Uint8List renderSoundWav(SoundName name, {int sampleRate = 44100}) {
  if (sampleRate < 1000) {
    throw ArgumentError.value(sampleRate, 'sampleRate', 'must be >= 1000');
  }
  final specs = soundSpecs[name]!;
  final totalSeconds = specs.fold<double>(
    0,
    (longest, spec) => math.max(longest, spec.at + spec.duration + 0.05),
  );
  final sampleCount = (totalSeconds * sampleRate).ceil();
  final samples = Float64List(sampleCount);

  for (final spec in specs) {
    final start = (spec.at * sampleRate).round();
    final length = (spec.duration * sampleRate).ceil();
    for (
      var index = 0;
      index < length && start + index < sampleCount;
      index++
    ) {
      final time = index / sampleRate;
      final phase = _phaseCycles(spec, time);
      final wave = _waveValue(spec.wave, phase);
      final envelope = _envelope(spec, time);
      samples[start + index] += wave * envelope;
    }
  }

  const headerLength = 44;
  final dataLength = sampleCount * 2;
  final output = Uint8List(headerLength + dataLength);
  final bytes = ByteData.sublistView(output);
  _ascii(output, 0, 'RIFF');
  bytes.setUint32(4, 36 + dataLength, Endian.little);
  _ascii(output, 8, 'WAVE');
  _ascii(output, 12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, 1, Endian.little); // mono
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  _ascii(output, 36, 'data');
  bytes.setUint32(40, dataLength, Endian.little);
  for (var index = 0; index < sampleCount; index++) {
    final sample = samples[index].clamp(-1.0, 1.0);
    bytes.setInt16(
      headerLength + index * 2,
      (sample * 32767).round(),
      Endian.little,
    );
  }
  return output;
}

void _ascii(Uint8List target, int offset, String value) {
  for (var index = 0; index < value.length; index++) {
    target[offset + index] = value.codeUnitAt(index);
  }
}

double _phaseCycles(OscSpec spec, double time) {
  final target = spec.f1;
  if (target == null || target <= 0 || spec.f0 <= 0) return spec.f0 * time;
  final ramp = (spec.rampSec ?? math.min(spec.duration, 0.13)).clamp(
    0.000001,
    spec.duration,
  );
  final ratio = target / spec.f0;
  final k = math.log(ratio) / ramp;
  if (k.abs() < 1e-9) return spec.f0 * time;
  final inRamp = math.min(time, ramp);
  final rampCycles = spec.f0 * (math.exp(k * inRamp) - 1) / k;
  return time <= ramp ? rampCycles : rampCycles + target * (time - ramp);
}

double _waveValue(WaveShape shape, double cycles) {
  final angle = cycles * math.pi * 2;
  return switch (shape) {
    WaveShape.sine => math.sin(angle),
    WaveShape.square => math.sin(angle) >= 0 ? 1 : -1,
    WaveShape.triangle => (2 / math.pi) * math.asin(math.sin(angle)),
    WaveShape.sawtooth => 2 * (cycles - (cycles + 0.5).floor()),
  };
}

double _envelope(OscSpec spec, double time) {
  final attack = spec.attackSec.clamp(
    0.001,
    math.max(0.001, spec.duration * 0.45),
  );
  if (time < attack && spec.duration > attack) {
    return spec.gain * time / attack;
  }
  if (spec.duration <= attack) {
    return spec.gain * (1 - time / spec.duration).clamp(0, 1);
  }
  final decayProgress = ((time - attack) / (spec.duration - attack)).clamp(
    0.0,
    1.0,
  );
  return spec.gain * math.pow(0.0001 / spec.gain, decayProgress);
}

Duration soundDuration(SoundName name) {
  final seconds = soundSpecs[name]!.fold<double>(
    0,
    (longest, spec) => math.max(longest, spec.at + spec.duration + 0.05),
  );
  return Duration(milliseconds: (seconds * 1000).ceil());
}

class ToneAudioService {
  final Map<SoundName, Uint8List> _cache = {};
  final Set<AudioPlayer> _players = {};
  final Set<Timer> _disposeTimers = {};
  double _volume = 0.8;
  bool _enabled = true;

  bool get available => _enabled;

  void configure({required bool enabled, required double volume}) {
    _enabled = enabled;
    _volume = volume.clamp(0, 1);
  }

  Future<void> play(SoundName name) async {
    if (!_enabled || _volume <= 0) return;
    final player = AudioPlayer();
    _players.add(player);
    try {
      final bytes = _cache.putIfAbsent(name, () => renderSoundWav(name));
      await player.setReleaseMode(ReleaseMode.stop);
      await player.play(
        BytesSource(bytes, mimeType: 'audio/wav'),
        volume: _volume,
      );
      late final Timer timer;
      timer = Timer(soundDuration(name) + const Duration(seconds: 1), () {
        _disposeTimers.remove(timer);
        _players.remove(player);
        unawaited(player.dispose());
      });
      _disposeTimers.add(timer);
    } on Object {
      _players.remove(player);
      await player.dispose();
      // 与旧 Web Audio 实现一致：音频后端不可用时静默进入无声模式。
      _enabled = false;
    }
  }

  Future<void> dispose() async {
    for (final timer in _disposeTimers) {
      timer.cancel();
    }
    _disposeTimers.clear();
    final players = List<AudioPlayer>.of(_players);
    _players.clear();
    await Future.wait(players.map((player) => player.dispose()));
  }
}
