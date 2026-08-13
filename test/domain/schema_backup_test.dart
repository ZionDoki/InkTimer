import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/backup.dart';
import 'package:uptimer/domain/defaults.dart';
import 'package:uptimer/domain/focus_quality.dart';
import 'package:uptimer/domain/growth.dart';
import 'package:uptimer/domain/growth_models.dart';
import 'package:uptimer/domain/migrate.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/schema.dart';

const validTemplateJson = <String, Object>{
  'id': 't1',
  'label': '专注',
  'kind': 'pomodoro',
  'createdAt': 1,
  'focusSec': 1500,
  'breakSec': 300,
  'rounds': 4,
};

const validSessionJson = <String, Object>{
  'id': 's1',
  'templateId': 't1',
  'label': '专注',
  'kind': 'pomodoro',
  'startedAt': 100,
  'endedAt': 200,
  'plannedSec': 1500,
  'elapsedSec': 1200,
  'completed': false,
  'roundsDone': 0,
  'roundsTotal': 4,
};

const validTodoJson = <String, Object>{
  'id': 'd1',
  'text': '**完成迁移**',
  'progress': 20,
  'pushes': 2,
  'createdAt': 50,
  'tags': ['迁移'],
  'dueAt': 100,
  'archivedAt': 125,
};

Map<String, Object?> backup({
  Object? templates = const [validTemplateJson],
  Object? sessions = const [validSessionJson],
  Object? settings = const {
    'volume': 0.8,
    'soundOn': true,
    'hapticsOn': true,
    'keepAwake': true,
    'theme': 'paper',
    'version': 1,
  },
  Object? todos,
}) => {
  'app': 'uptimer',
  'version': 1,
  'exportedAt': 999,
  'templates': templates,
  'sessions': sessions,
  'settings': settings,
  'todos': ?todos,
};

void main() {
  group('严格 schema', () {
    test('接受三类合法模板和统一阶段', () {
      expect(validateTemplate(validTemplateJson).id, 't1');
      expect(
        validateTemplate(const {
          'id': 'a',
          'label': '积累',
          'kind': 'accumulate',
          'createdAt': 0,
        }).kind,
        TemplateKind.accumulate,
      );
      final sequence = validateTemplate(const {
        'id': 'i',
        'label': '编排',
        'kind': 'interval',
        'createdAt': 0,
        'rounds': 2,
        'sequence': [
          {'role': 'prepare', 'durationSec': 5},
          {'role': 'work', 'durationSec': 20},
        ],
      });
      expect(sequence.sequence, hasLength(2));
    });

    test('拒绝旧类型、缺运行字段和编辑器边界外数据', () {
      expect(
        () => validateTemplate({...validTemplateJson, 'kind': 'tabata'}),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateTemplate(const {
          'id': 'x',
          'label': 'x',
          'kind': 'interval',
          'createdAt': 0,
        }),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateTemplate({...validTemplateJson, 'rounds': 21}),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateTemplate({
          ...validTemplateJson,
          'label': List.filled(21, '字').join(),
        }),
        throwsA(isA<SchemaException>()),
      );
    });

    test('记录允许积累零值并严格校验打断次数', () {
      expect(validateSession(validSessionJson).id, 's1');
      expect(validateSession(validSessionJson).scoringVersion, 0);
      expect(
        validateSession({
          ...validSessionJson,
          'kind': 'accumulate',
          'plannedSec': 0,
          'roundsDone': 0,
          'roundsTotal': 0,
          'interruptions': 2,
        }).interruptions,
        2,
      );
      expect(
        () => validateSession({...validSessionJson, 'interruptions': 1.5}),
        throwsA(isA<SchemaException>()),
      );
      final measured = validateSession({
        ...validSessionJson,
        'focusedSec': 900,
        'qualityScore': 92,
        'awardedMilliExp': 12345,
        'scoringVersion': 1,
        'qualityEvidence': const FocusQualityEvidence(
          manualPauseCount: 1,
        ).toJson(),
      });
      expect(measured.qualityScore, 92);
      expect(measured.qualityEvidence?.manualPauseCount, 1);
      expect(
        measured.copyWith(feeling: SessionFeeling.smooth).qualityScore,
        92,
      );
      expect(
        () => validateSession({
          ...validSessionJson,
          'focusedSec': 900,
          'qualityScore': 92,
          'scoringVersion': 1,
          'qualityEvidence': const FocusQualityEvidence(
            manualPauseCount: 1,
          ).toJson(),
        }),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateSession({
          ...validSessionJson,
          'focusedSec': 900,
          'qualityScore': 100,
          'awardedMilliExp': 12345,
          'scoringVersion': 1,
          'qualityEvidence': const FocusQualityEvidence(
            manualPauseCount: 1,
          ).toJson(),
        }),
        throwsA(isA<SchemaException>()),
      );
    });

    test('拒绝时间线、轮次关系不可能及 DateTime 无法表示的记录', () {
      expect(
        () => validateSession({
          ...validSessionJson,
          'startedAt': 300,
          'endedAt': 200,
        }),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateSession({
          ...validSessionJson,
          'roundsDone': 5,
          'roundsTotal': 4,
        }),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateSession({
          ...validSessionJson,
          'startedAt': 1 << 62,
          'endedAt': 1 << 62,
        }),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateTodo({...validTodoJson, 'dueAt': 1 << 62}),
        throwsA(isA<SchemaException>()),
      );
    });

    test('设置严格校验，导入归一则逐字段回落', () {
      expect(validateSettings(defaultSettings.toJson()).theme, 'paper');
      expect(
        () => validateSettings({...defaultSettings.toJson(), 'volume': 2}),
        throwsA(isA<SchemaException>()),
      );
      final normalized = normalizeSettings({
        'volume': 5,
        'soundOn': false,
        'theme': 'unknown',
      });
      expect(normalized.volume, defaultSettings.volume);
      expect(normalized.soundOn, isFalse);
      expect(normalized.hapticsOn, defaultSettings.hapticsOn);
      expect(normalized.theme, defaultSettings.theme);
    });

    test('TODO 接受合法可选字段并拒绝边界外数据', () {
      expect(validateTodo(validTodoJson).tags, ['迁移']);
      expect(validateTodo(validTodoJson).archivedAt, 125);
      expect(
        () => validateTodo({...validTodoJson, 'progress': 101}),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateTodo({...validTodoJson, 'tags': List.filled(9, 'x')}),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateTodo({...validTodoJson, 'text': ''}),
        throwsA(isA<SchemaException>()),
      );
    });
  });

  group('旧数据迁移', () {
    test('五种旧类型收敛为三类并剥离积累计时字段', () {
      final tabata =
          migrateTemplate({
                'id': 't',
                'label': 't',
                'kind': 'tabata',
                'workSec': 20,
                'restSec': 10,
                'rounds': 8,
              })
              as Map<String, Object?>;
      expect(tabata['kind'], 'interval');
      expect(tabata['createdAt'], 0);

      final hold =
          migrateTemplate({
                'id': 'h',
                'label': 'h',
                'kind': 'hold',
                'durationSec': 60,
                'rounds': 4,
                'sequence': const [],
              })
              as Map<String, Object?>;
      expect(hold['kind'], 'accumulate');
      expect(hold.containsKey('durationSec'), isFalse);
      expect(hold.containsKey('rounds'), isFalse);
      expect(hold.containsKey('sequence'), isFalse);
    });

    test('单式 phases 折叠为均匀制', () {
      final migrated =
          migrateTemplate({
                'id': 't',
                'label': 't',
                'kind': 'hiit',
                'phases': [
                  {'workSec': 30, 'restSec': 15},
                ],
              })
              as Map<String, Object?>;
      expect(migrated['workSec'], 30);
      expect(migrated['restSec'], 15);
      expect(migrated.containsKey('phases'), isFalse);
    });

    test('旧版已编辑内置笺自动补上末轮省略普通休息语义', () {
      final migrated =
          migrateTemplate({
                'id': 'builtin.tabata',
                'label': 'Tabata',
                'kind': 'interval',
                'builtin': true,
                'createdAt': 0,
                'rounds': 8,
                'sequence': [
                  {'role': 'work', 'durationSec': 20},
                  {'role': 'rest', 'durationSec': 10},
                ],
              })
              as Map<String, Object?>;
      expect(migrated['skipFinalRest'], isTrue);
    });

    test('旧记录宽容回填，但开始结束时间不伪造', () {
      final migrated =
          migrateSession({'id': 's', 'templateId': 't', 'kind': 'steady'})
              as Map<String, Object?>;
      expect(migrated['kind'], 'accumulate');
      expect(migrated['label'], '');
      expect(migrated['completed'], isFalse);
      expect(migrated['plannedSec'], 0);
      expect(migrated['roundsDone'], 0);
      expect(migrated.containsKey('startedAt'), isFalse);
      expect(migrated.containsKey('endedAt'), isFalse);
    });

    test('TODO 回填、钳制并清理非法可选字段', () {
      final migrated =
          migrateTodo({
                'id': 'd',
                'text': '事',
                'progress': 123.4,
                'tags': ['好', 1, '签'],
                'dueAt': 'bad',
                'archivedAt': 'bad',
              })
              as Map<String, Object?>;
      expect(migrated['progress'], 100);
      expect(migrated['pushes'], 0);
      expect(migrated['createdAt'], 0);
      expect(migrated['tags'], ['好', '签']);
      expect(migrated.containsKey('dueAt'), isFalse);
      expect(migrated.containsKey('archivedAt'), isFalse);
    });
  });

  group('备份导入导出', () {
    test('完整数据往返一致并保留自由编排', () {
      final template = validateTemplate(const {
        'id': 'q',
        'label': '编排',
        'kind': 'interval',
        'createdAt': 0,
        'rounds': 2,
        'sequence': [
          {'role': 'work', 'durationSec': 30},
          {'role': 'rest', 'durationSec': 10},
        ],
      });
      final session = validateSession(validSessionJson);
      final todo = validateTodo(validTodoJson);
      const growth = HiddenGrowth(
        level: 2,
        totalExp: 60,
        insights: ['first_10h'],
        insightUnlockedAt: {'first_10h': 100},
      );
      final json = buildBackup(
        [template],
        [session],
        defaultSettings,
        [todo],
        growth: growth,
        now: 123,
      );
      final parsed = parseBackup(json);
      expect(parsed.exportedAt, 123);
      expect(parsed.templates.single.toJson(), template.toJson());
      expect(parsed.todos.single.toJson(), todo.toJson());
      expect(parsed.skippedTotal, 0);
      expect(parsed.growth?.insightUnlockedAt['first_10h'], 100);
    });

    test('非 JSON、错 app、错版本与非数组字段硬拒绝', () {
      expect(() => parseBackup('{'), throwsA(isA<BackupException>()));
      expect(
        () => parseBackup(jsonEncode({...backup(), 'app': 'other'})),
        throwsA(isA<BackupException>()),
      );
      expect(
        parseBackup(jsonEncode({...backup(), 'version': 2})).exportedAt,
        999,
      );
      expect(
        () => parseBackup(jsonEncode({...backup(), 'version': 3})),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => parseBackup(jsonEncode(backup(templates: {}))),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => parseBackup(jsonEncode(backup(todos: {}))),
        throwsA(isA<BackupException>()),
      );
    });

    test('好坏条混杂逐条 salvage 并计数', () {
      final parsed = parseBackup(
        jsonEncode(
          backup(
            templates: [
              validTemplateJson,
              {'bad': true},
            ],
            sessions: [
              validSessionJson,
              {'id': 'bad'},
            ],
            todos: [
              validTodoJson,
              {'id': 'bad'},
            ],
          ),
        ),
      );
      expect(parsed.templates, hasLength(1));
      expect(parsed.sessions, hasLength(1));
      expect(parsed.todos, hasLength(1));
      expect(parsed.skippedTemplates, 1);
      expect(parsed.skippedSessions, 1);
      expect(parsed.skippedTodos, 1);
    });

    test('旧记录缺字段回填照收，缺 startedAt 则略过', () {
      final old = <String, Object>{
        'id': 'old',
        'templateId': 't1',
        'kind': 'pomodoro',
        'startedAt': 10,
        'endedAt': 20,
      };
      final missingStart = <String, Object>{...old, 'id': 'bad'}
        ..remove('startedAt');
      final parsed = parseBackup(
        jsonEncode(backup(sessions: [old, missingStart])),
      );
      expect(parsed.sessions.single.id, 'old');
      expect(parsed.sessions.single.roundsTotal, 0);
      expect(parsed.skippedSessions, 1);
    });

    test('重复 id 保留最后一份并计为略过', () {
      final parsed = parseBackup(
        jsonEncode(
          backup(
            templates: [
              validTemplateJson,
              {...validTemplateJson, 'label': '后来'},
            ],
          ),
        ),
      );
      expect(parsed.templates, hasLength(1));
      expect(parsed.templates.single.label, '后来');
      expect(parsed.skippedTemplates, 1);
    });

    test('旧备份无 todos 得空数组，settings 缺字段逐项回落', () {
      final parsed = parseBackup(
        jsonEncode(backup(settings: {'soundOn': false})),
      );
      expect(parsed.todos, isEmpty);
      expect(parsed.settings.soundOn, isFalse);
      expect(parsed.settings.volume, defaultSettings.volume);
    });

    test('同 id 旧记录不会覆盖本地冻结经验事实', () {
      final local = validateSession({
        ...validSessionJson,
        'focusedSec': 900,
        'qualityScore': 92,
        'qualityEvidence': const FocusQualityEvidence(
          manualPauseCount: 1,
        ).toJson(),
        'awardedMilliExp': 12345,
        'scoringVersion': 1,
      });
      final legacy = validateSession({
        ...validSessionJson,
        'label': '旧备份标题',
        'feeling': 'smooth',
      });
      final result = mergeById(
        [local],
        [legacy],
        (session) => session.id,
        mergeConflict: mergeSessionConflict,
      );
      final merged = result.items.single;
      expect(merged.label, '旧备份标题');
      expect(merged.feeling, SessionFeeling.smooth);
      expect(merged.focusedSec, 900);
      expect(merged.qualityScore, 92);
      expect(merged.awardedMilliExp, 12345);
      expect(merged.scoringVersion, 1);
    });

    test('同 id 无奖励旧备份不能覆盖本地版本零冻结经验', () {
      final local = validateSession({
        ...validSessionJson,
        'focusedSec': 900,
        'awardedMilliExp': 12345,
        'scoringVersion': 0,
      });
      final legacy = validateSession({
        ...validSessionJson,
        'label': '旧备份标题',
        'feeling': 'smooth',
      });
      final before = computeTotalExp(sessions: [local], todos: const []);
      final merged = mergeSessionConflict(local, legacy);

      expect(merged.label, '旧备份标题');
      expect(merged.feeling, SessionFeeling.smooth);
      expect(merged.focusedSec, 900);
      expect(merged.awardedMilliExp, local.awardedMilliExp);
      expect(merged.scoringVersion, 0);
      expect(computeTotalExp(sessions: [merged], todos: const []), before);
    });

    test('同 id 带奖励但不完整的 v2 不能覆盖本地冻结经验事实', () {
      final local = validateSession({
        ...validSessionJson,
        'focusedSec': 900,
        'qualityScore': 92,
        'qualityEvidence': const FocusQualityEvidence(
          manualPauseCount: 1,
        ).toJson(),
        'awardedMilliExp': 12345,
        'scoringVersion': 1,
      });
      final partialV2 = SessionRecord(
        id: local.id,
        templateId: local.templateId,
        label: '部分新版标题',
        kind: local.kind,
        startedAt: local.startedAt,
        endedAt: local.endedAt,
        plannedSec: local.plannedSec,
        elapsedSec: local.elapsedSec,
        completed: local.completed,
        roundsDone: local.roundsDone,
        roundsTotal: local.roundsTotal,
        feeling: SessionFeeling.transcendent,
        focusedSec: 1,
        awardedMilliExp: 999999,
        scoringVersion: 1,
      );

      final merged = mergeSessionConflict(local, partialV2);

      expect(merged.label, '部分新版标题');
      expect(merged.feeling, SessionFeeling.transcendent);
      expect(merged.focusedSec, 900);
      expect(merged.qualityScore, 92);
      expect(merged.awardedMilliExp, 12345);
      expect(merged.scoringVersion, 1);
    });

    test('合并保持旧顺序，同 id 更新，新 id 追加', () {
      const old = [
        TodoItem(id: 'a', text: 'A', progress: 0, pushes: 0, createdAt: 0),
        TodoItem(id: 'b', text: 'B', progress: 0, pushes: 0, createdAt: 0),
      ];
      const incoming = [
        TodoItem(id: 'b', text: 'B2', progress: 0, pushes: 0, createdAt: 0),
        TodoItem(id: 'c', text: 'C', progress: 0, pushes: 0, createdAt: 0),
      ];
      final result = mergeById(old, incoming, (todo) => todo.id);
      expect(result.items.map((todo) => todo.id), ['a', 'b', 'c']);
      expect(result.items[1].text, 'B2');
      expect(result.added, 1);
      expect(result.updated, 1);
    });
  });
}
