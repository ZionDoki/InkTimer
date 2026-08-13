import 'models.dart';

class DayBucket {
  const DayBucket({
    required this.date,
    required this.sec,
    required this.count,
    required this.completed,
    required this.interruptions,
  });

  final String date;
  final int sec;
  final int count;
  final int completed;
  final int interruptions;
}

class KindStat {
  const KindStat({required this.sec, required this.count});

  final int sec;
  final int count;
}

class TemplateStat {
  const TemplateStat({
    required this.templateId,
    required this.label,
    required this.kind,
    required this.sec,
    required this.count,
  });

  final String templateId;
  final String label;
  final TemplateKind kind;
  final int sec;
  final int count;
}

class DurationBucket {
  const DurationBucket({required this.label, required this.count});

  final String label;
  final int count;
}

class StatsSummary {
  const StatsSummary({
    required this.todaySec,
    required this.todayCount,
    required this.weekSec,
    required this.totalSec,
    required this.totalCount,
    required this.streakDays,
    required this.totalInterruptions,
    required this.zeroInterruptRate,
    required this.byHour,
    required this.durationBuckets,
    required this.longestSessionSec,
    required this.byKind,
    required this.byTemplate,
    required this.daily,
    required this.measuredQualityCount,
    required this.averageQuality,
    required this.undisturbedRate,
    required this.backgroundFocusSec,
    required this.legacyQualityCount,
  });

  final int todaySec;
  final int todayCount;
  final int weekSec;
  final int totalSec;
  final int totalCount;
  final int streakDays;
  final int totalInterruptions;
  final double zeroInterruptRate;
  final List<int> byHour;
  final List<DurationBucket> durationBuckets;
  final int longestSessionSec;
  final Map<TemplateKind, KindStat> byKind;
  final List<TemplateStat> byTemplate;
  final List<DayBucket> daily;
  final int measuredQualityCount;
  final double averageQuality;
  final double undisturbedRate;
  final int backgroundFocusSec;
  final int legacyQualityCount;
}

class TodoSummary {
  const TodoSummary({
    required this.doing,
    required this.done,
    required this.averageProgress,
    required this.totalPushes,
  });

  final int doing;
  final int done;
  final int averageProgress;
  final int totalPushes;
}

class _MutableDay {
  _MutableDay(this.date);

  final String date;
  int sec = 0;
  int count = 0;
  int completed = 0;
  int interruptions = 0;

  DayBucket freeze() => DayBucket(
    date: date,
    sec: sec,
    count: count,
    completed: completed,
    interruptions: interruptions,
  );
}

class _MutableKind {
  int sec = 0;
  int count = 0;
}

class _MutableTemplate {
  _MutableTemplate(this.label, this.kind);

  final String label;
  final TemplateKind kind;
  int sec = 0;
  int count = 0;
}

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _mondayOf(DateTime date) {
  final midnight = DateTime(date.year, date.month, date.day);
  return midnight.subtract(Duration(days: midnight.weekday - DateTime.monday));
}

int _durationBucketIndex(int sec) {
  if (sec < 300) return 0;
  if (sec < 900) return 1;
  if (sec < 1800) return 2;
  if (sec <= 3600) return 3;
  return 4;
}

StatsSummary summarizeSessions(List<SessionRecord> sessions, DateTime now) {
  final todayKey = dayKey(now);
  final nowMilliseconds = now.millisecondsSinceEpoch;
  final weekStart = _mondayOf(now).millisecondsSinceEpoch;
  final mutableKinds = {
    for (final kind in TemplateKind.values) kind: _MutableKind(),
  };
  final mutableTemplates = <String, _MutableTemplate>{};
  final days = <String, _MutableDay>{};
  final completedFocusedByDay = <String, int>{};
  final byHour = List<int>.filled(24, 0);
  final durationCounts = List<int>.filled(5, 0);

  var todaySec = 0;
  var todayCount = 0;
  var weekSec = 0;
  var totalSec = 0;
  var totalInterruptions = 0;
  var zeroInterrupt = 0;
  var longestSessionSec = 0;
  var totalCount = 0;
  var measuredQualityCount = 0;
  var totalQuality = 0;
  var undisturbed = 0;
  var backgroundFocusSec = 0;
  var legacyQualityCount = 0;

  for (final session in sessions) {
    if (session.startedAt > nowMilliseconds ||
        session.endedAt > nowMilliseconds) {
      continue;
    }
    totalCount += 1;
    if (session.qualityScore == null || session.qualityEvidence == null) {
      legacyQualityCount += 1;
    } else {
      measuredQualityCount += 1;
      totalQuality += session.qualityScore!;
      final evidence = session.qualityEvidence!;
      backgroundFocusSec += evidence.backgroundFocusSec;
      if (session.qualityScore == 100) undisturbed += 1;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(session.startedAt);
    final key = dayKey(date);
    final interruptions = session.interruptions ?? 0;
    final day = days.putIfAbsent(key, () => _MutableDay(key));
    day.sec += session.elapsedSec;
    day.count += 1;
    day.interruptions += interruptions;
    if (session.completed) {
      day.completed += 1;
      completedFocusedByDay[key] =
          (completedFocusedByDay[key] ?? 0) +
          (session.focusedSec ?? session.elapsedSec);
    }

    final kind = mutableKinds[session.kind]!;
    kind.sec += session.elapsedSec;
    kind.count += 1;
    final template = mutableTemplates.putIfAbsent(
      session.templateId,
      () => _MutableTemplate(session.label, session.kind),
    );
    template.sec += session.elapsedSec;
    template.count += 1;

    totalSec += session.elapsedSec;
    totalInterruptions += interruptions;
    if (interruptions == 0) zeroInterrupt += 1;
    byHour[date.hour] += 1;
    durationCounts[_durationBucketIndex(session.elapsedSec)] += 1;
    if (session.elapsedSec > longestSessionSec) {
      longestSessionSec = session.elapsedSec;
    }
    if (key == todayKey) {
      todaySec += session.elapsedSec;
      todayCount += 1;
    }
    if (session.startedAt >= weekStart) weekSec += session.elapsedSec;
  }

  final eligibleDays = {
    for (final entry in completedFocusedByDay.entries)
      if (entry.value >= 150) entry.key,
  };
  var streak = 0;
  var cursor = DateTime(now.year, now.month, now.day);
  if (!eligibleDays.contains(dayKey(cursor))) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  while (eligibleDays.contains(dayKey(cursor))) {
    streak += 1;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  final daily = <DayBucket>[];
  var date = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 83));
  for (var index = 0; index < 84; index += 1) {
    final key = dayKey(date);
    daily.add(
      days[key]?.freeze() ??
          DayBucket(
            date: key,
            sec: 0,
            count: 0,
            completed: 0,
            interruptions: 0,
          ),
    );
    date = date.add(const Duration(days: 1));
  }

  final byTemplate =
      mutableTemplates.entries
          .map(
            (entry) => TemplateStat(
              templateId: entry.key,
              label: entry.value.label,
              kind: entry.value.kind,
              sec: entry.value.sec,
              count: entry.value.count,
            ),
          )
          .toList()
        ..sort((a, b) => b.sec.compareTo(a.sec));

  const durationLabels = ['<5m', '5-15m', '15-30m', '30-60m', '>60m'];
  return StatsSummary(
    todaySec: todaySec,
    todayCount: todayCount,
    weekSec: weekSec,
    totalSec: totalSec,
    totalCount: totalCount,
    streakDays: streak,
    totalInterruptions: totalInterruptions,
    zeroInterruptRate: totalCount == 0 ? 0 : zeroInterrupt / totalCount,
    byHour: byHour,
    durationBuckets: [
      for (var index = 0; index < durationLabels.length; index += 1)
        DurationBucket(
          label: durationLabels[index],
          count: durationCounts[index],
        ),
    ],
    longestSessionSec: longestSessionSec,
    byKind: {
      for (final entry in mutableKinds.entries)
        entry.key: KindStat(sec: entry.value.sec, count: entry.value.count),
    },
    byTemplate: byTemplate,
    daily: daily,
    measuredQualityCount: measuredQualityCount,
    averageQuality: measuredQualityCount == 0
        ? 0
        : totalQuality / measuredQualityCount,
    undisturbedRate: measuredQualityCount == 0
        ? 0
        : undisturbed / measuredQualityCount,
    backgroundFocusSec: backgroundFocusSec,
    legacyQualityCount: legacyQualityCount,
  );
}

double recentMeasuredQualityAverage(
  List<SessionRecord> sessions, {
  int limit = 10,
}) {
  final measured =
      sessions
          .where(
            (session) =>
                session.completed &&
                (session.focusedSec ?? session.elapsedSec) >= 150 &&
                session.qualityScore != null,
          )
          .toList()
        ..sort((left, right) => right.endedAt.compareTo(left.endedAt));
  final recent = measured.take(limit).toList();
  if (recent.isEmpty) return 0;
  return recent.fold<int>(0, (sum, session) => sum + session.qualityScore!) /
      recent.length;
}

TodoSummary summarizeTodos(List<TodoItem> todos) {
  final visible = todos.where((todo) => todo.archivedAt == null).toList();
  if (visible.isEmpty) {
    return const TodoSummary(
      doing: 0,
      done: 0,
      averageProgress: 0,
      totalPushes: 0,
    );
  }
  final done = visible.where((todo) => todo.progress == 100).length;
  final progress = visible.fold(0, (sum, todo) => sum + todo.progress);
  final pushes = visible.fold(0, (sum, todo) => sum + todo.pushes);
  return TodoSummary(
    doing: visible.length - done,
    done: done,
    averageProgress: (progress / visible.length).round(),
    totalPushes: pushes,
  );
}

String formatDuration(num seconds) {
  final safe = seconds.round().clamp(0, 1 << 62);
  if (safe < 60) return '${safe}s';
  final minutes = (safe / 60).round();
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest > 0 ? '${hours}h ${rest}m' : '${hours}h';
}
