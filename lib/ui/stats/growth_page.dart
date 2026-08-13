import 'package:flutter/material.dart';

import '../../domain/growth.dart';
import '../../domain/growth_models.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/app_controller.dart';
import '../theme/zen_theme.dart';
import '../widgets/zen_page.dart';

/// 隐修履历：只显示已悟的条目，未悟的不列出——不做成就清单式的待办感。
class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
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
    final growth = controller.growth;
    final cultivated =
        controller.todos.where((todo) => todo.totalFocusSec > 0).toList()
          ..sort((a, b) => b.totalFocusSec.compareTo(a.totalFocusSec));
    final linkedSec = cultivated.fold<int>(
      0,
      (total, todo) => total + todo.totalFocusSec,
    );
    final summary = summarizeSessions(controller.sessions, DateTime.now());
    final recentQuality = recentMeasuredQualityAverage(controller.sessions);
    final unlocked = [
      for (final id in growth.insights)
        if (!sealInsightIds.contains(id)) ?insightById(id),
    ];
    final earnedSeals = sealMarks
        .where((mark) => growth.insights.contains(mark.insightId))
        .toList();

    return ZenPage(
      title: '隐 修 履 历',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LevelBand(growth: growth),
          if (unlocked.isEmpty && cultivated.isEmpty && earnedSeals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 72),
              child: Text(
                '尚 未 有 悟 · 只 管 去 坐',
                textAlign: TextAlign.center,
                style: inkText(
                  context,
                  size: 12,
                  color: palette.inkSoft,
                  spacing: 5,
                ),
              ),
            ),
          if (earnedSeals.isNotEmpty) ...[
            const ZenSectionTitle('印 记'),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 连续天数只用朱印说一遍，不在下面的文字列表里重复。
                for (final mark in earnedSeals)
                  ZenSeal(
                    key: ValueKey('growth-seal-${mark.insightId}'),
                    mark.character,
                    earned: true,
                  ),
              ],
            ),
          ],
          if (unlocked.isNotEmpty) ...[
            const ZenSectionTitle('已 悟'),
            for (final def in unlocked)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        def.name,
                        style: inkText(context, size: 13, spacing: 2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        [
                          def.description,
                          if (growth.insightUnlockedAt[def.id] case final at?)
                            _shortUnlockDate(at),
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: palette.inkSoft),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (summary.measuredQualityCount > 0 ||
              summary.legacyQualityCount > 0) ...[
            const ZenSectionTitle('定 力'),
            Text(
              summary.measuredQualityCount == 0
                  ? '旧 记 录 未 采 集 定 力'
                  : '近 十 次 平 均 ${recentQuality.round()}'
                        '${summary.legacyQualityCount > 0 ? ' · 旧记录未采集 ${summary.legacyQualityCount}' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: palette.inkSoft),
            ),
          ],
          if (cultivated.isNotEmpty) ...[
            const ZenSectionTitle('深 耕 档 案'),
            for (final todo in cultivated)
              _CultivationRow(
                key: ValueKey('cultivation-${todo.id}'),
                todo: todo,
              ),
            const SizedBox(height: 22),
            Text(
              summary.totalSec == 0
                  ? '目 标 协 同  尚 无'
                  : '目 标 协 同  ${(linkedSec / summary.totalSec * 100).clamp(0, 100).round()}%'
                        ' · 计 ${formatDuration(linkedSec)}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: palette.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

String _shortUnlockDate(int milliseconds) {
  final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  return '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
}

class _LevelBand extends StatelessWidget {
  const _LevelBand({required this.growth});

  final HiddenGrowth growth;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final floor = levelToExp(growth.level);
    final span = levelToNextExp(growth.level);
    final gained = (growth.totalExp - floor).clamp(0, span == 0 ? 1 : span);
    final ratio = span == 0 ? 1.0 : gained / span;
    return Column(
      children: [
        Text(
          '${growth.level}',
          style: TextStyle(
            fontFamily: 'Cormorant',
            fontSize: 58,
            height: 1,
            color: palette.ink,
          ).variableWeight,
        ),
        const SizedBox(height: 8),
        Text(
          '隐 修 等 级',
          style: inkText(context, size: 12, color: palette.inkSoft, spacing: 5),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            key: const ValueKey('growth-level-progress'),
            value: ratio.toDouble(),
            minHeight: 2,
            backgroundColor: palette.inkFaint,
            valueColor: AlwaysStoppedAnimation<Color>(
              palette.ink.withValues(alpha: 0.45),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          span == 0
              ? '${growth.totalExp} 经 验 · 已 至 尽 处'
              : '${growth.totalExp} 经 验 · 再 ${span - gained} 入 次 阶',
          style: TextStyle(fontSize: 12, color: palette.inkSoft),
        ),
      ],
    );
  }
}

class _CultivationRow extends StatelessWidget {
  const _CultivationRow({super.key, required this.todo});

  final TodoItem todo;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  todo.text.split('\n').first,
                  overflow: TextOverflow.ellipsis,
                  style: inkText(context, size: 12, spacing: 0.6),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                todoTierLabel(todo.totalFocusSec),
                style: inkText(
                  context,
                  size: 12,
                  color: palette.workSoft,
                  spacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${todo.sessionsLinked} 次 · ${formatDuration(todo.totalFocusSec)}'
            ' · ${todoLinkBonus(todo).toStringAsFixed(2)}x'
            ' · 进 度 ${todo.progress}%',
            style: TextStyle(fontSize: 12, color: palette.inkSoft),
          ),
        ],
      ),
    );
  }
}
