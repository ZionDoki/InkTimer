import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/stats.dart';
import '../theme/zen_theme.dart';

class HeatmapGridGeometry {
  const HeatmapGridGeometry({
    required this.origin,
    required this.cell,
    required this.gap,
    required this.columns,
    required this.rows,
  });

  final Offset origin;
  final double cell;
  final double gap;
  final int columns;
  final int rows;

  Size get gridSize => Size(
    columns * cell + (columns - 1) * gap,
    rows * cell + (rows - 1) * gap,
  );

  Rect cellRect(int slot) {
    final column = slot ~/ rows;
    final row = slot % rows;
    return Rect.fromLTWH(
      origin.dx + column * (cell + gap),
      origin.dy + row * (cell + gap),
      cell,
      cell,
    );
  }
}

HeatmapGridGeometry layoutHeatmapGrid(
  Size size, {
  int columns = 12,
  int rows = 7,
  double gap = 3,
}) {
  final cell = math.max(
    0.0,
    math.min(
      (size.width - gap * (columns - 1)) / columns,
      (size.height - gap * (rows - 1)) / rows,
    ),
  );
  final gridSize = Size(
    columns * cell + (columns - 1) * gap,
    rows * cell + (rows - 1) * gap,
  );
  return HeatmapGridGeometry(
    origin: Offset(
      (size.width - gridSize.width) / 2,
      (size.height - gridSize.height) / 2,
    ),
    cell: cell,
    gap: gap,
    columns: columns,
    rows: rows,
  );
}

class HeatmapEntry {
  const HeatmapEntry({required this.day, required this.slot});

  final DayBucket day;
  final int slot;
}

/// 将最后一天放到真实星期行；当前周未来日期保留为空白格。
List<HeatmapEntry> alignHeatmapDays(
  List<DayBucket> days, {
  int columns = 12,
  int rows = 7,
}) {
  if (days.isEmpty) return const [];
  final lastDate = DateTime.tryParse(days.last.date);
  if (lastDate == null) return const [];
  final capacity = columns * rows;
  final lastSlot = (columns - 1) * rows + (lastDate.weekday - 1);
  final visibleCount = math.min(days.length, math.min(capacity, lastSlot + 1));
  final visible = days.skip(days.length - visibleCount).toList();
  final startSlot = lastSlot - visible.length + 1;
  return [
    for (var index = 0; index < visible.length; index++)
      HeatmapEntry(day: visible[index], slot: startSlot + index),
  ];
}

int heatDepthLevel({required int seconds, required int count}) {
  final durationLevel = switch (seconds) {
    < 60 => 0,
    < 300 => 1,
    < 900 => 2,
    < 1800 => 3,
    < 3600 => 4,
    _ => 5,
  };
  final countLevel = count <= 0 ? 0 : math.min(count, 5);
  return math.min(durationLevel, countLevel);
}

Color heatmapCellColor(ZenPalette palette, int level) {
  final safeLevel = level.clamp(0, 5);
  if (safeLevel == 0) {
    return Color.lerp(palette.paper, palette.paperDeep, 0.72)!;
  }
  const activeMix = [0.20, 0.36, 0.52, 0.70, 0.90];
  return Color.lerp(palette.paperDeep, palette.work, activeMix[safeLevel - 1])!;
}

class CubicTrendSegment {
  const CubicTrendSegment({
    required this.start,
    required this.control1,
    required this.control2,
    required this.end,
  });

  final Offset start;
  final Offset control1;
  final Offset control2;
  final Offset end;
}

class SmoothTrendGeometry {
  const SmoothTrendGeometry({required this.points, required this.segments});

  final List<Offset> points;
  final List<CubicTrendSegment> segments;

  Path toPath() {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (final segment in segments) {
      path.cubicTo(
        segment.control1.dx,
        segment.control1.dy,
        segment.control2.dx,
        segment.control2.dy,
        segment.end.dx,
        segment.end.dy,
      );
    }
    return path;
  }
}

SmoothTrendGeometry layoutSmoothTrend(
  List<num> values,
  Size size, {
  EdgeInsets padding = const EdgeInsets.fromLTRB(2, 12, 2, 12),
}) {
  if (values.isEmpty) {
    return const SmoothTrendGeometry(points: [], segments: []);
  }
  final width = math.max(0, size.width - padding.horizontal);
  final height = math.max(0, size.height - padding.vertical);
  final maxValue = values.fold<double>(
    0,
    (max, value) => math.max(max, value.toDouble()),
  );
  final points = <Offset>[
    for (var index = 0; index < values.length; index++)
      Offset(
        padding.left +
            (values.length == 1
                ? width / 2
                : width * index / (values.length - 1)),
        padding.top +
            height *
                (1 - (maxValue == 0 ? 0 : values[index].toDouble() / maxValue)),
      ),
  ];
  final segments = <CubicTrendSegment>[];
  for (var index = 0; index < points.length - 1; index++) {
    final previous = index == 0 ? points[index] : points[index - 1];
    final start = points[index];
    final end = points[index + 1];
    final next = index + 2 < points.length ? points[index + 2] : end;
    final control1 = Offset(
      start.dx + (end.dx - previous.dx) / 6,
      (start.dy + (end.dy - previous.dy) / 6).clamp(
        padding.top,
        padding.top + height,
      ),
    );
    final control2 = Offset(
      end.dx - (next.dx - start.dx) / 6,
      (end.dy - (next.dy - start.dy) / 6).clamp(
        padding.top,
        padding.top + height,
      ),
    );
    segments.add(
      CubicTrendSegment(
        start: start,
        control1: control1,
        control2: control2,
        end: end,
      ),
    );
  }
  return SmoothTrendGeometry(points: points, segments: segments);
}
