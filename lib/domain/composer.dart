import 'models.dart';

enum ComposerMode { countdown, countup }

enum ComposerUnit { second, minute }

enum ComposerPreset { pomodoro, interval, blank, countup }

class ComposerPhase {
  const ComposerPhase({
    required this.id,
    required this.role,
    required this.durationSec,
    required this.unit,
  });

  final String id;
  final SequencePhaseRole role;
  final int durationSec;
  final ComposerUnit unit;

  ComposerPhase copyWith({
    SequencePhaseRole? role,
    int? durationSec,
    ComposerUnit? unit,
  }) => ComposerPhase(
    id: id,
    role: role ?? this.role,
    durationSec: durationSec ?? this.durationSec,
    unit: unit ?? this.unit,
  );
}

class ComposerDraft {
  const ComposerDraft({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.mode,
    required this.kind,
    required this.rounds,
    required this.phases,
    required this.longBreakEvery,
    required this.longBreakSec,
    required this.longBreakUnit,
    required this.skipFinalRest,
    this.builtin,
  });

  final String id;
  final String label;
  final bool? builtin;
  final int createdAt;
  final ComposerMode mode;
  final TemplateKind kind;
  final int rounds;
  final List<ComposerPhase> phases;
  final int longBreakEvery;
  final int longBreakSec;
  final ComposerUnit longBreakUnit;
  final bool skipFinalRest;

  ComposerDraft copyWith({
    String? label,
    ComposerMode? mode,
    TemplateKind? kind,
    int? rounds,
    List<ComposerPhase>? phases,
    int? longBreakEvery,
    int? longBreakSec,
    ComposerUnit? longBreakUnit,
    bool? skipFinalRest,
  }) => ComposerDraft(
    id: id,
    label: label ?? this.label,
    builtin: builtin,
    createdAt: createdAt,
    mode: mode ?? this.mode,
    kind: kind ?? this.kind,
    rounds: rounds ?? this.rounds,
    phases: phases ?? this.phases,
    longBreakEvery: longBreakEvery ?? this.longBreakEvery,
    longBreakSec: longBreakSec ?? this.longBreakSec,
    longBreakUnit: longBreakUnit ?? this.longBreakUnit,
    skipFinalRest: skipFinalRest ?? this.skipFinalRest,
  );
}

const _maxDurationSec = 86400;

int _clampInt(num value, int min, int max) => value.round().clamp(min, max);

ComposerUnit _preferredUnit(int durationSec) =>
    durationSec >= 120 ? ComposerUnit.minute : ComposerUnit.second;

ComposerPhase _phase(
  String id,
  SequencePhaseRole role,
  int durationSec, [
  ComposerUnit? unit,
]) => ComposerPhase(
  id: id,
  role: role,
  durationSec: durationSec,
  unit: unit ?? _preferredUnit(durationSec),
);

String formatDurationAmount(int durationSec, ComposerUnit unit) {
  final amount = durationSec / (unit == ComposerUnit.minute ? 60 : 1);
  if (amount == amount.roundToDouble()) return amount.round().toString();
  return amount
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

int durationFromAmount(Object raw, ComposerUnit unit, int fallbackSec) {
  final amount = double.tryParse(raw.toString().trim().replaceAll(',', '.'));
  if (amount == null || !amount.isFinite || amount <= 0) return fallbackSec;
  return _clampInt(
    amount * (unit == ComposerUnit.minute ? 60 : 1),
    1,
    _maxDurationSec,
  );
}

ComposerDraft templateToComposer(TimerTemplate template) {
  final kind = template.kind == TemplateKind.pomodoro
      ? TemplateKind.pomodoro
      : TemplateKind.interval;
  final phases = <ComposerPhase>[];
  if (template.sequence?.isNotEmpty ?? false) {
    for (var index = 0; index < template.sequence!.length; index += 1) {
      final item = template.sequence![index];
      phases.add(
        _phase('${template.id}.sequence.$index', item.role, item.durationSec),
      );
    }
  } else if (template.kind == TemplateKind.pomodoro) {
    phases.add(
      _phase(
        '${template.id}.focus',
        SequencePhaseRole.focus,
        template.focusSec ?? 1500,
        ComposerUnit.minute,
      ),
    );
    if ((template.breakSec ?? 0) > 0) {
      phases.add(
        _phase(
          '${template.id}.rest',
          SequencePhaseRole.rest,
          template.breakSec!,
          ComposerUnit.minute,
        ),
      );
    }
  } else if (template.kind == TemplateKind.interval) {
    final pairs = template.phases?.isNotEmpty ?? false
        ? template.phases!
        : [
            HiitPair(
              workSec: template.workSec ?? 30,
              restSec: template.restSec ?? 0,
            ),
          ];
    for (var index = 0; index < pairs.length; index += 1) {
      final pair = pairs[index];
      phases.add(
        _phase(
          '${template.id}.work.$index',
          SequencePhaseRole.work,
          pair.workSec,
          ComposerUnit.second,
        ),
      );
      if (pair.restSec > 0) {
        phases.add(
          _phase(
            '${template.id}.rest.$index',
            SequencePhaseRole.rest,
            pair.restSec,
            ComposerUnit.second,
          ),
        );
      }
    }
  }
  return ComposerDraft(
    id: template.id,
    label: template.label,
    builtin: template.builtin,
    createdAt: template.createdAt,
    mode: template.kind == TemplateKind.accumulate
        ? ComposerMode.countup
        : ComposerMode.countdown,
    kind: kind,
    rounds: template.rounds ?? 1,
    phases: phases,
    longBreakEvery: template.longBreakEvery ?? 0,
    longBreakSec: template.longBreakSec ?? 0,
    longBreakUnit: (template.longBreakSec ?? 0) >= 60
        ? ComposerUnit.minute
        : ComposerUnit.second,
    skipFinalRest: template.sequence?.isNotEmpty == true
        ? (template.skipFinalRest ?? false)
        : template.kind != TemplateKind.accumulate,
  );
}

ComposerDraft newComposerDraft({required String id, required int now}) =>
    templateToComposer(
      TimerTemplate(
        id: id,
        label: '',
        kind: TemplateKind.pomodoro,
        createdAt: now,
        focusSec: 1500,
        breakSec: 300,
        rounds: 4,
        longBreakEvery: 4,
        longBreakSec: 900,
      ),
    );

TimerTemplate composerToTemplate(ComposerDraft draft) {
  final fallbackLabel = draft.mode == ComposerMode.countup
      ? '积累'
      : draft.kind == TemplateKind.pomodoro
      ? '番茄钟'
      : '间歇';
  if (draft.mode == ComposerMode.countup) {
    return TimerTemplate(
      id: draft.id,
      label: draft.label.trim().isEmpty ? fallbackLabel : draft.label.trim(),
      kind: TemplateKind.accumulate,
      builtin: draft.builtin,
      createdAt: draft.createdAt,
    );
  }
  final phases = draft.phases.isNotEmpty
      ? draft.phases
      : [
          _phase(
            '${draft.id}.fallback',
            draft.kind == TemplateKind.pomodoro
                ? SequencePhaseRole.focus
                : SequencePhaseRole.work,
            60,
            ComposerUnit.minute,
          ),
        ];
  return TimerTemplate(
    id: draft.id,
    label: draft.label.trim().isEmpty ? fallbackLabel : draft.label.trim(),
    kind: draft.kind,
    builtin: draft.builtin,
    createdAt: draft.createdAt,
    rounds: _clampInt(draft.rounds, 1, 20),
    sequence: phases
        .map(
          (phase) => SequencePhase(
            role: phase.role,
            durationSec: _clampInt(phase.durationSec, 1, _maxDurationSec),
          ),
        )
        .toList(),
    longBreakEvery: draft.longBreakEvery > 0 && draft.longBreakSec > 0
        ? _clampInt(draft.longBreakEvery, 1, 20)
        : null,
    longBreakSec: draft.longBreakEvery > 0 && draft.longBreakSec > 0
        ? _clampInt(draft.longBreakSec, 1, _maxDurationSec)
        : null,
    skipFinalRest: draft.skipFinalRest ? true : null,
  );
}

ComposerDraft applyComposerPreset(ComposerDraft draft, ComposerPreset preset) =>
    switch (preset) {
      ComposerPreset.pomodoro => ComposerDraft(
        id: draft.id,
        label: '番茄钟',
        builtin: draft.builtin,
        createdAt: draft.createdAt,
        mode: ComposerMode.countdown,
        kind: TemplateKind.pomodoro,
        rounds: 4,
        phases: [
          _phase(
            '${draft.id}.preset.focus',
            SequencePhaseRole.focus,
            1500,
            ComposerUnit.minute,
          ),
          _phase(
            '${draft.id}.preset.rest',
            SequencePhaseRole.rest,
            300,
            ComposerUnit.minute,
          ),
        ],
        longBreakEvery: 4,
        longBreakSec: 900,
        longBreakUnit: ComposerUnit.minute,
        skipFinalRest: true,
      ),
      ComposerPreset.interval => ComposerDraft(
        id: draft.id,
        label: 'Tabata',
        builtin: draft.builtin,
        createdAt: draft.createdAt,
        mode: ComposerMode.countdown,
        kind: TemplateKind.interval,
        rounds: 8,
        phases: [
          _phase(
            '${draft.id}.preset.work',
            SequencePhaseRole.work,
            20,
            ComposerUnit.second,
          ),
          _phase(
            '${draft.id}.preset.rest',
            SequencePhaseRole.rest,
            10,
            ComposerUnit.second,
          ),
        ],
        longBreakEvery: 0,
        longBreakSec: 0,
        longBreakUnit: ComposerUnit.minute,
        skipFinalRest: true,
      ),
      ComposerPreset.blank => ComposerDraft(
        id: draft.id,
        label: '未命名',
        builtin: draft.builtin,
        createdAt: draft.createdAt,
        mode: ComposerMode.countdown,
        kind: TemplateKind.pomodoro,
        rounds: 1,
        phases: [
          _phase(
            '${draft.id}.preset.blank',
            SequencePhaseRole.focus,
            600,
            ComposerUnit.minute,
          ),
        ],
        longBreakEvery: 0,
        longBreakSec: 0,
        longBreakUnit: ComposerUnit.minute,
        skipFinalRest: false,
      ),
      ComposerPreset.countup => ComposerDraft(
        id: draft.id,
        label: '自由积累',
        builtin: draft.builtin,
        createdAt: draft.createdAt,
        mode: ComposerMode.countup,
        kind: draft.kind,
        rounds: 1,
        phases: const [],
        longBreakEvery: 0,
        longBreakSec: 0,
        longBreakUnit: ComposerUnit.minute,
        skipFinalRest: false,
      ),
    };
