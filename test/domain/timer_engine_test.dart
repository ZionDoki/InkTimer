import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/schedule.dart';
import 'package:uptimer/domain/timer_engine.dart';

const phases = <Phase>[
  Phase(kind: PhaseKind.work, durationSec: 4, round: 1, roundsTotal: 2),
  Phase(kind: PhaseKind.rest, durationSec: 2, round: 1, roundsTotal: 2),
  Phase(kind: PhaseKind.work, durationSec: 4, round: 2, roundsTotal: 2),
];

class Harness {
  double now = 0;
  final events = <TimerEvent>[];
  late final TimerEngine engine = TimerEngine(nowMs: () => now)
    ..addListener(events.add);

  void advance(double milliseconds) {
    now += milliseconds;
    engine.update();
  }
}

void main() {
  group('倒计时状态机', () {
    late Harness harness;

    setUp(() {
      harness = Harness();
      harness.engine.load(phases);
    });

    test('开始发送 start 与 phaseStart', () {
      harness.engine.start();
      expect(harness.events.map((event) => event.type), [
        TimerEventType.start,
        TimerEventType.phaseStart,
      ]);
      expect(harness.engine.status, TimerStatus.running);
    });

    test('整秒 tick 与最后三秒 countdown', () {
      harness.engine.start();
      harness.advance(1000);
      harness.advance(1000);
      harness.advance(1000);
      expect(
        harness.events
            .where((event) => event.type == TimerEventType.countdown)
            .map((event) => event.sec),
        [3, 2, 1],
      );
    });

    test('相位结束后自动进入下一相位', () {
      harness.engine.start();
      harness.advance(4100);
      final starts = harness.events
          .where((event) => event.type == TimerEventType.phaseStart)
          .toList();
      expect(starts, hasLength(2));
      expect(starts.last.phase?.kind, PhaseKind.rest);
      expect(harness.engine.remainSec(), 2);
    });

    test('全部相位结束完成且已用时等于计划', () {
      harness.engine.start();
      harness.advance(60 * 1000);
      expect(harness.engine.status, TimerStatus.done);
      expect(
        harness.events.map((event) => event.type),
        contains(TimerEventType.complete),
      );
      expect(harness.engine.elapsedSec(), 10);
    });

    test('暂停冻结，恢复从剩余时间续走', () {
      harness.engine.start();
      harness.advance(1000);
      harness.engine.pause();
      harness.advance(60 * 1000);
      expect(harness.engine.remainSec(), 3);
      harness.engine.resume();
      harness.advance(3100);
      expect(harness.engine.currentPhase()?.kind, PhaseKind.rest);
    });

    test('stop 返回 idle 并携带向上取整的已用秒数', () {
      harness.engine.start();
      harness.advance(2500);
      harness.engine.stop();
      expect(harness.engine.status, TimerStatus.idle);
      final stop = harness.events.lastWhere(
        (event) => event.type == TimerEventType.stop,
      );
      expect(stop.elapsedSec, 3);
    });

    test('部分后台追赶落在正确相位且不重新锚定', () {
      harness.engine.start();
      harness.advance(5000);
      expect(harness.engine.currentPhase()?.kind, PhaseKind.rest);
      expect(harness.engine.remainSec(), 1);
      expect(harness.engine.phaseProgress(), closeTo(0.5, 0.01));
    });

    test('追赶事件监听器同步暂停不会再发送 tick', () {
      final local = Harness();
      local.engine.load(phases);
      local.engine.addListener((event) {
        if (event.type == TimerEventType.phaseStart && event.index == 1) {
          local.engine.pause();
        }
      });
      local.engine.start();
      local.advance(5000);
      expect(local.engine.status, TimerStatus.paused);
      expect(local.engine.currentPhase()?.kind, PhaseKind.rest);
      expect(local.events.last.type, TimerEventType.pause);
    });
  });

  group('开放式正计时', () {
    test('只发 start，按秒增长且永不自动完成', () {
      final harness = Harness();
      harness.engine.loadCountUp();
      harness.engine.start();
      harness.advance(3500);
      expect(harness.engine.currentPhase(), isNull);
      expect(harness.engine.phaseProgress(), 0);
      expect(harness.engine.remainSec(), 3);
      expect(harness.engine.elapsedSec(), 3);
      expect(harness.engine.status, TimerStatus.running);
      expect(
        harness.events.where(
          (event) => event.type == TimerEventType.phaseStart,
        ),
        isEmpty,
      );
    });

    test('暂停时间不计入，恢复后继续累加', () {
      final harness = Harness();
      harness.engine.loadCountUp();
      harness.engine.start();
      harness.advance(2500);
      harness.engine.pause();
      harness.advance(60000);
      expect(harness.engine.elapsedSec(), 2);
      harness.engine.resume();
      harness.advance(1600);
      expect(harness.engine.elapsedSec(), 4);
    });

    test('stop 携带向下取整的已用秒数', () {
      final harness = Harness();
      harness.engine.loadCountUp();
      harness.engine.start();
      harness.advance(2500);
      harness.engine.stop();
      final stop = harness.events.lastWhere(
        (event) => event.type == TimerEventType.stop,
      );
      expect(stop.elapsedSec, 2);
    });
  });

  test('默认计时源由单调时钟工厂提供', () async {
    final now = createMonotonicClock();
    final before = now();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(now(), greaterThanOrEqualTo(before));
  });

  group('检查点恢复', () {
    test('运行中的倒计时按离线墙钟追赶', () {
      final source = Harness();
      source.engine.load(phases);
      source.engine.start();
      source.advance(1000);
      final snapshot = source.engine.snapshot(savedAtMs: 10 * 1000)!;

      final restored = Harness();
      expect(
        restored.engine.restore(phases, snapshot, restoredAtMs: 12 * 1000),
        isTrue,
      );
      restored.engine.update();
      expect(restored.engine.currentPhase()?.kind, PhaseKind.work);
      expect(restored.engine.remainSec(), 1);
    });

    test('暂停快照恢复后不计算离线时间', () {
      final source = Harness();
      source.engine.load(phases);
      source.engine.start();
      source.advance(1000);
      source.engine.pause();
      final snapshot = source.engine.snapshot(savedAtMs: 10 * 1000)!;

      final restored = Harness();
      expect(
        restored.engine.restore(phases, snapshot, restoredAtMs: 90 * 1000),
        isTrue,
      );
      expect(restored.engine.status, TimerStatus.paused);
      expect(restored.engine.remainSec(), 3);
    });

    test('运行中的正计时恢复后包含离线时长', () {
      final source = Harness();
      source.engine.loadCountUp();
      source.engine.start();
      source.advance(2500);
      final snapshot = source.engine.snapshot(savedAtMs: 10 * 1000)!;

      final restored = Harness();
      expect(
        restored.engine.restore(const [], snapshot, restoredAtMs: 15 * 1000),
        isTrue,
      );
      expect(restored.engine.elapsedSec(), 7);
    });

    test('非法索引的倒计时快照拒绝恢复', () {
      final restored = Harness();
      const snapshot = TimerSnapshot(
        mode: TimerMode.countdown,
        status: TimerStatus.running,
        index: 99,
        phaseRemainingMs: 1000,
        countUpElapsedMs: 0,
        savedAt: 0,
      );
      expect(restored.engine.restore(phases, snapshot), isFalse);
    });
  });
}
