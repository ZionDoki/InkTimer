import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/growth.dart';
import '../../domain/models.dart';
import '../../domain/sounds.dart';
import '../../domain/stats.dart';
import '../../domain/timer_engine.dart';
import '../../domain/todo_logic.dart';
import '../../state/app_controller.dart';
import '../theme/zen_theme.dart';
import '../widgets/global_nav.dart';
import '../widgets/zen_page.dart';

class TodosPage extends StatefulWidget {
  const TodosPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TodosPage> createState() => _TodosPageState();
}

class _TodosPageState extends State<TodosPage> {
  final _newText = TextEditingController();
  final _newTags = TextEditingController();
  final _search = TextEditingController();
  bool _showComposerDetails = false;
  DateTime? _newDue;
  TodoScope _scope = TodoScope.active;
  TodoSort _sort = TodoSort.smart;
  String? _activeTag;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    _search.addListener(_changed);
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    _search.removeListener(_changed);
    _newText.dispose();
    _newTags.dispose();
    _search.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final availableTags = controller.todos
        .where((todo) => todo.archivedAt == null)
        .expand((todo) => todo.tags ?? const <String>[])
        .toSet();
    if (_activeTag != null && !availableTags.contains(_activeTag)) {
      _activeTag = null;
    }
    setState(() {});
  }

  List<String> _parseTags(String value) => value
      .split(RegExp('[,，]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<void> _submit() async {
    if (_newText.text.trim().isEmpty) return;
    await controller.addTodo(
      text: _newText.text,
      tags: _parseTags(_newTags.text),
      dueAt: _newDue?.millisecondsSinceEpoch,
    );
    await controller.playCue(SoundName.plip);
    _newText.clear();
    _newTags.clear();
    setState(() {
      _newDue = null;
      _showComposerDetails = false;
      _scope = TodoScope.active;
    });
  }

  Future<void> _pickDue() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _newDue ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '截 止 日',
    );
    if (selected != null) setState(() => _newDue = selected);
  }

  Future<void> _edit(TodoItem todo) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _TodoEditorSheet(controller: controller, todo: todo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final now = DateTime.now().millisecondsSinceEpoch;
    final todos = controller.todos;
    final active = queryTodos(todos, scope: TodoScope.active, now: now);
    final today = queryTodos(todos, scope: TodoScope.today, now: now);
    final upcoming = queryTodos(todos, scope: TodoScope.upcoming, now: now);
    final completed = queryTodos(todos, scope: TodoScope.completed, now: now);
    final archived = queryTodos(todos, scope: TodoScope.archived, now: now);
    final tags =
        todos
            .where((todo) => todo.archivedAt == null)
            .expand((todo) => todo.tags ?? const <String>[])
            .toSet()
            .toList()
          ..sort();
    final activeTag = tags.contains(_activeTag) ? _activeTag : null;
    final shown = queryTodos(
      todos,
      scope: _scope,
      sort: _sort,
      now: now,
      query: _search.text,
      tag: activeTag,
    );
    final page = ZenPage(
      title: '事 项',
      maxWidth: 760,
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 104),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TodoComposer(
            text: _newText,
            tags: _newTags,
            due: _newDue,
            expanded: _showComposerDetails,
            onToggleExpanded: () =>
                setState(() => _showComposerDetails = !_showComposerDetails),
            onPickDue: _pickDue,
            onClearDue: () => setState(() => _newDue = null),
            onSubmit: _submit,
          ),
          const SizedBox(height: 28),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                _ScopeChip(
                  scope: TodoScope.active,
                  count: active.length,
                  selected: _scope == TodoScope.active,
                  onTap: () => setState(() => _scope = TodoScope.active),
                ),
                _ScopeChip(
                  scope: TodoScope.today,
                  count: today.length,
                  selected: _scope == TodoScope.today,
                  onTap: () => setState(() => _scope = TodoScope.today),
                ),
                _ScopeChip(
                  scope: TodoScope.upcoming,
                  count: upcoming.length,
                  selected: _scope == TodoScope.upcoming,
                  onTap: () => setState(() => _scope = TodoScope.upcoming),
                ),
                _ScopeChip(
                  scope: TodoScope.completed,
                  count: completed.length,
                  selected: _scope == TodoScope.completed,
                  onTap: () => setState(() => _scope = TodoScope.completed),
                ),
                _ScopeChip(
                  scope: TodoScope.archived,
                  count: archived.length,
                  selected: _scope == TodoScope.archived,
                  onTap: () => setState(() => _scope = TodoScope.archived),
                ),
                _ScopeChip(
                  scope: TodoScope.all,
                  count: todos.length - archived.length,
                  selected: _scope == TodoScope.all,
                  onTap: () => setState(() => _scope = TodoScope.all),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.only(left: 14, right: 4),
            decoration: BoxDecoration(
              color: palette.paperDeep.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.inkFaint),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 17, color: palette.inkSoft),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const ValueKey('todo-search-field'),
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: '搜 正 文 或 标 签',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                if (_search.text.isNotEmpty)
                  IconButton(
                    tooltip: '清 空 搜 索',
                    onPressed: _search.clear,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: palette.inkSoft,
                  ),
                PopupMenuButton<TodoSort>(
                  key: const ValueKey('todo-sort-menu'),
                  tooltip: '排 序',
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  color: palette.paper,
                  icon: Icon(Icons.tune_rounded, size: 18, color: palette.ink),
                  itemBuilder: (context) => [
                    for (final value in TodoSort.values)
                      PopupMenuItem(
                        value: value,
                        child: Text(_sortLabel(value)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                InkChip(
                  label: '全 部 标 签',
                  selected: activeTag == null,
                  onTap: () => setState(() => _activeTag = null),
                ),
                for (final tag in tags)
                  InkChip(
                    label: tag,
                    selected: activeTag == tag,
                    onTap: () => setState(() => _activeTag = tag),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                '${_scopeTitle(_scope)} · ${shown.length}',
                style: inkText(
                  context,
                  size: 11,
                  color: palette.inkSoft,
                  spacing: 3.2,
                ),
              ),
              const Spacer(),
              Text(
                _sortLabel(_sort),
                style: TextStyle(
                  fontSize: 12,
                  color: palette.inkSoft,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: shown.isEmpty
                ? _TodoEmpty(scope: _scope, key: ValueKey('empty-$_scope'))
                : Column(
                    key: ValueKey(
                      'list-${_scope.name}-${_sort.name}-${activeTag ?? ''}-${_search.text}',
                    ),
                    children: [
                      for (final todo in shown)
                        _TodoCard(
                          todo: todo,
                          onTap: () => _edit(todo),
                          onToggle: () => controller.setTodoProgressById(
                            todo.id,
                            todo.progress == 100 ? 0 : 100,
                          ),
                          onArchive: () => controller.archiveTodoById(todo.id),
                          onRestore: () => controller.restoreTodoById(todo.id),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: page),
        Positioned.fill(
          child: GlobalNav(
            current: GlobalNavDestination.goals,
            todoCount: controller.doingTodos.length,
            dim: controller.timer.status == TimerStatus.running,
            onFocus: () => Navigator.of(context).maybePop(),
            onGoals: () {},
          ),
        ),
      ],
    );
  }
}

class _TodoComposer extends StatelessWidget {
  const _TodoComposer({
    required this.text,
    required this.tags,
    required this.due,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onPickDue,
    required this.onClearDue,
    required this.onSubmit,
  });

  final TextEditingController text;
  final TextEditingController tags;
  final DateTime? due;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onPickDue;
  final VoidCallback onClearDue;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: palette.paper.withValues(alpha: 0.72),
        border: Border.all(color: palette.ink.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: palette.ink.withValues(alpha: 0.055),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('new-todo-text'),
                  controller: text,
                  maxLength: 500,
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSubmit(),
                  decoration: const InputDecoration(
                    hintText: '记 下 接 下 来 的 一 桩 事 …',
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                tooltip: '标 签 与 截 止 日',
                onPressed: onToggleExpanded,
                icon: Icon(
                  expanded ? Icons.expand_less_rounded : Icons.tune_rounded,
                  size: 18,
                ),
                color: palette.inkSoft,
              ),
              FilledButton(
                key: const ValueKey('add-todo'),
                onPressed: onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.ink,
                  foregroundColor: palette.paper,
                  minimumSize: const Size(52, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text('记', style: inkText(context, color: palette.paper)),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: !expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Column(
                      children: [
                        TextField(
                          controller: tags,
                          decoration: const InputDecoration(
                            hintText: '标签（逗号分隔）',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: onPickDue,
                              icon: const Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                              ),
                              label: Text(
                                due == null ? '设 截 止 日' : _dateLabel(due!),
                                style: inkText(
                                  context,
                                  size: 12,
                                  color: palette.inkSoft,
                                  spacing: 2,
                                ),
                              ),
                            ),
                            if (due != null)
                              IconButton(
                                tooltip: '清 除 截 止 日',
                                onPressed: onClearDue,
                                icon: const Icon(Icons.close_rounded, size: 14),
                                color: palette.inkSoft,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.scope,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final TodoScope scope;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkChip(
        key: ValueKey('todo-scope-${scope.name}'),
        label: '${_scopeTitle(scope)}  $count',
        selected: selected,
        filled: selected,
        onTap: onTap,
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({
    required this.todo,
    required this.onTap,
    required this.onToggle,
    required this.onArchive,
    required this.onRestore,
  });

  final TodoItem todo;
  final VoidCallback onTap;
  final Future<void> Function() onToggle;
  final Future<void> Function() onArchive;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final due = _dueInfo(todo);
    final archived = todo.archivedAt != null;
    return Container(
      key: ValueKey('todo-card-${todo.id}'),
      margin: const EdgeInsets.only(bottom: 11),
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      decoration: BoxDecoration(
        color: palette.paperDeep.withValues(alpha: archived ? 0.22 : 0.38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.inkFaint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            button: true,
            label: todo.progress == 100 ? '重 新 打 开' : '标 为 完 成',
            child: InkWell(
              onTap: archived ? null : () => unawaited(onToggle()),
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: 44,
                height: 44,
                child: CustomPaint(
                  painter: _TodoProgressPainter(todo.progress, palette),
                  child: Center(
                    child: todo.progress == 100
                        ? Icon(
                            Icons.check_rounded,
                            size: 17,
                            color: palette.rest,
                          )
                        : Text(
                            '${todo.progress}',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.inkSoft,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'NotoSerifSC',
                        fontSize: 13,
                        height: 1.65,
                        color: archived ? palette.inkSoft : palette.ink,
                        decoration: todo.progress == 100
                            ? TextDecoration.lineThrough
                            : null,
                      ).variableWeight,
                    ),
                    if (todo.totalFocusSec > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        '专 注 ${todo.sessionsLinked} 次 · ${formatDuration(todo.totalFocusSec)} · ${todoLinkBonus(todo).toStringAsFixed(2)}x',
                        style: inkText(
                          context,
                          size: 11,
                          color: palette.workSoft,
                          spacing: 1.1,
                        ),
                      ),
                    ],
                    if ((todo.tags?.isNotEmpty ?? false) || due != null) ...[
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 5,
                        children: [
                          if (due != null)
                            _MetaPill(
                              label: due.label,
                              color: due.overdue
                                  ? palette.work
                                  : palette.inkSoft,
                            ),
                          for (final tag in todo.tags ?? const <String>[])
                            _MetaPill(label: tag, color: palette.inkSoft),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (archived)
            IconButton(
              key: ValueKey('todo-restore-${todo.id}'),
              tooltip: '恢 复',
              onPressed: () => unawaited(onRestore()),
              icon: const Icon(Icons.unarchive_outlined, size: 18),
              color: palette.inkSoft,
            )
          else
            IconButton(
              key: ValueKey('todo-archive-${todo.id}'),
              tooltip: '归 档',
              onPressed: () => unawaited(onArchive()),
              icon: const Icon(Icons.archive_outlined, size: 18),
              color: palette.inkSoft,
            ),
        ],
      ),
    );
  }
}

class _TodoProgressPainter extends CustomPainter {
  const _TodoProgressPainter(this.progress, this.palette);

  final int progress;
  final ZenPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.42;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = palette.inkFaint,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -1.5708,
        6.2832 * (progress / 100),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.4
          ..color = progress == 100 ? palette.rest : palette.work,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TodoProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.palette != palette;
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.24)),
    ),
    child: Text(
      label,
      style: inkText(context, size: 11, color: color, spacing: 1.4),
    ),
  );
}

class _TodoEmpty extends StatelessWidget {
  const _TodoEmpty({super.key, required this.scope});

  final TodoScope scope;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Text(
            scope == TodoScope.archived ? '库 中 无 旧 事' : '此 间 无 事',
            style: inkText(
              context,
              size: 13,
              color: palette.inkSoft,
              spacing: 6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            scope == TodoScope.active ? '写下一桩，便有了落笔之处' : '换一处视图看看',
            style: TextStyle(fontSize: 11, color: palette.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _TodoEditorSheet extends StatefulWidget {
  const _TodoEditorSheet({required this.controller, required this.todo});

  final AppController controller;
  final TodoItem todo;

  @override
  State<_TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends State<_TodoEditorSheet> {
  late final TextEditingController _text = TextEditingController(
    text: widget.todo.text,
  );
  late final TextEditingController _tags = TextEditingController(
    text: (widget.todo.tags ?? const []).join('，'),
  );
  late double _progress = widget.todo.progress.toDouble();
  late DateTime? _due = widget.todo.dueAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(widget.todo.dueAt!);
  bool _confirmDelete = false;
  Timer? _deleteTimer;

  @override
  void dispose() {
    _text.dispose();
    _tags.dispose();
    _deleteTimer?.cancel();
    super.dispose();
  }

  List<String> _parsedTags() => _tags.text
      .split(RegExp('[,，]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  Future<void> _save() async {
    await widget.controller.updateTodo(
      widget.todo.id,
      text: _text.text,
      tags: _parsedTags(),
      dueAt: _due?.millisecondsSinceEpoch,
    );
    if (_progress.round() != widget.todo.progress) {
      await widget.controller.setTodoProgressById(widget.todo.id, _progress);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDue() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected != null) setState(() => _due = selected);
  }

  void _delete() {
    if (_confirmDelete) {
      unawaited(widget.controller.deleteTodo(widget.todo.id));
      Navigator.pop(context);
      return;
    }
    setState(() => _confirmDelete = true);
    _deleteTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _confirmDelete = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: palette.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            28,
            24,
            28,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            children: [
              Text('理 一 桩', style: inkText(context, size: 13, spacing: 5)),
              const SizedBox(height: 18),
              TextField(
                controller: _text,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tags,
                decoration: const InputDecoration(hintText: '标签（逗号分隔）'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _progress,
                      divisions: 100,
                      label: '${_progress.round()}%',
                      onChanged: (value) => setState(() => _progress = value),
                    ),
                  ),
                  SizedBox(
                    width: 46,
                    child: Text(
                      '${_progress.round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: palette.inkSoft),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _pickDue,
                    child: Text(
                      _due == null ? '截 止' : _dateLabel(_due!),
                      style: inkText(context, size: 12, color: palette.inkSoft),
                    ),
                  ),
                  if (_due != null)
                    IconButton(
                      onPressed: () => setState(() => _due = null),
                      icon: const Icon(Icons.close, size: 14),
                      color: palette.inkSoft,
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: _save,
                    child: Text('收', style: inkText(context, spacing: 4)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      '罢',
                      style: inkText(
                        context,
                        color: palette.inkSoft,
                        spacing: 4,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _delete,
                    child: Text(
                      _confirmDelete ? '确 认' : '删',
                      style: inkText(
                        context,
                        color: _confirmDelete ? palette.work : palette.inkSoft,
                        spacing: 3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _scopeTitle(TodoScope scope) => switch (scope) {
  TodoScope.active => '进 行',
  TodoScope.today => '今 日',
  TodoScope.upcoming => '将 来',
  TodoScope.completed => '已 成',
  TodoScope.archived => '归 档',
  TodoScope.all => '全 部',
};

String _sortLabel(TodoSort sort) => switch (sort) {
  TodoSort.smart => '智 能 排 序',
  TodoSort.due => '截 止 日',
  TodoSort.newest => '最 新 建 立',
  TodoSort.progress => '进 度 优 先',
};

String _dateLabel(DateTime date) => '${date.month} 月 ${date.day} 日';

({String label, bool overdue})? _dueInfo(TodoItem todo) {
  if (todo.dueAt == null) return null;
  final date = DateTime.fromMillisecondsSinceEpoch(todo.dueAt!);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(date.year, date.month, date.day);
  final delta = due.difference(today).inDays;
  final label = delta == 0
      ? '今 天'
      : delta == 1
      ? '明 天'
      : delta == -1
      ? '昨 天'
      : _dateLabel(date);
  return (
    label: label,
    overdue: todo.progress < 100 && todo.archivedAt == null && delta < 0,
  );
}
