import 'dart:math' show pow;

import 'focus_quality.dart';
import 'growth_models.dart';
import 'models.dart';
import 'stats.dart' show dayKey;

/// Kept for cultivation UI compatibility. Post-session linking no longer
/// changes experience; historical awards are immutable.
double todoLinkBonus(TodoItem? linkedTodo) {
  if (linkedTodo == null) return 1.0;
  final hours = linkedTodo.totalFocusSec / 3600.0;
  if (hours < 1) return 1.0 + hours * 0.01;
  if (hours < 2) return 1.01 + (hours - 1) * 0.02;
  if (hours < 4) return 1.03 + (hours - 2) * 0.035;
  if (hours < 10) return 1.10 + (hours - 4) * 0.0167;
  if (hours < 20) return 1.20 + (hours - 10) * 0.01;
  if (hours < 100) return 1.30 + (hours - 20) * 0.000625;
  if (hours < 1000) return 1.35 + (hours - 100) * 0.0000556;
  if (hours < 10000) return 1.40 + (hours - 1000) * 0.0000056;
  return 1.50;
}

/// Reflection is deliberately neutral for experience.
double feelingBonus(SessionFeeling? feeling) => 1.0;

const maxStreakBonusDays = 10;
const minimumEligibleFocusedSec = 150;

bool sessionEligibleForPractice(SessionRecord session) =>
    session.completed &&
    (session.focusedSec ?? session.elapsedSec) >= minimumEligibleFocusedSec;

Set<String> _eligiblePracticeDays(Iterable<SessionRecord> sessions) {
  final focusedByDay = <String, int>{};
  for (final session in sessions) {
    if (!session.completed) continue;
    final focused = session.focusedSec ?? session.elapsedSec;
    final key = dayKey(DateTime.fromMillisecondsSinceEpoch(session.startedAt));
    focusedByDay[key] = (focusedByDay[key] ?? 0) + focused;
  }
  return {
    for (final entry in focusedByDay.entries)
      if (entry.value >= minimumEligibleFocusedSec) entry.key,
  };
}

int streakDaysForSession(SessionRecord session, Set<String> eligibleDays) {
  final day = DateTime.fromMillisecondsSinceEpoch(session.startedAt);
  var cursor = DateTime(day.year, day.month, day.day);
  var streak = 0;
  while (streak < maxStreakBonusDays && eligibleDays.contains(dayKey(cursor))) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

int calculateSessionMilliExp({
  required SessionRecord session,
  required int streakDays,
}) {
  final frozen = session.awardedMilliExp;
  if (frozen != null) return frozen;
  final focused = session.focusedSec ?? session.elapsedSec;
  return calculateAwardedMilliExp(
    focusedSec: focused,
    accumulate: session.kind == TemplateKind.accumulate,
    completed: session.completed,
    qualityScore: session.qualityScore ?? 100,
    streakDays: streakDays,
  );
}

int calculateSessionExp({
  required SessionRecord session,
  required int streakDays,
  TodoItem? linkedTodo,
}) =>
    (calculateSessionMilliExp(session: session, streakDays: streakDays) / 1000)
        .round();

int computeTotalMilliExp({
  required List<SessionRecord> sessions,
  List<TodoItem> todos = const [],
}) {
  final eligibleDays = _eligiblePracticeDays(sessions);
  return sessions.fold<int>(0, (total, session) {
    return total +
        calculateSessionMilliExp(
          session: session,
          streakDays: streakDaysForSession(session, eligibleDays),
        );
  });
}

int computeTotalExp({
  required List<SessionRecord> sessions,
  required List<TodoItem> todos,
}) => (computeTotalMilliExp(sessions: sessions, todos: todos) / 1000).round();

/// Legacy curve used only to preserve a user's former level position once.
int legacyExpToLevel(int totalExp) {
  if (totalExp <= 0) return 1;
  return (pow(totalExp / 200.0, 0.6) + 1).floor().clamp(1, 99);
}

int legacyLevelToExp(int level) {
  if (level <= 1) return 0;
  return (200.0 * pow(level - 1, 1.0 / 0.6)).ceil();
}

int mapLegacyExpToNewCurve(int legacyExp) {
  final level = legacyExpToLevel(legacyExp);
  if (level >= 99) return levelToExp(99);
  final oldFloor = legacyLevelToExp(level);
  final oldSpan = legacyLevelToExp(level + 1) - oldFloor;
  final fraction = oldSpan <= 0
      ? 0.0
      : ((legacyExp - oldFloor) / oldSpan).clamp(0.0, 1.0);
  final newFloor = levelToExp(level);
  final newSpan = levelToExp(level + 1) - newFloor;
  return newFloor + (newSpan * fraction).round();
}

/// New, narrower curve: 60 × (level - 1)^1.65.
int levelToExp(int level) {
  if (level <= 1) return 0;
  return (60.0 * pow(level - 1, 1.65)).ceil();
}

int expToLevel(int totalExp) {
  if (totalExp <= 0) return 1;
  var low = 1;
  var high = 99;
  while (low < high) {
    final mid = (low + high + 1) ~/ 2;
    if (levelToExp(mid) <= totalExp) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

int levelToNextExp(int level) =>
    level >= 99 ? 0 : levelToExp(level + 1) - levelToExp(level);

const List<SealMark> sealMarks = [
  SealMark(character: '柒', insightId: 'streak_7', days: 7),
  SealMark(character: '卅', insightId: 'streak_30', days: 30),
  SealMark(character: '百', insightId: 'streak_100', days: 100),
];

final Set<String> sealInsightIds = {
  for (final mark in sealMarks) mark.insightId,
};

int bestStreakDays(List<SessionRecord> sessions) {
  final eligibleDays = _eligiblePracticeDays(sessions);
  var best = 0;
  for (final key in eligibleDays) {
    final parts = key.split('-').map(int.parse).toList();
    var cursor = DateTime(parts[0], parts[1], parts[2]);
    if (eligibleDays.contains(dayKey(cursor.add(const Duration(days: 1))))) {
      continue;
    }
    var run = 0;
    while (eligibleDays.contains(dayKey(cursor))) {
      run += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    if (run > best) best = run;
  }
  return best;
}

const List<InsightDefinition> allInsights = [
  InsightDefinition(
    id: 'first_10h',
    name: '始行',
    description: '累积专注 10 小时',
    check: _check10Hours,
  ),
  InsightDefinition(
    id: 'first_100h',
    name: '百时',
    description: '累积专注 100 小时',
    check: _check100Hours,
  ),
  InsightDefinition(
    id: 'first_500h',
    name: '五百',
    description: '累积专注 500 小时',
    check: _check500Hours,
  ),
  InsightDefinition(
    id: 'first_1000h',
    name: '千时',
    description: '累积专注 1000 小时',
    check: _check1000Hours,
  ),
  InsightDefinition(
    id: 'streak_7',
    name: '不辍',
    description: '连续 7 天专注',
    check: _checkStreak7,
  ),
  InsightDefinition(
    id: 'streak_30',
    name: '恒课',
    description: '连续 30 天专注',
    check: _checkStreak30,
  ),
  InsightDefinition(
    id: 'streak_100',
    name: '百日',
    description: '连续 100 天专注',
    check: _checkStreak100,
  ),
  InsightDefinition(
    id: 'single_90min',
    name: '深坐',
    description: '单次专注 90 分钟以上',
    check: _checkSingle90Min,
  ),
  InsightDefinition(
    id: 'transcendent_10',
    name: '心流初识',
    description: '10 次高定力「透」感受',
    check: _checkTranscendent10,
  ),
  InsightDefinition(
    id: 'todo_link_first',
    name: '始契',
    description: '首次为目标专注',
    check: _checkFirstTodoLink,
  ),
  InsightDefinition(
    id: 'todo_10h_single',
    name: '熟手',
    description: '单个目标累积 10 小时',
    check: _checkTodo10H,
  ),
  InsightDefinition(
    id: 'todo_100h_single',
    name: '专精',
    description: '单个目标累积 100 小时',
    check: _checkTodo100H,
  ),
  InsightDefinition(
    id: 'todo_1000h_single',
    name: '大师',
    description: '单个目标累积 1000 小时',
    check: _checkTodo1000H,
  ),
  InsightDefinition(
    id: 'zero_interrupt_50pct',
    name: '静定',
    description: '十次功课平均定力达到 90',
    check: _checkHighQuality,
  ),
];

bool _check10Hours(GrowthContext ctx) => ctx.totalSec >= 36000;
bool _check100Hours(GrowthContext ctx) => ctx.totalSec >= 360000;
bool _check500Hours(GrowthContext ctx) => ctx.totalSec >= 1800000;
bool _check1000Hours(GrowthContext ctx) => ctx.totalSec >= 3600000;
bool _checkStreak7(GrowthContext ctx) => ctx.bestStreakDays >= 7;
bool _checkStreak30(GrowthContext ctx) => ctx.bestStreakDays >= 30;
bool _checkStreak100(GrowthContext ctx) => ctx.bestStreakDays >= 100;
bool _checkSingle90Min(GrowthContext ctx) => ctx.sessions.any(
  (session) =>
      session.completed && (session.focusedSec ?? session.elapsedSec) >= 5400,
);
bool _checkTranscendent10(GrowthContext ctx) =>
    ctx.sessions.where((session) {
      return session.feeling == SessionFeeling.transcendent &&
          (session.qualityScore == null || session.qualityScore! >= 85);
    }).length >=
    10;
bool _checkFirstTodoLink(GrowthContext ctx) =>
    ctx.sessions.any((s) => s.linkedTodoId != null);
bool _checkTodo10H(GrowthContext ctx) =>
    ctx.todos.any((t) => t.totalFocusSec >= 36000);
bool _checkTodo100H(GrowthContext ctx) =>
    ctx.todos.any((t) => t.totalFocusSec >= 360000);
bool _checkTodo1000H(GrowthContext ctx) =>
    ctx.todos.any((t) => t.totalFocusSec >= 3600000);
bool _checkHighQuality(GrowthContext ctx) {
  final measured = ctx.sessions
      .where(
        (session) =>
            sessionEligibleForPractice(session) && session.qualityScore != null,
      )
      .toList();
  if (measured.length < 10) return false;
  return measured.fold<int>(0, (sum, session) => sum + session.qualityScore!) /
          measured.length >=
      90;
}

String todoTierLabel(int totalFocusSec) {
  final hours = totalFocusSec / 3600.0;
  if (hours < 1) return '初 涉';
  if (hours < 4) return '入 门';
  if (hours < 10) return '渐 熟';
  if (hours < 100) return '熟 手';
  if (hours < 1000) return '专 精';
  if (hours < 10000) return '大 师';
  return '宗 师';
}

InsightDefinition? insightById(String id) {
  for (final def in allInsights) {
    if (def.id == id) return def;
  }
  return null;
}

List<Insight> checkNewInsights(GrowthContext ctx, int now) {
  return [
    for (final def in allInsights)
      if (!ctx.unlockedInsights.contains(def.id) && def.check(ctx))
        Insight(
          id: def.id,
          name: def.name,
          description: def.description,
          unlockedAt: now,
        ),
  ];
}
