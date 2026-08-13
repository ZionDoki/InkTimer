import 'models.dart';

enum PhaseKind { work, rest, longRest }

extension PhaseKindWire on PhaseKind {
  String get wire => name;
}

class Phase {
  const Phase({
    required this.kind,
    required this.durationSec,
    required this.round,
    required this.roundsTotal,
    this.role,
  });

  final PhaseKind kind;
  final SequencePhaseRole? role;
  final int durationSec;
  final int round;
  final int roundsTotal;
}

int totalFocusSec(List<Phase> phases) => phases
    .where((phase) => phase.kind == PhaseKind.work)
    .fold(0, (sum, phase) => sum + phase.durationSec);

/// Focus seconds within the half-open elapsed interval [startSec, endSec).
int elapsedSecAtSnapshot(
  List<Phase> phases, {
  required int index,
  required double phaseRemainingMs,
}) {
  if (phases.isEmpty || index < 0 || index >= phases.length) return 0;
  final completed = phases
      .take(index)
      .fold<int>(0, (sum, phase) => sum + phase.durationSec);
  final current = phases[index];
  final progressedMs = (current.durationSec * 1000 - phaseRemainingMs).clamp(
    0,
    current.durationSec * 1000,
  );
  return completed + (progressedMs / 1000).floor();
}

int focusOverlapSec(List<Phase> phases, int startSec, int endSec) {
  final start = startSec.clamp(0, 1 << 62);
  final end = endSec.clamp(start, 1 << 62);
  if (end <= start) return 0;
  var cursor = 0;
  var overlap = 0;
  for (final phase in phases) {
    final phaseStart = cursor;
    final phaseEnd = cursor + phase.durationSec;
    if (phase.kind == PhaseKind.work) {
      final overlapStart = phaseStart > start ? phaseStart : start;
      final overlapEnd = phaseEnd < end ? phaseEnd : end;
      if (overlapEnd > overlapStart) overlap += overlapEnd - overlapStart;
    }
    cursor = phaseEnd;
    if (cursor >= end) break;
  }
  return overlap;
}

PhaseKind _kindForRole(SequencePhaseRole role) =>
    role == SequencePhaseRole.focus || role == SequencePhaseRole.work
    ? PhaseKind.work
    : PhaseKind.rest;

List<Phase> _compileSequence(TimerTemplate template, int rounds) {
  final specs = template.sequence!;
  var lastRestIndex = -1;
  for (var index = 0; index < specs.length; index += 1) {
    if (specs[index].role == SequencePhaseRole.rest) lastRestIndex = index;
  }
  final output = <Phase>[];
  for (var round = 1; round <= rounds; round += 1) {
    final useLongRest =
        template.longBreakEvery != null &&
        template.longBreakSec != null &&
        template.longBreakSec! > 0 &&
        round % template.longBreakEvery! == 0;
    for (var index = 0; index < specs.length; index += 1) {
      final spec = specs[index];
      final skipFinalRest =
          template.skipFinalRest == true &&
          round == rounds &&
          !useLongRest &&
          index == lastRestIndex;
      if (skipFinalRest) continue;
      if (useLongRest && index == lastRestIndex) {
        output.add(
          Phase(
            kind: PhaseKind.longRest,
            role: SequencePhaseRole.rest,
            durationSec: template.longBreakSec!,
            round: round,
            roundsTotal: rounds,
          ),
        );
      } else {
        output.add(
          Phase(
            kind: _kindForRole(spec.role),
            role: spec.role,
            durationSec: spec.durationSec,
            round: round,
            roundsTotal: rounds,
          ),
        );
      }
    }
    if (useLongRest && lastRestIndex < 0) {
      output.add(
        Phase(
          kind: PhaseKind.longRest,
          role: SequencePhaseRole.rest,
          durationSec: template.longBreakSec!,
          round: round,
          roundsTotal: rounds,
        ),
      );
    }
  }
  return output;
}

int _required(int? value, String field) {
  if (value == null || value <= 0) {
    throw ArgumentError('template missing $field');
  }
  return value;
}

List<Phase> _interval(
  int rounds,
  int Function(int round) work,
  ({int sec, bool isLong})? Function(int round) rest,
) {
  final output = <Phase>[];
  for (var round = 1; round <= rounds; round += 1) {
    output.add(
      Phase(
        kind: PhaseKind.work,
        durationSec: work(round),
        round: round,
        roundsTotal: rounds,
      ),
    );
    if (round < rounds) {
      final restSpec = rest(round);
      if (restSpec != null && restSpec.sec > 0) {
        output.add(
          Phase(
            kind: restSpec.isLong ? PhaseKind.longRest : PhaseKind.rest,
            durationSec: restSpec.sec,
            round: round,
            roundsTotal: rounds,
          ),
        );
      }
    }
  }
  return output;
}

List<Phase> compileTemplate(TimerTemplate template) {
  final rounds = template.rounds ?? 1;
  if (template.kind != TemplateKind.accumulate &&
      template.sequence != null &&
      template.sequence!.isNotEmpty) {
    return _compileSequence(template, rounds);
  }

  switch (template.kind) {
    case TemplateKind.pomodoro:
      final focus = _required(template.focusSec, 'focusSec');
      final regularBreak = template.breakSec ?? 0;
      final phases = _interval(rounds, (_) => focus, (round) {
        final isLong =
            template.longBreakEvery != null &&
            template.longBreakSec != null &&
            round % template.longBreakEvery! == 0;
        return (
          sec: isLong ? template.longBreakSec! : regularBreak,
          isLong: isLong,
        );
      });
      final terminalLongRest =
          template.longBreakEvery != null &&
          template.longBreakSec != null &&
          template.longBreakSec! > 0 &&
          rounds % template.longBreakEvery! == 0;
      if (terminalLongRest) {
        phases.add(
          Phase(
            kind: PhaseKind.longRest,
            durationSec: template.longBreakSec!,
            round: rounds,
            roundsTotal: rounds,
          ),
        );
      }
      return phases;
    case TemplateKind.interval:
      if (template.phases != null && template.phases!.isNotEmpty) {
        final output = <Phase>[];
        final pairs = template.phases!;
        for (var round = 1; round <= rounds; round += 1) {
          for (var index = 0; index < pairs.length; index += 1) {
            final pair = pairs[index];
            output.add(
              Phase(
                kind: PhaseKind.work,
                durationSec: pair.workSec,
                round: round,
                roundsTotal: rounds,
              ),
            );
            final lastPair = index == pairs.length - 1;
            if (!(lastPair && round == rounds) && pair.restSec > 0) {
              output.add(
                Phase(
                  kind: PhaseKind.rest,
                  durationSec: pair.restSec,
                  round: round,
                  roundsTotal: rounds,
                ),
              );
            }
          }
        }
        return output;
      }
      final work = _required(template.workSec, 'workSec');
      final rest = template.restSec ?? 0;
      return _interval(rounds, (_) => work, (_) => (sec: rest, isLong: false));
    case TemplateKind.accumulate:
      throw ArgumentError('accumulate 无相位，走正计时');
  }
}

int plannedDurationSec(Iterable<Phase> phases) =>
    phases.fold(0, (sum, phase) => sum + phase.durationSec);

int completedRounds(List<Phase> phases, int currentIndex) {
  final roundsTotal = phases.isEmpty ? 0 : phases.last.roundsTotal;
  var done = 0;
  for (var round = 1; round <= roundsTotal; round += 1) {
    final workIndices = <int>[];
    for (var index = 0; index < phases.length; index += 1) {
      if (phases[index].round == round &&
          phases[index].kind == PhaseKind.work) {
        workIndices.add(index);
      }
    }
    if (workIndices.isNotEmpty &&
        workIndices.every((index) => index < currentIndex)) {
      done += 1;
    }
  }
  return done;
}
