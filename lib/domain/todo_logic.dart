import 'models.dart';

enum TodoScope { active, today, upcoming, completed, archived, all }

enum TodoSort { smart, due, newest, progress }

int _round(double value) => value.round();

int _clampPercent(double value) => _round(value).clamp(0, 100);

TodoItem applyPush(TodoItem todo, double amount, int now) {
  final delta = _round(amount).clamp(1, 100);
  final progress = (todo.progress + delta).clamp(0, 100);
  final completedNow = progress == 100 && todo.progress < 100;
  return todo.copyWith(
    progress: progress,
    pushes: todo.pushes + 1,
    completedAt: completedNow ? now : todo.completedAt,
  );
}

TodoItem setTodoProgress(TodoItem todo, double amount, int now) {
  final progress = _clampPercent(amount);
  return todo.copyWith(
    progress: progress,
    completedAt: progress == 100 ? (todo.completedAt ?? now) : null,
  );
}

List<TodoItem> sortTodos(Iterable<TodoItem> todos) {
  final doing = todos.where((todo) => todo.progress < 100).toList();
  final done = todos.where((todo) => todo.progress == 100).toList();
  doing.sort((a, b) {
    final aDue = a.dueAt;
    final bDue = b.dueAt;
    if (aDue != bDue) {
      if (aDue == null) return 1;
      if (bDue == null) return -1;
      return aDue.compareTo(bDue);
    }
    return b.createdAt.compareTo(a.createdAt);
  });
  done.sort((a, b) => (b.completedAt ?? 0).compareTo(a.completedAt ?? 0));
  return [...doing, ...done];
}

List<TodoItem> queryTodos(
  Iterable<TodoItem> todos, {
  TodoScope scope = TodoScope.active,
  TodoSort sort = TodoSort.smart,
  required int now,
  String query = '',
  String? tag,
}) {
  final instant = DateTime.fromMillisecondsSinceEpoch(now);
  final today = DateTime(instant.year, instant.month, instant.day);
  final tomorrow = today.add(const Duration(days: 1)).millisecondsSinceEpoch;
  final normalizedQuery = query.trim().toLowerCase();
  final normalizedTag = tag?.trim();

  final filtered = todos.where((todo) {
    final archived = todo.archivedAt != null;
    final matchesScope = switch (scope) {
      TodoScope.active => !archived && todo.progress < 100,
      TodoScope.today =>
        !archived &&
            todo.progress < 100 &&
            todo.dueAt != null &&
            todo.dueAt! < tomorrow,
      TodoScope.upcoming =>
        !archived &&
            todo.progress < 100 &&
            todo.dueAt != null &&
            todo.dueAt! >= tomorrow,
      TodoScope.completed => !archived && todo.progress == 100,
      TodoScope.archived => archived,
      TodoScope.all => !archived,
    };
    if (!matchesScope) return false;
    if (normalizedTag != null &&
        normalizedTag.isNotEmpty &&
        !(todo.tags?.contains(normalizedTag) ?? false)) {
      return false;
    }
    if (normalizedQuery.isEmpty) return true;
    final searchable = '${todo.text}\n${(todo.tags ?? const []).join(' ')}'
        .toLowerCase();
    return searchable.contains(normalizedQuery);
  }).toList();

  switch (sort) {
    case TodoSort.smart:
      return sortTodos(filtered);
    case TodoSort.due:
      filtered.sort((a, b) {
        final aDue = a.dueAt;
        final bDue = b.dueAt;
        if (aDue == null && bDue != null) return 1;
        if (aDue != null && bDue == null) return -1;
        final dueOrder = (aDue ?? 0).compareTo(bDue ?? 0);
        return dueOrder != 0 ? dueOrder : _smartCompare(a, b);
      });
      break;
    case TodoSort.newest:
      filtered.sort((a, b) {
        final created = b.createdAt.compareTo(a.createdAt);
        return created != 0 ? created : a.id.compareTo(b.id);
      });
      break;
    case TodoSort.progress:
      filtered.sort((a, b) {
        final progress = b.progress.compareTo(a.progress);
        return progress != 0 ? progress : _smartCompare(a, b);
      });
      break;
  }
  return filtered;
}

int _smartCompare(TodoItem a, TodoItem b) {
  final aDone = a.progress == 100;
  final bDone = b.progress == 100;
  if (aDone != bDone) return aDone ? 1 : -1;
  if (aDone) {
    final completed = (b.completedAt ?? 0).compareTo(a.completedAt ?? 0);
    return completed != 0 ? completed : a.id.compareTo(b.id);
  }
  final aDue = a.dueAt;
  final bDue = b.dueAt;
  if (aDue == null && bDue != null) return 1;
  if (aDue != null && bDue == null) return -1;
  final due = (aDue ?? 0).compareTo(bDue ?? 0);
  if (due != 0) return due;
  final created = b.createdAt.compareTo(a.createdAt);
  return created != 0 ? created : a.id.compareTo(b.id);
}

TodoItem archiveTodo(TodoItem todo, int now) =>
    todo.copyWith(archivedAt: todo.archivedAt ?? now);

TodoItem restoreTodo(TodoItem todo) => todo.copyWith(archivedAt: null);

List<String> sanitizeTags(Iterable<String> tags) => tags
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .take(8)
    .map((tag) => tag.length <= 20 ? tag : tag.substring(0, 20))
    .toList();
