const _kindMap = <String, String>{
  'tabata': 'interval',
  'hiit': 'interval',
  'steady': 'accumulate',
  'hold': 'accumulate',
};

const _builtinCountdownIds = <String>{
  'builtin.pomodoro',
  'builtin.deepwork',
  'builtin.tabata',
  'builtin.hiit',
};

const _accumulateStrip = <String>[
  'workSec',
  'restSec',
  'rounds',
  'phases',
  'sequence',
  'focusSec',
  'breakSec',
  'longBreakSec',
  'longBreakEvery',
  'skipFinalRest',
];

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map) return null;
  final output = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    output[entry.key as String] = entry.value;
  }
  return output;
}

int _numberOr(Object? value, int fallback) {
  if (value is num && value.isFinite) return value.round().clamp(0, 1 << 62);
  return fallback;
}

Object? migrateTemplate(Object? raw) {
  final source = _stringMap(raw);
  if (source == null) return raw;
  final template = Map<String, Object?>.of(source);
  final kind = template['kind'];
  if (kind is String && _kindMap.containsKey(kind)) {
    template['kind'] = _kindMap[kind];
  }
  if (template['builtin'] == true &&
      _builtinCountdownIds.contains(template['id']) &&
      template['sequence'] is List &&
      !template.containsKey('skipFinalRest')) {
    template['skipFinalRest'] = true;
  }
  template.remove('durationSec');
  if (template['kind'] == 'interval') {
    final phases = template['phases'];
    if (phases is List && phases.length == 1) {
      final pair = _stringMap(phases.single);
      if (pair != null) {
        template['workSec'] = pair['workSec'];
        template['restSec'] = pair['restSec'];
        template.remove('phases');
      }
    }
  }
  if (template['kind'] == 'accumulate') {
    for (final field in _accumulateStrip) {
      template.remove(field);
    }
  }
  template['createdAt'] = _numberOr(template['createdAt'], 0);
  return template;
}

Object? migrateSession(Object? raw) {
  final source = _stringMap(raw);
  if (source == null) return raw;
  final session = Map<String, Object?>.of(source);
  final kind = session['kind'];
  if (kind is String && _kindMap.containsKey(kind)) {
    session['kind'] = _kindMap[kind];
  }
  if (session['label'] is! String) session['label'] = '';
  if (session['completed'] is! bool) session['completed'] = false;
  session['plannedSec'] = _numberOr(session['plannedSec'], 0);
  session['elapsedSec'] = _numberOr(session['elapsedSec'], 0);
  session['roundsDone'] = _numberOr(session['roundsDone'], 0);
  session['roundsTotal'] = _numberOr(session['roundsTotal'], 0);
  if (session.containsKey('interruptions')) {
    session['interruptions'] = _numberOr(session['interruptions'], 0);
  }
  for (final field in ['focusedSec', 'qualityScore', 'awardedMilliExp']) {
    if (session.containsKey(field)) {
      session[field] = _numberOr(session[field], 0);
    }
  }
  session['scoringVersion'] = _numberOr(
    session['scoringVersion'],
    0,
  ).clamp(0, 1);
  return session;
}

Object? migrateTodo(Object? raw) {
  final source = _stringMap(raw);
  if (source == null) return raw;
  final todo = Map<String, Object?>.of(source);
  todo['progress'] = _numberOr(todo['progress'], 0).clamp(0, 100);
  todo['pushes'] = _numberOr(todo['pushes'], 0);
  todo['createdAt'] = _numberOr(todo['createdAt'], 0);
  if (todo.containsKey('tags')) {
    final tags = todo['tags'];
    if (tags is List) {
      todo['tags'] = tags.whereType<String>().toList();
    } else {
      todo.remove('tags');
    }
  }
  for (final field in ['dueAt', 'completedAt', 'archivedAt']) {
    final value = todo[field];
    if (todo.containsKey(field) && !(value is num && value.isFinite)) {
      todo.remove(field);
    }
  }
  return todo;
}
