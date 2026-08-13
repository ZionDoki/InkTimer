import 'package:flutter/material.dart';

import '../../domain/composer.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../theme/zen_theme.dart';
import '../widgets/zen_page.dart';

class TemplateEditorPage extends StatefulWidget {
  const TemplateEditorPage({
    super.key,
    required this.controller,
    this.initial,
    this.initialDraft,
  }) : assert(initial != null || initialDraft != null);

  final AppController controller;
  final TimerTemplate? initial;
  final ComposerDraft? initialDraft;

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  late ComposerDraft _draft =
      widget.initialDraft ?? templateToComposer(widget.initial!);
  late final TextEditingController _label = TextEditingController(
    text: _draft.label,
  );

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _applyPreset(ComposerPreset preset) {
    setState(() {
      _draft = applyComposerPreset(_draft.copyWith(label: _label.text), preset);
      _label.text = _draft.label;
    });
  }

  void _updatePhase(int index, ComposerPhase phase) {
    final phases = List<ComposerPhase>.of(_draft.phases)..[index] = phase;
    setState(() => _draft = _draft.copyWith(phases: phases));
  }

  void _addPhase() {
    final role = _draft.kind == TemplateKind.pomodoro
        ? SequencePhaseRole.focus
        : SequencePhaseRole.work;
    final phase = ComposerPhase(
      id: '${_draft.id}.phase.${DateTime.now().microsecondsSinceEpoch}',
      role: role,
      durationSec: _draft.kind == TemplateKind.pomodoro ? 600 : 30,
      unit: _draft.kind == TemplateKind.pomodoro
          ? ComposerUnit.minute
          : ComposerUnit.second,
    );
    setState(() => _draft = _draft.copyWith(phases: [..._draft.phases, phase]));
  }

  Future<void> _save() async {
    _draft = _draft.copyWith(label: _label.text);
    await widget.controller.upsertTemplate(composerToTemplate(_draft));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return ZenPage(
      title: widget.initial == null ? '新 笺' : '编 笺',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('template-label'),
            controller: _label,
            maxLength: 20,
            textAlign: TextAlign.center,
            style: inkText(context, size: 17, spacing: 4),
            decoration: const InputDecoration(hintText: '笺 名', counterText: ''),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              InkChip(
                label: '番 茄',
                selected: false,
                onTap: () => _applyPreset(ComposerPreset.pomodoro),
              ),
              InkChip(
                label: '间 歇',
                selected: false,
                onTap: () => _applyPreset(ComposerPreset.interval),
              ),
              InkChip(
                label: '空 白',
                selected: false,
                onTap: () => _applyPreset(ComposerPreset.blank),
              ),
              InkChip(
                label: '积 累',
                selected: _draft.mode == ComposerMode.countup,
                onTap: () => _applyPreset(ComposerPreset.countup),
              ),
            ],
          ),
          const ZenSectionTitle('计 时 方 式', top: 38),
          Row(
            children: [
              Expanded(
                child: InkChip(
                  label: '倒 计 时',
                  selected: _draft.mode == ComposerMode.countdown,
                  onTap: () => setState(
                    () =>
                        _draft = _draft.copyWith(mode: ComposerMode.countdown),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkChip(
                  label: '正 计 时',
                  selected: _draft.mode == ComposerMode.countup,
                  onTap: () => setState(
                    () => _draft = _draft.copyWith(mode: ComposerMode.countup),
                  ),
                ),
              ),
            ],
          ),
          if (_draft.mode == ComposerMode.countdown) ...[
            const ZenSectionTitle('类 型 与 轮 次'),
            Row(
              children: [
                Expanded(
                  child: InkChip(
                    label: '番 茄',
                    selected: _draft.kind == TemplateKind.pomodoro,
                    onTap: () => setState(
                      () =>
                          _draft = _draft.copyWith(kind: TemplateKind.pomodoro),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkChip(
                    label: '间 歇',
                    selected: _draft.kind == TemplateKind.interval,
                    onTap: () => setState(
                      () =>
                          _draft = _draft.copyWith(kind: TemplateKind.interval),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                _NumberStepper(
                  value: _draft.rounds,
                  min: 1,
                  max: 20,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(rounds: value)),
                ),
              ],
            ),
            const ZenSectionTitle('编 排'),
            for (var index = 0; index < _draft.phases.length; index++)
              _PhaseRow(
                key: ValueKey(_draft.phases[index].id),
                phase: _draft.phases[index],
                onChanged: (phase) => _updatePhase(index, phase),
                onDelete: _draft.phases.length <= 1
                    ? null
                    : () {
                        final phases = List<ComposerPhase>.of(_draft.phases)
                          ..removeAt(index);
                        setState(
                          () => _draft = _draft.copyWith(phases: phases),
                        );
                      },
              ),
            Center(
              child: TextButton(
                onPressed: _addPhase,
                child: Text(
                  '添 一 段',
                  style: inkText(
                    context,
                    size: 11,
                    color: palette.inkSoft,
                    spacing: 4,
                  ),
                ),
              ),
            ),
            const ZenSectionTitle('长 休 规 则'),
            Row(
              children: [
                Text(
                  '每',
                  style: inkText(context, size: 11, color: palette.inkSoft),
                ),
                const SizedBox(width: 10),
                _NumberStepper(
                  value: _draft.longBreakEvery,
                  min: 0,
                  max: 20,
                  onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(longBreakEvery: value),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '轮 · 休',
                  style: inkText(context, size: 11, color: palette.inkSoft),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: formatDurationAmount(
                      _draft.longBreakSec,
                      _draft.longBreakUnit,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textAlign: TextAlign.center,
                    onChanged: (value) => _draft = _draft.copyWith(
                      longBreakSec: durationFromAmount(
                        value,
                        _draft.longBreakUnit,
                        _draft.longBreakSec,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _draft.longBreakUnit == ComposerUnit.minute ? '分' : '秒',
                  style: inkText(context, size: 12, color: palette.inkSoft),
                ),
              ],
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 62),
              child: Text(
                '无 终 点 · 自 由 积 累',
                textAlign: TextAlign.center,
                style: inkText(
                  context,
                  size: 12,
                  color: palette.inkSoft,
                  spacing: 5,
                ),
              ),
            ),
          ],
          const SizedBox(height: 52),
          Center(
            child: FilledButton.tonal(
              key: const ValueKey('save-template'),
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: palette.ink.withValues(alpha: 0.07),
                foregroundColor: palette.ink,
                padding: const EdgeInsets.symmetric(
                  horizontal: 34,
                  vertical: 14,
                ),
              ),
              child: Text('收 入 笺 匣', style: inkText(context, spacing: 5)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    super.key,
    required this.phase,
    required this.onChanged,
    this.onDelete,
  });

  final ComposerPhase phase;
  final ValueChanged<ComposerPhase> onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.inkFaint)),
      ),
      child: Row(
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<SequencePhaseRole>(
              value: phase.role,
              dropdownColor: palette.paper,
              style: inkText(context, size: 11),
              items:
                  const {
                        SequencePhaseRole.focus: '专 注',
                        SequencePhaseRole.work: '动 作',
                        SequencePhaseRole.rest: '休 息',
                        SequencePhaseRole.prepare: '准 备',
                      }.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                if (value != null) onChanged(phase.copyWith(role: value));
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              key: ValueKey(
                '${phase.id}.${phase.durationSec}.${phase.unit.name}',
              ),
              initialValue: formatDurationAmount(phase.durationSec, phase.unit),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              onChanged: (value) => onChanged(
                phase.copyWith(
                  durationSec: durationFromAmount(
                    value,
                    phase.unit,
                    phase.durationSec,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              final next = phase.unit == ComposerUnit.second
                  ? ComposerUnit.minute
                  : ComposerUnit.second;
              onChanged(phase.copyWith(unit: next));
            },
            child: Text(
              phase.unit == ComposerUnit.second ? '秒' : '分',
              style: inkText(context, size: 12, color: palette.inkSoft),
            ),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.close, size: 15),
              color: palette.inkSoft,
              tooltip: '删 除 此 段',
            ),
        ],
      ),
    );
  }
}

class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(
          context,
          '−',
          value <= min ? null : () => onChanged(value - 1),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: palette.ink),
          ),
        ),
        _stepButton(
          context,
          '+',
          value >= max ? null : () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _stepButton(BuildContext context, String label, VoidCallback? onTap) {
    final palette = ZenPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 18,
              color: onTap == null ? palette.inkFaint : palette.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}
