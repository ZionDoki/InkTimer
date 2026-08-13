import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/defaults.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/schedule.dart';

void main() {
  TimerTemplate byId(String id) =>
      builtinTemplates.firstWhere((template) => template.id == id);

  group('番茄编排', () {
    test('四轮末尾包含十五分钟长休', () {
      final phases = compileTemplate(byId('builtin.pomodoro'));
      expect(
        phases.where((phase) => phase.kind == PhaseKind.work),
        hasLength(4),
      );
      expect(
        phases.where((phase) => phase.kind == PhaseKind.longRest),
        hasLength(1),
      );
      expect(phases.last.kind, PhaseKind.longRest);
      expect(phases.last.durationSec, 15 * 60);
      expect(phases.last.round, 4);
      expect(plannedDurationSec(phases), 130 * 60);
    });

    test('长休周期会替换命中轮的普通休息并包含末轮', () {
      const template = TimerTemplate(
        id: 'x',
        label: 'x',
        kind: TemplateKind.pomodoro,
        createdAt: 0,
        focusSec: 100,
        breakSec: 10,
        rounds: 4,
        longBreakSec: 99,
        longBreakEvery: 2,
      );
      final phases = compileTemplate(template);
      expect(phases.map((phase) => phase.kind), [
        PhaseKind.work,
        PhaseKind.rest,
        PhaseKind.work,
        PhaseKind.longRest,
        PhaseKind.work,
        PhaseKind.rest,
        PhaseKind.work,
        PhaseKind.longRest,
      ]);
    });
  });

  group('间歇编排', () {
    test('Tabata 为八段工作、七段休息且末尾无休', () {
      final phases = compileTemplate(byId('builtin.tabata'));
      expect(
        phases.where((phase) => phase.kind == PhaseKind.work),
        hasLength(8),
      );
      expect(
        phases.where((phase) => phase.kind == PhaseKind.rest),
        hasLength(7),
      );
      expect(phases.last.kind, PhaseKind.work);
      expect(plannedDurationSec(phases), 8 * 20 + 7 * 10);
    });

    test('零秒休息不产生休息相位', () {
      const template = TimerTemplate(
        id: 'x',
        label: 'x',
        kind: TemplateKind.interval,
        createdAt: 0,
        workSec: 20,
        restSec: 0,
        rounds: 4,
      );
      final phases = compileTemplate(template);
      expect(phases, hasLength(4));
      expect(phases.every((phase) => phase.kind == PhaseKind.work), isTrue);
    });

    test('多式间歇优先于均匀字段', () {
      const template = TimerTemplate(
        id: 'h',
        label: 'h',
        kind: TemplateKind.interval,
        createdAt: 0,
        workSec: 999,
        restSec: 999,
        rounds: 2,
        phases: [
          HiitPair(workSec: 40, restSec: 20),
          HiitPair(workSec: 30, restSec: 10),
        ],
      );
      expect(
        compileTemplate(
          template,
        ).map((phase) => '${phase.kind.wire}:${phase.durationSec}'),
        [
          'work:40',
          'rest:20',
          'work:30',
          'rest:10',
          'work:40',
          'rest:20',
          'work:30',
        ],
      );
    });
  });

  group('统一自由编排', () {
    test('完整重复一轮的所有阶段并保留角色', () {
      const template = TimerTemplate(
        id: 's',
        label: 's',
        kind: TemplateKind.interval,
        createdAt: 0,
        rounds: 2,
        sequence: [
          SequencePhase(role: SequencePhaseRole.prepare, durationSec: 5),
          SequencePhase(role: SequencePhaseRole.work, durationSec: 20),
          SequencePhase(role: SequencePhaseRole.rest, durationSec: 10),
        ],
      );
      expect(
        compileTemplate(template).map(
          (phase) =>
              '${phase.role?.wire}:${phase.kind.wire}:${phase.durationSec}:${phase.round}',
        ),
        [
          'prepare:rest:5:1',
          'work:work:20:1',
          'rest:rest:10:1',
          'prepare:rest:5:2',
          'work:work:20:2',
          'rest:rest:10:2',
        ],
      );
    });

    test('长休替换最后一个休息；无休息时追加', () {
      const withRest = TimerTemplate(
        id: 's',
        label: 's',
        kind: TemplateKind.pomodoro,
        createdAt: 0,
        rounds: 2,
        sequence: [
          SequencePhase(role: SequencePhaseRole.focus, durationSec: 100),
          SequencePhase(role: SequencePhaseRole.rest, durationSec: 10),
        ],
        longBreakEvery: 2,
        longBreakSec: 99,
      );
      expect(
        compileTemplate(
          withRest,
        ).map((phase) => '${phase.kind.wire}:${phase.durationSec}'),
        ['work:100', 'rest:10', 'work:100', 'longRest:99'],
      );

      const withoutRest = TimerTemplate(
        id: 'n',
        label: 'n',
        kind: TemplateKind.interval,
        createdAt: 0,
        rounds: 2,
        sequence: [
          SequencePhase(role: SequencePhaseRole.work, durationSec: 20),
        ],
        longBreakEvery: 2,
        longBreakSec: 30,
      );
      expect(
        compileTemplate(
          withoutRest,
        ).map((phase) => '${phase.kind.wire}:${phase.durationSec}'),
        ['work:20', 'work:20', 'longRest:30'],
      );
    });

    test('统一阶段优先于全部旧制字段', () {
      const template = TimerTemplate(
        id: 's',
        label: 's',
        kind: TemplateKind.interval,
        createdAt: 0,
        rounds: 1,
        workSec: 999,
        phases: [HiitPair(workSec: 888, restSec: 888)],
        sequence: [
          SequencePhase(role: SequencePhaseRole.focus, durationSec: 12),
        ],
      );
      final phase = compileTemplate(template).single;
      expect(phase.kind, PhaseKind.work);
      expect(phase.role, SequencePhaseRole.focus);
      expect(phase.durationSec, 12);
    });
  });

  test('专注时长与跨相位区间只计算工作段', () {
    const phases = [
      Phase(kind: PhaseKind.work, durationSec: 20, round: 1, roundsTotal: 1),
      Phase(kind: PhaseKind.rest, durationSec: 10, round: 1, roundsTotal: 1),
      Phase(kind: PhaseKind.work, durationSec: 20, round: 1, roundsTotal: 1),
    ];
    expect(totalFocusSec(phases), 40);
    expect(focusOverlapSec(phases, 0, 50), 40);
    expect(focusOverlapSec(phases, 15, 35), 10);
    expect(focusOverlapSec(phases, 20, 30), 0);
    expect(elapsedSecAtSnapshot(phases, index: 1, phaseRemainingMs: 5000), 25);
  });

  test('已完成轮次要求本轮全部工作相位结束', () {
    const template = TimerTemplate(
      id: 'h',
      label: 'h',
      kind: TemplateKind.interval,
      createdAt: 0,
      rounds: 2,
      phases: [
        HiitPair(workSec: 40, restSec: 20),
        HiitPair(workSec: 30, restSec: 10),
      ],
    );
    final phases = compileTemplate(template);
    expect(completedRounds(phases, 1), 0);
    expect(completedRounds(phases, 2), 0);
    expect(completedRounds(phases, 3), 1);
    expect(completedRounds(phases, 4), 1);
  });

  test('积累模板不编译倒计时相位', () {
    expect(
      () => compileTemplate(byId('builtin.cardio')),
      throwsA(isA<ArgumentError>()),
    );
  });
}
