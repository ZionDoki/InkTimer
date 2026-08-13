import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/focus_quality.dart';
import 'package:uptimer/domain/growth.dart';
import 'package:uptimer/domain/growth_models.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/schema.dart';
import 'package:uptimer/domain/stats.dart';

SessionRecord session({
  int elapsedSec = 3600,
  bool completed = true,
  SessionFeeling? feeling,
  String? linkedTodoId,
}) => SessionRecord(
  id: 'session-1',
  templateId: 'template-1',
  label: '专注',
  kind: TemplateKind.pomodoro,
  startedAt: 100,
  endedAt: 100 + elapsedSec * 1000,
  plannedSec: elapsedSec,
  elapsedSec: elapsedSec,
  completed: completed,
  roundsDone: 1,
  roundsTotal: 1,
  interruptions: 0,
  feeling: feeling,
  linkedTodoId: linkedTodoId,
);

TodoItem todoWithHours(double hours) => TodoItem(
  id: 'todo-1',
  text: '练习',
  progress: 0,
  pushes: 0,
  createdAt: 1,
  totalFocusSec: (hours * 3600).round(),
  sessionsLinked: 1,
);

void main() {
  group('历史经验稳定', () {
    test('按累计投入时间分段递增并在一万小时封顶', () {
      expect(todoLinkBonus(null), 1.0);
      expect(todoLinkBonus(todoWithHours(0)), 1.0);
      expect(todoLinkBonus(todoWithHours(1)), closeTo(1.01, 0.000001));
      expect(todoLinkBonus(todoWithHours(2)), closeTo(1.03, 0.000001));
      expect(todoLinkBonus(todoWithHours(4)), closeTo(1.10, 0.000001));
      expect(todoLinkBonus(todoWithHours(10)), closeTo(1.20, 0.000001));
      expect(todoLinkBonus(todoWithHours(20)), closeTo(1.30, 0.000001));
      expect(todoLinkBonus(todoWithHours(100)), closeTo(1.35, 0.000001));
      expect(todoLinkBonus(todoWithHours(1000)), closeTo(1.40, 0.000001));
      expect(todoLinkBonus(todoWithHours(10000)), 1.50);
      expect(todoLinkBonus(todoWithHours(20000)), 1.50);
    });

    test('目标关联和主观感受不改变专注经验', () {
      final plain = calculateSessionExp(session: session(), streakDays: 10);
      final linked = calculateSessionExp(
        session: session(
          linkedTodoId: 'todo-1',
          feeling: SessionFeeling.transcendent,
        ),
        streakDays: 10,
        linkedTodo: todoWithHours(10000),
      );

      expect(plain, linked);
      expect(feelingBonus(null), 1.0);
      expect(feelingBonus(SessionFeeling.arduous), 1.0);
      expect(feelingBonus(SessionFeeling.smooth), 1.0);
      expect(feelingBonus(SessionFeeling.transcendent), 1.0);
    });
  });

  group('成长字段兼容解析', () {
    test('旧 session 与旧目标缺少新增字段时使用空值和零值', () {
      final oldSession = validateSession(const {
        'id': 's1',
        'templateId': 't1',
        'label': '专注',
        'kind': 'pomodoro',
        'startedAt': 100,
        'endedAt': 200,
        'plannedSec': 100,
        'elapsedSec': 100,
        'completed': true,
        'roundsDone': 1,
        'roundsTotal': 1,
      });
      final oldTodo = validateTodo(const {
        'id': 'd1',
        'text': '旧目标',
        'progress': 0,
        'pushes': 0,
        'createdAt': 100,
      });

      expect(oldSession.feeling, isNull);
      expect(oldSession.linkedTodoId, isNull);
      expect(oldTodo.totalFocusSec, 0);
      expect(oldTodo.sessionsLinked, 0);
    });

    test('新增字段严格校验类型与非负边界', () {
      expect(
        validateSession({
          ...session(linkedTodoId: 'todo-1').toJson(),
          'feeling': 'transcendent',
        }).feeling,
        SessionFeeling.transcendent,
      );
      expect(
        validateTodo({
          ...todoWithHours(2).toJson(),
          'totalFocusSec': 7200,
          'sessionsLinked': 3,
        }).sessionsLinked,
        3,
      );
      expect(
        () => validateSession({...session().toJson(), 'feeling': 'unknown'}),
        throwsA(isA<SchemaException>()),
      );
      final measured = validateSession({
        ...session().toJson(),
        'focusedSec': 3000,
        'qualityEvidence': const FocusQualityEvidence(
          inAppDiversionCount: 1,
        ).toJson(),
        'qualityScore': 94,
        'awardedMilliExp': 55000,
        'scoringVersion': 1,
      });
      expect(measured.copyWith(linkedTodoId: 'todo').qualityScore, 94);
      expect(
        measured.copyWith(feeling: SessionFeeling.smooth).awardedMilliExp,
        55000,
      );
      expect(
        () => validateTodo({...todoWithHours(2).toJson(), 'totalFocusSec': -1}),
        throwsA(isA<SchemaException>()),
      );
    });

    test('隐修摘要校验等级与悟列表边界', () {
      final parsed = validateHiddenGrowth(const {
        'level': 7,
        'totalExp': 3600,
        'insights': ['first_10h'],
      });
      expect(parsed.level, 7);
      expect(parsed.totalExp, 3600);
      expect(parsed.insights, ['first_10h']);
      expect(parsed.version, 1);

      expect(
        () => validateHiddenGrowth(const {
          'level': 0,
          'totalExp': 0,
          'insights': <String>[],
        }),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateHiddenGrowth(const {
          'level': 1,
          'totalExp': -1,
          'insights': <String>[],
        }),
        throwsA(isA<SchemaException>()),
      );
      expect(
        () => validateHiddenGrowth(const {
          'level': 1,
          'totalExp': 0,
          'insights': [1, 2],
        }),
        throwsA(isA<SchemaException>()),
      );
    });
  });

  group('等级与悟', () {
    test('经验转等级单调不递减并封顶在 99', () {
      expect(expToLevel(0), 1);
      expect(expToLevel(-10), 1);
      expect(expToLevel(59), 1);
      expect(expToLevel(60), 2);
      expect(expToLevel(2253), 10);
      expect(expToLevel(115791), 99);
      expect(expToLevel(99999999), 99);

      var previous = 0;
      for (var exp = 0; exp < 200000; exp += 977) {
        final level = expToLevel(exp);
        expect(level, greaterThanOrEqualTo(previous));
        previous = level;
      }
    });

    test('等级区间与下一阶差值互相吻合', () {
      expect(levelToExp(1), 0);
      expect(levelToExp(10), 2253);
      expect(levelToNextExp(99), 0);
      for (final level in [1, 2, 9, 30, 98]) {
        expect(
          levelToExp(level) + levelToNextExp(level),
          levelToExp(level + 1),
        );
        expect(expToLevel(levelToExp(level)), level);
      }
    });

    test('悟定义 id 唯一、可反查，且无中英文混拼名', () {
      final ids = allInsights.map((def) => def.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final def in allInsights) {
        expect(insightById(def.id), same(def));
        expect(
          RegExp(r'^[\u4e00-\u9fa5\u00b7]+$').hasMatch(def.name),
          isTrue,
          reason: '悟名应为纯中文：${def.name}',
        );
      }
      expect(insightById('not_exist'), isNull);
    });

    test('悟只在阈值达到时解锁，且不重复解锁', () {
      final base = GrowthContext(
        sessions: [session(elapsedSec: 5400)],
        todos: [todoWithHours(10)],
        totalSec: 36000,
        bestStreakDays: 7,
        zeroInterruptRate: 0.5,
        unlockedInsights: const [],
      );
      final unlocked = checkNewInsights(base, 999).map((i) => i.id).toSet();
      expect(
        unlocked,
        containsAll(<String>[
          'first_10h',
          'streak_7',
          'single_90min',
          'todo_10h_single',
        ]),
      );
      expect(unlocked, isNot(contains('first_100h')));
      expect(unlocked, isNot(contains('todo_link_first')));
      expect(unlocked, isNot(contains('zero_interrupt_50pct')));

      final again = checkNewInsights(
        GrowthContext(
          sessions: base.sessions,
          todos: base.todos,
          totalSec: base.totalSec,
          bestStreakDays: base.bestStreakDays,
          zeroInterruptRate: base.zeroInterruptRate,
          unlockedInsights: unlocked.toList(),
        ),
        1000,
      );
      expect(again, isEmpty);
      expect(checkNewInsights(base, 999).first.unlockedAt, 999);
    });

    test('深耕段位名随累积投入递进', () {
      expect(todoTierLabel(0), '初 涉');
      expect(todoTierLabel(3600), '入 门');
      expect(todoTierLabel(4 * 3600), '渐 熟');
      expect(todoTierLabel(10 * 3600), '熟 手');
      expect(todoTierLabel(100 * 3600), '专 精');
      expect(todoTierLabel(1000 * 3600), '大 师');
      expect(todoTierLabel(10000 * 3600), '宗 师');
    });
  });

  group('累积经验必须可重算（与重算时刻无关）', () {
    SessionRecord dayed(int dayOffset, {bool completed = true}) {
      final start = DateTime(2026, 3, 10 + dayOffset, 9).millisecondsSinceEpoch;
      return SessionRecord(
        id: 'session-$dayOffset',
        templateId: 'template-1',
        label: '专注',
        kind: TemplateKind.pomodoro,
        startedAt: start,
        endedAt: start + 1500 * 1000,
        plannedSec: 1500,
        elapsedSec: 1500,
        completed: completed,
        roundsDone: 1,
        roundsTotal: 1,
        interruptions: 0,
      );
    }

    test('同一批记录多次重算结果相同，不受“现在”影响', () {
      final sessions = [for (var day = 0; day < 5; day += 1) dayed(day)];
      final first = computeTotalExp(sessions: sessions, todos: const []);
      final again = computeTotalExp(
        sessions: List.of(sessions.reversed),
        todos: const [],
      );
      expect(again, first);
      expect(first, greaterThan(0));
    });

    test('连击取该次专注当天的连续天数，后来断签不会让旧记录经验缩水', () {
      final threeDays = [for (var day = 0; day < 3; day += 1) dayed(day)];
      final baseline = computeTotalExp(sessions: threeDays, todos: const []);

      // 隔了很久才练下一次：旧的三天仍然各算自己当时的连击。
      final withGap = [...threeDays, dayed(40)];
      final after = computeTotalExp(sessions: withGap, todos: const []);
      expect(after, greaterThan(baseline));
      expect(
        after - baseline,
        calculateSessionExp(session: dayed(40), streakDays: 1),
      );
    });

    test('连击加成封顶后不再回溯更多天', () {
      final long = [for (var day = 0; day < 30; day += 1) dayed(day)];
      final capped = calculateSessionExp(
        session: dayed(29),
        streakDays: maxStreakBonusDays,
      );
      final overCap = calculateSessionExp(session: dayed(29), streakDays: 30);
      expect(capped, overCap);
      expect(
        computeTotalExp(sessions: long, todos: const []),
        greaterThan(capped),
      );
    });

    test('未完成的专注不参与连击，但仍按折扣计经验', () {
      final onlyPartial = [dayed(0, completed: false)];
      final exp = computeTotalExp(sessions: onlyPartial, todos: const []);
      expect(
        exp,
        calculateSessionExp(session: dayed(0, completed: false), streakDays: 0),
      );
      expect(exp, greaterThan(0));
    });
  });

  group('印记与悟共用一套阈值', () {
    SessionRecord onDay(int dayOffset, {bool completed = true}) {
      final start = DateTime(2026, 1, 1 + dayOffset, 9).millisecondsSinceEpoch;
      return SessionRecord(
        id: 'session-$dayOffset',
        templateId: 'template-1',
        label: '专注',
        kind: TemplateKind.pomodoro,
        startedAt: start,
        endedAt: start + 1500 * 1000,
        plannedSec: 1500,
        elapsedSec: 1500,
        completed: completed,
        roundsDone: 1,
        roundsTotal: 1,
        interruptions: 0,
      );
    }

    GrowthContext ctxFor(List<SessionRecord> sessions) => GrowthContext(
      sessions: sessions,
      todos: const [],
      totalSec: sessions.fold(0, (sum, s) => sum + s.elapsedSec),
      bestStreakDays: bestStreakDays(sessions),
      zeroInterruptRate: 0,
      unlockedInsights: const [],
    );

    test('三方印记各自对应一条悟，且阈值与悟的判定一致', () {
      expect(sealMarks.map((m) => m.days), [7, 30, 100]);
      expect(sealMarks.map((m) => m.character), ['柒', '卅', '百']);
      for (final mark in sealMarks) {
        expect(
          insightById(mark.insightId),
          isNotNull,
          reason: '印记 ${mark.character} 没有对应的悟',
        );
        expect(sealInsightIds, contains(mark.insightId));

        // 差一天不解锁，刚好达到就解锁。
        final justShort = [
          for (var day = 0; day < mark.days - 1; day += 1) onDay(day),
        ];
        final exact = [for (var day = 0; day < mark.days; day += 1) onDay(day)];
        final shortIds = checkNewInsights(
          ctxFor(justShort),
          1,
        ).map((i) => i.id);
        final exactIds = checkNewInsights(ctxFor(exact), 1).map((i) => i.id);
        expect(shortIds, isNot(contains(mark.insightId)));
        expect(exactIds, contains(mark.insightId));
      }
    });

    test('印记取历史最长连续，断签后不会收回', () {
      final sevenThenBreak = [
        for (var day = 0; day < 7; day += 1) onDay(day),
        onDay(40), // 隔了很久才练下一次，当下连续只有 1 天
      ];
      expect(bestStreakDays(sevenThenBreak), 7);
      expect(
        checkNewInsights(ctxFor(sevenThenBreak), 1).map((i) => i.id),
        contains('streak_7'),
      );

      // 对比：当下连续天数已经跌回 1，若用它判定就会丢印。
      expect(
        summarizeSessions(sevenThenBreak, DateTime(2026, 2, 10)).streakDays,
        lessThan(7),
      );
    });

    test('最长连续取最长的那一段，不是第一段也不是最后一段', () {
      final sessions = [
        for (var day = 0; day < 3; day += 1) onDay(day),
        for (var day = 10; day < 19; day += 1) onDay(day),
        for (var day = 30; day < 32; day += 1) onDay(day),
      ];
      expect(bestStreakDays(sessions), 9);
    });

    test('未完成的专注不计入连续天数', () {
      expect(bestStreakDays([]), 0);
      expect(bestStreakDays([onDay(0, completed: false)]), 0);
      expect(
        bestStreakDays([onDay(0), onDay(1, completed: false), onDay(2)]),
        1,
      );
    });
  });
}
