import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/stats.dart';
import 'package:uptimer/ui/stats/chart_geometry.dart';
import 'package:uptimer/ui/theme/zen_theme.dart';

DayBucket day(String date, [int seconds = 0]) => DayBucket(
  date: date,
  sec: seconds,
  count: seconds == 0 ? 0 : 1,
  completed: seconds == 0 ? 0 : 1,
  interruptions: 0,
);

void main() {
  test('十二周热力网格在画布中水平与垂直居中', () {
    final geometry = layoutHeatmapGrid(const Size(320, 190));

    expect(
      geometry.origin.dx * 2 + geometry.gridSize.width,
      closeTo(320, 0.001),
    );
    expect(
      geometry.origin.dy * 2 + geometry.gridSize.height,
      closeTo(190, 0.001),
    );
    expect(geometry.cellRect(0).topLeft, geometry.origin);
    expect(
      geometry.cellRect(83).right,
      closeTo(320 - geometry.origin.dx, 0.001),
    );
  });

  test('热力图按周一到周日对齐，最后一天落在对应星期行', () {
    final days = List.generate(
      84,
      (index) => day(
        dayKey(DateTime(2026, 5, 16).add(Duration(days: index))),
        index * 60,
      ),
    );
    final entries = alignHeatmapDays(days);

    expect(DateTime.parse(entries.last.day.date).weekday, DateTime.friday);
    expect(entries.last.slot, 81);
    expect(entries.last.slot % 7, DateTime.friday - 1);
    expect(entries.any((entry) => entry.slot == 82), isFalse);
  });

  test('趋势采用连续三次贝塞尔段而非折线并保持控制点前进', () {
    final geometry = layoutSmoothTrend(const [
      0,
      20,
      8,
      30,
      16,
    ], const Size(300, 120));

    expect(geometry.segments, hasLength(4));
    for (final segment in geometry.segments) {
      expect(segment.control1.dx, greaterThanOrEqualTo(segment.start.dx));
      expect(segment.control2.dx, lessThanOrEqualTo(segment.end.dx));
      expect(segment.end.dx, greaterThan(segment.start.dx));
    }
  });

  test('十二周热力图按每日次数与总时长的较低档着色', () {
    expect(heatDepthLevel(seconds: 0, count: 0), 0);
    expect(heatDepthLevel(seconds: 59, count: 5), 0);

    expect(heatDepthLevel(seconds: 60, count: 1), 1);
    expect(heatDepthLevel(seconds: 300, count: 2), 2);
    expect(heatDepthLevel(seconds: 900, count: 3), 3);
    expect(heatDepthLevel(seconds: 1800, count: 4), 4);
    expect(heatDepthLevel(seconds: 3600, count: 5), 5);
  });

  test('十二周热力图不会因单项达到高档而过度着色', () {
    expect(heatDepthLevel(seconds: 3600, count: 1), 1);
    expect(heatDepthLevel(seconds: 3600, count: 2), 2);
    expect(heatDepthLevel(seconds: 60, count: 5), 1);
    expect(heatDepthLevel(seconds: 300, count: 5), 2);
    expect(heatDepthLevel(seconds: 7200, count: 8), 5);
  });

  test('十二周热力图时长档位在门槛处才升级', () {
    expect(heatDepthLevel(seconds: 299, count: 5), 1);
    expect(heatDepthLevel(seconds: 899, count: 5), 2);
    expect(heatDepthLevel(seconds: 1799, count: 5), 3);
    expect(heatDepthLevel(seconds: 3599, count: 5), 4);
  });

  test('零次且零秒的空白日使用独立浅色', () {
    final empty = heatmapCellColor(ZenPalette.paperTheme, 0);
    final first = heatmapCellColor(ZenPalette.paperTheme, 1);

    expect(
      empty,
      Color.lerp(
        ZenPalette.paperTheme.paper,
        ZenPalette.paperTheme.paperDeep,
        0.72,
      ),
    );
    expect(empty, isNot(first));
    expect(empty.computeLuminance(), greaterThan(first.computeLuminance()));
  });
}
