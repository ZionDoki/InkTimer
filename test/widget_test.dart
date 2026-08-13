import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uptimer/app.dart';
import 'package:uptimer/data/key_value_store.dart';
import 'package:uptimer/data/repository.dart';
import 'package:uptimer/domain/gestures.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/sounds.dart';
import 'package:uptimer/domain/timer_engine.dart';
import 'package:uptimer/services/runtime_effects.dart';
import 'package:uptimer/state/app_controller.dart';
import 'package:uptimer/ui/widgets/zen_page.dart';

class MemoryStore implements KeyValueStore {
  final values = <String, String>{StorageKeys.seenGuide: '1'};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> flush() async {}
}

class RecordingEffects implements RuntimeEffects {
  final sounds = <SoundName>[];

  @override
  bool get audioAvailable => true;

  @override
  void configureAudio({required bool enabled, required double volume}) {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> haptic(HapticCue cue) async {}

  @override
  Future<void> keepAwake(bool enabled) async {}

  @override
  Future<void> play(SoundName sound) async => sounds.add(sound);
}

void main() {
  testWidgets('主屏保留水墨计时器、顶部入口与专注目标胶囊导航', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('番茄钟'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
    expect(find.text('動'), findsOneWidget);
    expect(find.text('簿'), findsOneWidget);
    expect(find.text('···'), findsOneWidget);
    expect(find.text('笺'), findsNothing);
    expect(find.text('事'), findsNothing);
    expect(find.byKey(const ValueKey('global-nav-focus')), findsOneWidget);
    expect(find.byKey(const ValueKey('global-nav-goals')), findsOneWidget);
    expect(find.text('双 击 开 始'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('orb-fluid-repaint-boundary')),
      findsOneWidget,
    );
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
    final orbCenter = tester.getCenter(
      find.byKey(const ValueKey('orb-fluid-repaint-boundary')),
    );
    expect(orbCenter.dy / viewport.height, closeTo(0.43, 0.02));

    final center = tester.getCenter(find.byKey(const ValueKey('timer-time')));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.hasActiveSession, isTrue);
    expect(find.text('长 按 终 止'), findsNWidgets(2));

    controller.dispose();
  });

  testWidgets('横向拖动不再切换专注模板', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    final firstId = controller.selectedTemplateId;
    expect(find.byKey(const ValueKey('template-carousel')), findsNothing);
    final surface = find.byKey(const ValueKey('idle-gesture-surface'));
    await tester.drag(surface, const Offset(-480, 0));
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.selectedTemplateId, firstId);

    controller.dispose();
  });

  testWidgets('专注目标胶囊导航全局常驻并在目标页切回专注', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.addTodo(text: '整理迁移方案');
    await controller.addTodo(text: '已经完成');
    await controller.setTodoProgressById(controller.todos.last.id, 100);
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('global-nav-goal-count')), findsOneWidget);
    expect(find.text('专 注'), findsWidgets);
    expect(find.text('目 标'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('global-nav-goals')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));

    expect(find.byKey(const ValueKey('global-nav-focus')), findsOneWidget);
    expect(find.byKey(const ValueKey('global-nav-goals')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('global-nav-focus')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('timer-time')), findsOneWidget);
    expect(find.byKey(const ValueKey('close-template-drawer')), findsNothing);

    controller.dispose();
  });

  testWidgets('非番茄模式在顶部下拉入口提示可切换编排', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.selectTemplate('builtin.tabata');
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('template-menu-entry')), findsOneWidget);
    expect(find.byKey(const ValueKey('template-switch-hint')), findsOneWidget);
    expect(find.textContaining('切 换 编 排'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('当前专注标题与下拉提示垂直居中', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    final title = find.byKey(const ValueKey('template-menu-title'));
    final indicator = find.byKey(const ValueKey('template-menu-indicator'));
    expect(title, findsOneWidget);
    expect(indicator, findsOneWidget);
    expect(
      (tester.getCenter(title).dy - tester.getCenter(indicator).dy).abs(),
      lessThanOrEqualTo(0.5),
    );

    controller.dispose();
  });

  testWidgets('计时进行中可在主区域长按终止', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    final orbCenter = tester.getCenter(
      find.byKey(const ValueKey('timer-time')),
    );
    await tester.tapAt(orbCenter);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(orbCenter);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.hasActiveSession, isTrue);

    final screen = tester.getRect(find.byType(Scaffold));
    final mainAreaPoint = screen.centerRight - const Offset(90, 0);
    final hold = await tester.startGesture(mainAreaPoint);
    await tester.pump(const Duration(milliseconds: longPressMs + 32));
    await tester.pump();

    expect(controller.hasActiveSession, isFalse);
    await hold.up();
    controller.dispose();
  });

  testWidgets('双击暂停不会误触发长按蓄力音', (tester) async {
    final effects = RecordingEffects();
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: effects,
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    final center = tester.getCenter(find.byKey(const ValueKey('timer-time')));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));
    effects.sounds.clear();

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 400));

    expect(controller.timer.status, TimerStatus.paused);
    expect(effects.sounds, contains(SoundName.pauseLow));
    expect(effects.sounds, isNot(contains(SoundName.charge)));

    controller.dispose();
  });

  testWidgets('事项作为主入口并支持搜索、视图筛选与归档恢复', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.addTodo(text: '整理迁移方案', tags: ['工作']);
    final todoId = controller.todos.single.id;
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('global-nav-goals')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('todo-search-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-sort-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-scope-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-scope-archived')), findsOneWidget);
    expect(find.byKey(ValueKey('todo-card-$todoId')), findsOneWidget);

    final archiveButton = find.byKey(ValueKey('todo-archive-$todoId'));
    await tester.ensureVisible(archiveButton);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(archiveButton);
    await tester.pump(const Duration(milliseconds: 250));
    final archivedScope = find.byKey(const ValueKey('todo-scope-archived'));
    await tester.ensureVisible(archivedScope);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(archivedScope);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(ValueKey('todo-card-$todoId')), findsOneWidget);
    expect(find.byKey(ValueKey('todo-restore-$todoId')), findsOneWidget);

    controller.dispose();
  });

  testWidgets('所选标签最后一项归档后立即恢复展示其余事项', (tester) async {
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.addTodo(text: '带标签事项', tags: const ['工作']);
    await controller.addTodo(text: '无标签事项');
    final taggedId = controller.todos.first.id;
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('global-nav-goals')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InkChip, '工作'));
    await tester.pumpAndSettle();
    expect(find.text('无标签事项'), findsNothing);

    final archive = find.byKey(ValueKey('todo-archive-$taggedId'));
    await tester.ensureVisible(archive);
    await tester.tap(archive);
    await tester.pumpAndSettle();

    expect(find.text('无标签事项'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('窄屏下主屏、时间笺与清单无布局溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('25:00'), findsOneWidget);
    expect(tester.takeException(), isNull);

    var engineMs = 0.0;
    final doneController = AppController(
      repository: Repository(MemoryStore()),
      engine: TimerEngine(nowMs: () => engineMs),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await doneController.initialize();
    await doneController.addTodo(text: '窄屏目标');
    await doneController.selectTemplate('builtin.cardio');
    await tester.pumpWidget(InkTimerApp(controller: doneController));
    await tester.pump(const Duration(milliseconds: 300));
    await doneController.startSelectedSession();
    engineMs += 5000;
    doneController.tick();
    await doneController.stopSession();
    await tester.pump(const Duration(milliseconds: 900));

    final doneDetails = find.byKey(const ValueKey('done-details'));
    expect(
      find.byKey(const ValueKey('orb-fluid-repaint-boundary')),
      findsOneWidget,
    );
    expect(doneDetails, findsOneWidget);
    expect(tester.takeException(), isNull);
    doneController.dispose();

    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('template-menu-entry')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('时 间 笺'), findsOneWidget);
    expect(find.text('专 注'), findsWidgets);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('close-template-drawer')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('global-nav-goals')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('new-todo-text')), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('横屏极矮视口下完成态仍可布局且无异常', (tester) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var engineMs = 0.0;
    final controller = AppController(
      repository: Repository(MemoryStore()),
      engine: TimerEngine(nowMs: () => engineMs),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.addTodo(text: '横屏目标');
    await controller.selectTemplate('builtin.cardio');
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await controller.startSelectedSession();
    engineMs += 5000;
    controller.tick();
    await controller.stopSession();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byKey(const ValueKey('done-seal')), findsOneWidget);
    expect(find.byKey(const ValueKey('done-details')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('极窄屏与双倍文字下完成态仍无溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() async {
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.binding.setSurfaceSize(null);
    });
    var engineMs = 0.0;
    final controller = AppController(
      repository: Repository(MemoryStore()),
      engine: TimerEngine(nowMs: () => engineMs),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.addTodo(text: '双倍文字目标');
    await controller.selectTemplate('builtin.cardio');
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await controller.startSelectedSession();
    engineMs += 5000;
    controller.tick();
    await controller.stopSession();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byKey(const ValueKey('done-details')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-growth-feedback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('统计页说明图表含义并提供对齐热力图与平滑趋势', (tester) async {
    final store = MemoryStore();
    final now = DateTime.now();
    store.values[StorageKeys.sessions] = jsonEncode([
      for (var index = 0; index < 8; index++)
        SessionRecord(
          id: 'session-$index',
          templateId: 'builtin.pomodoro',
          label: '番茄钟',
          kind: TemplateKind.pomodoro,
          startedAt: now
              .subtract(Duration(days: index, hours: 1))
              .millisecondsSinceEpoch,
          endedAt: now.subtract(Duration(days: index)).millisecondsSinceEpoch,
          plannedSec: 1500,
          elapsedSec: 900 + index * 120,
          completed: true,
          roundsDone: 1,
          roundsTotal: 1,
          interruptions: index.isEven ? 0 : 1,
        ).toJson(),
    ]);
    final controller = AppController(
      repository: Repository(store),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('簿'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const ValueKey('stats-overview')), findsOneWidget);
    expect(find.text('近 30 日 节 律'), findsOneWidget);
    expect(find.textContaining('曲线越高'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-trend-chart')), findsOneWidget);
    expect(find.text('12 周 积 累'), findsOneWidget);
    expect(find.textContaining('次数与总时长取较低档'), findsOneWidget);
    expect(find.byKey(const ValueKey('stats-heatmap-chart')), findsOneWidget);
    for (var level = 0; level <= 5; level += 1) {
      expect(find.byKey(ValueKey('stats-heat-level-$level')), findsOneWidget);
    }
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('设置页版本来自安装包元数据而非硬编码', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: '成时',
      packageName: 'com.uptimer.app',
      version: '9.8.7',
      buildNumber: '654',
      buildSignature: '',
    );
    final controller = AppController(
      repository: Repository(MemoryStore()),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('···'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('成 时 · 9.8.7+654 · FLUTTER'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('结束后可选记下感受，不选也能直接离开', (tester) async {
    final store = MemoryStore();
    var engineMs = 0.0;
    final controller = AppController(
      repository: Repository(store),
      engine: TimerEngine(nowMs: () => engineMs),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.selectTemplate('builtin.cardio');
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await controller.startSelectedSession();
    engineMs += 90 * 60 * 1000;
    controller.tick();
    await tester.pump(const Duration(milliseconds: 300));
    await controller.stopSession();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('功 课 已 毕'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('session-growth-feedback')),
      findsOneWidget,
    );
    // 完成态保留球体，并将球体与「成」印章一起移到详情上方。
    final orb = find.byKey(const ValueKey('orb-fluid-repaint-boundary'));
    final seal = find.byKey(const ValueKey('done-seal'));
    final details = find.byKey(const ValueKey('done-details'));
    expect(orb, findsOneWidget);
    expect(seal, findsOneWidget);
    expect(details, findsOneWidget);
    expect(tester.getCenter(orb).dy, lessThan(tester.getTopLeft(details).dy));
    expect(
      tester.getBottomRight(seal).dy,
      lessThan(tester.getTopLeft(details).dy),
    );
    // 三个感受字常驻，但不预选：不选就是不选。
    expect(find.byKey(const ValueKey('feeling-arduous')), findsOneWidget);
    expect(find.byKey(const ValueKey('feeling-smooth')), findsOneWidget);
    expect(find.byKey(const ValueKey('feeling-transcendent')), findsOneWidget);
    expect(controller.lastSession?.feeling, isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('feeling-transcendent')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('feeling-transcendent')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.lastSession?.feeling, SessionFeeling.transcendent);

    // 可改主意，不是一锤子买断。
    await tester.tap(find.byKey(const ValueKey('feeling-arduous')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.lastSession?.feeling, SessionFeeling.arduous);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('结束后的“记”已合并进“专注于”目标选择流程', (tester) async {
    final store = MemoryStore();
    var engineMs = 0.0;
    final controller = AppController(
      repository: Repository(store),
      engine: TimerEngine(nowMs: () => engineMs),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await controller.addTodo(text: '整理迁移方案');
    final todo = controller.todos.single;
    await controller.selectTemplate('builtin.cardio');
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await controller.startSelectedSession();
    engineMs += 5000;
    controller.tick();
    await controller.stopSession();
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.byKey(const ValueKey('link-session-todo')), findsOneWidget);
    expect(find.byKey(const ValueKey('log-session-todo')), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('link-session-todo')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('link-session-todo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('专 注 于'), findsOneWidget);
    expect(find.textContaining('可 选 记 入 清 单 进 度'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todo-progress-25')));
    await tester.tap(find.byKey(const ValueKey('confirm-session-todo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.lastSession?.linkedTodoId, todo.id);
    expect(controller.todos.single.totalFocusSec, 5);
    expect(controller.todos.single.sessionsLinked, 1);
    expect(controller.todos.single.progress, 25);
    expect(controller.todos.single.pushes, 1);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('功课簿隐修摘要可进入隐修履历，只列已悟与深耕目标', (tester) async {
    final store = MemoryStore();
    final now = DateTime.now();
    store.values[StorageKeys.sessions] = jsonEncode([
      SessionRecord(
        id: 'session-deep',
        templateId: 'builtin.pomodoro',
        label: '番茄铟',
        kind: TemplateKind.pomodoro,
        startedAt: now
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
        endedAt: now.millisecondsSinceEpoch,
        plannedSec: 5400,
        elapsedSec: 5400,
        completed: true,
        roundsDone: 1,
        roundsTotal: 1,
        interruptions: 0,
        linkedTodoId: 'todo-deep',
      ).toJson(),
    ]);
    store.values[StorageKeys.todos] = jsonEncode([
      TodoItem(
        id: 'todo-deep',
        text: '练习 Flutter',
        progress: 30,
        pushes: 1,
        createdAt: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
        totalFocusSec: 5400,
        sessionsLinked: 1,
      ).toJson(),
    ]);
    final controller = AppController(
      repository: Repository(store),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('簿'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final summary = find.byKey(const ValueKey('stats-growth-summary'));
    expect(summary, findsOneWidget);
    await tester.scrollUntilVisible(
      summary,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('隐 修 履 历'), findsOneWidget);
    expect(find.text('已 悟'), findsOneWidget);
    // 「深坐」已达（单次 90 分钟），未悟的不列出来。
    expect(find.text('深坐'), findsOneWidget);
    expect(find.text('百时'), findsNothing);
    expect(find.byKey(const ValueKey('cultivation-todo-deep')), findsOneWidget);
    // 1.5h 累积投入→ 1.01 + 0.5*0.02 = 1.02x
    expect(find.textContaining('1.02x'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('连续天数只用朱印说一遍，不在隐修履历里重复成文字条目', (tester) async {
    final store = MemoryStore();
    final base = DateTime(2026, 3, 1, 9);
    // 连续 8 天，拿到「柒」；后面断签，当下连续已经不足 7 天。
    store.values[StorageKeys.sessions] = jsonEncode([
      for (var day = 0; day < 8; day += 1)
        SessionRecord(
          id: 'session-$day',
          templateId: 'builtin.pomodoro',
          label: '番茄铟',
          kind: TemplateKind.pomodoro,
          startedAt: base.add(Duration(days: day)).millisecondsSinceEpoch,
          endedAt: base
              .add(Duration(days: day, minutes: 25))
              .millisecondsSinceEpoch,
          plannedSec: 1500,
          elapsedSec: 1500,
          completed: true,
          roundsDone: 1,
          roundsTotal: 1,
          interruptions: 0,
        ).toJson(),
    ]);
    final controller = AppController(
      repository: Repository(store),
      effects: const NoopRuntimeEffects(),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();
    expect(controller.growth.insights, contains('streak_7'));
    expect(controller.growth.insights, isNot(contains('streak_30')));

    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('簿'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 功课簿：三方印记全列，得到的与未得的都在。
    expect(find.byKey(const ValueKey('seal-streak_7')), findsOneWidget);
    expect(find.byKey(const ValueKey('seal-streak_30')), findsOneWidget);
    expect(find.byKey(const ValueKey('seal-streak_100')), findsOneWidget);

    final summary = find.byKey(const ValueKey('stats-growth-summary'));
    await tester.scrollUntilVisible(
      summary,
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 隐修履历：只列已得的朱印，且不再出现「不辍」文字条目。
    expect(find.byKey(const ValueKey('growth-seal-streak_7')), findsOneWidget);
    expect(find.byKey(const ValueKey('growth-seal-streak_30')), findsNothing);
    expect(find.text('不辍'), findsNothing);
    expect(find.textContaining('连续 7 天专注'), findsNothing);
    expect(tester.takeException(), isNull);

    controller.dispose();
  });

  testWidgets('解锁新悟时在结束态淡入提示', (tester) async {
    final store = MemoryStore();
    var engineMs = 1000000.0;
    final controller = AppController(
      repository: Repository(store),
      effects: const NoopRuntimeEffects(),
      engine: TimerEngine(nowMs: () => engineMs),
      driveTicker: false,
      observeLifecycle: false,
    );
    await controller.initialize();

    // 启动一个 90 分钟专注（触发「深坐」悟）。
    await controller.selectTemplate('builtin.cardio');
    await tester.pumpWidget(InkTimerApp(controller: controller));
    await tester.pump();

    await controller.startSelectedSession();
    engineMs += 90 * 60 * 1000;
    controller.tick();
    await tester.pump(const Duration(milliseconds: 300));
    await controller.stopSession();
    await tester.pump(const Duration(milliseconds: 300));

    // 此时应有 pendingInsightNotice。
    expect(controller.pendingInsightNotice, isNotEmpty);
    expect(
      controller.pendingInsightNotice!.any((i) => i.id == 'single_90min'),
      isTrue,
    );

    // 结束态应显示「悟 · 深坐」。
    expect(find.text('功 课 已 毕'), findsOneWidget);
    expect(find.textContaining('悟 · 深坐'), findsOneWidget);

    // 动画控制器应该启动淡入。
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    // 2.5 秒后提示应消失。
    await tester.pump(const Duration(milliseconds: 2500));
    controller.clearInsightNotice();
    await tester.pump();
    expect(controller.pendingInsightNotice, isNull);

    expect(tester.takeException(), isNull);
    controller.dispose();
  });
}
