import 'focus_quality.dart';

enum TemplateKind { pomodoro, interval, accumulate }

extension TemplateKindWire on TemplateKind {
  String get wire => name;
}

enum SessionFeeling { arduous, smooth, transcendent }

extension SessionFeelingWire on SessionFeeling {
  String get wire => name;
}

enum SequencePhaseRole { focus, work, rest, prepare }

extension SequencePhaseRoleWire on SequencePhaseRole {
  String get wire => name;
}

class HiitPair {
  const HiitPair({required this.workSec, required this.restSec});

  final int workSec;
  final int restSec;

  Map<String, Object> toJson() => {'workSec': workSec, 'restSec': restSec};
}

class SequencePhase {
  const SequencePhase({required this.role, required this.durationSec});

  final SequencePhaseRole role;
  final int durationSec;

  Map<String, Object> toJson() => {
    'role': role.wire,
    'durationSec': durationSec,
  };
}

class TimerTemplate {
  const TimerTemplate({
    required this.id,
    required this.label,
    required this.kind,
    required this.createdAt,
    this.builtin,
    this.focusSec,
    this.breakSec,
    this.rounds,
    this.longBreakSec,
    this.longBreakEvery,
    this.workSec,
    this.restSec,
    this.phases,
    this.sequence,
    this.skipFinalRest,
  });

  final String id;
  final String label;
  final TemplateKind kind;
  final bool? builtin;
  final int createdAt;
  final int? focusSec;
  final int? breakSec;
  final int? rounds;
  final int? longBreakSec;
  final int? longBreakEvery;
  final int? workSec;
  final int? restSec;
  final List<HiitPair>? phases;
  final List<SequencePhase>? sequence;
  final bool? skipFinalRest;

  Map<String, Object> toJson() => {
    'id': id,
    'label': label,
    'kind': kind.wire,
    'createdAt': createdAt,
    'builtin': ?builtin,
    'focusSec': ?focusSec,
    'breakSec': ?breakSec,
    'rounds': ?rounds,
    'longBreakSec': ?longBreakSec,
    'longBreakEvery': ?longBreakEvery,
    'workSec': ?workSec,
    'restSec': ?restSec,
    if (phases != null)
      'phases': phases!.map((phase) => phase.toJson()).toList(),
    if (sequence != null)
      'sequence': sequence!.map((phase) => phase.toJson()).toList(),
    'skipFinalRest': ?skipFinalRest,
  };

  TimerTemplate copyWith({
    String? id,
    String? label,
    TemplateKind? kind,
    bool? builtin,
    bool clearBuiltin = false,
    int? createdAt,
    int? focusSec,
    int? breakSec,
    int? rounds,
    int? longBreakSec,
    int? longBreakEvery,
    int? workSec,
    int? restSec,
    List<HiitPair>? phases,
    List<SequencePhase>? sequence,
    bool? skipFinalRest,
  }) => TimerTemplate(
    id: id ?? this.id,
    label: label ?? this.label,
    kind: kind ?? this.kind,
    builtin: clearBuiltin ? null : (builtin ?? this.builtin),
    createdAt: createdAt ?? this.createdAt,
    focusSec: focusSec ?? this.focusSec,
    breakSec: breakSec ?? this.breakSec,
    rounds: rounds ?? this.rounds,
    longBreakSec: longBreakSec ?? this.longBreakSec,
    longBreakEvery: longBreakEvery ?? this.longBreakEvery,
    workSec: workSec ?? this.workSec,
    restSec: restSec ?? this.restSec,
    phases: phases ?? this.phases,
    sequence: sequence ?? this.sequence,
    skipFinalRest: skipFinalRest ?? this.skipFinalRest,
  );
}

class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.templateId,
    required this.label,
    required this.kind,
    required this.startedAt,
    required this.endedAt,
    required this.plannedSec,
    required this.elapsedSec,
    required this.completed,
    required this.roundsDone,
    required this.roundsTotal,
    this.interruptions,
    this.feeling,
    this.linkedTodoId,
    this.focusedSec,
    this.qualityEvidence,
    this.qualityScore,
    this.awardedMilliExp,
    this.scoringVersion = 0,
  });

  final String id;
  final String templateId;
  final String label;
  final TemplateKind kind;
  final int startedAt;
  final int endedAt;
  final int plannedSec;
  final int elapsedSec;
  final bool completed;
  final int roundsDone;
  final int roundsTotal;
  final int? interruptions;
  final SessionFeeling? feeling;
  final String? linkedTodoId;
  final int? focusedSec;
  final FocusQualityEvidence? qualityEvidence;
  final int? qualityScore;
  final int? awardedMilliExp;
  final int scoringVersion;

  Map<String, Object> toJson() => {
    'id': id,
    'templateId': templateId,
    'label': label,
    'kind': kind.wire,
    'startedAt': startedAt,
    'endedAt': endedAt,
    'plannedSec': plannedSec,
    'elapsedSec': elapsedSec,
    'completed': completed,
    'roundsDone': roundsDone,
    'roundsTotal': roundsTotal,
    'interruptions': ?interruptions,
    'feeling': ?feeling?.wire,
    'linkedTodoId': ?linkedTodoId,
    'focusedSec': ?focusedSec,
    'qualityEvidence': ?qualityEvidence?.toJson(),
    'qualityScore': ?qualityScore,
    'awardedMilliExp': ?awardedMilliExp,
    'scoringVersion': scoringVersion,
  };

  SessionRecord copyWith({
    SessionFeeling? feeling,
    Object? linkedTodoId = _notProvided,
    int? focusedSec,
    Object? qualityEvidence = _notProvided,
    Object? qualityScore = _notProvided,
    Object? awardedMilliExp = _notProvided,
    int? scoringVersion,
  }) => SessionRecord(
    id: id,
    templateId: templateId,
    label: label,
    kind: kind,
    startedAt: startedAt,
    endedAt: endedAt,
    plannedSec: plannedSec,
    elapsedSec: elapsedSec,
    completed: completed,
    roundsDone: roundsDone,
    roundsTotal: roundsTotal,
    interruptions: interruptions,
    feeling: feeling ?? this.feeling,
    linkedTodoId: identical(linkedTodoId, _notProvided)
        ? this.linkedTodoId
        : linkedTodoId as String?,
    focusedSec: focusedSec ?? this.focusedSec,
    qualityEvidence: identical(qualityEvidence, _notProvided)
        ? this.qualityEvidence
        : qualityEvidence as FocusQualityEvidence?,
    qualityScore: identical(qualityScore, _notProvided)
        ? this.qualityScore
        : qualityScore as int?,
    awardedMilliExp: identical(awardedMilliExp, _notProvided)
        ? this.awardedMilliExp
        : awardedMilliExp as int?,
    scoringVersion: scoringVersion ?? this.scoringVersion,
  );
}

class AppSettings {
  const AppSettings({
    required this.volume,
    required this.soundOn,
    required this.hapticsOn,
    required this.keepAwake,
    required this.theme,
    this.version = 1,
  });

  final double volume;
  final bool soundOn;
  final bool hapticsOn;
  final bool keepAwake;
  final String theme;
  final int version;

  Map<String, Object> toJson() => {
    'volume': volume,
    'soundOn': soundOn,
    'hapticsOn': hapticsOn,
    'keepAwake': keepAwake,
    'theme': theme,
    'version': version,
  };

  AppSettings copyWith({
    double? volume,
    bool? soundOn,
    bool? hapticsOn,
    bool? keepAwake,
    String? theme,
  }) => AppSettings(
    volume: volume ?? this.volume,
    soundOn: soundOn ?? this.soundOn,
    hapticsOn: hapticsOn ?? this.hapticsOn,
    keepAwake: keepAwake ?? this.keepAwake,
    theme: theme ?? this.theme,
  );
}

const Object _notProvided = Object();

class TodoItem {
  const TodoItem({
    required this.id,
    required this.text,
    required this.progress,
    required this.pushes,
    required this.createdAt,
    this.tags,
    this.dueAt,
    this.completedAt,
    this.archivedAt,
    this.totalFocusSec = 0,
    this.sessionsLinked = 0,
  });

  final String id;
  final String text;
  final int progress;
  final List<String>? tags;
  final int? dueAt;
  final int pushes;
  final int createdAt;
  final int? completedAt;
  final int? archivedAt;
  final int totalFocusSec;
  final int sessionsLinked;

  Map<String, Object> toJson() => {
    'id': id,
    'text': text,
    'progress': progress,
    'tags': ?tags,
    'dueAt': ?dueAt,
    'pushes': pushes,
    'createdAt': createdAt,
    'completedAt': ?completedAt,
    'archivedAt': ?archivedAt,
    'totalFocusSec': totalFocusSec,
    'sessionsLinked': sessionsLinked,
  };

  TodoItem copyWith({
    String? text,
    int? progress,
    Object? tags = _notProvided,
    Object? dueAt = _notProvided,
    int? pushes,
    int? createdAt,
    Object? completedAt = _notProvided,
    Object? archivedAt = _notProvided,
    int? totalFocusSec,
    int? sessionsLinked,
  }) => TodoItem(
    id: id,
    text: text ?? this.text,
    progress: progress ?? this.progress,
    tags: identical(tags, _notProvided) ? this.tags : tags as List<String>?,
    dueAt: identical(dueAt, _notProvided) ? this.dueAt : dueAt as int?,
    pushes: pushes ?? this.pushes,
    createdAt: createdAt ?? this.createdAt,
    completedAt: identical(completedAt, _notProvided)
        ? this.completedAt
        : completedAt as int?,
    archivedAt: identical(archivedAt, _notProvided)
        ? this.archivedAt
        : archivedAt as int?,
    totalFocusSec: totalFocusSec ?? this.totalFocusSec,
    sessionsLinked: sessionsLinked ?? this.sessionsLinked,
  );
}
