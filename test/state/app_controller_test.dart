import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/data/key_value_store.dart';
import 'package:uptimer/data/repository.dart';
import 'package:uptimer/domain/active_checkpoint.dart';
import 'package:uptimer/domain/defaults.dart';
import 'package:uptimer/domain/growth.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/sounds.dart';
import 'package:uptimer/domain/timer_engine.dart';
import 'package:uptimer/services/runtime_effects.dart';
import 'package:uptimer/state/app_controller.dart';

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};
  Duration sessionWriteDelay = Duration.zero;
  final sessionWriteCompleters = <Completer<void>>[];
  final failWrites = <String, int>{};
  final writeAttempts = <String, int>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, String value) async {
    writeAttempts[key] = (writeAttempts[key] ?? 0) + 1;
    final failuresRemaining = failWrites[key] ?? 0;
    if (failuresRemaining > 0) {
      failWrites[key] = failuresRemaining - 1;
      throw StateError('transient write failure: $key');
    }
    if (key == StorageKeys.sessions && sessionWriteCompleters.isNotEmpty) {
      await sessionWriteCompleters.removeAt(0).future;
    } else if (key == StorageKeys.sessions &&
        sessionWriteDelay > Duration.zero) {
      await Future<void>.delayed(sessionWriteDelay);
    }
    values[key] = value;
  }

  @override
  Future<void> flush() async {}
}

class FakeEffects implements RuntimeEffects {
  final sounds = <SoundName>[];
  final haptics = <HapticCue>[];
  final wakeStates = <bool>[];
  bool configuredEnabled = true;
  double configuredVolume = 0;

  @override
  bool get audioAvailable => true;

  @override
  void configureAudio({required bool enabled, required double volume}) {
    configuredEnabled = enabled;
    configuredVolume = volume;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> haptic(HapticCue cue) async => haptics.add(cue);

  @override
  Future<void> keepAwake(bool enabled) async => wakeStates.add(enabled);

  @override
  Future<void> play(SoundName sound) async => sounds.add(sound);
}

class Harness {
  Harness({Map<String, String>? initial, String? startupNotice}) {
    if (initial != null) store.values.addAll(initial);
    controller = AppController(
      repository: Repository(store),
      engine: TimerEngine(nowMs: () => monotonicMs),
      effects: effects,
      nowMs: () => wallMs,
      idFactory: () => 'id-${nextId++}',
      driveTicker: false,
      observeLifecycle: false,
      phaseCueDelay: Duration.zero,
      startupNotice: startupNotice,
    );
  }

  final MemoryStore store = MemoryStore();
  final FakeEffects effects = FakeEffects();
  late final AppController controller;
  double monotonicMs = 0;
  int wallMs = 1_000_000;
  int nextId = 1;

  void lifecycle(AppLifecycleState state) =>
      controller.didChangeAppLifecycleState(state);

  void advance(int milliseconds) {
    monotonicMs += milliseconds;
    wallMs += milliseconds;
    controller.tick();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('应用控制器', () {
    test('水合后保留兼容键、默认选中项与设置副作用', () async {
      final harness = Harness();
      await harness.controller.initialize();
      expect(harness.controller.ready, isTrue);
      expect(harness.controller.templates, hasLength(builtinTemplates.length));
      expect(
        harness.controller.selectedTemplate?.id,
        builtinTemplates.first.id,
      );
      expect(harness.effects.configuredVolume, defaultSettings.volume);
      expect(
        harness.store.values[StorageKeys.selected],
        builtinTemplates.first.id,
      );
      harness.controller.dispose();
    });

    test('倒计时可开始、暂停计打断、恢复并长按终止保存未完成记录', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.startSelectedSession();
      expect(harness.controller.timer.status, TimerStatus.running);
      expect(harness.controller.activeTemplate?.id, 'builtin.pomodoro');
      expect(harness.store.values, contains(StorageKeys.active));

      harness.advance(2500);
      await harness.controller.togglePause();
      expect(harness.controller.timer.status, TimerStatus.paused);
      expect(harness.controller.timer.interruptions, 1);
      await harness.controller.togglePause();
      expect(harness.controller.timer.status, TimerStatus.running);

      await harness.controller.stopSession();
      expect(harness.controller.timer.status, TimerStatus.idle);
      expect(harness.controller.sessions, hasLength(1));
      expect(harness.controller.sessions.single.completed, isFalse);
      expect(harness.controller.sessions.single.interruptions, 1);
      expect(
        harness.controller.sessions.single.qualityEvidence?.manualPauseCount,
        1,
      );
      expect(harness.effects.sounds, contains(SoundName.drum));
      expect(harness.store.values, isNot(contains(StorageKeys.active)));
      harness.controller.dispose();
    });

    test('生命周期噪声合并为一次离席且短暂 inactive 不扣分', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.selectTemplate('builtin.cardio');
      await harness.controller.startSelectedSession();
      harness.advance(10 * 1000);

      harness.lifecycle(AppLifecycleState.inactive);
      harness.lifecycle(AppLifecycleState.resumed);
      harness.advance(1000);
      expect(harness.controller.timer.status, TimerStatus.running);

      harness.lifecycle(AppLifecycleState.inactive);
      harness.lifecycle(AppLifecycleState.hidden);
      harness.lifecycle(AppLifecycleState.paused);
      harness.advance(10 * 1000);
      harness.lifecycle(AppLifecycleState.resumed);
      await harness.controller.stopSession();

      final evidence = harness.controller.sessions.single.qualityEvidence!;
      expect(evidence.backgroundExcursionCount, 1);
      expect(evidence.backgroundFocusSec, greaterThanOrEqualTo(10));
      expect(harness.controller.sessions.single.qualityScore, lessThan(100));
      harness.controller.dispose();
    });

    test('积累模板不足一秒丢弃，达到一秒则完成并停在 done', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.selectTemplate('builtin.cardio');
      await harness.controller.startSelectedSession();
      await harness.controller.stopSession();
      expect(harness.controller.sessions, isEmpty);
      expect(harness.controller.timer.status, TimerStatus.idle);

      await harness.controller.startSelectedSession();
      harness.advance(1600);
      await harness.controller.stopSession();
      expect(harness.controller.sessions, hasLength(1));
      expect(harness.controller.sessions.single.completed, isTrue);
      expect(harness.controller.timer.status, TimerStatus.done);
      expect(harness.controller.timer.remainSec, 1);
      expect(bestStreakDays(harness.controller.sessions), 0);
      harness.controller.dispose();
    });

    test('完成后可关联目标并同时记入进度，重复关联不重复累计投入', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.addTodo(text: '练习 Flutter');
      final firstTodo = harness.controller.todos.single;

      await harness.controller.selectTemplate('builtin.cardio');
      await harness.controller.startSelectedSession();
      harness.advance(5600);
      await harness.controller.stopSession();

      expect(harness.controller.sessions, hasLength(1));
      expect(harness.controller.sessions.single.linkedTodoId, isNull);
      expect(harness.controller.todos.single.totalFocusSec, 0);

      await harness.controller.applyLastSessionToTodo(
        firstTodo.id,
        progressAmount: 25,
      );
      final linked = harness.controller.todos.single;
      expect(harness.controller.sessions.single.linkedTodoId, firstTodo.id);
      expect(linked.totalFocusSec, 5);
      expect(linked.sessionsLinked, 1);
      expect(linked.progress, 25);
      expect(linked.pushes, 1);
      final frozenExp = harness.controller.growth.totalExp;
      expect(harness.controller.sessions.single.awardedMilliExp, isNotNull);
      expect(
        jsonDecode(
          harness.store.values[StorageKeys.sessions]!,
        ).single['linkedTodoId'],
        firstTodo.id,
      );
      expect(
        jsonDecode(harness.store.values[StorageKeys.todos]!).single['progress'],
        25,
      );

      await harness.controller.linkLastSessionToTodo(firstTodo.id);
      expect(harness.controller.todos.single.totalFocusSec, 5);
      expect(harness.controller.todos.single.sessionsLinked, 1);
      expect(harness.controller.todos.single.progress, 25);
      expect(harness.controller.todos.single.pushes, 1);
      expect(harness.controller.growth.totalExp, frozenExp);
      await harness.controller.pushTodo(firstTodo.id, 10);
      expect(harness.controller.growth.totalExp, frozenExp);
      await harness.controller.deleteTodo(firstTodo.id);
      expect(harness.controller.growth.totalExp, frozenExp);
      harness.controller.dispose();
    });

    test('感受可选且可重选，写入最后一次记录但不改历史经验', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.selectTemplate('builtin.cardio');
      await harness.controller.startSelectedSession();
      harness.advance(600000);
      await harness.controller.stopSession();

      expect(harness.controller.lastSession?.feeling, isNull);
      final neutralExp = harness.controller.growth.totalExp;
      expect(neutralExp, greaterThan(0));

      await harness.controller.setLastSessionFeeling(SessionFeeling.arduous);
      expect(harness.controller.lastSession?.feeling, SessionFeeling.arduous);
      expect(harness.controller.growth.totalExp, neutralExp);
      expect(
        jsonDecode(
          harness.store.values[StorageKeys.sessions]!,
        ).single['feeling'],
        'arduous',
      );

      await harness.controller.setLastSessionFeeling(
        SessionFeeling.transcendent,
      );
      expect(
        harness.controller.lastSession?.feeling,
        SessionFeeling.transcendent,
      );
      expect(harness.controller.growth.totalExp, neutralExp);
      harness.controller.dispose();
    });

    test('隐修摘要持久化并在重启后水合，清史后回零', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.selectTemplate('builtin.cardio');
      await harness.controller.startSelectedSession();
      harness.advance(5400000);
      await harness.controller.stopSession();

      final stored = jsonDecode(harness.store.values[StorageKeys.growth]!);
      expect(stored['totalExp'], harness.controller.growth.totalExp);
      expect(stored['level'], harness.controller.growth.level);
      expect(stored['insights'], contains('single_90min'));
      harness.controller.dispose();

      final revived = Harness(initial: harness.store.values);
      await revived.controller.initialize();
      expect(revived.controller.growth.totalExp, stored['totalExp']);
      expect(revived.controller.growth.insights, contains('single_90min'));

      await revived.controller.clearHistory();
      expect(revived.controller.growth.totalExp, 0);
      expect(revived.controller.growth.level, 1);
      expect(
        jsonDecode(revived.store.values[StorageKeys.growth]!)['totalExp'],
        0,
      );
      revived.controller.dispose();
    });

    test('TODO CRUD、推进及模板恢复均持久化', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.addTodo(text: '  写迁移说明  ', tags: ['迁移', '']);
      final todo = harness.controller.todos.single;
      expect(todo.text, '写迁移说明');
      expect(todo.tags, ['迁移']);
      await harness.controller.pushTodo(todo.id, 35);
      expect(harness.controller.todos.single.progress, 35);
      await harness.controller.archiveTodoById(todo.id);
      expect(harness.controller.todos.single.archivedAt, harness.wallMs);
      expect(harness.controller.doingTodos, isEmpty);
      await harness.controller.restoreTodoById(todo.id);
      expect(harness.controller.todos.single.archivedAt, isNull);
      expect(harness.controller.doingTodos.single.id, todo.id);
      await harness.controller.setTodoProgressById(todo.id, 100);
      expect(harness.controller.todos.single.completedAt, isNotNull);
      await harness.controller.deleteTemplate('builtin.pomodoro');
      expect(harness.controller.templates, hasLength(5));
      await harness.controller.resetBuiltinTemplates();
      expect(harness.controller.templates, hasLength(6));
      expect(
        jsonDecode(harness.store.values[StorageKeys.todos]!),
        hasLength(1),
      );
      harness.controller.dispose();
    });

    test('重置内置笺会恢复被修改内容并保留自定义笺', () async {
      final harness = Harness();
      await harness.controller.initialize();
      final canonical = builtinTemplates.firstWhere(
        (template) => template.id == 'builtin.deepwork',
      );
      await harness.controller.upsertTemplate(
        canonical.copyWith(label: '已修改', focusSec: 60),
      );
      await harness.controller.upsertTemplate(
        const TimerTemplate(
          id: 'custom',
          label: '自定义',
          kind: TemplateKind.accumulate,
          createdAt: 1,
        ),
      );

      await harness.controller.resetBuiltinTemplates();

      expect(
        harness.controller.templates
            .firstWhere((template) => template.id == canonical.id)
            .toJson(),
        canonical.toJson(),
      );
      expect(
        harness.controller.templates.any((template) => template.id == 'custom'),
        isTrue,
      );
      harness.controller.dispose();
    });

    test('启动存储降级提示会保留到控制器供首页展示', () async {
      final harness = Harness(startupNotice: '存 储 暂 不 可 用');
      await harness.controller.initialize();
      expect(harness.controller.notice, '存 储 暂 不 可 用');
      harness.controller.dispose();
    });

    test('恢复运行中的活动会话并按离线墙钟追赶', () async {
      const snapshot = TimerSnapshot(
        mode: TimerMode.countdown,
        status: TimerStatus.running,
        index: 0,
        phaseRemainingMs: 20 * 60 * 1000,
        countUpElapsedMs: 0,
        savedAt: 940_000,
      );
      final checkpoint = ActiveSessionCheckpoint(
        sessionId: 'restored',
        template: builtinTemplates.first,
        startedAt: 500_000,
        interruptions: 2,
        timer: snapshot,
      );
      final harness = Harness(
        initial: {StorageKeys.active: checkpoint.encode()},
      );
      await harness.controller.initialize();
      expect(harness.controller.timer.status, TimerStatus.running);
      expect(harness.controller.timer.remainSec, 19 * 60);
      expect(harness.controller.timer.interruptions, 2);
      expect(harness.controller.activeTemplate?.id, 'builtin.pomodoro');
      harness.controller.dispose();
    });

    test('恢复未满宽限的 provisional inactive 不记离席', () async {
      const snapshot = TimerSnapshot(
        mode: TimerMode.countdown,
        status: TimerStatus.running,
        index: 0,
        phaseRemainingMs: 15 * 1000,
        countUpElapsedMs: 0,
        savedAt: 999_000,
      );
      final checkpoint = ActiveSessionCheckpoint(
        sessionId: 'provisional',
        template: builtinTemplates.first,
        startedAt: 900_000,
        interruptions: 0,
        timer: snapshot,
        pendingInactiveAt: 999_000,
        pendingElapsedSec: 5,
      );
      final harness = Harness(
        initial: {StorageKeys.active: checkpoint.encode()},
      );
      await harness.controller.initialize();
      await harness.controller.stopSession();
      expect(
        harness
            .controller
            .sessions
            .single
            .qualityEvidence
            ?.backgroundExcursionCount,
        0,
      );
      harness.controller.dispose();
    });

    test('恢复确认离席可跨多相位精确计算工作重叠', () async {
      const template = TimerTemplate(
        id: 'cross',
        label: '跨段',
        kind: TemplateKind.interval,
        createdAt: 0,
        rounds: 2,
        workSec: 10,
        restSec: 10,
      );
      const snapshot = TimerSnapshot(
        mode: TimerMode.countdown,
        status: TimerStatus.running,
        index: 0,
        phaseRemainingMs: 5 * 1000,
        countUpElapsedMs: 0,
        savedAt: 980_000,
      );
      final checkpoint = ActiveSessionCheckpoint(
        sessionId: 'cross-phase',
        template: template,
        startedAt: 900_000,
        interruptions: 0,
        timer: snapshot,
        openBackgroundAt: 980_000,
        openBackgroundElapsedSec: 5,
      );
      final harness = Harness(
        initial: {StorageKeys.active: checkpoint.encode()},
      );
      await harness.controller.initialize();
      await harness.controller.stopSession();
      final evidence = harness.controller.sessions.single.qualityEvidence!;
      expect(evidence.backgroundExcursionCount, 1);
      expect(evidence.backgroundFocusSec, 10);
      harness.controller.dispose();
    });

    test('恢复穿过自动完成前先写入完整离席专注秒数', () async {
      const template = TimerTemplate(
        id: 'complete-away',
        label: '完成',
        kind: TemplateKind.interval,
        createdAt: 0,
        rounds: 2,
        workSec: 10,
        restSec: 10,
      );
      const snapshot = TimerSnapshot(
        mode: TimerMode.countdown,
        status: TimerStatus.running,
        index: 0,
        phaseRemainingMs: 5 * 1000,
        countUpElapsedMs: 0,
        savedAt: 950_000,
      );
      final checkpoint = ActiveSessionCheckpoint(
        sessionId: 'complete-away',
        template: template,
        startedAt: 900_000,
        interruptions: 0,
        timer: snapshot,
        openBackgroundAt: 950_000,
        openBackgroundElapsedSec: 5,
      );
      final harness = Harness(
        initial: {StorageKeys.active: checkpoint.encode()},
      );
      await harness.controller.initialize();
      await Future<void>.delayed(Duration.zero);
      final evidence = harness.controller.sessions.single.qualityEvidence!;
      expect(harness.controller.sessions.single.completed, isTrue);
      expect(evidence.backgroundExcursionCount, 1);
      expect(evidence.backgroundFocusSec, 15);
      harness.controller.dispose();
    });

    test('会话与活动检查点写入失败一次后队列仍可继续保存', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.addTodo(text: '重试目标');
      harness.store.failWrites[StorageKeys.active] = 1;

      await expectLater(
        harness.controller.startSelectedSession(),
        throwsA(isA<StateError>()),
      );
      await harness.controller.checkpointAndFlush();
      expect(harness.store.values, contains(StorageKeys.active));
      expect(
        harness.store.writeAttempts[StorageKeys.active],
        greaterThanOrEqualTo(2),
      );

      harness.store.failWrites[StorageKeys.sessions] = 1;
      harness.advance(2500);
      await expectLater(
        harness.controller.stopSession(),
        throwsA(isA<StateError>()),
      );
      expect(harness.controller.sessions, hasLength(1));

      await harness.controller.importBackup(
        jsonEncode({
          'app': 'uptimer',
          'version': 1,
          'exportedAt': harness.wallMs,
          'templates': const [],
          'sessions': const [],
          'todos': const [],
          'settings': defaultSettings.toJson(),
        }),
      );
      final stored = jsonDecode(harness.store.values[StorageKeys.sessions]!);
      expect(stored, hasLength(1));
      expect(stored.single['id'], harness.controller.sessions.single.id);
      expect(
        harness.store.writeAttempts[StorageKeys.sessions],
        greaterThanOrEqualTo(2),
      );
      harness.controller.dispose();
    });

    test('自动完成写会话失败时保留活动检查点，重试成功后才清除', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.upsertTemplate(
        const TimerTemplate(
          id: 'auto-durable',
          label: '自动落盘',
          kind: TemplateKind.interval,
          createdAt: 0,
          rounds: 1,
          workSec: 1,
          restSec: 0,
        ),
      );
      await harness.controller.startSelectedSession();
      final activeBefore = harness.store.values[StorageKeys.active];
      expect(activeBefore, isNotNull);
      harness.store.failWrites[StorageKeys.sessions] = 1;

      harness.advance(1600);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(harness.controller.timer.status, TimerStatus.done);
      expect(harness.controller.sessions, hasLength(1));
      expect(harness.store.values[StorageKeys.active], activeBefore);
      expect(harness.store.values[StorageKeys.sessions], isNull);

      await harness.controller.checkpointAndFlush();

      final stored = jsonDecode(harness.store.values[StorageKeys.sessions]!);
      expect(stored, hasLength(1));
      expect(stored.single['id'], harness.controller.sessions.single.id);
      expect(harness.store.values, isNot(contains(StorageKeys.active)));
      expect(
        harness.store.writeAttempts[StorageKeys.sessions],
        greaterThanOrEqualTo(2),
      );
      harness.controller.dispose();
    });

    test('延迟自动保存不会覆盖更快的感受与目标关联', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.addTodo(text: '并发目标');
      await harness.controller.upsertTemplate(
        const TimerTemplate(
          id: 'quick',
          label: '短专注',
          kind: TemplateKind.interval,
          createdAt: 0,
          rounds: 1,
          workSec: 1,
          restSec: 0,
        ),
      );
      final blockedSave = Completer<void>();
      harness.store.sessionWriteCompleters.add(blockedSave);
      await harness.controller.startSelectedSession();
      harness.advance(1600);
      await Future<void>.delayed(Duration.zero);
      expect(harness.controller.lastSession, isNotNull);
      final feeling = harness.controller.setLastSessionFeeling(
        SessionFeeling.transcendent,
      );
      final link = harness.controller.linkLastSessionToTodo(
        harness.controller.todos.single.id,
      );
      blockedSave.complete();
      await Future.wait([feeling, link]);
      final stored =
          jsonDecode(harness.store.values[StorageKeys.sessions]!).single
              as Map<String, Object?>;
      expect(stored['feeling'], 'transcendent');
      expect(stored['linkedTodoId'], harness.controller.todos.single.id);
      harness.controller.dispose();
    });

    test('目标深耕只累计专注段而不含编排休息', () async {
      final harness = Harness();
      await harness.controller.initialize();
      await harness.controller.addTodo(text: '只算工作段');
      await harness.controller.selectTemplate('builtin.tabata');
      await harness.controller.startSelectedSession();
      harness.advance(230 * 1000);
      await Future<void>.delayed(Duration.zero);
      await harness.controller.linkLastSessionToTodo(
        harness.controller.todos.single.id,
      );
      expect(harness.controller.lastSession?.focusedSec, 160);
      expect(harness.controller.todos.single.totalFocusSec, 160);
      harness.controller.dispose();
    });

    test('旧悟缺少时间时只迁移一次并持久化稳定时间', () async {
      final sessionJson = {
        'id': 'legacy-insight-session',
        'templateId': 't',
        'label': '旧功课',
        'kind': 'accumulate',
        'startedAt': 1000,
        'endedAt': 2000,
        'plannedSec': 0,
        'elapsedSec': 600,
        'completed': true,
        'roundsDone': 0,
        'roundsTotal': 0,
      };
      final initial = <String, String>{
        StorageKeys.sessions: jsonEncode([sessionJson]),
        StorageKeys.growth: jsonEncode({
          'level': 2,
          'totalExp': 60,
          'insights': ['first_10h'],
          'version': 1,
        }),
      };
      final harness = Harness(initial: initial);
      await harness.controller.initialize();
      expect(harness.controller.growth.insightUnlockedAt['first_10h'], 2000);
      final stored = jsonDecode(harness.store.values[StorageKeys.growth]!);
      expect(stored['version'], 2);
      expect(stored['insightUnlockedAt']['first_10h'], 2000);
      harness.controller.dispose();

      final revived = Harness(initial: harness.store.values);
      revived.wallMs = 9_000_000;
      await revived.controller.initialize();
      expect(revived.controller.growth.insightUnlockedAt['first_10h'], 2000);
      revived.controller.dispose();
    });

    test('备份逐条收录并整体采用备份设置', () async {
      final harness = Harness();
      await harness.controller.initialize();
      final backup = jsonEncode({
        'app': 'uptimer',
        'version': 1,
        'exportedAt': 1,
        'templates': [
          {'id': 'custom', 'label': '短练', 'kind': 'accumulate', 'createdAt': 1},
          {'bad': true},
        ],
        'sessions': const [],
        'todos': const [],
        'settings': defaultSettings.copyWith(theme: 'ink').toJson(),
      });
      final report = await harness.controller.importBackup(backup);
      expect(report.templatesAdded, 1);
      expect(report.skipped, 1);
      expect(harness.controller.settings.theme, 'ink');
      expect(
        harness.controller.templates.any((item) => item.id == 'custom'),
        isTrue,
      );
      harness.controller.dispose();
    });

    test('仅设置被采用时也计入导入变更，不会误报无可用数据', () async {
      final harness = Harness();
      await harness.controller.initialize();
      final backup = jsonEncode({
        'app': 'uptimer',
        'version': 1,
        'exportedAt': 1,
        'templates': [
          {'bad': true},
        ],
        'sessions': const [],
        'todos': const [],
        'settings': defaultSettings.copyWith(theme: 'ink').toJson(),
      });

      final report = await harness.controller.importBackup(backup);

      expect(report.settingsUpdated, isTrue);
      expect(report.changed, 1);
      expect(report.skipped, 1);
      expect(harness.controller.settings.theme, 'ink');
      harness.controller.dispose();
    });
  });
}
