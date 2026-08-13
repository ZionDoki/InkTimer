import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/growth.dart';
import '../../domain/growth_models.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_controller.dart';
import '../theme/zen_theme.dart';
import '../widgets/zen_page.dart';
import 'chart_geometry.dart';
import 'growth_page.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = ZenPalette.of(context);
    final summary = summarizeSessions(controller.sessions, DateTime.now());
    final todoSummary = summarizeTodos(controller.todos);
    final recentDone =
        controller.todos.where((todo) => todo.completedAt != null).toList()
          ..sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));

    return ZenPage(
      title: '功 课 簿',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (summary.totalCount == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 96),
              child: Text(
                '纸 上 尚 无 一 笔',
                textAlign: TextAlign.center,
                style: inkText(
                  context,
                  size: 13,
                  color: palette.inkSoft,
                  spacing: 6,
                ),
              ),
            )
          else ...[
            _StatsOverview(summary: summary),
            const ZenSectionTitle('专 注 构 成', top: 38),
            SizedBox(
              height: 148,
              child: Row(
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _DonutPainter(summary.byKind, palette),
                      child: Center(
                        child: Text(
                          formatDuration(summary.totalSec),
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 26),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _KindLine(
                          color: palette.work,
                          name: '番 茄',
                          stat: summary.byKind[TemplateKind.pomodoro]!,
                          totalSec: summary.totalSec,
                        ),
                        _KindLine(
                          color: palette.work.withValues(alpha: 0.45),
                          name: '间 歇',
                          stat: summary.byKind[TemplateKind.interval]!,
                          totalSec: summary.totalSec,
                        ),
                        _KindLine(
                          color: palette.work.withValues(alpha: 0.2),
                          name: '积 累',
                          stat: summary.byKind[TemplateKind.accumulate]!,
                          totalSec: summary.totalSec,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            _StatsChartCard(
              title: '近 30 日 节 律',
              subtitle: '每日专注时长 · 曲线越高，投入越深',
              value:
                  '共 ${formatDuration(summary.daily.takeLast(30).fold<int>(0, (sum, day) => sum + day.sec))}',
              child: Column(
                children: [
                  SizedBox(
                    key: const ValueKey('stats-trend-chart'),
                    height: 142,
                    child: CustomPaint(
                      painter: _TrendPainter(
                        summary.daily.takeLast(30),
                        palette,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('30 日 前', style: _chartAxisStyle(palette)),
                      Text('今 天', style: _chartAxisStyle(palette)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _StatsChartCard(
              title: '12 周 积 累',
              subtitle: '每格一天 · 空白日最浅，次数与总时长取较低档',
              value: '${summary.daily.where((day) => day.sec > 0).length} 天有记录',
              child: _HeatmapChart(days: summary.daily),
            ),
            const ZenSectionTitle('专 注 质 量', top: 38),
            Row(
              children: [
                Expanded(
                  child: _InsightCard(
                    label: '平 均 定 力',
                    value: summary.measuredQualityCount == 0
                        ? '—'
                        : '${summary.averageQuality.round()}',
                    accent: palette.work,
                    strength: summary.measuredQualityCount == 0
                        ? 0
                        : summary.averageQuality / 100,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InsightCard(
                    label: '安 定 功 课',
                    value: summary.measuredQualityCount == 0
                        ? '—'
                        : '${(summary.undisturbedRate * 100).round()}%',
                    accent: palette.work,
                    strength: summary.undisturbedRate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InsightCard(
                    label: '离 席 时 段',
                    value: formatDuration(summary.backgroundFocusSec),
                    accent: palette.work,
                    strength: summary.backgroundFocusSec == 0 ? 1 : 0.35,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _StatsChartCard(
              title: '高 效 时 段',
              subtitle: '每柱一小时 · 朱色越深，进入状态越多',
              value: _peakHourLabel(summary.byHour),
              child: Column(
                children: [
                  SizedBox(
                    height: 108,
                    child: CustomPaint(
                      painter: _HourPainter(summary.byHour, palette),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final label in const ['0', '6', '12', '18', '24'])
                        Text(label, style: _chartAxisStyle(palette)),
                    ],
                  ),
                ],
              ),
            ),
            const ZenSectionTitle('单 次 时 长'),
            for (final bucket in summary.durationBuckets)
              _HorizontalBar(
                label: bucket.label,
                value: bucket.count,
                max: summary.durationBuckets
                    .map((item) => item.count)
                    .fold(0, math.max),
              ),
            if (summary.byTemplate.isNotEmpty) ...[
              const ZenSectionTitle('常 用'),
              for (final template in summary.byTemplate.take(5))
                _TemplateBar(
                  stat: template,
                  max: summary.byTemplate
                      .take(5)
                      .map((item) => item.sec)
                      .fold(0, math.max),
                ),
            ],
            const ZenSectionTitle('印 记'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final mark in sealMarks)
                  ZenSeal(
                    key: ValueKey('seal-${mark.insightId}'),
                    mark.character,
                    // 读已悟列表而不是当下连续天数：印记得到了就不收回。
                    earned: controller.growth.insights.contains(mark.insightId),
                  ),
              ],
            ),
          ],
          if (controller.todos.isNotEmpty) ...[
            const ZenSectionTitle('事 务'),
            _Quad(
              cells: [
                (value: '${todoSummary.doing}', label: '进 行 中'),
                (value: '${todoSummary.done}', label: '已 完 成'),
                (value: '${todoSummary.averageProgress}%', label: '平 均 进 度'),
                (value: '${todoSummary.totalPushes} 次', label: '累 计 推 进'),
              ],
            ),
            if (recentDone.isNotEmpty) ...[
              const SizedBox(height: 30),
              for (final todo in recentDone.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          todo.text.split('\n').first,
                          overflow: TextOverflow.ellipsis,
                          style: inkText(context, size: 11, spacing: 0.5),
                        ),
                      ),
                      Text(
                        _shortDate(todo.completedAt!),
                        style: TextStyle(fontSize: 12, color: palette.inkSoft),
                      ),
                    ],
                  ),
                ),
            ],
          ],
          if (controller.growth.totalExp > 0 ||
              controller.growth.insights.isNotEmpty) ...[
            const ZenSectionTitle('隐 修'),
            _GrowthSummary(
              growth: controller.growth,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => GrowthPage(controller: controller),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final values = toList();
    return values.skip(math.max(0, values.length - count));
  }
}

class _StatsOverview extends StatelessWidget {
  const _StatsOverview({required this.summary});

  final StatsSummary summary;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Container(
      key: const ValueKey('stats-overview'),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: palette.paperDeep.withValues(alpha: palette.isInk ? 0.42 : 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.ink.withValues(alpha: 0.075)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '今 日 专 注',
                      style: inkText(
                        context,
                        size: 12,
                        color: palette.inkSoft,
                        spacing: 3.5,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      formatDuration(summary.todaySec),
                      style: TextStyle(
                        fontSize: 30,
                        height: 1,
                        color: palette.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(width: 26, height: 2, color: palette.work),
                  ],
                ),
              ),
              Text(
                '落笔 ${summary.todayCount} 次',
                style: TextStyle(fontSize: 12, color: palette.inkSoft),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 1, color: palette.inkFaint),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _OverviewMetric(
                  label: '本 周',
                  value: formatDuration(summary.weekSec),
                ),
              ),
              _OverviewDivider(color: palette.inkFaint),
              Expanded(
                child: _OverviewMetric(
                  label: '连 续',
                  value: '${summary.streakDays} 天',
                ),
              ),
              _OverviewDivider(color: palette.inkFaint),
              Expanded(
                child: _OverviewMetric(
                  label: '累 计',
                  value: formatDuration(summary.totalSec),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14,
            color: palette.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: inkText(
            context,
            size: 8.5,
            color: palette.inkSoft,
            spacing: 2.5,
          ),
        ),
      ],
    );
  }
}

class _OverviewDivider extends StatelessWidget {
  const _OverviewDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 28,
    margin: const EdgeInsets.symmetric(horizontal: 5),
    color: color,
  );
}

class _StatsChartCard extends StatelessWidget {
  const _StatsChartCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.child,
  });

  final String title;
  final String subtitle;
  final String value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        color: palette.paperDeep.withValues(alpha: palette.isInk ? 0.42 : 0.54),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.ink.withValues(alpha: 0.075)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: inkText(context, size: 12, spacing: 3)),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: inkText(
                        context,
                        size: 12,
                        color: palette.inkSoft,
                        spacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10.5,
                  color: palette.inkSoft,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _HeatmapChart extends StatelessWidget {
  const _HeatmapChart({required this.days});

  final List<DayBucket> days;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Column(
      children: [
        SizedBox(
          height: 172,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gutterWidth = 18.0;
              const gutterGap = 7.0;
              final chartWidth = math.max(
                0.0,
                constraints.maxWidth - gutterWidth - gutterGap,
              );
              final geometry = layoutHeatmapGrid(
                Size(chartWidth, constraints.maxHeight),
              );
              const labels = [(0, '一'), (2, '三'), (4, '五'), (6, '日')];
              return Row(
                children: [
                  SizedBox(
                    width: gutterWidth,
                    height: constraints.maxHeight,
                    child: Stack(
                      children: [
                        for (final (row, label) in labels)
                          Positioned(
                            top: geometry.cellRect(row).center.dy - 5,
                            left: 0,
                            right: 0,
                            height: 10,
                            child: Center(
                              child: Text(
                                label,
                                style: _chartAxisStyle(palette),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: gutterGap),
                  Expanded(
                    child: SizedBox.expand(
                      key: const ValueKey('stats-heatmap-chart'),
                      child: CustomPaint(
                        painter: _HeatmapPainter(days, palette),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 11),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('少', style: _chartAxisStyle(palette)),
            const SizedBox(width: 6),
            for (var level = 0; level <= 5; level++) ...[
              Container(
                key: ValueKey('stats-heat-level-$level'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: heatmapCellColor(palette, level),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              if (level < 5) const SizedBox(width: 3),
            ],
            const SizedBox(width: 6),
            Text('多', style: _chartAxisStyle(palette)),
          ],
        ),
      ],
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.strength,
  });

  final String label;
  final String value;
  final Color accent;
  final double strength;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final safeStrength = strength.clamp(0.0, 1.0);
    return Container(
      height: 98,
      padding: const EdgeInsets.fromLTRB(11, 13, 11, 11),
      decoration: BoxDecoration(
        color: palette.paperDeep.withValues(alpha: palette.isInk ? 0.42 : 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.ink.withValues(alpha: 0.075)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            style: inkText(
              context,
              size: 11,
              color: palette.inkSoft,
              spacing: 1.7,
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 16,
              color: palette.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              minHeight: 2,
              value: safeStrength,
              backgroundColor: palette.inkFaint,
              valueColor: AlwaysStoppedAnimation(accent.withValues(alpha: 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _chartAxisStyle(ZenPalette palette) => TextStyle(
  fontSize: 8.5,
  height: 1,
  color: palette.inkSoft.withValues(alpha: 0.82),
  fontFeatures: const [FontFeature.tabularFigures()],
);

String _peakHourLabel(List<int> hours) {
  if (hours.isEmpty || hours.every((value) => value == 0)) return '尚无峰值';
  var peak = 0;
  for (var index = 1; index < hours.length; index++) {
    if (hours[index] > hours[peak]) peak = index;
  }
  return '${peak.toString().padLeft(2, '0')}:00 · 最投入';
}

class _GrowthSummary extends StatelessWidget {
  const _GrowthSummary({required this.growth, required this.onTap});

  final HiddenGrowth growth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        key: const ValueKey('stats-growth-summary'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          decoration: BoxDecoration(
            color: palette.paperDeep.withValues(
              alpha: palette.isInk ? 0.42 : 0.5,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.ink.withValues(alpha: 0.075)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '隐 修 等 级  ${growth.level}',
                  style: inkText(context, size: 11, spacing: 2),
                ),
              ),
              Text(
                '${growth.totalExp} 经 验 · 已 悟 ${growth.insights.length}',
                style: TextStyle(fontSize: 12, color: palette.inkSoft),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: palette.inkSoft,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Quad extends StatelessWidget {
  const _Quad({required this.cells});

  final List<({String value, String label})> cells;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 2.35,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: [
        for (final cell in cells)
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                cell.value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 18,
                  color: palette.ink,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                cell.label,
                style: inkText(
                  context,
                  size: 11,
                  color: palette.inkSoft,
                  spacing: 3,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _KindLine extends StatelessWidget {
  const _KindLine({
    required this.color,
    required this.name,
    required this.stat,
    required this.totalSec,
  });

  final Color color;
  final String name;
  final KindStat stat;
  final int totalSec;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final percentage = totalSec == 0 ? 0 : (stat.sec / totalSec * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$name · ${stat.count}',
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: inkText(context, size: 12, spacing: 1),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${formatDuration(stat.sec)}  $percentage%',
            style: TextStyle(
              fontSize: 9.5,
              color: palette.inkSoft,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _HorizontalBar extends StatelessWidget {
  const _HorizontalBar({
    required this.label,
    required this.value,
    required this.max,
  });

  final String label;
  final int value;
  final int max;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: palette.inkSoft),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: max == 0 ? 0 : constraints.maxWidth * value / max,
                  height: 2,
                  color: palette.work.withValues(alpha: 0.62),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: palette.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateBar extends StatelessWidget {
  const _TemplateBar({required this.stat, required this.max});

  final TemplateStat stat;
  final int max;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              stat.label,
              overflow: TextOverflow.ellipsis,
              style: inkText(context, size: 12, spacing: 1.5),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: max == 0 ? 0 : constraints.maxWidth * stat.sec / max,
                  height: 2,
                  color: palette.ink.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              formatDuration(stat.sec),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: palette.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.stats, this.palette);

  final Map<TemplateKind, KindStat> stats;
  final ZenPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final total = stats.values.fold(0, (sum, stat) => sum + stat.sec);
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.37;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..color = palette.inkFaint;
    canvas.drawCircle(center, radius, base);
    if (total == 0) return;
    var start = -math.pi / 2;
    final colors = {
      TemplateKind.pomodoro: palette.work,
      TemplateKind.interval: palette.work.withValues(alpha: 0.45),
      TemplateKind.accumulate: palette.work.withValues(alpha: 0.2),
    };
    for (final kind in TemplateKind.values) {
      final sweep = math.pi * 2 * stats[kind]!.sec / total;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 7
          ..color = colors[kind]!,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

class _HeatmapPainter extends CustomPainter {
  const _HeatmapPainter(this.days, this.palette);

  final List<DayBucket> days;
  final ZenPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = layoutHeatmapGrid(size);
    if (geometry.cell <= 0) return;
    final entries = alignHeatmapDays(days);
    final radius = Radius.circular(math.max(2, geometry.cell * 0.16));

    for (var slot = 0; slot < geometry.columns * geometry.rows; slot++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(geometry.cellRect(slot), radius),
        Paint()..color = heatmapCellColor(palette, 0),
      );
    }

    for (final entry in entries) {
      final level = heatDepthLevel(
        seconds: entry.day.sec,
        count: entry.day.count,
      );
      if (level == 0) continue;
      final rect = RRect.fromRectAndRadius(
        geometry.cellRect(entry.slot),
        radius,
      );
      canvas.drawRRect(rect, Paint()..color = heatmapCellColor(palette, level));
    }

    if (entries.isNotEmpty) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(geometry.cellRect(entries.last.slot), radius),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = palette.ink.withValues(alpha: 0.30),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) => true;
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter(this.days, this.palette);

  final Iterable<DayBucket> days;
  final ZenPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final values = days.toList();
    if (values.isEmpty) return;
    final geometry = layoutSmoothTrend(
      values.map((day) => day.sec).toList(),
      size,
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 14),
    );
    if (geometry.points.isEmpty) return;
    final chartBottom = size.height - 14;

    canvas.drawLine(
      Offset(0, chartBottom),
      Offset(size.width, chartBottom),
      Paint()
        ..strokeWidth = 0.8
        ..color = palette.inkFaint,
    );

    final path = geometry.toPath();
    final area = Path()
      ..moveTo(geometry.points.first.dx, chartBottom)
      ..lineTo(geometry.points.first.dx, geometry.points.first.dy);
    for (final segment in geometry.segments) {
      area.cubicTo(
        segment.control1.dx,
        segment.control1.dy,
        segment.control2.dx,
        segment.control2.dy,
        segment.end.dx,
        segment.end.dy,
      );
    }
    area
      ..lineTo(geometry.points.last.dx, chartBottom)
      ..close();

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.work.withValues(alpha: 0.06),
            palette.work.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 10, size.width, chartBottom - 10)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..color = palette.work.withValues(alpha: 0.82),
    );

    final maxSec = values.map((day) => day.sec).fold(0, math.max);
    final maxIndex = values.indexWhere((day) => day.sec == maxSec);
    for (final index in {maxIndex, geometry.points.length - 1}) {
      final point = geometry.points[index];
      canvas.drawCircle(point, 3.2, Paint()..color = palette.paper);
      canvas.drawCircle(
        point,
        3.2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = palette.work,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}

class _HourPainter extends CustomPainter {
  const _HourPainter(this.hours, this.palette);

  final List<int> hours;
  final ZenPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = hours.fold(0, math.max);
    final width = size.width / 24;
    final baseline = size.height - 13;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..strokeWidth = 0.7
        ..color = palette.inkFaint,
    );
    for (var index = 0; index < 24; index++) {
      final ratio = maxValue == 0 ? 0.0 : hours[index] / maxValue;
      final height = ratio * (size.height - 26);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          index * width + 1.5,
          baseline - math.max(2, height),
          math.max(1, width - 3),
          math.max(2, height),
        ),
        Radius.circular(math.max(1, width * 0.23)),
      );
      final color = hours[index] == 0
          ? palette.inkFaint.withValues(alpha: 0.42)
          : Color.lerp(
              palette.work.withValues(alpha: 0.28),
              palette.work,
              ratio,
            )!;
      canvas.drawRRect(rect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _HourPainter oldDelegate) => true;
}

String _shortDate(int milliseconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${date.month} 月 ${date.day} 日';
}
