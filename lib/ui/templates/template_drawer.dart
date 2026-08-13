import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../domain/composer.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../theme/zen_theme.dart';
import 'template_editor.dart';

class TemplateDrawer extends StatefulWidget {
  const TemplateDrawer({super.key, required this.controller});

  final AppController controller;

  @override
  State<TemplateDrawer> createState() => _TemplateDrawerState();
}

class _TemplateDrawerState extends State<TemplateDrawer> {
  String? _confirmDelete;
  Timer? _confirmTimer;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    _confirmTimer?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _edit(TimerTemplate template) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            TemplateEditorPage(controller: controller, initial: template),
      ),
    );
  }

  Future<void> _create() async {
    final draft = newComposerDraft(
      id: const Uuid().v4(),
      now: DateTime.now().millisecondsSinceEpoch,
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) =>
            TemplateEditorPage(controller: controller, initialDraft: draft),
      ),
    );
  }

  Future<void> _duplicate(TimerTemplate template) async {
    final copy = template.copyWith(
      id: const Uuid().v4(),
      label: '${template.label} · 副',
      clearBuiltin: true,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await controller.upsertTemplate(copy);
  }

  void _delete(TimerTemplate template) {
    if (_confirmDelete == template.id) {
      _confirmTimer?.cancel();
      setState(() => _confirmDelete = null);
      unawaited(controller.deleteTemplate(template.id));
      return;
    }
    _confirmTimer?.cancel();
    setState(() => _confirmDelete = template.id);
    _confirmTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _confirmDelete = null);
    });
  }

  Future<void> _showActions(TimerTemplate template) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final palette = ZenPalette.of(context);
        return Container(
          padding: EdgeInsets.fromLTRB(
            24,
            18,
            24,
            18 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: palette.paper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: Text('编', style: inkText(context, spacing: 3)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'copy'),
                child: Text('摹', style: inkText(context, spacing: 3)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'delete'),
                child: Text(
                  '删',
                  style: inkText(context, color: palette.work, spacing: 3),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await _edit(template);
      case 'copy':
        await _duplicate(template);
      case 'delete':
        _delete(template);
    }
  }

  Widget _templateRow(TimerTemplate template) {
    final selected = template.id == controller.selectedTemplateId;
    return _TemplateRow(
      template: template,
      selected: selected,
      confirming: _confirmDelete == template.id,
      onSelect: () async {
        await controller.selectTemplate(template.id);
        if (mounted) Navigator.pop(context);
      },
      onEdit: () => _edit(template),
      onDelete: () => _delete(template),
      onLongPress: () => _showActions(template),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final focusTemplates = controller.templates
        .where((template) => template.kind == TemplateKind.pomodoro)
        .toList();
    final movementTemplates = controller.templates
        .where((template) => template.kind != TemplateKind.pomodoro)
        .toList();
    return FractionallySizedBox(
      widthFactor: 1,
      heightFactor: 0.82,
      child: Material(
        color: palette.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Center(
                child: TextButton(
                  key: const ValueKey('close-template-drawer'),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '收 起',
                    style: inkText(
                      context,
                      size: 11,
                      color: palette.inkSoft,
                      spacing: 5,
                    ),
                  ),
                ),
              ),
            ),
            Text('时 间 笺', style: inkText(context, size: 15, spacing: 7)),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  26,
                  0,
                  26,
                  20 + MediaQuery.paddingOf(context).bottom,
                ),
                itemCount:
                    (focusTemplates.isEmpty ? 0 : focusTemplates.length + 1) +
                    (movementTemplates.isEmpty
                        ? 0
                        : movementTemplates.length + 1) +
                    1,
                separatorBuilder: (_, _) => const SizedBox.shrink(),
                itemBuilder: (context, index) {
                  var cursor = index;
                  if (focusTemplates.isNotEmpty) {
                    if (cursor == 0) {
                      return const _TemplateGroupHeader(
                        label: '专 注',
                        first: true,
                      );
                    }
                    cursor -= 1;
                    if (cursor < focusTemplates.length) {
                      return _templateRow(focusTemplates[cursor]);
                    }
                    cursor -= focusTemplates.length;
                  }
                  if (movementTemplates.isNotEmpty) {
                    if (cursor == 0) {
                      return _TemplateGroupHeader(
                        label: '运 动',
                        first: focusTemplates.isEmpty,
                      );
                    }
                    cursor -= 1;
                    if (cursor < movementTemplates.length) {
                      return _templateRow(movementTemplates[cursor]);
                    }
                  }
                  return _NewTemplateRow(onPressed: _create);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateGroupHeader extends StatelessWidget {
  const _TemplateGroupHeader({required this.label, required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 14, bottom: 8),
      child: Column(
        children: [
          Text(
            label,
            style: inkText(
              context,
              size: 12,
              color: palette.inkSoft,
              spacing: 4,
            ),
          ),
          const SizedBox(height: 4),
          Container(width: 40, height: 1, color: palette.inkFaint),
        ],
      ),
    );
  }
}

class _NewTemplateRow extends StatelessWidget {
  const _NewTemplateRow({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: OutlinedButton(
        key: const ValueKey('new-template'),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          side: BorderSide(color: palette.inkFaint),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          '＋ 新 建',
          style: inkText(context, size: 13, color: palette.inkSoft, spacing: 5),
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({
    required this.template,
    required this.selected,
    required this.confirming,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onLongPress,
  });

  final TimerTemplate template;
  final bool selected;
  final bool confirming;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final phaseColor = switch (template.kind) {
      TemplateKind.pomodoro => palette.work,
      TemplateKind.interval => palette.rest,
      TemplateKind.accumulate => palette.gold,
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: selected ? palette.ink.withValues(alpha: .04) : null,
        borderRadius: BorderRadius.circular(14),
        border: selected ? Border.all(color: palette.ink, width: .9) : null,
      ),
      child: InkWell(
        onTap: onSelect,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 3,
                height: 54,
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: phaseColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            template.label,
                            overflow: TextOverflow.ellipsis,
                            style: inkText(context, size: 17, spacing: 2),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _templateDetail(template),
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.inkSoft,
                        letterSpacing: 3,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  minimumSize: const Size(42, 42),
                  padding: EdgeInsets.zero,
                  foregroundColor: palette.inkSoft,
                ),
                child: Text('编', style: inkText(context, size: 13)),
              ),
              TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 42),
                  padding: EdgeInsets.zero,
                  foregroundColor: confirming ? palette.work : palette.inkSoft,
                ),
                child: Text(
                  confirming ? '确 认' : '删',
                  style: inkText(
                    context,
                    size: confirming ? 9 : 13,
                    color: confirming ? palette.work : palette.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _templateDetail(TimerTemplate template) {
  if (template.kind != TemplateKind.accumulate &&
      template.sequence?.isNotEmpty == true) {
    return '编 排 · ${template.sequence!.length} 段 × ${template.rounds ?? 1}';
  }
  return switch (template.kind) {
    TemplateKind.pomodoro =>
      '番 茄 · ${_formatMinutes(template.focusSec ?? 0)}′/'
          '${_formatMinutes(template.breakSec ?? 0)}′ × ${template.rounds ?? 1}',
    TemplateKind.interval when (template.phases?.length ?? 0) > 1 =>
      '间 歇 · 自 定 义 × ${template.rounds ?? 1}',
    TemplateKind.interval =>
      '间 歇 · ${template.workSec ?? 0}″/${template.restSec ?? 0}″ '
          '× ${template.rounds ?? 1}',
    TemplateKind.accumulate => '积 累',
  };
}

String _formatMinutes(int seconds) {
  final minutes = seconds / 60;
  return minutes == minutes.roundToDouble()
      ? minutes.round().toString()
      : minutes.toStringAsFixed(1);
}
