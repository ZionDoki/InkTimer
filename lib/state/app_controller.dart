// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../data/repository.dart';
import '../domain/active_checkpoint.dart';
import '../domain/backup.dart';
import '../domain/defaults.dart';
import '../domain/focus_quality.dart';
import '../domain/growth.dart';
import '../domain/growth_models.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import '../domain/sounds.dart';
import '../domain/stats.dart';
import '../domain/timer_engine.dart';
import '../domain/todo_logic.dart';
import '../services/runtime_effects.dart';

class TimerViewState {
  const TimerViewState({
    required this.status,
    required this.phase,
    required this.remainSec,
    required this.phaseProgress,
    required this.round,
    required this.roundsTotal,
    required this.interruptions,
  });

  const TimerViewState.idle()
    : status = TimerStatus.idle,
      phase = null,
      remainSec = 0,
      phaseProgress = 0,
      round = 1,
      roundsTotal = 1,
      interruptions = 0;

  final TimerStatus status;
  final Phase? phase;
  final int remainSec;
  final double phaseProgress;
  final int round;
  final int roundsTotal;
  final int interruptions;

  TimerViewState copyWith({
    TimerStatus? status,
    Phase? phase,
    bool clearPhase = false,
    int? remainSec,
    double? phaseProgress,
    int? round,
    int? roundsTotal,
    int? interruptions,
  }) => TimerViewState(
    status: status ?? this.status,
    phase: clearPhase ? null : (phase ?? this.phase),
    remainSec: remainSec ?? this.remainSec,
    phaseProgress: phaseProgress ?? this.phaseProgress,
    round: round ?? this.round,
    roundsTotal: roundsTotal ?? this.roundsTotal,
    interruptions: interruptions ?? this.interruptions,
  );
}

class BackupImportReport {
  const BackupImportReport({
    required this.templatesAdded,
    required this.templatesUpdated,
    required this.sessionsAdded,
    required this.sessionsUpdated,
    required this.todosAdded,
    required this.todosUpdated,
    required this.skipped,
    required this.settingsUpdated,
  });

  final int templatesAdded;
  final int templatesUpdated;
  final int sessionsAdded;
  final int sessionsUpdated;
  final int todosAdded;
  final int todosUpdated;
  final int skipped;
  final bool settingsUpdated;

  int get changed =>
      templatesAdded +
      templatesUpdated +
      sessionsAdded +
      sessionsUpdated +
      todosAdded +
      todosUpdated +
      (settingsUpdated ? 1 : 0);
}

typedef MillisecondClock = int Function();
typedef IdFactory = String Function();

class SessionGrowthFeedback {
  const SessionGrowthFeedback({
    required this.qualityScore,
    required this.awardedExp,
    required this.oldLevel,
    required this.newLevel,
    required this.evidence,
  });

  final int qualityScore;
  final int awardedExp;
  final int oldLevel;
  final int newLevel;
  final FocusQualityEvidence evidence;

  bool get leveledUp => newLevel > oldLevel;
}

bool _sameSettings(AppSettings left, AppSettings right) =>
    left.volume == right.volume &&
    left.soundOn == right.soundOn &&
    left.hapticsOn == right.hapticsOn &&
    left.keepAwake == right.keepAwake &&
    left.theme == right.theme &&
    left.version == right.version;

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController({
    required Repository repository,
    TimerEngine? engine,
    RuntimeEffects? effects,
    MillisecondClock? nowMs,
    IdFactory? idFactory,
    this.driveTicker = true,
    this.observeLifecycle = true,
    this.phaseCueDelay = const Duration(milliseconds: 80),
    String? startupNotice,
  }) : _repository = repository,
       _engine = engine ?? TimerEngine(),
       _effects = effects ?? const NoopRuntimeEffects(),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _idFactory = idFactory ?? const Uuid().v4,
       _startupNotice = startupNotice {
    _engine.addListener(_onTimerEvent);
  }

  final Repository _repository;
  final TimerEngine _engine;
  final RuntimeEffects _effects;
  final MillisecondClock _nowMs;
  final IdFactory _idFactory;
  final String? _startupNotice;
  final bool driveTicker;
  final bool observeLifecycle;
  final Duration phaseCueDelay;

  List<TimerTemplate> _templates = List.of(builtinTemplates);
  List<SessionRecord> _sessions = [];
  List<TodoItem> _todos = [];
  HiddenGrowth _growth = defaultHiddenGrowth;
  AppSettings _settings = defaultSettings;
  String _selectedTemplateId = builtinTemplates.first.id;
  TimerTemplate? _activeTemplate;
  TimerTemplate? _currentTemplate;
  String _activeSessionId = '';
  int _sessionStartedAt = 0;
  int _sessionInterruptions = 0;
  FocusQualityEvidence _sessionQuality = emptyFocusQualityEvidence;
  int? _pendingInactiveAt;
  int? _pendingInactiveElapsedSec;
  int? _openBackgroundAt;
  int? _openBackgroundElapsedSec;
  Timer? _inactiveTimer;
  Future<void> _checkpointQueue = Future<void>.value();
  int _checkpointGeneration = 0;
  Future<void> _sessionSaveQueue = Future<void>.value();
  int _sessionSaveGeneration = 0;
  Future<void>? _automaticCompletionFinalization;
  TimerViewState _timer = const TimerViewState.idle();
  Timer? _ticker;
  Timer? _phaseSoundTimer;
  bool _ready = false;
  bool _seenGuide = false;
  bool _disposed = false;
  String? _notice;
  List<Insight>? _pendingInsightNotice;
  SessionGrowthFeedback? _sessionGrowthFeedback;

  bool get ready => _ready;
  bool get seenGuide => _seenGuide;
  bool get audioAvailable => _effects.audioAvailable;
  String? get notice => _notice;
  List<Insight>? get pendingInsightNotice => _pendingInsightNotice;
  SessionGrowthFeedback? get sessionGrowthFeedback => _sessionGrowthFeedback;
  List<TimerTemplate> get templates => List.unmodifiable(_templates);
  List<SessionRecord> get sessions => List.unmodifiable(_sessions);
  List<TodoItem> get todos => List.unmodifiable(_todos);
  HiddenGrowth get growth => _growth;
  AppSettings get settings => _settings;
  String get selectedTemplateId => _selectedTemplateId;
  TimerTemplate? get activeTemplate => _activeTemplate;
  TimerViewState get timer => _timer;
  SessionRecord? get lastSession => _sessions.isEmpty ? null : _sessions.last;
  List<TodoItem> get doingTodos => _todos
      .where((todo) => todo.progress < 100 && todo.archivedAt == null)
      .toList();

  TimerTemplate? get selectedTemplate {
    for (final template in _templates) {
      if (template.id == _selectedTemplateId) return template;
    }
    return _templates.firstOrNull;
  }

  TimerTemplate? get displayTemplate => _timer.status == TimerStatus.idle
      ? selectedTemplate
      : (_activeTemplate ?? selectedTemplate);

  bool get hasActiveSession =>
      _timer.status == TimerStatus.running ||
      _timer.status == TimerStatus.paused;

  Future<void> initialize() async {
    if (_ready) return;
    final hydrated = await _repository.hydrate(now: _nowMs());
    _templates = List.of(hydrated.templates);
    _sessions = List.of(hydrated.sessions);
    _todos = List.of(hydrated.todos);
    _growth = hydrated.growth;
    _settings = hydrated.settings;
    _selectedTemplateId = hydrated.selectedTemplateId;
    _seenGuide = hydrated.seenGuide;
    _notice = hydrated.notice ?? _startupNotice;
    _applyAudioSettings();

    await _migrateLegacySessionAwards(preserveStoredPosition: true);

    final activeRaw = hydrated.activeRaw;
    if (activeRaw != null) {
      try {
        final checkpoint = parseActiveCheckpoint(activeRaw);
        if (_sessions.any((session) => session.id == checkpoint.sessionId)) {
          await _repository.clearActive();
        } else if (!_restoreActiveSession(checkpoint)) {
          throw const FormatException('活动会话无法恢复');
        }
      } on Object {
        final timestamp = _nowMs();
        await _repository.store.write(
          '${StorageKeys.active}.backup-$timestamp',
          activeRaw,
        );
        await _repository.clearActive();
        _notice = '纸 笺 有 损 · 已 回 退 并 备 份 原 件';
      }
    }

    _ready = true;
    await _refreshGrowth();
    if (observeLifecycle) WidgetsBinding.instance.addObserver(this);
    _syncWakeLock();
    _notify();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  void clearSessionGrowthFeedback() {
    if (_sessionGrowthFeedback == null) return;
    _sessionGrowthFeedback = null;
    _notify();
  }

  void clearInsightNotice() {
    if (_pendingInsightNotice == null) return;
    _pendingInsightNotice = null;
    _notify();
  }

  Future<void> _saveSessionsLatest() {
    final generation = ++_sessionSaveGeneration;
    final sessions = List<SessionRecord>.of(_sessions);
    final operation = _sessionSaveQueue.then(
      (_) async {
        if (generation != _sessionSaveGeneration) return;
        await _repository.saveSessions(sessions);
      },
      onError: (_) async {
        if (generation != _sessionSaveGeneration) return;
        await _repository.saveSessions(sessions);
      },
    );
    _sessionSaveQueue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  Future<void> markGuideSeen() async {
    if (_seenGuide) return;
    _seenGuide = true;
    _notify();
    await _repository.markGuideSeen();
  }

  Future<void> selectTemplate(String id, {bool playCue = false}) async {
    if (!_templates.any((template) => template.id == id)) return;
    if (hasActiveSession || _selectedTemplateId == id) return;
    _selectedTemplateId = id;
    _notify();
    await _repository.saveSelectedTemplateId(id);
    if (playCue) await _effects.play(SoundName.plip);
  }

  Future<void> cycleTemplate(int direction) async {
    if (hasActiveSession || _templates.isEmpty) return;
    final current = _templates.indexWhere(
      (template) => template.id == _selectedTemplateId,
    );
    final base = current < 0 ? 0 : current;
    final next = (base + direction) % _templates.length;
    await selectTemplate(_templates[next].id, playCue: true);
  }

  Future<void> upsertTemplate(TimerTemplate template) async {
    final index = _templates.indexWhere((item) => item.id == template.id);
    if (index < 0) {
      _templates = [..._templates, template];
    } else {
      _templates = List.of(_templates)..[index] = template;
    }
    _selectedTemplateId = template.id;
    _notify();
    await Future.wait([
      _repository.saveTemplates(_templates),
      _repository.saveSelectedTemplateId(template.id),
    ]);
  }

  Future<void> deleteTemplate(String id) async {
    if (!_templates.any((template) => template.id == id)) return;
    _templates = _templates.where((template) => template.id != id).toList();
    if (_selectedTemplateId == id) {
      _selectedTemplateId = _templates.firstOrNull?.id ?? '';
    }
    _notify();
    await Future.wait([
      _repository.saveTemplates(_templates),
      _repository.saveSelectedTemplateId(_selectedTemplateId),
    ]);
  }

  Future<void> resetBuiltinTemplates() async {
    final canonical = {
      for (final template in builtinTemplates) template.id: template,
    };
    final restored = <TimerTemplate>[];
    final restoredBuiltinIds = <String>{};
    for (final template in _templates) {
      final builtin = canonical[template.id];
      if (builtin == null) {
        restored.add(template);
      } else if (restoredBuiltinIds.add(template.id)) {
        restored.add(builtin);
      }
    }
    for (final template in builtinTemplates) {
      if (restoredBuiltinIds.add(template.id)) restored.add(template);
    }
    _templates = restored;
    if (!_templates.any((item) => item.id == _selectedTemplateId)) {
      _selectedTemplateId = _templates.firstOrNull?.id ?? '';
    }
    _notify();
    await Future.wait([
      _repository.saveTemplates(_templates),
      _repository.saveSelectedTemplateId(_selectedTemplateId),
    ]);
  }

  Future<void> addTodo({
    required String text,
    List<String>? tags,
    int? dueAt,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    final safeTags = tags == null ? null : sanitizeTags(tags);
    final todo = TodoItem(
      id: _idFactory(),
      text: normalized.length <= 500
          ? normalized
          : normalized.substring(0, 500),
      progress: 0,
      tags: safeTags?.isEmpty ?? true ? null : safeTags,
      dueAt: dueAt != null && dueAt >= 0 ? dueAt : null,
      pushes: 0,
      createdAt: _nowMs(),
    );
    _todos = [..._todos, todo];
    _notify();
    await _repository.saveTodos(_todos);
  }

  Future<void> updateTodo(
    String id, {
    String? text,
    List<String>? tags,
    Object? dueAt = _unset,
  }) async {
    var changed = false;
    _todos = _todos.map((todo) {
      if (todo.id != id) return todo;
      var next = todo;
      if (text != null && text.trim().isNotEmpty) {
        final normalized = text.trim();
        next = next.copyWith(
          text: normalized.length <= 500
              ? normalized
              : normalized.substring(0, 500),
        );
      }
      if (tags != null) {
        final safe = sanitizeTags(tags);
        next = next.copyWith(tags: safe.isEmpty ? null : safe);
      }
      if (!identical(dueAt, _unset) &&
          (dueAt == null || (dueAt is int && dueAt >= 0))) {
        next = next.copyWith(dueAt: dueAt);
      }
      changed = true;
      return next;
    }).toList();
    if (!changed) return;
    _notify();
    await _repository.saveTodos(_todos);
  }

  Future<void> deleteTodo(String id) async {
    final next = _todos.where((todo) => todo.id != id).toList();
    if (next.length == _todos.length) return;
    _todos = next;
    _notify();
    await _repository.saveTodos(_todos);
    await _refreshGrowth();
  }

  Future<void> pushTodo(String id, double amount) async {
    _todos = _todos
        .map((todo) => todo.id == id ? applyPush(todo, amount, _nowMs()) : todo)
        .toList();
    _notify();
    await _repository.saveTodos(_todos);
    await _refreshGrowth();
  }

  Future<void> setTodoProgressById(String id, double progress) async {
    _todos = _todos
        .map(
          (todo) =>
              todo.id == id ? setTodoProgress(todo, progress, _nowMs()) : todo,
        )
        .toList();
    _notify();
    await _repository.saveTodos(_todos);
  }

  Future<void> archiveTodoById(String id) async {
    if (!_todos.any((todo) => todo.id == id)) return;
    _todos = _todos
        .map((todo) => todo.id == id ? archiveTodo(todo, _nowMs()) : todo)
        .toList();
    _notify();
    await _repository.saveTodos(_todos);
  }

  Future<void> restoreTodoById(String id) async {
    if (!_todos.any((todo) => todo.id == id)) return;
    _todos = _todos
        .map((todo) => todo.id == id ? restoreTodo(todo) : todo)
        .toList();
    _notify();
    await _repository.saveTodos(_todos);
  }

  Future<void> setLastSessionFeeling(SessionFeeling feeling) async {
    if (_sessions.isEmpty || _timer.status != TimerStatus.done) return;
    final index = _sessions.length - 1;
    final session = _sessions[index];
    if (session.feeling == feeling) return;
    _sessions = List<SessionRecord>.of(_sessions)
      ..[index] = session.copyWith(feeling: feeling);
    _notify();
    await _saveSessionsLatest();
    await _refreshGrowth();
  }

  Future<void> linkLastSessionToTodo(String todoId) =>
      applyLastSessionToTodo(todoId);

  Future<void> applyLastSessionToTodo(
    String todoId, {
    double? progressAmount,
  }) async {
    if (todoId.trim().isEmpty ||
        _sessions.isEmpty ||
        _timer.status != TimerStatus.done) {
      return;
    }
    final sessionIndex = _sessions.length - 1;
    final session = _sessions[sessionIndex];
    final linkedFocusSec = session.focusedSec ?? session.elapsedSec;
    if (linkedFocusSec <= 0) return;
    final targetIndex = _todos.indexWhere((todo) => todo.id == todoId);
    if (targetIndex < 0) return;
    final shouldRelink = session.linkedTodoId != todoId;
    final shouldPush = progressAmount != null;
    if (!shouldRelink && !shouldPush) return;

    final nextTodos = _todos.map((todo) {
      var next = todo;
      if (shouldRelink && todo.id == session.linkedTodoId) {
        next = next.copyWith(
          totalFocusSec: (next.totalFocusSec - linkedFocusSec).clamp(
            0,
            1 << 62,
          ),
          sessionsLinked: (next.sessionsLinked - 1).clamp(0, 1 << 62),
        );
      }
      if (todo.id == todoId) {
        if (shouldRelink) {
          next = next.copyWith(
            totalFocusSec: (next.totalFocusSec + linkedFocusSec).clamp(
              0,
              1 << 62,
            ),
            sessionsLinked: next.sessionsLinked + 1,
          );
        }
        if (shouldPush) {
          next = applyPush(next, progressAmount, _nowMs());
        }
      }
      return next;
    }).toList();
    final nextSessions = shouldRelink
        ? (List<SessionRecord>.of(_sessions)
            ..[sessionIndex] = session.copyWith(linkedTodoId: todoId))
        : _sessions;
    _todos = nextTodos;
    _sessions = nextSessions;
    _notify();
    await Future.wait([
      _repository.saveTodos(_todos),
      if (shouldRelink) _saveSessionsLatest(),
    ]);
    await _refreshGrowth();
  }

  bool get _isRunningFocus =>
      _engine.status == TimerStatus.running &&
      (_currentTemplate?.kind == TemplateKind.accumulate ||
          _engine.currentPhase()?.kind == PhaseKind.work);

  void recordCanceledHold() {
    if (!_isRunningFocus) return;
    _sessionQuality = _sessionQuality.copyWith(
      canceledHoldCount: _sessionQuality.canceledHoldCount + 1,
    );
    unawaited(_persistActiveCheckpoint());
  }

  void recordInAppDiversion() {
    if (!_isRunningFocus) return;
    _sessionQuality = _sessionQuality.copyWith(
      inAppDiversionCount: _sessionQuality.inAppDiversionCount + 1,
    );
    unawaited(_persistActiveCheckpoint());
  }

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    _applyAudioSettings();
    _notify();
    _syncWakeLock();
    await _repository.saveSettings(settings);
  }

  Future<void> startSelectedSession() async {
    final template = selectedTemplate;
    if (!_ready || template == null || hasActiveSession) return;
    await startSession(template);
  }

  Future<void> startSession(TimerTemplate template) async {
    if (!_ready || hasActiveSession) return;
    _currentTemplate = template;
    _activeTemplate = template;
    _activeSessionId = _idFactory();
    _sessionStartedAt = _nowMs();
    _sessionInterruptions = 0;
    _sessionQuality = emptyFocusQualityEvidence;
    _pendingInactiveAt = null;
    _pendingInactiveElapsedSec = null;
    _openBackgroundAt = null;
    _openBackgroundElapsedSec = null;
    _sessionGrowthFeedback = null;
    if (template.kind == TemplateKind.accumulate) {
      _engine.loadCountUp();
    } else {
      _engine.load(compileTemplate(template));
    }
    _engine.start();
    _pushTimerView();
    _startTicker();
    _syncWakeLock();
    await _persistActiveCheckpoint();
  }

  Future<void> togglePause() async {
    if (_engine.status == TimerStatus.running) {
      if (_isRunningFocus) {
        _sessionInterruptions += 1;
        _sessionQuality = _sessionQuality.copyWith(
          manualPauseCount: _sessionQuality.manualPauseCount + 1,
        );
      }
      _engine.pause();
      _stopTicker();
      _pushTimerView();
      await _persistActiveCheckpoint();
      await _effects.play(SoundName.pauseLow);
    } else if (_engine.status == TimerStatus.paused) {
      _engine.resume();
      _pushTimerView();
      _startTicker();
      _syncWakeLock();
      await _persistActiveCheckpoint();
      await _effects.play(SoundName.resumeHigh);
    }
  }

  Future<void> stopSession() async {
    if (!hasActiveSession) return;
    final template = _currentTemplate;
    if (template?.kind == TemplateKind.accumulate) {
      final elapsed = _engine.elapsedSec();
      if (elapsed >= 1) {
        await _effects.play(SoundName.complete);
        await _saveSession(completed: true);
        _engine.stop();
        _timer = TimerViewState(
          status: TimerStatus.done,
          phase: null,
          remainSec: elapsed,
          phaseProgress: 0,
          round: 1,
          roundsTotal: 1,
          interruptions: _sessionInterruptions,
        );
        _currentTemplate = null;
        _notify();
      } else {
        _engine.stop();
        await resetToIdle();
      }
    } else {
      await _effects.play(SoundName.drum);
      await _saveSession(completed: false);
      _engine.stop();
      _currentTemplate = null;
      _activeTemplate = null;
      _pushTimerView();
    }
    _checkpointGeneration += 1;
    await _checkpointQueue;
    await _repository.clearActive();
    _syncWakeLock();
  }

  Future<void> resetToIdle() async {
    _currentTemplate = null;
    _activeSessionId = '';
    _activeTemplate = null;
    _sessionInterruptions = 0;
    _sessionQuality = emptyFocusQualityEvidence;
    _pendingInactiveAt = null;
    _pendingInactiveElapsedSec = null;
    _openBackgroundAt = null;
    _openBackgroundElapsedSec = null;
    _inactiveTimer?.cancel();
    _timer = const TimerViewState.idle();
    _stopTicker();
    _notify();
    _checkpointGeneration += 1;
    await _checkpointQueue;
    await _repository.clearActive();
    _syncWakeLock();
  }

  void tick() {
    _engine.update();
    _pushTimerView();
    if (_engine.status != TimerStatus.running) _stopTicker();
  }

  String exportBackup() => buildBackup(
    _templates,
    _sessions,
    _settings,
    _todos,
    growth: _growth,
    now: _nowMs(),
  );

  Future<BackupImportReport> importBackup(String raw) async {
    final parsed = parseBackup(raw);
    final settingsUpdated = !_sameSettings(_settings, parsed.settings);
    final templates = mergeById(
      _templates,
      parsed.templates,
      (template) => template.id,
    );
    final sessions = mergeById(
      _sessions,
      parsed.sessions,
      (session) => session.id,
      mergeConflict: mergeSessionConflict,
    );
    final todos = mergeById(_todos, parsed.todos, (todo) => todo.id);
    _templates = templates.items;
    _sessions = sessions.items;
    _todos = todos.items;
    _settings = parsed.settings;
    if (parsed.growth != null) {
      final incoming = parsed.growth!;
      final insights = <String>{..._growth.insights, ...incoming.insights};
      final timestamps = <String, int>{..._growth.insightUnlockedAt};
      for (final entry in incoming.insightUnlockedAt.entries) {
        final old = timestamps[entry.key];
        timestamps[entry.key] = old == null
            ? entry.value
            : math.min(old, entry.value);
      }
      _growth = HiddenGrowth(
        level: _growth.level,
        totalExp: _growth.totalExp,
        insights: insights.toList(),
        insightUnlockedAt: timestamps,
      );
    }
    if (!_templates.any((item) => item.id == _selectedTemplateId)) {
      _selectedTemplateId = _templates.firstOrNull?.id ?? '';
    }
    _applyAudioSettings();
    _syncWakeLock();
    _notify();
    await Future.wait([
      _repository.saveTemplates(_templates),
      _saveSessionsLatest(),
      _repository.saveTodos(_todos),
      _repository.saveSettings(_settings),
      _repository.saveSelectedTemplateId(_selectedTemplateId),
      _repository.saveGrowth(_growth),
    ]);
    await _migrateLegacySessionAwards();
    await _refreshGrowth();
    return BackupImportReport(
      templatesAdded: templates.added,
      templatesUpdated: templates.updated,
      sessionsAdded: sessions.added,
      sessionsUpdated: sessions.updated,
      todosAdded: todos.added,
      todosUpdated: todos.updated,
      skipped: parsed.skippedTotal,
      settingsUpdated: settingsUpdated,
    );
  }

  Future<void> clearHistory() async {
    _sessions = [];
    _notify();
    await _saveSessionsLatest();
    await _refreshGrowth();
  }

  Future<void> playCue(SoundName sound) => _effects.play(sound);

  Future<void> checkpointAndFlush() async {
    if (_engine.status == TimerStatus.done &&
        _activeSessionId.isNotEmpty &&
        _currentTemplate != null) {
      _startAutomaticCompletionFinalization();
      await _automaticCompletionFinalization;
    } else {
      await _persistActiveCheckpoint();
    }
    await _repository.flush();
  }

  void _onTimerEvent(TimerEvent event) {
    switch (event.type) {
      case TimerEventType.phaseStart:
        _schedulePhaseSound(event.phase?.kind ?? PhaseKind.work);
        if (_settings.hapticsOn) {
          unawaited(_effects.haptic(HapticCue.phase));
        }
        unawaited(_persistActiveCheckpoint());
      case TimerEventType.countdown:
        unawaited(_effects.play(SoundName.tick));
      case TimerEventType.complete:
        _phaseSoundTimer?.cancel();
        unawaited(_effects.play(SoundName.complete));
        if (_settings.hapticsOn) {
          unawaited(_effects.haptic(HapticCue.complete));
        }
        _stopTicker();
        unawaited(_effects.keepAwake(false));
        _startAutomaticCompletionFinalization();
      case TimerEventType.stop:
        _phaseSoundTimer?.cancel();
        _stopTicker();
        unawaited(_effects.keepAwake(false));
        _checkpointGeneration += 1;
        unawaited(_checkpointQueue.then((_) => _repository.clearActive()));
        _activeSessionId = '';
      case TimerEventType.start:
      case TimerEventType.tick:
      case TimerEventType.phaseEnd:
      case TimerEventType.pause:
      case TimerEventType.resume:
        break;
    }
    _pushTimerView();
  }

  void _schedulePhaseSound(PhaseKind kind) {
    _phaseSoundTimer?.cancel();
    final sound = kind == PhaseKind.work
        ? SoundName.bowlWork
        : SoundName.bowlRest;
    if (phaseCueDelay == Duration.zero) {
      unawaited(_effects.play(sound));
      return;
    }
    _phaseSoundTimer = Timer(
      phaseCueDelay,
      () => unawaited(_effects.play(sound)),
    );
  }

  void _startAutomaticCompletionFinalization() {
    if (_automaticCompletionFinalization != null) return;
    final sessionId = _activeSessionId;
    final operation = _finalizeAutomaticCompletion(sessionId);
    _automaticCompletionFinalization = operation;
    unawaited(
      operation.whenComplete(() {
        if (identical(_automaticCompletionFinalization, operation)) {
          _automaticCompletionFinalization = null;
        }
      }),
    );
  }

  Future<void> _finalizeAutomaticCompletion(String sessionId) async {
    try {
      await _saveSession(completed: true);
      while (true) {
        final generation = _sessionSaveGeneration;
        await _sessionSaveQueue;
        if (generation == _sessionSaveGeneration) break;
      }
      _checkpointGeneration += 1;
      await _checkpointQueue;
      await _repository.clearActive();
      if (_activeSessionId == sessionId) {
        _currentTemplate = null;
        _activeSessionId = '';
      }
    } on Object {
      if (_activeSessionId == sessionId && _currentTemplate != null) {
        try {
          await _persistActiveCheckpoint();
        } on Object {
          // Preserve the last successfully written checkpoint for retry.
        }
      }
    }
  }

  Future<void> _saveSession({required bool completed}) async {
    final template = _currentTemplate;
    if (template == null) return;
    final elapsedSec = _engine.elapsedSec();
    final phases = template.kind == TemplateKind.accumulate
        ? const <Phase>[]
        : compileTemplate(template);
    final focusedSec = template.kind == TemplateKind.accumulate
        ? elapsedSec
        : focusOverlapSec(phases, 0, elapsedSec);
    final score = focusQualityScore(_sessionQuality);
    final draft = SessionRecord(
      id: _activeSessionId.isEmpty ? _idFactory() : _activeSessionId,
      templateId: template.id,
      label: template.label,
      kind: template.kind,
      startedAt: _sessionStartedAt,
      endedAt: _nowMs(),
      plannedSec: template.kind == TemplateKind.accumulate
          ? 0
          : plannedDurationSec(phases),
      elapsedSec: elapsedSec,
      completed: completed,
      roundsDone: template.kind == TemplateKind.accumulate
          ? 0
          : completed
          ? (phases.lastOrNull?.roundsTotal ?? 1)
          : completedRounds(phases, _engine.currentIndex()),
      roundsTotal: template.kind == TemplateKind.accumulate
          ? 0
          : phases.lastOrNull?.roundsTotal ?? 1,
      interruptions: _sessionInterruptions,
      focusedSec: focusedSec,
      qualityEvidence: _sessionQuality,
      qualityScore: score,
      scoringVersion: 1,
    );
    final existingIndex = _sessions.indexWhere((old) => old.id == draft.id);
    if (existingIndex >= 0) {
      await _saveSessionsLatest();
      await _refreshGrowth();
      return;
    }
    final eligibleDays = <String>{};
    final focusByDay = <String, int>{};
    for (final old in [..._sessions, draft]) {
      if (!old.completed) continue;
      final key = dayKey(DateTime.fromMillisecondsSinceEpoch(old.startedAt));
      focusByDay[key] =
          (focusByDay[key] ?? 0) + (old.focusedSec ?? old.elapsedSec);
    }
    for (final entry in focusByDay.entries) {
      if (entry.value >= minimumEligibleFocusedSec) eligibleDays.add(entry.key);
    }
    final streak = streakDaysForSession(draft, eligibleDays);
    final award = calculateAwardedMilliExp(
      focusedSec: focusedSec,
      accumulate: template.kind == TemplateKind.accumulate,
      completed: completed,
      qualityScore: score,
      streakDays: streak,
    );
    final session = draft.copyWith(awardedMilliExp: award);
    final oldLevel = _growth.level;
    _sessions = [..._sessions, session];
    _notify();
    await _saveSessionsLatest();
    await _refreshGrowth();
    _sessionGrowthFeedback = SessionGrowthFeedback(
      qualityScore: score,
      awardedExp: (award / 1000).round(),
      oldLevel: oldLevel,
      newLevel: _growth.level,
      evidence: _sessionQuality,
    );
    _notify();
  }

  Future<void> _migrateLegacySessionAwards({
    bool preserveStoredPosition = false,
  }) async {
    final legacyIndexes = <int>[];
    for (var index = 0; index < _sessions.length; index += 1) {
      if (_sessions[index].awardedMilliExp == null) legacyIndexes.add(index);
    }
    if (legacyIndexes.isEmpty) return;
    final oldExp = preserveStoredPosition && _growth.totalExp > 0
        ? _growth.totalExp
        : legacyIndexes.fold<int>(0, (sum, index) {
            final session = _sessions[index];
            final base = session.elapsedSec / 60.0;
            final completion = session.completed ? 1.2 : 0.6;
            return sum + (base * completion * 1.1).round();
          });
    final mappedMilli = mapLegacyExpToNewCurve(oldExp) * 1000;
    final weights = <int>[
      for (final index in legacyIndexes)
        math.max(1, _sessions[index].focusedSec ?? _sessions[index].elapsedSec),
    ];
    final weightTotal = weights.fold<int>(0, (sum, value) => sum + value);
    var assigned = 0;
    final next = List<SessionRecord>.of(_sessions);
    for (var offset = 0; offset < legacyIndexes.length; offset += 1) {
      final index = legacyIndexes[offset];
      final award = offset == legacyIndexes.length - 1
          ? mappedMilli - assigned
          : (mappedMilli * weights[offset] / weightTotal).floor();
      assigned += award;
      final session = next[index];
      next[index] = session.copyWith(
        focusedSec: session.focusedSec ?? session.elapsedSec,
        qualityEvidence: null,
        qualityScore: null,
        awardedMilliExp: award,
        scoringVersion: 0,
      );
    }
    _sessions = next;
    await _saveSessionsLatest();
  }

  Future<void> _refreshGrowth() async {
    final focusedTotal = _sessions
        .where((session) => session.completed)
        .fold<int>(
          0,
          (sum, session) => sum + (session.focusedSec ?? session.elapsedSec),
        );
    final totalExp = computeTotalExp(sessions: _sessions, todos: _todos);
    final context = GrowthContext(
      sessions: _sessions,
      todos: _todos,
      totalSec: focusedTotal,
      bestStreakDays: bestStreakDays(_sessions),
      zeroInterruptRate: summarizeSessions(
        _sessions,
        DateTime.fromMillisecondsSinceEpoch(_nowMs()),
      ).zeroInterruptRate,
      unlockedInsights: _growth.insights,
    );
    final now = _nowMs();
    final newInsights = checkNewInsights(context, now);
    final nextInsights = <String>[
      ..._growth.insights,
      for (final insight in newInsights) insight.id,
    ];
    final timestamps = <String, int>{..._growth.insightUnlockedAt};
    final migrationTimestamp = _sessions.isEmpty
        ? now
        : _sessions.map((session) => session.endedAt).reduce(math.min);
    for (final id in _growth.insights) {
      timestamps.putIfAbsent(id, () => migrationTimestamp);
    }
    for (final insight in newInsights) {
      timestamps.putIfAbsent(insight.id, () => insight.unlockedAt);
    }
    final next = HiddenGrowth(
      level: expToLevel(totalExp),
      totalExp: totalExp,
      insights: nextInsights,
      insightUnlockedAt: timestamps,
    );
    if (_growth.level == next.level &&
        _growth.totalExp == next.totalExp &&
        _growth.insights.length == next.insights.length &&
        _growth.insightUnlockedAt.length == next.insightUnlockedAt.length) {
      return;
    }
    _growth = next;
    if (newInsights.isNotEmpty) _pendingInsightNotice = newInsights;
    _notify();
    await _repository.saveGrowth(_growth);
  }

  Future<void> _persistActiveCheckpoint() {
    final template = _currentTemplate;
    if ((!_ready && _activeSessionId.isEmpty) ||
        template == null ||
        _activeSessionId.isEmpty) {
      return Future<void>.value();
    }
    final savedAt = _nowMs();
    final snapshot = _engine.snapshot(savedAtMs: savedAt);
    if (snapshot == null) return Future<void>.value();
    final generation = ++_checkpointGeneration;
    final checkpoint = ActiveSessionCheckpoint(
      sessionId: _activeSessionId,
      template: template,
      startedAt: _sessionStartedAt,
      interruptions: _sessionInterruptions,
      timer: snapshot,
      qualityEvidence: _sessionQuality,
      pendingInactiveAt: _pendingInactiveAt,
      pendingElapsedSec: _pendingInactiveElapsedSec,
      openBackgroundAt: _openBackgroundAt,
      openBackgroundElapsedSec: _openBackgroundElapsedSec,
    );
    final operation = _checkpointQueue.then(
      (_) async {
        if (generation != _checkpointGeneration) return;
        await _repository.saveActive(checkpoint.encode());
      },
      onError: (_) async {
        if (generation != _checkpointGeneration) return;
        await _repository.saveActive(checkpoint.encode());
      },
    );
    _checkpointQueue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  bool _restoreActiveSession(ActiveSessionCheckpoint checkpoint) {
    final template = checkpoint.template;
    final phases = template.kind == TemplateKind.accumulate
        ? const <Phase>[]
        : compileTemplate(template);
    _currentTemplate = template;
    _activeTemplate = template;
    _activeSessionId = checkpoint.sessionId;
    _sessionStartedAt = checkpoint.startedAt;
    _sessionInterruptions = checkpoint.interruptions;
    _sessionQuality = checkpoint.qualityEvidence;
    _pendingInactiveAt = checkpoint.pendingInactiveAt;
    _pendingInactiveElapsedSec = checkpoint.pendingElapsedSec;
    _openBackgroundAt = checkpoint.openBackgroundAt;
    _openBackgroundElapsedSec = checkpoint.openBackgroundElapsedSec;
    final restoredAt = _nowMs();
    final confirmedBackgroundStart = checkpoint.openBackgroundElapsedSec;
    final provisionalAwayMs = checkpoint.pendingInactiveAt == null
        ? 0
        : math.max(0, restoredAt - checkpoint.pendingInactiveAt!);
    final provisionalConfirmed =
        checkpoint.pendingElapsedSec != null && provisionalAwayMs >= 2000;
    final backgroundStart =
        confirmedBackgroundStart ??
        (provisionalConfirmed ? checkpoint.pendingElapsedSec : null);
    final snapshotElapsed = template.kind == TemplateKind.accumulate
        ? (checkpoint.timer.countUpElapsedMs / 1000).floor()
        : elapsedSecAtSnapshot(
            phases,
            index: checkpoint.timer.index,
            phaseRemainingMs: checkpoint.timer.phaseRemainingMs,
          );
    final offlineSec = checkpoint.timer.status == TimerStatus.running
        ? math.max(0, restoredAt - checkpoint.timer.savedAt) ~/ 1000
        : 0;
    final plannedSec = template.kind == TemplateKind.accumulate
        ? 1 << 62
        : plannedDurationSec(phases);
    final restoredEndElapsed = math.min(
      plannedSec,
      snapshotElapsed + offlineSec,
    );
    if (backgroundStart != null &&
        checkpoint.timer.status == TimerStatus.running) {
      final backgroundFocus = template.kind == TemplateKind.accumulate
          ? math.max(0, restoredEndElapsed - backgroundStart)
          : focusOverlapSec(phases, backgroundStart, restoredEndElapsed);
      if (backgroundFocus > 0) {
        _sessionQuality = _sessionQuality.copyWith(
          backgroundExcursionCount:
              _sessionQuality.backgroundExcursionCount + 1,
          backgroundFocusSec:
              _sessionQuality.backgroundFocusSec + backgroundFocus,
        );
      }
    }
    if (!_engine.restore(phases, checkpoint.timer, restoredAtMs: restoredAt)) {
      return false;
    }
    _openBackgroundAt = null;
    _openBackgroundElapsedSec = null;
    _pendingInactiveAt = null;
    _pendingInactiveElapsedSec = null;
    if (_engine.status == TimerStatus.running) _engine.update();
    _pushTimerView();
    if (_engine.status == TimerStatus.running) _startTicker();
    unawaited(_persistActiveCheckpoint());
    return true;
  }

  void _pushTimerView() {
    final phase = _engine.currentPhase();
    _timer = TimerViewState(
      status: _engine.status,
      phase: phase,
      remainSec: _engine.remainSec(),
      phaseProgress: _engine.phaseProgress(),
      round: phase?.round ?? 1,
      roundsTotal: phase?.roundsTotal ?? 1,
      interruptions: _sessionInterruptions,
    );
    _notify();
  }

  void _startTicker() {
    if (!driveTicker || _engine.status != TimerStatus.running) return;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _applyAudioSettings() {
    _effects.configureAudio(
      enabled: _settings.soundOn,
      volume: _settings.volume,
    );
  }

  void _syncWakeLock() {
    final enabled =
        _settings.keepAwake &&
        (_engine.status == TimerStatus.running ||
            _engine.status == TimerStatus.paused);
    unawaited(_effects.keepAwake(enabled));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _beginProvisionalInactive() {
    if (_engine.status != TimerStatus.running ||
        _currentTemplate == null ||
        _pendingInactiveAt != null ||
        _openBackgroundAt != null) {
      return;
    }
    _pendingInactiveAt = _nowMs();
    _pendingInactiveElapsedSec = _engine.elapsedSec();
    _inactiveTimer?.cancel();
    _inactiveTimer = Timer(const Duration(seconds: 2), () {
      _confirmBackgroundExcursion();
    });
  }

  void _confirmBackgroundExcursion() {
    if (_openBackgroundAt != null || _pendingInactiveAt == null) return;
    _openBackgroundAt = _pendingInactiveAt;
    _openBackgroundElapsedSec = _pendingInactiveElapsedSec;
    _pendingInactiveAt = null;
    _pendingInactiveElapsedSec = null;
    _inactiveTimer?.cancel();
    unawaited(_persistActiveCheckpoint());
  }

  void _closeBackgroundExcursion(int returnedAt) {
    _inactiveTimer?.cancel();
    if (_openBackgroundAt == null) {
      _pendingInactiveAt = null;
      _pendingInactiveElapsedSec = null;
      return;
    }
    final startElapsed = _openBackgroundElapsedSec ?? _engine.elapsedSec();
    final wallElapsed = math.max(
      0,
      (returnedAt - (_openBackgroundAt ?? returnedAt)) ~/ 1000,
    );
    final endElapsed = math.max(
      _engine.elapsedSec(),
      startElapsed + wallElapsed,
    );
    final template = _currentTemplate;
    var focusSec = 0;
    if (_engine.status == TimerStatus.running && template != null) {
      if (template.kind == TemplateKind.accumulate) {
        focusSec = math.max(0, endElapsed - startElapsed);
      } else {
        focusSec = focusOverlapSec(
          compileTemplate(template),
          startElapsed,
          endElapsed,
        );
      }
    }
    if (focusSec > 0) {
      _sessionQuality = _sessionQuality.copyWith(
        backgroundExcursionCount: _sessionQuality.backgroundExcursionCount + 1,
        backgroundFocusSec: _sessionQuality.backgroundFocusSec + focusSec,
      );
    }
    _openBackgroundAt = null;
    _openBackgroundElapsedSec = null;
    _pendingInactiveAt = null;
    _pendingInactiveElapsedSec = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _closeBackgroundExcursion(_nowMs());
        if (_engine.status == TimerStatus.running) {
          _engine.update();
          _pushTimerView();
          _startTicker();
        }
        unawaited(_persistActiveCheckpoint());
        _syncWakeLock();
      case AppLifecycleState.inactive:
        _beginProvisionalInactive();
        unawaited(_persistActiveCheckpoint());
        unawaited(_effects.keepAwake(false));
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_pendingInactiveAt == null && _openBackgroundAt == null) {
          _beginProvisionalInactive();
        }
        _confirmBackgroundExcursion();
        unawaited(_persistActiveCheckpoint());
        unawaited(_effects.keepAwake(false));
      case AppLifecycleState.detached:
        unawaited(_persistActiveCheckpoint());
        unawaited(_effects.keepAwake(false));
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (observeLifecycle && _ready) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _ticker?.cancel();
    _phaseSoundTimer?.cancel();
    _inactiveTimer?.cancel();
    _engine.removeListener(_onTimerEvent);
    unawaited(_persistActiveCheckpoint());
    unawaited(_effects.dispose());
    super.dispose();
  }
}

const Object _unset = Object();
