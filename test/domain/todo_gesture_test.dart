import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/domain/gestures.dart';
import 'package:uptimer/domain/models.dart';
import 'package:uptimer/domain/todo_logic.dart';

TodoItem todo({
  required String id,
  int progress = 0,
  int pushes = 0,
  int createdAt = 0,
  List<String>? tags,
  int? dueAt,
  int? completedAt,
  int? archivedAt,
}) => TodoItem(
  id: id,
  text: id,
  progress: progress,
  pushes: pushes,
  createdAt: createdAt,
  tags: tags,
  dueAt: dueAt,
  completedAt: completedAt,
  archivedAt: archivedAt,
);

void main() {
  group('清单推进', () {
    test('累加进度、计 pushes 并在首次达百时记完成时间', () {
      final first = applyPush(todo(id: 'a', progress: 80, pushes: 2), 25, 99);
      expect(first.progress, 100);
      expect(first.pushes, 3);
      expect(first.completedAt, 99);

      final again = applyPush(first, 10, 200);
      expect(again.progress, 100);
      expect(again.pushes, 4);
      expect(again.completedAt, 99);
    });

    test('增量四舍五入并钳在 1..100', () {
      expect(applyPush(todo(id: 'a'), -9, 0).progress, 1);
      expect(applyPush(todo(id: 'a'), 2.6, 0).progress, 3);
      expect(applyPush(todo(id: 'a'), 1000, 0).progress, 100);
    });

    test('手动进度钳在 0..100，不计 pushes，并能清完成时间', () {
      final done = setTodoProgress(todo(id: 'a', pushes: 4), 101, 30);
      expect(done.progress, 100);
      expect(done.completedAt, 30);
      expect(done.pushes, 4);

      final reopened = setTodoProgress(done, 49.6, 40);
      expect(reopened.progress, 50);
      expect(reopened.completedAt, isNull);
      expect(reopened.pushes, 4);
    });
  });

  group('清单排序与标签', () {
    test('未完成按期限和创建时间，完成项沉底', () {
      final items = [
        todo(id: 'done-old', progress: 100, completedAt: 10),
        todo(id: 'none-old', createdAt: 10),
        todo(id: 'due-late', createdAt: 30, dueAt: 200),
        todo(id: 'due-soon', createdAt: 20, dueAt: 100),
        todo(id: 'none-new', createdAt: 40),
        todo(id: 'done-new', progress: 100, completedAt: 20),
      ];
      expect(sortTodos(items).map((item) => item.id), [
        'due-soon',
        'due-late',
        'none-new',
        'none-old',
        'done-new',
        'done-old',
      ]);
      expect(items.first.id, 'done-old', reason: '不得修改输入列表');
    });

    test('标签去空、保序、截八项与二十字', () {
      final tags = sanitizeTags([
        ' 甲 ',
        '',
        '1234567890123456789012345',
        '三',
        '四',
        '五',
        '六',
        '七',
        '八',
        '九',
      ]);
      expect(tags, hasLength(8));
      expect(tags.first, '甲');
      expect(tags[1], '12345678901234567890');
    });
  });

  group('事项中心查询与归档', () {
    final today = DateTime(2026, 8, 7, 12).millisecondsSinceEpoch;
    final yesterday = DateTime(2026, 8, 6).millisecondsSinceEpoch;
    final todayDue = DateTime(2026, 8, 7, 18).millisecondsSinceEpoch;
    final tomorrow = DateTime(2026, 8, 8).millisecondsSinceEpoch;

    late List<TodoItem> items;

    setUp(() {
      items = [
        todo(id: '逾期方案', dueAt: yesterday, tags: ['工作']),
        todo(id: '今日复盘', dueAt: todayDue, tags: ['工作']),
        todo(id: '明日训练', dueAt: tomorrow, progress: 20, tags: ['健康']),
        todo(id: '随手记录', progress: 80),
        todo(id: '完成事项', progress: 100, completedAt: today - 100),
        todo(id: '封存事项', archivedAt: today - 200),
      ];
    });

    test('状态视图区分进行、今日、将来、完成与归档', () {
      expect(
        queryTodos(
          items,
          scope: TodoScope.active,
          now: today,
        ).map((item) => item.id),
        ['逾期方案', '今日复盘', '明日训练', '随手记录'],
      );
      expect(
        queryTodos(
          items,
          scope: TodoScope.today,
          now: today,
        ).map((item) => item.id),
        ['逾期方案', '今日复盘'],
      );
      expect(
        queryTodos(
          items,
          scope: TodoScope.upcoming,
          now: today,
        ).map((item) => item.id),
        ['明日训练'],
      );
      expect(
        queryTodos(items, scope: TodoScope.completed, now: today).single.id,
        '完成事项',
      );
      expect(
        queryTodos(items, scope: TodoScope.archived, now: today).single.id,
        '封存事项',
      );
    });

    test('关键词匹配正文或标签，并支持标签与进度排序', () {
      expect(
        queryTodos(
          items,
          scope: TodoScope.all,
          now: today,
          query: '工作',
        ).map((item) => item.id),
        ['逾期方案', '今日复盘'],
      );
      expect(
        queryTodos(
          items,
          scope: TodoScope.active,
          now: today,
          tag: '健康',
        ).single.id,
        '明日训练',
      );
      expect(
        queryTodos(
          items,
          scope: TodoScope.active,
          sort: TodoSort.progress,
          now: today,
        ).map((item) => item.progress),
        [80, 20, 0, 0],
      );
    });

    test('归档与恢复只改变归档时间', () {
      final source = todo(id: '一事', progress: 40, tags: ['甲']);
      final archived = archiveTodo(source, 99);
      expect(archived.archivedAt, 99);
      expect(archived.progress, 40);
      expect(archived.tags, ['甲']);
      expect(restoreTodo(archived).archivedAt, isNull);
    });
  });

  group('手势纯逻辑', () {
    test('窗口与半径内相邻两点成双，确认后重置', () {
      final guard = DoubleTapGuard();
      expect(guard.tap(10, 10, 100), isFalse);
      expect(guard.tap(20, 20, 300), isTrue);
      expect(guard.tap(21, 21, 320), isFalse);
    });

    test('超窗或半径外会重新起对', () {
      final guard = DoubleTapGuard();
      expect(guard.tap(0, 0, 0), isFalse);
      expect(guard.tap(0, 0, 351), isFalse);
      expect(guard.tap(100, 100, 500), isFalse);
      expect(guard.tap(101, 101, 700), isTrue);
    });

    test('轴向锁定、阻尼与长按进度', () {
      expect(lockAxis(12, 12), isNull);
      expect(lockAxis(30, 20), DragAxis.x);
      expect(lockAxis(20, 30), DragAxis.y);
      expect(dampen(100), 40);
      expect(dampen(1000), 56);
      expect(dampen(-1000), -56);
      expect(longPressProgress(1000, 2250), 0.5);
      expect(longPressProgress(1000, 5000), 1);
    });
  });
}
