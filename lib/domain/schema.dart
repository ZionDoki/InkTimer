import 'defaults.dart';
import 'focus_quality.dart';
import 'growth_models.dart';
import 'models.dart';

const maxDateTimeMilliseconds = 8640000000000000;

class SchemaException implements Exception {
  const SchemaException(this.message);

  final String message;

  @override
  String toString() => 'SchemaException: $message';
}

Never _fail(String field, [Object? value]) => throw SchemaException(
  value == null
      ? 'invalid field: $field'
      : 'invalid field: $field (got $value)',
);

Map<String, Object?> _object(Object? value, String field) {
  if (value is! Map) _fail(field, value);
  final output = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) _fail(field, value);
    output[entry.key as String] = entry.value;
  }
  return output;
}

String _string(
  Object? value,
  String field, {
  bool nonempty = false,
  int? maxLength,
}) {
  if (value is! String ||
      (nonempty && value.trim().isEmpty) ||
      (maxLength != null && value.length > maxLength)) {
    _fail(field, value);
  }
  return value;
}

num _number(
  Object? value,
  String field, {
  num min = 0,
  num max = double.infinity,
  bool integer = false,
}) {
  if (value is! num ||
      !value.isFinite ||
      value < min ||
      value > max ||
      (integer && value != value.roundToDouble())) {
    _fail(field, value);
  }
  return value;
}

int _integer(Object? value, String field, {int min = 0, int max = 1 << 62}) =>
    _number(value, field, min: min, max: max, integer: true).toInt();

int _duration(Object? value, String field, {int min = 0, int max = 86400}) =>
    _number(value, field, min: min, max: max).round();

bool _boolean(Object? value, String field) {
  if (value is! bool) _fail(field, value);
  return value;
}

int? _optionalDuration(
  Map<String, Object?> object,
  String field, {
  int min = 0,
  int max = 86400,
  bool integer = false,
}) {
  if (!object.containsKey(field)) return null;
  return integer
      ? _integer(object[field], field, min: min, max: max)
      : _duration(object[field], field, min: min, max: max);
}

TemplateKind _templateKind(Object? value) => switch (value) {
  'pomodoro' => TemplateKind.pomodoro,
  'interval' => TemplateKind.interval,
  'accumulate' => TemplateKind.accumulate,
  _ => _fail('kind', value),
};

SequencePhaseRole _sequenceRole(Object? value) => switch (value) {
  'focus' => SequencePhaseRole.focus,
  'work' => SequencePhaseRole.work,
  'rest' => SequencePhaseRole.rest,
  'prepare' => SequencePhaseRole.prepare,
  _ => _fail('sequence.role', value),
};

SessionFeeling? _sessionFeeling(Object? value) => switch (value) {
  null => null,
  'arduous' => SessionFeeling.arduous,
  'smooth' => SessionFeeling.smooth,
  'transcendent' => SessionFeeling.transcendent,
  _ => _fail('feeling', value),
};

TimerTemplate validateTemplate(Object? value) {
  final object = _object(value, 'template');
  final kind = _templateKind(object['kind']);
  List<HiitPair>? phases;
  if (object.containsKey('phases')) {
    final raw = object['phases'];
    if (raw is! List || raw.isEmpty || raw.length > 8) _fail('phases', raw);
    phases = raw.map((item) {
      final pair = _object(item, 'phases');
      return HiitPair(
        workSec: _duration(pair['workSec'], 'phases.workSec', min: 1),
        restSec: _duration(pair['restSec'], 'phases.restSec'),
      );
    }).toList();
  }
  List<SequencePhase>? sequence;
  if (object.containsKey('sequence')) {
    final raw = object['sequence'];
    if (raw is! List || raw.isEmpty || raw.length > 32) {
      _fail('sequence', raw);
    }
    sequence = raw.map((item) {
      final phase = _object(item, 'sequence');
      return SequencePhase(
        role: _sequenceRole(phase['role']),
        durationSec: _integer(
          phase['durationSec'],
          'sequence.durationSec',
          min: 1,
          max: 86400,
        ),
      );
    }).toList();
  }

  final template = TimerTemplate(
    id: _string(object['id'], 'id', nonempty: true),
    label: _string(object['label'], 'label', nonempty: true, maxLength: 20),
    kind: kind,
    builtin: object.containsKey('builtin')
        ? _boolean(object['builtin'], 'builtin')
        : null,
    createdAt: _duration(
      object['createdAt'],
      'createdAt',
      max: maxDateTimeMilliseconds,
    ),
    focusSec: _optionalDuration(object, 'focusSec', min: 1),
    breakSec: _optionalDuration(object, 'breakSec'),
    rounds: _optionalDuration(object, 'rounds', min: 1, max: 20, integer: true),
    longBreakSec: _optionalDuration(object, 'longBreakSec'),
    longBreakEvery: _optionalDuration(
      object,
      'longBreakEvery',
      min: 1,
      max: 20,
      integer: true,
    ),
    workSec: _optionalDuration(object, 'workSec', min: 1),
    restSec: _optionalDuration(object, 'restSec'),
    phases: phases,
    sequence: sequence,
    skipFinalRest: object.containsKey('skipFinalRest')
        ? _boolean(object['skipFinalRest'], 'skipFinalRest')
        : null,
  );
  if (kind == TemplateKind.accumulate && sequence != null) {
    _fail('sequence', object['sequence']);
  }
  if (kind == TemplateKind.accumulate && template.skipFinalRest != null) {
    _fail('skipFinalRest', object['skipFinalRest']);
  }
  if (kind == TemplateKind.pomodoro &&
      sequence == null &&
      template.focusSec == null) {
    _fail('focusSec', object['focusSec']);
  }
  if (kind == TemplateKind.interval &&
      sequence == null &&
      template.workSec == null &&
      phases == null) {
    _fail('workSec', object['workSec']);
  }
  return template;
}

FocusQualityEvidence _focusQualityEvidence(Object? value) {
  final object = _object(value, 'qualityEvidence');
  final version = _integer(
    object['version'],
    'qualityEvidence.version',
    min: 1,
    max: 1,
  );
  return FocusQualityEvidence(
    version: version,
    manualPauseCount: _integer(
      object['manualPauseCount'],
      'qualityEvidence.manualPauseCount',
      max: 1 << 31,
    ),
    canceledHoldCount: _integer(
      object['canceledHoldCount'],
      'qualityEvidence.canceledHoldCount',
      max: 1 << 31,
    ),
    inAppDiversionCount: _integer(
      object['inAppDiversionCount'],
      'qualityEvidence.inAppDiversionCount',
      max: 1 << 31,
    ),
    backgroundExcursionCount: _integer(
      object['backgroundExcursionCount'],
      'qualityEvidence.backgroundExcursionCount',
      max: 1 << 31,
    ),
    backgroundFocusSec: _integer(
      object['backgroundFocusSec'],
      'qualityEvidence.backgroundFocusSec',
    ),
  );
}

SessionRecord validateSession(Object? value) {
  final object = _object(value, 'session');
  final startedAt = _duration(
    object['startedAt'],
    'startedAt',
    max: maxDateTimeMilliseconds,
  );
  final endedAt = _duration(
    object['endedAt'],
    'endedAt',
    max: maxDateTimeMilliseconds,
  );
  final roundsDone = _integer(object['roundsDone'], 'roundsDone');
  final roundsTotal = _integer(object['roundsTotal'], 'roundsTotal');
  final focusedSec = object.containsKey('focusedSec')
      ? _integer(object['focusedSec'], 'focusedSec')
      : null;
  final qualityEvidence = object.containsKey('qualityEvidence')
      ? _focusQualityEvidence(object['qualityEvidence'])
      : null;
  final qualityScore = object.containsKey('qualityScore')
      ? _integer(object['qualityScore'], 'qualityScore', min: 40, max: 100)
      : null;
  final awardedMilliExp = object.containsKey('awardedMilliExp')
      ? _integer(object['awardedMilliExp'], 'awardedMilliExp')
      : null;
  final scoringVersion = object.containsKey('scoringVersion')
      ? _integer(object['scoringVersion'], 'scoringVersion', min: 0, max: 1)
      : 0;
  if (endedAt < startedAt) _fail('endedAt', endedAt);
  if (roundsDone > roundsTotal) _fail('roundsDone', roundsDone);
  if (scoringVersion == 1 &&
      (focusedSec == null ||
          qualityEvidence == null ||
          qualityScore == null ||
          awardedMilliExp == null ||
          focusQualityScore(qualityEvidence) != qualityScore)) {
    _fail('scoringVersion', scoringVersion);
  }
  return SessionRecord(
    id: _string(object['id'], 'id', nonempty: true),
    templateId: _string(object['templateId'], 'templateId', nonempty: true),
    label: _string(object['label'], 'label'),
    kind: _templateKind(object['kind']),
    startedAt: startedAt,
    endedAt: endedAt,
    plannedSec: _duration(object['plannedSec'], 'plannedSec', max: 1 << 62),
    elapsedSec: _duration(object['elapsedSec'], 'elapsedSec', max: 1 << 62),
    completed: _boolean(object['completed'], 'completed'),
    roundsDone: roundsDone,
    roundsTotal: roundsTotal,
    interruptions: object.containsKey('interruptions')
        ? _integer(object['interruptions'], 'interruptions')
        : null,
    feeling: _sessionFeeling(object['feeling']),
    linkedTodoId: object.containsKey('linkedTodoId')
        ? _string(object['linkedTodoId'], 'linkedTodoId', nonempty: true)
        : null,
    focusedSec: focusedSec,
    qualityEvidence: qualityEvidence,
    qualityScore: qualityScore,
    awardedMilliExp: awardedMilliExp,
    scoringVersion: scoringVersion,
  );
}

AppSettings validateSettings(Object? value) {
  final object = _object(value, 'settings');
  final volume = _number(object['volume'], 'volume', max: 1).toDouble();
  final theme = object['theme'];
  if (theme != 'paper' && theme != 'ink') _fail('theme', theme);
  if (object['version'] != 1) _fail('version', object['version']);
  return AppSettings(
    volume: volume,
    soundOn: _boolean(object['soundOn'], 'soundOn'),
    hapticsOn: _boolean(object['hapticsOn'], 'hapticsOn'),
    keepAwake: _boolean(object['keepAwake'], 'keepAwake'),
    theme: theme as String,
  );
}

AppSettings normalizeSettings(Object? value) {
  final object = value is Map ? value : const <Object?, Object?>{};
  final volume = object['volume'];
  final theme = object['theme'];
  return AppSettings(
    volume: volume is num && volume.isFinite && volume >= 0 && volume <= 1
        ? volume.toDouble()
        : defaultSettings.volume,
    soundOn: object['soundOn'] is bool
        ? object['soundOn']! as bool
        : defaultSettings.soundOn,
    hapticsOn: object['hapticsOn'] is bool
        ? object['hapticsOn']! as bool
        : defaultSettings.hapticsOn,
    keepAwake: object['keepAwake'] is bool
        ? object['keepAwake']! as bool
        : defaultSettings.keepAwake,
    theme: theme == 'paper' || theme == 'ink'
        ? theme! as String
        : defaultSettings.theme,
  );
}

TodoItem validateTodo(Object? value) {
  final object = _object(value, 'todo');
  List<String>? tags;
  if (object.containsKey('tags')) {
    final raw = object['tags'];
    if (raw is! List || raw.length > 8) _fail('tags', raw);
    tags = raw
        .map((tag) => _string(tag, 'tags', nonempty: true, maxLength: 20))
        .toList();
  }
  return TodoItem(
    id: _string(object['id'], 'id', nonempty: true),
    text: _string(object['text'], 'text', nonempty: true, maxLength: 500),
    progress: _integer(object['progress'], 'progress', max: 100),
    tags: tags,
    dueAt: object.containsKey('dueAt')
        ? _duration(object['dueAt'], 'dueAt', max: maxDateTimeMilliseconds)
        : null,
    pushes: _integer(object['pushes'], 'pushes'),
    createdAt: _duration(
      object['createdAt'],
      'createdAt',
      max: maxDateTimeMilliseconds,
    ),
    completedAt: object.containsKey('completedAt')
        ? _duration(
            object['completedAt'],
            'completedAt',
            max: maxDateTimeMilliseconds,
          )
        : null,
    archivedAt: object.containsKey('archivedAt')
        ? _duration(
            object['archivedAt'],
            'archivedAt',
            max: maxDateTimeMilliseconds,
          )
        : null,
    totalFocusSec: object.containsKey('totalFocusSec')
        ? _integer(object['totalFocusSec'], 'totalFocusSec')
        : 0,
    sessionsLinked: object.containsKey('sessionsLinked')
        ? _integer(object['sessionsLinked'], 'sessionsLinked')
        : 0,
  );
}

HiddenGrowth validateHiddenGrowth(Object? value) {
  final object = _object(value, 'growth');
  final rawInsights = object['insights'];
  if (rawInsights is! List || rawInsights.any((item) => item is! String)) {
    _fail('growth.insights', rawInsights);
  }
  final timestamps = <String, int>{};
  if (object.containsKey('insightUnlockedAt')) {
    final raw = _object(
      object['insightUnlockedAt'],
      'growth.insightUnlockedAt',
    );
    for (final entry in raw.entries) {
      if (!rawInsights.contains(entry.key)) continue;
      timestamps[entry.key] = _integer(
        entry.value,
        'growth.insightUnlockedAt.${entry.key}',
        max: maxDateTimeMilliseconds,
      );
    }
  }
  return HiddenGrowth(
    level: _integer(object['level'], 'growth.level', min: 1, max: 99),
    totalExp: _integer(object['totalExp'], 'growth.totalExp'),
    insights: rawInsights.cast<String>(),
    insightUnlockedAt: timestamps,
    version: object['version'] == null
        ? 1
        : _integer(object['version'], 'growth.version', min: 1, max: 2),
  );
}
