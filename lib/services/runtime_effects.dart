import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../domain/sounds.dart';
import 'audio_service.dart';

enum HapticCue { phase, complete }

abstract interface class RuntimeEffects {
  bool get audioAvailable;

  void configureAudio({required bool enabled, required double volume});

  Future<void> play(SoundName sound);

  Future<void> haptic(HapticCue cue);

  Future<void> keepAwake(bool enabled);

  Future<void> dispose();
}

class FlutterRuntimeEffects implements RuntimeEffects {
  FlutterRuntimeEffects({ToneAudioService? audio})
    : _audio = audio ?? ToneAudioService();

  final ToneAudioService _audio;
  bool _hapticsEnabled = true;
  bool _wakeEnabled = false;

  @override
  bool get audioAvailable => _audio.available;

  @override
  void configureAudio({required bool enabled, required double volume}) {
    _audio.configure(enabled: enabled, volume: volume);
  }

  void configureHaptics(bool enabled) => _hapticsEnabled = enabled;

  @override
  Future<void> play(SoundName sound) => _audio.play(sound);

  @override
  Future<void> haptic(HapticCue cue) async {
    if (!_hapticsEnabled) return;
    try {
      if (cue == HapticCue.complete) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    } on Object {
      // 无触感硬件的平台静默降级。
    }
  }

  @override
  Future<void> keepAwake(bool enabled) async {
    if (_wakeEnabled == enabled) return;
    try {
      await WakelockPlus.toggle(enable: enabled);
      _wakeEnabled = enabled;
    } on Object {
      // 浏览器权限或平台插件不可用时不影响计时。
    }
  }

  @override
  Future<void> dispose() async {
    await keepAwake(false);
    await _audio.dispose();
  }
}

class NoopRuntimeEffects implements RuntimeEffects {
  const NoopRuntimeEffects();

  @override
  bool get audioAvailable => true;

  @override
  void configureAudio({required bool enabled, required double volume}) {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> haptic(HapticCue cue) async {}

  @override
  Future<void> keepAwake(bool enabled) async {}

  @override
  Future<void> play(SoundName sound) async {}
}
