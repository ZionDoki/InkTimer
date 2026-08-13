import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/composer.dart';
import 'package:uptimer/domain/defaults.dart';
import 'package:uptimer/domain/markdown.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/schedule.dart';
import 'package:uptimer/domain/sounds.dart';
import 'package:uptimer/domain/stats.dart';

SessionRecord session({
  required String id,
  required DateTime started,
  int seconds = 600,
  bool completed = true,
  TemplateKind kind = TemplateKind.pomodoro,
  int interruptions = 0,
}) => SessionRecord(
  id: id,
  templateId: 'template.${kind.wire}',
  label: kind.wire,
  kind: kind,
  startedAt: started.millisecondsSinceEpoch,
  endedAt: started.add(Duration(seconds: seconds)).millisecondsSinceEpoch,
  plannedSec: seconds,
  elapsedSec: seconds,
  completed: completed,
  roundsDone: completed ? 1 : 0,
  roundsTotal: 1,
  interruptions: interruptions,
);

void main() {
  group('统计聚合', () {
    final now = DateTime(2026, 8, 7, 23, 59);

    test('空记录全零、84 日桶齐全', () {
      final summary = summarizeSessions(const [], now);
      expect(summary.todaySec, 0);
      expect(summary.totalCount, 0);
      expect(summary.streakDays, 0);
      expect(summary.zeroInterruptRate, 0);
      expect(summary.daily, hasLength(84));
      expect(summary.byHour, hasLength(24));
    });

    test('今日、本周、累计、类型与模板聚合', () {
      final sessions = [
        session(id: 'today', started: DateTime(2026, 8, 7, 9), seconds: 1200),
        session(
          id: 'week',
          started: DateTime(2026, 8, 4, 18),
          seconds: 300,
          kind: TemplateKind.interval,
        ),
        session(
          id: 'old',
          started: DateTime(2026, 7, 30),
          seconds: 60,
          kind: TemplateKind.accumulate,
        ),
      ];
      final summary = summarizeSessions(sessions, now);
      expect(summary.todaySec, 1200);
      expect(summary.todayCount, 1);
      expect(summary.weekSec, 1500);
      expect(summary.totalSec, 1560);
      expect(summary.totalCount, 3);
      expect(summary.byKind[TemplateKind.interval]?.sec, 300);
      expect(summary.byTemplate, hasLength(3));
    });

    test('连续天数今天无完成时从昨天倒数并可跨月', () {
      final summary = summarizeSessions([
        session(id: 'a', started: DateTime(2026, 8, 6)),
        session(id: 'b', started: DateTime(2026, 8, 5)),
        session(id: 'c', started: DateTime(2026, 8, 4)),
        session(
          id: 'incomplete',
          started: DateTime(2026, 8, 7),
          completed: false,
        ),
      ], now);
      expect(summary.streakDays, 3);
    });

    test('打断、小时、时长分布、最长场次', () {
      final items = [
        session(
          id: 'a',
          started: DateTime(2026, 8, 7, 9),
          seconds: 299,
          interruptions: 0,
        ),
        session(
          id: 'b',
          started: DateTime(2026, 8, 7, 9, 30),
          seconds: 300,
          interruptions: 2,
        ),
        session(
          id: 'c',
          started: DateTime(2026, 8, 7, 22),
          seconds: 3601,
          interruptions: 1,
        ),
      ];
      final summary = summarizeSessions(items, now);
      expect(summary.totalInterruptions, 3);
      expect(summary.zeroInterruptRate, closeTo(1 / 3, 0.001));
      expect(summary.byHour[9], 2);
      expect(summary.byHour[22], 1);
      expect(summary.durationBuckets.map((bucket) => bucket.count), [
        1,
        1,
        0,
        0,
        1,
      ]);
      expect(summary.longestSessionSec, 3601);
    });

    test('TODO 快照统计与时长格式', () {
      const todos = [
        TodoItem(id: 'a', text: 'a', progress: 25, pushes: 2, createdAt: 0),
        TodoItem(id: 'b', text: 'b', progress: 100, pushes: 3, createdAt: 0),
      ];
      final summary = summarizeTodos(todos);
      expect(summary.doing, 1);
      expect(summary.done, 1);
      expect(summary.averageProgress, 63);
      expect(summary.totalPushes, 5);
      expect(formatDuration(10), '10s');
      expect(formatDuration(3600), '1h');
      expect(formatDuration(3660), '1h 1m');
    });

    test('归档事项不进入进行中、完成与进度统计', () {
      const todos = [
        TodoItem(id: 'a', text: '进行', progress: 20, pushes: 2, createdAt: 0),
        TodoItem(
          id: 'b',
          text: '归档',
          progress: 80,
          pushes: 9,
          createdAt: 0,
          archivedAt: 1,
        ),
      ];
      final summary = summarizeTodos(todos);
      expect(summary.doing, 1);
      expect(summary.done, 0);
      expect(summary.averageProgress, 20);
      expect(summary.totalPushes, 2);
    });

    test('未来会话不污染今日、本周与累计统计', () {
      final summary = summarizeSessions([
        session(id: 'future', started: DateTime(2026, 8, 20)),
      ], now);
      expect(summary.todaySec, 0);
      expect(summary.weekSec, 0);
      expect(summary.totalSec, 0);
      expect(summary.totalCount, 0);
    });
  });

  group('极简 Markdown', () {
    test('整体转义 HTML，无注入面', () {
      expect(
        renderMarkdown('<script>alert("x")</script>'),
        '<p>&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;</p>',
      );
    });

    test('标题、列表、段落与行内样式', () {
      final html = renderMarkdown('# **题**\n\n- *甲*\n- `乙`\n\n正文');
      expect(
        html,
        '<h3><strong>题</strong></h3><ul><li><em>甲</em></li><li><code>乙</code></li></ul><p>正文</p>',
      );
    });

    test('仅 http(s) 链接可点，其余降级纯文字', () {
      final html = renderMarkdown(
        '[安全](https://example.com) [危险](javascript:alert(1))',
      );
      expect(html, contains('href="https://example.com"'));
      expect(html, isNot(contains('javascript:')));
      expect(html, contains('危险'));
    });
  });

  group('模板编排器', () {
    test('旧番茄字段归一为阶段并保留长休', () {
      const template = TimerTemplate(
        id: 'p',
        label: '番茄',
        kind: TemplateKind.pomodoro,
        createdAt: 0,
        focusSec: 1500,
        breakSec: 300,
        rounds: 4,
        longBreakEvery: 4,
        longBreakSec: 900,
      );
      final draft = templateToComposer(template);
      expect(draft.mode, ComposerMode.countdown);
      expect(draft.phases.map((phase) => phase.role), [
        SequencePhaseRole.focus,
        SequencePhaseRole.rest,
      ]);
      expect(draft.longBreakEvery, 4);
      expect(draft.longBreakSec, 900);
    });

    test('保存时只落统一阶段，积累模式为纯 accumulate', () {
      final draft = applyComposerPreset(
        newComposerDraft(id: 'x', now: 10),
        ComposerPreset.interval,
      );
      final template = composerToTemplate(draft);
      expect(template.kind, TemplateKind.interval);
      expect(template.sequence?.map((phase) => phase.durationSec), [20, 10]);
      expect(template.workSec, isNull);
      expect(template.phases, isNull);

      final countUp = composerToTemplate(
        applyComposerPreset(draft, ComposerPreset.countup),
      );
      expect(countUp.kind, TemplateKind.accumulate);
      expect(countUp.sequence, isNull);
      expect(countUp.rounds, isNull);
    });

    test('秒分钟只改变表示，内部始终为秒', () {
      expect(durationFromAmount('1.5', ComposerUnit.minute, 1), 90);
      expect(durationFromAmount('1,5', ComposerUnit.minute, 1), 90);
      expect(formatDurationAmount(90, ComposerUnit.minute), '1.5');
      expect(durationFromAmount('bad', ComposerUnit.second, 30), 30);
    });

    test('内置倒计时笺打开编辑后原样保存不改变实际编排', () {
      for (final original in builtinTemplates.where(
        (template) => template.kind != TemplateKind.accumulate,
      )) {
        final saved = composerToTemplate(templateToComposer(original));
        String signature(Phase phase) =>
            '${phase.kind.wire}:${phase.durationSec}:${phase.round}';
        expect(
          compileTemplate(saved).map(signature),
          compileTemplate(original).map(signature),
          reason: original.label,
        );
      }
    });
  });

  group('合成音色规格', () {
    test('工作与休息颂钵含基频加三泛音', () {
      expect(soundSpecs[SoundName.bowlWork], hasLength(4));
      expect(soundSpecs[SoundName.bowlWork]!.first.f0, 528);
      expect(soundSpecs[SoundName.bowlRest]!.first.f0, 396);
    });

    test('水滴、木鱼、完成双钵与蓄力参数保持一致', () {
      expect(soundSpecs[SoundName.plip]!.first.f0, 1150);
      expect(soundSpecs[SoundName.plip]!.first.f1, 380);
      expect(soundSpecs[SoundName.tick]!.first.duration, lessThan(0.15));
      expect(soundSpecs[SoundName.complete], hasLength(8));
      expect(soundSpecs[SoundName.complete]![4].f0, 396);
      expect(soundSpecs[SoundName.complete]![4].at, closeTo(0.48, 0.001));
      expect(soundSpecs[SoundName.charge]!.first.rampSec, 2.4);
    });
  });
}
