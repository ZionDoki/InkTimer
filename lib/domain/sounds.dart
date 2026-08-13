enum WaveShape { sine, square, triangle, sawtooth }

enum SoundName {
  bowlWork,
  bowlRest,
  tick,
  plip,
  pauseLow,
  resumeHigh,
  complete,
  drum,
  charge,
}

class OscSpec {
  const OscSpec({
    this.wave = WaveShape.sine,
    required this.f0,
    this.f1,
    this.at = 0,
    required this.duration,
    required this.gain,
    this.rampSec,
    this.attackSec = 0.012,
  });

  final WaveShape wave;
  final double f0;
  final double? f1;
  final double at;
  final double duration;
  final double gain;
  final double? rampSec;
  final double attackSec;
}

List<OscSpec> _bowl(
  double frequency,
  double volume,
  double duration, [
  double at = 0,
]) {
  const partials = <(double, double)>[
    (1, 1),
    (2.76, 0.42),
    (5.4, 0.18),
    (8.9, 0.07),
  ];
  return [
    for (var index = 0; index < partials.length; index += 1)
      OscSpec(
        f0: frequency * partials[index].$1,
        at: at,
        duration: duration * (index == 0 ? 1 : 0.55),
        gain: volume * partials[index].$2,
      ),
  ];
}

/// 完成提示使用更低峰值、更慢起音的双钵。每个泛音错峰进入，避免多个
/// 振荡器在同一采样点叠出尖锐瞬态。
List<OscSpec> _closingBowl(
  double frequency,
  double volume,
  double duration, {
  double at = 0,
}) {
  const partials = <(double, double, double, double, double)>[
    // 频率倍数、增益倍数、错峰、起音、时长倍数
    (1, 1, 0, 0.058, 1),
    (2.02, 0.25, 0.045, 0.068, 0.66),
    (3.86, 0.10, 0.095, 0.082, 0.48),
    (6.36, 0.035, 0.145, 0.095, 0.34),
  ];
  return [
    for (final partial in partials)
      OscSpec(
        f0: frequency * partial.$1,
        at: at + partial.$3,
        duration: duration * partial.$5,
        gain: volume * partial.$2,
        attackSec: partial.$4,
      ),
  ];
}

final soundSpecs = <SoundName, List<OscSpec>>{
  SoundName.bowlWork: _bowl(528, 0.16, 4),
  SoundName.bowlRest: _bowl(396, 0.16, 4),
  SoundName.tick: const [OscSpec(f0: 840, f1: 620, duration: 0.09, gain: 0.12)],
  SoundName.plip: const [
    OscSpec(f0: 1150, f1: 380, duration: 0.16, gain: 0.07),
  ],
  SoundName.pauseLow: const [
    // 两层向下滑落的陶音，错峰进入以形成“收气”而不是金属撞击。
    OscSpec(
      f0: 392,
      f1: 329.63,
      duration: 1.05,
      gain: 0.038,
      rampSec: 0.55,
      attackSec: 0.038,
    ),
    OscSpec(
      f0: 293.66,
      f1: 220,
      at: 0.07,
      duration: 1.65,
      gain: 0.065,
      rampSec: 0.9,
      attackSec: 0.05,
    ),
    OscSpec(
      f0: 587.33,
      f1: 440,
      at: 0.13,
      duration: 0.92,
      gain: 0.012,
      rampSec: 0.5,
      attackSec: 0.045,
    ),
    OscSpec(
      f0: 220,
      f1: 196,
      at: 0.18,
      duration: 1.4,
      gain: 0.018,
      rampSec: 0.8,
      attackSec: 0.06,
    ),
  ],
  SoundName.resumeHigh: _bowl(528, 0.12, 2),
  SoundName.complete: [
    ..._closingBowl(264, 0.105, 6),
    ..._closingBowl(396, 0.065, 5.4, at: 0.48),
  ],
  SoundName.drum: const [OscSpec(f0: 90, f1: 45, duration: 0.3, gain: 0.22)],
  SoundName.charge: const [
    OscSpec(f0: 180, f1: 620, duration: 2.5, gain: 0.08, rampSec: 2.4),
  ],
};
