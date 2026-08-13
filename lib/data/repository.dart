import 'dart:convert';

import '../domain/defaults.dart';
import '../domain/growth_models.dart';
import '../domain/migrate.dart';
import '../domain/models.dart';
import '../domain/schema.dart';
import 'key_value_store_base.dart';

abstract final class StorageKeys {
  static const templates = 'uptimer.templates.v1';
  static const sessions = 'uptimer.sessions.v1';
  static const settings = 'uptimer.settings.v1';
  static const todos = 'uptimer.todos.v1';
  static const selected = 'uptimer.selected.v1';
  static const active = 'uptimer.active.v1';
  static const growth = 'uptimer.growth.v1';
  static const seenGuide = 'uptimer.seenGuide';
}

class HydrationResult {
  const HydrationResult({
    required this.templates,
    required this.sessions,
    required this.settings,
    required this.todos,
    required this.growth,
    required this.selectedTemplateId,
    required this.activeRaw,
    required this.seenGuide,
    this.notice,
  });

  final List<TimerTemplate> templates;
  final List<SessionRecord> sessions;
  final AppSettings settings;
  final List<TodoItem> todos;
  final HiddenGrowth growth;
  final String selectedTemplateId;
  final String? activeRaw;
  final bool seenGuide;
  final String? notice;
}

class _Guarded<T> {
  const _Guarded(this.value, this.corrupted);

  final T value;
  final bool corrupted;
}

class Repository {
  Repository(this.store);

  final KeyValueStore store;

  Future<HydrationResult> hydrate({int? now}) async {
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    try {
      final values = await Future.wait([
        store.read(StorageKeys.templates),
        store.read(StorageKeys.sessions),
        store.read(StorageKeys.settings),
        store.read(StorageKeys.todos),
        store.read(StorageKeys.growth),
        store.read(StorageKeys.selected),
        store.read(StorageKeys.active),
        store.read(StorageKeys.seenGuide),
      ]);
      final templates = await _guard(
        StorageKeys.templates,
        values[0],
        _parseTemplates,
        () => List<TimerTemplate>.of(builtinTemplates),
        timestamp,
      );
      final sessions = await _guard(
        StorageKeys.sessions,
        values[1],
        _parseSessions,
        () => <SessionRecord>[],
        timestamp,
      );
      final settings = await _guard(
        StorageKeys.settings,
        values[2],
        (raw) => validateSettings(jsonDecode(raw)),
        () => defaultSettings,
        timestamp,
      );
      final todos = await _guard(
        StorageKeys.todos,
        values[3],
        _parseTodos,
        () => <TodoItem>[],
        timestamp,
      );
      final growth = await _guard(
        StorageKeys.growth,
        values[4],
        (raw) => validateHiddenGrowth(jsonDecode(raw)),
        () => defaultHiddenGrowth,
        timestamp,
      );
      final corrupted =
          templates.corrupted ||
          sessions.corrupted ||
          settings.corrupted ||
          todos.corrupted ||
          growth.corrupted;
      final selectedRaw = values[5];
      final selected =
          selectedRaw != null &&
              templates.value.any((template) => template.id == selectedRaw)
          ? selectedRaw
          : (templates.value.isEmpty ? '' : templates.value.first.id);
      if (selected != selectedRaw) {
        await store.write(StorageKeys.selected, selected);
      }
      return HydrationResult(
        templates: templates.value,
        sessions: sessions.value,
        settings: settings.value,
        todos: todos.value,
        growth: growth.value,
        selectedTemplateId: selected,
        activeRaw: values[6],
        seenGuide: values[7] == '1',
        notice: corrupted ? '纸 笺 有 损 · 已 回 退 并 备 份 原 件' : null,
      );
    } on Object {
      return HydrationResult(
        templates: List<TimerTemplate>.of(builtinTemplates),
        sessions: const [],
        settings: defaultSettings,
        todos: const [],
        growth: defaultHiddenGrowth,
        selectedTemplateId: builtinTemplates.first.id,
        activeRaw: null,
        seenGuide: false,
        notice: '纸 笺 暂 不 可 读 · 本 次 未 覆 盖 原 件',
      );
    }
  }

  Future<_Guarded<T>> _guard<T>(
    String key,
    String? raw,
    T Function(String raw) parse,
    T Function() fallback,
    int now,
  ) async {
    if (raw == null) return _Guarded(fallback(), false);
    try {
      return _Guarded(parse(raw), false);
    } on Object {
      final safe = fallback();
      await store.write('$key.backup-$now', raw);
      await store.write(key, jsonEncode(_jsonValue(safe)));
      return _Guarded(safe, true);
    }
  }

  Object? _jsonValue(Object? value) {
    if (value is TimerTemplate) return value.toJson();
    if (value is SessionRecord) return value.toJson();
    if (value is TodoItem) return value.toJson();
    if (value is AppSettings) return value.toJson();
    if (value is HiddenGrowth) return value.toJson();
    if (value is Iterable) return value.map(_jsonValue).toList();
    return value;
  }

  List<TimerTemplate> _parseTemplates(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('templates not array');
    return decoded
        .map((item) => validateTemplate(migrateTemplate(item)))
        .toList();
  }

  List<SessionRecord> _parseSessions(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('sessions not array');
    return decoded
        .map((item) => validateSession(migrateSession(item)))
        .toList();
  }

  List<TodoItem> _parseTodos(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('todos not array');
    return decoded.map((item) => validateTodo(migrateTodo(item))).toList();
  }

  Future<void> saveTemplates(List<TimerTemplate> templates) => store.write(
    StorageKeys.templates,
    jsonEncode(templates.map((template) => template.toJson()).toList()),
  );

  Future<void> saveSessions(List<SessionRecord> sessions) => store.write(
    StorageKeys.sessions,
    jsonEncode(sessions.map((session) => session.toJson()).toList()),
  );

  Future<void> saveSettings(AppSettings settings) =>
      store.write(StorageKeys.settings, jsonEncode(settings.toJson()));

  Future<void> saveGrowth(HiddenGrowth growth) =>
      store.write(StorageKeys.growth, jsonEncode(growth.toJson()));

  Future<void> saveTodos(List<TodoItem> todos) => store.write(
    StorageKeys.todos,
    jsonEncode(todos.map((todo) => todo.toJson()).toList()),
  );

  Future<void> saveSelectedTemplateId(String id) =>
      store.write(StorageKeys.selected, id);

  Future<void> saveActive(String raw) => store.write(StorageKeys.active, raw);

  Future<void> clearActive() => store.remove(StorageKeys.active);

  Future<void> markGuideSeen() => store.write(StorageKeys.seenGuide, '1');

  Future<void> flush() => store.flush();
}
