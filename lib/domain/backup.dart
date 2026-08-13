import 'dart:convert';

import 'focus_quality.dart';
import 'growth_models.dart';
import 'migrate.dart';
import 'models.dart';
import 'schema.dart';

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => 'BackupException: $message';
}

class ParsedBackup {
  const ParsedBackup({
    required this.exportedAt,
    required this.templates,
    required this.sessions,
    required this.settings,
    required this.todos,
    required this.skippedTemplates,
    required this.skippedSessions,
    required this.skippedTodos,
    this.growth,
  });

  final int exportedAt;
  final List<TimerTemplate> templates;
  final List<SessionRecord> sessions;
  final AppSettings settings;
  final List<TodoItem> todos;
  final int skippedTemplates;
  final int skippedSessions;
  final int skippedTodos;
  final HiddenGrowth? growth;

  int get skippedTotal => skippedTemplates + skippedSessions + skippedTodos;
}

class MergeResult<T> {
  const MergeResult({
    required this.items,
    required this.added,
    required this.updated,
  });

  final List<T> items;
  final int added;
  final int updated;
}

MergeResult<T> mergeById<T>(
  Iterable<T> existing,
  Iterable<T> incoming,
  String Function(T item) idOf, {
  T Function(T existing, T incoming)? mergeConflict,
}) {
  final map = <String, T>{};
  final order = <String>[];
  for (final item in existing) {
    final id = idOf(item);
    if (!map.containsKey(id)) order.add(id);
    map[id] = item;
  }
  var added = 0;
  var updated = 0;
  final incomingSeen = <String>{};
  for (final item in incoming) {
    final id = idOf(item);
    if (incomingSeen.add(id)) {
      if (map.containsKey(id)) {
        updated += 1;
      } else {
        added += 1;
        order.add(id);
      }
    }
    final current = map[id];
    map[id] = current != null && mergeConflict != null
        ? mergeConflict(current, item)
        : item;
  }
  return MergeResult(
    items: order.map((id) => map[id]!).toList(),
    added: added,
    updated: updated,
  );
}

/// Session conflicts keep the imported record's ordinary metadata, but a
/// legacy or partial duplicate can never erase locally frozen scoring facts.
SessionRecord mergeSessionConflict(
  SessionRecord local,
  SessionRecord incoming,
) {
  final localAwardFrozen = local.awardedMilliExp != null;
  final incomingAwardFrozen = _hasImportableFrozenAward(incoming);
  if (!localAwardFrozen || incomingAwardFrozen) return incoming;
  return SessionRecord(
    id: incoming.id,
    templateId: incoming.templateId,
    label: incoming.label,
    kind: incoming.kind,
    startedAt: incoming.startedAt,
    endedAt: incoming.endedAt,
    plannedSec: incoming.plannedSec,
    elapsedSec: incoming.elapsedSec,
    completed: incoming.completed,
    roundsDone: incoming.roundsDone,
    roundsTotal: incoming.roundsTotal,
    interruptions: incoming.interruptions ?? local.interruptions,
    feeling: incoming.feeling ?? local.feeling,
    linkedTodoId: incoming.linkedTodoId ?? local.linkedTodoId,
    focusedSec: local.focusedSec,
    qualityEvidence: local.qualityEvidence,
    qualityScore: local.qualityScore,
    awardedMilliExp: local.awardedMilliExp,
    scoringVersion: local.scoringVersion,
  );
}

bool _hasImportableFrozenAward(SessionRecord session) {
  if (session.awardedMilliExp == null) return false;
  if (session.scoringVersion == 0) return true;
  final evidence = session.qualityEvidence;
  final score = session.qualityScore;
  return session.scoringVersion == 1 &&
      session.focusedSec != null &&
      evidence != null &&
      score != null &&
      focusQualityScore(evidence) == score;
}

String buildBackup(
  List<TimerTemplate> templates,
  List<SessionRecord> sessions,
  AppSettings settings,
  List<TodoItem> todos, {
  HiddenGrowth? growth,
  int? now,
}) => const JsonEncoder.withIndent('  ').convert({
  'app': 'uptimer',
  'version': 2,
  'exportedAt': now ?? DateTime.now().millisecondsSinceEpoch,
  'templates': templates.map((template) => template.toJson()).toList(),
  'sessions': sessions.map((session) => session.toJson()).toList(),
  'settings': settings.toJson(),
  'todos': todos.map((todo) => todo.toJson()).toList(),
  if (growth != null) 'growth': growth.toJson(),
});

ParsedBackup parseBackup(String json) {
  Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException {
    throw const BackupException('文件不是合法 JSON');
  }
  if (decoded is! Map) throw const BackupException('文件结构非法');
  final object = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is String) object[entry.key as String] = entry.value;
  }
  if (object['app'] != 'uptimer') {
    throw const BackupException('不是成时备份文件');
  }
  if (object['version'] != 1 && object['version'] != 2) {
    throw BackupException('不支持的备份版本: ${object['version']}');
  }
  final rawTemplates = object['templates'];
  final rawSessions = object['sessions'];
  final rawTodos = object['todos'];
  if (rawTemplates is! List) {
    throw const BackupException('数据校验失败: templates 缺失');
  }
  if (rawSessions is! List) {
    throw const BackupException('数据校验失败: sessions 缺失');
  }
  if (rawTodos != null && rawTodos is! List) {
    throw const BackupException('数据校验失败: todos 缺失');
  }

  final templates = <TimerTemplate>[];
  var skippedTemplates = 0;
  for (final raw in rawTemplates) {
    try {
      templates.add(validateTemplate(migrateTemplate(raw)));
    } on Object {
      skippedTemplates += 1;
    }
  }
  final sessions = <SessionRecord>[];
  var skippedSessions = 0;
  for (final raw in rawSessions) {
    try {
      sessions.add(validateSession(migrateSession(raw)));
    } on Object {
      skippedSessions += 1;
    }
  }
  final todos = <TodoItem>[];
  var skippedTodos = 0;
  for (final raw in rawTodos is List ? rawTodos : const []) {
    try {
      todos.add(validateTodo(migrateTodo(raw)));
    } on Object {
      skippedTodos += 1;
    }
  }

  final dedupedTemplates = mergeById(
    const <TimerTemplate>[],
    templates,
    (template) => template.id,
  );
  final dedupedSessions = mergeById(
    const <SessionRecord>[],
    sessions,
    (session) => session.id,
  );
  final dedupedTodos = mergeById(const <TodoItem>[], todos, (todo) => todo.id);
  skippedTemplates += templates.length - dedupedTemplates.items.length;
  skippedSessions += sessions.length - dedupedSessions.items.length;
  skippedTodos += todos.length - dedupedTodos.items.length;

  HiddenGrowth? growth;
  if (object['growth'] != null) {
    try {
      growth = validateHiddenGrowth(object['growth']);
    } on Object {
      growth = null;
    }
  }
  final exportedAt = object['exportedAt'];
  return ParsedBackup(
    exportedAt: exportedAt is num && exportedAt.isFinite
        ? exportedAt.round()
        : 0,
    templates: dedupedTemplates.items,
    sessions: dedupedSessions.items,
    settings: normalizeSettings(object['settings']),
    todos: dedupedTodos.items,
    skippedTemplates: skippedTemplates,
    skippedSessions: skippedSessions,
    skippedTodos: skippedTodos,
    growth: growth,
  );
}
