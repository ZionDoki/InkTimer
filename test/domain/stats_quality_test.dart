import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/focus_quality.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/stats.dart';

SessionRecord _session({
  required String id,
  required int startedAt,
  int focusedSec = 160,
  int? qualityScore,
  FocusQualityEvidence? evidence,
}) => SessionRecord(
  id: id,
  templateId: 't',
  label: '专注',
  kind: TemplateKind.interval,
  startedAt: startedAt,
  endedAt: startedAt + focusedSec * 1000,
  plannedSec: focusedSec,
  elapsedSec: focusedSec,
  completed: true,
  roundsDone: 1,
  roundsTotal: 1,
  focusedSec: focusedSec,
  qualityScore: qualityScore,
  qualityEvidence: evidence,
  awardedMilliExp: 1000,
  scoringVersion: qualityScore == null ? 0 : 1,
);

void main() {
  test('统计定力排除旧记录并汇总安定率与离席时长', () {
    final now = DateTime(2026, 8, 13, 12);
    final start = DateTime(2026, 8, 13, 9).millisecondsSinceEpoch;
    final summary = summarizeSessions([
      _session(id: 'legacy', startedAt: start),
      _session(
        id: 'clean',
        startedAt: start + 1000000,
        qualityScore: 100,
        evidence: const FocusQualityEvidence(),
      ),
      _session(
        id: 'away',
        startedAt: start + 2000000,
        qualityScore: 80,
        evidence: const FocusQualityEvidence(
          backgroundExcursionCount: 1,
          backgroundFocusSec: 45,
        ),
      ),
    ], now);

    expect(summary.measuredQualityCount, 2);
    expect(summary.legacyQualityCount, 1);
    expect(summary.averageQuality, 90);
    expect(summary.undisturbedRate, 0.5);
    expect(summary.backgroundFocusSec, 45);
  });

  test('统计连续天数要求当日累计完成专注至少一百五十秒', () {
    final now = DateTime(2026, 8, 13, 12);
    final yesterday = DateTime(2026, 8, 12, 9).millisecondsSinceEpoch;
    final today = DateTime(2026, 8, 13, 9).millisecondsSinceEpoch;
    final summary = summarizeSessions([
      _session(id: 'one-second', startedAt: yesterday, focusedSec: 1),
      _session(id: 'tabata', startedAt: today, focusedSec: 160),
    ], now);

    expect(summary.streakDays, 1);
  });

  test('近十次定力只取最新十条合格实测记录', () {
    final base = DateTime(2026, 8, 1).millisecondsSinceEpoch;
    final sessions = [
      for (var index = 0; index < 12; index += 1)
        _session(
          id: '$index',
          startedAt: base + index * 1000000,
          qualityScore: 80 + index,
          evidence: const FocusQualityEvidence(),
        ),
    ];
    expect(recentMeasuredQualityAverage(sessions), 86.5);
  });
}
