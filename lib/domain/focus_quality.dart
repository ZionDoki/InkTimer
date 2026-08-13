import 'dart:math' as math;

/// Versioned, objective facts observed while one focus session is active.
class FocusQualityEvidence {
  const FocusQualityEvidence({
    this.version = 1,
    this.manualPauseCount = 0,
    this.canceledHoldCount = 0,
    this.inAppDiversionCount = 0,
    this.backgroundExcursionCount = 0,
    this.backgroundFocusSec = 0,
  });

  final int version;
  final int manualPauseCount;
  final int canceledHoldCount;
  final int inAppDiversionCount;
  final int backgroundExcursionCount;
  final int backgroundFocusSec;

  FocusQualityEvidence copyWith({
    int? manualPauseCount,
    int? canceledHoldCount,
    int? inAppDiversionCount,
    int? backgroundExcursionCount,
    int? backgroundFocusSec,
  }) => FocusQualityEvidence(
    version: version,
    manualPauseCount: manualPauseCount ?? this.manualPauseCount,
    canceledHoldCount: canceledHoldCount ?? this.canceledHoldCount,
    inAppDiversionCount: inAppDiversionCount ?? this.inAppDiversionCount,
    backgroundExcursionCount:
        backgroundExcursionCount ?? this.backgroundExcursionCount,
    backgroundFocusSec: backgroundFocusSec ?? this.backgroundFocusSec,
  );

  Map<String, Object> toJson() => {
    'version': version,
    'manualPauseCount': manualPauseCount,
    'canceledHoldCount': canceledHoldCount,
    'inAppDiversionCount': inAppDiversionCount,
    'backgroundExcursionCount': backgroundExcursionCount,
    'backgroundFocusSec': backgroundFocusSec,
  };
}

const emptyFocusQualityEvidence = FocusQualityEvidence();

int focusQualityScore(FocusQualityEvidence evidence) {
  final pauses = evidence.manualPauseCount;
  final pausePenalty = pauses == 0 ? 0 : math.min(24, 8 + 5 * (pauses - 1));
  final canceledHoldPenalty = math.min(8, 4 * evidence.canceledHoldCount);
  final diversions = evidence.inAppDiversionCount;
  final diversionPenalty = diversions == 0
      ? 0
      : math.min(18, 6 + 4 * (diversions - 1));
  final graceSec = 30 * evidence.backgroundExcursionCount;
  final timedPenalty =
      math.max(0, evidence.backgroundFocusSec - graceSec) ~/ 120;
  final backgroundPenalty = math.min(
    40,
    6 * evidence.backgroundExcursionCount + timedPenalty,
  );
  return (100 -
          pausePenalty -
          canceledHoldPenalty -
          diversionPenalty -
          backgroundPenalty)
      .clamp(40, 100);
}

/// Long open-ended sessions retain full credit for four hours, quarter credit
/// for the next four, and no further growth credit after eight hours.
///
/// This compatibility helper rounds only for presentation. Experience uses the
/// exact numerator below so each second after four hours contributes exactly a
/// quarter second of credit without boundary rounding artifacts.
int creditedFocusedSec(int focusedSec, {required bool accumulate}) =>
    (_creditedFocusedQuarterSeconds(focusedSec, accumulate: accumulate) / 4)
        .round();

int _creditedFocusedQuarterSeconds(int focusedSec, {required bool accumulate}) {
  final safe = focusedSec.clamp(0, 1 << 62);
  if (!accumulate) return safe * 4;
  const fourHours = 4 * 3600;
  const eightHours = 8 * 3600;
  if (safe <= fourHours) return safe * 4;
  final reduced = math.min(safe, eightHours) - fourHours;
  return fourHours * 4 + reduced;
}

int calculateAwardedMilliExp({
  required int focusedSec,
  required bool accumulate,
  required bool completed,
  required int qualityScore,
  required int streakDays,
}) {
  final creditedQuarterSeconds = _creditedFocusedQuarterSeconds(
    focusedSec,
    accumulate: accumulate,
  );
  final base = creditedQuarterSeconds * 1000 / (60.0 * 4);
  final completion = accumulate ? 1.0 : (completed ? 1.10 : 0.85);
  final quality = 0.40 + 0.006 * qualityScore.clamp(40, 100);
  final streak = 1.0 + math.min(streakDays, 10) * 0.02;
  return (base * completion * quality * streak).round();
}
