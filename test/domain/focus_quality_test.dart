import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/focus_quality.dart';

void main() {
  group('专注质量', () {
    test('无扰动为满分，各类扣分按规则封顶且总分不低于四十', () {
      expect(focusQualityScore(emptyFocusQualityEvidence), 100);
      expect(
        focusQualityScore(const FocusQualityEvidence(manualPauseCount: 1)),
        92,
      );
      expect(
        focusQualityScore(const FocusQualityEvidence(manualPauseCount: 2)),
        87,
      );
      expect(
        focusQualityScore(
          const FocusQualityEvidence(backgroundExcursionCount: 1),
        ),
        94,
      );
      expect(
        focusQualityScore(
          const FocusQualityEvidence(
            backgroundExcursionCount: 1,
            backgroundFocusSec: 630,
          ),
        ),
        89,
      );
      expect(
        focusQualityScore(
          const FocusQualityEvidence(
            manualPauseCount: 100,
            canceledHoldCount: 100,
            inAppDiversionCount: 100,
            backgroundExcursionCount: 100,
            backgroundFocusSec: 999999,
          ),
        ),
        40,
      );
    });

    test('积累时长四小时后降档且八小时后封顶', () {
      expect(creditedFocusedSec(4 * 3600, accumulate: true), 4 * 3600);
      expect(creditedFocusedSec(8 * 3600, accumulate: true), 5 * 3600);
      expect(creditedFocusedSec(20 * 3600, accumulate: true), 5 * 3600);
      expect(creditedFocusedSec(20 * 3600, accumulate: false), 20 * 3600);

      const fourHours = 4 * 3600;
      final base = calculateAwardedMilliExp(
        focusedSec: fourHours,
        accumulate: true,
        completed: true,
        qualityScore: 100,
        streakDays: 0,
      );
      for (var extra = 1; extra <= 4; extra += 1) {
        final award = calculateAwardedMilliExp(
          focusedSec: fourHours + extra,
          accumulate: true,
          completed: true,
          qualityScore: 100,
          streakDays: 0,
        );
        expect(award, (base + extra * 1000 / 240).round());
      }
    });

    test('定力下降会降低经验，累计使用固定点数', () {
      final clean = calculateAwardedMilliExp(
        focusedSec: 1500,
        accumulate: false,
        completed: true,
        qualityScore: 100,
        streakDays: 0,
      );
      final distracted = calculateAwardedMilliExp(
        focusedSec: 1500,
        accumulate: false,
        completed: true,
        qualityScore: 80,
        streakDays: 0,
      );
      expect(clean, 27500);
      expect(distracted, 24200);
      expect(clean, greaterThan(distracted));
    });
  });
}
