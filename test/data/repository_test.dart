import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/data/key_value_store.dart';
import 'package:uptimer/data/repository.dart';
import 'package:uptimer/domain/active_checkpoint.dart';
import 'package:uptimer/domain/defaults.dart';
import 'package:uptimer/domain/focus_quality.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/timer_engine.dart';

class MemoryStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> flush() async {}
}

void main() {
  group('Repository 水合', () {
    test('空存储使用内置模板、空记录、默认设置与首个选中项', () async {
      final result = await Repository(MemoryStore()).hydrate(now: 100);
      expect(result.templates, hasLength(builtinTemplates.length));
      expect(result.sessions, isEmpty);
      expect(result.todos, isEmpty);
      expect(result.settings.toJson(), defaultSettings.toJson());
      expect(result.selectedTemplateId, builtinTemplates.first.id);
      expect(result.notice, isNull);
    });

    test('保存后按旧版键原样读回', () async {
      final store = MemoryStore();
      final repository = Repository(store);
      await repository.saveTemplates([builtinTemplates.last]);
      await repository.saveSettings(
        defaultSettings.copyWith(theme: 'ink', soundOn: false),
      );
      await repository.saveSelectedTemplateId(builtinTemplates.last.id);
      final result = await repository.hydrate(now: 100);
      expect(result.templates.single.id, 'builtin.plank');
      expect(result.settings.theme, 'ink');
      expect(result.settings.soundOn, isFalse);
      expect(result.selectedTemplateId, 'builtin.plank');
      expect(store.values, contains(StorageKeys.templates));
    });

    test('损坏 JSON 备份原件、回退并写回安全值', () async {
      final store = MemoryStore()
        ..values[StorageKeys.templates] = '{bad'
        ..values[StorageKeys.sessions] = jsonEncode([
          {'bad': true},
        ]);
      final result = await Repository(store).hydrate(now: 123);
      expect(result.templates, hasLength(builtinTemplates.length));
      expect(result.sessions, isEmpty);
      expect(result.notice, contains('已 回 退'));
      expect(
        store.values.keys,
        contains('${StorageKeys.templates}.backup-123'),
      );
      expect(store.values.keys, contains('${StorageKeys.sessions}.backup-123'));
      expect(jsonDecode(store.values[StorageKeys.templates]!), isA<List>());
    });

    test('旧 TODO 缺字段经迁移回填', () async {
      final store = MemoryStore()
        ..values[StorageKeys.todos] = jsonEncode([
          {'id': 'd', 'text': '旧事'},
        ]);
      final result = await Repository(store).hydrate(now: 100);
      expect(result.todos.single.progress, 0);
      expect(result.todos.single.pushes, 0);
      expect(result.todos.single.createdAt, 0);
      expect(result.todos.single.archivedAt, isNull);
    });

    test('不存在的选中项回落首项并修复存储', () async {
      final store = MemoryStore()..values[StorageKeys.selected] = 'missing';
      final result = await Repository(store).hydrate(now: 100);
      expect(result.selectedTemplateId, builtinTemplates.first.id);
      expect(store.values[StorageKeys.selected], builtinTemplates.first.id);
    });
  });

  group('活动会话检查点', () {
    const template = TimerTemplate(
      id: 'a',
      label: '积累',
      kind: TemplateKind.accumulate,
      createdAt: 0,
    );
    const snapshot = TimerSnapshot(
      mode: TimerMode.countup,
      status: TimerStatus.paused,
      index: 0,
      phaseRemainingMs: 0,
      countUpElapsedMs: 1500,
      savedAt: 10,
    );

    test('合法检查点可序列化往返', () {
      const checkpoint = ActiveSessionCheckpoint(
        sessionId: 'session',
        template: template,
        startedAt: 1,
        interruptions: 2,
        timer: snapshot,
        qualityEvidence: FocusQualityEvidence(
          manualPauseCount: 1,
          backgroundExcursionCount: 1,
        ),
        openBackgroundAt: 20,
        openBackgroundElapsedSec: 1,
      );
      final parsed = parseActiveCheckpoint(checkpoint.encode());
      expect(parsed.sessionId, 'session');
      expect(parsed.template.kind, TemplateKind.accumulate);
      expect(parsed.timer.mode, TimerMode.countup);
      expect(parsed.timer.countUpElapsedMs, 1500);
      expect(parsed.qualityEvidence.manualPauseCount, 1);
      expect(parsed.openBackgroundAt, 20);
    });

    test('v1 检查点以空定力数据兼容恢复', () {
      final legacy = {
        'version': 1,
        'sessionId': 'legacy',
        'template': template.toJson(),
        'startedAt': 0,
        'interruptions': 0,
        'timer': snapshot.toJson(),
      };
      final parsed = parseActiveCheckpoint(jsonEncode(legacy));
      expect(parsed.version, 1);
      expect(parsed.qualityEvidence, emptyFocusQualityEvidence);
    });

    test('拒绝模式不匹配、负数与非法状态', () {
      final mismatch = {
        'version': 1,
        'sessionId': 's',
        'template': template.toJson(),
        'startedAt': 0,
        'interruptions': 0,
        'timer': {...snapshot.toJson(), 'mode': 'countdown'},
      };
      expect(
        () => parseActiveCheckpoint(jsonEncode(mismatch)),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseActiveCheckpoint(jsonEncode({...mismatch, 'startedAt': -1})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseTimerSnapshot({...snapshot.toJson(), 'status': 'done'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
