import 'schedule.dart';

enum TimerStatus { idle, running, paused, done }

enum TimerMode { countdown, countup }

enum TimerEventType {
  start,
  phaseStart,
  tick,
  countdown,
  phaseEnd,
  pause,
  resume,
  complete,
  stop,
}

class TimerSnapshot {
  const TimerSnapshot({
    this.version = 1,
    required this.mode,
    required this.status,
    required this.index,
    required this.phaseRemainingMs,
    required this.countUpElapsedMs,
    required this.savedAt,
  });

  final int version;
  final TimerMode mode;
  final TimerStatus status;
  final int index;
  final double phaseRemainingMs;
  final double countUpElapsedMs;
  final int savedAt;

  Map<String, Object> toJson() => {
    'version': version,
    'mode': mode.name,
    'status': status.name,
    'index': index,
    'phaseRemainingMs': phaseRemainingMs,
    'countUpElapsedMs': countUpElapsedMs,
    'savedAt': savedAt,
  };
}

class TimerEvent {
  const TimerEvent(
    this.type, {
    this.index,
    this.phase,
    this.remainSec,
    this.phaseProgress,
    this.sec,
    this.elapsedSec,
  });

  final TimerEventType type;
  final int? index;
  final Phase? phase;
  final int? remainSec;
  final double? phaseProgress;
  final int? sec;
  final int? elapsedSec;
}

typedef TimerListener = void Function(TimerEvent event);

double Function() createMonotonicClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsedMicroseconds / 1000;
}

class TimerEngine {
  TimerEngine({double Function()? nowMs})
    : _now = nowMs ?? createMonotonicClock();

  final double Function() _now;
  final Set<TimerListener> _listeners = {};
  TimerStatus status = TimerStatus.idle;
  List<Phase> _phases = const [];
  int _index = 0;
  double _phaseEndAt = 0;
  double _remainOnPauseMs = 0;
  int _lastWholeSec = -1;
  int _doneSecBefore = 0;
  bool _countUp = false;
  double _countUpAccumMs = 0;
  double _countUpStartAt = 0;

  void addListener(TimerListener listener) => _listeners.add(listener);

  void removeListener(TimerListener listener) => _listeners.remove(listener);

  void _emit(TimerEvent event) {
    for (final listener in List<TimerListener>.of(_listeners)) {
      listener(event);
    }
  }

  void load(List<Phase> phases) {
    _phases = List<Phase>.of(phases);
    _index = 0;
    _doneSecBefore = 0;
    _lastWholeSec = -1;
    _countUp = false;
    _remainOnPauseMs = 0;
    _countUpAccumMs = 0;
    status = TimerStatus.idle;
  }

  void loadCountUp() {
    _phases = const [];
    _countUp = true;
    _index = 0;
    _doneSecBefore = 0;
    _lastWholeSec = -1;
    _countUpAccumMs = 0;
    _remainOnPauseMs = 0;
    status = TimerStatus.idle;
  }

  TimerSnapshot? snapshot({int? savedAtMs}) {
    if (status != TimerStatus.running && status != TimerStatus.paused) {
      return null;
    }
    final savedAt = savedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    if (_countUp) {
      final elapsed =
          _countUpAccumMs +
          (status == TimerStatus.running
              ? (_now() - _countUpStartAt).clamp(0, double.infinity)
              : 0);
      return TimerSnapshot(
        mode: TimerMode.countup,
        status: status,
        index: 0,
        phaseRemainingMs: 0,
        countUpElapsedMs: elapsed,
        savedAt: savedAt,
      );
    }
    return TimerSnapshot(
      mode: TimerMode.countdown,
      status: status,
      index: _index,
      phaseRemainingMs: status == TimerStatus.paused
          ? _remainOnPauseMs
          : (_phaseEndAt - _now()).clamp(0, double.infinity),
      countUpElapsedMs: 0,
      savedAt: savedAt,
    );
  }

  bool restore(
    List<Phase> phases,
    TimerSnapshot snapshot, {
    int? restoredAtMs,
  }) {
    if (snapshot.version != 1 ||
        (snapshot.status != TimerStatus.running &&
            snapshot.status != TimerStatus.paused) ||
        snapshot.index < 0 ||
        snapshot.phaseRemainingMs < 0 ||
        snapshot.countUpElapsedMs < 0 ||
        snapshot.savedAt < 0) {
      return false;
    }
    final restoredAt = restoredAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final offlineMs = (restoredAt - snapshot.savedAt).clamp(0, 1 << 62);

    if (snapshot.mode == TimerMode.countup) {
      _phases = const [];
      _countUp = true;
      _index = 0;
      _doneSecBefore = 0;
      _lastWholeSec = -1;
      _remainOnPauseMs = 0;
      _countUpAccumMs =
          snapshot.countUpElapsedMs +
          (snapshot.status == TimerStatus.running ? offlineMs : 0);
      _countUpStartAt = _now();
      status = snapshot.status;
      return true;
    }

    if (phases.isEmpty || snapshot.index >= phases.length) return false;
    _phases = List<Phase>.of(phases);
    _countUp = false;
    _index = snapshot.index;
    _doneSecBefore = phases
        .take(snapshot.index)
        .fold(0, (sum, phase) => sum + phase.durationSec);
    _lastWholeSec = -1;
    _countUpAccumMs = 0;
    status = snapshot.status;
    if (snapshot.status == TimerStatus.paused) {
      _remainOnPauseMs = snapshot.phaseRemainingMs;
      _phaseEndAt = 0;
    } else {
      _remainOnPauseMs = 0;
      _phaseEndAt = _now() + snapshot.phaseRemainingMs - offlineMs;
    }
    return true;
  }

  void start() {
    if (status == TimerStatus.running) return;
    if (_countUp) {
      status = TimerStatus.running;
      _countUpAccumMs = 0;
      _countUpStartAt = _now();
      _lastWholeSec = -1;
      _emit(const TimerEvent(TimerEventType.start));
      return;
    }
    if (_phases.isEmpty) throw StateError('timer has no phases');
    _index = 0;
    _doneSecBefore = 0;
    status = TimerStatus.running;
    _emit(const TimerEvent(TimerEventType.start));
    _beginPhase();
  }

  void _beginPhase() {
    final phase = _phases[_index];
    _phaseEndAt = _now() + phase.durationSec * 1000;
    _lastWholeSec = -1;
    _emit(TimerEvent(TimerEventType.phaseStart, index: _index, phase: phase));
  }

  void pause() {
    if (status != TimerStatus.running) return;
    if (_countUp) {
      _countUpAccumMs += _now() - _countUpStartAt;
      status = TimerStatus.paused;
      _emit(const TimerEvent(TimerEventType.pause));
      return;
    }
    _remainOnPauseMs = (_phaseEndAt - _now()).clamp(0, double.infinity);
    status = TimerStatus.paused;
    _emit(const TimerEvent(TimerEventType.pause));
  }

  void resume() {
    if (status != TimerStatus.paused) return;
    if (_countUp) {
      _countUpStartAt = _now();
      _lastWholeSec = -1;
      status = TimerStatus.running;
      _emit(const TimerEvent(TimerEventType.resume));
      return;
    }
    _phaseEndAt = _now() + _remainOnPauseMs;
    _lastWholeSec = -1;
    status = TimerStatus.running;
    _emit(const TimerEvent(TimerEventType.resume));
  }

  void stop() {
    if (status == TimerStatus.idle || status == TimerStatus.done) return;
    final elapsed = elapsedSec();
    status = TimerStatus.idle;
    _emit(TimerEvent(TimerEventType.stop, elapsedSec: elapsed));
  }

  void update() {
    if (status != TimerStatus.running) return;
    if (_countUp) {
      final whole = ((_countUpAccumMs + _now() - _countUpStartAt) / 1000)
          .floor();
      if (whole != _lastWholeSec) {
        _lastWholeSec = whole;
        _emit(
          TimerEvent(TimerEventType.tick, remainSec: whole, phaseProgress: 0),
        );
      }
      return;
    }

    var remainMs = _phaseEndAt - _now();
    while (remainMs <= 0 && status == TimerStatus.running) {
      final phase = _phases[_index];
      _emit(TimerEvent(TimerEventType.phaseEnd, index: _index, phase: phase));
      _doneSecBefore += phase.durationSec;
      _index += 1;
      if (_index >= _phases.length) {
        status = TimerStatus.done;
        _emit(const TimerEvent(TimerEventType.complete));
        return;
      }
      final next = _phases[_index];
      _phaseEndAt += next.durationSec * 1000;
      _lastWholeSec = -1;
      _emit(TimerEvent(TimerEventType.phaseStart, index: _index, phase: next));
      remainMs = _phaseEndAt - _now();
    }
    if (status != TimerStatus.running) return;
    final phase = _phases[_index];
    final whole = (remainMs / 1000).ceil();
    if (whole != _lastWholeSec) {
      _lastWholeSec = whole;
      final progress = 1 - remainMs / (phase.durationSec * 1000);
      _emit(
        TimerEvent(
          TimerEventType.tick,
          remainSec: whole,
          phaseProgress: progress,
        ),
      );
      if (whole >= 1 && whole <= 3) {
        _emit(TimerEvent(TimerEventType.countdown, sec: whole));
      }
    }
  }

  Phase? currentPhase() =>
      _countUp || _index >= _phases.length ? null : _phases[_index];

  int currentIndex() => _index;

  int remainSec() {
    if (_countUp) return elapsedSec();
    if (status == TimerStatus.paused) {
      return (_remainOnPauseMs / 1000).ceil();
    }
    if (status != TimerStatus.running) {
      return currentPhase()?.durationSec ?? 0;
    }
    return ((_phaseEndAt - _now()).clamp(0, double.infinity) / 1000).ceil();
  }

  double phaseProgress() {
    if (_countUp) return 0;
    final phase = currentPhase();
    if (phase == null) return 0;
    final remainMs = status == TimerStatus.paused
        ? _remainOnPauseMs
        : (_phaseEndAt - _now()).clamp(0, double.infinity);
    return (1 - remainMs / (phase.durationSec * 1000)).clamp(0, 1);
  }

  int elapsedSec() {
    if (_countUp) {
      final milliseconds =
          _countUpAccumMs +
          (status == TimerStatus.running ? _now() - _countUpStartAt : 0);
      return (milliseconds / 1000).floor();
    }
    final phase = currentPhase();
    final current = phase == null
        ? 0
        : (phase.durationSec * phaseProgress()).ceil();
    return _doneSecBefore + current;
  }
}
